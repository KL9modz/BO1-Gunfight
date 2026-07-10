# mp_gunfight â€” Plutonium T5 (Black Ops 1 MP) Gunfight Mod
---
### TODO

**Bugs**
- "Pregame lobby" ends on its own at some point (should only end via load/min-players gate or admin start)
- Fast restart clears the bots
  FIXED 2026-07-08 (pending in-game verify): the lobby's `map_restart(false)` wipes `game[]` (so the
  once-per-match `game["gf_botInit"]` gate in `gf.gsc` re-fires) but does NOT stop running threads —
  so `_bot::init` re-threaded a SECOND set of managers over the surviving ones, while `level.bots`
  was wiped. `_bot::init` now fires `level notify("bot_reinit")` before re-threading and every
  persistent bot loop carries `level endon("bot_reinit")`, collapsing back to exactly one live set.
  The new reconciler also counts off `level.players` + `istestclient()` (never `level.bots`), so a
  wiped bookkeeping array can't make bots vanish. See the **Dynamic Bot Fill** section.
- Sometimes too many bots appear — make default fill 3v3
  FIXED 2026-07-08 (pending in-game verify): replaced the global `bots_manage_fill` headcount with
  `gf_fill_n` = PER-TEAM target N. `set gf_fill_n 3` => exactly 3v3, humans+bots, forever. The old
  `addBots()`/`teamBots()` pair could both over-add and fight each other; the single reconciler is
  overshoot-free (finite parked pool + one-add-in-flight). Set the default in `dedicated.cfg`.
- Bot bug: as bots connect one by one, they sometimes suicide — suspect they're self-balancing teams mid-connect while counts are momentarily uneven
  FIXED 2026-07-08 (pending in-game verify): root cause = `teamBots()` in `_bot.gsc` re-balancing
  bots with raw `[[level.allies/axis/spectator]]()` (stock `menuAllies`/`menuAxis`), which `suicide()`s
  the target when `sessionstate == "playing"`. During the connect/fill window every already-spawned bot
  is "playing" (frozen in prematch), so a 1.5s balance pass that fires while counts are momentarily
  uneven yanks one -> visible suicide. Enabled by `doNonDediBots()` (local "Basic Training") setting
  `bots_team custom` + `bots_team_force true`, which drives the two team-move branches. The existing
  `gf_roundActive` guard only blocked LIVE rounds, not prematch/connect. Fix = the same invariant the
  RCON bridge's `gf_applyTeamMove` already uses: **skip the move for any bot with `sessionstate ==
  "playing"`** (guard added at both move-selection sites). A not-yet-spawned (spectator/limbo) bot is
  still placeable, so custom-amount + autoassign-force assignment of freshly-connected bots still works;
  the engine's connect-time autoassign keeps teams balanced without teamBots having to suicide anyone.
  SUPERSEDED 2026-07-08: `teamBots()` is now RETIRED entirely (unthreaded) — the root cause is gone, not
  just guarded. Bot team placement is owned by the reconciler, which only ever switches bots that are
  parked/connecting (never a "playing" one) and only parks surplus bots BETWEEN rounds.
- Mod changes people's client settings
- Democlient round-cam lag
- Start music killed by ambient music
- Log thinks some bots are people (bot/human miscount in logs)
  FIXED 2026-07-08: root cause = the box-side `status` parsers split each player line on
  whitespace and assumed the NAME is a single token (`p[4]`) with the address at a fixed
  `p[6]`. A bot named "MCG Gordon" (space in the name) splits into TWO tokens, which (a) read
  the name as just "MCG" and (b) shift every trailing column right by one, so `p[6]` held the
  *lastmsg* value instead of `"unknown"` — so the bot check `guid=="0" && p[6]=="unknown"`
  failed and the bot counted as a human (the "MCG joined" false ntfy alert). Fix = read name +
  address END-anchored (address = 3rd-from-last token, name = everything between guid and
  lastmsg) and define bot = the address column is not a real `ip:port` (nor a listen `loopback`).
  This matches the already-hardened `status_service.ps1`. Applied to all three still-naive
  parsers: `tools/rcon/server.js::parseStatusText` (RCON panel), `tools/notify/join-notify.ps1`
  (the deployed GF-JoinNotify service) + `tools/notify/join-notify.js`. `status_service` /
  `conn_logger` (admin.json) were already safe via their own end-anchored ip:port check.
  Also fixes human players whose NAME contains a space (previously shown truncated to the 1st
  word). Deploy: `deploy.ps1 -Mod` ships the panel; the notify/status services are box-side
  (scp/restart the GF-JoinNotify task), not part of the mod mirror.
- Map size change (large/small mode) takes effect a round late
- Minimap compass not showing wager mode size for some DLC maps

**Bots**
- Rename "democlient"

**RCON / Admin panel**
- Gas/stun/flash intensity sliders
- Mantle/climb speed control
- Manage teams from RCON — combined ask: team switching, a "balance teams now" button, and allowing changing teams before countdown without forcing spectate
  MOSTLY DONE 2026-07-08: right-click move (allies/axis/spectator) for humans AND bots, "Balance teams
  now" (`balanceteams`), and pre-countdown moves apply live (the pre-prematch hold runs with
  `inPrematchPeriod` already true, so `gf_bridgeTeamSafeNow()` applies immediately, no spectate bounce).
  Moves now STICK because the `teamBots()` rebalance that undid them is retired. Remaining nuance: a
  LIVE human can't be moved without dying (engine-level — false `onDeadEvent` + nulled `self.class`), so
  mid-round it's next-round (normal click) or force-now/respawn (Shift+click). Bot moves are transient
  while `gf_fill_n > 0` (the reconciler owns bot placement); set `gf_fill_n 0` for manual bot control.
- Friendly Fire setting exists in 2 RCON spots and re-enables itself next round (dedup/fix)
  FIXED 2026-07-09 (panel redesign): ROOT CAUSE — the MATCH-tab FF toggle wrote `scr_gf_ff` +
  `scr_team_ff`, which NOTHING reads (dead dvars), so it was a no-op whose UI state lied; the
  real dvar is `scr_team_fftype` (stock tweakable, re-read only at round init → "re-enables/
  reverts next round" feel), and the engine also polls a per-gametype OVERRIDE dvar
  `scr_gf_team_fftype` every ~5s (`_serversettings::updateServerSettings` →
  `getTweakableValue`, override wins when non-empty). Fix = ONE canonical 4-state select
  (Off/On/Reflect/Shared) on DASHBOARD → GAMEPLAY that sets BOTH `scr_team_fftype` (base,
  persistence + non-gf modes) and `scr_gf_team_fftype` (live ≤5s in gf) — zero GSC changes.
  Set All / 💾 Save write both (a stale override would silently win over the base).
- PANEL REDESIGNED 2026-07-09 — split `index.html` into `index.html`+`app.css`+`app.js` (same
  look/feel); tabs are now **DASHBOARD** (run the live match: GUNFIGHT rules, deduped GAMEPLAY,
  BOTS incl. difficulty, PLAYER STATE, FUN & VISION, ADMIN) and **ADVANCED** (configure: MATCH
  START, MOVEMENT, GAME RULES, PLAYER, TEAMS, PERKS(+multipliers), GENERAL, ENGINE GAMEPLAY,
  BOT TUNING, HUD/CLIENT-LOCAL/VISUAL TWEAKS, MODIFIERS, DEBUG, other-gametype dvars); internal
  tab keys stay `match`/`srv`. **The floating right-hand rail (`#rail`, `positionRail()`) is
  RETIRED**: MATCH CONTROL (`#matchCtrl`, a `.block.sb-block` that keeps the `.btitle` collapse)
  docks in the SIDEBAR **beside** SERVER+SCOREBOARD — the sidebar top is a `.sb-top` flex row
  (`.sb-top-l` = SERVER+SCOREBOARD, `.sb-top-r` = MATCH CONTROL, paired buttons stacked via
  `.sb-top-r .two{grid-template-columns:1fr}`), visible on every tab. To fit side-by-side the
  sidebar default widened to **380** (`--sbw` fallback + `SB_DEF`) and `COL_MIN` dropped to
  **400** so a 1270-1280px half-screen still keeps 2 content columns. The behavior-pill
  LEGEND is a collapsed-by-default strip at the bottom of each settings tab
  (`buildLegendFooters()`/`toggleLegend()`, own `gf_legend` key — it can't ride the `.block`
  collapse list because `restoreCollapse()` only ever ADDS `collapsed`).
  Layout = EXPLICIT FLEX COLUMNS driven by `layoutColumns()` (app.js), NOT CSS multi-columns:
  multi-columns balance by height, so zooming / collapsing a block reshuffled which block sat in
  which column ("sections move"). Now each block is assigned to a column ONCE and only
  redistributed when the column COUNT changes. Count = `_wantCols()`: `COL_MIN`=400,
  `MAX_COLS`=3, `PANEL_CAP`=2100 (mirrors the `#p-*` max-width in app.css) => 3 cols on a 2560px
  display (the space the rail used to occupy), 2 cols at a 1270-1280px half-screen window, 1 col
  below that. Set `MAX_COLS=2` for a strict two-column layout. Columns live in a `.cols` row
  wrapper so the legend footer can sit beneath them; `.flow` wrappers stay as the JS render
  targets (`display:contents`) and `layoutColumns` re-parents the built blocks into `.pcol`.
  `.panel` is `overflow:hidden auto` — a bare `overflow-y:auto` also makes overflow-x `auto`,
  which is what produced the horizontal scrollbar on zoom-in. `layoutColumns`
  is guarded to `p-match`/`p-srv` only (MAPS/CONSOLE keep their own flow). Sidebar width
  (`--sbw`, default 320) and Activity-log height (`--alh`, default 220) are DRAG-RESIZABLE via
  `#sbDrag`/`#alDrag` (double-click resets; persisted in `gf_sbw`/`gf_alh`). All blocks
  collapsible (state persisted). Duplicates collapsed to ONE
  control each (FF, Max Team Size, Killstreaks, Headshots Only, Radar, Health Regen, Killcam) —
  killstreaks/headshots/radar are combined dvar+bridge switches (`togDvarBridge`: sticky dvar +
  live bridge in one toggle). Data rows now carry `data-dvar`/`data-also` (Set All / Save / search
  read attributes first, legacy onclick-regex kept for static rows). `GT_SECTIONS.gf` split into
  `GF_MATCH_VARS` (Dashboard) + `GF_START_VARS` (Advanced MATCH START); concat preserved for the
  sweep/search. Removed: legacy localStorage migrations, dead `set gf_debug` console chips, the
  `reorderSrvSections` IIFE (now declared `SRV_ORDER`). Added `?tab=` deep-link (composes with
  `?profile=`/`?autoconnect`). server.js untouched — transport/ack/secrets/profiles + `/api/tick`
  `/api/status` contracts unchanged (VPS-tunnel + listen-server flows unaffected).

**Gameplay / Spawns**
- Allow players to spawn in late to a round if teams are uneven
- Preserve players from lobby (don't re-shuffle/reset on transition)
  DONE 2026-07-08 (pending in-game verify): `gf_writeTeamPlan()` snapshots each human's `getGuid()`->team
  into the `gf_teamplan` DVAR just before the lobby's `map_restart(false)` (dvars are the only state that
  survives it), and `gf_applyTeamPlan()` re-seats them by GUID during the post-restart prematch. Bots are
  re-padded by `gf_fill_n`. NOTE the load-bearing detail: `gf_applyTeamPlan` must `wait` BEFORE its first
  roster check — it is threaded from the tail of `onStartGameType`, where `_spawnlogic::init` has already
  emptied `level.players`, so a synchronous first pass would see zero players, think it was done, and drop
  the already-consumed plan.
- Lobby ready up or team picking?
- Widen the spawns
- Adjust spawns & flags generally
- Berlin Wall: move flag away from the building
- Add min-players-to-start option that includes bots in the count
- Hockey gamemode on Arena (map-specific mode idea)
- Lobby fly cam controls
- Ship weapon files: ADS FOV / move speed tuning
- shorten round time. raise capture time 3.5s
- hardened on sniper classes

**HUD / Visual**
- Persistent clean "gunfight.us" text on HUD
- General visual improvements (tracked against the feature list)

**Site / Branding**
- Fable-style website design pass
- Server advertisements
- Add credit to Plutonium/bots/etc.
- Show which features are supported on every map
- Consider renaming gametype display to "Gunfight" instead of "GF"

**Setup guide additions**
- Recommend `cg_fov 65`, `cg_fovScale 1.4`

**Ideas / Future**
- BO1 server "role" (Discord role tied to server activity?)
- IW5/MW3 face-off Gunfight — reference: mwgunfight.com


fast restart sometimes makes the prematch timer look like its running at 1fps
the prematch countdown is in slow motion
  DIAGNOSED 2026-07-04 (VPS): NOT the sv_fps-30 skew — verified NO `sv_fps` is set
  anywhere on the box (dedicated.cfg, start_mp_server.bat, any exec'd cfg), so the VPS
  runs the DEFAULT sv_fps 20 (the "VPS runs sv_fps 30 → fast countdown" claim in the
  30-FPS TODO item below is STALE/never-deployed). Root cause = a TRANSIENT server-frame
  hitch during the restart burst: the stock prematch countdown (matchStartTimer,
  [_globallogic.gsc:396-435]) is the ONE visible timer still riding a wait(1.0)-driven
  hudelem, and `wait` counts server GAME time (advances 1/sv_fps per server frame). When
  the box drops a few frames per real second, game time dilates and the whole prematch
  (number + freeze + gf_nativePrematchTicker beep) runs in real slow-mo / redraws at
  "1fps", then snaps normal at prematch_over. Live play is immune because every live clock
  we own (round/OT/roster/load gates) is gettime()-anchored (wall clock). "Random on
  restarts" = the deterministic per-restart work (player connects on rotation + bridge
  connect-sweep + the round-1 bot FILL burst) occasionally colliding with Contabo
  shared-CPU contention. BOTS DO RUN ON THE VPS (corrected 2026-07-04 — this Pluto build
  spawns test clients on dedicated w/o the exe patch docs/DEV.md assumed; enabled at
  RUNTIME via the RCON panel — bots_manage_fill/+Add Bot over rcon — which is why they're
  absent from dedicated.cfg). So the round-1 bot fill lands in the wait-driven prematch and
  IS a contributor: addBots() drains the whole queued deficit back-to-back at 0.25s/bot
  (12 bots = ~3s of connect+loadout+HUD-reveal in the countdown window). MITIGATION APPLIED
  2026-07-04: widened the per-bot drain to 0.5s in _bot.gsc addBots() to halve the peak
  add-rate (safe now that bots are excluded from the roster + load gates, so the fill no
  longer has to beat prematch_over). REAL FIX = own the prematch countdown with gettime()
  (the "fully custom timers"
  test-branch item below); that makes a hitch degrade to a 1-frame stutter (number holds,
  then jumps) instead of slow-mo, AND kills the sv_fps-30 fast-countdown deal-breaker if
  30-fps perf is ever wanted. Interim: shave box-side contention during restart. Verify
  in-game on the LOCAL dedi with `set sv_fps 10` to force-reproduce the dilation.
  INSTRUMENTED 2026-07-10 (measure before the risky prematch rewrite): added a dev-only
  frame-hitch monitor `gf_hitchMonitor()` (+ `gf_hitchPhase/Humans/Bots`) in `_gf_debug.gsc`,
  launched once via `level thread gf_hitchMonitor()` in `gf.gsc` onStartGameType and kept to a
  single live sampler across rounds/map_restart by a new `gf_hitch_reinit` notify (threads
  survive map_restart, so a bare re-thread would stack). Each 0.5s it measures how far
  `gettime()` advanced across a `wait 0.5` and, when the window ran slow, logs
  `GF_HITCH: <real>ms vs 500ms (+N% slow) phase=<prematch|live|overtime|roundend|restart>
  humans=H bots=B` to logs\games_mp.log. Tunables (dvars, no rebuild): `gf_hitch_pct` (log
  threshold %, default 25) and `gf_hitch_debug 1` (log EVERY sample). Built on ONLY
  `gettime()`+`wait()` → zero compile risk, AND self-validating about the load-bearing claim
  above that gettime() is WALL-clock: if a KNOWN slow-mo (run with `gf_hitch_debug 1`) logs
  +N% dilation, gettime is wall-clock and we have the magnitude+phase; if it logs ~+0%
  throughout the slow-mo, gettime is GAME-time (dilates in lockstep with `wait`, so the
  "live clocks are immune" line above is only true of the sv_fps-scaling quirk, NOT a real
  CPU stall) and the reference must move to `getRealTime` — confirm that need before risking
  that builtin (unknown-function = gametype fails to load; T5 stock scripts don't use it, so
  it's unconfirmed for this engine). NOTE the monitor only MEASURES the stall; owning the
  countdown with gettime() (the REAL FIX above) makes the number/beep honest but does NOT stop
  the movement/animation slow-mo — that needs less restart-burst CPU (or more box CPU).
  GSC-only, dev-wiring strip-wrapped → no public leak, no mod.ff rebuild; ships to the VPS via
  `deploy.ps1 -Mod` (full main mirror). Verify: LOCAL dedi first, `set gf_hitch_debug 1`, watch
  a normal round (baseline should read ~+0% ≈ real 500ms → confirms gettime=wall + monitor
  works), then reproduce the slow-mo and read the GF_HITCH lines.
  DONE 2026-07-04: went fully MANUAL. The SYSTEM/boot GF-GameServer task ran the server in
  Session 0 (invisible desktop) - that's why there was no console. Disabled that task
  (reversible) and added a Desktop shortcut "Gunfight Launch" -> C:\gameserver\T5\gf_launch.bat:
  kills stale plutonium-bootstrapper + node, bounces the GF-RconPanel task, then launches the
  game server as a VISIBLE console in that window. No auto-logon / no stored credential (user's
  choice); server stays down after a reboot until you log in and double-click the icon. Revert
  with `schtasks /change /tn GF-GameServer /enable`. See memory [[vps-server-provisioned]].
- Mid-round bot backfill (DESIGNED 2026-07-04, ~25 lines, dev/VPS-only — not built): let a bot
  added after round start spawn INTO the live round instead of waiting for next round. Feasible
  because blocked clients never retry (stock `spawnClient` one-shots into spectate on a closed
  `maySpawn`), so a targeted re-spawn can't leak to others. Impl: in `_bot.gsc` `addBots` path,
  once the bot is teamed — guard round live (+ not `gf_roundEnding`), `!level.inOvertime`, and
  bot's team has `>=1` alive (one-life integrity: reinforce, never resurrect a wiped team) —
  flip `level.inGracePeriod = true`, `[[level.spawnClient]]` the bot, flip back next frame, then
  `level thread updateTeamStatus()` (same mirror `gf_closeGraceEarly` does — closes the one race:
  grace suppresses wipe detection for that frame). Already handled elsewhere: late-spawn facing
  uses curated points (2026-07-01 fix), bots excluded from roster gate, OT double-blocked inside
  `maySpawn`. Lives in dev-only bot files (stripped from public builds). TEST: add bots mid-round
  → they drop in; team wipe during the flick frame → round still ends; during OT → blocked.
- On-brand live card (Discord)
A card in the site's own orange 'Evolved Dark' theme showing the live online count (96 now) + a 'Join the Discord'
button. Fetches widget.json client-side. Matches the site perfectly. CSP cost: add script-src 'self' 'unsafe-inline' +
connect-src https://discord.com (same script/connect relaxation status.html already needs). No avatars - img-src
untouched.

- support 30 FPS Server tick rate (sv_fps 30) — investigated 2026-07-02. NOTE 2026-07-04: the
  VPS is NOT actually running sv_fps 30 — verified no `sv_fps` set on the box; it runs default 20.
  This item is planning only; wherever it says "the VPS countdown runs 1.5x fast", that's the
  PREDICTED behavior if 30 were set, not the current live state. WHY IT'S NOT JUST A DVAR:
  T5/CoD scales GSC `wait` by 20/sv_fps, so at sv_fps 30 every wait-driven timer runs ~1.5x fast
  (0.667x real duration). Our round/OT clocks are IMMUNE (gettime()-delta anchored + setGameEndTime,
  self-correcting) and so are the pre-prematch load/min-players gate + gf_closeGraceEarly (gettime deadlines). The ONE
  visible casualty is the STOCK prematch countdown: matchStartTimer() ([_globallogic.gsc:396-435])
  decrements a local hudelem on `wait(1.0)`, and its number + the freeze/hold + prematch_over are all
  welded to level.prematchPeriod (can't peel off just the number — direct `thread` call, unreachable
  local element). So the visible count ticks ~1.5x fast on the VPS (also the gf_nativePrematchTicker
  beep). User verdict: fast-appearing timer is a DEAL BREAKER; wants to keep the sv_fps 30 perf
  (smoother snapshots/hit-reg). FIX (planned, moderate work + regression risk in the prematch flow):
  set level.prematchPeriod ~= 0 so the engine draws NO number, then OWN the frozen-countdown phase in
  gf_tryActivateRound using STOCK primitives — freeze_player_controls() for the freeze (stock spawn
  only auto-freezes while inPrematchPeriod, [_globallogic_spawn.gsc:191-193], which we'd be
  shortening, so we freeze late/gate spawners ourselves), leaderDialog() for intro VO, gettime() for
  an honest countdown number + per-second beep — positioned where the pre-prematch gate already holds, so
  the two compose into one frozen window. gettime itself is native-friendly (stock waveSpawnTimer
  [_globallogic.gsc:448-456] uses getTime() deltas too); caveats: ignores pauseTimer (raw wall clock
  — that's the immunity), keeps counting across map_restart (baseline per-window). New surface we'd
  own: intro freeze, intro vision blend (minor cosmetic), VO timing. TEST: add `set sv_fps "30"` to
  the LOCAL dedi cfg to reproduce the VPS skew exactly (listen server is always 20 → looked normal).
  Alt if native-purity wins: revert VPS to sv_fps 20 (zero custom, loses the perf). Client-side
  cl_maxpackets 100 already applied (helps independently); snaps 30 is inert until sv_fps >= 30.
- the mod hangs on first download — ROOT CAUSE FOUND 2026-07-01 (client-engine-side, can't be fully
  fixed server-side): after the first-time FastDL download the Plutonium client does an in-place
  engine rebuild with NO loading UI — unloads ALL fastfiles, DESTROYS + recreates the D3D window
  (that blank window IS the black screen), reloads ~180MB of zones + mod.ff, re-execs configs, and
  re-syncs Demonware stats. Once per client: later joins take the fast "[mod dl] mod already
  downloaded" path (proven in local console_mp.log). Mitigations DONE: (1) mod.ff now ships an
  empty ui_mp/mod.txt stub — the engine hard-looks it up on every mod load and BLOCKED a measured
  4.6s when missing ("Waited 4597 msec for missing asset"); (2) site + GETTING_STARTED now set the
  expectation (black screen = normal, wait it out, restart as fallback). REMAINING: (a) verify
  in-game that the new mod.ff with the empty mod.txt doesn't break the gametype UI (menufile
  pitfall class) BEFORE deploying; (b) on the VPS check console_mp.log says "found 1 files required
  for mod download" — the deployed folder mirrors main and .csv/.gsc are downloadable extensions,
  so if it advertises >1 file while IIS hosts only mod.ff, first joiners grind 404 retries;
  (c) staff-endorsed unstick trick if a player reports a hard hang: type vid_restart in the
  Plutonium bootstrapper console window.
  FIX APPLIED 2026-07-05 (pending mod-less-client confirm). "(b)" verified: `found 1 files required
  for mod download!` (mod.ff, 17KB). CORRECTED SYMPTOM (user): the FastDL **download window reaches
  100% then STICKS**; the 30-60s engine rebuild happens only on the **2nd, manual reconnect** — the
  download completes but the client never advances on attempt 1 (download→load HANDOFF failure, NOT
  a timeout drop; the rebuild doesn't even start on attempt 1, so the first sv_timeout theory was
  wrong). sv_timeout was raised to 240 then **fully REVERTED** at user request ("no sv_timeout edit")
  — live 15 + cfg from `dedicated.cfg.bak-svtimeout` + tracked example all back to 15. Ruled out:
  framing clean (mod.ff HTTPS 200, correct Content-Length 17344, Accept-Ranges/206, no gzip/chunk).
  ROOT CAUSE (high-confidence): FastDL is IIS over **HTTPS + keep-alive**; the client gets all bytes
  (100%) but waits for **connection-close/EOF** that keep-alive withholds → hangs at 100% (reconnect
  finds mod.ff on disk → skips download → loads → joins). FIX: added
  `<location path="mods"><system.webServer><httpProtocol allowKeepAlive="false"/></system.webServer></location>`
  to the VPS `C:\inetpub\wwwroot\web.config` (backup `web.config.bak-fastdl`). Verified at HTTP layer:
  mod.ff now returns `Connection: close` + IIS closes the socket; homepage still 200; scoped to /mods
  so site security untouched. Live (IIS applies web.config on the fly) — NO restart, NO new port, NO
  Contabo change. NEXT: a fresh mod-less client must confirm one-click download→join. If still hung
  (cause isn't connection-close): plan B = plain-HTTP HFS on its own port (`sv_wwwBaseURL
  http://gunfight.us:<port>/`, needs restart + Contabo port), or grab the CLIENT console_mp.log to
  pinpoint. Revert this fix via `web.config.bak-fastdl`. See memory [[svtimeout-connect-twice-firstjoin]]. (Aside found the same pass: the FastDL web root
  `C:\inetpub\wwwroot\mods\mp_gunfight` also holds stale cruft — console_mp.log(.000), logs\,
  maps\, mod.csv — from an old full-mirror; only mod.ff needs to be there. NOT an active leak:
  verified `/mods/mp_gunfight/console_mp.log` returns 404 (web.config denies .log) while mod.ff
  returns 200. Low-urgency hygiene cleanup.)
- Custom round-timer HUD: the stock game timer turns orange + shows tenths in the final 30s, which
  is hardcoded in the engine CG layer (NOT GSC-tunable — no dvar/property/hook; `setGameEndTime`
  only feeds it the end time). To trigger that at 10s instead, draw our OWN top-center timer fed by
  the existing `gf_roundRemaining` clock (MM:SS white normally, switch to S.T + orange at <=10s),
  hide the engine timer (`setGameEndTime 0`), and route the OT countdown through the same element
  so round + OT share one style. Moderate work, not a threshold tweak.
  HYBRID PLAN (preferred — keeps the native engine-driven tick, only owns the final-seconds phase):
  What we DON'T lose by going custom: the native time-out AUDIO is already ours — `pauseTimer()`
  already gates off the stock `timeLimitClock` loop, so the announcer VO / `TIME_OUT` music /
  30s+12s+1-min beeps are already suppressed and replaced by our `timesup` VO (15s) + final-10s
  beeps. Only the VISIBLE number is still the engine element (fed by `setGameEndTime`). So the cost
  of going custom is purely visual: engine-driven rendering smoothness, the exact native font/glow/
  position, and automatic spectator/killcam visibility (re-own via `archived`/`hidewheninmenu`).
  DESIGN — two-phase, one visible number at a time:
  (1) NORMAL phase (remaining > threshold, default 10s): keep an engine-driven element showing
      `MM:SS` white — either leave the stock `setGameEndTime` number as-is, or mirror it onto our
      own hudelem via `setTimerDown`/`setTimerUp` (engine ticks it, zero polling, no stutter).
      `setTimer*` only renders `MM:SS`, NOT tenths — that's why it's the normal phase only.
  (2) FINAL phase (remaining <= threshold): hide the engine number (`setGameEndTime 0`), reveal our
      OWN element hand-driven from `gf_roundRemaining` showing `S.T` (seconds.tenths) in orange,
      updated on a fast loop (the micro-stutter is invisible/acceptable for a 10s burst).
  Route the OT countdown through the SAME final-phase element so round + OT share one style.
  Prefer the MENU layer (`hud_gf_health.menu` + `ui_gf_*` dvars) to match the rest of the mod HUD
  and stay off the ~17 per-client render cap; menu STRUCTURE change needs a `mod.ff` rebuild
  (`tools/build_ff.ps1`), positions/thresholds stay GSC-tunable. Set `hidewheninmenu`/spectator
  visibility so killcam + spectators still see it (the one native freebie we'd be re-owning).
  PLANNED TEST BRANCH — "fully custom timers + server tick-rate (sv_fps) offsets". A throwaway
  branch (keeps the prematch-flow regression risk off main) that combines this hybrid timer with
  the sv_fps 30 item at the top of the TODO into one experiment: (a) own EVERY visible countdown
  with gettime()-anchored logic — this round timer PLUS the stock prematch/intro countdown — so no
  visible timer rides a wait-scaled hudelem; (b) run sv_fps 30 for the snapshot/hit-reg perf and
  compensate the 20/sv_fps `wait`-scaling wherever a wait still drives timing (the "offset"). Goal:
  keep the sv_fps 30 perf WITHOUT the ~1.5x-fast prematch countdown (the current deal-breaker).

DONE:
- "Slow loaders miss the prematch intro on map rotation" (+ hidden worse symptom: they could
  SPECTATE all of round 1) — FIXED 2026-07-03 (pending in-game verify): pre-prematch LOAD GATE.
  Root cause: rotation-carried clients fire `Callback_PlayerConnect` while STILL on the loading
  screen (statusicon `hud_status_connecting` until the engine's `"begin"`; only then do they enter
  `level.players`/spawn), but nothing waits for them — stock `startGame()`'s `waitForPlayers()` is
  an EMPTY STUB in T5 (matchStartTimer's "Waiting for teams..." phase exists but is never seen), so
  the countdown starts on wall clock. Worse: loading clients are invisible to the roster poll, so
  `gf_closeGraceEarly` shut `maySpawn`'s first-spawn window ~3s after prematch_over and a >~18s
  loader spectated the whole first round (the 2026-07-01 early-close TIGHTENED stock's 15s window
  for them). Fix (`gf_armLoadGate` / `gf_loadGateTracker` / `gf_waitForLoadingClients` in
  `_gf_rounds.gsc`): collect clients via the stock level `"connecting"` notify (armed early in
  `onStartGameType`, before the slice can yield), then HOLD as the LAST statement of
  `onStartGameType` — the engine threads `startGame()` the moment it returns — until no tracked
  human still has the connecting statusicon (race-free vs. listening for `"begin"`). Players who
  load during the hold spawn frozen (inPrematchPeriod already true) with their own intro VO/splash;
  release plays the FULL stock countdown for everyone. Bounded by `scr_gf_load_wait` (default 30s,
  0=off, 3s arrival floor, 0-120 clamp); first round of a match only; bots excluded via
  `istestclient()`; FastDL first-timers (30-60s+ engine rebuild) deliberately not absorbed.
  Mid-hold map_restart safe: threads survive restarts, so the gate is generation-stamped
  (`level.gf_loadGateGen` = gettime) + tracker retired via `gf_load_gate_reset` notify.
  `gf_nativePrematchTicker` now starts AFTER the gate (it loops on inPrematchPeriod — already true
  during the hold — and would have beeped through it). Stock precedent for waiting inside
  `Callback_StartGameType`: the `scr_writeconfigstrings` path `wait(1)`s in the same function.
  IN-GAME VERIFY: (a) two-client rotation — slow client sees loading, fast client sees "Waiting
  for teams... N/M", countdown starts only when both in; (b) `GF_LOADGATE:` line in games_mp.log
  with sane hold ms; (c) solo + bots: gate releases at the 3s floor (bots never counted).
  FOLLOW-UP 2026-07-04 — straggler grace extension (`scr_gf_load_grace`, default 20s): if the load
  gate hits its ceiling with a client STILL loading (the FastDL first-timer case the gate
  deliberately doesn't absorb), keep the grace period open up to `scr_gf_load_grace` seconds past
  prematch_over so that client can still take its round-1 first spawn instead of spectating. Two
  parts: `gf_waitForLoadingClients` raises `level.gracePeriod` at release (before onStartGameType
  returns, so the stock `gracePeriod()` backstop honours it), and `gf_closeGraceEarly` holds (past
  its 3s floor) while `gf_anyTrackedClientLoading()` is true, bounded by that ceiling. Tradeoff: a
  round-1 wipe can't end the round until grace closes. `0` disables (straggler spectates). VERIFY:
  join a 3rd client that loads slowly (or throttle FastDL) so it lands AFTER the countdown — it
  should still spawn into the live round 1, and grace should close the moment it spawns.
  FOLLOW-UP 2026-07-04 — GATE CONSOLIDATION (user: "min-players after prematch is too late"): the
  old post-prematch `gf_waitForMinPlayers` (freeze + damage-void warmup) and the `gf_allTeamedPlayersSpawned`
  roster wait (`scr_gf_roster_wait`) are DELETED. Min-players is now a second release condition on the
  SAME pre-prematch hold as the load gate (`gf_waitForLoadingClients` releases when: all tracked clients
  loaded AND >= scr_gf_min_players humans present, each bounded). Moving it in front of prematch means
  nobody has spawned during the hold, so the freeze + `level.gf_waitingForPlayers` damage-void are gone
  (also removed the fresh-spawn freeze in `gf_onSpawned` and the void in `gf_onPlayerDamage`). Net: 5
  helper funcs + 1 dvar retired, and the intro never plays for a match that then stalls waiting for
  people. Roster wait dropped as redundant — loaded-before-prematch implies spawned-by-prematch_over.
  Panel: swapped the `scr_gf_roster_wait` control for `scr_gf_load_wait`/`scr_gf_load_grace`, fixed the
  min-players tip. gf_armLoadGate now arms when EITHER load OR min-players is active.
  RCON PANEL RESHAPE 2026-07-04 (user: "make rcon control simple", "reshape rcon windows"): the flat
  gf settings list (GT_SECTIONS.gf) is now grouped into fire-order sub-sections — **Match** / **Match
  Start** / **Spawns & Round Time** / **Overtime** — so the 5 match-start knobs (Min Players, Load Wait,
  Prematch, Preround, Load Grace[adv]) sit together in the order they act instead of scattered. Done via
  an optional `grp:'Label'` on the first var of each group + a header emit in `srvBlock` (purely additive:
  every other consumer still sees normal entries with `.n`, so no read/set path can break; `.sgroup` CSS
  added). Also FIXED the misleading duplicate: the SERVER tab's `party_minplayers` was labeled "Min
  Players to Start" with a tip claiming it gates the match — relabeled "Lobby Min Players (pregame)" +
  tip corrected to say it does NOT affect gf (points to scr_gf_min_players). Prematch/Preround labels
  kept (user: "the names prematch and preround are fine").
- "Match starts before all players spawned" + "bot fill issues" + "bots die on spawn" — FIXED
  2026-07-01 (pending in-game verify), one root cause: nothing ever waited for the roster.
  (1) `gf_tryActivateRound` now polls after `prematch_over` until every teamed player has
  `hasSpawned` (bounded 8s), THEN closes grace early via `gf_closeGraceEarly` (3s floor after
  prematch_over — the join slack team-select idlers had under the old grace=3, they're invisible
  to the poll; + stock-mirrored `updateTeamStatus` pass so a during-wait wipe is noticed) and
  starts the round clock; `pauseTimer()` + the grenade-dud disable now happen BEFORE the hold
  (verifier catch: the unpaused stock `timeLimitClock` starts inside the 40-60s
  `match_ending_soon` band on a 45s round → premature last-round winning/losing VO; and pausing
  freezes `getTimePassed()` → duds), with `setGameEndTime(0)` hiding the native clock during a
  real hold. `gf_updateAutoTeamMode()` moved after the poll (was captured 0.2s after the FIRST
  spawn → undercounted bot fill, poisoned next round's small/large mode). `level.gracePeriod`
  restored 3 -> 15 (stock) as the ceiling — the "3" was justified by a `!gf_roundActive` damage
  gate that NEVER EXISTED. (2) Bot fill now beats the prematch: `bot_wait_for_host` skips the 10s
  host-wait on dedis (no host ever exists → pure wasted prematch), and `addBots` batches the whole
  fill deficit per pass instead of 1 bot/1.7s. (3) `gf_getCustomSpawnPoint` gained the stock
  `positionWouldTelefrag` scan — the bare round-robin cursor could wrap onto point 0 and telefrag
  the round's first spawner standing frozen in prematch.
- Spawn facing wrong direction — FIXED 2026-07-01 (pending in-game verify): small mode now
  short-circuits `onSpawnPlayerUnified` -> `onSpawnPlayer` (gf.gsc), so late/async spawns (bot fill,
  late joiners, 60s forceSpawn) always use curated fight-facing points instead of falling through to
  the stock scored `mp_tdm_spawn` pool once `useStartSpawns` flips false (same exemption stock SD
  gets in `_spawning`). BONUS fix found during verification: the curated-spawn branch now sets
  `self.lastSpawnTime`/`self.lastSpawnPoint` — stock `_globallogic_player.gsc:783` does UNGUARDED
  arithmetic on them (grenade spawn-protection), and undefined aborted the damage callback, silently
  VOIDING grenade-classed damage against curated-spawned players all round.
- "unkown command cd" — resolved 2026-07-01: never the mod (no stufftext/sendServerCommand anywhere);
  stray console paste client-side. The related cfg `;`-inside-comment parse errors in dedicated.cfg
  were fixed separately on the box.
- Server player limit + team-size caps set: `sv_maxclients 14` (launch bat) = 12 playing + 2
  spectator headroom; `scr_team_maxsize 6` (up to 6v6, overflow -> spectator) in `dedicated.cfg`.
  Spatial mode flips small->large by the LARGER team's roster, HARD-WIRED to the health-panel
  skull cap (`gf_hudSkullCap()` = 4): `<=4v4` small + skulls, any team of `5+` large + readout —
  the spawn mode and the panel's skulls->`alive/total` readout share one switch point.
  `gf_autoLargeFromCounts()` keys off the larger team (2v6 -> large). (2026-07-03 — replaced the
  old TOTAL-count rule; the `scr_gf_largemode_minplayers` dvar is now RETIRED/inert — a tunable
  spawn threshold could only ever DEcouple it from the fixed menu skull cap, and a stale total
  value under the reinterpreted meaning was a live footgun. Force a mode with
  `scr_gf_teamspawnmode large|small`.)
- 30s warning replaced by a mod-owned live-round clock (`gf_startRoundClock` etc. in
  `_gf_rounds.gsc`): native `timeLimitClock` is silenced via `pauseTimer()`, so the stock
  time-out sequence (announcer + TIME_OUT music + 30s beeps + the 1-min/12s client cues) no
  longer fires. We drive the HUD via `setGameEndTime` and play our own warning: `timesup` VO at
  15s remaining (no music), countdown beeps in the final 10s only. Verify the VO wording in-game.


- Organize repo — DONE:
`release` branch (GitHub default) + Release zip now carry the SAME minimal content (mod.ff + gameplay GSC + README), via tools/package_release.ps1 (see "Release & Distribution")
Dev files (_bot, _gf_debug, _gf_bridge, bots/, tools/) and in-file dev wiring (`// #strip-begin ... // #strip-end`) are stripped from public outputs; all still present on `main`

- SECURITY (do this): rotate the RCON password on the VPS + dedicated.cfg. The old hardcoded value leaked via public git history; the gf.gsc dvar block is now strip-wrapped (dev-only) but `main` is still public if the GitHub repo is public — prefer dedicated.cfg as the sole owner.

Fix ADS: `exec autoexec`
---

## Dedicated Server Setup

**Launch script:** `C:\Users\klaze\AppData\Local\Plutonium\storage\t5\T5ServerConfig-master\!start_mp_server.bat`
**Config:** `C:\Users\klaze\AppData\Local\Plutonium\storage\t5\dedicated.cfg`
**Game files:** `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops\`
**Mod files:** `C:\Users\klaze\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight\`

**To start:** run `!start_mp_server.bat` (auto-restarts on crash).
**To connect locally:** `connect 127.0.0.1:28960` in the Plutonium client console.

**Deviation from official docs** â€” The [Plutonium T5 server docs](https://plutonium.pw/docs/server/t5/setting-up-a-server/) say to place the bat files inside the game folder so that `set gamepath=%cd%` resolves correctly. Our bat lives in `T5ServerConfig-master` instead; we work around this by hardcoding `set gamepath=S:\SteamLibrary\steamapps\common\Call of Duty Black Ops` in the bat. The server works as-is â€” this note exists so the deviation is understood if the bat is ever moved or reset.

**Known cfg quirks:**
- `set scr_xpscale "1"` in `dedicated.cfg` is read-only on a dedicated server â€” harmless error, ignore it.
- `party_minplayers` must be `"1"` for solo testing; set back to `"2"` for a public server.

---

**Core Rules**
- One life per round, no respawns 
- No killstreaks, no health regen, no weapon drops â€” `level.killstreaksenabled = 0`, `level.healthRegenDisabled = true`
- 6-round win limit.
  - `level.roundWinLimit = 6` â€” belt-and-suspenders; `hitRoundWinLimit()` reads this level var directly
- Round wins tracked in `game["roundswon"]["allies"/"axis"]`; scoreboard accumulates correctly
- HP comparison on timer expiry 
- Draw rounds don't count toward win limit 

**Round System**
- SD-style round cycling, intermission, spawns

**Loadout System**
- Shared random loadout â€” all players get same primary/secondary/equipment each round
- Expanded loadout pool; shuffle-without-repeat, no back-to-back repeat
- Class select suppression â€” `scr_disable_cac=1`

**HUD**
- Loadout icon slide-in
- Perk display notification 
- HUD recreation per spawn 


---

## Team-Size Mode (Large vs Small)

Gunfight runs two spatial modes depending on the larger team's roster size, selected by
`scr_<gametype>_teamspawnmode` = `auto` (default) | `large` | `small`. Resolved every round
in `onStartGameType` -> `gf_resolveTeamMode()` (`_gf_rounds.gsc`); the result lives in
`level.gf_largeMode` (wiped + re-derived each `map_restart`).

- **small** (auto when every team has `<=4` players, i.e. `<=4v4`): curated, clustered gunfight spawns from `_gf_locations.gsc`
  (fall back to `mp_wager_spawn`, then `mp_tdm_spawn`). The baked wager blockers
  (`gun/oic/hlnd/shrp`) are KEPT in the `_gameobjects` allow-list to shrink the play space, the
  wager compass material is applied, and overtime uses the curated OT flag spot.
- **large** (auto when either team has `5+` players): full-map `mp_tdm_spawn` pool. Wager blockers are
  OMITTED so `_gameobjects::main` deletes them and the whole map opens up; overtime uses the
  native Domination B flag (`dom` is always kept in the allow-list so that flag survives).

The `<=4` / `5+` split is the health-panel skull cap (`gf_hudSkullCap()` = 4, mirroring the
menu's `cnt > 4` gate): auto-mode goes large exactly when a team exceeds what the panel can draw
as skulls, so the large-map spawns and the panel's `alive/total` readout share one switch point.
`gf_autoLargeFromCounts()` keys off the LARGER team (not the total) so lopsided rosters stay
correct (e.g. 2v6 -> large, since the 6-man team needs the readout). The split is **hard-wired**
to the skull cap: the menu's skull->readout gate is a fixed, rebuild-gated constant, so a tunable
spawn threshold could only DEcouple the two — the old `scr_gf_largemode_minplayers` dvar is
retired (no longer read; any stale cfg value is inert). To pin the spatial mode use
`scr_<gametype>_teamspawnmode` = `large` | `small`.

> **Timing caveat — same threshold, not the same clock.** Spawn mode is decided once per round
> and applied the NEXT round (persisted in `game["gf_autoLargeMode"]`, snapshot at round
> activation), while the HUD readout is LIVE. So on a roster change that crosses a team 4↔5 (a
> mid-round join, bot backfill, or **round 1 of a bot-filled match** — bots connect after
> `onStartGameType`), the readout can appear one round before the spawns switch to match. It
> self-corrects the following round. This is inherent to the snapshot design (a live count is
> unreliable in `onStartGameType`), not the coupling; the readout is always the correct live count.

`auto` can't trust a live roster count inside `onStartGameType` (bots/late joiners connect
after it — `_bot::init()` is threaded at its end), so it reads `game["gf_autoLargeMode"]`,
captured at round activation by `gf_updateAutoTeamMode()` once everyone has spawned and
persisted across `map_restart` in `game[]`. The live count is only a first-setup fallback.

Each mode reads its OWN copy of the tunable dvars (round length, overtime limit, capture
time) via a `_large` suffix, so flipping modes never clobbers the other mode's value.

---

## Dynamic Bot Fill (NvN) + Team Management

Added 2026-07-08. **One reconciler** (`gf_reconcilerInit` and friends in `_bot.gsc`) is the single
authority over how many bots exist and which team each is on. It **replaces** BotWarfare's two
competing loops — `addBots()` (a global bot headcount) and `teamBots()` (a team rebalance) — which
fought each other, undid manual RCON team moves, and whose mid-connect `suicide()` was the
long-standing "bots suicide as they connect" bug. Both are now unthreaded dead code.

### The invariant
`gf_fill_n` = **per-team target N** (`3` -> 3v3). Each team is padded to exactly **N playing clients
(humans + bots)**, and **bots absorb all the variance**:
- A **human joining team T displaces a bot on T** (event-driven off the `"connecting"` notify, plus a
  3s safety poll). A human leaving re-pads that side.
- **Humans are NEVER auto-moved.** If humans on a side exceed N, that side's bots go to 0 and the side
  simply stays big; the other side still fills to N. Human placement is yours (RCON / autoassign).
- `gf_fill_n 0` = **reconciler inert**. This is the mode in which the panel's manual per-team bot
  add / kick / move actually **sticks**. With fill on, bot *counts* stick but bot *identity* doesn't —
  you cannot have "both sides = N" *and* "this specific bot pinned to the overfull side".

### Why it can't overshoot or churn
- **Parked pool.** A displaced/surplus bot is moved to **spectator** ("parked") rather than kicked, and
  redeployed instantly when a slot reopens. Deploy drains the parked pool (a single index shared across
  both teams, so one bot is never assigned twice) before adding anything new.
- **One add in flight.** A new bot is added only when nothing is mid-connect. The bot carries
  `.gf_fillPending = <target team>` for its whole trip and is counted **in-flight** (neither parked nor
  on a team) until `gf_botDeployWhenReady` lands it. This is load-bearing: the stock connect path parks
  a fresh bot in `spectator` and `teamWatch` may autoassign it to the *wrong* team before the watcher
  lands it — without the marker, the parked pool would steal it or the deficit would be miscounted.
  On landing, the marker clears and a pass is requested immediately, so a cold fill converges at
  ~one bot per driver tick (0.5s) instead of crawling on the 3s backstop.
- **Serialized passes.** `gf_reconcilerDriver` runs at most one `gf_reconcilePass()` per 0.5s tick,
  coalescing requests via `level.gf_reconcileDirty`. A pass never yields (all switches/adds are
  threaded), so passes are atomic; the tick gap lets a pass's async switches land before the next count.
- **Reserve cap = live human count.** Leftover parked bots beyond one-per-playing-human are **kicked**.
  That is what makes *reducing* N kick the freed bots (0 humans -> 0 reserve -> all parked kicked) while
  a human-displaced bot still parks for reuse. `gf_fill_kick_floor` additionally kicks parked bots
  before they can breach `sv_maxclients` and lock a human out.

### Round-safety
**REVISED 2026-07-10.** The stock team switch (`level.allies/axis/spectator` = menuAllies/menuAxis/
menuSpectator) calls `suicide()` on a *"playing"* client — a spawned, **alive** bot, which **includes
the prematch-frozen state**. Do that to a live bot and you get the two reported bugs: a **visible
"bot suicides at spawn"** (park spectating a frozen bot during prematch) and, if it was the team's
last-alive, a **phantom round-end**. The old rule "park only between rounds (`!gf_roundActive`)" did
NOT actually make this safe, because `gf_roundActive` is false *during prematch too* — bots are
spawned & frozen (alive) there — so the park still suicided them. The fix is a per-bot gate,
`gf_botSwitchSafe()` = **not (`sessionstate=="playing"` && `health>0`)**: a switch is only issued to a
bot that is **dead** (one-life: eliminated for the round) or **spectator/limbo**. Both are invisible
(no fresh spawn) and can't touch the live alive-count (no phantom end), so park now runs **every pass**
with no round gate. In practice a mid-round human joiner's surplus bot is trimmed **the instant it dies**
during the round (or a round later if it survives), landing his side at exactly N with **zero visible
suicide**. The same gate guards `gf_botDeployWhenReady` (a fresh bot autoassigned+spawned on the wrong
side is left there, not suicide-switched — the next pass rebalances via park). Counts key off
`level.players` + `istestclient()` (**not** `level.bots`), so the reconciler stays correct even when a
restart disturbs BotWarfare's bookkeeping.

### Surviving restarts
`_bot::init` fires **`level notify("bot_reinit")`** before re-threading, and every persistent bot loop
carries `level endon("bot_reinit")`. This matters because **threads survive `map_restart(false)`** while
`game[]`/`pers[]`/`level[]` are wiped — so the once-per-match `game["gf_botInit"]` gate in `gf.gsc`
re-fires after the lobby fast-restart and would otherwise stack a *second* set of managers. The notify
collapses it back to exactly one live set. Between rounds (`map_restart(true)`) `game[]` survives, the
gate does not re-fire, and the managers keep running. This is also the fix for **"fast restart clears
the bots"**.

### Team moves that stick
Human moves always stick (the reconciler never touches humans). A **live human cannot be moved across
teams without dying** — a quiet reassign of a spawned player fires a false `onDeadEvent` (moving the
last-alive player off a side reads as a team wipe) and nulls `self.class`, corrupting alive counts. So
the panel offers exactly two actions: **normal click = next round** (queued via `pers["gf_pendingTeam"]`,
no death) and **Shift+click = force now** (`pteamforce_`, respawns, costs the round). Same rule for bots.

---

## Gametype Dvars

Registered/clamped in `gf.gsc` (`onStartGameType` + the `register*Dvar` calls in `main()`) and
`_gf_rounds.gsc` (`gf_cfgFloat`). Set in `dedicated.cfg` or via RCON. The `scr_gf_*` family
persists through `map_restart`.

| Dvar | Default | Meaning |
|---|---|---|
| `scr_gf_timelimit` | 0.75 | Round length (min), SMALL mode (0.75 = 45s) |
| `scr_gf_timelimit_large` | 1.5 | Round length (min), LARGE mode |
| `scr_gf_scorelimit` | 6 | Round wins to win the match |
| `scr_gf_roundswitch` | 2 | Rounds between side switches |
| `scr_gf_roundsperloadout` | 2 | Rounds before the shared loadout rotates (clamped 1-9) |
| `scr_gf_overtimelimit` | 15 | Overtime seconds, SMALL; `0` disables OT (HP decides immediately) |
| `scr_gf_overtimelimit_large` | 30 | Overtime seconds, LARGE |
| `gf_capture_time` | 3 | OT zone hold-to-capture seconds, SMALL |
| `gf_capture_time_large` | 5 | OT zone hold-to-capture seconds, LARGE |
| `scr_gf_teamspawnmode` | auto | `auto` \| `large` \| `small` (see Team-Size Mode) |
| ~~`scr_gf_largemode_minplayers`~~ | *(retired)* | **RETIRED 2026-07-03 — no longer read.** The small/large split is now hard-wired to the health-panel skull cap in `gf_autoLargeFromCounts()` (`<=4v4` small, any team of `5+` large). A tunable spawn threshold could only DEcouple it from the fixed menu `cnt > 4` gate, and the old TOTAL-vs-new-PER-TEAM reinterpretation was a live footgun (a stale `7` made large mode unreachable). Any stale cfg value is inert. Pin the mode with `scr_gf_teamspawnmode large\|small` |
| ~~`scr_gf_roster_wait`~~ | *(retired)* | **RETIRED 2026-07-04 — no longer read.** Was a post-prematch hold of the round clock until every teamed human had spawned. Made redundant by the pre-prematch load gate (`scr_gf_load_wait`): once every client is confirmed loaded *before* prematch, they've all spawned (frozen) *by* `prematch_over`, so there was nothing left to wait for. `gf_allTeamedPlayersSpawned` deleted with it. Any stale cfg value is inert |
| `scr_gf_min_players` | 1 | **Min-HUMANS-to-start gate** — **folded into the pre-prematch load gate 2026-07-04** (`gf_waitForLoadingClients`, `_gf_rounds.gsc`; the old standalone `gf_waitForMinPlayers` is gone). Holds the match's FIRST round (`game["roundsplayed"]==0`) *before* the prematch countdown until at least this many *humans* are here (bots — `istestclient()` — don't count). Because it now runs BEFORE anyone spawns, it needs **no freeze and no damage-void** (the old `level.gf_waitingForPlayers` machinery is deleted) — nobody is in the world yet to die, and the intro no longer plays for a match that then stalls. Counts tracked humans (loaded **or** still loading — a loader counts as "here"). Anti-wedge: a **pure-bot lobby** (0 humans) never holds, and a **90s** `GF_MINPLAYERS_MAX_HOLD` ceiling is the "start anyway" fallback. Match-start only. `1` = effectively off. Clamped 1-8. Shares the "Waiting for teams…" screen with the load gate. Distinct from `scr_gf_load_wait` only in *what* it waits for (enough humans to exist vs. the known roster finishing its map load) — same hold, two release conditions |
| `scr_gf_load_wait` | 0 (off) | **Pre-prematch gate — LOAD condition** (`gf_armLoadGate`/`gf_waitForLoadingClients`, `_gf_rounds.gsc`; added 2026-07-03, min-players folded in 2026-07-04). Match's FIRST round only: holds at the END of `onStartGameType` — the engine threads `startGame()` (prematch countdown) only when that callback returns — until every rotation-carried HUMAN client has left the loading screen, so everyone sees the full countdown/intro together and slow loaders can't be grace-locked into spectating round 1. Works because clients connect while STILL LOADING (`Callback_PlayerConnect` fires pre-load; statusicon `hud_status_connecting` until the engine's `"begin"`, and only then do they enter `level.players`) — the stock `waitForPlayers()` hook for this is an empty stub in T5. Loading = statusicon check; entities collected via the level `"connecting"` notify (pre-begin clients exist nowhere else). Bots (`istestclient()`) excluded from wait + readout. This dvar = ceiling seconds (clamped 0-120, `0` = gate off); 3s arrival floor. Shows the stock "Waiting for teams..." string + a live yellow `loaded / total` readout (setValue-driven, configstring-safe) in the countdown's slot. FastDL first-time downloaders (30-60s+ engine rebuild) are deliberately NOT absorbed. Releases log `GF_LOADGATE:` to games_mp.log. The SAME hold also enforces `scr_gf_min_players` (the humans-exist condition); a client STILL loading when the load ceiling hits is then covered by `scr_gf_load_grace` (below) |
| `scr_gf_load_grace` | 20 | **Straggler grace extension** (`gf_anyTrackedClientLoading`/`gf_closeGraceEarly`, `_gf_rounds.gsc`; added 2026-07-04). Companion to `scr_gf_load_wait`: when the load gate releases with a client STILL loading (it hit the `scr_gf_load_wait` ceiling — e.g. a first-time FastDL downloader taking 30-60s+), keep the grace period open this many seconds *past `prematch_over`* so that client can still take its round-1 first spawn (stock `maySpawn` only admits a late first-spawn while `inGracePeriod`) instead of spectating the whole round. Implemented by raising `level.gracePeriod` at gate release (so the stock `gracePeriod()` backstop doesn't close first) + a hold in `gf_closeGraceEarly` keyed off the same tracker snapshot. **Cost:** a round-1 team wipe can't END the round until grace closes (bounded by this ceiling and by round length) — the deliberate tradeoff for letting the loader play. `0` = off (straggler spectates round 1, the pre-2026-07-04 behavior). Round 1 only (tracker snapshot is `map_restart`-wiped); bots excluded (`istestclient()`); a straggler who disconnects mid-load releases the hold. Clamped 0-60 |
| `scr_gf_lobby` | 0 (Normal) | **Match Start mode — the "pregame lobby"** (`gf_waitForLoadingClients`, `_gf_rounds.gsc`; `lobbystart`/`gf_bridgeLobbyStart` in `_gf_bridge.gsc`; **consolidated 2026-07-05** from the retired `scr_gf_lobby_hold`/`scr_gf_lobby_restart`/`scr_gf_lobby_restart_full`). How the match's FIRST round starts (before the prematch countdown): `0` = **Normal** (default) — no lobby; starts in place (still holds for loaders / `scr_gf_min_players` via the pre-prematch gate, then the countdown plays; **no restart**). `1` = **Auto** — hold a pregame lobby (desaturated `mpIntro` vision + "Waiting for teams N/M" readout) until everyone is loaded AND `scr_gf_min_players` humans are here, then **`map_restart(false)`** into a fresh match. `2` = **Manual** — hold until the admin's **START MATCH** click (RCON panel → Match Control rail → bridge `lobbystart` → `level.gf_lobbyStart`, polled every 0.25s), then fast-restart; lets an admin arrange teams (right-click → move; applied **live**, `inPrematchPeriod` is already true during the hold). **Why the fast-restart:** the in-place hold pauses mid-init (the engine set `inPrematchPeriod`/InitGame BEFORE `onStartGameType`), so it's a paused-startup, not a true lobby; **`map_restart(false)`** re-inits FRESH so the full start presentation fires — weapon first-raise/"gun rack", spawn music, welcome splash — which the between-rounds **`map_restart(true)`** deliberately suppresses (verified in-game 2026-07-05: false racks the gun + plays music, fast, no map reload). The restart branch **blocks `onStartGameType` from returning** so `startGame()` never threads a stale prematch/timer (which would survive the restart and stack → double countdown); the **`gf_matchArmed` dvar** (NOT game[]: `map_restart(false)` wipes game[]/pers[], so a game[] flag would re-lobby forever) makes the post-restart pass skip the gate → real match threads its clocks once. Auto/Manual: START MATCH is an **instant override**; **10-min `GF_LOBBY_MAX_HOLD` backstop**; live state mirrored into the `gf_state` `lobbyHold` field so the panel reveals START only while a hold is up. Match-start only (`roundsplayed==0`); clamped 0-2. Manual needs the dev RCON bridge (inert on a bridge-less build; backstop still recovers). **CAVEAT RESOLVED 2026-07-08 — lobby-arranged teams now TRANSFER** (pending in-game verify): `gf_writeTeamPlan()` snapshots every human's `getGuid()`->team into the `gf_teamplan` DVAR immediately before `map_restart(false)`, and `gf_applyTeamPlan()` (threaded from the `gf_matchArmed` consume branch, with `level.forceAutoAssign=true` so returning humans skip the team menu) re-seats each by GUID during the post-restart prematch — where the stock switch is the harmless frozen warmup. Bots are NOT snapshotted; the fill reconciler re-pads them from `gf_fill_n`. Both helpers are self-contained in `_gf_rounds.gsc` (no bridge dep) so they survive the public-build strip |
| `gf_fill_n` | 0 (off) | **Dynamic bot fill — the PER-TEAM target N** (`3` = 3v3). The reconciler (`_bot.gsc`, dev-only) pads each side to exactly N *playing* clients (humans+bots), with **bots absorbing all the variance**. A human joining team T displaces a bot on T; a human leaving re-pads it. **Humans are NEVER auto-moved** — if humans on a side exceed N, that side's bots go to 0 and it may exceed N while the other side still fills to N. Displaced bots **park in spectator** for instant reuse (kicked instead under client-slot pressure; and *reducing* N kicks the freed bots, because the parked reserve is capped at the live human count). Overshoot-free: parked bots are reused from a finite pool and new bots are added **one-in-flight-at-a-time** (a bot is marked `.gf_fillPending` until it lands on its target team, so no pass can steal or miscount it). `0` = **fill OFF -> reconciler inert**, which is what makes the panel's manual per-team bot add/kick/move *stick*. Survives `map_restart(true)` (between rounds) and `map_restart(false)` (lobby fast-restart). A DVAR because that is the only state surviving the fast-restart. Clamped 0-6 on read (`gf_fillTarget()`); the panel clamps too. RCON: **DASHBOARD → BOTS → Fill (per team)**. See the **Dynamic Bot Fill** section |
| `gf_fill_kick_floor` | 2 | Client slots kept free for humans. A parked bot is **kicked** rather than parked once total clients would breach `sv_maxclients - gf_fill_kick_floor`, so parked bots can never lock a real player out of the server (at 6v6 with `sv_maxclients 14`, an uncapped parked reserve would exhaust slots). Also caps the parked reserve. Read via `gf_fillKickFloor()` (>=0) |
| `gf_teamplan` | "" | Read-only plumbing for the lobby->match transfer: a `"<guid>:<a\|x\|s>,..."` snapshot of arranged HUMAN teams, written by `gf_writeTeamPlan()` just before the lobby's `map_restart(false)` and consumed once by `gf_applyTeamPlan()` after. A dvar because `game[]`/`pers[]`/`level[]` are all wiped by that restart. Humans only (bots are re-padded by fill) |
| ~~`bots_manage_fill`~~ / ~~`bots_manage_fill_kick`~~ / ~~`bots_manage_add`~~ / ~~`bots_team_amount`~~ / ~~`bots_team_force`~~ | *(retired for Gunfight)* | **RETIRED 2026-07-08 — no longer read.** These drove BotWarfare's `addBots()` (global bot headcount) and `teamBots()` (team rebalance) loops, which fought each other *and* fought manual RCON team moves, and whose mid-connect `suicide()` was the "bots suicide as they connect" bug. Both loops are now **unthreaded dead code**; the Gunfight reconciler (`gf_reconcilerInit`, `_bot.gsc`) replaces them with one authority over bot counts + placement, driven by `gf_fill_n`. Still *seeded* in `_bot::init` for BotWarfare AI compatibility; setting them does nothing. `doNonDediBots()` (local "Basic Training") is retired with them — set `gf_fill_n` instead |
| `scr_gf_flinch` | 1 | **Flinch (damage view-kick) scale** — a MULTIPLIER of stock `bg_viewKickScale` (0.2): `1` = stock, `0` = no flinch, `>1` = more; clamped 0-3. Applied in `gf_applyFlinch()` (`_gf_rounds.gsc`) via **server-side `setDvar`**, which runs with engine authority and so bypasses the `sv_cheats` gate that blocks rcon/console `set` of a cheat-protected dvar — i.e. it holds on the **dedicated VPS**, unlike the client-pushed `gf_vis_*` r_* tweaks. `bg_` dvars replicate to clients, so the reduced kick is what each player feels. Re-applied every `onStartGameType` (persists across `map_restart`). RCON: **DASHBOARD → PLAYER STATE → Flinch** slider (bridge `flinch_<mult>` → sets `scr_gf_flinch` + applies live). *Pending in-game verify that server-side `bg_viewKickScale` replication reduces the felt flinch on a dedicated server.* |
| `scr_team_maxsize` | 0 (shipped cfg sets **6**) | `>0` caps players/team; overflow is sent to spectator on spawn (`gf_playerSpawnedCB`). `dedicated.cfg` ships `6` (up to 6v6); `sv_maxclients` 14 = 12 play + 2 spectator. Set `4` for a 4v4 server |
| `perk_weapSwitchMultiplier` | (engine default) | Engine weapon-swap speed (lower = faster); gated by `specialty_fastweaponswitch`, which is **OFF by default** (no longer in the base loadout). NOT forced by the mod — stock by default. To use it: enable Fast Weapon Switch via the RCON Perks tab (`gf_perk_on`), then tune the slider; inert until the perk is on |
| `gf_perk_on` / `gf_perk_off` | "" | Comma-separated perk override lists (RCON-managed) applied AFTER the base perk set in `gf_giveCustomLoadout` |
| `gf_admin_guids` | "" | Comma-separated player-GUID allowlist for **private** bridge feedback. `gf_bridgeNotify` prints command confirmations ONLY to these players (empty = nobody), replacing the old bare `iPrintLnBold` that center-printed to EVERYONE. Managed by the panel's right-click "Send feedback to me" (pushed live + re-pushed each reconnect). GUID = the stable `status` guid, matched via `self getGuid()`. The `saymsg` broadcast is deliberately NOT gated — it still prints to all. |
| `gf_ack` | 0 | Read-only telemetry: sequence id of the last `gf_cmd` the bridge processed. The panel stamps each command `set gf_cmd <seq>:<cmd>` and polls `gf_ack` (via `/api/ack`, high-priority lane) to flip its command-queue entry from ⏳ "sent" to ✓ "received" (with round-trip ms). Single-token read → dedicated-only, like `gf_state`; on a listen server the panel confirms optimistically. |

**Level flags (not dvars), toggled by the dev RCON bridge `_gf_bridge.gsc`:** `level.gf_headshotsOnly`
(only head/helmet hits deal damage). The bridge is dev-only (stripped from public builds), so this is off in release.

**Dev/debug dvars** (callers are strip-wrapped, so only active on `main`): `gf_debug_spawns`,
`gf_debug_hud_pool`, `gf_debug_elem_probe`. Loadout test aids (`_gf_loadouts.gsc`): `gf_force_loadout`
(lock a specific pool index every spawn, `-1`/unset = off — inspect any 1 of the 54 without waiting
for the rotation) and `gf_force_camo` (force a camo index 0-15 on BOTH guns every spawn, `-1`/unset =
off — e.g. `set gf_force_camo 15` to check gold-camo visibility per weapon). Both read via `getDvar`,
so a listen host sets them straight from the console.

**Loadout camo is now per-slot.** `gf_load()` takes a 7th arg `camoSec` (secondary-gun camo, `0-15`
or `-1` random), independent of the primary `camo`. Old 6-arg calls still work (secondary follows the
primary). Visibility caveat unchanged: only real-base secondaries (crossbow; maybe pistols w/ solid
colors/Gold) actually render camo. `ks23_mp` is a dud (finger-gun fallback) — dropped from the editor;
`hs10_mp` is the real single shotgun. See [[invalid-weapon-finger-gun-fallback]].

**RCON bridge command protocol (private feedback + sent/received acks, added 2026-07-03):** the panel
sends every bridge command as `set gf_cmd <seq>:<cmd>` (monotonic seq, persisted in the panel's
localStorage). The GSC poll loop runs at **20 Hz** (was 2 Hz — cuts up to ~450ms of latency; read+clear
are adjacent statements so the take is race-free, no dedup needed), splits `<seq>:<cmd>`, dispatches,
and writes the seq into `gf_ack`. Command feedback is now **private**: `gf_bridgeNotify(text)` replaces
the ~40 bare `iPrintLnBold` confirmation calls and prints only to `gf_admin_guids` players (the `saymsg`
broadcast keeps its global `iPrintLnBold`). On the server side, `sendRconQueued` is now a **priority
scheduler**: user clicks (`/api/rcon` `priority:true`) and ack reads (`/api/ack`) take a high lane so
they preempt the background status/score/roster ticks and the ~100-dvar connect sweep — the ≥850ms
reply gap is still enforced (hard Plutonium limit), priority only reorders who goes next. The panel shows
a bottom-left **command queue** (`cqAdd`/`cqResolve` etc.): ⏳ sent → ✓ received (round-trip ms) → ✗
timeout. See the `_gf_bridge.gsc` header comment for the wire format.

**RCON transport rebuilt (2026-07-03 late — root cause of "panel commands took minutes on the VPS"):**
TWO compounding causes, both fixed. (1) PANEL SELF-SATURATION: each background rcon read holds the
panel's send lane ~1.25s (850ms enforced gap + reply collect), but the UI enqueued THREE reads per
tick cycle (status @3s + gf_state + gf_roster @2.5s on two `setInterval`s) ≈ 1.4× the lane's drain
rate — on a dedicated server the queue grew without bound (a listen server masked it: scoreTick
early-returned there, which is why it only hurt on the VPS). Stacked hanging fetches then exhausted
the browser's 6-per-origin connection pool, so even PRIORITY clicks (team moves, map restart, bots)
waited minutes in the browser before the server's priority lane could see them, then their acks
timed out → retry spam. Fix: ONE self-scheduling poll (`pollTick`, next cycle armed only after the
previous resolves — can never stack) hitting a new **`/api/tick`** that chains `status;gf_state;gf_roster`
into ONE rcon send; plus server-side **coalescing** (`_rconEnqueue` `key` arg) so identical queued
reads piggyback on one send. Steady state ≈ 1 send / ~3.8s ≈ 35% of lane capacity. (2) COMPETING
BOX-SIDE SENDERS: the VPS also ran status_service (2 raw sends / 5s), TWO join-notify tasks (duplicate
"GF Join Notifier" task removed; canonical is GF-JoinNotify per register_services.ps1), and
conn_logger (1 / 15s) — independent unpaced UDP senders racing the panel for the server's
~1-reply-per-0.7s rcon limit; collisions silently ate replies (each eaten panel reply = a 3s timeout
stall). All three services are now **panel-first**: they read via the panel's `/api/tick`/`/api/status`
(sharing its paced, coalescing queue — status_service's read even merges with the admin panel's own
tick when both are queued) and fall back to direct rcon only when the panel isn't running. RULE:
never add another direct rcon poller on the box — go through the panel API on 127.0.0.1:3000 so
exactly one process owns the pacing. Deployed live via scp 2026-07-03 (panel + 3 services restarted).
**UPDATE 2026-07-05 — conn_logger no longer rcon-polls at all.** It now diffs `status_service`'s
`admin.json` FILE (the auth-gated admin snapshot, which carries per-player IP + GUID), so it does
zero rcon of its own and inherits the 5s cadence (was a 15s direct poll). status_service is the
single box-side rcon reader for both the snapshot AND the connect log. `admin.json` is written
atomically (temp + Move), reads are never torn; a missing/stale (>30s)/offline snapshot makes
conn_logger skip that tick (never a mass-LEFT). Both status_service (`$adminList`) and conn_logger
also require a real `ip:port` (or listen `local`/`loopback`) per player, so bots the panel's
`guid==0 && addr=='unknown'` check misses (and still-connecting clients whose address column holds a
lastmsg value) no longer inflate the human count or spam the log. The admin page (`/admin/admin.html`)
gained a searchable multi-day **Connection history** card, fed by `admin_history.json` (built by
status_service from the `players_*.log` day-files every 60s, last 60 days, capped 5000 events, same
`.secured` gate + guid now included).

**Dropped-packet self-heal + forced team move (added 2026-07-03).** Plutonium silently drops rcon
packets sent faster than ~1/0.7s, so a click could vanish with no effect. Two-part fix: (1) the panel
**auto-retries** an unacked command — resends the SAME seq up to 3× ~1.5s apart (`ackTick`), showing
"retry 2/3" — and the GSC bridge **dedups by a high-water `level.gf_ackSeq`**: a seq `<=` the mark is
re-ACKed but NOT re-run, so a retry of an already-run command (e.g. `endround`, `quake`, `tpall`) can
never double-fire. seq `0` (unstamped / manual console) skips dedup and always runs. (2) **`pteamforce_<num>_<team>`**
(panel: **Shift+click** a move, with a confirm) bypasses the next-round defer and applies the switch
immediately via the stock team-change — it **respawns** the player, so during a live round it costs them
the round. The cap (`scr_team_maxsize`) still holds; plain `pteam_` keeps the safe next-round deferral.

**RCON team management (dev bridge):** the RCON panel's per-player right-click menu moves a player
between allies/axis/spectator via bridge command `pteam_<num>_<allies|axis|spec>`
(`gf_bridgeTeamCmd` in `_gf_bridge.gsc`). A live switch would `suicide()` a "playing" player
(stock `menuAllies`/`menuAxis`/`menuSpectator` = `level.allies`/`axis`/`spectator`), so it's applied
**immediately only during the native prematch countdown** (`level.inPrematchPeriod` — players frozen,
round unscored, so the suicide/respawn is the harmless warmup switch). **Any other time — live round or
killcam — it DEFERS** via `self.pers["gf_pendingTeam"]` (the only state that
survives `map_restart`) and is applied in the **next round's prematch**. Two subtleties drove this
(both caught by adversarial review): (1) it can't sweep at `gf_bridgeInit`, because `_spawnlogic::init`
empties `level.players` *before* `onStartGameType` and `Callback_PlayerConnect` only repopulates it
later — so the deferred apply is driven by a `gf_bridgeWatchPendingTeam` watcher on the
`spawned_player` notify (fires when a player has actually spawned that round); (2) it must NOT flip
`pers["team"]` on a live player, because `gf_onPlayerDamage` reads it for friendly-fire — deferral
keeps the pending team in a *separate* `pers` key until the prematch apply. `gf_applyTeamMove` then
branches on `sessionstate`: `"playing"` (spawned/frozen) → full stock switch; otherwise a quiet
`pers["team"]`/`team`/`sessionteam` reassign the spawn honors. Team-size
caps are enforced up front in `gf_bridgeTeamCmd` (`gf_bridgeTeamFull` mirrors `gf_playerSpawnedCB`'s
overflow count) so an over-cap move is refused with feedback instead of a silent spectator-bounce. The
panel reads a new **`gf_roster`** telemetry dvar (`<num>,<team>,<alive>,<pending>;…`, codes `a/x/s/-`)
for per-player team badges + grouped-by-team roster; dedicated-only (times out on a listen server, like
`gf_state`), so on listen it falls back to a flat list while the move commands still work.

> Note: video tweaks are STOCK by default (rebuilt 2026-07-03). `gf_playerSpawnedCB` calls
> `gf_applyVisTweaks()` (humans only), which pushes ONLY the `gf_vis_*` dvars that are non-empty
> (`gf_vis_ambient/gridint/gridcon/hdr/fog` → `r_lightTweakAmbient`/`r_lightGridIntensity`/
> `r_lightGridContrast`/`r_fullHDRrendering`/`r_fog`). The RCON Visuals sliders persist values into
> those dvars via the bridge (`vis<key>_<value>`; value `stock` clears one, `visreset` clears all).
> The old `scr_gf_visualtweaks` force-push (r_gamma 1.1 etc. every spawn) was removed: `r_gamma` is
> a SAVED client dvar Plutonium blocks servers from writing.

---

## Overtime Zone Color System

Two independent visual layers carry different information:
- **Icons** (2D minimap + 3D above the flag) — **team-relative**: green = *your* team capturing, red = *enemy* capturing.
- **Apron** (ground FX ring) — **absolute**: a zone-activity cue everyone sees the same.

### Required behavior
| State | Apron (FX) — same for all viewers | Minimap + 3D icon — capturing-team viewer | Minimap + 3D icon — other-team viewer |
|---|---|---|---|
| Nobody capturing | White | White | White |
| A team capturing | Gold | Green (friendly) | Red (enemy) |
| Contested (both in) | Red | White | White |

### Why icons CAN be team-relative but the apron CANNOT — engine constraint
This is the key limitation, and it dictates the whole design:

**Icons are team-routed elements.** The 2D minimap icon is an `objective` (per-team `objIDAllies`/`objIDAxis`) and the 3D world icon is an `objpoint` (`newTeamHudElem(team)`). Both are created and shown **per team**, so allies and axis can be shown *different* icons at the same instant. That is how "green to your team / red to the enemy" is possible.

**The apron is world-space FX.** In T5, an FX entity spawned with `spawnFx` exists in **world space** and is rendered **identically for every connected player**. There is no per-team FX visibility — you cannot show a blue ring to allies and a red ring to axis from one FX entity. Therefore the apron *cannot* encode "friendly/enemy"; it can only show one color to everyone. We use it as an absolute activity cue: **white idle, gold while a team is capturing, red contested.**

### Why the icons coincide (2D minimap == 3D flag icon)
Both icons are driven from the **same native `_gameobjects` path** in `gf_setOvertimeZoneIcons( zone, friendlyIcon, enemyIcon )`, which sets `set2DIcon`/`set3DIcon` with a **matched shader family**: `compass_waypoint_X` for the minimap and `waypoint_X` for the world icon, same `X` per relative-team slot. Because they are the same artwork in 2D vs 3D form, their colors coincide *by construction* — no manual RGB to keep in sync. Mapping (dom.gsc convention): **friendly → `defend` (green), enemy → `capture` (red), idle/contested → `captureneutral` (white).**
`setOwnerTeam( capturingTeam )` routes the capturing team into the "friendly" slot and the other team into "enemy".

> Pitfall that caused the earlier "my team shows red" bug: the friendly/enemy → shader mapping was reversed (`friendly→capture`). `defend` is the friendly/owner color, `capture` is the enemy color. Keep friendly→defend, enemy→capture.

### Implementation
- **Icons** (`gf_setOvertimeZoneIcons` + `gf_setOvertimeZoneIconColor`): native `set2DIcon`/`set3DIcon` matched pairs + `setOwnerTeam`. No custom HUD elements (the old `level.gf_ot_wi_*` / `gf_updateOvertimeWorldIcons` were removed — a parallel custom 3D element that drifted out of sync with the native 2D icon).
- **Apron FX** (`gf_setOvertimeZoneIconColor`): deletes the old handle and `spawnFx` the color for the state — `gf_ot_baseFx_neutral`(white) / `_allies`+`_axis`(gold) / `_contested`(red).
- **Visual driver**: `gf_overtimeZoneVisuals` polling thread (100 ms tick) — counts players per team via `isTouching`, drives all state transitions. Replaced the old `_gameobjects` `onBeginUse/onEndUse/onUseUpdate` callbacks which had a `numTouching` race.

### Apron FX handle lifecycle — must reload every OT (map_restart pitfall)
`loadfx()` handles are stored in `level.*` (`level.gf_ot_baseFx_*`). `onPrecacheGameType` runs **once per match**, but `_globallogic::endGame` does `map_restart(true)` between rounds, which **wipes all `level.*`**. So a handle loaded only at precache is `undefined` by round 2 → no apron. Fix: `gf_loadOvertimeApronFx()` is called **every OT entry** from `gf_createOvertimeZone` (as well as at precache) to re-establish the handles. See memory `onprecache-once-per-match-loadfx-wiped`.

### FX assets (no rebuild needed for current colors)
- **white idle** → custom `misc/fx_ui_flagbase_gf_white` (in mod.ff). The only color sourced from the custom `.efx`.
- **gold capturing** → stock `env/light/fx_ray_grnd_loc_marker_ylw_mp` (yellow ≈ gold).
- **red contested** → stock `env/light/fx_ray_grnd_loc_marker_red_mp`.

Stock `fx_ray_grnd_loc_marker_*` markers only exist in **grn / red / ylw** (no white, no blue) — that's why gold/red are stock but white stays custom. The old `fx_ui_flagbase_gf_blue.efx` (allies/blue) is now **unused**; `blue.efx` was earlier edited to green content anyway. Only rebuild mod.ff if you change the custom white `.efx`.

---

## Wager Map Zone

### Proven approach

Gunfight uses the stock wager-map play spaces automatically without enabling the wager-match framework. No console setup is required.

The important discovery is that many wager blockers are already baked into the map entity lump. They are normal map entities tagged with:

```gsc
script_gameobjectname "gun oic hlnd shrp"
```

Stock `_gameobjects::main( allowed )` deletes entities whose `script_gameobjectname` does not match the gametype allow-list. Gunfight keeps the wager blockers by adding the stock wager gametype tags to `allowed`.

### Implementation

- `maps/mp/gametypes/gf.gsc` uses `mp_wager_spawn` for both teams when wager spawns exist.
- `maps/mp/gametypes/gf.gsc` keeps `gf` and `dom` gameobjects, then adds `gun`, `oic`, `hlnd`, and `shrp` before calling `_gameobjects::main( allowed )`.
- `maps/mp/gametypes/_gf_wager_zones.gsc` applies the wager minimap material and the extra Cosmodrome small-map collision helpers.
- Do not set `xblive_wagermatch` to `1`; enabling it brings back wager UI/lives/prematch side effects.

### Verified catalogs

Offline fastfile/entity extraction found the stock wager data without needing a runtime dump:

- `tools/wager_spawns/` lists maps with `mp_wager_spawn` entities.
- `tools/wager_entities/` lists baked blocker entities tagged with `script_gameobjectname "gun oic hlnd shrp"`.
- Maps with baked blocker catalogs: `mp_array`, `mp_cracked`, `mp_duga`, `mp_hanoi`, `mp_havoc`, `mp_russianbase`.
- Maps with wager spawns: `mp_array`, `mp_cairo`, `mp_cosmodrome`, `mp_cracked`, `mp_crisis`, `mp_duga`, `mp_hanoi`, `mp_havoc`, `mp_mountain`, `mp_radiation`, `mp_russianbase`, `mp_villa`.

### Normal test

```cfg
set g_gametype gf
map mp_havoc
```

Expected result: Gunfight loads normally, uses wager spawns/minimap, and preserves the stock visible blockers such as rocks, gates, fencing, sandbags, debris, and brushmodels.

### Cleanup notes

Removed failed research paths from the project:

- No local overrides of stock `gun.gsc` or `oic.gsc`.
- No `gf_dumper.gsc` auto-loader script.
- No `xblive_wagermatch` dvar toggle — setting it was never necessary and activates the full wager framework.
- No plugin/DLL dvar timing workaround for this feature.

`_gf_debug.gsc` remains in the project as a general dev tool (spawn recorder + `gf_do_dump` entity scanner), but it has no connection to how wager barriers are enabled.

---
## Design Goals

> Focus on minimizing custom systems in favor of leveraging native engine functionality wherever possible. 
> Thoroughly review all relevant source files S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\raw\maps\mp\gametypesand dual.gsc.
> Identify redundant logic, inefficient patterns, and unnecessary custom implementations.
> Highlight areas where built-in or stock game engine systems can replace custom code.
> Investigate making the project more lightweight and maintainable.
> Reduce script complexity, execution overhead, and duplication.
> Ensure better integration with existing game framework features.
> Propose specific refactors to improve structure, readability, and modularity.
> Suggest simplifications that preserve functionality while reducing code size and complexity.
> Identify CPU-heavy logic, repeated calls, or inefficient loops.
> Suggest improvements that align with a more â€œOEM/stockâ€ feel.

### Core gameplay
- Round-based (last team standing ends the round, then killcam plays)
- 6 rounds to win the match
- One life per round â€” no respawns
- No killstreaks, no perks shown pre-round, no health regen, no weapon drops


### Loadout HUD (priority visual feature)
- On spawn: weapon icons slide in from the right â€” primary, secondary, lethal, tactical, then 3 perk icons
- All rows slide in simultaneously via `moveOverTime(0.5)`, hold 5.5s, slide back out


---

## Resources

### T5 Source Code
- **plutoniummod/t5-scripts** â€” Official Plutonium T5 source dump (MP + ZM gametypes, utility scripts, etc.)
  https://github.com/plutoniummod/t5-scripts
  Key files: `MP/Common/maps/mp/gametypes/shrp.gsc`, `gun.gsc`, `sd.gsc`, `_wager.gsc`, `_globallogic.gsc`, `_class.gsc`, `_hud_util.gsc`, `_rank.gsc`
- **Local T5 source dump** (user's machine): `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\raw`
- https://github.com/JTAG7371/T5-RawFile-Dump

### Community Mods (reference/pattern source)
- **Xinerki/t5-gunfight** â€” T5 Gunfight/duel gametype mod; source of confirmed weapon icon shader names and T5 player methods
  https://github.com/Xinerki/t5-gunfight
- **misterbubb/T6-Gunfight-Gamemode** â€” BO2/T6 Plutonium Gunfight; closest engine to T5, best code reference for overtime + equipment delay
  https://github.com/misterbubb/T6-Gunfight-Gamemode
  https://github.com/misterbubb/T6-Gunfight-Gamemode/blob/main/gunfight_mp/maps/mp/gametypes/sd.gsc
  https://forum.plutonium.pw/topic/43931/release-gunfight-gamemode
- **bblack16/plutonium-waypoints** â€” IW5/MW3 Gunfight port
  https://github.com/bblack16/plutonium-waypoints
  https://github.com/bblack16/plutonium-waypoints/blob/main/iw5/scripts/gamemode_gunfight.gsc
  https://forum.plutonium.pw/topic/37594/release-custom-game-modes-reinforce-gunfight-and-gun-game
- **iAmThatMichael/gunfight** â€” BO3/T7 Gunfight recreation; used for game-mode design reference
  https://github.com/iAmThatMichael/gunfight
  https://github.com/iAmThatMichael/gunfight/blob/master/scripts/mp/gametypes/gf.gsc
- **GunMd0wn custom_gunfight.gsc** â€” community Gunfight mod (runs on HQ/TDM); source of class-select suppression patterns and weapon dvar approach. No GitHub â€” search Plutonium BO1 forum or megathread.
- **mp_EMv2_Recreation, mp_iMCSx, mp_EnCoReV8** C:\Users\klaze\iCloudDrive\Documents\iCloud Drive (Archive)\mods\Games\Black Ops\Inject ready GSC
- **Resxt/Plutonium-T5-Scripts** â€” Collection of community T5 GSC scripts
  https://github.com/Resxt/Plutonium-T5-Scripts
- **CabConModding BO1 weapons GSC tutorial**
  https://cabconmodding.com/threads/black-ops-1-all-about-weapons-gsc-tutorial.1268/


### Plutonium Docs & Forums
- **Loading mods into Plutonium**
  https://plutonium.pw/docs/modding/loading-mods/
- **Plutonium new GSC scripting features** (T5/T6 scripting extensions)
  https://www.plutonium.pw/docs/modding/gsc/new-scripting-features/
- **Plutonium BO1 modding releases & resources forum**
  https://forum.plutonium.pw/category/60/bo1-modding-releases-resources
- **BO1 mods megathread** (organized collection of mods, tutorials, guides)
  https://forum.plutonium.pw/topic/34555/megathread-organized-collection-of-bo1-mods-releases-tutorials-and-guides

### Future Projects (reference)
- **PlutoniumT5 map vote mod** â€” full mods folder + map vote system
  https://github.com/DoktorSAS/PlutoniumT5Mapvote
- **ProjectDonetsk/T9** â€” T9 port for Plutonium
  https://github.com/ProjectDonetsk/T9

---

## Building mod.ff

`mod.ff` is the compiled zone file that registers the gametype in the UI (strings, gametype table, mapvote menu) and compiles binary assets (FX, models, images). Rebuild it whenever `gametypesTable.csv`, `gf.str`, `mapvote.menu`, or any `.efx` file under `raw/fx/` changes.

**Tools:** `S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\bin\linker_pc.exe`

**Step 1 â€” stage source files to mod tools `raw/`:**
```
mod folder                              â†’ mod tools raw/
mp/gametypesTable.csv                   â†’ raw/mp/gametypesTable.csv
localizedstrings/gf.str                 â†’ raw/english/localizedstrings/gf.str
maps/mp/gametypes/_gametypes.txt        â†’ raw/maps/mp/gametypes/_gametypes.txt
maps/mp/gametypes/gf.txt               â†’ raw/maps/mp/gametypes/gf.txt
ui_mp/hud_gf.txt                        â†’ raw/ui_mp/hud_gf.txt
ui_mp/hud_gf_health.menu               â†’ raw/ui_mp/hud_gf_health.menu
raw/fx/misc/*.efx                       â†’ raw/fx/misc/*.efx   (FX assets — must be staged or they are silently dropped from the zone)
mod.csv                                 â†’ zone_source/mods/mp_gunfight.csv
mod.csv                                 â†’ zone_source/english/assetinfo/mods/mp_gunfight.csv
mod.csv                                 â†’ zone_source/english/assetlist/mods/mp_gunfight.csv
```

> **assetlist is the one the linker actually reads.** The linker loads its rawfile/asset list from `zone_source/english/assetlist/mods/mp_gunfight.csv` (NOT `assetinfo`). If you only refresh `assetinfo` after changing `mod.csv`, the build silently uses the stale `assetlist` copy. Stage `mod.csv` to **all three** paths above. (`assetinfo` also holds generated `*_dep.txt` / `*_xmodel.csv` from prior builds — leave those; they're not source.)

**Step 2 â€” run linker from `bin/`:**
```
cd “S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740\bin”
linker_pc.exe -language english mods/mp_gunfight
```
**Must run with cwd = `bin/`.** The linker resolves the source CSV via the relative path `../zone_source/...`, so running it from anywhere else fails with `could not open '../zone_source/english/assetlist/mods/mp_gunfight.csv'` even though the file exists. (PowerShell tool: `Set-Location "<game>\bin"` then `& ".\linker_pc.exe" ...`.)
GSC rawfile errors are expected â€” Plutonium loads those directly, they don’t need to be in the zone.
FX image-missing errors for stock T5 materials (e.g. `fxt_ui_tickring`) are harmless â€” those images live in the base game fastfiles and are available at runtime.

**Step 3 â€” copy output back:**
```
zone/english/mods/mp_gunfight.ff  â†’  mods/mp_gunfight/mod.ff  (Plutonium storage)
```

**Gametype UI icon** â€” controlled by the 4th column of the `gf` row in `mp/gametypesTable.csv`.
Available values: `playlist_tdm`, `playlist_ffa`, `playlist_search_destroy`, `playlist_domination`, `playlist_headquarters`, `playlist_demolition`, `playlist_ctf`, `playlist_sabotage`.
Currently set to `playlist_tdm`. Change and rebuild mod.ff to update.

**menufile double-load pitfall** â€” If a `.menu` file is already referenced by a `loadMenu` directive inside another `menufile` (e.g. `hud_gf.txt` loads `hud_gf_health.menu`), do NOT also list it as a separate `menufile` entry in `mod.csv`. The engine registers the menu name twice, which crashes the menu system and makes **all gametypes disappear** from the UI â€” a symptom that looks completely unrelated to the duplicate. Rule: each `.menu` file appears in `mod.csv` exactly once, either as a direct `menufile` OR via a txt loader, never both.

---

## Secrets Handling (RCON password, join password, Plutonium server key)

Secrets never live in a tracked file. Three layers keep them out of git:

1. **Gitignored stores (the values live here, per machine):**
   - **VPS `rcon_password` / `g_password`** → `dedicated.cfg` (gitignored; sole owner on the box).
   - **RCON panel `rcon_password`** → `tools/rcon/secrets.local.json` (gitignored) — a
     `{ "profiles": { "<profile name>": "<rcon_password>" } }` map keyed by the panel's server-dropdown
     name. `server.js` reads/writes it over the loopback-only API (`GET`/`POST /api/secrets`); the panel
     never stores a password in browser localStorage (only host/port land there, in `gf_rcon_profiles`).
     Type the password into the panel once and it saves to this file. Template: `secrets.local.json.example`.
     Keep `rcon_password` ≤23 chars (Plutonium silently ignores longer — see memory `rcon-tool-vps-connect-23char-cap`).
   - **Plutonium server key** → VPS launch config only; it's a platform-issued token (NOT a value you pick),
     so don't reuse it as the RCON password and never put it on a command line (that's how it leaked 2026-07-02).

2. **`.gitignore`** blocks `tools/rcon/secrets.local.json`, `tools/notify/config.json`, `dedicated.cfg`.

3. **Pre-commit guard** `tools/hooks/pre-commit` (tracked). Enabled per-clone with
   `git config core.hooksPath tools/hooks` — **run this once after a fresh clone.** It refuses to commit the
   secret stores (even `git add -f`) and scans staged added-lines for a non-empty `rcon_password`/`g_password`
   value (cfg `set x "v"` and gsc `setDvar("x","v")` forms) or a long `key <token>`. Blank `""` and prose
   mentions are allowed. Bypass a genuine false positive with `git commit --no-verify`.

> History is already public: the old RCON password (commit `43f79da`) and the exposed server key were
> leaked before this setup existed — **rotate both once** (VPS `dedicated.cfg` + platform serverkey page).
> The layers above only prevent *future* leaks; they can't un-leak the old values.

---

## Release & Distribution

> Deployment infra (set up 2026-06-15). Scripts live in `tools/`; their output goes to gitignored `tools/dist/`.

**Plutonium T5 DOES download the server's mod to clients on join — via FastDL (`sv_wwwBaseURL`).** Set up correctly, a joiner auto-fetches `mod.ff` from the server's download host and loads it — no manual install. (The old "NO client-side mod download" claim was a misconfiguration, **corrected 2026-06-29**; see `docs/VPS_DEPLOY.md` for the FastDL setup and the Plutonium-staff confirmation.) Two caveats remain: FastDL ships only the **mod**, not the Plutonium **engine** build, so players keep their launcher updated to match the server; and the server's `mod.ff` and the FastDL-hosted `mod.ff` must be byte-identical (`deploy.ps1 -Mod` updates both together). Manual install still works as a fallback, so the public player package stays useful for that and for offline/local use.

### Two outputs, one minimal public profile
| Output | Content | Built by |
|---|---|---|
| **`main` branch** | Everything: bots (`_bot`/`bots`), RCON (`_gf_bridge`), `_gf_debug`, `tools/`, `.claude/`. The real history — develop here. | — |
| **`release` branch** (GitHub **default**) + **Release zip** | **Same minimal content**: `mod.ff` + the gameplay GSC + `README.md`. No bots/RCON/debug, no `tools/`, no `mod.csv`. Branch = browsable/clonable; zip = download. | `package_release.ps1 -PublishBranch` (branch) / `-Publish` (zip) |

The branch is a force-pushed **orphan single commit** (no history → no binary bloat, `mod.ff` included). The zip is just the archive of the same staged tree, so **branch and zip are byte-identical in content.**

⚠️ Because `release` is the GitHub default branch, a fresh `git clone` lands there (minimal, no `tools/`). **Keep pushing `main`** via `push_all.ps1` — it is the only branch with history/tooling. `git checkout main` after a fresh clone to develop. GitHub Releases are repo-wide/tag-based, independent of the default branch.

### Strip markers
Dev wiring that lives inside *kept* gameplay files is wrapped in markers and removed from the public outputs by `package_release.ps1`:
- `// #strip-begin … // #strip-end` — e.g. the RCON bridge include + bot/RCON init in `gf.gsc`, and the `_gf_debug` include + `gf_debug_*` blocks in `_gf_rounds.gsc`.

Every `#strip-begin … #strip-end` region (marker lines + body) is removed when staging. On `main` the markers are inert `//` comments, so the dev build is unaffected. (The fully dev files — `_bot`, `bots/`, `_gf_bridge`, `_gf_debug` — are excluded by filename via `$DevFiles`.)

### Comment stripping (public GSC)
After the markers are removed, `package_release.ps1`'s `Strip-Comments` strips ALL `//` line and `/* */` block comments from the staged gameplay GSC, so the public source carries no dev notes/TODOs. It is a char-scanning state machine (not regex) so comment markers **inside `"string literals"`** are preserved (e.g. a `"http://"` URL or a `//` inside a printed message); comment-only lines are removed outright while author blank lines are kept (blank runs collapse to one). **Order matters: `Strip-Comments` runs AFTER `Strip-Markers`** — the strip-marker lines are themselves `//` comments but the wiring between them is real code, so stripping comments first would leak the dev body. `main` keeps every comment; only the staged copies are stripped. Pass `-KeepComments` to skip stripping (e.g. when debugging a release build).

### Scripts (`tools/`, ASCII-only so Windows PowerShell 5.1 parses them)
- **`build_ff.ps1`** — build `mod.ff` (stages both zones, cleans `raw/`). Always build via this.
- **`package_release.ps1 [ver] [-PublishBranch] [-Publish] [-SkipBuild] [-KeepComments]`** — bare-bones zip; `-PublishBranch` force-pushes the `release` snapshot; `-Publish` cuts the GitHub Release (tags `release` via `--target`). Staged GSC is marker-stripped AND comment-stripped (see "Comment stripping"); `-KeepComments` keeps comments in the public copy.
- **`package_server.ps1 [ver] [-RotateRcon] [-SanitizeConfig] [-IncludeRconTool]`** — **PRIVATE** VPS bundle. The mod folder is a **complete mirror of `main`** (every `git ls-files` path — all gameplay + dev GSC, `mod.csv`, the UI/strings/csv source, `gf.cfg`, `notes/`, `tools/` incl. the RCON panel, `.claude/`, README, ...) **plus the compiled `mod.ff`** (gitignored, added explicitly). This is the deliberate inverse of `package_release.ps1`, which ships only a stripped public subset — the server gets *everything from main*. The file set is git-driven, so gitignored junk (`tools/dist`, logs, `raw/`, the real `dedicated.cfg`) is auto-excluded and there is no hand-maintained include list to keep in sync. Bundle also carries `dedicated.cfg` (carries `rcon_password` — never publish) + `DEPLOY.txt`. Extract into the Plutonium `t5/` storage dir. `-RotateRcon` injects a fresh cryptographically-random `rcon_password` into the bundled cfg **only** (source cfg untouched) and prints it to the console — so the live password is never the one in git history; deploy the bundle, then paste the printed value into your RCON client. Takes precedence over `-SanitizeConfig`.
- **`push_all.ps1 ["msg"]`** — stage/commit/push the current branch.
- **`deploy.ps1 [-Mod] [-Web] [-DryRun] [-NoPull] [-NoRestart] [-ModDest ..] [-WebDest ..]`** —
  **runs ON the VPS**, inside the deploy clone (e.g. `C:\gfdeploy\BO1-Gunfight`), as the account
  that RUNS the game server — on the current VPS that is **Administrator** (confirmed 2026-07-02
  via the bootstrapper process owner; no `gfsvc` account exists — the runbook's low-priv `gfsvc`
  is aspirational hardening). A wrong-account deploy SILENTLY mirrors into that account's own
  `$env:LOCALAPPDATA` Plutonium storage while the server keeps loading old files (this exact
  failure shipped stale GSC once). The git-pull deploy applier (full flow in `docs/VPS_DEPLOY.md`
  Phase 11). `-Web` git-pulls,
  secret-scans `site/wwwroot/` (hard-fails on `rcon_password` / the leaked literal / secret-
  assignment patterns), then robocopy `/MIR`s it into `C:\inetpub\wwwroot` — preserving the
  VPS-owned hardened `web.config` (excluded from the mirror unless the repo tracks one); no
  restart. `-Mod` git-pulls `main`, checks `mod.ff` out of the `release` branch (it is a gitignored
  binary on `main`), mirrors the tracked tree + `mod.ff` into the Plutonium mods folder, then
  restarts the server (`taskkill` the bootstrapper → the restart-loop bat relaunches it under
  the server account). Never touches the live `dedicated.cfg` (it lives in `storage\t5\`, not the
  mod folder).
  Refuses the mod mirror if `-ModDest` doesn't contain `mp_gunfight` (anti-typo guard). `-DryRun`
  passes robocopy `/L` to preview. This is the **inverse direction** of the packagers: they build
  artifacts; `deploy.ps1` applies a git-pulled checkout in place on the box.

---

## Project Overview

Custom Gunfight game mode for Black Ops 1 running on Plutonium T5 MP.

**Load:** `loadMod mp_gunfight` in the Plutonium console, then `map_restart`.
**Mod folder must be prefixed `mp_`** for it to appear in the in-game mod menu.

```
mp_gunfight/  (GitHub: KL9modz/BO1-Gunfight)
  .claude/CLAUDE.md                  <- this file (project instructions)
  README.md                          <- dev README (release README is generated by the packager)
  mod.csv                            <- build manifest: zone-source list the linker reads
  mp/gametypesTable.csv              <- registers the 'gf' gametype row in the UI
  localizedstrings/gf.str            <- localized UI strings (titles, popups)
  ui_mp/
    hud_gf.txt                       <- menufile loader (loadMenu hud_gf_health.menu)
    hud_gf_health.menu               <- ALL mod HUD: health panel + loadout overview + self bar
  maps/mp/gametypes/
    gf.gsc                           <- ENTRY POINT: main(), callbacks, precache, spawn pipeline
    _gf_rounds.gsc                   <- round lifecycle, overtime, damage/score, team-size mode
    _gf_loadouts.gsc                 <- loadout pool, shuffle, give, camo randomizer
    _gf_hud.gsc                      <- health panel + loadout overview + score popup (menu-driven)
    _gf_locations.gsc                <- per-map curated spawns + overtime flag points
    _gf_wager_zones.gsc              <- wager compass material + map-specific zone helpers
    _gf_debug.gsc        (dev only)  <- spawn recorder + entity dump (stripped from public)
    _gf_bridge.gsc       (dev only)  <- RCON web-tool bridge   (stripped from public)
    _bot.gsc             (dev only)  <- bot integration        (stripped from public)
  maps/mp/bots/          (dev only)  <- vendored bot framework: _bot_loadout/_bot_script/_bot_utility
  raw/fx/misc/*.efx                  <- custom overtime apron FX (white halo; gold/red use stock FX)
  site/wwwroot/                      <- PUBLIC website source (gunfight.us); static HTML/CSS/JS,
                                        mirrored to IIS by tools/deploy.ps1 -Web. NOT the RCON panel.
  tools/                 (dev only)  <- build_ff.ps1, package_release.ps1, package_server.ps1,
                                        push_all.ps1, deploy.ps1 (VPS-side git-pull applier)
  tools/rcon/            (dev only)  <- PRIVATE loopback-only RCON admin panel (never web-deployed)
```

> Entry point is `gf.gsc::main()` (NOT `mp_gunfight.gsc` — that file does not exist). There
> is no `_gf_tests.gsc`, `mp_spawn_fix.gsc`, or `zm_spawn_fix.gsc`. The `(dev only)` files
> are excluded from public release outputs by `package_release.ps1` (see "Release & Distribution").

---

## T5 GSC â€” Critical API Differences from T6/T7

These are confirmed-broken functions in T5 mod scripts and their correct replacements:

| Broken in T5 mods | Correct T5 replacement |
|---|---|
| `getPlayers()` | `level.players` (engine array, always available) |
| `spawnStruct()` | Associative array: `s = []; s["key"] = val;` |
| `player isAlive()` (method) | `player.health > 0` |
| `isAlive(player)` (standalone) | `player.health > 0` |
| `player.team` | `player.pers["team"]` â†’ returns `"allies"`, `"axis"`, or `"spectator"` |
| `setDvar("scr_player_healthregentime", "0")` | `setDvar("scr_player_healthregentime", "0")` DOES work â€” set it before `_healthoverlay::init()` threads so the engine reads 0 and disables regen itself |
| `level.onGiveLoadout = ::fn` | Does not exist in T5. Two hooks do the job: (1) `level.giveCustomLoadout = ::gf_giveCustomLoadout` is the actual loadout-delivery hook — `_class::giveLoadout` calls it, so weapons/perks are given there (no `takeAllWeapons`-after-spawn race). (2) `level.playerSpawnedCB = ::gf_playerSpawnedCB` handles player lifecycle: it fires `level notify("spawned_player")` to keep SD happy, then threads `gf_onSpawned()` / the health HUD |

**Compile error diagnosis:** When T5 throws `unknown function: @ scripts/mp/<file>::<func>`, the broken call is INSIDE the named function â€” scan every call within it for T5 compatibility.

**Cross-file calls require `#include`:** Each `.gsc` file must `#include` every other mod script whose functions it calls **directly**. T5 does **not** support transitive includes â€” if A includes B which includes C, A cannot call functions from C. Each file must have its own explicit `#include` for every file it calls into. Missing include â†’ `unknown function` compile error on the calling function. Current include graph (each file `#include`s what it calls directly):
- `gf.gsc` -> `_gf_locations`, `_gf_rounds`, `_gf_loadouts`, `_gf_wager_zones` (+ `_gf_bridge` dev) + stock `_utility`/`_hud_util`
- `_gf_rounds.gsc` -> `_gf_hud` (+ `_gf_debug` dev) + stock `_hud_util`
- `_gf_loadouts.gsc` -> `_gf_hud`
- `_gf_hud.gsc` -> stock `_hud_util`

---

## T5 Engine Reference

### SD callbacks registered in `sd.gsc::main()`
| Level var | Fires when |
|---|---|
| `level.playerSpawnedCB` | Player spawns â†’ fires `level notify("spawned_player")` |
| `level.onPlayerKilled` | Player dies |
| `level.onDeadEvent(team)` | A team is fully eliminated |
| `level.onOneLeftEvent(team)` | Last player alive on a team |
| `level.onTimeLimit` | Round timer expires â†’ defenders win |
| `level.onRoundSwitch` | Halftime / side swap |
| `level.onRoundEndGame` | Returns overall round winner string |

### SD state vars
- `game["attackers"]` / `game["defenders"]` â€” team role assignment
- `level.aliveCount[team]` â€” engine-maintained alive count per team
- `game["roundswon"]["allies"]` / `game["roundswon"]["axis"]` â€” round wins
- `game["roundsplayed"]` â€” rounds played so far

### Overridable callbacks (set in `_globallogic.gsc::SetupCallbacks()`)
```
level.onSpawnPlayer          // fires after player spawns into world
level.playerSpawnedCB        // fires after spawn (SD sets this to notify "spawned_player")
level.onPlayerKilled         // fires on kill
level.onDeadEvent(team)      // fires when a whole team is eliminated
level.onOneLeftEvent(team)   // fires when last player on team is alive
level.onTimeLimit            // fires when round clock hits 0
level.onRoundSwitch          // fires at halftime / side swap
level.onRoundEndGame         // should return winner string "allies"/"axis"/"tie"
level.giveCustomLoadout      // called BY _class::giveLoadout to deliver the loadout (gf = ::gf_giveCustomLoadout). NOTE: level.onGiveLoadout does NOT exist in T5 — this is the real hook
level.spawnClient            // queues/delays client spawn; default: _globallogic_spawn::spawnClient
level.spawnPlayer            // puts player into world; default: _globallogic_spawn::spawnPlayer
level._setTeamScore          // set team score directly (default updates game["teamScores"])
level._getTeamScore          // read team score (default returns game["teamScores"][team])
```

### Spawn pipeline (what happens inside `spawnPlayer()`)
Order of operations every time a player spawns:
1. `setSpawnVariables()` â€” sets player origin, angles, team, sessionstate = "playing"
2. `[[level.onSpawnPlayer]]()` â€” SD's callback; sets `isBombCarrier = false`, selects spawnpoint, calls `self spawn(...)`
3. `[[level.playerSpawnedCB]]()` â€” SD fires `level notify("spawned_player")` here â† our waittill
4. `maps\mp\gametypes\_class::setClass(self.class)` â€” sets perk state
5. `maps\mp\gametypes\_class::giveLoadout(team, class)` â€” builds the default class, then calls `[[level.giveCustomLoadout]]()` = **our `gf_giveCustomLoadout`**, which `setupBlankRandomPlayer` (clears) and gives the gunfight primary/secondary/knife/lethal/tactical/equipment + perks + threads the loadout HUD

The gunfight loadout is delivered *inside* `giveLoadout` via the `level.giveCustomLoadout` hook (step 5) â€” there is no separate `waittill("spawned_player")` + `takeAllWeapons` overwrite thread. `gf_playerSpawnedCB` (step 3, via `playerSpawnedCB`) only handles lifecycle: it fires `spawned_player`, seeds damage/capture score, and threads the health HUD.

### Key game state vars
```gsc
game["state"]                 // "playing" | "postgame"
game["attackers"]             // team string of attacking team in SD
game["defenders"]             // team string of defending team
game["roundswon"]["allies"]   // rounds won by allies
game["roundswon"]["axis"]     // rounds won by axis
game["roundsplayed"]          // total rounds completed
level.gameEnded               // bool â€” set true when endGame() is called
level.inGracePeriod           // bool â€” grace period blocks deaths/forfeits
level.inOvertime              // bool â€” setting true blocks new spawns automatically
level.aliveCount["allies"]    // engine-maintained alive player count (updated by updateTeamStatus)
level.aliveCount["axis"]
level.alivePlayers["allies"]  // array of alive player entities
level.alivePlayers["axis"]
level.playerCount["allies"]   // total connected players per team (alive + dead)
```

### Ending a round / game
```gsc
// SD's wrapper â€” increments winning team score by 1, then ends round/game:
sd_endGame( winningTeam, endReasonText )

// Core engine function â€” use for our own endgame calls if not going through SD:
maps\mp\gametypes\_globallogic::endGame( winningTeam, endReasonText )

// Direct team score manipulation:
[[level._setTeamScore]]( "allies", newScore )
[[level._getTeamScore]]( "allies" )
```

### SD round cycling â€” confirmed working pattern

**`maps\mp\gametypes\sd::sd_endGame( winner, "" )`** â€” confirmed callable from mod scripts in Plutonium T5.

Calling this from `onDeadEvent` or a custom timer handler:
- Increments `game["roundswon"][winner]` by 1 and updates the scoreboard
- Checks `hitRoundWinLimit()` â€” ends the match if reached, otherwise cycles the round
- SD handles intermission display, player respawn, and the next prematch automatically
- No manual `pers["lives"]` reset needed â€” SD handles it
- No manual `[[level.spawnClient]]()` calls needed **between rounds** â€” SD handles respawning. But `gf_bypassClassChoice` must call it for the initial connect spawn (see class select suppression section).

The 0.2s wait is a brief spawn-protection window (PvP blocked via `!gf_roundActive` in damage handler). `gf_timerEnd` is set before the wait so the HUD countdown shows immediately on spawn. `gf_roundEnding` must be explicitly cleared here â€” SD never resets it.

### Timer control
```gsc
maps\mp\gametypes\_globallogic_utils::pauseTimer()   // stops round clock
maps\mp\gametypes\_globallogic_utils::resumeTimer()  // resumes round clock
// Useful for overtime: pause clock, wait for zone capture, then end round
```

### Score events
```gsc
maps\mp\gametypes\_globallogic_score::givePlayerScore( "kill", player )
// Recognized events: "kill", "headshot", "assist", "assist_25/50/75",
//                    "plant", "defuse", "win", "loss", "tie"
```

### Useful T5 utility functions (maps\mp\_utility)
```gsc
getOtherTeam( team )               // "allies"<->"axis"
getRoundsWon( team )               // game["roundswon"][team]
getRoundsPlayed()                  // game["roundsplayed"]
hitRoundWinLimit()                 // true if any team hit level.roundWinLimit
playSoundOnPlayers( sound, team )  // plays local sound to all players on team
dvarIntValue( name, def, min, max )  // reads scr_sd_<name>, sets default if unset
```

### Engine callbacks â€” full list
Registered by `_callbacksetup.gsc`. These engine events call into GSC:
```
CodeCallback_StartGameType()     game init â€” calls sd.gsc::main()
CodeCallback_PlayerConnect()     player joins server
CodeCallback_PlayerDisconnect()  player leaves
CodeCallback_PlayerDamage()      damage event (before health change)
CodeCallback_PlayerKilled()      death event
CodeCallback_ActorDamage()       NPC damage
CodeCallback_ActorKilled()       NPC death
CodeCallback_VehicleDamage()     vehicle hit
CodeCallback_HostMigration()     host migration
CodeCallback_GlassSmash()        glass break FX
```

### Critical gotchas
- **`updateTeamStatus()` runs async** (waittillframeend) â€” `level.aliveCount` may be one frame stale after a kill
- **`level.inGracePeriod = true` blocks forfeit/dead-event checks** â€” clear it before main gameplay starts
- **`level.inOvertime = true` prevents all new spawns** â€” useful for overtime zone capture
- **`map_restart(true)`** keeps player positions but resets entities AND `level.*` vars; `false` = full restart. `self.pers[]` and `game[]` are the only things that survive. Do not rely on `level.*` state across a `map_restart`.
- **`self.pers[]` persists across rounds** â€” player stats, team, class survive `map_restart`
- **`scr_disable_cac = 1`** makes `beginClassChoice` auto-assign `level.defaultClass = "CLASS_ASSAULT"` and auto-spawn
- **SD's `onDeadEvent`** checks `level.bombPlanted` before deciding winner â€” our override must handle this or replicate the logic

---

## T5 HUD System

### ⚠️ The per-client DRAWN render cap — the real HUD limit (learned 2026-06-14)

T5 has **two separate** client-HUD limits, and only the harmless one is measurable:
- **Allocation pool** — `newClientHudElem` succeeds until ~900+ used (global, ~1024 total). Measured `free=903`. NOT the constraint.
- **Per-client DRAWN/render cap (~17–20)** — the engine only actually *draws* ~17–20 client hudelems per player. Beyond that the overflow **silently does not render**, even though allocation succeeds AND the element's `.alpha`/`.x` are set. **No script probe can detect this** (allocation says "tons free"; reading `.alpha` looks healthy) — only the human eye sees it. It also has a **global component**, so it scales with lobby size: a *late-created* element (e.g. the kill popup) draws fine at 2 players and silently vanishes as the lobby grows.

**Symptom:** the last-created elements silently disappear (enemy HP row dropped when the panel hit 21 elems; kill popup vanished in bigger lobbies). Creation order matters — late elements drop first.

The cap is **global across ALL hudelem types** (our stuff + stock ammo/compass HUD + score popup + overtime flag objpoint all share it), and proven so: with the panel at 17 client hudelems, the kill popup AND the flag icon were invisible during play and only appeared when the round-end teardown freed slots. So "17 for us" was wrong — 17 is most of the *whole* per-client budget.

**Mitigation — move EVERYTHING mod-owned off client hudelems into the MENU layer** (`ui_mp/hud_gf_health.menu`), a separate rendering system with no such cap (0 client hudelems). Server pushes state via `setClientDvar` only on change; menu itemDefs read the dvars (`exp rect X/Y`, `exp rect W`, `exp forecolor A`, `exp material(dvarString())`, `visible when(...)` — `when` supports `>`/`<=`/`&&`, not just `==`). All mod HUD is now menu-rendered → **~0 client hudelems**:
- **Team health panel** (2026-06-15; 6v6 readout 2026-07-03) — bg fade + 8 skulls (shown while a team has `<=4`) OR 2 `alive / total` readouts (shown when a team has `>4`, e.g. 6v6) + 2 bars + 2 numbers. Dvars: `ui_gf_panel_x/y` (anchor), `ui_gf_hp_alpha` (reveal fade), `ui_gf_rN_hp/_fw/_cnt/_alive/_alivecount` (row N=0 friendly/1 enemy), `ui_gf_skull_mat`/`ui_gf_fade_mat` (material names). GSC `gf_pushHealthRow`/`gf_setRowDvar` (real, unclamped counts — the menu owns the 4-skull cap via a per-skull `cnt<=4` gate; the readout appears via `cnt>4`, so small mode / 4v4 is byte-identical). Skulls = alive(team-colour)+dead(white) itemDef per slot (forecolor R/G/B isn't exp-drivable, only A). Materials MUST be dynamic `exp material(dvarString())` — static `background "hud_..."` makes the linker try to bundle the .iwi (missing → build error).
- **Self health bar** (`ui_gf_self_*`), **Loadout overview** (`ui_gf_lo_*`), **Team-panel border** (`ui_gf_panel_*`).
- **Kill popup** "Elimination"/"Assist" — reuses the ENGINE's score popup element `self.hud_rankscroreupdate` (`NewScoreHudElem`, created by `_rank` at spawn) for the exact stock yellow look (font/glow/fontPulse); `gf_showScorePopup` `setText`'s it. Still counts in the global cap, but there's room now that the panel is off the pool. (Dormant `ui_gf_popup_*` menu items remain from an earlier attempt — unused.)

- **Stock "+N" XP popups suppressed via `self.enableText = false` per spawn** (gf_playerSpawnedCB, added 2026-07-01) - the stock gate on `_rank::giveRankXP`'s popup push to the SHARED `hud_rankscroreupdate` element; `_persistence` re-sets it true on every connect/map_restart, hence per-spawn. Needed because medals (First Blood), challenges, and stat milestones pass EXPLICIT XP values that bypass our zeroed kill/assist score info - a ranked-server-only symptom (giveRankXP early-returns unranked), where they raced/replaced our Elimination/Assist popup. XP itself still accrues (incRankXP precedes the gate).

`gf_debug_hud_pool` overlay shows `DRAWN: N/17` (now ~0 for mod HUD). Menu *structure* changes need a `mod.ff` rebuild; dvar values/positions are GSC-tunable (no rebuild). **Always build with `tools/build_ff.ps1`** (stages both zones + cleans `raw/`); a leftover staged `.menu` in `raw/` double-loads and kills the gametype UI. See memory `settext-configstring-exhaustion` + `build-stage-transitive-menu`.

### Server-side HUD (reference — NOT the current health/loadout approach)

Both the Loadout HUD and Health HUD use `newTeamHudElem(team)` (server-side elements) so one element pair per team covers the full lobby without consuming per-player client pool slots.

**Key APIs:**
- `createServerIcon(shader, w, h, team)` — icon visible to `team` ("allies" or "axis")
- `createServerFontString(font, scale, team)` — text visible to `team`
- `createServerBar(color, w, h, flashFrac, team)` — progress bar visible to `team`
- All three live in `maps\mp\gametypes\_hud_util.gsc`. With `#include maps\mp\gametypes\_hud_util` they're callable directly (no namespace prefix needed).
- Can be called from a **level-thread** context because with `team` provided they never touch `self`.

**What changed vs client-side:**
- `gf_startHealthHUD()` — level-scope; callers changed to `level thread gf_startHealthHUD()` with no bot guard. Spectator spawn no longer restarts the HUD.
- `gf_showWeaponHUD(load)` — level-scope; caller changed to `level thread gf_showWeaponHUD(load)`.
- `gf_destroyLoadoutHUD()` / `gf_destroyHealthHUD()` — use `level.gf_loadoutHudElems` / `level.gf_healthHud` instead of `self.*`.
- Two sets of health HUD elements are created per round: one for allies viewers (allies=green row 0, axis=red row 1) and one for axis viewers (reversed). `gf_updateHealthHUD()` updates both.

**To revert to client-side:** See the comment block at the top of `_gf_hud.gsc` for a step-by-step reverting guide.

**Server-side font string sizing — confirmed working pattern:**
```gsc
elem = createServerFontString( "default", 1.4, team );
elem setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
gf_styleHealthElem( elem, sort );   // sets sort, foreground, hidewheninmenu, etc.
elem.alpha = 0;
```
- `fontscale` is a multiplier on the font's **native rasterization size**, NOT a pixel height cap. Small values on large-native fonts (like `"bigfixed"`) still render huge and pixelated.
- **`"default"` at `1.4`** is the correct combination for small readable UI text — confirmed working in both the health HUD HP numbers and the loadout weapon name labels.
- **`"bigfixed"` at any scale ≤ 1.0 is unusable** — renders oversized and aliased because bigfixed has a very large native raster size.
- Do NOT add a redundant `elem.fontScale = X` line after `createServerFontString` — the fontscale is already set internally.
- Server-side text elements (`newTeamHudElem`) always render **above** client elements (`newClientHudElem`) regardless of sort values. If text must appear on top of server bars, make it a server element too and give it a higher sort number (e.g., bar frame = sort 42, icons = sort 45, HP text = sort 46).

---

All HUD elements created with `newClientHudElem(player)`.

**Coordinate system:**
- `horzAlign="left"`, `vertAlign="top"` â†’ x/y are pixel offsets from screen top-left corner
- `horzAlign="left"`, `vertAlign="middle"` â†’ y is vertical center of element (element straddles y)
- `alignX` / `alignY` control which edge/center of the element the x/y coordinate refers to

**Colored rectangles (health bars, backgrounds):**
```gsc
e = newClientHudElem(player);
e.horzAlign = "left";
e.vertAlign = "top";
e.alignX    = "left";
e.alignY    = "middle";
e.x         = 10;
e.y         = 145;   // vertical center of the rect
e.color     = (0.3, 0.55, 1);
e.alpha     = 0.9;
e.sort      = 2;     // draw order (higher = on top)
e setShader("white", 68, 5);  // width=68px, height=5px
```

**To resize a bar:** `e setShader("white", newWidth, height)` â€” call each update tick.
Use `"progress_bar_fill"` / `"progress_bar_bg"` instead of `"white"` for native-styled bars.

**Text elements:** set `e.font = "smallfixed"` and `e.fontScale = 1.0`, then `e setText("string")`.

**Timer:** `e setTimerUp(0)` starts counting up from 0. Engine-driven, no script polling needed.

**Persistent HUD pattern:** Create elements once after first `spawned_player`, update every 0.2s in a loop, never destroy/rebuild mid-session. Destroy on `disconnect`.

### Better HUD creation functions (_hud_util.gsc)
These are cleaner than raw `newClientHudElem` + `setShader`:
```gsc
createFontString( font, fontScale )              // text element
createIcon( shader, width, height )              // icon element
createBar( color, width, height )                // colored bar (wraps setShader)
createPrimaryProgressBar()                       // game-styled primary progress bar
createSecondaryProgressBar()                     // game-styled secondary progress bar
createServerFontString( font, fontScale, team )  // server-side (all players see same)
createServerIcon( shader, width, height, team )
createServerBar( color, width, height, flashFrac, team )
```
Font strings: `"default"`, `"bigfixed"`, `"smallfixed"`, `"objective"`, `"extrabig"`

### HUD transition helpers (from IW5/T5 `_hud_util.gsc`)
These are wrapper methods on HUD elements â€” call on an element created with `createIcon` / `createFontString`:
```gsc
e transitionSlideIn( duration, direction );   // direction: "left", "right", "up", "down"
e transitionSlideOut( duration, direction );
e hideElem();        // sets alpha=0, non-interactive
e showElem();        // restores alpha
e updateBar( fraction );     // resizes bar to fraction [0.0 - 1.0] of its max width
e setFlashFrac( fraction );  // sets flash threshold on a progress bar (flashes below fraction)
```
These assume elements were created with `createBar`/`createIcon` which store `.baseWidth` etc. as properties on the element. Raw `newClientHudElem` elements won't have those properties; use `createBar` / `createIcon` instead.

### HUD element types
```gsc
hud = newHudElem( player );          // server-side, general purpose
hud = newClientHudElem( player );    // client-side only
hud = NewScoreHudElem( player );     // score-specific HUD element
```
`hud.archived = false` â€” prevents HUD from being hidden during menus or demo playback.

### HUD animations
```gsc
hud fadeOverTime( 0.3 );       // fade alpha over time
hud moveOverTime( 0.2 );       // smooth position transition (set .x/.y after)
hud.alpha = 0;                 // set target alpha after fadeOverTime
hud.x = 100; hud.y = 50;      // set target pos after moveOverTime

// Font glow
hud.glowAlpha = 1;
hud.glowColor = ( r/255, g/255, b/255 );

// Pulse (score pop)
hud fontPulse( player );       // brief scale-up pop effect
```

### Standard properties for live-round HUD elements
```gsc
e.archived       = false;   // don't hide during menus / demo playback
e.hidewheninmenu = true;    // hide during pause menu
e.glowColor      = ( 1, 0.3, 0 );
e.glowAlpha      = 0.5;
```

---

## T5 Asset Reference

### Weapons

**giveWeapon arguments**
`GiveWeapon( weaponName )` â€” basic form.
`GiveWeapon( weaponName, dualWield )` â€” `dualWield` is a **boolean**, NOT a camo number.
- `true` gives the akimbo/dualwield variant
- `false` (or omit) gives the single variant
- **T6 uses a 3rd camo-number arg; T5 does not** â€” passing a number here may crash or be silently ignored

To give a weapon with an embedded attachment, use the `_attachment_` naming pattern:
```gsc
self GiveWeapon( "famas_reflex_mp" );   // attachment baked into weapon name
self GiveWeapon( "python_speed_mp" );   // _speed_ is speed-draw holster variant
```
Common attachments: `acog_mp`, `reflex_mp`, `silencer_mp`, `dualwield_mp`, `grip_mp`, `masterkey_mp`, `flamethrower_mp`

### Perks

Pass these strings to `self SetPerk(name)` / check with `self hasPerk(name)`.

```
specialty_bulletaccuracy     Steady Aim
specialty_movefaster         Lightweight
specialty_holdbreath         Scout
specialty_fastreload         Sleight of Hand
specialty_gpsjammer          Ghost
specialty_detectexplosive    Hacker
specialty_bulletpenetration  Deep Impact
specialty_quieter            Ninja
specialty_pistoldeath        Second Chance
specialty_gas_mask           Tactical Mask
specialty_twoattach          Warlord / Professional
specialty_extraammo          Extra Ammo
specialty_killstreak         Hardline
specialty_longersprint       Marathon
specialty_scavenger          Scavenger
specialty_armorvest          Flak Jacket
specialty_blindeye           Cold Blooded
specialty_sprintrecovery     Extreme Conditioning
```

Additional perks confirmed from T5 source (weapons.txt):
```
specialty_twogrenades        Two grenades (extra grenade slot)
specialty_twoprimaries       Two primary weapons (warlord tier)
specialty_rof                Increased rate of fire
specialty_stunprotection     Reduced stun effect duration
specialty_nomotionsensor     Not visible on motion sensor
specialty_loudenemies        Hear enemies more clearly
specialty_showenemyequipment Show enemy equipment on minimap
specialty_showonradar        Show player on enemy radar (negative perk use)
specialty_shellshock         Shellshock effect on nearby explosions
specialty_nottargetedbyai    Not targeted by AI turrets/dogs
specialty_noname             Unnamed perk slot (test before using)
```

### HUD Shaders

**Weapon & lethal icon shaders** â€” confirmed from Xinerki `t5-gunfight/duel.gsc` (T5 gametype mod).

Default rule: `"menu_mp_weapons_" + baseName` where baseName has no `_mp` and no variant suffix.

Special cases (base name doesn't match shader):
```
Weapon base name          Shader
ithaca_grip             -> menu_mp_weapons_ithaca
stoner63                -> menu_mp_weapons_stoner63a
crossbow_explosive      -> menu_mp_weapons_crossbow
minigun_wager           -> menu_mp_weapons_minigun
python_speed            -> menu_mp_weapons_python
m1911_upgradesight      -> menu_mp_weapons_colt
makarov_upgradesight    -> menu_mp_weapons_makarov
cz75_upgradesight       -> menu_mp_weapons_cz75
Default secondary: "menu_mp_weapons_" + base (strip suffix like _speed, _upgradesight)
```

Lethal icon shaders:
```
frag_grenade            -> hud_grenadeicon
satchel_charge_mp       -> hud_icon_satchelcharge   (confirmed from weapon def file hudIcon field; NOT in loose IWDs â€” compiled into .ff zone; hud_sticky_grenade / hud_satchelcharge both wrong)
sticky_grenade          -> hud_icon_sticky_grenade
hatchet                 -> hud_hatchet
Default: "hud_" + baseName
```

Tactical grenade icon shaders â€” confirmed from IWD `images/*.iwi` listing:
```
flash_grenade_mp       -> hud_us_flashgrenade
concussion_grenade_mp  -> hud_us_stungrenade
smoke_grenade_mp       -> hud_us_smokegrenade
```
Pattern: `hud_us_` prefix (NOT `hud_` directly).

Precaching before use:
```gsc
PreCacheShader( "menu_mp_weapons_famas" );   // call at match start before HUD creation
e setShader( "menu_mp_weapons_famas", 64, 32 );
```

**Named shaders (precached by T5 â€” usable in setShader / createIcon)**
```
Progress bars:    progress_bar_bg, progress_bar_fill, progress_bar_fg
Score bars:       score_bar_bg, score_bar_allies, score_bar_opfor
Waypoints:        waypoint_bomb, waypoint_kill, waypoint_capture, waypoint_defend
                  waypoint_defuse, waypoint_target, waypoint_second_chance
Compass:          compass_waypoint_bomb, compass_waypoint_capture, compass_waypoint_defend
HUD:              hud_suitcase_bomb, hud_momentum, hud_scavenger_pickup
Factions:         faction_128_marines, faction_128_nva, faction_128_spetsnaz
Emblems:          composite_emblem_team_allies, composite_emblem_team_axis
Generic:          white, black
```

`score_bar_allies` / `score_bar_opfor` are particularly useful â€” native styled team HP/score bars the game uses internally.

### Audio

**Sound playback**
```gsc
self playLocalSound( alias )                           // plays to this player only
maps\mp\_utility::playSoundOnPlayers( alias, team )   // plays to whole team (or all if team undefined)
play_sound_in_space( alias, origin )                   // positional 3D sound
```

**leaderDialog (voice callouts)**
```gsc
maps\mp\gametypes\_globallogic_audio::leaderDialog( dialogKey )
maps\mp\gametypes\_globallogic_audio::leaderDialog( dialogKey, team )
```
Available dialog keys (set via `game["dialog"][key]`):
```
"gametype"       mode intro VO
"last_one"       last player alive warning
"halftime"       halftime VO
"round_success"  encourage_win
"round_failure"  encourage_lost
"winning"        winning
"losing"         losing
"timesup"        timesup
"challenge"      challengecomplete
```

**Music states**
```gsc
maps\mp\gametypes\_globallogic_audio::set_music_on_team( state, team )
```
```
"MP_LAST_STAND"          last-alive suspense
"TIME_OUT"               bomb countdown
"CTF_WE_TAKE"            friendly picks up object
"CTF_THEY_TAKE"          enemy picks up object
"SILENT"                 mute music
```

**Dynamic music**
```gsc
actionMusicSet( "state_name" );   // triggers music state (e.g. "round_end_win", "combat")
```

### Classes & Menus

**Class name constants**
```
CLASS_ASSAULT    CLASS_SMG       CLASS_CQB
CLASS_LMG        CLASS_SNIPER
OFFLINE_CLASS1 ... OFFLINE_CLASS10    (offline preset classes)
CLASS_CUSTOM1  ... CLASS_CUSTOM5      (online custom classes)
CLASS_CUSTOM6  ... CLASS_CUSTOM10     (prestige custom slots)
```
`level.defaultClass = "CLASS_ASSAULT"` (set in _class.gsc init)

**Menu name constants (game["menu_*"])**
```
game["menu_team"]                  = "team_marinesopfor"
game["menu_class_allies"]          = "class_marines"
game["menu_class_axis"]            = "class_opfor"
game["menu_changeclass_allies"]    = "changeclass"
game["menu_changeclass_axis"]      = "changeclass"
game["menu_changeclass_custom"]    = "changeclass_custom"
game["menu_changeclass_barebones"] = "changeclass_barebones"
```

### DVARs

Useful dvars for Gunfight (from dvarlist.txt):
```
compass         "0" / "1"       show/hide the minimap compass
compassSize     integer         minimap size in pixels (0 = hidden)
cg_fov          float           field of view (default 65)
bg_gravity      float           gravity (default 800)
set scr_game_prematchperiod	15
```
Set via `setDvar( name, value )` in `init()`. `compass "0"` resolves the minimap-disable TODO.
reset bg_ladder_yawcap
reset bg_maxGrenadeIndicatorSpeed
reset bg_prone_yawcap
reset mantle_check_range
reset jump_spreadAdd
reset player_adsExitDelay
reset player_runbkThreshhold
reset player_sprintCameraBob
reset player_sprintStrafeSpeedScale 
reset player_sprintThreshhold
reset bg_fallDamageMaxHeight
reset bg_fallDamageMinHeight
reset bg_viewBobMax
reset com_timescale
reset friction
reset g_synchronousClients
reset jump_height
reset jump_ladderPushVel
reset jump_slowdownEnable
reset mantle_check_radius
reset mantle_check_angle
reset mantle_enable
reset player_backSpeedScale
reset player_breath_fire_delay
reset player_breath_gasp_lerp
reset player_breath_gasp_scale
reset player_breath_gasp_time
reset player_breath_hold_lerp
reset player_breath_hold_time
reset player_dmgtimer_minScale
reset player_footstepsThreshhold
reset player_scopeExitOnDamage
reset player_sprintForwardMinimum
reset player_sprintMinTime
reset player_sprintRechargePause
reset player_sprintSpeedScale
reset player_sprintTime
reset player_sprintUnlimited
reset player_strafeSpeedScale
reset player_view_pitch_down
reset player_view_pitch_up
reset sv_clientSideBullets
reset timescale
set scr_disable_cac 0
set scr_disable_weapondrop 0
set actionslotshide 0
set ammoCounterHide 0
set player_sprintUnlimited 0
if ( dvarInt( ui_multiplayer ) == 1 ) exec "reset_bindings.cfg"
set ui_selectlobby 0

// oldschool dvars set in script
reset ragdoll_explode_force
reset ragdoll_explode_upbias

reset jump_height
reset jump_slowdownEnable
reset bg_fallDamageMinHeight
reset bg_fallDamageMaxHeight
// end oldschool dvars set in script

// wager-zone blockers are preserved via _gameobjects allow-list, not wager dvars
---

## T5 Spawn System

### Getting spawn points
```gsc
maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_attacker" )
maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_defender" )
maps\mp\gametypes\_spawnlogic::getSpawnpoint_Random( spawnPoints )
maps\mp\gametypes\_spawnlogic::getRandomIntermissionPoint()
```
SD uses `mp_sd_spawn_attacker` (allies) and `mp_sd_spawn_defender` (axis) classnames.

### Spawn influencer types (for custom spawn bias)
```gsc
// Push enemies away from a position (e.g. stop spawning behind a zone):
maps\mp\gametypes\_spawning::addSpawnInfluencer( origin, radius, weight, influencerType, teamMask )
```
Influencer types: `eINFLUENCER_TYPE_NORMAL`(0), `eINFLUENCER_TYPE_PLAYER`(1), `eINFLUENCER_TYPE_GAME_MODE`(6)
Team masks: `iSPAWN_TEAMMASK_ALLIES`(4), `iSPAWN_TEAMMASK_AXIS`(2)

Spawn point weighting (from community mods):
```gsc
addSphereInfluencer( origin, radius, weight );
// weight > 0 attracts spawns; weight < 0 repels
```

---

## T5 Game Objects â€” Overtime Zone

For implementing an overtime capture zone (`_gameobjects.gsc`):
```gsc
// Create a zone players must stand in (like a koth hill or overtime zone):
zone = maps\mp\gametypes\_gameobjects::createUseObject( ownerTeam, trigger, visuals, offset );
zone maps\mp\gametypes\_gameobjects::allowUse( "enemy" );    // "friendly", "enemy", "any", "none"
zone maps\mp\gametypes\_gameobjects::setUseTime( seconds );  // how long to capture
zone maps\mp\gametypes\_gameobjects::setUseText( &"string" );
zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "any" );
zone maps\mp\gametypes\_gameobjects::set2DIcon( "any", "compass_waypoint_capture" );
zone maps\mp\gametypes\_gameobjects::set3DIcon( "any", "waypoint_capture" );
zone.onBeginUse = ::myOnBeginUse;   // player starts capturing
zone.onEndUse   = ::myOnEndUse;     // player stops / finishes
zone.onUse      = ::myOnCapture;    // capture complete

// Get which team owns the zone:
winningTeam = zone maps\mp\gametypes\_gameobjects::getOwnerTeam();
```

---

## T5 Loadout Delivery

```gsc
// Full custom loadout override (call after spawned_player):
self takeAllWeapons();
self GiveWeapon( "famas_mp" );
self GiveWeapon( "python_speed_mp" );
self GiveWeapon( "knife_mp" );
self switchToWeapon( "famas_mp" );
self giveMaxAmmo( "famas_mp" );
self giveMaxAmmo( "python_speed_mp" );
self GiveWeapon( "frag_grenade_mp" );      // lethal grenade â€” use GiveWeapon, NOT GiveOffhandWeapon
self GiveWeapon( "flash_grenade_mp" );     // tactical grenade â€” same

// Perks:
self SetPerk( "specialty_fastreload" );
self SetPerk( "specialty_gpsjammer" );

// Remove a perk:
self UnSetPerk( "specialty_killstreak" );

// Equipment slot (claymore, camera spike etc â€” NOT grenades):
self GiveWeapon( equipment_weapon );
self SetActionSlot( 1, "weapon", equipment_weapon );
```
Use `GiveWeapon()` for ALL weapon types including grenades and equipment.
`SetActionSlot(1, "weapon", ...)` is only needed for equipment (claymores etc.) so they appear in the correct UI slot â€” grenades do not need it.

### Weapon camos â€” `CalcWeaponOptions` + `GiveWeapon` 3rd arg

Camo is applied via the 3rd parameter of `GiveWeapon`, which is a packed integer produced by the native `CalcWeaponOptions`:
```gsc
camoOpts = int( self CalcWeaponOptions( camoIndex, lensIndex, reticleIndex, reticleColorIndex ) );
self GiveWeapon( weapon, 0, camoOpts );
// Minimal form â€” camo only, stock lens/reticle:
camoOpts = int( self CalcWeaponOptions( 7, 0, 0, 0 ) );   // Jungle ERDL
self GiveWeapon( "galil_extclip_mp", 0, camoOpts );
```

**Camo indices** (from `mp/weaponOptions.csv`):
```
0   Default (weapon-specific gunmetal / wood / plastic)
1   Dusty          2   Ice            3   Red
4   OD Green       5   Desert Nevada  6   Desert Sahara
7   Jungle ERDL    8   Jungle Tiger   9   Urban German
10  Urban Warsaw   11  Winter Siberia 12  Winter Yukon
13  Woodland       14  Woodland Flora 15  Gold
```

**Lens indices** (0â€“5): white, red, blue, green, orange, yellow. Pass `0` for stock.
**Reticle indices** (0â€“39): various dot/cross/shape patterns. Pass `0` for stock red-dot.
**Reticle color indices** (0â€“6): red, green, blue, purple, cyan, yellow, orange.

**Weapons where pattern camos (5â€“14) won't show** â€” they use `weapon_camo_neutral` as their base and are unaffected by patterns. Solid colors (1â€“4) and Gold (15) behavior may vary:
`python`, `knife`, `knife_ballistic`, `m1911`, `cz75`, `makarov`, `asp`, `rpg`, `strela`, `m72_law`, `china_lake` (plus the dual-pistol variants pythondw/cz75dw/m1911dw/makarovdw/aspdw).

**Exception - `crossbow_explosive`** uses pattern base `cammo_gunmetal` plus a gold material, so patterns (5-14) and Gold (15) DO show; only the solid colors (1-4) don't (its solid base is neutral). It is the one secondary in our pool that can actually be camo'd (verified in `mp/weaponOptions.csv`).

**Why `custom_class["camo_num"]` does NOT work for this mod:**
`camo_num` is only read in `_weapons.gsc::stow_on_back()` â€” it affects only the weapon model rendered on the player's *back* (not in-hand). It also requires `isSubStr(self.curclass, "CUSTOM")`, which is false for `CLASS_ASSAULT` (our class when `scr_disable_cac=1`). Dead end.

**Current mod implementation** (`_gf_loadouts.gsc`):
- Each loadout rolls two independent camos at pool-build time (match start): `load["camo"]` (primary) and `load["camoSecondary"]` (secondary), both `randomInt(16)`
- `gf_giveCustomLoadout` builds a packed `CalcWeaponOptions(idx, 0, 0, 0)` for each and passes them to the primary and secondary `GiveWeapon` calls respectively
- Secondary camo only displays on real-base weapons (crossbow); it's a harmless no-op on neutral-base pistols/launchers, so no per-weapon guard is needed
- Minigun & M202 force `["camo"] = 0` (special primaries reject real camo); their secondaries are neutral-base, so the secondary roll is moot there

---

## T5 Player Utilities

### Controls & movement
```gsc
self freezeControls( 1 );        // lock movement + shooting (still allows looking)
self freezeControls( 0 );        // re-enable controls
// NOTE: confirmed in IW5 source; T5 should be identical â€” verify in-game

self DisableWeaponCycling()      // lock player to current weapon, no scrolling
self EnableWeaponCycling()       // re-enable
self setSpawnWeapon( "famas_mp" ) // sets weapon held on spawn
```

### Team messaging & menus
```gsc
printBoldOnTeam( text, team );   // send bold center-screen message to entire team
                                  // team = "allies" | "axis" | undefined (all)

self closePopupMenu();           // close any open popup
self closeIngameMenu();          // close in-game menu (pause/settings overlay)
closemenus();                    // calls both
```

### Array utilities
```gsc
quickSort( array );              // in-place sort, returns sorted array
// Usage: sorted = quickSort( myArray );
```

### Button detection (self = player, call in loop with wait 0.05)
```gsc
self AttackButtonPressed()
self UseButtonPressed()
self MeleeButtonPressed()
self AdsButtonPressed()
self JumpButtonPressed()
self FragButtonPressed()
self SecondaryOffHandButtonPressed()
self ActionSlotOneButtonPressed()    // through ActionSlotFourButtonPressed()
```

### String utilities (confirmed working in T5)
```gsc
strTok( string, delimiter )        // splits string -> array
getSubStr( string, start, end )    // substring; end = string.size to go to end
```

### Weapon attachment name pattern (from shrp.gsc line 267)
```gsc
// Strip _mp suffix, append _att_mp
base = getSubStr( weaponName, 0, weaponName.size - 3 );   // removes "_mp"
result = base + "_" + attachmentName + "_mp";
// e.g. "famas_mp" + "reflex" -> "famas_reflex_mp"
```

### Objective markers
Simpler than createUseObject â€” just places a waypoint:
```gsc
objId = 150;    // arbitrary ID 0-255
objective_add( objId, "active", origin );
objective_icon( objId, "waypoint_defend" );    // waypoint_capture, waypoint_target, etc.
objective_state( objId, "active" );            // "active", "invisible", "done", "failed"
objective_setvisibletoplayer( objId, player ); // call per player to show
objective_delete( objId );                      // cleanup
```

3D always-on world waypoint via HUD element:
```gsc
wp = newClientHudElem( player );
wp.x = origin[0];
wp.y = origin[1];
wp.z = origin[2] + 40;
wp setShader( "waypoint_defend", 12, 12 );
wp setwaypoint( true, true );   // arg1: always show off-screen; arg2: onscreen indicator
wp.color = ( 1, 1, 0 );
wp.hidewheninmenu = true;
```

### Visual effects
```gsc
fxid = loadfx( "fx/path/to/effect" );
spawnFx( fxid, origin );
triggerFx( fxid );
```

### Function pointer arrays (dynamic dispatch / menu systems)
```gsc
menu.functions = [];
menu.functions[0] = ::myFunc;
menu.functions[1] = ::otherFunc;
// Call: self [[ menu.functions[selected] ]]();
```

### notify/waittill as state machine
Use `level notify("state_name")` + `level waittill("state_name")` to drive state transitions instead of polling flags. Cleaner than busy-wait loops for events like round start/end.

### Scoreboard column names (valid values for setscoreboardcolumns)
```
kills  deaths  assists  captures  defends  returns  plants  defuses
stabs  humiliated  tomahawks  kdratio  x2score  survived  headshots  none
```

### givePlayerScore â€” event types
```gsc
givePlayerScore( "kill",        player );
givePlayerScore( "headshot",    player );
givePlayerScore( "assist",      player );
givePlayerScore( "capture",     player );
givePlayerScore( "defend",      player );
givePlayerScore( "plant",       player );
givePlayerScore( "defuse",      player );
givePlayerScore( "assault",     player );
givePlayerScore( "melee_kill",  player );
givePlayerScore( "hatchet_kill",player );
givePlayerScore( "other_kill",  player );
```

---

### Team health score display (GunMd0wn pattern)
```gsc
maps\mp\gametypes\_gamescore::_setteamscore("allies", getTeamHealth("allies"));
```

### game[] persistence for loadouts
`game[]` persists across rounds (SD round cycling doesn't reset it). Use it to pre-generate all loadouts at match start:
```gsc
if ( !isDefined( game["gf_init"] ) )
{
    game["gf_pool"]  = [];
    game["gf_loads"] = [];
    for ( i = 0; i < 6; i++ )
        game["gf_loads"][i] = gf_buildLoadout();
    game["gf_idx"]  = 0;
    game["gf_init"] = 1;
}
level.gf_currentLoad = game["gf_loads"][ game["gf_idx"] ];
// Advance: game["gf_idx"] = int( game["gf_rounds_done"] / 2 ); in onDeadEvent
```

### Loadout as associative array (confirmed T5)
```gsc
load = [];
load["primary"]   = "famas_reflex_mp";
load["secondary"] = "python_speed_mp";
load["lethal"]    = "frag_grenade_mp";
load["tactical"]  = "flash_grenade_mp";
```

### Singleton HUD kill pattern
Prevents stale HUD instances when recreating after round cycling:
```gsc
level notify( "kill_healthhud" );
level endon( "kill_healthhud" );
// ... create HUD elements below ...
```

### Overtime countdown â€” manual decrement, pauses while zone contested
```gsc
gf_overtimeCountdown()
{
    level endon( "game_ended" );
    timeLeft = 20.0;
    while ( timeLeft > 0 )
    {
        if ( !level.gf_overtimeCaptureActive )
            timeLeft -= 0.1;
        wait 0.1;
    }
    level notify( "gf_overtime_expired" );
}
```

> **Why the OT clock is a custom decrement loop (not the native round timer) — reviewed 2026-06-16.**
> The real implementation (`gf_beginOvertime` / `gf_overtimeClock` / `gf_syncOvertimeRemaining` /
> `gf_pause`/`gf_resumeOvertimeForCapture` in `_gf_rounds.gsc`) tracks `level.gf_overtimeRemaining`
> in ms and drives the HUD via `setGameEndTime`, with `level.timeLimitOverride = true` suppressing
> the native `onTimeLimit`. This is custom on purpose: the native round timer has **no** support for
> (a) pausing/resuming on a *gameplay condition* (the OT clock must freeze while the zone is being
> captured and resume if the capture breaks — done here with a depth counter), (b) *hiding* the clock
> during that pause (`setGameEndTime(0)`), or (c) a per-second countdown tick during OT. It already
> uses the native `pauseTimer()`/`setGameEndTime()` where they fit. A rewrite onto
> `pauseTimer`/`resumeTimer` + re-enabled `onTimeLimit` was evaluated and **rejected**: it would still
> need custom expiry detection, tick sound, and hide-on-capture, so it trades a well-tested flow
> (pause depth, resume-on-interrupt, expiry-by-HP, capture-win, wipe-during-OT) for little real LOC
> savings. Keep it unless the native timer gains condition-pause support.

> **The live (non-OT) round timer is ALSO mod-owned now (added 2026-06-18).**
> `gf_startRoundClock` / `gf_roundClock` / `gf_syncRoundRemaining` / `gf_updateRoundWarning` in
> `_gf_rounds.gsc` mirror the OT clock for the main round. `gf_tryActivateRound` calls
> `gf_startRoundClock()` once the round goes live — uniform every round: after `prematch_over`
> it pauses the native clock, threads `gf_closeGraceEarly` (3s floor past prematch_over; stock
> `level.gracePeriod` stays 15 as the ceiling), and starts the clock. The former post-prematch
> "wait until every teamed player has spawned" roster hold was RETIRED 2026-07-04 — the roster is
> now confirmed loaded by the pre-prematch load/min-players gate (`gf_waitForLoadingClients`), so
> everyone has spawned by `prematch_over` and there is nothing left to wait for.
> It `pauseTimer()`s — which gates off the stock `_globallogic::timeLimitClock` warning
> loop (`if ( !level.timerStopped && level.timeLimit )`) so NONE of the native time-out sequence fires
> (no announcer, no `TIME_OUT` music, no 30s/12s/1-min beeps or client cues) — sets
> `level.timeLimitOverride = true` (own expiry via `gf_onTimeLimit`), and drives the HUD via
> `setGameEndTime`. Our warning: `leaderDialog("timesup")` once at 15s remaining (no team arg → both
> teams, generic callout, no music), then `mpl_ui_timer_countdown` beeps each second in the final 10s.
> Expiry still hands to `gf_onTimeLimit` (→ overtime or HP decision). Reason this is custom: the stock
> warning thresholds are hardcoded absolute seconds and `level.timeLimit` is re-set from the dvar every
> `updateGameTypeDvars` tick, so there is no flag that silences the native warning without also freezing
> the clock — owning it is the only clean route. Trade-off: the stock last-round winning/losing VO is
> also suppressed (it rides the same `match_ending_soon` notify).

### Delayed grenade delivery (prevents spawn-instant-throw)
```gsc
gf_giveDelayedGrenade( lethal )
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );
    wait 3;
    if ( self.health > 0 )
    {
        self GiveWeapon( lethal );   // T5: GiveWeapon for grenades, not GiveOffhandWeapon
        self setWeaponAmmoClip( lethal, 1 );   // one grenade only
    }
}
```

### hideHardpointModels â€” canonical pattern (confirmed misterbubb T6 matches our T5 impl)
```gsc
hardpoints = getentarray( "hq_hardpoint", "targetname" );
for ( i = 0; i < hardpoints.size; i++ )
{
    hp = hardpoints[i];
    hp.original_origin = hp.origin;
    if ( isDefined( hp.target ) )
    {
        visuals = getentarray( hp.target, "targetname" );
        for ( j = 0; j < visuals.size; j++ )
            if ( isDefined( visuals[j] ) )
            {
                visuals[j].origin = visuals[j].origin + ( 0, 0, -10000 );
                visuals[j] hide();
            }
    }
    if ( isDefined( hp.model ) ) hp hide();
}
```
`hp.original_origin` is read in `gf_overtime()` to place the capture zone at the correct world position.

### Admin / permission pattern
```gsc
if ( player.guid == getDvar( "sv_adminGUID" ) ) { ... }
// Or maintain a level.admins[] array populated at connect time
```

### T5 player methods confirmed (Xinerki duel.gsc â€” T5 gametype)
```gsc
maps\mp\gametypes\_wager::setupBlankRandomPlayer( takeAll, chooseBody )
// clears player and optionally assigns a random body model; call before giveWeapon
```

---

