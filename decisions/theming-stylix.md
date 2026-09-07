# Theming: adopt stylix

**Ruling** [USER 2026-08-31]: `host.theme.*` stays and gets wired up via
stylix rather than deleted — colorscheme/fonts/wallpaper single-sourced from
the struct, so per-host colour/opacity stays a host-struct fact rather than a
per-module literal.

**Rejected**: deleting the currently-dead `host.theme` scaffolding.

**Revisit if**: stylix cannot drive one of the target apps (sway, ghostty,
nvim, zathura, gtk) without fighting it.
