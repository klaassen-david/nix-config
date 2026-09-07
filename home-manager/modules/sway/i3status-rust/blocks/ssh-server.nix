{
  pkgs,
  styledIcon,
  colorOn,
  colorOff,
  unitStatusView,
  ...
}:

# on-demand sshd (common/modules/ssh-on-demand): the daemon is off at boot and
# flipped by hand, so the bar is the only thing that says whether the machine is
# currently reachable. Blue glyph = listening, struck-through white = stopped.
#
# service_status reads ActiveState off org.freedesktop.systemd1 and repaints
# when it changes — no `interval`, unlike the custom blocks. It talks to the
# unit's D-Bus object directly, so should systemd ever unload sshd.service while
# it is stopped the block would error; the fallback in that case is a custom
# block polling `systemctl is-active`.

{
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
}
