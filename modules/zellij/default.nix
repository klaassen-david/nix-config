{ pkgs, lib, ... } :

{
  programs.zellij = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    settings = {
      theme = "nord";
      pane_frames = false;
      default_layout = "compact";
      keybinds = {
        shared = {
          bind = {
            _args = ["Ctrl a"];
            Run = {
              _args = ["cat" "~/.config/zellij/config.kdl"];
              direction = "Down";
            };
          };
        };
      };
    };
  };
}
