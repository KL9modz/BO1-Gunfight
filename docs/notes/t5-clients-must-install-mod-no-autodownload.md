---
name: t5-clients-must-install-mod-no-autodownload
description: CORRECTED 2026-06-29 — Plutonium T5 DOES auto-download the server mod to clients on join, via FastDL (sv_wwwBaseURL). The earlier "T5 can't download mods" conclusion was a FastDL misconfiguration, not an engine limit. Manual install still works as a fallback; Plutonium build must match.
metadata: 
  node_type: memory
  type: project
  originSessionId: 4742057e-0b4d-4982-8749-a8735ac3d7de
---

**CORRECTION (2026-06-29, session 2): the prior "T5 has NO mod auto-download / FastDL is a dead end" claim was WRONG.** It was a misconfiguration conclusion, not an engine limit. Plutonium T5 (BO1) **does** download the server's mod to connecting clients, and **FastDL (`sv_wwwBaseURL`) is the mechanism that makes it happen.**

**Proof:**
1. **Local `console.log` (client, build r5328)** shows the working protocol every join:
   `Requesting mod list` → `Received mod dl info response!` → `found 4 files required for mod download!` for `mods/mp_gunfight` → `[mod dl] mod already downloaded, joining server...` (it resolves to "already downloaded" only because this box already has the mod). The download machinery is present and active.
2. **Plutonium staff Resxt, forum topic 44044, 2026-02-13:** *"It never says FastDL is made to speed up. It says FastDL is how you make the downloading happen."* And 2026-02-14 he recommends **HFS (rejetto/hfs)** as a noob-friendly host that *"handles MIME types automatically for you."*
3. **Official docs exist:** `plutonium.pw/docs/server/t5/fastdl/` and `.../t5/loading-mods/` (both Cloudflare-gated to bots; reached via the research workflow). They say: stand up any web server, **place a copy of your `mods` (and `usermaps`) folder into the web server root**, verify the files are publicly downloadable, then set `sv_wwwBaseURL`.
4. **Origin of the myth:** the 2022 Bot Warfare guide (topic 22385) literally says *"As of ... 16 June 2022, using pluto release r3259, the client doesn't support server-sided mods / downloading of mods yet."* That was true in 2022 and has since changed. Don't cite it as current.

**Why the earlier IIS test failed ("Invalid download response" / zero HTTP hits):**
- **MIME types** — IIS returns 404 for unmapped extensions (`.ff`, `.iwd`, `.iwi`). Unmapped = client gets an HTML 404 page instead of the file = "Invalid file/response." (This is exactly why staff recommend HFS, which auto-handles MIME.)
- **Wrong base URL target** — `sv_wwwBaseURL` must point at a dir that *contains* a `mods` folder, NOT at the mods folder directly. Forum (topic 27828-ish): *"the URL has to be ... a page that has a mods folder."* Resulting path: `http://<host>/mods/mp_gunfight/mod.ff`.
- **Version mismatch** — that same test session also had a r5316 client vs r5328 server, which fails the handshake independently of FastDL.

**FastDL config (current, for the Windows/IIS VPS):**
- Web root layout: `<wwwroot>/mods/mp_gunfight/mod.ff` (+ whatever else the client requests — the "4 files"). Serve a CLEAN mod copy (release content), NOT the dev tree (no `.git`/`tools`/`dedicated.cfg`).
- `set sv_wwwBaseURL "http://gunfight.us/"` (or a `/fastdl/` subpath whose child is `mods/`). Trailing slash.
- IIS: add `<staticContent>` MIME maps for `.ff`, `.iwd`, `.iwi` (→ `application/octet-stream`); GET/HEAD verbs are fine. Or run **HFS on a separate port** (staff-recommended, zero MIME fuss) to avoid touching the hardened public web.config.
- Files served **raw** over HTTP — no zip/manifest step beyond what the engine does.

**Mechanism split — mods vs maps vs assets:** all ride the same FastDL/`sv_wwwBaseURL` HTTP path. Mods: `mods/<name>/`. Custom maps: `usermaps/<map>/<map>.ff` (+ `.iwd`). Loose assets: `.iwi` etc. Put both `mods/` and `usermaps/` in the web root.

**Still true even with FastDL:**
- A **mod-less / wrong-version** joiner still gets broken menu HUD + blank localized strings + missing custom FX (those assets live in `mod.ff`); gameplay GSC runs server-side regardless.
- **Plutonium engine build must match** (e.g. r5328). FastDL delivers the *mod*, NOT the engine — players still update their launcher.
- **Manual install** (ship the release zip; load via Mods menu) remains a valid fallback and is what we shipped before. FastDL just removes that requirement for players.

**CONFIRMED LIVE on the VPS 2026-06-30:** FastDL is set up and the download endpoint is verified.
- `appcmd set config /section:staticContent /+"[fileExtension='.ff',mimeType='application/octet-stream']"` (writes the `.ff` MIME map at MACHINE/WEBROOT/APPHOST — global for all IIS sites).
- `dedicated.cfg` (live one at `C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\dedicated.cfg`, line ~43): `set sv_wwwBaseURL "https://gunfight.us/"`. Use **https** — `http://gunfight.us/` 301-redirects to https (hardened IIS) and the FastDL client may not follow it.
- `deploy.ps1 -Mod` publishes mod.ff to `C:\inetpub\wwwroot\mods\mp_gunfight\mod.ff` (commit d4eefc8+).
- Verified externally: `GET https://gunfight.us/mods/mp_gunfight/mod.ff` -> `200`, `Content-Type: application/octet-stream`, `Content-Length: 97792` (byte-exact), first bytes `IWffu100` (valid zone, not an HTML 404). STILL UNTESTED: a clean client (no mod, build-matched r5328) actually auto-joining — server was down at verification time.
- Deploy gotchas hit & fixed: (1) `deploy.ps1` self-update trap — git pull rewrites the script mid-run, so the first post-update run executes the OLD in-memory copy (no FastDL); guard added (commit b9c876c) + use `-NoPull` to run the on-disk copy. (2) Restart-Server used `taskkill`, whose stderr aborts the deploy under `ErrorActionPreference=Stop` when the server is already down; switched to Get-Process/Stop-Process (commit 58d029d). Note: the restart-loop bat only relaunches AFTER a kill — it can't start a fully-stopped server, so a deploy to a down server leaves it down (start the bat manually).

Sources: forum.plutonium.pw/topic/44044 (staff, Feb 2026), plutonium.pw/docs/server/t5/{fastdl,loading-mods}, local Plutonium console.log (r5328), forum.plutonium.pw/topic/22385 (the obsolete 2022 claim), live VPS verification 2026-06-30.
