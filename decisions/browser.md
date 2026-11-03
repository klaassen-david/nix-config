# browser: Waterfox with native tree tabs

**Ruling** [USER 2026-11-03]: Waterfox becomes the desktops' default browser (in place of Zen).
**Firefox stays** [USER 2026-11-03]: it remains installed and configured
(`home-manager/modules/firefox`); Waterfox becomes the default, not the only browser.
Required behaviour: no top bar; one sidebar holding url bar, extension
buttons and a tab tree (children indented, Sidebery-style level lines); no
hover reveals anywhere; Zen-style floating url bar (centred, suggestions open
immediately, Escape always closes, Ctrl+T creates the tab only on Enter).

**Order** [USER 2026-11-03]: stylix is wired up and committed *before* the
switch; the browser's UI colours come from a theme add-on generated from the
stylix/base16 palette, not from hand-written userChrome colours or Dark Reader
(Dark Reader stays, for page content only).

**Waterfox defaults overridden** [USER 2026-11-03]: OCSP on; DNS-over-HTTPS
off by policy (Waterfox sends it through its own relay to Cloudflare and
would bypass systemd-resolved, breaking internal names); suggestions not
proxied through search.waterfox.com; no DRM. Safe Browsing was asked for but
cannot work: the build has no Google API key
(`%GOOGLE_SAFEBROWSING_API_KEY%` resolves to `no-google-safebrowsing-api-key`)
and Waterfox blanks the list URLs [AGENT 2026-11-03]. Search: Startpage
default; Claude, Google, YouTube, Wikipedia en/de, NixOS packages/options,
Home Manager, GitHub, noogle; the other built-ins removed by policy.

**Rejected**:
- Zen — hover pop-ups; no automatic tree (folders only); Sidebery inside it
  needs CSS to hide Zen's own tab list and inherits Sidebery's desync.
- Firefox + Sidebery/TST — tree state lives in the extension and drifts from
  the real tabs (Sidebery has no reconciliation pass; issues #147, #262, #2227);
  the url-bar-in-sidebar userChrome broke across releases.
- Writing a browser (qutebrowser tree tabs unmerged since 2024; Qt/GTK
  engines lack the extension support).

Waterfox 6.7 builds the tree into the vertical tab strip and persists it in
the session store. Costs: ESR base (security fixes after Mozilla's), small
team, not in nixpkgs (packaged here). The layout and url-bar behaviour come
from an autoconfig script that patches browser internals
(`gURLBar._whereToOpen`, `BrowserCommands.openTab`, `endLayoutExtend`, the
toolbox position) — the same release-to-release fragility that sank the
Firefox userChrome, smaller in scope; expect to re-check it on each Waterfox
update [AGENT 2026-11-03].

**Revisit if** Waterfox stalls on security releases, or Firefox ships native
tree tabs.
