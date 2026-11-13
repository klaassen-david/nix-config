# browser: Waterfox with native tree tabs

**Ruling** [USER 2026-11-03]: Waterfox becomes the desktops' default browser (in place of Zen).
**Firefox stays** [USER 2026-11-03]: it remains installed and configured
(`home-manager/modules/firefox`); Waterfox becomes the default, not the only browser.
Required behaviour: no top bar; one sidebar holding url bar, extension
buttons and a tab tree (children indented, Sidebery-style level lines); no
hover reveals anywhere; Zen-style floating url bar (centred, suggestions open
immediately, Escape always closes, Ctrl+T creates the tab only on Enter).

**Private windows** [USER 2026-11-04]: every add-on runs in private windows,
also ones installed by hand.

**Sidebar controls** [USER 2026-11-04]: the first row starts with app menu,
extensions, back, forward, reload in that order; back/forward always shown,
also when disabled; Firefox View, the Waterfox blocker and all-tabs buttons
removed.

**Sidebar bottom row** [USER 2026-11-13]: no sidebar tools (synced tabs,
history, bookmarks); downloads then zoom (`- N% +`, the percentage resets to
100 %) at the right end, zoom rightmost. Top-row buttons keep their size but
lose the horizontal gap; less space between them and the url bar.
Downloads always ask where to save [USER 2026-11-13].
*Amended* [USER 2026-11-13]: no bottom row at all. Row 1: app menu, back,
forward, reload, downloads, zoom; row 2: extensions button, then the pinned
add-ons; then the url bar. Supersedes the row order under *Sidebar controls*.

**Pinned tabs** [USER 2026-11-13]: not resizable; the area always shows
every row of pinned tabs and ends right below them.

**Sidebar width** [USER 2026-11-13]: no visible splitter strip between
sidebar and page; an invisible handle on the sidebar's right edge still drags
the width. Rejected: the handle over the page, where web content takes the
clicks [AGENT 2026-11-13].

**Url bar buttons** [USER 2026-11-13]: no reader-view or bookmark-star button.

**Url bar in the sidebar** [USER 2026-11-04]: the address stays visible in the
sidebar while the floating url bar is open.

**Switch-to-tab across windows** [USER 2026-11-04]: out of scope. The other
window's tab is selected but its workspace is only marked urgent: sway's
`focus_on_window_activation smart` (home-manager's default) does not focus a
window that is not visible. Rejected: `focus` (applies to every app) and
focusing from Waterfox via `swaymsg`.

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
