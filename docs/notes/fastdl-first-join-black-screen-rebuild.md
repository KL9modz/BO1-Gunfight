---
name: fastdl-first-join-black-screen-rebuild
description: "Why first-join FastDL hangs at a black screen for minutes on Plutonium T5 — in-place engine rebuild with no UI; empty ui_mp/mod.txt stub kills a measured 4.6s stall; 'found N files' advertisement semantics"
metadata: 
  node_type: memory
  type: project
  originSessionId: ceddb6e3-e06d-4666-b628-539d12d11391
---

Root cause of the "mod hangs on first download" symptom (researched 2026-07-01, evidence from local Plutonium logs + forum/docs).

**Mechanism (client-engine-side, unfixable from the server):** after the first-time FastDL download completes, the Plutonium T5 client switches fs_game in place with NO loading UI: full FS_Startup → unload ALL loaded fastfiles → **destroy + recreate the D3D9 window/device** (the fresh blank window IS the black screen) → reload ~180MB of zones + mod.ff → re-exec configs → full Demonware stats/CAC re-sync. Waiting it out works (it IS progressing); killing + restarting works because the restart cold-boots into the **cached** mod ("[mod dl] mod already downloaded, joining server..." in console_mp.log) with a normal loading UI. Every join re-runs the mod-list handshake but skips the HTTP fetch when the local copy checks out — so the expensive path runs exactly once per client.

**Measured stall + fix:** the engine hard-looks-up the menufile asset `ui_mp/mod.txt` on every mod load and the DB layer **blocks ~4.6s** when it's missing (`Waited 4597 msec for missing asset "ui_mp/mod.txt"` in console.log). Fixed 2026-07-01: mod.ff now ships an EMPTY `ui_mp/mod.txt` stub (`{ }` — must NOT loadMenu anything, see the menufile double-load pitfall). `mod.arena` lookup also fires but is non-blocking — not worth shipping.

**"found N files required for mod download":** the server advertises every file in the mod folder matching downloadable extensions (`.ff .arena .iwi .iwd .files .csv .wav .gsc .csc` per plutonium.pw/docs/server/t5/fastdl). The VPS mod folder is a full mirror of main (mod.csv + all GSC = downloadable extensions) while IIS hosts only mod.ff — if the VPS log says >1 file, first joiners grind 404 retries. CHECK PENDING on the VPS (local server-mode run showed "found 1 files"; dev client showed "found 4").

**Player-stuck fallback (staff-endorsed):** alt-tab to the Plutonium bootstrapper console window and type `vid_restart` (forum.plutonium.pw/topic/10142).

Sources: forum.plutonium.pw/topic/44494 (multi-attempt download cycles are normal), topic/26441 ("Fetching stats" multi-minute stall lives in the re-sync path), plutonium.pw/docs/server/t5/fastdl. Related: [[t5-clients-must-install-mod-no-autodownload]], [[build-stage-transitive-menu]].
