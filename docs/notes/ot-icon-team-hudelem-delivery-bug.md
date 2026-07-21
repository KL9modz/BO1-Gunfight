---
name: ot-icon-team-hudelem-delivery-bug
description: Proven T5 engine bug — newTeamHudElem (OT flag objpoint) not delivered to a client when another client connects mid-round; server state healthy; user chose to keep native path
metadata: 
  node_type: memory
  type: project
  originSessionId: 3de94378-8209-4c75-97c6-903afb220b96
---

The rare "no capture icon above the OT flag" bug is a T5 engine **client-delivery** failure of `newTeamHudElem` elements, NOT a script bug. Proven 2026-06-12 via side-by-side `games_mp.log` evidence (mp_cracked sessions): in the failing match (bot added mid-round) and the working match (bot added pre-round), the server-side objpoint state was bit-for-bit identical — `objpointAllies=1 objpointAxis=1`, `alpha=0.5 shown=1`, same x/y/z — yet the client rendered nothing in the failing case.

**Repro:** start a round with only 1 player spawned, add a bot mid-round, reach OT → icon missing. Populate both teams before round start → icon works.

**Why:** correlated with a client (testclient/bot counts) connecting mid-round — engine snapshot/team-mask bookkeeping; unfixable from GSC on the native objpoint path.

**A working replacement existed and was reverted by user preference:** per-player `newClientHudElem` + `setWaypoint(true,true)` waypoints driven by `level.gf_otIconState` (same migration pattern that fixed the health HUD). User said "I liked how it was before" — native objpoints restored. If the bug needs killing later, that replacement is in git history just before the revert (look for `gf_runOTWaypoint` in `_gf_rounds.gsc`, ~2026-06-12).

**Mitigation in use:** populate teams before round start (e.g. `bots_manage_fill` pre-fill) instead of adding bots mid-round.

**Diagnostics kept in code:** `GF_OT: zone created entNum=... objpointAllies/Axis` and `GF_OT: iconstate ...` logPrints in `_gf_rounds.gsc`; mod log lives at `mods/mp_gunfight/games_mp.log` (NOT `main/games_mp.log`).

Related: [[onprecache-once-per-match-loadfx-wiped]]
