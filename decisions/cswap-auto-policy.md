# cswap auto-switch policy

**Ruling** [USER 2026-09-21, amending 2026-09-20]: the `cswap-auto` service picks
the Claude account by this hierarchy:

1. Never a disabled profile (`cswap disable`).
2. Then slot order: `klaassed@rptu.de` (slot 1) is spent first and returned to
   when its window resets — `autoswitch.drainAccount`. Live again as of
   2026-10-01 (it was disabled when this was first written, which made the rule
   dormant rather than dropped: `_drain_account_target` folds in `cswap
   disable`). Being live is what makes rule 5's departures ordinary rather
   than theoretical — see the 2026-10-01 fix below.
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
   But it ranks it only *among healthy peers*: a forced departure prefers any
   account below its own line to a sooner-resetting one that is spent, and
   falls back to reset order only when nothing is healthy. Rule 4 is a
   preference between usable accounts, never a reason to land on an unusable
   one — see the 2026-10-01 fix below.
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

**Fixed in the fork** [AGENT 2026-09-21]: the no-return bar held the engine off
the soonest-resetting account. None of its release legs was "the peer's weekly
window resets sooner" — the axis this policy ranks on — and a departure recorded
at full headroom clamps the headroom leg (`h >= min(leftHeadroom + 3, 100)`) at
an unreachable 100, leaving only a collapse of the active account's own headroom.
Observed: sitting on slot 2 (resets Sep 27) while slot 3 (resets Sep 23, 23
points spare) stayed barred by a `drain-return` departure recorded 2026-09-19
with `leftHeadroom: 100.0`; the tick reported `already-consuming-soonest`, which
is what an empty ranking looks like from outside. `claude-swap` 2f1bb16 adds a
fourth release leg on the weekly axis — no margin, because the ordering flips
only on a rollover, after which the ranking's own filter refuses the return.
A manual `cswap switch` also clears a stuck bar: `lastSwitchTo` stops matching
the active account.

**Fixed in the fork** [AGENT 2026-10-01]: `consume-first` landed a forced
departure on a nearly-spent account because its weekly window reset sooner.
`at-limit` and `failover` skip the proactive landing-health gate on purpose —
escaping a spent account outranks optimising a return time — but the
consume-first sort key then ranked on reset ordering ALONE, leaving "headroom
above zero" as the only filter on the target. Filter and sort on two different
axes, which is the split the all-above key (rule 6) was already tiered to avoid.

Observed 2026-10-01 14:36, the first rptu-enabled instance of rule 5: at-limit
off slot 1 (5h at 100 % against its 95 line) with slot 2 at 99 % weekly — one
point left, resetting Oct 4 — and slot 3 at 36 %, 64 points, resetting Oct 7.
Slot 2 was chosen on reset order alone; the next tick would have fired at-limit
straight back off it. Caught manually, 17 s later (`leftTrigger: at-limit`,
`leftHeadroom: 0.0` in `autoswitch_state.json`).

`claude-swap` 0766ac8 tiers both proactive strategy keys on landing health, so
each axis ranks only within a tier. It RANKS rather than filters: an
at-/over-threshold account still sorts, just behind every healthy one, so the
at-limit escape survives when nothing healthy exists — rule 6's state, where
holding still would burn the active account into a hard limit. Under a
proactive trigger the gate has already dropped those candidates, so the tier is
a no-op there and rule 4 is untouched between two usable accounts.
`weekly-headroom` had the identical shape (a full week ranking ahead of a spent
5h window) and got the same treatment, though this policy does not use it.

**Revisit if**: a fourth account joins — `drain-return` off a freshly reset
account is what records the baseline for the no-return bar above, so that gap
resurfaces there. The rptu-re-enabled half of this note is now spent: it was
re-enabled on 2026-10-01 and the gap it predicted is the 14:36 incident above.
