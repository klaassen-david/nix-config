# orchestrator.service survives OOM kills and has a memory limit

**Ruling** [USER 2026-10-17]: `orchestrator.service` on hestia runs with
`OOMPolicy=continue`, `MemoryHigh=6G` and `MemoryMax=10G`
(`common/modules/orchestrator/default.nix`). Decided with the research sweep of
2026-10-17 (question 1 of its report, finding X11-01).

**Why.** systemd's default `OOMPolicy=stop` with `KillMode=control-group` turns
one kernel OOM kill of any process in the unit into a stop of the whole unit,
daemon included. The sweep found the unit unlimited (`MemoryMax=infinity`) on a
31 GiB host. Agents now run in their own `orch-agent-*.scope` units under dk's
user manager, not in this cgroup, so what remains inside is the daemon, its git
work (merges, gates) and its `coordinator run` clients. With `continue`, an OOM
kill takes only the killed process; if that is the daemon, `Restart=on-failure`
brings it back.

**Values.** The journal's per-run peaks on 2026-10-17 were 2.5–7.1 G, almost all
page cache from git writes (the daemon's own RSS is ~35 M). `MemoryHigh=6G`
makes the kernel reclaim that cache early; `MemoryMax=10G` is the hard bound.

**Not here**: agent CPU and memory caps and the hold throttle are the harness's
(the i806/i807 re-land), set on the agent scopes by the orchestrator itself.

**Revisit if**: the daemon is OOM-killed or throttled at `MemoryHigh` in normal
operation (`systemctl show orchestrator.service -p MemoryPeak`, journal
"Consumed … memory peak"), or agents move back into this unit's cgroup.
