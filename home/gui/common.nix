{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ../programs/1password.nix
    ../programs/fonts.nix
    ../programs/gnome.nix
    ../programs/ptyxis.nix
    ../programs/vikno.nix
    ../programs/vscode.nix
  ];

  options.my.gui = {
    apps = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "List of GUI apps to install, which might need wrapping on non-NixOS systems";
    };

    wrapper = lib.mkOption {
      type = lib.types.functionTo lib.types.package;
      default = lib.id;
      description = "Wrapper function to apply to GUI apps (e.g. nixGL)";
    };
  };

  config = lib.mkIf config.my.gui.enable {
    my.gui.apps = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) (
      with pkgs;
      [
        apostrophe
        cameractrls-gtk4
        mission-center
        obsidian
        spotify
      ]
    );

    programs.chromium-pwa-wmclass-sync.service.enable = true;

    home.packages = map config.my.gui.wrapper config.my.gui.apps;

    xdg.autostart.entries = [
      "${pkgs.google-chrome}/share/applications/google-chrome.desktop"
    ];
  };
}
