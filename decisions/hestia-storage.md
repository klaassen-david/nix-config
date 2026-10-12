# hestia storage: second NVMe for backups and builds

**Ruling** [USER 2026-10-12]: the Samsung 970 EVO 1 TB, previously unused, is
wiped and split into two parts. `hestia-backup` (100 GiB, ext4) holds `/var/backup`,
which contains the restic repo. `hestia-dev` (the rest, ext4, dk-owned) holds `/mnt/dev`,
where the coordinator's build slots move. Both are mounted by label with `noatime,nofail`.
`/`, `/nix/store` and `/mnt/games` stay on the Kingston NV1.

**Why**: build I/O stalls. The Kingston is QLC with no DRAM and 83–87 % full.
It carried everything, and PSI io-full reached 20–50 %, freezing builds and
merge gates.

**Consequences**
- The backup units (`mail-backup`, `orch-state-backup`, `restic-check`)
  carry `RequiresMountsFor=/var/backup` through `backupRepo.alertHook`. If the
  disk is missing, the job fails instead of letting `restic init` create a
  new repo on `/` under the empty mount point. This is fleet-wide: on hermes,
  `/var/backup` is on `/`, so the requirement is a no-op there.
- fstrim runs daily at 07:30 instead of on Mondays, which suits the QLC drive.
  It stays out of the night window (hot-swap.md) [USER 2026-10-12].
- Moving `SLOTS_ROOT` to `/mnt/dev/coordinator/slots` is an app setting
  (`~/deploy/coordinator/env`), not a nix change.

**Rejected**: keeping the build slots on `/mnt/games`. It is on the same NVMe
as `/`, so it adds space but not a separate I/O path.

**Revisit if**: the restic repo outgrows 100 GiB, or builds still stall with
the slots on `/mnt/dev`.
