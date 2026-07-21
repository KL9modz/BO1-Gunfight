---
name: gf-admin-connection-history
description: "The VPS admin page's searchable multi-day connection history (find who connected days ago) + conn_logger now reading admin.json instead of rcon; data flow, files, and the ip:port human filter (built 2026-07-05)"
metadata: 
  node_type: memory
  type: project
  originSessionId: f7f2d832-7d28-4029-8c46-9a43fa4f61dd
---

Built 2026-07-05 (deployed live to the VPS via scp; **NOT yet committed** to git as of that
session — a future `deploy.ps1 -Web`/`-Mod` git-pull would revert the live files unless committed).

**Goal:** let an admin find someone who connected days ago (before a reboot) from
`gunfight.us/admin/admin.html`. The permanent per-day IP log already existed
(`storage\t5\logs\players_YYYY-MM-DD.log`, written by conn_logger, survives reboots); the admin page
just wasn't surfacing more than today's tail.

**Data flow now:**
- `conn_logger.ps1` → appends CONNECT/LEFT/ONLINE (ts + IP + GUID + session) to `players_YYYY-MM-DD.log`.
  **CHANGED 2026-07-05:** it no longer rcon-polls — it diffs `status_service`'s `admin.json` FILE
  (`C:\inetpub\wwwroot\admin\live\admin.json`, which carries per-player IP + GUID). Zero rcon of its
  own; 5s cadence (was 15s). Missing/stale(>`-StaleSeconds` 30)/`online:false` snapshot → skip the
  tick (never a mass-LEFT). admin.json is written atomically (temp+Move) so reads never tear.
- `status_service.ps1` → every 5s writes `admin.json` (roster+IP+**guid**, `.secured`-gated) and the
  public `status.json` (no IP). Also builds `admin_history.json` in the same `.secured` folder every
  **60s** (`Build-ConnHistory`: reads last `-AdminHistoryDays` 60 `players_*.log` files, newest-first,
  capped `-AdminHistoryMax` 5000 events).
- `admin.html`/`admin.js` → a **Connection history** card (own `#history` container so the 5s roster
  re-render can't wipe the search box) fetches `live/admin_history.json` and client-side filters by
  name / IP / GUID.

**guid plumbing:** the panel's `parseStatusText` already returns `guid` (p[3]); status_service was
DROPPING it. Added `guid` to the tick-path player map, the direct-rcon `Parse-StatusPlayers`, and
`$adminList`. So admin.json (and thus the log + history) now carry guid; public status.json does not.

**ip:port human filter (bug found + fixed same day):** a phantom entry "DAA" (guid 0, address column
holding a *lastmsg* value that changes each tick — a bot the panel's `guid==0 && addr=='unknown'`
check missed, or a still-connecting client) leaked into admin.json as a "human", inflating the count
AND (because guid-0 keys fall back to the moving bogus ip) spamming CONNECT/LEFT every tick. Fix:
BOTH `conn_logger` (`Get-CurrentPlayers`) and `status_service` (the `$list`/`$adminList` loop) now
require a real `ip:port` per player (status_service also allows listen `local`/`loopback`); the old
direct-status conn_logger had this guard and it was lost in the admin.json switch. This also
corrected the public human count (a bot no longer shows as a player).

**Ops:** services = `GF-StatusService` (5s) + `GF-ConnLogger` (5s), SYSTEM scheduled tasks via
`register_services.ps1`. To apply script changes: scp to the storage mods `tools\...` path, then
`Stop`/`Start-ScheduledTask` (status) or re-run `register_services.ps1 -Only GF-ConnLogger` (logger).
Remote PS over SSH: the bash→ssh layer STRIPS `$` — drive ssh from the local PowerShell tool with a
base64 `-EncodedCommand` (`[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($here))`).

Related: [[rcon-panel-queue-saturation]] (the "one box-side rcon reader" rule this reinforces),
[[svtimeout-connect-twice-firstjoin]], [[vps-server-provisioned]] (SSH access).
