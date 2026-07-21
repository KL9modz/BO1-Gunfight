---
name: invalid-weapon-finger-gun-fallback
description: "In Pluto T5/BO1, GiveWeapon with an invalid weapon token yields the engine's default \"finger gun\" (not an error). ks23_mp is invalid; hs10_mp works as a single. Easter-egg idea."
metadata: 
  node_type: memory
  type: project
  originSessionId: 1a6cc2e8-9070-4faf-b14b-859aef9ac7bb
---

In Plutonium T5 (BO1), calling `GiveWeapon()` with an **invalid / non-existent weapon token** does not error or leave the player empty-handed — the engine hands out its **default fallback weapon, a "finger gun"** (player points a finger; no real weapon). Found 2026-07-06 while validating shotgun tokens for the Gunfight loadout catalog:

- `hs10_mp` — **valid**, gives a real single HS-10 (the "akimbo only" note in [[reference-t5-mp-weapons]] was wrong; `hs10dw_mp`/`hs10lh_mp` are the akimbo variants).
- `ks23_mp` — **invalid** in MP; gives the finger-gun fallback (a `weapons/mp/ks23_mp` rawfile exists with its own model, but it is not a functional MP weapon).

**Idea (user flagged as "save for another time"):** the finger-gun fallback could be a fun **easter egg** — a joke round, a hidden / April-Fools loadout, or a "humiliation" mode — by deliberately `GiveWeapon`-ing an invalid token so everyone gets the finger gun.
