{ pkgs, lib, ... } : 
{
  programs.tmux = {
    enable = true;
    extraConfig = ''
      bind C-T next-window
      bind C-S-T previous-window
    '';
  };
}
