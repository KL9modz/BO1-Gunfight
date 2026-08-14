# An unplanned joiner's coin flip opens a 2-gap that bots then freeze in for the match

**Date:** 2026-08-13 **Status:** FIXED (both connect-time paths), verified against the live log only —
not yet observed on a subsequent match.

Reported by the owner as "teams were not balanced" on `mp_crisis`; root-caused off the VPS
`games_mp.log`, window `2872:50`–`2883:54`.

## What the log showed

| Side | Players |
|---|---|
| Allies | KL9, gandylion, `[bot]X756sosa23` |
| Axis | matzues, Nico_gam, YooDyl |

- **Round 0 played 2 humans + 1 bot vs 4 humans.** The carried plan held **5 entries** and seated them
  2 allies / 3 axis (legal, off-by-1). TomTheWhale was **not in the plan** and landed on axis → 2v4.
  The fill then correctly padded allies to 3 (`GF_ENDMARK: add_bot team=allies 1/1`, 2872:52).
- The round-0→1 boundary corrected it (`GF_TEAMTRACE: human TomTheWhale axis -> allies by seatjoin`,
  2873:53) and rounds 1-3 were a clean **3v3, all human**.
- TomTheWhale quit at 2875:47 → 5 humans → 2 allies / 3 axis → the bot went back on allies, and
  **rounds 4-end were 2 humans + bot vs 3 humans** (~7 rounds).

The tail is **by design** (at 5 humans every split is 3/2 and bots pad the short side — the only lever
is `gf_fill_n 0`). **Round 0 was the defect.**

## The two bugs

1. **`gf_autoassignPlanned`'s unplanned-joiner branch was a BARE stock autoassign.** A plan is a
   snapshot of the *previous* roster, so the unplanned joiner is exactly the player most likely to
   unbalance it — and that branch gave them *less* protection than a normal mid-match joiner, a pure
   coin flip ignoring the seating just applied.
2. **`gf_autoJoinBalance` fell through to stock at `diff <= 1`.** A legal 1-gap could become a 2-gap by
   coin flip. Whatever opens the 2-gap, bots pad to `max(bigger human side, gf_fill_n)`, so it sets as
   **"N humans vs N-1 humans + a bot"** for the rest of the match — head count NvN, so no guard trips,
   but players feel it every round.

## The trap in the fix

The obvious fix — steer the unplanned joiner by a **live head-count** — **does not work**, and the log
proves it: at the `map_restart(false)` re-begin wave clients reconnect one at a time, and TomTheWhale
re-began **first of six**. A live count would have read `0/0` → "parity" → coin flip → same bug.

Steer against the **projected** split instead (`gf_planProjectedHumans`): count the **plan entries**
(`<guid>:<a|x|s>`), plus any already-seated human the plan does not name. A stale entry (a planned
player who never returns) costs at most a 1-gap, which the round boundary evens — strictly better than
the 2-gap it prevents.

## Shipped

- **`gf_seatBalancedJoin( ha, hx )`** — shared pre-spawn seating tail (lock → balance) for *both*
  connect-time paths, so they cannot drift. Falls through to stock **only at exact parity**.
- **`gf_planProjectedHumans( exclude )`** — the projected-split reader above.
- `gf_autoassignPlanned`'s `want == ""` branch now routes through both.

Both live in `_gf_rounds.gsc` inside the `MATCH-START HOLD + LOBBY->MATCH TRANSFER` strip region
(public builds keep stock autoassign). `verify_release_strip.ps1` passes.

## Diagnostic gotcha found on the way

**`humans=N` in `GF_ENDMARK` / `GF_HITCH` is inflated by one** — `_gf_debug::gf_hitchHumans()` is written
as `!gf_isRealBot(p)`, the inverse-of-a-bot-filter CLAUDE.md warns against, so the **democlient counts as
a human**. `humans=6` means 5 real. The reconciler's own `gf_reconcileCount` uses `gf_holdsSeat` and is
correct, so this is display-only — but it will mislead anyone reading a fill decision out of the log.

## Related

[[gf-fill-reconciler-and-team-transfer]], [[untraced-writes-are-unstamped-stock-menu-paths]],
[[quiet-team-move-cleared-class-blocks-respawn]]
