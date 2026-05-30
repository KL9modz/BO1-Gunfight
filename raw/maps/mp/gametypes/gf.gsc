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

    maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar(   level.gameType, 3, 0, 9    );
    maps\mp\gametypes\_globallogic_utils::registerTimeLimitDvar(     level.gameType, 1, 0, 1440 );
    maps\mp\gametypes\_globallogic_utils::registerNumLivesDvar(      level.gameType, 1, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerRoundWinLimitDvar( level.gameType, 6, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerScoreLimitDvar(    level.gameType, 6, 0, 500  );
    maps\mp\gametypes\_globallogic_utils::registerRoundLimitDvar(    level.gameType, 0, 0, 15   );
    maps\mp\gametypes\_weapons::registerGrenadeLauncherDudDvar( level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_weapons::registerThrownGrenadeDudDvar(   level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_weapons::registerKillstreakDelay(        level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_globallogic::registerFriendlyFireDelay(  level.gameType, 0, 0, 1440 );

    level.teamBased           = true;
    level.overrideTeamScore   = true;
    level.endGameOnScoreLimit = false;

    level.onPrecacheGameType   = ::onPrecacheGameType;
    level.onStartGameType      = ::onStartGameType;
    level.onSpawnPlayer        = ::onSpawnPlayer;
    level.onSpawnPlayerUnified = ::onSpawnPlayerUnified;
    level.playerSpawnedCB      = ::gf_playerSpawnedCB;
    level.onPlayerKilled       = ::gf_onPlayerKilled;
    level.onDeadEvent          = ::gf_onDeadEvent;
    level.onOneLeftEvent       = ::gf_onOneLeftEvent;
    level.onTimeLimit          = ::gf_onTimeLimit;
    level.onRoundSwitch        = ::gf_onRoundSwitch;
    level.onRoundEndGame       = ::gf_onRoundEndGame;
    level.giveCustomLoadout    = ::gf_giveCustomLoadout;

    game["dialog"]["gametype"] = "sd_start";

    setscoreboardcolumns( "kills", "deaths", "none", "none" );

    replacefunc(
        maps\mp\gametypes\_globallogic_ui::beginClassChoice,
        ::gf_bypassClassChoice
    );
}

// ─── Gametype Setup ────────────────────────────────────────────────────────

onPrecacheGameType()
{
    precacheShader( "waypoint_kill" );
    precacheShader( "waypoint_defend" );
    precacheShader( "compass_waypoint_defend" );
    precacheString( &"PLATFORM_PRESS_TO_SPAWN" );
}

onStartGameType()
{
    setDvar( "scr_player_healthregentime", "0" );
    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 99999;
    level.gf_cfg_roundsPerLoadout        = 2;

    level.gf_roundActive     = false;
    level.gf_roundNum        = 0;
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
    maps\mp\gametypes\_rank::registerScoreInfo( "kill",     250 );
    maps\mp\gametypes\_rank::registerScoreInfo( "headshot", 250 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist",   100 );

    game["gf_init"] = undefined;
    gf_initLoadouts();
    gf_pickLoadout();

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
}

// ─── Spawn Pipeline ────────────────────────────────────────────────────────

onSpawnPlayer( teamOverride )
{
    self.sessionstate = "playing";
    self.usingObj     = undefined;
    self.maxhealth    = 100;
    self.health       = self.maxhealth;

    if ( level.inGracePeriod )
    {
        // Round start — use fixed team start positions
        spawnPoints = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_" + self.pers["team"] + "_start" );

        if ( !spawnPoints.size )
            spawnPoints = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sab_spawn_" + self.pers["team"] + "_start" );

        if ( spawnPoints.size )
            spawnPoint = maps\mp\gametypes\_spawnlogic::getSpawnpoint_Random( spawnPoints );
        else
        {
            spawnPoints = maps\mp\gametypes\_spawnlogic::getTeamSpawnPoints( self.pers["team"] );
            spawnPoint  = maps\mp\gametypes\_spawnlogic::getSpawnpoint_NearTeam( spawnPoints );
        }
    }
    else
    {
        // Mid-round (spectator joining, etc.) — use intelligent spawn selection
        spawnPoints = maps\mp\gametypes\_spawnlogic::getTeamSpawnPoints( self.pers["team"] );
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

// ─── Class Select Bypass ───────────────────────────────────────────────────

gf_bypassClassChoice()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    self.pers["class"] = level.defaultClass;
    self.class         = level.defaultClass;

    self thread maps\mp\gametypes\_spectating::setSpectatePermissionsForMachine();

    if ( self.sessionstate != "playing" )
        self thread [[level.spawnClient]]();

    level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
}
