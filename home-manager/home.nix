{
  pkgs,
  lib,
  inputs,
  host,
  ...
}:

{
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./modules/nvim
    ./modules/fish
    ./modules/ghostty
    ./modules/yazi
    ./modules/git
    ./modules/bash
    ./modules/claude
    # ~/.ssh/config: fleet hosts + the id_priv identity ssh will not find on its own
    ./modules/ssh
  ];

  # deliberately trails host.stateVersion (25.05): HM state predates the hosts'
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  home.username = "dk";
  home.homeDirectory = "/home/dk";
  home.keyboard.layout = lib.head (lib.splitString "," host.keyboard.layout);

  home.packages = with pkgs; [
    # rust implementations
    uutils-coreutils-noprefix

    # unpack
    unzip
    unrar
    p7zip
    _7zz

    # download
    wget
    curl

    # search
    ripgrep
    fd
    fzf

    btop
    gcc
  ];
}
