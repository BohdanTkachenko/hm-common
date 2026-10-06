{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.gui.enable {
    home.packages = with pkgs; [
      adw-gtk3
      adwaita-icon-theme
      gnome-themes-extra
    ];

    home.activation = {
      refreshGnomeShell = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Only run if we are inside a graphical session
        if [ -n "''${XDG_DATA_DIRS:-}" ]; then
          $DRY_RUN_CMD mkdir -p $HOME/.local/share/applications $HOME/.local/share/icons
          $DRY_RUN_CMD touch $HOME/.local/share/applications $HOME/.local/share/icons
          $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database $HOME/.local/share/applications
        fi
      '';
    };

    xdg = {
      enable = true;
      mime.enable = true;

      autostart = {
        enable = true;
        entries = lib.optionals (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.spotify) [
          "${pkgs.spotify}/share/applications/spotify.desktop"
        ];
      };
    };

    systemd.user.sessionVariables.NIXOS_OZONE_WL = "1";

    gtk = {
      enable = true;
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
      };
      gtk4.theme = null;
    };

    programs.gnome-shell = {
      enable = true;
      extensions = with pkgs.gnomeExtensions; [
        { package = appindicator; }
        { package = blur-my-shell; }
        { package = caffeine; }
        # Stock Dash to Dock. A live dev checkout at ~/Projects/dash-to-dock is
        # symlinked over this in ~/.local/share/gnome-shell/extensions and
        # shadows it; remove that symlink to fall back to this packaged build.
        { package = dash-to-dock; }
        { package = just-perfection; }
        # { package = paperwm; }
        { package = search-light; }
        { package = tiling-shell; }
        { package = bing-wallpaper-changer; }
        { package = rounded-window-corners-reborn; }
      ];
    };

    dconf.settings = with lib.hm.gvariant; {
      "org/gnome/desktop/session" = {
        # The schema type is uint32; GNOME ignores a plain (int32) value.
        idle-delay = mkUint32 900;
      };

      "org/gnome/shell/extensions/just-perfection" = {
        quick-settings-airplane-mode = false;
        startup-status = 0;
      };

      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-battery-timeout = 1800;
        sleep-inactive-ac-timeout = 14400;
      };

      "org/gnome/shell/extensions/caffeine" = {
        show-notifications = false;
      };

      "org/gnome/shell/extensions/bingwallpaper" = {
        icon-name = "low-frame-symbolic";
        random-mode-include-only-uhd = true;
      };

      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        icon-theme = "Adwaita";
        gtk-enable-primary-paste = false;
        show-battery-percentage = true;
        enable-hot-corners = false;
      };

      "org/gnome/desktop/peripherals/mouse" = {
        natural-scroll = true;
      };

      "org/gnome/desktop/peripherals/touchpad" = {
        tap-to-click = false;
      };

      "org/gnome/desktop/input-sources" = {
        xkb-options = [
          "grp:sclk_toggle"
          "grp:toggle"
        ];
        sources = [
          (mkTuple [
            "xkb"
            "us"
          ])
          (mkTuple [
            "xkb"
            "ua"
          ])
        ];
      };

      "org/gnome/desktop/wm/keybindings" = {
        close = [ "<Shift><Control>q" ];
        switch-applications = [ "<Control>Tab" ];
        switch-applications-backward = [ "<Shift><Control>Tab" ];
        switch-group = [ "<Control>grave" ];
        switch-group-backward = [ "<Shift><Control>grave" ];
        switch-to-workspace-left = [ ];
        switch-to-workspace-right = [ ];
      };

      "org/gnome/desktop/wm/preferences" = {
        button-layout = "':minimize,maximize,close";
      };

      "org/gnome/mutter" = {
        experimental-features = [
          "scale-monitor-framebuffer"
          "variable-refresh-rate"
          "xwayland-native-scaling"
        ];

        overlay-key = "Super_R";
      };

      "org/gnome/settings-daemon/plugins/media-keys" = {
        next = [ "AudioNext" ];
        play = [ "AudioPlay" ];
        previous = [ "AudioPrev" ];
      };

      "org/gnome/shell/extensions/dash-to-dock" = {
        always-center-icons = true;
        apply-custom-theme = true;
        click-action = "focus-or-appspread";
        custom-theme-shrink = false;
        dash-max-icon-size = 48;
        dock-fixed = true;
        extend-height = false;
        hot-keys = false;
        isolate-monitors = true;
        show-apps-at-top = true;
        show-icons-notifications-counter = false;
        show-show-apps-button = false;
        show-trash = false;
      };

      "org/gnome/shell/extensions/search-light" = {
        shortcut-search = [ "<Control>space" ];
        popup-at-cursor-monitor = true;
      };
    };
  };
}
