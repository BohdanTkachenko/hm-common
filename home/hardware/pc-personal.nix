{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.hardware.pc;
in
{
  options.my.hardware.pc.enable = lib.mkEnableOption "personal PC hardware support";

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.openrgb
    ];
  };
}
