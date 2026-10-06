{
  config,
  lib,
  pkgs,
  pkgs-antigravity-hub,
  ...
}:
let
  pinToCCD1 = import ../../../lib/pin-to-ccd1.nix { inherit pkgs; };
in
{
  config = lib.mkIf config.my.gui.enable {
    home.packages = [
      (pinToCCD1 pkgs-antigravity-hub.antigravity-hub)
    ];
  };
}
