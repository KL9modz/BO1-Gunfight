---
name: modff-cannot-embed-new-images
description: "The T5 linker writes an image REFERENCE by name, not pixel data — STILL TRUE. But 2026-08-14 the conclusion 'therefore mod.ff cannot ship a custom image' fell: Classixz/bo1-competitiveleaguemod ships 132 custom images on EXACTLY that reference-only model (material registered in the ff, .iwi delivered loose beside it). Format fully decoded, generator + verifier + tests in tools/material_spike/ (corpus-validated byte-for-byte); the laptop spike + the Plutonium delivery question are the open half."
metadata: 
  node_type: memory
  type: project
  originSessionId: c744c337-8003-4081-9056-ab50fbe151a1
---

**`tools/build_ff.ps1` + `linker_pc.exe` cannot get a new image into `mod.ff`.** An `image,<name>` line in `mod.csv` is accepted silently and the name appears in the zone, but the **pixel data is never embedded** — the linker writes only a by-name reference and resolves it at load time from whatever zones already exist. Tried 2026-07-12 and reverted; do not retry casually.

**How it was proven (reuse this method):** fill the `.iwi` payload with a sentinel byte (`0xAB`), build, then inflate `mod.ff` (it's `IWffu100` + 12-byte header + a zlib stream — skip 14 bytes, raw-inflate) and search for a long run of the sentinel. Corroborate with size: a 64×64 DXT image is 4096 bytes, so an embedded payload grows the *inflated* zone by ~4KB. Observed: **no sentinel run, zone grew 16 bytes.** Not embedded.

⚠ **The failure mode is WORSE than doing nothing, which is the real trap.** Both attempts *built clean with no linker error*:
- `material,net_disconnect` + `image,net` — the material's `colorMap` just resolved to the game's **stock** `net` image. A silent **no-op** that would have looked like "the idea failed".
- `material,net_disconnect` (patched so `colorMap` → a unique name `gfn`) + `image,gfn` — the material then points at an image present in **NO zone**, which draws the **missing-texture checkerboard**. Shipping that would have put a permanent artifact on every client's screen.

---

## 2026-08-14 — the conclusion falls: the reference-only linker was never the blocker

**`Classixz/bo1-competitiveleaguemod` ("BOCL", the retail league mod) ships 132 custom
images — rank icons, camos, team logos, menu backgrounds — on EXACTLY the reference-only
model this note proved.** Its `mod.csv` registers **zero** `image,` rows; it registers 64
**`material,`** rows (each material a tiny raw binary that *names* its image) and ships the
`.iwi` files **loose beside the fastfile** (retail: mod folder / `.iwd`, FastDL-delivered —
`sv_wwwBaseURL` in their config). The linker writing "only a by-name reference" is not the
wall; it is the *design*: the material record rides `mod.ff`, the pixels ride next to it,
and the client resolves the name at load. Our 2026-07-12 attempt 2 even reproduced the
missing half by accident — the checkerboard was the reference *working* with nothing to
resolve against.

**The raw material format is now fully decoded** (all 132 BOCL binaries parsed, 132/132
geometry + string round-trip): `[0x40 header][12-byte texture entries @0x40][20-byte
constant entries][string pool: techset, name, image, map/constant names]`, little-endian,
absolute offsets, no padding, no dedup of equal name/image strings. For a 2d single-colorMap
HUD material the whole file is 0x4F + len(name)+1 + len(image)+1 + 9 bytes; two 2d families
exist (hud sortKey 43 / decal sortKey 4) differing in 4 header constants. Companion
`material_properties/<name>` = 16 bytes (u32 0, 1, mirror-of-+0x20, garbage). `.iwi` v13 =
48-byte header with **EIGHT** u32 size slots at 0x10..0x2F (⚠ not 4 — a 32-byte hexdump
mis-called that once; the regenerated header diverged at 0x20 until fixed), then DXT payload
(DXT5 = W×H bytes; format byte 0x0B DXT1 / 0x0C DXT3 / 0x0D DXT5).

**Tooling (all committed, all tested):**
- `tools/material_spike/make_material.ps1` — fabricates the triplet. **Corpus-validated
  byte-for-byte**: regenerates BOCL's `blank`, `icon_x3`, `bo_cl_camo_1` identically.
- `tools/material_spike/verify_zone.ps1` — post-build verdict (PIXELS / REFERENCE-ONLY /
  broken), encoding this note's sentinel method + the deployed-zone baseline (102,232 B
  inflated, exactly one nul-delimited `2d`, zero `IWi` magic).
- `tools/tests/material_spike.Tests.ps1` — 13 tests pinning the format; the corpus
  comparison auto-runs when `%TEMP%\bo1-clm` exists.
- `build_ff.ps1`'s `material` case now co-stages `material_properties\<name>`.

**OPEN — the spike itself (laptop-only; this box has no linker); the delivery route is
now strongly evidenced but not end-to-end proven.** Research (2026-08-14, Wayback reads —
plutonium.pw is Cloudflare-blocked to direct fetch — plus live GitHub artifacts) settled
the ordering: **the `.iwd` is the community-standard carrier.** `Classixz/bo1-snife`'s
*shipped* mod folder is `mod.ff` + `mp_UU_snife.iwd`, and that .iwd unzips to **exactly
169 `images/*.iwi` and nothing else** — materials in the ff, pixels in the iwd, resolved
by name at load. Plutonium T5 provably mounts mod-folder .iwds client-side (an
actively-maintained iwd-only ZM mod loads its in-iwd scripts; Bot Warfare ships
`mod.ff + mp_bots.iwd`; a loose .iwd in `storage\t5` root even auto-loads globally), T5
MP mod downloading is a maintained feature (changelog r3417), and the official T5 FastDL
doc requires `.iwd`/`.iwi` MIME types on the mirror. ⚠ `storage\t5\images\` is NOT a
route: officially **replacement-only** (must match an existing texture name) and
**client-local** — it can never carry a new image. Still unknown: whether Plutonium reads
a loose `images\` subfolder *inside* a mod folder (retail does; community ships the iwd
instead), whether the dedicated binary must hold the .iwd to advertise it, and the exact
downloader manifest — the runbook's empirical tests + a FastDL access-log watch on a
clean join close all three. Runbook: `tools/material_spike/README.md`.

**RESULTS — RESOLVED 2026-08-16: CUSTOM IMAGES WORK.** Shipped and confirmed in game: 8 custom
weapon camos. The finding above stands unchanged (the linker still embeds no pixels), but the
delivery half is now answered:

1. **Route: a mod-folder `.iwd`.** Plutonium mounts it — the client log lists
   `mp_gunfight.iwd (N files)` in the FS search path. Plain zip of `images/<name>.iwi`, forward
   slashes, **Deflate** (snife's shipped 68 MB `.iwd` uses `Defl:N`; the "store to be safe" guess
   in the spike README was wrong). Built by `tools/make_iwd.ps1`.
2. ⚠ **A mounted image is NOT a loaded image.** Delivery alone rendered everything WHITE. Anything
   referenced only by a runtime string lookup (a `weaponOptions` camo cell) never gets registered,
   and the image loader does not search the filesystem. It needs a **carrier material** in the zone
   naming the image — which is why BOCL ships `material,bo_cl_camo_1..11` for images its GSC never
   uses. See [[custom-camos-bocl-architecture]].
3. So the working shape is: **material in `mod.ff` (by-name image reference) + the `.iwi` beside it
   in the `.iwd`** — exactly the BOCL/snife model this note predicted.

**Consequence for the plug icon below:** the blocker is gone. A transparent `net.iwi`
(`-Payload transparent`, all-zero DXT5 = alpha 0) plus a `material,net_disconnect` carrier is now a
concrete, testable change rather than an unproven one.

**If delivery works, first users:** transparent `net` image (`-Payload transparent`, an
all-zero DXT5 payload decodes to alpha 0) to finally kill the plug icon below; gunfight.us
HUD branding; custom camos. ⚠ **The camo claim here — "BOCL's `weaponOptions.csv` pattern,
rows 17+ feed the same `CalcWeaponOptions` camo index, no weapon-file forks" — is WRONG and
was never evidence-backed.** Reading the actual mod (2026-08-16): BOCL's camo dvars clamp to
0..15 and its custom camos are **separate weapons** built from forked weapon files + viewmodel
xmodels + per-gun repainted `.iwi`s. Whether any camo index >15 works is open; probe shipped.
See [[custom-camos-bocl-architecture]].

---

**Consequence — the "Connection Interrupted" PLUG ICON cannot be hidden** *(as of
2026-07-12; the spike above exists to overturn this)*. [[stock-engine-string-override-via-modff]] blanks the *text* (a localizedstring, looked up by name at draw time, so an override wins). The icon is **material `net_disconnect` → colorMap image `net`** (Q3's inherited `gfx/2d/net` phone-jack). It has **no dvar**, and its screen position is **hardcoded in `CG_DrawDisconnect`**, so it cannot be moved offscreen either. Transparency was the only lever and the image pipeline blocks it. ~~Hiding it would need a genuine image asset in the zone via the Asset Manager / `.gdt` pipeline (`bin/asset_manager.exe`, `bin/converter.exe`) — unproven.~~ ⚠ That guess is retired: BOCL proves the route is a raw material + loose image, no Asset Manager involved.

**Useful things learned anyway:**
- **`raw/materials/<name>`** holds the STOCK material sources (13,373 of them) as small binaries: a header of absolute offsets into a trailing string block (`"2d"` techniqueSet | material name | image name | `"colorMap"`). A **same-length** string swap is offset-safe (and with the format now decoded, ANY-length edits are safe via `make_material.ps1`'s layout law). `net_disconnect` is 107 bytes and uses techniqueSet `2d` (alpha-blended — so alpha 0 *would* have rendered invisible).
- **`raw/images/*.iwi`** are `IWi` **v13**: 48-byte header (magic, ver, format, flags, w, h, depth, then 9 dwords — one zero + eight size slots), then payload. Format `0x0b` = DXT1 (0.5 B/px), `0x0c` = DXT3, `0x0d` = DXT5 (1 B/px). An **all-zero DXT3/DXT5 payload decodes to alpha 0** = fully transparent, so a transparent `.iwi` can be synthesized by copying a stock header and zeroing the payload — no art tools needed. (`make_material.ps1 -Payload transparent` does exactly this.)
- **`build_ff.ps1` now backs up and RESTORES** any stock file it stages over (materials live in the game's own `raw/`, and the cleanup pass would otherwise *delete* a stock modtools source from the install).
- ~~BO1 has **no loose `images/` folder** — image data lives inside fastfiles, so there is no client-side loose-file route either.~~ ⚠ Superseded: true for the BASE game's assets, but BOCL's whole image set is loose-file/iwd resolved on retail `fs_game` mods. Whether Plutonium T5 mirrors that mod-folder route is the spike's open question.
