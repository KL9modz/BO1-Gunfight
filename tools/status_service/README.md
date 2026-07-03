# status_service - public live-status snapshot for the website

Polls the dedicated server over loopback RCON and writes a small, **public-safe**
JSON snapshot that `site/wwwroot/status.html` renders as a read-only scoreboard:
map, gametype, match score, per-team roster (alive/ping), and a short
recent-activity feed. It's a read-only "RCON for the public" - no commands, no
control.

## Data flow

```
game server --(loopback RCON: gf_state; gf_roster; status)--> status_service.ps1
   --> C:\inetpub\wwwroot\live\status.json  --(IIS static)-->  status.html (browser fetch, 5s)
```

Merges the same three sources the RCON panel uses:
- `gf_state`  -> `alliesWins:axisWins:round:aliveAllies:aliveAxis:gametype`
- `gf_roster` -> `<num>,<team>,<alive>,<pending>;...`
- `status`    -> per-client num / name / ping

## Privacy (important)

`status.json` is **world-readable** (served by IIS). It carries player **names
only** - exactly what anyone sees in the in-game server browser. It does **NOT**
contain IP addresses or GUIDs. The IP connect log lives in `tools/conn_logger`
and stays **private on the box** - it is never written to the web root.

The RCON password is read from `dedicated.cfg` at runtime and never written out.

## Deploy notes

- The snapshot is written to `wwwroot\live\` **on the box**. `tools/deploy.ps1 -Web`
  excludes `live\` from its `/MIR`, so publishing the site never purges it.
- `status.html` is part of the tracked site source and ships with `deploy.ps1 -Web`
  like any other page. It is `noindex` and not linked from the homepage by default -
  share the URL (`https://gunfight.us/status.html`) or add a link when you're ready.
- IIS serves `.json` with the correct MIME by default; no `web.config` change needed.

## Admin view (with IPs) - password protected

There is a second, **private** page at `wwwroot\admin\admin.html` that shows the live
roster **with IP addresses** plus a tail of the connection log. Its data
(`admin\live\admin.json`) is written by this same service but is **fail-safe gated**:

- Pass `-AdminOutFile "C:\inetpub\wwwroot\admin\live\admin.json"` (the registrar does).
- The service writes it **only if** a `.secured` marker exists in that folder.
- The marker is created by `tools/vps_services/setup_admin_auth.ps1` **after** it
  configures IIS Basic auth on `wwwroot\admin`. So IP data can never reach the web
  root before the folder is locked - no leak window.

Secure it (once, elevated, on the box):
```powershell
# in tools\vps_services\
powershell -ExecutionPolicy Bypass -File setup_admin_auth.ps1
```
That installs IIS Basic Auth + creates a dedicated low-priv Windows user, prints the
password once, and drops the marker. Basic auth rides the site's existing HTTPS+HSTS,
so credentials are never sent in the clear. Page: `https://gunfight.us/admin/admin.html`.
Revert with `setup_admin_auth.ps1 -Uninstall`.

## Run it

Interactive test (as the server account):
```powershell
powershell -ExecutionPolicy Bypass -File status_service.ps1
```

Auto-run at boot: registered by `tools/vps_services/register_services.ps1`
(as `GF-StatusService`).

## Params

| Param | Default | Meaning |
|---|---|---|
| `-RconHost` / `-RconPort` | `127.0.0.1` / `28960` | loopback server |
| `-IntervalSeconds` | `5` | snapshot cadence |
| `-OutFile` | `C:\inetpub\wwwroot\live\status.json` | public snapshot (no IPs) |
| `-AdminOutFile` | `''` (off) | admin snapshot WITH IPs; written only if set AND `.secured` marker present |
| `-LogDir` | `storage\t5\logs` | source of the connection-log tail shown in the admin view |
| `-AdminLogTail` | `40` | log-tail lines in the admin snapshot |
| `-RconPassword` / `-CfgPath` | (from `dedicated.cfg`) | password source |
| `-RecentMax` | `15` | public recent-activity feed length |

### Manual IIS auth (fallback for `setup_admin_auth.ps1`)

If you'd rather configure it by hand in IIS Manager: select **Default Web Site → admin**,
open **Authentication**, **disable Anonymous** + **enable Basic**; under **Authorization
Rules** remove "All users" and add an Allow rule for your admin account; create that
account in **Computer Management → Local Users**. Then create the marker so the snapshot
starts: `New-Item C:\inetpub\wwwroot\admin\live\.secured -Force`. Basic auth is HTTPS-only
here by design (the site already forces HTTPS + HSTS).
