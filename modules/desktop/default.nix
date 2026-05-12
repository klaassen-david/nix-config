{ pkgs, ... }:

{
  imports = [
    ../firefox
    ../zathura
    ../kdeconnect
    ../zen-browser
  ];

  home.packages = with pkgs; [
    # fonts
    nerd-fonts.fira-code
    corefonts
    freetype

    pulseaudio

    # gaming
    steamcmd
    steam-run
    adwaita-icon-theme
    # lutris
    wineWow64Packages.stable
    winetricks
    vulkan-tools
    mangohud
    heroic

    # password manager
    proton-pass
  ];

  fonts.fontconfig.enable = true;
}
