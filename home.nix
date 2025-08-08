{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    inputs.zen-browser.homeModules.beta
    ./modules/nvim
    # ./modules/zellij
    ./modules/fish
    ./modules/ghostty
    ./modules/tmux
    ./modules/sway
    ./modules/firefox
    ./modules/zathura
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  home.username = "dk";
  home.homeDirectory = "/home/dk";
  # home.keyboard = {
  #   layout = "us";
  #   variant = "dvorak";
  # };

  home.packages = with pkgs; [
    vim

    # replace cat, ls, etc with rust implementations
    uutils-coreutils-noprefix

    # unpack
    unzip
    unrar

    # download
    wget
    curl

    # search
    ripgrep
    fd
    fzf

    btop # htop replacement

    # fonts
    nerd-fonts.fira-code
    corefonts

    gcc
     
    pulseaudio
  ];

  fonts.fontconfig.enable = true;

  programs.git.enable = true;

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
    initExtra = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };

  programs.zen-browser = {
    enable = true;
    policies = {
      DisableAppUpdate = true;
    };
  };
}
