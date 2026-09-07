{
  host,
  pkgs,
  lib,
  defaultBrowser,
  ...
}:

{
  imports = [
    ../browser # defaultBrowser: which browser the startup entry launches
    ./kanshi.nix
    ./i3status-rust
  ];

  wayland.windowManager.sway = {
    enable = true;

    wrapperFeatures.gtk = true;
    swaynag.enable = true;
    extraOptions = lib.optional (host.gpu == "nvidia") "--unsupported-gpu";
    # sway -C needs a renderer, and the build sandbox has no DRM FD to make one
    checkConfig = false;
    extraSessionCommands =
      let
        common = ''
          export MOZ_ENABLE_WAYLAND=1
          export XDG_CURRENT_DESKTOP=sway
          export XDG_SESSION_TYPE=wayland
          export QT_QPA_PLATFORM=wayland # For Qt apps
          export GDK_BACKEND=wayland     # For GTK apps
        '';
        hostSpecific =
          if host.gpu == "nvidia" then
            ''
              export __GLX_VENDOR_LIBRARY_NAME=nvidia
              export WLR_RENDERER=vulkan
              export WLR_NO_HARDWARE_CURSORS=1
              export NIXOS_OZONE_WL=1
              # If the vulkan renderer stops finding the nvidia ICD or picks the
              # wrong card, the historical fixes were pointing LD_LIBRARY_PATH /
              # VK_ICD_FILENAMES at /run/opengl-driver and pinning WLR_DRM_DEVICES
              # to the nvidia card's /dev/dri/by-path node.
            ''
          else
            "";
      in
      common + hostSpecific;

    config =
      let
        modifier = "Mod1";
      in
      {
        terminal = "ghostty";
        inherit modifier;
        menu = "tofi-run | xargs swaymsg exec --";
        startup = [
          { inherit (defaultBrowser) command; }
        ];

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

        bars = [ ];
        keybindings = lib.mkOptionDefault {
          "XF86AudioMute" = "exec swayosd-client --output-volume mute-toggle";
          "XF86AudioRaiseVolume" = "exec swayosd-client --output-volume raise";
          "XF86AudioLowerVolume" = "exec swayosd-client --output-volume lower";
          "XF86AudioPlay" = "exec playerctl play-pause";
          "XF86AudioPause" = "exec playerctl play-pause";
          "XF86AudioPrev" = "exec playerctl previous";
          "XF86AudioNext" = "exec playerctl next";
          "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
          "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
          "Ctrl+XF86MonBrightnessDown" =
            "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateTemperature n -5000";
          "Ctrl+XF86MonBrightnessUp" =
            "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateTemperature n +5000";
          "Shift+XF86MonBrightnessDown" =
            "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateBrightness d -0.1";
          "Shift+XF86MonBrightnessUp" =
            "exec busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateBrightness d +0.1";
          "${modifier}+n" = "exec swaync-client -t -sw";
          "${modifier}+p" = "exec grimshot copy area";
          "${modifier}+shift+p" = "exec grimshot copy screen";
          "${modifier}+ctrl+p" = "exec grimshot copy window";
        };
      };

    extraConfig = lib.mkOrder 1000 (
      let
        common = ''
          include /etc/sway/config.d/*

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

          exec mpvpaper ${host.display.primary} /home/dk/wallpaper/current --mpv-options "loop"

          exec wl-gammarelay-rs run

          exec swaync
        '';
        # workspace->output pinning moved to kanshi profile exec (topology-dependent);
        # lid handling stays here (laptop input behavior, not display topology)
        # On battery hosts the lid bindswitch also pokes power-profile-reconcile
        # (sway sees lid events reliably); reconcile reads the authoritative state,
        # so running it on both edges — and on --reload — is fine.
        lidReconcile = lib.optionalString host.capabilities.battery ", exec power-profile-reconcile";
        hostSpecific =
          if host.role == "laptop" then
            ''
              bindswitch --reload --locked lid:on output ${host.display.primary} disable${lidReconcile}
              bindswitch --reload --locked lid:off output ${host.display.primary} enable${lidReconcile}
            ''
          else
            "";
      in
      common + hostSpecific
    );

  };

  services.kanshi.enable = true;
  services.playerctld.enable = true;

  home.packages = with pkgs; [
    slurp
    sway-contrib.grimshot
    wl-clipboard
    brightnessctl
    wl-gammarelay-rs
    nwg-displays
    swaynotificationcenter
  ];

  programs.tofi = {
    enable = true;
    settings = {
      font = "${pkgs.nerd-fonts.fira-code.outPath}/share/fonts/truetype/NerdFonts/FiraCode/FiraCodeNerdFontMono-Regular.ttf";
      output = host.display.primary;
      matching-algorithm = "fuzzy";
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

  services.swaync = {
    enable = true;
  };

  services.swayosd.enable = true;
}
