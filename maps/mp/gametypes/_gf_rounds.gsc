// Gunfight v3 — Round Management
// _globallogic::endGame handles scoring, win-limit, intermission, and respawn.

#include maps\mp\gametypes\_gf_hud;
// #strip-begin - _gf_debug include (dev/main only; stripped from public release)
#include maps\mp\gametypes\_gf_debug;
// #strip-end
#include maps\mp\gametypes\_hud_util;

gf_registerOvertimeLimitDvar()
{
    level.gf_overtimeLimitDvar = "scr_" + level.gameType + "_overtimelimit";
    gf_getOvertimeLimit();
}

gf_getOvertimeLimit()
{
    if ( !isDefined( level.gf_overtimeLimitDvar ) )
        level.gf_overtimeLimitDvar = "scr_" + level.gameType + "_overtimelimit";

    // Each mode reads its own dvar so both are independently tunable (cfg/RCON)
    // and the small-mode value is never clobbered when the mode flips.
    if ( isDefined( level.gf_largeMode ) && level.gf_largeMode )
        value = gf_cfgFloat( level.gf_overtimeLimitDvar + "_large", 30, 0, 120 );
    else
        value = gf_cfgFloat( level.gf_overtimeLimitDvar, 15, 0, 120 );

    level.gf_cfg_overtimeLimit = value;
    return value;
}

// OT zone capture time (seconds), per mode. Reads gf_capture_time /
// gf_capture_time_large so both are tunable; defaults preserve prior behavior.
gf_getCaptureTime()
{
    if ( isDefined( level.gf_largeMode ) && level.gf_largeMode )
        return gf_cfgFloat( "gf_capture_time_large", 5, 0.5, 60 );
    return gf_cfgFloat( "gf_capture_time", 3, 0.5, 60 );
}

// Reads a float dvar, registering the default if unset and clamping to [lo,hi].
// Mirrors the register*Dvar pattern (default-if-empty, clamp, persist).
gf_cfgFloat( dvar, def, lo, hi )
{
    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, def );

    v = GetDvarFloat( dvar );
    clamped = maps\mp\gametypes\_globallogic_utils::getValueInRange( v, lo, hi );
    if ( clamped != v )
        setDvar( dvar, clamped );   // persist the clamped value back, as before
    return clamped;
}

// The engine's native prematch (matchStartTimer) draws the countdown number but plays NO sound.
// Mirror a per-second tick so the prematch has the same audible cadence as the overtime tick.
// Loops while level.inPrematchPeriod, so it self-stops at prematch_over.
gf_nativePrematchTicker()
{
    level endon( "game_ended" );

    tickObj = spawn( "script_origin", ( 0, 0, 0 ) );
    while ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
    {
        tickObj playSound( "mpl_ui_timer_countdown" );
        wait 1.0;
    }
    tickObj delete();
}

// ─── Team-Size Spawn/Barrier Mode ──────────────────────────────────────────
// Resolves "large" (full-map TDM spawns, wager barriers deleted, OT flag at the
// Domination B flag) vs "small" (curated gunfight spawns + wager barriers).
// Re-evaluated every round from onStartGameType, which map_restart re-fires, so
// the result lives in level.* (wiped per round). The spawn/allow-list/wager
// branches in onStartGameType and onSpawnPlayer/gf_getOvertimeFlagTrigger all
// read level.gf_largeMode.
//
// scr_<gametype>_teamspawnmode: auto (default) | large | small. "auto" goes
// large once the TOTAL in-match player count (allies + axis) reaches
// scr_gf_largemode_minplayers (default 7 -> 0-6 players small, 7+ large); a
// forced value pins the mode for admins/RCON/testing.
//
// onStartGameType (where this runs) snapshots the roster BEFORE bots/late
// joiners connect — _bot::init() is threaded at the end of onStartGameType — so
// a live count here is unreliable. auto therefore prefers game["gf_autoLargeMode"],
// captured at round activation by gf_updateAutoTeamMode() once everyone has
// spawned, and persisted through map_restart in game[]. The live count is only a
// first-setup fallback (e.g. a populated server where players are already
// connected at map load).
gf_resolveTeamMode()
{
    dvar = "scr_" + level.gameType + "_teamspawnmode";
    mode = GetDvar( dvar );
    if ( mode != "auto" && mode != "large" && mode != "small" )
    {
        mode = "auto";
        setDvar( dvar, mode );
    }

    if ( mode == "large" )
    {
        level.gf_largeMode = true;
        return;
    }
    if ( mode == "small" )
    {
        level.gf_largeMode = false;
        return;
    }

    if ( isDefined( game["gf_autoLargeMode"] ) )
    {
        level.gf_largeMode = game["gf_autoLargeMode"];
        return;
    }

    // level.playerCount is engine-maintained (_globallogic::updateTeamStatus) and initialized
    // in _globallogic::init(), so it's safe to read here. This is only the first-setup fallback;
    // once a round activates, gf_updateAutoTeamMode persists the decision in game[].
    level.gf_largeMode = ( ( level.playerCount["allies"] + level.playerCount["axis"] ) >= gf_largeModeThreshold() );
}

// Captures the live team sizes once the round is active and everyone (incl.
// late-added bots) has spawned, persisting the auto decision in game[] for the
// next round's onStartGameType setup. No-op when the mode is force-pinned.
gf_updateAutoTeamMode()
{
    if ( GetDvar( "scr_" + level.gameType + "_teamspawnmode" ) != "auto" )
        return;

    game["gf_autoLargeMode"] = ( ( level.playerCount["allies"] + level.playerCount["axis"] ) >= gf_largeModeThreshold() );
}

// Total in-match players (allies + axis) at or above which auto-mode selects
// LARGE (full-map) spawns; below it, SMALL (curated). Tunable via
// scr_gf_largemode_minplayers (default 7 -> 0-6 small, 7+ large; clamp 2-12).
gf_largeModeThreshold()
{
    return int( gf_cfgFloat( "scr_gf_largemode_minplayers", 7, 2, 12 ) );
}

// ─── Player Lifecycle ──────────────────────────────────────────────────────

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );

    // Silence the stock "+N" XP popups. _rank::giveRankXP pushes them onto the SAME
    // element our Elimination/Assist popup reuses (self.hud_rankscroreupdate), gated
    // only by self.enableText — the stock per-player "XP text" preference, re-set true
    // by _persistence on every connect (so every map_restart), hence per-spawn here.
    // Our zeroed kill/assist score info already silences those types, but medals
    // (First Blood etc.), challenges, and stat milestones pass EXPLICIT XP values that
    // bypass the zeroing — on a ranked server they raced our popup and sometimes
    // replaced it. XP itself still accrues (incRankXP runs before the gate); only the
    // engine's popup text is suppressed.
    self.enableText = false;

    // ...and the CLIENT half of the same stock toggle (ui_xpText), which
    // _persistence re-pushes "1" on every connect. Both halves stay as defense in
    // depth, but on the ranked VPS a stock "+N" STILL got through with both off —
    // every script gate checked out on paper (retail AND plutoniummod/t5-scripts),
    // so the decisive fix is element-level: our popup now uses its OWN element
    // (gf_popupElem) and the stock hud_rankscroreupdate is parked offscreen below.
    self setClientDvar( "ui_xpText", "0" );

    // Element-level backstop: park the stock rank-score element offscreen so any
    // stock "+N" that slips past the gates renders invisibly. No stock writer
    // ever re-sets x/y after creation. Humans only — bots draw no HUD.
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self thread gf_parkStockScorePopup();

    // One-time welcome splash, once per CONNECTION (pers[] resets on disconnect,
    // so a rejoiner is greeted again; the between-round map_restart is not a
    // re-greet). Humans only — bots draw no HUD and their names would burn
    // setText configstrings for nothing.
    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        && !isDefined( self.pers["gf_welcomed"] ) )
    {
        self.pers["gf_welcomed"] = true;
        self thread gf_welcomeMessage();
    }

    // If scr_team_maxsize > 0, redirect to spectator when the team is already full.
    // The notify above still fires so SD and round logic don't stall.
    maxTeam = getDvarInt( "scr_team_maxsize" );
    if ( maxTeam > 0 )
    {
        team = self.pers["team"];
        if ( team == "allies" || team == "axis" )
        {
            count = 0;
            players = level.players;
            for ( i = 0; i < players.size; i++ )
            {
                if ( players[i] == self ) continue;
                if ( players[i].pers["team"] == team ) count++;
            }
            if ( count >= maxTeam )
            {
                self.pers["team"] = "spectator";
                self [[level.spawnSpectator]]( self.origin, self.angles );
                return;
            }
        }
    }

    self gf_syncCaptureScore();
    self gf_initDamageScore();

    // Mark that this player actually spawned into the current round, so the team-health
    // stats only count real participants. A mid-round joiner is team-assigned but never
    // spawns this round (they spectate) — without this they'd inflate the team's max
    // health and shrink the bar even though they contribute no current health.
    self.pers["gf_spawnedRound"] = game["roundsplayed"];

    // Level-side stats publisher — start once per round; the player panels read its output.
    if ( !isDefined( level.gf_healthHudStartRound ) || level.gf_healthHudStartRound != game["roundsplayed"] )
    {
        level.gf_healthHudStartRound = game["roundsplayed"];
        level thread gf_startHealthHUD();
    }
    gf_queueHealthHUDUpdate();
    // Forced video tweaks, gated by scr_gf_visualtweaks (0 = leave the player's own video alone).
    if ( getDvarInt( "scr_gf_visualtweaks" ) )
    {
        self setClientDvar( "r_lightTweakAmbient",  "0.1" );
        self setClientDvar( "r_lightGridIntensity", "1.1" );
        self setClientDvar( "r_lightGridContrast",  "1"   );   // domain is -1..1; 1.1 is rejected by the engine
        self setClientDvar( "r_gamma",              "1.1" );
        self setClientDvar( "r_fullHDRrendering",   "1"   );
    }
    self thread gf_onSpawned();

    // Drive the entire per-player health panel in the PLAYER's own context (create +
    // update + destroy) — T5 client HUD elements don't network if created from a level
    // thread. Mirrors the loadout HUD pattern.
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self thread gf_runHealthHUD();

    // #strip-begin - spawn recorder + HUD-pool overlays (dev/main only; stripped from public release)
    if ( getDvarInt( "gf_debug_spawns" ) == 1 )
        self thread gf_startSpawnRecorder();

    if ( getDvarInt( "gf_debug_hud_pool" ) == 1 )
    {
        if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
            self thread gf_startHUDPoolOverlay();
    }

    // One-shot ALLOCATION sanity check — prints "ALLOC free: N" ~9s after spawn. Measures the
    // allocation pool only (huge); the real per-player DRAWN cap (~17) shows on the pool overlay.
    if ( getDvarInt( "gf_debug_elem_probe" ) == 1 )
    {
        if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
            self thread gf_debugElemProbe();
    }
    // #strip-end
}


gf_onSpawnSpectator( origin, angles )
{
    maps\mp\gametypes\_globallogic_defaults::default_onSpawnSpectator( origin, angles );
    gf_queueHealthHUDUpdate();

    // Spectators always see the whole health HUD. The panel is fully menu-rendered and the
    // intro is a snap now, so re-threading gf_runHealthHUD on each spectator spawn is cheap
    // and harmless (it re-pushes the per-client dvars).
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self thread gf_runHealthHUD();
}

gf_onSpawned()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    self.gf_assisters = [];
    self.gf_dmgOnTarget = [];

    if ( !level.gf_roundActive )
        level thread gf_tryActivateRound();
}

// ─── Round Activation ──────────────────────────────────────────────────────

gf_tryActivateRound()
{
    if ( level.gf_activatingRound )
        return;

    level.gf_activatingRound = true;
    level endon( "game_ended" );

    // 0.2s dedup so a single activation thread wins the spawn burst.
    wait 0.2;

    if ( level.gf_roundActive )
    {
        level.gf_activatingRound = false;
        return;
    }

    level.gf_roundEnding     = false;
    level.gf_roundActive     = true;
    level.gf_activatingRound = false;
    level.gf_warnedLastPlayer = [];
    gf_forceHealthHUDUpdate();

    // The engine's native per-round prematch (set up in onStartGameType via level.prematchPeriod)
    // owns the countdown, player freeze, intro VO, objective hint, and timer-hide. We reach here
    // ~0.2s INTO it (players spawn frozen during the prematch, and that first spawn is what
    // triggers gf_tryActivateRound), so wait for the prematch to finish before starting the round
    // clock — otherwise it draws the round timer over the countdown AND burns round time. While
    // the clock isn't running, timeLimitOverride stays false, so the engine hides the timer for
    // the whole prematch (clean, no flicker), exactly like SD.
    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
        level waittill( "prematch_over" );

    // Silence the native timeLimitClock across the (usually zero-length) hold below —
    // it starts at prematch_over and on a 45s round timeLeftInt begins inside the stock
    // 40-60s match_ending_soon band, which would set xblive_matchEndingSoon and fire the
    // last-round winning/losing VO at ROUND START during a real hold. Pausing here (same
    // frame position the old code paused from, via gf_startRoundClock) also freezes
    // getTimePassed() at ~0, so disable the stock grenade-dud window now too or grenades
    // thrown during the hold fire as duds (same interaction gf_startRoundClock handles).
    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    level.grenadeLauncherDudTime = -1;
    level.thrownGrenadeDudTime   = -1;

    // Hold the round clock until every teamed player has actually spawned. The engine
    // never waits for the roster itself — startGame()'s waitForPlayers() is an empty
    // stub and prematch_over is pure wall clock — so round-1 bot fill and slow loaders
    // land after it. Bounded so a stuck client can't stall the match.
    graceFloor = gettime() + 3000;
    deadline   = gettime() + 8000;
    if ( !gf_allTeamedPlayersSpawned() )
    {
        setGameEndTime( 0 );   // hide the native clock while holding (it would count down, then snap back to full)
        while ( gettime() < deadline && !gf_allTeamedPlayersSpawned() )
            wait 0.1;
    }

    // Close grace early — the moment the roster is in — instead of at the stock 15s
    // mark, but never before 3s after prematch_over: a human still sitting in
    // team-select is invisible to the spawn poll (no pers["team"] yet), and 3s is the
    // join slack the old gracePeriod=3 gave them. Threaded so the round clock below
    // starts immediately either way.
    level thread gf_closeGraceEarly( graceFloor );

    // Capture the auto team-size decision from the now-settled roster for the next
    // round's setup. (Doing this before the spawn wait undercounted round-1 bot fill
    // and poisoned game["gf_autoLargeMode"] for round 2.)
    gf_updateAutoTeamMode();

    // Take over the live-round timer. This silences the native 30s "time running out" sequence
    // (announcer + TIME_OUT music + beeps) and drives our own countdown instead: VO at 15s, beeps
    // in the final 10s, no music.
    gf_startRoundClock();
}

// Closes the grace period once floorTime has passed. Closing grace reopens
// onDeadEvent (a wipe can end the round again) and shuts maySpawn's first-spawn
// window. Mirror stock gracePeriod()'s close with an updateTeamStatus pass so a
// wipe that happened WHILE grace was open is still noticed (updateGameEvents only
// re-runs on team-status ticks). The stock gracePeriod() thread still runs its own
// idempotent close at the full 15s as a backstop.
gf_closeGraceEarly( floorTime )
{
    level endon( "game_ended" );

    while ( gettime() < floorTime )
        wait 0.1;

    level.inGracePeriod = false;
    level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
}

// True once every connected player on a playing team has completed a spawn this round
// (stock self.hasSpawned: reset false in Callback_PlayerConnect — which re-runs for
// every client on the between-round map_restart — and set true in spawnPlayer).
// Spectators and players still in team-select don't count: they can't spawn into this
// round, so they must not hold the clock hostage.
gf_allTeamedPlayersSpawned()
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        player = players[i];

        team = player.pers["team"];
        if ( !isDefined( team ) || ( team != "allies" && team != "axis" ) )
            continue;

        if ( !isDefined( player.hasSpawned ) || !player.hasSpawned )
            return false;
    }

    return true;
}

// ─── Live-Round Clock ──────────────────────────────────────────────────────
//
// We own the live-round timer instead of the native one. The stock
// _globallogic::timeLimitClock fires a fixed "time running out" sequence at
// hardcoded thresholds (announcer VO ~32s, TIME_OUT music + countdown beeps at
// 30s), keyed off absolute seconds remaining — so on a 45s round it triggers
// almost immediately and there is no dvar to retune it. pauseTimer() sets
// level.timerStopped, which gates off that native loop entirely (no music, no
// VO, no beeps); we then drive the HUD clock via setGameEndTime and own expiry
// via level.timeLimitOverride. Same proven approach as the overtime clock below.
gf_startRoundClock()
{
    // Round length (minutes) -> ms. level.timeLimit is per-mode (small vs _large),
    // re-derived each round in main()/onStartGameType.
    roundLen = 0.75;
    if ( isDefined( level.timeLimit ) && level.timeLimit > 0 )
        roundLen = level.timeLimit;

    level.gf_roundRemaining    = roundLen * 60 * 1000;
    level.gf_roundLastTime     = gettime();
    level.gf_roundLastTick     = undefined;
    level.gf_roundWarned       = false;
    level.gf_roundClockRunning = true;
    level.gf_roundPaused       = false;
    level.timeLimitOverride    = true;

    if ( isDefined( level.gf_roundTickObject ) )
        level.gf_roundTickObject delete();
    level.gf_roundTickObject = spawn( "script_origin", ( 0, 0, 0 ) );

    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    gf_updateRoundGameEndTime();

    // pauseTimer() freezes getTimePassed() at ~0 for the whole round, which breaks
    // the stock grenade-dud window (_weapons::turnGrenadeIntoADud compares
    // dudTime >= getTimePassed()/1000). With the clock frozen that stays true all
    // round, so frags/semtex AND launchers (gl_*, china_lake_mp) fire as duds and
    // spam "unavailable for 1 second". Negative thresholds disable the dud system
    // entirely (no positive value would ever elapse against a frozen clock). Set
    // here (after map_restart wipes level.*) so it re-applies every round; persists
    // through overtime in the same round.
    level.grenadeLauncherDudTime = -1;
    level.thrownGrenadeDudTime   = -1;

    level thread gf_roundClock();
}

gf_roundClock()
{
    level endon( "game_ended" );
    level endon( "gf_round_over" );   // round ended early by elimination

    while ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        gf_syncRoundRemaining();

        if ( level.gf_roundRemaining <= 0 )
        {
            level.gf_roundClockRunning = false;
            // Leave level.timerStopped / level.timeLimitOverride set: expiry either
            // enters overtime (which re-pauses + keeps the override) or ends the round
            // (map_restart wipes the state). Only clear our own clock vars here.
            gf_cleanupRoundTimerState();
            gf_onTimeLimit();
            return;
        }

        // While admin-paused, skip the HUD push + warning tick so the setGameEndTime(0)
        // from gf_pauseMatch stays sticky (a re-push would re-arm the on-screen clock)
        // and no countdown beep fires on a frozen clock — same guard as gf_overtimeClock.
        if ( !isDefined( level.gf_roundPaused ) || !level.gf_roundPaused )
        {
            gf_updateRoundGameEndTime();
            gf_updateRoundWarning();
        }

        wait 0.1;
    }
}

gf_syncRoundRemaining()
{
    if ( !isDefined( level.gf_roundLastTime ) )
        level.gf_roundLastTime = gettime();

    now = gettime();
    elapsed = now - level.gf_roundLastTime;
    level.gf_roundLastTime = now;

    // While admin-paused (RCON bridge), advance the reference time but hold the
    // remaining ms — same freeze the OT clock does via level.gf_overtimePaused.
    if ( isDefined( level.gf_roundPaused ) && level.gf_roundPaused )
        return;

    if ( elapsed > 0 )
        level.gf_roundRemaining -= elapsed;

    if ( level.gf_roundRemaining < 0 )
        level.gf_roundRemaining = 0;
}

gf_updateRoundGameEndTime()
{
    if ( !isDefined( level.gf_roundRemaining ) )
        return;

    remaining = level.gf_roundRemaining;
    if ( remaining < 0 )
        remaining = 0;

    setGameEndTime( int( gettime() + remaining ) );
}

gf_updateRoundWarning()
{
    if ( !isDefined( level.gf_roundRemaining ) )
        return;

    remaining = level.gf_roundRemaining;

    // Announcer VO once at 15s remaining. No team arg -> leaderDialogBothTeams plays
    // the generic "timesup" callout to everyone (no "squad_30sec" variant). No music:
    // we never fire the native match_ending_* notifies that drive TIME_OUT.
    if ( remaining <= 15000 && ( !isDefined( level.gf_roundWarned ) || !level.gf_roundWarned ) )
    {
        level.gf_roundWarned = true;
        maps\mp\gametypes\_globallogic_audio::leaderDialog( "timesup" );
    }

    // Countdown beeps in the final 10 seconds only (one per second, 10 -> 1).
    if ( remaining <= 0 || remaining > 10000 )
        return;

    tick = int( ( remaining + 999 ) / 1000 );
    if ( tick < 1 || tick > 10 )
        return;

    if ( isDefined( level.gf_roundLastTick ) && level.gf_roundLastTick == tick )
        return;

    level.gf_roundLastTick = tick;

    if ( isDefined( level.gf_roundTickObject ) )
        level.gf_roundTickObject playSound( "mpl_ui_timer_countdown" );
}

gf_cleanupRoundTimerState()
{
    level.gf_roundClockRunning = false;
    level.gf_roundRemaining    = undefined;
    level.gf_roundLastTime     = undefined;
    level.gf_roundLastTick     = undefined;

    if ( isDefined( level.gf_roundTickObject ) )
    {
        level.gf_roundTickObject delete();
        level.gf_roundTickObject = undefined;
    }
}

// ─── Admin Match Pause (RCON bridge) ───────────────────────────────────────
// The live round timer is now mod-owned (gf_roundClock / gf_syncRoundRemaining),
// so the stock pauseTimer() the bridge used to call no longer freezes the visible
// clock — it only sets level.timerStopped, which we already hold true all round
// (and flipping it back via resumeTimer would re-arm the native "time running out"
// VO/music/beeps we deliberately suppress). Instead the bridge delegates here:
// we freeze whichever mod clock is live (overtime takes priority over the round
// clock, matching gf_onTimeLimit), freeze human controls, and freeze bots.
//
// Bots ignore freezeControls (they're server-driven by the vendored framework,
// not client input), so we toggle the framework's own bots_play_move dvar — its
// per-bot bot_watch_stop_move loop pins velocity/origin when it's 0.
gf_pauseMatch()
{
    // Freeze whichever mod clock is live. Overtime routes through the capture
    // pause-depth counter (gf_pauseOvertimeForCapture) so an admin pause composes
    // with an in-progress zone capture — the OT clock only resumes once BOTH
    // release it. The round clock has no such counter, so it uses a simple flag.
    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
        gf_pauseOvertimeForCapture();
    else if ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        if ( !isDefined( level.gf_roundPaused ) || !level.gf_roundPaused )
        {
            gf_syncRoundRemaining();
            level.gf_roundPaused = true;
            setGameEndTime( 0 );   // hide the clock while paused (matches capture pause)
        }
    }

    setDvar( "bots_play_move", 0 );   // framework's bot_watch_stop_move pins every bot in place

    players = level.players;
    for ( i = 0; i < players.size; i++ )
        players[i] freezeControls( true );
}

gf_resumeMatch()
{
    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
        gf_resumeOvertimeForCapture();
    else if ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        if ( isDefined( level.gf_roundPaused ) && level.gf_roundPaused )
        {
            // Reset the reference time BEFORE clearing the flag so the paused interval
            // is discarded (no catch-up jump), like gf_resumeOvertimeForCapture.
            level.gf_roundLastTime = gettime();
            level.gf_roundPaused   = false;
            gf_updateRoundGameEndTime();
        }
    }

    setDvar( "bots_play_move", 1 );

    // bots_play_move=1 stops bot_watch_stop_move from re-pinning, but the last-spawned
    // botStopMove(true) loop only ends on this notify (or death/disconnect) — without it
    // a bot that was mid-navigation stays frozen in place for the rest of the round.
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        players[i] freezeControls( false );
        if ( isDefined( players[i].pers["isBot"] ) && players[i].pers["isBot"] )
            players[i] notify( "botStopMove" );
    }
}

// ─── Round End ─────────────────────────────────────────────────────────────

// Central round-end helper — mirrors sd_endGame().
// Updates game["teamScores"] so the native score bar HUD reflects the win,
// then hands off to _globallogic::endGame() for round cycling / win-limit.
gf_endRound( winner )
{
    if ( gf_resolveOvertime( winner ) )
        return;

    level.gf_roundEnding = true;
    level.gf_roundActive = false;
    level notify( "gf_round_over" );

    // gf_round_over endons the round clock thread before it can self-clean; tear down
    // its tick object + state here so an early elimination end doesn't leave them.
    gf_cleanupRoundTimerState();

    gf_forceHealthHUDUpdate();

    if ( isDefined( winner ) && winner != "tie" )
        [[level._setTeamScore]]( winner, [[level._getTeamScore]]( winner ) + 1 );

    // Native WIN/LOSS banner subtitle — reason set at the decision site (carried
    // via level var so it survives the OT gf_ot_done re-entry into gf_endRound).
    reasonText = "";
    if ( isDefined( level.gf_endReasonText ) )
        reasonText = level.gf_endReasonText;
    level.gf_endReasonText = undefined;

    level thread maps\mp\gametypes\_killcam::startLastKillcam();
    level thread maps\mp\gametypes\_globallogic::endGame( winner, reasonText );
}

gf_onDeadEvent( team )
{
    if ( level.gf_roundEnding ) return;
    if ( !level.gf_roundActive ) return;

    if ( team == "all" )
        winner = "tie";
    else
        winner = maps\mp\_utility::getOtherTeam( team );

    gf_forceHealthHUDUpdate();
    level.gf_endReasonText = gf_reasonText( "elim", winner );
    gf_endRound( winner );
}

gf_onTimeLimit()
{
    if ( level.gf_roundEnding ) return;

    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
    {
        hpWinner = gf_getHPWinner();
        level.gf_endReasonText = gf_reasonText( "health", hpWinner );
        gf_resolveOvertime( hpWinner );
        return;
    }

    alliesHP = gf_getTeamHP( "allies" );
    axisHP   = gf_getTeamHP( "axis"   );

    // Both sides still alive enter overtime; otherwise HP decides the round.
    if ( alliesHP > 0 && axisHP > 0 )
    {
        overtimeLimit = gf_getOvertimeLimit();
        if ( overtimeLimit <= 0 )
        {
            hpWinner = gf_getHPWinner();
            level.gf_endReasonText = gf_reasonText( "health", hpWinner );
            gf_endRound( hpWinner );
            return;
        }

        gf_beginOvertime( overtimeLimit );
        return;
    }

    hpWinner = gf_getHPWinner();
    level.gf_endReasonText = gf_reasonText( "health", hpWinner );
    gf_endRound( hpWinner );
}

gf_resolveOvertime( winner )
{
    if ( !isDefined( level.gf_overtimeActive ) || !level.gf_overtimeActive )
        return false;

    if ( isDefined( level.gf_overtimeResolving ) && level.gf_overtimeResolving )
        return true;

    level.gf_overtimeResolving = true;
    level notify( "gf_ot_done", winner );
    return true;
}

gf_beginOvertime( overtimeLimit )
{
    level.gf_overtimeActive        = true;
    level.gf_overtimeResolving     = false;
    level.gf_overtimePaused        = false;
    level.gf_overtimePauseDepth    = 0;
    level.gf_overtimeRemaining     = overtimeLimit * 1000;
    level.gf_overtimeLastTime      = gettime();
    level.gf_overtimeLastTickMs    = undefined;
    level.gf_overtimeClockRunning  = true;
    level.inOvertime               = true;
    level.timeLimitOverride        = true;

    if ( isDefined( level.gf_overtimeTickObject ) )
        level.gf_overtimeTickObject delete();
    level.gf_overtimeTickObject = spawn( "script_origin", ( 0, 0, 0 ) );

    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    gf_updateOvertimeGameEndTime();

    level thread gf_overtime();
}

gf_overtime()
{
    level endon( "game_ended" );

    gf_showOvertimeMessage();

    // Ensure _gameobjects vars are ready (guarded in case _gameobjects::init was skipped)
    if ( !isDefined( level.numGametypeReservedObjectives ) )
        level.numGametypeReservedObjectives = 0;
    if ( !isDefined( level.releasedObjectives ) )
        level.releasedObjectives = [];

    zone = gf_createOvertimeZone();

    // Safety net: if the round ends mid-OT via a path that fires game_ended WITHOUT
    // going through gf_resolveOvertime (forfeit, host migration), the endon above kills
    // this thread before the cleanup below runs — leaking the zone's 2 objpoint HUD
    // elements + 2 objective IDs. Engine-side hudelem/objective state SURVIVES
    // map_restart(true) (observed: objective IDs accumulate), so leaks persist for the
    // whole map session and can exhaust the server HUD pool → later OT rounds get no
    // flag icon. This watcher cleans up on game_ended; the gf_ot_done endon makes the
    // two cleanup paths mutually exclusive.
    level thread gf_overtimeZoneGameEndCleanup( zone );

    // Steer any bots onto the flag so they can win OT by capture, not just HP.
    if ( isDefined( zone ) )
        level thread gf_botOvertimeAI( zone );

    level thread gf_overtimeClock();
    level waittill( "gf_ot_done", winner );

    level.gf_roundEnding = true;
    level.gf_overtimeClockRunning = false;
    gf_cleanupOvertimeZone( zone );
    gf_cleanupOvertimeTimerState();

    gf_endRound( winner );
}

gf_overtimeZoneGameEndCleanup( zone )
{
    level endon( "gf_ot_done" );
    level waittill( "game_ended" );
    gf_cleanupOvertimeZone( zone );
}

gf_showOvertimeMessage()
{
    maps\mp\_utility::playSoundOnPlayers( "mpl_hq_cap_us" );

    // Announcer VO: stock "Overtime" callout, then our CTF cue ("ctf_start", registered as
    // game["dialog"]["gf_overtime_cue"] in gf.gsc::onPrecacheGameType) right after. leaderDialog
    // queues per-player, so the second line auto-plays ~3s behind the first (see
    // playLeaderDialogOnPlayer in _globallogic_audio). No team arg -> both teams hear both.
    // "overtime" comes from the shared _globallogic_audio::init() dialog table.
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "overtime" );
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "gf_overtime_cue" );

    titleText = &"MP_OVERTIME_CAPS";
    if ( isDefined( game["strings"] ) && isDefined( game["strings"]["overtime"] ) )
        titleText = game["strings"]["overtime"];

    // 6th arg = duration (seconds). Without it the message uses
    // level.startMessageDefaultDuration (2.0s), which vanishes too fast.
    overtimeMsgDuration = 5.0;

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        player thread maps\mp\gametypes\_hud_message::oldNotifyMessage( titleText, undefined, undefined, ( 1, 0, 0 ), undefined, overtimeMsgDuration );
    }
}

gf_overtimeClock()
{
    level endon( "game_ended" );

    while ( isDefined( level.gf_overtimeClockRunning ) && level.gf_overtimeClockRunning )
    {
        if ( !level.gf_overtimeActive || level.gf_overtimeResolving )
            return;

        gf_syncOvertimeRemaining();
        if ( level.gf_overtimeRemaining <= 0 )
        {
            hpWinner = gf_getHPWinner();
            level.gf_endReasonText = gf_reasonText( "health", hpWinner );
            gf_resolveOvertime( hpWinner );
            return;
        }

        if ( !isDefined( level.gf_overtimePaused ) || !level.gf_overtimePaused )
        {
            gf_updateOvertimeGameEndTime();
            gf_updateOvertimeTickSound();
        }

        wait 0.1;
    }
}

gf_syncOvertimeRemaining()
{
    if ( !isDefined( level.gf_overtimeLastTime ) )
        level.gf_overtimeLastTime = gettime();

    now = gettime();
    elapsed = now - level.gf_overtimeLastTime;
    level.gf_overtimeLastTime = now;

    if ( isDefined( level.gf_overtimePaused ) && level.gf_overtimePaused )
        return;

    if ( elapsed > 0 )
        level.gf_overtimeRemaining -= elapsed;

    if ( level.gf_overtimeRemaining < 0 )
        level.gf_overtimeRemaining = 0;
}

gf_updateOvertimeGameEndTime()
{
    if ( !isDefined( level.gf_overtimeRemaining ) )
        return;

    remaining = level.gf_overtimeRemaining;
    if ( remaining < 0 )
        remaining = 0;

    setGameEndTime( int( gettime() + remaining ) );
}

gf_updateOvertimeTickSound()
{
    if ( !isDefined( level.gf_overtimeRemaining ) )
        return;

    remaining = level.gf_overtimeRemaining;
    if ( remaining <= 0 || remaining > 10000 )   // tick only in the final 10s
        return;

    // 1 beep/sec from 10s -> 5s (matches the round beeps), then 2 beeps/sec for the final 5s.
    // Driven off the OT remaining time, NOT wall-clock, so it honors the capture pause/resume —
    // gf_overtimeClock only calls this while the clock is running, and remaining freezes during a
    // pause, so the cadence freezes with it.
    if ( remaining > 5000 )  interval = 1000;   // 10s..5s : 1/sec
    else                     interval = 500;    // last 5s : 2/sec

    // First tick fires immediately on entering the 10s window (lastTickMs undefined); after that,
    // tick once the remaining time has dropped by at least the current interval.
    if ( isDefined( level.gf_overtimeLastTickMs ) && ( level.gf_overtimeLastTickMs - remaining ) < interval )
        return;

    level.gf_overtimeLastTickMs = remaining;

    if ( isDefined( level.gf_overtimeTickObject ) )
        level.gf_overtimeTickObject playSound( "mpl_ui_timer_countdown" );
}

gf_pauseOvertimeForCapture()
{
    if ( !isDefined( level.gf_overtimeActive ) || !level.gf_overtimeActive )
        return;

    if ( !isDefined( level.gf_overtimePauseDepth ) )
        level.gf_overtimePauseDepth = 0;

    level.gf_overtimePauseDepth++;
    if ( level.gf_overtimePauseDepth > 1 )
        return;

    gf_syncOvertimeRemaining();
    level.gf_overtimePaused = true;
    setGameEndTime( 0 );   // hide the clock while paused; a re-push "freeze" flickers (engine has no display-hold)
}

gf_resumeOvertimeForCapture()
{
    if ( !isDefined( level.gf_overtimeActive ) || !level.gf_overtimeActive )
        return;

    if ( !isDefined( level.gf_overtimePauseDepth ) || level.gf_overtimePauseDepth <= 0 )
        level.gf_overtimePauseDepth = 0;
    else
        level.gf_overtimePauseDepth--;

    if ( level.gf_overtimePauseDepth > 0 )
        return;

    level.gf_overtimePaused = false;
    level.gf_overtimeLastTime = gettime();
    gf_updateOvertimeGameEndTime();
}

gf_cleanupOvertimeTimerState()
{
    level.gf_overtimeActive       = false;
    level.gf_overtimeResolving    = false;
    level.gf_overtimePaused       = false;
    level.gf_overtimePauseDepth   = 0;
    level.gf_overtimeRemaining    = undefined;
    level.gf_overtimeLastTime     = undefined;
    level.gf_overtimeLastTickMs   = undefined;
    level.gf_overtimeClockRunning = false;
    level.inOvertime              = false;
    level.timeLimitOverride       = false;

    if ( isDefined( level.gf_overtimeTickObject ) )
    {
        level.gf_overtimeTickObject delete();
        level.gf_overtimeTickObject = undefined;
    }

    setGameEndTime( 0 );
}

// Sets the 2D minimap icon and the 3D world icon together, from the SAME native
// _gameobjects path, so they can never disagree. For a given relative-team slot the
// 2D uses "compass_waypoint_X" and the 3D uses "waypoint_X" — the same artwork in
// minimap vs world form, so their colors coincide by construction regardless of the
// shaders' baked colors. dom.gsc convention: "defend" renders in the friendly/owner
// color (green), "capture" in the enemy color (red), "captureneutral" white.
//
// NOTE (engine constraint): the per-team friendly/enemy coloring works here because
// these are native team-routed objective/objpoint elements. It CANNOT be done with
// world-space FX (the apron) — those render identically for every player. So the
// team-relative green/red lives on these icons; the apron is an absolute cue only.
gf_setOvertimeZoneIcons( zone, friendlyIcon, enemyIcon )
{
    zone maps\mp\gametypes\_gameobjects::set2DIcon( "friendly", "compass_waypoint_" + friendlyIcon );
    zone maps\mp\gametypes\_gameobjects::set3DIcon( "friendly", "waypoint_"         + friendlyIcon );
    zone maps\mp\gametypes\_gameobjects::set2DIcon( "enemy",    "compass_waypoint_" + enemyIcon );
    zone maps\mp\gametypes\_gameobjects::set3DIcon( "enemy",    "waypoint_"         + enemyIcon );
}

gf_setOvertimeZoneIconColor( zone, team )
{
    if ( !isDefined( zone ) )
        return;

    if ( isDefined( zone.flagModel ) )
    {
        if ( team == "allies" )
            zone.flagModel setModel( "mp_flag_allies_1" );
        else if ( team == "axis" )
            zone.flagModel setModel( "mp_flag_axis_1" );
        else
            zone.flagModel setModel( "mp_flag_neutral" );
    }

    // Ground apron FX — delete old handle, spawn the color for this state.
    // World-space FX (same for all viewers), so it's an absolute zone-activity cue,
    // NOT team-relative: white idle, gold while a team captures, red contested.
    // Team-relative green/red lives on the 3D icon — see CLAUDE.md OT zone color system.
    if ( isDefined( zone.baseFxPos ) )
    {
        if ( isDefined( zone.baseFxHandle ) )
        {
            zone.baseFxHandle delete();
            zone.baseFxHandle = undefined;
        }

        fxAsset = level.gf_ot_baseFx_neutral;   // white apron when idle
        if ( team == "allies" )
            fxAsset = level.gf_ot_baseFx_allies;
        else if ( team == "axis" )
            fxAsset = level.gf_ot_baseFx_axis;
        else if ( team == "contested" )
            fxAsset = level.gf_ot_baseFx_contested;

        if ( isDefined( fxAsset ) )
        {
            zone.baseFxHandle = spawnFx( fxAsset, zone.baseFxPos, zone.baseFxFwd, zone.baseFxRight );
            triggerFx( zone.baseFxHandle );
        }
    }

    // Icons: the capturing team is set as ownerTeam, so _gameobjects routes that team
    // into the "friendly" slot and the other team into "enemy". Both the 2D minimap and
    // 3D world icon are set together (gf_setOvertimeZoneIcons) so they always coincide.
    // friendly = defend (green), enemy = capture (red), idle/contested = captureneutral.
    if ( team == "allies" || team == "axis" )
    {
        zone maps\mp\gametypes\_gameobjects::setOwnerTeam( team );
        gf_setOvertimeZoneIcons( zone, "defend", "capture" );   // capturers green, defenders red
    }
    else
    {
        // neutral (nobody capturing) and contested both resolve to a white icon for all.
        zone maps\mp\gametypes\_gameobjects::setOwnerTeam( "neutral" );
        gf_setOvertimeZoneIcons( zone, "captureneutral", "captureneutral" );
    }
}

// Polls player positions every 0.1 s and drives all OT zone visuals (FX apron,
// 3D icons, 2D flash, timer pause/resume).  Replaces the onBeginUse / onEndUse /
// onUseUpdate callbacks, which suffered from a _gameobjects numTouching race
// condition that caused flicker and missed-capture visual glitches.
gf_overtimeZoneVisuals( zone, flagTrigger )
{
    level endon( "game_ended" );
    level endon( "gf_ot_done" );

    curState  = "neutral";
    label     = zone maps\mp\gametypes\_gameobjects::getLabel();

    while ( true )
    {
        wait 0.1;

        if ( !isDefined( zone ) || !isDefined( flagTrigger ) )
            return;

        alliesCount = 0;
        axisCount   = 0;

        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( p.sessionstate != "playing" ) continue;
            if ( !isAlive( p ) ) continue;
            if ( !( p isTouching( flagTrigger ) ) ) continue;

            team = p.pers["team"];
            if ( team == "allies" )      alliesCount++;
            else if ( team == "axis" )   axisCount++;
        }

        newState = "neutral";
        if ( alliesCount > 0 && axisCount > 0 )   newState = "contested";
        else if ( alliesCount > 0 )                newState = "allies";
        else if ( axisCount   > 0 )                newState = "axis";

        if ( newState == curState )
            continue;

        oldState = curState;
        curState  = newState;

        gf_setOvertimeZoneIconColor( zone, curState );
        setDvar( "scr_obj" + label + "_flash", int( curState != "neutral" ) );
        setDvar( "scr_obj" + label, curState );

        if ( isDefined( zone.objPoints ) )
        {
            if ( curState != "neutral" && curState != "contested" && isDefined( zone.objPoints[curState] ) )
                zone.objPoints[curState] thread maps\mp\gametypes\_objpoints::startFlashing();
            if ( oldState != "neutral" && oldState != "contested" && isDefined( zone.objPoints[oldState] ) )
                zone.objPoints[oldState] thread maps\mp\gametypes\_objpoints::stopFlashing();
        }

        if ( oldState == "neutral" && curState != "neutral" )
        {
            gf_pauseOvertimeForCapture();
        }
        else if ( oldState != "neutral" && curState == "neutral" )
        {
            if ( !isDefined( level.gf_overtimeResolving ) || !level.gf_overtimeResolving )
                gf_resumeOvertimeForCapture();
        }
    }
}

gf_cleanupOvertimeZone( zone )
{
    if ( !isDefined( zone ) )
        return;

    if ( isDefined( zone.baseFxHandle ) )
        zone.baseFxHandle delete();
    zone.baseFxHandle = undefined;
    zone.baseFxPos    = undefined;

    zone.interactTeam = "none";
    zone.onUse        = undefined;
    zone.curProgress  = 0;
    zone.claimTeam    = "none";
    zone.claimPlayer  = undefined;

    // Reset ownerTeam before hiding so updateCompassIcons sees a clean state.
    zone maps\mp\gametypes\_gameobjects::setOwnerTeam( "neutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );

    // Delete objectives so their IDs are freed each round (they accumulate otherwise).
    if ( isDefined( zone.objIDAllies ) )
        objective_delete( zone.objIDAllies );
    if ( isDefined( zone.objIDAxis ) )
        objective_delete( zone.objIDAxis );

    // Delete 3D objPoint HUD elements. Custom trigger maps spawn a new trigger entity
    // each overtime round (new entNum → new name), so _gameobjects won't recycle them.
    if ( isDefined( zone.objPoints ) )
    {
        if ( isDefined( zone.objPoints["allies"] ) )
            maps\mp\gametypes\_objpoints::deleteObjPoint( zone.objPoints["allies"] );
        if ( isDefined( zone.objPoints["axis"] ) )
            maps\mp\gametypes\_objpoints::deleteObjPoint( zone.objPoints["axis"] );
        zone.objPoints = [];
    }

    if ( isDefined( zone.spawnedModel ) )
        zone.spawnedModel delete();

    if ( isDefined( zone.customTrigger ) )
        zone.customTrigger delete();
}

// Re-registers the OT apron FX handles. MUST run every OT entry, not just at
// precache: onPrecacheGameType runs once per match (guarded by game["gamestarted"]),
// but _globallogic::endGame does map_restart(true) between rounds, which wipes all
// level.* vars — so the handles set at precache are undefined by round 2. loadfx()
// at runtime re-establishes them. The custom .efx live in mod.ff and stay in the
// loaded zone for the whole server session, so loadfx finds them every round.
gf_loadOvertimeApronFx()
{
    // The apron is WORLD-SPACE FX — it renders identically for every player, so it
    // physically cannot be team-relative (T5 has no per-team FX visibility). It is an
    // absolute "zone activity" cue:  idle = white, capturing (either team) = gold,
    // contested = red.  The team-relative friendly/enemy color (green/red) lives on
    // the 3D icon instead (newTeamHudElem, per-team).  White is the custom mod.ff halo;
    // gold/red are stock common_mp_fx ground markers (always runtime-loadable). loadfx
    // is re-called every OT entry because map_restart(true) between rounds wipes these
    // level.* handles.
    whiteFx = loadfx( "misc/fx_ui_flagbase_gf_white" );            // custom (mod.ff)
    goldFx  = loadfx( "env/light/fx_ray_grnd_loc_marker_ylw_mp" ); // stock (yellow ~ gold)
    redFx   = loadfx( "env/light/fx_ray_grnd_loc_marker_red_mp" ); // stock

    level.gf_ot_baseFx_neutral   = whiteFx;   // nobody capturing
    level.gf_ot_baseFx_allies    = goldFx;    // a team is capturing
    level.gf_ot_baseFx_axis      = goldFx;    // ...same gold regardless of which team
    level.gf_ot_baseFx_contested = redFx;     // both teams contesting
}

gf_createOvertimeZone()
{
    flagTrigger = gf_getOvertimeFlagTrigger();
    if ( !isDefined( flagTrigger ) )
        return undefined;

    // Refresh FX handles wiped by the previous round's map_restart.
    gf_loadOvertimeApronFx();

    traceStart = flagTrigger.origin + ( 0, 0, 32 );
    traceEnd   = flagTrigger.origin + ( 0, 0, -256 );
    trace      = bulletTrace( traceStart, traceEnd, false, undefined );
    upAngles   = vectorToAngles( trace["normal"] );
    fxFwd      = anglesToForward( upAngles );
    fxRight    = anglesToRight( upAngles );
    fxPos      = trace["position"] + ( 0, 0, 1 );

    // Use the map-linked visual if it exists; otherwise spawn one
    if ( isDefined( flagTrigger.target ) )
    {
        flagModel        = getEnt( flagTrigger.target, "targetname" );
        spawnedModel     = undefined;
    }
    else
    {
        flagModel        = spawn( "script_model", flagTrigger.origin );
        flagModel.angles = flagTrigger.angles;
        spawnedModel     = flagModel;
    }
    flagModel setModel( "mp_flag_neutral" );

    visuals    = [];
    visuals[0] = flagModel;

    zone = maps\mp\gametypes\_gameobjects::createUseObject( "neutral", flagTrigger, visuals, ( 0, 0, 100 ) );

    zone maps\mp\gametypes\_gameobjects::allowUse( "any" );
    zone maps\mp\gametypes\_gameobjects::setUseTime( gf_getCaptureTime() );
    zone maps\mp\gametypes\_gameobjects::setUseText( &"MP_CAPTURING_FLAG" );
    gf_setOvertimeZoneIcons( zone, "captureneutral", "captureneutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "any" );
    zone.onUse           = ::gf_onZoneCapture;
    zone.spawnedModel    = spawnedModel;
    zone.didStatusNotify = false;

    if ( isDefined( flagTrigger.gf_customOvertimeTrigger ) && flagTrigger.gf_customOvertimeTrigger )
        zone.customTrigger = flagTrigger;

    zone.flagModel   = flagModel;
    zone.gf_flagTrigger = flagTrigger;   // capture point for the bot OT AI
    zone.baseFxPos   = fxPos;
    zone.baseFxFwd   = fxFwd;
    zone.baseFxRight = fxRight;
    gf_setOvertimeZoneIconColor( zone, "neutral" );

    level thread gf_overtimeZoneVisuals( zone, flagTrigger );

    return zone;
}

gf_getOvertimeFlagTrigger()
{
    flag = gf_findDominationBFlag();

    // Large mode plays the full map, so the OT objective sits at the native
    // Domination B (neutral/center) flag. Only small mode moves it to the
    // curated, shrunk-zone overtime spot.
    if ( !level.gf_largeMode && isDefined( level.gf_customOvertimeLocation ) )
    {
        if ( isDefined( flag ) )
        {
            gf_applyCustomOvertimeLocationToFlag( flag, level.gf_customOvertimeLocation );
            return flag;
        }

        return gf_spawnCustomOvertimeTrigger( level.gf_customOvertimeLocation );
    }

    return flag;
}

gf_findDominationBFlag()
{
    flags = getEntArray( "flag_primary", "targetname" );
    flag = undefined;
    for ( i = 0; i < flags.size; i++ )
    {
        if ( isDefined( flags[i].script_label ) && flags[i].script_label == "_b" )
        {
            flag = flags[i];
            break;
        }
    }

    if ( !isDefined( flag ) && flags.size > 0 )
        flag = flags[ int( flags.size / 2 ) ];

    return flag;
}

gf_applyCustomOvertimeLocationToFlag( flag, location )
{
    flag.origin = location["origin"];
    flag.angles = location["angles"];

    if ( !isDefined( flag.target ) )
        return;

    visuals = getEntArray( flag.target, "targetname" );
    for ( i = 0; i < visuals.size; i++ )
    {
        visuals[i].origin = location["origin"];
        visuals[i].angles = location["angles"];
    }
}

gf_spawnCustomOvertimeTrigger( location )
{
    radius = 96;
    height = 96;

    if ( isDefined( location["radius"] ) )
        radius = location["radius"];
    if ( isDefined( location["height"] ) )
        height = location["height"];

    trigger = spawn( "trigger_radius", location["origin"], 0, radius, height );
    trigger.angles = location["angles"];
    trigger.gf_customOvertimeTrigger = true;

    return trigger;
}

gf_onZoneCapture( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) ) return;
    if ( isDefined( level.gf_overtimeResolving ) && level.gf_overtimeResolving ) return;

    player gf_awardOvertimeCapture();
    level.gf_endReasonText = gf_reasonText( "capture", player.pers["team"] );
    gf_resolveOvertime( player.pers["team"] );
}

// ─── Bot Overtime Capture AI ───────────────────────────────────────────────
// Bots have no built-in concept of our overtime flag, so during OT we steer
// them onto it the same way stock bots cap a DOM flag (_bot_script::bot_cap_get_flag):
// lock the goal and SetScriptGoal onto the flag. The OT flag is a _gameobjects
// PROXIMITY object (its trigger is a trigger_radius, so createUseObject runs
// useObjectProxThink, NOT the hold-USE useObjectUseThink) — so simply STANDING
// in the trigger accrues curProgress and fires zone.onUse ( = gf_onZoneCapture ).
// No button press, no custom capture logic — just navigation, like a human walking on.
// Threads die on gf_ot_done / game_ended; the leftover goal+lock are reset by
// the round's map_restart, and the killcam hides any brief leftover camp.
gf_botOvertimeAI( zone )
{
    level endon( "game_ended" );
    level endon( "gf_ot_done" );

    if ( !isDefined( zone ) || !isDefined( zone.gf_flagTrigger ) )
        return;

    flagTrigger = zone.gf_flagTrigger;

    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( !isDefined( p ) ) continue;
        if ( !isDefined( p.pers["isBot"] ) || !p.pers["isBot"] ) continue;
        if ( p.pers["team"] != "allies" && p.pers["team"] != "axis" ) continue;
        if ( !isAlive( p ) ) continue;

        p thread gf_botPursueOvertimeZone( flagTrigger );
    }
}

gf_botPursueOvertimeZone( flagTrigger )
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );
    level endon( "gf_ot_done" );

    if ( !isDefined( flagTrigger ) )
        return;

    // Small radius so the bot stops standing ON the flag (well inside the
    // trigger), matching the stock DOM cap goal. Standing is all it takes —
    // useObjectProxThink accrues the capture while the bot touches.
    radius = 32;

    // Lock BEFORE setting the goal; the "new_goal" notify makes any think thread
    // already parked on its own goal release it to us without clearing it.
    self.bot_lock_goal = true;
    self gf_botSetGoal( flagTrigger.origin, radius );

    // Keep the bot camped on the flag for the whole OT; re-assert the goal if it
    // gets knocked off so it walks back. The proximity think does the capturing.
    for ( ;; )
    {
        wait 1;

        if ( !isDefined( flagTrigger ) )
            break;

        if ( !self isTouching( flagTrigger ) )
            self gf_botSetGoal( flagTrigger.origin, radius );
    }
}

// Local copy of the stock _bot_utility::SetBotGoal wrapper so this file carries
// no bot-script dependency. The waittillframeend + "new_goal" notify is what
// lets us take a goal away from a bot's own AI without it being cleared back.
gf_botSetGoal( origin, radius )
{
    self SetScriptGoal( origin, radius );
    waittillframeend;
    self notify( "new_goal" );
}


// Called by _globallogic to determine the overall match leader at round end.
// Must compare cumulative roundswon — NOT the single-round result.
gf_onRoundEndGame()
{
    if ( game["roundswon"]["allies"] == game["roundswon"]["axis"] )
        return "tie";
    else if ( game["roundswon"]["axis"] > game["roundswon"]["allies"] )
        return "axis";
    return "allies";
}

// ─── Optional Callbacks ────────────────────────────────────────────────────

gf_onPlayerKilled( eInflictor, attacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration )
{
    // On death, every player who damaged the victim (killer and assisters alike)
    // sees a popup with their own exact damage share — no floor.
    victimKey = "v" + int( self.entnum );

    // Cap: recorded damage can overshoot applied damage (recorded pre-mitigation),
    // so never show more than one player's worth of health for a single death.
    cap = 100;
    if ( isDefined( self.maxhealth ) && self.maxhealth > 0 )
        cap = self.maxhealth;

    if ( isDefined( self.gf_assisters ) )
    {
        // Popups first in their own pass — a hiccup in the score/assist bookkeeping
        // below must never block a later damager's popup.
        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            damager = self.gf_assisters[i];
            if ( !isDefined( damager ) || !isPlayer( damager ) ) continue;
            if ( !isDefined( damager.gf_dmgOnTarget ) || !isDefined( damager.gf_dmgOnTarget[victimKey] ) ) continue;

            popup = damager.gf_dmgOnTarget[victimKey];
            damager.gf_dmgOnTarget[victimKey] = undefined;
            if ( popup > cap )
                popup = cap;

            logPrint( "GF_POPUP: " + self.name + " died, " + damager.name + " share " + popup + "\n" );

            // Text popups instead of damage numbers: killer sees "Elimination"
            // (priority 2), every other damager sees "Assist" (priority 1).
            // Localized istrings from gf.str (mod.ff) — raw string literals here would
            // allocate from the dynamic string table, which can be exhausted (the raw
            // "Elimination" literal silently failed to render for exactly that reason).
            if ( !isDefined( damager.pers["isBot"] ) || !damager.pers["isBot"] )
            {
                if ( isDefined( attacker ) && damager == attacker )
                    damager thread gf_showScorePopup( 2, 2 );   // type 2 = elimination, pri 2
                else
                    damager thread gf_showScorePopup( 1, 1 );   // type 1 = assist, pri 1
            }
        }

        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            damager = self.gf_assisters[i];
            if ( !isDefined( damager ) || !isPlayer( damager ) ) continue;

            damager gf_syncDamageScore();

            if ( !isDefined( attacker ) || damager != attacker )
                maps\mp\gametypes\_globallogic_score::givePlayerScore( "assist", damager );
        }
        self.gf_assisters = [];
    }

    gf_forceHealthHUDUpdate();

    if ( isDefined( level.gf_roundActive ) && level.gf_roundActive )
    {
        victimTeam = self.pers["team"];
        if ( victimTeam == "allies" || victimTeam == "axis" )
        {
            otherTeam = maps\mp\_utility::getOtherTeam( victimTeam );
            maps\mp\_utility::playSoundOnPlayers( "mpl_flagdrop_sting_friend", victimTeam );
            maps\mp\_utility::playSoundOnPlayers( "mpl_flagget_sting_friend",  otherTeam );
        }
    }
}

gf_onPlayerDisconnect()
{
    gf_queueHealthHUDUpdate();
}

gf_onPlayerDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime )
{
    if ( iDamage <= 0 )
        return iDamage;

    if ( self.sessionstate == "playing" && isDefined( self.health ) && self.health > 0 )
        gf_queueHealthHUDUpdate();

    if ( !isDefined( eAttacker ) || !isPlayer( eAttacker ) || eAttacker == self )
        return iDamage;

    if ( !isDefined( self.pers["team"] ) || !isDefined( eAttacker.pers["team"] ) )
        return iDamage;

    if ( self.pers["team"] == eAttacker.pers["team"] )
        return iDamage;

    if ( self.sessionstate != "playing" || eAttacker.sessionstate != "playing" )
        return iDamage;

    hp = self.health;
    if ( hp <= 0 )
        return iDamage;

    if ( isDefined( level.gf_headshotsOnly ) && level.gf_headshotsOnly )
    {
        if ( sHitLoc != "head" && sHitLoc != "helmet" )
            return 0;
    }

    damage = iDamage;
    if ( damage > hp )
        damage = hp;

    if ( damage > 0 )
    {
        if ( !isDefined( eAttacker.pers["gf_damage"] ) )
            eAttacker.pers["gf_damage"] = 0;

        eAttacker.pers["gf_damage"] += damage;
        gf_setPlayerScoreSilent( eAttacker, eAttacker.pers["gf_damage"] );

        // Per-target damage for kill popup
        victimKey = "v" + int( self.entnum );
        if ( !isDefined( eAttacker.gf_dmgOnTarget ) )
            eAttacker.gf_dmgOnTarget = [];
        if ( !isDefined( eAttacker.gf_dmgOnTarget[victimKey] ) )
            eAttacker.gf_dmgOnTarget[victimKey] = 0;
        eAttacker.gf_dmgOnTarget[victimKey] += damage;

        // Track unique assisters on the victim for assist awarding on kill
        if ( !isDefined( self.gf_assisters ) )
            self.gf_assisters = [];
        alreadyTracked = false;
        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            if ( self.gf_assisters[i] == eAttacker ) { alreadyTracked = true; break; }
        }
        if ( !alreadyTracked )
            self.gf_assisters[self.gf_assisters.size] = eAttacker;

        gf_queueHealthHUDUpdate();
    }

    return iDamage;
}

gf_initDamageScoring()
{
    if ( !isDefined( game["gf_damage_match"] ) )
        game["gf_damage_match"] = gettime();

    if ( isDefined( game["gf_damage_init"] ) )
        return;

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        player.pers["gf_damage"] = 0;
        player.pers["gf_damage_match"] = game["gf_damage_match"];
        player gf_syncDamageScore();
    }

    game["gf_damage_init"] = 1;
}

gf_syncCaptureScore()
{
    if ( !isDefined( self.pers["captures"] ) )
        self.pers["captures"] = 0;

    self.captures = self.pers["captures"];
}

gf_awardOvertimeCapture()
{
    if ( !isDefined( self.pers["captures"] ) )
        self.pers["captures"] = 0;

    self.pers["captures"]++;
    self.captures = self.pers["captures"];
}

gf_initDamageScore()
{
    if ( !isDefined( game["gf_damage_match"] ) )
        game["gf_damage_match"] = gettime();

    if ( !isDefined( self.pers["gf_damage_match"] ) || self.pers["gf_damage_match"] != game["gf_damage_match"] )
    {
        self.pers["gf_damage"] = 0;
        self.pers["gf_damage_match"] = game["gf_damage_match"];
    }

    self gf_syncDamageScore();
}

gf_syncDamageScore()
{
    if ( !isDefined( self.pers["gf_damage"] ) )
        self.pers["gf_damage"] = 0;

    gf_setPlayerScoreSilent( self, self.pers["gf_damage"] );
}

// Sets player score without triggering updateRankScoreHUD popup.
// The default _setPlayerScore calls updateRankScoreHUD for private matches,
// which shows a score delta popup on every damage event.
gf_setPlayerScoreSilent( player, score )
{
    if ( score == player.pers["score"] )
        return;
    player.pers["score"] = score;
    player.score         = player.pers["score"];
    player notify( "update_playerscore_hud" );
}

gf_queueHealthHUDUpdate()
{
    if ( isDefined( level.gf_healthUpdateQueued ) && level.gf_healthUpdateQueued )
        return;

    level.gf_healthUpdateQueued = true;
    level thread gf_doQueuedHealthHUDUpdate();
}

gf_doQueuedHealthHUDUpdate()
{
    wait 0.05;
    level.gf_healthUpdateQueued = false;

    gf_forceHealthHUDUpdate();
}

gf_forceHealthHUDUpdate()
{
    level notify( "gf_health_hud_update" );
}

gf_onOneLeftEvent( team )
{
    if ( isDefined( level.gf_roundEnding ) && level.gf_roundEnding )
        return;

    if ( !isDefined( level.gf_roundActive ) || !level.gf_roundActive )
        return;

    if ( team != "allies" && team != "axis" )
        return;

    if ( !isDefined( level.gf_warnedLastPlayer ) )
        level.gf_warnedLastPlayer = [];

    if ( isDefined( level.gf_warnedLastPlayer[team] ) )
        return;

    level.gf_warnedLastPlayer[team] = true;

    // onOneLeftEvent fires when level.aliveCount[team] == 1, so the engine-maintained
    // level.alivePlayers[team] holds exactly that last living player at index 0.
    if ( level.alivePlayers[team].size <= 0 )
        return;
    player = level.alivePlayers[team][0];

    player maps\mp\gametypes\_globallogic_audio::leaderDialogOnPlayer( "last_one" );
    player playLocalSound( "mus_last_stand" );
}

gf_onRoundSwitch()
{
    if ( !isDefined( game["switchedsides"] ) )
        game["switchedsides"] = false;

    game["switchedsides"] = !game["switchedsides"];
    level.halftimeType = "halftime";

    maps\mp\gametypes\_globallogic::resetOutcomeForAllPlayers();
}

// ─── Utilities ─────────────────────────────────────────────────────────────

// Sum of living HP for a team. level.alivePlayers[team] is the engine-maintained array of
// alive, playing players on that team (built in _globallogic::updateTeamStatus), so it's
// exactly the set the old all-players scan filtered to. The health>0 guard is redundant
// (alive implies it) but kept defensive.
gf_getTeamHP( team )
{
    total = 0;
    arr = level.alivePlayers[team];
    for ( i = 0; i < arr.size; i++ )
    {
        p = arr[i];
        if ( isDefined( p ) && isDefined( p.health ) && p.health > 0 )
            total += p.health;
    }
    return total;
}

gf_getHPWinner()
{
    alliesHP = gf_getTeamHP( "allies" );
    axisHP   = gf_getTeamHP( "axis"   );

    if ( alliesHP > axisHP )
        return "allies";
    if ( axisHP > alliesHP )
        return "axis";

    return "tie";
}

// Neutral round-end reason string for the native WIN/LOSS banner subtitle
// (outcomeText in _hud_message::teamOutcomeNotify, fed via endGame's 2nd arg).
// The banner header is already team-relative (ROUND WIN / ROUND LOSS / ROUND DRAW),
// so the subtitle states the absolute reason — matching stock SD ("BOMB DEFUSED").
// reason: "capture" (OT flag taken) | "health" (timer/OT decided by total HP) |
//         "elim" (a team fully wiped out). winner == "tie" => draw wording.
gf_reasonText( reason, winner )
{
    isTie = ( !isDefined( winner ) || winner == "tie" );

    if ( reason == "capture" )
        return "Objective captured";

    if ( reason == "elim" )
    {
        if ( isTie )
            return "Both teams eliminated";
        return "Team eliminated";
    }

    // health
    if ( isTie )
        return "Time expired - equal health";
    return "Time expired - health advantage";
}
