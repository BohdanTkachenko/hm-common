{ config, lib, ... }:
{
  config = lib.mkIf config.my.gui.enable {
    dconf.settings = {
      "io/github/bohdantkachenko/Vikno/Shortcuts" = {
        close-tab = "<Control>w";
        copy = "<Control>c";
        new-tab = "<Control>t";
        paste = "<Control>v";
        undo-close-tab = "<Control>y";
      };
    };
  };
}
