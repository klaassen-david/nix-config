{ pkgs, lib, ... } :

{
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    shellWrapperName = "y";
  };
}
