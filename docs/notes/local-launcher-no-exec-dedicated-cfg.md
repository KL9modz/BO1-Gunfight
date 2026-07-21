# The LAPTOP's dedicated server never execs dedicated.cfg — the file is decoration there

**Date:** 2026-07-20 · **Status:** root-caused live, contained with `seta`

## Symptom
Bot-tuning overrides (`gf_sv_botYawSpeed`/`Ads`) and `bot_difficulty fu` kept reverting to
preset/stock after local server restarts, even AFTER the values were written into
`storage/t5/dedicated.cfg`. Post-restart the mirrors read `Unknown command` (never created).

## Root cause
The local dedicated server is **launcher-started with no cfg exec at all**:

```
plutonium-bootstrapper-win32.exe t5mp "S:\...\Call of Duty Black Ops" -token <...>
```

No `+exec dedicated.cfg`, no `+set` args — so `storage/t5/dedicated.cfg` is **never read on the
laptop**. Everything that looks configured comes from the **archived** (`seta`) dvars in
`players/mods/mp_gunfight/config_mp.cfg` plus the mod's GSC seeds.

**Fingerprint proof** (live rcon vs the cfg file): `sv_timeout` 240 (cfg says 15),
`scr_gf_match_prematch_seconds` 20 (cfg says 15), `sv_hostname` carries `^4` (cfg has `^5`).
Three independent mismatches = the file was not exec'd, ever — this is
[[read-the-server-not-the-file]] with the whole FILE as the lie, not one line.

## Consequences
- ⚠ **The RCON panel's 💾 Save is decoration on the laptop**: `CFG_PATH` writes
  `storage/t5/dedicated.cfg` (correct for the VPS layout, where the start bat DOES
  `+exec dedicated.cfg`), but nothing reads that file locally. Save works as designed **only on
  the VPS panel**.
- This is almost certainly the mechanism behind the old TODO "FF/settings revert on restart" —
  a restart reverts anything that was only ever rcon-`set`, because no cfg re-creates it.
- The VPS is NOT affected: its `start_mp_server.bat` execs the cfg (see
  [[vps-launch-bat-and-maxclients-latch]]).

## Containment (applied) and the real fix
- **Containment:** the local tuning is now written with **`seta`** (`gf_sv_botYawSpeed 12`,
  `gf_sv_botYawSpeedAds 10`, `bot_difficulty fu`) — the engine archives these into the mod's
  `config_mp.cfg` on **clean shutdown**, so they survive launcher restarts. A crash/kill skips
  the archive flush, so this is best-effort, not a guarantee.
- **Real fix (open):** launch the local dedicated via a start bat that passes
  `+exec dedicated.cfg` (mirror the VPS bat) — then the laptop cfg becomes authoritative and the
  panel's 💾 Save means what it says locally.

## Related
[[read-the-server-not-the-file]] · [[vps-launch-bat-and-maxclients-latch]] ·
[[rcon-dedicated-dvar-push-limits]]
