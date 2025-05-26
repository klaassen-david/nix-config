{ pkgs, lib, ... } :

{
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    settings = {
      font-size = 16;
      # font-family = "Fira Code Nerd Font";
      background-opacity = 0.8;
      gtk-tabs-location = "hidden";
      keybind = [
        "ctrl+e=write_scrollback_file:open"
      ];
    };
  };
}
