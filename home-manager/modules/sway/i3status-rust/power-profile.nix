{ pkgs, lib, host }:

# Everything behind ./blocks/power-profiles.nix: the lid/AC rule, the
# `power-profile-reconcile` command the sway lid bindswitch calls (../default.nix),
# and the monitor ./default.nix runs as a user service. The block itself only
# needs `manualFile` — it is the writer of the value the rule falls back to.

let
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
in
rec {
  # Where the bar block records the last manually chosen profile. One expression
  # for both the block's click handler (the writer) and the reconcile script
  # (the reader), so they never drift.
  manualFile = ''"''${XDG_STATE_HOME:-$HOME/.local/state}/power-profile/manual"'';

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
    ${lib.optionalString host.capabilities.lid "lid=$(${host.lid_state})"}

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

  # Reconcile at login, then on AC edges only. upower --monitor is noisy (battery
  # ticks fire it constantly), so we re-derive AC state on each event and act only
  # when it flips — otherwise a periodic tick would revert a value the user forced
  # via the bar click. Lid edges come from the sway bindswitch in ../default.nix.
  monitor = pkgs.writeShellScript "power-profile-reconcile-monitor" ''
    ${reconcile}/bin/power-profile-reconcile
    prev=$(${onAc})
    ${pkgs.upower}/bin/upower --monitor | while read -r _; do
      cur=$(${onAc})
      [ "$cur" = "$prev" ] && continue
      prev=$cur
      ${reconcile}/bin/power-profile-reconcile
    done
  '';
}
