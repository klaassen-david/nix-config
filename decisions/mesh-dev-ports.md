# Mesh dev ports: TCP 9000–9099, mesh interface only, every host

**Ruling** [USER 2026-10-11]: every host accepts TCP 9000–9099 on the WireGuard
mesh interface (`olympus`), by default via `host.firewall.mesh.tcpRanges`
(`common/host.nix`). Dev servers bound there are reachable from the other mesh
hosts and from phones that have `vpn-phone <phone> hosts on`; never from the LAN
or the internet. Relayed exit traffic is still refused the exit's own services
(`vpn-exit`).

Prompted by a phone (dkA33) failing to reach a test server on hestia:8080 — the
mesh interface only accepted 22, and ad-hoc `iptables` rules die on every
firewall reload.

**Rejected**:
- `trustedInterfaces = [ "olympus" ]` — exposes every listener, present and
  future, to every phone with host access.
- An on-demand `mesh-port@<port>` unit inserting the rule at runtime — closed by
  default, but more code, re-applied on each firewall reload, gone at reboot.
- A per-host opt-in — the user wants the range everywhere.

**Known limit**: phones reach olympus on `wg0`, not `olympus`, so olympus's own
range is open to mesh hosts only.

**Revisit if**: something long-running starts listening on `0.0.0.0` inside
9000–9099, or a phone needs olympus's dev ports.
