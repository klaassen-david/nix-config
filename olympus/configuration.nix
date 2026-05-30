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
    ../common/modules/nextcloud
    ../common/modules/stalwart
  ];

  host = {
    hostName = "olympus";
    role = "vps";
    stateVersion = "25.05";
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.configurationLimit = config.host.keepGenerations;
}
