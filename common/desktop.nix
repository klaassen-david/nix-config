{ config, pkgs, ... }:

{
  imports = [ ./common.nix ];

  environment.systemPackages = with pkgs; [
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

  # droidcam
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.kernelModules = [
    "v4l2loopback"
    "uinput"
  ];

  networking = {
    enableIPv6 = true;
    firewall =
      let
        ranges = [
          {
            from = 6112;
            to = 6119;
          }
          {
            # testing
            from = 8000;
            to = 8100;
          }
          {
            # kdeconnect
            from = 1714;
            to = 1764;
          }
        ];
        ports = [
          2350 # wc3
          23756
          5180 # wireguard
        ];
      in
      {
        enable = true;
        checkReversePath = false;
        allowedTCPPorts = ports;
        allowedTCPPortRanges = ranges;
        allowedUDPPorts = ports;
        allowedUDPPortRanges = ranges;
      };
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
    jack.enable = true;
  };

  security.pam.services.swaylock.text = "auth include login";

  programs.kdeconnect.enable = true;

  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "bash -l -c 'dbus-run-session sway'";
        user = "dk";
      };
      default_session = initial_session;
    };
  };

  programs.dconf.enable = true;

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
        "--hdr-sdr-content-nits"
        "400"
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
        "--backend"
        "drm"
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
    capSysNice = false;
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

  # mouse control
  programs.ydotool = {
    enable = true;
    group = "input";
  };
}
