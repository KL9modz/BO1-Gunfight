#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_gf_locations;
#include maps\mp\gametypes\_gf_rounds;
#include maps\mp\gametypes\_gf_loadouts;
#include maps\mp\gametypes\_gf_wager_zones;

main()
{
    if ( GetDvar( #"mapname" ) == "mp_background" )
        return;

    maps\mp\gametypes\_globallogic::init();
    maps\mp\gametypes\_callbacksetup::SetupCallbacks();
    maps\mp\gametypes\_globallogic::SetupCallbacks();

    maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar(   level.gameType, 2, 0, 9    );
    maps\mp\gametypes\_globallogic_utils::registerTimeLimitDvar(     level.gameType, 0.75, 0, 1440 );
    maps\mp\gametypes\_globallogic_utils::registerNumLivesDvar(      level.gameType, 1, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerRoundWinLimitDvar( level.gameType, 0, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerScoreLimitDvar(    level.gameType, 6, 0, 10   );
    maps\mp\gametypes\_globallogic_utils::registerRoundLimitDvar(    level.gameType, 0, 0, 15   );

    maps\mp\gametypes\_weapons::registerGrenadeLauncherDudDvar( level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_weapons::registerThrownGrenadeDudDvar(   level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_weapons::registerKillstreakDelay(        level.gameType, 0, 0, 1440 );
    maps\mp\gametypes\_globallogic::registerFriendlyFireDelay(  level.gameType, 0, 0, 1440 );

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
    level.onPlayerDisconnect   = ::gf_onPlayerDisconnect;
    level.onSpawnSpectator     = ::gf_onSpawnSpectator;
    level.onDeadEvent          = ::gf_onDeadEvent;
    level.onOneLeftEvent       = ::gf_onOneLeftEvent;
    level.onTimeLimit          = ::gf_onTimeLimit;
    level.onRoundSwitch        = ::gf_onRoundSwitch;
    level.onRoundEndGame       = ::gf_onRoundEndGame;
    level.giveCustomLoadout    = ::gf_giveCustomLoadout;

    setscoreboardcolumns( "kills", "deaths", "assists", "captures" );

}

onPrecacheGameType()
{
    game["dialog"]["gf_overtime_cue"]    = "ctf_start";
    game["dialog"]["offense_obj"]        = "generic_boost";
    game["dialog"]["defense_obj"]        = "generic_boost";
    game["dialog"]["last_one"]           = "encourage_last";
    game["dialog"]["side_switch"]        = "sd_halftime";

    precacheShader( "score_bar_bg" );
    precacheShader( "score_bar_allies" );
    precacheShader( "score_bar_opfor" );
    precacheShader( "progress_bar_bg" );
    precacheShader( "progress_bar_fill" );
    precacheShader( "progress_bar_fg" );
    precacheShader( "hud_score_progress" );
    precacheShader( "hud_frame_faction_fade" );
    precacheShader( "hud_frame_faction_lines" );
    precacheShader( "hud_death_suicide" );
    precacheString( &"PLATFORM_PRESS_TO_SPAWN" );

    precacheShader( "menu_mp_weapons_famas"    );
    precacheShader( "menu_mp_weapons_python"   );
    precacheShader( "menu_mp_weapons_m16"      );
    precacheShader( "menu_mp_weapons_colt"     );
    precacheShader( "menu_mp_weapons_aug"      );
    precacheShader( "menu_mp_weapons_makarov"  );
    precacheShader( "menu_mp_weapons_galil"    );
    precacheShader( "menu_mp_weapons_cz75"     );
    precacheShader( "menu_mp_weapons_commando" );
    precacheShader( "menu_mp_weapons_fnfal"    );
    precacheShader( "menu_mp_weapons_m14"      );
    precacheShader( "menu_mp_weapons_mp5k"     );
    precacheShader( "menu_mp_weapons_ak74u"    );
    precacheShader( "menu_mp_weapons_mpl"      );
    precacheShader( "menu_mp_weapons_spectre"  );
    precacheShader( "menu_mp_weapons_uzi"      );
    precacheShader( "menu_mp_weapons_pm63"     );
    precacheShader( "menu_mp_weapons_hk21"     );
    precacheShader( "menu_mp_weapons_m60"      );
    precacheShader( "menu_mp_weapons_rpk"      );
    precacheShader( "menu_mp_weapons_stoner63a");
    precacheShader( "menu_mp_weapons_l96a1"    );
    precacheShader( "menu_mp_weapons_wa2000"   );
    precacheShader( "menu_mp_weapons_spas"     );
    precacheShader( "menu_mp_weapons_ithaca"   );
    precacheShader( "menu_mp_weapons_ak47"     );
    precacheShader( "menu_mp_weapons_enfield"  );
    precacheShader( "menu_mp_weapons_g11"      );
    precacheShader( "menu_mp_weapons_kiparis"  );
    precacheShader( "menu_mp_weapons_mac11"    );
    precacheShader( "menu_mp_weapons_skorpion" );
    precacheShader( "menu_mp_weapons_psg1"     );
    precacheShader( "menu_mp_weapons_dragunov" );
    precacheShader( "menu_mp_weapons_rottweil72");
    precacheShader( "menu_mp_weapons_hs10"     );
    precacheShader( "menu_mp_weapons_asp"      );
    precacheShader( "menu_mp_weapons_crossbow"      );
    precacheShader( "menu_mp_weapons_minigun"        );
    precacheShader( "menu_mp_weapons_china_lake"    );
    precacheShader( "menu_mp_weapons_m72_law"       );
    precacheShader( "menu_mp_weapons_rpg"           );
    precacheShader( "hud_m202"                       );
    precacheShader( "menu_mp_weapons_ballistic_knife");
    precacheShader( "hud_grenadeicon"          );
    precacheShader( "hud_icon_satchelcharge"   );
    precacheShader( "hud_icon_sticky_grenade"  );
    precacheShader( "hud_hatchet"              );
    precacheShader( "hud_us_flashgrenade"      );
    precacheShader( "hud_us_stungrenade"       );
    precacheShader( "hud_us_smokegrenade"      );
    precacheShader( "hud_icon_tabun_gasgrenade");
    precacheShader( "hud_nightingale"          );
    precacheShader( "hud_icon_claymore"        );
    precacheShader( "hud_radar_jammer"         );
    precacheShader( "hud_acoustic_sensor"      );
    precacheShader( "hud_deployable_camera"    );

    PrecacheItem( "m202_flash_wager_mp" );
    PrecacheItem( "minigun_wager_mp"    );

    PrecacheItem( "tabun_gas_mp"        );
    PrecacheItem( "nightingale_mp"      );

    gf_loadOvertimeApronFx();

    precacheModel( "mp_flag_neutral" );
    precacheModel( "mp_flag_allies_1" );
    precacheModel( "mp_flag_axis_1" );
    precacheShader( "compass_waypoint_captureneutral" );
    precacheShader( "waypoint_captureneutral" );
    precacheShader( "compass_waypoint_capture" );
    precacheShader( "waypoint_capture" );
    precacheShader( "compass_waypoint_defend" );
    precacheShader( "waypoint_defend" );
    precacheShader( "compass_waypoint_captureneutral_b" );
    precacheShader( "waypoint_captureneutral_b" );
    precacheShader( "compass_waypoint_capture_b" );
    precacheShader( "waypoint_capture_b" );
    precacheString( &"MP_CAPTURING_FLAG" );
    precacheString( &"MP_OVERTIME_CAPS" );
    precacheString( &"GF_POPUP_ELIMINATION" );
    precacheString( &"GF_POPUP_ASSIST" );

    gf_precacheWagerZoneAssets();
}

onStartGameType()
{
    level.noPersistence = true;

    setDvar( "scr_disable_cac", "1" );
    setDvar( "scr_disable_weapondrop", "1" );
    setDvar( "scr_showperksonspawn", "0" );

    dvar = "scr_" + level.gameType + "_visualtweaks";
    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, 1 );

    setDvar( "scr_player_healthregentime", "0" );
    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 99999;
    gf_registerLoadoutCycleDvar();
    gf_registerOvertimeLimitDvar();
    gf_initDamageScoring();
    gf_resolveTeamMode();

    if ( level.gf_largeMode )
    {
        level.timelimit = gf_cfgFloat( "scr_" + level.gameType + "_timelimit_large", 1.5, 0, 60 );
        setDvar( "ui_timelimit", level.timelimit );
    }

    level.gracePeriod = 15;

    if ( getDvar( "scr_gf_match_prematch_seconds" ) == "" )
        setDvar( "scr_gf_match_prematch_seconds", "15" );
    if ( getDvar( "scr_gf_prematch_seconds" ) == "" )
        setDvar( "scr_gf_prematch_seconds", "7" );

    if ( game["roundsplayed"] == 0 )
    {
        level.prematchPeriod = maps\mp\gametypes\_globallogic_utils::getValueInRange( getDvarInt( "scr_gf_match_prematch_seconds" ), 2, 30 );
    }
    else
    {
        level.prematchPeriod = maps\mp\gametypes\_globallogic_utils::getValueInRange( getDvarInt( "scr_gf_prematch_seconds" ), 2, 20 );
        game["strings"]["match_starting_in"] = "ROUND BEGINS IN";
    }
    level thread gf_nativePrematchTicker();

    level.gf_roundActive     = false;
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;
    level.gf_overtimeActive  = false;
    level.inOvertime         = false;
    level.timeLimitOverride  = false;

    gf_rocketOncePerMatch();

    if ( !isDefined( game["switchedsides"] ) )
        game["switchedsides"] = false;

    setClientNameMode( "auto_change" );

    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "allies", &"GF_GAMETYPE_DESC" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "axis",   &"GF_GAMETYPE_DESC" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "allies", &"GF_GAMETYPE_DESC_SCORE" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "axis",   &"GF_GAMETYPE_DESC_SCORE" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveHintText( "allies", &"GF_GAMETYPE_HINT" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveHintText( "axis",   &"GF_GAMETYPE_HINT" );

    maps\mp\gametypes\_rank::registerScoreInfo( "win",      5   );
    maps\mp\gametypes\_rank::registerScoreInfo( "loss",     1   );
    maps\mp\gametypes\_rank::registerScoreInfo( "tie",      2.5 );
    maps\mp\gametypes\_rank::registerScoreInfo( "kill",      0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "headshot",  0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_75", 0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_50", 0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_25", 0 );
    maps\mp\gametypes\_rank::registerScoreInfo( "assist",    0 );

    gf_initLoadouts();
    gf_pickLoadout();
    gf_initCustomLocations();

    level.spawnMins = ( 0, 0, 0 );
    level.spawnMaxs = ( 0, 0, 0 );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_allies_start" );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_axis_start" );
    if ( level.gf_largeMode )
    {
        maps\mp\gametypes\_spawnlogic::addSpawnPoints( "allies", "mp_tdm_spawn" );
        maps\mp\gametypes\_spawnlogic::addSpawnPoints( "axis",   "mp_tdm_spawn" );
    }
    else
    {
        wagerSpawns = getEntArray( "mp_wager_spawn", "classname" );
        if ( wagerSpawns.size > 0 )
        {
            maps\mp\gametypes\_spawnlogic::addSpawnPoints( "allies", "mp_wager_spawn" );
            maps\mp\gametypes\_spawnlogic::addSpawnPoints( "axis",   "mp_wager_spawn" );
        }
        else
        {
            maps\mp\gametypes\_spawnlogic::addSpawnPoints( "allies", "mp_tdm_spawn" );
            maps\mp\gametypes\_spawnlogic::addSpawnPoints( "axis",   "mp_tdm_spawn" );
        }
    }
    maps\mp\gametypes\_spawning::updateAllSpawnPoints();
    level.spawn_allies_start = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_allies_start" );
    level.spawn_axis_start   = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_axis_start" );

    level.mapCenter = maps\mp\gametypes\_spawnlogic::findBoxCenter( level.spawnMins, level.spawnMaxs );
    setMapCenter( level.mapCenter );

    spawnpoint = maps\mp\gametypes\_spawnlogic::getRandomIntermissionPoint();
    setDemoIntermissionPoint( spawnpoint.origin, spawnpoint.angles );

    allowed[0] = "gf";
    allowed[1] = "dom";
    if ( !level.gf_largeMode )
    {
        allowed[allowed.size] = "gun";
        allowed[allowed.size] = "oic";
        allowed[allowed.size] = "hlnd";
        allowed[allowed.size] = "shrp";
    }
    maps\mp\gametypes\_gameobjects::main( allowed );

    maps\mp\gametypes\_spawning::create_map_placed_influencers();

    if ( !level.gf_largeMode )
        gf_applyWagerZoneAssets();

}

gf_rocketOncePerMatch()
{
    if ( GetDvar( #"mapname" ) != "mp_cosmodrome" )
        return;

    if ( isDefined( game["gf_rocketLaunched"] ) && game["gf_rocketLaunched"] )
    {
        setDvar( "scr_rocket_event_off", "101" );
        return;
    }

    setDvar( "scr_rocket_event_off", "0" );
    level thread gf_watchRocketLaunch();
}

gf_watchRocketLaunch()
{
    level waittill( "rocket_launch" );
    game["gf_rocketLaunched"] = true;
}

gf_registerLoadoutCycleDvar()
{
    dvar = "scr_" + level.gameType + "_roundsperloadout";

    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, 2 );

    raw   = GetDvarInt( dvar );
    value = maps\mp\gametypes\_globallogic_utils::getValueInRange( raw, 1, 9 );
    if ( value != raw )
        setDvar( dvar, value );

    level.gf_cfg_roundsPerLoadout = value;
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

    if ( !level.gf_largeMode )
    {
        customSpawn = gf_getCustomSpawnPoint( spawnTeam );
        if ( isDefined( customSpawn ) )
        {
            self.lastSpawnTime  = getTime();
            self.lastSpawnPoint = spawn( "script_origin", customSpawn["origin"] );

            self spawn( customSpawn["origin"], customSpawn["angles"], "gf" );
            return;
        }
    }

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

    self spawn( spawnPoint.origin, spawnPoint.angles, "gf" );
}

onSpawnPlayerUnified()
{
    self.usingObj = undefined;

    if ( level.useStartSpawns && !level.inGracePeriod )
        level.useStartSpawns = false;

    if ( !level.gf_largeMode )
    {
        self onSpawnPlayer();
        return;
    }

    maps\mp\gametypes\_spawning::onSpawnPlayer_Unified();
}
