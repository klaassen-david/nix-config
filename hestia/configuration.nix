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
    extraGroups = [ "wheel" ];
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

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # nvidia
  hardware = {
    graphics.enable = true;
    nvidia.open = true;
  };
  services.xserver.videoDrivers = [ "nouveau" ];

  networking = {
    hostName = "hestia";
  };

  # dvorak
  console.useXkbConfig = true;
  services.xserver = {
    xkb.layout = "us";
    xkb.variant = "dvorak";
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
    kitty
    pavucontrol
    pamixer
    greetd.gtkgreet
  ];

  programs.dconf.enable = true;

  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "sway";
        # command = "${pkgs.greetd.gtkgreet}/bin/gtkgreet --command=\"dbus-run-session sway\"";
        user = "dk";
      };
      default_session = initial_session;
    };
  };
}
