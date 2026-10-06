{ config, lib, ... }:

lib.mkIf (config.my.hardware.lenovo.thinkpad.model == "x1-carbon-gen12") {
  services.xremap.config.modmap = [
    {
      name = "Remap special function keys to media keys";
      device.only = [ "AT Translated Set 2 keyboard" ];
      remap = {
        home = "key_previoussong";
        end = "key_playpause";
        insert = "key_nextsong";
      };
    }
    {
      name = "Remap PageUp and PageDown keys to Home/End";
      device.only = [ "AT Translated Set 2 keyboard" ];
      remap = {
        pageup = "home";
        pagedown = "end";
      };
    }
  ];

  services.xremap.config.keymap = [
    {
      name = "Remap navigation keys";
      device.only = [ "AT Translated Set 2 keyboard" ];
      remap = {
        "C-up" = "pageup";
        "C-down" = "pagedown";
        "C-left" = "C-pageup";
        "C-right" = "C-pagedown";
      };
    }
  ];
}
