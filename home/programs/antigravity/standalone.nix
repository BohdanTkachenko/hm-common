{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.antigravity.cli.standalone;
  home = config.home.homeDirectory;
  # Keep the writable executable behind the managed launcher so ~/.local/bin
  # cannot bypass the launcher's CPU scheduling policy.
  installDir = "${home}/.local/share/antigravity-cli";
  executable = "${installDir}/agy";
  pinToCCD1 = import ../../../lib/pin-to-ccd1.nix { inherit pkgs; };

  launcher = pinToCCD1 (
    pkgs.writeShellApplication {
      name = "agy";
      text = ''
        if [[ ! -x ${lib.escapeShellArg executable} ]]; then
          echo "Antigravity CLI is not ready; start antigravity-cli-standalone-install.service" >&2
          exit 127
        fi
        exec ${lib.escapeShellArg executable} "$@"
      '';
    }
  );

  platform =
    {
      x86_64-linux = "linux_amd64";
      aarch64-linux = "linux_arm64";
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "Standalone Antigravity CLI requires Linux on x86-64 or ARM64");

  installer = pkgs.writeShellApplication {
    name = "antigravity-cli-standalone-install";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.gnutar
      pkgs.gzip
    ];
    text = ''
      executable=${lib.escapeShellArg executable}
      if [[ -x "$executable" && -w "$executable" && "$(readlink -f "$executable")" != /nix/store/* ]] \
        && AGY_CLI_DISABLE_AUTO_UPDATE=true "$executable" --version >/dev/null; then
        exit 0
      fi

      mkdir -p ${lib.escapeShellArg installDir}
      staging_dir=$(mktemp -d ${lib.escapeShellArg "${installDir}/.install.XXXXXXXX"})
      trap 'rm -rf "$staging_dir"' EXIT

      # Use the same manifest and SHA512 verification as the official Unix
      # installer, without its native `install` step that edits shell profiles.
      curl --proto '=https' -fsSL --retry 3 \
        ${lib.escapeShellArg "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/${platform}.json"} \
        -o "$staging_dir/manifest.json"
      url=$(jq -er '.url | select(startswith("https://"))' "$staging_dir/manifest.json")
      checksum=$(jq -er '.sha512 | select(test("^[0-9a-fA-F]{128}$"))' "$staging_dir/manifest.json")
      curl --proto '=https' -fsSL --retry 3 "$url" -o "$staging_dir/payload"
      printf '%s  %s\n' "$checksum" "$staging_dir/payload" | sha512sum --check --status

      case "$url" in
        *.tar.gz*)
          tar -xzf "$staging_dir/payload" -C "$staging_dir" antigravity
          install -m755 "$staging_dir/antigravity" "$staging_dir/agy"
          ;;
        *) install -m755 "$staging_dir/payload" "$staging_dir/agy" ;;
      esac
      AGY_CLI_DISABLE_AUTO_UPDATE=true "$staging_dir/agy" --version
      mv -fT "$staging_dir/agy" "$executable"
    '';
  };
in
{
  options.my.antigravity.cli.standalone.enable =
    lib.mkEnableOption "the self-updating standalone Antigravity CLI";

  config = lib.mkIf cfg.enable {
    my.antigravity.cli.package = launcher;
    home.file.".local/bin/agy".source = lib.getExe launcher;

    systemd.user.services.antigravity-cli-standalone-install = {
      Unit = {
        Description = "Install the self-updating Antigravity CLI";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe installer;
        Restart = "on-failure";
        RestartSec = 30;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
