{ config, lib, ... }:
let
  cfg = config.my.hardware.lenovo.thinkpad;
in
{
  imports = [
    ./lenovo-thinkpad-x1-carbon-gen12.nix
    ./lenovo-thinkpad-z16-gen1.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.model != null;
        message = "You must specify 'my.hardware.lenovo.thinkpad.model' when the Thinkpad tweaks are enabled.";
      }
    ];

    services.xremap.config.modmap = lib.mkIf cfg.enable [
      {
        name = "Put modifier keys in more usable places";
        device.only = [ "AT Translated Set 2 keyboard" ];
        remap = {
          "Alt_L" = "Control_L";
          "Super_L" = "Alt_L";
          "Control_L" = "Super_L";
        };
      }
      {
        name = "Make CapsLock useful";
        device.only = [ "AT Translated Set 2 keyboard" ];
        remap = {
          "CapsLock" = "Backspace";
        };
      }
    ];
  };
}
