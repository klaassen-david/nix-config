{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./host.nix
    # self-selects server (vps) vs on-demand client by host.role
    ./modules/wireguard
    # self-gates on host.capabilities.wifi (+ lid-close keepalive on capabilities.lid)
    ./modules/wifi
    # self-gates on host.capabilities.samba
    ./modules/samba
    # consumer side of the self-hosted attic binary cache (substituter + pull
    # auth on every host, push on binaryCachePush hosts)
    ./modules/attic-cache
    # self-gates on host.debug.crashCapture: panic-on-hang + pstore + watchdog
    ./modules/crash-capture
    # self-gates on host.capabilities.onDemandSshServer: sshd configured but never
    # started at boot (desktops); headless.nix runs its own permanent sshd
    ./modules/ssh-on-demand
    # password-less systemctl start/stop for the units modules register in
    # host.userManagedUnits (wg-quick clients, on-demand sshd)
    ./modules/polkit-units
    # fprintd, driven by host.capabilities.fingerprint
    ./modules/fingerprint
    # self-gates on host.capabilities.chargeLimit: unprivileged battery charge limit
    ./modules/charge-limit
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings = {
    extra-substituters = [
      "https://nix-gaming.cachix.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
  };

  # hardlink identical store paths to reclaim disk (esp. olympus VPS).
  nix.settings.auto-optimise-store = true;

  services.fstrim.enable = true;
  zramSwap.enable = true;

  # unfree is opt-in per package: a new unfree dependency fails the eval
  # loudly instead of slipping in silently
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "nvidia-kernel-modules"
      "nvidia-settings"
      "steam"
      "steam-unwrapped"
      "steamcmd"
      "unrar"
      "claude-code"
      "corefonts"
    ];

  # decrypt agenix secrets with the shared user key (present on every host),
  # so a single recipient (id_priv) in secrets.nix covers all machines.
  age.identityPaths = [ "/home/dk/.ssh/id_priv" ];

  # only groups that exist on every host; the ones a service creates are added
  # where that service is enabled (networkmanager/gamemode in desktop.nix, seat
  # with seatd on hestia, bluetooth on hermes)
  users.users.dk = {
    isNormalUser = true;
    shell = pkgs.fish;
    initialHashedPassword = "$y$j9T$cnJaTuoqcS9wMqEV..0Ie0$/jU6CWhP4O4PUqKD.YprPkcbDVnfkc90XjarzlO6kh9";
    home = "/home/dk";
    openssh.authorizedKeys.keyFiles = [ ./keys/id_priv.pub ];
    extraGroups = [
      "wheel"
      "video"
      "render"
    ];
  };

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # console/XWayland fallback: first entry of host.keyboard (sway gets the full list)
  console.useXkbConfig = true;
  services.xserver = {
    xkb.layout = lib.head (lib.splitString "," config.host.keyboard.layout);
  };

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  programs.fish.enable = true;

  security.polkit.enable = true;
}
