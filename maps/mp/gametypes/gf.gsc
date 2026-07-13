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
// #strip-begin - frame-hitch/slow-mo monitor include (dev/main only; stripped from public release)
#include maps\mp\gametypes\_gf_debug;
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
    maps\mp\gametypes\_globallogic_utils::registerTimeLimitDvar(     level.gameType, 0.7, 0, 1440 ); // 0.7 = 42s SMALL-mode round default
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

    // Finger Gun easter egg primary. "fingergun_mp" is not a real weapon (an
    // invalid token was relying on the engine's silent fallback, which never
    // actually gives anything without precache — same GiveWeapon-no-op as the
    // special weapons above). "defaultweapon" IS a real weapon def (raw\weapons\sp,
    // stock devgui uses it the same way: raw\maps\_debug.gsc precacheItem+GiveWeapon)
    // — precache it here so the loadout pool entry actually delivers the gun.
    PrecacheItem( "defaultweapon"       );

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
    // Stock "spawn within N seconds or be dropped" kick (_globallogic_spawn::kickIfIDontSpawnInternal).
    // The engine REGISTERS scr_kick_time at 60, and the thread is armed whenever level.rankedMatch is
    // true — which it is on our dedicated server (onlinegame 1 + xblive_privatematch 0). It exempts
    // pers["team"] == "spectator", so a real spectator is safe, but it kicks anyone Gunfight holds
    // team-assigned WITHOUT spawning: every human in an Auto/Manual pregame lobby hold (forceAutoAssign
    // seats them on a team and nobody spawns for up to scr_gf_lobby_timer = 600s), and a large-mode late
    // joiner (90s round + killcam outlasts 60s). Push it out of reach — AFK enforcement is g_inactivity's
    // job (dedicated.cfg), which kicks on real input inactivity instead of on "hasn't spawned yet".
    setDvar( "scr_kick_time", "3600" );
    // Weapon-swap speed left fully stock by default: we neither force perk_weapSwitchMultiplier nor
    // grant specialty_fastweaponswitch (gf_giveCustomLoadout no longer adds it). To speed up swaps,
    // an admin enables Fast Weapon Switch in the RCON Perks tab (-> gf_perk_on), then tunes the
    // "Weapon Switch Speed" slider; without the perk the multiplier dvar is inert.
    // #strip-begin - dev cheats for LOCAL listen-server testing only.
    // ⚠ `dedicated` is an ENUM dvar: its VALUE is a STRING ("listen server" / "dedicated LAN
    // server" / "dedicated internet server"), NOT the index. getDvarInt() parses that string to
    // 0 on EVERY server type, so the old `getDvarInt( "dedicated" ) == 0` guard was ALWAYS TRUE
    // and this block ran on the live dedicated VPS — forcing sv_cheats 1 and blanking g_password
    // every single round. (Verified live 2026-07-11: rcon `set sv_cheats 0` -> `fast_restart` ->
    // reads back 1.) Never infer server type with getDvarInt on this dvar.
    //
    // The string compare below FAILS CLOSED: any value that isn't exactly "listen server" — a
    // dedicated server, or a future build that renames the label — leaves cheats OFF. The worst
    // case is a listen server losing its dev cheats (annoying), never a dedicated server gaining
    // them (catastrophic). dedicated.cfg is the SOLE owner of rcon_password / g_password /
    // sv_cheats on the VPS; NO password is set here (never commit a secret).
    if ( getDvar( "dedicated" ) == "listen server" )
    {
        setDvar( "sv_cheats", "1" );
        setDvar( "g_password", "" );
    }
    // #strip-end

    // Tripwire (ships in EVERY build, including public — deliberately outside the strip markers).
    // sv_cheats on a dedicated server hands every player with console access noclip/god/give; the
    // only thing standing between that and a public lobby is sv_disableClientConsole. The guard
    // above already fails closed, so this can now only fire if a cfg sets sv_cheats 1 by hand — but
    // the previous guard failed OPEN and silently for months, so the failure mode gets an alarm
    // rather than another comment. Logs to games_mp.log (the deploy-verification log) + console.
    gf_warnIfCheatsOnDedicated();

    setDvar( "scr_player_healthregentime", "0" );
    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 99999;

    // #strip-begin - pregame-lobby + bot-fill spawn hook (dev/main only; stripped from public release).
    // Restart-lobby: route the throwaway "spawn" straight to spectator. maySpawn() calls this hook
    // FIRST (_globallogic_spawn.gsc:28), and a false sends the engine down its own maySpawn-false
    // path (:566-583) — self thread [[level.spawnSpectator]] — instead of a full frozen spawnPlayer.
    // That skips the loadout build, spawn music, team-name splash, AND score bar in one shot: the
    // lobby becomes pure spectators. gf_lobbyMaySpawn returns false ONLY while gf_lobbyRestartHold is
    // set, so the real match after map_restart (and every normal round) spawns exactly as before and
    // the stock maySpawn grace/lives logic is untouched. Re-set here every onStartGameType because
    // map_restart wipes level.*.
    // The public build has neither a lobby nor a bot reconciler, so it installs NO hook — stock
    // maySpawn guards with isDefined( level.maySpawn ) and falls through to its own grace/lives logic.
    level.maySpawn = ::gf_lobbyMaySpawn;
    // #strip-end

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

    // FINAL-KILLCAM SLOW MOTION — see gf_killcamSlowmoOn() in _gf_rounds.gsc for the full story.
    // Stock's round-end killcam drops the whole server to SetTimeScale(0.25) two seconds before the
    // killing blow, which stops the server acking clients' usercmds and makes the engine's own
    // "Connection Interrupted" plug flash mid-replay on a healthy connection. Seeded here so the
    // RCON panel can read/toggle it from boot; gf_endRound acts on it.
    if ( getDvar( "scr_gf_killcam_slowmo" ) == "" )
        setDvar( "scr_gf_killcam_slowmo", "1" );   // 1 = stock cinematic (default), 0 = hold real time
    // Stock reads scr_killcam_time as a STRING and only uses it when non-empty (_killcam.gsc:554),
    // deriving camtime from the weapon otherwise. So seed it EMPTY: the panel gets a dvar it can
    // read without an "Unknown cmd", and stock keeps its own per-weapon default until someone sets
    // a value. Seeding a number here would silently override every killcam length in the game.
    if ( getDvar( "scr_killcam_time" ) == "" )
        setDvar( "scr_killcam_time", "" );

    // Per-round prematch via the engine's native countdown. The engine zeroes level.prematchPeriod
    // every round (Callback_StartGameType) and only refills it once per match, so we set it HERE
    // each round: onStartGameType runs after the engine's prematch randomization and before
    // startGame()'s prematchPeriod(), so this exact value drives the countdown every round (>=2
    // required for the engine to render the timer). The native prematch freezes controls (incl.
    // firing), plays the intro VO, shows the objective hint, and hides the round timer until
    // prematch_over — gf_tryActivateRound waits for prematch_over before starting our round clock.
    // #strip-begin - match-start machinery (dev/main only; stripped from public release).
    //
    // Everything seeded below belongs to a system the PUBLIC build does not have: the
    // pre-prematch hold (load gate / min-players / Auto-Manual lobby), the engine's pregame
    // warmup, and the bot-fill reconciler. The public build runs the native prematch straight
    // through into the round — no waiting on loaders, no min-player hold, no lobby, no warmup,
    // no bots — so seeding their dvars would only publish knobs that nothing reads.
    //
    // The prematch LENGTH is the one exception worth keeping tunable here: the public build
    // pins it to the fixed 20s/7s assigned below (see level.prematchPeriod), while dev/VPS gets
    // these two dvars so the RCON panel can retune it live.
    if ( getDvar( "scr_gf_match_prematch_seconds" ) == "" )
        setDvar( "scr_gf_match_prematch_seconds", "20" );   // first round of the match (longer intro)
    if ( getDvar( "scr_gf_prematch_seconds" ) == "" )
        setDvar( "scr_gf_prematch_seconds", "7" );          // every later round

    // Seed the pre-prematch gate dvars here so they exist from boot (the RCON panel reads
    // them, and they'd otherwise show "not read" until gf_waitForLoadingClients first
    // touched them via gf_cfgFloat). Clamping still happens on read in _gf_rounds.gsc.
    // Both feed the single pre-prematch hold in gf_waitForLoadingClients.
    if ( getDvar( "scr_gf_min_players" ) == "" )
        setDvar( "scr_gf_min_players", "1" );     // min HUMANS to start the match (1 = off)
    if ( getDvar( "scr_gf_minplayers_timer" ) == "" )
        setDvar( "scr_gf_minplayers_timer", "0" );// min-players "start anyway" ceiling (s). 0 = never auto-start (hold until enough humans / admin START). Was a hardcoded 90s that started too-thin matches
    if ( getDvar( "scr_gf_load_wait" ) == "" )
        setDvar( "scr_gf_load_wait", "0" );       // max s to hold the prematch for map-loading clients (0 = off, default; slow loaders may miss the intro)
    if ( getDvar( "scr_gf_load_grace" ) == "" )
        setDvar( "scr_gf_load_grace", "20" );     // s past prematch_over to keep grace open for a still-loading client so it spawns into round 1 (0 = off)
    if ( getDvar( "scr_gf_lobby" ) == "" )
        setDvar( "scr_gf_lobby", "0" );           // Match Start: 0 = Normal (default, off), 1 = Auto lobby (min-players -> fast-restart), 2 = Manual lobby (admin START -> fast-restart)
    if ( getDvar( "scr_gf_lobby_timer" ) == "" )
        setDvar( "scr_gf_lobby_timer", "600" );   // MANUAL lobby auto-start timer (s). Was the hardcoded 10-min backstop; now RCON-adjustable. 0 = never auto-start (hold until START)

    // PRE-MATCH WARMUP — 100% stock, zero mod GSC. g_pregame_enabled is an ENGINE dvar (it lives in
    // BlackOpsMP.exe, alongside the hardcoded script path "maps/mp/gametypes/_pregame"): when it is
    // set, the engine loads BO1's own _pregame gametype INSTEAD of this one — a no-XP free-for-all
    // that waits for party_minplayers players, then pregamestartgame() + map_restart(false) hands off
    // back into g_gametype (which reads "gf" throughout). We own NONE of that; we only expose the
    // switch in the RCON panel. Seeded if-empty purely so the panel's connect-sweep never reads it by
    // bare name and gets "Unknown cmd". ⚠ Read at LEVEL LOAD → only ever affects the NEXT map.
    //
    // Not seeding it is exactly what keeps the warmup OUT of the public build: the engine defaults
    // it to 0, nothing else writes it, so BO1's pregame gametype can never come up. (This is also
    // why there is no _pregame.gsc to exclude — the warmup carries no mod GSC at all.)
    if ( getDvar( "g_pregame_enabled" ) == "" )
        setDvar( "g_pregame_enabled", "0" );
    // ⚠ MUST be 0, and it is OUR job to make it so. The warmup's OWN time limit is registered by stock
    // _pregame::main() -> registerTimeLimitDvar( "pregame", 5, 0, 1440 ) on PC, and registerTimeLimitDvar
    // is SEED-IF-EMPTY — so an unregistered scr_pregame_timelimit lands on FIVE MINUTES. _pregame's
    // onTimeLimit then calls _globallogic::endGame, and on the time-out path it never reaches
    // pregamestartgame(): the map ROTATES instead of starting the match, so an under-populated server
    // just cycles maps every 5 min forever. Seeding "0" here pre-empts that (0 = no time limit: stock
    // timeLimitClock gates on `level.timeLimit`, which 0 makes falsy) — the seed survives into the
    // warmup's level load because dvars outlive a map change, and _pregame's seed-if-empty then leaves
    // our 0 alone. dedicated.cfg.example sets it too, for the boot-straight-into-a-warmup case where
    // this callback has never run.
    if ( getDvar( "scr_pregame_timelimit" ) == "" )
        setDvar( "scr_pregame_timelimit", "0" );
    // Dynamic bot fill. gf_fill_n is the PER-TEAM target N (humans+bots per side): the Gunfight
    // round-boundary reconciler (gf_reconcilerInit in _bot.gsc, dev-only) pads each side to exactly
    // N with bots at each round boundary — mid-round roster changes are absorbed at the next round
    // start. It MUST be a dvar — the only state that survives the lobby's map_restart(false).
    if ( getDvar( "gf_fill_n" ) == "" )
        setDvar( "gf_fill_n", "0" );              // 0 = fill off; 3 = 3v3, 4 = 4v4, ... (clamped 0-6 on read)
    if ( getDvar( "gf_fill_kick_floor" ) == "" )
        setDvar( "gf_fill_kick_floor", "2" );     // client slots kept free for humans: a parked bot is KICKED (not parked) once level.players >= sv_maxclients - this
    if ( getDvar( "gf_teamplan" ) == "" )
        setDvar( "gf_teamplan", "" );             // lobby->match transfer: "<guid>:<a|x|s>,..." snapshot written pre-restart, re-applied post-restart (survives map_restart(false))
    // #strip-end

    // Register scr_team_maxsize with its documented default (0 = no cap) so it always exists
    // in the dvar table. The mod reads it via getDvarInt (0 when unset), but an UNregistered
    // dvar echoes "Unknown cmd scr_team_maxsize" when the RCON panel's connect-sweep reads it
    // by bare name — spam the host sees on a listen server. dedicated.cfg still overrides this.
    if ( getDvar( "scr_team_maxsize" ) == "" )
        setDvar( "scr_team_maxsize", "0" );       // max players/team (0 = no cap); cfg ships 6

    // Seed BOTH team-size-mode variants of every mode-specific dvar so they ALWAYS exist in the
    // dvar table, even the variant for the mode not currently active. Each is otherwise only
    // registered (gf_cfgFloat's seed-if-empty) when ITS mode runs — so in small mode the *_large
    // dvars (and vice-versa) are unregistered, and the RCON panel's connect-sweep reads them by
    // bare name → the engine prints "Unknown cmd <name>" (a burst of them on the listen-host
    // screen / server console). Defaults mirror the read sites (round-length above,
    // gf_getOvertimeLimit, gf_getCaptureTime). scr_gf_timelimit + scr_gf_teamspawnmode are
    // already always-registered (registerTimeLimitDvar / gf_resolveTeamMode).
    gtp = "scr_" + level.gameType;
    if ( getDvar( gtp + "_timelimit" ) == "" )           setDvar( gtp + "_timelimit", "0.7" );
    if ( getDvar( gtp + "_timelimit_large" ) == "" )     setDvar( gtp + "_timelimit_large", "1.5" );
    if ( getDvar( gtp + "_overtimelimit" ) == "" )       setDvar( gtp + "_overtimelimit", "15" );
    if ( getDvar( gtp + "_overtimelimit_large" ) == "" ) setDvar( gtp + "_overtimelimit_large", "30" );
    if ( getDvar( "gf_capture_time" ) == "" )            setDvar( "gf_capture_time", "3.5" );
    if ( getDvar( "gf_capture_time_large" ) == "" )      setDvar( "gf_capture_time_large", "5" );

    // #strip-begin - dev debug dvars: seed to 0 so the RCON panel's DEBUG section reads them
    // cleanly (they're otherwise read via getDvarInt, which never registers them → "Unknown cmd"
    // on the panel's bare-name sweep). Dev-only; the reader blocks are strip-wrapped too.
    if ( getDvar( "gf_debug_spawns" ) == "" )    setDvar( "gf_debug_spawns", "0" );
    if ( getDvar( "gf_debug_hud_pool" ) == "" )  setDvar( "gf_debug_hud_pool", "0" );
    if ( getDvar( "gf_debug_elem_probe" ) == "" ) setDvar( "gf_debug_elem_probe", "0" );
    if ( getDvar( "gf_force_loadout" ) == "" )    setDvar( "gf_force_loadout", "-1" );   // loadout test aids (read in _gf_loadouts.gsc)
    if ( getDvar( "gf_force_camo" ) == "" )       setDvar( "gf_force_camo", "-1" );
    // #strip-end

    // Flinch (damage view-kick) scale — mult of stock bg_viewKickScale (0.2).
    // Seeds scr_gf_flinch (default 0.5 = half stock kick) and applies bg_viewKickScale each
    // round so an RCON change persists across map_restart. Server-side, so it
    // holds on the dedicated VPS. RCON bridge: flinch_<mult> for a live change.
    // ⚠ This is the ONLY flinch reducer. specialty_bulletflinch (Hardened Pro) gates a SECOND
    // multiplier (perk_damageKickReduction, default 0.2 = an 80% cut) and is deliberately out of
    // the base perk set for that reason — see gf_applyFlinch in _gf_rounds.gsc.
    gf_applyFlinch();

    // Jump fatigue (the engine's post-jump slowdown) — Gunfight ships it OFF.
    // Seeds scr_gf_jump_fatigue (default 0) and applies jump_slowdownEnable each round.
    // RCON bridge: jumpfatigue_<0|1> for a live change.
    gf_applyJumpFatigue();

    // Unlimited sprint — seeds scr_gf_sprint_unlimited (default 0 = stock) and sets the server
    // copy of player_sprintUnlimited each round. player_sprintUnlimited is a CLIENT dvar that
    // stock only ever pushes at connect and only in the ON direction, so the mod owns the push
    // (per-client, both directions, every spawn) rather than trusting the engine to deliver it.
    // RCON bridge: sprintunlimited_<0|1> for a live change.
    gf_applySprintUnlimited();

    // Gunfight's default LOOK: the "enhance" vision set (contrast pop). Core to the mod, so every
    // build gets it — the RCON vision_<key> override is layered on top inside gf_roundVisionKey.
    // Re-run every round (vision is level state, wiped by map_restart) and must be BEFORE the bridge
    // init below, which reads the level.gf_defaultVision this establishes. The actual apply is
    // deferred to prematch_over — the stock countdown stomps vision after this callback returns.
    gf_initRoundVision();

    // roundsplayed == 0 is the match's first round (longer intro); later rounds get the shorter one.
    // These fixed values ARE the public build's prematch — it has no dvars for this (see the
    // strip-marked seeds above), so the countdown, intro VO, freeze and gun-rack all still play,
    // they are just not retunable. Dev/VPS overrides both from scr_gf_*_prematch_seconds below.
    if ( game["roundsplayed"] == 0 )
    {
        level.prematchPeriod = 20;
    }
    else
    {
        level.prematchPeriod = 7;
        // matchStartTimer setText's game["strings"]["match_starting_in"]; round 1 keeps the engine's
        // "MATCH STARTING IN", rounds 2+ say "ROUND BEGINS IN" (raw string is fine — no rebuild).
        game["strings"]["match_starting_in"] = "ROUND BEGINS IN";
    }
    // #strip-begin - RCON-tunable prematch length (dev/main only; the public build keeps the fixed 20/7 above)
    if ( game["roundsplayed"] == 0 )
        level.prematchPeriod = maps\mp\gametypes\_globallogic_utils::getValueInRange( getDvarInt( "scr_gf_match_prematch_seconds" ), 2, 30 );
    else
        level.prematchPeriod = maps\mp\gametypes\_globallogic_utils::getValueInRange( getDvarInt( "scr_gf_prematch_seconds" ), 2, 20 );
    // #strip-end

    // #strip-begin - pre-prematch load gate (dev/main only; the public build has no match-start hold)
    // Arm the load-gate's connect tracker NOW: the engine delivers "connecting"
    // callbacks (which fire for rotation-carried clients while they are STILL on
    // their loading screen) as soon as this Callback_StartGameType slice first
    // yields, so the tracker must be listening before any later helper can wait.
    // The actual hold is the last statement of this function. (The per-second
    // prematch tick also moved there: it loops on inPrematchPeriod, which is
    // already true during the hold, and would have beeped through it from here.)
    gf_armLoadGate();
    // #strip-end

    level.gf_roundActive     = false;
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;
    level.gf_overtimeActive  = false;
    level.inOvertime         = false;
    level.timeLimitOverride  = false;

    // Round generation stamp — re-stamped every onStartGameType (so every round AND
    // every map_restart, which wipes level.*). gettime() is monotonic across map_restart.
    // gf_tryActivateRound / gf_roundWatchdog capture this and bail if it moves, so a stale
    // activator that survived a lobby map_restart(false) can never strand or double-start a
    // round (see gf_tryActivateRound in _gf_rounds.gsc — replaces the old load-gate endon).
    level.gf_roundGen = gettime();

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

    // XP economy — 5x stock across the board. These values feed RANK XP ONLY, never the
    // scoreboard: level.overridePlayerScore (above) makes _globallogic_score::givePlayerScore
    // return on its first line, so the scoreboard stays our damage total. The "+N" XP popup
    // that would otherwise race our Elimination/Assist popup is killed by self.enableText =
    // false (gf_playerSpawnedCB), NOT by these values — so they are free to be non-zero.
    //
    // win/loss/tie are SCALARS on the end-of-match bonus, not flat XP: stock computes
    // scalar * (level.timeLimit * spm) * timePlayedFrac. Everything else is flat XP per event.
    // A headshot kill pays kill + headshot (both fire), i.e. 1000.
    maps\mp\gametypes\_rank::registerScoreInfo( "win",      5    );   // stock 1
    maps\mp\gametypes\_rank::registerScoreInfo( "loss",     2.5  );   // stock 0.5
    maps\mp\gametypes\_rank::registerScoreInfo( "tie",      3.75 );   // stock 0.75
    maps\mp\gametypes\_rank::registerScoreInfo( "kill",     500 );    // stock 100 — fires from _globallogic_player::Callback_PlayerKilled -> giveKillStats (NOT via our onPlayerKilled hook)
    maps\mp\gametypes\_rank::registerScoreInfo( "headshot", 500 );    // stock 100 — stacks on top of "kill"
    maps\mp\gametypes\_rank::registerScoreInfo( "assist",    100 );   // stock 20 — the only assist tier we award (gf_onPlayerKilled pays every damager the flat tier)
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_25", 200 );   // stock 40 — tiers below are registered for completeness only; stock's
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_50", 300 );   // stock 60   giveAssist() routes through givePlayerScore, which overridePlayerScore
    maps\mp\gametypes\_rank::registerScoreInfo( "assist_75", 400 );   // stock 80   kills, so nothing in this mode can actually fire them.

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
    // map_restart (SD round cycling), but _bot::init() threads PERSISTENT managers (diffBots +
    // the round-boundary fill reconciler) that must survive round cycling; re-threading them
    // every round would stack copies. Gate on game[] — the only state that survives map_restart,
    // and it resets on a genuine new map load — so exactly ONE manager set runs per match and it
    // still re-inits for the next match.
    // ⚠ This gate is only safe because those managers do NOT endon("game_ended"). That notify is
    // NOT match-end: _globallogic::endGame fires it on EVERY round end (gf_endRound threads
    // endGame in the same frame it notifies gf_round_over). This comment used to claim the
    // opposite, and gf_boundaryListener carried the endon on that basis — so it died at the first
    // round end, was never re-threaded by this once-per-match gate, and the bot fill silently
    // stopped reconciling for the rest of the match ("fill ignores humans"). Re-init is collapsed
    // by "bot_reinit" (fired at the top of _bot::init), which is the only notify that may tear
    // these down. Same idiom as
    // gf_rocketOncePerMatch / game["gf_init"]. bots_manage_add is legacy-cleared: nothing
    // consumes it anymore (the addBots loop is deleted), but a stale nonzero value from an
    // older build should not linger in the panel-visible dvar table.
    if ( !isDefined( game["gf_botInit"] ) )
    {
        game["gf_botInit"] = true;
        setDvar( "bots_manage_add", 0 );
        thread maps\mp\gametypes\_bot::init();
    }

    // Default bot difficulty. bot_difficulty is BotWarfare's own dvar: _bot::diffBots re-reads it
    // every 1.5s and re-applies the whole sv_bot* preset from it. Nothing seeded it, and an unset
    // value falls through bot_set_difficulty's final else to "normal" (which then writes the dvar
    // back) — so the default was normal by fallthrough, not by choice. Seed-if-empty: a
    // dedicated.cfg value and a live panel botdiff_* both still win, and because the preset writes
    // the dvar back this only ever fires on the first round after a server boot.
    if ( getDvar( "bot_difficulty" ) == "" )
        setDvar( "bot_difficulty", "fu" );

    // Frame-hitch / slow-mo diagnostic (dev only). Chases the "prematch/preround
    // countdown + whole game runs in slow-motion until it hits 0" report: samples
    // how much gettime() advances across a fixed wait() and logs GF_HITCH to
    // games_mp.log when a window runs slow. Re-launched every onStartGameType but
    // collapsed to exactly one live sampler by the gf_hitch_reinit notify (threads
    // survive map_restart, so a bare re-thread would stack). See _gf_debug.gsc.
    level notify( "gf_hitch_reinit" );
    level thread gf_hitchMonitor();

    // Killcam timescale readout for the RCON panel (gf_roundEndProbe overwrites it every round end
    // with the lowest timescale that window reached). Seeded so the panel's connect-sweep never
    // reads it by bare name and gets "Unknown cmd" before the first round has ended.
    if ( getDvar( "gf_killcam_ts" ) == "" )
        setDvar( "gf_killcam_ts", "1" );

    // Report the round-end dark window from the FAR side of map_restart. gf_roundEndProbe runs
    // on the near side and dies inside the restart (a thread parked in a timed wait does not
    // come back), so it stamps a heartbeat into a dvar and we read it here — the first mod code
    // to run after the restart. Yields the one number the "Connection Interrupted" theory has
    // always assumed and never measured: how long the server ran no script at all.
    gf_reportRoundEndGap();
    // #strip-end

    // Undo any timescale stock's final-killcam slowdown left behind. Its SetTimeScale(1.0) restore
    // sits AFTER a wait and behind endon("end_killcam"), so if every viewer skips (or drops out of)
    // the killcam in that window the restore never runs and the server is stranded at 0.25x — and
    // nothing in stock ever puts it back. One unconditional call per round closes that hole.
    // ⚠ ORDER: this MUST stay below gf_reportRoundEndGap() above, which logs GF_TS: LEAKED if the
    // round STARTED dilated. Reset first and the detector would only ever see the value it just
    // wrote — erasing the evidence for the bug it exists to catch.
    gf_resetTimeScale();

    // #strip-begin - pre-prematch hold (dev/main only; stripped from public release)
    // Pre-prematch load gate — MUST be the last statement: the engine threads
    // startGame() (prematch countdown -> prematch_over) the moment this callback
    // returns, and everything above (spawn points, gameobjects, bridge, bots)
    // must be in place before the first yield lets connect/spawn callbacks run.
    // Holds the match's FIRST round until every rotation-carried client is off
    // the loading screen (bounded by scr_gf_load_wait) so the full countdown and
    // intro play for everyone at once, and slow loaders can no longer be
    // grace-locked into spectating round 1. See _gf_rounds.gsc.
    //
    // The public build has NO hold: with this call gone, onStartGameType simply returns and the
    // engine threads the prematch immediately. That is the whole "no lobby / no wait times" of the
    // public build — there is nothing else to switch off, because every hold hangs off this one call.
    gf_waitForLoadingClients();
    // #strip-end

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

// Alarm if a DEDICATED server is running with cheats enabled. sv_cheats 1 makes every
// cheat-protected dvar and command (noclip / god / give / r_* renderer tweaks) reachable
// from a player's console — sv_disableClientConsole is then the ONLY thing holding the line
// on a public lobby, which is not a margin worth relying on.
//
// Read `dedicated` as a STRING, never getDvarInt(): it is an ENUM dvar whose value is a label
// ("listen server" / "dedicated LAN server" / "dedicated internet server"), so getDvarInt()
// returns 0 for all of them — that exact mistake is what let the dev-cheat block above run on
// the live VPS. Anything that is not "listen server" is treated as dedicated (fail-closed).
gf_warnIfCheatsOnDedicated()
{
    if ( getDvar( "dedicated" ) == "listen server" )
        return;

    // Accept BOTH representations rather than trust one accessor — sv_cheats is a bool dvar, and
    // the whole reason this function exists is that getDvarInt() silently returned the wrong thing
    // for a non-int dvar. An alarm that can false-NEGATIVE is worthless, so check the string too.
    cheatsOn = ( getDvarInt( "sv_cheats" ) == 1 || getDvar( "sv_cheats" ) == "1" );
    if ( !cheatsOn )
        return;

    println( "^1[GF] SECURITY: sv_cheats is 1 on a DEDICATED server. Cheat commands (noclip/god/give) are reachable from any player console. Set sv_cheats 0 in dedicated.cfg." );
    logPrint( "GF_SECURITY sv_cheats=1 on dedicated server\n" );
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
    // #strip-begin - lobby throwaway-spawn music suppression (dev/main only; no lobby in the public build)
    // Restart-lobby: pre-arm the stock spawn-music flag so the prematch spawn sting
    // (_globallogic_spawn.gsc ~line 199) is skipped for the throwaway lobby spawn. map_restart(false)
    // on release wipes pers, so the real match's first spawn still plays the music fresh. Gated on the
    // RESTART hold (not gf_inLobbyHold) so a non-restart Normal-mode hold still gets its music.
    if ( isDefined( level.gf_lobbyRestartHold ) && level.gf_lobbyRestartHold && isDefined( self.pers["music"] ) )
        self.pers["music"].spawn = true;
    // #strip-end

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
    // #strip-begin - lobby throwaway-spawn music suppression (dev/main only; no lobby in the public build)
    // Restart-lobby: suppress the stock prematch spawn-music sting for the throwaway lobby spawn
    // (see onSpawnPlayer). Also covers large mode, which routes to _spawning::onSpawnPlayer_Unified
    // instead of our onSpawnPlayer.
    if ( isDefined( level.gf_lobbyRestartHold ) && level.gf_lobbyRestartHold && isDefined( self.pers["music"] ) )
        self.pers["music"].spawn = true;
    // #strip-end

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

// #strip-begin - level.maySpawn hook (dev/main only; the public build installs no hook at all)
// level.maySpawn hook. Returns false ONLY during the restart-lobby hold, so maySpawn()
// (_globallogic_spawn.gsc:28) short-circuits and the engine routes the player to spawnSpectator
// (:581) instead of a frozen spawnPlayer — no loadout, spawn music, team splash, or score bar. Any
// other time returns true, leaving the full stock maySpawn (grace/lives/overtime) logic to run. Kept
// deliberately strict (single flag) because a stray false during the live match would block ALL
// spawning.
//
// Both of its jobs are dev-only (the lobby hold, and the bot reconciler's surplus-bot park), so the
// public build ships neither the hook nor its assignment in onStartGameType — stock maySpawn guards
// with isDefined( level.maySpawn ), so it falls straight through to its own grace/lives logic.
gf_lobbyMaySpawn()
{
    if ( isDefined( level.gf_lobbyRestartHold ) && level.gf_lobbyRestartHold )
        return false;

    // Dynamic-fill surplus trim (driven by the dev-only bot reconciler; inert without it since
    // nothing else sets the mark). When a human joins a team already at the per-team fill target,
    // the reconciler marks the displaced bot pers["gf_parkPending"]; here — the pre-spawn window,
    // where the bot is not yet "playing" so no suicide is needed — we route it to spectator instead
    // of letting it spawn frozen. Setting the team fields first makes the engine's spawnSpectator
    // produce a CLEAN spectator (statusicon cleared, not "dead"), and the reconciler then counts it
    // as parked/reusable. pers survives map_restart(true), so the mark reaches this next-round spawn.
    if ( isDefined( self.pers["gf_parkPending"] ) && self.pers["gf_parkPending"] )
    {
        self.pers["gf_parkPending"] = undefined;
        self.pers["team"]           = "spectator";
        self.team                   = "spectator";
        self.sessionteam            = "spectator";
        return false;
    }

    return true;
}
// #strip-end

