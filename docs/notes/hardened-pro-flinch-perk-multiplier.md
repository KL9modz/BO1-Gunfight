---
name: hardened-pro-flinch-perk-multiplier
description: "Hardened Pro (specialty_bulletflinch) is a SECOND flinch multiplier — perk_damageKickReduction 0.2 is the kick REMAINING (an 80% cut), and it multiplies with scr_gf_flinch. Base-set grant made the live VPS 10% of stock flinch"
metadata: 
  node_type: memory
  type: project
  originSessionId: 9576bd2b-17bd-461a-978c-966fc84a0a62
---

`specialty_bulletflinch` (Hardened Pro) gates the engine's **`perk_damageKickReduction`**, and that dvar's
registered default is **`0.2`** — which is the fraction of view kick **REMAINING**, i.e. an **80% cut**, not
"20% off". Proof is stock's own custom-games perk editor
(`raw/ui_mp/custom_specialty_editor.menu`, the Hardened popup): it maps the label `"50%"` → value `0.5` and
`"95%"` → `0.05`. Plutonium ships `g_fix_damageKickReductionPerk 1` (engine default ON), so the perk really
applies on T5 MP.

**It MULTIPLIES with `scr_gf_flinch` → `bg_viewKickScale`.** With the perk in Gunfight's base set (every
player, every round), the live VPS read (2026-07-13, `/api/dvars?fresh=1`):

    bg_viewKickScale          0.1   (= stock 0.2 x scr_gf_flinch 0.5)
    scr_gf_flinch             0.5   (from the BOX's dedicated.cfg — not the GSC default)
    perk_damageKickReduction  0.2   (engine default, on every client)
    -> effective 0.2 x 0.5 x 0.2 = 0.02 = 10% of stock flinch

That is why flinch "felt like zero". Two traps compounded it:

1. **The perk is ~5x stronger than the dvar**, so an earlier fix that moved `scr_gf_flinch` 0.5 → 1.0
   "to stop double-reducing" removed the *weaker* reducer and left the strong one. And at the dvar's clamp
   ceiling of 3, stock flinch was **not even reachable** while the perk was on (you'd need 5.0).
2. **The GSC default never applied.** `gf_cfgFloat` is **seed-if-empty**, and the box's `dedicated.cfg`
   (which `deploy.ps1` does NOT ship — it lives only on the VPS) had `set scr_gf_flinch "0.5"`. The repo's
   1.0 was dead code on the live server. See [[read-the-server-not-the-file]].

**Resolution:** `specialty_bulletflinch` is OUT of the base set and rides **only** in the sniper/heavy
package (10 loadouts), where the extra 0.2x is a deliberate class trait. `scr_gf_flinch` is the single
global flinch lever, shipped at **0.5 = half stock**, and its numbers now mean what they say.

⚠ **Hardened Pro is TWO tokens** — `specialty_armorpiercing` AND `specialty_bulletflinch`. The sniper
package carried only the base `specialty_bulletpenetration`, so "snipers keep Hardened Pro" required adding
the flinch token explicitly. Don't assume a Pro is one token
([[reference_t5_perks_and_pro_specialties]]).

⚠ **Unverified:** whether `perk_damageKickReduction` replicates. View kick is scaled client-side
([[flinch-bg-viewkickscale-not-replicated]]), so a server-side `set` on it may be inert — it doesn't matter
today only because we never write it and every client sits on the engine default 0.2. Do not add a panel
slider for it without proving the push lands.

**How to apply:** any "flinch feels wrong" report starts by asking *which perks are live*, not just what
`scr_gf_flinch` reads. A `perk_*` dvar is a magnitude whose gate is a `specialty_*` perk — granting the perk
silently arms the multiplier for everyone.
