# cswap auto-switch policy

**Ruling** [USER 2026-09-20]: the `cswap-auto` service picks the Claude account
by this hierarchy:

1. Never a disabled profile (`cswap disable`).
2. Then slot order: `klaassed@rptu.de` (slot 1) is spent first and returned to
   when its window resets — `autoswitch.drainAccount`.
3. Leave an account as soon as *any* of its limits (5h, 7d, per-model) reaches
   its line: 95 % for `klaassed@rptu.de`, 98 % for every other account —
   `autoswitch.threshold 98`, `autoswitch.accountThresholds klaassed@rptu.de=95`,
   `autoswitch.model all`.
4. Between the two Claude Max accounts (slots 2 and 3), sit on the one with the
   most remaining *weekly* quota, rebalancing below the threshold; frequent
   switching is accepted — `autoswitch.strategy weekly-headroom`,
   `autoswitch.hysteresisPct 1` (a move needs one point of weekly lead, a
   reverse move two points of real burn; the 5-minute cooldown bounds the rate).
5. A spent session window still leaves at 98 % even when the only healthy peer
   has less weekly quota left — the weekly rule ranks the target, it never
   blocks a departure.

The policy lives in cswap's `settings.json` (`cswap config`), not in this repo;
`weekly-headroom` and `accountThresholds` are additions to the
`klaassen-david/claude-swap` fork (`dk/main`), so the service only honours them
once the flake input is bumped past that commit.

**Rejected**: `strategy best` (ranks by the binding window, so a Max account with
a spent 5h window but a full week could be left idle while the other one drains
its week); `consume-first` (spends the soonest-resetting week first — the
opposite of balancing).

**Revisit if**: a fourth account joins (the weekly rule then covers a pool, not
a pair), or the rptu account is re-enabled and slot order stops matching the
intended spend order.
