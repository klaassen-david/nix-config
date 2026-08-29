{
  pkgs,
  host,
  lib,
  ...
}:
let
  # Middle-click target for the service blocks below: a live, read-only
  # `systemctl status <unit>` in neovim. See ./unit-status-view.nix.
  unitStatusView = pkgs.callPackage ./unit-status-view.nix { };

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

  # Is any external display actually in use? 1 iff some DRM connector other than
  # the internal panel (host.display.primary) is "enabled" in sysfs — i.e. part
  # of the current modeset. We deliberately read `enabled`, not `status`: a
  # monitor left cabled but switched off usually still keeps its EDID line
  # powered and reads status=connected, whereas `enabled` tracks whether the
  # compositor is genuinely driving the output. Read from sysfs rather than
  # swaymsg so it works from the login-time systemd invocation too (no SWAYSOCK
  # required). Sysfs connector dirs are `cardN-<connector>`, so we strip the
  # `cardN-` prefix before comparing against the primary name.
  externalDisplay = pkgs.writeShellScript "external-display" ''
    for c in /sys/class/drm/*/enabled; do
      dir=''${c%/enabled}
      name=''${dir##*/}        # cardN-<connector>, e.g. card1-eDP-1
      name=''${name#card*-}    # strip the cardN- prefix -> eDP-1
      [ "$name" = "${host.display.primary}" ] && continue
      [ "$(cat "$c" 2>/dev/null)" = enabled ] && { echo 1; exit 0; }
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
    ++ [ unitStatusView ]
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
        # swaybar renders every block as pango markup (i3status-rs sets
        # "markup":"pango" on each one unconditionally), so span attributes buy
        # more than the size bump: `foreground` overrides the theme's state
        # colour for this run of text, and `strikethrough` draws a line through
        # the glyph. Both are honoured by the bar's font.
        styledIcon =
          {
            color ? null,
            strike ? false,
          }:
          icon:
          "<span size='${toString defaultIconSize}'"
          + lib.optionalString (color != null) " foreground='${color}'"
          + lib.optionalString strike " strikethrough='true'"
          + ">${icon}</span>";
        wrapIcon = styledIcon { };
        # on/off colours for the service blocks. The blue is solarized, i.e. the
        # palette the `plain` theme's state colours already come from (green
        # #859900, yellow #b58900, red #dc322f); the white matches the bar's
        # statusline (./kanshi.nix).
        colorOn = "#268bd2";
        colorOff = "#ffffff";
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
        # on-demand sshd (common/modules/ssh-on-demand): the daemon is off at
        # boot and flipped by hand, so the bar is the only thing that says
        # whether the machine is currently reachable. Blue glyph = listening,
        # struck-through white = stopped.
        #
        # service_status reads ActiveState off org.freedesktop.systemd1 and
        # repaints when it changes — no `interval`, unlike the custom blocks
        # above. It talks to the unit's D-Bus object directly, so should systemd
        # ever unload sshd.service while it is stopped the block would error;
        # the fallback in that case is a custom block polling
        # `systemctl is-active`.
        sshServer = {
          block = "service_status";
          service = "sshd"; # the block appends .service itself
          active_format = " ${styledIcon { color = colorOn; } "󰣀"} ";
          inactive_format = " ${
             styledIcon {
               color = colorOff;
               strike = true;
             } "󰣀"
           } ";
          # both Idle so the pango foreground above is the only thing colouring
          # the glyph: the default inactive_state = Critical would paint an
          # off-by-design daemon in alarm red.
          active_state = "Idle";
          inactive_state = "Idle";
          click = [
            {
              # no sudo needed — sshd.service is in host.userManagedUnits, so
              # common/modules/polkit-units lets wheel flip it unprivileged.
              button = "right";
              # the D-Bus property change already repaints the block; this only
              # closes the gap if that signal is ever missed.
              update = true;
              cmd = ''
                if systemctl is-active -q sshd; then verb=stop; else verb=start; fi
                # a refused start is otherwise entirely silent: the glyph just
                # stays as it was and looks like a click that did not register
                err=$(systemctl "$verb" sshd 2>&1) \
                  || ${pkgs.libnotify}/bin/notify-send -u critical "sshd $verb failed" "$err"
              '';
            }
            {
              button = "middle";
              cmd = "ghostty -e ${unitStatusView}/bin/unit-status-view sshd.service";
            }
          ];
        };
        common = [
          net
        ]
        ++ lib.optional host.capabilities.onDemandSshServer sshServer
        ++ [
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
