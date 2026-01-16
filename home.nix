{ config, pkgs, inputs, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      lutris = prev.lutris.override {
        extraLibraries = 
        pkgs: with pkgs; [
          libadwaita
          gtk4
        ];
      };
    })
  ]
  ;

  imports = [
    inputs.nixvim.homeModules.nixvim
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
    p7zip
    _7zz

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
    freetype

    gcc
     
    pulseaudio

    # gaming
    steamcmd
    steam-run
    adwaita-icon-theme
    lutris
    wineWowPackages.stable
    winetricks
    vulkan-tools
    mangohud
    nexusmods-app
    heroic
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
      # if [[ -z ''${BASH_EXECUTION_STRING} ]]
      # then
      #   shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      #   exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      # fi
    '';
  };

  # programs.zen-browser = {
  #   enable = true;
  #   policies = {
  #     DisableAppUpdate = true;
  #   };
  # };

}
