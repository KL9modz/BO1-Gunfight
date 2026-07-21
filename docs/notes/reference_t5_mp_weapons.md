---
name: reference-t5-mp-weapons
description: "Full verified list of valid T5 MP weapon strings for use in GiveWeapon() calls, including valid attachment variants per weapon. Use when building or validating loadouts."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 50568bcd-7df1-4e63-a542-62dd885ee2d9
---

Full weapon name list sourced from MP.txt (authoritative T5 MP weapon name dump). All names use `_mp` suffix. Only names in this list are safe to pass to `GiveWeapon()`.

## Known invalid names (confirmed absent from list)
- `galil_grip_mp` — no grip variant; use `galil_extclip_mp`
- `mpl_extclip_mp` — no extclip variant; use `mpl_rf_mp`
- `pm63_silencer_mp` — no silencer variant; use `pm63_extclip_mp`
- `hk21_grip_mp` — no grip variant; use `hk21_extclip_mp`
- `stoner63_grip_mp` — no grip variant; use `stoner63_extclip_mp`
- `ithaca_mp` — base form invalid; only `ithaca_grip_mp` exists
- `smoke_grenade_mp` — absent from list; T5 smoke grenade is `willy_pete_mp`

## Invalid dual-attachment combos — CONFIRMED finger-guns (pool audit 2026-07-08)
Two-attachment (Warlord) combos exist ONLY where enumerated per-base below. A slot-legal AND
attachment-COMPATIBLE combo name (well-formed per attachmentTable.csv) still finger-guns if
Treyarch never compiled that specific asset. These 7 were in the loadout pool, confirmed invalid
(two independent adversarial verifiers, high confidence) and fixed 2026-07-08:
- `m16_ir_extclip_mp` → `m16_ir_mp`   (also threw a CG_SetWeaponHidePartBits bone error)
- `m14_reflex_grip_mp` → `m14_acog_grip_mp`   (m14 combos exist ONLY as acog_grip / ir_grip)
- `spectre_grip_extclip_mp` → `spectre_acog_grip_mp`   (spectre combo exists ONLY as acog_grip)
- `wa2000_ir_silencer_mp` → `wa2000_ir_mp`   (NO sniper has dual-combos; no silencer-pair exists on any gun)
- `mac11_grip_silencer_mp` → `mac11_silencer_mp`   (mac11 is singles-only)
- `aug_elbit_dualclip_mp` → `aug_elbit_mp`   (every AR except m14 is singles-only)
- `kiparis_elbit_grip_mp` → `kiparis_acog_grip_mp`   (kiparis combos exist ONLY as acog_grip / grip_extclip)

RECURRENCE RISK: `tools/loadout_editor/index.html` synthesizes combo names by slot-ordering single
attachments and does NOT verify a compiled asset exists (its own comment admits combos "still need
an in-game give test"). `gf_buildWeaponDB`/`gf_wdb` only resolve the weapon FAMILY (first `_`
segment) for icons, so an invalid combo resolves cleanly and is never caught. Validate any new pool
combo against the per-base list below (or the inline copy at _gf_loadouts.gsc ~L461-540) before
shipping. See [[invalid-weapon-finger-gun-fallback]].

## Assault Rifles
```
ak47_mp, ak47_acog_mp, ak47_dualclip_mp, ak47_elbit_mp, ak47_extclip_mp,
ak47_ft_mp, ak47_gl_mp, ak47_ir_mp, ak47_mk_mp, ak47_reflex_mp, ak47_silencer_mp
aug_mp, aug_acog_mp, aug_dualclip_mp, aug_elbit_mp, aug_extclip_mp,
aug_ft_mp, aug_gl_mp, aug_ir_mp, aug_mk_mp, aug_reflex_mp, aug_silencer_mp
commando_mp, commando_acog_mp, commando_dualclip_mp, commando_elbit_mp, commando_extclip_mp,
commando_ft_mp, commando_gl_mp, commando_ir_mp, commando_mk_mp, commando_reflex_mp, commando_silencer_mp
enfield_mp, enfield_acog_mp, enfield_dualclip_mp, enfield_elbit_mp, enfield_extclip_mp,
enfield_ft_mp, enfield_gl_mp, enfield_ir_mp, enfield_mk_mp, enfield_reflex_mp, enfield_silencer_mp
famas_mp, famas_acog_mp, famas_dualclip_mp, famas_elbit_mp, famas_extclip_mp,
famas_ft_mp, famas_gl_mp, famas_ir_mp, famas_mk_mp, famas_reflex_mp, famas_silencer_mp
fnfal_mp, fnfal_acog_mp, fnfal_dualclip_mp, fnfal_elbit_mp, fnfal_extclip_mp,
fnfal_ft_mp, fnfal_gl_mp, fnfal_ir_mp, fnfal_mk_mp, fnfal_reflex_mp, fnfal_silencer_mp
g11_mp, g11_lps_mp, g11_vzoom_mp
galil_mp, galil_acog_mp, galil_dualclip_mp, galil_elbit_mp, galil_extclip_mp,
galil_ft_mp, galil_gl_mp, galil_ir_mp, galil_mk_mp, galil_reflex_mp, galil_silencer_mp
m14_mp, m14_acog_mp, m14_acog_grip_mp, m14_elbit_mp, m14_extclip_mp,
m14_ft_mp, m14_gl_mp, m14_grip_mp, m14_ir_mp, m14_ir_grip_mp, m14_mk_mp, m14_reflex_mp, m14_silencer_mp
m16_mp, m16_acog_mp, m16_dualclip_mp, m16_elbit_mp, m16_extclip_mp,
m16_ft_mp, m16_gl_mp, m16_ir_mp, m16_mk_mp, m16_reflex_mp, m16_silencer_mp
```

## SMGs
```
ak74u_mp, ak74u_acog_mp, ak74u_acog_grip_mp, ak74u_dualclip_mp, ak74u_elbit_mp,
ak74u_extclip_mp, ak74u_gl_mp, ak74u_grip_mp, ak74u_grip_dualclip_mp, ak74u_grip_extclip_mp,
ak74u_reflex_mp, ak74u_rf_mp, ak74u_silencer_mp
kiparis_mp, kiparis_acog_mp, kiparis_acog_grip_mp, kiparis_elbit_mp, kiparis_extclip_mp,
kiparis_grip_mp, kiparis_grip_extclip_mp, kiparis_reflex_mp, kiparis_rf_mp, kiparis_silencer_mp
mac11_mp, mac11_elbit_mp, mac11_extclip_mp, mac11_grip_mp, mac11_reflex_mp, mac11_rf_mp, mac11_silencer_mp
mp5k_mp, mp5k_acog_mp, mp5k_elbit_mp, mp5k_extclip_mp, mp5k_reflex_mp, mp5k_rf_mp, mp5k_silencer_mp
mpl_mp, mpl_acog_mp, mpl_acog_grip_mp, mpl_dualclip_mp, mpl_elbit_mp,
mpl_grip_mp, mpl_reflex_mp, mpl_rf_mp, mpl_silencer_mp
pm63_mp, pm63_extclip_mp, pm63_grip_mp, pm63_rf_mp  (NO silencer)
skorpion_mp, skorpion_extclip_mp, skorpion_grip_mp, skorpion_rf_mp, skorpion_silencer_mp
spectre_mp, spectre_acog_mp, spectre_acog_grip_mp, spectre_elbit_mp, spectre_extclip_mp,
spectre_grip_mp, spectre_reflex_mp, spectre_rf_mp, spectre_silencer_mp
uzi_mp, uzi_acog_mp, uzi_acog_grip_mp, uzi_elbit_mp, uzi_extclip_mp,
uzi_grip_mp, uzi_reflex_mp, uzi_rf_mp, uzi_silencer_mp
```

## LMGs
```
hk21_mp, hk21_acog_mp, hk21_elbit_mp, hk21_extclip_mp, hk21_ir_mp, hk21_reflex_mp  (NO grip)
m60_mp, m60_acog_mp, m60_acog_grip_mp, m60_elbit_mp, m60_extclip_mp,
m60_grip_mp, m60_ir_mp, m60_ir_grip_mp, m60_reflex_mp
rpk_mp, rpk_acog_mp, rpk_dualclip_mp, rpk_elbit_mp, rpk_extclip_mp, rpk_ir_mp, rpk_reflex_mp
stoner63_mp, stoner63_acog_mp, stoner63_elbit_mp, stoner63_extclip_mp,
stoner63_ir_mp, stoner63_reflex_mp  (NO grip)
```

## Snipers
```
dragunov_mp, dragunov_acog_mp, dragunov_extclip_mp, dragunov_ir_mp, dragunov_silencer_mp, dragunov_vzoom_mp
l96a1_mp, l96a1_acog_mp, l96a1_extclip_mp, l96a1_ir_mp, l96a1_silencer_mp, l96a1_vzoom_mp
psg1_mp, psg1_acog_mp, psg1_extclip_mp, psg1_ir_mp, psg1_silencer_mp, psg1_vzoom_mp
wa2000_mp, wa2000_acog_mp, wa2000_extclip_mp, wa2000_ir_mp, wa2000_silencer_mp, wa2000_vzoom_mp
```

## Shotguns
```
hs10_mp  (single HS-10 CONFIRMED giveable in Pluto T5 2026-07-06 — the "akimbo only" note was WRONG; hs10dw_mp/hs10lh_mp are the akimbo variants)
ithaca_grip_mp  (NO plain ithaca_mp)
ks23_mp  — DO NOT USE: NOT a functional MP weapon; GiveWeapon gives NO gun (default "finger gun" fallback), confirmed in-game 2026-07-06. See [[invalid-weapon-finger-gun-fallback]]
rottweil72_mp
spas_mp, spas_silencer_mp
```

## Pistols / Secondaries
```
asp_mp
cz75_mp, cz75_auto_mp, cz75_extclip_mp, cz75_silencer_mp, cz75_upgradesight_mp
m1911_mp, m1911_extclip_mp, m1911_silencer_mp, m1911_upgradesight_mp
makarov_mp, makarov_extclip_mp, makarov_silencer_mp, makarov_upgradesight_mp
python_mp, python_acog_mp, python_snub_mp, python_speed_mp
```

## Launchers / Specials
```
china_lake_mp
crossbow_mp, crossbow_explosive_mp
knife_ballistic_mp
m72_law_mp
m202_flash_mp, m202_flash_wager_mp
minigun_mp, minigun_wager_mp
rpg_mp
strela_mp
```

## Equipment / Grenades
```
claymore_mp
concussion_grenade_mp
frag_grenade_mp, frag_grenade_short_mp
hatchet_mp
satchel_charge_mp
sticky_grenade_mp
willy_pete_mp   ← T5 smoke grenade (NOT smoke_grenade_mp)
flash_grenade_mp
tabun_gas_mp    ← Nova Gas tactical (icon hud_icon_tabun_gasgrenade)
nightingale_mp  ← Decoy tactical — BO1's decoy is internally "Nightingale", NOT "decoy_mp" (which doesn't exist). Icon hud_nightingale. Works natively: maps\mp\_decoy is threaded by _globallogic + createDecoyWatcher per spawn from _weaponobjects. NOT in default classes, so PrecacheItem it (like minigun/m202) or GiveWeapon no-ops.
knife_mp
tactical_insertion_mp
camera_spike_mp
```

The full T5 MP **tactical** roster is exactly 5 (per _class.gsc validation): `flash_grenade_mp`, `concussion_grenade_mp`, `willy_pete_mp` (smoke), `tabun_gas_mp` (gas), `nightingale_mp` (decoy).

## Dual-wield variants (pass true as 2nd arg to GiveWeapon)
```
aspdw_mp / asplh_mp
cz75dw_mp / cz75lh_mp
hs10dw_mp / hs10lh_mp
kiparisdw_mp / kiparislh_mp
m1911dw_mp / m1911lh_mp
mac11dw_mp / mac11lh_mp
makarovdw_mp / makarovlh_mp
pm63dw_mp / pm63lh_mp
pythondw_mp / pythonlh_mp
skorpiondw_mp / skorpionlh_mp
```
