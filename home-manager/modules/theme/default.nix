# Stylix targets for the desktop bundle. autoEnable is off
# (common/modules/theme, decisions/theming-stylix.md), so this list is the
# whole set stylix styles in home-manager; programs without a target read
# config.lib.stylix.colors themselves (sway bar in ../sway/kanshi.nix,
# i3status blocks, swayosd in ../sway, Waterfox in ../waterfox).
#
# No browser target: stylix's firefox target pins web-view font sizes (never in
# a web view: decisions/theming-stylix.md). Firefox sets families and reader
# colours itself (../firefox), its UI follows GTK; Waterfox has its theme
# add-on; Zen is not themed.
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
      });
}
