{ pkgs, lib, ... }:

{
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    settings = {
      font-size = 16;
      background-opacity = 0.8;
      gtk-tabs-location = "hidden";
      keybind = [
        "ctrl+shift+w=unbind"
      ];
    };
  };
}
