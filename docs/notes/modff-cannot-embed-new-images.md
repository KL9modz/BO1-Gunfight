---
name: modff-cannot-embed-new-images
description: "The T5 linker writes an image REFERENCE by name, it does NOT embed .iwi pixel data — so mod.ff cannot ship a new/overriding image. This is why the 'Connection Interrupted' PLUG ICON cannot be hidden (only its text)."
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

**Consequence — the "Connection Interrupted" PLUG ICON cannot be hidden.** [[stock-engine-string-override-via-modff]] blanks the *text* (a localizedstring, looked up by name at draw time, so an override wins). The icon is **material `net_disconnect` → colorMap image `net`** (Q3's inherited `gfx/2d/net` phone-jack). It has **no dvar**, and its screen position is **hardcoded in `CG_DrawDisconnect`**, so it cannot be moved offscreen either. Transparency was the only lever and the image pipeline blocks it. Hiding it would need a genuine image asset in the zone via the Asset Manager / `.gdt` pipeline (`bin/asset_manager.exe`, `bin/converter.exe`) — **unproven**.

**Useful things learned anyway:**
- **`raw/materials/<name>`** holds the STOCK material sources (13,373 of them) as small binaries: a header of absolute offsets into a trailing string block (`"2d"` techniqueSet | material name | image name | `"colorMap"`). A **same-length** string swap is offset-safe. `net_disconnect` is 107 bytes and uses techniqueSet `2d` (alpha-blended — so alpha 0 *would* have rendered invisible).
- **`raw/images/*.iwi`** are `IWi` **v13**: 48-byte header (magic, ver, format, flags, w, h, depth, then 9 dwords), then payload. Format `0x0b` = DXT1 (0.5 B/px), `0x0c` = DXT3/DXT5 (1 B/px). An **all-zero DXT3/DXT5 payload decodes to alpha 0** = fully transparent, so a transparent `.iwi` can be synthesized by copying a stock header and zeroing the payload — no art tools needed. (The technique is sound; only the *delivery* is blocked.)
- **`build_ff.ps1` now backs up and RESTORES** any stock file it stages over (materials live in the game's own `raw/`, and the cleanup pass would otherwise *delete* a stock modtools source from the install).
- BO1 has **no loose `images/` folder** — image data lives inside fastfiles, so there is no client-side loose-file route either.
