{
  config,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../common/headless.nix
    ../common/modules/nginx
    ../common/modules/nextcloud
    ../common/modules/stalwart
    ../common/modules/wg-easy
    ../common/modules/attic
    ../common/modules/trainer
    # orchestrator./coordinator.dklaassen.de, proxied over the mesh to the
    # hot-swapped apps on hestia (decisions/hot-swap.md)
    ../common/modules/hot-swap/vhosts.nix
    # serves the mail store to hestia's restic repo (keyed on stalwart)
    ../common/modules/mail-backup
  ];

  host = {
    hostName = "olympus";
    role = "vps";
    stateVersion = "25.05";
    # wildcard cert renewed by ACME/dns-01 (../common/modules/acme)
    tls.acme = true;
  };

  # Nextcloud SSO (any authenticated user) in front of the
  # orchestrator/coordinator dashboards, on top of the VPN ACL
  # (decisions/hot-swap.md)
  hotSwap.sso = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.configurationLimit = config.host.keepGenerations;
}
