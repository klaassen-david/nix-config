{ pkgs, lib, ... }:

{
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    shellWrapperName = "y";
  };

  # yazi is a TUI, so the packaged yazi.desktop sets Terminal=true. GLib (used by
  # Zen/Firefox to launch mime handlers, e.g. "open containing folder") can't spawn
  # our terminal for Terminal=true entries, so opening a directory silently does
  # nothing. Shadow it (XDG_DATA_HOME wins) with an entry that runs yazi inside
  # ghostty and is marked non-terminal, so GIO just launches ghostty directly.
  xdg.desktopEntries.yazi = {
    name = "Yazi File Manager";
    genericName = "File Manager";
    comment = "Blazing fast terminal file manager written in Rust, based on async I/O";
    icon = "yazi";
    exec = "ghostty -e yazi %f";
    terminal = false;
    type = "Application";
    mimeType = [ "inode/directory" ];
    categories = [ "System" "FileManager" ];
  };

  xdg.mimeApps.defaultApplications."inode/directory" = "yazi.desktop";
}
