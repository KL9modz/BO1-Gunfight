// Gunfight custom map locations.
//
// Use gf_debug_spawns 1, stand on the desired points, then press ActionSlot3
// to print paste-ready spawn and overtime snippets to the console.

gf_initCustomLocations()
{
    level.gf_customSpawns           = gf_getCustomSpawnLocations();
    level.gf_customOvertimeLocation = gf_getCustomOvertimeLocation();
    level.gf_customSpawnRound       = -1;
    level.gf_customSpawnCursor      = [];

    gf_normalizeCustomSpawnLocations();
    gf_validateCustomLocations();
    gf_validateCustomOvertimeLocation();
}

gf_getCustomSpawnLocations()
{
    mapname = getDvar( "mapname" );

    result = [];
    result["sets"]   = [];
    result["allies"] = [];
    result["axis"]   = [];

    // Paste map blocks here. Example:
    //
    // if ( mapname == "mp_havoc" )
    // {
    //     set = gf_spawnSet();
    //     a = set["allies"];
    //     a[ a.size ] = gf_sp( ( 0, 0, 0 ), 90 );
    //
    //     x = set["axis"];
    //     x[ x.size ] = gf_sp( ( 128, 0, 0 ), 270 );
    //
    //     result["sets"][ result["sets"].size ] = set;
    //
    //     return result;
    // }

    return result;
}

gf_getCustomOvertimeLocation()
{
    mapname = getDvar( "mapname" );

    // Paste overtime blocks here. Example:
    //
    // if ( mapname == "mp_havoc" )
    //     return gf_ot( ( 64, 64, 0 ), 0 );

    return undefined;
}

gf_spawnSet()
{
    set = [];
    set["allies"] = [];
    set["axis"]   = [];
    return set;
}

gf_sp( origin, yaw )
{
    point = [];
    point["origin"] = origin;
    point["angles"] = ( 0, yaw, 0 );
    return point;
}

gf_ot( origin, yaw )
{
    point = [];
    point["origin"] = origin;
    point["angles"] = ( 0, yaw, 0 );
    point["radius"] = 96;
    point["height"] = 96;
    return point;
}

gf_getCustomSpawnPoint( team )
{
    if ( !isDefined( level.gf_customSpawns ) )
        return undefined;

    if ( !isDefined( level.gf_customSpawns["sets"] ) )
        return undefined;

    sets = level.gf_customSpawns["sets"];
    if ( sets.size <= 0 )
        return undefined;

    roundKey = 0;
    if ( isDefined( game["roundsplayed"] ) )
        roundKey = game["roundsplayed"];

    if ( !isDefined( level.gf_customSpawnRound ) || level.gf_customSpawnRound != roundKey )
    {
        level.gf_customSpawnRound = roundKey;
        level.gf_customSpawnCursor = [];
        level.gf_customSpawnCursor["allies"] = 0;
        level.gf_customSpawnCursor["axis"] = 0;
    }

    if ( !isDefined( level.gf_customSpawnCursor[team] ) )
        level.gf_customSpawnCursor[team] = 0;

    setIndex = roundKey % sets.size;
    set = sets[setIndex];

    if ( !isDefined( set[team] ) || set[team].size <= 0 )
        return undefined;

    spawns = set[team];
    index = level.gf_customSpawnCursor[team] % spawns.size;
    level.gf_customSpawnCursor[team]++;

    return spawns[index];
}

gf_normalizeCustomSpawnLocations()
{
    if ( !isDefined( level.gf_customSpawns ) )
    {
        level.gf_customSpawns = [];
        level.gf_customSpawns["sets"] = [];
        return;
    }

    if ( !isDefined( level.gf_customSpawns["sets"] ) )
        level.gf_customSpawns["sets"] = [];

    if ( level.gf_customSpawns["sets"].size > 0 )
        return;

    alliesCount = gf_getCustomSpawnCount( "allies" );
    axisCount   = gf_getCustomSpawnCount( "axis" );

    if ( alliesCount <= 0 || axisCount <= 0 )
        return;

    set = gf_spawnSet();
    set["allies"] = level.gf_customSpawns["allies"];
    set["axis"]   = level.gf_customSpawns["axis"];
    level.gf_customSpawns["sets"][0] = set;
}

gf_validateCustomLocations()
{
    if ( !isDefined( level.gf_customSpawns ) )
        return;

    if ( !isDefined( level.gf_customSpawns["sets"] ) )
        level.gf_customSpawns["sets"] = [];

    validSets = [];
    totalAllies = 0;
    totalAxis = 0;

    for ( i = 0; i < level.gf_customSpawns["sets"].size; i++ )
    {
        set = level.gf_customSpawns["sets"][i];
        alliesCount = gf_getCustomSpawnSetCount( set, "allies" );
        axisCount   = gf_getCustomSpawnSetCount( set, "axis" );

        if ( alliesCount > 0 && axisCount > 0 )
        {
            validSets[validSets.size] = set;
            totalAllies += alliesCount;
            totalAxis += axisCount;
            continue;
        }

        println( "Gunfight custom spawn set ignored for " + getDvar( "mapname" ) + ": both allies and axis need at least one point." );
    }

    level.gf_customSpawns["sets"] = validSets;

    if ( validSets.size > 0 )
    {
        println( "Gunfight custom spawn sets loaded for " + getDvar( "mapname" ) + ": sets=" + validSets.size + " allies=" + totalAllies + " axis=" + totalAxis );
        return;
    }

    alliesCount = gf_getCustomSpawnCount( "allies" );
    axisCount   = gf_getCustomSpawnCount( "axis" );

    if ( alliesCount > 0 || axisCount > 0 )
        println( "Gunfight custom spawns ignored for " + getDvar( "mapname" ) + ": both allies and axis need at least one point." );

    level.gf_customSpawns["allies"] = [];
    level.gf_customSpawns["axis"]   = [];
}

gf_validateCustomOvertimeLocation()
{
    if ( !isDefined( level.gf_customOvertimeLocation ) )
        return;

    if ( isDefined( level.gf_customOvertimeLocation["origin"] ) && isDefined( level.gf_customOvertimeLocation["angles"] ) )
    {
        println( "Gunfight custom overtime flag loaded for " + getDvar( "mapname" ) );
        return;
    }

    println( "Gunfight custom overtime flag ignored for " + getDvar( "mapname" ) + ": missing origin or angles." );
    level.gf_customOvertimeLocation = undefined;
}

gf_getCustomSpawnCount( team )
{
    if ( !isDefined( level.gf_customSpawns ) )
        return 0;

    if ( !isDefined( level.gf_customSpawns[team] ) )
        return 0;

    return level.gf_customSpawns[team].size;
}

gf_getCustomSpawnSetCount( set, team )
{
    if ( !isDefined( set ) )
        return 0;

    if ( !isDefined( set[team] ) )
        return 0;

    return set[team].size;
}
