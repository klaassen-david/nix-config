{
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
  ];

  system.stateVersion = "25.05";

  boot.loader.grub.enable = true;

  networking = {
    hostName = "olympus";
  };
}
