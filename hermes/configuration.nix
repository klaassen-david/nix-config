{ lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  powerManagement.enable = true;

  users.extraUsers.dk = {
    isNormalUser = true;
    initialPassword = "4TestPW";
    home = "/home/dk";
    extraGroups = [ "wheel" "networkmanager" "video" "wpa_supplicant" ];
  };

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

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

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

  # keyboard layout
  console.useXkbConfig = true;
  services.xserver = {
    xkb.layout = "gb";
    exportConfiguration = lib.mkOptionDefault true;
  };

  # audio
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    audio.enable = true;
    # wireplumber.enable = true;
    jack.enable = true;
  };
  # services.playerctld.enable = true;

  # bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = { General = {Experimental = true;}; };
  };
  services.blueman.enable = true;

  # sway auto login
  security.polkit.enable = true;
  security.pam.services.swaylock.text = "auth include login";

  environment.systemPackages = with pkgs; [
    git
    vim
    kitty
    pavucontrol
    pamixer
    gtkgreet
    steamcmd
    steam-run
    libreoffice-qt6
    thunderbird
    wpa_supplicant_gui
    playerctl
    calibre
    framework-tool
  ];

  programs.dconf.enable = true;

  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "sway";
        # command = "${pkgs.gtkgreet}/bin/gtkgreet --command=\"dbus-run-session sway\"";
        user = "dk";
      };
      default_session = initial_session;
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    wlr.enable = true;
    wlr.settings = {
      screencast = {
        output_name = "DP-2";
        chooser_type = "simple";
        chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
      };
    };
    config = {
      sway = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
      };
    };
  };

  programs.steam = {
    enable = true;
  };

  networking.firewall = rec {
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };
}
