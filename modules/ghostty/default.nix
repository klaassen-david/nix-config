{ pkgs, lib, ... } :

{
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      font-size = 13;
      # font-family = "Fira Code Nerd Font";
    };
  };
}
