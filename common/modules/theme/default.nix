# Stylix, driven by the host struct (decisions/theming-stylix.md).
#
# `host.theme.base16` names a base16-schemes scheme ("nord", "gruvbox-dark-hard",
# … — `ls $(nix build --no-link --print-out-paths nixpkgs#base16-schemes)/share/themes`);
# changing it re-themes everything below. No consumer hardcodes a palette:
# targets stylix ships are opted in (autoEnable = false) here (console, every
# host) and in home-manager/modules/theme (the desktop bundle); everything
# without a target reads `config.lib.stylix.colors` (sway bar, i3status blocks,
# swayosd, Waterfox's theme add-on).
#
# The NixOS module also imports stylix's home-manager module for every HM user
# and forwards these settings to it (homeManagerIntegration.followSystem).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.host) theme;
  desktop = config.host.role != "vps";
in
{
  stylix = {
    enable = true;
    autoEnable = false;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/${theme.base16}.yaml";
    polarity = "dark";

    # text console colours, every host (olympus included)
    targets.console.enable = true;

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      # ghostty's size before stylix
      sizes.terminal = 16;
    };

    cursor = lib.mkIf desktop {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    opacity.terminal = theme.opacity;
  };
}
