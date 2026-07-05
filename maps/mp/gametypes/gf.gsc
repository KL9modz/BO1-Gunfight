// Gunfight v3 — Standalone Gametype
// By KL9

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_gf_locations;
#include maps\mp\gametypes\_gf_rounds;
#include maps\mp\gametypes\_gf_loadouts;
#include maps\mp\gametypes\_gf_wager_zones;
// #strip-begin - RCON bridge include (dev/main only; stripped from public release)
#include maps\mp\gametypes\_gf_bridge;
// #strip-end

main()
{
    if ( GetDvar( #"mapname" ) == "mp_background" )
        return;

    // gunfight must run with xblive_wagermatch 0 (no wager lives / betting / prematch),
    // but it CANNOT be forced here: the map's own main() reads xblive_wagermatch at
    // level-load, BEFORE this gametype main() runs, so a setDvar here is too late for the
    // load-time reads (the wager pregame/compass decision). The flag is set BEFORE the map
    // loads by the RCON map page (0 for gf, 1 for the wager gametypes gun/oic/shrp/hlnd);
    // see tools/rcon/public/index.html and "Wager Map Zone" in CLAUDE.md.
    maps\mp\gametypes\_globallogic::init();
    maps\mp\gametypes\_callbacksetup::SetupCallbacks();
    maps\mp\gametypes\_globallogic::SetupCallbacks();

    maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar(   level.gameType, 2, 0, 9    );
    maps\mp\gametypes\_globallogic_utils::registerTimeLimitDvar(     level.gameType, 0.75, 0, 1440 ); // 0.75 = 45s SMALL-mode round default
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
    precacheShader( "hud_icon_tabun_gasgrenade");   // Gas (tactical)
    precacheShader( "hud_nightingale"          );   // Decoy / Nightingale (tactical)
    precacheShader( "hud_icon_claymore"        );
    precacheShader( "hud_radar_jammer"         );
    precacheShader( "hud_acoustic_sensor"      );
    precacheShader( "hud_deployable_camera"    );

    // Special weapons (minigun = Death Machine, m202 = Grim Reaper) are NOT in the
    // normal MP weapon table, so the class system never auto-precaches them like it
    // does famas/galil/etc. Without an explicit PrecacheItem here, GiveWeapon()
    // silently no-ops at runtime — the loadout icon still shows (separate shader,
    // above) but the player receives nothing. PrecacheItem is only valid in the
    // precache phase (this function), never at gameplay time.
    //
    // Use the _wager variants (NOT the killstreak minigun_mp/m202_flash_mp): the
    // killstreak names are registered in the killstreak system, which fires the
    // "killstreak called in" announcer on give AND prevents re-selecting the weapon
    // after you holster it. The _wager builds are identical guns without that hook,
    // so they behave as normal swappable primaries. Stock shrp.gsc uses these too.
    PrecacheItem( "m202_flash_wager_mp" );
    PrecacheItem( "minigun_wager_mp"    );

    // Gas + Decoy tacticals — added to the loadout rotation. Unlike flash/stun/
    // smoke (which the class system auto-precaches), these two aren't in any
    // default class, so PrecacheItem here guarantees GiveWeapon() actually
    // delivers them. The decoy's behavior (fake gunfire/blips) is driven by
    // stock maps\mp\_decoy, already threaded from _globallogic — no extra wiring.
    PrecacheItem( "tabun_gas_mp"        );
    PrecacheItem( "nightingale_mp"      );

    // OT apron FX — initial registration. NOTE: these handles are wiped by the
    // map_restart(true) that _globallogic::endGame runs between rounds, and
    // onPrecacheGameType only runs once per match — so gf_createOvertimeZone calls
    // gf_loadOvertimeApronFx() again on every OT entry to re-establish them.
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
    precacheString( &"GF_POPUP_ELIMINATION" );   // mod.ff localized strings (gf.str) —
    precacheString( &"GF_POPUP_ASSIST" );        // zone assets, no dynamic string table

    gf_precacheWagerZoneAssets();
}

onStartGameType()
{
    level.noPersistence = true;

    // These are STOCK engine dvars, NOT mod-registered scr_gf_* dvars: _globallogic::registerDvars()
    // runs during Callback_StartGameType and seeds scr_disable_cac to "0" BEFORE this callback fires,
    // so a `== ""` guard never sees empty and never sticks. Force them every map_restart, or the
    // class-select screen reappears (cac) and weapon drops come back.
    setDvar( "scr_disable_cac", "1" );
    setDvar( "scr_disable_weapondrop", "1" );
    setDvar( "scr_showperksonspawn", "0" );   // pinned: stock perk popup off; the custom loadout HUD (gf_showWeaponHUD) owns perk display
    // Weapon-swap speed left fully stock by default: we neither force perk_weapSwitchMultiplier nor
    // grant specialty_fastweaponswitch (gf_giveCustomLoadout no longer adds it). To speed up swaps,
    // an admin enables Fast Weapon Switch in the RCON Perks tab (-> gf_perk_on), then tunes the
    // "Weapon Switch Speed" slider; without the perk the multiplier dvar is inert.
    // #strip-begin - dev cheats for LOCAL listen-server testing only.
    // Guarded by `dedicated == 0` (0 = listen server; 1/2 = dedicated) so the ENGINE itself
    // blocks this on any dedicated server (the VPS), independent of the build pipeline. The
    // strip markers additionally remove it from the public release build. dedicated.cfg is the
    // SOLE owner of rcon_password / g_password / sv_cheats on the VPS. NO password is set here
    // (never commit a secret): for local RCON-panel testing, set `rcon_password` yourself in a
    // gitignored local cfg or the listen-server console.
    if ( getDvarInt( "dedicated" ) == 0 )
    {
        setDvar( "sv_cheats", "1" );
        setDvar( "g_password", "" );
    }
    // #strip-end

    setDvar( "scr_player_healthregentime", "0" );
    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 99999;
    gf_registerLoadoutCycleDvar(); // also sets level.gf_cfg_roundsPerLoadout
    gf_registerOvertimeLimitDvar(); // also sets level.gf_cfg_overtimeLimit
    gf_initDamageScoring(); // relies on level.gf_cfg_roundsPerLoadout
    gf_resolveTeamMode(); // sets level.gf_largeMode (drives spawns, barriers, OT flag)

    // Large mode uses its own round-length dvar (scr_<gt>_timelimit_large,
    // default 1.5 = 1:30); small mode keeps the admin/cfg scr_<gt>_timelimit
    // (e.g. dedicated.cfg's 10). main() re-derives level.timelimit from the
    // small dvar every map_restart, so overriding the level var here applies for
    // this round only and never clobbers either dvar.
    if ( level.gf_largeMode )
    {
        level.timelimit = gf_cfgFloat( "scr_" + level.gameType + "_timelimit_large", 1.5, 0, 60 );
        setDvar( "ui_timelimit", level.timelimit ); // keep the HUD clock in sync
    }

    // Stock sets level.gracePeriod = 15 (numLives branch). Grace does two jobs in a
    // one-life mode: (1) _globallogic_spawn::maySpawn only admits a FIRST spawn while
    // inGracePeriod is true — anyone landing later (bot fill, slow loaders) spectates
    // the whole round; and (2) _globallogic::updateGameEvents suppresses onDeadEvent
    // while it's true, so a wipe can't end the round mid-spawn-wave. This used to be
    // shortened to 3 on the (false) assumption that PvP was gated by !gf_roundActive
    // in the damage handler — no such gate exists — which silently locked round-1 bot
    // fill and slow loaders out of the match. Keep the stock ceiling; gf_tryActivateRound
    // closes grace EARLY (the moment every teamed player has spawned, bounded at 8s)
    // so the "everyone dead but round can't end" window never outlives the spawn wave.
    level.gracePeriod = 15;

    // Per-round prematch via the engine's native countdown. The engine zeroes level.prematchPeriod
    // every round (Callback_StartGameType) and only refills it once per match, so we set it HERE
    // each round: onStartGameType runs after the engine's prematch randomization and before
    // startGame()'s prematchPeriod(), so this exact value drives the countdown every round (>=2
    // required for the engine to render the timer). The native prematch freezes controls (incl.
    // firing), plays the intro VO, shows the objective hint, and hides the round timer until
    // prematch_over — gf_tryActivateRound waits for prematch_over before starting our round clock.
    if ( getDvar( "scr_gf_match_prematch_seconds" ) == "" )
        setDvar( "scr_gf_match_prematch_seconds", "15" );   // first round of the match (longer intro)
    if ( getDvar( "scr_gf_prematch_seconds" ) == "" )
        setDvar( "scr_gf_prematch_seconds", "7" );          // every later round

    // Seed the pre-prematch gate dvars here so they exist from boot (the RCON panel reads
    // them, and they'd otherwise show "not read" until gf_waitForLoadingClients first
    // touched them via gf_cfgFloat). Clamping still happens on read in _gf_rounds.gsc.
    // Both feed the single pre-prematch hold in gf_waitForLoadingClients.
    if ( getDvar( "scr_gf_min_players" ) == "" )
        setDvar( "scr_gf_min_players", "1" );     // min HUMANS to start the match (1 = off)
    if ( getDvar( "scr_gf_load_wait" ) == "" )
        setDvar( "scr_gf_load_wait", "0" );       // max s to hold the prematch for map-loading clients (0 = off, default; slow loaders may miss the intro)
    if ( getDvar( "scr_gf_load_grace" ) == "" )
        setDvar( "scr_gf_load_grace", "20" );     // s past prematch_over to keep grace open for a still-loading client so it spawns into round 1 (0 = off)
    if ( getDvar( "scr_gf_lobby" ) == "" )
        setDvar( "scr_gf_lobby", "0" );           // Match Start: 0 = Normal (default, off), 1 = Auto lobby (min-players -> fast-restart), 2 = Manual lobby (admin START -> fast-restart)

    // Flinch (damage view-kick) scale — mult of stock bg_viewKickScale (0.2).
    // Seeds scr_gf_flinch (default 1 = stock) and applies bg_viewKickScale each
    // round so an RCON change persists across map_restart. Server-side, so it
    // holds on the dedicated VPS. RCON bridge: flinch_<mult> for a live change.
    gf_applyFlinch();

    // roundsplayed == 0 is the match's first round (longer intro); later rounds get the shorter one.
    if ( game["roundsplayed"] == 0 )
    {
        level.prematchPeriod = maps\mp\gametypes\_globallogic_utils::getValueInRange( getDvarInt( "scr_gf_match_prematch_seconds" ), 2, 30 );
    }
    else
    {
        level.prematchPeriod = maps\mp\gametypes\_globallogic_utils::getValueInRange( getDvarInt( "scr_gf_prematch_seconds" ), 2, 20 );
        // matchStartTimer setText's game["strings"]["match_starting_in"]; round 1 keeps the engine's
        // "MATCH STARTING IN", rounds 2+ say "ROUND BEGINS IN" (raw string is fine — no rebuild).
        game["strings"]["match_starting_in"] = "ROUND BEGINS IN";
    }
    // Arm the load-gate's connect tracker NOW: the engine delivers "connecting"
    // callbacks (which fire for rotation-carried clients while they are STILL on
    // their loading screen) as soon as this Callback_StartGameType slice first
    // yields, so the tracker must be listening before any later helper can wait.
    // The actual hold is the last statement of this function. (The per-second
    // prematch tick also moved there: it loops on inPrematchPeriod, which is
    // already true during the hold, and would have beeped through it from here.)
    gf_armLoadGate();

    level.gf_roundActive     = false;
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;
    level.gf_overtimeActive  = false;
    level.inOvertime         = false;
    level.timeLimitOverride  = false;

    gf_rocketOncePerMatch();   // Cosmodrome: stop the launch re-firing every round

    if ( !isDefined( game["switchedsides"] ) )
        game["switchedsides"] = false;

    setClientNameMode( "auto_change" ); 

    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "allies", &"GF_GAMETYPE_DESC" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveText( "axis",   &"GF_GAMETYPE_DESC" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "allies", &"GF_GAMETYPE_DESC_SCORE" );  // &&1 = scorelimit (the splash passes it; needs a token or it appends the number)
    maps\mp\gametypes\_globallogic_ui::setObjectiveScoreText( "axis",   &"GF_GAMETYPE_DESC_SCORE" );
    maps\mp\gametypes\_globallogic_ui::setObjectiveHintText( "allies", &"GF_GAMETYPE_HINT" );  // single-line: decode FX (setCOD7DecodeFX) collapses \n during scramble, so a multi-line hint overflows
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

    gf_initLoadouts();   // guarded by game["gf_init"] — shuffles once per match and picks loadout 0 for round 1 
    gf_pickLoadout();    // deterministic: index derived from game["roundsplayed"] 
    gf_initCustomLocations();

    level.spawnMins = ( 0, 0, 0 );
    level.spawnMaxs = ( 0, 0, 0 );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_allies_start" );
    maps\mp\gametypes\_spawnlogic::placeSpawnPoints( "mp_tdm_spawn_axis_start" );
    // Large mode plays the full map on the standard TDM spawn pool; small mode
    // prefers the wager spawn cluster when the map has one.
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
    // Small mode keeps the baked wager blockers (gun/oic/hlnd/shrp) to shrink the
    // play space; large mode omits them so _gameobjects::main deletes them and the
    // full map opens up. dom is always kept so flag_primary (the OT B flag) survives.
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

    // #strip-begin - RCON bridge + bot init (dev/main only; stripped from public release)
    thread gf_bridgeInit();   // per-round: re-seeds dvars/flags + re-arms the vision blend (level.* wiped by map_restart); its telemetry/poll/pending-team loops self-guard to once-per-match inside
    // The bot manager is once-per-MATCH, NOT once-per-round. onStartGameType re-runs on every
    // map_restart (SD round cycling), but _bot::init() threads PERSISTENT managers
    // (handleBots/addBots/diffBots/teamBots) that carry only "game_ended" endon (fires at match
    // end, never on a map_restart), so they SURVIVE round cycling. Re-threading them every round
    // stacked N concurrent addBots() fill loops that raced on the shared bots_manage_add dvar and
    // over-added bots ("keeps adding more every match"). Gate on game[] — the only state that
    // survives map_restart, and it resets on a genuine new map load — so exactly ONE manager set
    // runs per match and it still re-inits for the next match. Same idiom as gf_rocketOncePerMatch
    // / game["gf_init"]. Also clear any stale bots_manage_add the prior match's racing loops left
    // behind (handleBots' reconciliation tail is unreachable dead code), so each match starts clean
    // and the single fill loop converges to bots_manage_fill instead of ratcheting upward.
    if ( !isDefined( game["gf_botInit"] ) )
    {
        game["gf_botInit"] = true;
        setDvar( "bots_manage_add", 0 );
        thread maps\mp\gametypes\_bot::init();
    }
    // #strip-end

    // Pre-prematch load gate — MUST be the last statement: the engine threads
    // startGame() (prematch countdown -> prematch_over) the moment this callback
    // returns, and everything above (spawn points, gameobjects, bridge, bots)
    // must be in place before the first yield lets connect/spawn callbacks run.
    // Holds the match's FIRST round until every rotation-carried client is off
    // the loading screen (bounded by scr_gf_load_wait) so the full countdown and
    // intro play for everyone at once, and slow loaders can no longer be
    // grace-locked into spectating round 1. See _gf_rounds.gsc.
    gf_waitForLoadingClients();

    level thread gf_nativePrematchTicker();      // engine matchStartTimer is silent — re-add the per-second tick (start only now, post-hold)
}

// ─── Cosmodrome rocket: once per match, not once per round ───────────────────
// The stock Cosmodrome rocket is armed in mp_cosmodrome::main() (rocket_think →
// rocket_timer_init). SD round cycling map_restarts between rounds, which
// re-runs main() and re-arms the launch — so it fires every round instead of
// once per match. We gate it with the native scr_rocket_event_off abort lever,
// tracked through game[] (the only state that survives map_restart). The gate
// keys off whether the rocket ACTUALLY launched (not "round 1"), so the single
// launch still happens even if early rounds end by elimination before the clock
// reaches the launch trigger.
gf_rocketOncePerMatch()
{
    if ( GetDvar( #"mapname" ) != "mp_cosmodrome" )
        return;

    if ( isDefined( game["gf_rocketLaunched"] ) && game["gf_rocketLaunched"] )
    {
        // Already fired this match — force a deterministic abort. 101 is
        // intentionally past the stock assert bound so RandomInt(101) < 101 is
        // always true; the assert is a no-op on Plutonium release.
        setDvar( "scr_rocket_event_off", "101" );
        return;
    }

    setDvar( "scr_rocket_event_off", "0" );   // allow this round's launch
    level thread gf_watchRocketLaunch();
}

gf_watchRocketLaunch()
{
    // mp_cosmodrome fires level notify("rocket_launch") when the rocket goes.
    // Latch it in game[] so every later round suppresses.
    level waittill( "rocket_launch" );
    game["gf_rocketLaunched"] = true;
}

// ─── Spawn Pipeline ────────────────────────────────────────────────────────

gf_registerLoadoutCycleDvar()
{
    dvar = "scr_" + level.gameType + "_roundsperloadout";

    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, 2 );

    raw   = GetDvarInt( dvar );
    value = maps\mp\gametypes\_globallogic_utils::getValueInRange( raw, 1, 9 );
    if ( value != raw )
        setDvar( dvar, value );   // persist the clamped value back, as before

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

    // Small mode uses the curated, clustered gunfight spawns; large mode falls
    // through to the full-map TDM start spawns below.
    if ( !level.gf_largeMode )
    {
        customSpawn = gf_getCustomSpawnPoint( spawnTeam );
        if ( isDefined( customSpawn ) )
        {
            // Stock Callback_PlayerDamage does UNGUARDED arithmetic on these two
            // fields for grenade/gas spawn-protection (_globallogic_player.gsc:783:
            // self.lastSpawnTime + 3500, self.lastSpawnPoint.origin). The stock
            // _spawnlogic selectors set them in finalizeSpawnpointChoice, but the
            // curated path bypasses those — leaving them undefined aborts the damage
            // callback and silently voids grenade damage against curated-spawned
            // players. Set them the way finalizeSpawnpointChoice does; a script_origin
            // stands in for the spawnpoint entity (map_restart reaps it each round).
            self.lastSpawnTime  = getTime();
            self.lastSpawnPoint = spawn( "script_origin", customSpawn["origin"] );

            self spawn( customSpawn["origin"], customSpawn["angles"], "gf" );
            return;
        }
    }

    // Always use team-specific start spawns. Gunfight has fixed sides per round
    // and never respawns mid-round, so getSpawnpoint_NearTeam on a shared pool
    // (both teams use the same wager/TDM points) could place a late-spawning bot
    // on the wrong side when inGracePeriod is false.
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

    // Small mode: ALWAYS spawn via our curated fight-facing points. The stock
    // unified path only routes to onSpawnPlayer while useStartSpawns is true;
    // once it flips false (first enemy damage), late/async spawns (bot fill,
    // late joiners, 60s forceSpawn) fall through to the generic scored
    // mp_tdm_spawn pool and face the wrong way. One life per round means those
    // are the only mid-round spawns, so short-circuit instead. Large mode keeps
    // the stock unified system (full-map pool benefits from spawn scoring).
    if ( !level.gf_largeMode )
    {
        self onSpawnPlayer();
        return;
    }

    maps\mp\gametypes\_spawning::onSpawnPlayer_Unified();
}

