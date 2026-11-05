{ ... }:

# Fleet members: base.nix plus the mesh, the private cache, the shared id_priv
# identity and the hardware modules. Hosts outside the mesh import base.nix alone
# (decisions/implementer-host.md).
{
  imports = [
    ./base.nix
    # self-selects server (vps) vs on-demand client by host.role
    ./modules/wireguard
    # self-gates on host.capabilities.wifi (+ lid-close keepalive on capabilities.lid)
    ./modules/wifi
    # self-gates on host.capabilities.samba
    ./modules/samba
    ./modules/wooting
    # consumer side of the self-hosted attic binary cache (substituter + pull
    # auth on every host, push on binaryCachePush hosts)
    ./modules/attic-cache
    # self-gates on host.debug.crashCapture: panic-on-hang + pstore + watchdog
    ./modules/crash-capture
    # self-gates on host.capabilities.sshServer: key-only sshd on the desktops,
    # mesh + home LAN only; headless.nix runs its own sshd
    ./modules/ssh-server
    # password-less systemctl start/stop for the units modules register in
    # host.userManagedUnits (wg-quick clients, sshd)
    ./modules/polkit-units
    # fprintd, driven by host.capabilities.fingerprint
    ./modules/fingerprint
    # self-gates on host.capabilities.chargeLimit: unprivileged battery charge limit
    ./modules/charge-limit
    # self-gates on host.gpuPowerLimitWatts (nvidia hosts only): caps board power
    ./modules/nvidia-power-limit
  ];

  # decrypt agenix secrets with the shared user key (present on every host),
  # so a single recipient (id_priv) in secrets.nix covers all machines.
  age.identityPaths = [ "/home/dk/.ssh/id_priv" ];

  # `sudo nixos-rebuild` evaluates as root, which must fetch the git+ssh
  # trainer input from dk@olympus
  programs.ssh.extraConfig = ''
    Match host dklaassen.de user dk localuser root
      IdentityFile /home/dk/.ssh/id_priv
      IdentitiesOnly yes
  '';
  programs.ssh.knownHosts."dklaassen.de".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICC2ITqo7NHmJIn8Cgd3O5ezGJAmLSE/Srlq9l8Ix9io";

  # VPN-only vhosts on olympus (modules/trainer, modules/hot-swap/vhosts.nix);
  # also in public DNS, but a router's DNS-rebind protection may drop the
  # private answer
  networking.hosts."10.100.0.1" = [
    "trainer.dklaassen.de"
    "orchestrator.dklaassen.de"
    "coordinator.dklaassen.de"
  ];
}
