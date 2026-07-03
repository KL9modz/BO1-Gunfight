# Health HUD Menu Numbers Experiment

Context: script HUD font elems rendered the team HP numbers much larger than expected, even with small font scales.

Current experiment:
- Move team HP number rendering out of script HUD elems and into a UI menu layer.
- Keep the script HUD responsible for bars, skull icons, and health calculations.
- Drive the menu text with per-client dvars:
  - `ui_gf_health_hp_visible`
  - `ui_gf_health_hp0`, `ui_gf_health_hp0_x`, `ui_gf_health_hp0_show`
  - `ui_gf_health_hp1`, `ui_gf_health_hp1_x`, `ui_gf_health_hp1_show`

Expected benefits:
- Reliable menu `textscale` instead of script HUD font scaling.
- Frees the two script HUD elems previously used for HP text.
- Lets HP numbers follow the right edge of the visible team health bars.

Files involved:
- `maps/mp/gametypes/_gf_hud.gsc`
- `ui_mp/hud_gf.txt`
- `ui_mp/hud_gf_splitscreen.txt`
- `ui_mp/hud_gf_health.menu`
- `mod.csv`

Revert path:
- Remove the menu file entry from `mod.csv`.
- Remove `loadMenu { "ui_mp/hud_gf_health.menu" }` from both HUD txt files.
- Delete `ui_mp/hud_gf_health.menu`.
- In `_gf_hud.gsc`, remove menu-number dvar helpers/calls and restore no HP text, or restore the prior script text path if desired.
