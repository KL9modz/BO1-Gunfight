---
name: gf-match-start-gates
description: How Gunfight's match-start hold works — ONE pre-prematch gate; scr_gf_lobby (Normal/Auto/Manual, 2026-07-05) fast-restarts via map_restart(false) for a fresh-start presentation; why party_minplayers is irrelevant; stuck-start diagnostics
metadata:
  node_type: memory
  originSessionId: e6d12527-65d6-4b7d-bda8-4c464707307d
---

Gunfight's match START (first round only) is gated by ONE pre-prematch hold: `gf_waitForLoadingClients`
(`_gf_rounds.gsc`), the last statement of `onStartGameType`. The engine threads `startGame()` (→ the
prematch countdown → `prematch_over`) only when that callback returns, so holding there sits IN FRONT of
the countdown. It releases when BOTH: (a) every tracked client is off its loading screen (LOAD condition,
bounded by `scr_gf_load_wait`, default 20s) AND (b) >= `scr_gf_min_players` humans are present (MIN-PLAYERS
condition, bounded by `scr_gf_minplayers_timer`, default 0 = never auto-start; a pure-bot lobby never holds). Then the full intro/countdown plays for
everyone at once. Shows a "Waiting for teams… N/M" readout.

FAST-RESTART LOBBY (added + consolidated 2026-07-05) — the "pregame lobby" T5 lacks natively, folded onto the
same gate as a release-behavior. ONE dvar `scr_gf_lobby`: `0`=Normal (DEFAULT — no lobby; in-place hold, no restart),
`1`=Auto (hold for load+min-players, then FAST-RESTART), `2`=Manual (hold until the admin's **START
MATCH** click → bridge `lobbystart` → `gf_bridgeLobbyStart` sets `level.gf_lobbyStart`, polled every 0.25s →
then fast-restart). Retired the experimental `scr_gf_lobby_hold`/`scr_gf_lobby_restart`/`_restart_full`.
KEY MECHANISM — **`map_restart(FALSE)`** is the fast restart that re-inits the match FRESH so the full start
presentation fires (weapon first-raise/"gun rack", spawn music, welcome splash); **`map_restart(true)`** — the
between-rounds restart — deliberately preserves player state and SUPPRESSES those (that's why they never fire
between rounds). VERIFIED in-game 2026-07-05: false racks the gun + plays music, fast (~1s, NO map reload).
GSC canNOT fire the console `fast_restart` (no `executeCommand` in Plutonium T5 — that's H2M/IW6x/S1x only);
`map_restart(false)` IS the GSC equivalent. The restart branch **blocks `onStartGameType` from returning** so
`startGame()` never threads a stale prematch/gameTimer (they endon "game_ended", NOT fired here, so a sliver
would survive the restart and STACK → double countdown); the `gf_matchArmed` DVAR (NOT game[]: map_restart(false)
WIPES game[]/pers[] — that's how it re-fires the fresh presentation — so a game[] flag would re-lobby forever;
dvars survive) makes the post-restart pass skip the gate → real match threads its clocks once. Auto/Manual paint the desaturated
`mpIntro` lobby vision; START MATCH is an instant override in both; 10-min `GF_LOBBY_MAX_HOLD` backstop; live
state mirrored into the `gf_state` `lobbyHold` field so the panel shows START only while a hold is up. Team
moves apply LIVE during the hold (`inPrematchPeriod` already true, `gf_bridgeTeamSafeNow()` true). CAVEAT
(unverified): map_restart(false)'s fuller reset may WIPE admin-arranged teams in Manual mode — snapshot+reapply
if so. Files: `_gf_rounds.gsc` gate, `_gf_bridge.gsc` command + telemetry, `server.js` parseGfState, panel
`index.html` (Match Start sel + startBtn).

RULED OUT — engine `party_minplayers`: NOT involved. Stock `waitForPlayers()`
(`raw/.../_globallogic.gsc:1519`) is an EMPTY stub, and `party_minplayers` only gates the separate
`_pregame.gsc` lobby gametype (`level.pregame`), never gf. `prematch_over` fires on a pure wall-clock timer.
So the ONLY "min players" knob that affects gf is the mod's own `scr_gf_min_players`.

HISTORY (2026-07-04 consolidation): this replaced TWO separate POST-prematch gates that used to run in
`gf_tryActivateRound` and caused "stuck after prematch, waiting for someone" when bot-testing:
- old **roster gate** `gf_allTeamedPlayersSpawned()` — held the round clock until every teamed player had
  `hasSpawned` (bounded `scr_gf_roster_wait`). RETIRED as redundant: loaded-before-prematch ⇒
  spawned-by-`prematch_over`. Dvar `scr_gf_roster_wait` retired.
- old **min-players gate** `gf_waitForMinPlayers()` — froze everyone + voided all damage
  (`level.gf_waitingForPlayers`) AFTER prematch. Moved in front of prematch, where nobody has spawned yet,
  so the freeze + damage-void are GONE (also removed the `gf_onSpawned` fresh-spawn freeze + the
  `gf_onPlayerDamage` void). The user's driver: "min-players after prematch is too late" — the intro used
  to play, then the match stalled backwards; now the wait precedes the intro.
Deleted helpers: `gf_allTeamedPlayersSpawned`, `gf_waitForMinPlayers`, `gf_humanCount`,
`gf_connectedHumanCount`, `gf_setWaitFreeze`. `gf_armLoadGate` now arms when EITHER load OR min-players is on.

STUCK-START DIAGNOSTIC (post-consolidation): a long "Waiting for teams…" before the countdown = the gate
holding. Causes: (a) a client genuinely still loading (bounded by `scr_gf_load_wait`, then it starts anyway
— a FastDL first-timer past the ceiling is covered by `scr_gf_load_grace` letting it spawn into round 1);
(b) `scr_gf_min_players`≥2 with too few humans (held until `scr_gf_minplayers_timer` — default 0 = never
auto-start, so it holds until enough humans arrive). A pure-bot lobby does
NOT hold. Nothing is permanent anymore — every path is bounded. Bots (`istestclient()`) never count toward
either condition. `GF_LOADGATE:` logs the release to games_mp.log.

Related: [[gf-timer-prematch-and-pause-model]], [[paused-timer-freezes-gettimepassed]],
[[spawn-wrong-facing-usestartspawns-gate]], [[fastdl-first-join-black-screen-rebuild]].
