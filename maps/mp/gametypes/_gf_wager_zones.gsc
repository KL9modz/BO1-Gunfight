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

    // Same gate as the map's double_doors_open_at_start / switch_lights, so we
    // share their timeline no matter what the prematch period is this round.
    if ( level.prematchPeriod > 0 && level.inPrematchPeriod == true )
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

gf_getWagerCompassMaterial( mapname )
{
    if ( mapname == "mp_array" )
        return "compass_map_mp_array_wager";
    if ( mapname == "mp_cairo" )
        return "compass_map_mp_cairo_wager";
    if ( mapname == "mp_cracked" )
        return "compass_map_mp_cracked_wager";
    if ( mapname == "mp_crisis" )
        return "compass_map_mp_crisis_wager";
    if ( mapname == "mp_cosmodrome" )
        return "compass_map_mp_cosmodrome_wager";
    if ( mapname == "mp_duga" )
        return "compass_map_mp_duga_wager";
    if ( mapname == "mp_hanoi" )
        return "compass_map_mp_hanoi_wager";
    if ( mapname == "mp_havoc" )
        return "compass_map_mp_havoc_wager";
    if ( mapname == "mp_mountain" )
        return "compass_map_mp_mountain_wager";
    if ( mapname == "mp_radiation" )
        return "compass_map_mp_radiation_wager";
    if ( mapname == "mp_russianbase" )
        return "compass_map_mp_russianbase_wager";
    if ( mapname == "mp_villa" )
        return "compass_map_mp_villa_wager";

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
