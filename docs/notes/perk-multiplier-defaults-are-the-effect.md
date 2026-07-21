---
name: perk-multiplier-defaults-are-the-effect
description: "A perk_* multiplier's ENGINE DEFAULT *is* the perk's effect (0.5 = half time). 1.0 is NOT stock — it is the WORST value, i.e. the perk does nothing. Domains cap at 1, so any slider offering >1 silently does nothing"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 8a232369-377c-48f1-bfd0-c500caa88440
---

# `perk_*` multipliers: the default IS the effect

**The model:** a `specialty_*` perk is the **gate**; the `perk_*` dvar is the **magnitude**. The engine
only consults the dvar for a player who **has** the perk. They never fight — but two things about the
magnitudes are deeply counter-intuitive and cost a whole wrong investigation:

1. **The engine's registered DEFAULT is the perk's entire effect.** `perk_weapReloadMultiplier` defaults
   to **0.5** — that 0.5 *is* Sleight of Hand. You do not "turn the perk on" by setting a dvar; granting
   the perk is enough, and the stock default already delivers the advertised benefit.
2. **`1.0` is NOT "stock" — it is the WORST value in the domain**, meaning *no reduction at all*. Setting
   one of these to 1.0 **silently disables the perk's benefit** while leaving the perk visibly granted.

## Live-read values (VPS, `rcon <dvarname>` — the only authority)

| dvar | default | domain | direction | gated by |
|---|---|---|---|---|
| `perk_weapReloadMultiplier` | **0.5** | 0 – 1 | lower = faster | `specialty_fastreload` (Sleight of Hand) |
| `perk_weapAdsMultiplier` | **0.5** | 0.01 – 1 | lower = faster | `specialty_fastads` (SoH Pro) |
| `perk_weapSwitchMultiplier` | **0.5** | 0.01 – 1 | lower = faster | `specialty_fastweaponswitch` (Scout Pro) |
| `perk_weapMeleeMultiplier` | **0.5** | 0.01 – 1 | lower = faster | `specialty_fastmeleerecovery` (Steady Aim Pro) |
| `perk_weapSpreadMultiplier` | **0.65** | 0 – 1 | lower = tighter | `specialty_bulletaccuracy` (Steady Aim) |
| `perk_weapRateMultiplier` | **0.75** | 0 – 1 | lower = faster fire | `specialty_rof` (Double Tap) |
| `perk_sprintRecoveryMultiplier` | **0.6** | 0 – 1 | lower = faster | `specialty_sprintrecovery` (Steady Aim Pro) |
| `perk_sprintMultiplier` | **2** | 0 – 3 | **HIGHER = longer** | `specialty_longersprint` (Marathon) |
| `perk_speedMultiplier` | **1.07** | 0 – 5 | **HIGHER = faster** | `specialty_movefaster` (Lightweight) |
| `perk_damageKickReduction` | **0.2** | 0 – 1 | = kick REMAINING (80% cut) | `specialty_bulletflinch` (Hardened Pro) |
| `perk_armorVest` | **80** | — | = % damage remaining | `specialty_armorvest` (Body Armor) |

⚠ **Note the two odd ones out**: `perk_sprintMultiplier` and `perk_speedMultiplier` run the OTHER
direction (higher = more). Don't assume "lower = better" across the family.

## Two traps this closed

⚠ **The domain CAPS AT 1** for the whole `weap*`/`sprintRecovery` family. A panel slider offering 1.5 or
2.0 is offering values the **server rejects** — the slider moves, the dvar doesn't change, and it reads as
"this dvar is broken / doesn't replicate" when in fact the value was never accepted. **Read the domain
before concluding a dvar is inert.** This nearly produced a bogus "perk_weapMeleeMultiplier doesn't work"
finding: the plan was to push 2.0 to make melee obviously sluggish, which the engine would have refused.

⚠ **`tools/rcon/public/app.js` shipped `def:'1.0'` + `max:'1.5'`–`2.0` on all 8 of these sliders**, so its
Reset button *disabled* the perks it claimed to tune. Fixed 2026-07-13 to the real defaults/domains above.

## Practical consequence
**To get "fast melee recovery": grant `specialty_fastmeleerecovery`. That's it.** The 0.5 default already
halves recovery time — exactly what the in-game Steady Aim Pro text ("recovery rate after lunging with
knife is reduced") describes. Push it toward 0.01 only if you want it *dramatic*.

Related: [[reference_t5_perks_and_pro_specialties]], [[engine-dvar-defaults-from-log-dump]],
[[read-the-server-not-the-file]], [[hardened-pro-flinch-perk-multiplier]].
