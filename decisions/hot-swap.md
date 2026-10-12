# hot-swap: orchestrator and coordinator run outside the store, on hestia

**Ruling** [USER 2026-10-11]: unlike the
trainer, the orchestrator and the coordinator are not flake inputs. nix-config
declares, once, per app: a system unit running as dk that execs
`~/deploy/<app>/current/bin/<app>`, its port, and `<app>-swap.service`, which
moves `current` to the version named in `~/deploy/<app>/want`, health-checks it
and rolls back (`common/modules/hot-swap`). Upgrade and downgrade are the same,
unattended and without sudo:
`echo <v> > ~/deploy/<app>/want && systemctl start <app>-swap` (both units in
`host.userManagedUnits`). Accepted against the nix model for iteration speed.

**Placement** [USER 2026-10-11]: both apps run on **hestia** (orchestrator
:3040, coordinator :7300; `common/modules/hot-swap/apps.nix`), next to the agents,
worktrees and builds they drive; a network outage then costs only the dashboard.
olympus's nginx serves `orchestrator.dklaassen.de` and `coordinator.dklaassen.de`
and proxies them over the mesh to 10.100.0.2 (`hot-swap/vhosts.nix`), with the
trainer's ACL (10.100.0.0/16), no buffering and 1 h timeouts for SSE and
websockets. The apps bind 0.0.0.0 (a mesh restart cannot leave them unbound);
hestia's firewall accepts the two ports on the mesh interface from the hub
(10.100.0.1) only. Phones and other hosts are refused, so nginx is the only door.

**Coordinator on more nodes** [PROPOSED 2026-10-11]: not yet. Its API is
unauthenticated and starts processes as dk, and no second node runs. A node on
hermes later adds hermes's mesh address to the coordinator's `sources` once the
API authenticates its peers (or rides the forced-command ssh channel of the
remote-execution design instead of a port).

**Task confinement**: the coordinator unit has `Delegate=yes`,
`DelegateSubgroup=supervisor`, `KillMode=process` (systemd chowns the delegated
cgroup to `User=`, so dk can create task cgroups and write
memory.max/cpu.max/cgroup.freeze), and both apps get dk's `XDG_RUNTIME_DIR`, so
`systemd-run --user` puts work in dk's manager, where it outlives every swap.
hestia declares `users.users.dk.linger = true` for that (it was on, but only as
leftover state).

**SSO** [USER 2026-10-11]: on. `hotSwap.sso = true` (olympus) puts the
existing Nextcloud SSO gate (`nextcloudSSO`, as on every other gated vhost) in
front of both dashboards: any SSO-authenticated user, no group restriction.
The PWA manifest, `sw.js` and `/icons/` bypass the gate (Chrome fetches the
manifest without credentials). Without it, every wg-easy phone, and any process
on olympus, could drive agents that run as dk.

**Night window** [USER 2026-10-11]: hestia's `fstrim` and
`restic-check` move from Monday 00:00 to Monday 07:30 / 08:00, out of the
21:00–07:00 overnight build window: `modules/crash-capture` panics the host on a
task blocked for 60 s, and an I/O stall under build load is the likeliest way to
get one. Both timers are Persistent. crash-capture itself stays as it is.
Amended [USER 2026-10-12]: fstrim is now daily at 07:30 (hestia-storage.md).

**Build directories**: no nix change. `/mnt/games` is dk-owned (`dk:root 0755`),
ext4, 270 G free; cargo target dirs, build slots and sccache go there. It is
`nofail`: a tool that writes there checks that it is a mount point first, or it
fills `/`. It shares the NVMe with `/`, so it is extra space, not separate I/O.
Superseded for build slots [USER 2026-10-12]: `/mnt/dev` on the second NVMe
(hestia-storage.md).

**Source**: both apps come from one repo for now (olympus:~/code/orchestrator,
a cargo workspace with the coordinator crates in it; olympus:~/code/coordinator
is frozen until the shared crates are split out again). Still two binaries, two
units, two `~/deploy/<app>` trees.

**Releases**: `cargo build --release --target x86_64-unknown-linux-musl` on
hestia inside the project's devShell (nix supplies only the toolchain), then
`rsync` of the one static binary (frontend embedded) to
`deploy/<app>/releases/<v>/bin/` (a local copy on hestia today). Static, so a
release never depends on a devShell store path, wherever it runs.

**Names**: public A records `orchestrator.dklaassen.de` and
`coordinator.dklaassen.de` → 10.100.0.1 plus the hosts entry in common.nix,
exactly as `trainer`; the existing `*.dklaassen.de` Let's Encrypt wildcard
(dns-01, `common/modules/acme`) covers both, no new cert.

**Rejected**:
- the daemons on olympus — 6 weak vCPUs and 7 GiB, and every agent command would
  cross the mesh; remote execution does not exist yet. Revisit when it does.
- nginx on hestia — a second TLS endpoint with the cert copied off olympus, and
  phones reach hestia only with `vpn-phone … hosts on`.
- the dashboard ports open to the whole mesh (`host.firewall.mesh.tcpRanges`) —
  phones with host access would bypass nginx's gate.
- flake inputs like the trainer — every version is a commit, a lock bump and a
  switch.
- home-manager user units + linger — boot ordering between home-manager-dk and
  the lingering manager has already bitten once (nix-config 8400150).
- `nix copy` of a nix-built closure — dk is not a trusted user, and the user
  wants cargo, not `nix build`.
- the app supervising itself (re-exec/socket handover) — a broken release then
  has to roll itself back.
- SSO by `allowed_emails` — the address is user-editable in Nextcloud.
- SSO narrowed to a Nextcloud group (`allowed_groups`) — not wanted for now
  [USER 2026-10-11].

**Revisit if**: an app needs a C library that will not link statically, a
release needs a unit/port change on every swap, remote execution lets the
control plane move to olympus, or a second coordinator node appears.

**Settings file** [USER 2026-10-12]: each app unit reads an optional `~/deploy/<app>/env`
(`EnvironmentFile=-`), owned by dk and written only by the operator. App settings (steward keepalive, sandbox,
accounts, task hiding) change with `systemctl restart <app>`, without a nix switch.
