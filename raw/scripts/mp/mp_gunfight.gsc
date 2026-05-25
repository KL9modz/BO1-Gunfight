// Gunfight v2 — Entry Point
// Load: loadMod mp_gunfight → map_restart

#include scripts\mp\_gf_rounds;
#include scripts\mp\_gf_loadouts;

init()
{
    // ── 0. Config ──────────────────────────────────────────────────────
    level.gf_cfg_roundTime        = getDvarInt( "gf_round_time" );
    if ( level.gf_cfg_roundTime <= 0 ) level.gf_cfg_roundTime = 60;
    level.gf_cfg_winLimit         = 6;    // rounds to win the match
    level.gf_cfg_roundSwitch      = 3;    // switch sides every N rounds
    level.gf_cfg_roundsPerLoadout = 2;    // rounds before rotating loadout

    // ── 1. Dvars ───────────────────────────────────────────────────────
    setDvar( "scr_player_healthregentime", "0" );   // _healthoverlay::init() reads this; 0 → healthRegenDisabled = true
    setDvar( "scr_sd_numlives",       "1" );
    setDvar( "scr_sd_roundlimit",     "0" );   // 0 = no total-round cap
    setDvar( "scr_sd_roundwinlimit",  "6" );   // real win-limit dvar: scr_<gametype>_roundwinlimit
    setDvar( "scr_sd_scorelimit",     "6" );   // SD score = rounds won; must match win limit so UI has a valid 0-6 scale
    setDvar( "scr_sd_timelimit",      "" + ( level.gf_cfg_roundTime / 60.0 ) );
    setDvar( "scr_sd_roundswitch", "" + level.gf_cfg_roundSwitch );
    setDvar( "scr_disable_cac",    "1" );   // backup; Plutonium ignores it — replacefunc is real fix
    setDvar( "compass",            "0" );

    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 99999;
    level.roundWinLimit                  = level.gf_cfg_winLimit;

    // ── 2. State ───────────────────────────────────────────────────────
    level.gf_roundActive     = false;
    level.gf_roundNum        = 0;
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;

    // ── 3. Scoreboard ──────────────────────────────────────────────────
    setscoreboardcolumns( "kills", "deaths", "none", "none" );

    // ── 4. Callbacks ───────────────────────────────────────────────────
    level.onDeadEvent      = ::gf_onDeadEvent;
    level.onTimeLimit      = ::gf_onTimeLimit;
    level.playerSpawnedCB  = ::gf_playerSpawnedCB;   // level.onGiveLoadout does not exist in T5

    replacefunc(
        maps\mp\gametypes\_globallogic_ui::beginClassChoice,
        ::gf_bypassClassChoice
    );

    // ── 5. Pre-generate loadout pool ───────────────────────────────────
    gf_initLoadouts();

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

    gf_pickLoadout();
    self gf_giveLoadout();

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
