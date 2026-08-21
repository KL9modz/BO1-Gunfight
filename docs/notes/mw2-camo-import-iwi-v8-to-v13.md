# MW2 camo import, and the two camo-table rules it uncovered

**2026-08-20/21.** Four Modern Warfare 2 camos shipped, converted out of a retail MW2 install. The
import itself was the easy half. The audition that followed turned up **two properties of
`weaponOptions.csv` that nothing in this repo knew**, one of which silently breaks camos you never
touched — read those two sections even if you never care about MW2.

## What shipped

| index | camo | notes |
|---|---|---|
| 30 | MW2 Blue Tiger | navy tiger stripe |
| 31 | MW2 Red Tiger | red/black tiger stripe |
| 32 | MW2 Red Urban | red/grey urban splinter |
| 33 | MW2 Orange Fall | orange/yellow autumn |

Cut after looking at them in game: Woodland, Desert (too close to stock 13/5), Digital, Arctic,
Bush Dweller. In the same pass the **17 never-rollable camos were deleted outright** (rows, art,
materials) and the shipped set became exactly the rotation: 13 existing + these 4.
⚠ Net effect on the download: `mp_gunfight.iwd` went **998,582 B → 846,728 B** — smaller than before,
while gaining four camos and seventeen furniture textures.

## Why MW2 is an unusually easy source

**MW2 keeps its textures in loose `main\iw_NN.iwd` zips.** BO1 does not (its art is inside `.ff`
zones), so every MW2 texture is one `unzip` away — no fastfile extractor, no Greyhound/Wraith:

```
unzip -j "…\Call of Duty Modern Warfare 2\main\iw_07.iwd" "images/weapon_camo_*" -d art\mw2
```

`iw_07.iwd` holds nine tiling camo tiles (`128x128 DXT1`) plus eight `weapon_camo_menu_*` UI swatches
(`408x152`, non-tiling, useless as camo). ⚠ **MW2's gold is not importable** — it ships as
`weapon_desert_eagle_gold_col`, a per-weapon UV-mapped diffuse, i.e. the per-gun repaint category a
camo cell provably cannot deliver ([[custom-camos-bocl-architecture]]).
⚠ This does **not** generalise forward: MW3/BO2/Ghosts went fastfile-only.

## The conversion: IWi v8 -> v13 (`tools/iw4_iwi_to_t5.ps1`)

|          | IW4 v8 (MW2) | T5 v13 (BO1) |
|---|---|---|
| magic | `"IWi" + 0x08` | `"IWi" + 0x0D` |
| format / flags | `[8]`, `[9]` | `[4]`, `[5]` (`0xC3`) |
| width / height | `[10]`, `[12]` | `[6]`, `[8]` |
| mip slots | 4 x u32 end-offsets | 8 x u32 |
| header | 32 B | 48 B |

⚠⚠ **v8 stores its mip chain SMALLEST-FIRST — mip 0 is the file's TAIL.** Take the head and you get a
structurally valid image that renders as a smear, with no error anywhere. Worked example,
`weapon_camo_woodland.iwi` (128², DXT1, 10,968 B): offsets `10968, 2776, 728, 216`, where
`216 = 32 + 8+8+8+32+128` (header + mips 1..16px), and mip 0 is the last 8,192 bytes. The tool
**verifies** this off `offsets[0]`/`offsets[1]` and refuses a file that disagrees.

Everything else is `dds_to_iwi.ps1`'s trick: same raw DXT blocks, so it is a header swap — no
re-encode, no quality loss.

## ⚠⚠ RULE 1: a camo is identified by its ROW POSITION, not by the index column

**This cost the most time tonight and it fails in the most confusing way possible.** The engine
resolves `gf_force_camo N` (and every loadout camo) to the **Nth camo row in the file**. The number in
column 1 is decorative. While the block runs contiguously 0..N the two always agree, so nothing
reveals it.

Deleting the 17 unused camo rows shifted every row after the first gap:

- `gf_force_camo 20` (Toxic) rendered **Violet** — position 20 in the pruned block.
- Camos 47-50 rendered **nothing at all** — they pointed past the end of a 34-row block.
- Camo 17 (Crimson) still worked, because it sits **before** the first gap.

⚠ **Never delete a camo row without renumbering the block, and never leave a gap.** The symptom
appears on camos nowhere near the row you removed, and "the new camo renders nothing" looks exactly
like a delivery failure — we checked the `.iwd`, the carrier materials, the zone strings and the
client log before the position theory occurred to anyone. Diagnostic: force a camo whose index is
*after* a gap; if you get its neighbour's art, the block is misaligned.

## ⚠ RULE 2: the six "solid" columns are per-material, and one size does not fit them

Stock rows 5-14 put a flat 8x8 swatch in **f4, f5, f10, f12, f14, f19** and the tile everywhere else.
Those six are the plastic/wood/black furniture materials, whose UVs magnify a texture far harder than
the metal ones. Our rows 17+ used to put the tile in all 17 columns, which is the **smear**: one blob
of tile stretched across a whole handguard, mismatched against fine weave on the receiver.

Stock's fix is the flat swatch. We tried it and the owner rejected it (a plain panel, which is exactly
what stock looks like). What shipped instead: **only `cammo_gunplastic` (f4) gets a finer variant**
(`<camo>_solid`, 8 repeats via `tools/camo_shrink.ps1`); **every other furniture column takes the base
tile**, the same one the metal uses.

Measured, one gun at a time — the numbers are not transferable between columns:

| column | surface | verdict |
|---|---|---|
| f4 `cammo_gunplastic` | Commando shroud | 2x coarse, 4x coarse; ships **8 repeats** (existing camos) / **6x** (MW2) |
| f5 `cammo_wood_tile_red` | AK47 wood grip | 2x **too fine** -> base tile fixed it |
| f19 `cammo_base_L96A1` | — | **INERT, see open question** |
| f10/f12/f14 | MPL / black / MAC11 | inferred from the AK, unverified |

**19 of 53 weapons** touch f4 (aug, commando, enfield, famas, galil, hs10dw, ithaca, kiparis(dw), m14,
m16, m60, psg1, rpk, spas, spectre, stoner63, uzi, wa2000); the other 34 now render one uniform tile.

⚠ **Scale variance WITHIN one column is unfixable from a camo cell.** The FAL's stock top and sides
disagree at every setting because their UV densities differ; so do a Commando's shroud and receiver.
Treyarch hit the same wall — the flat swatch is a surrender, not a design.
⚠ And matching an extreme magnification is self-defeating: at 16 repeats the tiger stripe degrades into
a regular dotted mesh (rendered and rejected). **Character or scale, pick one.**

## Tooling added

- **`tools/iw4_iwi_to_t5.ps1`** — IW4 v8 -> T5 v13, layout-verified.
- **`tools/camo_punch.ps1`** — contrast/brightness by transforming each DXT1 block's two 565
  **endpoints**, plus `-TileN` block-grid tiling. Both are pure block operations: **lossless, no
  re-encode**. ⚠ A block whose endpoint order would flip is left untouched (that order is DXT1's
  4-colour vs 3-colour+black **mode bit**).
- **`tools/camo_shrink.ps1`** — the one place we genuinely re-encode: decode, box-downscale, DXT1
  range-fit encode, then block-tile up. Encoding targets the **shrunk** image (64² = tiny), so it is
  fast. This is how a furniture variant gets 8 repeats at 512² instead of a 2 MB texture.
- Shipped art derives as: metal = `camo_punch -Contrast 1.35 -Bright 1.05 -TileN 3` (MW2; 4x read "a little fine" in game) or the
  original tile (existing camos); furniture = `camo_shrink -Shrink 8 -TileN 8` for the 13 existing camos, `camo_punch -TileN 6` for the MW2 four.

## Smaller findings, each of which cost a cycle

- **`fungive_<weapon>` used to strip the camo** — a bare `GiveWeapon(w)` is camo index 0, so swapping
  weapons during a camo review silently gave you a plain gun. Now camo-aware (`_gf_fun.gsc`, honours
  `gf_force_camo`). With god mode it makes weapon-by-weapon review instant, no round restart.
- **A loose `images/*.iwi` does NOT override the mod's own `.iwd`** (tested: replaced a loose file,
  `map_restart`, no change). The mod folder outranking *stock* IWDs
  ([[mod-folder-is-first-in-client-fs-search-path]]) does not extend to our own package. So every art
  tweak costs a `make_iwd` **and a full client restart** — a reconnect is not enough, and neither is a
  map change.
- **`mod.ff` changes need a client relaunch too.** The zone is read at launch; reconnecting reuses it.
- **`preview_iwi.ps1 -Full` was scrambling rows** — `[int]($t / 4)` is PowerShell **banker's
  rounding**, giving `0,0,0,1,1,1,2,2,2,2,2,3,3,3,4,4` instead of four rows of four. It painted a fake
  dot lattice that reads as woven detail. Fixed to `[Math]::Floor`. ⚠ `[int]` in PowerShell is not
  truncation.
- **Plutonium drops rcon sends that arrive too fast after a restart** — several `set`s came back "(no
  reply)" and genuinely did not apply. **Read every value back**; do not trust the send.

## Open question: what paints the L96A1's stock?

Its row names `cammo_gunmetal` + `cammo_base_L96A1` (f19), and its stock renders visibly finer than its
barrel. **f19 is inert**: pointing row 17's f19 at Toxic's acid-green tile changed nothing on a
relaunched client, while f4/f5 changes on the same build were plainly visible. The L96 is also **not**
in the f4 group, so both of its declared columns are ruled out and the driver is unknown.

⚠ Do not "fix" this by guessing at a column. The next step is to green-test the *other* columns one at
a time on that gun, or to accept that the weapon->material mapping in the table is not the whole story.
Cosmetic and low priority: one surface on one sniper.
