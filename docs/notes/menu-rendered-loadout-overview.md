---
name: menu-rendered-loadout-overview
description: loadout spawn overview is fully MENU-rendered (hud_gf_health.menu) — in-game menus CAN draw weapon/perk icons via material(dvarString) when the material is precached; zero client hudelems
metadata: 
  node_type: memory
  type: project
  originSessionId: 19af7383-278e-402c-8e4c-11b5c3fab77e
---

The spawn loadout overview (BO1 create-a-class style: big primary, secondary, 3-across equipment row, 3-across perk row; each item = icon + bracket line/ticks + name) is rendered **entirely in `ui_mp/hud_gf_health.menu`**, not as client hudelems. This sidesteps T5's ~17 drawn-per-player render cap (see [[settext-configstring-exhaustion]]) and never touches `setText`.

**Confirmed engine fact:** an in-game HUD menu CAN draw a dynamic icon via `exp material( dvarString( "ui_gf_lo_iconN" ) );` (pattern from stock `teamicon.inc` / `hud_twar.menu`) **as long as the material is registered** — all loadout icons are precached (weapons/equipment in `gf.gsc::onPrecacheGameType`, perk icons by stock `_class.gsc:421`). Verified rendering in-game.

**Driver:** `_gf_hud.gsc::gf_showWeaponHUD` pushes 8 icon materials + 8 names + anchor via `setClientDvar`, then `gf_slideLoadout(offFrom,offTo,alphaFrom,alphaTo,dur)` animates a unified slide (`ui_gf_lo_off`, added to every item's X) + fade (`ui_gf_lo_alpha`, multiplied into every item's `forecolor A`). Gated by `ui_gf_lo_show`. Coords: `HORIZONTAL_ALIGN_RIGHT` (x<0 = left of right safe edge) + `VERTICAL_ALIGN_CENTER`.

**Layout knobs:** anchor `ui_gf_lo_cx` (-104) / `ui_gf_lo_cy` (-6) and the slide/fade live in GSC → tune with a `map_restart`, **no rebuild**. Item sizes/row spacing are baked in the menu → editing them needs a `mod.ff` rebuild ([[build-stage-transitive-menu]]). Perk slot order (which perk in which column) is just the order of the `setClientDvar` pushes in `gf_showWeaponHUD` — swappable in GSC, no rebuild.

**Pitfall fixed:** row pitch too small drew each weapon's NAME under the next row's icon (names looked "missing"). Rows are now spaced so every name sits clear.
