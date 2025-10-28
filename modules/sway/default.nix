{ pkgs, lib, ... } :

{
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    swaynag.enable = true;
    extraOptions = [ "--unsupported-gpu "];
    config = {
      terminal = "ghostty";
      modifier = "Mod1";
      menu = "tofi-run | xargs swaymsg exec --";
      startup = [
        { command = "zen"; }
      ];

      output = {
        DP-1 = {
          pos = "0 0";
          res = "2560x1440";
        };
        DP-3 = {
          pos = "2560 0";
          res = "3840x2160";
          scale = "1.5";
        };
        HDMI-A-1 = {
          pos = "5120 240";
          res = "1600x1200";
        };
      };

      input = {
        "type:keyboard" = {
          xkb_layout = "gb,de,us";
          xkb_variant = ",,dvorak";
          xkb_options = "grp:win_space_toggle,caps:escape_shifted_capslock";
          repeat_rate = "45";
          repeat_delay = "500";
        };
        "type:touchpad" = {
          natural_scroll = "enabled";
          scroll_factor = "0.5";
          scroll_method = "two_finger";
          pointer_accel = "0.4";
          clickfinger_button_map = "lrm";
          tap_button_map = "lrm";
          tap = "enabled";
          drag = "disabled";
        };
      };

      window = {
        border = 0;
        hideEdgeBorders = "smart";
        titlebar = false;
      };

      bars = [];
      keybindings = lib.mkOptionDefault {
        "XF86AudioMute" = "exec 'pactl set-sink-mute @DEFAULT_SINK@ toggle'";
        "XF86AudioRaiseVolume" = "exec 'pactl set-sink-volume @DEFAULT_SINK@ +5%'";
        "XF86AudioLowerVolume" = "exec 'pactl set-sink-volume @DEFAULT_SINK@ -5%'";
        "XF86AudioPlay" = "exec playerctl play-pause";
        "XF86AudioPause" = "exec playerctl play-pause";
        "XF86AudioPrev" = "exec playerctl previous";
        "XF86AudioNext" = "exec playerctl next";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
        "Ctrl+XF86MonBrightnessDown" = "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateTemperature n -5000";
        "Ctrl+XF86MonBrightnessUp" = "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateTemperature n +5000";
        "Shift+XF86MonBrightnessDown" = "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateBrightness d -0.1";
        "Shift+XF86MonBrightnessUp" = "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateBrightness d +0.1";
      };
    };

    extraConfig = ''
      include /etc/sway/config.d/*

      workspace 1 output DP-1
      workspace 2 output DP-3
      workspace 3 output HDMI-A-1

      # XDG
      exec systemctl --user set-environment XDG_CURRENT_DESKTOP=sway

      exec systemctl --user import-environment DISPLAY \
        SWAYSOCK \
        WAYLAND_DISPLAY \
        XDG_CURRENT_DESKTOP

      exec hash dbus-update-activation-environment 2>/dev/null && \
        dbus-update-activation-environment --systemd DISPLAY \
          SWAYSOCK \
          XDG_CURRENT_DESKTOP=sway \
          WAYLAND_DISPLAY

      # bar swaybar_command waybar
      bar {
        font pango:monospace 8.000000
        mode dock
        hidden_state hide
        position bottom
        status_command ${pkgs.i3status}/bin/i3status
        swaybar_command ${pkgs.sway}/bin/swaybar
        workspace_buttons yes
        strip_workspace_numbers no
        tray_output DP-1
        output DP-1
        output DP-3
        colors {
          background #000000
          statusline #ffffff
          separator #666666
          focused_workspace #4c7899 #285577 #ffffff
          active_workspace #333333 #5f676a #ffffff
          inactive_workspace #333333 #222222 #888888
          urgent_workspace #2f343a #900000 #ffffff
          binding_mode #2f343a #900000 #ffffff
        }
      }

      exec mpvpaper DP-3 /home/dk/wallpaper/current --mpv-options "loop" 

      exec wl-gammarelay-rs run 2>> /home/dk/logs/wl-gammarelay-rs
    '';
  };

  # xdg = {
  #   portal = {
  #     enable = true;
  #
  #     config = {
  #       sway = {
  #         default = [ "gtk" ];
  #         "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
  #         "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
  #       };
  #     };
  #     extraPortals = with pkgs; [
  #       xdg-desktop-portal-wlr
  #       xdg-desktop-portal-gtk
  #     ];
  #   };
  #   desktopEntries = {
  #     nvim = {
  #       name = "NeoVim";
  #       genericName = "Text Editor";
  #       exec = "ghostty -e nvim";
  #       terminal = false;
  #       categories = [ "Application" "Utility" ];
  #       mimeType = [ "text/plain" ];
  #     };
  #   };
  #
  #   mimeApps = {
  #     enable = true;
  #     defaultApplications = {
  #       "text/plain" = [ "nvim.desktop" ];
  #     };
  #   };
  # };

  services.kanshi.enable = true;
  services.playerctld.enable = true;

  home.packages = with pkgs; [ 
    slurp
    wl-clipboard
    brightnessctl
    wl-gammarelay-rs
    nwg-displays
  ];

  programs.tofi = {
    enable = true;
    settings = {
      font = "${pkgs.nerd-fonts.fira-code.outPath}/share/fonts/truetype/NerdFonts/FiraCode/FiraCodeNerdFontMono-Regular.ttf"; 
      output = "DP-3";
      matching-algoritm = "fuzzy";
      width = "100%";
      height = "100%";
      border-width = 0;
      outline-width = 0;
      padding-left = "35%";
      padding-top = "35%";
      result-spacing = 25;
      num-results = 5;
      background-color = "#000A";
    };
  };

  programs.mpv.enable = true;
  programs.mpvpaper.enable = true;
  xdg.configFile."mpvpaper/pauselist".text = "";
  xdg.configFile."mpvpaper/stoplist".text = "";

  home.sessionVariables = {
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland"; # For Qt apps
    GDK_BACKEND = "wayland";     # For GTK apps
  };

  # programs.waybar = {
  #   enable = true;
  #   settings = {
  #     mainBar = {
  #       layer = "top";
  #       position = "bottom";
  #       height = 30;
  #       output = [
  #         "DP-1"
  #         "DP-3"
  #       ];
  #       modules-left = [ "sway/workspaces" ];
  #       # modules-center = [ "sway/window" ];
  #       modules-right = [ "sway/mode" ];
  #     };
  #   };
  # };

}
