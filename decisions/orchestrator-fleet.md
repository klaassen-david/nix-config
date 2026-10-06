# Orchestrator fleet: coordinator on olympus, leases between hermes and hestia

**Ruling** [AGENT 2026-10-06]: the orchestrator's fleet plan (`~/code/orchestrator`,
`docs/deploy-coordinator.md` there) is deployed as prepared by its supervisor at the user's
request; the user makes the secrets and switches (the orchestrator's `DECISIONS.md`, 61, 63,
82: the supervisor commits, the user switches).

- **Coordinator** on olympus: `common/modules/orch-coordinator`, the orchestrator's
  `nixosModules.coordinator` with the vhost `orch.dklaassen.de` on the shared cert and the
  Nextcloud SSO gate. The link (`/link/v1`) is outside the gate; the host token is its check.
- **VPN only:** the vhost allows 10.100.0.0/24 (mesh) and 10.100.1.0/24 (phones) and denies the
  rest. hermes and hestia resolve the name to olympus's mesh address with a `networking.hosts`
  line (`common/modules/orch`), so no public DNS record is needed.
- **One link token per worker host**, `orch-link-<host>.age`: root-only on olympus (a systemd
  credential), owner dk 0400 on the host, whose worker reads it.

**Leases** (`docs/deploy-fleet.md` there): hestia accepts other hosts' tasks always
(`fleet.acceptsAlways`), hermes only in windows (`orch accept 3h`) and holds a sleep inhibitor
so closing the lid gives idempotent leased tasks back. Each worker has its own ssh key
(`orch-fleet-<host>.age`, dk 0400) to fetch trees from the other; the other authorizes its
public half (`common/keys/orch-fleet-<host>.pub`) for dk with `restrict` and the forced command
`orch git-endpoint`, serving snapshot refs of repositories under `/home/dk/code` and agentd's
clones only.
- The authorized line is added only when the `.pub` file is in git (`builtins.pathExists`), so
  the tree evaluates before the user has made the keys; the build warns meanwhile.
- No new port: sshd is already on the mesh (`common/modules/ssh-server`), and both hosts have
  each other's host keys in dk's `known_hosts`.

**hestia knows the orchestrator project** (2026-10-06): `projects.orchestrator = { }` in hestia's
`services.orch`, by name only, so tasks of hermes's agents leased to hestia (gates, tests) are
known as the project's and get its dev shell, built from the leased tree. No `path` or `flake`:
hestia has no checkout, and it can't reach olympus's repository (no known host key).

**Rejected:**
- a public DNS record pointing at 10.100.0.1 instead of the hosts lines: it serves phones too,
  but nothing needs that yet;
- binding the vhost to the mesh address (`nginx.listenAddresses`): an address missing at
  nginx's start keeps all of nginx down;
- reusing `id_priv` for tree fetches: it is a full login on every host; a separate key with a
  forced command can fetch snapshots and nothing else.

**Revisit if:** phones use the dashboard (add the DNS record); a host's mesh traffic leaves with
an exit's source range (add it to `services.orch-coordinator.nginx.allow`); agentd runs on
hestia (add its clones under `/mnt/games/orch` to hestia's `fleet.endpointAllow`); a third
worker host appears (the `workers` lists in `common/modules/orch` and
`common/modules/orch-coordinator`).
