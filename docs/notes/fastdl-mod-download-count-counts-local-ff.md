---
name: fastdl-mod-download-count-counts-local-ff
description: "client log 'found N files required for mod download' counts .ff in the LOCAL mod folder RECURSIVELY (incl. nested tools/dist build copies), NOT the server's advertised manifest. VPS advertises 1 (mod.ff); a scary dev-box '4' = stale tools/dist copies, not a FastDL regression"
metadata: 
  node_type: memory
  type: project
  originSessionId: 86bb72be-2616-4611-9b93-de0c6736a9f5
---

The CLIENT `console_mp.log` line `found N files required for mod download!` is the client's
**recursive FS scan of its LOCAL `mods/mp_gunfight` folder counting `.ff` files** (the scan's
extension set is .ff-only — .csv/.gsc are NOT counted). It is NOT the server's advertised
download manifest.

On the dev box it read **4** because `tools/dist/` (gitignored build output) sits UNDER the live
client mod folder, so 3 stale nested `mod.ff` copies get counted alongside the real root one:
`tools/dist/stage/.../mod.ff`, `.../branch-stage/.../mod.ff`, `.../server-stage/.../mod.ff`.
Harmless — the client loads only the ROOT `mod.ff`, and the join logged `[mod dl] mod already
downloaded ... No mods to download!`. Silence it with `rm -rf tools/dist` on the dev box (it
regenerates on the next package run).

The VPS **SERVER advertises exactly 1** file (mod.ff) — verified across 149+ log occurrences,
always 1, even when the folder also held mod.csv + gametypesTable.csv + a full maps tree. IIS
FastDL (`C:\inetpub\wwwroot\mods\mp_gunfight`) serves exactly that one byte-identical mod.ff. So
a "4 files" on a dev client is NOT a FastDL regression and NOT player-facing — do not chase it as
one. Verify server-side with the VPS mod-folder `console_mp.log` (`found 1 files`), not the dev
client. See [[svtimeout-connect-twice-firstjoin]], [[fastdl-first-join-black-screen-rebuild]].
