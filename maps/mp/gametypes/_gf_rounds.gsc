// Gunfight v3 — Round Management
// _globallogic::endGame handles scoring, win-limit, intermission, and respawn.

#include maps\mp\gametypes\_gf_hud;
#include maps\mp\gametypes\_gf_debug;
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

    if ( GetDvar( level.gf_overtimeLimitDvar ) == "" )
        setDvar( level.gf_overtimeLimitDvar, 15 );

    value = GetDvarInt( level.gf_overtimeLimitDvar );
    if ( value < 0 )
    {
        value = 0;
        setDvar( level.gf_overtimeLimitDvar, value );
    }
    else if ( value > 120 )
    {
        value = 120;
        setDvar( level.gf_overtimeLimitDvar, value );
    }

    level.gf_cfg_overtimeLimit = value;
    return value;
}

// ─── Player Lifecycle ──────────────────────────────────────────────────────

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );
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
    self gf_applyVisualTweaks();
    self thread gf_onSpawned();

    // Drive the entire per-player health panel in the PLAYER's own context (create +
    // update + destroy) — T5 client HUD elements don't network if created from a level
    // thread. Mirrors the loadout HUD pattern.
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self thread gf_runHealthHUD();

    if ( getDvarInt( "gf_debug_spawns" ) == 1 )
        self thread gf_startSpawnRecorder();

    if ( getDvarInt( "gf_debug_hud_pool" ) == 1 )
    {
        if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
            self thread gf_startHUDPoolOverlay();
    }

    // One-shot pool headroom measurement — prints "free client HUD elems: N" ~9s after
    // spawn (when the loadout intro is gone and the health panel is fully built).
    if ( getDvarInt( "gf_debug_elem_probe" ) == 1 )
    {
        if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
            self thread gf_debugElemProbe();
    }
}

gf_applyVisualTweaks()
{
    dvar = "scr_" + level.gameType + "_visualtweaks";
    if ( GetDvarInt( dvar ) != 1 )
    {
        self setClientDvar( "r_fog",                "1" );
        self setClientDvar( "r_lightTweakAmbient",  "0"   );
        self setClientDvar( "r_lightGridIntensity", "1"   );
        self setClientDvar( "r_lightGridContrast",  "1"   );
        self setClientDvar( "r_gamma",              "1"   );
        self setClientDvar( "r_fullHDRrendering",   "0"   );
        return;
    }

    self setClientDvar( "r_fog",                "0"   );
    self setClientDvar( "r_lightTweakAmbient",  "0.1" );
    self setClientDvar( "r_lightGridIntensity", "1.1" );
    self setClientDvar( "r_lightGridContrast",  "1.1" );
    self setClientDvar( "r_gamma",              "1.1" );
    self setClientDvar( "r_fullHDRrendering",   "1"   );
}

gf_onSpawnSpectator( origin, angles )
{
    maps\mp\gametypes\_globallogic_defaults::default_onSpawnSpectator( origin, angles );
    gf_queueHealthHUDUpdate();

    // Spectators always see the whole health HUD. Only create the panel if this player
    // doesn't already have one (a dead team player free-looking keeps their existing
    // panel — restarting it here would replay the slide-in every death). Spectators get
    // no loadout intro, so skip the intro wait and show immediately.
    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] ) && !isDefined( self.gf_hudElems ) )
        self thread gf_runHealthHUD( true );
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

    if ( game["roundsplayed"] > 0 )
    {
        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( p.sessionstate == "playing" )
            {
                p freezeControls( 1 );
                if ( isDefined( p.pers["isBot"] ) && p.pers["isBot"] )
                {
                    p.bot_lock_goal = true;
                    p SetScriptGoal( p.origin, 8 );
                }
            }
        }

        maps\mp\gametypes\_globallogic_utils::pauseTimer();
        gf_hideRoundTimerForCountdown();
        level thread gf_roundStartCountdown();
        wait 7;
        maps\mp\gametypes\_globallogic_utils::resumeTimer();
        gf_restoreRoundTimerAfterCountdown();
        gf_playRoundStartDialog();

        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( p.sessionstate == "playing" )
            {
                p freezeControls( 0 );
                if ( isDefined( p.pers["isBot"] ) && p.pers["isBot"] )
                {
                    p.bot_lock_goal = false;
                    p ClearScriptGoal();
                }
            }
        }
    }
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

    level thread maps\mp\gametypes\_killcam::startLastKillcam();
    level thread maps\mp\gametypes\_globallogic::endGame( winner, "" );
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
    gf_endRound( winner );
}

gf_onTimeLimit()
{
    if ( level.gf_roundEnding ) return;

    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
    {
        gf_resolveOvertime( gf_getHPWinner() );
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
            gf_endRound( gf_getHPWinner() );
            return;
        }

        gf_beginOvertime( overtimeLimit );
        return;
    }

    gf_endRound( gf_getHPWinner() );
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
            gf_resolveOvertime( gf_getHPWinner() );
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
    zone maps\mp\gametypes\_gameobjects::setUseTime( 2.5 );
    zone maps\mp\gametypes\_gameobjects::setUseText( &"MP_CAPTURING_FLAG" );
    gf_setOvertimeZoneIcons( zone, "captureneutral", "captureneutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "any" );
    zone.onUse           = ::gf_onZoneCapture;
    zone.spawnedModel    = spawnedModel;
    zone.didStatusNotify = false;

    if ( isDefined( flagTrigger.gf_customOvertimeTrigger ) && flagTrigger.gf_customOvertimeTrigger )
        zone.customTrigger = flagTrigger;

    zone.flagModel   = flagModel;
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

    if ( isDefined( level.gf_customOvertimeLocation ) )
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
    gf_resolveOvertime( player.pers["team"] );
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

            if ( !isDefined( damager.pers["isBot"] ) || !damager.pers["isBot"] )
                damager thread gf_showDamagePopup( popup );
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
