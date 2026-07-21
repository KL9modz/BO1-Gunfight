---
name: spawn-wrong-facing-usestartspawns-gate
description: "FIXED 2026-07-01 (commit 4a2ed34, pending in-game verify) — wrong-facing spawns: curated spawns were gated behind level.useStartSpawns; small mode now short-circuits onSpawnPlayerUnified -> onSpawnPlayer. Bonus: curated branch now sets lastSpawnTime/lastSpawnPoint (undefined aborted stock grenade damage callback)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 68aa8aea-e95c-45db-a8bc-1bbee17ea041
---

Root cause of the open TODO "sometimes spawn facing wrong direction" (diagnosed 2026-07-01, adversarially verified via multi-agent workflow).

The curated, fight-facing gunfight spawns (`gf_getCustomSpawnPoint`, `gf_sp` yaw in `_gf_locations.gsc`) run ONLY when the engine flag `level.useStartSpawns == true` at spawn time. Because the gametype string is `gf` (not `sd`), the SD force-curated branch in stock `_spawning.gsc:927-930` never fires, so once `useStartSpawns` is false the stock UNIFIED scored-spawn system (`getSpawnPoint` → `self spawn(origin, angles)`, `_spawning.gsc:940/948`) places the player at a generic `mp_tdm_spawn`/`mp_wager_spawn` entity yaw NOT aimed at the fight. Nothing re-aims after spawn().

`useStartSpawns` lifecycle: set true each round at level init (`_globallogic.gsc:1752`, re-runs on map_restart), flipped false by (a) first enemy damage that round (`_globallogic_player.gsc:978`) and (b) the mod's own `onSpawnPlayerUnified` at `gf.gsc:484` on the first spawn resolving after grace ends. Never re-asserted → the first mis-routed spawn latches every later spawn that round onto the generic-angle path until next map_restart.

Why NORMAL spawns are fine: the round-start respawn wave happens during prematch+grace (`inGracePeriod==true`), which both allows the spawn AND suppresses the gf.gsc:484 flip → curated path. Why it's VERY OCCASIONAL: one-life-per-round means almost no spawns see a false flag. The exposed ones are async/late: bot-fill connects landing after the ~10s prematch(7s)+grace(3s) window, late human joiners slipping through `maySpawn`'s spectator hold while `gameHasStarted` is still false, and 60s `forceSpawn` timeouts. Bots self-correct (SetBotGoal path-aim) so the persistent symptom skews HUMAN.

Ruled out (checked directly): `switchedsides`/halftime mapping is CORRECT — each cluster's `gf_sp` points face the OPPOSING cluster, so swapping spawnTeam to the enemy's old cluster still points at the relocated enemy regardless of map symmetry (verified mp_villa/mp_cairo/mp_cosmodrome). Also ruled out: curated angle-data errors, `getSpawnpoint_NearTeam` sub-fallback (uncurated maps only), killcam/intermission/tactical-insertion/demo-point paths.

FIX APPLIED 2026-07-01, commit 4a2ed34 (pending in-game verify): `gf.gsc::onSpawnPlayerUnified` short-circuits small mode to `self onSpawnPlayer(); return;`. Keeps large mode's unified anti-spawn-kill scoring; makes small-mode facing independent of `useStartSpawns`. Verified by 3-lens adversarial workflow (pipeline coverage / callee safety / mode lifecycle), zero refutes.

BONUS BUG found+fixed in the same commit: the curated-spawn branch never set `self.lastSpawnTime`/`self.lastSpawnPoint` (stock `_spawnlogic::finalizeSpawnpointChoice` sets them, but curated spawns bypass the stock selectors). Stock `_globallogic_player.gsc:783` does UNGUARDED `self.lastSpawnTime + 3500` and `self.lastSpawnPoint.origin` on grenade/gas-classed damage → undefined aborted the whole damage callback, silently VOIDING grenade damage against curated-spawned players all round. Fixed by setting both at curated spawn (script_origin stands in for the spawnpoint entity; map_restart reaps it). Related: [[gf-timer-prematch-and-pause-model]].
