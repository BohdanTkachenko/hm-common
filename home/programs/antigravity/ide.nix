{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  pkgs-antigravity-ide,
  ...
}:
let
  pinToCCD1 = import ../../../lib/pin-to-ccd1.nix { inherit pkgs; };
  settings = import ../vscode-settings.nix { inherit pkgs pkgs-unstable; };

  extensions = import ../vscode-extensions.nix {
    inherit pkgs lib config;
  };

  antigravityIdePkg = pkgs-antigravity-ide.antigravity-ide;

  antigravityIdeWithExtensions = pkgs-antigravity-ide.vscode-with-extensions.override {
    vscode = antigravityIdePkg;
    vscodeExtensions = extensions;
  };
in
{
  config = lib.mkIf config.my.gui.enable {
    home.packages = [
      (pinToCCD1 antigravityIdeWithExtensions)
    ];

    anti-drift.files = {
      ".config/Antigravity IDE/User/settings.json" = {
        source = (pkgs.formats.json { }).generate "antigravity-settings.json" (
          settings
          // config.my.vscode.extraSettings
          // {
            "securecoder.enabled" = true;
          }
        );
        json = true;
      };
    };
  };
}
