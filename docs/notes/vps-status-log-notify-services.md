---
name: vps-status-log-notify-services
description: "The VPS status page / IP connection log / ntfy notify stack: the 3 boot-start tasks, the auth-gated admin view, and how it all wires together"
metadata: 
  node_type: memory
  type: project
  originSessionId: 950eb6c9-1bea-46df-8f75-8389d16391fe
---

Deployed 2026-07-03 (see [[vps-server-provisioned]]). Three SYSTEM boot-start scheduled tasks,
registered together by `tools/vps_services/register_services.ps1` (`-List`/`-Uninstall`/`-Only`):

- **GF-ConnLogger** (`tools/conn_logger`) - polls RCON `status` every 15s, writes a PRIVATE
  per-day IP log `storage\t5\logs\players_YYYY-MM-DD.log` (CONNECT/LEFT + name/GUID/**IP**/session).
  Rationale: T5 GSC canNOT read a player IP; the RCON `status` `address` column is the only native
  source, so this lives OUTSIDE the mod (no ff rebuild). Bots (no IP) excluded.
- **GF-StatusService** (`tools/status_service`) - merges `gf_state`+`gf_roster`+`status`, writes
  PUBLIC `C:\inetpub\wwwroot\live\status.json` (names only, **NO IP/GUID**, BOM-free) → served at
  `gunfight.us/live/status.json`, rendered by `gunfight.us/status.html` (read-only scoreboard,
  linked subtly from the homepage footer).
- **GF-JoinNotify** (`tools/notify/join-notify.ps1`, pre-existing) - ntfy phone alerts. Topic is
  **`gunfight`** (user switched from the random `gf-alert-4bi57bk68vs2` to the plain public name
  2026-07-03 for simplicity - accepts that a PUBLIC ntfy topic is readable/spammable by anyone).
  Lives in gitignored `tools/notify/config.json` ON THE BOX. DIAGNOSTIC LESSON: "not getting
  notifications" was NOT server-side - the box was publishing fine (verified via
  `https://ntfy.sh/<topic>/json?poll=1`, which even showed a real "KL9 joined" alert); the PHONE
  was subscribed to a different topic (`gunfight` vs the configured random one). Always check the
  topic on both ends + query the ntfy topic's `/json` to isolate server-side vs app-side.

**Admin view (with IPs):** `gunfight.us/admin/admin.html` + `admin/live/admin.json` (live roster
WITH IPs + tail of the conn_logger log). Protected by **IIS Basic auth** over the site's HTTPS -
user **`gfweb`** (password generated + set 2026-07-03 by `tools/vps_services/setup_admin_auth.ps1`;
shown once, user saved it; re-run the script to reset). FAIL-SAFE INTERLOCK: status_service writes
admin.json ONLY when a `.secured` marker exists in `admin\live\` - the marker is created by
setup_admin_auth AFTER it locks the folder, so IPs can never hit an unprotected web path. Verified:
`/admin/*` returns 401 without creds, 200 with; public status.json has zero `ip` fields.

**GF-RconPanel (added 2026-07-03):** the RCON admin panel (`tools/rcon/server.js`, zero-dep Node)
now ALSO runs ON the VPS as a boot-start SYSTEM task, bound **loopback-only** `127.0.0.1:3000`
(never public - no firewall rule, and server.js has a Host-header allowlist). Set up by
`tools/rcon/setup_rcon_vps.ps1` (installs **Node LTS - v24 now on the box**, was Node-less;
writes `secrets.local.json` profile `Local (listen)` from dedicated.cfg's rcon_password). Reach it
from a workstation via SSH tunnel: `ssh -i ~/.ssh/gf_vps -L 3000:127.0.0.1:3000 Administrator@94.72.121.4`
then `http://localhost:3000` (pick the "Local (listen)" profile). RCON stays on the box (no
plaintext-password-over-internet like the laptop→VPS setup in [[rcon-tool-vps-connect-23char-cap]]).
Local port 3000 must be free for the tunnel (stop any laptop server.js first). Deliberately NOT a
public webpage: the panel is read-WRITE server control, unlike the read-only status page.
**Laptop side (2026-07-03): the tunnel now runs SILENTLY at every login** via a Startup-folder VBS
(`shell:startup\GF-RCON-Tunnel.vbs` -> hidden powershell loop at `%LOCALAPPDATA%\GunfightRcon\tunnel.ps1`,
auto-reconnects) - non-admin (Register-ScheduledTask needed elevation, so Startup folder instead).
So just bookmark `http://localhost:3000`; no launcher needed (a `Gunfight RCON.bat` on the Desktop
also exists as a manual fallback). **BOM GOTCHA (root cause of "Connect didn't work"):** PowerShell
`Set-Content -Encoding UTF8` writes a UTF-8 BOM; server.js's `loadSecrets()` does
`JSON.parse(fs.readFileSync(...))` which THROWS on a leading BOM -> returns `{}` -> panel has NO saved
password -> Connect silently fails auth. Fix: write secrets.local.json (and any Node-parsed JSON like
status.json) with NO-BOM (`[System.IO.File]::WriteAllText(path,json,(New-Object System.Text.UTF8Encoding($false)))`).
Same class of bug bit status.json earlier. secrets now seeds BOTH `Local (listen)` + `VPS` profiles.

**Deploy survival:** `tools/deploy.ps1 -Web` `/XD`-excludes `live\` + `admin\live\` (generated
snapshots) from the `/MIR`; `-Mod` `/XF`-excludes `config.json` + `secrets.local.json` (gitignored
box-side secrets) so mod deploys don't purge them.

RCON password for all three auto-reads from `dedicated.cfg` at runtime (never stored in a script or
the logs/JSON). All are self-contained Windows PowerShell 5.1 (the box has no Node).
