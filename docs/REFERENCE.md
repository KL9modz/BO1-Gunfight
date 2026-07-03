# Black Ops Gunfight - Technical Reference

The complete technical reference: how each system works, every gameplay dvar/variable, and a per-file function reference. *Part of the [Black Ops Gunfight](../README.md) documentation.*

> Scope: this covers the **gameplay** scripts. Dev-only tooling (RCON, bots, debug) is in [DEV.md](DEV.md).

## Contents
- [Architecture & systems](#architecture--systems)
- [Configuration: dvars & variables](#configuration-dvars--variables)
- [Function reference](#function-reference)

## Architecture & systems

Black Ops Gunfight is a standalone team-based, round-based gametype built on the Plutonium T5 engine. It registers as gametype `gf` and is implemented entirely in GSC across six gameplay files under `maps/mp/gametypes/`, plus a menu-driven HUD layer in `ui_mp/`. The entry point is `main` (`gf.gsc`), which wires up the engine callbacks (`onStartGameType`, `onSpawnPlayer`, `giveCustomLoadout`, `onDeadEvent`, `onTimeLimit`, etc.) and registers the gametype's dvars before `onStartGameType` runs per round.

The design philosophy is to lean on stock engine systems wherever possible — round cycling, scoring, intermission, killcam, prematch, and `_gameobjects` are all native — and to own only the few systems the stock game cannot express (a retunable round clock, a gameplay-condition-paused overtime, and a render-cap-exempt HUD). Round cycling is delegated to `_globallogic::endGame`, which performs `map_restart(true)` between rounds. That `map_restart` wipes all `level.*` state, so persistence lives in `game[]` (loadout pool, auto-mode decision, round counter) and `self.pers[]` (team, score, damage), and `onStartGameType` re-derives every per-round `level.*` value on each restart.

### Round lifecycle & win conditions

A match is a sequence of rounds; the first team to `scr_gf_scorelimit` (6) round wins takes the match.

Runtime flow per round:
1. `onStartGameType` (`gf.gsc`) runs on every `map_restart`: forces gameplay dvars (`scr_disable_cac`, `scr_disable_weapondrop`, health-regen off, `level.killstreaksenabled = 0`), resolves team-size mode, sets the per-round native prematch period, and lays down spawns and `_gameobjects`.
2. Players spawn frozen during the engine's native prematch. The first spawn fires `gf_playerSpawnedCB` -> `gf_onSpawned` (`_gf_rounds.gsc`), which threads `gf_tryActivateRound`.
3. `gf_tryActivateRound` dedups (0.2s), waits for `prematch_over`, sets `level.gf_roundActive`, captures the auto team-mode decision, and starts the round clock.
4. The round ends by one of three paths, all routed through `gf_endRound`: a team is fully eliminated (`gf_onDeadEvent`), the clock expires (`gf_onTimeLimit` -> HP decision or overtime), or an overtime zone is captured.
5. `gf_endRound` increments the winner's team score via `level._setTeamScore`, sets the WIN/LOSS banner subtitle (`gf_reasonText`), starts the last killcam, and hands off to `_globallogic::endGame`, which cycles the round or ends the match.

The overall match winner is decided by `gf_onRoundEndGame`, which compares cumulative `game["roundswon"]`. `gf_onRoundSwitch` flips `game["switchedsides"]` at the side-switch interval. Draws (`winner == "tie"`) add no score. `level.gracePeriod` is shortened to 3s so an early team wipe is not held by the stock grace window. Key dvars: `scr_gf_scorelimit`, `scr_gf_roundswitch`; key vars: `level.gf_roundActive`, `level.gf_roundEnding`, `game["roundswon"]`, `game["roundsplayed"]`.

### Custom round clock & warnings

The live (non-overtime) round timer is mod-owned rather than the native round timer. The stock `_globallogic::timeLimitClock` fires its "time running out" sequence (announcer VO, `TIME_OUT` music, countdown beeps) at hardcoded absolute-second thresholds, which on a 45s round triggers almost immediately and cannot be retuned.

`gf_startRoundClock` (`_gf_rounds.gsc`) takes over: it derives the round length from `level.timeLimit` (per-mode), calls `pauseTimer()` — which sets `level.timerStopped` and gates off the entire native warning loop — sets `level.timeLimitOverride = true` to own expiry, and drives the HUD clock via `setGameEndTime`. `gf_roundClock` ticks every 0.1s (`gf_syncRoundRemaining` decrements ms off `gettime`, `gf_updateRoundGameEndTime` re-pushes the HUD end time), and `gf_updateRoundWarning` plays the mod's own warning: a single `leaderDialog("timesup")` at 15s remaining (no music, both teams) and a `mpl_ui_timer_countdown` beep each second in the final 10s. On expiry it cleans its tick object (`gf_cleanupRoundTimerState`) and calls `gf_onTimeLimit`.

Because `pauseTimer` freezes `getTimePassed`, the stock grenade/launcher dud window would mis-fire; `gf_startRoundClock` disables it by setting `level.grenadeLauncherDudTime`/`thrownGrenadeDudTime` to `-1`. The native per-round prematch is left to the engine (countdown, freeze, intro VO, hint, timer-hide), with `gf_nativePrematchTicker` adding the per-second beep the silent stock countdown lacks. Key dvars: `scr_gf_timelimit`, `scr_gf_timelimit_large`, `scr_gf_match_prematch_seconds`, `scr_gf_prematch_seconds`; key vars: `level.gf_roundRemaining`, `level.timeLimitOverride`.

### Overtime & capture zone

If the round clock expires with both teams still alive and `scr_gf_overtimelimit > 0`, the round enters overtime; otherwise the higher-total-HP team wins immediately (`gf_getHPWinner`).

`gf_beginOvertime` (`_gf_rounds.gsc`) mirrors the round clock (ms tracking, `pauseTimer`, `setGameEndTime`, `timeLimitOverride`) and threads `gf_overtime`, which announces overtime (`gf_showOvertimeMessage`), creates the capture zone, and starts `gf_overtimeClock`. The zone is a native `_gameobjects` proximity use-object built by `gf_createOvertimeZone` at the round's flag location (`gf_getOvertimeFlagTrigger`). `gf_overtimeClock` ticks the remaining time and plays accelerating beeps (`gf_updateOvertimeTickSound`) in the final 10s; expiry resolves by HP.

The distinguishing feature is condition-based pause: `gf_overtimeZoneVisuals` polls player positions every 0.1s (`isTouching`), and when a team begins capturing it calls `gf_pauseOvertimeForCapture` (depth-counted, hides the clock via `setGameEndTime(0)`); breaking the capture resumes it (`gf_resumeOvertimeForCapture`). A completed capture fires `zone.onUse` -> `gf_onZoneCapture` -> `gf_resolveOvertime` (notify `gf_ot_done`), ending the round for the capturing team. Bots are steered onto the flag by `gf_botOvertimeAI`/`gf_botPursueOvertimeZone`. Cleanup (`gf_cleanupOvertimeZone`, plus a `game_ended` safety watcher) deletes the objective IDs and objpoints each round so they don't accumulate.

The zone has a two-layer visual driven by `gf_setOvertimeZoneIconColor`: team-relative icons (native `set2DIcon`/`set3DIcon` matched `compass_waypoint_*`/`waypoint_*` pairs, routed friendly/enemy via `setOwnerTeam` — friendly=`defend`/green, enemy=`capture`/red), and an absolute ground apron FX (`spawnFx`, white idle / gold capturing / red contested). Apron FX handles are re-loaded every OT entry (`gf_loadOvertimeApronFx`) because `map_restart` wipes the precached `level.*` handles. Key dvars: `scr_gf_overtimelimit`, `scr_gf_overtimelimit_large`, `gf_capture_time`, `gf_capture_time_large`; key vars: `level.gf_overtimeActive`, `level.gf_overtimeRemaining`, `level.inOvertime`.

### Team-size mode (large vs small)

Gunfight runs two spatial profiles selected by `scr_gf_teamspawnmode` = `auto` (default) | `large` | `small`, resolved every round by `gf_resolveTeamMode` (`_gf_rounds.gsc`) into `level.gf_largeMode`.

- **small** (default at 6 or fewer total players): curated clustered spawns from `_gf_locations.gsc` (falling back to `mp_wager_spawn`, then `mp_tdm_spawn`); the baked wager blockers (`gun`/`oic`/`hlnd`/`shrp`) are kept in the `_gameobjects` allow-list to shrink the play space; the wager compass material is applied; overtime uses the curated flag spot.
- **large** (auto at 7+ total players, allies+axis): the full-map `mp_tdm_spawn` pool; wager blockers are omitted so `_gameobjects::main` deletes them; overtime uses the native Domination B flag (`dom` is always kept in the allow-list so the flag survives); large mode also overrides `level.timeLimit` with `scr_gf_timelimit_large`.

`auto` cannot trust a live roster count inside `onStartGameType` because bots and late joiners connect after it (`_bot::init` is threaded at its end). It therefore reads `game["gf_autoLargeMode"]`, captured once the round is active and everyone has spawned by `gf_updateAutoTeamMode` (called from `gf_tryActivateRound`) and persisted across `map_restart` in `game[]`; the live `level.playerCount` check is only a first-setup fallback. Each mode reads its own `_large`-suffixed copy of the tunables (round length, overtime limit, capture time) so flipping modes never clobbers the other's value. The mode branches live in `onStartGameType` (spawns, allow-list, wager assets), `onSpawnPlayer` (curated vs start spawns), and `gf_getOvertimeFlagTrigger`.

### Loadout system & camos

All players share one random loadout per rotation, guaranteeing fairness without a class-select screen (`scr_disable_cac = 1`).

`gf_initLoadouts` (`_gf_loadouts.gsc`) builds a 54-entry pool once per match (guarded by `game["gf_init"]`): each entry pairs a curated primary (with a hardcoded attachment), secondary, and equipment via `gf_buildLoadout`/`gf_item`. Lethals (Frag/Semtex/Tomahawk) and tacticals (Flash/Stun/Smoke/Gas/Decoy) are assigned in even rotation across the pool, then the whole pool is Fisher-Yates shuffled and stored in `game["gf_pool"]`. `gf_pickLoadout` selects deterministically by `int(game["roundsplayed"] / level.gf_cfg_roundsPerLoadout) % pool.size`, so every client resolves the same loadout by construction and it rotates every `scr_gf_roundsperloadout` (1-9) rounds.

Delivery happens through the `level.giveCustomLoadout` hook (`gf_giveCustomLoadout`, called by `_class::giveLoadout`): it blanks the player (`setupBlankRandomPlayer`), gives primary/secondary/knife with packed camo options, gives lethal (Tomahawks get 2) and tactical with clamped clip counts, gives the placed equipment (skipped for bots), grants the fixed base perks (Lightweight, Marathon, Flak Jacket plus pros), applies admin RCON perk overrides (`gf_perk_on`/`gf_perk_off` via `gf_applyPerkList`), and threads the loadout HUD. Each loadout rolls two independent camos at build time (`load["camo"]`, `load["camoSecondary"]`, each `randomInt(16)`), packed by `CalcWeaponOptions` and passed as `GiveWeapon`'s 3rd arg; special primaries (Minigun/M202, precached via `PrecacheItem` in `onPrecacheGameType`) force camo 0. Key vars: `level.gf_currentLoad`, `game["gf_pool"]`, `level.gf_cfg_roundsPerLoadout`.

### Menu-driven HUD

All mod-owned HUD is rendered through the menu layer (`ui_mp/hud_gf_health.menu`) rather than client hudelems, because T5 has a per-client DRAWN render cap (~17-20 elements) shared across all hudelem types; pushing past it silently drops the last-created elements. The server publishes state through `setClientDvar` only, and menu itemDefs read those dvars — costing ~0 client hudelems.

Three HUD systems live in `_gf_hud.gsc`:
- **Team health panel** — a level thread (`gf_startHealthHUD` -> `gf_updateHealthHUD`, driven by the `gf_health_hud_update` notify and a 0.5s periodic tick) computes per-team totals (`gf_getTeamHealthStats`, counting only players who spawned this round) and publishes them to `level.gf_*`. Each player runs `gf_runHealthHUD`, which pushes those totals to per-client row dvars (`ui_gf_rN_*`, cached so only changes send via `gf_setRowDvar`) and reveals the panel; row 0 is the viewer's own team (green), row 1 the enemy (red). A bottom self-bar (`gf_updateSelfBar`) pushes the viewer's own HP.
- **Loadout overview** — `gf_showWeaponHUD` pushes 8 icon materials + 8 names + the anchor (`ui_gf_lo_*`) for a create-a-class-style summary (primary, secondary, lethal, tactical, equipment, 3 perks), holds ~7s, then slides out (`gf_slideLoadout`).
- **Score popup** — `gf_showScorePopup` reuses the engine's own score element (`self.hud_rankscroreupdate`, a `NewScoreHudElem` from a render-cap-exempt pool) to show "Elimination"/"Assist" in the stock yellow style, with priority so an Assist can't stomp an Elimination.

Damage/score bookkeeping that feeds the popups and scoreboard lives in `gf_onPlayerDamage` (records per-attacker, per-target damage and unique assisters) and `gf_onPlayerKilled` (awards assists, shows popups). Menu *structure* changes need a `mod.ff` rebuild; dvar values and positions are GSC-tunable.

### Spawns & curated locations

Spawn placement depends on team-size mode. `onStartGameType` always places the `mp_tdm_spawn_*_start` start pools and adds either the full `mp_tdm_spawn` pool (large) or the `mp_wager_spawn` cluster when present (small).

`onSpawnPlayer` (`gf.gsc`) resolves the actual spawn point: in small mode it first asks `gf_getCustomSpawnPoint` (`_gf_locations.gsc`) for a curated point, otherwise it uses team-specific start spawns (deliberately not `getSpawnpoint_NearTeam` on a shared pool, which could place a late bot on the wrong side). Curated spawns are defined per map in `gf_getCustomSpawnLocations` (per-team origin/yaw lists, built via `gf_spawnSet`/`gf_sp`) and per-map overtime flag points in `gf_getCustomOvertimeLocation` (`gf_ot`, with capture radius/height). `gf_initCustomLocations` loads these into `level.gf_customSpawns`/`level.gf_customOvertimeLocation`, normalizes and validates them (a set is dropped unless both teams have at least one point). `gf_getCustomSpawnPoint` cycles a per-team cursor through the round's set so successive spawners fan out across the cluster, resetting the cursor each round. Maps with no curated entry (e.g. `mp_firingrange`) fall through to the big-map defaults intentionally. Spawn FX/influencers use the stock `_spawnlogic`/`_spawning` paths (`updateAllSpawnPoints`, `create_map_placed_influencers`).

### Wager map zones

Gunfight reuses the stock wager-map play spaces without enabling the wager-match framework (`xblive_wagermatch` is left 0 — set 1 brings back wager UI/lives/prematch side effects). Many wager blockers are already baked into the map entity lump tagged `script_gameobjectname "gun oic hlnd shrp"`; stock `_gameobjects::main(allowed)` deletes any entity whose tag isn't in the allow-list, so small mode keeps these by adding those tags (`onStartGameType`).

`_gf_wager_zones.gsc` handles the remaining helpers, applied in small mode by `gf_applyWagerZoneAssets`:
- **Compass** — `gf_setupWagerZoneCompass` applies the zoomed `compass_map_<map>_wager` minimap via `_compass::setupMiniMap`, but only for the whitelisted maps (`gf_getWagerCompassMaterial`) whose wager compass image is actually resident during a non-wager match; all other maps return `""` and keep their full compass rather than showing a blank.
- **Cosmodrome collision** — `gf_applyCosmodromeWagerZone` spawns extra small-map collision helpers (`gf_spawnWagerCollision`/`spawncollision`) from models precached in `gf_precacheWagerZoneAssets`.
- **Radiation doors** — `gf_disableRadiationDoors` keeps the center blast doors shut like the stock wager modes by `trigger_off`-ing both switch ents and repointing `level._door_switch_trig1/2` at a dummy `script_origin` so the auto-open notify lands harmlessly. It re-runs each round via `onStartGameType`.

Catalogs of which maps carry baked blockers and wager spawns are kept offline under `tools/wager_entities/` and `tools/wager_spawns/`.

## Configuration: dvars & variables

All gameplay dvars are registered, defaulted, and clamped in code (`gf.gsc::main`/`onStartGameType`, plus the `gf_cfgFloat`/`gf_register*` helpers in `_gf_rounds.gsc`). They can be set in `server/dedicated.cfg` or over RCON. The `scr_gf_*` family is read or re-asserted each `map_restart`, so values persist across rounds. Each team-size mode reads its **own** copy of the tunables via a `_large` suffix, so changing one mode never clobbers the other.

### Gameplay dvars

| Dvar | Default | Range / Values | Mode | Meaning |
|---|---|---|---|---|
| `scr_gf_timelimit` | `0.75` | `0`–`1440` (min) | small | Round length in minutes for small mode. `0.75` = 45s. |
| `scr_gf_timelimit_large` | `1.5` | `0`–`60` (min) | large | Round length in minutes for large mode. `1.5` = 1:30. |
| `scr_gf_scorelimit` | `6` | `0`–`10` | both | Round wins required to win the match. |
| `scr_gf_roundswitch` | `2` | `0`–`9` | both | Rounds played between side switches. |
| `scr_gf_roundsperloadout` | `2` | `1`–`9` | both | Rounds before the shared loadout rotates. Clamped value is written back. |
| `scr_gf_overtimelimit` | `15` | `0`–`120` (s) | small | Overtime length in seconds for small mode. `0` disables OT (HP decides immediately). |
| `scr_gf_overtimelimit_large` | `30` | `0`–`120` (s) | large | Overtime length in seconds for large mode. |
| `gf_capture_time` | `3` | `0.5`–`60` (s) | small | OT zone hold-to-capture time, small mode. |
| `gf_capture_time_large` | `5` | `0.5`–`60` (s) | large | OT zone hold-to-capture time, large mode. |
| `scr_gf_teamspawnmode` | `auto` | `auto` \| `large` \| `small` | both | Spatial mode selector. `auto` goes large once the total in-match player count (allies+axis) reaches `scr_gf_largemode_minplayers`. An invalid value is rewritten to `auto`. |
| `scr_gf_largemode_minplayers` | `7` | `2`–`12` | both | Total in-match players (allies+axis) at/above which `auto` mode uses large spawns; below it, small. `0`–`6` small, `7+` large. |
| `scr_team_maxsize` | `0` (shipped cfg sets `4`) | `>0` caps team | both | If `>0`, caps players per team; overflow is redirected to spectator on spawn (`gf_playerSpawnedCB`). Shipped `dedicated.cfg` sets `4` (4v4); with `sv_maxclients` 10 that's 8 playing + 2 spectator. |
| `scr_gf_match_prematch_seconds` | `15` | `2`–`30` (s) | both | Native prematch countdown length for the match's first round (longer intro). |
| `scr_gf_prematch_seconds` | `7` | `2`–`20` (s) | both | Native prematch countdown length for every later round. |
| `gf_vis_ambient` / `gf_vis_gridint` / `gf_vis_gridcon` / `gf_vis_hdr` / `gf_vis_fog` | `""` (unset) | client-dvar value | both | Persistent video tweaks (→ `r_lightTweakAmbient` / `r_lightGridIntensity` / `r_lightGridContrast` / `r_fullHDRrendering` / `r_fog`). Unset = the mod never touches that client setting (stock). A set value is pushed to every player on every spawn (`gf_applyVisTweaks`). Normally managed by the RCON Visuals sliders via the bridge (`vis<key>_<value>`, value `stock` clears one, `visreset` clears all). Replaces the removed `scr_gf_visualtweaks` force-push; `r_gamma` was dropped entirely — it is a saved client dvar that Plutonium blocks servers from writing. |
| `gf_perk_on` | `""` | comma-separated perk list | both | Extra perks granted, applied **after** the base perk set in `gf_giveCustomLoadout`. RCON-managed. |
| `gf_perk_off` | `""` | comma-separated perk list | both | Perks removed, applied after the base set. RCON-managed. |
| `perk_weapSwitchMultiplier` | engine default | float | both | Engine weapon-swap speed. Inert unless `specialty_fastweaponswitch` is enabled (off by default; opt in via `gf_perk_on`). Not forced by the mod. |

The mod also pins these stock engine dvars every round (not mod-registered, no `scr_gf_` prefix): `scr_disable_cac "1"`, `scr_disable_weapondrop "1"`, `scr_showperksonspawn "0"`, `scr_player_healthregentime "0"`. On Cosmodrome it drives `scr_rocket_event_off` to fire the rocket only once per match.

### Dev / debug dvars (dev builds only)

These are read only by `_gf_debug.gsc` and `_gf_bridge.gsc`, which are stripped from public release builds. Set them before loading the map.

| Dvar | Default | Values | Meaning |
|---|---|---|---|
| `gf_debug_spawns` | `0` | `0` \| `1` | Spawn recorder. `1` threads `gf_startSpawnRecorder` per player. |
| `gf_debug_hud_pool` | `0` | `0` \| `1` | DRAWN-hudelem overlay (`DRAWN: N/17`). `1` threads `gf_startHUDPoolOverlay` per non-bot. |
| `gf_debug_elem_probe` | `0` | `0` \| `1` | One-shot allocation-pool probe; prints `ALLOC free: N` ~9s after spawn. |
| `gf_cmd` | `""` | command string | RCON bridge command inbox (consumed and cleared each tick). |
| `gf_say` | `""` | text | RCON bridge server-say inbox. |
| `gf_state` | `0:0:1:0:0:<gametype>` | status string | RCON bridge state outbox (round/alive counts). |
| `gf_expbullets_radius` | `200` | int | RCON "Blast Radius" slider; read live per shot for the explosive-bullets dev toggle. |
| `sv_FullAmmo` | `0` | `0` \| `1` | Set by the RCON bridge full-ammo toggle. |

### Level state vars (`level.gf_*`)

Set on the level entity; wiped by `map_restart` between rounds and re-derived in `onStartGameType` unless noted.

| Var | Meaning |
|---|---|
| `level.gf_largeMode` | Resolved team-size mode (`true` = large/full-map, `false` = small/curated). Drives spawns, wager-blocker allow-list, and OT flag location. |
| `level.gf_currentLoad` | The shared loadout for the current round (picked from `game["gf_pool"]`). |
| `level.gf_cfg_roundsPerLoadout` | Cached clamped value of `scr_gf_roundsperloadout`. |
| `level.gf_cfg_overtimeLimit` | Cached OT limit for the active mode. |
| `level.gf_overtimeLimitDvar` | Base name of the OT-limit dvar (`scr_<gt>_overtimelimit`). |
| `level.gf_roundActive` / `level.gf_roundEnding` / `level.gf_activatingRound` | Round lifecycle flags. |
| `level.gf_roundRemaining` / `level.gf_roundLastTime` / `level.gf_roundLastTick` / `level.gf_roundClockRunning` / `level.gf_roundWarned` / `level.gf_roundTickObject` | Mod-owned live-round clock state (ms remaining, tick bookkeeping, the `script_origin` that plays countdown beeps). |
| `level.gf_overtimeActive` / `level.gf_overtimeResolving` / `level.gf_overtimePaused` / `level.gf_overtimePauseDepth` | Overtime state and the capture-pause depth counter. |
| `level.gf_overtimeRemaining` / `level.gf_overtimeLastTime` / `level.gf_overtimeLastTickMs` / `level.gf_overtimeClockRunning` / `level.gf_overtimeTickObject` | Mod-owned OT clock state. |
| `level.gf_endReasonText` | WIN/LOSS banner subtitle reason, carried to `gf_endRound`. |
| `level.gf_ot_baseFx_neutral` / `_allies` / `_axis` / `_contested` | OT apron FX handles (reloaded every OT entry via `gf_loadOvertimeApronFx`). |
| `level.gf_warnedLastPlayer` | Per-team flag for the "last one" VO. |
| `level.gf_healthHudStartRound` / `level.gf_healthUpdateQueued` | Health-HUD publisher round guard + update-coalesce flag. |
| `level.gf_headshotsOnly` | When `true`, only head/helmet hits deal damage. Dev/bridge-only (off in release). |
| `level.gf_customSpawns` / `level.gf_customOvertimeLocation` / `level.gf_customSpawnRound` / `level.gf_customSpawnCursor` | Curated small-mode spawn sets, OT flag spot, and per-round round-robin spawn cursors (`_gf_locations.gsc`). |

### Persisted game vars (`game[]`)

`game[]` survives `map_restart`, so these carry state across rounds for the whole match.

| Var | Meaning |
|---|---|
| `game["gf_init"]` | Set after the loadout pool is built and shuffled (build-once guard). |
| `game["gf_pool"]` | The shuffled per-match loadout schedule (all players read the same index). |
| `game["gf_autoLargeMode"]` | The `auto`-mode large/small decision captured at round activation, read next round. |
| `game["gf_damage_match"]` / `game["gf_damage_init"]` | Match-scoped damage-scoring epoch + init guard. |
| `game["gf_rocketLaunched"]` | Cosmodrome: latched once the rocket fires so later rounds suppress it. |
| `game["switchedsides"]` | Side-switch state toggled at halftime. |
| `game["roundswon"]["allies"/"axis"]`, `game["roundsplayed"]` | Standard round-win tallies and round counter (engine-maintained; read for loadout index and match winner). |

### Player-persistent vars (`self.pers[]`)

`self.pers[]` survives `map_restart`, so these persist per player across rounds.

| Var | Meaning |
|---|---|
| `self.pers["team"]` | `"allies"` / `"axis"` / `"spectator"`. May be set to `"spectator"` on overflow when `scr_team_maxsize` is exceeded. |
| `self.pers["gf_damage"]` | Cumulative damage dealt this match (drives the player's scoreboard score). |
| `self.pers["gf_damage_match"]` | Epoch matching `game["gf_damage_match"]`; mismatch resets `gf_damage` to 0. |
| `self.pers["captures"]` | OT zone captures (mirrored to `self.captures` for the scoreboard). |
| `self.pers["gf_spawnedRound"]` | The round index in which the player actually spawned (so team-health stats only count real participants). |
| `self.pers["score"]` | Player score, set silently to avoid the per-damage rank-score popup. |
| `self.pers["isBot"]` | Bot flag, used to gate per-client HUD threads and equipment delivery. |

## Function reference

Every function in the gameplay scripts, grouped by file.

### `maps/mp/gametypes/_gf_rounds.gsc`

The round lifecycle core: it owns the live-round and overtime clocks, the team-size (large/small) spawn-mode resolution, the overtime capture zone (visuals, FX apron, icons, bot AI), the damage/score/assist bookkeeping, and the round-end/win decision logic. It `#include`s `maps\mp\gametypes\_gf_hud` (health-panel push/update helpers), `maps\mp\gametypes\_gf_debug` (dev-only, strip-wrapped), and `maps\mp\gametypes\_hud_util`. It also reaches directly into stock scripts (`_globallogic`, `_globallogic_utils`, `_globallogic_audio`, `_globallogic_score`, `_globallogic_defaults`, `_gameobjects`, `_objpoints`, `_killcam`, `_hud_message`, `_utility`).

#### `gf_registerOvertimeLimitDvar()`
Caches the overtime-limit dvar name `scr_<gametype>_overtimelimit` into `level.gf_overtimeLimitDvar`, then calls `gf_getOvertimeLimit()` to register/read the value.

#### `gf_getOvertimeLimit()`
Returns the current overtime length in seconds, mode-aware. Defines the dvar name if unset, then reads `..._large` (default 30, clamp 0–120) when `level.gf_largeMode` is true, else the base dvar (default 15, clamp 0–120) via `gf_cfgFloat`. Stores the result in `level.gf_cfg_overtimeLimit` and returns it. Each mode reads its own dvar so flipping modes never clobbers the other's value.

#### `gf_getCaptureTime()`
Returns the OT zone hold-to-capture time in seconds, mode-aware: `gf_capture_time_large` (default 5, clamp 0.5–60) in large mode, else `gf_capture_time` (default 3, clamp 0.5–60). Reads via `gf_cfgFloat`.

#### `gf_cfgFloat( dvar, def, lo, hi )`
General float-dvar reader mirroring the stock `register*Dvar` pattern: sets `def` if the dvar is empty, reads it as a float, clamps to `[lo,hi]` via `_globallogic_utils::getValueInRange`, persists the clamped value back if it changed, and returns the clamped value.

#### `gf_nativePrematchTicker()`
Threaded per-second tick during the engine's silent native prematch so the prematch countdown has the same audible cadence as overtime. Ends on `game_ended`; spawns a `script_origin`, loops `playSound("mpl_ui_timer_countdown")` + `wait 1.0` while `level.inPrematchPeriod`, then deletes the tick object (self-stops at `prematch_over`).

#### `gf_resolveTeamMode()`
Resolves and sets `level.gf_largeMode` for the round (called each round from `onStartGameType`). Reads `scr_<gametype>_teamspawnmode`, normalizing any invalid value back to `"auto"`. `"large"`/`"small"` pin the mode directly. `"auto"` prefers the persisted `game["gf_autoLargeMode"]` decision; only as a first-setup fallback does it derive large = total in-match players (`level.playerCount["allies"] + ["axis"]`) `>= gf_largeModeThreshold()` (`scr_gf_largemode_minplayers`, default 7).

#### `gf_updateAutoTeamMode()`
Captures the live auto team-size decision once the round is active and persists it in `game["gf_autoLargeMode"]` for the next round's `onStartGameType`. No-op unless the spawn-mode dvar is `"auto"`. Large = total in-match players (`level.playerCount["allies"] + ["axis"]`) `>= gf_largeModeThreshold()` (`scr_gf_largemode_minplayers`, default 7).

#### `gf_playerSpawnedCB()`
Registered as `level.playerSpawnedCB`; the spawn lifecycle hook. Fires `level notify("spawned_player")` (keeps SD happy). If `scr_team_maxsize > 0` and the player's team is already at the cap, flips them to `"spectator"` and routes to `level.spawnSpectator`, then returns. Otherwise: syncs capture/damage score (`gf_syncCaptureScore`, `gf_initDamageScore`), marks `self.pers["gf_spawnedRound"] = game["roundsplayed"]` (so health stats only count real participants), starts the level-side health-stats publisher once per round (`gf_startHealthHUD`), queues a HUD update, applies any configured `gf_vis_*` video tweaks (`gf_applyVisTweaks`, non-bots; nothing is pushed while they're unset), threads `gf_onSpawned()`, and for non-bots threads the per-player health panel `gf_runHealthHUD()` (T5 client HUD must be created in the player's own context). Strip-wrapped dev block threads `gf_startSpawnRecorder`/`gf_startHUDPoolOverlay`/`gf_debugElemProbe` per the `gf_debug_*` dvars.

#### `gf_onSpawnSpectator( origin, angles )`
Registered as the spectator-spawn callback. Calls stock `_globallogic_defaults::default_onSpawnSpectator`, queues a health HUD update, and (non-bots) re-threads `gf_runHealthHUD()` so spectators always see the whole menu-rendered health panel (cheap re-push of per-client dvars).

#### `gf_onSpawned()`
Threaded from `gf_playerSpawnedCB`. Returns unless the player is on `allies`/`axis`. Resets the per-life `self.gf_assisters` and `self.gf_dmgOnTarget` arrays, and if the round isn't active yet threads `gf_tryActivateRound()`.

#### `gf_tryActivateRound()`
Threaded; opens the round once players have settled. Guards against re-entry via `level.gf_activatingRound`; ends on `game_ended`; waits 0.2s to dedup multiple spawns. Sets `gf_roundEnding=false`, `gf_roundActive=true`, clears `gf_warnedLastPlayer`, forces a health HUD update, and captures the auto team-mode decision (`gf_updateAutoTeamMode`). If still in the native prematch it `waittill("prematch_over")` (so the round clock doesn't draw over the countdown or burn round time), then calls `gf_startRoundClock()`.

#### `gf_startRoundClock()`
Takes over the live-round timer from the engine. Derives round length from `level.timeLimit` (fallback 0.75 min) → `level.gf_roundRemaining` in ms; initializes clock bookkeeping (`gf_roundLastTime`, `gf_roundWarned`, `gf_roundClockRunning=true`), sets `level.timeLimitOverride=true`, and (re)spawns `level.gf_roundTickObject`. Calls `_globallogic_utils::pauseTimer()` (which gates off the native time-out VO/music/beeps), pushes the HUD via `gf_updateRoundGameEndTime`, and sets `level.grenadeLauncherDudTime = -1` / `level.thrownGrenadeDudTime = -1` to disable the stock grenade-dud window broken by the frozen `getTimePassed()`. Threads `gf_roundClock()`.

#### `gf_roundClock()`
Threaded clock loop; ends on `game_ended` and `gf_round_over` (early elimination). Each 0.1s tick: `gf_syncRoundRemaining()`; on `gf_roundRemaining <= 0` it stops the clock, calls `gf_cleanupRoundTimerState()` and hands expiry to `gf_onTimeLimit()` (leaving `timerStopped`/`timeLimitOverride` set); otherwise updates the HUD end-time and the warning (`gf_updateRoundGameEndTime`, `gf_updateRoundWarning`).

#### `gf_syncRoundRemaining()`
Decrements `level.gf_roundRemaining` by the wall-clock ms elapsed since the last `gettime()` sample, advancing `level.gf_roundLastTime`. Clamps to a floor of 0.

#### `gf_updateRoundGameEndTime()`
Pushes the HUD round clock by `setGameEndTime(gettime() + remaining)` from `level.gf_roundRemaining` (clamped non-negative).

#### `gf_updateRoundWarning()`
Drives the round's audio warnings off `level.gf_roundRemaining`. Once at `<= 15000` ms it plays the generic `leaderDialog("timesup")` to both teams (no music). In the final 10s it plays one `mpl_ui_timer_countdown` beep per second (10→1), computing the integer second `tick` and guarding against repeats via `level.gf_roundLastTick`.

#### `gf_cleanupRoundTimerState()`
Clears the round-clock vars (`gf_roundClockRunning=false`, remaining/last-time/last-tick → undefined) and deletes/undefines `level.gf_roundTickObject`.

#### `gf_endRound( winner )`
Central round-end helper (mirrors `sd_endGame`). First calls `gf_resolveOvertime(winner)`; if OT is active it returns (the OT path re-enters). Otherwise sets `gf_roundEnding=true`/`gf_roundActive=false`, notifies `gf_round_over`, tears down the round-timer state, forces a health HUD update, and for a non-tie winner bumps `[[level._setTeamScore]]` by 1. Reads/clears the carried `level.gf_endReasonText` for the WIN/LOSS subtitle, then threads `_killcam::startLastKillcam()` and `_globallogic::endGame(winner, reasonText)` for round cycling / win-limit.

#### `gf_onDeadEvent( team )`
Registered as `level.onDeadEvent`; fires when a team is fully eliminated. No-ops if the round is ending or not active. Winner is `"tie"` when `team == "all"`, else the other team. Forces a health HUD update, sets `level.gf_endReasonText = gf_reasonText("elim", winner)`, and calls `gf_endRound(winner)`.

#### `gf_onTimeLimit()`
Registered (via the round clock) as the timer-expiry handler. No-ops if round ending. If overtime is already active, resolves it by HP (`gf_getHPWinner`). Otherwise reads both teams' HP: if both are alive it either ends immediately by HP when `gf_getOvertimeLimit() <= 0`, or enters overtime via `gf_beginOvertime(limit)`. If only one side is alive, decides immediately by HP. Sets `level.gf_endReasonText` (capture/health) before ending.

#### `gf_resolveOvertime( winner )`
Resolves an in-progress overtime to a winner. Returns false if OT isn't active. Guards against double-resolve via `level.gf_overtimeResolving`; sets it true, `notify("gf_ot_done", winner)`, and returns true (so callers like `gf_endRound` know OT handled it).

#### `gf_beginOvertime( overtimeLimit )`
Initializes and starts overtime. Sets all OT state vars (`gf_overtimeActive=true`, `gf_overtimePaused=false`, `gf_overtimePauseDepth=0`, `gf_overtimeRemaining = overtimeLimit*1000`, `gf_overtimeClockRunning=true`, `level.inOvertime=true`, `level.timeLimitOverride=true`), (re)spawns `level.gf_overtimeTickObject`, calls `_globallogic_utils::pauseTimer()`, pushes the HUD end-time, and threads `gf_overtime()`.

#### `gf_overtime()`
Threaded OT driver; ends on `game_ended`. Shows the OT message, ensures `_gameobjects` vars exist, creates the capture zone (`gf_createOvertimeZone`), threads a game-end cleanup watcher (`gf_overtimeZoneGameEndCleanup`) to avoid leaking objpoints/objective IDs, threads bot OT AI (`gf_botOvertimeAI`) and the OT clock (`gf_overtimeClock`). Then `waittill("gf_ot_done", winner)`: sets `gf_roundEnding=true`, stops the OT clock, cleans up the zone and OT timer state, and calls `gf_endRound(winner)`.

#### `gf_overtimeZoneGameEndCleanup( zone )`
Threaded safety-net watcher. Ends on `gf_ot_done` (making it mutually exclusive with the normal cleanup); on `game_ended` it calls `gf_cleanupOvertimeZone(zone)` so a forfeit/host-migration path that bypasses `gf_resolveOvertime` doesn't leak the zone's HUD elements/objective IDs (which survive `map_restart`).

#### `gf_showOvertimeMessage()`
Announces overtime entry. Plays `mpl_hq_cap_us` to all players, queues two leader VO lines (`"overtime"` then the custom `"gf_overtime_cue"`, which auto-plays ~3s later), and shows a 5.0s red `oldNotifyMessage` "OVERTIME" title to every player (using `game["strings"]["overtime"]` if defined, else `&"MP_OVERTIME_CAPS"`).

#### `gf_overtimeClock()`
Threaded OT clock loop; ends on `game_ended`. Returns if OT became inactive/resolving. Each 0.1s tick: `gf_syncOvertimeRemaining()`; on `<= 0` decides by HP (`gf_getHPWinner`) and `gf_resolveOvertime`. While not paused it pushes the HUD end-time and the tick sound (`gf_updateOvertimeGameEndTime`, `gf_updateOvertimeTickSound`).

#### `gf_syncOvertimeRemaining()`
Decrements `level.gf_overtimeRemaining` by ms elapsed since the last `gettime()` sample, advancing `gf_overtimeLastTime`. Returns early (freezing remaining) while `level.gf_overtimePaused`. Clamps to a floor of 0.

#### `gf_updateOvertimeGameEndTime()`
Pushes the HUD OT clock via `setGameEndTime(gettime() + remaining)` from `level.gf_overtimeRemaining` (clamped non-negative).

#### `gf_updateOvertimeTickSound()`
Plays the OT countdown beeps off `level.gf_overtimeRemaining` (final 10s only): 1 beep/sec from 10s→5s (interval 1000ms), 2 beeps/sec for the last 5s (interval 500ms). Fires immediately on entering the window, then once remaining has dropped by at least the current interval (tracked via `level.gf_overtimeLastTickMs`); driven off OT time so it honors the capture pause.

#### `gf_pauseOvertimeForCapture()`
Pauses the OT clock while a team holds the zone, using a depth counter (`level.gf_overtimePauseDepth`). No-op if OT inactive. Only the first increment actually pauses: syncs remaining, sets `gf_overtimePaused=true`, and `setGameEndTime(0)` to hide the clock (a re-push freeze would flicker).

#### `gf_resumeOvertimeForCapture()`
Decrements the pause depth and, when it returns to 0, resumes: clears `gf_overtimePaused`, resets `gf_overtimeLastTime` to now, and re-pushes the HUD end-time. No-op if OT inactive.

#### `gf_cleanupOvertimeTimerState()`
Resets all OT timer state to inactive/undefined (`gf_overtimeActive=false`, paused/depth cleared, remaining/last-time/last-tick → undefined, `level.inOvertime=false`, `level.timeLimitOverride=false`), deletes the OT tick object, and calls `setGameEndTime(0)`.

#### `gf_setOvertimeZoneIcons( zone, friendlyIcon, enemyIcon )`
Sets the 2D minimap and 3D world icons together from the same native `_gameobjects` path so they can't disagree: `set2DIcon`/`set3DIcon` for both the `"friendly"` and `"enemy"` slots, using `compass_waypoint_X` (2D) and `waypoint_X` (3D) of the same artwork family.

#### `gf_setOvertimeZoneIconColor( zone, team )`
Drives all per-state OT visuals for the given state (`"allies"`/`"axis"`/`"contested"`/neutral). Updates the flag model (`mp_flag_allies_1`/`mp_flag_axis_1`/`mp_flag_neutral`). Rebuilds the world-space apron FX by deleting the old `zone.baseFxHandle` and `spawnFx`+`triggerFx` the state color (white idle / gold capturing / red contested) from the `level.gf_ot_baseFx_*` handles — an absolute cue, since FX can't be team-relative. For a capturing team it sets `setOwnerTeam(team)` and routes friendly→`defend`(green)/enemy→`capture`(red); for neutral/contested it sets owner `"neutral"` and both icons to `captureneutral`(white).

#### `gf_overtimeZoneVisuals( zone, flagTrigger )`
Threaded 0.1s polling driver for all OT zone state (replaces the racy `_gameobjects` use-callbacks). Ends on `game_ended`/`gf_ot_done`. Each tick counts alive, playing players of each team `isTouching` the trigger, derives `newState` (contested if both, else the single team, else neutral), and on a state change: updates icon/FX colors (`gf_setOvertimeZoneIconColor`), sets `scr_obj<label>_flash` and `scr_obj<label>` dvars, starts/stops objpoint flashing, and drives the clock — pauses on neutral→active (`gf_pauseOvertimeForCapture`), resumes on active→neutral (`gf_resumeOvertimeForCapture`, unless already resolving).

#### `gf_cleanupOvertimeZone( zone )`
Tears down the OT zone. No-op if undefined. Deletes the apron FX handle, clears zone interaction state, resets owner team to `"neutral"` and visibility to `"none"`, deletes the two objective IDs (`objIDAllies`/`objIDAxis`) so they're freed each round, deletes the two 3D objPoint HUD elements via `_objpoints::deleteObjPoint`, and deletes any spawned flag model and custom trigger.

#### `gf_loadOvertimeApronFx()`
Re-registers the apron FX handles via `loadfx`, called every OT entry (because `map_restart(true)` wipes the `level.*` handles between rounds). Loads custom `misc/fx_ui_flagbase_gf_white` (mod.ff) for neutral/idle and stock `fx_ray_grnd_loc_marker_ylw_mp`/`..._red_mp` for capturing/contested, storing them in `level.gf_ot_baseFx_neutral/_allies/_axis/_contested` (both team slots share the gold handle).

#### `gf_createOvertimeZone()`
Builds the OT capture zone and returns the `_gameobjects` use-object (or undefined if no flag trigger). Gets the flag trigger (`gf_getOvertimeFlagTrigger`), reloads apron FX, traces down 256u to find the apron ground position/orientation, resolves or spawns the flag model (`mp_flag_neutral`), creates the use object via `_gameobjects::createUseObject("neutral", ...)`, configures it (`allowUse("any")`, `setUseTime(gf_getCaptureTime())`, `setUseText(&"MP_CAPTURING_FLAG")`, neutral icons, `setVisibleTeam("any")`, `onUse = ::gf_onZoneCapture`), stashes apron/flag/trigger refs on the zone, paints the initial neutral color, and threads `gf_overtimeZoneVisuals`.

#### `gf_getOvertimeFlagTrigger()`
Returns the trigger entity used as the OT objective. Finds the Domination B flag (`gf_findDominationBFlag`). In small mode with a curated `level.gf_customOvertimeLocation`, it either repositions the found flag onto that location (`gf_applyCustomOvertimeLocationToFlag`) and returns it, or spawns a custom trigger there (`gf_spawnCustomOvertimeTrigger`). Large mode (or no custom location) returns the native B flag as-is.

#### `gf_findDominationBFlag()`
Locates the Domination center flag among `flag_primary` entities: returns the one with `script_label == "_b"`, falling back to the middle entity of the array if none matches (and undefined if there are none).

#### `gf_applyCustomOvertimeLocationToFlag( flag, location )`
Moves a flag (and any of its `target` visual ents) to the curated `location["origin"]`/`["angles"]`.

#### `gf_spawnCustomOvertimeTrigger( location )`
Spawns and returns a `trigger_radius` at the curated location (default radius/height 96, overridable via `location["radius"]`/`["height"]`), angled to match, tagged with `gf_customOvertimeTrigger = true`.

#### `gf_onZoneCapture( player )`
Registered as the zone's `onUse` (capture complete). No-ops on invalid player or while resolving. Awards the capture (`gf_awardOvertimeCapture`), sets `level.gf_endReasonText = gf_reasonText("capture", team)`, and resolves OT to the capturer's team.

#### `gf_botOvertimeAI( zone )`
Threaded; ends on `game_ended`/`gf_ot_done`. For each alive bot on a real team it threads `gf_botPursueOvertimeZone(flagTrigger)` so bots can win OT by walking onto the proximity flag (no button press needed).

#### `gf_botPursueOvertimeZone( flagTrigger )`
Threaded per-bot pursuit; ends on `death`/`disconnect`/`game_ended`/`gf_ot_done`. Locks the bot's goal (`self.bot_lock_goal = true`) and sets a goal on the flag (radius 32) via `gf_botSetGoal`, then every 1s re-asserts the goal whenever the bot isn't touching the trigger so it walks back and keeps capturing.

#### `gf_botSetGoal( origin, radius )`
Local copy of the stock `_bot_utility::SetBotGoal` wrapper (so this file carries no bot-script dependency): `SetScriptGoal(origin, radius)`, `waittillframeend`, then `notify("new_goal")` — the notify lets it take a goal from the bot's own AI without it being cleared back.

#### `gf_onRoundEndGame()`
Registered as `level.onRoundEndGame`; returns the overall match leader by comparing cumulative `game["roundswon"]["allies"]` vs `["axis"]` — `"tie"` if equal, else the higher team.

#### `gf_onPlayerKilled( eInflictor, attacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration )`
Registered as `level.onPlayerKilled`. Computes a per-death damage cap (`self.maxhealth`, default 100). In a first pass over `self.gf_assisters`, it shows each damager their exact damage-share popup (clamped to cap), `logPrint`s it, and (non-bots) threads `gf_showScorePopup(2,2)` "Elimination" for the killer or `(1,1)` "Assist" for other damagers. A second pass syncs each damager's score and awards `"assist"` score to non-killers, then clears the assisters array. Forces a health HUD update, and (while the round is active) plays the flag-drop/flag-get death stings to the victim's team and the other team respectively.

#### `gf_onPlayerDisconnect()`
Registered as the disconnect callback; queues a health HUD update so the panel reflects the departed player.

#### `gf_onPlayerDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime )`
Registered damage hook; returns the (possibly modified) damage. Returns early for non-positive damage. Queues a health HUD update if the victim is alive. Returns `iDamage` unchanged for self-damage, missing teams, friendly fire, or non-playing states. If `level.gf_headshotsOnly` is set, returns 0 for non-head/helmet hits. Caps recorded damage at the victim's remaining HP, then accumulates `eAttacker.pers["gf_damage"]` (pushed silently via `gf_setPlayerScoreSilent`), records per-target damage in `gf_dmgOnTarget[victimKey]` for the kill popup, tracks the attacker as a unique assister on the victim, and queues a HUD update.

#### `gf_initDamageScoring()`
Match-level damage-score init (once-per-match, guarded by `game["gf_damage_init"]`). Seeds `game["gf_damage_match"]` (a match token = `gettime()`), zeroes every player's `pers["gf_damage"]`, stamps their match token, and syncs each player's score.

#### `gf_syncCaptureScore()`
Ensures `self.pers["captures"]` exists and mirrors it onto `self.captures` (the scoreboard field).

#### `gf_awardOvertimeCapture()`
Increments `self.pers["captures"]` (creating it if absent) and mirrors it onto `self.captures`.

#### `gf_initDamageScore()`
Per-player damage-score init keyed off the match token: ensures `game["gf_damage_match"]` exists, and if the player's stored `pers["gf_damage_match"]` doesn't match the current match it zeroes their `gf_damage` and restamps. Then syncs the score.

#### `gf_syncDamageScore()`
Pushes the player's accumulated `pers["gf_damage"]` to their visible score via `gf_setPlayerScoreSilent` (defaulting it to 0 if unset).

#### `gf_setPlayerScoreSilent( player, score )`
Sets a player's score without triggering the rank score-delta popup that the default `_setPlayerScore` shows on every damage event. No-op if unchanged; otherwise writes `pers["score"]`/`score` and fires `notify("update_playerscore_hud")`.

#### `gf_queueHealthHUDUpdate()`
Coalesces health-HUD updates: if none is already queued, sets `level.gf_healthUpdateQueued=true` and threads `gf_doQueuedHealthHUDUpdate()`.

#### `gf_doQueuedHealthHUDUpdate()`
Threaded debounce: waits 0.05s, clears the queued flag, then calls `gf_forceHealthHUDUpdate()`.

#### `gf_forceHealthHUDUpdate()`
Fires `level notify("gf_health_hud_update")` to push the menu-driven health panel immediately.

#### `gf_onOneLeftEvent( team )`
Registered as `level.onOneLeftEvent` (last player alive on a team). No-ops if the round is ending/not active, the team is invalid, or that team was already warned this round (`level.gf_warnedLastPlayer[team]`). Marks it warned, then to that last living player (`level.alivePlayers[team][0]`) plays `leaderDialogOnPlayer("last_one")` and the local `mus_last_stand` last-stand music.

#### `gf_onRoundSwitch()`
Registered as `level.onRoundSwitch` (halftime/side swap). Toggles `game["switchedsides"]`, sets `level.halftimeType = "halftime"`, and calls `_globallogic::resetOutcomeForAllPlayers()`.

#### `gf_getTeamHP( team )`
Returns the summed living HP of `level.alivePlayers[team]` (engine-maintained), with a defensive `health > 0` guard.

#### `gf_getHPWinner()`
Compares `gf_getTeamHP("allies")` vs `("axis")` and returns the higher team, or `"tie"` on equal HP.

#### `gf_reasonText( reason, winner )`
Returns the neutral WIN/LOSS banner subtitle string fed to `endGame`. `"capture"` → "Objective captured"; `"elim"` → "Both teams eliminated" (tie) or "Team eliminated"; otherwise (health) → "Time expired - equal health" (tie) or "Time expired - health advantage". A `"tie"`/undefined winner selects the draw wording.

### `maps/mp/gametypes/gf.gsc`

The entry point and engine-callback hub for the Gunfight gametype. It runs `_globallogic`/`_callbacksetup` init, registers the stock round/time/score dvars, wires every gametype callback (`level.on*` hooks + `level.giveCustomLoadout`), precaches all loadout/score/overtime assets, sets up spawn pools and the wager-blocker allow-list, and contains the spawn pipeline plus the once-per-match Cosmodrome rocket gate. It `#include`s `maps\mp\_utility`, `maps\mp\gametypes\_hud_util`, `maps\mp\gametypes\_gf_locations`, `maps\mp\gametypes\_gf_rounds`, `maps\mp\gametypes\_gf_loadouts`, `maps\mp\gametypes\_gf_wager_zones`, and (dev-only, strip-wrapped) `maps\mp\gametypes\_gf_bridge`.

#### `main()`
Gametype entry point; sets up the engine and registers all callbacks. Early-returns if the map is `mp_background`. Calls `_globallogic::init()`, `_callbacksetup::SetupCallbacks()`, and `_globallogic::SetupCallbacks()`, then registers the stock dvars: round-switch (default 2), time-limit (default 0.75 = 45s, max 1440), num-lives (default 1), round-win-limit (default 0), score-limit (default 6), round-limit (default 0), grenade-launcher/thrown-grenade dud (0), killstreak delay (0), friendly-fire delay (0). Sets `level.teamBased = true`, `level.overrideTeamScore`/`overridePlayerScore = true`, `level.endGameOnScoreLimit = false`. Wires every gametype hook: `onPrecacheGameType`, `onStartGameType`, `onSpawnPlayer`, `onSpawnPlayerUnified`, `playerSpawnedCB = ::gf_playerSpawnedCB`, `onPlayerKilled = ::gf_onPlayerKilled`, `onPlayerDamage = ::gf_onPlayerDamage`, `onPlayerDisconnect = ::gf_onPlayerDisconnect`, `onSpawnSpectator = ::gf_onSpawnSpectator`, `onDeadEvent`, `onOneLeftEvent`, `onTimeLimit`, `onRoundSwitch`, `onRoundEndGame`, and `giveCustomLoadout = ::gf_giveCustomLoadout`. Finally sets the scoreboard columns to `kills`, `deaths`, `assists`, `captures`. (Note: it does NOT force `xblive_wagermatch` here — the map reads it at level-load before this runs; it is set pre-load by the RCON map page.)

#### `onPrecacheGameType()`
Registered as `level.onPrecacheGameType`; runs once per match to precache all assets. Seeds `game["dialog"]` keys (`gf_overtime_cue` = `ctf_start`, `offense_obj`/`defense_obj` = `generic_boost`, `last_one` = `encourage_last`, `side_switch` = `sd_halftime`). Precaches score-bar/progress-bar/HUD-frame shaders and `PLATFORM_PRESS_TO_SPAWN`, then the full loadout weapon-icon shader set (`menu_mp_weapons_*` for ARs/SMGs/snipers/shotguns/dual-wields/launchers, plus special-icon shaders `hud_m202`, lethal/tactical/equipment HUD icons such as `hud_grenadeicon`, `hud_icon_satchelcharge`, `hud_us_flashgrenade`, `hud_icon_claymore`, etc.). Calls `PrecacheItem` for the four special/extra weapons that the class system never auto-precaches: `m202_flash_wager_mp`, `minigun_wager_mp`, `tabun_gas_mp`, `nightingale_mp` (the `_wager` minigun/M202 builds are used so the killstreak announcer/holster-lock hook doesn't fire). Calls `gf_loadOvertimeApronFx()` to register OT apron FX (re-called per OT entry because `map_restart` wipes the handles). Precaches the OT flag models (`mp_flag_neutral`/`_allies_1`/`_axis_1`), the matched `compass_waypoint_*` / `waypoint_*` icon families (capture/defend/captureneutral, plus `_b` variants), the OT strings `MP_CAPTURING_FLAG`/`MP_OVERTIME_CAPS`, and the mod popup strings `GF_POPUP_ELIMINATION`/`GF_POPUP_ASSIST`. Ends by calling `gf_precacheWagerZoneAssets()`.

#### `onStartGameType()`
Registered as `level.onStartGameType`; runs every round (including each `map_restart`) to configure the live match. Sets `level.noPersistence = true`. Force-sets stock engine dvars every round (since `registerDvars` reseeds them before this fires): `scr_disable_cac "1"`, `scr_disable_weapondrop "1"`, `scr_showperksonspawn "0"`. In a strip-wrapped dev block, when `dedicated == 0` (listen server only) it sets `sv_cheats "1"` and `g_password ""` (no password is set here). Disables health regen (`scr_player_healthregentime "0"`, `level.healthRegenDisabled = true`, `level.playerHealth_RegularRegenDelay = 99999`) and killstreaks (`level.killstreaksenabled = 0`). Calls `gf_registerLoadoutCycleDvar()`, `gf_registerOvertimeLimitDvar()`, `gf_initDamageScoring()`, and `gf_resolveTeamMode()` (sets `level.gf_largeMode`). In large mode, overrides `level.timelimit` from `scr_<gt>_timelimit_large` (default 1.5) and syncs `ui_timelimit`. Shortens `level.gracePeriod` to 3 so early team wipes can end the round quickly. Sets per-round native prematch length via `scr_gf_match_prematch_seconds` (default 15, clamped 2–30) for the match's first round (`game["roundsplayed"] == 0`) or `scr_gf_prematch_seconds` (default 7, clamped 2–20) for later rounds, writing `level.prematchPeriod` accordingly; for rounds 2+ it also rewrites `game["strings"]["match_starting_in"]` to `"ROUND BEGINS IN"`. Threads `gf_nativePrematchTicker()` to restore the per-second tick. Resets round-state flags (`gf_roundActive`, `gf_roundEnding`, `gf_activatingRound`, `gf_overtimeActive`, `inOvertime`, `timeLimitOverride` all false). Calls `gf_rocketOncePerMatch()`. Defaults `game["switchedsides"]` to false; sets `setClientNameMode("auto_change")`. Sets the objective/score/hint text for both teams (`GF_GAMETYPE_DESC`, `GF_GAMETYPE_DESC_SCORE`, `GF_GAMETYPE_HINT`). Registers rank score info (win 5, loss 1, tie 2.5, all kill/headshot/assist tiers 0). Calls `gf_initLoadouts()`, `gf_pickLoadout()`, and `gf_initCustomLocations()`. Builds spawn pools: zeroes `level.spawnMins`/`spawnMaxs`, places `mp_tdm_spawn_<team>_start` points, then adds `mp_tdm_spawn` (large mode) or `mp_wager_spawn` when present else `mp_tdm_spawn` (small mode); calls `updateAllSpawnPoints()`, caches `level.spawn_allies_start`/`spawn_axis_start`, computes `level.mapCenter` via `findBoxCenter` + `setMapCenter`, and sets the demo intermission point. Builds the `_gameobjects` allow-list (`gf`, `dom`, plus `gun`/`oic`/`hlnd`/`shrp` in small mode only) and calls `_gameobjects::main(allowed)`, then `_spawning::create_map_placed_influencers()`. In small mode calls `gf_applyWagerZoneAssets()`. In a strip-wrapped dev block, threads `gf_bridgeInit()` and `_bot::init()`.

#### `gf_rocketOncePerMatch()`
Gates the Cosmodrome launch rocket so it fires once per match instead of once per round. Returns immediately unless the map is `mp_cosmodrome`. If `game["gf_rocketLaunched"]` is already set/true, force-aborts the launch by setting `scr_rocket_event_off "101"` (intentionally past the stock assert bound so the abort always triggers) and returns. Otherwise sets `scr_rocket_event_off "0"` (allow this round) and threads `gf_watchRocketLaunch()`. Called from `onStartGameType()`.

#### `gf_watchRocketLaunch()`
Threaded watcher (level thread) that latches the rocket-launch event across rounds. `waittill("rocket_launch")` (notified by `mp_cosmodrome`), then sets `game["gf_rocketLaunched"] = true` so subsequent rounds suppress the relaunch via `game[]` (the only state surviving `map_restart`).

#### `gf_registerLoadoutCycleDvar()`
Registers and clamps the rounds-per-loadout dvar. Reads `scr_<gt>_roundsperloadout`, defaulting it to 2 if unset, clamps the value to the range 1–9 via `getValueInRange`, persists the clamped value back to the dvar if it changed, and stores the result in `level.gf_cfg_roundsPerLoadout`. Called from `onStartGameType()`.

#### `onSpawnPlayer( teamOverride )`
Registered as `level.onSpawnPlayer`; selects a spawn point and spawns the player. Sets `self.sessionstate = "playing"`, clears `self.usingObj`, and sets `self.maxhealth`/`self.health = 100`. Resolves `spawnTeam` from `self.pers["team"]`, flipping it via `getOtherTeam` when `game["switchedsides"]` is true. In small mode it tries `gf_getCustomSpawnPoint(spawnTeam)` and, if defined, spawns there with the `"gf"` class and returns. Otherwise it uses team-specific start spawns: `mp_tdm_spawn_<team>_start`, falling back to `mp_sab_spawn_<team>_start`; if either has points it picks one via `getSpawnpoint_Random`, else it falls back to `getTeamSpawnPoints` + `getSpawnpoint_NearTeam`. Finally spawns the player at the chosen origin/angles with the `"gf"` class. (Team-specific starts are used deliberately so a late-spawning bot isn't placed on the wrong side of a shared pool.)

#### `onSpawnPlayerUnified()`
Registered as `level.onSpawnPlayerUnified`; the unified spawn-system entry. Clears `self.usingObj`, turns off `level.useStartSpawns` once grace period has ended (`if ( level.useStartSpawns && !level.inGracePeriod )`), then delegates to `_spawning::onSpawnPlayer_Unified()`.

### `maps/mp/gametypes/_gf_loadouts.gsc`

This file owns the entire shared-loadout system: a 54-entry pre-built loadout pool, the once-per-match Fisher-Yates shuffle and even lethal/tactical balancing, the deterministic per-round loadout pick, the actual loadout delivery hook (`level.giveCustomLoadout`), the per-weapon random camo, and the RCON perk-override layer. It `#include`s `maps\mp\gametypes\_gf_hud` (used by `gf_giveCustomLoadout`, which threads `gf_showWeaponHUD`).

#### `gf_initLoadouts()`
Builds the full loadout pool once per match and stores it in `game["gf_pool"]`, guarded by `game["gf_init"]` so it runs only on first call (re-entry returns immediately). Constructs 54 loadouts via `gf_buildLoadout( pri, sec, equip )` using `gf_item(...)` triples for primary/secondary/equipment, organized by weapon class (AR x8, SMG x6, LMG x4, Sniper x2, Shotgun x2, then expanded AR/SMG/Sniper/Shotgun/dual-wield/heavy batches). The two special primaries — M202 (`m202_flash_wager_mp`) and Minigun (`minigun_wager_mp`) — get `pool[n]["camo"] = 0` forced after build because launcher/special primaries reject a real camo. It then assigns lethal and tactical offhands *here* (not per-loadout) for even match-wide distribution: a 3-entry `lethals` array (Frag `frag_grenade_mp`, Semtex `sticky_grenade_mp`, Tomahawk `hatchet_mp`) and a 5-entry `tacticals` array (Flash, Stun `concussion_grenade_mp`, Smoke `willy_pete_mp`, Gas `tabun_gas_mp`, Decoy `nightingale_mp`) are dealt round-robin via `i % size`, copying `["w"]/["n"]/["s"]` into each pool entry's lethal/tactical fields. Finally it runs an in-place Fisher-Yates shuffle (loop `i` from `pool.size-1` down to 1, swap with `randomInt(i+1)`) so order is randomized per match while the modulo-balanced offhand counts are preserved and decorrelated from weapon class. Sets `game["gf_pool"]` and `game["gf_init"] = 1`.

#### `gf_pickLoadout()`
Selects the active loadout for the current round into `level.gf_currentLoad`. Returns early if `game["gf_pool"]` is undefined. Deterministic by construction: `idx = int( game["roundsplayed"] / level.gf_cfg_roundsPerLoadout ) % game["gf_pool"].size` — derived purely from the persisted round counter, so calling it multiple times in a round (e.g. from `onStartGameType` and `gf_endRound`) always yields the same loadout, and the loadout rotates every `level.gf_cfg_roundsPerLoadout` rounds.

#### `gf_giveCustomLoadout()`
The loadout-delivery hook registered as `level.giveCustomLoadout`; called by `_class::giveLoadout` with `self` = the spawning player. Returns early if `level.gf_currentLoad` is undefined or if the player's `self.pers["team"]` is not `"allies"`/`"axis"`. Reads `load = level.gf_currentLoad`, then `self maps\mp\gametypes\_wager::setupBlankRandomPlayer( true, true )` to clear the player and assign a random body. Computes packed camo options for primary and secondary via `CalcWeaponOptions( load["camo"], 0, 0, 0 )` and `CalcWeaponOptions( load["camoSecondary"], 0, 0, 0 )` (stock lens/reticle). Wraps the weapon grants in `DisableWeaponCycling()` / `EnableWeaponCycling()`. Gives primary (`GiveWeapon( load["primary"], 0, camoOpts )`), secondary (with `secCamoOpts` — only shows on real-base secondaries like crossbow, no-op on neutral pistols/launchers), and `knife_mp`, then `switchToWeapon( load["primary"] )` (no `giveMaxAmmo` — relies on default reserve ammo). Gives the lethal with `setWeaponAmmoClip` of `lethalCount` = 1, except `hatchet_mp` which gets 2, then `SwitchToOffhand( load["lethal"] )`. Gives the tactical clamped to 1. Equipment (`load["equip"]` + `SetActionSlot( 1, "weapon", ... )`) is given only when the player is NOT a bot (`self.pers["isBot"]`). Then sets the base perk set: `specialty_movefaster` (Lightweight), `specialty_fallheight` (Lightweight Pro / no fall damage), `specialty_longersprint` (Marathon), `specialty_armorvest` (Flak Jacket), `specialty_flakjacket` (Flak Jacket Pro / throwback grenades). Applies the RCON override layer last via `gf_applyPerkList( getDvar("gf_perk_on"), true )` and `gf_applyPerkList( getDvar("gf_perk_off"), false )` so admin toggles win over the base set. Finally `self thread gf_showWeaponHUD( load )` to slide in the loadout HUD.

#### `gf_applyPerkList( listStr, enable )`
Helper that forces a comma-separated perk list on or off on `self` (the RCON Perks-tab override layer). Returns immediately if `listStr` is undefined or empty (zero spawn cost when no overrides are set). Splits with the native `strTok( listStr, "," )`, skips empty tokens, and for each perk calls `self SetPerk(perk)` when `enable` is true or `self UnSetPerk(perk)` otherwise.

#### `gf_buildLoadout( pri, sec, equip )`
Assembles one loadout associative array from three `gf_item` triples (primary, secondary, equipment). Copies `["w"]/["n"]/["s"]` into `primary*/secondary*/equip*` fields (`primary`, `primaryName`, `primaryShader`, etc.). Rolls two independent camos at build time: `load["camo"] = randomInt(16)` (primary) and `load["camoSecondary"] = randomInt(16)` (secondary, only visible on real-base secondaries). Note: lethal/tactical are deliberately NOT set here — they are assigned in even rotation by `gf_initLoadouts` to keep match-wide counts balanced. Returns the `load` array.

#### `gf_item( w, n, s )`
Tiny constructor for a weapon/item triple. Returns an associative array with `it["w"]` = weapon name, `it["n"]` = display name, `it["s"]` = HUD shader/material name. Used throughout `gf_initLoadouts` to pass primary/secondary/equipment/lethal/tactical descriptors.

### `maps/mp/gametypes/_gf_hud.gsc`

This file owns every mod-rendered HUD surface in Gunfight: the two-team health panel, the per-player self health bar, the create-a-class loadout overview, and the "Elimination"/"Assist" score popup. All four are deliberately MENU-rendered (`ui_mp/hud_gf_health.menu`) or routed through the engine's own score-element pool to stay clear of T5's ~17-element per-client DRAWN render cap; the GSC side only computes team totals and pushes per-client dvars (`setClientDvar`). It `#include`s `maps\mp\gametypes\_hud_util` (for the HUD-element helpers/`fontPulse` family) and calls into stock `maps\mp\gametypes\_hud` for `fontPulse`/`fontPulseInit` on the score popup.

#### `gf_startHealthHUD()`
Level thread that owns the health-panel data pump. Fires and `endon`s `"gf_restart_health_hud"` (singleton) plus `endon "game_ended"`, computes initial totals via `gf_updateHealthHUD()`, threads `gf_periodicHealthHUDUpdate()`, then loops forever recomputing on each `"gf_health_hud_update"` notify. It only publishes team totals to `level.gf_*`; the actual rendering is per-player (`gf_runHealthHUD`) because T5 client HUD elems can't be touched from a level thread.

#### `gf_periodicHealthHUDUpdate()`
Level thread that calls `gf_updateHealthHUD()` every 0.5s as a fallback refresh, so totals stay current even without an explicit `"gf_health_hud_update"` notify. `endon`s `"gf_restart_health_hud"` and `"game_ended"`.

#### `gf_styleHealthElem( elem, sort )`
Helper that stamps the standard live-round HUD-element flags on `elem`: `sort`, `foreground = true`, `hidewheninmenu`, `hidewheninkillcam`, `hidewhileremotecontrolling`, `archived = false`. No-ops if `elem` is undefined. (Legacy helper for client-elem styling; the panel is now menu-rendered.)

#### `gf_updateHealthHUD()`
Recomputes both teams' health stats via `gf_getTeamHealthStats()` and publishes them to `level.gf_*` for the per-player panels to read: current HP (`gf_hpAllies/Axis`), fill fraction (`gf_fracAllies/Axis` via `gf_getHealthFraction`), connected count (`gf_cntAllies/Axis`), and alive count (`gf_aliveAllies/Axis`). Also mirrors HP/count into `level.gf_dbg_*` for the `gf_debug_hud_pool` overlay.

#### `gf_REVEAL_TIME()`
Returns the shared spawn-in reveal duration `0.6` (seconds). The health-panel reveal, loadout slide+fade, and self-bar slide all animate over this so they reveal in sync. GSC-tunable (no mod.ff rebuild).

#### `gf_runHealthHUD()`
Per-player thread that builds, reveals, and continuously updates the health panel. Fires/`endon`s `"gf_kill_health_hud"` (singleton) and `endon`s `"disconnect"`; first destroys any prior panel. Sequence: zero `ui_gf_hp_alpha`, seed totals (`gf_updateHealthHUD`), `gf_createHealthPanel`, `gf_updateHealthPanel`, `gf_hideHealthPanelForIntro`, `gf_revealHealthPanel`, thread `gf_hidePanelChromeOnRoundEnd`, wait `gf_REVEAL_TIME()`, then loop `gf_updateHealthPanel()` every 0.1s. Because the panel is menu-rendered (zero client hudelems), it builds immediately on spawn and coexists with the loadout intro.

#### `gf_createHealthPanel()`
Initializes per-player panel state for the menu-rendered panel. Sets `self.gf_panelActive = true`, resets `self.gf_dvarCache` (so the first per-row push always sends), pushes the player's name to `ui_gf_self_name`, clears the self-bar cache (`gf_sbHp`/`gf_sbShow`), and calls `gf_pushPanelChrome()`. No client hudelems are created.

#### `gf_pushPanelChrome()`
Pushes the menu panel's anchor and material dvars: `ui_gf_panel_x = -22` / `ui_gf_panel_y = 142` (border-box top-left), `ui_gf_skull_mat = "hud_death_suicide"` (alive/dead skull icon), `ui_gf_fade_mat = "hud_frame_faction_fade"` (soft bg fade). Materials are pushed as dvars so the menu uses dynamic `material(dvarString(...))` and the linker doesn't try to bundle the `.iwi`.

#### `gf_hidePanelChromeOnRoundEnd()`
Per-player thread that waits on `level "gf_round_over"` and then hides the menu border (`ui_gf_panel_show 0`), keeping the menu-rendered chrome in sync with the round-end wipe (the row dvars are wiped by `map_restart`, but the border would otherwise linger until the next spawn's teardown). `endon`s `"disconnect"` and `"gf_kill_health_hud"`.

#### `gf_HP_MAX_SKULLS()`
Returns `4` — the per-row skull cap (4v4).

#### `gf_HP_BAR_W()`
Returns `45` — the team-bar fill width in pixels that `gf_pushHealthRow` scales by the health fraction.

#### `gf_updateSelfBar()`
Per-player update of the bottom-center self health bar (menu-rendered). Reads `self.health` (0 if dead/undefined) and computes `show` (1 only if HP > 0 and `sessionstate == "playing"`). Pushes `ui_gf_self_hp` only when the cached `gf_sbHp` changes; on a `show` change it either threads `gf_slideSelfBarIn()` (reveal) or pushes `ui_gf_self_show 0` (hide). Change-gated so it doesn't spam dvars each tick.

#### `gf_slideSelfBarIn()`
Per-player thread that reveals the self bar. Fires/`endon`s `"gf_sb_slide"` (singleton) and `endon`s `"disconnect"`. The intro slide is currently DISABLED (snap-in): it just sets `ui_gf_self_off = 0` and `ui_gf_self_show = 1`. (The menu adds `ui_gf_self_off` to the bar's Y; the disabled animation would slide it 40→0.)

#### `gf_debugElemProbe()` *(dev only — strip-wrapped)*
Dev HUD-allocation probe, only threaded under `gf_debug_elem_probe`. `endon`s `"disconnect"`/`"game_ended"`, waits 9s (after both intros build), then allocates `newClientHudElem` up to 1024 times until the pool runs out, frees them all, and reports the free count via `iPrintLnBold` + `logPrint`. Measures only the allocation pool (~900+ free), NOT the real ~17 DRAWN render cap. Wrapped in `// #strip-begin … // #strip-end` so it's removed from public builds.

#### `gf_hideHealthPanelForIntro()`
Sets `ui_gf_hp_alpha = 0` so the menu-rendered panel chrome starts invisible before the reveal fades it in.

#### `gf_revealHealthPanel()`
Reveals the panel: sets `ui_gf_panel_show = 1` and `ui_gf_hp_alpha = 1`. The fade-in animation is currently DISABLED (snap-in); the commented-out path threaded `gf_fadeDvar("ui_gf_hp_alpha", 0, 1, gf_REVEAL_TIME())`.

#### `gf_fadeDvar( dvarName, from, to, dur )`
Per-player linear fade of a client dvar from `from` to `to` over `dur` seconds in 0.05s frames. Fires/`endon`s `"gf_fade_" + dvarName` (singleton per dvar) and `endon`s `"disconnect"`. Computes `steps = int(dur / 0.05)` (min 1), sets the start value, steps the interpolation, then snaps to `to`. Used to cross-fade the menu chrome via `ui_gf_hp_alpha` (currently unused since the reveal snaps in).

#### `gf_updateHealthPanel()`
Per-tick panel refresh. No-ops unless `self.gf_panelActive` is set. Updates the self bar (`gf_updateSelfBar`), then maps the viewer's own team to row 0 (friendly/green) and the enemy to row 1 (red) — defaulting to allies=green/axis=red for spectators/unassigned — and pushes both rows via `gf_pushHealthRow`.

#### `gf_pushHealthRow( r, team )`
Pushes one row's data as per-client dvars. Reads HP/fraction/count/alive via the `gf_readTeam*` helpers, clamps count and alive to `gf_HP_MAX_SKULLS()`, computes fill width `fw = int(gf_HP_BAR_W()*frac + 0.5)` (forced to 0 when HP ≤ 0, floored to 1 otherwise), then sets `ui_gf_r{r}_hp`, `_fw`, `_cnt`, `_alive` via `gf_setRowDvar`. Colour isn't pushed (the menu fixes row 0 green, row 1 red).

#### `gf_setRowDvar( name, val )`
Change-gated `setClientDvar`: lazily inits `self.gf_dvarCache`, returns early if the cached value equals `val`, otherwise caches and pushes. Prevents the 0.1s loop from spamming 8 pushes per tick; `gf_createHealthPanel` resets the cache so the first push each spawn always sends.

#### `gf_readTeamHP( team )`
Returns the published team current HP (`level.gf_hpAllies`/`level.gf_hpAxis`) for the given team, or `0` if unset/unknown.

#### `gf_readTeamFrac( team )`
Returns the published team health fraction (`level.gf_fracAllies`/`level.gf_fracAxis`), or `0`.

#### `gf_readTeamCount( team )`
Returns the published connected-player count (`level.gf_cntAllies`/`level.gf_cntAxis`), or `0`.

#### `gf_readTeamAlive( team )`
Returns the published alive count (`level.gf_aliveAllies`/`level.gf_aliveAxis`), or `0`.

#### `gf_destroyHealthPanel()`
Tears down the panel by hiding the menu chrome (`ui_gf_panel_show 0`). No client-hudelem cleanup remains since the panel is fully menu-rendered.

#### `gf_getTeamHealthStats( team )`
Builds a `spawnstruct()` of `current`/`max`/`alive` HP and the `players` array for `team`. Iterates `level.players`, skipping players not on the team and — critically — skipping players whose `pers["gf_spawnedRound"]` doesn't equal the current `game["roundsplayed"]` (excludes mid-round joiners who are team-assigned but spectating, which would inflate `max` and halve the bar). For each counted player it adds `gf_getPlayerMaxHealth()` to `max`, and if alive (`health > 0`) adds to `current` and increments `alive`.

#### `gf_getPlayerMaxHealth()`
Returns `self.maxhealth` if defined and > 0, otherwise `100`.

#### `gf_getHealthFraction( current, maxHealth )`
Returns `current / maxHealth` clamped to `[0, 1]`; returns `0` if `maxHealth <= 0`.

#### `gf_showWeaponHUD( load )`
Per-player thread that shows the menu-rendered create-a-class loadout overview, then hides it. No-ops if `load` is undefined. Fires/`endon`s `"gf_kill_loadout_hud"` (singleton), `endon`s `"disconnect"`, `endon`s `level "game_ended"`. Pushes 8 icon materials (`ui_gf_lo_icon0..7`: primary, secondary, lethal, tactical, equipment, then the three fixed perks Flak Jacket/Marathon/Lightweight via `gf_getPerkShader`) and 8 names (`ui_gf_lo_name0..7`), plus the column anchor `ui_gf_lo_cx = -104` / `ui_gf_lo_cy = -6`. The intro slide is DISABLED (snap-in: `ui_gf_lo_off 0`, `ui_gf_lo_alpha 1`, `ui_gf_lo_show 1`). After `wait 7`, it slides+fades out via `gf_slideLoadout( 0, 70, 1, 0, 0.5 )` and sets `ui_gf_lo_show 0`.

#### `gf_slideLoadout( offFrom, offTo, alphaFrom, alphaTo, dur )`
Per-player linear slide+fade of the whole overview over `dur` seconds in 0.05s frames (`steps = int(dur/0.05)`, min 1). The menu adds `ui_gf_lo_off` to every item's X and multiplies `ui_gf_lo_alpha` into every item's alpha, so this drives the block as one. Raises `ui_gf_lo_show` on the first frame (so the block is never seen parked), keeps `ui_gf_lo_off` fractional (no `int()` rounding, to avoid uneven 20Hz steps), then snaps to the final `offTo`/`alphaTo`.

#### `gf_getPerkShader( specialty )`
Resolves a perk specialty string to its full HUD shader name via the engine perk tables: `level.perkReferenceToIndex[specialty]` → `level.tbl_PerkData[idx]["reference_full"]`. Returns `"white"` if the perk/index isn't found.

#### `gf_destroyLoadoutHUD()`
Hides the overview (`ui_gf_lo_show 0`). Also defensively tears down any legacy `self.gf_loadoutHudElems` client elements (`destroyElem` each, then clears the array) to tolerate stale state.

#### `gf_popupSize()`
Returns `1.5` — the resting fontscale of the score popup (stock score popup is 2.0). Applied via `baseFontScale`/`maxFontScale`, not `.fontscale`, because `fontPulse` always animates back to `baseFontScale`.

#### `gf_popupX()`
Returns `170` — horizontal offset of the popup from screen centre (+ = right; element is centre-aligned).

#### `gf_popupY()`
Returns `0` — vertical offset of the popup from screen centre (+ = down, − = up; 0 = middle screen).

#### `gf_showScorePopup( popupType, pri )`
Per-player thread that shows the stock-yellow "Elimination"/"Assist" popup by reusing the engine's own score element `self.hud_rankscroreupdate` (a `NewScoreHudElem`, render-cap-exempt). `endon`s `"disconnect"`; defaults `pri = 1`. Priority guard: if a higher-priority popup is still on screen (`now < self.gf_popupExpire && self.gf_popupPri > pri`) it returns without stomping it; otherwise it records `gf_popupPri` and `gf_popupExpire = now + 1000` (ms). Ensures the element exists (`gf_ensureScorePopupElem`), picks `&"GF_POPUP_ELIMINATION"` when `popupType == 2` else `&"GF_POPUP_ASSIST"`, notifies `"update_score"` (cancel any in-flight stock rank popup on the shared element) and fires/`endon`s `"gf_dmg_popup"`. Sets the element's label/color/`baseFontScale`/`maxFontScale`(=size×2)/`fontScale`/x/y, `setText`s it, sets alpha 0.85, threads `_hud::fontPulse`, then after `wait 1` `fadeOverTime(0.75)` to alpha 0. (`popupType`: 2 = elimination, 1 = assist.)

#### `gf_ensureScorePopupElem()`
Lazily creates `self.hud_rankscroreupdate` as a fallback for the engine's `_rank::onPlayerSpawned` creation, so the popup works even if that init didn't run. Returns early if the element already exists. Otherwise creates a `NewScoreHudElem(self)` and stamps the stock score-popup properties verbatim: center/middle alignment, x=0/y=−60, `font "default"`, `fontscale 2.0`, `archived false`, color (1,1,0.5), alpha 0, sort 50, then `_hud::fontPulseInit()` and `overrridewhenindemo = true` (engine spelling preserved).

### `maps/mp/gametypes/_gf_locations.gsc`

Holds the per-map curated Gunfight spawn sets and overtime flag points, plus the helpers that load, normalize, validate, and dispense them at runtime. It defines no `#include` directives and calls only engine builtins (`getDvar`, `logPrint`, `isDefined`). The curated data is consumed by the spawn pipeline and overtime system in `_gf_rounds.gsc`/`gf.gsc`, which read the `level.gf_customSpawns` / `level.gf_customOvertimeLocation` state this file populates.

#### `gf_initCustomLocations()`
Entry point that loads and prepares all custom-location state for the current map. Reads the curated spawn data into `level.gf_customSpawns` (via `gf_getCustomSpawnLocations()`) and the overtime point into `level.gf_customOvertimeLocation` (via `gf_getCustomOvertimeLocation()`), initializes the round tracker `level.gf_customSpawnRound = -1` and the per-team dispense cursor `level.gf_customSpawnCursor = []`, then runs `gf_normalizeCustomSpawnLocations()`, `gf_validateCustomLocations()`, and `gf_validateCustomOvertimeLocation()` to coerce the data into the canonical "sets" form and log/drop anything malformed.

#### `gf_getCustomSpawnLocations()`
Returns the curated small-mode spawn data for the current map, or an empty result for unmapped maps. Reads `mapname` from the `mapname` dvar and matches it against a long `if` chain of supported maps (`mp_villa`, `mp_cosmodrome`, `mp_cairo`, `mp_cracked`, `mp_silo`, `mp_nuked`, `mp_array`, `mp_mountain`, `mp_radiation`, `mp_hanoi`, `mp_crisis`, `mp_russianbase`, `mp_duga`, `mp_havoc`, `mp_golfcourse`, `mp_area51`, `mp_drivein`, `mp_zoo`, `mp_outskirts`, `mp_hotel`, `mp_gridlock`, `mp_stadium`, `mp_kowloon`, `mp_discovery`, `mp_berlinwall2`). It builds a `result` array with `result["sets"]`, `result["allies"]`, and `result["axis"]` keys; for a matched map it creates a single spawn set via `gf_spawnSet()`, fills the `allies`/`axis` arrays with five `gf_sp( origin, yaw )` points each (the baked coordinates/angles captured with the `gf_debug_spawns` recorder), appends the set to `result["sets"]`, and returns immediately. Maps with no match fall through to `return result` (empty `sets`), which downstream causes small mode to fall back to wager/TDM spawns.

#### `gf_getCustomOvertimeLocation()`
Returns the curated overtime flag point for the current map, or `undefined` if the map has none. Reads `mapname` and matches it through an `if` chain covering the same map list; each match returns a single `gf_ot( origin, yaw )` struct (origin, yaw, plus the 96/96 radius/height defaults set by `gf_ot`). Unmatched maps return `undefined`, so overtime falls back to its default flag spot (e.g. native Domination B).

#### `gf_spawnSet()`
Constructs and returns an empty spawn-set associative array with initialized `set["allies"]` and `set["axis"]` arrays. Used as the container for one round's pair of team spawn lists.

#### `gf_sp( origin, yaw )`
Builds a single spawn-point struct: an associative array with `point["origin"] = origin` and `point["angles"] = ( 0, yaw, 0 )` (yaw-only orientation). Returns the struct.

#### `gf_ot( origin, yaw )`
Builds a single overtime-flag struct: `point["origin"] = origin`, `point["angles"] = ( 0, yaw, 0 )`, plus the zone dimensions `point["radius"] = 96` and `point["height"] = 96`. Returns the struct.

#### `gf_getCustomSpawnPoint( team )`
Dispenses the next curated spawn point for `team` ("allies"/"axis"), cycling through the active set's list round-robin. Returns `undefined` if no custom spawn data exists (`level.gf_customSpawns` / `["sets"]` undefined, or zero sets). It derives `roundKey` from `game["roundsplayed"]` (defaulting to 0); when the round changes (`level.gf_customSpawnRound != roundKey`) it stores the new round and resets both per-team cursors (`level.gf_customSpawnCursor["allies"/"axis"] = 0`). It selects the set with `setIndex = roundKey % sets.size` (so sets rotate by round when more than one exists), returns `undefined` if that set's team list is empty, otherwise returns `spawns[ cursor % spawns.size ]` and post-increments the team cursor so successive callers within the round get successive points.

#### `gf_normalizeCustomSpawnLocations()`
Coerces legacy flat `allies`/`axis` arrays into the canonical single-set form so the rest of the code only deals with `["sets"]`. If `level.gf_customSpawns` is undefined it creates it with an empty `["sets"]` and returns; it ensures `["sets"]` exists, and returns early if at least one set is already present. Otherwise it counts the flat `allies`/`axis` arrays via `gf_getCustomSpawnCount()`; only if both have at least one point does it build a new set with `gf_spawnSet()`, copy the flat arrays into it, and store it as `level.gf_customSpawns["sets"][0]`.

#### `gf_validateCustomLocations()`
Validates the loaded spawn sets, dropping any set that lacks points for both teams, and logs the outcome. Returns early if `level.gf_customSpawns` is undefined; ensures `["sets"]` exists. It iterates every set, counting team points with `gf_getCustomSpawnSetCount()`; sets with both `allies > 0` and `axis > 0` are kept (accumulating `totalAllies`/`totalAxis`), otherwise the set is skipped with a `logPrint` warning. It rewrites `level.gf_customSpawns["sets"]` to the surviving sets and `logPrint`s a load summary (set/allies/axis counts) when any remain. If no sets survive but the flat `allies`/`axis` arrays still hold partial data, it logs an "ignored" warning, then clears both flat arrays.

#### `gf_validateCustomOvertimeLocation()`
Validates the loaded overtime flag, discarding it if malformed. Returns early if `level.gf_customOvertimeLocation` is undefined; if it has both `["origin"]` and `["angles"]` it `logPrint`s a success message and returns. Otherwise it logs an "ignored: missing origin or angles" warning and sets `level.gf_customOvertimeLocation = undefined`.

#### `gf_getCustomSpawnCount( team )`
Returns the number of points in the legacy flat `level.gf_customSpawns[team]` array, or `0` if `level.gf_customSpawns` or the team array is undefined. Used by the normalize/validate helpers.

#### `gf_getCustomSpawnSetCount( set, team )`
Returns the number of points in a given set's `set[team]` array, or `0` if `set` or `set[team]` is undefined. Used by `gf_validateCustomLocations()` to gate which sets are kept.

### `maps/mp/gametypes/_gf_wager_zones.gsc`

This file provides the wager-zone support layer for Gunfight: it precaches and applies the map-specific assets needed to reuse stock wager-map play spaces without enabling the wager-match framework. Responsibilities are the wager (zoomed) minimap compass material, the Cosmodrome small-map collision helpers, and a fix to keep the mp_radiation center blast doors shut. It calls into stock scripts directly: `maps\mp\_compass::setupMiniMap` (compass) and `common_scripts\utility::trigger_off` (radiation doors). (The actual blocker entities are preserved elsewhere, via the `_gameobjects` allow-list in `gf.gsc` — not here.)

#### `gf_precacheWagerZoneAssets()`
Precaches the custom collision models for the Cosmodrome wager zone so they can be spawned later. Reads `mapname` from the dvar; only when it is `mp_cosmodrome` does it `precacheModel` the three collision geometry models (`collision_geo_mc_8x560x190`, `collision_geo_mc_4x52x190`, `collision_geo_mc_4x156x190`). No-op on every other map. Intended to run during precache.

#### `gf_applyWagerZoneAssets()`
Runtime entry point that applies wager-zone behavior once the map is loaded. Bails immediately if there are no `mp_wager_spawn` entities on the map (`getEntArray( "mp_wager_spawn", "classname" )`, returns if size `<= 0`). Otherwise reads `mapname`, then always calls `gf_setupWagerZoneCompass( mapname )`; additionally calls `gf_applyCosmodromeWagerZone()` on `mp_cosmodrome` and threads `gf_disableRadiationDoors()` on `mp_radiation` (the radiation fix runs on a level thread because it waits).

#### `gf_disableRadiationDoors()`
Threaded level routine (from `gf_applyWagerZoneAssets`) that keeps the mp_radiation center blast doors shut, matching stock wager behavior. Has `level endon( "game_ended" )`. The problem it solves: the stock auto-open fires a direct script notify on `level._door_switch_trig1` at `prematch_over + 0.3s`, and `trigger_off()` only blocks the player-use path, not script notifies. The two-part fix: (1) `waittillframeend` then loop with `wait 0.05` until both `level._door_switch_trig1` and `level._door_switch_trig2` are defined, then `trigger_off()` both switch ents (via `common_scripts\utility::trigger_off`) to block the player/bot use path; (2) wait for `prematch_over` (only if `level.prematchPeriod > 0 && level.inPrematchPeriod == true`) plus `wait 0.2`, then spawn a dummy `script_origin` at `(0,0,0)` and repoint both `level._door_switch_trig1` and `level._door_switch_trig2` at it. The auto-open notify then lands on the dummy while the real door driver stays parked on the now-silent triggers, so the door mover never runs. The +0.2s gate is deliberate so it swaps after the map's light threads re-read the vars (+0.1s) but before the auto-open notify (+0.3s), leaving the lights idling like an untouched wager match. Re-runs each round via `onStartGameType`/`map_restart`.

#### `gf_setupWagerZoneCompass( mapname )`
Binds the wager (zoomed) minimap compass for maps that support it. Resolves the material name via `gf_getWagerCompassMaterial( mapname )`; if that returns `""`, returns without changing the compass (the map keeps its own full compass). Otherwise applies it with `maps\mp\_compass::setupMiniMap( material )`.

#### `gf_getWagerCompassMaterial( mapname )`
Returns the wager compass material name for a whitelisted map, or `""` for everything else. Returns `"compass_map_" + mapname + "_wager"` only when `mapname` is one of the 14 maps whose wager compass image is resident during a Gunfight match: `mp_array`, `mp_cairo`, `mp_cosmodrome`, `mp_cracked`, `mp_crisis`, `mp_duga`, `mp_hanoi`, `mp_havoc`, `mp_mountain`, `mp_radiation`, `mp_russianbase`, `mp_villa`, `mp_silo`, `mp_berlinwall2`. All other maps return `""` so they keep their full compass instead of showing a blank — the First Strike/Escalation maps are deliberately excluded because their wager compass art lives in a wager-only zone that Gunfight (`xblive_wagermatch 0`) never loads.

#### `gf_applyCosmodromeWagerZone()`
Spawns the three custom collision helpers that shrink/shape the Cosmodrome small-map wager play space. Calls `gf_spawnWagerCollision` three times with fixed model/origin/angles: `collision_geo_mc_8x560x190` at `(-393, 396.5, -72)` angles `(0,270,0)`; `collision_geo_mc_4x52x190` at `(-358, 676.5, -74)` angles `(0,0,0)`; `collision_geo_mc_4x156x190` at `(-328.5, 758, -74)` angles `(0,270,0)`.

#### `gf_spawnWagerCollision( model, origin, angles )`
Thin helper that spawns one collision brush. Calls the native `spawncollision( model, "collider", origin, angles )` with the passed model/origin/angles and the fixed `"collider"` tag.