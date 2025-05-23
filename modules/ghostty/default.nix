{ pkgs, lib, ... } :

{
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    settings = {
      font-size = 16;
      # font-family = "Fira Code Nerd Font";
    };
  };
}
