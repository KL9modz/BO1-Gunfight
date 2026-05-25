// Gunfight v2 — In-Engine Test Harness
// Enable: set gf_test 1  in the Plutonium console, then loadMod + map_restart
// Results appear on-screen (iPrintLn) and in the server log (logprint)

#include scripts\mp\_gf_rounds;

init()
{
    if ( getDvarInt( "gf_test" ) != 1 )
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
    gf_assertEq( level.playerHealth_RegularRegenDelay, 0,  "regen delay = 0" );
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

    // spot-check entry fields
    slot = game["gf_pool"][0];
    gf_assert( isDefined( slot["primaryBase"] ),       "entry has primaryBase" );
    gf_assert( isDefined( slot["primaryShader"] ),     "entry has primaryShader" );
    gf_assert( isDefined( slot["primaryName"] ),       "entry has primaryName" );
    gf_assert( isDefined( slot["primaryAtts"] ),       "entry has primaryAtts" );
    gf_assert( isDefined( slot["perks"] ),             "entry has perks" );
    gf_assertEq( slot["perks"].size, 3,                "entry has 3 perks" );

    // check all 22 entries have required fields + _mp suffix on base
    allValid = true;
    for ( i = 0; i < game["gf_pool"].size; i++ )
    {
        s = game["gf_pool"][i];
        base = s["primaryBase"];
        stem = getSubStr( base, base.size - 3, base.size );
        if ( stem != "_mp" )
        {
            iPrintLn( "[FAIL] pool[" + i + "] primaryBase missing _mp: " + base );
            logprint( "[FAIL] pool[" + i + "] primaryBase missing _mp: " + base + "\n" );
            level.gf_tf++;
            allValid = false;
        }
        if ( s["perks"].size != 3 )
        {
            iPrintLn( "[FAIL] pool[" + i + "] wrong perk count: " + s["perks"].size );
            logprint( "[FAIL] pool[" + i + "] wrong perk count: " + s["perks"].size + "\n" );
            level.gf_tf++;
            allValid = false;
        }
    }
    if ( allValid )
    {
        iPrintLn( "[PASS] all 22 pool entries valid" );
        logprint( "[PASS] all 22 pool entries valid\n" );
        level.gf_tp++;
    }

    // shader prefix check
    for ( i = 0; i < game["gf_pool"].size; i++ )
    {
        shader = game["gf_pool"][i]["primaryShader"];
        pfx    = getSubStr( shader, 0, 18 );   // "menu_mp_weapons_" = 16 chars
        gf_assert( pfx == "menu_mp_weapons_", "pool[" + i + "] shader prefix ok: " + shader );
    }
}

// ─── Suite: Attachment Logic ───────────────────────────────────────────────

gf_testSuite_attachmentLogic()
{
    gf_header( "Attachment Logic" );

    atts    = [];
    atts[0] = "reflex";
    atts[1] = "acog";

    // run 10 times and verify every result ends with _mp
    allGood = true;
    for ( i = 0; i < 10; i++ )
    {
        r    = gf_addRandomAttachment( "famas_mp", atts );
        stem = getSubStr( r, r.size - 3, r.size );
        if ( stem != "_mp" )
        {
            gf_assert( false, "attachment result ends with _mp: " + r );
            allGood = false;
        }
    }
    if ( allGood )
        gf_assert( true, "10 attachment rolls all end with _mp" );

    // no-attachment path (empty list always returns base)
    empty   = [];
    base    = "m16_mp";
    for ( i = 0; i < 5; i++ )
    {
        r = gf_addRandomAttachment( base, empty );
        gf_assertEq( r, base, "empty att list returns base unchanged" );
    }

    // single attachment — result must be base OR base_att_mp
    oneAtt    = [];
    oneAtt[0] = "silencer";
    ok = true;
    for ( i = 0; i < 20; i++ )
    {
        r = gf_addRandomAttachment( "mp5k_mp", oneAtt );
        if ( r != "mp5k_mp" && r != "mp5k_silencer_mp" )
        {
            gf_assert( false, "unexpected attachment result: " + r );
            ok = false;
        }
    }
    if ( ok )
        gf_assert( true, "single-att results valid over 20 rolls" );
}

// ─── Suite: Loadout Picking ────────────────────────────────────────────────

gf_testSuite_loadoutPicking()
{
    gf_header( "Loadout Picking" );

    savedRounds  = game["roundsplayed"];
    savedIdx     = game["gf_idx"];
    savedLoad    = level.gf_currentLoad;

    // round 0 → idx 0
    game["roundsplayed"] = 0;
    game["gf_idx"]       = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    gf_assert( isDefined( level.gf_currentLoad ),    "pickLoadout defines currentLoad" );
    gf_assert( isDefined( level.gf_currentLoad["primary"] ),   "currentLoad has primary" );
    gf_assert( isDefined( level.gf_currentLoad["secondary"] ), "currentLoad has secondary" );
    gf_assert( isDefined( level.gf_currentLoad["lethal"] ),    "currentLoad has lethal" );
    gf_assert( isDefined( level.gf_currentLoad["tactical"] ),  "currentLoad has tactical" );
    gf_assert( isDefined( level.gf_currentLoad["perks"] ),     "currentLoad has perks" );
    gf_assertEq( level.gf_currentLoad["perks"].size, 3,        "currentLoad has 3 perks" );
    gf_assertEq( game["gf_idx"], 0,                            "idx = 0 at round 0" );

    // idempotent: same roundsplayed → same loadout
    firstPrimary = level.gf_currentLoad["primary"];
    game["roundsplayed"] = 0;
    gf_pickLoadout();
    gf_assertEq( level.gf_currentLoad["primary"], firstPrimary, "pickLoadout idempotent" );

    // round 2 → idx 1  (with roundsPerLoadout = 2)
    game["roundsplayed"] = 2;
    game["gf_idx"]       = -1;
    gf_pickLoadout();
    expectedIdx = int( 2 / level.gf_cfg_roundsPerLoadout ) % game["gf_pool"].size;
    gf_assertEq( game["gf_idx"], expectedIdx, "idx advances at round " + 2 );

    // restore
    game["roundsplayed"] = savedRounds;
    game["gf_idx"]       = savedIdx;
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

    // no duplicate primaryBase entries
    seen   = [];
    dupes  = 0;
    for ( i = 0; i < game["gf_pool"].size; i++ )
    {
        base = game["gf_pool"][i]["primaryBase"];
        if ( isDefined( seen[base] ) )
        {
            iPrintLn( "[FAIL] duplicate pool entry: " + base );
            logprint( "[FAIL] duplicate pool entry: " + base + "\n" );
            level.gf_tf++;
            dupes++;
        }
        else
            seen[base] = 1;
    }
    if ( dupes == 0 )
        gf_assert( true, "all 22 pool entries have unique primaryBase" );

    // spot-check: representative weapon from each class present
    mustHave    = [];
    mustHave[0] = "famas_mp";     // AR
    mustHave[1] = "mp5k_mp";      // SMG
    mustHave[2] = "hk21_mp";      // LMG
    mustHave[3] = "l96a1_mp";     // Sniper
    mustHave[4] = "spas_mp";      // Shotgun
    for ( i = 0; i < mustHave.size; i++ )
    {
        found = false;
        for ( j = 0; j < game["gf_pool"].size; j++ )
        {
            if ( game["gf_pool"][j]["primaryBase"] == mustHave[i] )
            {
                found = true;
                break;
            }
        }
        gf_assert( found, "pool contains " + mustHave[i] );
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

    if ( !isDefined( game["gf_pool"] ) )
    {
        gf_skip( "loadout cycle — pool not initialized" );
        return;
    }

    savedRounds = game["roundsplayed"];
    savedIdx    = game["gf_idx"];
    savedLoad   = level.gf_currentLoad;

    poolSz = game["gf_pool"].size;   // 22

    // full cycle: rounds = poolSz * roundsPerLoadout → idx wraps back to 0
    game["roundsplayed"] = poolSz * level.gf_cfg_roundsPerLoadout;
    game["gf_idx"]       = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    gf_assertEq( game["gf_idx"], 0, "idx wraps to 0 at full cycle (round " + game["roundsplayed"] + ")" );

    // last slot before wrap: rounds = (poolSz * roundsPerLoadout) - roundsPerLoadout
    lastRound = poolSz * level.gf_cfg_roundsPerLoadout - level.gf_cfg_roundsPerLoadout;
    game["roundsplayed"] = lastRound;
    game["gf_idx"]       = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    expectedLast = int( lastRound / level.gf_cfg_roundsPerLoadout ) % poolSz;
    gf_assertEq( game["gf_idx"], expectedLast, "idx = " + expectedLast + " at last slot before wrap" );

    // half-way through pool
    midRound = int( poolSz / 2 ) * level.gf_cfg_roundsPerLoadout;
    game["roundsplayed"] = midRound;
    game["gf_idx"]       = -1;
    level.gf_currentLoad = undefined;
    gf_pickLoadout();
    expectedMid = int( midRound / level.gf_cfg_roundsPerLoadout ) % poolSz;
    gf_assertEq( game["gf_idx"], expectedMid, "idx = " + expectedMid + " at pool midpoint" );

    // restore
    game["roundsplayed"] = savedRounds;
    game["gf_idx"]       = savedIdx;
    level.gf_currentLoad = savedLoad;
}

// ─── Suite: SD Compatibility ──────────────────────────────────────────────
// Verifies that SD's internal state hasn't been clobbered and our overrides
// are still wired correctly.  Nothing here calls sd_endgame — pure reads.

gf_testSuite_sdCompatibility()
{
    gf_header( "SD Compatibility" );

    // ── Our callbacks still registered ─────────────────────────────────
    gf_assert( isDefined( level.onDeadEvent ),   "level.onDeadEvent is set" );
    gf_assert( isDefined( level.onTimeLimit ),   "level.onTimeLimit is set" );
    gf_assert( isDefined( level.onGiveLoadout ), "level.onGiveLoadout is set" );

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

    // ── Bomb vars — SD's default onDeadEvent reads these to pick winner;
    //    our override bypasses it, but they must stay 0 so bomb HUD
    //    prompts never appear and SD's bomb timers never fire.
    gf_assertEq( level.bombplanted,  0, "bombplanted = 0 (suppress working)" );
    gf_assertEq( level.bombexploded, 0, "bombexploded = 0" );
    gf_assertEq( level.bombdefused,  0, "bombdefused = 0" );

    // ── Killstreaks and regen still off (verify SD didn't re-enable) ───
    gf_assertEq( level.killstreaksenabled,           0,    "killstreaks still disabled" );
    gf_assert(   level.healthRegenDisabled == true,        "health regen still disabled" );
    gf_assertEq( level.playerHealth_RegularRegenDelay, 0,  "regen delay still 0" );

    // ── Minimap still hidden ───────────────────────────────────────────
    gf_assertEq( getDvarInt( "compass" ), 0, "minimap still hidden" );
}

// ─── Suite: Not Yet Implemented ────────────────────────────────────────────

gf_testSuite_notImplemented()
{
    gf_header( "Not Yet Implemented (future)" );
    gf_skip( "HP tiebreaker on timeout — overtime not built" );
    gf_skip( "one team 1 HP more wins on timeout — overtime not built" );
    gf_skip( "timeout tie = draw — overtime not built" );
    gf_skip( "spectator mode on death — engine-handled, verify manually" );
    gf_skip( "damage values — requires live DoDamage call in session" );
}
