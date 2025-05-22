{ pkgs, lib, ... } :

{
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
  };
}
