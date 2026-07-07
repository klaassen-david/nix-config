{
  pkgs,
  host,
  lib,
  ...
}:
let
  # Where the powerProfiles bar block records the last manually chosen profile.
  # Same expression is inlined into both the block's click handler (the writer)
  # and the reconcile script (the reader), so they never drift.
  manualFile = ''"''${XDG_STATE_HOME:-$HOME/.local/state}/power-profile/manual"'';

  # AC state as 0|1 (any Mains supply online). Factored out so the reconcile rule
  # and the monitor's edge filter share one definition.
  onAc = pkgs.writeShellScript "on-ac" ''
    for ps in /sys/class/power_supply/*; do
      [ "$(cat "$ps/type" 2>/dev/null)" = Mains ] || continue
      [ "$(cat "$ps/online" 2>/dev/null)" = 1 ] && { echo 1; exit 0; }
    done
    echo 0
  '';

  # Is any external display connected? 1 iff some DRM connector other than the
  # internal panel (host.display.primary) reports "connected" in sysfs. Read from
  # sysfs rather than swaymsg so it works from the login-time systemd invocation
  # too (no SWAYSOCK required). Sysfs connector dirs are `cardN-<connector>`, so
  # we strip the `cardN-` prefix before comparing against the primary name.
  externalDisplay = pkgs.writeShellScript "external-display" ''
    for c in /sys/class/drm/*/status; do
      dir=''${c%/status}
      name=''${dir##*/}        # cardN-<connector>, e.g. card1-eDP-1
      name=''${name#card*-}    # strip the cardN- prefix -> eDP-1
      [ "$name" = "${host.display.primary}" ] && continue
      [ "$(cat "$c" 2>/dev/null)" = connected ] && { echo 1; exit 0; }
    done
    echo 0
  '';

  # The one place the profile rule lives: lid closed *and no external display* ->
  # power-saver (wins the closed+charging overlap), else on AC -> performance,
  # else the last manual value. A closed lid while docked to an external screen is
  # a desktop session, not an on-the-go one, so it falls through to the AC/manual
  # rule instead of dropping to power-saver. Invoked ONLY on real lid/AC
  # transitions (the sway lid bindswitch and the monitor's AC edge filter) — never
  # on periodic ticks, and never by the bar click. So a manual click holds until
  # the next lid/AC transition, at which point the rule reasserts.
  reconcile = pkgs.writeShellScriptBin "power-profile-reconcile" ''
    set -u
    ppctl=${pkgs.power-profiles-daemon}/bin/powerprofilesctl
    manual=${manualFile}

    lid=open
    ${lib.optionalString host.capabilities.lid ''lid=$(${host.lid_state})''}

    if [ "$lid" = closed ] && [ "$(${externalDisplay})" = 0 ]; then
      target=power-saver
    elif [ "$(${onAc})" = 1 ]; then
      target=performance
    else
      target=$(cat "$manual" 2>/dev/null || true)
      [ -n "$target" ] || target=$("$ppctl" get)
    fi

    [ "$("$ppctl" get)" = "$target" ] || "$ppctl" set "$target"
  '';
in
{
  home.packages =
    (with pkgs; [
      iwgtk
    ])
    ++ lib.optional host.capabilities.battery reconcile;

  # Reconcile at login, then on AC edges only. upower --monitor is noisy (battery
  # ticks fire it constantly), so we re-derive AC state on each event and act only
  # when it flips — otherwise a periodic tick would revert a value the user forced
  # via the bar click. Lid edges come from the sway bindswitch in ../sway.
  systemd.user.services.power-profile-reconcile = lib.mkIf host.capabilities.battery {
    Unit = {
      Description = "Reconcile power profile on lid/AC change (lid > AC > manual)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "power-profile-reconcile-monitor" ''
        ${reconcile}/bin/power-profile-reconcile
        prev=$(${onAc})
        ${pkgs.upower}/bin/upower --monitor | while read -r _; do
          cur=$(${onAc})
          [ "$cur" = "$prev" ] && continue
          prev=$cur
          ${reconcile}/bin/power-profile-reconcile
        done
      '';
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

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
                case "$(powerprofilesctl get)" in
                  power-saver) next=balanced ;;
                  balanced) next=performance ;;
                  performance) next=power-saver ;;
                esac
                powerprofilesctl set "$next"
                # Record as the manual value the reconcile script restores to.
                manual=${manualFile}
                mkdir -p "$(dirname "$manual")"
                printf '%s\n' "$next" > "$manual"
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
