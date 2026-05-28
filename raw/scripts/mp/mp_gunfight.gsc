// Gunfight v2 — Entry Point
// Load: loadMod mp_gunfight → map_restart

// why don't we use these? // #include maps\mp\gametypes\_globallogic; // for team status management and other SD internal logic related to gametype flow; we call updateTeamStatus after setting player scores to 0 in initLoadouts to ensure teams show 0 rounds won/lost on scoreboard at match start, and we call it after class choice bypass to ensure teams show correct player counts; also for maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar, which we use to register our round switch dvar with SD's utils to ensure the UI reads the correct value and switches sides at the correct time; we also track the round switch value in level.gf_cfg_roundSwitch for our own logic to read when determining whether to switch sides at round start"
// #include maps\mp\gametypes\_globallogic_ui; // for UI updates related to gametype flow; we call updateScoreboard after setting player scores to 0 in initLoadouts to force immediate scoreboard update to show new columns and reset scores to 0 at match start; also for maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar, which we use to register our round switch dvar with SD's utils to ensure the UI reads the correct value and switches sides at the correct time; we also track the round switch value in level.gf_cfg_roundSwitch for our own logic to read when determining whether to switch sides at round start"   
    // #include common_scripts\utility; // for utility functions like waitUntil, which we use in our background threads to watch for bomb plant/defuse and forfeit conditions without blocking the main thread; also for maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar, which we use to register our round switch dvar with SD's utils to ensure the UI reads the correct value and switches sides at the correct time; we also track the round switch value in level.gf_cfg_roundSwitch for our own logic to read when determining whether to switch sides at round start"
    // #include maps\mp\_utility; // for maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar; we register our round switch dvar with SD's utils to ensure the UI reads the correct value and switches sides at the correct time; we also track the round switch value in level.gf_cfg_roundSwitch for our own logic to read when determining whether to switch sides at round start"
    // #include maps\mp\gametypes\_hud_util; // for HUD element creation and management functions like createPrimaryProgressBar, which we use to create and update our custom progress bars for round timer and bomb plant/defuse timer; also for maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar, which we use to register our round switch dvar with SD's utils to ensure the UI reads the correct value and switches sides at the correct time; we also track the round switch value in level.gf_cfg_roundSwitch for our own logic to read when determining whether to switch sides at round start"

#include scripts\mp\_gf_rounds; // round flow, win conditions, and score tracking
#include scripts\mp\_gf_loadouts; // loadout pool generation and management
maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar( level.gameType, 3, 0, 9 );
init()
{
    // ── 0. Config ──────────────────────────────────────────────────────
    level.gf_cfg_roundTime        = getDvarInt( "gf_round_time" ); // per-round time limit in seconds; 0 or negative = no time limit (infinite)
    if ( level.gf_cfg_roundTime <= 0 ) level.gf_cfg_roundTime = 60; // default to 60s if invalid value provided
    level.gf_cfg_winLimit         = 6;    // rounds to win the match // must be > 0 and ≤ scr_sd_scorelimit (SD score = rounds won); win limit is tracked in level.roundWinLimit for UI to read
    level.gf_cfg_roundSwitch      = 3;    // switch sides every N rounds // must be > 0 and ≤ gf_cfg_winLimit / 2 (to avoid switching after match already decided); tracked in scr_sd_roundswitch for UI to read 
    // ^ why dony we use "maps\mp\gametypes\_globallogic_utils::registerRoundSwitchDvar( level.gameType, 3, 0, 9 );" // SD's internal behavior is to switch sides every N rounds if scr_sd_roundswitch > 0, so we register our round switch dvar with SD's utils to ensure the UI reads the correct value and switches sides at the correct time; we also track the round switch value in level.gf_cfg_roundSwitch for our own logic to read when determining whether to switch sides at round start"
    level.gf_cfg_roundsPerLoadout = 2;    // rounds before rotating loadout // must be > 0; tracked in game["gf_roundsPerLoadout"] for UI to read and gf_pickLoadout to rotate loadouts

    // ── 1. Dvars ───────────────────────────────────────────────────────
    setDvar( "scr_player_healthregentime", "0" );   // _healthoverlay::init() reads this; 0 → healthRegenDisabled = true // also set level.playerHealth_RegularRegenDelay = 99999 to prevent regen after delay expires
    setDvar( "scr_sd_numlives",       "1" );  // SD internal behavior: if numlives > 1, round doesn't end on player death; we want round to end on death, so set numlives to 1 and trigger round loss in onDeadEvent
    setDvar( "scr_sd_roundlimit",     "0" );   // 0 = no total-round cap // we track round limit ourselves with level.roundWinLimit to enforce win-by-rounds and ensure UI has correct win limit for end-of-match screen
    setDvar( "scr_sd_roundwinlimit",  "6" );   // real win-limit dvar: scr_<gametype>_roundwinlimit
    setDvar( "scr_sd_scorelimit",     "6" );   // SD score = rounds won; must match win limit so UI has a valid 0-6 scale
    setDvar( "scr_sd_timelimit",      "" + ( level.gf_cfg_roundTime / 60.0 ) );
    setDvar( "scr_sd_roundswitch", "" + level.gf_cfg_roundSwitch );  // SD internal behavior: if roundswitch > 0, teams switch sides every N rounds; we want to switch sides every N rounds, so set roundswitch to our config value and track it in scr_sd_roundswitch for UI to read
    setDvar( "scr_disable_cac",    "1" );   // backup; Plutonium ignores it — replacefunc is real fix

    level.killstreaksenabled             = 0; 
    level.healthRegenDisabled            = true;          
    level.playerHealth_RegularRegenDelay = 99999; 
    level.roundWinLimit                  = level.gf_cfg_winLimit;

    // ── 2. State ───────────────────────────────────────────────────────
    level.gf_roundActive     = false; // whether a round is currently active (started but not ended); used to gate round start/end triggers in spawn and death handlers
    level.gf_roundNum        = 0; // current round number (1-based); incremented at round start; used to track rounds for loadout rotation and side switching 
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;

    // ── 3. Scoreboard ──────────────────────────────────────────────────
    setscoreboardcolumns( "kills", "deaths", "assists", "captures"); // repurpose kills/deaths columns to show rounds won/lost; hide assists/score columns 
    // I want to use "score" to represent "damage dealt" and use "captures" for future OT flag feature. idk what these are:
     //   maps\mp\gametypes\_globallogic::updateTeamStatus(); // updateTeamStatus sets team scores from player scores, so call after setting player scores to 0 in initLoadouts
     //   maps\mp\gametypes\_globallogic_ui::updateScoreboard(); // force immediate scoreboard update to show new columns and reset scores to 0

    // ── 4. Callbacks ───────────────────────────────────────────────────
    level.onDeadEvent       = ::gf_onDeadEvent; // preserve SD internal behavior; also used to trigger round loss on death
    level.onTimeLimit       = ::gf_onTimeLimit;   // preserve SD internal behavior; also used to trigger round end on time limit        
    level.playerSpawnedCB   = ::gf_playerSpawnedCB; // called at spawn pipeline step 3 (before engine giveLoadout at step 5); used to trigger round start on first spawn
    level.giveCustomLoadout = ::gf_giveCustomLoadout;   // engine calls this at spawn step 5 (from _class::giveLoadout)

    replacefunc( 
        maps\mp\gametypes\_globallogic_ui::beginClassChoice,
        ::gf_bypassClassChoice
    );

    // ── 5. Pre-generate loadout pool ───────────────────────────────────
    // Clear init flag so gf_initLoadouts always rebuilds on map_restart.
    // game[] persists across rounds and map_restart; stale schedule objects
    // (missing keys added in later versions) cause script errors in gf_giveLoadout.
    game["gf_init"] = undefined;
    gf_initLoadouts(); // pre-generate loadout pool; also generates default loadout used for class choice bypass and fallback in gf_giveCustomLoadout
    gf_pickLoadout();   // pre-pick round 1 before any spawn 

    // ── 6. Background threads ──────────────────────────────────────────
    level thread gf_bombSuppress();
    level thread gf_forfeitWatch(); 
}

// ─── Player Lifecycle ──────────────────────────────────────────────────────

gf_playerSpawnedCB()
{
    // self = player; called at spawn pipeline step 3 (before engine giveLoadout at step 5)
    level notify( "spawned_player" );   // preserve SD internal behavior
    self thread gf_onSpawned();         // thread runs after giveLoadout has completed
}

gf_onSpawned()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    if ( !level.gf_roundActive )
        level thread gf_tryActivateRound();
}

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
