{ pkgs, host, ... }:
{
  home.packages = with pkgs; [
    iwgtk
  ];

  programs.i3status-rust = {
    enable = true;
    bars.default =
      let
        defaultIconSize = 1024 * 11;
        wrapIcon = icon: "<span size='${toString defaultIconSize}'>${icon}</span>";
        net = {
          block = "net";
          format = " $icon {$signal_strength $ssid |Wired connection}";
          click = [
            {
              button = "right";
              cmd = "rfkill toggle wifi";
            }
            {
              button = "middle";
              cmd = "iwgtk";
            }
          ];
        };
        bluetooth = {
          block = "bluetooth";
          mac = "00:1B:66:27:65:39";
          format = " $icon $name{ $percentage|} ";
          disconnected_format = " $icon ";
          click = [
            {
              button = "right";
              cmd = ''
                state=$(bluetoothctl show | sed -n 's/.*Powered: //p')
                case "$state" in
                  yes) bluetoothctl power off ;;
                  no) bluetoothctl power on ;;
                esac
              '';
            }
            {
              button = "middle";
              cmd = "blueman-manager";
            }
          ];
        };
        diskSpace = {
          block = "disk_space";
          info_type = "available";
          alert_unit = "GB";
          alert = 10.0;
          warning = 15.0;
          format = " $icon $available ";
          format_alt = " $icon $available / $total ";
        };
        memory = {
          block = "memory";
          format = " $icon $mem_used_percents ";
          format_alt = " $icon $swap_used_percents ";
        };
        cpu = {
          block = "cpu";
          interval = 1;
        };
        sound = {
          block = "sound";
          click = [
            {
              button = "middle";
              cmd = "pavucontrol";
            }
          ];
        };
        time = {
          block = "time";
          format = " $timestamp.datetime(f:'%a %d/%m %T') ";
          interval = 5;
        };
        battery = {
          block = "battery";
          interval = 5;
          driver = "upower";
        };
        chargeLimit = {
          block = "custom";
          interval = 1;
          json = true;
          command = ''
            LIMIT=$(framework_tool --charge-limit 2>/dev/null | grep -oP '\d+' | tail -1)
            printf '{"text": "%s"}' "${wrapIcon "󱞜"} $LIMIT"
          '';
          click = [
            {
              button = "left";
              cmd = ''
                CURRENT=$(framework_tool --charge-limit 2>/dev/null | grep -oP '\d+' | tail -1)
                if [ "$CURRENT" -le 60 ]; then
                  framework_tool --charge-limit 100
                else
                  framework_tool --charge-limit 60
                fi
              '';
            }
          ];
        };
        powerProfiles = {
          block = "custom";
          interval = 1;
          json = true;
          command = ''
            case $(powerprofilesctl get) in 
              performance) icon="<span color='#44ff44'>󰑮</span>" ;;
              balanced)    icon="<span color='#ffaa00'>󰜎</span>" ;;
              power-saver) icon="<span color='#ff4444'></span>" ;;
            esac

            printf '{"text": "%s"}' "${wrapIcon "$icon"}"
          '';
          click = [
            {
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
            }
          ];
        };
        common = [
          net
          diskSpace
          memory
          cpu
          sound
          time
        ];
      in
      {
        settings = {
          icons_format = "${wrapIcon "{icon}"}";
        };
        icons = "material-nf";
        blocks =
          if host == "hermes" then
            common
            ++ [
              bluetooth
              battery
              chargeLimit
              powerProfiles
            ]
          else
            common ++ [ ];
      };
  };
}
