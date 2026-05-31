// Gunfight v3 — Standalone Gametype
// Load: g_gametype gf → loadMod mp_gunfight → map_restart

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_gf_rounds;
#include maps\mp\gametypes\_gf_loadouts;

main()
{
    if ( GetDvar( #"mapname" ) == "mp_background" )
        return;

    maps\mp\gametypes\_globallogic::init();
    maps\mp\gametypes\_callbacksetup::SetupCallbacks();
    maps\mp\gametypes\_globallogic::SetupCallbacks();

    maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar(   level.gameType, 2, 0, 9    );
    maps\mp\gametypes\_globallogic_utils::registerTimeLimitDvar(     level.gameType, 1, 0, 1440 );
    maps\mp\gametypes\_globallogic_utils::registerNumLivesDvar(      level.gameType, 1, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerRoundWinLimitDvar( level.gameType, 0, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerScoreLimitDvar(    level.gameType, 6, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerRoundLimitDvar(    level.gameType, 0, 0, 15   );
    maps\mp\gametypes\_weapons::registerGrenadeLauncherDudDvar( level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_weapons::registerThrownGrenadeDudDvar(   level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_weapons::registerKillstreakDelay(        level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_globallogic::registerFriendlyFireDelay(  level.gameType, 0, 0, 1440 );

    level.roundSwitch = false;
    if ( level.roundswitch > 0 )
        level.roundSwitch = true;

    level.teamBased           = true;
    level.overrideTeamScore   = true;
    level.overridePlayerScore = true;
    level.endGameOnScoreLimit = false;

    level.onPrecacheGameType   = ::onPrecacheGameType;
    level.onStartGameType      = ::onStartGameType;
    level.onSpawnPlayer        = ::onSpawnPlayer;
    level.onSpawnPlayerUnified = ::onSpawnPlayerUnified;
    level.playerSpawnedCB      = ::gf_playerSpawnedCB;
    level.onPlayerKilled       = ::gf_onPlayerKilled;
    level.onPlayerDamage       = ::gf_onPlayerDamage;
    level.onSpawnSpectator     = ::gf_onSpawnSpectator;
    level.onDeadEvent          = ::gf_onDeadEvent;
    level.onOneLeftEvent       = ::gf_onOneLeftEvent;
    level.onTimeLimit          = ::gf_onTimeLimit;
    level.onRoundSwitch        = ::gf_onRoundSwitch;
    level.onRoundEndGame       = ::gf_onRoundEndGame;
    level.giveCustomLoadout    = ::gf_giveCustomLoadout;

    game["dialog"]["gametype"] = "sd_start";

    setscoreboardcolumns( "kills", "deaths", "none", "none" );

}

// ─── Gametype Setup ────────────────────────────────────────────────────────

onPrecacheGameType()
{
    // Score bar — native engine HUD reads these shaders for the round-win display
    precacheShader( "score_bar_bg" );
    precacheShader( "score_bar_allies" );
    precacheShader( "score_bar_opfor" );

    precacheShader( "waypoint_kill" );
    precacheShader( "waypoint_defend" );
    precacheShader( "compass_waypoint_defend" );
    precacheString( &"PLATFORM_PRESS_TO_SPAWN" );
}

onStartGameType()
{
    setDvar( "scr_disable_cac", "1" );
    makeDvarServerInfo( "scr_disable_cac", 1 );
    setDvar( "scr_showperksonspawn", "0" );
    makeDvarServerInfo( "scr_showperksonspawn", 0 );

    setDvar( "scr_player_healthregentime", "0" );
    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 99999;
    gf_registerLoadoutCycleDvar();
    gf_initDamageScoring();

    level.gf_roundActive     = false;
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;

    if ( !isDefined( game["switchedsides"] ) )
        game["switchedsides"] = false;

    setClientNameMode( "auto_change" );

    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "allies", &"OBJECTIVES_TDM" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "axis",   &"OBJECTIVES_TDM" );
    if ( level.splitscreen )
    {
        maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "allies", &"OBJECTIVES_TDM" );
        maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "axis",   &"OBJECTIVES_TDM" );
    }
    else
    {
        maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "allies", &"OBJECTIVES_TDM_SCORE" );
        maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "axis",   &"OBJECTIVES_TDM_SCORE" );
    }
    maps\mp\gametypes\_globallogic_ui::setObjectiveHintText( "allies", &"OBJECTIVES_TDM_HINT" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveHintText( "axis",   &"OBJECTIVES_TDM_HINT" );

    maps\mp\gametypes\_rank::registerScoreInfo( "win",      5   );
    maps\mp\gametypes\_rank::registerScoreInfo( "loss",     1   );
    maps\mp\gametypes\_rank::registerScoreInfo( "tie",      2.5 );
    maps\mp\gametypes\_rank::registerScoreInfo( "kill",      0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "headshot",  0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_75", 0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_50", 0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_25", 0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist",    0 );

    gf_initLoadouts();   // guarded by game["gf_init"] — shuffles once per match
    gf_pickLoadout();    // deterministic: index derived from game["roundsplayed"]

    level.spawnMins = ( 0, 0, 0 );
    level.spawnMaxs = ( 0, 0, 0 );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_allies_start" );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_axis_start" );
    maps\mp\gametypes\_spawnlogic::addSpawnPoints( "allies", "mp_tdm_spawn" );
    maps\mp\gametypes\_spawnlogic::addSpawnPoints( "axis",   "mp_tdm_spawn" );
    maps\mp\gametypes\_spawning::updateAllSpawnPoints();
    level.spawn_allies_start = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_allies_start" );
    level.spawn_axis_start   = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_axis_start" );

    level.mapCenter = maps\mp\gametypes\_spawnlogic::findBoxCenter( level.spawnMins, level.spawnMaxs );
    setMapCenter( level.mapCenter );

    spawnpoint = maps\mp\gametypes\_spawnlogic::getRandomIntermissionPoint();
    setDemoIntermissionPoint( spawnpoint.origin, spawnpoint.angles );

    allowed[0] = "gf";
    maps\mp\gametypes\_gameobjects::main( allowed );

    maps\mp\gametypes\_spawning::create_map_placed_influencers();

    setMatchFlag( "pregame", 0 );
}

// ─── Spawn Pipeline ────────────────────────────────────────────────────────

gf_registerLoadoutCycleDvar()
{
    dvar = "scr_" + level.gameType + "_roundsperloadout";

    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, 2 );

    value = GetDvarInt( dvar );
    if ( value < 1 )
    {
        value = 1;
        setDvar( dvar, value );
    }
    else if ( value > 9 )
    {
        value = 9;
        setDvar( dvar, value );
    }

    level.gf_cfg_roundsPerLoadout = value;
    makeDvarServerInfo( dvar, value );
}

onSpawnPlayer( teamOverride )
{
    self.sessionstate = "playing";
    self.usingObj     = undefined;
    self.maxhealth    = 100;
    self.health       = self.maxhealth;

    spawnTeam = self.pers["team"];
    if ( isDefined( game["switchedsides"] ) && game["switchedsides"] )
        spawnTeam = maps\mp\_utility::getOtherTeam( spawnTeam );

    if ( level.inGracePeriod )
    {
        // Round start — use fixed team start positions
        spawnPoints = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_" + spawnTeam + "_start" );

        if ( !spawnPoints.size )
            spawnPoints = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sab_spawn_" + spawnTeam + "_start" );

        if ( spawnPoints.size )
            spawnPoint = maps\mp\gametypes\_spawnlogic::getSpawnpoint_Random( spawnPoints );
        else
        {
            spawnPoints = maps\mp\gametypes\_spawnlogic::getTeamSpawnPoints( spawnTeam );
            spawnPoint  = maps\mp\gametypes\_spawnlogic::getSpawnpoint_NearTeam( spawnPoints );
        }
    }
    else
    {
        // Mid-round (spectator joining, etc.) — use intelligent spawn selection
        spawnPoints = maps\mp\gametypes\_spawnlogic::getTeamSpawnPoints( spawnTeam );
        spawnPoint  = maps\mp\gametypes\_spawnlogic::getSpawnpoint_NearTeam( spawnPoints );
    }

    self spawn( spawnPoint.origin, spawnPoint.angles, "gf" );
}

onSpawnPlayerUnified()
{
    self.usingObj = undefined;

    if ( level.useStartSpawns && !level.inGracePeriod )
        level.useStartSpawns = false;

    maps\mp\gametypes\_spawning::onSpawnPlayer_Unified();
}


