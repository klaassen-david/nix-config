{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
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
    "nvidia.NVreg_EnableSigndedColor=1" # Essential for 580.x drivers
    "nvidia.NVreg_EnableGpuFirmware=1"   # Improves stability for newer NVIDIA cards
  ];
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
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
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    useDHCP = false;
    dhcpcd.enable = false;
    networkmanager = {
      enable = true;
      dns = lib.mkForce "none";
    };
  };
  services.resolved.enable = true;

  security.polkit.enable = true;

  security.pam.services.swaylock.text = "auth include login";

  environment.systemPackages = with pkgs; [
  ];

  # services.openssh = {
  #   enable = true;
  #   ports = [ 22 ];
  #   settings = {
  #     UseDns = true;
  #     PasswordAuthentication = true;
  #     AllowUsers = null;
  #     PermitRootLogin = "yes";
  #   };
  # };

  programs.steam = {
    enable = true;
    protontricks.enable = true;
    gamescopeSession = {
      enable = true;
      args = [
        "--hdr-enabled"
        "--hdr-itm-enabled"
        "--hdr-sdr-content-nits" "400"
        "-W 3840"
        "-H 2160"
        "-w 3840"
        "-h 2160"
        "-r 120"
        "-f"
        # "--force-grab-cursor"
        # "--force-windows-fullscreen"
        # "--hide-cursor-delay 1"
        # "--scaler stretch"
        "--rt"
        "--mangoapp"
        "--backend" "drm"
      ];
      env = {
        # WLR_NO_HARDWARE_CURSORS="1";
        # PROTON_ENABLE_WAYLAND="1";
        # PROTON_USE_WINE3D="0";
        # PROTON_DLSS_UPGRADE="1";
        # PROTON_ENABLE_HDR="1";
        # ENABLE_GAMESCOPE_HDR="1";
        # ENABLE_GAMESCOPE_WSI="1";
        # DXVK_HDR="1";
        # WINE_ENABLE_RAW_INPUT="1";
        # PULSE_LATENCY_MSEC="50";
        # VKD3D_CONFIG="no_invariant_position";
        ENABLE_GAMESCOPE_WSI = "1";
        DXVK_HDR = "1";
        PROTON_ENABLE_HDR = "1";
        WINE_HDR_ENABLE = "1";
        WINE_GET_HDR_STATE = "1";

        WLR_NO_HARDWARE_CURSORS = "1";
        PROTON_ENABLE_WAYLAND = "1";
        NV_SURFACE_FLINGER_ALLOW_LINEAR = "1";
        DXVK_HDR_LAYER_PATH = "${pkgs.gamescope}/share/vulkan/implicit_layer.d";
        # NVIDIA Specific Fixes
        __GL_GSYNC_ALLOWED = "1";
        __GL_VRR_ALLOWED = "1";
        
        # Tell Xwayland/Gamescope to use the NVIDIA backend correctly
        XWAYLAND_NO_GLAMOR = "0";
      };
    };
  };
}
