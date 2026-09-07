# Decisions — index

Settled questions, kept so they stop being re-litigated. The ruling is in the
line; the linked file carries rationale, rejected alternatives, and a
*revisit-if* condition. One file per question, amended in place when a ruling
changes (old ruling stays in the file as history).

- [nextcloud-not-backed-up](decisions/nextcloud-not-backed-up.md) — only the
  stalwart mail store is backed up; Nextcloud data is covered by the desktop
  sync, residual server-side-only loss accepted [USER 2026-08-31]
- [nixpkgs-channel](decisions/nixpkgs-channel.md) — one channel
  (`nixpkgs-unstable`) for all three hosts; no stable pin for the vps
  [USER 2026-08-31]
- [password-manager](decisions/password-manager.md) — Vaultwarden on olympus;
  KeePassXC-over-Nextcloud and keeping Proton Pass rejected [USER 2026-08-31]
- [theming-stylix](decisions/theming-stylix.md) — adopt stylix, driven from
  `host.theme.*`; the scaffolding stays [USER 2026-08-31]
- [hestia-dns-mkforce](decisions/hestia-dns-mkforce.md) — the `mkForce` on
  `networkmanager.dns` is real (resolved.nix defines the option); keep it
  [AGENT 2026-09-07]
- [sway-checkconfig](decisions/sway-checkconfig.md) — `checkConfig = false`
  stays; the build sandbox has no DRM FD for `sway -C`'s renderer
  [AGENT 2026-09-07]
