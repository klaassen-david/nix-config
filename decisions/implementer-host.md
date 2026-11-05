# implementer-host: hephaestus runs agents and builds, outside the fleet's trust

**Ruling** [USER 2026-11-05]: `hephaestus` is an implementer host: Claude Code
agents and cargo/reference builds, headless. It is not a coordinator executor.

- **Network**: a wg-easy client (`10.100.1.0/24`) plus one hub rule. No mesh key,
  no `olympus` interface, no registry entry. It reaches the hosts on port 22 only;
  hosts and phones reach it.
- **Trust**: no `id_priv` on this host, ever. Git only on olympus and hestia,
  through a forced command with a repo allowlist. No shell on hestia.
- **Pushes**: branches only, never `main`, enforced server-side. Allowlist:
  orchestrator2 (`olympus:code/orchestrator`, `hestia:work/orchestrator/repo`),
  ostt3 (`hestia:/home/dk/work/ostt3/repo`).
- **VPN-only sites**: denied to its address (`modules/trainer`,
  `hot-swap/vhosts.nix`).
- **Accounts**: the user logs in himself with one Claude account; no credentials
  are copied. `cswap` can come later.
- **Headless, public caches only**: no attic, no desktop bundle.

**Rejected**: mesh membership (a mesh key plus `id_priv` would give it every fleet
secret); `vpn-phone hosts on` (opens every port the hosts accept on the mesh, not
22 alone); a plain key on dk@hestia (dk can read `~/.ssh/id_priv`, so that is
`id_priv` in effect); a dedicated `impl` WireGuard interface (new code in the hub
for one peer).

**Why `base.nix` holds so little** [AGENT 2026-11-05]: the refactor had to leave
hermes, hestia and olympus byte-identical, and module import depth and order set
list-merge order (`systemPackages`, `tmpfiles`). Only `host.nix` and `theme` stay
under `base.nix`; the self-gated hardware modules stay under `common.nix` in their
old order, which an implementer host does not miss.

**Revisit if**: the host needs a shell on hestia (a separate non-wheel user, not
dk), or becomes a coordinator executor.
