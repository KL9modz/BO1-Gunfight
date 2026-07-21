---
name: settext-configstring-exhaustion
description: "T5 setText burns engine string-table slots that survive map_restart; per-tick setText overflows it over a session, then ALL setText calls throw and kill threads. Use setValue for numbers; menu+dvar for per-player HUD."
metadata: 
  node_type: memory
  type: project
  originSessionId: 3de94378-8209-4c75-97c6-903afb220b96
---

**T5 `setText` exhausts a finite engine string table that survives `map_restart`** — only a full server-process restart clears it. Per-tick `setText` (HP numbers at 10/s, debug overlays with unique composite strings every 0.1–0.2s) fills the table over a session. Once full, **every** `setText` throws a script error that kills the calling thread — symptom: HUD creation threads die partway, leaving partial chrome at creation alphas, never updated/revealed, getting worse as the session ages. Diagnosed 2026-06-12 (self health bar "saw part of it one round, then nothing"; strip screenshot = border+bg only, death at `setText(self.name)`).

**Rules:**
- Numbers → `setValue()` (engine numeric path, zero string usage). Proven everywhere in this mod.
- Unavoidable `setText` (e.g. player names) → call once, in an isolated throwaway thread so an overflow kills only that label.
- Debug overlays with live composite text readouts (`gf_debug_hud_pool`, coords HUD) are the biggest burners — short-session tools only.
- `GF_HUD: panel built ... elems=N` checkpoint logPrint in `gf_createHealthPanel` — its absence after a spawn means a creation thread died.

**The robust pattern for per-player HUD (used by the self health bar):** menu-rendered via `ui_mp/hud_gf_health.menu` (in mod.ff) — itemDefs with `exp text(dvarString("ui_gf_self_hp"))`, `exp rect W(dvarInt(...)*1.2)`, `visible when(dvarInt("ui_gf_self_show"))`; server pushes `setClientDvar` **only on value change**. Fully client-rendered: immune to HUD elem pool, string table, team-elem delivery bug ([[ot-icon-team-hudelem-delivery-bug]]), thread death; killcam/menu hiding free via `visibilityBits`. Menu edits require a mod.ff rebuild (linker pipeline in CLAUDE.md).

**TWO separate hudelem limits — the dangerous one is invisible to probes (2026-06-14, confirmed in-game):**

1. **Allocation pool** — `newClientHudElem` returns valid. Measured **free=903, ceiling≥924** with the 1024-cap probe on top of the 21-element panel. Engine-global owner-tagged `g_hudelems`. Enormous headroom; NOT the constraint.
2. **Per-client RENDER/network cap** — the engine only DRAWS a limited number of client-owned hudelems per player per snapshot (empirically ~17–20). Beyond it, the extra elements **silently do not render**, even though allocation succeeded AND their script-side `.alpha`/`.x` are set correctly. **This is the real failure class and NO script-side probe can detect it** — `gf_debug_elem_probe` measures allocation (saw 903 free), and reading `elem.alpha`/`elem.x` shows healthy values (the gf_dbgRows debug showed `fill a=0.9 num a=1` while nothing drew). Only the human eye sees it.

**Confirmed bracket:** the health panel at **21** client hudelems dropped the LAST-created elements (row1's bar + number invisible); removing the 4 border lines → **17** → everything rendered. The "enemy bar missing fill" mystery was THIS, not data/HP.

**The cap is GLOBAL across ALL hudelem types, not just client hudelems (2026-06-15).** Proof: with the panel at 17, the kill popup AND the overtime flag objpoint were invisible during play and only appeared the instant the round-end teardown cleared other elements. `NewScoreHudElem` (score popup) is NOT a separate exempt pool — it's in the same ceiling. So "17 for us" was wrong: 17 is most of the WHOLE per-client budget, shared with stock HUD + score popup + flag.

**Fix (applied 2026-06-15): the ENTIRE health panel is now menu-rendered → 0 client hudelems.** bg fade + 8 skulls + 2 bars + 2 numbers are all `hud_gf_health.menu` itemDefs driven by per-client dvars: `ui_gf_panel_x/y` (anchor), `ui_gf_hp_alpha` (reveal fade), `ui_gf_rN_hp/_fw/_cnt/_alive` (row data, N=0 friendly/1 enemy), `ui_gf_skull_mat`/`ui_gf_fade_mat` (material names). GSC: `gf_pushHealthRow`/`gf_setRowDvar` (push on change) replace the old client-hudelem create/update. Skulls = 2 itemDefs/slot (alive team-colour + dead white, gated by `_alive`/`_cnt` — forecolor R/G/B can't be exp-driven, only A). **Enemy data shows fine** because it's server-computed and pushed per-client (the old "enemy not visible client-side" fear was about client-side computation, which this isn't). Materials MUST be dynamic `exp material(dvarString(...))` not static `background "hud_..."` — static makes the linker bundle the .iwi (missing → build error). `when()` supports `>` / `<=` / `&&`, not just `==`.

**(Separately, the string table above is still a real, independent limit** — per-tick `setText` of unique strings, biggest burners are debug overlays; survives `map_restart`.)
