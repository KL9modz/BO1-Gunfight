---
name: build-stage-transitive-menu
description: "mod.ff build silently used a STALE hud_gf_health.menu — transitive .menu (loaded via loadMenu, not a mod.csv menufile) must be staged to raw/ before linking"
metadata: 
  node_type: memory
  type: project
  originSessionId: 19af7383-278e-402c-8e4c-11b5c3fab77e
---

`ui_mp/hud_gf_health.menu` is pulled in **transitively** by `hud_gf.txt`'s `loadMenu` directive, so it is intentionally NOT its own `menufile` entry in `mod.csv` (a duplicate menufile entry double-registers the menu and crashes the whole UI — see CLAUDE.md menufile double-load pitfall). But the linker reads it from `raw/ui_mp/hud_gf_health.menu` when it expands `hud_gf.txt`.

`tools/build_ff.ps1` originally only staged files listed in `mod.csv`, so it never copied edited `hud_gf_health.menu` to `raw/` → the linker compiled a **stale raw copy** and menu edits silently never reached `mod.ff` (symptom: in-game HUD unchanged after a "successful" build; `grep -c ui_gf_lo_ raw/.../hud_gf_health.menu` = 0 while the mod copy had them).

**Fix (applied):** `build_ff.ps1` now explicitly does `$assetsToStage.Add("ui_mp/hud_gf_health.menu")` after the mod.csv parse, so it stages AND cleans it like everything else. Any future transitive `.menu` needs the same treatment.

**Why:** the build looks successful but compiles old art.
**How to apply:** after editing any `.menu`, confirm it appears in the build's "staged ..." list; if not, add it to `$assetsToStage`. Related: [[settext-configstring-exhaustion]] for why HUD chrome lives in menus, and [[menu-rendered-loadout-overview]].

**ALWAYS build with `tools/build_ff.ps1` — never a manual `Copy-Item raw/ + linker` (2026-06-14).** Two reasons the manual path bites: (1) it builds only the NAMED zone (`mods/mp_gunfight` → `mp_gunfight.ff`) and renames that to `mod.ff`, but Plutonium loads `mod.ff` built from the **mod zone** (`-moddir mp_gunfight mod`) — build_ff.ps1 runs BOTH linker passes. (2) **It never cleans the staged files out of `raw/`.** Plutonium reads `raw/` as a fallback over the IWDs, so a leftover `raw/ui_mp/hud_gf_health.menu` gets loaded **in addition to** the copy in `mod.ff` → the menu name (`gf_health_hp_numbers`) double-registers → the menu system crashes and **ALL gametypes vanish from the UI** (same symptom as the mod.csv menufile double-load pitfall, different cause). build_ff.ps1 stages → builds both zones → **removes the staged files from `raw/`** ("Cleaned N staged file(s) from raw/") → copies `mod.ff` back. Symptom of the bug: gametypes gone after a `loadMod`; fix: run build_ff.ps1 (it cleans raw/) or manually delete the leftover `raw/ui_mp/hud_gf_health.menu`.
