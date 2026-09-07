# Picks the default browser from `host.browser`. Both browsers are installed
# either way — the choice only moves the xdg handler for links and the sway
# startup entry, so switching is a rebuild plus a relogin, not a migration.
#
# Exports `defaultBrowser` ({ command, desktopFile }) as a _module.args, the
# same convention as nginx's sslVhost: the sway module imports this one to read
# the startup command instead of re-deriving the mapping.
{ host, lib, ... }:

let
  browsers = {
    zen = {
      command = "zen-beta";
      desktopFile = "zen-beta.desktop";
    };
    firefox = {
      command = "firefox";
      desktopFile = "firefox.desktop";
    };
  };

  # every mime type and url scheme the default browser claims
  webTypes = [
    "text/html"
    "application/xhtml+xml"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/about"
    "x-scheme-handler/unknown"
  ];
in
{
  imports = [
    ../firefox
    ../zen-browser
  ];

  _module.args.defaultBrowser = browsers.${host.browser};

  xdg.mimeApps.defaultApplications = lib.genAttrs webTypes (_: browsers.${host.browser}.desktopFile);
}
