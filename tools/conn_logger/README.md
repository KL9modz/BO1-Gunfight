# conn_logger - VPS player connection logger

Appends a clean, grep-friendly record of every player **connect / disconnect** -
including their **IP** and **GUID** - to a dated log on the box. The admin page's
searchable **Connection history** (`admin_history.json`) is built from these files.

## Source: status_service's admin.json (changed 2026-07-05)

This logger **no longer polls RCON itself.** It diffs the roster snapshot that
`status_service` already writes every 5s to **admin.json** (the auth-gated admin
page's data file, which carries per-player **IP + GUID**).

**Why:** `status_service` is the single box-side RCON reader. A second poller here
only competed for the server's ~1-reply-per-0.7s rcon limit (and could eat its
replies - see the RCON transport notes in `CLAUDE.md`). Reading its output file
adds **zero rcon load** and inherits its **5s** cadence (was a 15s direct poll), so
short sessions are caught more reliably.

Plutonium T5 **GSC cannot read a player's IP**, and the existing `games_mp.log`
records join/kill/quit but has **no IP** - the RCON `status` reply (which
`status_service` parses) is the only native place the IP/GUID is exposed, so this
still runs **outside the mod** - no GSC change, no `mod.ff` rebuild.

## Dependency

Needs `status_service` running with `-AdminOutFile` set **and** the `.secured`
marker present (that is what makes `admin.json` exist). If `admin.json` is missing,
**stale** (older than `-StaleSeconds`, default 30), or reports the server offline,
this logger simply **skips that tick** - it never misreads "no snapshot" as
"everyone left". `admin.json` is written atomically (temp + `Move`), so reads are
never torn.

## What it writes

`storage\t5\logs\players_YYYY-MM-DD.log` (rotates daily):

```
2026-07-03 14:22:07  ONLINE   ip=76.167.246.191:3074  name="Klaze"  guid=1100001abc  ping=32
2026-07-03 14:31:10  CONNECT  ip=203.0.113.9:28960    name="Guest"  guid=1100001def  ping=61
2026-07-03 14:41:55  LEFT     ip=203.0.113.9:28960    name="Guest"  guid=1100001def  ping=-   session=10m45s
```

- `ONLINE`  = already connected when the logger (cold) started
- `CONNECT` = joined while the logger was running
- `LEFT`    = dropped (with session length)

Bots and loopback are skipped (`status_service` already drops them from the admin
roster). `.connstate.json` in the same folder tracks who is currently on, so a
logger restart doesn't duplicate CONNECTs.

## Security

- No RCON password lives here anymore - the logger reads `status_service`'s
  `admin.json` file, so it never handles a secret. (`status_service` reads the
  password from `dedicated.cfg` at runtime.)
- The log **contains player IPs** - it is private operator data. Keep it on the box;
  do **not** mirror it into the public web root. (The public status page ships a
  redacted, name-only view - see `tools/status_service/`. The admin page's
  `admin_history.json` is built from this log but sits behind IIS Basic auth.)

## Run it

Interactive test (as the server account, e.g. Administrator):
```powershell
powershell -ExecutionPolicy Bypass -File conn_logger.ps1
```

Install as a boot-start service (once, elevated, on the VPS) - registered together
with the notify + status services by the unified installer:
```powershell
# in tools\vps_services\
powershell -ExecutionPolicy Bypass -File register_services.ps1            # install all
powershell -ExecutionPolicy Bypass -File register_services.ps1 -Only GF-ConnLogger
powershell -ExecutionPolicy Bypass -File register_services.ps1 -List      # status
powershell -ExecutionPolicy Bypass -File register_services.ps1 -Uninstall # remove all
```

Runs as SYSTEM, starts at boot, restarts on exit. Paths are resolved relative to
the script location, so it finds `logs\` regardless of account.

## Params (`conn_logger.ps1`)

| Param | Default | Meaning |
|---|---|---|
| `-AdminJson` | `C:\inetpub\wwwroot\admin\live\admin.json` | roster snapshot written by `status_service` (source of truth) |
| `-IntervalSeconds` | `5` | how often to re-read `admin.json` (bounded by its 5s write cadence) |
| `-StaleSeconds` | `30` | ignore an `admin.json` older than this (status_service dead/stuck) |
| `-LogDir` | `storage\t5\logs` | where to write `players_*.log` |
