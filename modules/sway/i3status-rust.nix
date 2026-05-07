{pkgs, ...}: {
  home.packages = with pkgs; [
    iwgtk
  ];

  programs.i3status-rust = {
    enable = true;
    bars.default = let 
      defaultIconSize = 1024 * 11; 
      wrapIcon = icon: "<span size='${toString defaultIconSize}'>${icon}</span>";

    in {
      settings = {
        icons_format = "${wrapIcon "{icon}"}";
      };
      icons = "material-nf";
      blocks = [
        {
          block = "net";
          format = " $icon {$signal_strength $ssid |Wired connection}";
          click = [{
            button = "right";
            cmd = "rfkill toggle wifi";
          } {
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
            printf '{"text": "%s"}' "${wrapIcon "󱞜"} $LIMIT"
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

            printf '{"text": "%s"}' "${wrapIcon "$icon"}"
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
}
