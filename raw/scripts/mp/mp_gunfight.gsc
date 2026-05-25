// Gunfight v2 — Entry Point
// Load: loadMod mp_gunfight → map_restart

#include scripts\mp\_gf_rounds;

init()
{
    // ── 0. Config ──────────────────────────────────────────────────────
    level.gf_cfg_roundTime        = 90;   // seconds per round
    level.gf_cfg_winLimit         = 6;    // rounds to win the match
    level.gf_cfg_roundSwitch      = 3;    // switch sides every N rounds
    level.gf_cfg_roundsPerLoadout = 2;    // rounds before rotating loadout

    // ── 1. Dvars ───────────────────────────────────────────────────────
    setDvar( "scr_sd_numlives",    "1" );
    setDvar( "scr_sd_timelimit",   "" + ( level.gf_cfg_roundTime / 60.0 ) );
    setDvar( "scr_sd_roundswitch", "" + level.gf_cfg_roundSwitch );
    setDvar( "scr_disable_cac",    "1" );   // backup; Plutonium ignores it — replacefunc is real fix
    setDvar( "compass",            "0" );

    level.killstreaksenabled             = 0;
    level.healthRegenDisabled            = true;
    level.playerHealth_RegularRegenDelay = 0;
    level.roundWinLimit                  = level.gf_cfg_winLimit;

    // ── 2. State ───────────────────────────────────────────────────────
    level.gf_roundActive     = false;
    level.gf_roundNum        = 0;
    level.gf_roundEnding     = false;
    level.gf_activatingRound = false;

    // ── 3. Scoreboard ──────────────────────────────────────────────────
    setscoreboardcolumns( "kills", "deaths", "none", "none" );

    // ── 4. Callbacks ───────────────────────────────────────────────────
    level.onDeadEvent   = ::gf_onDeadEvent;
    level.onTimeLimit   = ::gf_onTimeLimit;
    level.onGiveLoadout = ::gf_onGiveLoadout;

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

gf_onGiveLoadout()
{
    // self = player; fires after engine's giveLoadout (step 5 of spawn pipeline)
    // safe to overwrite weapons here
    gf_pickLoadout();
    self gf_giveLoadout();

    if ( !level.gf_roundActive )
        level thread gf_tryActivateRound();
}

gf_bypassClassChoice()
{
    // replacefunc target — skips class select screen entirely
    self.pers["class"] = level.defaultClass;
    self.class         = level.defaultClass;
}
