{ host, pkgs, lib, ... } :

let
  mainDisplay = if host == "hestia" then "DP-3" else "eDP-1";
in
{
  wayland.windowManager.sway = {
    enable = true;

    wrapperFeatures.gtk = true;
    swaynag.enable = true;
    extraOptions = [ "--unsupported-gpu "];
    checkConfig = false;
    extraSessionCommands = 
      let 
        common = ''
          export XDG_CURRENT_DESKTOP=sway
          export XDG_SESSION_TYPE=wayland
          export QT_QPA_PLATFORM=wayland # For Qt apps
          export GDK_BACKEND=wayland     # For GTK apps
        '';
        hostSpecific = if host == "hestia" then ''
          export __GLX_VENDOR_LIBRARY_NAME=nvidia
          export WLR_RENDERER=vulkan
          export WLR_NO_HARDWARE_CURSORS=1
          export NIXOS_OZONE_WL=1
          # export LD_LIBRARY_PATH=/run/opengl-driver/lib
          # export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json
          # export WLR_DRM_DEVICES=/dev/dri/by-path/pci-0000:2b:00.0-card
        '' else "";
      in common + hostSpecific;

    config = 
      let modifier = "Mod1";
      in {
      terminal = "ghostty";
      modifier = modifier;
      menu = "tofi-run | xargs swaymsg exec --";
      startup = [
        { command = "zen"; }
      ];

      output = 
        if host == "hestia" then
          {
            DP-1 = {
              pos = "0 0";
              res = "3840x2160";
            };
            DP-3 = {
              pos = "3840 0";
              res = "3840x2160";
              scale = "1.5";
            };
            HDMI-A-1 = {
              pos = "6400 240";
              res = "1600x1200";
            };
          }
        else if host == "hestia" then {
          DP-1 = {
            pos = "0 0";
            res = "2560x1440";
          };
          DP-4 = {
            pos = "2560 0";
            res = "2560x1440";
          };
        } else {};

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
        # "XF86AudioMute" = "exec 'pactl set-sink-mute @DEFAULT_SINK@ toggle'";
        # "XF86AudioRaiseVolume" = "exec 'pactl set-sink-volume @DEFAULT_SINK@ +5%'";
        # "XF86AudioLowerVolume" = "exec 'pactl set-sink-volume @DEFAULT_SINK@ -5%'";
        "XF86AudioMute" = "exec swayosd-client --output-volume mute-toggle";
        "XF86AudioRaiseVolume" = "exec swayosd-client --output-volume raise";
        "XF86AudioLowerVolume" = "exec swayosd-client --output-volume lower";
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
        "${modifier}+n" = "exec swaync-client -t -sw";
        "${modifier}+p" = "exec grimshot copy area";
        "${modifier}+shift+p" = "exec grimshot copy screen";
        "${modifier}+ctrl+p" = "exec grimshot copy window";
      };
    };

    extraConfig = let common = ''
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

      # bar swaybar_command waybar
      bar {
        font pango:monospace 8.000000
        mode dock
        hidden_state hide
        position bottom
        status_command i3status-rs ~/.config/i3status-rust/config-default.toml
        swaybar_command ${pkgs.sway}/bin/swaybar
        workspace_buttons yes
        strip_workspace_numbers no
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

      exec mpvpaper ${mainDisplay} /home/dk/wallpaper/current --mpv-options "loop" 

      exec wl-gammarelay-rs run 2>> /home/dk/logs/wl-gammarelay-rs

      exec swaync
    ''; 
      hostSpecific = if host == "hestia" then ''
        workspace 1 output DP-1
        workspace 2 output ${mainDisplay}
        workspace 3 output HDMI-A-1
        tray_output ${mainDisplay}
        output ${mainDisplay}
        tray_output DP-1
        output DP-1
      ''
      else if host == "hermes" then ''
        bindswitch --reload --locked lid:on output ${mainDisplay} disable
        bindswitch --reload --locked lid:off output ${mainDisplay} enable
      '' else '''';
    in common + hostSpecific;
    
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

    iwgtk # for bar
  ];

  programs.tofi = {
    enable = true;
    settings = {
      font = "${pkgs.nerd-fonts.fira-code.outPath}/share/fonts/truetype/NerdFonts/FiraCode/FiraCodeNerdFontMono-Regular.ttf"; 
      output = mainDisplay;
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
  };

  programs.i3status.enable = false;
  programs.i3status-rust = {
    enable = true;
    bars.default = {
      icons = "material-nf";
      blocks = [
        {
          block = "net";
          format = " $icon {$signal_strength $ssid |Wired connection}";
          click = [{
              button = "middle";
              cmd = "iwgtk";
          }];
        }
        {
          block = "bluetooth";
          mac = "00:1B:66:27:65:39";
          format = " $icon $name{ $percentage|} ";
          disconnected_format = " $icon ";
          click = [{
            button = "right";
            cmd = ''
              state=$(bluetoothctl show | sed -n 's/.*Powered: //p')
              case "$state" in
                yes) bluetoothctl power off ;;
                no) bluetoothctl power on ;;
              esac
            '';
          } {
              button = "middle";
              cmd = "blueman-manager";
          }];
        }
        {
          block = "disk_space";
          info_type = "available";
          alert_unit = "GB";
          alert = 10.0;
          warning = 15.0;
          format = " $icon $available ";
          format_alt = " $icon $available / $total ";
        }
        {
          block = "memory";
          format = " $icon $mem_used_percents ";
          format_alt = " $icon $swap_used_percents ";
        }
        {
          block = "cpu";
          interval = 1;
        }
        {
          block = "sound";
          click = [{
            button = "middle";
            cmd = "pavucontrol";
          }];
        }
        {
          block = "time";
          format = " $timestamp.datetime(f:'%a %d/%m %T') ";
          interval = 5;
        }
        {
          block = "battery";
          interval = 5;
          driver = "upower";
        }
        {
          block = "custom";
          interval = 1;
          json = true;
          command = ''
            LIMIT=$(framework_tool --charge-limit 2>/dev/null | grep -oP '\d+' | tail -1)
            printf '{"text": "󱞜 %s"}' "$LIMIT"
          '';
          click = [{
              button = "left";
              cmd = ''
                CURRENT=$(framework_tool --charge-limit 2>/dev/null | grep -oP '\d+' | tail -1)
                if [ "$CURRENT" -le 60 ]; then
                  framework_tool --charge-limit 100
                else
                  framework_tool --charge-limit 60
                fi
              '';
          }];
        }
        {
          block = "custom";
          interval = 1;
          json = true;
          command = ''
            case $(powerprofilesctl get) in 
              performance) icon="󰑮" ;;
              balanced)    icon="󰜎" ;;
              power-saver) icon="" ;;
            esac

            printf '{"text": "%s"}' "$icon"
          '';

          click = [{
              button = "left";
              update = true;
              cmd = ''
                current=$(powerprofilesctl get)
                case "$current" in
                  power-saver) powerprofilesctl set balanced ;;
                  balanced) powerprofilesctl set performance ;;
                  performance) powerprofilesctl set power-saver ;;
                esac
              '';
          }];
        }
      ];
    };
  };

  services.swaync = {
    enable = true;
  };

  services.swayosd.enable = true;
}
