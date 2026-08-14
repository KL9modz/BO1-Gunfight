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

## Gameplay stats (kills / deaths / damage / wins)

The mod logPrints one **delta** line per human per round (`GF_STAT;...`) and one
result line per human at match end (`GF_MATCH;...`) into the engine's own
`games_mp.log` - the classic CoD stat-line transport, same stream as stock's `J;`
connect lines. This service tails that file **incrementally** (byte offset +
creation-time identity persisted in `storage\t5\logs\gamestats.local.json`, so a
restart resumes instead of double-counting) and sums every line into per-day
per-GUID buckets: kills, deaths, assists, headshots, damage (= the in-game score),
captures, round wins, match W-L-T, rounds. Because the lines are deltas, the sum
is the truth - no dedup, no per-match reconciliation, and rotation of the live
log (engine restart) recovers the unread tail from the newest archive.

The projection (`admin\live\gamestats.json`) is **GUID-keyed, so it rides the same
`.secured` gate as `admin_history.json`** - it must never land in the open web
root. The admin page joins it to the connection history by GUID and renders the
Combat leaderboard + per-player drill-down. Ingest itself runs even while the gate
is down (the accumulator is box-local); only the projection waits.

**Bots never count.** The GSC enforces it at emission: kills/deaths/assists/
headshots/damage are human-vs-human only, a round win or capture needs a human on
the opposing team that round, and a match result line is only written when both
teams hold a human at match end. The in-game scoreboard still counts bots (it shows
the round actually played); only these persistent stats are bot-blind.

Known, accepted losses: a player who leaves **mid-round** takes that partial
round's numbers with them, and a watchdog `map_rotate` on a stuck match skips the
final round's flush (no endGame = no lines) - both degrade, never corrupt.

### Muting a player from the activity surfaces

`tools/ignore.local.json` (gitignored, box-local — copy `tools/ignore.example.json`; shared
with `GF-JoinNotify`) lists players by GUID. An ignored player is **excluded from activity,
not from presence**:

| surface | ignored player |
|---|---|
| `status.json` → `players` (live list on the site) | **still shown**, still counted in `humans` |
| `status.json` → `recent` ring | withheld |
| `activity.json` (public 7-day feed) | withheld |
| `admin.json` / `admin_history.json` / `players_*.log` | **still fully logged** |
| ntfy push (`GF-JoinNotify`) | no alert; not counted at all (see that README) |

The filter runs at the **projection**, never at the source: `conn_logger` still writes every
connect to the day-files, so the private admin history stays complete and un-muting someone
restores their whole 7 days retroactively. The file is re-read on change (no restart), and a
missing or malformed file means "ignore nobody" rather than taking the service down.
