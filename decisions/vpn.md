# VPN: per-device egress over the olympus hub

## Rulings [USER 2026-09-30]

**Hosts** (hermes, hestia) choose their internet egress on the device, at
runtime (switches are rare, < 1/week):

- direct — nothing goes via olympus
- via olympus's uplink
- via one of the other hosts, relayed through olympus (hermes → olympus →
  hestia; the extra RTT is accepted)
- via tukl, dialled directly by the host — never relayed via olympus

**Host mesh**: split-tunnel links between the three hosts are always on; a
command takes them down and back up.

**tukl**: each host gets its own RPTU WireGuard config (more can be issued).
Phones never get tukl through the fleet — only via their own RPTU profile.

**Phones** stay on wg-easy, because they must be addable/removable on the fly
from its UI; it moves from v14 to v15 (host network namespace — its "routed"
mode) together with this change. They get a full tunnel to olympus; each phone's egress (olympus
uplink or one of the hosts) is set on olympus by a runtime command, default
olympus's uplink. Host reachability is a per-phone option set by the same
command, default off.

**Home-network access** (hestia's LAN, real addresses) is a switch separate
from egress — choosing hestia as exit grants none. Hosts and olympus flip it
locally; for phones it is a per-phone option on olympus, never on the phone —
phones are untrusted. While it is on, the home prefix wins over a colliding
local LAN on the device; reaching both at once is not needed.

**Host interface** [USER 2026-10-02]: a `vpn` wrapper (`vpn status`,
`vpn egress <direct|olympus|host|tukl>`, `vpn home on|off`, `vpn mesh on|off`)
over the units, and an i3status block showing the current exit.

**Exit offline**: traffic is dropped; hosts additionally show a notification.

**olympus** keeps its own traffic on its uplink — no exit, no filtered split
(mail, inbound replies, ACME would all need exempting). It is on the mesh and
reaches the hosts like any other node.

## Constraints [AGENT 2026-09-30]

- Within one WireGuard interface only one peer may hold `0.0.0.0/0`, so the
  exit-capable hosts cannot share the single `olympus` interface as plain
  peers — each exit needs its own interface or an encapsulation (e.g. GRE)
  over the mesh.
- Per-phone egress needs each phone's tunnel address visible on olympus; the
  in-container MASQUERADE (plus podman's NAT) currently collapses all phones
  into one container address.

## Rejected

- Headscale/Tailscale exit nodes — exit choice is client-side, foreign devices
  need the app, and it replaces the whole stack.
- Phones as entries in the nix `nodes` registry — every add/remove would be a
  rebuild.
- Egress as a nix setting on olympus for hosts — the choice belongs on the
  device.
- olympus egress via an exit with address-bound traffic filtered to the
  uplink — feasible, no use case.
- reaching the LAN hermes is on, and remapping colliding LANs (NETMAP on
  hestia or hermes) — not worth the cost; collisions are worked around by
  hand (amends an earlier same-day ruling that included hermes's LAN).
- tukl terminated on olympus — one key shared by every user of it, an extra
  hop, and RPTU's DNS would not follow the egress choice.

## Revisit if

- host-to-host exits need to bypass olympus (would need NAT traversal or a
  port forward at home);
- wg-easy is abandoned upstream, or its UI stops being how phones are added;
- a device without its own RPTU profile needs RPTU egress.
