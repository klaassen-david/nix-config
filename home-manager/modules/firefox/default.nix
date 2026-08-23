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
    # We deliberately don't set `userChrome` here — the stylesheet stays a
    # hand-edited file in the profile's chrome/ dir (see pref below).
    profiles.default = {
      id = 0;
      path = "pfypjkxg.default-1689518983179";
      isDefault = true;
      settings = {
        # Required for Firefox to load chrome/userChrome.css (+ userContent.css).
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
    };
  };
}
