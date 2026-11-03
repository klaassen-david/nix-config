{
  config,
  ...
}:

{
  programs.firefox = {
    enable = true;
    # Adopt the XDG path (home-manager's new default from stateVersion 26.05).
    # Our stateVersion predates that, so without this we'd stay on the legacy
    # ~/.mozilla/firefox and get the migration warning.
    configPath = "${config.xdg.configHome}/mozilla/firefox";

    # Declare the existing on-disk profile so we can flip prefs on it
    # declaratively. `path` MUST match the real profile directory under
    # configPath — home-manager writes profiles.ini as a read-only store
    # symlink, so a wrong path doesn't fall back to the old profile, it makes
    # Firefox start a brand-new empty one (and the old profiles.ini, the only
    # record of the right name, is gone — see profiles.ini.home-manager.bak).
    # Verify against `ls ~/.config/mozilla/firefox/` before changing this.
    # The UI follows the stylix-themed GTK theme via Firefox's "System theme".
    profiles.default = {
      id = 0;
      path = "pfypjkxg.default-1689518983179";
      isDefault = true;
      # Font families and reader-mode colours from stylix, set here rather than
      # via stylix's firefox target: that target also pins font *sizes*, and
      # web views keep the browser defaults (sizing is zoom's job, sites should
      # look the same everywhere).
      settings =
        let
          inherit (config.stylix) fonts;
          c = config.lib.stylix.colors.withHashtag;
        in
        {
          "font.name.monospace.x-western" = fonts.monospace.name;
          "font.name.sans-serif.x-western" = fonts.sansSerif.name;
          "font.name.serif.x-western" = fonts.serif.name;
          "reader.color_scheme" = "custom";
          "reader.custom_colors.background" = c.base00;
          "reader.custom_colors.foreground" = c.base05;
          "reader.custom_colors.selection-highlight" = c.base04;
          "reader.custom_colors.unvisited-links" = c.base0D;
          "reader.custom_colors.visited-links" = c.base0E;
        };
    };
  };
}
