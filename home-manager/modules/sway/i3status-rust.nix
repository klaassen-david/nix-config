{
  pkgs,
  host,
  lib,
  ...
}:
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
        # next appointment from the pimsync-synced khal calendars (../calendar).
        # left-click opens ikhal. khal format flags / icon may want tuning once
        # real events exist; before the first pimsync sync this shows "No events".
        calendar = {
          block = "custom";
          shell = "sh";
          interval = 60;
          json = true;
          command = ''
            next=$(${pkgs.khal}/bin/khal list --notstarted -df "" -f "{start-time} {title}" now 24h 2>/dev/null | grep -m1 . | tr -d '"')
            printf '{"text": "%s %s"}' "${wrapIcon "󰃭"}" "''${next:-No events}"
          '';
          click = [
            {
              button = "middle";
              cmd = "ghostty -e ikhal";
            }
          ];
        };
        battery = {
          block = "battery";
          interval = 5;
          driver = "upower";
        };
        chargeLimit = {
          block = "custom";
          shell = "sh";
          interval = 1;
          json = true;
          command = ''
            LIMIT=$(framework_tool --charge-limit 2>/dev/null | grep -oP '\d+' | tail -1)
            STATE=$([ "$LIMIT" -le 60 ] && echo "Good" || echo "Warning")
            printf '{"text": "%s %s", "state": "%s"}' "${wrapIcon "󱞜"}" "$LIMIT" "$STATE"
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
          shell = "sh";
          json = true;
          command = ''
            case $(powerprofilesctl get) in
              performance) icon="󰑮"; state="Warning" ;;
              balanced)    icon="󰜎"; state="Info" ;;
              power-saver) icon=""; state="Good" ;;
            esac

            printf '{"text": "%s", "state": "%s"}' "${wrapIcon "$icon"}" "$state"
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
          calendar
          time
        ];
      in
      {
        settings = {
          icons_format = "${wrapIcon "{icon}"}";
        };
        icons = "material-nf";
        blocks =
          common
          ++ lib.optionals host.capabilities.bluetooth [ bluetooth ]
          ++ lib.optionals host.capabilities.battery [
            battery
            chargeLimit
            powerProfiles
          ];
      };
  };
}
