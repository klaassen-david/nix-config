# Stylix targets for the desktop bundle. autoEnable is off
# (common/modules/theme, decisions/theming-stylix.md), so this list is the
# whole set stylix styles in home-manager; programs without a target read
# config.lib.stylix.colors themselves (sway bar in ../sway/kanshi.nix,
# i3status blocks, swayosd in ../sway, Waterfox in ../waterfox).
#
# Firefox: fonts and reader mode only; its UI follows the GTK theme. Zen: not
# themed.
{ lib, ... }:

{
  stylix.targets =
    lib.genAttrs
      [
        # desktop
        "sway"
        "swaync"
        "tofi"
        "gtk"
        "qt"
        "fontconfig"
        "font-packages"
        # terminal and tools
        "ghostty"
        "nixvim"
        "fish"
        "starship"
        "fzf"
        "tmux"
        "zellij"
        "yazi"
        "zathura"
        "mpv"
      ]
      (_: {
        enable = true;
      })
    // {
      firefox = {
        enable = true;
        profileNames = [ "default" ];
      };
    };
}
