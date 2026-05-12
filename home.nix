{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./modules/nvim
    ./modules/fish
    ./modules/ghostty
    # ./modules/tmux
    ./modules/sway
    ./modules/yazi
    # ./modules/zellij
    ./modules/git
    ./modules/bash
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  home.username = "dk";
  home.homeDirectory = "/home/dk";
  home.keyboard.layout = "gb";

  home.packages = with pkgs; [
    vim

    # replace cat, ls, etc with rust implementations
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
