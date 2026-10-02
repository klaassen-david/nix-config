# sshd on the desktop hosts
# =========================
# Starts at boot like any service, so the laptop and tower are reachable over the
# mesh without anyone first logging in to flip a switch. It can still be stopped
# by hand (the unit is in host.userManagedUnits, so no sudo):
#
#   systemctl stop  sshd
#   systemctl start sshd
#
# Key-only: an always-up daemon on a machine that roams has no fail2ban (that jail
# lives in headless.nix), so passwords are off entirely. Root login is off and
# AllowUsers is pinned to dk.
#
# Port 22 is not opened globally. It is accepted on the mesh interface and from
# the home LAN prefix (the `lan` fields of the vpn.nodes registry, which keeps the
# `.local` LAN fast path working); café and university networks see a closed port.
#
# Mutually exclusive with headless.nix, which runs its own permanent sshd;
# asserted in common/host.nix.
{ config, lib, ... }:

let
  lans = lib.filter (l: l != null) (lib.mapAttrsToList (_: n: n.lan) config.vpn.nodes);
in
lib.mkIf config.host.capabilities.sshServer {
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    openFirewall = false;
    settings = {
      UseDns = false;
      PasswordAuthentication = false;
      # NixOS defaults this to true; with UsePAM that re-offers a password
      # prompt over keyboard-interactive despite PasswordAuthentication = false.
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "dk" ];
      PermitRootLogin = "no";
    };
  };

  networking.firewall.interfaces.olympus.allowedTCPPorts = [ 22 ];
  networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (
    lan: "iptables -A nixos-fw -s ${lan} -p tcp --dport 22 -j nixos-fw-accept"
  ) lans;

  # stoppable without sudo (common/modules/polkit-units)
  host.userManagedUnits = [ "sshd.service" ];
}
