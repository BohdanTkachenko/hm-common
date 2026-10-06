# EPOS / Sennheiser gaming audio support (GSX 300)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.hardware.epos;

  toggleAudio = pkgs.writeShellScriptBin "epos-toggle-audio" ''
    set -eu
    PACTL="${pkgs.pulseaudio}/bin/pactl"

    HP_SINK_RE='^alsa_output[.]usb-Sennheiser_EPOS_GSX_300_.*-00[.]analog-stereo$'
    HP_SOURCE_RE='^alsa_input[.]usb-Sennheiser_EPOS_GSX_300_.*-00[.]mono-fallback$'
    SB_SINK_RE='^alsa_output[.]usb-Generic_USB_SPDIF_Adapter_.*-00[.]analog-stereo$'
    SB_SOURCE_RE='^alsa_input[.]usb-046d_Logitech_BRIO_.*[.]analog-stereo$'

    HP_SINK=$($PACTL list short sinks | ${pkgs.gawk}/bin/awk -v re="$HP_SINK_RE" '$2 ~ re { print $2; exit }')
    HP_SOURCE=$($PACTL list short sources | ${pkgs.gawk}/bin/awk -v re="$HP_SOURCE_RE" '$2 ~ re { print $2; exit }')
    SB_SINK=$($PACTL list short sinks | ${pkgs.gawk}/bin/awk -v re="$SB_SINK_RE" '$2 ~ re { print $2; exit }')
    SB_SOURCE=$($PACTL list short sources | ${pkgs.gawk}/bin/awk -v re="$SB_SOURCE_RE" '$2 ~ re { print $2; exit }')

    current_sink=$($PACTL get-default-sink)
    if [ -n "$HP_SINK" ] && [ -n "$SB_SINK" ] && [ "$current_sink" = "$HP_SINK" ]; then
      $PACTL set-default-sink "$SB_SINK"
      if [ -n "$SB_SOURCE" ]; then
        $PACTL set-default-source "$SB_SOURCE"
      fi
    elif [ -n "$HP_SINK" ]; then
      $PACTL set-default-sink "$HP_SINK"
      if [ -n "$HP_SOURCE" ]; then
        $PACTL set-default-source "$HP_SOURCE"
      fi
    fi
  '';

  reader =
    pkgs.writers.writePython3 "epos-smart-button-reader"
      {
        flakeIgnore = [ "E501" ];
      }
      ''
        import glob
        import os
        import subprocess
        import sys
        import time

        REPORT_SMART_BUTTON_PRESS = b"\x02\x01"
        SH = "${pkgs.bash}/bin/sh"


        def find_epos_hidraw():
            if os.path.exists("/dev/epos-gsx-smartbutton"):
                return "/dev/epos-gsx-smartbutton"
            for uevent in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
                try:
                    with open(uevent, "r") as f:
                        content = f.read()
                        if "1395" in content and "0098" in content:
                            hidraw_name = uevent.split("/")[4]
                            dev_path = f"/dev/{hidraw_name}"
                            if os.path.exists(dev_path):
                                return dev_path
                except OSError:
                    pass
            return None


        def run_action(cmd):
            try:
                subprocess.run([SH, "-c", cmd], check=False)
            except Exception as e:
                print(f"action failed: {e}", file=sys.stderr, flush=True)


        def main():
            cmd = sys.argv[1] if len(sys.argv) > 1 else "true"
            while True:
                dev = find_epos_hidraw()
                if not dev:
                    time.sleep(5)
                    continue
                try:
                    with open(dev, "rb", buffering=0) as f:
                        while True:
                            data = f.read(64)
                            if not data:
                                break
                            if data[:2] == REPORT_SMART_BUTTON_PRESS:
                                run_action(cmd)
                except (FileNotFoundError, PermissionError):
                    time.sleep(5)
                except OSError as e:
                    print(f"read error: {e}", file=sys.stderr, flush=True)
                    time.sleep(2)


        if __name__ == "__main__":
            main()
      '';

  volumeRedirect =
    pkgs.writers.writePython3 "epos-volume-redirect"
      {
        flakeIgnore = [ "E501" ];
      }
      ''
        import re
        import subprocess
        import sys
        import time

        PACTL = "${pkgs.pulseaudio}/bin/pactl"
        EPOS_SINK_RE = re.compile(r'^alsa_output\.usb-Sennheiser_EPOS_GSX_300_.*-00\.analog-stereo$')
        SINK_EVENT_RE = re.compile(r"Event 'change' on sink #(\d+)")
        VOLUME_RE = re.compile(r':\s*(\d+)\s*/')
        MAX_VOL = 65536


        def pactl(*args):
            try:
                return subprocess.run(
                    [PACTL, *args], check=False, capture_output=True, text=True,
                ).stdout
            except Exception as e:
                print(f"pactl error: {e}", file=sys.stderr, flush=True)
                return ""


        def list_sinks():
            sinks = []
            for line in pactl("list", "short", "sinks").splitlines():
                parts = line.split("\t")
                if len(parts) >= 2:
                    try:
                        sinks.append((int(parts[0]), parts[1]))
                    except ValueError:
                        pass
            return sinks


        def find_epos_sink():
            for idx, name in list_sinks():
                if EPOS_SINK_RE.match(name):
                    return idx, name
            return None, None


        def get_sink_volume(sink):
            m = VOLUME_RE.search(pactl("get-sink-volume", sink))
            return int(m.group(1)) if m else None


        def set_sink_volume(sink, value):
            value = max(0, min(int(value), MAX_VOL))
            subprocess.run(
                [PACTL, "set-sink-volume", sink, str(value)], check=False,
            )


        def watch(epos_idx, epos_name, last_vol):
            proc = subprocess.Popen(
                [PACTL, "subscribe"], stdout=subprocess.PIPE, text=True, bufsize=1,
            )
            try:
                for line in proc.stdout:
                    m = SINK_EVENT_RE.match(line)
                    if not m or int(m.group(1)) != epos_idx:
                        continue
                    new_vol = get_sink_volume(epos_name)
                    if new_vol is None or new_vol == last_vol:
                        continue
                    last_vol = new_vol
                    for idx, name in list_sinks():
                        if idx == epos_idx:
                            continue
                        other_vol = get_sink_volume(name)
                        if other_vol is not None and other_vol != new_vol:
                            set_sink_volume(name, new_vol)
            finally:
                proc.terminate()


        def main():
            while True:
                epos_idx, epos_name = find_epos_sink()
                if epos_idx is None:
                    time.sleep(5)
                    continue
                last_vol = get_sink_volume(epos_name)
                if last_vol is None:
                    time.sleep(5)
                    continue
                try:
                    watch(epos_idx, epos_name, last_vol)
                except Exception as e:
                    print(f"watch error: {e}", file=sys.stderr, flush=True)
                time.sleep(2)


        if __name__ == "__main__":
            main()
      '';
in
{
  options.my.hardware.epos = {
    enable = lib.mkEnableOption "EPOS gaming audio support";

    smartButtonAction = lib.mkOption {
      type = lib.types.str;
      default = "${toggleAudio}/bin/epos-toggle-audio";
      description = ''
        Shell command to run when the GSX 300 Smart Button is pressed.
        The command is executed via `sh -c` in the user's session.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      toggleAudio
    ];

    systemd.user.services.epos-smart-button = {
      Unit = {
        Description = "Bind EPOS GSX 300 Smart Button to a user action";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${reader} ${lib.escapeShellArg cfg.smartButtonAction}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.user.services.epos-volume-redirect = {
      Unit = {
        Description = "Redirect EPOS GSX 300 hardware volume knob to the default sink";
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "pipewire-pulse.service"
        ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${volumeRedirect}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
