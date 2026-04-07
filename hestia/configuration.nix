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
    extraGroups = [ "wheel" "networkmanager" "gamemode" "video" "render" "seat" ];
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
  boot.kernelModules = ["v4l2loopback" "uinput"];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

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
    enableIPv6 = true;
    firewall = {
      enable = true;
      checkReversePath = false;
      allowedTCPPorts = [ 3450 5000 23756 ];
      allowedTCPPortRanges = [ 
        { from = 6112; to = 6119; }
        { from = 1714; to = 1764; } # kdeconnect
      ];
      allowedUDPPorts = [ 
        2350 # wc3
        23756 
        5180 # wireguard
      ];
      allowedUDPPortRanges = [ 
        { from = 6112; to = 6119; }
        { from = 1714; to = 1764; } # kdeconnect
      ];
    };

    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    useDHCP = false;
    dhcpcd.enable = false;
    networkmanager = {
      enable = true;
      dns = lib.mkForce "none";
    };
  };
  services.resolved.enable = true;

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

  programs.kdeconnect.enable = true;
  users.users.dk.extraGroups = ["input" "uinput"];

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
  programs.gamemode.enable = true;
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

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

  programs.ccache.enable = true;
  nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];
}
