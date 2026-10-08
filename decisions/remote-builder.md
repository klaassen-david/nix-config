# hestia builds for hermes

**Ruling** [USER 2026-10-05]: hermes uses hestia as a Nix remote builder
(`common/modules/remote-builder`), over the mesh, VM tests included. Part of the
orchestrator's speed-up list of 2026-10-05: its gates' Nix checks and NixOS VM
tests are most of a gate's time, and parallel agents loaded hermes into flaky tests.

- ssh-ng as dk with `id_priv` to hestia's mesh address; hestia's host key is pinned.
- hestia trusts dk as a Nix user (a remote builder's user must be trusted); dk
  already has sudo there.
- A 5 s connect timeout: without the mesh, hermes builds locally.
- `builders-use-substitutes`: hestia fetches from the caches itself.

**Amended** [AGENT 2026-10-05]: hestia's `/` reached 98 % in a day of builds for hermes (dead
paths after results went back). The supervisor freed 60.9 GiB of dead paths (`nix-store --gc
--max-freed 60G`, no generations touched), and hestia now has `min-free` 30 GiB / `max-free`
80 GiB, so Nix collects dead paths itself while it builds.

**Rejected:** a dedicated `nixremote` user with a forced command (more to maintain
for no gain, as dk is already root-equivalent on hestia); building on olympus (small
VPS, no KVM).

**Revisit if:** hestia's load from builds disturbs its own work or ostt3's
measurements (`measure` lock), or a third build host appears.

**Switched off on hermes for now (2026-10-07):** `remoteBuilder.useHestia = false` in
`hermes/configuration.nix`. hermes reaches hestia over Wi-Fi only, and a remote build's round
trip costs more than building on hermes (a trivial derivation 13-28 s remote against ~7 s local;
the orchestrator's `docs/gate-times.md` and `docs/research/iteration-time.md`). The module and
hestia's side are unchanged: setting it to `true` and switching hermes brings the remote builds
back, once the two are on a fast link.

**Memory budgets while building alone** [AGENT 2026-10-07]: hermes froze at 09:42 (journal
cut mid-line, no pstore record, hard reset) two minutes after 18 orchestrator agents resumed.
Its nix-daemon, outside the orchestrator's ledger, reached 24 GiB beside orch.slice's 22.6 GiB
(MemTotal 30.6 GiB), and 56 GiB of swap (swapfile, zram, partition) let it thrash instead of
killing anything. With `useHestia = false`: nix-daemon `MemoryHigh` 8G / `MemoryMax` 9G /
`MemorySwapMax` 1G with `OOMPolicy = continue`, `max-jobs` 2 and `cores` 4; orch.slice's ceiling
14 GiB (26 with hestia) and `MemorySwapMax` 2G; the orchestrator runs at most 6 agents [USER
2026-10-07]. An over-budget build is killed and fails; the box stays up.

Amended the same day: 4 cores per build got rustc OOM-killed in the daemon three times in
15 min (hermes kept 14 GiB free); now `cores` 3 and `MemoryHigh` 9G / `MemoryMax` 10G.

**Back on over Wi-Fi** [USER 2026-10-07]: building alone, hermes livelocked. `max-jobs` holds
per client connection, not per daemon, and every gate step is a client: 13 steps ran ~12
builders at once inside nix-daemon's 10 GiB, which `MemoryHigh` 9G throttled for an hour without
an OOM kill. Remote builds are bounded by the builder's slots across all clients, so
`useHestia = true` again. hermes keeps nix-daemon `MemoryMax` 10G / `MemorySwapMax` 1G /
`OOMPolicy = continue` (no `MemoryHigh`) and orch.slice `MemorySwapMax` 2G in both modes; the
orch ceiling is 26 GiB with hestia, 14 without. Revisit if: a global limit on local builds
(hermes as its own remote builder, or one in the orchestrator's worker).

**Budgets that fit, and an oomd net** [AGENT 2026-10-07]: hermes froze again at 22:07 (journal
cut, no pstore), five minutes after the worker's queue drained and admitted tasks up to its
25 GiB ledger. With hestia back on, orch.slice's ceiling was 26 GiB beside nix-daemon's 10 GiB:
together more than MemTotal (30.6 GiB), so the box ran out before either cgroup reached its own
limit, and swapped instead of killing. Now the two sum to 25 GiB in both modes (orch 19 + nix 6
with hestia, 15 + 10 without), and systemd-oomd kills inside orch-tasks.slice or nix-daemon after
20 s at 50 % memory pressure.

**CPU caps** [AGENT 2026-10-07]: with hestia on and `max-jobs = auto`, a build runs on hermes
whenever hestia's slots are full: a full gate booted five VM tests on hermes (load 36, Tctl
92 °C). Now hermes keeps one local job per client with hestia, nix-daemon's `CPUQuota` is 400 %
(800 % without hestia), and orch-tasks.slice's is 800 % of the 16 cores.

**More room for the desktop** [AGENT 2026-10-08]: hermes froze a third time at 08:54 (journal cut
30 s before; apps died, then sway, then the box). Two task cgroups had OOM-killed rustc minutes
before; with orch.slice at 19 GiB and nix-daemon at 6 GiB only ~5.6 GiB of MemTotal remained for
the desktop, zram's own pages and the kernel, while Zen alone takes 3-5 GiB. Now orch.slice 14
GiB (12 without hestia), nix-daemon 5 GiB, app.slice `MemoryLow` 6 GiB and session.slice 512 MiB,
and journald syncs every 5 s (crash-capture) so the next freeze keeps its last seconds.
