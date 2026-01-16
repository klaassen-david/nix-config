{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  users.extraUsers.dk = {
    isNormalUser = true;
    initialPassword = "4TestPW";
    home = "/home/dk";
    extraGroups = [ "wheel" "gamemode" "video" ];
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
    efi.efiSysMountPoint = "/boot/efi";
  };

  # droidcam
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.kernelModules = ["v4l2loopback"];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # nvidia
  hardware = {
    graphics.enable = true;
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
    enableIPv6 = false;
    firewall = {
      enable = false;
      allowedTCPPorts = [ 3450 5000 23756 ];
      allowedTCPPortRanges = [ 
        { from = 6112; to = 6119; }
      ];
      allowedUDPPorts = [ 2350 23756 ];
      allowedUDPPortRanges = [ 
        { from = 6112; to = 6119; }
      ];
    };
  };

  # dvorak
  console.useXkbConfig = true;
  services.xserver = {
    xkb.layout = "gb";
    # xkb.variant = "dvorak";
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

  security.polkit.enable = true;

  security.pam.services.swaylock.text = "auth include login";

  environment.systemPackages = with pkgs; [
    git
    vim
    gparted
    kitty
    pavucontrol
    pamixer
    gtkgreet
    piper

    libreoffice
    thunderbird

    # droidcam
    droidcam
    v4l-utils
    android-tools

    (pkgs.buildFHSEnv {
      name = "winefhs";
      targetPkgs = pkgs: with pkgs; [
        wine
        protontricks
        freetype
        fontconfig
        zlib
        libpng
        vulkan-tools
        cabextract
      ];
      profile = ''
        export STEAM_DIR="$HOME/.steam/steam"
        export PROTON_DIR="$STEAM_DIR/compatibilitytools.d"
        export PATH="$STEAM_DIR:$PATH"
        export LD_LIBRARY_PATH="/usr/lib:$LD_LIBRARY_PATH"
      '';
    })

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

  programs.dconf.enable = true;

  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "sway";
        # command = "${pkgs.gtkgreet}/bin/gtkgreet --command=\"dbus-run-session sway\"";gtkgreet
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
    protontricks.enable = true;
    gamescopeSession.enable = true;
  };
  programs.gamemode.enable = true;

  # gaming mouse
  services.ratbagd.enable = true;

  # printing
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true; 
    openFirewall = true;

  };

  programs.fish.enable = true;
}
