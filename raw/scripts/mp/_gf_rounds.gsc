// Gunfight v2 — Round Management
// SD-native round cycling: we call sd_endGame; SD handles score, win-limit, intermission, respawn

#include scripts\mp\_gf_loadouts;

// ─── Round Activation ──────────────────────────────────────────────────────

gf_tryActivateRound()
{
    if ( level.gf_activatingRound )
        return;

    level.gf_activatingRound = true;
    level endon( "game_ended" );

    // pick loadout for this round (idempotent if same round index)
    gf_pickLoadout();

    // 0.2s dedup grace — multiple players spawning at once all call this;
    // only the first one through should open the round
    wait 0.2;

    if ( level.gf_roundActive )
    {
        level.gf_activatingRound = false;
        return;
    }

    level.gf_roundNum++;
    level.gf_roundEnding    = false;   // SD never resets this between rounds
    level.gf_roundActive    = true;
    level.gf_activatingRound = false;

    // pause SD's native clock during 3s freeze, then let it run
    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    wait 3;
    maps\mp\gametypes\_globallogic_utils::resumeTimer();
}

// ─── Round End ─────────────────────────────────────────────────────────────

gf_onDeadEvent( team )
{
    // override of level.onDeadEvent — suppresses SD bomb logic entirely
    if ( level.gf_roundEnding )
        return;

    level.gf_roundEnding = true;
    level.gf_roundActive = false;
    level notify( "gf_round_over" );

    if ( team == "all" )
        winner = game["defenders"];
    else
        winner = maps\mp\_utility::getOtherTeam( team );

    maps\mp\gametypes\sd::sd_endgame( winner, "" );
}

gf_onTimeLimit()
{
    if ( level.gf_roundEnding )
        return;

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
    {
        // Pass "tie" for the round-end screen text, then undo the increment
        // to game["roundswon"]["tie"] so hitRoundWinLimit never counts draws.
        // endGame is threaded inside sd_endgame; gf_undoTieMark races it —
        // in either order the net change to the tie counter is zero.
        maps\mp\gametypes\sd::sd_endgame( "tie", "" );
        level thread gf_undoTieMark();
        return;
    }

    maps\mp\gametypes\sd::sd_endgame( winner, "" );
}

// ─── Background Threads ────────────────────────────────────────────────────

gf_bombSuppress()
{
    level endon( "game_ended" );
    while ( true )
    {
        wait 0.5;

        if ( isDefined( level.sdBomb ) )
        {
            level.sdBomb maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );
            level.sdBomb maps\mp\gametypes\_gameobjects::allowCarry( "none" );
        }

        if ( isDefined( level.bombZones ) )
        {
            for ( i = 0; i < level.bombZones.size; i++ )
            {
                if ( !isDefined( level.bombZones[i] ) ) continue;
                level.bombZones[i] maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );
                level.bombZones[i] maps\mp\gametypes\_gameobjects::allowUse( "none" );
            }
        }

        level.bombCarrier  = undefined;
        level.bombplanted  = 0;
        level.bombexploded = 0;
        level.bombdefused  = 0;
    }
}

gf_forfeitWatch()
{
    // two consecutive empty-team polls (20s gap) → award win to other team
    level endon( "game_ended" );
    wait 30;   // prematch grace

    while ( true )
    {
        wait 10;

        alliesEmpty = gf_teamIsEmpty( "allies" );
        axisEmpty   = gf_teamIsEmpty( "axis" );

        if ( alliesEmpty || axisEmpty )
        {
            wait 10;

            if ( gf_teamIsEmpty( "allies" ) && !gf_teamIsEmpty( "axis" ) )
                maps\mp\gametypes\_globallogic::endGame( "axis", "GAME_FORFEIT" );
            else if ( gf_teamIsEmpty( "axis" ) && !gf_teamIsEmpty( "allies" ) )
                maps\mp\gametypes\_globallogic::endGame( "allies", "GAME_FORFEIT" );
        }
    }
}

// ─── Utilities ─────────────────────────────────────────────────────────────

gf_undoTieMark()
{
    game["roundswon"]["tie"]--;
    if ( game["roundswon"]["tie"] < 0 )
        game["roundswon"]["tie"] = 0;
}

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

gf_getTeamPlayerCount( team )
{
    count = 0;
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( p.pers["team"] == team && p.sessionstate == "playing" )
            count++;
    }
    return count;
}

gf_teamIsEmpty( team )
{
    return ( gf_getTeamPlayerCount( team ) == 0 );
}
