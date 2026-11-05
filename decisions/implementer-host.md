# implementer-host: hephaestus runs agents and builds, outside the fleet's trust

**Ruling** [USER 2026-11-05]: `hephaestus` is an implementer host: Claude Code
agents and cargo/reference builds, headless. It is not a coordinator executor.

- **Network**: a wg-easy client (`10.100.1.0/24`) plus one hub rule. No mesh key,
  no `olympus` interface, no registry entry. It reaches the hosts on port 22 only;
  hosts and phones reach it.
- **Trust**: no `id_priv` on this host, ever. Git only on olympus and hestia,
  through a forced command with a repo allowlist. No shell on hestia.
- **Pushes**: branches only, never `main`, enforced server-side. Allowlist:
  orchestrator2 (`olympus:code/orchestrator`, `hestia:work/orchestrator/repo`),
  ostt3 (`hestia:/home/dk/work/ostt3/repo`).
- **VPN-only sites**: denied to its address (`modules/trainer`,
  `hot-swap/vhosts.nix`).
- **Accounts**: the user logs in himself with one Claude account; no credentials
  are copied. `cswap` can come later.
- **Headless, public caches only**: no attic, no desktop bundle.

**Rejected**: mesh membership (a mesh key plus `id_priv` would give it every fleet
secret); `vpn-phone hosts on` (opens every port the hosts accept on the mesh, not
22 alone); a plain key on dk@hestia (dk can read `~/.ssh/id_priv`, so that is
`id_priv` in effect); a dedicated `impl` WireGuard interface (new code in the hub
for one peer).

**Why `base.nix` holds so little** [AGENT 2026-11-05]: the refactor had to leave
hermes, hestia and olympus byte-identical, and module import depth and order set
list-merge order (`systemPackages`, `tmpfiles`). Only `host.nix` and `theme` stay
under `base.nix`; the self-gated hardware modules stay under `common.nix` in their
old order, which an implementer host does not miss.

**Push policy** [AGENT 2026-11-05]: a pre-receive hook passed only to the forced
command's receive-pack (`-c core.hooksPath`), never installed in a repo, allowing
`refs/heads/implementer/*` alone; `common/modules/implementer-git` says why a repo
hook and an "anything but main" rule both interfere with the orchestrator. The
namespace is narrower than the ruling asked; widening it is one line in the hook.

**Disks** [USER 2026-11-05]: M.2 = ESP 1 GiB, root 100 GiB with `/nix`, the rest
(about 137 GiB) at `/mnt/scratch` for compile output; second SSD whole at
`/mnt/dev` for worktrees and repos. Both are SATA 6 Gb/s; the point is capacity.

Evaluation [AGENT 2026-11-05], open for the user; nothing below is applied:
- **Swap the two data filesystems**: `/mnt/dev` on the M.2's 137 GiB, `/mnt/scratch`
  on the whole second SSD. Compile output is the larger share (up to about 22 GiB per
  hestia slot against about 2 GiB tracked plus `.git` for ostt3, 9 GiB with its lake
  output), and the heaviest writer would no longer share a disk with root and `/nix`.
  Losing the older drive (inferred from its serial) then costs only rebuildable output.
- **GC**: none here (`nix.gc.automatic` false, no `min-free`), and 100 GiB needs it:
  measured ostt3 shell 16.6 GiB, system at least 3.8 GiB. Add `min-free` / `max-free`
  and a weekly `nix.gc`, keeping shells with `nix develop --profile`.
- **Build output**: `build.build-dir = "/mnt/scratch/cargo/{workspace-path-hash}"` in
  `~/.cargo/config.toml` gives each worktree its own directory; not
  `CARGO_TARGET_DIR`, which `scripts/build-web`, `scripts/release` and ostt3's
  `scripts/measure` read or set. Add a daily cleanup of directories idle for 14 days.
- **Memory**: `zramSwap` as is. `systemd.oomd` manages no slice here, so cap
  `user-1000.slice` (`MemoryHigh` 26G, `MemoryMax` 28G) and an OOM stays inside it.

**Switching side effect** [AGENT 2026-11-05]: `keyAge` is a path under
`${secretsPath}`, so any change in `secrets/` moves the restart triggers: a switch
restarts orchestrator and coordinator on hestia and the key unit on olympus.

**Revisit if**: the host needs a shell on hestia (a separate non-wheel user, not
dk), or becomes a coordinator executor.

Applied (user, same day): `/mnt/dev` on the M.2's remaining space and `/mnt/scratch` on the whole second SSD, weekly GC with min-free 20 GiB and max-free 40 GiB, Cargo `build-dir` on scratch with a daily cleanup, and `user-1000.slice` capped at MemoryHigh 26G, MemoryMax 28G.
