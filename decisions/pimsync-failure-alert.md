# pimsync failure alert

**Ruling** [USER 2026-09-29]: a failing `pimsync-sync` raises a desktop
notification (`pimsync-sync-alert.service`, `OnFailure=`), after a conflict on
one event went unnoticed from 2026-06-18 to 2026-09-29 and stalled that item.

**Scope** [AGENT 2026-09-29]: only exit 3 (unresolved conflict) notifies — it
never clears on its own. Other failures (offline laptop, server down) retry on
the next 5-minute tick and would notify constantly, so they stay in the journal.

**Rejected**: auto-resolving via pimsync's `conflict_resolution` hook (e.g.
always take the server copy) — it would silently drop whichever side loses.

**Revisit if**: a non-conflict failure (e.g. a revoked app password) goes
unnoticed for long — it would need a "failing for N hours" check.
