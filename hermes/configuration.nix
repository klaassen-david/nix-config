{ lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  powerManagement.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

  # Bootloader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware = {
    graphics.enable = true;
  };
  services.xserver.videoDrivers = [ "amdgpu" ];

  networking = {
    hostName = "hermes";
    wireless.enable = false;
    networkmanager = {
      enable = true;
      wifi = {
        backend = "iwd";
        powersave = false;
        scanRandMacAddress = true;
        macAddress = "stable";
      };
    };
  };

  # bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = { General = {Experimental = true;}; };
  };
  services.blueman.enable = true;

  environment.systemPackages = with pkgs; [
    playerctl
    calibre
    framework-tool
  ];


  programs.steam = {
    enable = true;
  };
}
