# conn_logger - VPS player connection logger

Polls the dedicated server's RCON `status` on an interval and appends a clean,
grep-friendly record of every player **connect / disconnect** - including their
**IP** - to a dated log on the box.

## Why RCON (not the mod)

Plutonium T5 **GSC cannot read a player's IP**. The RCON `status` reply is the
only native place the IP is exposed (its `address` column). So this runs
**outside the mod** - no GSC change, no `mod.ff` rebuild, zero gameplay risk.

The existing `games_mp.log` (already enabled via `g_log`) records join/kill/quit
events but has **no IP** - this fills that gap.

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

Bots and loopback are skipped (no IP). `.connstate.json` in the same folder
tracks who is currently on, so a logger restart doesn't duplicate CONNECTs.

## Security

- The RCON password is **read at runtime from the `rcon_password` line in `dedicated.cfg`**,
  never hard-coded and never written to the log. Falls back to `-RconPassword` or
  env `GF_RCON_PW`.
- The log **contains player IPs** - it is private operator data. Keep it on the box;
  do **not** mirror it into the public web root. (The public status page ships a
  redacted, name-only view - see `tools/status_service/`.)

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
the script location, so it finds `dedicated.cfg` / `logs\` regardless of account.

## Params (`conn_logger.ps1`)

| Param | Default | Meaning |
|---|---|---|
| `-RconHost` | `127.0.0.1` | server host (loopback) |
| `-RconPort` | `28960` | server port |
| `-IntervalSeconds` | `15` | poll cadence (a join+leave inside one interval can be missed) |
| `-RconPassword` | (from cfg) | override the cfg-parsed password |
| `-CfgPath` | `storage\t5\dedicated.cfg` | where to parse `rcon_password` |
| `-LogDir` | `storage\t5\logs` | where to write `players_*.log` |
