# Orchestrator fleet: coordinator on olympus

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

**Rejected:** a public DNS record pointing at 10.100.0.1 instead of the hosts lines: it serves
phones too, but nothing needs that yet. Binding the vhost to the mesh address
(`nginx.listenAddresses`): an address missing at nginx's start keeps all of nginx down.

**Revisit if:** phones use the dashboard (add the DNS record); a host's mesh traffic leaves with
an exit's source range (add it to `services.orch-coordinator.nginx.allow`).
