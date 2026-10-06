{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.gui.enable {
    home.packages = with pkgs; [ _1password-gui ];
  };
}
