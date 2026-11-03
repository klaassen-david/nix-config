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
- nixvim's own `colorschemes.nord` gives way to stylix's base16 rendering.
- olympus gets the text-console colours too; nothing else there.
- Firefox: stylix's target for fonts and reader mode only; the UI follows
  the stylix GTK theme via Firefox's "System theme" (no NUR Firefox Color,
  no GNOME theme). The old userChrome pref went: no userChrome.css existed.

**Rejected**: deleting the currently-dead `host.theme` scaffolding.

**Revisit if**: stylix cannot drive one of the target apps (sway, ghostty,
nvim, zathura, gtk) without fighting it.
