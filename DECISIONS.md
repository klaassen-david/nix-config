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
- [hestia-gpu-lockups](decisions/hestia-gpu-lockups.md) — the hard freezes are
  Xid 79 (GPU off the PCIe bus), not a game or config fault; transient power
  delivery is the leading cause, under test via a 280 W cap [AGENT 2026-09-08]
- [dk-password](decisions/dk-password.md) — per-host passwords set with
  `passwd`; `initialHashedPassword` stays as the bootstrap value, agenix
  `hashedPasswordFile` rejected (would unify the fleet) [USER 2026-09-08]
- [nextcloud-sync-excludes](decisions/nextcloud-sync-excludes.md) — `excludeFile`
  drops `target`/`.lake`/`.claude`; artifacts filled olympus's disk, and the
  excludes must land *after* the server-side cleanup, never before
  [USER 2026-09-10]
- [hermes-cpu-clock-lock](decisions/hermes-cpu-clock-lock.md) — the 544 MHz
  lock-until-reboot is Framework's open BIOS 4.05 bug, tripped by a failing
  charger PD negotiation; cpufreq is wide open, so no repo change can fix it
  [AGENT 2026-09-10]
- [nvim-markdown-stack](decisions/nvim-markdown-stack.md) — render-markdown +
  nabla + image.nvim + mkdnflow + otter; bullets.vim rejected (subsumed by
  mkdnflow, and its `<CR>` map shadows cmp's confirm) [USER 2026-09-12]
- [render-markdown-fork](decisions/render-markdown-fork.md) — render-markdown is
  built from the `wrapped-cells` branch of the personal fork for
  `pipe_table.cell = "wrapped"`; nixpkgs' copy has no wrapped tables
  [USER 2026-09-12]
- [cswap-auto-policy](decisions/cswap-auto-policy.md) — never a disabled
  profile; slot 1 (rptu) drained first; leave at 95 % (rptu) / 98 % (others) on
  any limit; the two Max accounts sit on the soonest-resetting week and drain it
  before it resets [USER 2026-09-21]
- [pimsync-failure-alert](decisions/pimsync-failure-alert.md) — `pimsync-sync`
  conflicts (exit 3) raise a critical desktop notification; other failures
  stay in the journal [USER 2026-09-29]
- [wallpaper-per-host](decisions/wallpaper-per-host.md) — mpvpaper plays
  `host.theme.wallpaper`; null starts no mpvpaper (hermes) [USER 2026-09-30]
- [power-log-scope](decisions/power-log-scope.md) — the power logger runs on
  hermes only [USER 2026-09-30]
- [hibernate-swapfile](decisions/hibernate-swapfile.md) — hermes hibernates
  into a 32 GiB swapfile on `/`, by hand only (`systemctl hibernate`, plus
  upower's HybridSleep at 2 %): lid close plain-suspends, never while an
  external display is connected; only the power button resumes; no frozen
  screen while the image is written [USER 2026-09-30, amended 2026-10-03]
- [vpn](decisions/vpn.md) — egress per device: hosts toggle direct / olympus
  / another host (relayed via olympus) / tukl (direct, own RPTU config) at
  runtime over an always-on split mesh; phones stay on wg-easy, egress and host
  reachability set per phone on olympus; home-LAN access is a separate
  per-device switch, no remapping; a dead exit drops traffic
  [USER 2026-09-30]
- [wifi-backend](decisions/wifi-backend.md) — hermes drives NetworkManager with
  wpa_supplicant, not iwd: iwd deauthenticates past its hard-coded 1200 TU
  association comeback and the MFP-requiring Bbox asks 1953; the MT7922 also
  gets `disable_aspm=1` [USER 2026-10-04]
- [orchestrator-worker](decisions/orchestrator-worker.md) — hermes runs the
  orchestrator's worker and agentd (`home-manager/modules/orch`) with
  lingering on; input is `git+file` pinned to a deployable rev [USER 2026-10-05];
  hestia runs the worker only, data on `/mnt/games/orch`, ceiling 27 GiB
  [AGENT 2026-10-06]; agentd runs on the development host `orchDevHost`
  (hestia; flipping it is the hand-over), its data at `~/.local/share/orch` on
  either host [USER 2026-10-09]; agents' and tasks' sandboxes block the VPN's
  networks on every worker host, and the development host's dashboard answers on
  its mesh address without a login [USER 2026-10-09]
- [remote-builder](decisions/remote-builder.md) — hermes builds on hestia over
  the mesh (ssh-ng as dk, host key pinned, local fallback), VM tests included
  [USER 2026-10-05]
  ; on over Wi-Fi too, since local builds have no global limit (max-jobs is per
  client) [USER 2026-10-07]; on hermes nix-daemon and orch.slice together stay 5 GiB under
  its RAM, with little swap and a systemd-oomd net, so builds can't freeze it
- [orchestrator-fleet](decisions/orchestrator-fleet.md) — the orchestrator's
  coordinator runs on olympus behind `orch.dklaassen.de` (SSO, VPN only; the
  hosts reach it through the mesh), one link token per worker host; hestia
  accepts hermes's tasks always, hermes in windows, trees fetched over ssh with
  a per-host key forced to `orch git-endpoint` [AGENT 2026-10-06]
