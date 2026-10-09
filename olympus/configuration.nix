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

  boot.loader.grub.enable = true;
  boot.loader.grub.configurationLimit = config.host.keepGenerations;
}
