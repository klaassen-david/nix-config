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
      chargeLimit = true;
      lid = true;
    };
    chargeLimitPercent = 60;

    # LID0/state is confirmed present on the Framework 16; the token is "open"/"closed".
    lid_state = pkgs.writeShellScript "lid-state" ''
      if ${pkgs.gnugrep}/bin/grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
        echo closed
      else
        echo open
      fi
    '';
  };

  # Bootloader
  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = config.host.keepGenerations;
    efi.canTouchEfiVariables = true;
  };

  boot.kernelModules = [ "ryzen_smu" ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware = {
    graphics.enable = true;
  };
  services.xserver.videoDrivers = [ "amdgpu" ];

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

  services.upower = {
    enable = true;
  };

  services.fwupd.enable = true;
  systemd.services.fp-led-brightness = {
    description = "Set fingerprint LED brightness";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.framework-tool}/bin/framework_tool --fp-brightness 1";
    };
  };

  services.resolved.enable = true;
}
