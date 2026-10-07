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
