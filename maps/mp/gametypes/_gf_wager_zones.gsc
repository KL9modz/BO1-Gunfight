// Gunfight wager-zone support.
//
// The important blockers are baked into the map entity lump with
// script_gameobjectname values for the stock wager gametypes.  Gunfight keeps
// them by adding gun/oic/hlnd/shrp to the _gameobjects allow-list in gf.gsc.
// This file only handles the remaining wager-zone helpers.

gf_shouldUseWagerZones()
{
    if ( getDvar( "scr_gf_wagerzones" ) == "" )
        setDvar( "scr_gf_wagerzones", "1" );

    return getDvarInt( "scr_gf_wagerzones" ) == 1;
}

gf_precacheWagerZoneAssets()
{
    if ( !gf_shouldUseWagerZones() )
        return;

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
    if ( !gf_shouldUseWagerZones() )
        return;

    wagerSpawns = getEntArray( "mp_wager_spawn", "classname" );
    if ( wagerSpawns.size <= 0 )
        return;

    mapname = getDvar( "mapname" );

    gf_setupWagerZoneCompass( mapname );

    if ( mapname == "mp_cosmodrome" )
        gf_applyCosmodromeWagerZone();
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
