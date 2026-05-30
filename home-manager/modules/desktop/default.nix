{ pkgs, ... }:

{
  imports = [
    ../sway
    ../firefox
    ../zathura
    ../kdeconnect
    ../zen-browser
    ../nextcloud-sync
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

  # Home Manager
  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "auto"; # FIXME does not show
  };
}
