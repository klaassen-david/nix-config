# Stylix targets for the desktop bundle. autoEnable is off
# (common/modules/theme, decisions/theming-stylix.md), so this list is the
# whole set stylix styles in home-manager, nixvim aside (../nvim, per theme);
# programs without a target read config.lib.stylix.colors themselves (sway bar
# in ../sway/kanshi.nix, i3status blocks, swayosd in ../sway, Waterfox in
# ../waterfox).
#
# No browser target: stylix's firefox target pins web-view font sizes (never in
# a web view: decisions/theming-stylix.md). Firefox sets families and reader
# colours itself (../firefox), its UI follows GTK; Waterfox has its theme
# add-on; Zen is not themed.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # the icon theme from before stylix (it set none, so GTK fell back to Adwaita)
  stylix.icons = {
    enable = true;
    package = pkgs.kdePackages.breeze-icons;
    dark = "breeze-dark";
    light = "breeze";
  };

  # GTK4/libadwaita and the Mozilla apps take light/dark from this portal
  # setting, not from the GTK theme; stylix leaves it unset.
  dconf.settings."org/gnome/desktop/interface".color-scheme =
    if config.stylix.polarity == "light" then "default" else "prefer-dark";

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
