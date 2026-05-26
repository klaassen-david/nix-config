{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common/desktop.nix
  ];

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
    efi.efiSysMountPoint = "/boot/efi";
  };

  # nvidia
  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
    "nvidia.NVreg_EnableSignedColor=1" # Essential for 580.x drivers
    "nvidia.NVreg_EnableGpuFirmware=1" # Improves stability for newer NVIDIA cards
  ];
  boot.initrd.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];
  services.seatd.enable = true;
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        vulkan-validation-layers
        vulkan-extension-layer
        vulkan-loader
        vulkan-tools
        nvidia-vaapi-driver
        gamescope-wsi
      ];
    };
    nvidia = {
      open = true;
      nvidiaSettings = true;
      modesetting.enable = true;
    };
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  networking = {
    hostName = "hestia";
    # defaultGateway = { address = "192.168.178.3"; interface = "enp42s0"; };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    useDHCP = false;
    dhcpcd.enable = false;
    networkmanager = {
      enable = true;
      dns = lib.mkForce "none";
    };
  };
  services.resolved.enable = true;
}
