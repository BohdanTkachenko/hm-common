{
  pkgs,
  pkgs-antigravity-cli,
  ...
}:
let
  pinToCCD1 = import ../../../lib/pin-to-ccd1.nix { inherit pkgs; };
in
{
  home.packages = [
    (pinToCCD1 pkgs-antigravity-cli.antigravity-cli)
  ];

  anti-drift.files = {
    ".gemini/antigravity-cli/settings.json" = {
      json = true;
      preserve = [ "trustedWorkspaces" "permissions" ];
      source = (pkgs.formats.json { }).generate "antigravity-cli-settings.json" {
        colorScheme = "dark";
        enableTelemetry = false;
        # Terminal sandbox (rootless podman/crun) works in interactive `agy`
        # sessions; under `agy -p` it silently runs on the host instead — an
        # upstream agy bug, not a NixOS issue.
        enableTerminalSandbox = true;
      };
    };
  };
}
