{ config, lib, ... }:

lib.mkIf (config.my.hardware.lenovo.thinkpad.model == "z16-gen1") {
  # Add ThinkPad Extra Buttons to xremap's device list while still matching
  # standard keyboards (built-in and external via substring match)
  services.xremap.deviceNames = [
    "keyboard"
    "ThinkPad Extra Buttons"
  ];

  services.xremap.config.modmap = [
    {
      name = "Remap special function keys to media keys";
      device.only = [ "ThinkPad Extra Buttons" ];
      remap = {
        "KEY_PICKUP_PHONE" = "KEY_PREVIOUSSONG";
        "KEY_HANGUP_PHONE" = "KEY_PLAYPAUSE";
        "KEY_BOOKMARKS" = "KEY_NEXTSONG";
      };
    }
  ];
}
