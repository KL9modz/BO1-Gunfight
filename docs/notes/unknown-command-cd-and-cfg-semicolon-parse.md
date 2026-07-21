---
name: unknown-command-cd-and-cfg-semicolon-parse
description: "client kill-feed 'Unknown cmd cd' (every non-updated client, every spawn, VPS) ROOT CAUSE = out-of-date Plutonium build on the VPS SERVER; updating Plutonium fixed it. NOT the mod/GSC/mod.ff/ui_xpText/vis-tweaks. cfg ;-in-comment parse is a separate server-console thing"
metadata: 
  node_type: memory
  type: project
  originSessionId: 694b8759-9d23-4472-a612-9a3763e6d16f
---

**RESOLVED 2026-07-08 — root cause was an OUT-OF-DATE PLUTONIUM BUILD on the VPS server.**
Updating Plutonium on the box made the "Unknown cmd cd" kill-feed spam stop (user-confirmed,
"error is gone"). It was **never the mod.** FastDL only ever syncs `mod.ff` — never the Plutonium
**engine build** — so a stale server build drifted out of sync and its client-facing protocol
emitted a command (`cd`) that non-updated clients rejected, rendered to the on-screen notify/kill-feed
area every spawn. The one person who never saw it (the admin/dev) kept their client current.

**Every earlier theory in this file's history was WRONG** — do not revisit them:
- NOT the per-spawn `setClientDvar` bursts. NOT `ui_xpText` (removed 2026-07-05 on a wrong hunch —
  harmless redundant cleanup, but it fixed nothing). NOT the `scr_gf_visualtweaks`/`gf_vis_*` r_*
  pushes (already stock-by-default). NOT `mod.ff` staleness (a GSC edit isn't in mod.ff anyway;
  GSC loads loose from the mod folder). NOT a missing client-side `gf.gsc` (falsified by a clean
  FastDL-only rejoin test — admin still saw no error). The literal string "Unknown cmd cd" exists
  **nowhere** in the mod or on the server (exhaustive grep of every .gsc/.cfg/.js/.txt) — that plus
  the abbreviated `cmd` (not the stock engine's `Unknown command "%s"` with quotes) was the tell it's
  the **Plutonium client layer**, i.e. a version-skew symptom, not our content.

**DIAGNOSTIC LESSON:** when an in-game string appears NOWHERE in mod/server source, suspect the
**Plutonium engine build** (server or client out of date), not the mod. Get the affected client's
`version` vs the server's early; don't chase GSC.

**FIX-FORWARD (applied 2026-07-08):** added `"%~dp0plutonium.exe" -install-dir "%LOCALAPPDATA%\Plutonium"
-update-only` as the FIRST line inside the `:server` loop of `C:\gameserver\T5\start_mp_server.bat`
(backup `start_mp_server.bat.bak-preupdate`), so every boot / crash-restart / deploy updates the
server's Plutonium before launching the bootstrapper. `plutonium.exe` lives at `C:\gameserver\T5\`
(`%~dp0`), install dir is `%LOCALAPPDATA%\Plutonium` (where `bin\plutonium-bootstrapper-win32.exe`
is). `start_mp_server.bat` is called by `gf_launch.bat`. **First-run caveat to verify in-game:**
confirm `plutonium.exe -update-only` EXITS after updating (doesn't pop/hold the launcher GUI) — if it
blocks, the server never starts. See [[vps-launch-bat-and-maxclients-latch]] and [[vps-server-provisioned]].

**Separate issue — NOW RESOLVED + SOURCE PINNED (2026-07-12).** The CoD/Pluto cfg parser splits on `;`
INSIDE `//` comments and tries to **execute each fragment**, printing a bogus `Unknown command "..."` in
the SERVER console (not the client kill-feed). The residual spam in `console_mp.log` was
`Unknown command "limit"` / `"range"` / `"value"` — which is **exactly** the `rcon_rate_limit` comment
splitting on its three semicolons:

    set rcon_rate_limit "500"   // Rate limit RCon; limit is per IP; range is 0 to 10 000; value is in milliseconds.

The predicted latent `party_minplayers` `;` was indeed still there (`(2 = public; set to 1 ...)`), plus a
`scr_teambalance` one in the tracked example. All three rewritten semicolon-free on the VPS **and** in
`server/dedicated.cfg.example`; both now audit clean (`grep -nE '//[^"]*;'` → none).

**RULE: every `dedicated.cfg` comment must be SEMICOLON-FREE** — including a comment *about* semicolons
(that one bit me while writing the fix). Audit with `grep -nE '//[^"]*;'` after any cfg edit. VPS
dedicated.cfg is never touched by deploy/git — edit on the box. The same `T5ServerConfig` template is the
source of several hostile defaults → [[sv-timeout-and-connecttimeout-template-defaults]].
