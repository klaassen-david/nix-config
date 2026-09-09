# ~/sync excludes build artifacts; restoring it after the olympus disk-full

**Ruling** [USER 2026-09-10]: `home-manager/modules/nextcloud-sync`'s
`excludeFile` carries `target`, `.lake` and `.claude` alongside `.git`. Build
output and agent worktrees never round-trip through the server.

**Why**: with `.git` as the only exclude, every artifact tree under `~/sync`
was uploaded — 456k of the 467k sync-journal entries, ~60G against a 236G
disk. olympus filled until redis could no longer write its RDB snapshot, at
which point it refuses all writes and Nextcloud answered `ServiceUnavailable`
on every DAV request (2026-09-09 23:28). The content is worthless remotely:
`cargo build` / `lake build` regenerate it, and it churns on every build.

**Restoration process**, in the order that works:

1. **Stop the sync first.** `systemctl --user stop nextcloud-cmd.timer
   nextcloud-cmd-watch.service` — the watcher fires 3s after any local change,
   so deleting artifacts with sync live races the engine.
2. **Back up what is not an artifact** before deleting anything:
   `rsync -a --exclude=target/ --exclude=.claude/ --exclude=.lake/
   --exclude='.sync_*.db' ~/sync/ ~/sync-backup-<date>/`. 61G → 219M, which is
   the proof that the rest was all artifacts.
3. **Delete locally, keeping the sync journal.** `.sync_*.db` is what turns a
   missing local file into a server-side DELETE; without it nextcloudcmd does
   fresh discovery, sees 60G remotely that is absent locally, and downloads it
   all back. Delete only the *outermost* `target`/`.lake` (nested `.lake` dirs
   go with their parents), then `git worktree prune` — `rm -rf` on a worktree
   leaves stale admin files in `.git/worktrees/`, and `prune` skips any
   worktree still marked `locked` until `git worktree unlock`.
4. **Remove the server-side copies.** Newly-excluded paths are *ignored*, not
   deleted, so anything already uploaded has to go from olympus's side —
   deletion, then `occ trashbin:cleanup` and `files_versions`. The trashbin
   move is a rename, not a copy, so disk stays flat until trash is emptied.
5. **Only then add the excludes and re-enable.** Excludes landing before step 4
   strand the 60G on olympus permanently.

**Cost of step 4**: `occ trashbin:cleanup` is per-row bookkeeping over the
whole trashbin, not bulk unlinking. Measured mid-run at ~44% of a core in
postgres with the data already gone from disk (200G → 56G used) and inode
count flat — hours of database work after the space has been returned. Expect
it to look hung when it is not.

**Revisit if**: another artifact directory shows up in the fleet (a `dist/`,
`node_modules/`, `_build/`), or `target` as a bare name ever collides with a
real file — it matches files as well as directories at any depth.

Related: [[nextcloud-not-backed-up]] — ~/sync is the reason olympus's Nextcloud
data is not backed up, which makes the sync's correctness load-bearing.
