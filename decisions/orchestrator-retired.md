# The orchestrator on hestia is retired

**Ruling** [USER 2026-11-20]: the orchestrator is turned off on hestia; "it is
being retired in favor of the current architecture". hestia no longer imports
`common/modules/orchestrator`, so `orchestrator.service` and
`orchestrator-swap.service` are gone after the next switch and nothing starts
the harness at boot.

**Current architecture.** Agents are headless `claude -p` runs started by small
worker scripts on the implementer hosts (hephaestus; feature directories, one
branch per feature), supervised from a session on hermes. No daemon, no stewards.

**Why.** The orchestrator is pinned to claude 2.1.296 and would need porting to
stay usable. Its stewards were the largest cost of the Setrapla work: 73 % of
the harness's spend there went to four steward sessions, 56 % to one of them.
It also started at every boot of hestia and resumed its stewards, which then
drew usage while the host was cordoned.

**What stays.**
- `common/modules/orchestrator` and the `orchestrator` entry of
  `hot-swap/apps.nix`: unused by any host, kept so that the ruling can be
  reverted with one import line.
- `~/deploy/orchestrator` on hestia (binary, `state/` with the database and
  the agents' transcripts) and its hourly backup (`modules/orch-state-backup`):
  the state is a record, not live data.
- The coordinator (`common/modules/coordinator`): the measurement kits on
  hestia still take their holds from it.
- `orchestrator.dklaassen.de` on olympus (`hot-swap/vhosts.nix`): answers 502
  from now on; removing the vhost is a separate change and needs an olympus
  switch.

**At the switch.** Agent scopes (`orch-agent-*.scope`) run under dk's user
manager, outside the unit: a steward that is running when hestia switches
keeps running until it is stopped or the host reboots
(`systemctl --user stop 'orch-agent-*.scope'`).
