---
name: extract-dlc-map-gsc-from-fastfile
description: "DLC map GSC/CSC is NOT in the raw/ dump but IS extractable from the map's .ff — inflate the outer zlib, then inflate each rawfile's own zlib blob"
metadata: 
  node_type: memory
  type: reference
  originSessionId: b84324e5-b6fe-4b4c-a2ad-e6ef44c7cf1f
---

The `raw/` dump (`S:\...\Call of Duty Black Ops 42740\raw`) only carries **base-game** map scripts.
DLC maps (Silo, Hazard, Drive-In, Hangar 18, Berlin Wall, Zoo, …) have **no `mp_<map>.gsc` there** — but
their source is still shipped, verbatim with comments, inside the map fastfile. T5 ships GSC/CSC as
**rawfile source** and compiles at load time (which is exactly why Plutonium can run loose `.gsc`).

**The map .ff is in the PLAYABLE install, not the modtools one:**
`S:\SteamLibrary\steamapps\common\Call of Duty Black Ops\zone\Common\mp_<map>.ff`
(`...\Call of Duty Black Ops 42740\` is the modtools tree — its `zone/` holds only `mod.ff`.)

**Two layers of zlib, both raw-deflate:**
1. **Outer.** Header `IWffu100` (8 bytes) + version (4). Zlib stream starts at **offset 12**; skip its
   2-byte `78 9c` header and inflate from **14** with .NET `DeflateStream`. mp_silo → 96 MB.
2. **Per-rawfile.** In the inflated zone, each rawfile is `name\0` + 2 ints + **its own** `78 9c` blob.
   So a plain `grep` for `scr_` / `rocket` over the inflated zone **finds nothing** — the script text is
   still compressed. Find the name (`grep -aob "maps/mp/mp_silo.gsc"`), then inflate from
   `offset + len(name) + 1 + 8 + 2`.

```powershell
$fs=[IO.File]::OpenRead($ff); $fs.Position = $start + 2
$ds=New-Object IO.Compression.DeflateStream($fs,[IO.Compression.CompressionMode]::Decompress)
$ms=New-Object IO.MemoryStream; try { $ds.CopyTo($ms) } catch {}   # catch: it overruns into the next asset
```
The `CopyTo` throws at the end of the blob — **catch and keep the bytes**, the output is complete.

Grep the inflated zone for `(maps|clientscripts)/mp/[a-z0-9_/]*<map>[a-z0-9_]*\.(gsc|csc)` to get every
script for that map at once: `mp_X.gsc`, `_amb`, `_fx`, `createfx/`, and the **`clientscripts/…csc`**
counterparts — the client scripts are where a lot of BO1 MP ambient behavior actually lives
([[silo-background-missiles-are-client-side]]).

No Python on this box (the WindowsApps `python` is a Store stub) — use PowerShell + `System.IO.Compression`.
