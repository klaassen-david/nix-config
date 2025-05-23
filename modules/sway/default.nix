{ pkgs, lib, ... } :

{
  wayland.windowManager.sway = {
    enable = true;
    config = {
      terminal = "ghostty";
      modifier = "Mod1";
      input = {
        "*" = { 
          xkb_variant = "dvorak";
          xkb_layout = "us";
        };
      };
      menu = "tofi-run | xargs swaymsg exec --";
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
    };
  };

  home.packages = with pkgs; [ 
    slurp
    tofi
  ];

  programs.tofi = {
    enable = true;
    settings = {
      font = "${pkgs.nerd-fonts.fira-code.outPath}/share/fonts/truetype/NerdFonts/FiraCode/FiraCodeNerdFontMono-Regular.ttf"; 
      output = "DP-2";
      matching-algoritm = "fuzzy";
    };
  };
}
