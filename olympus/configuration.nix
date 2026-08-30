{
  config,
  lib,
  pkgs,
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
    ../common/modules/mail-backup
  ];

  host = {
    hostName = "olympus";
    role = "vps";
    stateVersion = "25.05";
    # shared vhost cert renewed by ACME (../common/modules/acme) instead of the
    # hand-rolled ssl-fullchain/ssl-key pair
    tls.acme = true;
    # hestia pulls the mail store from here; see ../common/modules/mail-backup
    backup.mail.serve = true;
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.configurationLimit = config.host.keepGenerations;
}
