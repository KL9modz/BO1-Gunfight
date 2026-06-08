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

gf_startHealthHUDConnectWatcher()
{
    level endon( "game_ended" );

    if ( isDefined( level.gf_healthHUDConnectWatcherStarted ) )
        return;

    level.gf_healthHUDConnectWatcherStarted = true;

    if ( isDefined( level.players ) )
    {
        for ( i = 0; i < level.players.size; i++ )
        {
            if ( isDefined( level.players[i] ) && isPlayer( level.players[i] ) )
                level.players[i] thread gf_startPregameHealthHUD();
        }
    }

    while ( true )
    {
        level waittill( "connected", player );

        if ( isDefined( player ) && isPlayer( player ) )
            player thread gf_startPregameHealthHUD();
    }
}

gf_startPregameHealthHUD()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    wait 0.05;

    self thread gf_startHealthHUD();
    self thread gf_startHealthIconGalleryWatcher();

    for ( i = 0; i < 24; i++ )
    {
        gf_queueHealthHUDUpdate();
        wait 0.5;
    }
}

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );
    self setClientUIVisibilityFlag( "hud_visible", 1 );
    setMatchFlag( "pregame", 0 );
    self gf_syncCaptureScore();
    self gf_initDamageScore();
    self thread gf_startHealthHUD();
    self thread gf_startHealthIconGalleryWatcher();
    gf_queueHealthHUDUpdate();
    self gf_applyVisualTweaks();
    self thread gf_onSpawned();

    if ( getDvarInt( "gf_debug_spawns" ) == 1 )
    {
        self thread gf_startSpawnRecorder();
        self thread gf_startCoordsHUD();
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
    self thread gf_startHealthHUD();
    self thread gf_startHealthIconGalleryWatcher();
    gf_queueHealthHUDUpdate();
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
    level.gf_preMatchHealthHUDActive = false;
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
            }
        }

        maps\mp\gametypes\_globallogic_utils::pauseTimer();
        gf_hideRoundTimerForCountdown();
        level.gf_preRoundCountdownActive = true;
        gf_forceHealthHUDUpdate();
        level thread gf_roundStartCountdown();
        wait 7;
        level.gf_preRoundCountdownActive = false;
        gf_forceHealthHUDUpdate();
        maps\mp\gametypes\_globallogic_utils::resumeTimer();
        gf_restoreRoundTimerAfterCountdown();
        gf_playRoundStartDialog();

        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( p.sessionstate == "playing" )
            {
                p freezeControls( 0 );
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

    count = 7;
    while ( count > 0 )
    {
        num setValue( count );
        num thread maps\mp\gametypes\_hud::fontPulse( level );
        count--;
        wait 1.0;
    }

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

    level thread gf_overtimeClock();
    level waittill( "gf_ot_done", winner );

    level.gf_roundEnding = true;
    level.gf_overtimeClockRunning = false;
    gf_cleanupOvertimeZone( zone );
    gf_cleanupOvertimeTimerState();

    gf_endRound( winner );
}

gf_showOvertimeMessage()
{
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "gf_overtime_cue", undefined, "introboost" );

    titleText = &"MP_OVERTIME_CAPS";
    if ( isDefined( game["strings"] ) && isDefined( game["strings"]["overtime"] ) )
        titleText = game["strings"]["overtime"];

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        player thread maps\mp\gametypes\_hud_message::oldNotifyMessage( titleText, undefined, undefined, ( 1, 0, 0 ), undefined );
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

gf_setOvertimeZoneIconColor( zone, team )
{
    if ( !isDefined( zone ) || !isDefined( zone.objPoints ) )
        return;

    neutralColor  = ( 1, 1, 1 );
    friendlyColor = ( 0.4, 0.7, 1.0 );
    enemyColor    = ( 1.0, 0.45, 0.45 );

    if ( team != "allies" && team != "axis" )
    {
        if ( isDefined( zone.objPoints["allies"] ) )
            zone.objPoints["allies"].color = neutralColor;
        if ( isDefined( zone.objPoints["axis"] ) )
            zone.objPoints["axis"].color = neutralColor;
        return;
    }

    otherTeam = "axis";
    if ( team == "axis" )
        otherTeam = "allies";

    if ( isDefined( zone.objPoints[team] ) )
        zone.objPoints[team].color = friendlyColor;
    if ( isDefined( zone.objPoints[otherTeam] ) )
        zone.objPoints[otherTeam].color = enemyColor;
}

gf_cleanupOvertimeZone( zone )
{
    if ( !isDefined( zone ) )
        return;

    zone.interactTeam = "none";
    zone.onUse        = undefined;
    zone.onBeginUse   = undefined;
    zone.onEndUse     = undefined;
    zone.onUseUpdate  = undefined;
    zone.curProgress  = 0;
    zone.claimTeam    = "none";
    zone.claimPlayer  = undefined;
    gf_setOvertimeZoneIconColor( zone, "neutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );

    if ( isDefined( zone.spawnedModel ) )
        zone.spawnedModel delete();
}

gf_createOvertimeZone()
{
    // Find the B flag entity kept alive by allowed[1]="dom" in onStartGameType
    flags = getEntArray( "flag_primary", "targetname" );
    bFlag = undefined;
    for ( i = 0; i < flags.size; i++ )
    {
        if ( isDefined( flags[i].script_label ) && flags[i].script_label == "_b" )
        {
            bFlag = flags[i];
            break;
        }
    }
    if ( !isDefined( bFlag ) && flags.size > 0 )
        bFlag = flags[ int( flags.size / 2 ) ];

    if ( !isDefined( bFlag ) )
        return undefined;

    // Ground-orient and spawn the flag base halo FX (same technique as dom.gsc)
    traceStart = bFlag.origin + ( 0, 0, 32 );
    traceEnd   = bFlag.origin + ( 0, 0, -32 );
    trace      = bulletTrace( traceStart, traceEnd, false, undefined );
    upAngles   = vectorToAngles( trace["normal"] );
    baseFx     = spawnFx( level.gf_ot_baseFx, trace["position"],
                          anglesToForward( upAngles ), anglesToRight( upAngles ) );
    triggerFx( baseFx );

    // Use the map-linked visual if it exists; otherwise spawn one
    if ( isDefined( bFlag.target ) )
    {
        flagModel        = getEnt( bFlag.target, "targetname" );
        spawnedModel     = undefined;
    }
    else
    {
        flagModel        = spawn( "script_model", bFlag.origin );
        flagModel.angles = bFlag.angles;
        spawnedModel     = flagModel;
    }
    flagModel setModel( "mp_flag_neutral" );

    visuals    = [];
    visuals[0] = flagModel;

    zone = maps\mp\gametypes\_gameobjects::createUseObject( "neutral", bFlag, visuals, ( 0, 0, 100 ) );
    zone maps\mp\gametypes\_gameobjects::allowUse( "any" );
    zone maps\mp\gametypes\_gameobjects::setUseTime( 2.5 );
    zone maps\mp\gametypes\_gameobjects::setUseText( &"MP_CAPTURING_FLAG" );
    zone maps\mp\gametypes\_gameobjects::set2DIcon( "friendly", "compass_waypoint_captureneutral" );
    zone maps\mp\gametypes\_gameobjects::set2DIcon( "enemy",    "compass_waypoint_captureneutral" );
    zone maps\mp\gametypes\_gameobjects::set3DIcon( "friendly", "waypoint_captureneutral" );
    zone maps\mp\gametypes\_gameobjects::set3DIcon( "enemy",    "waypoint_captureneutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "any" );
    zone.onUse        = ::gf_onZoneCapture;
    zone.onBeginUse   = ::gf_onZoneBeginUse;
    zone.onEndUse     = ::gf_onZoneEndUse;
    zone.spawnedModel = spawnedModel;
    zone.didStatusNotify = false;
    gf_setOvertimeZoneIconColor( zone, "neutral" );

    return zone;
}

gf_onZoneCapture( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) ) return;
    if ( isDefined( level.gf_overtimeResolving ) && level.gf_overtimeResolving ) return;

    player gf_awardOvertimeCapture();
    gf_resolveOvertime( player.pers["team"] );
}

gf_onZoneBeginUse( player )
{
    label = self maps\mp\gametypes\_gameobjects::getLabel();
    setDvar( "scr_obj" + label + "_flash", 1 );
    setDvar( "scr_obj" + label, player.pers["team"] );
    self.didStatusNotify = false;
    gf_setOvertimeZoneIconColor( self, player.pers["team"] );

    if ( isDefined( self.objPoints ) && isDefined( self.objPoints[player.pers["team"]] ) )
        self.objPoints[player.pers["team"]] thread maps\mp\gametypes\_objpoints::startFlashing();

    gf_pauseOvertimeForCapture();
}

gf_onZoneEndUse( team, player, success )
{
    label = self maps\mp\gametypes\_gameobjects::getLabel();
    setDvar( "scr_obj" + label + "_flash", 0 );
    setDvar( "scr_obj" + label, "neutral" );
    gf_setOvertimeZoneIconColor( self, "neutral" );

    if ( isDefined( self.objPoints ) )
    {
        if ( isDefined( self.objPoints["allies"] ) )
            self.objPoints["allies"] thread maps\mp\gametypes\_objpoints::stopFlashing();
        if ( isDefined( self.objPoints["axis"] ) )
            self.objPoints["axis"] thread maps\mp\gametypes\_objpoints::stopFlashing();
    }

    if ( isDefined( success ) && success )
        return;

    if ( isDefined( level.gf_overtimeResolving ) && level.gf_overtimeResolving )
        return;

    gf_resumeOvertimeForCapture();
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
    if ( isDefined( attacker ) && isPlayer( attacker ) )
    {
        attacker gf_syncDamageScore();
        victimKey = "v" + int( self.entnum );
        if ( isDefined( attacker.gf_dmgOnTarget ) && isDefined( attacker.gf_dmgOnTarget[victimKey] ) )
        {
            attacker thread maps\mp\gametypes\_rank::updateRankScoreHUD( attacker.gf_dmgOnTarget[victimKey] );
            attacker.gf_dmgOnTarget[victimKey] = undefined;
        }
    }

    if ( isDefined( self.gf_assisters ) )
    {
        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            assister = self.gf_assisters[i];
            if ( !isDefined( assister ) || !isPlayer( assister ) ) continue;
            if ( isDefined( attacker ) && assister == attacker ) continue;
            maps\mp\gametypes\_globallogic_score::givePlayerScore( "assist", assister );
        }
        self.gf_assisters = [];
    }

    gf_forceHealthHUDUpdate();
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
    for ( i = 0; i < level.players.size; i++ )
    {
        if ( isDefined( level.players[i] ) )
            level.players[i] gf_syncDamageScore();
    }

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
