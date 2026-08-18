// Fun / mod-menu features ported from EnCoRe V8.3 and its guest patches -- DEV ONLY.
// PRUNED 2026-08-15 to the owner's keep-list. Cut for performance/code-size: movement dvar sliders,
// fly/double-jump, model swap, killstreak gives, world builders, trampoline, music player, the
// per-player kill/bring/goto verbs, and the funSetDvar snapshot machinery they needed. The client-
// dvar features (infections, name/clantag/class names, sun/fog colour) ship as CLIENT-ONLY clipboard
// rows in the panel instead -- a dedicated server cannot push them, so GSC for them would be a lie.
// Full accounting: docs/notes/encore-v8-feature-port.md.
//
// WHY THIS IS ITS OWN FILE, and not more strip regions in _gf_rounds.gsc:
// release_common.ps1's $DevFiles drops this file WHOLESALE from the public build, exactly like
// _gf_bridge.gsc and _gf_debug.gsc. So the whole feature set adds ZERO strip-hole surface -- there
// is no marker to get wrong, and verify_release_strip.ps1 only has to prove that no KEPT code calls
// in here. ⚠ Every call INTO this file must therefore come from another dropped file
// (_gf_bridge.gsc) or from inside a strip region.
//
// ⚠ NO #include of _gf_bridge here, and none of this file there: both directions are fully
// qualified (maps\mp\gametypes\_gf_bridge::gf_bridgeNotify) so the two dropped files never form an
// include cycle. Same reason _gf_rounds helpers are called fully qualified below.
//
// STATE MODEL -- read before adding a feature:
//   * map_restart(true) runs between EVERY round and wipes all level.* and every entity. So any
//     toggle that must survive a round lives in a `gf_fun_*` DVAR, and gf_funInit() re-applies it.
//     level.* here is per-round cache ONLY.
//   * gf_funInit() is called from gf_bridgeInit(), which is already re-threaded every round behind
//     the gf_bridge_reinit collapse notify. Do not add a second per-round hook.
//   * Every persistent loop MUST carry endon("gf_fun_stop") so funreset can collapse it, plus
//     endon("game_ended") -- which fires at the end of EVERY ROUND, not at match end
//     ([[game-ended-fires-every-round-end]]). That is why the per-player "already adopted" marks
//     are GENERATION-STAMPED (level.gf_funGen), never booleans: the mark lives on the player
//     entity and survives map_restart, while the thread it records is already dead.

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
// vector_scale lives in common_scripts\utility, NOT maps\mp\_utility -- T5 has no transitive
// includes, so omitting this is an "unknown function" blamed on the CALLING function
// ([[vector-scale-in-common-scripts-utility]]).
#include common_scripts\utility;

// Max entities the fun features may hold at once (clones, gersh grenades' FX, adventure spheres,
// FX-bullet effects). Small on purpose: everything here is short-lived, and map_restart wipes it
// all between rounds anyway.
gf_funEntCap()
{
    return 120;
}

// Called once per round from gf_bridgeInit (a dropped file -- see the header). Seeds the dvars the
// panel sweeps (an unregistered dvar echoes "Unknown cmd" back at the connect sweep --
// [[rcon-connect-sweep-unknown-cmd-spam]]) and re-applies whatever was left switched on.
gf_funInit()
{
    // Master gate for the player-affecting verbs (aimbot, team god, account edits). Default 0 ON
    // PURPOSE: these change the outcome of a live public match (or write a profile), so they take a
    // deliberate second click in the panel rather than riding along with the harmless toys.
    if ( getDvar( "gf_fun_cheats"   ) == "" ) setDvar( "gf_fun_cheats",   "0"   );
    if ( getDvar( "gf_fun_bullet"   ) == "" ) setDvar( "gf_fun_bullet",   "off" );
    if ( getDvar( "gf_fun_nade"     ) == "" ) setDvar( "gf_fun_nade",     "0"   );
    if ( getDvar( "gf_fun_antiquit" ) == "" ) setDvar( "gf_fun_antiquit", "0"   );
    // Text payload slot for the verbs that carry a string (team names, splash, loading tip).
    // Cleared on read so a stale string can never be re-broadcast by a later click.
    if ( getDvar( "gf_fun_text"     ) == "" ) setDvar( "gf_fun_text",     ""    );

    level.gf_funEnts = [];

    // ⚠ PER-ROUND GENERATION TOKEN, load-bearing -- see the state model in the header.
    level.gf_funGen = gettime();

    // Re-apply the persisted toggles. These read their own gf_fun_* dvar rather than a level flag,
    // because map_restart wipes level.* between rounds and an admin expects a toggle to stay on.
    if ( getDvar( "gf_fun_bullet" ) != "" && getDvar( "gf_fun_bullet" ) != "off" )
        level thread gf_funManager( "bullet", "gf_fun_bullet_stop", ::gf_funBulletLoop );
    if ( getDvarInt( "gf_fun_nade" ) == 1 )
        level thread gf_funManager( "nade", "gf_fun_nade_stop", ::gf_funNadeLoop );
    if ( getDvarInt( "gf_fun_antiquit" ) == 1 )
        level thread gf_funAntiQuitLoop();
}

// --- Shared helpers -----------------------------------------------------------
//
// The human/bot PREDICATE is not redefined here: _gf_rounds::gf_isHuman is the single source, and it
// is a kept (public) helper specifically so dropped files can call it fully qualified. ⚠ It matters
// that it tests BOTH isdemoclient() and istestclient() -- a demo client is neither a human nor a
// bot, so "human" can never be written as "not a bot".

gf_funHumans()
{
    out = [];
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( isDefined( p ) && maps\mp\gametypes\_gf_rounds::gf_isHuman( p ) )
            out[out.size] = p;
    }
    return out;
}

gf_funCheatsAllowed()
{
    return getDvarInt( "gf_fun_cheats" ) == 1;
}

// Refusals are REPORTED, never silent: a silent ack on a locked gate reads as a broken button and
// sends the admin hunting the wrong thing (the gf_bridgeDumpPerks convention).
gf_funCheatGate()
{
    if ( gf_funCheatsAllowed() )
        return true;
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1Locked: enable 'Cheat Verbs' first (ADVANCED -> CHAOS & ACCOUNT)" );
    return false;
}

// Free text cannot ride the gf_cmd token (one bare rcon word), so the panel writes gf_fun_text
// FIRST, in the SAME chained rcon command as the verb (two packets race on the paced queue), and
// the reader clears the slot.
gf_funTakeText()
{
    text = getDvar( "gf_fun_text" );
    setDvar( "gf_fun_text", "" );
    return text;
}

// True only when the mark was stamped by THIS round's generation. An undefined mark (never adopted)
// and a stale one (adopted last round, thread since killed by game_ended) both read false, which is
// what makes the managers self-heal at every boundary.
gf_funAdopted( mark )
{
    return ( isDefined( mark ) && isDefined( level.gf_funGen ) && mark == level.gf_funGen );
}

// The adoption marks live in ONE keyed array per player rather than a field per feature, so
// adding a feature adds no field here, no case to gf_funClearFlag and no manager copy.
gf_funMarkOf( player, which )
{
    if ( !isDefined( player.gf_funMark ) )
        return undefined;
    return player.gf_funMark[which];
}

gf_funSetMark( which, value )
{
    if ( !isDefined( self.gf_funMark ) )
        self.gf_funMark = [];
    self.gf_funMark[which] = value;
}

// Drop the per-player marks so re-enabling a feature re-adopts everyone immediately rather than at
// the next round. The threads themselves are already dead (their level endon fired); this only
// clears the bookkeeping.
gf_funClearFlag( which )
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        // isDefined guard like every other roster walk here: a field write through an undefined
        // slot is a runtime error, and this one runs from gf_funReset -- an error partway would
        // abort the reset before its team-god sweep, leaving a side invulnerable while the admin
        // has been told the reset completed.
        if ( !isDefined( players[i] ) || !isDefined( players[i].gf_funMark ) )
            continue;
        players[i].gf_funMark[which] = undefined;
    }
}

// ONE adoption manager for every per-player toggle feature. Bullet modes and grenade ride ran
// byte-identical copies of this loop, and gf_funClearFlag mirrored their two field names a third
// time as a string switch -- three places to keep in step for the generation-stamp trick that this
// file's whole self-healing rests on (see the STATE MODEL in the header). Miss one and that
// feature quietly stops re-adopting players after a round boundary.
//   which      - mark key, and the gf_funClearFlag key
//   stopNotify - the feature's own collapse notify (funreset's gf_fun_stop is added here)
//   loopFn     - ::per-player loop, threaded on the player at first adoption
// ⚠ Both a variable endon() and `player thread [[fn]]()` are stock-proven in the MP VM.
gf_funManager( which, stopNotify, loopFn )
{
    level endon( "game_ended" );
    level endon( "gf_fun_stop" );
    level endon( stopNotify );
    for ( ;; )
    {
        humans = gf_funHumans();
        for ( i = 0; i < humans.size; i++ )
        {
            if ( gf_funAdopted( gf_funMarkOf( humans[i], which ) ) )
                continue;
            humans[i] gf_funSetMark( which, level.gf_funGen );
            humans[i] thread [[ loopFn ]]();
        }
        wait 2.0;
    }
}

// --- Spawned-entity registry ---------------------------------------------------
//
// Every entity a fun feature spawns goes through here, so the cap and funreset both apply. A feature
// that allocates around it is a leak the next round inherits.

gf_funTrackEnt( ent )
{
    if ( !isDefined( ent ) )
        return false;
    if ( !isDefined( level.gf_funEnts ) )
        level.gf_funEnts = [];
    // ⚠ Reclaim dead slots BEFORE judging the cap, or the cap counts TOMBSTONES: a deleted
    // entity leaves its slot behind (gf_funDeleteAfter frees the entity, not the array entry),
    // so ~15s of FX-bullet fire fills the registry with dead entries and every later crate /
    // FX / clone / sphere is spawned and instantly deleted -- the feature set silently dies
    // until the next map_restart. The cap is meant to bound LIVE entities.
    if ( level.gf_funEnts.size >= gf_funEntCap() )
        gf_funCompactEnts();
    if ( level.gf_funEnts.size >= gf_funEntCap() )
    {
        ent delete();
        return false;
    }
    level.gf_funEnts[level.gf_funEnts.size] = ent;
    return true;
}

// Drop slots whose entity is already gone (timed delete, round-end wipe, engine cleanup).
// Only ever called when the registry looks full, so the walk costs nothing in normal play.
gf_funCompactEnts()
{
    live = [];
    for ( i = 0; i < level.gf_funEnts.size; i++ )
    {
        if ( isDefined( level.gf_funEnts[i] ) )
            live[live.size] = level.gf_funEnts[i];
    }
    level.gf_funEnts = live;
}

gf_funClearEnts()
{
    if ( !isDefined( level.gf_funEnts ) )
    {
        level.gf_funEnts = [];
        return 0;
    }
    n = 0;
    for ( i = 0; i < level.gf_funEnts.size; i++ )
    {
        if ( isDefined( level.gf_funEnts[i] ) )
        {
            level.gf_funEnts[i] delete();
            n++;
        }
    }
    level.gf_funEnts = [];
    return n;
}

// Timed cleanup for one-shot FX entities. spawnFx creates a REAL entity that outlives its visual --
// without this, every FX bullet would leak one entity until the round ends.
gf_funDeleteAfter( ent, seconds )
{
    level endon( "game_ended" );
    wait seconds;
    if ( isDefined( ent ) )
        ent delete();
}

// --- Weapons -------------------------------------------------------------------
//
// ⚠ A gift lasts the CURRENT LIFE only, by design: gf_giveCustomLoadout rebuilds the shared loadout
// on every spawn, so the next respawn returns the player to the round's real weapons. That is the
// correct behaviour for a competitive gametype -- a permanent give would silently break the shared-
// loadout rule the whole mode rests on. Take All is the mid-life undo.
gf_funGiveWeapon( weapon )
{
    humans = gf_funHumans();
    n = 0;
    for ( i = 0; i < humans.size; i++ )
    {
        if ( !isAlive( humans[i] ) )
            continue;
        humans[i] GiveWeapon( weapon );
        humans[i] SwitchToWeapon( weapon );
        humans[i] GiveMaxAmmo( weapon );
        n++;
    }
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^2Gave ^7" + weapon + "^2 to " + n + " player(s) ^7(this life only)" );
}

gf_funTakeAll()
{
    humans = gf_funHumans();
    for ( i = 0; i < humans.size; i++ )
    {
        if ( isAlive( humans[i] ) )
            humans[i] TakeAllWeapons();
    }
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1Took all weapons ^7(returns next spawn)" );
}

// --- Bullet modes --------------------------------------------------------------
//
// One mode at a time, held in gf_fun_bullet so it survives map_restart. Every mode rides the
// "weapon_fired" notify and traces from the eye, exactly like the existing Explosive Bullets.
// ⚠ THROTTLED at 120ms for the same reason gf_bridgeExpBullets is: full-auto fire otherwise queues
// one impact per round-per-player and buries the frame.
//
// FX modes (EnCoRe's "FX Bullets"): fx_electric / fx_green / fx_red / fx_boom / fx_blood.
// loadfx handles are level.* and are wiped by map_restart, so they are loaded LAZILY per round
// ([[onprecache-once-per-match-loadfx-wiped]] -- same rule as the OT apron FX). Each impact effect
// is tracked AND timed-deleted: spawnFx creates a real entity that outlives its visual.
gf_funFxHandle( mode )
{
    path = "";
    if ( mode == "fx_electric" ) path = "maps/mp_maps/fx_mp_elec_spark_burst_lg";
    if ( mode == "fx_green"    ) path = "misc/fx_equip_tac_insert_light_grn";
    if ( mode == "fx_red"      ) path = "misc/fx_equip_tac_insert_light_red";
    if ( mode == "fx_boom"     ) path = "maps/mp_maps/fx_mp_exp_bomb";
    if ( mode == "fx_blood"    ) path = "trail/fx_trail_blood_streak_mp";
    if ( path == "" )
        return undefined;

    if ( !isDefined( level.gf_funFx ) )
        level.gf_funFx = [];
    if ( !isDefined( level.gf_funFx[mode] ) )
        level.gf_funFx[mode] = loadfx( path );
    return level.gf_funFx[mode];
}


gf_funBulletLoop()
{
    self endon( "disconnect" );
    level endon( "game_ended" );
    level endon( "gf_fun_stop" );
    level endon( "gf_fun_bullet_stop" );
    last = 0;
    for ( ;; )
    {
        self waittill( "weapon_fired" );

        mode = getDvar( "gf_fun_bullet" );
        if ( mode == "" || mode == "off" )
            continue;
        if ( gettime() - last < maps\mp\gametypes\_gf_bridge::gf_bridgeShotThrottleMs() )
            continue;
        last = gettime();

        // Shared with Explosive Bullets -- one copy of the trace geometry and one throttle.
        aim = self maps\mp\gametypes\_gf_bridge::gf_bridgeCrosshairTrace();
        eye = aim.eye;
        fwd = aim.forward;
        hit = aim.pos;

        if ( mode == "care" )
        {
            crate = spawn( "script_model", hit + ( 0, 0, 8 ) );
            crate setModel( "mp_supplydrop_ally" );
            gf_funTrackEnt( crate );    // cap reached: TrackEnt already deleted it
            continue;
        }
        if ( mode == "tele" )
        {
            self SetOrigin( hit + ( 0, 0, 16 ) );
            continue;
        }

        fx = gf_funFxHandle( mode );
        if ( isDefined( fx ) )
        {
            effect = spawnFx( fx, hit );
            triggerFx( effect );
            if ( gf_funTrackEnt( effect ) )
                level thread gf_funDeleteAfter( effect, 4.0 );
            continue;
        }

        // Launcher modes: fire a real projectile from the muzzle toward the impact point. The
        // weapon MUST be precached (gf.gsc's strip-marked fun block) or MagicBullet silently
        // does nothing -- the same no-op rule GiveWeapon has.
        // ⚠ EVERY mode is named explicitly and an unknown one is a NO-OP. This used to default
        // proj to "rpg_mp" and fall through, so a single typo'd verb (funbullet_fx_purple, a
        // manual `set gf_cmd`, a panel option that drifts from this list) turned every human's
        // every shot into a live RPG in a one-life round -- and gf_fun_bullet persisted it
        // across rounds via gf_funInit.
        proj = "";
        if ( mode == "rpg"       ) proj = "rpg_mp";
        if ( mode == "law"       ) proj = "m72_law_mp";
        if ( mode == "chinalake" ) proj = "china_lake_mp";
        if ( mode == "minigun"   ) proj = "minigun_wager_mp";
        if ( proj == "" )
            continue;
        MagicBullet( proj, eye + vector_scale( fwd, 32 ), hit, self );
    }
}

gf_funBulletMode( mode )
{
    if ( mode == "" )
        mode = "off";
    setDvar( "gf_fun_bullet", mode );

    if ( mode == "off" )
    {
        level notify( "gf_fun_bullet_stop" );
        gf_funClearFlag( "bullet" );
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^7Bullet mode OFF" );
        return;
    }
    // Collapse any live manager BEFORE threading a new one (the gf_funAntiQuit shape). Without
    // this, cycling modes stacked one 2s roster loop per click for the rest of the round --
    // the every-loop-is-collapsible rule in this file's header. Clearing the marks re-adopts
    // everyone immediately under the new manager instead of at its first tick.
    level notify( "gf_fun_bullet_stop" );
    gf_funClearFlag( "bullet" );
    level thread gf_funManager( "bullet", "gf_fun_bullet_stop", ::gf_funBulletLoop );
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Bullet mode: ^7" + mode );
}

// --- Positions ------------------------------------------------------------------

// Teleport every live human to whatever THEY are looking at. Per-player aim, not a single
// destination, so it scatters people usefully instead of stacking them on one point (which
// telefrags -- the curated-spawn rule).
gf_funTeleportToAim()
{
    humans = gf_funHumans();
    n = 0;
    for ( i = 0; i < humans.size; i++ )
    {
        p = humans[i];
        if ( !isAlive( p ) )
            continue;
        aim = p maps\mp\gametypes\_gf_bridge::gf_bridgeCrosshairTrace();
        p SetOrigin( aim.pos + ( 0, 0, 16 ) );
        n++;
    }
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Teleported " + n + " player(s) to their crosshair" );
}

// Save/load a position per player. pers[] because it is the only per-player store that survives the
// map_restart between rounds -- a level.* slot would be wiped before the admin could load it.
gf_funSavePos()
{
    humans = gf_funHumans();
    for ( i = 0; i < humans.size; i++ )
        humans[i].pers["gf_funPos"] = humans[i].origin;
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^2Saved " + humans.size + " position(s)" );
}

gf_funLoadPos()
{
    humans = gf_funHumans();
    n = 0;
    for ( i = 0; i < humans.size; i++ )
    {
        if ( !isAlive( humans[i] ) || !isDefined( humans[i].pers["gf_funPos"] ) )
            continue;
        humans[i] SetOrigin( humans[i].pers["gf_funPos"] );
        n++;
    }
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Restored " + n + " position(s)" );
}

// Drop a corpse copy of every live human. ⚠ EnCoRe calls this CloneSelf() -- that builtin does not
// exist anywhere in the T5 raw dump. The real one is clonePlayer( deathAnimDuration ), which stock
// MP uses for death corpses (_globallogic_player.gsc:1691). Clones are tracked so funreset removes
// them; map_restart removes them at the round boundary regardless.
gf_funClonePlayers()
{
    humans = gf_funHumans();
    n = 0;
    for ( i = 0; i < humans.size; i++ )
    {
        if ( !isAlive( humans[i] ) )
            continue;
        body = humans[i] clonePlayer( 1000 );
        if ( gf_funTrackEnt( body ) )
            n++;
    }
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Cloned " + n + " player(s)" );
}

// --- Ride your grenade (EnCoRe "Nade Training") --------------------------------
//
// Link the thrower to their own grenade and watch it fly. The CORE is server-side (LinkTo,
// freezeControls, hide, invulnerability) so it works on dedicated; only EnCoRe's camera dressing is
// partly out of reach -- cg_thirdPerson pushes fine, but its cg_fov 100 does not (archived client
// dvar, refused), so the ride is a normal-FOV third-person shot rather than a wide one.
gf_funNadeLoop()
{
    self endon( "disconnect" );
    level endon( "game_ended" );
    level endon( "gf_fun_stop" );
    level endon( "gf_fun_nade_stop" );
    for ( ;; )
    {
        self waittill( "grenade_fire", grenade );
        if ( isDefined( grenade ) )
            self thread gf_funRideGrenade( grenade );
    }
}

gf_funRideGrenade( grenade )
{
    self endon( "disconnect" );

    self freezeControls( true );
    self enableInvulnerability();
    self hide();
    self setClientDvar( "cg_thirdPerson", 1 );
    self linkTo( grenade );

    // BOUNDED, and the bound is the point: a grenade entity that is destroyed without ever firing a
    // notify we are waiting on would otherwise strand the rider frozen, invulnerable and invisible
    // for the rest of the round -- on a one-life 42s round that is the whole round.
    //
    // ⚠ DEATH AND ROUND END ARE LOOP EXITS, NOT endons. An endon("death") here skipped the restore
    // block entirely, and one of its writes does NOT heal on respawn: cg_thirdPerson is a pushed
    // CLIENT dvar, so a rider killed mid-flight (funreset's invulnerability sweep landing on a
    // linked rider, a sequenced team move, a trigger_hurt) played the REST OF THEIR SESSION in
    // third person. Everything else here is re-established by the next spawn; that one is not.
    start = gettime();
    for ( ;; )
    {
        if ( !isDefined( grenade ) || gettime() - start >= 6000 )
            break;
        if ( !isAlive( self ) )
            break;
        if ( isDefined( level.gameEnded ) && level.gameEnded )
            break;
        wait 0.05;
    }

    self unlink();
    self show();
    self setClientDvar( "cg_thirdPerson", 0 );
    // ⚠ Only unfreeze someone the ENGINE is not deliberately holding: stock freezes every client
    // for the round-end killcam and the next prematch, so an unconditional unfreeze here let a
    // rider walk around mid-countdown while everyone else was frozen. A dead/end-of-round rider
    // gets their controls back from the spawn itself.
    if ( isAlive( self ) && !( isDefined( level.gameEnded ) && level.gameEnded ) )
        self freezeControls( false );
    // ⚠ Only drop invulnerability if a global god mode is not standing, or this would quietly cancel
    // the admin's god_on for whoever last threw a grenade.
    if ( !isDefined( level.gf_godMode ) || !level.gf_godMode )
        self disableInvulnerability();
}

gf_funNadeRide( enable )
{
    if ( enable )
    {
        setDvar( "gf_fun_nade", "1" );
        // Collapse first, then re-thread -- same reason as gf_funBulletMode above: two ON
        // clicks without an intervening OFF used to leave two managers running.
        level notify( "gf_fun_nade_stop" );
        gf_funClearFlag( "nade" );
        level thread gf_funManager( "nade", "gf_fun_nade_stop", ::gf_funNadeLoop );
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Grenade ride ON" );
    }
    else
    {
        setDvar( "gf_fun_nade", "0" );
        level notify( "gf_fun_nade_stop" );
        gf_funClearFlag( "nade" );
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^7Grenade ride OFF" );
    }
}

// --- Text verbs -----------------------------------------------------------------

// The text verbs share one refusal. An EMPTY slot means the panel's chained
// "set gf_fun_text <s>;set gf_cmd <n>:<verb>" write was split or dropped on the paced rcon queue
// -- returning silently there still acks the seq, so the admin is left looking at a button that
// did nothing. Refusals are REPORTED (the gf_funCheatGate convention at the top of this file).
gf_funNoText( verb )
{
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1" + verb + ": no text arrived (the write raced or dropped) -- click it again" );
}

// --- Engine-dvar snapshots (so funreset can actually undo the text verbs) ---------
//
// The text verbs write ENGINE dvars that survive every map_restart and have no round-start
// re-apply, so funreset could stop every loop and still leave a real match being played by
// "CLOWN COLLEGE" vs "CLOWN COLLEGE". Snapshot the pre-fun value on the FIRST write and let
// funreset put it back.
// ⚠ A dvar because level.* dies at the next map_restart while these writes outlive every round.
// ⚠ The "1:" prefix is a presence sentinel: an engine default here can legitimately BE the empty
// string, which is otherwise indistinguishable from "never snapshotted".
gf_funSnapshot( name )
{
    if ( getDvar( "gf_fun_prev_" + name ) == "" )
        setDvar( "gf_fun_prev_" + name, "1:" + getDvar( name ) );
}

gf_funRestore( name )
{
    saved = getDvar( "gf_fun_prev_" + name );
    if ( saved == "" )
        return false;
    // 2-arg getSubStr = "from index 2 to the end", stock-proven in MP (_weapons.gsc:525).
    setDvar( name, getSubStr( saved, 2 ) );
    setDvar( "gf_fun_prev_" + name, "" );
    return true;
}

// Per-team names -- allies / axis / both are separate verbs because g_TeamName_Allies and
// g_TeamName_Axis are separate plain SERVER dvars (no per-client push needed).
gf_funTeamName( side )
{
    text = gf_funTakeText();
    if ( text == "" )
    {
        gf_funNoText( "Team name" );
        return;
    }

    if ( side == "allies" || side == "both" )
    {
        gf_funSnapshot( "g_TeamName_Allies" );
        setDvar( "g_TeamName_Allies", text );
    }
    if ( side == "axis" || side == "both" )
    {
        gf_funSnapshot( "g_TeamName_Axis" );
        setDvar( "g_TeamName_Axis", text );
    }
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Team name (" + side + "): ^7" + text );
}

// Center-screen splash. oldNotifyMessage is deliberate over a hand-rolled hudelem: it uses the
// engine's native decode/typewriter FX, serialises its own queue, and costs ZERO mod hudelems --
// which matters because the drawn-element cap (~17-20) is already close on this HUD.
gf_funMotd()
{
    text = gf_funTakeText();
    if ( text == "" )
    {
        gf_funNoText( "Splash" );
        return;
    }
    humans = gf_funHumans();
    for ( i = 0; i < humans.size; i++ )
    {
        // Signature is ( titleText, notifyText, iconName, glowColor, sound, duration ) -- the
        // duration is the SIXTH arg, so the unused slots have to be spelled out or the number
        // lands in `sound` and the splash plays a missing alias instead of holding for 4s.
        humans[i] thread maps\mp\gametypes\_hud_message::oldNotifyMessage( text, undefined, undefined, undefined, undefined, 4.0 );
    }
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Splash sent: ^7" + text );
}

// EnCoRe's loading-screen "didyouknow" tip string (its _rank.gsc credit scroll). A plain server
// dvar; shown by the client's loading UI. ⚠ Whether Plutonium's loading screen renders it is
// UNVERIFIED -- the write is cheap either way, and the panel row says so.
gf_funTip()
{
    text = gf_funTakeText();
    if ( text == "" )
    {
        gf_funNoText( "Loading tip" );
        return;
    }
    gf_funSnapshot( "didyouknow" );
    setDvar( "didyouknow", text );
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Loading tip set: ^7" + text );
}

// --- World FX -------------------------------------------------------------------

// Any raw engine vision by name, applied immediately to everyone.
// ⚠ TRANSIENT ON PURPOSE, and that is the difference from the bridge's vision_<key>: the persistent
// path is keyed (gf_vis_vision) and re-applied at prematch_over by _gf_rounds::gf_applyRoundVision,
// so a raw name persisted here would just be overwritten at the next round start anyway. Some of
// EnCoRe's 35 names are SP/campaign sets that may not exist in the MP zones on every map -- a
// missing set is a harmless no-op.
gf_funRawVision( name )
{
    visionSetNaked( name, 1.0 );
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Vision: ^7" + name + " ^7(until next round)" );
}

gf_funSound( alias )
{
    thread playSoundOnPlayers( alias );
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Sound: ^7" + alias );
}

// --- Anti-quit ------------------------------------------------------------------
//
// EnCoRe's "Toggle Anti Quit" (LockAll): keep every human's in-game menu closed so the ESC -> quit
// path is unusable. ⚠ Two honesty notes baked into the design:
//   * closeInGameMenu is a reliable command PER CALL PER PLAYER. EnCoRe runs it at 20 Hz, which on
//     our server is a reliable-command stream in exactly the class the budget rules forbid
//     ([[server-command-overflow-reliable-command-budget]]). 2 Hz is plenty -- navigating to Quit
//     takes seconds, and the menu snaps shut under you either way.
//   * It only blocks the MENU. Alt-F4, the console, and a network drop all still quit. It is a
//     speed bump for ragequitters, not a lock, and the panel tooltip says so.
gf_funAntiQuitLoop()
{
    level endon( "game_ended" );
    level endon( "gf_fun_stop" );
    level endon( "gf_fun_antiquit_stop" );
    for ( ;; )
    {
        if ( getDvarInt( "gf_fun_antiquit" ) == 1 )
        {
            humans = gf_funHumans();
            for ( i = 0; i < humans.size; i++ )
                humans[i] closeInGameMenu();
        }
        wait 0.5;
    }
}

gf_funAntiQuit( enable )
{
    if ( enable )
    {
        setDvar( "gf_fun_antiquit", "1" );
        level notify( "gf_fun_antiquit_stop" );   // collapse any prior copy before threading anew
        level thread gf_funAntiQuitLoop();
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1Anti-quit ON ^7(menu only -- Alt-F4 still quits)" );
    }
    else
    {
        setDvar( "gf_fun_antiquit", "0" );
        level notify( "gf_fun_antiquit_stop" );
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^7Anti-quit OFF" );
    }
}

// --- Toys -----------------------------------------------------------------------

// Gersh Device: hand a player one frag; wherever it lands, they teleport. The zombies-EE effect,
// rebuilt server-side (grenade watch + SetOrigin). Bounded like the nade ride.
gf_funGersh( numStr )
{
    target = maps\mp\gametypes\_gf_bridge::gf_bridgeFindPlayer( int( numStr ) );
    if ( !isDefined( target ) || !isAlive( target ) )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1No live player with client num " + numStr );
        return;
    }
    target GiveWeapon( "frag_grenade_mp" );
    target SetWeaponAmmoClip( "frag_grenade_mp", 1 );
    target thread gf_funGershWatch();
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5Gersh Device armed: ^7" + target.name + " ^7(throw to teleport)" );
}

gf_funGershWatch()
{
    self endon( "disconnect" );
    self endon( "death" );
    level endon( "game_ended" );
    level endon( "gf_fun_stop" );

    // Wait for THIS player's FRAG, not merely their next throw. Every shared loadout carries a
    // tactical, so returning on the first non-frag notify silently disarmed the device whenever
    // the target threw a flash/stun first -- and said nothing to anyone. The endons above bound
    // this wait (disconnect / death / round end / funreset), so an un-thrown device just expires.
    grenade = undefined;
    for ( ;; )
    {
        self waittill( "grenade_fire", thrown, weapname );
        if ( isDefined( thrown ) && weapname == "frag_grenade_mp" )
        {
            grenade = thrown;
            break;
        }
    }

    // Follow the grenade until it detonates (entity deleted), then send the thrower to its last
    // position. Bounded at 15s so a swallowed grenade can't leave a watcher thread parked forever.
    last  = grenade.origin;
    start = gettime();
    while ( isDefined( grenade ) && gettime() - start < 15000 )
    {
        last = grenade.origin;
        wait 0.05;
    }
    if ( isAlive( self ) )
        self SetOrigin( last + ( 0, 0, 16 ) );
}

// Adventure Time: link the player to a sphere and ride it into the sky, then drop them. The drop is
// the punchline (EnCoRe's does the same); with fall damage stock they will likely die -- which is
// why it sits behind the cheat gate: it can spend a life in a one-life round.
gf_funAdventure( numStr )
{
    if ( !gf_funCheatGate() )
        return;

    target = maps\mp\gametypes\_gf_bridge::gf_bridgeFindPlayer( int( numStr ) );
    if ( !isDefined( target ) || !isAlive( target ) )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1No live player with client num " + numStr );
        return;
    }
    target thread gf_funAdventureRide();
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^5It's Adventure Time: ^7" + target.name );
}

gf_funAdventureRide()
{
    self endon( "disconnect" );
    self endon( "death" );
    level endon( "game_ended" );
    level endon( "gf_fun_stop" );

    sphere = spawn( "script_model", self.origin );
    sphere setModel( "test_sphere_silver" );   // precached in gf.gsc's strip-marked fun block
    if ( !gf_funTrackEnt( sphere ) )
        return;

    self linkTo( sphere );
    sphere MoveTo( self.origin + ( 0, 0, 2000 ), 4 );
    wait 4.5;
    self unlink();
    sphere delete();
}

// --- Cheats: aimbot / team god ---------------------------------------------------

// Nearest ALIVE enemy with line of sight from `shooter`, by head tag. undefined if there is none --
// callers must treat that as "do nothing", never as "shoot anyway".
gf_funNearestEnemy( shooter )
{
    best     = undefined;
    bestDist = 0;
    eye      = shooter GetEye();
    players  = level.players;

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) || p == shooter || !isAlive( p ) )
            continue;
        // Team check via pers["team"] -- .team is not the field to trust here (the T5 API
        // difference table in CLAUDE.md exists because of exactly this).
        if ( level.teamBased && p.pers["team"] == shooter.pers["team"] )
            continue;
        head = p GetTagOrigin( "j_head" );
        if ( !bulletTracePassed( eye, head, false, shooter ) )
            continue;

        d = distance( eye, head );
        if ( !isDefined( best ) || d < bestDist )
        {
            best     = p;
            bestDist = d;
        }
    }
    return best;
}

// Two honestly-different aimbots, because on a dedicated server they are not the same thing:
//
//   snap   - drags the player's VIEW onto the target with setPlayerAngles. The view is
//            client-authoritative, so the client fights back and the result reads as violent aim
//            assist rather than a lock (the same effect gf_lockSpawnYaw has to re-assert against).
//   silent - leaves the view alone and puts the ROUND where the target is on each shot
//            (MagicBullet from the shooter's eye to the head tag). Server-authoritative, so there is
//            nothing to fight; it is also the one that actually kills reliably.
gf_funAimLoop( mode )
{
    self endon( "disconnect" );
    self endon( "gf_fun_aim_stop" );
    level endon( "game_ended" );
    level endon( "gf_fun_stop" );

    if ( mode == "silent" )
    {
        for ( ;; )
        {
            self waittill( "weapon_fired" );
            target = gf_funNearestEnemy( self );
            if ( !isDefined( target ) )
                continue;
            MagicBullet( self GetCurrentWeapon(), self GetEye(), target GetTagOrigin( "j_head" ), self );
        }
    }

    // ⚠ TARGET re-acquired at 4 Hz, VIEW re-asserted at 20 Hz. Re-picking every tick ran a full
    // line-of-sight sweep (a GetTagOrigin + bulletTracePassed for every live enemy) twenty times a
    // second for as long as the aimbot was armed -- up to ~260 traces/sec in a full lobby, on four
    // SHARED vCPUs, and bulletTrace is among the most expensive builtins here. What a player sees
    // is the 20 Hz angle write, not the pick behind it, so the effect is unchanged to the eye.
    target      = undefined;
    lastAcquire = 0;
    for ( ;; )
    {
        if ( isAlive( self ) )
        {
            if ( gettime() - lastAcquire >= 250 )
            {
                target      = gf_funNearestEnemy( self );
                lastAcquire = gettime();
            }
            // Drop a target that died or left mid-interval rather than aiming at it for the rest
            // of the quarter second (a disconnect makes the entity ref itself undefined).
            if ( isDefined( target ) && !isAlive( target ) )
                target = undefined;
            if ( isDefined( target ) )
                self SetPlayerAngles( VectorToAngles( target GetTagOrigin( "j_head" ) - self GetEye() ) );
        }
        wait 0.05;
    }
}

gf_funAimbot( numStr, mode )
{
    target = maps\mp\gametypes\_gf_bridge::gf_bridgeFindPlayer( int( numStr ) );
    if ( !isDefined( target ) )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1No player with client num " + numStr );
        return;
    }

    // ⚠ DISARMING IS DELIBERATELY UNGATED, and it sits ABOVE the gate for that reason. With the
    // cheat gate first, re-locking Cheat Verbs while an aimbot was running made its own Off
    // button answer "Locked: enable 'Cheat Verbs' first" -- the loop kept landing head shots and
    // the refusal named no way to stop it (only a re-unlock or a full funreset). Turning a live
    // cheat OFF must never require the permission that armed it. ARMING stays gated below.
    if ( mode == "off" )
    {
        target notify( "gf_fun_aim_stop" );
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^7Aimbot OFF: " + target.name );
        return;
    }

    if ( !gf_funCheatGate() )
        return;

    // ⚠ Humans only. A bot handed an aimbot fights BotWarfare's own aim loop for the same view, and
    // the reconciler owns bot behaviour.
    if ( !maps\mp\gametypes\_gf_rounds::gf_isHuman( target ) )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1" + target.name + " is a bot -- aimbot is humans-only" );
        return;
    }

    if ( mode != "snap" && mode != "silent" )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1Unknown aim mode '" + mode + "' (want snap|silent|off)" );
        return;
    }

    target notify( "gf_fun_aim_stop" );   // collapse any previous mode before arming a new one
    target thread gf_funAimLoop( mode );
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1Aimbot " + mode + ": ^7" + target.name );
}

// Per-team god mode. Separate from the bridge's god_on (which is everyone) because "make one side
// invulnerable" is the actual admin toy -- refereeing a 1vN, letting a team walk a demo.
gf_funTeamGod( team, enable )
{
    if ( !gf_funCheatGate() )
        return;
    if ( team != "allies" && team != "axis" )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1Unknown team '" + team + "' (want allies|axis)" );
        return;
    }

    players = level.players;
    n = 0;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) || !isDefined( p.pers["team"] ) || p.pers["team"] != team )
            continue;
        if ( enable )
            p enableInvulnerability();
        else
            p disableInvulnerability();
        n++;
    }

    state = "^1ON";
    if ( !enable )
        state = "^7OFF";
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^3God " + state + "^3 for " + team + " (" + n + ")" );
}

// --- Account editors -------------------------------------------------------------
//
// ⚠ THREE FACTS decide what is honest here:
//  1. Plutonium stats are NAMESPACED PER MOD -- everything below writes
//     players\mods\mp_gunfight\mpstats, this mod's own ladder
//     ([[plutonium-stats-are-namespaced-per-mod]]). Nobody's real Black Ops rank is touched.
//  2. These writes are PERSISTENT with NO UNDO, which is why they sit behind the cheat gate and
//     use only paths proven elsewhere: the prestige write is EnCoRe's exact battle-tested sequence
//     (setDStat plevel + setRank), the level-50 write is its exact statSet, and the pro-perk unlock
//     is stock's own unlockItemFromChallenge.
//  3. The name / clantag / class-name editors EnCoRe ships next to these are setClientDvar writes
//     to ARCHIVED client dvars ("name", "clanName", "customclassN") -- refused on arrival on a
//     dedicated server. They ship as CLIENT-ONLY clipboard rows in the panel, not as GSC.

gf_funPrestige( numStr, prestigeStr )
{
    if ( !gf_funCheatGate() )
        return;

    target = maps\mp\gametypes\_gf_bridge::gf_bridgeFindPlayer( int( numStr ) );
    if ( !isDefined( target ) || !maps\mp\gametypes\_gf_rounds::gf_isHuman( target ) )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1No human with client num " + numStr );
        return;
    }

    p = int( prestigeStr );
    target.pers["plevel"] = p;
    target setDStat( "playerstatslist", "plevel", "StatValue", p );
    rank = 0;
    if ( isDefined( target.pers["rank"] ) )
        rank = target.pers["rank"];
    target setRank( rank, p );
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^2Prestige " + p + ": ^7" + target.name );
}

gf_funLevel50( numStr )
{
    if ( !gf_funCheatGate() )
        return;

    target = maps\mp\gametypes\_gf_bridge::gf_bridgeFindPlayer( int( numStr ) );
    if ( !isDefined( target ) || !maps\mp\gametypes\_gf_rounds::gf_isHuman( target ) )
    {
        maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^1No human with client num " + numStr );
        return;
    }
    // EnCoRe's exact write: 1,262,500 is max-rank XP on the BO1 rank table. The in-game rank badge
    // updates at the next spawn/scoreboard refresh; the stat is committed immediately.
    target maps\mp\gametypes\_persistence::statSet( "rankxp", 1262500, true );
    target.pers["rankxp"] = 1262500;
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^2Level 50: ^7" + target.name );
}

gf_funCodPoints( amountStr )
{
    if ( !gf_funCheatGate() )
        return;

    humans = gf_funHumans();
    for ( i = 0; i < humans.size; i++ )
        humans[i] maps\mp\gametypes\_rank::setCodPointsStat( int( amountStr ) );
    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^2CoD Points set to " + amountStr + " for " + humans.size + " player(s)" );
}

// EnCoRe's "Unlock All" and "Unlock Pro Perks" are the SAME call (its UnlockAll thread just runs
// UnlockPro) -- one verb covers both menu labels. Stock's own unlock path.
gf_funUnlockPro()
{
    if ( !gf_funCheatGate() )
        return;

    perks = [];
    perks[perks.size] = "PERKS_SLEIGHT_OF_HAND";
    perks[perks.size] = "PERKS_GHOST";
    perks[perks.size] = "PERKS_NINJA";
    perks[perks.size] = "PERKS_HACKER";
    perks[perks.size] = "PERKS_LIGHTWEIGHT";
    perks[perks.size] = "PERKS_SCOUT";
    perks[perks.size] = "PERKS_STEADY_AIM";
    perks[perks.size] = "PERKS_DEEP_IMPACT";
    perks[perks.size] = "PERKS_MARATHON";
    perks[perks.size] = "PERKS_SECOND_CHANCE";
    perks[perks.size] = "PERKS_TACTICAL_MASK";
    perks[perks.size] = "PERKS_PROFESSIONAL";
    perks[perks.size] = "PERKS_SCAVENGER";
    perks[perks.size] = "PERKS_FLAK_JACKET";
    perks[perks.size] = "PERKS_HARDLINE";

    humans = gf_funHumans();
    for ( i = 0; i < humans.size; i++ )
        for ( p = 0; p < perks.size; p++ )
            for ( n = 0; n < 3; n++ )
                humans[i] maps\mp\gametypes\_persistence::unlockItemFromChallenge( "perkpro " + perks[p] + " " + n );

    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^2Pro perks unlocked for " + humans.size + " player(s)" );
}

// --- funreset: the master kill switch --------------------------------------------
//
// One click undoes the WHOLE feature set, because the realistic failure mode is an admin who left
// something on and a real match starting. Collapse every loop, delete every spawned entity, clear
// the toggles so the next round's gf_funInit re-applies nothing, and re-lock the gate.
// (Account writes are persistent by nature and are NOT undone -- that is what the gate is for.)
gf_funReset()
{
    level notify( "gf_fun_stop" );

    ents = gf_funClearEnts();

    setDvar( "gf_fun_cheats",   "0"   );
    setDvar( "gf_fun_bullet",   "off" );
    setDvar( "gf_fun_nade",     "0"   );
    setDvar( "gf_fun_antiquit", "0"   );
    setDvar( "gf_fun_text",     ""    );
    gf_funClearFlag( "bullet" );
    gf_funClearFlag( "nade"   );

    // Put back the ENGINE dvars the text verbs wrote. These survive every map_restart and have no
    // round-start re-apply, so without this the one-click kill switch stopped every loop and still
    // let the next REAL match be played by "CLOWN COLLEGE" vs "CLOWN COLLEGE" under a joke loading
    // tip -- the most VISIBLE fun state was the only state the reset missed.
    restored = 0;
    if ( gf_funRestore( "g_TeamName_Allies" ) ) restored++;
    if ( gf_funRestore( "g_TeamName_Axis"   ) ) restored++;
    if ( gf_funRestore( "didyouknow"        ) ) restored++;

    // Drop any per-team god the CHAOS block granted -- unless the global god_on is standing, which
    // funreset deliberately does not own (it has its own panel toggle).
    if ( !isDefined( level.gf_godMode ) || !level.gf_godMode )
    {
        players = level.players;
        for ( i = 0; i < players.size; i++ )
        {
            if ( isDefined( players[i] ) )
                players[i] disableInvulnerability();
        }
    }

    maps\mp\gametypes\_gf_bridge::gf_bridgeNotify( "^2Fun reset: ^7loops stopped, " + ents + " entities removed, " + restored + " dvar(s) restored, gate re-locked", true );
}
