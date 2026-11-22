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

      # WORKAROUND: rounded-window-corners crashes gnome-shell on maximize or
      # fullscreen. Keep its effect on those windows so it is never removed.
      #
      # When a window maximizes or goes fullscreen, gnome-shell's resize
      # animation (windowManager.js `_prepareAnimationInfo`) snapshots the
      # window with `actor.paint_to_content()`. While that paint runs, mutter
      # emits `size-changed` on the window texture (and `notify::size` on the
      # actor). The extension handles those signals synchronously in
      # `refreshRoundedCorners()`; with the default settings a maximized or
      # fullscreen window should not have rounded corners, so it calls
      # `remove_effect_by_name()` right there, mid-paint. Clutter flags it
      # (`clutter_actor_meta_real_set_actor: runtime check failed:
      # (!priv->actor || !CLUTTER_ACTOR_IN_PAINT (priv->actor))`), keeps
      # painting the now-detached effect, and aborts in
      # `clutter_actor_node_new: assertion failed: (actor != NULL)`. That
      # SIGABRT takes down the whole session. A Chrome PWA (Google Meet)
      # starting a call triggers it every time; any window that resizes this
      # way can.
      #
      # The removal is what crashes this path. With keepRoundedCorners on for
      # both states, the extension's `shouldEnableEffect()` stays true across
      # maximize/fullscreen, so the size-change handler only updates shader
      # uniforms and never removes the effect. Cost: maximized and fullscreen
      # windows keep 15px rounded corners. This does not cover the separate
      # add-mid-paint path PR #144 describes (a null `metaWindow` leaving the
      # handlers half-connected); that one was not seen here.
      #
      # Upstream (flexagoon/rounded-window-corners); main still runs these
      # handlers synchronously as of 2026-11-21 (extension v18 packaged here):
      # - https://github.com/flexagoon/rounded-window-corners/pull/144
      #   diagnoses this exact path, naming the keepRoundedCorners.maximized
      #   = false default; proposes deferring the handlers with GLib.idle_add.
      #   Closed unmerged 2026-07-19.
      # - https://github.com/flexagoon/rounded-window-corners/issues/115
      #   Open; same pair of Clutter assertions, including on GNOME 50 with
      #   extension v18.
      # Drop this block (back to stock defaults) once the extension defers or
      # guards effect removal in its size-change handlers.
      #
      # The key is a single a{sv}, so setting it replaces the whole default:
      # every other entry is spelled out with the extension's v18 defaults.
      "org/gnome/shell/extensions/rounded-window-corners-reborn" = {
        global-rounded-corner-settings =
          let
            entry = key: value: mkDictionaryEntry [ key (mkVariant value) ];
          in
          [
            (entry "padding" [
              (entry "left" (mkUint32 1))
              (entry "right" (mkUint32 1))
              (entry "top" (mkUint32 1))
              (entry "bottom" (mkUint32 1))
            ])
            (entry "keepRoundedCorners" [
              (entry "maximized" true)
              (entry "fullscreen" true)
            ])
            (entry "borderRadius" (mkUint32 15))
            (entry "smoothing" 0)
            (entry "borderColor" [
              0.5
              0.5
              0.5
              1.0
            ])
            (entry "enabled" true)
          ];
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
