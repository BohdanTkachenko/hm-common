{
  config,
  lib,
  pkgs,
  ...
}:
{
  # programs.gnome-shell = {
  #   enable = true;
  #   extensions = with pkgs.gnomeExtensions; [
  #     { package = xremap; }
  #   ];
  # };

  # Input remapping only matters with a graphical session.
  services.xremap = {
    enable = lib.mkForce config.my.gui.enable;
    watch = true;
    mouse = true;
    withGnome = true;
    config.keymap = [
      {
        name = "Easy tab switch in Chrome";
        remap = {
          "C-left" = "C-pageup";
          "C-right" = "C-pagedown";
          "C-up" = "C-pageup";
          "C-down" = "C-pagedown";
        };
      }
      {
        name = "Disable mouse middle click";
        remap = {
          BTN_MIDDLE = "KEY_RESERVED";
        };
      }
    ];
  };
}
