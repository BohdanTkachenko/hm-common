{
  config,
  lib,
  pkgs,
  ...
}:
let

  emojiFontFamily = "Noto Color Emoji";
  fontFamily = "Adwaita Sans";
  monospaceFontFamily = "MesloLGL Nerd Font Mono";
  gnomeFontSize = "12";
  gnomeMonospaceFontSize = "12";
  gnomeFontName = "${fontFamily} ${gnomeFontSize}";
  gnomeMonospaceFontName = "${monospaceFontFamily} ${gnomeMonospaceFontSize}";
in
{
  config = lib.mkIf config.my.gui.enable {

    home.packages = with pkgs; [
      adwaita-fonts
      nerd-fonts.meslo-lg
      noto-fonts-color-emoji
    ];

    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        emoji = [ emojiFontFamily ];
        monospace = [ monospaceFontFamily ];
        sansSerif = [ fontFamily ];
        serif = [ fontFamily ];
      };
    };

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        font-name = gnomeFontName;
        document-font-name = gnomeFontName;
        monospace-font-name = gnomeMonospaceFontName;
      };
    };
  };
}
