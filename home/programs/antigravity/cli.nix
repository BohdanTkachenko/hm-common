{
  config,
  lib,
  pkgs,
  pkgs-antigravity-cli,
  ...
}:
let
  cfg = config.my.antigravity.cli;
  pinToCCD1 = import ../../../lib/pin-to-ccd1.nix { inherit pkgs; };
in
{
  imports = [ ./standalone.nix ];

  options.my.antigravity.cli.package = lib.mkOption {
    type = lib.types.package;
    default = pinToCCD1 pkgs-antigravity-cli.antigravity-cli;
    description = "Antigravity CLI package or launcher used by the shell and helper commands.";
  };

  config = {
    home.packages = [ cfg.package ];

    anti-drift.files = {
      ".gemini/antigravity-cli/settings.json" = {
        json = true;
        preserve = [
          "trustedWorkspaces"
          "permissions"
        ];
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
  };
}
