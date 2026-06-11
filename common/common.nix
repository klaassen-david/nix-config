{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./host.nix
    # self-selects server (vps) vs on-demand client by host.role
    ./modules/wireguard
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
      "https://klaassen-david.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "klaassen-david.cachix.org-1:JSXHnsFehuyyhJ+JZSRhJNlx1gCudEBCTMXLd4y1Tn8="
    ];
  };

  # hardlink identical store paths to reclaim disk (esp. olympus VPS).
  nix.settings.auto-optimise-store = true;

  # nh: rebuild front-end (auto closure diff via nvd on `nh os switch`) plus its
  # own GC timer. nh.clean replaces nix.gc.automatic — running both is rejected.
  # keep host.keepGenerations generations and anything newer than 30 days.
  programs.nh = {
    enable = true;
    flake = "/home/dk/nix-config";
    clean = {
      enable = true;
      extraArgs = "--keep ${toString config.host.keepGenerations} --keep-since 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # decrypt agenix secrets with the shared user key (present on every host),
  # so a single recipient (id_priv) in secrets.nix covers all machines.
  age.identityPaths = [ "/home/dk/.ssh/id_priv" ];

  programs.ccache.enable = true;
  nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];

  users.extraUsers.dk = {
    isNormalUser = true;
    shell = pkgs.fish;
    initialHashedPassword = "$y$j9T$cnJaTuoqcS9wMqEV..0Ie0$/jU6CWhP4O4PUqKD.YprPkcbDVnfkc90XjarzlO6kh9";
    home = "/home/dk";
    openssh.authorizedKeys.keyFiles = [ ./keys/id_priv.pub ];
    extraGroups = [
      "wheel"
      "networkmanager"
      "gamemode"
      "video"
      "render"
      "seat"
    ];
  };

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # gb keyboard layout
  console.useXkbConfig = true;
  services.xserver = {
    xkb.layout = "gb";
    # xkb.variant = "dvorak";
  };

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  programs.fish.enable = true;

  security.polkit.enable = true;
}
