---
name: onprecache-once-per-match-loadfx-wiped
description: "T5 round games — onPrecacheGameType runs once per match, map_restart wipes level.* so loadfx handles die after round 1"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1c5dc0eb-3c55-46a6-8529-bc74aa357f15
---

In the Gunfight round structure, `level.onPrecacheGameType` runs **exactly once per match**, not once per round. It is guarded in `_globallogic.gsc` by `if ( !isDefined( game["gamestarted"] ) )` (line ~1601) which sets `game["gamestarted"] = true` immediately after calling it; `game[]` survives `map_restart`, so the guard blocks all re-runs.

Between rounds, `_globallogic::endGame` calls `map_restart( true )` (line ~836), which **wipes every `level.*` var**. Net effect: any asset handle stored in `level.*` from inside `onPrecacheGameType` (e.g. `level.x = loadfx(...)`) is valid in round 1, then becomes `undefined` for round 2+ — and is never re-established.

**Symptom:** a precached visual/FX works on the first round only, silently vanishes afterward. Easy to misdiagnose as an FX-session-pool / ShutdownGame issue (it is NOT — there is no ShutdownGame between rounds, only map_restart).

**Fix:** call `loadfx()` again at runtime, at the point of use that re-executes every round (for OT this is `gf_createOvertimeZone`). `loadfx` re-registers the handle into the fresh post-restart `level` fx list. This is how the OT apron FX (`gf_loadOvertimeApronFx()`) was fixed — called both at precache and on every OT entry.

Applies to anything: `loadfx`, and any other handle/index cached in `level.*` during precache. Store in `game[]` instead, or re-acquire at runtime each round. See [[reference_t5_mp_weapons]] for the broader T5 asset notes.
