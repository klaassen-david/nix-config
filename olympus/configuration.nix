{
  lib,
  pkgs,
  ...
}:

{
  system.stateVersion = "25.05";

  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../common/headless.nix
    ../common/modules/nextcloud
    ../common/modules/stalwart
  ];

  boot.loader.grub.enable = true;

  networking = {
    hostName = "olympus";
  };
}
