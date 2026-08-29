# Password-less systemctl for hand-toggled units
# ==============================================
# Several services here are deliberately off at boot and started by hand —
# the wg-quick client tunnels (modules/wireguard) and the on-demand sshd
# (modules/ssh-on-demand). Reaching for `sudo` (or a password prompt) every time
# is friction on units that are *designed* to be flipped, so this grants dk the
# exact verbs on the exact units instead:
#
#   systemctl start wg-quick-tukl        # no sudo, no password
#
# How it works: a non-root `systemctl start` is a D-Bus call to systemd, which
# asks polkit for org.freedesktop.systemd1.manage-units. The rule below answers
# YES for that action when all three hold — caller in wheel, unit in
# host.userManagedUnits, verb in the toggle set — and NOT_HANDLED otherwise, so
# every other unit keeps the default "authenticate as admin" behaviour.
#
# Notes:
#   - Read-only verbs (status, is-active, show, list-units, journalctl -u) never
#     hit polkit at all; they already work unprivileged. Only state *changes* do.
#   - The rule deliberately does not test subject.active/subject.local, so it
#     also applies over SSH — you can stop sshd from the very session it serves.
#   - `enable`/`disable` are a different action (manage-unit-files) and stay
#     privileged. That is the point: nothing here can make a unit boot-persistent.
#   - polkit's JS engine is Duktape (ES5) — no arrow functions, no Array#includes.
{ config, lib, ... }:

let
  units = config.host.userManagedUnits;
  # the toggle set: enough to flip and re-flip a unit, nothing that reconfigures it
  verbs = [
    "start"
    "stop"
    "restart"
    "try-restart"
    "reload-or-restart"
  ];
  toJsList = xs: "[ ${lib.concatMapStringsSep ", " (x: ''"${x}"'') xs} ]";
in
lib.mkIf (units != [ ]) {
  security.polkit.extraConfig = ''
    // hand-toggled units: wheel may flip these without authenticating
    polkit.addRule(function (action, subject) {
      if (action.id != "org.freedesktop.systemd1.manage-units") {
        return polkit.Result.NOT_HANDLED;
      }
      if (!subject.isInGroup("wheel")) {
        return polkit.Result.NOT_HANDLED;
      }
      var units = ${toJsList units};
      var verbs = ${toJsList verbs};
      if (units.indexOf(action.lookup("unit")) < 0) {
        return polkit.Result.NOT_HANDLED;
      }
      if (verbs.indexOf(action.lookup("verb")) < 0) {
        return polkit.Result.NOT_HANDLED;
      }
      return polkit.Result.YES;
    });
  '';
}
