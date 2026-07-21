---
name: special-weapons-precacheitem-and-camo
description: "Minigun/M202 (and other special/KS weapons) show their loadout icon but GiveWeapon silently no-ops unless PrecacheItem'd; they also reject a non-zero camo"
metadata: 
  node_type: memory
  type: project
  originSessionId: 38ca40ac-6343-474e-a388-9dd837a5efec
---

Special/killstreak weapons (`minigun_mp` = Death Machine, `m202_flash_mp` = Grim Reaper, and the `_wager_` variants) are NOT in the normal MP weapon table, so the class system never auto-precaches them like it does famas/galil/etc.

USE THE `_wager` VARIANTS, NOT the killstreak names. The mod's heavy loadouts use `minigun_wager_mp` / `m202_flash_wager_mp`. The killstreak names `minigun_mp` / `m202_flash_mp` are registered in the killstreak system, which causes TWO bugs when given as a loadout weapon: (a) the "killstreak called in" announcer fires on every give, and (b) once you holster the weapon you CANNOT re-select it (killstreak weapons don't cycle back). The `_wager` builds are the identical guns (same fields, same `killIcon`, same `menu_mp_weapons_minigun`/`hud_m202` shaders) WITHOUT the killstreak registration, so they behave as normal swappable primaries. Stock `shrp.gsc` uses the `_wager` variants for exactly this reason.

Three gotchas, first two produce the same symptom — **loadout HUD icon shows but the player receives no weapon**:
1. **No PrecacheItem** → `GiveWeapon()` silently no-ops at runtime. Fix: `PrecacheItem( "minigun_wager_mp" )` / `PrecacheItem( "m202_flash_wager_mp" )` in `gf.gsc::onPrecacheGameType` (PrecacheItem is ONLY valid in the precache phase, never at gameplay time). The icon is a separate shader (`menu_mp_weapons_minigun` / `hud_m202`), which is why it renders even when the gun fails.
2. **Camo rejection** → these special weapons reject a non-zero `camoOpts` the way launchers/pistols do, so `GiveWeapon(primary, 0, camoOpts)` no-ops. Stock `shrp.gsc` gives the minigun with no camo args at all. In the loadout pool, force `pool[n]["camo"] = 0` for any special-weapon-as-primary so `CalcWeaponOptions(0,0,0,0)` yields 0.
3. **Killstreak hook** (announcer + can't re-select after holster) → use `_wager` variant instead of the killstreak name. See top of this note.

**Why:** items 1+2 were the root cause of the long-standing "Minigun & M202 not working" TODO bug; item 3 surfaced once they were given a pistol secondary (couldn't switch back to the heavy).
**How to apply:** any new heavy/special weapon should use the `_wager` build, get a `PrecacheItem` in onPrecacheGameType, and (if it's the camo'd primary) `["camo"]=0`. Related: [[onprecache-once-per-match-loadfx-wiped]] (different precache pitfall — loadfx handles wiped by map_restart).
