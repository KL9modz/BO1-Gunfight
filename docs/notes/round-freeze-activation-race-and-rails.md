---
name: round-freeze-activation-race-and-rails
description: "The 24h round-freeze root cause (stranded gf_tryActivateRound) + the fix (gen token + gf_roundWatchdog) + the box-side safety rails (health.json, active watchdog recovery)"
metadata: 
  node_type: memory
  type: project
  originSessionId: e0d54d99-dd02-4469-a292-5445ffafa253
---

**2026-07-10 — the "server stuck, all bots dead, no timer, round never ends" freeze.**

ROOT CAUSE (not the workflow's first guess of "lobby never returns" — the log proved a round WAS
live with kills after the last InitGame): `gf_tryActivateRound` set `level.gf_roundActive = true`
BEFORE its `waittill("prematch_over")`, and carried `level endon("gf_load_gate_reset")`. That notify
fires on every Auto-lobby RE-arm (`gf_armLoadGate`), so in a 0-human Auto-lobby `map_restart(false)`
re-lobby loop it killed a LIVE activator mid-commit → round left `gf_roundActive=true` but grace never
closed + round clock never started. `inGracePeriod` stuck true suppresses stock team-wipe detection →
a wiped team never ends the round → 24h freeze, engine still running. The mod removes EVERY native
round-end backstop (pauseTimer gates timeLimitClock; timeLimitOverride early-returns checkTimeLimit),
so one dropped edge is permanent.

FIX #1 (`_gf_rounds.gsc` gf_tryActivateRound + gf.gsc:396): removed the `gf_load_gate_reset` endon;
commit `gf_roundActive` AFTER the prematch wait; guard with `gf_roundGenChanged(myGen)` where
`level.gf_roundGen = gettime()` is stamped every onStartGameType. A stale Pass-1 activator that
survived the lobby `map_restart(false)` now bails on the gen change instead of double-starting.

FIX #2 (`_gf_rounds.gsc` gf_roundWatchdog, threaded per-round at commit): gettime()-anchored net —
force-closes a grace stuck >65s, starts a clock that never started, and force-ends a round whose team
is wiped >3s out of grace. Logs `GF_WATCHDOG:` to games_mp.log (should be rare). Every round-end
routes through gf_endRound→`gf_round_over` which retires it. See [[gf-timer-prematch-and-pause-model]],
[[gf-stuck-after-prematch-two-gates]].

CONFIG SAFETY: `scr_gf_lobby` was overridden to `1` (Auto) at RUNTIME via the RCON panel — the cfg on
disk says `0`. Auto/Manual lobby is the whole fast-restart/stale-activator surface. Keep `scr_gf_lobby 0`
in dedicated.cfg unless actively arranging teams; a runtime override lingers until reset.

BOX SAFETY RAILS (all box-side, deploy via scp + task restart, NOT the mod mirror unless via deploy.ps1 -Mod):
- `status_service.ps1` now writes `health.json` beside admin.json (round/roundStuck/lobbyHold/
  secsSinceRoundChange/gamesLogAgeSecs/serverUptimeMins). roundStuck = online + humans>0 + !lobbyHold +
  round unchanged ≥ RoundStuckSecs(300).
- `watchdog.ps1` (GF-Watchdog, every 3 min) upgraded from ALERT-ONLY to ACTIVE RECOVERY: (a) kills a
  wedged `plutonium.exe -update-only` (no bootstrapper child > 120s) — the confirmed gap that leaves the
  server DOWN with the task still State=Running; (b) kills a hung bootstrapper when admin.json is
  hard-stale >300s (bat loop relaunches); (c) map_rotate via the panel `/api/rcon` when health.roundStuck.
  `-NoRemediate` = old alert-only behavior. New ntfy state keys: updater-wedge, server-hung, match-stuck.
- `admin.html`/`admin.js` gained a "Server Health" card fetching `live/health.json` (LIVE / MATCH STUCK /
  PREGAME LOBBY / OFFLINE pill + stat grid).

WHY NO PLUTONIUM CONSOLE: GF-GameServer runs as SYSTEM + BootTrigger → Session 0 (isolated services
session, no interactive desktop), so the bootstrapper console is on an invisible desktop. This is FINE
for a headless server (robust, survives reboot/logoff); the fix for "can't see it" is observability
(admin.html health + ntfy), not moving it to an interactive session. The 2026-07-04 "went manual with a
Desktop shortcut" note is STALE — the SYSTEM boot task is active again; `gf_launch.bat` still exists as
the manual visible-console fallback.
