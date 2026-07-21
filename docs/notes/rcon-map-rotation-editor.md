---
name: rcon-map-rotation-editor
description: "RCON panel Maps tab is a live sv_maprotation editor (reorder/save/play-next) that drives the engine's own rotation; replaced the reactive browser queue. Plutonium T5 exposes + honors rcon writes to sv_maprotation AND sv_maprotationcurrent"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6239e750-2f05-451b-aee2-af0f2e52bbf5
---

Built 2026-07-07 (pending in-game behavioral verify). Fixes the CLAUDE.md TODO "the auto queue maps
behaivor is odd" / "auto que happens too late".

**Root cause of "too late":** the old Maps tab was a browser-side `mapQueue` + `autoQ` that, on
detecting `status` map changed, REACTIVELY fired `map <id>` — so the engine's own `sv_maprotation`
loaded its next map FIRST (wrong-map flash), then the panel corrected it (double load). It raced the
engine instead of driving it.

**New design (`tools/rcon/`):** read + edit the LIVE `sv_maprotation` directly.
- `GET /api/maprotation` (server.js) reads `sv_maprotation;sv_maprotationcurrent` in one send;
  `parseMapRotation()` → `[{gametype,map}]`.
- Maps tab renders an ordered editor: ↑↓ reorder, ✕ remove, click a grid tile to add. Current map
  gets a **● LIVE** highlight (from `d.map`), the next map a **NEXT** badge.
- **Save Order** writes BOTH `sv_maprotation` (template) AND `sv_maprotationcurrent` (= order after
  the current map) so the new order takes effect on the very next rotation — one clean engine load,
  no flash. **⏭ Play next** writes `sv_maprotationcurrent = slice(i)` (loads on match end). **▶ Load
  now** = hard `map <id>`. **Save to cfg** upserts `sv_maprotation` into dedicated.cfg (persist).

**Load-bearing facts (verified live against the local Pluto T5 dedi 2026-07-07):**
- `sv_maprotationcurrent` EXISTS and is populated on this build; it's the not-yet-played REMAINDER —
  its HEAD is the next map the engine loads at match end (`exitLevel`→`map_rotate`). Confirmed by
  observing it = the tail of `sv_maprotation`. Both dvars are plain server dvars: rcon `set` on them
  persists byte-exact (read-back proven) — NOT cheat-gated, works on the dedicated VPS.
- Editing only `sv_maprotation` defers the change a whole cycle (engine drains `current` first) —
  that's why Save writes `current` too.
- Rotation grammar tolerates the **bare `map X map Y`** form (no `gametype` tokens — inherits
  `g_gametype`); the local dedi's rotation was bare. `buildRotStr` OMITS `gametype` when empty so the
  bare form round-trips (don't emit `gametype  map X`). The shipped dedicated.cfg uses the explicit
  `gametype gf map X` form.
- The local `sv_maprotation` value carried stray **0x93/0x94 (Win-1252 smart-quote)** bytes from a doc
  paste that dropped/corrupted maps; `parseMapRotation` sanitizes each token to `[A-Za-z0-9_]`. A
  clean Save would fix it (we don't auto-rewrite live state).
- `savecfg` value cap raised 256→1024 (a 26-map rotation is ~600 chars; the injection guard is the
  `" \r \n ;` strip, not the length).

**To activate:** restart `node server.js` (new endpoint) + reload the browser (index.html served
no-cache). Panel runs local 127.0.0.1:3000 → VPS. See [[rcon-tool-vps-connect-23char-cap]],
[[rcon-panel-queue-saturation]].
