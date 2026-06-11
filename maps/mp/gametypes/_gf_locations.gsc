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

    if ( mapname == "mp_villa" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (4644, 3299, 198), -132 );
        a[ a.size ] = gf_sp( (4562, 3297, 193), -117 );
        a[ a.size ] = gf_sp( (4466, 3297, 192), -102 );
        a[ a.size ] = gf_sp( (4400, 3297, 192), -88 );
        a[ a.size ] = gf_sp( (4320, 3295, 192), -65 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (2890, -312, 296), 32 );
        x[ x.size ] = gf_sp( (2889, -202, 296), 34 );
        x[ x.size ] = gf_sp( (3006, -318, 296), 48 );
        x[ x.size ] = gf_sp( (3114, -318, 296), 61 );
        x[ x.size ] = gf_sp( (3210, -313, 296), 87 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_cosmodrome" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (436, 2075, -167), -116 );
        a[ a.size ] = gf_sp( (356, 2103, -167), -106 );
        a[ a.size ] = gf_sp( (247, 2118, -175), -103 );
        a[ a.size ] = gf_sp( (149, 2083, -174), -86 );
        a[ a.size ] = gf_sp( (516, 1930, -171), -134 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-68, -1399, -167), 65 );
        x[ x.size ] = gf_sp( (28, -1409, -169), 81 );
        x[ x.size ] = gf_sp( (129, -1409, -169), 87 );
        x[ x.size ] = gf_sp( (227, -1378, -167), 98 );
        x[ x.size ] = gf_sp( (378, -1358, -167), 111 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_cairo" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-615, -1438, 7), 58 );
        a[ a.size ] = gf_sp( (-502, -1439, 8), 61 );
        a[ a.size ] = gf_sp( (-416, -1437, 8), 79 );
        a[ a.size ] = gf_sp( (-595, -1346, 7), 42 );
        a[ a.size ] = gf_sp( (-457, -1336, 7), 1 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (1699, 1289, -28), -144 );
        x[ x.size ] = gf_sp( (1699, 1197, -29), -141 );
        x[ x.size ] = gf_sp( (1603, 1299, -26), -134 );
        x[ x.size ] = gf_sp( (1500, 1299, -25), -117 );
        x[ x.size ] = gf_sp( (1604, 1218, -27), -157 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_crisis" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-549, 2083, 65), -136 );
        a[ a.size ] = gf_sp( (-811, 2329, 64), -122 );
        a[ a.size ] = gf_sp( (-534, 1986, 65), -150 );
        a[ a.size ] = gf_sp( (-911, 2347, 64), -105 );
        a[ a.size ] = gf_sp( (-693, 2092, 64), -130 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-2924, -486, 16), -30 );
        x[ x.size ] = gf_sp( (-3093, -193, 22), 99 );
        x[ x.size ] = gf_sp( (-2999, -114, 15), -8 );
        x[ x.size ] = gf_sp( (-2927, -269, 15), 34 );
        x[ x.size ] = gf_sp( (-2817, -420, 29), 36 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_russianbase" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (1768, -1006, 12), 144 );
        a[ a.size ] = gf_sp( (1768, -880, 3), 146 );
        a[ a.size ] = gf_sp( (1626, -1006, 7), 126 );
        a[ a.size ] = gf_sp( (1484, -1021, 13), 83 );
        a[ a.size ] = gf_sp( (1643, -891, -4), 138 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-555, 1217, 25), -42 );
        x[ x.size ] = gf_sp( (-603, 1101, 21), -28 );
        x[ x.size ] = gf_sp( (-420, 1224, 25), -45 );
        x[ x.size ] = gf_sp( (-587, 892, 14), -19 );
        x[ x.size ] = gf_sp( (-462, 1021, 6), -32 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_duga" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-1788, -1343, 7), -63 );
        a[ a.size ] = gf_sp( (-1689, -1352, 7), -70 );
        a[ a.size ] = gf_sp( (-1940, -1349, 2), -60 );
        a[ a.size ] = gf_sp( (-1759, -1454, 0), -47 );
        a[ a.size ] = gf_sp( (-1977, -1599, 0), -34 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (1037, -3781, 8), 125 );
        x[ x.size ] = gf_sp( (838, -3794, -1), 61 );
        x[ x.size ] = gf_sp( (1049, -3676, 8), 136 );
        x[ x.size ] = gf_sp( (936, -3783, 3), 103 );
        x[ x.size ] = gf_sp( (932, -3625, 7), 173 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    return result;
}

gf_getCustomOvertimeLocation()
{
    mapname = getDvar( "mapname" );

    if ( mapname == "mp_villa" )
        return gf_ot( (4480, 1315, 288), 1 );

    if ( mapname == "mp_cosmodrome" )
        return gf_ot( (700, 386, -7), 0 );

    if ( mapname == "mp_cairo" )
        return gf_ot( (569, -42, -13), 174 );

    if ( mapname == "mp_crisis" )
        return gf_ot( (-1922, 349, -6), 54 );

    if ( mapname == "mp_russianbase" )
        return gf_ot( (405, -286, -23), -4 );

    if ( mapname == "mp_duga" )
        return gf_ot( (-779, -2575, 0), 90 );

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

        logPrint( "Gunfight custom spawn set ignored for " + getDvar( "mapname" ) + ": both allies and axis need at least one point.\n" );
    }

    level.gf_customSpawns["sets"] = validSets;

    if ( validSets.size > 0 )
    {
        logPrint( "Gunfight custom spawn sets loaded for " + getDvar( "mapname" ) + ": sets=" + validSets.size + " allies=" + totalAllies + " axis=" + totalAxis + "\n" );
        return;
    }

    alliesCount = gf_getCustomSpawnCount( "allies" );
    axisCount   = gf_getCustomSpawnCount( "axis" );

    if ( alliesCount > 0 || axisCount > 0 )
        logPrint( "Gunfight custom spawns ignored for " + getDvar( "mapname" ) + ": both allies and axis need at least one point.\n" );

    level.gf_customSpawns["allies"] = [];
    level.gf_customSpawns["axis"]   = [];
}

gf_validateCustomOvertimeLocation()
{
    if ( !isDefined( level.gf_customOvertimeLocation ) )
        return;

    if ( isDefined( level.gf_customOvertimeLocation["origin"] ) && isDefined( level.gf_customOvertimeLocation["angles"] ) )
    {
        logPrint( "Gunfight custom overtime flag loaded for " + getDvar( "mapname" ) + "\n" );
        return;
    }

    logPrint( "Gunfight custom overtime flag ignored for " + getDvar( "mapname" ) + ": missing origin or angles.\n" );
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
