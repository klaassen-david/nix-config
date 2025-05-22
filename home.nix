{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    ./modules/nvim
    # ./modules/zellij
    ./modules/ghostty
    ./modules/tmux
    ./modules/sway
    ./modules/firefox
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  home.username = "dk";
  home.homeDirectory = "/home/dk";
  home.keyboard = {
    layout = "us";
    variant = "dvorak";
  };

  home.packages = with pkgs; [
    vim

    # unpack
    unzip
    unrar

    # download
    wget
    curl

    # search
    ripgrep
    fzf

    btop # htop replacement
    
    thunderbird
  ];

  programs.git = {
    enable = true;
    userName = "David Klaaßen";
    userEmail = "david.klaassen@web.de";
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = "";
    shellAliases = {
      ns = "nix-shell";
      nd = "nix develop";
      l = "ls -l";
      ll = "ls -lA";
      la = "ls -la";
      nvims = "nvim -S";
    };
  };
}
