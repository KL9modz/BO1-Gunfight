# Custom-material spike: can we ship our own images?

**Question under test:** can `mp_gunfight` ship a custom image (HUD art, killfeed icons,
custom camos, a transparent `net` to hide the killcam plug icon) on Plutonium T5?

**Status: prepared on the VPS 2026-08-14, NOT yet run — the build needs the laptop**
(the linker + `zone_source` live only in the S:\ BO1 install; this box has neither —
verified). Everything below is one command per step.

## What changed since "impossible"

`docs/notes/modff-cannot-embed-new-images.md` (2026-07-12) proved our linker writes an
image **reference by name and drops the pixel data**, and concluded custom images were
unreachable without the Asset Manager pipeline. `Classixz/bo1-competitiveleaguemod`
("BOCL") is the counterexample **that agrees with the finding**: its mod.csv registers
**zero** images — it registers 64 *materials* (each a tiny raw binary naming its image)
and ships the 132 `.iwi` files **loose beside the fastfile**. The linker never needed to
embed pixels; the client resolves the material's by-name reference against the shipped
`.iwi` at load. On retail that sideload rides the mod folder / `.iwd` + FastDL. Whether
Plutonium T5 has an equivalent resolution path is exactly what steps 5–6 test.

The material binary format was fully reverse-engineered from the BOCL corpus (132/132
files parsed; see the note). `make_material.ps1` implements it and is **validated
byte-for-byte**: regenerating BOCL's `blank`, `icon_x3` (hud family) and `bo_cl_camo_1`
(decal family) reproduces their exact bytes — pinned in
`tools/tests/material_spike.Tests.ps1` (13 tests).

## The spike, step by step (laptop)

```powershell
# 0. current repo, and make sure the working tree is otherwise clean
git pull

# 1. generate the triplet at the repo root (materials\ material_properties\ images\)
powershell -File tools\material_spike\make_material.ps1 -Name gf_test_brand -Image gf_test -Width 256
#    -> images\gf_test.iwi is 65,584 B, payload solid 0xAB: the tracer dye every test below keys on.

# 2. BASELINE build (mod.csv untouched), keep its inflated zone
powershell -File tools\build_ff.ps1
powershell -File tools\inflate_fastfile_zlib.ps1 -FastFile "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\zone\english\mod.ff" -OutFile $env:TEMP\base.zone

# 3. add ONE line to mod.csv (next to the existing material comment block):
#       material,gf_test_brand
#    then rebuild + inflate
powershell -File tools\build_ff.ps1
powershell -File tools\inflate_fastfile_zlib.ps1 -FastFile "S:\...\zone\english\mod.ff" -OutFile $env:TEMP\spike.zone

# 4. verdict
powershell -File tools\material_spike\verify_zone.ps1 -Zone $env:TEMP\spike.zone -BaselineZone $env:TEMP\base.zone -Name gf_test_brand -Image gf_test -IwiBytes 65584
```

`build_ff.ps1` stages the whole triplet itself (its `material` case now co-stages
`material_properties\<name>`; missing sources only warn) and cleans it back out of the
game's `raw\` afterwards.

## Interpreting step 4

| Verdict | Meaning | Next |
|---|---|---|
| **PIXELS BAKED** (test A) | Our linker embeds the image when the full triplet is staged — 2026-07-12 overturned outright | Skip to step 6; delivery is solved (mod.ff carries everything, FastDL already ships it) |
| **REFERENCE-ONLY** (C passes, A doesn't) | The BOCL model: material record in the ff, pixels must travel beside it | Step 5 — the delivery tests |
| **C FAIL / D FAIL** | The linker rejected or the build broke | Read the linker output; the material binary is corpus-validated, so suspect staging first |

## 5. Delivery tests (only for REFERENCE-ONLY)

Find where the Plutonium T5 **client** resolves a loose `.iwi`, most-likely first. After
each placement: `loadMod mp_gunfight` + `map mp_nuked` (listen host) → step 6 look.

1. **Mod folder, loose:** copy `images\gf_test.iwi` to
   `%LOCALAPPDATA%\Plutonium\storage\t5\mods\mp_gunfight\images\` — the literal BOCL
   layout. ⚠ If this works it is also the *production* path: the repo IS the mod folder,
   so committing `images\` ships it, and FastDL clients need it delivered too — test a
   second machine or a fresh FastDL download before calling it done.
2. **Storage raw:** `%LOCALAPPDATA%\Plutonium\storage\t5\raw\images\gf_test.iwi`
   (Plutonium's raw/ fallback — proven for rawfiles, unknown for images).
3. **IWD:** zip `images\gf_test.iwi` (folder path inside the zip: `images/gf_test.iwi`,
   **store/no-compression** to be safe), rename `gf_test.iwd`, drop in the mod folder —
   the classic retail sideload; unknown whether Plutonium T5 mounts mod-folder IWDs.

## 6. The look (in-game confirmation)

On the listen host, mid-round, in the console:

```
setdvar ui_gf_skull_mat gf_test_brand
```

The health panel's skull slots are `exp material(dvarString("ui_gf_skull_mat"))` items —
no rebuild, no new menu. (Server pushes re-set the dvar each spawn; set it after spawning.)

- **Solid/uniform tile** (0xAB DXT5 decodes to a flat ~67%-alpha color) → **image resident. Success.**
- **Checkerboard** → material resident, image not (the attempt-2 signature) → that
  delivery route failed, try the next one.
- Nothing changes → material itself didn't load; re-check step 4's C test.

## 7. Afterwards

- Record the outcome in `docs/notes/modff-cannot-embed-new-images.md` (it carries a
  RESULTS placeholder), and revert the spike: drop the mod.csv line, delete the triplet,
  rebuild.
- `materials/ material_properties/ images/` at the repo root are gitignored as spike
  workspace. If delivery works and real assets go to production, lift the ignore
  deliberately — a committed `images\` deploys to the VPS and FastDL like everything else.
- **If it all works**, the first production users, in order of payoff: transparent `net`
  image for the killcam plug (`-Payload transparent`, needs the `material,net_disconnect`
  route from the note), gunfight.us HUD branding, custom camos via `weaponOptions.csv`
  rows 17+ (the BOCL pattern: carrier material + `NN,camo,<image>` row + the
  `CalcWeaponOptions` camo index we already drive).
