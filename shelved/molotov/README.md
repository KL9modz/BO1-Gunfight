# SHELVED: Molotov (2026-08-15)

Working code, parked mid-flight. Nothing here is referenced by the live mod — `mod.csv`, `gf.gsc`
and `_gf_loadouts.gsc` all have a `SHELVED 2026-08-15` comment where its lines used to be, so
restoring is a search for that marker plus the steps below.

**State when shelved:** it built clean and ran in game. The weapon model and throw animation were
confirmed good by eye. Two things were unfinished:

1. **Fire FX** — the first attempt used a generic environment fire (`env/fire/fx_fire_lg`) and
   looked wrong. Fixed to the authentic `weapon/molotov/fx_molotov_exp`, but **never seen in game**.
2. **Icon** — unresolved, and the reason this stalled. See below.

## The icon problem, and exactly how far it got

`hud_icon_molotov` is a stock material that no MP zone loads, and it resolves to image
`hud_molotov`, which exists in **no zone and has no `.iwi` source** anywhere in the mod tools. So
the art has to be shipped.

**Proven here: this linker never embeds image pixels.** Staged a full valid triplet (material +
material_properties + a 65,584 B sentinel `.iwi`); the zone grew **32 bytes, not 65,536**, and the
0xAB tracer never appeared in it. That re-confirms `modff-cannot-embed-new-images` and means the
pixels must travel **beside** `mod.ff`.

So the open question is purely **delivery**: will Plutonium load a mod-supplied `.iwi`? That was
set up and never tested. `images/hud_molotov.iwi` here is the **sentinel pattern, not real art** —
which makes the test unambiguous:

- **flat coloured square** → delivery works; then extract the genuine `hud_molotov` art and the
  same mechanism unlocks the custom camos.
- **checkerboard** → Plutonium will not load it; fall back to a resident stand-in and the camos
  are off the table.

Fallback icons, all verified resident in `common_mp.ff`: `hud_obit_flame_attach` (a flame glyph,
the best of them), `hud_m2_flamethrower`, `hud_icon_tabun_gasgrenade`.

## Restore checklist

1. Copy `weapons/`, `images/`, `materials/`, `material_properties/` from here back to the repo root.
2. `mod.csv` — re-add at the shelve marker. Order and content matter:
   ```
   weapon,mp/gf_molotov_mp
   image,hud_molotov
   material,hud_icon_molotov
   ```
   ⚠ `image,` embeds no pixels but is **not** optional: it registers the asset so the material can
   bind. Without it the link asserts or dies.
3. `gf.gsc` `onPrecacheGameType` — re-add `PrecacheItem( "gf_molotov_mp" );` and, if using the real
   icon, `precacheShader( "hud_icon_molotov" );`
4. `_gf_loadouts.gsc` — re-add the `gf_reg` row:
   `gf_reg( "gf_molotov_mp", "Molotov", "<icon>" );` then put it in the pool. It previously took 6
   of 53 entries (2 each from frag / semtex / tomahawk, on the `aug_silencer`, `m14_grip`,
   `uzi_acog_grip`, `pm63_extclip`, `hk21_reflex` and `ithaca_grip` loadouts).
5. Rebuild `mod.ff` (**laptop only**), and rebuild `mp_gunfight.iwd` if testing that delivery route
   — it is just `images/*.iwi` zipped **stored, with forward-slash entry names**.

## Traps that cost real time — read before resuming

- **`linker_pc.exe` throws MODAL ASSERT DIALOGS and `-nopause` does not stop them.** An automated
  build looks like a hang; `exit=-2147483645` is `STATUS_BREAKPOINT`, i.e. that same assert. If a
  build hangs or returns that code, **look at the desktop for a dialog first.**
- **Damage is STOCK and must stay stock** (200 / 250 / 40). An earlier pass shipped invented values
  and that was reverted. Balance is the owner's call, not a side effect of adding a weapon.
- Everyone carries Flak Jacket and `perk_flakJacket` defaults to 35, so **every explosive lands at
  35%**. Stock 250 at the epicentre is ~87, i.e. not lethal on its own. Pre-existing; applies to the
  frags and semtex too.
- `weapon,mp/<name>` — the `mp/` is mandatory; a root-level name is rejected outright.
- The weapon's own `hudIcon`/`killIcon` were left on resident stand-ins
  (`hud_icon_air_napalm` / `hud_obit_napalm`) so only the loadout tile tested the delivered image.

Full pipeline write-up: `docs/notes/custom-weapon-modff-pipeline.md`.
