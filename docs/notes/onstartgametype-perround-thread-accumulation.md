---
name: onstartgametype-perround-thread-accumulation
description: Persistent loops threaded from onStartGameType accumulate one copy per round because map_restart re-runs onStartGameType but does NOT kill surviving threads; guard them or they stack all match
metadata: 
  node_type: memory
  type: project
  originSessionId: 6244dcc7-e9ff-4fba-8a45-02bcb0793107
---

GF trap class (found 2026-07-03 via the "bots keep adding more every match" bug). Two facts combine:
(1) `onStartGameType` re-runs on EVERY round — stock `_globallogic::startNextRound` cycles rounds via `map_restart(true)` (raw `_globallogic.gsc:836`), and the StartGameType callback re-invokes `[[level.onStartGameType]]()` (`:1880`) each time. `onPrecacheGameType` is behind the `game["gamestarted"]` guard (`:1686`) so it's once-per-match, but onStartGameType is not.
(2) GSC threads SURVIVE `map_restart(true)`. `game_ended` fires ONLY in `endGame()` at true match end (`_globallogic.gsc:924`), never on a round transition. Proof the author knew this: the mod's own round clock endons BOTH `"game_ended"` AND `"gf_round_over"` (`_gf_rounds.gsc`), and `_gf_hud.gsc:38-40` uses the "Singleton HUD kill pattern" (`level notify("gf_restart_health_hud"); level endon(...)`) — pointless if map_restart already killed threads.

=> Anything threaded from onStartGameType that starts a persistent `for(;;)`/`waittill` loop with ONLY `level endon("game_ended")` (or no endon) stacks a NEW copy every round and they all run until match end.

**Why:** by round R of a match there are R concurrent copies. For bots this stacked R `addBots()` fill loops racing on the shared `bots_manage_add` dvar (async bot connect lag → each loop re-consumes the deficit before new bots are counted → OVER-add past `bots_manage_fill`; `fill_kick=false` never trims it, and a leftover positive `bots_manage_add` survives to the next match since `_bot::init` only defaults it when empty → ratchets up "every match"). NOTE: `addBots` is a *convergent* controller (targets absolute count vs fill), so it's a bounded overshoot/ratchet, not infinite multiplication. The `handleBots` reconciliation tail (`_bot.gsc:121-124`) is unreachable dead code — `addBots()` is called blocking and its `game_ended` endon kills the whole thread there.

**How to apply:** two guard idioms, pick by whether the function is *meant* to re-run each round:
- Once-per-MATCH (e.g. bot manager, which should bootstrap once): gate the thread call on a `game[]` flag (`game[]` survives map_restart, resets on a genuine new map). Mirrors `gf_rocketOncePerMatch` / `game["gf_init"]`.
- Re-run each round but kill stale watchers (e.g. `gf_bridgeInit`, which MUST re-run to apply pending RCON team moves): `level notify("<x>_reinit"); level endon("<x>_reinit")` singleton pattern.

**Status:**
- FIXED 2026-07-03: `_bot::init()` — `gf.gsc` onStartGameType now gates `thread _bot::init()` behind `if(!isDefined(game["gf_botInit"]))` + `setDvar("bots_manage_add",0)` (inside the existing `#strip-begin/#strip-end` dev block, so release builds still strip it). See [[gf-timer-prematch-and-pause-model]].
- FIXED 2026-07-10: `gf_bridgeInit`. The interim fix had been a `game["gf_bridgeInit"]` guard (thread `gf_bridgeTelemetry`/`gf_bridgePoll`/`gf_bridgeWatchPendingTeam` once, skip while game[] survives). That guard was fragile the OTHER direction: after `game_ended` kills those loops, a match that restarts on a game[]-PRESERVING path (same-map cycle / lobby fast-restart) left the guard set and the loops **DEAD FOR GOOD** — this is what broke the RCON "remote scoreboard": on the live VPS `gf_state` was pinned at its 6-field seed (`0:0:1:0:0:gf`, fillN null) and `gf_ack` never advanced (whole bridge — telemetry, gf_roster team-grouping, AND the gf_cmd command poll — silently dead). Diagnosed by reading the VPS `gf_state` via the panel API and a sentinel-overwrite that was never reclaimed; NO GSC runtime error in console_mp.log (the loops simply never ran). Fix = switched to the **`_bot::init` `bot_reinit` idiom**: removed the game[] guard, `level notify("gf_bridge_reinit")` at the top of the thread block, re-thread all three unconditionally every round, each loop carries `level endon("gf_bridge_reinit")` (+ its existing `game_ended`). Collapses survivors to exactly one live set per round AND self-heals a set that died at match end. `gf_bridgeVisionPersist` left alone (one-shot, returns). GSC-only → ships via `deploy.ps1 -Mod` (no mod.ff rebuild). LESSON: prefer the collapse-notify idiom over a game[] guard for any onStartGameType-threaded persistent loop that can outlive its game[] flag. See [[rcon-connect-sweep-unknown-cmd-spam]].
