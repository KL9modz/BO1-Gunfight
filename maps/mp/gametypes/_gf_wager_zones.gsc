// Gunfight wager-zone support.
//
// The important blockers are baked into the map entity lump with
// script_gameobjectname values for the stock wager gametypes.  Gunfight keeps
// them by adding gun/oic/hlnd/shrp to the _gameobjects allow-list in gf.gsc.
// This file only handles the remaining wager-zone helpers.

gf_precacheWagerZoneAssets()
{
    mapname = getDvar( "mapname" );

    if ( mapname == "mp_cosmodrome" )
    {
        precacheModel( "collision_geo_mc_8x560x190" );
        precacheModel( "collision_geo_mc_4x52x190" );
        precacheModel( "collision_geo_mc_4x156x190" );
    }
}

gf_applyWagerZoneAssets()
{
    wagerSpawns = getEntArray( "mp_wager_spawn", "classname" );
    if ( wagerSpawns.size <= 0 )
        return;

    mapname = getDvar( "mapname" );

    gf_setupWagerZoneCompass( mapname );

    if ( mapname == "mp_cosmodrome" )
        gf_applyCosmodromeWagerZone();

    if ( mapname == "mp_radiation" )
        level thread gf_disableRadiationDoors();
}

// mp_radiation: keep the center blast doors shut, like the stock wager modes do.
//
// The stock door driver (mp_radiation.gsc::door_switch_func) parks at
// waittill_any_ents( level._door_switch_trig1, "trigger", trig2, "trigger" ),
// and the auto-open (double_doors_open_at_start) fires a DIRECT script notify
// on level._door_switch_trig1 at prematch_over + 0.3s. trigger_off() only
// moves the trigger out of player reach — script notifies pass right through
// it, which is why turning the switches off alone never stopped the auto-open.
//
// Two-part fix, all engine primitives:
//   1. trigger_off() both switch ents — blocks the player/bot use path.
//   2. Repoint level._door_switch_trig1/2 at a dummy script_origin — the
//      auto-open notify lands on the dummy; the door driver stays parked on
//      the real (now silent) triggers forever, so the door mover never runs.
//
// The swap waits for prematch_over + 0.2s on purpose: the map's switch_lights/
// tunnel_lights threads re-read the level vars at +0.1s and the auto-open
// notify fires at +0.3s. Swapping in between leaves the lights idling on the
// real triggers (green panel, no blink) exactly like an untouched wager match,
// while the +0.3s notify hits the dummy. Re-runs every round via
// onStartGameType, which map_restart re-fires.
gf_disableRadiationDoors()
{
    level endon( "game_ended" );

    // The map assigns these in level_objects_init after its waittillframeend;
    // that resumes earlier in this same frame-end slice. Loop is a fallback.
    waittillframeend;
    while ( !isDefined( level._door_switch_trig1 ) || !isDefined( level._door_switch_trig2 ) )
        wait 0.05;

    level._door_switch_trig1 common_scripts\utility::trigger_off();
    level._door_switch_trig2 common_scripts\utility::trigger_off();

    // Same gate as the map's double_doors_open_at_start / switch_lights, so we share their
    // timeline. ⚠ MUST anchor on the ENGINE's t≈0 prematch_over fire (level.prematchPeriod is
    // pinned to 0 by the mod-owned countdown, gf.gsc) — the same fire the map's own listeners
    // consume, because the auto-open notify lands at that fire +0.3s and the swap below has to
    // beat it. inPrematchPeriod is NOT a usable gate here: gf_prematchCountdown re-asserts it
    // true right after the engine fire, so parking on it could strand this thread until the GO
    // re-fire — 0.3s AFTER the doors already auto-opened on the real triggers. The countdown
    // stamps gf_enginePrematchFired in the same notify dispatch, so: unset → the fire hasn't
    // happened, park with the map threads; set → it just happened this frame, fall through.
    // (Either way the doors/lights sequence runs at countdown START, not GO — players are
    // locked then; cosmetic.)
    if ( !isDefined( level.gf_enginePrematchFired ) || !level.gf_enginePrematchFired )
        level waittill( "prematch_over" );
    wait 0.2;

    dummy = spawn( "script_origin", ( 0, 0, 0 ) );
    level._door_switch_trig1 = dummy;
    level._door_switch_trig2 = dummy;
}

gf_setupWagerZoneCompass( mapname )
{
    material = gf_getWagerCompassMaterial( mapname );
    if ( material == "" )
        return;

    maps\mp\_compass::setupMiniMap( material );
}

// Whitelist of maps whose compass_map_<map>_wager image is actually RESIDENT during
// a gunfight match, so we only force the wager (zoomed) minimap where it can render;
// every other map returns "" and keeps its own full compass (never blank).
//
// Subtlety learned the hard way: the art existing is not enough — it has to be
// loaded in gunfight. The 12 base maps keep theirs in the always-loaded
// common_mp_compass zone, and Silo + Berlin Wall keep theirs somewhere resident too,
// so all of those bind fine. But First Strike & Escalation maps (Discovery,
// Convoy=mp_gridlock, Hotel, Stockpile=mp_outskirts, Kowloon, Stadium, Zoo) keep
// their wager compass in a wager-only zone that gunfight (xblive_wagermatch 0) never
// loads — the art only appears when you set xblive_wagermatch 1, and precaching
// can't pull it from an unloaded zone. So those stay OFF this list and show their
// full compass instead of a blank.
//
// ⚠ FOUR exclusions are UNVERIFIED, not reasoned (the rationale above covers the others):
//   - mp_nuked (base): Nuketown was never a wager map, so a compass_map_mp_nuked_wager
//     image likely doesn't exist at all — but that has not been checked.
//   - mp_golfcourse / mp_area51 / mp_drivein (Annihilation): their PACK-MATE mp_silo is
//     whitelisted and demonstrably resident, so residency is per-MAP, not per-pack — these
//     three may be free zoomed-minimap wins. One-time test per map: load it under gf, run
//     the bridge's compass apply (or add the name here on a dev build) and LOOK — resident
//     art renders, unloaded art shows a BLANK compass (that visible blank is the failure
//     mode this whitelist exists to prevent, and the eye is the only probe; nothing in the
//     GSC VM can query zone residency).
gf_getWagerCompassMaterial( mapname )
{
    if ( mapname == "mp_array"       || mapname == "mp_cairo"       ||
         mapname == "mp_cosmodrome"   || mapname == "mp_cracked"     ||
         mapname == "mp_crisis"       || mapname == "mp_duga"        ||
         mapname == "mp_hanoi"        || mapname == "mp_havoc"       ||
         mapname == "mp_mountain"     || mapname == "mp_radiation"   ||
         mapname == "mp_russianbase"  || mapname == "mp_villa"       ||
         mapname == "mp_silo"         || mapname == "mp_berlinwall2" )
        return "compass_map_" + mapname + "_wager";

    return "";
}

gf_applyCosmodromeWagerZone()
{
    gf_spawnWagerCollision( "collision_geo_mc_8x560x190", (-393, 396.5, -72), (0, 270, 0) );
    gf_spawnWagerCollision( "collision_geo_mc_4x52x190", (-358, 676.5, -74), (0, 0, 0) );
    gf_spawnWagerCollision( "collision_geo_mc_4x156x190", (-328.5, 758, -74), (0, 270, 0) );
}

gf_spawnWagerCollision( model, origin, angles )
{
    spawncollision( model, "collider", origin, angles );
}
