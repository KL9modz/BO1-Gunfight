---
name: stock-teamswitch-suicide-no-life-restore
description: "Stock team switch (menuAllies/menuAxis) suicides a \"playing\" player but never restores pers[\"lives\"] → maySpawn denies the respawn once both teams have existed → player spectates the round dead"
metadata: 
  node_type: memory
  type: project
  originSessionId: a2589459-bc5d-4f25-87e9-7af6079fc4e7
---

**"Players sometimes start round 1 dead" after a lobby→match team transfer** — FIXED 2026-07-10 (pending in-game verify).

Root cause is an engine trap in the stock team switch used to re-seat players:
- `[[level.allies]]()` / `[[level.axis]]()` = stock `menuAllies`/`menuAxis` (`_globallogic_ui.gsc`)
  `suicide()`s a `sessionstate=="playing"` (prematch-frozen but ALIVE) player, then relies on
  `beginClassChoice()` (scr_disable_cac=1 auto-spawn) to respawn them. **The switch NEVER restores
  `self.pers["lives"]`**, which the suicide dropped to 0.
- `maySpawn()` (`_globallogic_spawn.gsc:41`) then blocks the respawn:
  `if ( !self.pers["lives"] && gameHasStarted ) return false;` where
  `gameHasStarted = level.everExisted["axis"] && level.everExisted["allies"]`
  (`everExisted[t]` is set by `updateTeamStatus` the moment team t has an alive player).
- On denial, `spawnClient` bounces the player to **spectator with NO retry** (`_globallogic_spawn.gsc:581`)
  → dead the whole round. Self-heals round 2 because `map_restart(true)` resets `pers["lives"]=numLives`.

**Intermittent** because it only bites once BOTH teams have had an alive player this prematch. Early
movers (before both sides populated) respawn fine; the rest spectate. That's why a lobby re-seating
several humans at once shows it but a single admin move usually doesn't.

Fix (original, 2026-07-10) = `gf_reseatRespawn()`: a ~1s guard threaded after the stock switch that
restored `pers["lives"] = level.numLives` and re-drove `[[level.spawnClient]]()` if the deny bounced.

**2026-07-16: `gf_reseatRespawn` is DELETED — absorbed into `_gf_rounds::gf_seqTeamMove`**, the
sequenced move primitive that now handles EVERY "playing"-player move (suicide → wait for the death
to settle → quiet reassign → restore life → drive respawn, with the same prematch-bounded retry loop
as its tail). The old stock-switch-then-recover pair raced the suicide's async death against the
respawn — that race was also the rare "spawned at enemy spawns / spawned at 1 HP" post-move bug.
DON'T force `hasSpawned=false` in the recovery — the player already spawned this prematch, which
satisfies maySpawn's gate B; zeroing it re-trips B once grace has closed.

RULE: never move an already-spawned player via the raw stock switch; use `gf_seqTeamMove`, which owns
the life restore (or the deferred `pers["gf_movePending"]` pre-spawn mark for killcam survivors).
