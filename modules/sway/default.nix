{ pkgs, lib, ... } :

{
  wayland.windowManager.sway = {
    enable = true;
    config = {
      terminal = "ghostty";
      modifier = "Mod1";
      input = {
        "*" = { 
          xkb_variant = "dvorak";
          xkb_layout = "us";
        };
      };
    };
  };
}
