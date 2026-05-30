{ lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../common/desktop.nix
  ];

  powerManagement.enable = true;

  host = {
    hostName = "hermes";
    role = "laptop";
    stateVersion = "25.05";
    gpu = "amdgpu";
    display.primary = "eDP-1";
    capabilities = {
      wifi = true;
      bluetooth = true;
      battery = true;
      fingerprint = true;
    };
  };

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
  hardware.enableAllFirmware = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        MultiProfile = "multiple";
      };
    };
  };
  services.blueman.enable = true;
  users.users.dk.extraGroups = [ "bluetooth" ];
  services.pipewire = {
    wireplumber.enable = true;
    wireplumber.extraConfig = {
      "10-bluetooth-policy" = {
        "wireplumber.settings" = {
          # Keep A2DP profile when in-ears connect; don't auto-switch to HFP/HSP
          "bluetooth.autoswitch-to-headset-profile" = false;
        };
      };
      "10-bluetooth" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
            "bap_sink"
            "bap_source"
            "hsp_hs"
            "hsp_ag"
            "hfp_hf"
            "hfp_ag"
          ];
          "bluez5.codecs" = [
            "sbc"
            "sbc_xq"
            "aac"
            "aptx"
            "aptx_hd"
            "ldac"
          ];
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    playerctl
    calibre
    framework-tool
  ];

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
