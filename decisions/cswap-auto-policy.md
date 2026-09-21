# cswap auto-switch policy

**Ruling** [USER 2026-09-21, amending 2026-09-20]: the `cswap-auto` service picks
the Claude account by this hierarchy:

1. Never a disabled profile (`cswap disable`).
2. Then slot order: `klaassed@rptu.de` (slot 1) is spent first and returned to
   when its window resets — `autoswitch.drainAccount`. Disabled today, which
   makes the rule dormant rather than dropped: `_drain_account_target` folds in
   `cswap disable`.
3. Leave an account as soon as *any* of its limits (5h, 7d, per-model) reaches
   its line: 95 % for `klaassed@rptu.de`, 98 % for every other account —
   `autoswitch.threshold 98`, `autoswitch.accountThresholds klaassed@rptu.de=95`,
   `autoswitch.model all`.
4. Between the two Claude Max accounts (slots 2 and 3), sit on the one whose
   **weekly window resets soonest** and drain it before that reset —
   `autoswitch.strategy consume-first`. A standing preference, not only a
   tiebreak at departure: below the threshold the engine still moves onto a
   sooner-resetting peer. Self-stabilising — once there, nothing resets sooner —
   so it costs one move per weekly rollover, and the bouncing you actually see
   is rule 3 firing on 5h windows.
5. A spent session window still leaves at 98 % even when the only healthy peer
   resets later — the weekly rule ranks the target, it never blocks a departure.
6. When *nothing* is below its threshold the weekly rule is overridden: rank by
   soonest **binding** recovery instead (usually a 5h window, minutes out, not
   a weekly one days out). `_every_account_above_threshold` → `_recovery_is_useful`.

**Why consume-first and not weekly-headroom** (the 2026-09-20 ruling, superseded):
weekly quota is perishable, and balancing drives both accounts toward *equal*
remainders — so each one arrives at its own reset still holding what it never
spent. Spending the soonest-expiring stock first is what avoids that. It only
pays while weekly demand sits between one and two accounts' worth; below that
nothing is ever exhausted and above it everything is, and the ordering is a
no-op either way.

`drainAccount` and `consume-first` are both live, and that is supported rather
than tolerated: `_at_drain_account` suppresses the consume-first *departure*
from a healthy drain account, so the named anchor wins outright and the reset
ordering only ranks the remainder. Two unsuppressed anchors cycled forever on
fixed data (measured `1 -> 2 -> 1 -> 3 -> 1 -> 2`).

**98 % is deliberate** [USER 2026-09-21]: two points of runway against a 60 s
poll floor (`URGENT_INTERVAL_S`), and nothing reacts to a 429 Claude Code itself
receives — the at-limit trigger fires only once measured headroom is already
gone. Accepted for maximum extraction per account; upstream's default is 90.

`autoswitch.hysteresisPct` is back to its default and is no longer policy: the
consume-first gate is a bare strict inequality on reset ordering, and reads the
setting nowhere, so any value there was inert.

**Rejected**: `weekly-headroom` (superseded — see above); `strategy best` (ranks
by the binding window, so a Max account with a spent 5h window but a full week
could be left idle while the other one drains its week).

**Revisit if**: a fourth account joins, or rptu is re-enabled — at three or more
candidates the no-return bar can hold the engine off the soonest-resetting
account, because its release legs are headroom- and binding-reset-shaped and
the unbarred retry only fires when the barred ranking comes back empty.
