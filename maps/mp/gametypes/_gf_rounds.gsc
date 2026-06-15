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
    if ( v < lo )
    {
        v = lo;
        setDvar( dvar, v );
    }
    else if ( v > hi )
    {
        v = hi;
        setDvar( dvar, v );
    }
    return v;
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
// large only when BOTH teams have 4+ players; a forced value pins the mode for
// admins/RCON/testing.
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

    counts = gf_countTeams();
    level.gf_largeMode = ( counts["allies"] >= 4 && counts["axis"] >= 4 );
}

// Captures the live team sizes once the round is active and everyone (incl.
// late-added bots) has spawned, persisting the auto decision in game[] for the
// next round's onStartGameType setup. No-op when the mode is force-pinned.
gf_updateAutoTeamMode()
{
    if ( GetDvar( "scr_" + level.gameType + "_teamspawnmode" ) != "auto" )
        return;

    counts = gf_countTeams();
    game["gf_autoLargeMode"] = ( counts["allies"] >= 4 && counts["axis"] >= 4 );
}

gf_countTeams()
{
    counts = [];
    counts["allies"] = 0;
    counts["axis"]   = 0;

    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( !isDefined( players[i].pers["team"] ) )
            continue;

        team = players[i].pers["team"];
        if ( team == "allies" )
            counts["allies"]++;
        else if ( team == "axis" )
            counts["axis"]++;
    }

    return counts;
}

// ─── Player Lifecycle ──────────────────────────────────────────────────────

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );

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
    self setClientDvar( "r_lightTweakAmbient",  "0.1" );
    self setClientDvar( "r_lightGridIntensity", "1.1" );
    self setClientDvar( "r_lightGridContrast",  "1.1" );
    self setClientDvar( "r_gamma",              "1.1" );
    self setClientDvar( "r_fullHDRrendering",   "1"   );
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

    // Spectators always see the whole health HUD. Only create the panel if this player
    // doesn't already have one (a dead team player free-looking keeps their existing
    // panel — restarting it here would replay the slide-in every death).
    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] ) && !isDefined( self.gf_hudElems ) )
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
    else if ( isDefined( level.gf_roundStartFreezeActive ) && level.gf_roundStartFreezeActive )
        self thread gf_freezeLateJoinerForRoundStart();
}

// ─── Round Activation ──────────────────────────────────────────────────────

gf_tryActivateRound()
{
    if ( level.gf_activatingRound )
        return;

    level.gf_activatingRound = true;
    level endon( "game_ended" );

    // 0.2s dedup: let all players finish spawning before opening the round
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

    // Roster is now settled (post 0.2s wait, all spawned) — capture the auto
    // team-size decision for the next round's setup.
    gf_updateAutoTeamMode();

    if ( game["roundsplayed"] > 0 )
    {
        // Flag the freeze window so anyone who spawns DURING the countdown
        // (late-connecting bots, mid-countdown joiners) freezes themselves on
        // spawn instead of slipping past this one-time snapshot loop.
        level.gf_roundStartFreezeActive = true;

        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( p.sessionstate == "playing" )
                p gf_applyRoundStartFreeze();
        }

        maps\mp\gametypes\_globallogic_utils::pauseTimer();
        gf_hideRoundTimerForCountdown();
        level thread gf_roundStartCountdown();
        wait 7;
        maps\mp\gametypes\_globallogic_utils::resumeTimer();
        gf_restoreRoundTimerAfterCountdown();
        gf_playRoundStartDialog();
        gf_showRoundObjective();

        // Closing the window releases the snapshot players (below) and signals
        // any late-joiner freeze threads to self-release.
        level.gf_roundStartFreezeActive = false;

        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( p.sessionstate == "playing" )
                p gf_clearRoundStartFreeze();
        }
    }
}

gf_applyRoundStartFreeze()
{
    self freezeControls( 1 );
    if ( isDefined( self.pers["isBot"] ) && self.pers["isBot"] )
    {
        self.bot_lock_goal = true;
        self SetScriptGoal( self.origin, 8 );
    }
}

gf_clearRoundStartFreeze()
{
    self freezeControls( 0 );
    if ( isDefined( self.pers["isBot"] ) && self.pers["isBot"] )
    {
        self.bot_lock_goal = false;
        self ClearScriptGoal();
    }
}

// A player that spawns mid-countdown missed the snapshot freeze loop. Lock it on
// the spot and self-release when the window closes. We re-assert each tick because
// a freshly spawned bot's bot_on_spawn sets bot_lock_goal=false right after spawn —
// it can race our lock off, so one set isn't enough (the snapshot loop dodges this
// via gf_tryActivateRound's 0.2s pre-wait; a late joiner has no such buffer).
gf_freezeLateJoinerForRoundStart()
{
    self endon( "death" );
    self endon( "disconnect" );

    while ( isDefined( level.gf_roundStartFreezeActive ) && level.gf_roundStartFreezeActive )
    {
        self gf_applyRoundStartFreeze();
        wait 0.5;
    }

    self gf_clearRoundStartFreeze();
}

gf_roundStartCountdown()
{
    level endon( "game_ended" );

    label = createServerFontString( "extrabig", 1.5 );
    label setPoint( "CENTER", "CENTER", 0, -40 );
    label.sort = 1001;
    label.foreground = false;
    label.hidewheninmenu = true;
    label setText( "ROUND BEGINS IN" );

    num = createServerFontString( "extrabig", 2.2 );
    num setPoint( "CENTER", "CENTER", 0, 0 );
    num.sort = 1001;
    num.color = ( 1, 1, 0 );
    num.foreground = false;
    num.hidewheninmenu = true;
    num maps\mp\gametypes\_hud::fontPulseInit();

    tickObj = spawn( "script_origin", ( 0, 0, 0 ) );

    count = 7;
    while ( count > 0 )
    {
        num setValue( count );
        num thread maps\mp\gametypes\_hud::fontPulse( level );
        tickObj playSound( "mpl_ui_timer_countdown" );
        count--;
        wait 1.0;
    }

    tickObj delete();
    num destroyElem();
    label destroyElem();
}

gf_hideRoundTimerForCountdown()
{
    level.gf_preRoundTimeLimitOverride = false;
    if ( isDefined( level.timeLimitOverride ) && level.timeLimitOverride )
        level.gf_preRoundTimeLimitOverride = true;

    level.timeLimitOverride = true;
    setGameEndTime( 0 );
}

gf_restoreRoundTimerAfterCountdown()
{
    if ( isDefined( level.gf_preRoundTimeLimitOverride ) && level.gf_preRoundTimeLimitOverride )
    {
        level.gf_preRoundTimeLimitOverride = undefined;
        return;
    }

    level.gf_preRoundTimeLimitOverride = undefined;
    level.timeLimitOverride = false;

    if ( !isDefined( level.startTime ) || !isDefined( level.timeLimit ) || level.timeLimit <= 0 )
    {
        setGameEndTime( 0 );
        return;
    }

    timeLeft = maps\mp\gametypes\_globallogic_utils::getTimeRemaining();
    if ( timeLeft > 0 )
        setGameEndTime( getTime() + int( timeLeft ) );
    else
        setGameEndTime( 0 );
}

gf_playRoundStartDialog()
{
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "offense_obj", game["attackers"], "introboost" );
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "defense_obj", game["defenders"], "introboost" );
}

// Re-show the gametype objective splash each round — the same stock objective hint
// (_hud_message::hintMessage) that _globallogic shows once at match start
// (prematchPeriod, _globallogic.gsc). This is the visual half; gf_playRoundStartDialog
// above is the VO half. Mirrors _globallogic's per-player hasSpawned guard.
gf_showRoundObjective()
{
    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;
        if ( !isDefined( player.hasSpawned ) || !player.hasSpawned )
            continue;

        hintText = maps\mp\gametypes\_globallogic_ui::getObjectiveHintText( player.pers["team"] );
        if ( !isDefined( hintText ) )
            continue;

        player thread maps\mp\gametypes\_hud_message::hintMessage( hintText );
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
    level.gf_overtimeLastTick      = undefined;
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
    if ( remaining <= 0 || remaining > 15000 )
        return;

    tick = int( ( remaining + 999 ) / 1000 );
    if ( tick < 1 || tick > 15 )
        return;

    if ( isDefined( level.gf_overtimeLastTick ) && level.gf_overtimeLastTick == tick )
        return;

    level.gf_overtimeLastTick = tick;

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
    setGameEndTime( 0 );
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
    level.gf_overtimeLastTick     = undefined;
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

    // Diagnostic for the missing-flag-icon report: server-side state of both objpoints
    // after every icon update. If this logs shown/alpha>0 while a player sees no icon,
    // the element is healthy on the server and the failure is client-side rendering.
    if ( isDefined( zone.objPoints ) && isDefined( zone.objPoints["allies"] ) && isDefined( zone.objPoints["axis"] ) )
    {
        logPrint( "GF_OT: iconstate state=" + team
            + " alliesAlpha=" + zone.objPoints["allies"].alpha + " alliesShown=" + int( zone.objPoints["allies"].isShown )
            + " axisAlpha=" + zone.objPoints["axis"].alpha + " axisShown=" + int( zone.objPoints["axis"].isShown )
            + " x=" + int( zone.objPoints["allies"].x ) + " y=" + int( zone.objPoints["allies"].y ) + " z=" + int( zone.objPoints["allies"].z ) + "\n" );
    }
    else
    {
        logPrint( "GF_OT: iconstate state=" + team + " OBJPOINTS MISSING\n" );
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
    heartbeat = 0;
    logPrint( "GF_OT: visuals thread STARTED label=" + label + "\n" );

    while ( true )
    {
        wait 0.1;

        if ( !isDefined( zone ) || !isDefined( flagTrigger ) )
        {
            logPrint( "GF_OT: visuals thread EXITING - zone or trigger undefined\n" );
            return;
        }

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

        heartbeat++;
        if ( heartbeat >= 50 )
        {
            logPrint( "GF_OT: heartbeat state=" + curState + " al=" + alliesCount + " ax=" + axisCount + "\n" );
            heartbeat = 0;
        }

        if ( newState == curState )
            continue;

        oldState = curState;
        curState  = newState;

        logPrint( "GF_OT: TRANSITION " + oldState + " -> " + curState + " al=" + alliesCount + " ax=" + axisCount + "\n" );
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

    logPrint( "GF_OT: apron FX white=" + int( isDefined( whiteFx ) ) + " gold=" + int( isDefined( goldFx ) ) + " red=" + int( isDefined( redFx ) ) + "\n" );
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

    // Diagnostic for the rare "no icon above the flag" report: if either objpoint is 0
    // here, the server HUD element pool was exhausted at creation time.
    haveAllies = isDefined( zone.objPoints ) && isDefined( zone.objPoints["allies"] );
    haveAxis   = isDefined( zone.objPoints ) && isDefined( zone.objPoints["axis"] );
    logPrint( "GF_OT: zone created entNum=" + zone.entNum + " objpointAllies=" + int( haveAllies ) + " objpointAxis=" + int( haveAxis ) + "\n" );

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

    player = gf_getLastLivingPlayer( team );
    if ( !isDefined( player ) )
        return;

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

gf_getTeamHP( team )
{
    total = 0;
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( p.pers["team"] == team && p.sessionstate == "playing" && p.health > 0 )
            total += p.health;
    }
    return total;
}

gf_getLastLivingPlayer( team )
{
    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        if ( !isDefined( player.pers["team"] ) || player.pers["team"] != team )
            continue;

        if ( player.sessionstate == "playing" && player.health > 0 )
            return player;
    }

    return undefined;
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
