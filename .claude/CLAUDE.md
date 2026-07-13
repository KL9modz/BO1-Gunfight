# mp_gunfight — Black Ops Gunfight for Plutonium T5 (Black Ops 1 MP)

A standalone **Gunfight** gametype (`gf`) for Call of Duty: Black Ops 1 on Plutonium T5. Two teams,
a **shared loadout that rotates every other round**, one life per round, no killstreaks/regen/drops.
Time expires → most-remaining-health wins the round (or capture the overtime flag). First to **6 round
wins** takes the match.

> This file is the agent operating manual: goal, current architecture, the load-bearing engine
> knowledge, and an organized TODO. It intentionally **summarizes and points** rather than duplicates —
> exhaustive per-function / per-dvar detail lives in `docs/`, and hard-won single-incident findings
> live in `memory/` (the `MEMORY.md` index is auto-loaded each session, so a `[[slug]]` reference is
> enough — open the file for depth). Keep this file present-tense: update behavior in place; do not
> append dated "FIXED …" changelog notes (that history is in `git log` and `memory/`).

---

## TODO

### Open bugs
- **Which client orphans `.killcam` in the round-end deadlock is still unproven.** The deadlock itself is
  now broken by `gf_postRoundWatchdog` (the infinite round can't recur), but the *leaker* was never pinned:
  `finalKillcam`'s only live endon is `self endon("disconnect")`, and a disconnected player leaves
  `level.players` — yet the observed hang persisted after the disconnector left again, so the leaker was a
  client that STAYED. Prime suspect is a fill bot added into the killcam window (`gf_boundaryListener` adds
  at `gf_round_over` +0.5s, and `startLastKillcam` snapshots `level.players` *after* `play_final_killcam`).
  **Next occurrence: read the `GF_ENDWATCH:` log line — it names the client and the flag.**
  ([[infinite-round-orphaned-killcam-flag]])
- **Pregame lobby can end on its own** (should end only via the load/min gate or an admin START) — only
  reachable when `scr_gf_lobby` is Auto/Manual (default Normal has no hold, so masked by default).
- **Prematch/intro countdown runs in slow-motion** — NOT transient and NOT a rendering artifact.
  `GF_HITCH` measures **game-time dilation** (`wait` counts game time, `gettime()` counts real time), so
  `750ms vs 500ms` means the whole simulation ran at ~65% speed for that window. The countdown is simply
  the last clock still driven by a game-time `wait(1.0)`; the mod's own clocks are gettime-anchored and
  immune. **Measured on the VPS (10 days, 2,803 hitches):** 99.3% land in `phase=prematch` — roughly one
  per round, ~700-750ms, and **flat across bot count** (694ms at 0 bots vs 746ms at 6), so it is the
  engine's `map_restart` itself, *not* our bots / HUD pushes / loadout giving. It is not ours to delete →
  **the fix is to make the countdown immune** (gettime-own it; see Ideas). Separately, 226 hitches exceed
  **2s** (map load + the `MatchRecord` stat flush), and **15 landed mid-gameplay** at ~2.8s — those are the
  ones that actually hurt, and the two suspects now have panel toggles: **`demo_enabled`** (match
  recording / the `democlient`; the killcam does **not** depend on it) and **`scr_allowbattlechatter`**
  (whose `CheckDistanceToEvent` the GSC VM has killed 3× with "potential infinite loop", each landing on a
  2.4-2.5s frame hitch). Ceiling: the box is 4 **shared** Contabo vCPUs — steal time produces multi-second
  stalls no config fixes. Instrumented via `gf_hitchMonitor` (`gf_hitch_pct`/`gf_hitch_debug`)
  ([[vps-prematch-slowmo-framehitch]]).
- **Mod may still change some client settings** — the r_* vis-tweak force-push was removed; confirm
  nothing else writes a saved client dvar.
- **Democlient round-cam lag.**
- **Start music is killed by the ambient map music.**
- **Minimap compass doesn't show wager (zoomed) size on some DLC maps** — inherent to the resident-art
  whitelist excluding First Strike/Escalation maps.
- **Berlin Wall:** OT flag / spawn area sits too close to the building.
- **SECURITY:** rotate the leaked RCON password (VPS `dedicated.cfg`) + the exposed Plutonium server key.
- **Prevent a duplicate launcher from squatting port 28960 after a reboot** (root cause of the reported
  "FF/settings revert on restart").

> Known design caveat, not a bug: **large/small spawn mode takes effect one round after the HUD readout**
> (next-round snapshot vs live count — see *Team-size mode*).

### Ideas & future
- **Own the prematch/intro countdown with `gettime()`** so a hitch degrades to a 1-frame stutter (the
  planned fully-custom-timers branch). **This is the real fix for the slow-mo countdown** — see the
  frame-hitch bug above: the hitch itself is the engine's `map_restart` and is not ours to delete, but the
  countdown is the last clock still driven by game-time `wait(1.0)`, so owning it makes the symptom vanish.
  ⚠ Do **not** pair this with the once-floated **sv_fps 30** experiment: `GF_HITCH` is *game-time dilation*
  (wall time to advance 0.5s of game time), and the stall is a fixed lump of wall-clock work — more frames
  per second on a CPU-starved box buys more overhead and *more* dilation, not less. VPS runs 20; leave it.
- **Hybrid custom round-timer HUD:** keep the native engine-driven `MM:SS` for the normal phase, own only
  the final ≤10s (orange `S.T` tenths) via the menu layer, route OT through the same element.
- **Mid-round late spawn / bot backfill** (designed ~25 lines, not built): let a client added mid-round
  spawn into a live round when its team still has ≥1 alive (double-blocked in OT).
- RCON: gas/stun/flash intensity sliders; mantle/climb speed control.
- Lobby ready-up / team-picking UI; lobby fly-cam controls.
- Min-players option that also counts bots (`scr_gf_min_players` counts humans only today).
- Spawn/flag pass: widen spawns; adjust flags generally; Hockey mode on Arena (map-specific).
- Ship custom weapon files for ADS-FOV / move-speed tuning; tuning pass (shorter round, capture 3.5s,
  Hardened on sniper classes).
- Persistent "gunfight.us" HUD text; general HUD/visual polish; rename the "democlient" bot label; rename
  the gametype display "GF" → "Gunfight".
- Site/branding: design pass; server ads; credit Plutonium/bots; show per-map feature support; on-brand
  Discord live-count card ([[discord-widget-csp-frame-src]]). Setup guide: recommend `cg_fov 65`,
  `cg_fovScale 1.4`. BO1 server "role" tied to Discord activity.
  - Map/mode vote
  - Perks per class

---

## Goal & design philosophy

**Bring an authentic Gunfight experience to T5 using as much native/core-engine and existing-library
functionality as possible.** The bar for writing custom code is: *does a stock system already express
this?* If yes, use it. We own only the few systems the engine genuinely cannot express, and we own
them for a specific, documented reason.

Principles, in priority order:
1. **Native-first.** Round cycling, scoring, intermission, killcam, prematch, `_gameobjects`, spawn
   selection, friendly-fire, and flinch are all stock. We hook them via `level.on*` callbacks, we do
   not reimplement them.
2. **Own only what stock can't do**, and say why in a comment: the retunable **round clock** (stock
   time-out thresholds are hardcoded absolute seconds, unusable on a 45s round), the **overtime clock**
   (needs pause/resume on a *gameplay condition* + hide-on-capture), and the **HUD** (the per-client
   render cap forces the menu layer).
3. **Strictly avoid poor-performance patterns.** No per-frame busy loops, no redundant polling, no
   piling `setClientDvar` bursts on one frame, no per-client HUD-render-cap abuse. Polling loops are
   bounded (`endon` a lifecycle notify), event-driven where possible, and coalesced.
4. **Lean on `game[]`/`self.pers[]` for anything that must survive `map_restart`** (see the map_restart
   rule below); re-derive everything else each round in `onStartGameType`.

We do **not** reference other community Gunfight mods — they are not a design source here. The only
external references we use are the official engine sources (see **Resources**).

---

## Working in this repo

**The repo IS the mod folder.** A clone of `main` drops into the Plutonium T5 storage tree at
`%localappdata%\Plutonium\storage\t5\mods\mp_gunfight\`, so testing is just `loadMod mp_gunfight` +
`map_restart` in the Plutonium console (`connect 127.0.0.1:28960` for a local dedicated server).

- **GSC is loaded as loose rawfiles** — edit a `.gsc` and `map_restart`; **no rebuild**. Only compiled
  assets need `mod.ff` (see *Building mod.ff*).
- **Local-test cfg quirks:** `party_minplayers 1` for solo testing (`2` for public); `set scr_xpscale`
  is read-only on a dedicated server (harmless error). If ADS feels wrong locally, `exec autoexec`.
- **Test panel/bridge/telemetry changes against a DEDICATED server, not a listen host** — a listen
  server masks RCON queue saturation and the "Unknown cmd" dvar-probe spam that only bite on the VPS.

### Companion docs (NOT auto-loaded — open them for depth)
| Doc | Owns |
|---|---|
| `docs/REFERENCE.md` | Authoritative present-tense per-system prose, the full gameplay dvar/var tables, and a per-function reference for the gameplay files. |
| `docs/DEV.md` | Repo layout, GSC include graph, `build_ff.ps1`, branch/release model + strip markers, deploy pipeline, dev tooling (RCON/bots/debug). |
| `docs/VPS_DEPLOY.md` | 11-phase VPS provisioning + deploy runbook (FastDL, git-pull deploy). |
| `docs/VPS_HARDENING.md` | Security runbook (RDP/WinRM/TLS/IIS `web.config`/DNS) with as-applied status. |
| `docs/GETTING_STARTED.md` | Player-facing install / settings / ADS-fix / join guide. |

`memory/` holds ~50 single-incident deep-dives; the `MEMORY.md` index is in context every session, so
this file links them as `[[slug]]`.

### Project map
```
mp_gunfight/  (GitHub: KL9modz/BO1-Gunfight)
  .claude/CLAUDE.md                  <- this file
  mod.csv                            <- build manifest the linker reads
  mp/gametypesTable.csv              <- registers the 'gf' (+ wager gun/oic/hlnd/shrp) UI rows
  localizedstrings/gf.str            <- localized UI strings (assets are named GF_<REFERENCE>)
  localizedstrings/cgame.str         <- OVERRIDES of stock engine strings (see below)
  ui_mp/
    hud_gf.txt                       <- menufile loader (loadMenu hud_team + hud_gf_health)
    hud_gf_health.menu               <- ALL mod HUD (health panel, loadout overview, self bar, lobby)
    mod.txt / mod_ingame.txt         <- empty {} stubs (kill a ~4.6s missing-asset stall on mod load)
  maps/mp/gametypes/
    gf.gsc                           <- ENTRY POINT: main(), callbacks, precache, spawn pipeline
    _gf_rounds.gsc                   <- round lifecycle, clocks, overtime, match-start/lobby, team-size, damage/score
    _gf_loadouts.gsc                 <- shared loadout pool, shuffle, give, camo
    _gf_hud.gsc                      <- menu-driven HUD (health panel, loadout overview, score popup)
    _gf_locations.gsc                <- per-map curated spawns + overtime flag points
    _gf_wager_zones.gsc              <- wager compass material + map-specific zone helpers
    _gf_debug.gsc        (dev only)  <- spawn recorder, HUD-pool probe, frame-hitch monitor
    _gf_bridge.gsc       (dev only)  <- RCON -> GSC command bridge
    _bot.gsc             (dev only)  <- bot integration + dynamic-fill reconciler
  maps/mp/bots/          (dev only)  <- vendored BotWarfare framework (_bot_loadout/_bot_script/_bot_utility)
  raw/fx/misc/*.efx                  <- custom overtime apron FX (white ring; gold/red use stock FX)
  site/wwwroot/                      <- PUBLIC static website (gunfight.us). NOT the RCON panel.
  tools/                 (dev only)  <- build_ff, packagers, deploy, RCON panel, box services, loadout editor
```
> Entry point is `gf.gsc::main()`. `(dev only)` files are excluded from public release outputs by
> `package_release.ps1`. There is no `mp_gunfight.gsc`.

**Cross-file `#include` rule (T5 has no transitive includes):** each file must `#include` every other
file whose functions it calls *directly*; a missing include is an `unknown function` compile error on
the calling function. Current graph: `gf.gsc` → `_gf_locations`/`_gf_rounds`/`_gf_loadouts`/
`_gf_wager_zones` (+ dev `_gf_bridge`/`_gf_debug`) + stock `_utility`/`_hud_util`; `_gf_rounds` →
`_gf_hud` (+ dev `_gf_debug`) + `_hud_util`; `_gf_loadouts` → `_gf_hud`; `_gf_hud` → `_hud_util`.

---

## Core gameplay spec

- **Round-based, one life** — last team standing ends the round; then killcam. `scr_gf_numlives 1`.
- **Match = 6 round wins.** The real threshold is `scr_gf_scorelimit` (6), enforced by stock
  `hitScoreLimit()` on `game["teamScores"]` — each round win adds **1** to the winner's team score in
  `gf_endRound`. (`level.roundWinLimit`/`hitRoundWinLimit` are **inert** here — `RoundWinLimit` is
  registered at 0. To change match length, change `scr_gf_scorelimit`.)
- **Shared random loadout** — every player gets the same primary/secondary/lethal/tactical/equipment
  each round; the pool rotates every `scr_gf_roundsperloadout` (2) rounds.
- **No killstreaks, no health regen, no weapon drops, no class-select** — `level.killstreaksenabled=0`,
  `level.healthRegenDisabled=true`, `scr_disable_weapondrop 1`, `scr_disable_cac 1` (all re-forced each
  round in `onStartGameType`).
- **Round decided by time** → most total remaining HP wins; equal HP is a **draw** (draws add no score).
  If both teams are still alive at expiry, **overtime**: capture the overtime flag, else HP decides.
- **Damage-based scoring** — a player's score is the running total of damage they've dealt.
- **Loadout HUD** — on spawn, a create-a-class-style overview of the round's weapons + perks.

---

## How each system works today

*(Present-tense architecture. File refs are `_gf_rounds.gsc` unless noted. Deep detail →
`docs/REFERENCE.md`; incident depth → `[[memory]]`.)*

### The `map_restart` rule (read first)
SD round cycling calls `_globallogic::endGame` → **`map_restart(true)` between rounds**, which wipes
**all `level.*`** (and entities) but keeps `game[]` and `self.pers[]`. The pregame lobby uses
**`map_restart(false)`**, which wipes `game[]`/`pers[]`/`level[]` too. Consequences that shape the whole
codebase: `onStartGameType` re-runs every round and must re-establish every `level.*` value; anything
that must survive a restart lives in `game[]`, `pers[]`, or a **dvar** (dvars are the *only* thing
surviving `map_restart(false)`); and **threads survive both restarts** (only `game_ended` tears them
down), so persistent loops are collapsed to one copy via a re-init notify (`bot_reinit`,
`gf_bridge_reinit`) rather than a `game[]` once-guard.

### Round lifecycle & activation
`onStartGameType` stamps `level.gf_roundGen = gettime()` (monotonic across restarts) and resets round
flags. The round runs on the **engine's native prematch** (`level.prematchPeriod`): countdown, freeze,
intro VO, hint, timer-hide are all stock; the only addition is `gf_nativePrematchTicker()` (a 1 Hz beep
the silent stock countdown lacks). Activation is spawn-driven: `gf_onSpawned` threads
`gf_tryActivateRound`, which dedups (0.2s), `waittill("prematch_over")`, then in one **yield-free**
block sets `gf_roundActive`, threads `gf_roundWatchdog(myGen)`, closes grace early
(`gf_closeGraceEarly`, prematch_over+3s floor), captures the team-mode snapshot, and starts the round
clock. Staleness is handled by **capturing `myGen` and bailing if `gf_roundGen` moved** — never by an
`endon` on a lobby-reset notify (that once killed a committing activator and stranded the round;
[[round-freeze-activation-race-and-rails]]).

The round ends by three paths, all → `gf_endRound(winner)` → `_globallogic::endGame`:
elimination (`gf_onDeadEvent`), clock expiry (`gf_onTimeLimit` → HP decision or overtime), or OT
capture. `gf_endRound` adds 1 to the winner's team score (not for "tie"), sets the WIN/LOSS banner
subtitle (`gf_reasonText`), and starts the last killcam. `gf_roundWatchdog` is the only **in-round**
backstop (the mod suppresses every native fallback), gettime()-anchored, 1 Hz: it force-closes a stuck
grace after >65s and force-ends a round when a team has 0 alive out of grace for >3s.

**`gf_postRoundWatchdog` is the round-END half**, threaded from `gf_endRound` *before* `endGame`, because
`gf_roundWatchdog` carries `endon("gf_round_over")` and so retires exactly when the round-end hazard
opens. Stock's end sequence is **synchronous** (`endGame` → `startNextRound` → `displayRoundEnd` →
`executePostRoundEvents` → `map_restart(true)`) and two of its gates are unbounded: `finalKillcamWaiter()`
spins while **any** player merely has `.killcam` *defined*, and `roundEndWait()` spins while any player has
`.doingNotify` true. An orphaned flag on one client therefore blocks `map_restart` **forever** — and the
engine's own force-clear (`endedFinalKillcamCleanup`) waits on `game_ended`, which `endGame` already fired
*before* the final killcam starts, so it is **dead code on this path**. The watchdog is gen-token retired,
clears both flags after 20s, and logs which client/flag leaked (`GF_ENDWATCH:`)
([[infinite-round-orphaned-killcam-flag]]).

⚠ Never re-add an `endon` to the committing activator. ⚠ `gf_roundWatchdog` must stay.
⚠ `gf_postRoundWatchdog` must **not** carry `endon("game_ended")` (endGame fires it within a frame of the
thread starting) and must stay armed on the last round (the same waiter gates the match-end podium).

### Custom round clock & warnings
The live round timer is mod-owned because stock `timeLimitClock` fires its time-out sequence (announcer
VO, `TIME_OUT` music, beeps) at hardcoded absolute seconds — on a 45s round that fires almost
immediately and no dvar retunes it. `gf_startRoundClock` derives length from `level.timeLimit`
(per-mode), sets `level.timeLimitOverride=true` (own expiry), calls `pauseTimer()` (which sets
`level.timerStopped` and gates off the *entire* native warning loop), and drives the HUD via
`setGameEndTime`. `gf_roundClock` ticks 10 Hz off `gettime()` deltas (wall-clock, so sv_fps-immune).
Warning: one `leaderDialog("timesup")` at 15s + a beep each second in the final 10s. Starting the clock
before `prematch_over` would draw over the native countdown — so activation parks on `prematch_over`.
⚠ `pauseTimer()` freezes `getTimePassed()`, which breaks any stock system keyed off it — the grenade-dud
window is disabled (`grenadeLauncherDudTime`/`thrownGrenadeDudTime = -1`) for exactly this reason
([[paused-timer-freezes-gettimepassed]], [[gf-timer-prematch-and-pause-model]]).

### Overtime & the two-layer zone color system
`gf_onTimeLimit`: if both teams are alive at expiry → overtime (unless `scr_gf_overtimelimit <= 0`, then
HP decides immediately); else HP decides. Overtime is a custom ms-decrement clock (`gf_beginOvertime`/
`gf_overtimeClock`, gettime()-anchored) because the native timer cannot **pause/resume on a gameplay
condition** (freeze while the zone is being captured, resume if the capture breaks — via a pause-depth
counter), **hide during that pause** (`setGameEndTime(0)`), or tick per-second. The capture zone is
native `_gameobjects::createUseObject` on a **`trigger_radius`**, so standing in it accrues capture (no
button — which is also how bots win OT). A capture wins the round outright.

The color system is two layers with different meaning, dictated by an **engine constraint**:
- **Icons — team-relative** (2D minimap + 3D world), driven from the same native `_gameobjects` path
  (`set2DIcon`/`set3DIcon` + `setOwnerTeam`): **friendly → `defend` (green), enemy → `capture` (red)**,
  neutral/contested → white. (Reversing friendly→capture is the known "my team shows red" bug —
  [[overtime-icon-2d-3d-coincidence]].)
- **Apron ring FX — absolute** (white idle / gold capturing / red contested), the same for everyone,
  because a `spawnFx` entity renders in world space with **no per-team visibility** in T5. The apron
  physically *cannot* encode friendly/enemy — that's why the green/red lives only on the routed icons.

⚠ `loadfx` handles are `level.*`, wiped by `map_restart(true)` — so `gf_loadOvertimeApronFx()` re-loads
them **every OT entry**, not just at precache ([[onprecache-once-per-match-loadfx-wiped]]). ⚠ Native
objective IDs / objpoints accumulate across restarts, so per-round `gf_cleanupOvertimeZone` is mandatory
or the HUD pool exhausts. Deep detail → `docs/REFERENCE.md` "Overtime & capture zone".

### Match-start gate & pregame lobby
**One pre-prematch hold** (`gf_waitForLoadingClients`, called as the LAST statement of
`onStartGameType` — the engine threads the prematch only once that callback returns, so blocking there
= "prematch hasn't started"). It replaced two retired post-prematch gates. Loading clients connect while
still on the loading screen and aren't in `level.players` yet, so `gf_armLoadGate` collects them off the
level `"connecting"` notify (armed early, before the first yield); "loading" is read from `statusicon`.
Bots (`istestclient()`) and demo clients (`isdemoclient()`) are excluded. Three release conditions on
the one hold: **LOAD** (everyone off the loading screen, ceiling `scr_gf_load_wait`, 3s floor),
**MIN-PLAYERS** (`scr_gf_min_players` humans present; ceiling `scr_gf_minplayers_timer`, default 0 =
never auto-start; a 0-human lobby always releases), and **LOBBY MODE**.

`scr_gf_lobby`: **0 = Normal** (in-place hold, no restart), **1 = Auto** (release on load+min, then
fast-restart), **2 = Manual** (hold until an admin's START click, then fast-restart;
`scr_gf_lobby_timer` auto-start backstop, default 600s). The fast-restart is **`map_restart(false)`** —
the fresh reset that re-fires full match-start presentation (gun-rack, spawn music, welcome splash);
`map_restart(true)` deliberately suppresses that. The lobby branch **never returns** (`for(;;) wait 1;`
after the restart) so `startGame()` never threads a stale prematch that would survive and stack a double
countdown. The loop-break flag is the **`gf_matchArmed` dvar** (not `game[]`, which `false` wipes): set
before the restart, consumed after so the real match threads its clocks once. Lobby presentation:
desaturated `mpIntro` vision, bodyless overview cam, a custom `gf_lobby_hud` menuDef ("Waiting for
teams N/M"), forced autoassign. ([[gf-stuck-after-prematch-two-gates]])

**Lobby → match team transfer** survives the `false`-restart via dvars: `gf_writeTeamPlan`/
`gf_applyTeamPlan` carry humans by GUID (`gf_teamplan`); `gf_writeBotPlan`/`gf_applyBotPlan` carry bot
**counts** (`gf_botplan`, inert when `gf_fill_n > 0` — the reconciler owns bots then). `gf_applyTeamPlan`
must **yield before its first roster read** (it runs from the tail of `onStartGameType` where
`level.players` is empty). ⚠ A prematch team switch suicides an alive frozen player without restoring
`pers["lives"]`, so `maySpawn` then denies the respawn → "starts round 1 dead"; `gf_reseatRespawn`
restores the life and re-drives `spawnClient` ([[stock-teamswitch-suicide-no-life-restore]]).
`scr_gf_load_grace` (non-restart path) keeps round-1 grace open for a still-loading straggler.

### Pre-match warmup — `g_pregame_enabled` (100% stock, zero mod GSC)
BO1 ships a **pre-match lobby gametype**: a playable no-XP free-for-all on the map while the server
waits for players, which then hands itself off into the real match. It is fully native and we own
**none** of it — we only expose the switch in the RCON panel.

- **How the engine does it:** `BlackOpsMP.exe` carries the dvar **`g_pregame_enabled`** and the
  hardcoded script path `maps/mp/gametypes/_pregame`. When the dvar is set, the engine loads **that
  stock script instead of `<g_gametype>.gsc`** at level load. `g_gametype` still reads `gf` throughout,
  so `level.gameType`, the server browser and the panel all still say "gf". `_pregame::main()` sets
  `level.pregame = true` → `isPregame()` → stock `_globallogic` turns off XP/rank/AAR/leader-dialog and
  skips the prematch countdown. On release it calls the engine builtin **`pregamestartgame()`** (which
  latches `isPregameGameStarted()`, so a between-round `map_restart` does **not** re-enter the warmup)
  + `SetPreGameTeam`/`SetPregameClass` to carry players, then `map_restart(false)` into `gf`.
  ✅ Verified working on the Plutonium dedicated VPS — `set g_pregame_enabled 1` + `map_restart`.
- ⚠ **Read at LEVEL LOAD** → only ever affects the **next** map (same constraint as `xblive_wagermatch`).
  A `map_restart` is enough to trigger it. The panel badges it `NEXT MAP`. Seeded if-empty in
  `gf.gsc onStartGameType` purely so the panel's connect-sweep doesn't get "Unknown cmd".
- **Gate = `party_minplayers`** (NOT `scr_gf_min_players`). Snapshotted at level load, and it counts any
  non-spectator, so **bots count toward it**.
- ⚠ **`scr_pregame_timelimit` must be 0 — and the mod is what makes it so.** Stock `_pregame::main()`
  registers it via `registerTimeLimitDvar("pregame", 5, …)`, which is **seed-if-empty**, so an
  unregistered dvar lands on **5 minutes**; the warmup's `onTimeLimit` then calls
  `_globallogic::endGame`, and on *that* path it never reaches `pregamestartgame()` — the map
  **rotates** instead of starting the match, so an under-populated server just cycles maps every 5 min.
  `gf.gsc onStartGameType` therefore seeds it to `0` (strip-marked, next to the `g_pregame_enabled`
  seed): dvars outlive a map change, so our 0 is already in the table when the warmup loads and its
  seed-if-empty leaves it alone. `dedicated.cfg.example` sets it too, for the boot-straight-into-a-
  warmup case where that callback has never run.
- Known costs of staying stock (accept, or own with a documented reason): the warmup gives **stock
  classes**, not the Gunfight shared loadout; **no mod GSC runs during it**, so the RCON bridge is dead
  and `gf_state` goes stale (watch for `GF-Watchdog`'s `roundStuck` → `map_rotate` if a warmup with
  humans on it outlives `RoundStuckSecs` = 300s); and the `ui_gf_*` **client** dvars survive the map
  load, so a client that was last in a gf lobby renders the `gf_lobby_hud` menuDef *over* the warmup
  (stale "auto-starts in M:SS" and all). That overlay is an accident, not a feature — it only appears
  for clients that saw a lobby earlier.

⚠ **Do NOT ship a mod `maps/mp/gametypes/_pregame.gsc`.** One was written and reverted (2026-07-12): the
native path already does the job, and overriding the stock script also means keeping its whole public
surface or the server won't compile — see the `unknown function` rule in the T5 cheatsheet below.

### Team-size mode (large vs small)
`level.gf_largeMode` (re-derived each round by `gf_resolveTeamMode`) is the single flag driving spawns,
the wager-blocker allow-list, the OT flag choice, and which `_large` dvar variant is read.
`scr_gf_teamspawnmode` = `auto` | `large` | `small`. **auto** is hard-wired to the health-panel skull cap
(`gf_hudSkullCap()`=4, mirroring the menu's `cnt > 4` gate): **≤4 per team → small** (curated clustered
wager-style spawns + skulls), **any team of 5+ → large** (full-map `mp_tdm_spawn` + `alive/total`
readout). It keys off the **larger** team (2v6 → large). Each mode reads its own dvar copy
(`_timelimit`/`_overtimelimit`/`gf_capture_time` + `_large`) so flipping never clobbers the other.

⚠ **Inherent one-round lag:** the spawn mode is a snapshot (`game["gf_autoLargeMode"]`, captured
post-prematch by `gf_updateAutoTeamMode`, applied *next* round) while the HUD readout is live — so a
roster crossing 4↔5 shows the readout one round before the spawns switch. By design (a live count inside
`onStartGameType` is unreliable — bots/late joiners connect after it), not a bug. ⚠ `gf_hudSkullCap()`
must stay in lockstep with the menu skull gate (rebuild-gated). Full detail → `docs/REFERENCE.md`.

### Loadout system
Shared random, **deterministic by round index** — every client reads the same
`int(game["roundsplayed"] / roundsPerLoadout) % poolSize`, so sync is by construction (no per-player
roll at give time). `gf_initLoadouts` builds a **53-entry** hand-authored pool once per match
(`game["gf_init"]` gate), Fisher-Yates shuffles it, stores it in `game["gf_pool"]`. Delivery is the
**`level.giveCustomLoadout = ::gf_giveCustomLoadout` hook** — stock `_class::giveLoadout` calls it during
the spawn's loadout build, so there's no `takeAllWeapons` overwrite race (`level.onGiveLoadout` does not
exist in T5). Base perks: Lightweight (+no-fall-damage), Marathon, Flak Jacket, flash/stun resist. Fast
weapon switch is **not** in the base set (admins add it via `gf_perk_on`).

Per-slot camo via `CalcWeaponOptions` (primary + independent secondary); rolled once at pool build.
Camo only renders on real-base weapons (the crossbow is the one pool secondary that shows it); pistols/
launchers are neutral-base no-ops. Special weapons need `PrecacheItem` in `onPrecacheGameType` or
`GiveWeapon` silently no-ops: `minigun_wager_mp`/`m202_flash_wager_mp` (the `_wager` builds, NOT the
killstreak names — those fire the "called-in" announcer + holster-lock), the `tabun_gas_mp`/
`nightingale_mp` tacticals, and `defaultweapon` (the Finger-Gun easter-egg, a real SP weapon def; icon =
`hud_death_suicide`). See [[special-weapons-precacheitem-and-camo]], [[invalid-weapon-finger-gun-fallback]],
[[reference_t5_mp_weapons]]. Dev aids: `gf_force_loadout`, `gf_force_camo`.

### Dynamic bot fill + team management
**One round-boundary reconciler** (`gf_reconcilerInit` in `_bot.gsc`, dev-only) is the single authority
over bot counts and placement; BotWarfare's own managers (`addBots`/`teamBots`/`doNonDediBots`) are
**deleted**. `gf_fill_n` = **per-team target N** (`3` → 3v3): each side is padded to exactly N *playing*
clients (humans+bots) at **each round start**, and **bots absorb all variance**. **Humans are never
auto-moved** (if humans on a side exceed N, that side's bots go to 0 and it stays big while the other
side still fills). Mid-round roster changes (and fill-N changes) are deliberately ignored until the next
boundary — worst case one ~45s round. `gf_fill_n 0` = reconciler inert — the mode in which manual
per-team bot add/kick/move sticks (with fill on, a manual move lasts at most until the round ends).

**Boundary-only = suicide-free + overshoot-free by construction.** ONE yield-free `gf_boundaryPass` per
round, triggered by: `gf_round_over` +0.5s (inside the killcam, where every eliminated bot is already
un-"playing"), the match-start gate release (`gf_load_gate_reset` with players present — pre-spawn, so
the round-1 wave reads the finished plan; the Auto/Manual lobby-release fire instead **kicks all bots**
pre-restart and the post-restart pass rebuilds the fill clean), and one roster-settle pass after init.
Placement is a **quiet pers reassign** (`gf_botQuietSetTeam`, mirror of the bridge's `gf_forceTeamQuiet`
— no suicide path exists); an **alive ("playing", incl. prematch-frozen) bot is never touched**: a
surplus one gets `pers["gf_parkPending"]` and `gf_lobbyMaySpawn` (gf.gsc) routes it to a clean spectator
in its next pre-spawn window. Adds are staggered (0.5s) and **generation-stamped** (`level.gf_fillGen` —
a newer pass cancels an older pass's add loop) with steer marks (`.gf_fillPending = team`, counted
toward the target team while mid-connect) — the old model's racing passes + wrong-team autoassign
landings were the "bots exceed the target" bug, and its mid-prematch stock switches racing the async
spawn commit were the "bots suicide during the countdown" bug. Displaced bots **park in spectator** for
reuse; the parked reserve is capped at the live human count (so *reducing* N kicks freed bots) and
`gf_fill_kick_floor` kicks parked bots before they breach `sv_maxclients`. Counts key off
`level.players` + `istestclient()`, never `level.bots` (which a restart desyncs). Every persistent bot
loop carries `endon("bot_reinit")`; `init()` fires `bot_reinit` before re-threading so a
restart-surviving manager set collapses to one. Full detail →
[[gf-fill-reconciler-and-team-transfer]], `docs/DEV.md`.

### HUD (menu-layer)
All mod HUD is rendered in the **menu layer** (`ui_mp/hud_gf_health.menu`, in `mod.ff`), NOT client
hudelems, because T5 has an invisible per-client **DRAWN render cap (~17-20 elements)** shared across
*all* hudelem types; the old client-side panel blew past it and silently starved the score popup and OT
flag ([[settext-configstring-exhaustion]]). The server pushes `ui_gf_*` client dvars on-change; menu
itemDefs read them via `exp material(dvarString())`, `exp rect`, `exp forecolor A`, `visible when(...)`.
Materials **must** be dynamic `material(dvarString())` — a static `background "hud_..."` makes the linker
try to bundle the `.iwi` → build error.

- **Health panel:** two rows (row 0 = friendly green, row 1 = enemy red), each an HP number + bar +
  EITHER up to 4 skulls (both teams ≤4) OR an `Alive: N` readout (either team >4). The skull/readout
  mode (`ui_gf_hp_mode`) is shared so both rows switch together — this **is** the small/large coupling
  threshold. Each skull slot is two itemDefs (alive team-colour + dead white) because forecolor RGB
  isn't exp-drivable, only alpha.
- **Self health bar**, **loadout overview** (icons via `ui_gf_lo_*`; 3 hardcoded perk icons), and two
  separate menuDefs — **pregame lobby** (`gf_lobby_hud`) and the admin **pause banner** (`gf_pause_hud`,
  "MATCH PAUSED", gated on `ui_gf_paused`) — both gated `!BIT_IN_KILLCAM` not `BIT_HUD_VISIBLE`
  (the lobby cam clears hud_visible, and a pause can land in a state that has too).
- **Kill/score popup:** renders "Elimination"/"Assist" on its own `NewScoreHudElem` (`self.gf_popupElem`,
  a separate pool from the ~17 cap), styled to match the stock yellow popup; the engine's own
  `hud_rankscroreupdate` is parked offscreen each spawn so stock "+N" XP pushes can't race ours.

⚠ Round-start respawn bursts stagger their `setClientDvar` pushes (`gf_hudRevealStagger`) so ~40
pushes/human don't pile on one 20 Hz frame and widen the between-rounds snapshot gap (the "Connection
Interrupted" flash — [[connection-interrupted-mitigations]]). Menu **structure** changes need a `mod.ff`
rebuild; dvar values/positions are GSC-tunable. Intro slide/fade animations are currently disabled
(snap-in); only the loadout outro animates. Related: [[menu-rendered-loadout-overview]],
[[script-hudelem-number-oversized]]. Full ui_gf_* map → `docs/REFERENCE.md`.

### Damage scoring, friendly fire, flinch, vision
- **Score = total damage dealt** (`gf_onPlayerDamage`), capped per hit at the victim's current HP (no
  overkill inflation), pushed silently (bypasses the stock rank-popup so score doesn't flash each hit).
- **Friendly fire is 100% stock** — the mod GSC sets no FF dvar. It's owned by the RCON panel writing the
  stock tweakables `scr_team_fftype` (base) + `scr_gf_team_fftype` (per-gametype override the engine
  re-polls ~5s). FF damage is applied by the engine but never scored. ([[t5-tweakable-override-dvars-live]])
- **Flinch:** `scr_gf_flinch` (mult of stock `bg_viewKickScale` 0.2; **default 0.5** = half stock →
  `bg_viewKickScale` 0.1), re-applied every round by `gf_applyFlinch`. ⚠ **`bg_viewKickScale` does NOT
  replicate** — each client scales its own damage view kick from its LOCAL copy, so the server-side
  `setDvar` alone changes nothing for anyone on a dedicated server (it only ever appeared to work on a
  listen host, where the host *is* a client). So the value is **pushed per-client**: to live humans in
  `gf_applyFlinch`, and per-spawn via `gf_applyFlinchClient` (which skips only at an explicit stock 1 —
  a fresh client already sits at 0.2; at the 0.5 default it always pushes). ⚠ That per-spawn push
  **overrides a player's own `bg_viewKickScale`** from their autoexec — the server's value always wins,
  so the dvar is the one flinch number that matters. Session-only; `bg_viewKickScale` is not a saved
  client dvar. ⚠ The two `gf_cfgFloat` defaults (`gf_applyFlinch` + `gf_applyFlinchClient`) must stay in
  lockstep — the seed is seed-if-empty, so a drift is masked by whichever ran first.
  ([[flinch-bg-viewkickscale-not-replicated]])
- **There is NO second flinch multiplier — `g_fix_viewkick_dupe` is INERT on T5 MP.** `scr_gf_flinch` is
  the only flinch knob; `0.5` → `bg_viewKickScale 0.1` is exactly half stock. This file previously claimed
  the dvar doubled felt flinch, on the strength of it *appearing* in the `console_mp.log` dump — which
  proves nothing, because a cfg-created dvar appears there too. A **live RCON read** settles it: the real
  fixes carry a typed domain and a fixed registered default (`g_fixBulletDamageDupe` → `is:"1"
  default:"0" Domain is 0 or 1` — the default stays `0` even though we set `1`), whereas
  `g_fix_viewkick_dupe` → `is:"1" default:"1" **Domain is any text**`, i.e. its "default" merely mirrors
  the value **our own cfg** set. The engine never registered it (Plutonium filed that fix under **SP**).
  Setting it is harmless but does nothing. The panel row is kept, labelled `(INERT)`, so a future
  Plutonium build that *does* register it is easy to spot. ([[engine-dvar-defaults-from-log-dump]])
- **Jump fatigue is OFF** (`scr_gf_jump_fatigue`, default 0 — shipped, public build included). "Jump
  fatigue" is the community name for the engine's **`jump_slowdownEnable`** (stock `1`): every jump drags
  your movement speed, so consecutive hops decay. 42s rounds on wager-sized maps live on short
  repositioning hops, so the stock drag punishes exactly the movement this mode is built on. There is no
  dvar *named* fatigue — the whole engine family is `jump_height` / `jump_slowdownEnable` / `jump_spreadAdd`
  / `jump_stepSize` / `jump_ladderPushVel`. `gf_applyJumpFatigue` (`_gf_rounds.gsc`) re-applies it every
  round; RCON bridge `jumpfatigue_<0|1>`. No per-client push (the `jump_*` family replicates — it must,
  movement is client-predicted), which is what makes it *unlike* flinch.
- ⚠ **CHEAT PROTECTION IS A *CLIENT-SIDE* CHECK — an rcon / `dedicated.cfg` `set` on a dedicated server
  is NOT gated by it.** This is the opposite of what this file and `_gf_bridge.gsc` used to say, and the
  mistake cost a whole wrong "fix": the familiar `Error: jump_height is cheat protected` spam comes from a
  game **CLIENT** exec'ing the stock `default_xboxlive.cfg` at boot — *not* from a server refusing you.
  The `DVAR_CHEAT` flag bites wherever the console belongs to a client: a player's own console, a client
  exec'ing a cfg, and a `setClientDvar` **arriving** at a client. The **dedicated server's own console
  (rcon + `dedicated.cfg`) is not gated**, so `jump_height`, `bg_fallDamage*`, `bg_gravity`, `g_speed`,
  `timescale` etc. are all settable there with a plain `set`, `sv_cheats 0` and all.
  **Proven live on the VPS 2026-07-12** (`sv_cheats 0`, `dedicated` = "dedicated internet server"):
  rcon `set ragdoll_explode_force 18001` — a dvar on the engine's *own* cheat-protected list — read back
  as `18001` (then restored to 18000). Control in the same session: `set bg_gravity 0` (domain starts at
  1) **did** echo its rejection back and kept 800 — so error echoes genuinely reach the panel, and the
  silence on the accepted writes was a real accept, not a swallowed reply.
  ⚠ **What IS unreachable on a dedicated server** (and the only thing the panel is right to grey out) is
  a **cheat-protected CLIENT dvar** — the `r_*` Visual Tweaks — because those ride `setClientDvar` and the
  *client* re-checks on arrival; plus **archived/saved** client dvars (`cg_fov`, `bg_viewBobAmplitudeBase`),
  which Plutonium refuses to let a server write at all.
  ⚠ So **do not route a server dvar through the bridge's `svset_` on the theory that rcon cannot reach
  it** — rcon can. `svset_` survives for two narrower reasons: the **listen/dev host**, where the panel's
  rcon lands on a console that *is* a client's (that is the setup where `set bg_viewKickScale 0.9` was
  once seen refused, which is what seeded the whole misconception), and its `gf_<dvar>` mirror, which
  buys cfg-persistence for free.
- **Reading engine-dvar defaults:** the dvar dump in `console_mp.log` prints **registered defaults, never
  live values** (`g_inactivity` 190 vs our cfg's 300; `sv_maxclients` 4 vs 14). It is the cheapest way to
  read an engine dvar's true default and to prove a dvar is engine-registered at all — a `set` on a name
  the engine never registers creates a user dvar that looks real in every dump and is read by nothing.
  For **live** values use the panel (`/api/dvars?fresh=1`), never the dump and never the cfg.
  ([[engine-dvar-defaults-from-log-dump]], [[read-the-server-not-the-file]])
- ⚠ **THE `bg_*` / `cg_*` PREFIX RULE — a server-side `set` on one is INERT on a dedicated server.**
  The prefix *is* the ownership marker: **`g_`/`sv_`/`scr_` = server** (a `set` works), **`bg_` =
  shared/predicted** and **`cg_` = client game** (every client reads its **own local copy**; the server's
  copy replicates to nobody). This has now bitten twice — `bg_viewKickScale` (flinch), which is why the
  mod must **push it per-client** via `setClientDvar` every spawn, and `bg_viewBobAmplitudeBase`, whose
  `dedicated.cfg` line was commented "bg_* replicates to all clients" and **did nothing for years**.
  It only ever *appears* to work on a listen host, where the host **is** a client.
  **Before setting any dvar server-side, read its prefix.** If it is `bg_`/`cg_`, you have exactly three
  options: push it per-client from GSC (the flinch pattern), hand the player the console command (the
  panel's 📋 clipboard button on the Bob slider), or accept that it is decoration. `cg_hudGrenadeIcon-
  ShowFriendly` in `dedicated.cfg.example` is unaudited and likely inert for the same reason.
  ([[flinch-bg-viewkickscale-not-replicated]])
- **Vision — the contrast pop is Gunfight's DEFAULT look, in every build** (`_gf_rounds.gsc`,
  shipped): `gf_initRoundVision` (called from `onStartGameType`) stamps `level.gf_defaultVision` =
  the map's own set and threads `gf_applyRoundVision`, which **waits for `prematch_over`** and then
  `visionSetNaked( "default_night", 3.0 )` — the `"enhance"` key (saturation 1, contrast 1.2).
  ⚠ It **cannot** be applied from `onStartGameType`: the stock prematch stomps vision *afterwards*
  (matchStartTimer forces `mpIntro`, then at T-2s blends back to the map vision over 3s), so we take
  over the tail of that blend — the 3.0s transition is what makes the reveal read as native. Vision is
  `level` state, so `map_restart` wipes it and this re-runs **every round**.
  The RCON `vision_<key>` override layers on top: it persists a key in `gf_vis_vision`, which
  `gf_roundVisionKey()` reads **inside a strip region** — so the public build has no dvar read at all
  and is always the default. ⚠ **Empty `gf_vis_vision` means "the gf default", NOT "the map vision"** —
  the bare map vision is reachable only via the *explicit* `normal` key, which is why `gf_bridgeVision`
  persists the string `"normal"` instead of clearing the dvar, and why `visreset` restores *enhance*.
- **Video (`r_*`) is stock and stays stock.** `gf_vis_*` server dvars map to client `r_*` (ambient/
  gridint/gridcon/hdr/fog), pushed per human spawn only if non-empty — but these are cheat-protected
  and **unreliable on dedicated**, which is exactly why the look lever above is `visionSetNaked` and
  not r_* ([[rcon-dedicated-dvar-push-limits]]). RCON-only, stripped from public builds. `r_gamma` is a
  saved client dvar Plutonium blocks.
- **Headshots-only** (`level.gf_headshotsOnly`) is a dev-bridge flag, off/undefined in public builds.

### Spawns & wager map zone
Curated hand-placed spawns for **25 maps** (`_gf_locations.gsc`, built once/match, cached in `game[]`);
each map has one set of 5 allies + 5 axis points and one OT flag point. Small mode consumes them via
`onSpawnPlayer`/`onSpawnPlayerUnified`, which **short-circuits all small-mode spawns to the curated
points** so late/async spawns (bot fill, late joiners, 60s forceSpawn) keep fight-facing points instead
of the stock scored pool ([[spawn-wrong-facing-usestartspawns-gate]]). An unlisted map (e.g.
`mp_firingrange`) gets no curated data and degrades to `mp_tdm_spawn` + native Dom-B OT flag — omitting a
map is the supported opt-out ([[firingrange-intentional-bigmap-default]]). ⚠ The curated branch must set
`self.lastSpawnTime`/`lastSpawnPoint` (stock `Callback_PlayerDamage` does unguarded arithmetic on them
for grenade spawn-protection) and does a `positionWouldTelefrag` scan (spawning onto an occupied point
kills the occupant).

**Wager zone without the wager framework:** small mode uses stock `mp_wager_spawn` entities and **keeps
the baked wager blocker entities** (map ents tagged `script_gameobjectname "gun oic hlnd shrp"`) by
adding those four tags to the `_gameobjects::main` allow-list (`["gf","dom"]` + the four in small mode;
large mode omits them so the map opens up; `dom` always kept so the OT B flag survives). A wager compass
material is applied for a 14-map whitelist (the art must be resident — First Strike/Escalation maps keep
their full compass). ⚠ `xblive_wagermatch` is **not** set in `gf.gsc` (the map reads it at level-load,
before the gametype `main()` runs) — it's set to `0` (or `1` for gun/oic/shrp/hlnd) by the RCON map page
before the map loads.

### RCON bridge + admin panel (dev-only)
Both are stripped from public builds; a public build has no RCON control. **`_gf_bridge.gsc`** is the
GSC side: the panel writes `set gf_cmd <seq>:<cmd>`, `gf_bridgePoll` reads+clears at 20 Hz and writes
`gf_ack`, with high-water seq dedup (`level.gf_ackSeq`) so a dropped-packet retry can't double-fire a
non-idempotent command. ⚠ The mark is **seeded from the `gf_ack` dvar every round, never reset** — a
command that restarts the match itself (`matchrestart`, `lobbystart`) wipes the round that owed it an
ack, so a reset would leave the panel un-acked → it resends the same seq → the wiped mark lets it
**re-run** (one click, N restarts, each re-arming the next). Telemetry (dedicated-only single-token reads): **`gf_state`** (11 colon fields:
`wA:wX:round:aliveA:aliveX:gametype:hold:fillN:pAllies:pAxis:parked`) and **`gf_roster`**
(`<num>,<team>,<alive>,<pending>,<bot>;…`). Command feedback is private to `gf_admin_guids`
(`gf_bridgeNotify`); only `saymsg` broadcasts. Team moves: `pteam_<num>_<team>` defers to next-round
prematch (`pers["gf_pendingTeam"]`, applied on `spawned_player`); `pteamforce_` applies now (respawns).
⚠ A live human cannot be moved without dying — deferral is why. Verbs cover bots, balance-teams,
match-control (`lobbystart`, endround, the two restarts, pause/resume), gameplay toggles, and fun/visual
commands. **`roundrestart`** replays the round with no score/loadout-rotation/side-switch by ending it as
a `"tie"` through `gf_endRound` with `game["roundsplayed"]` pre-decremented (endGame's `++` nets it back)
and `level.roundswitch` zeroed for the cycle. **`matchrestart`** restarts the match (scores 0-0, round 1,
same map + teams) by reusing the lobby's fast-restart plumbing: snapshot the sides into the
`gf_teamplan`/`gf_botplan` dvars + `gf_matchArmed=1`, fire `game_ended`, `map_restart(false)` — so the
post-restart gate skips the lobby hold and re-applies the plan. ⚠ Neither restart may be a raw
`fast_restart` / `map_restart`: those skip `_globallogic::endGame`, so the `game_ended` notify that tears
down every per-round `endon("game_ended")` thread never fires — the old round's loops survive as a second
copy AND the engine's re-`InitGame` stacks a second `prematchPeriod()`/`gameTimer()` (double countdown).
**Pause** delegates the freeze to the mod clock (`gf_pauseMatch` — live clock + controls + bots +
`level.gf_matchPaused`, which drives the `gf_pause_hud` "MATCH PAUSED" menuDef) and keeps the B&W
vision on the bridge side, since only the bridge knows the `gf_vis_vision` key to restore on resume;
a `vision_*`/`visreset` issued mid-pause persists its key but doesn't apply until resume. `gf_bridgeInit` re-threads its loops every round behind a `gf_bridge_reinit`
collapse notify ([[onstartgametype-perround-thread-accumulation]]).

**`tools/rcon/`** is a loopback-only (127.0.0.1) Node admin panel (never web-deployed). Its transport is
the load-bearing part: Plutonium answers ~1 RCON reply per 0.7s and silently drops faster sends, so
**everything goes through one paced (`RCON_MIN_GAP=850ms`), priority, coalescing queue**. The UI runs a
single self-scheduling `pollTick` → `/api/tick` (chains `status;gf_state;gf_roster` into one send).
⚠ **Never add another RCON poller** — box services read through the panel API instead
([[rcon-panel-queue-saturation]]). Panel UI: FAVORITES (landing tab) / DASHBOARD / MAPS (live
`sv_maprotation` editor — [[rcon-map-rotation-editor]]) / ADVANCED / CONSOLE tabs; explicit-flex
`layoutColumns` (not CSS multicolumn); a dead-dvar cache silences "Unknown cmd" probing
([[rcon-connect-sweep-unknown-cmd-spam]]). **FAVORITES** is a pinboard: a ☆ on every DASHBOARD/
ADVANCED settings row pins it, and the pinned row is the **same DOM node, borrowed** — moved out of
its home block while the tab is open and put straight back on leaving. Never render a second copy of
a control: reads (`srvApplyValues`) and writes (`sdve`/`sdvv`, Set All, 💾 Save) are keyed by element
id / `data-dvar`, so a duplicate id silently drifts out of sync with the server. Per-gametype rows
(`#srv-gt-body`) are deliberately not pinnable — that block is re-rendered on every dropdown change,
which would destroy a borrowed row's home. ⚠ **The pinboard is stored SERVER-side** — the panel's
gitignored `tools/rcon/prefs.local.json` via `GET`/`POST /api/prefs`, `localStorage.gf_favs` is only a
first-paint cache — so it follows the **panel process**, not the browser: the VPS panel is one pinboard
whether you reach it by RDP or over the SSH tunnel from the laptop, and a laptop's own local panel keeps
its own. `deploy.ps1` `/XF`-excludes the file so `/MIR` can't delete it. Any settings row also answers a
**right-click** (`showRowCtx`): copy its dvar, pin/unpin, reset to default — the default read from the
DOM's own `defaultValue`/`defaultChecked` (so nothing carries a second copy of it), and pushed back
through the row's **own** apply button / change handler, so a reset can't drift from the row's transport.
Per-profile passwords live in gitignored `secrets.local.json`. ⚠ Status/dvar parsing is **end-anchored**
because names can contain spaces (a bot "MCG Gordon" would otherwise leak in as a human —
[[status-parser-name-spaces-bot-miscount]]).

---

## Gametype dvars

Set in `dedicated.cfg` or via RCON. The `scr_gf_*` family persists through `map_restart(true)`. Almost
every mod dvar is **seeded in `gf.gsc onStartGameType`** so the panel's connect-sweep never reads an
unregistered dvar (which echoes "Unknown cmd"); clamps live at the read site (`gf_cfgFloat(dvar,def,lo,hi)`).
**Rule: any new panel-read dvar must be seeded there.** Full ranges + `level.*`/`game[]`/`pers[]` var
tables → `docs/REFERENCE.md`.

**Gunfight rules**
| dvar | default | meaning |
|---|---|---|
| `scr_gf_scorelimit` | 6 | Round wins to win the match (the real match-end threshold). |
| `scr_gf_roundswitch` | 2 | Rounds between side switches. |
| `scr_gf_roundsperloadout` | 2 | Rounds before the shared loadout rotates (clamp 1-9). |
| `scr_gf_timelimit` / `_large` | 0.7 / 1.5 | Round length in minutes, small / large mode (0.7 = 42s). |
| `scr_gf_overtimelimit` / `_large` | 15 / 30 | Overtime seconds, small / large; `0` = OT off (HP decides now). |
| `gf_capture_time` / `_large` | 3.5 / 5 | OT zone hold-to-capture seconds, small / large. |
| `scr_gf_teamspawnmode` | auto | `auto` \| `large` \| `small` (auto goes large when a team hits 5+). |
| `scr_gf_flinch` | 0.5 | Flinch scale (× stock `bg_viewKickScale` 0.2 → 0.1); pushed **per-client** — the server dvar alone doesn't replicate, and the push beats a player's own autoexec (clamp 0-3). |
| `scr_gf_jump_fatigue` | 0 | **0 = OFF (the GF default)** / 1 = stock. Drives the engine's `jump_slowdownEnable` (post-jump movement drag — "jump fatigue"). The mod owns it so OFF ships as a default even with no cfg and no panel (`gf_applyJumpFatigue`, re-applied every round). RCON bridge: `jumpfatigue_<0\|1>`. |
| `g_fix_viewkick_dupe` | 1 | **INERT on T5 MP** — the engine never registered it (live read: `Domain is any text`, `default:` mirrors our own `set`). Harmless, does nothing. Flinch is `scr_gf_flinch` alone. |
| `scr_team_maxsize` | 0 (cfg ships 6) | `>0` caps players/team; overflow → spectator on spawn. |

**Match start / pregame lobby** (match's first round only)
| dvar | default | meaning |
|---|---|---|
| `scr_gf_match_prematch_seconds` / `scr_gf_prematch_seconds` | 20 / 7 | Native prematch countdown length: first round / later rounds. |
| `scr_gf_min_players` | 1 | Min **humans** to start (1 = off); a release condition on the pre-prematch hold. |
| `scr_gf_minplayers_timer` | 0 | Min-players "start anyway" ceiling (s); **0 = never auto-start**. |
| `scr_gf_load_wait` | 0 | Max s to hold the prematch for still-loading clients (0 = off; 3s floor). |
| `scr_gf_load_grace` | 20 | s past prematch_over to keep round-1 grace open for a straggler loader (0 = off). |
| `scr_gf_lobby` | 0 | Match Start: **0 Normal** / **1 Auto** / **2 Manual** (Auto/Manual fast-restart via `map_restart(false)`). |
| `scr_gf_lobby_timer` | 600 | Manual-lobby auto-start ceiling (s); 0 = never auto-start. |
| `g_pregame_enabled` | 0 | **ENGINE** dvar, read at **level load** → **next map only**. `1` = run BO1's stock pre-match warmup lobby (`maps/mp/gametypes/_pregame`) before the match. 100% native; the mod only seeds + exposes it. |
| `party_minplayers` | 2 | Players the **stock warmup** waits for (its only gate). Counts bots. Unrelated to `scr_gf_min_players`. |
| `scr_pregame_timelimit` | 0 | Warmup time limit (min). ⚠ Keep **0** — stock registers it seed-if-empty at 5, and its time-out **rotates the map** instead of starting the match. Seeded to 0 by `gf.gsc` (strip-marked) + `dedicated.cfg.example`. |

**Bots** (dev-only reconciler)
| dvar | default | meaning |
|---|---|---|
| `gf_fill_n` | 0 | Per-team fill target N (3 = 3v3); **0 = reconciler inert** (manual bot control sticks). Clamp 0-6. |
| `gf_fill_kick_floor` | 2 | Client slots kept free for humans; a parked bot is kicked once total ≥ `sv_maxclients − this`. |
| `bot_difficulty` | fu | BotWarfare AI difficulty (easy/normal/hard/fu). Seeded if-empty in `gf.gsc` (a `dedicated.cfg` value or a live panel `botdiff_*` wins); `_bot::diffBots` re-applies the preset from it every 1.5s. |

**Perks / RCON-managed / plumbing**
| dvar | default | meaning |
|---|---|---|
| `gf_perk_on` / `gf_perk_off` | "" | Comma-separated perk lists added/removed after the base set. |
| `gf_admin_guids` | "" | GUID allowlist for private bridge command feedback. |
| `gf_teamplan` / `gf_botplan` / `gf_matchArmed` | "" / "" / "" | Lobby→match transfer + loop-break plumbing (dvars because `map_restart(false)` wipes `game[]`). |
| `gf_vis_*` (`vision`/`ambient`/`gridint`/`gridcon`/`hdr`/`fog`) | "" | RCON visual tweaks; client-side, unreliable on dedicated. |
| `gf_expbullets_radius` | 200 | RCON explosive-bullets blast radius. |

**Bridge telemetry** (dev-only, dedicated-only): `gf_cmd`, `gf_ack`, `gf_state`, `gf_roster`, `gf_say`.
**HUD** (per-client menu dvars): the `ui_gf_*` family (health panel, self bar, loadout overview,
lobby) — see `docs/REFERENCE.md`. **Dev/debug** (strip-wrapped): `gf_debug_spawns`, `gf_debug_hud_pool`,
`gf_debug_elem_probe`, `gf_hitch_pct`, `gf_hitch_debug`, `gf_force_loadout`, `gf_force_camo`,
`gf_diag_cd_no_lobby_dvars`.

**Friendly fire** is set via the **stock** tweakables `scr_team_fftype` + `scr_gf_team_fftype` by the
RCON panel — the mod GSC has **zero** FF references.

**Idle/AFK kicks are stock, not the mod** ([[stock-afk-and-spawn-kick-timers]]) — two independent
sub-5-minute timers, neither with a single `kick()` call in mod GSC. **`g_inactivity`** (input-idle kick,
**spectators included**) is owned by `dedicated.cfg`: the Plutonium `T5ServerConfig` template ships **190**
(kicks a quiet spectator at ~3 min), the VPS + our example now run **300**; the panel's ADVANCED tab edits
it live (cfg is boot-read). **`scr_kick_time`** (stock spawn-or-be-dropped) is *engine-registered at 60* and
armed whenever `level.rankedMatch` is true — which it **is** on our dedicated (`onlinegame 1` +
`xblive_privatematch 0`). It exempts `pers["team"] == "spectator"`, but would kick anyone the mod holds
team-assigned without spawning (a whole Auto/Manual lobby hold; a large-mode late joiner), so `gf.gsc`
pins it to **3600**.

**Connect/timeout drops are a separate axis from AFK — and are TWO dvars, not one**
([[sv-timeout-and-connecttimeout-template-defaults]]). Both measure *packet silence*, never input, and
both are **engine-registered** (no `gf.gsc` seed needed) and **not latched** (the panel's ADVANCED tab
changes them live).
- **`sv_timeout`** — an **already-in-game** client. The `T5ServerConfig` template ships **15**, which is
  hostile two ways: it drops anyone who alt-tabs out of **exclusive fullscreen** (Windows minimizes the
  window, the client stops pumping its main loop and stops sending — borderless/windowed keeps running
  unfocused and never hit it), and it makes the **server ~3× stricter than the client** (`cl_timeout` is
  **40**), so an ordinary lag spike drops a player who is still sitting there waiting. **Never set this
  below `cl_timeout` (40).** VPS + example now run **240** (the engine default). Raising it only costs the
  time a hard-crashed client keeps its player slot.
- **`sv_connectTimeout`** — a client still **connecting/loading**, i.e. the **first-join budget**. Engine
  default **80**, which is thin: a first-timer FastDL-downloads `mod.ff`, then the Plutonium client rebuilds
  its engine *in place* with no loading UI (D3D9 device destroyed + recreated, ~180MB of zones reloaded — a
  30-60s black screen, [[fastdl-first-join-black-screen-rebuild]]) and then runs a Demonware stats/CAC
  re-sync with documented multi-minute stalls. Blowing 80s mid-rebuild is much of why new players report
  having to **connect twice**. VPS + example now run **200** (matching the client's own `cl_connectTimeout`).
  It only ever applies before a client finishes loading, so raising it costs nothing.

**The Plutonium `g_fix_*` family — and why Gunfight ships 3 of 4 against the grain.** These are engine-level
bug fixes Plutonium added, and their **engine defaults split on one line**: a fix with **no gameplay
semantics ships ON**, a fix that **changes felt gameplay ships OFF**, so a stock server stays
vanilla-faithful — bugs and all. Gunfight opts into all of them, because a competitive gametype wants
*correct* damage and flinch, not bug-for-bug BO1 parity. ⚠ **Only 3 of the 4 names below are real dvars** —
`g_fix_viewkick_dupe` is a placebo. Registration and engine defaults come from a **live RCON read** (the
`Domain is …` + `default:` fields), NOT the `console_mp.log` dump: the dump cannot tell a registered dvar
from one our own cfg created ([[engine-dvar-defaults-from-log-dump]]).

| dvar | engine default | GF | what the bug is |
|---|---|---|---|
| `g_fix_damageKickReductionPerk` | **1** (on) | 1 (untouched) | Pure fix, already on. No cfg sets it and it still reports `Domain is 0 or 1`, so the family *exists* in MP. ⚠ That vouches for the family, **not for any individual name** — check each one's own domain. |
| `g_fix_entity_leaks` | **1** (on) | **1** | Engine entity leaks, incl. the `Hunk_AllocAlign failed on 8 bytes` leak from **weapon switching** — this mod's hot path (a fresh shared loadout every round, 24/7). ⚠ The **T5ServerConfig template sets this to 0**, actively *disabling* a fix the engine ships enabled. Restoring it is the one change here that is not a deviation. |
| `g_fix_viewkick_dupe` | **— (unregistered)** | 1 (**inert**) | ⚠ **NOT a real MP dvar.** Live read: `Domain is any text`, and `default:` merely mirrors the value our own cfg `set`. Setting it does nothing — there is no doubled flinch. Kept in cfg/panel only as a tripwire. |
| `g_fixBulletDamageDupe` | **0** (off) | **1** | A bullet through two **intersecting** players deals its damage **twice**. Corrupts three things GF is built on: score **is** cumulative damage dealt, a timed-out round is decided by **most remaining HP**, and rounds are **one life** (a doubled bullet = an unearned instant kill). Bodies overlap constantly in the tight 2v2 spawns. |

⚠ Note the **inconsistent naming** — three are `g_fix_snake_case`, one is `g_fixBulletDamageDupe`
(camelCase, no underscore). A `g_fix_` grep silently misses it. ⚠ All four are set in
`dedicated.cfg`, not seeded by GSC (three are real **engine** dvars; the fourth is inert); the panel
exposes them under ADVANCED → ENGINE GAMEPLAY. The VPS's
`dedicated.cfg` lives on the box and is **not** shipped by `deploy.ps1`, so a change here reaches the VPS
only via the panel (toggle live, then 💾 Save to persist) or a hand edit. ⚠ `g_print_entity_leaks 1` logs
leaks as they happen — the way to actually verify the entity-leak fix rather than assume it.

⚠ **Keep every `dedicated.cfg` comment semicolon-free** — the cfg parser splits on `;` *inside* a `//`
comment and executes each fragment ([[unknown-command-cd-and-cfg-semicolon-parse]]).

**Retired / inert dvars** (no longer read; a stale
cfg value does nothing): `scr_gf_largemode_minplayers`, `scr_gf_roster_wait`, `scr_gf_lobby_hold`/
`_restart`/`_restart_full`, `scr_gf_ff`/`scr_team_ff`, and the `bots_manage_*`/`bots_team_*` family as
Gunfight controls (still seeded for the vendored BotWarfare AI — don't delete the seeds; use `gf_fill_n`).

---

## Building mod.ff

`mod.ff` is a **gitignored build output** (registers the UI rows + strings + menus, compiles the custom
FX). **Pure GSC changes never need a rebuild** — edit + `map_restart`. Rebuild only when a *compiled*
asset changes: `mp/gametypesTable.csv`, `localizedstrings/gf.str`, `localizedstrings/cgame.str`,
`ui_mp/hud_gf.txt` or `ui_mp/hud_gf_health.menu` **structure** (dvar values/positions are
runtime-tunable), or a `raw/fx/misc/*.efx`.

### Overriding stock engine strings (`localizedstrings/cgame.str`)
A localizedstring baked into **our** `mod.ff` **overrides the game's own shipped-zone copy** — so any
single-purpose engine string can be retitled or blanked. ⚠ **The asset name is `<STR FILENAME>_<REFERENCE>`**,
so an engine `CGAME_*` string MUST be declared in a file literally named `cgame.str` (+ `localize,cgame`
in `mod.csv`); the same reference in `gf.str` compiles to `GF_*`, which nothing reads — a **silent no-op**.
An empty value renders as **nothing** (the engine does not fall back to printing the raw key). Currently
shipped: `SB_SCORE` → **"Damage"** (score in this mod IS cumulative damage dealt) and
`CONNECTIONINTERUPTED` → **""** (blanks the between-rounds banner — note the engine's own typo, one R).

The banner blank is the **only** lever that exists: `CG_DrawDisconnect` is client engine code and the
client has **no `cg_drawDisconnect` dvar** (verified against `BlackOpsMP.exe`), so GSC and the menu layer
can't reach it. It **hides** the banner; it does not close the snapshot gap (the irreducible floor of stock
`map_restart(true)` round cycling — see [[connection-interrupted-mitigations]]). ⚠ It also suppresses the
warning for **genuine** lag/packet loss. ⚠ Keep overrides to single-purpose keys: the scoreboard's other
columns are `MPUI_*`, which the combat record / leaderboards / after-action report also use — renaming one
changes it **everywhere**. ⚠ Overrides only reach clients that downloaded `mod.ff`, i.e. players **already
on the server** — a messaging surface, never an ads/acquisition one. Full detail →
[[stock-engine-string-override-via-modff]].

**Always build via `tools/build_ff.ps1`** — it stages `mod.csv` to all five zone-source paths (the
linker reads the **assetlist** copy), stages the transitive `hud_gf_health.menu` explicitly, runs the
linker twice from `cwd=bin/`, cleans staged files back out of `raw/`, and copies `mod.ff` back. Never
call the linker by hand; step-by-step → `docs/DEV.md`. Key gotchas ([[build-stage-transitive-menu]]):
- **menufile double-load kills ALL gametypes.** A `.menu` pulled in by a `loadMenu` (like
  `hud_gf_health.menu` via `hud_gf.txt`) must NOT also be a `menufile` entry in `mod.csv` — double
  registration crashes the menu system and every gametype vanishes from the UI.
- **Empty `ui_mp/mod.txt` + `mod_ingame.txt` stubs** kill a ~4.6s "missing asset" mod-load stall (a
  first-join black-screen contributor — [[fastdl-first-join-black-screen-rebuild]]). Keep both.
- **GSC is deliberately NOT baked into `mod.ff`** — it loads as loose rawfiles; baking the unstripped
  `gf.gsc` once left a dangling dev `#include` that crashed FastDL clients. Never add `rawfile,*.gsc`.
- `build_ff.ps1` cleans `raw/` because Plutonium reads `raw/` as a fallback over IWDs even with no mod
  loaded — a leftover staged file silently overrides the stock game.
- `.efx` files must already live in `<GameRoot>\raw\fx\misc\`; the wrapper does not copy them. Expected
  harmless linker noise: GSC-rawfile errors and stock-FX image-missing errors.

---

## Release, deploy & secrets

**Branch model** ([[repo-release-branch-structure]]): `main` = full dev history + tooling (develop
here). **`release` is the GitHub default branch** — a fresh `git clone` lands there (minimal public
content), so `git checkout main` after cloning and push `main` with `tools/push_all.ps1`. *(The local
`origin/HEAD` may show `main` — that's a stale local ref; the actual GitHub default is `release`.)*

- **`package_release.ps1`** builds the public output (release branch = release zip, byte-identical):
  `mod.ff` + gameplay GSC + README. Dev files excluded by name; `// #strip-begin … #strip-end` regions
  removed, then comments stripped. ⚠ **Strip order is load-bearing** — markers before comments, or the
  dev body leaks (the marker lines are themselves comments; the wiring between them is real code).
  `tools/release_common.ps1` holds the shared drop-list + strip regex (one source of truth for the
  packager AND the verifier below).
- **The public build is a STRIPPED-DOWN Gunfight** — same *gameplay* as the VPS (rounds, shared
  rotating loadouts, overtime + capture zone, auto large/small team mode, curated spawns, damage
  scoring, menu HUD), **none of the dev/ops machinery**. Cut: the whole match-start hold
  (`gf_waitForLoadingClients` and everything it drives — load gate, min-players, Auto/Manual lobby +
  its camera/roster HUD, the team/bot plan transfer), the engine pregame warmup (the
  `g_pregame_enabled` seed is strip-marked — unseeded, the engine defaults it to 0 and BO1's own
  `_pregame` gametype can never come up, so there is **no `_pregame.gsc` to exclude**), bots, the RCON
  bridge, debug tooling, admin pause, the `gf_vis_*` r_* push, the RCON perk overrides, and the
  `level.maySpawn` hook (stock guards it with `isDefined`, so the public build installs none and falls
  through to stock grace/lives). The prematch **countdown stays** — pinned at a fixed 20s/7s, with the
  dvar-tunable version strip-marked behind it. A public server owner still gets the core knobs:
  `scr_gf_scorelimit` / `_timelimit(_large)` / `_overtimelimit(_large)` / `_roundswitch` /
  `_roundsperloadout` / `_teamspawnmode` / `gf_capture_time(_large)` / `scr_gf_flinch` /
  `scr_team_maxsize`.
  ⚠ Two functions are deliberately kept OUTSIDE the strip regions because **live-round code still
  calls them**: `gf_anyTrackedClientLoading()` (called by `gf_roundWatchdog` + `gf_closeGraceEarly`;
  already returns false when the tracker never armed, so it degrades to "nobody is loading") and
  `gf_pushPauseBanner()` (called by `gf_runHealthHUD` every spawn; with `gf_matchPaused` never set it
  just clears the banner). The ~8 inert `isDefined( level.gf_inLobbyHold )` guards in
  `gf_playerSpawnedCB` / `_gf_loadouts` are likewise left in place — they degrade correctly and
  excising conditions from live `if` expressions is pure compile risk for zero behavior change.
- **`tools/verify_release_strip.ps1`** — **run after touching ANY strip region.** GSC resolves symbols
  at *compile* time, so a region that removes a function some KEPT code still calls is an `unknown
  function` that fails the **whole server**, and it won't surface until a client connects. The verifier
  applies the strip regions and statically proves: no kept call lands in stripped code, no kept
  `#include` points at a dropped file, and no dev-only dvar leaked. It does **not** prove the GSC
  parses — a real map load is still the final word.
- **`package_server.ps1`** builds the PRIVATE VPS bundle: the **entire `main` tree** + `mod.ff` +
  `dedicated.cfg`. ⚠ It does **not** strip — the VPS runs dev wiring live by design; only a hardcoded
  `rcon_password` in GSC is blocked ([[package-server-does-not-strip-markers]]).
- **`deploy.ps1`** runs **ON the VPS** as the server's own account (a wrong-account run silently mirrors
  to the wrong profile). `-Mod`: pulls `main`, checks `mod.ff` out of `origin/release` (gitignored on
  `main`), mirrors the tree + `mod.ff` into the mods folder, publishes `mod.ff` to the FastDL web root,
  restarts, and recycles the RCON panel + load-once box services. `-Web`: secret-scans + robocopy-mirrors
  `site/wwwroot` into IIS (preserving the box-owned `web.config`). ⚠ The restart auto-recovers a wedged
  `plutonium.exe -update-only` and drops a self-expiring watchdog-maintenance window
  ([[deploy-recycles-box-services]], [[deploy-restart-wedges-on-plutonium-updater]]).
  ⚠ `mod.ff` only reaches the box via `origin/release`, so committed menu/str/csv/FX changes are NOT
  live until rebuilt + republished ([[modff-drift-vs-gsc-deploy]]); verify a deploy via the two logs in
  the storage-path mod folder ([[vps-gsc-deploy-log-verification]]).

**Secrets** — three layers, no secret ever in a tracked file: (1) gitignored stores hold the values
(VPS `rcon_password`/`g_password` in `dedicated.cfg`; panel password in `secrets.local.json`; server key
in launch config); (2) `.gitignore`; (3) the tracked pre-commit hook `tools/hooks/pre-commit` (enable
once per clone: `git config core.hooksPath tools/hooks`). ⚠ `rcon_password` must be **≤23 chars**
(Plutonium truncates on login — [[rcon-tool-vps-connect-23char-cap]]). **The old leaked RCON password +
server key are in public git history and must be rotated once** — the layers only prevent future leaks.
Security runbook status → `docs/VPS_HARDENING.md`, [[gunfight-us-security-audit]].

## VPS & box services

The live server is a Contabo VPS ([[vps-server-provisioned]]); the launch bat + `sv_maxclients` latch
live only in `C:\gameserver\T5\start_mp_server.bat` ([[vps-launch-bat-and-maxclients-latch]]); the
in-game browser name comes from the Plutonium **server key label**, not `sv_hostname`
([[plutonium-serverkey-sets-browser-name]]). Box helpers are Scheduled Tasks (`register_services.ps1`):
`GF-RconPanel`, `GF-StatusService` (the single box-side RCON reader → writes the public `status.json` +
`activity.json` plus the `.secured`-gated `admin.json`/`health.json`, all atomically), `GF-ConnLogger`
(zero RCON — diffs `admin.json`), `GF-JoinNotify` (ntfy alerts), `GF-Watchdog` (short-lived, re-invoked
every 3 min so it can't exhaust a retry budget; restarts dead tasks, recovers wedges, `map_rotate`s a
stuck match).

**Muting a player (the owner's own connects).** `tools/ignore.local.json` (gitignored + `/XF`-excluded,
so it's box-local; shared loader `tools/ignore_list.ps1`, re-read on change with no restart) lists GUIDs
that are **excluded from activity, not from presence**. `GF-StatusService` filters them out of the
`recent` ring and the public `activity.json` **at the projection, never at the source** — `conn_logger`
still writes every connect to the `players_*.log` day-files, so the admin history stays complete and
un-muting restores the feed retroactively — while they stay in `status.json`'s live `players` list, so
the site's "who's on right now" remains truthful. `GF-JoinNotify` applies the same list *harder*: an
ignored player is treated as **not connected at all**, so they can't count toward "N online" or suppress
the high-priority "server now active" push when a real player joins.
⚠ **Panel-first rule: never add another direct RCON poller on the box** — all readers go through the
panel API on `127.0.0.1:3000`. The same rule now covers **geo**: the panel is the box's single ip-api
client (disk-cached `.geocache.json`, paced under the free tier's 45 req/min), and `/api/geoip?ips=`
is the cache-first, non-blocking batch read everything else uses. Player IP/GUID data reaches the web
only behind IIS Basic auth + the `.secured` interlock.

**Public connect history + country flags.** `activity.json` (public web root, **no** `.secured` gate) is
a 7-day connect/leave feed parsed from the same `players_*.log` day-files as the admin history, but
**PII-stripped**: time/name/event/session + a 2-letter country code, never an IP or GUID. status.html
renders it as a searchable feed and puts a flag next to each live player. Flags are **self-hosted SVGs**
(`site/wwwroot/assets/flags/`, vendored circle-flags) — emoji flags are NOT usable, they don't render on
Windows, and self-hosting keeps the CSP's `img-src 'self'` intact. ⚠ The feed inherits conn_logger's
chain (no `.secured` → no `admin.json` → no day-files → empty feed); status.js falls back to the live
in-memory `recent` ring in that case. Full runbook → `docs/VPS_DEPLOY.md`. Admin site + connection history →
[[gf-admin-connection-history]].

---

# T5 Engine Cheatsheet

> The load-bearing "how to write correct T5 GSC on this engine" reference. This is the **only**
> auto-loaded copy (`docs/REFERENCE.md` is scoped to *this mod's* code). Keep it inline.

## T5 GSC — critical API differences (confirmed-broken → correct)
| Broken in T5 mods | Correct T5 replacement |
|---|---|
| `getPlayers()` | `level.players` (engine array, always available) |
| `spawnStruct()` | Associative array: `s = []; s["key"] = val;` |
| `player isAlive()` / `isAlive(player)` | `player.health > 0` |
| `player.team` | `player.pers["team"]` → `"allies"`/`"axis"`/`"spectator"` |
| `level.onGiveLoadout = ::fn` | Does not exist. Loadout is delivered via `level.giveCustomLoadout` (called by `_class::giveLoadout`); lifecycle via `level.playerSpawnedCB`. |
| `player visionSetNaked(...)` | `visionSetNaked(...)` — a **bare** builtin in the MP VM (global to all clients); the method form throws unknown-function ([[vector-scale-in-common-scripts-utility]]). |

`setDvar("scr_player_healthregentime","0")` DOES work — set it before `_healthoverlay::init()` threads
and the engine disables regen itself.

**Compile-error diagnosis:** `unknown function: @ scripts/mp/<file>::<func>` means the broken call is
*inside* the named function — scan every call within it for (a) a T5-incompatible builtin, (b) a helper
in an un-`#include`d file, (c) a bare builtin called with a method prefix, or (d) **a function you
deleted from a stock script you override**. Causes (b)/(c) → [[vector-scale-in-common-scripts-utility]].

⚠ **(d) — overriding a stock script means keeping its ENTIRE public surface.** GSC resolves symbols at
**compile** time, so a stock caller links against your file *unconditionally* — even from inside a
runtime guard that would never be true. `_globallogic_ui::menuClass` does `if (isPregame()) self
maps\mp\gametypes\_pregame::OnPlayerClassChange(response);`, so shipping a `_pregame.gsc` without that
function fails the WHOLE server with `unknown function @ _globallogic_ui::menuclass` — naming the
caller, not the missing symbol. Before overriding any stock script, grep the raw dump for
`<scriptname>::` and keep every function you find, stubbed if unused.

## T5 engine reference

**Overridable engine/SD callbacks** (most set via `level.*` in `main()`): `playerSpawnedCB` (fires
`spawned_player`), `onSpawnPlayer`/`onSpawnPlayerUnified`, `onPlayerKilled`, `onPlayerDamage`,
`onDeadEvent(team)`, `onOneLeftEvent(team)`, `onTimeLimit`, `onRoundSwitch`, `onRoundEndGame` (returns
the match winner), `giveCustomLoadout`, `_setTeamScore`/`_getTeamScore`. Note `level.maySpawn` is set in
`onStartGameType` and **must be re-set every round** (map_restart wipes it); `spawnClient`/`spawnPlayer`
are engine defaults the mod does not override.

**Spawn pipeline (`spawnPlayer()` order):** (1) `setSpawnVariables` (origin/angles/team,
`sessionstate="playing"`); (2) `[[level.onSpawnPlayer]]()` selects the point and `self spawn(...)`;
(3) `[[level.playerSpawnedCB]]()` fires `spawned_player`; (4) `_class::setClass`; (5)
`_class::giveLoadout` → `[[level.giveCustomLoadout]]()` (our loadout is built here).

**Key state vars:** `game["state"]` (`playing`/`postgame`), `game["roundswon"][team]`,
`game["roundsplayed"]`, `game["switchedsides"]`, `level.gameEnded`, `level.inGracePeriod` (blocks
dead-event/forfeit), `level.inOvertime` (blocks all new spawns), `level.aliveCount[team]` /
`level.alivePlayers[team]` / `level.playerCount[team]`.

**Ending a round/game:** `sd::sd_endGame(winner, "")` (increments the winner's score, checks limits,
cycles the round / ends the match — no manual lives reset or `spawnClient` needed between rounds), or the
core `_globallogic::endGame(winner, reasonText)`. Score: `_setTeamScore(team, n)` / `_getTeamScore(team)`.

**Timer control:** `_globallogic_utils::pauseTimer()` / `resumeTimer()`. Score events (via
`_globallogic_score::givePlayerScore(event, player)`): `kill`, `headshot`, `assist`, `assist_25/50/75`,
`capture`, `defend`, `plant`, `defuse`, `melee_kill`, `hatchet_kill`, `other_kill`.

**Engine callbacks (`_callbacksetup.gsc`):** `CodeCallback_StartGameType`, `PlayerConnect`,
`PlayerDisconnect`, `PlayerDamage`, `PlayerKilled`, `ActorDamage`/`ActorKilled`, `VehicleDamage`,
`HostMigration`, `GlassSmash`.

**Critical gotchas:** `map_restart(true)` keeps `pers[]`/`game[]` and player positions but wipes all
`level.*` + entities; `false` wipes `pers[]`/`game[]` too (only dvars survive); threads survive both.
`updateTeamStatus()` runs `waittillframeend` → `level.aliveCount` can be one frame stale after a kill.
A **demo client is neither a human nor a bot** (`isdemoclient()` true, `istestclient()` **false**, no
`pers["isBot"]`, stock connect parks it teamless at `pers["team"] = ""`), so a bot filter must never be
written as the inverse of a humans-only filter — the real-bot test is `istestclient() && !isdemoclient()`.
`level.inGracePeriod=true` blocks forfeit/dead-event checks; `level.inOvertime=true` blocks new spawns.
`scr_disable_cac 1` auto-assigns `level.defaultClass="CLASS_ASSAULT"` and auto-spawns.

## T5 HUD system

**The per-client DRAWN render cap (the real limit).** T5 has TWO client-HUD limits and only the harmless
one is measurable: the **allocation pool** (`newClientHudElem` succeeds until ~900+ used) is NOT the
constraint; the **per-client DRAWN cap (~17-20)** is — beyond it, the last-created elements silently
don't render even though allocation succeeds and `.alpha`/`.x` read healthy. **No script probe can detect
it** (only the eye). It is **global across ALL hudelem types** (mod HUD + stock ammo/compass + score
popup + OT flag objpoint) and scales with lobby size, so a late-created element vanishes as the lobby
grows. **Mitigation: render mod HUD in the menu layer** (`ui_mp/hud_gf_health.menu`) — a separate system
with no such cap. Server pushes state via `setClientDvar` on change; itemDefs read it via `exp
rect X/Y`, `exp rect W`, `exp forecolor A`, `exp material(dvarString())`, `visible when(...)` (supports
`>`/`<=`/`&&`). Materials must be `material(dvarString())`, never a static `background` (the linker would
try to bundle the `.iwi`). Menu structure needs a `mod.ff` rebuild; dvar values don't. `setText` also
burns configstring slots that survive `map_restart`; use `setValue` for numbers and dvars for per-player
text ([[settext-configstring-exhaustion]]).

**Creation APIs (`_hud_util.gsc`):** `createFontString(font,scale)`, `createIcon(shader,w,h)`,
`createBar(color,w,h)`, `createPrimaryProgressBar()`, and server-side (all players, no per-player pool
slot) `createServerFontString(font,scale,team)`/`createServerIcon(...)`/`createServerBar(...)`. Fonts:
`default`, `bigfixed`, `smallfixed`, `objective`, `extrabig`. **Sizing:** `"default"` at `1.4` is the
reliable small-UI text combo; `fontScale` is a multiplier on the font's native raster, so `"bigfixed"`
at any scale ≤1.0 renders huge/aliased. For a **pulsing** element (score popup) set `baseFontScale`/
`maxFontScale`, not `.fontScale` (`fontPulse` resets to baseFontScale each frame —
[[script-hudelem-number-oversized]]). Server-side text always renders above client bars regardless of
sort.

**Transition helpers (on elements made with `createIcon`/`createBar`):** `transitionSlideIn(dur,dir)`,
`transitionSlideOut`, `hideElem`/`showElem`, `updateBar(frac)`, `setFlashFrac(frac)`.
**Element types:** `newHudElem` (server), `newClientHudElem` (client), `NewScoreHudElem` (score, a
separate pool from the ~17 cap). **Animation:** `fadeOverTime(t)` then set `.alpha`; `moveOverTime(t)`
then set `.x`/`.y`; `.glowColor`/`.glowAlpha`; `fontPulse(player)`. Standard live-element props:
`archived=false`, `hidewheninmenu=true`. Center-screen splashes: `_hud_message::oldNotifyMessage`
(native decode/typewriter FX, serialized, zero mod hudelems — use this, not `notifyMessage`, which needs
the broken `spawnStruct()`).

## T5 asset reference

**GiveWeapon:** `GiveWeapon(name)` or `GiveWeapon(name, dualWield /*bool*/)`. **T5 does NOT take a 3rd
camo arg like T6 in the 2-arg form** — camo goes through `CalcWeaponOptions` (below). Attachments are
baked into the name (`famas_reflex_mp`, `python_speed_mp`). Grenades AND equipment use `GiveWeapon`;
equipment also needs `SetActionSlot(1,"weapon",equip)`.

**Camo** — `camoOpts = int(self CalcWeaponOptions(camoIdx, lensIdx, reticleIdx, reticleColorIdx)); self
GiveWeapon(weapon, 0, camoOpts);`. Camo indices 0-15: 0 Default, 1 Dusty, 2 Ice, 3 Red, 4 OD Green,
5 Desert Nevada, 6 Desert Sahara, 7 Jungle ERDL, 8 Jungle Tiger, 9 Urban German, 10 Urban Warsaw,
11 Winter Siberia, 12 Winter Yukon, 13 Woodland, 14 Woodland Flora, 15 Gold. Pattern camos (5-14) don't
show on neutral-base weapons (python/knife/pistols/launchers). `crossbow_explosive` is the exception
(patterns + gold show). `custom_class["camo_num"]` is a dead end here (only affects the on-back model +
requires a CUSTOM class). Special primaries (minigun/m202/defaultweapon) reject camo — force index 0.

**Perks** (`SetPerk`/`hasPerk`/`UnSetPerk`): `specialty_movefaster` (Lightweight), `specialty_fallheight`
(Lightweight Pro), `specialty_longersprint` (Marathon), `specialty_armorvest`/`specialty_flakjacket`
(Flak Jacket), `specialty_fastreload`, `specialty_gpsjammer` (Ghost), `specialty_bulletpenetration`,
`specialty_quieter` (Ninja), `specialty_gas_mask`, `specialty_stunprotection`, `specialty_shades` (flash
resist), `specialty_fastweaponswitch`, `specialty_twoprimaries`, `specialty_scavenger`, `specialty_rof`,
`specialty_holdbreath`, `specialty_bulletaccuracy`.

**HUD shaders** — weapons default to `"menu_mp_weapons_" + base` (base = no `_mp`, no variant suffix).
Special cases: `ithaca_grip→…ithaca`, `stoner63→…stoner63a`, `crossbow_explosive→…crossbow`,
`minigun_wager→…minigun`, `python_speed→…python`, `m1911→…colt`, `makarov→…makarov`, `cz75→…cz75`.
Lethals: `frag_grenade→hud_grenadeicon`, `satchel_charge_mp→hud_icon_satchelcharge`,
`sticky_grenade→hud_icon_sticky_grenade`, `hatchet→hud_hatchet`. Tacticals use a `hud_us_` prefix:
`flash→hud_us_flashgrenade`, `concussion→hud_us_stungrenade`, `smoke→hud_us_smokegrenade`
(Gas→`hud_icon_tabun_gasgrenade`, Decoy→`hud_nightingale`). Precache in the precache phase
(`PreCacheShader`). Named shaders usable directly: `progress_bar_bg/fill/fg`, `score_bar_bg/allies/opfor`,
`waypoint_*` / `compass_waypoint_*` (`capture`/`defend`/`captureneutral`), `white`, `black`,
`hud_death_suicide` (the skull the health panel + Finger-Gun reuse).

**Audio:** `self playLocalSound(alias)`, `_utility::playSoundOnPlayers(alias, team)`,
`play_sound_in_space(alias, origin)`. `_globallogic_audio::leaderDialog(key[, team])` keys:
`gametype`, `last_one`, `halftime`, `round_success`/`round_failure`, `winning`/`losing`, `timesup`,
`challenge` (set the alias via `game["dialog"][key]`). Music:
`_globallogic_audio::set_music_on_team(state, team)` (`MP_LAST_STAND`, `TIME_OUT`, `SILENT`, …);
`actionMusicSet("state")`.

**Classes/menus:** `level.defaultClass="CLASS_ASSAULT"`; classes `CLASS_ASSAULT`/`SMG`/`CQB`/`LMG`/
`SNIPER`, `CLASS_CUSTOM1..10`. Menu names live in `game["menu_*"]`.

**Useful dvars:** `compass 0/1`, `compassSize`, `cg_fov`, `bg_gravity`, `scr_game_prematchperiod`. Full
weapon-name list + attachment variants → [[reference_t5_mp_weapons]]; the "oldschool/reset" dvar set
(jump/mantle/fall-damage/sprint resets) is documented there rather than pasted here.

## T5 spawn system, game objects, loadout delivery, player utilities

**Spawn points:** `_spawnlogic::getSpawnpointArray(classname)`, `getSpawnpoint_Random(points)`,
`getSpawnpoint_NearTeam(points)`, `getRandomIntermissionPoint()`. SD classnames: `mp_sd_spawn_attacker`
(allies) / `mp_sd_spawn_defender` (axis); TDM start: `mp_tdm_spawn_<team>_start`. Bias with
`_spawning::addSpawnInfluencer(origin,radius,weight,type,teamMask)` / `addSphereInfluencer`.

**Game objects (OT zone):** `zone = _gameobjects::createUseObject(ownerTeam, trigger, visuals, offset)`;
then `allowUse("friendly"|"enemy"|"any"|"none")`, `setUseTime(s)`, `setUseText(&"str")`,
`setVisibleTeam("any")`, `set2DIcon`/`set3DIcon`, `setOwnerTeam(team)`. On a `trigger_radius` the engine
runs the **proximity** think (standing accrues capture, no button). `zone.onUse` fires on capture-complete;
`getOwnerTeam()` reads the owner. Simpler waypoint: `objective_add(id,"active",origin)` +
`objective_icon(id,shader)` + `objective_state`/`_setvisibletoplayer`/`_delete`.

**Loadout delivery:** inside `giveCustomLoadout`, `_wager::setupBlankRandomPlayer(takeAll, chooseBody)`
clears the player, then `GiveWeapon`/`switchToWeapon`/`giveMaxAmmo`/`setWeaponAmmoClip`/`SetPerk`/
`SetActionSlot`. Delay grenades a few seconds after spawn to prevent spawn-instant throws.

**Player utilities:** `freezeControls(0/1)`, `DisableWeaponCycling`/`EnableWeaponCycling`,
`setSpawnWeapon`, `closePopupMenu`/`closeIngameMenu`/`closemenus`, `printBoldOnTeam(text, team)`.
Button polls (in a `wait 0.05` loop): `AttackButtonPressed`, `UseButtonPressed`, `MeleeButtonPressed`,
`AdsButtonPressed`, `JumpButtonPressed`, `FragButtonPressed`, `ActionSlotOneButtonPressed`, …
Strings: `strTok(str, delim)`, `getSubStr(str, start, end)`. Arrays: `quickSort(arr)`. Dynamic dispatch:
`self [[ fnArray[i] ]]()`. Prefer `notify`/`waittill` state machines over polling flags. Scoreboard:
`setscoreboardcolumns(...)` (`kills`/`deaths`/`assists`/`captures`/`headshots`/…). FX: `id = loadfx(path)`
then `spawnFx(id, origin)` / `triggerFx(id)` (⚠ handles are `level.*` → re-load after `map_restart`).
`trigger_off()` blocks players only — a hardcoded engine notify passes through it; divert it by repointing
the level var at a dummy `script_origin` ([[trigger-off-vs-script-notify]]).

---

## Resources (engine references only)
- **Plutonium T5 official source dump** — https://github.com/plutoniummod/t5-scripts (MP/ZM gametypes,
  `_globallogic`, `_class`, `_hud_util`, `sd.gsc`, `_wager.gsc`, …).
- **Local `raw/` engine dump** — `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\raw`
  (the definitive stock GSC/menu/weapon source; read it before reimplementing a stock system).
- **JTAG7371/T5-RawFile-Dump** — https://github.com/JTAG7371/T5-RawFile-Dump.
- **Plutonium docs** — modding/loading mods, GSC scripting features, T5 server setup, BO1 modding forum.
- **Client bind note:** the sprint↔ADS compound bind fix is in [[bo1-sprint-ads-compound-bind]].
