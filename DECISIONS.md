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
- [browser](decisions/browser.md) — Waterfox (native tree tabs) becomes the
  default over Zen; Firefox stays installed; stylix lands first and themes it
  via a generated theme add-on [USER 2026-11-03]; add-ons run in private
  windows; address shown while the url bar floats; switch-to-tab does not
  focus another window's workspace (out of scope) [USER 2026-11-04]; sidebar
  rows = menu, back, forward, reload, downloads, zoom (`- N% +`) / extensions
  + add-ons, no bottom row, no sidebar tools; downloads ask where to save;
  pinned tabs not resizable, every row always shown; no url-bar reader/star buttons; invisible sidebar-width handle, double-click resets [USER 2026-11-13]
- [browser-sync](decisions/browser-sync.md) — no tab sync between hosts for
  now; the rest of browser sync is undecided [USER 2026-11-03]
- [password-manager](decisions/password-manager.md) — Vaultwarden on olympus;
  KeePassXC-over-Nextcloud and keeping Proton Pass rejected [USER 2026-08-31]
- [theming-stylix](decisions/theming-stylix.md) — adopt stylix, driven from
  `host.theme.*`; the scaffolding stays [USER 2026-08-31]; explicit targets,
  Nord by name, Noto + FiraCode, olympus console only [USER 2026-11-03]; nvim
  renders per a theme -> plugin|mini.base16 map, Nord by its plugin, unmapped
  schemes rejected [USER 2026-11-04]
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
- [mesh-dev-ports](decisions/mesh-dev-ports.md) — every host accepts TCP
  9000–9099 on the mesh interface only (`host.firewall.mesh.tcpRanges`
  default): mesh hosts and phones with host access, never LAN/internet
  [USER 2026-10-11]
- [trainer](decisions/trainer.md) — served by nginx on olympus
  to VPN sources only; app comes in as a `git+ssh` flake input from
  olympus:~/code; public A record to 10.100.0.1 for now, olympus resolver
  deferred [USER 2026-10-11]
- [hestia-storage](decisions/hestia-storage.md) — hestia's Samsung 970 EVO:
  100 GiB `hestia-backup` at `/var/backup` (restic repo), the rest
  `hestia-dev` at `/mnt/dev` (build slots); backup units require the mount;
  fstrim daily 07:30 [USER 2026-10-12]
- [hot-swap](decisions/hot-swap.md) — orchestrator and coordinator run on
  hestia from `~/deploy/<app>/current` (static musl binaries cargo-built
  there), not from the store; nix-config owns only units, ports, vhosts and the
  swap/rollback unit; upgrade = downgrade = `systemctl start <app>-swap`, no
  sudo, no switch; olympus's nginx proxies both dashboards over the mesh, their
  ports accept the hub only, existing Nextcloud SSO in front (any
  authenticated user) [USER 2026-10-11]; the apps trust the hub only with a
  shared proxy key nginx sends as `X-Orch-Proxy-Key` (`hotSwap.proxyKey`,
  `orch-proxy-key.age`) [USER 2026-10-13]
- [orch-state-backup](decisions/orch-state-backup.md) — hestia's
  orchestrator/coordinator state and the night kit's history are backed up
  hourly as `--host hestia --tag orch-state`, keep-last 2, into hestia's repo
  and a second one on hermes (each host pulls on its own; ends the
  single-repository rule; mail keeps its history and goes to both); WAL
  databases via `VACUUM INTO`; tokens included since the repos are encrypted
  [USER 2026-10-12]
- [control](decisions/control.md) — control.dklaassen.de (phone_controller
  relay) runs on olympus as a hot-swapped app, built on a desktop and pushed,
  never built on olympus; the vhost is public, no Nextcloud SSO
  [USER 2026-10-15]
- [hestia-cpu-governor](decisions/hestia-cpu-governor.md) — hestia runs
  `performance` permanently since the 2026-10-20 cooler swap (67-68 C at full load);
  the coordinator no longer switches per measurement session
  (`measure.session_governor = 0`) [USER 2026-10-20; amends 2026-10-18].
- [orchestrator-oom-policy](decisions/orchestrator-oom-policy.md) —
  `orchestrator.service` runs with `OOMPolicy=continue`, `MemoryHigh=6G`,
  `MemoryMax=10G`; agents stay in their own user scopes [USER 2026-10-17]
- [nextcloud-major](decisions/nextcloud-major.md) — olympus on `nextcloud35`,
  bumped from 34 at 35.0.0; majors are explicit one-step pins, DB dump +
  config copy first [USER 2026-10-22]
- [ls-eza](decisions/ls-eza.md) — fish's `ls` goes through eza, bash keeps GNU
  `ls`; `l`/`ll`/`la` mean the same in both (`la` includes `.` and `..`)
  [USER 2026-11-04]
- [nvim-editor-defaults](decisions/nvim-editor-defaults.md) — guess-indent only,
  no sleuth; builtin `gc` instead of comment.nvim; `updatetime` 250
  [USER 2026-11-04]
- [nvim-lsp-closure](decisions/nvim-lsp-closure.md) — clangd, omnisharp,
  ocamlformat and rust-analyzer come from the project's devshell (`nd`), the
  lighter servers stay bundled; same nvim on every host; no direnv
  [USER 2026-11-04]
- [nvim-no-debugger](decisions/nvim-no-debugger.md) — no dap, dap-ui or codelldb in
  nvim; 1.4 GiB of closure for tooling with no keymaps [USER 2026-11-04]
- [implementer-host](decisions/implementer-host.md) — hephaestus: wg-easy client
  plus one hub rule (port 22 to the hosts), no mesh key, no `id_priv`; git only
  on olympus and hestia through a forced command with a repo allowlist; pushes
  to branches only, never `main`; off the VPN-only vhosts; public caches,
  headless [USER 2026-11-05]
