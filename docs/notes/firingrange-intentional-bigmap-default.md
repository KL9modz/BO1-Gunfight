---
name: firingrange-intentional-bigmap-default
description: "mp_firingrange is INTENTIONALLY left uncurated in _gf_locations.gsc — it uses tdm/big-map defaults in both team modes by design, not a forgotten omission."
metadata: 
  node_type: memory
  type: project
  originSessionId: afe51c37-ce6c-4fbf-aaad-a67d6dc80cb5
---

`mp_firingrange` (Firing Range, base map, IS in the live sv_maprotation) has NO
`gf_spawnSet()` block and NO `gf_ot()` overtime flag in `_gf_locations.gsc`. This is a
deliberate decision (user, 2026-06-26): "for firing range we are just going to use big map
defaults for small map too as is." Do NOT treat it as a missing map to record/curate.

**Why this works with zero code change — small mode == large mode for this map.** Every
small-mode special-case is gated on data firing range doesn't have, so it degrades to the
large/big-map path automatically:
- spawns: `gf.gsc` small branch uses `mp_wager_spawn` only if those ents exist; firing range
  has none → falls back to `mp_tdm_spawn` (same as large).
- curated set: `gf_getCustomSpawnPoint` returns undefined when `sets.size <= 0` → tdm points.
- wager minimap: `gf_applyWagerZoneAssets` early-returns when `wagerSpawns.size <= 0`.
- blockers: no baked `gun/oic/hlnd/shrp` ents, so keeping them in the allow-list is a no-op.
- OT flag: `gf_getOvertimeFlagTrigger` only relocates if `gf_customOvertimeLocation` is
  defined → undefined here → native Domination B flag (same as large).

So if you ever want a map to use big-map defaults regardless of team size, the established
pattern is simply: leave it out of `_gf_locations.gsc`. See [[gf-timer-prematch-and-pause-model]]
for related team-mode (`level.gf_largeMode`) context.
