# Display input auto-switching for a monitor shared between two PCs via a USB
# KVM switch (defaults target the LG 45GX950A, but every hardware-specific value
# is an option so another box — or another monitor — can reuse this).
#
# Runs entirely in Home Manager — no root needed: the work only reads sysfs
# (unprivileged) and calls `ddcutil setvcp` over i2c, which works without sudo
# because the user is in the `i2c` group and the host sets hardware.i2c.enable
# (both system-level, configured elsewhere). `users.users.<name>.linger` makes
# the user manager — and therefore the watcher — start at boot, before anyone
# logs in; without it the panel could sit on the other input with no way to
# reach the login screen.
#
# ## Why writes are event-driven, and reads do the watching
#
# Two hardware facts, both measured on the 45GX950A, shape this:
#
#  * Re-writing the input the panel is *already* on is not a no-op: it forces a
#    full re-sync, blanking the screen for about a second. So the desired input
#    can never simply be re-asserted on a timer — that would blink forever.
#  * No register names the displayed input. `getvcp 0x60` answers with the input
#    the request *arrived on*, so over DisplayPort it always says DisplayPort-1
#    even while the panel shows the other machine; 0xF4, 0xAC/0xAE, 0xD6 and
#    0x52 are frozen too, and the DP link stays `connected`/`On` throughout, so
#    DRM sees nothing either.
#
# Writes therefore happen only when something has plausibly desynced the panel:
# KVM attach/detach, first start (boot), monitor power-on, DPMS wake, resume.
#
# That still misses drift with no event behind it, so reads — which are cheap
# and don't disturb the picture — cover the gap. The panel serves whichever
# input's picture settings are live, and those settings fingerprint the source
# well enough to tell the two apart (see fingerprintFn). The watcher samples
# that fingerprint on a timer and switches when it positively matches the wrong
# input.
#
# ## Startup ambiguity
#
# "Hub absent" means "KVM is on the other PC" only once USB has enumerated. At
# boot the watcher starts seconds after the kernel, when no hub exists yet, and
# reading that as a hand-off makes this PC shove the panel to the other machine.
# Hub *presence* is therefore trusted immediately, while hub *absence* is only
# believed after startupGraceSeconds at start, and after handoffDelaySeconds
# thereafter (a KVM flip briefly re-enumerates the hub).
#
# ## Units
#
#  * monitor-input-watch.service — the poller. Reads only sysfs (hub presence,
#    DRM connector status/dpms), decides the target, and starts the apply unit
#    on an edge. No i2c/DDC.
#  * monitor-input-apply@.service — a templated oneshot. The instance name (%i,
#    "active" or "inactive") names the input, so it does not re-read the hub.
#    Before writing it waits for the panel to answer a DDC *read*: a swallowed
#    write is invisible (`--noverify` means setvcp reports success regardless),
#    so the only defence is to write when the scaler is known to be responsive.
#    A flock serialises the write, and a target file lets the newest request
#    supersede one still waiting on the lock.
#
# Plus `monitor-input` — a CLI to switch the panel input on demand, and
# `monitor-input status` to see which source the panel is actually showing.
# A manual switch to a *third* input (HDMI) sticks, since no fingerprint is
# learned for it; switching to the input the KVM disagrees with will be
# corrected at the next verify pass.
#
# Input-select — confirmed working on the LG 45GX950A via cable DDC/CI:
#   ddcutil setvcp 0xF4 <val> --i2c-source-addr=0x50 --noverify
#   0xD0 = DisplayPort-1   0xD1 = USB-C   0x90 = HDMI-1   0x91 = HDMI-2   0x00 = AUTO
# Gotchas baked into the defaults below:
# - Opcode is LG's 0xF4, NOT standard 0x60 (which this panel ignores).
# - Source address MUST be 0x50 (not the standard 0x51).
# - The change is never reflected by getvcp, so --noverify is required.
{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardware.kvmSwitch;
  ddc = "${pkgs.ddcutil}/bin/ddcutil";
  systemctl = "${pkgs.systemd}/bin/systemctl";

  # Minimal PATH for the scripts (date, sleep, cat, grep, flock, timeout).
  binPath = "${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.util-linux}/bin";

  # Per-user runtime files: last applied input (for `toggle` and status), the
  # most recently requested target (supersede check), and the DDC write lock.
  stateFile = ''"''${XDG_RUNTIME_DIR:-/tmp}/monitor-input.state"'';
  targetFile = ''"''${XDG_RUNTIME_DIR:-/tmp}/monitor-input.target"'';
  lockFile = ''"''${XDG_RUNTIME_DIR:-/tmp}/monitor-input.lock"'';

  # The DDC write, shared by the CLI and the apply unit (opcode + source address
  # are configurable; --noverify because this panel never reflects the change).
  setvcp = ''${ddc} setvcp ${cfg.vcp.feature} "$1" --i2c-source-addr=${cfg.vcp.sourceAddr} --noverify'';

  # Optional EDID narrowing for the monitor-connected check.
  edidMatch =
    lib.optionalString (cfg.monitorEdidMatch != "")
      ''grep -qa ${lib.escapeShellArg cfg.monitorEdidMatch} "$dir/edid" 2>/dev/null || continue'';

  # Is the monitor's USB hub attached to this PC? Presence is the one unambiguous
  # signal that the KVM is pointed here.
  hubFn = ''
    hub_present() {
      for d in /sys/bus/usb/devices/*; do
        [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ] || continue
        [ "$(cat "$d/idVendor"  2>/dev/null)" = "${cfg.usb.vendorId}" ]  || continue
        [ "$(cat "$d/idProduct" 2>/dev/null)" = "${cfg.usb.productId}" ] || continue
        return 0
      done
      return 1
    }
  '';

  # The target monitor's DRM connector directory, or non-zero if it isn't
  # connected. Cheap sysfs only, no i2c probe; skips internal laptop panels and
  # optionally narrows to one monitor by EDID substring.
  monitorDirFn = ''
    monitor_dir() {
      for s in /sys/class/drm/*/status; do
        [ "$(cat "$s" 2>/dev/null)" = "connected" ] || continue
        dir="''${s%/status}"
        name="''${dir##*/}"
        case "$name" in *eDP* | *LVDS* | *DSI*) continue ;; esac
        ${edidMatch}
        echo "$dir"
        return 0
      done
      return 1
    }
  '';

  # Reading which source is on screen.
  #
  # No register reports it directly (0x60 answers with the channel the request
  # arrived on). But this panel keeps a separate set of picture settings per
  # input and serves the *displayed* input's values, so the settings themselves
  # identify the source: on the desktop DisplayPort-1 reads colour preset 0x0b /
  # sharpness 70 / gamma 0x78 where USB-C reads 0x03 / 50 / 0x64. Taken
  # together they are a fingerprint of whichever input is live — verified
  # stable while the panel was on the other machine, and reverting exactly on
  # the way back.
  #
  # This is evidence, not an identifier: it only discriminates while the two
  # inputs are configured differently, and adjusting a picture setting changes
  # it. Callers must therefore treat "matches the other input" as the only
  # actionable result — never "does not match mine".
  fingerprintFn = ''
    FP_FEATURES="${lib.concatStringsSep " " cfg.verify.features}"
    FP_TOTAL=${toString (builtins.length cfg.verify.features)}
    FP_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/monitor-input"

    # One "VCP <code> <value...>" line per feature, sorted, so two readings can
    # be compared register by register rather than all-or-nothing.
    read_fingerprint() {
      # Unquoted on purpose: the feature list must split into separate argv
      # entries for ddcutil, which reads them all over one bus open.
      # shellcheck disable=SC2086
      timeout 20 ${ddc} getvcp $FP_FEATURES --brief 2>/dev/null |
        grep '^VCP' | LC_ALL=C sort
    }

    # How many registers of reading $2 match stored fingerprint $1; -1 when
    # there is nothing stored to compare against. Scoring rather than equality
    # is what keeps a changed picture setting from invalidating the whole
    # fingerprint — adjusting the colour preset moves exactly one register.
    fp_score() {
      { [ -s "$1" ] && [ -s "$2" ]; } || { echo -1; return 0; }
      LC_ALL=C comm -12 "$1" "$2" | grep -c '^VCP' || true
    }
  '';

  # On-demand CLI: `monitor-input <target>`
  monitorInput = pkgs.writeShellScriptBin "monitor-input" ''
    set -u
    export PATH="${binPath}:$PATH"
    STATE=${stateFile}
    TARGET=${targetFile}
    LOCK=${lockFile}
    ${hubFn}
    ${monitorDirFn}
    ${fingerprintFn}

    usage() {
      cat >&2 <<'EOF'
    monitor-input — switch the monitor input
      monitor-input pc       DisplayPort-1 (this PC)
      monitor-input usbc     USB-C (other PC)
      monitor-input hdmi1    HDMI-1
      monitor-input hdmi2    HDMI-2
      monitor-input auto     auto-select
      monitor-input toggle   flip between pc and usbc
      monitor-input sync     re-apply whatever the KVM says it should be
      monitor-input status   show what this PC believes
    EOF
      exit 2
    }

    set_input() { # $1=hex value  $2=label
      # Claim the target so an apply unit still waiting on the lock stands down,
      # and hold the lock so a concurrent apply can't interleave on i2c.
      echo manual > "$TARGET" 2>/dev/null || true
      exec 9>"$LOCK"
      flock 9
      if ${setvcp}; then
        echo "$2" > "$STATE" 2>/dev/null || true
        echo "→ $2"
      else
        echo "monitor-input: failed to switch to $2" >&2
        echo "  (is the monitor detected? are you in the 'i2c' group? try: ${ddc} detect)" >&2
        exit 1
      fi
    }

    [ $# -ge 1 ] || usage
    case "$1" in
      pc | dp1 | this) set_input ${cfg.activeInput.value} "${cfg.activeInput.label}" ;;
      usbc | other)    set_input ${cfg.inactiveInput.value} "${cfg.inactiveInput.label}" ;;
      hdmi1)           set_input 0x90 "HDMI-1" ;;
      hdmi2)           set_input 0x91 "HDMI-2" ;;
      auto)            set_input 0x00 "AUTO" ;;
      toggle)
        case "$(cat "$STATE" 2>/dev/null || true)" in
          "${cfg.activeInput.label}") set_input ${cfg.inactiveInput.value} "${cfg.inactiveInput.label}" ;;
          *)                          set_input ${cfg.activeInput.value} "${cfg.activeInput.label}" ;;
        esac
        ;;
      sync)
        if hub_present; then t=active; else t=inactive; fi
        echo "re-applying $t"
        ${systemctl} --user start "monitor-input-apply@$t.service"
        ;;
      status)
        if hub_present; then
          echo "KVM hub:       present -> this PC should own the panel"
        else
          echo "KVM hub:       absent  -> the other PC should own the panel"
        fi
        if dir="$(monitor_dir)"; then
          echo "monitor:       ''${dir##*/} (dpms $(cat "$dir/dpms" 2>/dev/null || echo '?'))"
        else
          echo "monitor:       not connected"
        fi
        echo "last applied:  $(cat "$STATE" 2>/dev/null || echo '(none)')"
        cur="''${XDG_RUNTIME_DIR:-/tmp}/monitor-input.fp.cli"
        read_fingerprint > "$cur"
        if [ ! -s "$cur" ]; then
          echo "panel shows:   (no DDC response)"
        else
          sa="$(fp_score "$FP_DIR/active" "$cur")"
          si="$(fp_score "$FP_DIR/inactive" "$cur")"
          if [ "$sa" -ge ${toString cfg.verify.minMatches} ] && [ "$((sa - si))" -ge ${toString cfg.verify.minMargin} ]; then
            echo "panel shows:   ${cfg.activeInput.label}"
          elif [ "$si" -ge ${toString cfg.verify.minMatches} ] && [ "$((si - sa))" -ge ${toString cfg.verify.minMargin} ]; then
            echo "panel shows:   ${cfg.inactiveInput.label}"
          else
            echo "panel shows:   unknown — not enough to tell the inputs apart"
          fi
          echo "fingerprint:   $sa/$FP_TOTAL vs this PC, $si/$FP_TOTAL vs the other"
          echo "               (-1 = that input hasn't been switched to yet)"
        fi
        rm -f "$cur"
        ;;
      -h | --help | help) usage ;;
      *) echo "monitor-input: unknown target '$1'" >&2; usage ;;
    esac
  '';

  # Poller: watches cheap sysfs signals and starts the apply unit on an edge.
  watchScript = pkgs.writeShellScript "monitor-input-watch" ''
    set -u
    export PATH="${binPath}:$PATH"
    INTERVAL=${toString cfg.intervalSeconds}
    GRACE=${toString cfg.startupGraceSeconds}
    HANDOFF=${toString cfg.handoffDelaySeconds}
    SELF_ASSERT=${if cfg.mode == "self-assert" then "1" else "0"}
    ON_CONNECT=${if cfg.applyOnMonitorConnect then "1" else "0"}
    ON_WAKE=${if cfg.applyOnMonitorWake then "1" else "0"}
    ON_RESUME=${if cfg.applyOnResume then "1" else "0"}
    STATE=${stateFile}
    LOCK=${lockFile}
    VERIFY=${if cfg.verify.enable then "1" else "0"}
    VERIFY_INTERVAL=${toString cfg.verify.intervalSeconds}
    VERIFY_BACKOFF=${toString cfg.verify.backoffSeconds}
    MAX_STRIKES=${toString cfg.verify.maxCorrections}
    MIN_MATCH=${toString cfg.verify.minMatches}
    MARGIN=${toString cfg.verify.minMargin}
    CUR_FP=''${XDG_RUNTIME_DIR:-/tmp}/monitor-input.fp
    ACTIVE_LABEL="${cfg.activeInput.label}"
    INACTIVE_LABEL="${cfg.inactiveInput.label}"
    ${hubFn}
    ${monitorDirFn}
    ${fingerprintFn}

    # "connected"/"disconnected" and the DPMS state of the target monitor.
    monitor_state() {
      if dir="$(monitor_dir)"; then
        echo "1 $(cat "$dir/dpms" 2>/dev/null || echo unknown)"
      else
        echo "0 none"
      fi
    }

    echo "monitor-input-watch started (mode ${cfg.mode}, interval ''${INTERVAL}s)"

    # Controller mode only: at boot the hub may not be enumerated yet, and reading
    # that as "the KVM is on the other PC" would push the panel away from the
    # machine someone is sitting at. Measured against uptime rather than
    # time-in-this-loop, so a mid-session restart never waits. Self-assert never
    # acts on absence, so it has no such ambiguity and skips the wait.
    if [ "$SELF_ASSERT" = 0 ]; then
      up0="$(cut -d. -f1 /proc/uptime)"
      while ! hub_present; do
        [ "$(cut -d. -f1 /proc/uptime)" -ge "$GRACE" ] && break
        sleep 1
      done
      up1="$(cut -d. -f1 /proc/uptime)"
      [ "$((up1 - up0))" -eq 0 ] || echo "waited $((up1 - up0))s at boot for USB enumeration"
    fi

    prev_desired=""
    prev_conn=""
    prev_dpms=""
    absent_since=0
    last_tick="$(date +%s)"
    next_verify=0
    strikes=0

    while :; do
      now="$(date +%s)"
      # A wall-clock jump much larger than the interval means the machine was
      # suspended; the panel may have been handed around while we were out.
      resumed=0
      [ "$((now - last_tick))" -gt "$((INTERVAL * 5))" ] && resumed=1
      last_tick="$now"

      if hub_present; then
        absent_since=0
        desired=active
      elif [ "$SELF_ASSERT" = 1 ]; then
        # The KVM is on another machine; it asserts its own input. We never drive
        # the panel away from ourselves, so there is nothing to do.
        desired=none
      else
        [ "$absent_since" -eq 0 ] && absent_since="$now"
        # A KVM flip re-enumerates the hub, so a brief disappearance is not yet
        # a hand-off. Keep the previous target until the absence sticks.
        if [ "$((now - absent_since))" -ge "$HANDOFF" ] || [ -z "$prev_desired" ]; then
          desired=inactive
        else
          desired="$prev_desired"
        fi
      fi

      # Self-assert with the KVM elsewhere: idle until the hub returns. Recording
      # prev_desired=none means the hub reappearing reads as a "kvm -> active"
      # edge and re-asserts our input.
      if [ "$desired" = none ]; then
        prev_desired=none
        sleep "$INTERVAL"
        continue
      fi

      mstate="$(monitor_state)"
      conn="''${mstate%% *}"
      dpms="''${mstate#* }"

      reason=""
      if [ -z "$prev_desired" ]; then
        # First tick. The state file says what this PC last asked for, and it is
        # cleared each boot, so a match means this is a service restart rather
        # than a fresh boot and nothing can have desynced the panel. Skipping
        # the write there keeps rebuilds from blanking the screen for a second.
        case "$desired" in
          active) want="$ACTIVE_LABEL" ;;
          *)      want="$INACTIVE_LABEL" ;;
        esac
        [ "$(cat "$STATE" 2>/dev/null || true)" = "$want" ] || reason="startup"
      elif [ "$desired" != "$prev_desired" ]; then
        reason="kvm -> $desired"
      elif [ "$resumed" -eq 1 ] && [ "$ON_RESUME" -eq 1 ]; then
        reason="resume from suspend"
      elif [ "$ON_CONNECT" -eq 1 ] && [ "$conn" = 1 ] && [ "$prev_conn" = 0 ]; then
        reason="monitor connected"
      elif [ "$ON_WAKE" -eq 1 ] && [ "$conn" = 1 ] && [ "$dpms" = On ] && [ "$prev_dpms" != On ]; then
        reason="monitor woke"
      fi

      # An edge means the panel is being corrected anyway, so any earlier failure
      # to correct it is moot.
      [ -z "$reason" ] || strikes=0

      # No event, but the panel may still have been moved behind our back (the
      # OSD joystick, or the other machine claiming it). Read the picture-setting
      # fingerprint and act only on positive evidence that the *other* input is
      # on screen — a reading that matches neither side means the settings drifted
      # or that input was never learned, and guessing there would blank the screen
      # for nothing. Skipped while the panel is asleep so it isn't poked awake.
      if [ "$VERIFY" -eq 1 ] && [ -z "$reason" ] && [ "$conn" = 1 ] && [ "$dpms" = On ] &&
        [ "$strikes" -lt "$MAX_STRIKES" ] && [ "$now" -ge "$next_verify" ]; then
        next_verify=$((now + VERIFY_INTERVAL))
        case "$desired" in
          active) other=inactive ;;
          *)      other=active ;;
        esac
        # Either fingerprint is enough to be worth a read: with only the other
        # one learned a drift is still detectable, and with only this one
        # learned it can still be kept fresh against picture-setting changes.
        if [ -s "$FP_DIR/$other" ] || [ -s "$FP_DIR/$desired" ]; then
          (exec 9>"$LOCK"; flock 9; read_fingerprint) > "$CUR_FP"
          s_desired="$(fp_score "$FP_DIR/$desired" "$CUR_FP")"
          s_other="$(fp_score "$FP_DIR/$other" "$CUR_FP")"

          if [ ! -s "$CUR_FP" ]; then
            : # no DDC response; say nothing and try again later
          elif [ "$SELF_ASSERT" = 1 ]; then
            # Self-assert only ever knows its *own* input's fingerprint (it never
            # switches to the other one), so it acts on the absence of a match to
            # itself rather than a match to the other. We hold the KVM, so the
            # panel should be showing us; if it clearly is not, take it back. A
            # partial match is us with a picture setting changed — refresh, which
            # also keeps this test from misfiring on our own tweaks over time.
            if [ "$s_desired" -lt "$MIN_MATCH" ]; then
              strikes=$((strikes + 1))
              next_verify=$((now + VERIFY_BACKOFF))
              reason="panel is not showing us ($s_desired/$FP_TOTAL — correction $strikes/$MAX_STRIKES)"
              if [ "$strikes" -ge "$MAX_STRIKES" ]; then
                echo "verify: $MAX_STRIKES corrections did not stick — pausing checks until the next event"
              fi
            elif [ "$s_desired" -lt "$FP_TOTAL" ]; then
              strikes=0
              cp "$CUR_FP" "$FP_DIR/$desired" 2>/dev/null &&
                echo "verify: picture settings changed on $desired ($s_desired/$FP_TOTAL) -> fingerprint refreshed"
            fi
          elif [ "$s_other" -ge "$MIN_MATCH" ] && [ "$((s_other - s_desired))" -ge "$MARGIN" ]; then
            # Correcting costs a visible re-sync, and a correction that doesn't
            # take would otherwise repeat forever. Back off, and after a few
            # failures stop until a real event proves the situation changed.
            strikes=$((strikes + 1))
            next_verify=$((now + VERIFY_BACKOFF))
            reason="panel is showing $other ($s_other/$FP_TOTAL vs $s_desired — correction $strikes/$MAX_STRIKES)"
            if [ "$strikes" -ge "$MAX_STRIKES" ]; then
              echo "verify: $MAX_STRIKES corrections did not stick — pausing checks until the next event"
            fi
          elif [ "$s_desired" -ge "$MIN_MATCH" ] && [ "$((s_desired - s_other))" -ge "$MARGIN" ]; then
            strikes=0
            # Same input, but a register moved — a picture setting was adjusted.
            # Refresh the stored fingerprint, otherwise it decays until it can no
            # longer identify this input at all.
            if [ "$s_desired" -lt "$FP_TOTAL" ]; then
              cp "$CUR_FP" "$FP_DIR/$desired" 2>/dev/null &&
                echo "verify: picture settings changed on $desired ($s_desired/$FP_TOTAL) -> fingerprint refreshed"
            fi
          fi
        fi
      fi

      if [ -n "$reason" ]; then
        echo "$reason -> apply $desired"
        ${systemctl} --user start --no-block "monitor-input-apply@$desired.service" || true
      fi

      prev_desired="$desired"
      prev_conn="$conn"
      prev_dpms="$dpms"
      sleep "$INTERVAL"
    done
  '';

  # Apply: switch the panel input to the target named by $1 (active|inactive),
  # passed down from the unit instance (%i). No hub recheck — the watcher already
  # decided.
  applyScript = pkgs.writeShellScript "monitor-input-apply" ''
    set -u
    export PATH="${binPath}:$PATH"
    STATE=${stateFile}
    TARGET=${targetFile}
    LOCK=${lockFile}
    REQUIRE_MONITOR=${if cfg.requireMonitor then "1" else "0"}
    READY_TIMEOUT=${toString cfg.ddcReadyTimeoutSeconds}
    REPEATS=${toString cfg.writeRepeats}
    LEARN=${if cfg.verify.enable then "1" else "0"}
    SETTLE=${toString cfg.verify.settleSeconds}
    ${monitorDirFn}
    ${fingerprintFn}

    case "''${1:-}" in
      active)   VAL="${cfg.activeInput.value}";   LABEL="${cfg.activeInput.label}" ;;
      inactive) VAL="${cfg.inactiveInput.value}"; LABEL="${cfg.inactiveInput.label}" ;;
      *) echo "usage: monitor-input-apply <active|inactive>" >&2; exit 2 ;;
    esac
    TARGET_NAME="$1"   # $1 is reused for the DDC value below

    if [ "$REQUIRE_MONITOR" = 1 ] && ! monitor_dir >/dev/null; then
      echo "monitor not connected -> skip ($1)"
      exit 0
    fi

    # Claim the target before the (possibly long) readiness wait, so a request
    # that arrives meanwhile wins and this one stands down at the lock.
    echo "$1" > "$TARGET" 2>/dev/null || true

    # `setvcp --noverify` reports success even when the panel ignores the write,
    # which is exactly what happens while the scaler is still coming up after a
    # boot or a wake — the switch is then silently lost. Reads are free and do
    # not disturb the picture, so wait until the panel answers one before
    # writing.
    waited=0
    until timeout 10 ${ddc} getvcp ${cfg.vcp.probeFeature} --brief >/dev/null 2>&1; do
      if [ "$waited" -ge "$READY_TIMEOUT" ]; then
        echo "no DDC response after ''${READY_TIMEOUT}s -> writing blind"
        break
      fi
      sleep 2
      waited=$((waited + 2))
    done
    [ "$waited" -eq 0 ] || echo "panel answered DDC after ''${waited}s"

    # Serialise the actual write so two instances can't interleave on i2c.
    exec 9>"$LOCK"
    flock 9

    current_target="$(cat "$TARGET" 2>/dev/null || true)"
    if [ "$current_target" != "$1" ]; then
      echo "superseded by '$current_target' -> skip ($1)"
      exit 0
    fi

    set -- "$VAL"   # $1 = hex value for ${setvcp}
    rc=1
    for r in $(seq 1 "$REPEATS"); do
      [ "$r" -eq 1 ] || sleep 3
      for i in 1 2 3 4 5; do
        if ${setvcp}; then
          echo "switched to $LABEL (write $r, attempt $i)"
          rc=0
          break
        fi
        sleep 1
      done
    done

    if [ "$rc" -eq 0 ]; then
      echo "$LABEL" > "$STATE" 2>/dev/null || true
      # Relearn this input's fingerprint from the panel we just switched to, so
      # the watcher can recognise it later. Done here, still holding the lock,
      # because this is the one moment the displayed input is known for certain.
      # Settling first matters: the panel re-syncs for about a second and reads
      # taken during that report the outgoing input's settings.
      if [ "$LEARN" = 1 ]; then
        sleep "$SETTLE"
        mkdir -p "$FP_DIR" 2>/dev/null || true
        if read_fingerprint > "$FP_DIR/$TARGET_NAME.new" && [ -s "$FP_DIR/$TARGET_NAME.new" ]; then
          mv "$FP_DIR/$TARGET_NAME.new" "$FP_DIR/$TARGET_NAME"
        else
          rm -f "$FP_DIR/$TARGET_NAME.new"
          echo "could not read fingerprint for $TARGET_NAME" >&2
        fi
      fi
      exit 0
    fi
    echo "FAILED to switch to $LABEL" >&2
    exit 1
  '';

  inputSubmodule = lib.types.submodule {
    options = {
      value = lib.mkOption {
        type = lib.types.str;
        description = "DDC input-source value written to the VCP feature.";
      };
      label = lib.mkOption {
        type = lib.types.str;
        description = "Human label recorded to the state file / journal for this input.";
      };
    };
  };
in
{
  options.my.hardware.kvmSwitch = {
    enable = lib.mkEnableOption "auto display-input switch (a poller starts a templated oneshot that switches the panel input on KVM attach/detach, at boot, and when the monitor powers on, wakes, or the machine resumes)";

    mode = lib.mkOption {
      type = lib.types.enum [ "controller" "self-assert" ];
      default = "controller";
      description = ''
        How this machine drives the shared panel.

        `controller` (default) — one machine owns both inputs. Hub present selects
        `activeInput` (this PC), hub absent selects `inactiveInput` (the other PC).
        It has to *infer* whether "hub absent" means the KVM handed off or USB just
        hasn't enumerated yet (hence startupGraceSeconds), and it uses the
        fingerprint check to catch drift to the other input. Correct when only one
        side runs the agent.

        `self-assert` — every machine sharing the panel runs the agent and each one
        only ever selects its *own* input (`activeInput`), and only when the KVM
        hub is present on it. Hub absent means the KVM is on another machine, which
        will assert its own input, so this one does nothing. The USB hub's physical
        exclusivity is the coordination: no shared state, no network, and the
        startup ambiguity disappears because absence is never acted on. Set each
        host's `activeInput` to the input it is cabled to. The fingerprint check
        still runs as a backstop, but only re-asserts our own input while we hold
        the hub — it never switches the panel away from us.
      '';
    };

    intervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "How often (seconds) the poller samples the USB hub and DRM connector state.";
    };

    startupGraceSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 15;
      description = ''
        Uptime (seconds) before the hub's absence is believed at startup. The
        watcher starts a few seconds into boot, and treating a not-yet-enumerated
        hub as "the KVM is on the other PC" would push the panel away from the
        machine someone is sitting at. Hub *presence* is always acted on at once,
        and the wait is against uptime, so this only ever costs anything on a
        cold boot. On the desktop USB enumerates by ~2.5s, so 15s is ample.
      '';
    };

    handoffDelaySeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 2;
      description = "How long the hub must stay absent before treating it as a hand-off to the other PC (a KVM flip briefly re-enumerates the hub).";
    };

    ddcReadyTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 60;
      description = "How long to wait for the panel to answer a DDC read before writing anyway. Guards the boot/wake race where a write is accepted by the i2c layer but ignored by a scaler that is still coming up.";
    };

    writeRepeats = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        How many times to send the input-select write per apply. Leave at 1:
        re-selecting the input the panel already shows forces a full re-sync and
        blanks the screen for about a second, so extra writes are visible.
      '';
    };

    # The three "the panel may have come back somewhere else" edges, split
    # because they differ by orders of magnitude in how often they fire — and
    # every apply costs a ~1s re-sync, since the panel can't be asked whether
    # a write is even needed.
    applyOnMonitorConnect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Re-apply when the monitor's DRM connector appears — it was powered on, or its cable was replugged, and it may have come back on the other input.";
    };

    applyOnMonitorWake = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Re-apply when the monitor wakes from DPMS (the session's screen blank).
        Off by default: this edge fires on every single wake, and since the panel
        can't be asked whether a switch is even needed, each one costs a ~1s
        black flash — a poor trade against the rare case of the panel being
        moved while the screen was off. `monitor-input sync` covers that case on
        demand. The rarer, higher-value wake edges (applyOnMonitorConnect,
        applyOnResume) stay on.
      '';
    };

    applyOnResume = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Re-apply after resume from suspend, detected as a wall-clock jump much larger than the poll interval.";
    };

    verify = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Periodically check which input the panel is actually showing, and
          correct it when it is the wrong one. This is the only way to catch
          drift that arrives with no event behind it — the OSD joystick, or the
          other machine taking the panel.

          It works because the monitor keeps per-input picture settings and
          reports the displayed input's values, so those settings fingerprint
          the live source (there is no register that names it). Fingerprints are
          learned automatically each time this PC switches an input, since that
          is the one moment the displayed source is known for certain.

          Only a positive match against the *other* input's fingerprint triggers
          a switch, so identically-configured inputs simply make this a no-op
          rather than a source of spurious switching.
        '';
      };

      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "How often (seconds) to read the fingerprint. Reads are cheap (~0.3s) and, unlike writes, do not disturb the picture. Skipped while the monitor is asleep.";
      };

      minMatches = lib.mkOption {
        type = lib.types.ints.positive;
        default = 6;
        description = ''
          How many of the fingerprint's registers must match before a reading is
          believed to identify an input at all. Below this it is treated as
          unknown. Set relative to `features` (6 of 8 by default), leaving room
          for a couple of picture settings to have been adjusted since the
          fingerprint was learned.
        '';
      };

      minMargin = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = ''
          How much better a reading must match one input than the other before
          acting on it. Guards the case where the two inputs share most of their
          settings: a thin lead is not evidence, and switching on it would blank
          the screen for a guess.
        '';
      };

      backoffSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "How long to wait before re-checking after a correction, so a switch that is still settling isn't read as another drift.";
      };

      maxCorrections = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = ''
          How many consecutive corrections may fail to stick before verification
          pauses until the next real event. Without this, a panel that refuses
          the write — or a fingerprint that has gone stale in a way that always
          reads as the other input — would re-sync the screen forever.
        '';
      };

      settleSeconds = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 3;
        description = "How long to wait after a switch before learning the new input's fingerprint. The panel re-syncs for about a second, and a read taken during that still reports the outgoing input.";
      };

      features = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "0x0C"
          "0x14"
          "0x15"
          "0x72"
          "0x87"
          "0xF5"
          "0xF9"
          "0xFE"
        ];
        description = ''
          VCP features read to fingerprint the live input — the ones measured to
          differ between this monitor's inputs (colour preset, sharpness, gamma
          and LG's proprietary equivalents). Must not include self-changing
          registers: 0xAF is a counter that increments on every read and would
          make every fingerprint unique. `ddcutil getvcp` accepts at most 20
          features per call.
        '';
      };
    };

    usb = {
      vendorId = lib.mkOption {
        type = lib.types.str;
        default = "05e3";
        description = "USB idVendor of the monitor's built-in hub to watch (lowercase hex, no 0x).";
      };
      productId = lib.mkOption {
        type = lib.types.str;
        default = "0610";
        description = "USB idProduct of the monitor's built-in hub to watch (lowercase hex, no 0x).";
      };
    };

    vcp = {
      feature = lib.mkOption {
        type = lib.types.str;
        default = "0xF4";
        description = "DDC/CI VCP feature code for input select (LG uses 0xF4, not the standard 0x60).";
      };
      sourceAddr = lib.mkOption {
        type = lib.types.str;
        default = "0x50";
        description = "ddcutil --i2c-source-addr value (the LG needs 0x50, not the standard 0x51).";
      };
      probeFeature = lib.mkOption {
        type = lib.types.str;
        default = "0x60";
        description = ''
          A harmless VCP feature read to prove the panel is answering DDC before
          a write. Its *value* is useless here — this monitor reports the input
          the request arrived on, not the one it displays — but a successful read
          means the scaler is up.
        '';
      };
    };

    activeInput = lib.mkOption {
      type = inputSubmodule;
      default = {
        value = "0xD0";
        label = "DisplayPort-1 (this PC)";
      };
      description = "Input to select when the USB hub is present on this PC (this PC is active).";
    };

    inactiveInput = lib.mkOption {
      type = inputSubmodule;
      default = {
        value = "0xD1";
        label = "USB-C (other PC)";
      };
      description = "Input to select when the USB hub is absent (handed off to the other PC).";
    };

    requireMonitor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only switch when an external monitor is actually connected (so it's safe on an undocked laptop).";
    };

    monitorEdidMatch = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "ULTRAGEAR";
      description = "If set, the monitor-connected check only counts a connected output whose EDID contains this substring. Empty means any external (non-internal) output.";
    };
  };

  config = {
    # The CLI is always available (harmless on hosts without the monitor).
    home.packages = [ monitorInput ];

    # The poller (long-running) and the templated apply oneshot it triggers. User
    # services: they run in the logged-in session and need the user in the `i2c`
    # group + hardware.i2c.enable (set at the NixOS level). Lingering is what
    # gets them running at boot rather than at first login.
    systemd.user.services.monitor-input-watch = lib.mkIf cfg.enable {
      Unit.Description = "Watch the KVM hub and monitor state, and switch the panel input on change";
      Service = {
        ExecStart = "${watchScript}";
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services."monitor-input-apply@" = lib.mkIf cfg.enable {
      Unit.Description = "Switch the monitor input to %i (active=${cfg.activeInput.label}, inactive=${cfg.inactiveInput.label})";
      Service = {
        Type = "oneshot";
        ExecStart = "${applyScript} %i";
        # Generous: the readiness wait can legitimately run the whole
        # ddcReadyTimeoutSeconds when the panel is still coming up.
        TimeoutStartSec = cfg.ddcReadyTimeoutSeconds + 60;
      };
      # No Install/WantedBy: started on demand by the poller (or by hand).
    };
  };
}
