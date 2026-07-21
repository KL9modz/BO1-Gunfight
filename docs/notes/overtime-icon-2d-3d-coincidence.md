---
name: overtime-icon-2d-3d-coincidence
description: T5 OT zone — 2D minimap and 3D flag icon coincide ONLY when driven from the same native _gameobjects path (matched compass_waypoint_X / waypoint_X)
metadata: 
  node_type: memory
  type: project
  originSessionId: 1c5dc0eb-3c55-46a6-8529-bc74aa357f15
---

The OT capture-zone minimap icon and the icon above the flag mismatched intermittently for a long time. Root cause: they were **two different systems** — the 2D minimap was native `_gameobjects` (`set2DIcon` + `setOwnerTeam`), the 3D icon was a custom `newTeamHudElem` with hand-set RGB (`level.gf_ot_wi_*` / `gf_updateOvertimeWorldIcons`). Two systems = guaranteed drift; they only agreed when your own team captured.

**Fix (proven, matches dom.gsc):** drive BOTH from the same native path. `gf_setOvertimeZoneIcons(zone, friendlyIcon, enemyIcon)` sets `set2DIcon("friendly","compass_waypoint_"+X)` + `set3DIcon("friendly","waypoint_"+X)` (and same for enemy). Same artwork in 2D vs 3D form → colors coincide *by construction*, no RGB to sync. The custom 3D element was deleted entirely.

**Color mapping (dom convention — do not reverse):** `setOwnerTeam(capturingTeam)` routes the capturer into the "friendly" slot. friendly → `defend` (renders GREEN/owner), enemy → `capture` (renders RED), idle/contested → `captureneutral` (white). The old bug "my team shows RED when capturing" was because the mapping was reversed (`friendly→capture`). Keep **friendly→defend, enemy→capture**.

**Hard engine limit (why the apron can't do this):** `spawnFx` apron is world-space — rendered identically for every player, no per-team visibility. So team-relative green/red can ONLY live on the team-routed icon/objpoint elements, never on FX. The apron is an absolute cue (white idle / gold capturing / red contested).

Meta-lesson (why this finally worked after many tries): the fix came from READING the stock engine source (`_globallogic.gsc`, `_gameobjects.gsc`, `dom.gsc`) to find the real mechanism, not from iterating on asset swaps or theories. An inherited summary had the wrong root cause; verifying against actual code beat trusting it. Related: [[onprecache-once-per-match-loadfx-wiped]].
