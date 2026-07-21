---
name: deploy-recycles-box-services
description: deploy.ps1 -Mod now auto-recycles the load-once box services + sets a watchdog maintenance window; box services are NOT manual-scp anymore
metadata: 
  node_type: memory
  type: project
  originSessionId: b7eb29ae-1a0e-4ee5-9c67-df1561318167
---

As of 2026-07-10 (commit 47d6273) `deploy.ps1 -Mod` fully owns the box-side VPS services — the
older CLAUDE.md notes that say the notify/status services are "box-side (scp/restart manually), not
part of the mod mirror" are STALE.

**Why they already deployed but appeared not to:** every `GF-*` scheduled task runs its script
straight out of the mirrored mod folder (`...\storage\t5\mods\mp_gunfight\tools\...` = `$ModDest`),
so `deploy.ps1 -Mod`'s robocopy always updated their code ON DISK. The gap was that
`GF-StatusService` / `GF-ConnLogger` / `GF-JoinNotify` are load-once `while($true)` loops
(register_services.ps1), so a changed script kept running the OLD in-memory code until the process
was recycled. `deploy.ps1` only bounced the game server + `GF-RconPanel`.

**Fix (3 parts, all in deploy.ps1 / watchdog.ps1):**
- `Restart-BoxServices` bounces GF-StatusService/GF-ConnLogger/GF-JoinNotify after the mirror
  (skipped under `-NoRestart`/`-DryRun`). `GF-Watchdog` is EXEMPT — it's a short-lived task re-run
  every 3 min, so it re-reads its script on the next run with no restart.
- `Set-Maintenance` drops a self-expiring `watchdog_maintenance.json` (5-min `until`) into
  `$ModDest\tools\vps_services\` right before the bootstrapper kill; `watchdog.ps1` reads it at the
  top and stands down (no kill, no alert) while active, deleting it once expired. This kills the
  FALSE "updater wedged" page a planned deploy fires: killing the bootstrapper makes the launcher
  bat re-run `plutonium.exe -update-only` for ~2 min, which trips the 120s updater-wedge check. See
  [[deploy-restart-wedges-on-plutonium-updater]] and [[vps-server-provisioned]].
- `$xf` now excludes `.dvarcache.json`, `watchdog_state.json`, `watchdog_maintenance.json` so `/MIR`
  stops purging box-local runtime state each deploy (the churn reset the watchdog's alert memory →
  duplicate page after every deploy).

**To activate a deploy.ps1 change itself** without a server bounce (deploy.ps1/watchdog.ps1 edits
don't need a game restart): `git pull --ff-only; .\tools\deploy.ps1 -Mod -NoRestart -NoPull` mirrors
the new scripts, then manually `Stop/Start-ScheduledTask` the 3 services. `-NoPull` dodges the
self-update trap (Update-Repo exits if the pull changed deploy.ps1). Verified end-to-end 2026-07-10
(maintenance gate: active→stand-down, expired→resume+self-delete).
