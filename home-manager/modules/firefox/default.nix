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

    # Declare the existing on-disk profile (Name=default, Path=i023pnk7.default)
    # so we can flip prefs on it declaratively. `path` must match the existing
    # dir or home-manager would spawn a *second* profile that shadows this one.
    # We deliberately don't set `userChrome` here — the stylesheet stays a
    # hand-edited file in the profile's chrome/ dir (see pref below).
    profiles.default = {
      id = 0;
      path = "i023pnk7.default";
      isDefault = true;
      settings = {
        # Required for Firefox to load chrome/userChrome.css (+ userContent.css).
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
    };
  };
}
