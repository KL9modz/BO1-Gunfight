// Gunfight v3 — Round Management
// _globallogic::endGame handles scoring, win-limit, intermission, and respawn.

#include maps\mp\gametypes\_gf_hud;
#include maps\mp\gametypes\_gf_debug;
#include maps\mp\gametypes\_hud_util;

// ─── Player Lifecycle ──────────────────────────────────────────────────────

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );
    self setClientUIVisibilityFlag( "hud_visible", 1 );
    setMatchFlag( "pregame", 0 );
    self gf_initDamageScore();
    gf_queueHealthHUDUpdate();
    self gf_applyVisualTweaks();
    self thread gf_onSpawned();

    if ( getDvarInt( "gf_debug_spawns" ) == 1 )
        self thread gf_startSpawnRecorder();
    if ( getDvarInt( "gf_debug_ents" ) == 1 )
        self thread gf_startEntityDumper();

    if ( getDvarInt( "gf_debug_spawns" ) == 1 )
        self thread gf_startSpawnRecorder();
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
}

gf_onSpawned()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    self.gf_assisters = [];

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

        level thread gf_roundStartCountdown();
        wait 7;

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

// ─── Round End ─────────────────────────────────────────────────────────────

// Central round-end helper — mirrors sd_endGame().
// Updates game["teamScores"] so the native score bar HUD reflects the win,
// then hands off to _globallogic::endGame() for round cycling / win-limit.
gf_endRound( winner )
{
    level.gf_roundEnding = true;
    level.gf_roundActive = false;
    level notify( "gf_round_over" );

    gf_queueHealthHUDUpdate();

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

    gf_endRound( winner );
}

gf_onTimeLimit()
{
    if ( level.gf_roundEnding ) return;

    alliesHP = gf_getTeamHP( "allies" );
    axisHP   = gf_getTeamHP( "axis"   );

    // OT clock ran out without a capture → HP comparison resolves it
    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
    {
        if ( alliesHP > axisHP )      winner = "allies";
        else if ( axisHP > alliesHP ) winner = "axis";
        else                          winner = "tie";
        level notify( "gf_ot_done", winner );
        return;
    }

    // Both sides still alive → overtime
    if ( alliesHP > 0 && axisHP > 0 )
    {
        level thread gf_overtime();
        return;
    }

    if ( alliesHP > axisHP )      winner = "allies";
    else if ( axisHP > alliesHP ) winner = "axis";
    else                          winner = "tie";

    gf_endRound( winner );
}

gf_overtime()
{
    level endon( "game_ended" );

    level.gf_overtimeActive = true;

    maps\mp\gametypes\_globallogic_utils::pauseTimer();

    for ( i = 0; i < level.players.size; i++ )
        level.players[i] iPrintLnBold( "OVERTIME" );
    maps\mp\_utility::playSoundOnPlayers( "mp_sd_bomb_warning", undefined );

    // Wind the clock back 15 s before resuming so the native timer counts down from 0:15
    level.discardTime += 15000;
    maps\mp\gametypes\_globallogic_utils::resumeTimer();

    // Ensure _gameobjects vars are ready (guarded in case _gameobjects::init was skipped)
    if ( !isDefined( level.numGametypeReservedObjectives ) )
        level.numGametypeReservedObjectives = 0;
    if ( !isDefined( level.releasedObjectives ) )
        level.releasedObjectives = [];

    // State vars mirrored from dom.gsc for onBeginUse / statusDialog
    if ( !isDefined( level.lastDialogTime ) )  level.lastDialogTime = 0;
    if ( !isDefined( level.lastStatus ) )      level.lastStatus = [];
    if ( !isDefined( level.lastStatus["allies"] ) ) level.lastStatus["allies"] = 0;
    if ( !isDefined( level.lastStatus["axis"]   ) ) level.lastStatus["axis"]   = 0;

    zone = gf_createOvertimeZone();

    level waittill( "gf_ot_done", winner );

    level.gf_overtimeActive = false;
    if ( isDefined( zone ) && isDefined( zone.spawnedModel ) )
        zone.spawnedModel delete();

    gf_endRound( winner );
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
    zone maps\mp\gametypes\_gameobjects::setUseTime( 5 );
    zone maps\mp\gametypes\_gameobjects::setUseText( &"MP_CAPTURING_FLAG" );
    zone maps\mp\gametypes\_gameobjects::set2DIcon( "any", "compass_waypoint_captureneutral" );
    zone maps\mp\gametypes\_gameobjects::set3DIcon( "any", "waypoint_captureneutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "any" );
    zone.onUse        = ::gf_onZoneCapture;
    zone.onBeginUse   = ::gf_onZoneBeginUse;
    zone.onEndUse     = ::gf_onZoneEndUse;
    zone.spawnedModel = spawnedModel;
    zone.didStatusNotify = false;

    return zone;
}

gf_onZoneCapture( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) ) return;
    level notify( "gf_ot_done", player.pers["team"] );
}

gf_onZoneBeginUse( player )
{
    label = self maps\mp\gametypes\_gameobjects::getLabel();
    setDvar( "scr_obj" + label + "_flash", 1 );
    self.didStatusNotify = false;

    // For a neutral zone, only the capturing team's objPoint flashes
    if ( isDefined( self.objPoints ) && isDefined( self.objPoints[player.pers["team"]] ) )
        self.objPoints[player.pers["team"]] thread maps\mp\gametypes\_objpoints::startFlashing();
}

gf_onZoneEndUse( team, player, success )
{
    label = self maps\mp\gametypes\_gameobjects::getLabel();
    setDvar( "scr_obj" + label + "_flash", 0 );

    if ( isDefined( self.objPoints ) )
    {
        if ( isDefined( self.objPoints["allies"] ) )
            self.objPoints["allies"] thread maps\mp\gametypes\_objpoints::stopFlashing();
        if ( isDefined( self.objPoints["axis"] ) )
            self.objPoints["axis"] thread maps\mp\gametypes\_objpoints::stopFlashing();
    }
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
        attacker gf_syncDamageScore();

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

    gf_queueHealthHUDUpdate();
}

gf_onPlayerDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime )
{
    if ( iDamage <= 0 )
        return iDamage;

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

    for ( i = 0; i < level.players.size; i++ )
        level.players[i] gf_syncDamageScore();

}

gf_onOneLeftEvent( team )
{
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "last_one" );
    maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "allies" );
    maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "axis" );
}

gf_onRoundSwitch()
{
    if ( !isDefined( game["switchedsides"] ) )
        game["switchedsides"] = false;

    game["switchedsides"] = !game["switchedsides"];
    level.halftimeType = "halftime";

    maps\mp\gametypes\_globallogic::resetOutcomeForAllPlayers();
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "side_switch" );
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

