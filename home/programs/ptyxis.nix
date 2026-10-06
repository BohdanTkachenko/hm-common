{
  config,
  lib,
  pkgs,
  ...
}:
let
  defaultProfileUuid = "C0FFEE-C0DE-FEED-FACE-AC1DDEADBEEF";
  defaultProfile = {
    label = "The Coffee Coder";
    palette = "Japanesque";
    opacity = lib.gvariant.mkDouble 0.9;
    cell-height-scale = 1.0;
    use-custom-command = false;
  };
in
{
  config = lib.mkIf config.my.gui.enable {
    dconf.settings = {
      "org/gnome/Ptyxis/Shortcuts" = {
        close-tab = "<Control>w";
        close-window = "";
        copy-clipboard = "<Control>c";
        new-tab = "<Control>t";
        new-window = "<Shift><Control>n";
        paste-clipboard = "<Control>v";
        reset-and-clear = "<Shift><Control>r";
        search = "<Shift><Control>f";
        select-all = "<Control>a";
      };

      "org/gnome/Ptyxis" = {
        default-profile-uuid = defaultProfileUuid;
        profile-uuids = [
          defaultProfileUuid
        ];
        use-system-font = true;
      };

      "org/gnome/Ptyxis/Profiles/${defaultProfileUuid}" = defaultProfile;
    };
  };
}
