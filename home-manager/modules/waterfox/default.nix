# Waterfox: native tree tabs, no top bar (decisions/browser.md).
#
# Pieces:
#   package.nix    unwrapped tarball (not in nixpkgs), wrapped below with wrapFirefox
#   window.cfg     privileged autoconfig script, appended to the wrapper's mozilla.cfg
#                  (layout, floating url bar, Ctrl+T, keys, unloading) — it patches
#                  browser internals: re-check it on every Waterfox bump
#   userChrome.css compact tree, level lines, floating url bar
#   theme.nix      theme add-on generated from the stylix base16 palette
#
# programs.waterfox comes from home-manager's own mkFirefoxModule (the same
# builder behind programs.firefox/floorp/librewolf), so policies, profiles,
# settings and userChrome work as for Firefox. The profile lives in
# ~/.config/waterfox (XDG, like Firefox's): a non-default configPath also makes
# the wrapper export MOZ_APP_DATA, which Waterfox honours.
#
# Extension *list* is declarative but additive: dropping an id here does not
# uninstall it — retire one with `installation_mode = "blocked"`. Extension data
# (filter lists, userscripts) is not managed.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  mkFirefoxModule = import "${inputs.home-manager}/modules/programs/firefox/mkFirefoxModule.nix";

  waterfox = pkgs.wrapFirefox (pkgs.callPackage ./package.nix { }) {
    # window.cfg needs Services/ChromeUtils, i.e. an unsandboxed autoconfig;
    # wrapFirefox writes only filename + obscure_value itself
    extraAutoConfig = ''pref("general.config.sandbox_enabled", false);'';
    # interpolated: the wrapper `cat`s these in its builder, so they must be
    # store paths with context, not bare flake-source paths
    extraPrefsFiles = [ "${./window.cfg}" ];
  };

  # UI colours from the stylix palette (common/modules/theme)
  palette = lib.genAttrs (map (i: "base0${lib.toHexString i}") (lib.range 0 15)) (
    n: config.lib.stylix.colors.withHashtag.${n}
  );
  theme = pkgs.callPackage ./theme.nix {
    inherit palette;
    polarity = if config.stylix.polarity == "light" then "light" else "dark";
  };

  # AMO "latest" by add-on id; normal_installed = installed once, updates itself
  amo = id: {
    installation_mode = "normal_installed";
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${lib.escapeURL id}/latest.xpi";
  };
  engine = Name: Alias: URLTemplate: IconURL: {
    inherit
      Name
      Alias
      URLTemplate
      IconURL
      ;
  };
in
{
  imports = [
    (mkFirefoxModule {
      modulePath = [
        "programs"
        "waterfox"
      ];
      name = "Waterfox";
      wrappedPackageName = "waterfox";
      unwrappedPackageName = "waterfox-bin-unwrapped";
      platforms.linux.configPath = ".waterfox";
      # never used (x86_64-linux only), but the builder evaluates it for its
      # option defaults (darwinDefaultsId) — `nix flake check` fails without it
      platforms.darwin = {
        appName = "Waterfox";
        configPath = "Library/Application Support/Waterfox";
      };
    })
  ];

  programs.waterfox = {
    enable = true;
    package = waterfox;
    configPath = "${config.xdg.configHome}/waterfox";
    globalExtensions = [ theme ];

    policies = {
      DisableAppUpdate = true;
      # system add-ons would update from aus.waterfox.com
      DisableSystemAddonUpdate = true;
      # Waterfox ships DoH through its own relay to Cloudflare, bypassing
      # systemd-resolved (internal names, tukl, the home LAN)
      DNSOverHTTPS = {
        Enabled = false;
        Locked = true;
      };
      ExtensionSettings = lib.genAttrs [
        "uBlock0@raymondhill.net"
        "addon@darkreader.org" # page content only; the UI is themed by `theme`
        "78272b6fa58f4a1abaac99321d503a20@proton.me" # until Vaultwarden (decisions/password-manager.md)
        "firefox@tampermonkey.net"
        "sponsorBlocker@ajay.app"
        "gdpr@cavi.au.dk" # Consent-O-Matic
        "{7be2ba16-0f1e-4d93-9ebc-5164397477a9}" # Video Speed Controller
        "{88ebde3a-4581-4c6b-8019-2a05a9e3e938}" # Hide YouTube Shorts
      ] amo;
      # Tab in the url bar cycles through exactly these (window.cfg)
      SearchEngines = {
        Default = "Startpage";
        Remove = [
          "Bing"
          "DuckDuckGo"
          "Ecosia"
          "Mojeek"
          "Qwant"
          "Waterfox Private Search"
        ];
        Add = [
          (engine "Startpage" "@sp" "https://www.startpage.com/sp/search?query={searchTerms}"
            "https://www.startpage.com/favicon.ico"
          )
          (engine "Claude" "@claude" "https://claude.ai/new?q={searchTerms}" "https://claude.ai/favicon.ico")
          (engine "Wikipedia (en)" "@w" "https://en.wikipedia.org/w/index.php?search={searchTerms}"
            "https://en.wikipedia.org/favicon.ico"
          )
          (engine "Wikipedia (de)" "@wde" "https://de.wikipedia.org/w/index.php?search={searchTerms}"
            "https://de.wikipedia.org/favicon.ico"
          )
          (engine "NixOS packages" "@np"
            "https://search.nixos.org/packages?channel=unstable&query={searchTerms}"
            "https://search.nixos.org/favicon.png"
          )
          (engine "NixOS options" "@no" "https://search.nixos.org/options?channel=unstable&query={searchTerms}"
            "https://search.nixos.org/favicon.png"
          )
          (engine "Home Manager options" "@hm"
            "https://home-manager-options.extranix.com/?release=master&query={searchTerms}"
            "https://home-manager-options.extranix.com/favicon.ico"
          )
          (engine "YouTube" "@yt" "https://www.youtube.com/results?search_query={searchTerms}"
            "https://www.youtube.com/favicon.ico"
          )
          (engine "GitHub" "@gh" "https://github.com/search?q={searchTerms}" "https://github.com/favicon.ico")
          (engine "noogle" "@nix" "https://noogle.dev/q?term={searchTerms}" "https://noogle.dev/favicon.ico")
        ];
      };
    };

    profiles.default = {
      id = 0;
      isDefault = true;
      userChrome = builtins.readFile ./userChrome.css;
      settings = {
        # layout: native vertical tabs + tree, one always-visible sidebar
        "sidebar.revamp" = true;
        "sidebar.verticalTabs" = true;
        "sidebar.visibility" = "always-show";
        "sidebar.autoHide" = false;
        "browser.tabs.verticalTabs.tree.enabled" = true;
        "browser.tabs.verticalTabs.tree.indentPx" = 10;
        "browser.tabs.pinnedIconOnly" = true; # labels would clip in the 28px icon grid
        "browser.tabs.verticalTabs.tree.autoCollapse.onSelect" = false; # off for now
        # an expanded parent's close promotes its first child; a collapsed
        # parent always takes its whole branch
        "browser.tabs.verticalTabs.tree.closeParentBehavior" = 0;
        # Firefox's own fullscreen autohide would slide the moved toolbox and
        # reveal it on hover; window.cfg hides the sidebar instead
        "browser.fullscreen.autohide" = false;
        "extensions.activeThemeID" = theme.addonId;

        # startup: restore the session (the tree lives in it), no nags
        "browser.startup.page" = 3;
        "browser.aboutwelcome.enabled" = false;
        "browser.startup.homepage_override.mstone" = "ignore";
        "startup.homepage_welcome_url" = "";
        "startup.homepage_welcome_url.additional" = "";
        "browser.startup.upgradeDialog.enabled" = false; # Waterfox flips it on
        "browser.shell.checkDefaultBrowser" = false;
        "browser.newtabpage.activity-stream.showWeather" = false;
        "browser.newtabpage.activity-stream.system.showWeather" = false;

        # background tabs unload under memory pressure (collapsed branches: window.cfg)
        "browser.tabs.unloadOnLowMemory" = true;

        # privacy / security (decisions/browser.md)
        "waterfox.blocker.enabled" = false; # uBlock Origin blocks; no conflict prompt
        "waterfox.search.suggestions.useProxy" = false; # not via search.waterfox.com
        "security.OCSP.enabled" = 1; # Waterfox ships 0
        "media.eme.enabled" = false; # no DRM
        # Safe Browsing cannot be enabled: the build has no Google API key
      };
    };
  };
}
