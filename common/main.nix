{ config, lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  programs.ccache.enable = true;
  nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];

  users.extraUsers.dk = {
    isNormalUser = true;
    initialPassword = "4TestPW";
    home = "/home/dk";
    extraGroups = [ "wheel" "networkmanager" "gamemode" "video" "render" "seat" ];
  };

  # droidcam
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.kernelModules = ["v4l2loopback" "uinput"];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  networking = {
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
  };

  # gb keyboard layout
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
}
