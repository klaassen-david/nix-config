{ pkgs, ... }:

{
  imports = [
    ../sway
    ../firefox
    ../zathura
    ../kdeconnect
    ../zen-browser
    ../nextcloud-sync
    ../calendar
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

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # mail
      "x-scheme-handler/mailto" = "thunderbird.desktop";
      "message/rfc822" = "thunderbird.desktop";

      # LibreOffice Writer (doc/docx/odt)
      "application/msword" = "writer.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
      "application/vnd.oasis.opendocument.text" = "writer.desktop";

      # LibreOffice Calc (xls/xlsx/ods/csv)
      "application/vnd.ms-excel" = "calc.desktop";
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "calc.desktop";
      "application/vnd.oasis.opendocument.spreadsheet" = "calc.desktop";
      "text/csv" = "calc.desktop";

      # LibreOffice Impress (ppt/pptx/odp)
      "application/vnd.ms-powerpoint" = "impress.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" = "impress.desktop";
      "application/vnd.oasis.opendocument.presentation" = "impress.desktop";
    };
  };

  # Home Manager
  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "auto"; # FIXME does not show
  };
}
