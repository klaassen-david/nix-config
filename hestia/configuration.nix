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

  host = {
    hostName = "hestia";
    role = "tower";
    stateVersion = "25.05";
    gpu = "nvidia";
    display.primary = "DP-3";
    capabilities.samba = true;
    # 510M ESP only fits ~2 kernel+initrd pairs (initrd ~198M each); the
    # default of 10 overflows /boot/efi and breaks the systemd-boot install.
    keepGenerations = 2;
  };

  # games library on the second NVMe — mount by UUID so it survives the
  # nvme0/nvme1 enumeration swap; nofail keeps boot going if the disk is absent.
  fileSystems."/mnt/games" = {
    device = "/dev/disk/by-uuid/458b8b57-edd0-4426-bf5e-6d06543c46b0";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  # Bootloader
  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = config.host.keepGenerations;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot/efi";
  };

  # nvidia
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
      package = config.boot.kernelPackages.nvidiaPackages.production;
      open = false;
      nvidiaSettings = true;
      modesetting.enable = true;
    };
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  networking = {
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
