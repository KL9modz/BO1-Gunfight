# `refactor/tier1` — laptop compile + smoke checklist

**Status: not yet run.** This branch (12 commits, `2157485..c73d76d`) was developed and
reviewed on a box with no map-load capability (no GitHub credentials, and touching the
live server was off-limits — see `.claude/CLAUDE.md`). Every commit passed
`tools/verify_release_strip.ps1` (static symbol-resolution proof) and an independent
review pass re-derived the risky transformations by hand (predicate boolean equivalence,
seed-pair diffs, bot-preset-table diffs, spawn-coordinate-tuple diffs — see the review
notes in the PR/commit history). **None of that substitutes for a real compile.** This
file is the gate before merging to `main`.

## 1. Pull the branch

```powershell
git fetch <path-to-bundle-or-remote> refactor/tier1:refactor/tier1
git checkout refactor/tier1
```

## 2. Compile pass — GSC loads as loose rawfiles, so this is just a map load

Two builds to check, because Tier 1 touched strip-marked regions in every GSC file:

- **Dev tree** (this checkout, dropped into
  `%localappdata%\Plutonium\storage\t5\mods\mp_gunfight\`): `loadMod mp_gunfight` +
  `map_restart` in the Plutonium console. Watch `console_mp.log` for `unknown function`
  or any GSC compile error — those are the two failure modes item 8/9's restructuring
  and item 10's table could introduce (a missed `#include`, a dropped strip marker, a
  function-size limit on `gf_locationsTable()`, which is now the largest single
  function in the mod at ~550 lines).
- **Public (stripped) build**: run `tools\package_release.ps1`, then point a *second*
  local server at the unzipped output and `loadMod` + `map_restart` that. This is the
  only way to actually load-test the strip regions — `verify_release_strip.ps1` proves
  symbol resolution statically but never parses the GSC.

Pass condition: both loads reach the pregame/prematch with **zero** `unknown function`
or other compile errors in `console_mp.log`.

## 3. Behavioral smoke (dev build, one match, `party_minplayers 1`, a few bots)

Targets the specific restructures in this branch — not a full regression pass:

- [ ] **Round cycle**: at least 2 rounds complete normally (win by elimination, win by
      timeout/HP). Exercises the decomposed `onStartGameType` (item 8) — if a stage
      helper's local variable leaked or an order dependency broke, this is where it
      shows (e.g. team mode / loadout / spawn setup happening in the wrong sequence).
- [ ] **Team-write predicates** (item 1, `gf_isHuman`/`gf_isRealBot`/`gf_holdsSeat`):
      add/kick a bot from the RCON panel, let the reconciler run a boundary pass. Watch
      `logs\games_mp.log` for `GF_TEAMTRACE`/`GF_FILLGUARD` lines — team sizes should
      settle exactly like they did on `main`, no phantom bot count drift.
- [ ] **Panel team moves** (item 2, `gf_setTeamFields`; item 9, the `gf_maySpawn_*`
      guard stages): use the panel's `pteam_` (next-round move) and `pteamforce_`
      (immediate) on a human. Confirm no "spawned at the enemy spawns" or "spawned
      with 1 HP" — that bug class is exactly what the stamp-then-write ordering and
      the maySpawn guard order are load-bearing for.
- [ ] **Self team-switch**: a human clicks Allies/Axis mid-round. Confirm the
      sequenced move (die + sit out, or free during prematch) still works.
- [ ] **Bot difficulty** (item 4, the preset table): `botdiff_fu` / `botdiff_hard` /
      `botdiff_easy` / `botdiff_normal` from the panel; confirm bots visibly change
      behavior (aim speed / reaction time) and `gf_state` field 12 reports the right
      preset.
- [ ] **Spawn recorder round-trip** (item 10 — the actual codegen contract): set
      `gf_debug_spawns 1`, stand somewhere on any CURATED map (e.g. `mp_villa`),
      press ActionSlot3. Confirm the printed block in `games_mp.log` matches the
      `gf_locationsTable()` entry format (`// mapname` / `e = gf_locMapEntry();` /
      `e["sets"][...] = set;` / `e["ot"] = gf_ot(...)` / `t["mapname"] = e;`) — this
      is the one place a format mismatch between the table and the recorder would be
      silent until someone tries to paste a new map in.
- [ ] **Curated spawns still curated**: play a round on a curated small-mode map
      (e.g. `mp_villa`, `mp_cracked`) and confirm spawns are still the fight-facing
      curated points, not the stock `mp_tdm_spawn` pool — proves the table lookup in
      `gf_getCustomSpawnLocations`/`gf_getCustomOvertimeLocation` (item 10) actually
      returns the right map's data.
- [ ] **Flinch/tick feel unchanged** (item 6, single-sourced constants): no specific
      test beyond "does it feel like the same 0.5-scale flinch and the same countdown
      beep" — the change was pure constant deduplication, not a value change.

## 4. Panel smoke (`tools/rcon/` — items 7a/7b/7c)

- [ ] Open the panel against the local server. DASHBOARD tab loads live status.
- [ ] FAVORITES tab renders the pinboard; pin/unpin a row.
- [ ] Click 💾 Save on any dvar row — confirm it writes to `dedicated.cfg` (the
      `/api/savecfg` → `readJsonBody`/`handle` path, item 7b).
- [ ] BOTS tab: Add Bot / Kick All / difficulty buttons all still work (exercises
      `postJSON`, item 7c, and confirms nothing in the deleted `/api/gfstate`/
      `/api/gfroster` endpoints was actually needed — the panel should read that
      telemetry through `/api/tick` only).

## 5. If anything fails

Each of the 12 commits passed `verify_release_strip.ps1` independently and is scoped
to one restructure — `git bisect` across `2157485..refactor/tier1` will isolate the
breaking commit quickly. The commit messages name the exact transformation each one
made, so once bisect lands on a commit the fix should be obvious from its diff.

## 6. On pass

Merge `refactor/tier1` → `main`, push, deploy through the normal pipeline whenever
convenient — nothing on the VPS or `C:\gfdeploy` changes until a deploy is run.
