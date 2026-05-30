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

    game["gf_init"] = undefined;
    gf_initLoadouts();
    gf_pickLoadout();

    level.spawnMins = ( 0, 0, 0 );
    level.spawnMaxs = ( 0, 0, 0 );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_sd_spawn_attacker" );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_sd_spawn_defender" );
    level.mapCenter = maps\mp\gametypes\_spawnlogic::findBoxCenter( level.spawnMins, level.spawnMaxs );
    setMapCenter( level.mapCenter );

    spawnpoint = maps\mp\gametypes\_spawnlogic::getRandomIntermissionPoint();
    setDemoIntermissionPoint( spawnpoint.origin, spawnpoint.angles );

    allowed[0] = "gf";
    maps\mp\gametypes\_gameobjects::main( allowed );

    maps\mp\gametypes\_spawning::create_map_placed_influencers();

    level.spawn_allies_start = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_attacker" );
    level.spawn_axis_start   = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_defender" );
}

// ─── Spawn Pipeline ────────────────────────────────────────────────────────

onSpawnPlayer( teamOverride )
{
    self.sessionstate = "playing";
    self.maxhealth    = 100;
    self.health       = self.maxhealth;

    // Match SD pattern: use game["attackers"] not team name so sides stay
    // correct after a round switch
    if ( self.pers["team"] == game["attackers"] )
        spawnPoints = level.spawn_allies_start;
    else
        spawnPoints = level.spawn_axis_start;

    // Fallback: try the other side's points rather than re-trying the same empty array
    if ( !isDefined( spawnPoints ) || !spawnPoints.size )
    {
        spawnPoints = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_attacker" );
        if ( !spawnPoints.size )
            spawnPoints = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_sd_spawn_defender" );
    }

    assert( spawnPoints.size );
    spawnPoint = maps\mp\gametypes\_spawnlogic::getSpawnpoint_Random( spawnPoints );
    self spawn( spawnPoint.origin, spawnPoint.angles, "gf" );
}

onSpawnPlayerUnified()
{
    // fires for all spawn types (including intermission); no-op for one-life mode
}

// ─── Class Select Bypass ───────────────────────────────────────────────────

gf_bypassClassChoice()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    self.pers["class"] = level.defaultClass;
    self.class         = level.defaultClass;

    if ( self.sessionstate != "playing" )
        self thread [[level.spawnClient]]();

    level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
}
