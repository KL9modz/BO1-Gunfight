# Custom weapon files DO work on this stack — the mod.ff pipeline, measured

**Settled 2026-08-15** while shipping the molotov (`weapons/mp/gf_molotov_mp`), the first custom
weapon def this mod has ever carried. Several things here **overturn** what the repo assumed, and
one of them was silently truncating builds.

## The rule: the linker bakes everything EXCEPT image pixels

`raw/images` in the mod tools holds only **186 sample textures**; every real game texture lives
inside the shipped `.ff` zones. So the linker can never re-bake a stock material, and it says so,
loudly, once per asset:

```
ERROR: image 'images/~-grus_exp_molotovcocktail_c.iwi' is missing
    failed loading material 'mc/mtl_weapon_molotov_grenade' for asset 'mp/gf_molotov_mp' ...
```

**These are non-fatal and expected.** The linker degrades to writing the asset **reference by
name**, finishes with `link...compress...save...done.`, and **exits 0**. The client resolves the
name at runtime out of `common_mp.ff`, where the asset is resident. This is the same reference-only
behaviour already documented for images in [[modff-cannot-embed-new-images]] — it simply applies to
*every* asset class, not just images we author.

| Asset class | Baked into mod.ff? |
|---|---|
| weapon def, xmodel, xmodelparts/surfs, **xanim**, material, `.efx` | **yes** — pulled transitively |
| image (`.iwi`) **pixels** | **no** — reference only, must be resident or delivered |

⚠ **`image,<name>` embeds nothing, but it is still MANDATORY.** Two separate facts, and conflating
them cost two broken builds. It does **not** carry pixels: re-proven 2026-08-15 with a full valid
triplet (material + material_properties + a 65,584 B sentinel `.iwi`), the zone grew **32 bytes,
not 65,536**, and the 0xAB dye never appears. But the row still **registers the image asset so a
material can bind to it** — drop it and the link asserts or dies. Ship the `.iwi` anyway: it is
what has to reach the client beside `mod.ff`.

## ⚠ The transitive bake is REAL (this was an open question)

The investigation that preceded this could only *infer* that a `weapon,` entry pulls its models and
anims. It does. Adding one weapon entry took `mod.ff` from **22,240 B → 178,624 B**, and the
inflated zone contains `viewmodel_molotov_idle`, `_throw`, `_light`,
`projectile_rus_molotov_grenade` and `viewhands_usmc` — none of which has a `mod.csv` entry of its
own. **No `xanim,` / `xmodel,` lines are needed, and none were used.**

This is what unblocks the melee weapons: geometry and animation are free, only textures are gated.

## ⚠ `build_ff.ps1` treated the benign errors as failure, and that TRUNCATED the build

`Invoke-Linker` threw on `$exitCode -ne 0 -or ($output -match "^ERROR:")`. Since every stock asset
reference produces an `ERROR:` line, the first custom weapon made the wrapper throw **after the
first (named-zone) link had already succeeded and saved**, so the *second* link — the one that
writes `mod.ff` — never ran. The named zone was fresh while `mod.ff` was stale, which looks exactly
like "my change didn't take".

Now judged on **fatal errors + a saved zone**, not on the ERROR count:

```powershell
$benign = "^ERROR: (image '.+' is missing|effect '.+' not found)"
```

Calibration check, both directions: it passes the good build (`exit=0 zoneSaved=True fatal=0
benign=18`) and still fails a genuinely crashed one (below).

## ⚠ A failed build used to leave staged files shadowing the stock game

The cleanup pass sat **after** the `try/finally`, so a linker throw skipped it and left all 11
staged files in the game's `raw/` tree — where Plutonium reads them as a fallback **over stock, with
no mod loaded**. Moved into the `finally`. A failed build is precisely when cleanup matters.

## ⚠⚠ The linker pops MODAL ASSERT DIALOGS, and `-nopause` does not stop them

**Read this before diagnosing any linker hang or crash.** `linker_pc.exe` throws Windows assert
dialogs (a small window, e.g. `fileSize > 0`, with an OK button). Consequences that wasted an
entire debugging session on 2026-08-15:

- An automated/backgrounded build **looks like a hang**. It is not hung, it is waiting for a click
  nobody is there to give. Wall-clock timings from such a run are meaningless.
- **`exit=-2147483645` is `STATUS_BREAKPOINT` — that IS the assert**, not a segfault. So "it
  crashed" and "it hung" were the same event, differing only in whether someone clicked OK.
- The crash *location* therefore appears to move between runs, which made it look like memory
  corruption and sent me chasing missing FX textures that were never the cause.

If a build hangs or returns -2147483645: **look at the desktop for a dialog first.**

## ⚠⚠ build_ff.ps1 DELETED STOCK FILES from the game install

The trigger for that assert was self-inflicted. The cleanup pass iterated `$assetsToStage` — every
asset mod.csv *mentions* — and deleted whatever sat at each path unless a backup existed. But
staging is **skipped** for an asset we ship no local source for (a `material,` row naming a stock
material), so no backup is recorded, and cleanup then found the **stock** file there and removed
it. `raw\materials\hud_icon_molotov` and its `material_properties` twin were destroyed that way;
the next build asserted `fileSize > 0` trying to read the file we had deleted.

Fixed: cleanup now keys off `$stagedPaths`, populated only when this script actually writes a file.
**Only ever remove a file the build created.** Two further guards came out of the same session:
paths are normalised *before* de-duplication (mixed `/` and `\` forms made the script back up its
own staged copy as if it were stock, then restore it into the game tree), and the whole pass runs
in `finally`.

Belt and braces: we now ship our **own** `materials/hud_icon_molotov` + `material_properties/`
(generated by `tools/material_spike/make_material.ps1`, corpus-validated format), so the build no
longer depends on the game install's copy at all. The install's originals were restored with
regenerated equivalents — **not byte-identical to Treyarch's**, so a Steam "verify integrity" on
appid 42740 is the exact fix if it ever matters.

## Gotchas worth keeping

- **`weapon,mp/<name>` — the `mp/` is mandatory.** All 775 stock `weapon,` lines in the game's own
  `zone_source` carry `mp/` or `sp/`. A root-level `weapon,gf_molotov_mp` is rejected outright:
  `failed loading 'gf_molotov_mp' of type 'weapon'`. Keep the *filename* unique (`gf_*`) so staging
  can never overwrite a stock modtools source.
- **`weapon/molotov/fx_molotov_exp` CRASHES the linker** (`exit=-2147483645`, STATUS_BREAKPOINT),
  faulting right after its scorch-mark decal (`mc/` + `wc/gfx_fxt_decal_scorch_mark`) whose image is
  missing. Decal materials appear not to survive the missing-image degradation that ordinary
  materials do. Replaced with `env/fire/fx_fire_lg` (source exists, resident in MP). If a future FX
  crashes the build, suspect a decal.
- **FX path shape**: the zone string `fire/fx_fire_lg` is a *substring* of the real
  `env/fire/fx_fire_lg`. Grepping a zone for an FX name gives you the tail, not the path.
- **`raw/fx/fire/` is empty** — fire FX sources live under `raw/fx/env/fire/`.

## Why the molotov specifically was cheap

Treyarch left the SP molotov's assets in the **multiplayer** zone. Verified resident in
`common_mp.ff`: `viewmodel_rus_molotov_grenade`, `weapon_rus_molotov_grenade`, both materials, all
six colour/normal/spec images, `fx_molotov_burn_trail`, and all four `wpn_molotov_*` sound aliases.
The weapon file is the stock `raw/weapons/sp/molotov_sp` with **16 of 384 fields** changed.

Two substitutions were forced, both because the asset is absent from MP **and** unbakeable:

- `hudIcon` / `killIcon`: stock `hud_icon_molotov` needs image `hud_molotov`, which has **no raw
  source at all**. Replaced with the Napalm Strike icons `hud_icon_air_napalm` / `hud_obit_napalm`,
  both verified resident (material + colorMap).
- `handModel`: `viewmodel_hands_cloth` is SP-only → `viewhands_usmc`, what every stock MP offhand
  uses.

## The molotov's damage is STOCK — do not "fix" it

`explosionRadius` / `InnerDamage` / `OuterDamage` are Treyarch's own **200 / 250 / 40**, unchanged
from `raw/weapons/sp/molotov_sp`. An earlier pass here shipped invented values (150/300/60) tuned
around the Flak Jacket interaction below; that was an **unrequested balance change and was reverted
2026-08-15**. Balance for this mode is the owner's call, not a side effect of adding a weapon. If
the molotov ever needs retuning, that is its own deliberate change with a playtest behind it.

## ⚠ Context for whoever does tune it: explosives here are multiplied by 0.35

Worth knowing before touching any explosive number, and it is **pre-existing, not caused by the
molotov**: everyone carries `specialty_flakjacket` (base perk set) and we never set
`perk_flakJacket`, so the engine default **35** applies — `_class::cac_modified_damage` does
`final_damage = int(old_damage * (35/100))`, a **65% cut on every explosive**. It already applies to
our frags, semtex and tomahawk today. At stock values the molotov's epicentre lands at
`250 × 0.35 ≈ 87`, i.e. **not lethal on its own** against 100 HP.

⚠ **Untested**: `projImpactExplode 1` means a *direct* hit may register as `MOD_PROJECTILE`, which
`cac_modified_damage` excludes from Flak Jacket entirely — so a direct hit could land the full 250
while splash stays at 35%. Look at it in game before drawing any conclusion about how it feels.
Overkill is harmless for scoring (`gf_onPlayerDamage` caps each hit at the victim's current HP).

Related: [[modff-cannot-embed-new-images]], [[build-stage-transitive-menu]],
[[special-weapons-precacheitem-and-camo]], [[modff-drift-vs-gsc-deploy]].
