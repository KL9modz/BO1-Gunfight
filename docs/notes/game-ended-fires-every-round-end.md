---
name: ""
metadata: 
  node_type: memory
  originSessionId: 79682440-f371-4bd0-a6d4-b22a8ea90457
---

**`level notify("game_ended")` fires at the end of EVERY ROUND, not at match end.**

`gf_endRound` (`_gf_rounds.gsc`) notifies `gf_round_over` and then, **in the same frame**, threads
`_globallogic::endGame`. Stock `endGame` (raw `_globallogic.gsc:896`) runs **yield-free** from its entry
guard to `level notify("game_ended")` at line 924 — there is no `wait` in between. Round cycling goes
through `endGame` every round (that IS the round-end path: endGame → startNextRound → map_restart(true)),
so `game_ended` lands ~instantly after every single round ends.

**Consequence: `endon("game_ended")` means "die at the next round end."** It does not mean "live for the
match." A thread that must survive round cycling must endon something else — the codebase's collapse
notifies (`bot_reinit`, `gf_bridge_reinit`) exist for exactly this, fired at the top of the re-init that
would otherwise stack a second copy.

**Bugs it has caused (twice):**
1. `gf_postRoundWatchdog` — documented in CLAUDE.md: it must not carry the endon, because endGame fires
   it within a frame of the thread starting. Caught during design.
2. **The bot fill reconciler (2026-07-12).** `gf_boundaryListener` (`_bot.gsc`) held
   `level endon("game_ended")` with the comment *"match end tears it down"*. It does
   `waittill("gf_round_over")` → `wait 0.5` → `gf_boundaryPass()` — so it was **killed during that 0.5s
   wait**, at the first round end, before ever running a pass. And `_bot::init` is gated **once per match**
   (`game["gf_botInit"]` in `gf.gsc`), so nothing re-threaded it. **Net: the boundary pass never once ran at
   a boundary.** The only pass that ever executed was the one-shot `gf_matchStartPass`, which is why the
   fill *looked* fine on an empty server (N bots/side) and then never adapted: humans joining later were
   never counted against the per-team target, so a side sat at **N bots + humans, forever**. Reported as
   "bot fill is ignoring humans". Fix = drop the endon; `gf_matchIsOver()` already skips the final round
   and `bot_reinit` already collapses re-inits.

**The lethal combination is `endon("game_ended")` + a once-per-match thread gate.** Either alone is
survivable; together, the thread dies at round 1 and *nothing ever brings it back*, and the failure is
silent — the system keeps whatever state it had at match start, so it looks configured-but-stale rather
than crashed.

**Counter-example (a legit use):** `gf_gateListener` in `_bot.gsc` *keeps* the endon deliberately — dying
at round 1's end is what confines it to the match-start gate, since `gf_load_gate_reset` also fires every
round. Both readings are load-bearing somewhere, so **read each thread's intended lifetime before
touching its endon**.

Related: [[gsc-notify-kills-the-notifying-thread]] (a notify kills the thread that fires it),
[[onstartgametype-perround-thread-accumulation]] (why the once-per-match gates exist at all),
[[gf-fill-reconciler-and-team-transfer]] (the reconciler this broke).
