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

  boot.kernelModules = [ "ryzen_smu" ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware = {
    graphics.enable = true;
  };
  services.xserver.videoDrivers = [ "amdgpu" ];

  networking = {
    hostName = "hermes";
    wireless.enable = false;
    wireless.iwd.settings.General.EnableNetworkConfiguration = false;
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
    settings = { 
      General = {
        Experimental = true;
        MultiProfile = "multiple";
        AutoConnect = true;
        Enable = "Source,Sink,Media,Socket";
      }; 
    };
  };
  services.blueman.enable = true;
  services.pipewire = {
    wireplumber.enable = true;
    wireplumber.extraConfig = {
      "10-bluetooth" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [ "a2dp_sink" "a2dp_source" "bap_sink" "bap_source" "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" ];
          "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "aptx" "aptx_hd" "ldac" ];
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    playerctl
    calibre
    framework-tool
  ];


  programs.steam = {
    enable = true;
  };

  # fingerprint auth
  services.fprintd.enable = true;
  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.login.fprintAuth = true;
  security.pam.services.swaylock.fprintAuth = true;

  security.wrappers.framework_tool = {
    source = "${pkgs.framework-tool}/bin/framework_tool";
    owner = "root";
    group = "root";
    setuid = true;
  };

  services.upower = {
    enable = true;
  };
}
