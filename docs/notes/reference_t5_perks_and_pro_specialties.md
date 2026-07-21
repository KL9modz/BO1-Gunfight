---
name: reference_t5_perks_and_pro_specialties
description: "BO1 in-game perk names (3 sections) mapped to their SetPerk specialty_* tokens — a Pro ability is just EXTRA tokens, individually grantable. Includes the 52-token engine vocabulary"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 8a232369-377c-48f1-bfd0-c500caa88440
---

# BO1 perks ↔ `specialty_*` tokens

**The model:** a create-a-class perk is a `|`-delimited **group** of `specialty_*` tokens
(`_class::validatePerkGroup` StrToks it; `register_perks()` then `SetPerk`s each one). **A Pro ability
is nothing but one or two EXTRA tokens in that group** — there is no "pro" flag, no upgrade state. So
GSC can grant *any* perk, any Pro ability, or a Pro ability **without its base perk**, à la carte.

**Sources (all three agree):** the engine's own token table (`grep -a "specialty_" BlackOpsMP.exe` → the
52 valid names, listed below); `_properks.gsc` (per-perk challenge stats, e.g. `PERKS_GHOST_*` keyed off
`specialty_gpsjammer`); and `raw/maps/mp/gametypes/shrp.gsc`, which registers base+pro tokens under one
shared `PERKS_<NAME>_PRO` string — the cleanest confirmation of the grouping.
⚠ The real group table is `mp/statsTable.csv`, which is **not in `raw/`** and is **not extractable**:
in the zone its stringtable cells are stored as **hashes**, not text (inflating `common_mp.ff` gets you
the asset name and nothing else). Don't burn time re-trying that; use the three sources above.

## The table (in-game label → base token → Pro token(s))

### Perk Section 1
| In-game | Base | Pro adds |
|---|---|---|
| **Lightweight** — move faster | `specialty_movefaster` | `specialty_fallheight` (no fall damage) |
| **Scavenger** — pick up ammo from the fallen | `specialty_scavenger` | `specialty_extraammo` (extra mags; tacticals replenish) |
| **Ghost** — invisible to Spy Plane/Blackbird | `specialty_gpsjammer` | `specialty_nottargetedbyai` + `specialty_noname` (no red name/crosshair) |
| **Hardline** — killstreaks cost 1 fewer kill | `specialty_killstreak` | care-package reroll (`_supplydrop` gates on the base token) |
| **Flak Jacket** — reduced explosive damage | `specialty_flakjacket` | `specialty_fireproof` (fire immunity) + `specialty_pin_back` (slower throwbacks) |

### Perk Section 2
| In-game | Base | Pro adds |
|---|---|---|
| **Hardened** — bullet penetration | `specialty_bulletpenetration` | `specialty_armorpiercing` (vs aircraft/turrets) + `specialty_bulletflinch` (**reduced flinch when shot**) |
| **Scout** — hold breath longer | `specialty_holdbreath` | `specialty_fastweaponswitch` (faster raise/drop) |
| **Steady Aim** — hip-fire accuracy | `specialty_bulletaccuracy` | `specialty_sprintrecovery` (faster ADS after sprint) + `specialty_fastmeleerecovery` |
| **Sleight of Hand** — faster reload | `specialty_fastreload` | `specialty_fastads` (faster ADS, non-scoped) |
| **Warlord** — two attachments | `specialty_twoattach` | `specialty_twogrenades` (+1 lethal, +1 tactical) |

### Perk Section 3
| In-game | Base | Pro adds |
|---|---|---|
| **Tactical Mask** — resist Nova Gas | `specialty_gas_mask` | `specialty_shades` (flash) + `specialty_stunprotection` (concussion) |
| **Marathon** — longer sprint | `specialty_longersprint` | **`specialty_unlimitedsprint`** ← see below |
| **Ninja** — move silently | `specialty_quieter` | `specialty_loudenemies` (enemies louder) |
| **Second Chance** — pistol on the ground | `specialty_pistoldeath` | `specialty_finalstand` (survive longer, revivable) |
| **Hacker** — detect enemy equipment | `specialty_detectexplosive` | `specialty_disarmexplosive` + `specialty_nomotionsensor` |

## Two live consequences for mp_gunfight

1. ⚠ **`specialty_armorvest` is NOT Flak Jacket — and it is NOT any BO1 perk.** We call it **"Body Armor"**,
   named for its effect — do **NOT** give it a BO1-sounding name (that is how `specialty_blindeye` survived);
   it is an engine leftover token with no create-a-class row. `_class::cac_modified_damage`
   (called from stock `_globallogic_player.gsc:677`, so it is on the live damage path) does
   `final_damage = damage * (perk_armorVest * .01)` on **non-headshot bullet** damage, and
   `perk_armorVest` defaults to **80** → a flat **20% bullet-damage reduction**. `_gf_loadouts.gsc:223`
   grants it to every player, mislabeled `// Flak Jacket`. Real Flak Jacket is `specialty_flakjacket`
   (already granted on the next line, mislabeled "Pro"); real Flak Jacket Pro is `specialty_fireproof`.
   It is symmetric so it doesn't unbalance PvP, but it lengthens every bodyshot TTK by 25%, makes
   headshots disproportionately strong (they bypass it), and skews both **score = damage dealt** and the
   **most-remaining-HP** round decision toward headshots.
   ✅ **Decided 2026-07-12: KEEP the perk, fix the labels.** It is now a knowing design choice (the
   softer bullet TTK suits a 42s round), not a bug — do **not** re-flag it. The mislabel was corrected in
   `_gf_loadouts.gsc`, `CLAUDE.md`, `docs/REFERENCE.md` and the RCON panel's perk row (now labelled
   "Body Armor (-20% bullet dmg)"). Removing it remains a live option if headshot skew ever bites.
2. **`specialty_unlimitedsprint` exists in the engine** — so the whole `player_sprintUnlimited`
   per-client-dvar push (`scr_gf_sprint_unlimited`, see [[player-sprintunlimited-one-way-connect-push]])
   should be replaceable by one `SetPerk`. It has **no GSC reference** anywhere in `raw/` (engine-side
   movement code consumes it), so whether it works is a **hypothesis to test**, not a fact.
   ✅ **2026-07-12: added to the GF base perk set** (`_gf_loadouts.gsc`, + a `def:'1'` panel row). The
   `scr_gf_sprint_unlimited` dvar path is deliberately left in place — the two are independent inputs to
   the same movement sim and cannot fight. **Once the perk is confirmed live, retire the dvar path.**

**The GF base set is 9 tokens:** `fallheight`, `longersprint`, `unlimitedsprint`,
`armorvest`, `flakjacket`, `shades`, `stunprotection`, `loudenemies`, `fastmeleerecovery`. **`movefaster`
and `bulletflinch` are NO LONGER in the base set** — `movefaster` (+7% speed made 42s rounds twitchy) is
opt-in via `gf_perk_on`, and `bulletflinch` rides the **sniper/heavy package only** (it's a second flinch
multiplier — see [[hardened-pro-flinch-perk-multiplier]] — so leaving it in the base set silently defeats
`scr_gf_flinch`). **Five are Pros granted without their base perk** — intentional, and the whole point of
the à-la-carte model.
⚠ `BASE_PERKS` in **both** `tools/rcon/public/app.js` and `tools/loadout_editor/server.js` must mirror
this list exactly, or their checkboxes lie about what players actually have.

**Globally louder footsteps = `specialty_loudenemies` granted to EVERYONE, `specialty_quieter` to nobody.**
There is **no footstep-volume dvar** in T5 (`perk_footstepVolume*` doesn't exist; `cg_footsteps` is a
**client** dvar so a server `set` is inert; `compassEnemyFootstep*` is the minimap dot, not audio). The
engine does export a `CodeCallback_PlayerFootstep` hook but **no stock GSC implements it**. `loudenemies`
is Ninja Pro's "enemy movement is louder" half and is **listener-side**, so giving it to all players makes
everyone hear everyone else louder — symmetric, one `SetPerk`, no dvar.

⚠ **`specialty_fastads` NEVER STICKS.** Proven live on the VPS (2026-07-13) with the bridge's
`pperkdump_<num>` probe: with `gf_perk_on` listing 7 perks, **6 land on every player and `fastads` never
does** — `SetPerk` on it does not produce a `hasPerk` of true, while 11 other perks set in the same loop
all do. It IS a real engine token (in `BlackOpsMP.exe`, used by stock `shrp.gsc`) and nothing in stock GSC
unsets it. Consequences: **Sleight of Hand Pro cannot be granted this way**, and `perk_weapAdsMultiplier`
(gated by it) is a **dead** panel slider. Root cause unknown — leading theory is that ADS speed is baked
into weapon state at `GiveWeapon` time and we `SetPerk` *after* handing out the guns. Untested.

⚠ **`specialty_blindeye` is NOT a T5 token** (it's MW naming; 0 hits in `BlackOpsMP.exe`). The RCON panel
shipped a "Cold Blooded" row pushing it for a long time and it **did nothing** — `SetPerk` on an unknown
name is a **silent no-op**, which is the generic failure mode for any invented perk token. Replaced with
the real Ghost Pro pair (`nottargetedbyai` + `noname`). Likewise "Extreme Conditioning" is not a BO1 perk:
`specialty_sprintrecovery` is half of **Steady Aim Pro**.

## The full 52-token engine vocabulary
Anything not on this list is not a real perk — `SetPerk` on an unknown name is a silent no-op.
`armorpiercing armorvest bulletaccuracy bulletdamage bulletflinch bulletpenetration copycat
delayexplosive detectexplosive disarmexplosive explosivedamage extraammo extramoney fallheight fastads
fastinteract fastmantle fastmeleerecovery fastreload fastweaponswitch finalstand fireproof flakjacket
gambler gas_mask gpsjammer grenadepulldeath healthregen holdbreath killstreak longersprint loudenemies
movefaster nomotionsensor noname nottargetedbyai pin_back pistoldeath quieter reconnaissance rof
scavenger shades shellshock showenemyequipment showonradar sprintrecovery stunprotection twoattach
twogrenades twoprimaries unlimitedsprint` (each prefixed `specialty_`).

Non-BO1-perk leftovers worth knowing: `specialty_bulletdamage` = Stopping Power,
`specialty_armorvest` = Body Armor (engine leftover, not a BO1 perk), `specialty_rof` = Double Tap, `specialty_grenadepulldeath` =
Martyrdom, `specialty_twoprimaries` = Overkill.
