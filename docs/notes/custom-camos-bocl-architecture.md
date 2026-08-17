# Custom weapon camos: how BOCL actually does it, and the claim it overturns

**Investigated 2026-08-16** against two installed reference mods, both on this laptop:
`storage/t5/mods/mp_league` (Classixz's BOCL — a **source checkout**, no `mod.ff`) and
`storage/t5/mods/bo1-snife-1.0` (snife — full source **plus** the shipped `mod.ff` +
`mp_UU_snife.iwd` + build logs). Reading them settles several open questions and **contradicts a
claim this repo was carrying**.

## ⚠ The claim that was wrong

`tools/material_spike/README.md` and `modff-cannot-embed-new-images.md` both said custom camos were

> "custom camos via `weaponOptions.csv` rows 17+ (**the BOCL pattern**: carrier material +
> `NN,camo,<image>` row + the `CalcWeaponOptions` camo index we already drive — **no weapon-file
> forks**)"

**That is not what BOCL does, and it was never evidence for it.** It was an inference drawn from
seeing `bo_cl_camo_1`-style materials plus rows 17-27 in their `weaponOptions.csv`. The actual mod
shows the opposite:

- `maps/BOCL/_utility.gsc:9-10` clamps both camo dvars to **0..15**:
  `CreateDvar("bocl_team1_camo", 0, 0, 15, "int")`.
- Custom camos are given as **entirely different weapons**, not as a camo index:
  `_utility.gsc:398-401` does `self.pers["primary_wpn"] = self.pers["wpnCamoCustom"] + "_" +
  self.pers["primary_wpn"]` → `camo1_ak47` → `GiveWeapon("camo1_ak47_mp", 0, calcWeaponOptions(0,…))`
  with camo index **0**.
- `mod.csv` carries **50** `weapon,camos/camoN_<gun>_mp` lines (5 camos × 10 guns), and
  `_utility.gsc:107-…` `precacheItem`s all 50.

So rows 17-30 in their table (`camo_1`…`camo_11`, plus `dark_matter_purple`, `camo_dark_matter`) are
**not the mechanism they ship** — the GSC can never produce those indices. They are either an
abandoned attempt or shop-UI bookkeeping. Either reading is a warning, not an endorsement: someone
added those rows and then went and forked 50 weapons anyway.

## What a BOCL custom camo actually is

A **full gun repaint**, delivered as a parallel weapon. Per (camo × gun):

| Layer | Example | Notes |
|---|---|---|
| weapon file | `weapons/camos/camo1_ak47_mp` | stock `ak47_mp` with **one** field changed — `viewmodel`: `t5_weapon_ak47_viewmodel` → `vm_ak47_camo_1` (diffed: that is the only difference) |
| xmodel | `xmodel/vm_ak47_camo_1` | stock viewmodel with the gun-body material renamed `t5_weapon_mtl_ak47_gunset` → `cc1_t5_weapon_ak47_gunset` |
| material | `materials/cc1_t5_weapon_ak47_gunset` | 501 B, techniqueSet `l_sm_r0c0n0s0_wpn_clrdtl_hero`, 5 maps: colorMap (**custom**), colorDetailMap/normalMap/specularMap/colorMap15 (**all stock, reused**) + 3 constants |
| image | `images/~-cc1_weapon_ak47_gunset_c.iwi` | the repainted diffuse, **one per gun per camo** |

Counts in BOCL: 50 weapon files, 61 xmodels, 55 `ccN_*` materials, ~30 camo `.iwi`s — for 5 camos on
10 guns.

⚠ **`mod.csv` registers ONLY the `weapon,` lines.** No `xmodel,`, no `material,`, and **no `image,`
at all** — xmodels, xmodelparts/surfs and materials all arrive via the transitive bake. This is a
second correction: the pipeline note says `image,<name>` is "MANDATORY", but BOCL ships 132 images
with zero `image,` rows. The difference is *whose* material it is — BOCL ships its **own** material
binary naming the image, so the linker just writes the reference; our molotov case registered a
**stock** material whose source the linker then tried to resolve. Ship your own material and the
`image,` row is not needed.

## ⚠ Stock camos and BOCL camos are not the same kind of thing

This is the distinction that makes the cheap route plausible, and it is easy to miss.

- **Stock camo** = **one shared material reused across every gun.** Stock row 13 is
  `camo_woodland,solid_camo_woodland,solid_camo_woodland,camo_woodland,…` — the same handful of
  material names repeated across all 17 weapon-parent columns. There is no per-gun woodland art.
- **BOCL camo** = a **per-gun repainted colorMap**. That is why they needed one image per gun, and
  why they stopped at 10 guns.

So BOCL's cost is the price of *repainting guns*, **not** the price of *adding a camo index*. Those
are separable, and nobody appears to have tried the cheap half.

## The one unknown, and the probe now shipped for it

**Does the engine accept a camo index above 15?** BO1 ships exactly 16 camos (0-15) — suspiciously
4 bits — and if `CalcWeaponOptions` packs the camo in 4 bits, indices >15 are unrepresentable and
BOCL's fork route is the only one. Nothing in either reference mod answers this, because neither
ever produces such an index.

Probe shipped 2026-08-16 (`mp/weaponOptions.csv` + the `stringtable,` line in `mod.csv`): our own
copy of the stock 148-line table with **two rows appended**, byte-for-byte clones of the
known-working rows 3 (`cammo_red`) and 13 (`camo_woodland`) with **only the index changed** to 16
and 17. Distinct materials on purpose — cloning `gold` (row 15) would be unreadable, since a clamp
back to 15 also renders gold. Test with the existing dev dvar (it has no upper clamp):

```
gf_force_camo 3    -> red      (control: the row we cloned)
gf_force_camo 16   -> red?     (clone of 3 at a new index)
gf_force_camo 17   -> woodland?
```

**ANSWER: YES.** Confirmed in game 2026-08-16 — index 16 rendered red and 17 woodland. The engine
accepts camo indices above 15, so the cheap route is real and BOCL's 50-fork stack is not required.
**Shipped: 8 custom camos at 17-24**, each one image + one carrier material, applying to every
weapon. Index 16 is kept permanently as the diagnostic control described below.

Build verified clean (`exit=0 fatal=0`, zone grew 22,240 → 34,208 B, and camo material names that
exist only in this table — `cammo_red`, `gold`, `solid_camo_woodland` — are now present in the
inflated zone). ⚠ Zone strings are **pooled/de-duplicated**, so occurrence counts cannot confirm
the added rows; only the in-game look can.

⚠ Overriding `weaponOptions.csv` means shipping the **whole** stock table — it also carries the
`lens`, `reticle` and other blocks. Ours is a verbatim copy plus 2 lines, and `build_ff.ps1`
correctly backed up and restored the stock file it staged over.

## ⚠⚠ A weaponOptions row is NOT enough — the CARRIER MATERIAL is mandatory

**This is the single most load-bearing thing in this note, and it cost a full debug cycle.** With
the table rows in place, the .iwd mounted and the images correct, every custom camo still rendered
**flat WHITE**. The log (`storage\t5\main\console_mp.log`) had the answer:

```
mp_gunfight.iwd (6 files)                      <- in the FS search path: delivery WORKED
Error: Could not load image "gf_camo_crimson".  <- ...and all six
```

So the engine read our table and asked for the images **by name** — then failed to load them. A
`weaponOptions` cell is a **runtime string lookup**; it does not register an image asset, and the
image loader will not go hunting the filesystem for one.

**The fix is a carrier material**, and it is exactly why BOCL ships `material,bo_cl_camo_1..11`
next to images `camo_1..11` that its own GSC never uses — a material in the zone references the
image by name, so the image is registered at zone load and then resolves out of the .iwd. That
apparently-pointless material block is the mechanism, not decoration.

Ours: `material,gf_camo_<n>_mtl` → image `gf_camo_<n>`, generated with
`make_material.ps1 -Family decal -SkipIwi` (the `decal` family is the one validated byte-for-byte
against BOCL's `bo_cl_camo_1`). Material name deliberately ≠ image name, mirroring theirs.
⚠ **Nothing references these materials directly — do not "clean up" an unused material row.**

⚠ White specifically is what a MISSING camo image looks like. If a custom camo ever renders white,
this is the first thing to check, not the image. (We now also ship a *deliberate* near-white camo,
`gf_camo_white` — pure `#FFF` would be a no-op, since a camo multiplies over the gun.)

## Delivery is settled, and it is the `.iwd`

`bo1-snife-1.0` is the production answer, because it holds the **shipped artifacts** next to their
sources:

- The mod folder ships exactly **`mod.ff` + `mp_UU_snife.iwd`** (68 MB). `mp_UU_snife_final` — the
  installed copy — is *only* those two files.
- The `.iwd` is a plain zip of **210 entries, every one `images/<name>.iwi`**, nothing else.
- ⚠ **Compression is `Defl:N` (normal deflate), not stored.** Our spike README guessed
  "store/no-compression to be safe" — deflate is proven in production, and at 68 MB it matters.
- Entry paths use **forward slashes**; `mp_UU_snife.files` is the 171-line manifest the build zips.
- snife's `mod.csv` likewise registers `weapon,<dir>/<name>` and **no images**.

⚠ `mp_league` has **no `mod.ff`** — it is a source checkout, so its loose `images/` folder is *not*
evidence that Plutonium reads loose mod-folder images. The `.iwd` is the route with actual proof
behind it.

## Community camo packs are CLIENT-SIDE REPLACEMENTS — re-point them, don't install them

Every BO1 camo pack on the Plutonium forum (e.g. "Coloured Gold Camo Pack", "BO1 Custom Camos MP
SSCv1") works the same way, and it is **not** a server-delivery mechanism:

- Its `.iwi` files are named after **stock** camos (`camo_woodland`, `camo_desert_nevada`,
  `camo_gold_c/env/spec`), so they **replace** stock camo art rather than adding anything.
- Install is "drop into the game's `main\` folder" (or `storage\t5\images\`), i.e. **per-player and
  client-local** — it only affects whoever installs it. Matches the standing rule that
  `storage\t5\images\` is replacement-only and client-local; it is not a route for a NEW image.
- The packaged form is an `.iwd` of `images/<name>.iwi` — **the identical shape we ship**, more
  confirmation this is simply the standard route.

Plutonium's own documentation for that folder states the rules outright, and all three are
properties of **that route**, not of custom images generally:

> Camos and other textures only work on the game they were created for, the .iwi version is
> different between games. … have to **replace an existing texture** that is already in the game,
> therefore the filename has to be the same … are **only visible to you**, other players still see
> the original texture.

Our route escapes two of the three: we ship **new** image names (the carrier material registers
them, so there is nothing to replace) and they are **server-delivered over FastDL**, so everyone
sees them. That difference is the whole value of this implementation versus any forum pack.

⚠ The **first** rule still binds us, and it is the live hazard now that we import third-party art:
an `.iwi` from another game packs, deploys and downloads perfectly and then simply does not render.
`make_iwd.ps1` therefore **refuses to package** anything whose header is not `IWi` **v13** (0x0D) —
the version every stock T5 image and every working camo here carries. Tested both directions.

⚠ **The textures are unrelated to the names they ship under** — SSCv1's `camo_desert_nevada` is
rainbow stripes, `camo_woodland` is a green/purple oil swirl. Name imported camos by their LOOK.

Re-shipped through our pipeline (new indices + carrier material + our `.iwd`) they reach every
player automatically over FastDL and stock camos survive. 10 of SSCv1's are in at **25-34**.
⚠ **Gold is not importable this way**: it is a 3-map material (`_c`/`_env`/`_spec`) and the
`colorDetailMap` route carries a single image. ⚠ Third-party art — credit the pack if it ships
publicly.

## Other things worth keeping

- **`CalcWeaponOptions` takes 5 args on T5**, not 4: `(camo, lens, reticle, clantag, emblem)` —
  BOCL passes `GetDvarInt("bocl_show_gun_clantag")` and `…_emblem` as 4th/5th. Our
  `_gf_loadouts.gsc` passes 4, so **gun clantags/emblems are an unused feature** we could switch on
  for free.
- BOCL has a ready-made camo sweeper worth stealing for any future test:
  `_utility.gsc::testWeaponCamos(wpn, start, end)` gives the weapon at each index in turn with a
  1.5 s wait and an on-screen index readout.
- Weapon-surface materials need **no `material_properties`** twin (BOCL ships those only for its 2D
  `bo_cl_*` materials); 2D/HUD ones do.

Related: [[custom-weapon-modff-pipeline]], [[modff-cannot-embed-new-images]],
[[special-weapons-precacheitem-and-camo]], [[build-stage-transitive-menu]].
