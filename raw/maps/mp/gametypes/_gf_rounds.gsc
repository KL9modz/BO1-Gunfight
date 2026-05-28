// Gunfight v3 — Round Management
// _globallogic::endGame handles scoring, win-limit, intermission, and respawn.

#include maps\mp\gametypes\_gf_loadouts;

// ─── Player Lifecycle ──────────────────────────────────────────────────────

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );
    self thread gf_onSpawned();
}

gf_onSpawned()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

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
    level.gf_timerEnd = gettime() + 60 * 1000;   // placeholder; real timer driven by scr_gf_timelimit dvar
    wait 0.2;

    if ( level.gf_roundActive )
    {
        level.gf_activatingRound = false;
        return;
    }

    level.gf_roundNum++;
    level.gf_roundEnding     = false;
    level.gf_roundActive     = true;
    level.gf_activatingRound = false;

    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    wait 3;
    maps\mp\gametypes\_globallogic_utils::resumeTimer();
}

// ─── Round End ─────────────────────────────────────────────────────────────

gf_onDeadEvent( team )
{
    if ( level.gf_roundEnding ) return;
    if ( !level.gf_roundActive ) return;

    level.gf_roundEnding = true;
    level.gf_roundActive = false;
    level notify( "gf_round_over" );

    if ( team == "all" )
        winner = game["defenders"];
    else
        winner = maps\mp\_utility::getOtherTeam( team );

    game["gf_winner"] = winner;
    gf_pickLoadout();
    maps\mp\gametypes\_globallogic::endGame( winner, "" );
}

gf_onTimeLimit()
{
    if ( level.gf_roundEnding ) return;
    if ( !level.gf_roundActive ) return;

    level.gf_roundEnding = true;
    level.gf_roundActive = false;
    level notify( "gf_round_over" );

    alliesHP = gf_getTeamHP( "allies" );
    axisHP   = gf_getTeamHP( "axis" );

    if ( alliesHP > axisHP )
        winner = "allies";
    else if ( axisHP > alliesHP )
        winner = "axis";
    else
        winner = "tie";

    game["gf_winner"] = winner;
    gf_pickLoadout();
    maps\mp\gametypes\_globallogic::endGame( winner, "" );
}

gf_onRoundEndGame()
{
    // _globallogic calls this to get the winner string for the scoreboard
    if ( isDefined( game["gf_winner"] ) )
        return game["gf_winner"];
    return "tie";
}

// ─── Optional Callbacks ────────────────────────────────────────────────────

gf_onPlayerKilled( eInflictor, attacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration )
{
    // stub — hook here for kill-ding, damage score, etc.
}

gf_onOneLeftEvent( team )
{
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "last_one" );
    maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "allies" );
    maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "axis" );
}

gf_onRoundSwitch()
{
    // sides swap automatically via registerRoundSwitchDvar; no extra logic needed
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

gf_getAliveCount( team )
{
    count = 0;
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( p.pers["team"] == team && p.sessionstate == "playing" && p.health > 0 )
            count++;
    }
    return count;
}
