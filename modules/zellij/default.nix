{ pkgs, lib, ... } :

{
  programs.zellij = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      theme = "nord";
      keybinds = {
        shared = {
          bind = {
            _args = ["Ctrl a"];
            Run = {
              _args = ["cat" "~/.config/zellij/config.kdl"];
              direction = "Down";
            };
          };
          # bind "Ctrl Shift Tab" { MoveFocusOrTab "Left"; }
        };
      };
    };
  };
}
