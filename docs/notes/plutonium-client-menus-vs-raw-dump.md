---
name: plutonium-client-menus-vs-raw-dump
description: "The Plutonium T5 CLIENT options menus differ from the stock raw/ui dump — FOV cap is raised past 80, and the Game tab adds settings absent from raw. Don't treat raw/ui as ground truth for live client UI."
metadata: 
  node_type: memory
  type: reference
  originSessionId: b533c3f5-f975-4b4b-95af-f09967900a79
---

The stock `raw/ui/options_graphics_pc.menu` in the T5 dump defines the FOV slider as `cg_fov_default`, range **65–80** — but the **live Plutonium client raises the cap**: an in-game Graphics screenshot showed **Field of View = 87**. And Plutonium's **Game** tab (`options_game_pc.menu` in raw only has `hud_enable`) actually shows client-added settings not in the dump: **FOV Scale** (a multiplier on the base FOV, e.g. 1.04), **Max FPS** (`com_maxfps`, e.g. 237), **Reduce Engine Sleeps**, **Streamer Mode**, **Record clientside/serverside demos**, **Draw Game Identifier**.

Practical FOV model for BO1/Plutonium: **base Field of View (Graphics) × FOV Scale (Game tab) = effective FOV shown.** So a base ~78 with FOV scale ~1.05 displays in the high-80s. `cg_fov_default <n>` sets the base from console (some builds allow up to ~90); FOV scale has no confirmed console dvar — it's the Plutonium menu.

Confirmed-from-source graphics dvars that DO match raw and work in console: `r_fullscreen`, `r_vsync`, `r_aasamples`, `r_texFilterAnisoMin` (1–16), `r_texFilterMipMode "Force Trilinear"`, `r_picmip 0`, `r_shaderWarming`, `sm_enable`, `fx_marks`, `r_gamma`, `hud_enable`. `cl_allowdownload 1` = the "Allow downloading" MP setting (from Plutonium forum, not the raw menu).

Lesson: when documenting client-facing Plutonium settings, verify against a live-client **screenshot**, not just the raw dump — the dump is stock Treyarch UI and misses Plutonium's client patches. These are now written into [[repo README docs/GETTING_STARTED.md]] (the Getting Started guide + gunfight.us `site/wwwroot/setup.html`).
