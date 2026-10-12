# orch-state: the agent harness's state is backed up hourly into two repos

**Ruling** [USER 2026-10-12]: hestia's orchestrator and coordinator state go
into the fleet's restic backups **hourly**, into **both** hestia's repository
and a new one on **hermes**, keeping the **last two** snapshots per
repository. Mail keeps its own retention and history (daily 7 / weekly 5 /
monthly 12); it is pulled into hermes's repository as well.

**Fleet rule changed** [USER 2026-10-12]: `common/modules/backup` used to say
there is exactly one repository in the fleet. Now every host with a non-empty
`host.backup.pull` (hestia, hermes) owns one local repository
(`/var/backup/restic`) and pulls each listed source into it **on its own**:
pull, not push, so neither host can write to or delete from the other's
repository, and a host that is down or offline leaves the other's copy
current. Still one repository per host, configured alike; same password
(`restic-repo-pass.age`, any host decrypts it), so one secret opens both.

**Design** [AGENT 2026-10-12], `common/modules/orch-state-backup`:
- source `orch-state` = `--host hestia --tag orch-state` in both repos,
  `maxAgeDays = 3`, `retention = [ "--keep-last=2" ]` (per source; mail keeps
  the top-level list);
- scope: `~/deploy/orchestrator/state`, `~/deploy/coordinator/state`, the
  retired night kit's `~/night/orchestrator/{state,logs}` (still read by the
  orchestrator through `ORCH_NIGHT_ROOT`); ~300 MB. Excluded: the live database
  files and claude's per-profile `paste-cache`/`statsig`;
- hestia (the apps' node, from `hot-swap/apps.nix`) backs up its own files at
  :30; hermes at :45 runs `orch-state-snapshot` on hestia over ssh as dk
  (`id_priv`, hestia's host key pinned), rsyncs the same set into
  `/var/lib/orch-state-mirror` (only the delta crosses the mesh) and backs
  the mirror up. Hestia unreachable is a skip (exit 75, a success to systemd),
  not an alert: hermes is offline as a matter of course, and the freshness
  check catches a gap over three days. Switch hestia before hermes.
- mail on hermes is the unchanged `mail-backup` module (boot + weekly pull from
  olympus, 14-day max age): enabling `"mail"` in hermes's `host.backup.pull`
  is all it takes; olympus needs no change.

**Consistency**: both databases are SQLite in WAL mode and written around the
clock, so a file-level copy of `.db` + `-wal` + `-shm` can be torn.
`orch-state-snapshot` runs `VACUUM INTO` as dk into
`/var/lib/orch-state-snapshot` (dk 0700): one read transaction, consistent
without stopping the apps, checked with `PRAGMA quick_check` and only then
renamed into place, so a reader (the rsync from hermes) never sees a partial
copy. The backups take those copies, never the live files. The sqlite3 CLI's
`.backup` was rejected: it copies 100 pages per step and restarts whenever
another connection writes. Everything else (transcripts, task logs, jsonl
history) is append-mostly and taken as is; restic's exit 3 (a file vanished
mid-run) is a warning, not a failure.

**Secrets included**: `secrets/` (admin token, `accounts/*.token`) goes into
both repositories. They are encrypted with `restic-repo-pass.age` and
root-only on each host; a restore without the tokens would need every account
re-provisioned.

**Night window trade-off**: hourly runs land in hestia's 21:00–07:00 build
window (`decisions/hot-swap.md`), where an I/O stall over 60 s panics the host
(crash-capture). Accepted for hourly freshness, and kept light: idle I/O class
and Nice 10, an incremental restic run plus two `VACUUM INTO` copies (~25 MB),
and `--prune` (which repacks) at most once a day and only between 07:00 and
21:00; plain `forget` runs hourly.

**Accepted exposure**: two hourly snapshots means a restore reaches back about
two hours; anything deleted or corrupted and noticed later is gone from both
repos. hermes's copy is as old as its last online hour.

**Rejected**: hestia pushing to hermes (sftp/rest-server) — hermes would need
an inbound write endpoint and hestia, where agents run as dk, could delete
hermes's copy; a full tar over ssh each hour (like mail) — ~300 MB/h relayed
through olympus's hub; stopping the apps for a cold copy; backing up the live
WAL triple; keep-last 2 for mail — the user kept mail's history.

**Revisit if**: the state moves off hestia, a database grows past what an
hourly `VACUUM INTO` copies in seconds, the night window ever panics during a
backup, or the night kit's history is no longer read (drop those two paths).
