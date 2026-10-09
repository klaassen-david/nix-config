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
is the orchestrator's rollback drill, X5. From `2434a6b` (2026-10-05) the input follows `main`,
which the switchover plan shares; the supervisor deploys by home-manager activation (its
DECISIONS 82), the system switch stays the user's.

**Amended** [AGENT 2026-10-06]: hestia runs the worker too, worker role only, with the fleet
deploy (decisions/orchestrator-fleet.md): `ceilingGiB = 27` (MemTotal 31 GiB less 4),
`dataRoot = "/mnt/games/orch"` (the orchestrator's Q11), the disk floor 100 GiB absolute as on
hermes (15 % of the 1.4 TiB `/mnt/games` would be 210 GiB). The per-host values live in
`home-manager/modules/orch`, keyed on `host.hostName`; lingering, the link token and the
coordinator's address in `common/modules/orch`.
- hestia's `/` has 457 GiB with ~68 GiB free, below its 100 GiB floor: the worker's results,
  logs and dev environments there get tended every minute. Trees and clones are on
  `/mnt/games`.
- No projects on hestia yet: ostt3's come with the orchestrator's `ostt3-adoption` (Q12).

**Amended** [USER 2026-10-09]: hestia is the development host: it runs agentd, hermes the
worker only and supervises hestia's agentd remotely while connected; development may move back
(the orchestrator's `DECISIONS.md`, 136 and 137). One binding, `orchDevHost` in
`home-manager/modules/orch`, gives the `agentd` role and everything agentd needs (the
orchestrator project with its checkout, agentd's settings, hermes's `gateNixStore` when hermes
is the host) to that host; changing it is the hand-over, in either direction (the steps are in
the module header).
- agentd's `data_root` is `~/.local/share/orch` on either host, not the worker's `dataRoot`
  (`/mnt/games/orch` on hestia): the same paths everywhere, so agents' sessions resume by their
  cwd after a hand-over, and `orch merge` and `fleet.endpointAllow` find the clones. No bind
  mount. Clones with their `target/` dirs need far more than hestia's `/` has free (126 GiB on
  hermes, 6 GiB without `target/`; hestia's `/` had 58 GiB free on 2026-10-09).
- As the development host, hestia's ledger is 19 of its 27 GiB ceiling: agentd (2 GiB) and its
  runners live in `orch.slice` outside the ledger.
- ostt3 stays on hermes: hestia has no checkout of it.
- Every orchestrator host pins olympus's ssh host key for its mesh address, so the development
  host fetches and pushes `olympus:git/orchestrator.git` without trust-on-first-use.

**Input** [AGENT 2026-10-04]: `git+file:///home/dk/code/orchestrator`, pinned
by `ref` and `rev` to a commit `orch deployable <rev>` accepts.
- Rejected: `git+ssh` to `olympus:git/orchestrator.git`. `sudo nixos-rebuild`
  fetches inputs as root, which has no ssh key for olympus.
- The input's own nixpkgs stays its own pin, so the build deployed is the one
  the orchestrator's `gate full` tested; only home-manager follows.

**Revisit if:** the orchestrator moves to GitHub or olympus becomes fetchable as
root; hestia's `/` can't hold agentd's clones (then their build output, not their path, moves to
`/mnt/games`). The `git+file` input needs the checkout on whichever host evaluates this flake.
