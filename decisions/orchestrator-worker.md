# Orchestrator worker on hermes

**Ruling** [USER 2026-10-04]: hermes runs the orchestrator's worker
(`~/code/orchestrator`, `docs/deploy-worker.md` there) as the home-manager module
`home-manager/modules/orch`, worker role only, with lingering on
(`users.users.dk.linger = true`). The change was made by the orchestrator's
supervising agent at the user's request; the user switches.

- **Lingering** keeps task units alive through a logout. The orchestrator's ruling
  is that a logout must not end work unless the host is meant to be work-free
  (its `DECISIONS.md`, 58); the module's build fails without it.
- **Sizing:** `ceilingGiB = 26` (MemTotal 30 GiB less 4, as ostt3's `ostt.slice`),
  disk floor 100 GiB absolute on `/`.
- **Two ceilings:** until ostt3's heavy commands go through `orch submit`,
  `ostt.slice` and `orch.slice` each cap close to all of RAM. Don't run heavy work
  through both at once.

**Amended** [USER 2026-10-05]: hermes also runs agentd (`roles = [ "worker" "agentd" ]`), in
the same switch as the worker's fixes, so the soak runs while agentd works instead of before it
(the orchestrator's `DECISIONS.md`, 63 and the speed-up list of 2026-10-05). The pin moved to
`36fa730`, then (2026-10-05) to `cc3c81e` (the worker survives the user manager
re-executing), then to `b428736` (an agent's gate runs inside a worker task); switching to it
is the orchestrator's rollback drill, X5.

**Input** [AGENT 2026-10-04]: `git+file:///home/dk/code/orchestrator`, pinned
by `ref` and `rev` to a commit `orch deployable <rev>` accepts.
- Rejected: `git+ssh` to `olympus:git/orchestrator.git`. `sudo nixos-rebuild`
  fetches inputs as root, which has no ssh key for olympus.
- The input's own nixpkgs stays its own pin, so the build deployed is the one
  the orchestrator's `gate full` tested; only home-manager follows.

**Revisit if:** the orchestrator moves to GitHub or olympus becomes fetchable as
root; agentd's role is added (the orchestrator's switchover); hestia is
deployed (`dataRoot = "/mnt/games/orch"`, its own ceiling).
