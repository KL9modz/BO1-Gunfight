---
name: rcon-dedicated-dvar-push-limits
description: "Why RCON visual/client controls fail on the VPS (dedicated) but work on a local listen server: three dvar classes; Vision FX is the VPS-safe look lever; panel greys them via .ded-lockable"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 9b4509da-5e70-4bb9-a2a8-b7873e140195
---

Server→client dvar pushes on a **dedicated** BO1/Plutonium server fail for THREE distinct
reasons (only the archived one I'd tracked before; found the other two 2026-07-03 chasing
"view bob/fov/drawfps + visual-tweak sliders don't work on the VPS"):

1. **Archived (`seta`) client dvars → blocked always.** Plutonium refuses server writes to a
   client's saved dvars (targeting yourself via RCON doesn't help — keyed on the dvar, not the
   caller). Verified against `players/mods/mp_gunfight/config_mp.cfg`: only `bg_viewBobAmplitudeBase`
   and `cg_drawFPS` are `seta` among panel dvars. `cg_fov` isn't `seta` but still fails because the
   FOV/View-Bob sliders use a plain server `set` (sdvv) that only touches the server's copy, never a
   client viewport. Client lobby default for these = the shipped `config_mp.cfg` (view bob 0.1,
   `cg_fov_default` 87), applied per-client at load. See [[unknown-command-cd-and-cfg-semicolon-parse]].
2. **Cheat-protected `r_*` renderer dvars → need `sv_cheats 1`.** The RCON **Visual Tweaks** sliders
   push `r_lightTweakAmbient` / `r_lightGridIntensity` / `r_lightGridContrast` / `r_fog` /
   `r_fullHDRrendering` via `setClientDvar` (`gf_bridgeVisSet`, `_gf_bridge.gsc`). The engine only
   honours those when `sv_cheats 1`, and **gf.gsc:~226 sets `sv_cheats 1` ONLY when
   `getDvarInt("dedicated")==0`** (listen server). So on the VPS every Visual-Tweaks push is silently
   refused — this is why they "work locally, not on VPS" (local listen = cheats on). Same class as the
   panel's `sv_botFov` "needs sv_cheats" note.
3. **Plain non-archived, non-cheat client dvars → actually work on the VPS.** `cg_drawCrosshair`,
   `cg_drawCrosshairNames`, and the `ui_gf_*` menu-HUD dvars. **`cg_thirdPerson` also works on the
   VPS** (user-confirmed 2026-07-03, despite being commonly cheat-flagged) — do NOT gate it.

**VPS-safe look lever = Vision FX (`visionSetNaked`), which is NOT cheat-gated** — that's why
`gf_vis_vision` is the RCON-overridable persisted default. Use vision sets (Enhance/B&W/etc.) to
change the look on a public server; the `r_*` sliders are a listen/dev fine-tuning tool only.

**No clean non-cheat fog toggle exists:** every BO1 map drives fog through per-map **volumetric**
fog (`setVolFog(...)` in each `mp_<map>_art.gsc`); originals aren't captured, so `setExpFog` could at
best do a one-way "clear fog" (returns on `map_restart`), map-dependent. Decided 2026-07-03 to skip it
and rely on Vision FX.

**RCON panel handling (tools/rcon/public/index.html):** blocks that only work off a dedicated server
carry class `.ded-lockable`; `applyServerMode()` toggles `.ded-locked` on them when `!_listenServer`
(server mode read from the `dedicated` dvar), CSS greys `.ctrl` inside (opacity + `pointer-events:none`).
Applied to CLIENT-LOCAL (view bob/FOV/drawfps) and VISUAL TWEAKS. Client-paste helpers stay usable on
dedicated: 📋/right-click copy the console line (`copyClientDvar`), and CLIENT BINDS has split
MOUSE2-only vs MOUSE2+SHIFT copies (`copyMouse2Ads`/`copySprintAdsFix`). Copy buttons deliberately
lack the `.ctrl` class so they never grey. See [[bo1-sprint-ads-compound-bind]].
