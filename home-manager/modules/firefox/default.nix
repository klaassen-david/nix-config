{
  config,
  lib,
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
    # Fonts and reader mode come from stylix (home-manager/modules/theme); the
    # UI follows the stylix-themed GTK theme via Firefox's "System theme".
    profiles.default = {
      id = 0;
      path = "pfypjkxg.default-1689518983179";
      isDefault = true;
      # stylix derives this from the terminal size (16pt for ghostty -> 21px);
      # web code text keeps Firefox's default
      settings."font.size.monospace.x-western" = lib.mkForce 13;
    };
  };
}
