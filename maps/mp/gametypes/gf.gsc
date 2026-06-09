// Gunfight v3 — Standalone Gametype
// By KL9

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
    maps\mp\gametypes\_globallogic_utils::registerTimeLimitDvar(     level.gameType, 1, 0, 1440 );
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

// ─── Gametype Setup ────────────────────────────────────────────────────────

onPrecacheGameType()
{
    game["dialog"]["gf_overtime_cue"]    = "ctf_start";
    game["dialog"]["offense_obj"]        = "generic_boost";
    game["dialog"]["defense_obj"]        = "generic_boost";
    game["dialog"]["last_one"]           = "encourage_last";
    game["dialog"]["side_switch"]        = "sd_halftime";

    // Score bar — native engine HUD reads these shaders for the round-win display
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

    // Loadout HUD shaders — must be precached here (not in onStartGameType)
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
    // AR expanded
    precacheShader( "menu_mp_weapons_ak47"     );
    precacheShader( "menu_mp_weapons_enfield"  );
    precacheShader( "menu_mp_weapons_g11"      );
    // SMG expanded
    precacheShader( "menu_mp_weapons_kiparis"  );
    precacheShader( "menu_mp_weapons_mac11"    );
    precacheShader( "menu_mp_weapons_skorpion" );
    // Sniper expanded
    precacheShader( "menu_mp_weapons_psg1"     );
    precacheShader( "menu_mp_weapons_dragunov" );
    // Shotgun expanded
    precacheShader( "menu_mp_weapons_rottweil72");
    // Dual-wield (shared icons with base weapon)
    precacheShader( "menu_mp_weapons_hs10"     );
    precacheShader( "menu_mp_weapons_asp"      );
    // Launchers / specials — icons may be absent for some; fails silently
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
    precacheShader( "hud_icon_claymore"        );
    precacheShader( "hud_radar_jammer"         );
    precacheShader( "hud_acoustic_sensor"      );
    precacheShader( "hud_deployable_camera"    );

    level.gf_ot_baseFx_neutral = loadfx( "misc/fx_ui_flagbase_gold_t5" );

    precacheModel( "mp_flag_neutral" );
    precacheShader( "compass_waypoint_captureneutral" );
    precacheShader( "waypoint_captureneutral" );
    precacheShader( "compass_waypoint_captureneutral_b" );
    precacheShader( "waypoint_captureneutral_b" );
    precacheShader( "compass_waypoint_capture_b" );
    precacheShader( "waypoint_capture_b" );
    precacheString( &"MP_CAPTURING_FLAG" );
    precacheString( &"MP_OVERTIME_CAPS" );

    gf_precacheWagerZoneAssets();
}

onStartGameType()
{
    setDvar( "scr_disable_cac", "1" );
    setDvar( "scr_disable_weapondrop", 1 );
    setDvar( "scr_showperksonspawn", "1" );
    setDvar( "sv_cheats", "1" );

    dvar = "scr_" + level.gameType + "_visualtweaks";
    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, 1 );

    setDvar( "scr_player_healthregentime", "0" );
    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 99999;
    gf_registerLoadoutCycleDvar(); // also sets level.gf_cfg_roundsPerLoadout
    gf_registerOvertimeLimitDvar(); // also sets level.gf_cfg_overtimeLimit
    gf_initDamageScoring(); // relies on level.gf_cfg_roundsPerLoadout

    level.gf_roundActive     = false;
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;
    level.gf_overtimeActive  = false;
    level.inOvertime         = false;
    level.timeLimitOverride  = false;

    if ( !isDefined( game["switchedsides"] ) )
        game["switchedsides"] = false;

    setClientNameMode( "auto_change" ); 

    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "allies", &"OBJECTIVES_TDM" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "axis",   &"OBJECTIVES_TDM" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "allies", &"OBJECTIVES_TDM_SCORE" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "axis",   &"OBJECTIVES_TDM_SCORE" );
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

    gf_initLoadouts();   // guarded by game["gf_init"] — shuffles once per match and picks loadout 0 for round 1 
    gf_pickLoadout();    // deterministic: index derived from game["roundsplayed"] 
    gf_initCustomLocations();

    level.spawnMins = ( 0, 0, 0 );
    level.spawnMaxs = ( 0, 0, 0 );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_allies_start" );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_axis_start" );
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
    maps\mp\gametypes\_spawning::updateAllSpawnPoints();
    level.spawn_allies_start = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_allies_start" );
    level.spawn_axis_start   = maps\mp\gametypes\_spawnlogic::getSpawnpointArray( "mp_tdm_spawn_axis_start" );

    level.mapCenter = maps\mp\gametypes\_spawnlogic::findBoxCenter( level.spawnMins, level.spawnMaxs );
    setMapCenter( level.mapCenter );

    spawnpoint = maps\mp\gametypes\_spawnlogic::getRandomIntermissionPoint();
    setDemoIntermissionPoint( spawnpoint.origin, spawnpoint.angles );

    allowed[0] = "gf";
    allowed[1] = "dom";
    allowed[allowed.size] = "gun";
    allowed[allowed.size] = "oic";
    allowed[allowed.size] = "hlnd";
    allowed[allowed.size] = "shrp";
    maps\mp\gametypes\_gameobjects::main( allowed );

    maps\mp\gametypes\_spawning::create_map_placed_influencers();

    gf_applyWagerZoneAssets();

    thread maps\mp\gametypes\_bot::init();
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

    customSpawn = gf_getCustomSpawnPoint( spawnTeam );
    if ( isDefined( customSpawn ) )
    {
        self spawn( customSpawn["origin"], customSpawn["angles"], "gf" );
        return;
    }

    if ( level.inGracePeriod )
    {
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

