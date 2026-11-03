{
  pkgs,
  lib,
  colors, # config.lib.stylix.colors.withHashtag
}:

# Shared vocabulary for ./blocks/*: the pango wrapper every icon goes through,
# the on/off colours, and the unit viewer the service blocks middle-click into.
# ./default.nix splats this into every block's arguments, so a block file names
# only what it uses (`{ wrapIcon, ... }:`).

rec {
  defaultIconSize = 1024 * 11;

  # swaybar renders every block as pango markup (i3status-rs sets
  # "markup":"pango" on each one unconditionally), so span attributes buy more
  # than the size bump: `foreground` overrides the theme's state colour for this
  # run of text, and `strikethrough` draws a line through the glyph. Both are
  # honoured by the bar's font.
  styledIcon =
    {
      color ? null,
      strike ? false,
    }:
    icon:
    "<span size='${toString defaultIconSize}'"
    + lib.optionalString (color != null) " foreground='${color}'"
    + lib.optionalString strike " strikethrough='true'"
    + ">${icon}</span>";

  wrapIcon = styledIcon { };

  # on/off colours for the service blocks, from the stylix palette: the accent
  # for on, the bar's statusline colour (../kanshi.nix) for off
  colorOn = colors.base0D;
  colorOff = colors.base05;

  # Middle-click target for the service blocks: a live, read-only
  # `systemctl status <unit>` in neovim. See ../unit-status-view.nix.
  unitStatusView = pkgs.callPackage ../unit-status-view.nix { };
}
