---
name: infinite-round-orphaned-killcam-flag
description: "The 2026-07-11 infinite round = an orphaned player .killcam flag pinning _killcam::areAnyPlayersWatchingTheKillcam() true forever, which blocks map_restart inside the stock round-end sequence. The engine's own cleanup net is DEAD CODE on this path (it waits on \"game_ended\", already fired)."
metadata: 
  node_type: memory
  type: project
  originSessionId: 2bcb62a0-0866-4ca6-aabb-4fd3c62c1e6d
---

**The stock round-end sequence can deadlock forever, and the engine has no net for it.**

Observed 2026-07-11 on the VPS (`mp_kowloon`, 6 humans + bots): a human (`matzues`) disconnected
mid-round, the round ended on a team wipe, a fill bot connected 0.5s later — and the match then sat in
**one round forever**. Server was perfectly healthy the whole time: ~9% CPU (sampled 0.94s CPU / 10s —
NOT a busy loop), still accepting joins. `games_mp.log` just stops: no `ShutdownGame`, no `InitGame`.
Had to be resumed by hand.

**The mechanism (all stock, all in `raw/maps/mp/gametypes/`):**

`_globallogic::endGame` → `startNextRound` → `displayRoundEnd` → **`executePostRoundEvents()`** →
`_killcam::postRoundFinalKillcam` → `finalKillcamWaiter()` — and only THEN `map_restart(true)`
(`_globallogic.gsc:803` … `:836`). It is all **synchronous**. `finalKillcamWaiter()` spins while
`level.inFinalKillcam`, which clears only when `_killcam::areAnyPlayersWatchingTheKillcam()` goes
false — and that returns **true if ANY player merely has `.killcam` DEFINED** (`_killcam.gsc:89-100`).

`self.killcam = true` is set in `_killcam::finalKillcam` (`:496`) and cleared **only** by `endKillcam()`
off the `"end_killcam"` notify (`self.killcam = undefined`, `:300`). So **one client with an orphaned
`.killcam` blocks `map_restart` forever.**

**Why nothing recovers — two dead nets:**
1. `_killcam::endedFinalKillcamCleanup()` is the engine's force-clear, but it does
   `level waittill("game_ended")` — and `endGame` fires `game_ended` at `_globallogic.gsc:924`, i.e.
   **seconds BEFORE the final killcam even starts** (`play_final_killcam` is notified later, past
   `roundEndWait`). It waits for a notify already in the past. **Structurally dead on this path.**
2. The mod's `gf_roundWatchdog` carries `endon("gf_round_over")` — it **retires at the exact instant
   this hazard opens**. Nothing watched the post-round path.

The same sequence's other unbounded gate: `_globallogic::roundEndWait` spins while any player has
`.doingNotify` true (`:1067-1105`) — orphanable the same way.

**Fix (2026-07-12):** `_gf_rounds::gf_postRoundWatchdog`, threaded from `gf_endRound` **before**
`endGame` (endGame fires `game_ended` within a frame). It is gen-token retired (`gf_roundGenChanged`),
**must NOT carry `endon("game_ended")`**, and must stay armed on the last round too (the same waiter
gates the match-end podium). After 20s it clears orphaned `.killcam` / `.doingNotify` and **logPrints
which client and which flag** (`GF_ENDWATCH:`) — that log line is the diagnostic that will finally
identify the leaking client, which the log alone could not.

⚠ **Open:** WHICH client orphaned `.killcam` is still unproven. `finalKillcam`'s only live endon is
`self endon("disconnect")`, and a disconnected player leaves `level.players` (so shouldn't block) —
yet `matzues` leaving again did NOT unstick it, so the leaker was a client that STAYED. Prime suspect
is the fill bot added into the killcam window by `_bot::gf_boundaryListener`
(`waittill("gf_round_over"); wait 0.5;` → `add_bot()`), because `startLastKillcam` snapshots
`level.players` **after** `play_final_killcam` and threads `finalKillcam()` on everyone in it — including
a client that connected in between and has never spawned. **Not proven** — deferring the adds was
rejected as the fix because `level.inFinalKillcam` stays true right up until `map_restart`, so gating
adds on it would mean they never run at all (it would break the fill).

**Immediate mitigation if it recurs before a deploy:** `gf_fill_n 0` (reconciler inert → no
`addtestclient()` at the boundary). See [[gf-fill-reconciler-and-team-transfer]],
[[round-freeze-activation-race-and-rails]] (the *other*, in-round freeze — different bug, same
"engine still running, round never ends" signature).
