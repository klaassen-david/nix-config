{
  pkgs,
  ...
}:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  programs.ccache.enable = true;
  nix.settings.extra-sandbox-paths = [ "/var/cache/ccache" ];

  users.extraUsers.dk = {
    isNormalUser = true;
    initialHashedPassword = "$y$j9T$cnJaTuoqcS9wMqEV..0Ie0$/jU6CWhP4O4PUqKD.YprPkcbDVnfkc90XjarzlO6kh9";
    home = "/home/dk";
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
