{
  config,
  lib,
  pkgs,
  ...
}:

# What every host has, mesh member or not: the host struct, theme, nix settings,
# user dk. The fleet-only and hardware-only modules are in common.nix; a host
# outside the mesh imports this file alone (decisions/implementer-host.md).
{
  imports = [
    ./host.nix
    # stylix from host.theme (console on every host; desktop targets in HM)
    ./modules/theme
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

  # Cap core dumps. A GPU fault aborts every GL client at once, and on hestia
  # 2026-09-07 systemd-coredump met that storm by writing 17 GB and holding 8.8 GB
  # RSS while the box was already failing. Fleet-wide because an uncapped dump is
  # a disk hazard on the vps for the same reason. Dumps stay enabled: the java
  # backtrace is what identified that fault.
  systemd.coredump.settings.Coredump = {
    ProcessSizeMax = "2G";
    ExternalSizeMax = "2G";
    MaxUse = "2G";
  };

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
      "wootility"
    ];

  # only groups that exist on every host; the ones a service creates are added
  # where that service is enabled (networkmanager/gamemode in desktop.nix, seat
  # with seatd on hestia, bluetooth on hermes)
  users.users.dk = {
    isNormalUser = true;
    shell = pkgs.fish;
    # bootstrap only: applied when the user is first created, then replaced on
    # every host with `passwd` (each host has its own). Public in git, which is
    # fine for a hash no live host uses; see decisions/dk-password.md
    initialHashedPassword ="$y$j9T$cnJaTuoqcS9wMqEV..0Ie0$/jU6CWhP4O4PUqKD.YprPkcbDVnfkc90XjarzlO6kh9";
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
  # NixOS's default aliases would shadow home-manager's eza functions (decisions/ls-eza.md)
  programs.fish.shellAliases = {
    ls = null;
    l = null;
    ll = null;
  };

  security.polkit.enable = true;
}
