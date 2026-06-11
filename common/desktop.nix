{
  config,
  pkgs,
  ...
}:

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

  services.udisks2.enable = true;
}
