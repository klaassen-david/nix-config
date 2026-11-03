# browser-sync: syncing the browser between hermes and hestia

**Ruling** [USER 2026-11-03]: syncing open tabs between hosts is out of scope
for now. Nothing is built for it: no Firefox Sync tabs engine, no floccus tab
sync, no session mirroring.

Context (evaluation of a Waterfox setup, 2026-11-03): open tabs reach other
devices only as Firefox Sync's per-device "tabs from other devices" list, never
as a mirrored session or tab tree; floccus's tab sync is marked experimental
upstream (duplicates, empty-session overwrite). The rest of browser sync —
bookmarks, history, Mozilla's servers vs. `services.firefox-syncserver` on
olympus — is not decided here. Settings, policies and
`userChrome.css` are meant to be declarative in the flake, identical on both
hosts by construction, so they need no sync. The extension *list* is only
additive by policy (`normal_installed`/`force_installed` never uninstall; an
id dropped from nix stays where it was installed — retire it with
`"blocked"`), and extension *data* (filter lists, userscripts, per-site
settings) is not declarative at all [AGENT 2026-11-03, Policies.sys.mjs]. Passwords are covered by
[password-manager](password-manager.md).

**Revisit if** the user wants to continue on one host with the tabs left open
on the other.
