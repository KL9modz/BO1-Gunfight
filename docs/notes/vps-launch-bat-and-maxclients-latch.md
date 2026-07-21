---
name: vps-launch-bat-and-maxclients-latch
description: "VPS live launcher is C:\\gameserver\\T5\\start_mp_server.bat (NOT the T5ServerConfig-master !copy); sv_maxclients lives ONLY in the bat (not dedicated.cfg) and needs a FULL bat restart — the restart-loop's `goto server` does NOT re-read `set maxclients`, so bootstrapper-taskkill / deploy.ps1 recycle keeps the old value"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6165d7a3-e1bd-4806-8147-81adb9c41b22
---

The VPS (94.72.121.4, server runs as Administrator) has TWO mp launch bats — only one is live:
- `C:\gameserver\T5\start_mp_server.bat` — **the LIVE launcher** (hardcodes gamepath `"C:\gameserver\T5"`, matches VPS_DEPLOY.md's documented launch line). Set `set maxclients=<N>` here.
- `C:\gameserver\T5\T5ServerConfig-master\!start_mp_server.bat` — stale template copy (uses `%gamepath%`); NOT live.

The VPS `dedicated.cfg` (`C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\dedicated.cfg`) has **NO `sv_maxclients` line** — sv_maxclients is supplied ONLY by the bat via `+set sv_maxclients %maxclients%`. (Unlike the local dev cfg, whose RCON-tool block does carry sv_maxclients.)

GOTCHA: the bat is a restart loop (`:server ... start /wait bootstrapper ... goto server`). `set maxclients=` runs ONCE *above* the `:server` label, so `goto server` — and a bootstrapper-only `taskkill`, which is exactly what `deploy.ps1 -Mod` does to restart — relaunches with the OLD `maxclients` env value. **Changing sv_maxclients requires a FULL bat restart** (kill the cmd.exe host + re-run the bat), best from RDP. `scr_team_maxsize` (in the cfg) likewise only reloads on the next `exec dedicated.cfg` = next full start; a live change needs `rcon set scr_team_maxsize N` or a restart.

Byte-safe remote edits over SSH: read/write via `[Text.Encoding]::GetEncoding(28591)` (Latin1) roundtrip so box-drawing chars in the cfg aren't corrupted; PS over SSH returns CLIXML unless `powershell -OutputFormat Text -EncodedCommand <b64>`.

2026-07-03: 6v6 SHIPPED (release 0.5.4). cfg `scr_team_maxsize "6"` is LIVE (the `deploy.ps1 -Mod` restart re-exec'd the cfg) and `mod.ff` 0.5.4 (with the `>4`/team green/red "alive / total" HUD readout) is deployed + FastDL-published. The running server still has `sv_maxclients 12` (the restart-loop kept the old env = exactly 6v6, no spectator slack); the bat is set to `14`, which applies the +2 spectator headroom only on the next FULL bat restart (close the console window + re-run `start_mp_server.bat`, ideally from RDP). Backups: `<file>.6v6bak`. See [[vps-server-provisioned]], [[repo-release-branch-structure]].
