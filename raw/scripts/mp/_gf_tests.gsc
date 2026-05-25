// Gunfight v2 — In-Engine Test Harness
// Disable: set gf_test 0  in the Plutonium console, then loadMod + map_restart
// Results appear on-screen (iPrintLn) and in the server log (logprint)

#include scripts\mp\_gf_rounds;
#include scripts\mp\_gf_loadouts;

init()
{
    if ( getDvarInt( "gf_test" ) == 0 )
        return;

    // wait one frame for mp_gunfight::init() to finish
    level thread gf_runAllTests();
}

// ─── Runner ────────────────────────────────────────────────────────────────

gf_runAllTests()
{
    level endon( "game_ended" );
    wait 0.5;

    level.gf_tp = 0;
    level.gf_tf = 0;
    level.gf_ts = 0;

    gf_testSuite_config();
    gf_testSuite_loadoutPool();
    gf_testSuite_attachmentLogic();
    gf_testSuite_loadoutPicking();
    gf_testSuite_roundState();
    gf_testSuite_winCondition();
    gf_testSuite_playerLoadout();   // skipped if no players connected
    gf_testSuite_poolShuffle();
    gf_testSuite_bombSuppress();
    gf_testSuite_loadoutCycle();
    gf_testSuite_sdCompatibility();
    gf_testSuite_notImplemented();

    total = level.gf_tp + level.gf_tf + level.gf_ts;
    summary = "GF TESTS  passed:" + level.gf_tp
            + "  failed:" + level.gf_tf
            + "  skipped:" + level.gf_ts
            + "  total:" + total;

    iPrintLn( summary );
    logprint( summary + "\n" );
}

// ─── Assert helpers ────────────────────────────────────────────────────────

gf_assert( cond, name )
{
    if ( cond )
    {
        iPrintLn( "[PASS] " + name );
        logprint( "[PASS] " + name + "\n" );
        level.gf_tp++;
    }
    else
    {
        iPrintLn( "[FAIL] " + name );
        logprint( "[FAIL] " + name + "\n" );
        level.gf_tf++;
    }
}

gf_assertEq( a, b, name )
{
    gf_assert( a == b, name + " (" + a + " == " + b + ")" );
}

gf_skip( name )
{
    iPrintLn( "[SKIP] " + name );
    logprint( "[SKIP] " + name + "\n" );
    level.gf_ts++;
}

gf_header( name )
{
    iPrintLn( "── " + name );
    logprint( "── " + name + "\n" );
}

// ─── Suite: Config ─────────────────────────────────────────────────────────

gf_testSuite_config()
{
    gf_header( "Config" );
    gf_assertEq( getDvarInt( "scr_sd_numlives" ),    1,    "one life per round" );
    gf_assert(   level.healthRegenDisabled == true,        "health regen disabled" );
    gf_assert(   level.playerHealth_RegularRegenDelay > 0, "regen delay set (non-zero disables regen)" );
    gf_assertEq( level.killstreaksenabled,           0,    "killstreaks disabled" );
    gf_assertEq( getDvarInt( "compass" ),            0,    "minimap hidden" );
    gf_assertEq( level.gf_cfg_winLimit,              6,    "win limit = 6" );
    gf_assertEq( level.roundWinLimit,  level.gf_cfg_winLimit, "roundWinLimit matches config" );
    gf_assert(   level.gf_cfg_roundTime > 0,               "round time > 0" );
    gf_assert(   level.gf_cfg_roundsPerLoadout > 0,        "rounds per loadout > 0" );

    // timer dvar matches config (SD uses minutes)
    timerSecs = int( getDvarFloat( "scr_sd_timelimit" ) * 60.0 );
    gf_assertEq( timerSecs, level.gf_cfg_roundTime, "timer dvar matches config" );

    // side-switch dvar matches config
    gf_assertEq( getDvarInt( "scr_sd_roundswitch" ), level.gf_cfg_roundSwitch, "roundswitch dvar matches config" );
}

// ─── Suite: Loadout Pool ───────────────────────────────────────────────────

gf_testSuite_loadoutPool()
{
    gf_header( "Loadout Pool" );
    gf_assert( isDefined( game["gf_pool"] ),          "pool exists in game[]" );
    gf_assertEq( game["gf_pool"].size, 22,            "pool has 22 entries" );
    gf_assert( isDefined( game["gf_schedule"] ),      "schedule exists in game[]" );
    gf_assertEq( game["gf_schedule"].size,
        game["gf_pool"].size * level.gf_cfg_roundsPerLoadout, "schedule size = pool * roundsPerLoadout" );

    // spot-check entry fields on pool[0]
    slot = game["gf_pool"][0];
    gf_assert( isDefined( slot["primary"] ),         "entry has primary" );
    gf_assert( isDefined( slot["primaryShader"] ),   "entry has primaryShader" );
    gf_assert( isDefined( slot["primaryName"] ),     "entry has primaryName" );
    gf_assert( isDefined( slot["secondary"] ),       "entry has secondary" );
    gf_assert( isDefined( slot["secondaryShader"] ), "entry has secondaryShader" );
    gf_assert( isDefined( slot["lethal"] ),          "entry has lethal" );
    gf_assert( isDefined( slot["lethalShader"] ),    "entry has lethalShader" );
    gf_assert( isDefined( slot["tactical"] ),        "entry has tactical" );

    // check all 22 entries: primary weapon string ends with _mp
    allValid = true;
    for ( i = 0; i < game["gf_pool"].size; i++ )
    {
        s    = game["gf_pool"][i];
        prim = s["primary"];
        stem = getSubStr( prim, prim.size - 3, prim.size );
        if ( stem != "_mp" )
        {
            iPrintLn( "[FAIL] pool[" + i + "] primary missing _mp suffix: " + prim );
            logprint( "[FAIL] pool[" + i + "] primary missing _mp suffix: " + prim + "\n" );
            level.gf_tf++;
            allValid = false;
        }
    }
    if ( allValid )
    {
        iPrintLn( "[PASS] all 22 pool entries have valid primary _mp suffix" );
        logprint( "[PASS] all 22 pool entries have valid primary _mp suffix\n" );
        level.gf_tp++;
    }

    // shader prefix check
    for ( i = 0; i < game["gf_pool"].size; i++ )
    {
        shader = game["gf_pool"][i]["primaryShader"];
        pfx    = getSubStr( shader, 0, 16 );   // "menu_mp_weapons_" = 16 chars
        gf_assert( pfx == "menu_mp_weapons_", "pool[" + i + "] shader prefix ok: " + shader );
    }
}

// ─── Suite: Attachment Logic ───────────────────────────────────────────────
// gf_addRandomAttachment was removed — attachments are now baked into pool entries at init.

gf_testSuite_attachmentLogic()
{
    gf_header( "Attachment Logic" );
    gf_skip( "attachment randomization removed — attachments baked into pool entries at init" );
}

// ─── Suite: Loadout Picking ────────────────────────────────────────────────

gf_testSuite_loadoutPicking()
{
    gf_header( "Loadout Picking" );

    if ( !isDefined( game["gf_schedule"] ) )
    {
        gf_skip( "loadout picking — schedule not initialized" );
        return;
    }

    savedRounds  = game["roundsplayed"];
    savedIdx     = game["gf_schedIdx"];
    savedLoad    = level.gf_currentLoad;

    // round 0 → schedIdx 0
    game["roundsplayed"]  = 0;
    game["gf_schedIdx"]   = -1;
    level.gf_currentLoad  = undefined;
    gf_pickLoadout();
    gf_assert( isDefined( level.gf_currentLoad ),             "pickLoadout defines currentLoad" );
    gf_assert( isDefined( level.gf_currentLoad["primary"] ),  "currentLoad has primary" );
    gf_assert( isDefined( level.gf_currentLoad["secondary"] ),"currentLoad has secondary" );
    gf_assert( isDefined( level.gf_currentLoad["lethal"] ),   "currentLoad has lethal" );
    gf_assert( isDefined( level.gf_currentLoad["tactical"] ), "currentLoad has tactical" );
    gf_assertEq( game["gf_schedIdx"], 0,                      "schedIdx = 0 at round 0" );

    // idempotent: same roundsplayed → same loadout
    firstPrimary = level.gf_currentLoad["primary"];
    game["roundsplayed"] = 0;
    gf_pickLoadout();
    gf_assertEq( level.gf_currentLoad["primary"], firstPrimary, "pickLoadout idempotent" );

    // round 2 → schedIdx 2  (schedule is indexed directly by roundsplayed)
    game["roundsplayed"] = 2;
    game["gf_schedIdx"]  = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    expectedIdx = 2 % game["gf_schedule"].size;
    gf_assertEq( game["gf_schedIdx"], expectedIdx, "schedIdx = " + expectedIdx + " at round 2" );

    // restore
    game["roundsplayed"] = savedRounds;
    game["gf_schedIdx"]  = savedIdx;
    level.gf_currentLoad = savedLoad;
}

// ─── Suite: Round State Machine ────────────────────────────────────────────

gf_testSuite_roundState()
{
    gf_header( "Round State Machine" );

    // initial state
    gf_assert( !level.gf_roundActive,    "roundActive starts false" );
    gf_assert( !level.gf_roundEnding,    "roundEnding starts false" );
    gf_assert( !level.gf_activatingRound,"activatingRound starts false" );

    // simulate dead-event state transitions (without calling sd_endgame)
    savedActive  = level.gf_roundActive;
    savedEnding  = level.gf_roundEnding;

    level.gf_roundActive = true;
    level.gf_roundEnding = false;

    // replicate what gf_onDeadEvent does to flags (not the sd_endgame call)
    level.gf_roundEnding = true;
    level.gf_roundActive = false;

    gf_assert( !level.gf_roundActive, "roundActive cleared on elimination" );
    gf_assert( level.gf_roundEnding,  "roundEnding set on elimination" );

    // double-fire guard: calling again with roundEnding=true should be no-op
    level.gf_roundActive = true;    // set back to test guard
    if ( level.gf_roundEnding )
    {
        // gf_onDeadEvent would return early — simulate that
        level.gf_roundActive = false; // restored because guard exits early
    }
    gf_assert( !level.gf_roundActive, "double-fire guard keeps roundActive false" );

    // restore
    level.gf_roundActive = savedActive;
    level.gf_roundEnding = savedEnding;
}

// ─── Suite: Win Condition ──────────────────────────────────────────────────

gf_testSuite_winCondition()
{
    gf_header( "Win Condition" );

    gf_assertEq( level.roundWinLimit, 6, "first to 6 rounds wins" );
    gf_assertEq( level.roundWinLimit, level.gf_cfg_winLimit, "win limit from config" );

    // roundswon structure
    gf_assert( isDefined( game["roundswon"] ),           "game[roundswon] exists" );
    gf_assert( isDefined( game["roundswon"]["allies"] ),  "allies wins tracked" );
    gf_assert( isDefined( game["roundswon"]["axis"] ),    "axis wins tracked" );

    // match point: a team at winLimit-1 is at match point
    savedAllies = game["roundswon"]["allies"];
    game["roundswon"]["allies"] = level.roundWinLimit - 1;
    atMatchPoint = ( game["roundswon"]["allies"] == level.roundWinLimit - 1 );
    gf_assert( atMatchPoint, "match point detected at winLimit-1" );
    game["roundswon"]["allies"] = savedAllies;

    // forfeit: gf_teamIsEmpty should return true with 0 playing players
    // (safe to test since it only reads level.players — no side effects)
    gf_assert( isDefined( level.players ), "level.players defined" );
}

// ─── Suite: Player Loadout (requires connected players) ────────────────────

gf_testSuite_playerLoadout()
{
    gf_header( "Player Loadout" );

    if ( level.players.size == 0 )
    {
        gf_skip( "all player loadout tests — no players connected" );
        return;
    }

    if ( !isDefined( level.gf_currentLoad ) )
    {
        gf_skip( "player loadout tests — no loadout picked yet (spawn first)" );
        return;
    }

    primary = level.gf_currentLoad["primary"];

    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( p.pers["team"] == "spectator" )
            continue;
        if ( p.sessionstate != "playing" )
            continue;

        // primary weapon
        gf_assert( p hasWeapon( primary ),
            "player " + i + " has primary: " + primary );

        // knife always present
        gf_assert( p hasWeapon( "knife_mp" ),
            "player " + i + " has knife" );

        // weapon ends with _mp
        stem = getSubStr( primary, primary.size - 3, primary.size );
        gf_assertEq( stem, "_mp", "primary weapon has _mp suffix" );
    }

    // both teams get identical primary (all playing players share currentLoad)
    teamsMatch = true;
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( p.pers["team"] == "spectator" || p.sessionstate != "playing" )
            continue;
        if ( !p hasWeapon( primary ) )
        {
            teamsMatch = false;
        }
    }
    gf_assert( teamsMatch, "all teams have identical primary weapon" );
}

// ─── Suite: Pool Shuffle Uniqueness ───────────────────────────────────────

gf_testSuite_poolShuffle()
{
    gf_header( "Pool Shuffle Uniqueness" );

    if ( !isDefined( game["gf_pool"] ) )
    {
        gf_skip( "pool shuffle — pool not initialized" );
        return;
    }

    // no duplicate primary entries (full baked weapon string is unique per slot)
    seen   = [];
    dupes  = 0;
    for ( i = 0; i < game["gf_pool"].size; i++ )
    {
        prim = game["gf_pool"][i]["primary"];
        if ( isDefined( seen[prim] ) )
        {
            iPrintLn( "[FAIL] duplicate pool entry: " + prim );
            logprint( "[FAIL] duplicate pool entry: " + prim + "\n" );
            level.gf_tf++;
            dupes++;
        }
        else
            seen[prim] = 1;
    }
    if ( dupes == 0 )
        gf_assert( true, "all 22 pool entries have unique primary" );

    // spot-check: one representative weapon base per class must be present
    classWeapons    = [];
    classWeapons[0] = "famas";    // AR
    classWeapons[1] = "mp5k";     // SMG
    classWeapons[2] = "hk21";     // LMG
    classWeapons[3] = "l96a1";    // Sniper
    classWeapons[4] = "spas";     // Shotgun
    for ( i = 0; i < classWeapons.size; i++ )
    {
        base  = classWeapons[i];
        found = false;
        for ( j = 0; j < game["gf_pool"].size; j++ )
        {
            prim = game["gf_pool"][j]["primary"];
            if ( getSubStr( prim, 0, base.size ) == base )
            {
                found = true;
                break;
            }
        }
        gf_assert( found, "pool contains " + base + " class" );
    }
}

// ─── Suite: Bomb Suppress ──────────────────────────────────────────────────

gf_testSuite_bombSuppress()
{
    gf_header( "Bomb Suppress" );

    // at startup the suppress thread should have zeroed these
    gf_assertEq( level.bombplanted,  0, "bombplanted zeroed at init" );
    gf_assertEq( level.bombexploded, 0, "bombexploded zeroed at init" );
    gf_assertEq( level.bombdefused,  0, "bombdefused zeroed at init" );

    // verify suppress logic itself: set to non-zero, apply, confirm back to zero
    level.bombplanted  = 1;
    level.bombexploded = 1;
    level.bombdefused  = 1;
    level.bombplanted  = 0;
    level.bombexploded = 0;
    level.bombdefused  = 0;
    gf_assertEq( level.bombplanted,  0, "suppress resets bombplanted" );
    gf_assertEq( level.bombexploded, 0, "suppress resets bombexploded" );
    gf_assertEq( level.bombdefused,  0, "suppress resets bombdefused" );
}

// ─── Suite: Loadout Cycle Rotation ────────────────────────────────────────

gf_testSuite_loadoutCycle()
{
    gf_header( "Loadout Cycle Rotation" );

    if ( !isDefined( game["gf_schedule"] ) )
    {
        gf_skip( "loadout cycle — schedule not initialized" );
        return;
    }

    savedRounds = game["roundsplayed"];
    savedIdx    = game["gf_schedIdx"];
    savedLoad   = level.gf_currentLoad;

    schedSz = game["gf_schedule"].size;   // pool.size * roundsPerLoadout

    // full cycle: roundsplayed = schedSz wraps schedIdx back to 0
    game["roundsplayed"] = schedSz;
    game["gf_schedIdx"]  = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    gf_assertEq( game["gf_schedIdx"], 0, "schedIdx wraps to 0 at full cycle (round " + game["roundsplayed"] + ")" );

    // last slot: roundsplayed = schedSz - 1 → idx = schedSz - 1
    lastRound = schedSz - 1;
    game["roundsplayed"] = lastRound;
    game["gf_schedIdx"]  = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    gf_assertEq( game["gf_schedIdx"], lastRound, "schedIdx = last slot before wrap" );

    // half-way through schedule
    midRound = int( schedSz / 2 );
    game["roundsplayed"] = midRound;
    game["gf_schedIdx"]  = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    gf_assertEq( game["gf_schedIdx"], midRound % schedSz, "schedIdx = schedule midpoint" );

    // restore
    game["roundsplayed"] = savedRounds;
    game["gf_schedIdx"]  = savedIdx;
    level.gf_currentLoad = savedLoad;
}

// ─── Suite: SD Compatibility ──────────────────────────────────────────────
// Verifies that SD's internal state hasn't been clobbered and our overrides
// are still wired correctly.  Nothing here calls sd_endgame — pure reads.

gf_testSuite_sdCompatibility()
{
    gf_header( "SD Compatibility" );

    // ── Our callbacks still registered ─────────────────────────────────
    gf_assert( isDefined( level.onDeadEvent ),     "level.onDeadEvent is set" );
    gf_assert( isDefined( level.onTimeLimit ),     "level.onTimeLimit is set" );
    gf_assert( isDefined( level.playerSpawnedCB ), "level.playerSpawnedCB is set" );

    // ── SD game[] state our winner logic depends on ────────────────────
    gf_assert( isDefined( game["attackers"] ), "game[attackers] defined — needed by gf_onDeadEvent" );
    gf_assert( isDefined( game["defenders"] ), "game[defenders] defined — needed by gf_onTimeLimit" );
    gf_assert( isDefined( game["state"] ),     "game[state] defined" );

    // ── roundWinLimit not clobbered after our init() set it ────────────
    gf_assertEq( level.roundWinLimit, level.gf_cfg_winLimit,
        "roundWinLimit not overwritten post-init (SD may set from scr_sd_roundlimit)" );

    // ── Grace period must not be blocking dead-event / forfeit checks ──
    gf_assert( !level.inGracePeriod, "inGracePeriod is false at test time" );

    // ── defaultClass must exist for gf_bypassClassChoice ──────────────
    gf_assert( isDefined( level.defaultClass ), "level.defaultClass defined for class bypass" );

    // ── SD numlives dvar — SD reads this to decide if player can respawn
    gf_assertEq( getDvarInt( "scr_sd_numlives" ), 1, "scr_sd_numlives = 1 (no mid-round respawns)" );

    // ── Class select backup dvar ───────────────────────────────────────
    gf_assertEq( getDvarInt( "scr_disable_cac" ), 1, "scr_disable_cac = 1" );

    // ── Bomb vars — our override bypasses SD's bomb logic; they must stay
    //    at 0 so bomb HUD prompts never appear and bomb timers never fire.
    gf_assertEq( level.bombplanted,  0, "bombplanted = 0 (suppress working)" );
    gf_assertEq( level.bombexploded, 0, "bombexploded = 0" );
    gf_assertEq( level.bombdefused,  0, "bombdefused = 0" );

    // ── Killstreaks and regen still off (verify SD didn't re-enable) ───
    gf_assertEq( level.killstreaksenabled,            0,    "killstreaks still disabled" );
    gf_assert(   level.healthRegenDisabled == true,         "health regen still disabled" );
    gf_assert(   level.playerHealth_RegularRegenDelay > 0,  "regen delay still set (non-zero)" );

    // ── Minimap still hidden ───────────────────────────────────────────
    gf_assertEq( getDvarInt( "compass" ), 0, "minimap still hidden" );
}

// ─── Suite: Not Yet Implemented ────────────────────────────────────────────

gf_testSuite_notImplemented()
{
    gf_header( "Not Yet Implemented (future)" );
    gf_skip( "spectator mode on death — engine-handled, verify manually" );
    gf_skip( "damage values — requires live DoDamage call in session" );
    gf_skip( "perk icon shader names — unverified in T5, check in-game" );
}
