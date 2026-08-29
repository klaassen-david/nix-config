# On-demand SSH server (desktop hosts)
# ====================================
# Occasional remote access — pull a file off the tower, drive it from the laptop —
# does not justify a daemon listening 24/7 on a machine that also sits on café and
# university networks. So sshd is *configured* like any other service but never
# started automatically: it exists, ready, and is off until asked for.
#
#   systemctl start sshd     # on
#   systemctl stop  sshd     # off   (same idiom as the wg-quick clients)
#
# No sudo: the unit is registered in host.userManagedUnits, so modules/polkit-units
# lets wheel flip it unprivileged — including from the ssh session it serves.
#
# Off-at-boot is structural, not a habit:
#   - services.openssh.enable builds sshd.service and /etc/ssh/sshd_config as usual;
#     forcing wantedBy = [] removes the *only* thing that pulls the unit into
#     multi-user.target, so a reboot always comes up with no daemon.
#   - `systemctl enable sshd` cannot defeat that: /etc/systemd/system/*.wants is
#     regenerated from the store on every switch, so the symlink is gone after the
#     next rebuild.
#   - Host keys are unaffected — sshd-keygen.service carries its own
#     wantedBy = multi-user.target, so keys already exist when you first start sshd
#     and the manual start is neither slow nor racy.
#
# The firewall port stays open unconditionally (openFirewall). With the daemon
# stopped nothing listens, so :22 simply refuses the connection; flipping an nft
# rule in lockstep with the unit would add moving parts to hide a closed port
# behind a filtered one.
#
# PasswordAuthentication is on because this is a LAN convenience and the desktop
# base ships no fail2ban (that jail lives in headless.nix) — acceptable only
# because the daemon runs solely in the windows where you started it by hand.
# Root login is off and AllowUsers is pinned to dk.
#
# Mutually exclusive with headless.nix, which runs a permanent, key-only sshd;
# the mkForce below would silently disarm it. Asserted in common/host.nix.
{ config, lib, ... }:

lib.mkIf config.host.capabilities.onDemandSshServer {
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    openFirewall = true;
    settings = {
      UseDns = false;
      PasswordAuthentication = true;
      AllowUsers = [ "dk" ];
      PermitRootLogin = "no";
    };
  };

  # the toggle: defined, wired, but pulled in by nothing at boot
  systemd.services.sshd.wantedBy = lib.mkForce [ ];

  # ... and flippable without sudo (common/modules/polkit-units)
  host.userManagedUnits = [ "sshd.service" ];
}
