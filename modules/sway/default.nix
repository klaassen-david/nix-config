{ pkgs, lib, ... } :

{
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    swaynag.enable = true;
    config = {
      terminal = "ghostty";
      modifier = "Mod1";
      menu = "tofi-run | xargs swaymsg exec --";
      startup = [
        { command = "zen"; }
      ];

      input = {
        "*" = { 
          xkb_variant = "dvorak";
          xkb_layout = "us";
        };
      };

      output = {
        DP-3 = {
          pos = "0 0";
          res = "2560x1440";
        };
        DP-2 = {
          pos = "2560 0";
          res = "3840x2160";
          scale = "1.3";
        };
        HDMI-A-1 = {
          pos = "5513 0";
          res = "1600x1200";
        };
      };

      window = {
        border = 0;
        hideEdgeBorders = "smart";
        titlebar = false;
      };

      bars = [];
    };

    extraConfig = ''
      workspace 1 output DP-3
      workspace 2 output DP-2
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

      exec_always mpvpaper DP-2 /home/dk/wallpaper/current --mpv-options "loop" --fork
    '';
  };

  xdg = {
    portal = {
      enable = true;

      config = {
        sway = {
          default = [ "gtk" ];
          "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        };
      };
      extraPortals = with pkgs; [
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
      ];

      # wlr.enable = true;
      # wlr.settings = {
      #   screencast = {
      #     output_name = "DP-2";
      #     chooser_type = "simple";
      #     chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
      #   };
      # };

    };
    desktopEntries = {
      nvim = {
        name = "NeoVim";
        genericName = "Text Editor";
        exec = "ghostty -e nvim";
        terminal = false;
        categories = [ "Application" "Utility" ];
        mimeType = [ "text/plain" ];
      };
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/plain" = [ "nvim.desktop" ];
      };
    };
  };

  home.packages = with pkgs; [ 
    slurp
    wl-clipboard
  ];

  programs.tofi = {
    enable = true;
    settings = {
      font = "${pkgs.nerd-fonts.fira-code.outPath}/share/fonts/truetype/NerdFonts/FiraCode/FiraCodeNerdFontMono-Regular.ttf"; 
      output = "DP-2";
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
}
