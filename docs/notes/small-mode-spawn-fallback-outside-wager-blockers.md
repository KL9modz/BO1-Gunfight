# Small-mode curated-miss fallback spawned players OUTSIDE the wager blockers — the in-bounds pool is `mp_wager_spawn`

**Symptom (live reports, 2026-08):** in small mode a player occasionally spawned outside the sealed
wager play area — free to roam the full map (or stuck behind the blockers) on a round where everyone
else was fighting inside the arena.

## Root cause

Small mode's spawn chain in `gf.gsc onSpawnPlayer` was: curated point → **`mp_tdm_spawn_<team>_start`**.
The curated picker (`_gf_locations::gf_getCustomSpawnPoint`) legitimately returns `undefined` when every
curated point is telefrag-occupied — reachable ever since a small-mode side could hold **6 bodies on 5
curated points** (team size 5-6, a 4v4-human + late-seat round, or an admin forcing
`scr_gf_teamspawnmode small` on a crowded server via RCON). The fallback pool was the problem: on a
wager-blocker map the **TDM start points sit OUTSIDE the baked blockers** (`script_gameobjectname
"gun oic hlnd shrp"` ents, kept in small mode to seal the arena), so the overflow spawner landed out of
bounds. The three miss reasons (`full:<n>` / `noteam` / `nodata`, stamped in `level.gf_customSpawnMiss`)
all took the same escape hatch.

## Fix — fall back to the map's own `mp_wager_spawn` pool, never TDM starts

The wager gametypes (gun/oic/hlnd/shrp) spawn on `mp_wager_spawn` entities, which are **inside the
wager play area by construction** — and small mode already registers + inits that pool in
`onStartGameType` (`addSpawnPoints`), so `getSpawnpointArray("mp_wager_spawn")` returns inited points at
spawn time. The chain is now: curated → **wager pool** → TDM starts.

- Selector: **`getSpawnpoint_NearTeam`** — telefrag-aware (`getSpawnpoint_Final` /
  `getBestWeightedSpawnpoint` both skip `positionWouldTelefrag` points) and biased toward the teammates
  already standing on the curated points, so the overflow spawn lands on the **right side** of a shared
  (team-neutral) pool. The old "never NearTeam on a shared pool" caveat was about the full-map TDM pool
  with no teammates placed yet; here ≥5 teammates are provably already standing in the arena (that is
  what "full" means), so the bias has an anchor.
- `finalizeSpawnpointChoice` runs inside `getSpawnpoint_Final`, so `lastSpawnTime`/`lastSpawnPoint`
  (the fields stock `Callback_PlayerDamage` does unguarded grenade-protection arithmetic on) are set for
  free on this path — no manual stamping like the curated branch needs.
- **TDM starts survive only for maps with no wager pool** — and a map with no `mp_wager_spawn` ents has
  no baked blockers either (`tools/wager_entities/` ⊂ `tools/wager_spawns/`), so there is no sealed
  boundary to escape there; the fallthrough is safe by construction.

## Rules

- ⚠ **Small mode must never route a spawn to `mp_tdm_spawn*` on a map that has a wager pool.** Any new
  spawn path (late spawn, admin move, future modes) added to small mode must go curated → wager pool.
- ⚠ Still never force the curated point itself on "full" — spawning ONTO an occupied point telefrags the
  frozen occupant (the original raw-cursor bug).
- The `GF_SPAWNMISS` diagnostic (`_gf_debug::gf_logCuratedSpawnMiss`) still fires on every curated miss;
  a `full:<n>` line now means "landed on the wager pool", not "out of bounds".
