{
  config,
  lib,
  pkgs,
  ...
}:

# WiFi for hosts with host.capabilities.wifi: NetworkManager driving the iwd
# backend. iwd owns association/roaming (better than wpa_supplicant), but we
# leave IP config to NetworkManager (EnableNetworkConfiguration = false) so DHCP
# and DNS still flow through NM. powersave is off to avoid latency spikes; MAC is
# randomised per-scan but stable per-connection.
#
# When the host also has a lid (host.capabilities.lid), we add lid-close
# wifi-keepalive: default logind suspends the instant the lid shuts, tearing down
# wifi. Instead logind ignores the lid and we drive suspend ourselves via acpid —
# on close we stay awake (wifi up) until the network drops or 3 minutes elapse,
# then suspend. Reopening the lid aborts it. An external display counts as
# "docked" → we never suspend, matching systemd's default
# HandleLidSwitchDocked = "ignore".

lib.mkIf config.host.capabilities.wifi (
  lib.mkMerge [
    {
      networking = {
        wireless.enable = false;
        wireless.iwd.settings.General.EnableNetworkConfiguration = false;
        networkmanager = {
          enable = true;
          wifi = {
            backend = "iwd";
            powersave = false;
            scanRandMacAddress = true;
            macAddress = "stable";
          };
        };
      };
    }

    (lib.mkIf config.host.capabilities.lid {
      services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
      };

      services.acpid.enable = true;
      # Read the actual lid state rather than parse the event tokens (their format
      # is hardware-dependent); LID0/state is confirmed present on the Framework.
      services.acpid.handlers.lid = {
        event = "button/lid.*";
        action = ''
          if ${pkgs.gnugrep}/bin/grep -qi closed /proc/acpi/button/lid/*/state; then
            ${pkgs.systemd}/bin/systemctl start --no-block lid-suspend-delay.service
          else
            ${pkgs.systemd}/bin/systemctl stop lid-suspend-delay.service
          fi
        '';
      };

      systemd.services.lid-suspend-delay = {
        description = "Hold wifi up after lid close, then suspend (max 3 min, or on network drop)";
        serviceConfig = {
          Type = "oneshot";
          # Must exceed the 180 s wait loop, else the oneshot start-timeout kills it.
          TimeoutStartSec = 240;
          ExecStart = pkgs.writeShellScript "lid-suspend-delay" ''
            set -u
            # Docked (any external connector live) → stay awake, like the default.
            for f in /sys/class/drm/*/status; do
              case "$f" in *eDP*) continue ;; esac
              [ "$(cat "$f" 2>/dev/null)" = connected ] && exit 0
            done
            # Stay awake up to 3 min, bailing early if the lid reopens (→ no suspend)
            # or the network drops (→ suspend now). acpid also stops this unit on
            # reopen; the in-loop lid poll is a belt-and-suspenders backup.
            i=0
            while [ "$i" -lt 180 ]; do
              ${pkgs.gnugrep}/bin/grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null || exit 0
              case "$(${pkgs.networkmanager}/bin/nmcli -t -f STATE g 2>/dev/null)" in
                connected*) ;;
                *) break ;;
              esac
              sleep 1
              i=$((i + 1))
            done
            # Reached only via timeout or network drop, both with the lid still shut.
            ${pkgs.systemd}/bin/systemctl suspend
          '';
        };
      };
    })
  ]
)
