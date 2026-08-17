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

gf_disableRadiationDoors()
{
    level endon( "game_ended" );

    waittillframeend;
    while ( !isDefined( level._door_switch_trig1 ) || !isDefined( level._door_switch_trig2 ) )
        wait 0.05;

    level._door_switch_trig1 common_scripts\utility::trigger_off();
    level._door_switch_trig2 common_scripts\utility::trigger_off();

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
