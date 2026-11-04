# Theming: adopt stylix

**Ruling** [USER 2026-08-31]: `host.theme.*` stays and gets wired up via
stylix rather than deleted — colorscheme/fonts/wallpaper single-sourced from
the struct, so per-host colour/opacity stays a host-struct fact rather than a
per-module literal.

**Shape** [USER 2026-11-03]:
- Targets are opted in explicitly (`stylix.autoEnable = false`), so nothing
  restyles unannounced; stylix should cover most/all of the desktop, the rest
  (sway bar colours, i3status blocks, swayosd, Waterfox) reads
  `config.lib.stylix.colors`.
- Scheme: Nord, but switching is one line (`host.theme.base16`, a
  base16-schemes name) — no consumer hardcodes a palette.
- Fonts: Noto Sans / Noto Serif, FiraCode Nerd Font for code. Cursor set by
  stylix (Adwaita 24).
- Sizes stay hand-tuned [USER 2026-11-03]: GTK/apps 12 (zathura too),
  terminal 17 (ghostty's old 16 in JetBrains Mono), tofi 24; icons stay
  Breeze (dark). Font *families* always follow stylix — only sizes are pinned.
  zathura otherwise follows stylix entirely (colours, opacity).
- ~~nixvim's own `colorschemes.nord` gives way to stylix's base16 rendering.~~
  Amended [USER 2026-11-04]: stylix's rendering made nvim mostly red under
  Nord, and the plugin reads better. `nvimThemes` in `common/host.nix` maps each
  scheme to a nixvim colorscheme or `mini.base16`; `host.theme.base16` only
  accepts its keys, so a scheme without a mapping fails at eval. Nord uses the
  plugin, and it is the only entry. A plugin brings its own colours (Nord's
  comments are `616e88`, not in the stylix palette), so nvim is the one
  exception to "no consumer hardcodes a palette".
- olympus gets the text-console colours too; nothing else there, except that
  nvim follows the same mapping on every host [USER 2026-11-04].
- Firefox: font families and reader-mode colours from the stylix values. Its
  UI is only dark (the portal `color-scheme`, derived from stylix's polarity),
  not palette-coloured: Firefox enforces add-on signing, so it cannot take the
  generated theme add-on (no NUR Firefox Color, no GNOME theme). The old
  userChrome pref went: no userChrome.css existed.
- Thunderbird and Waterfox get the same generated theme add-on
  (`common/modules/theme/mozilla-theme.nix`); both install unsigned add-ons.
- Web views [USER 2026-11-03]: stylix never sets font *sizes* inside a web
  view, in any browser — sizing is zoom's job and sites should look the same
  everywhere. Hence no stylix firefox target (it pins font.size.*).

**Rejected**: deleting the currently-dead `host.theme` scaffolding.

**Revisit if**: stylix cannot drive one of the target apps (sway, ghostty,
nvim, zathura, gtk) without fighting it.
