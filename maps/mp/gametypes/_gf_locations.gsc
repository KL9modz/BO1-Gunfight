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

    if ( mapname == "mp_silo" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (2146, -218, -38), 135 );
        a[ a.size ] = gf_sp( (2355, -60, -39), 126 );
        a[ a.size ] = gf_sp( (2273, -187, -38), 135 );
        a[ a.size ] = gf_sp( (2448, 102, 8), 161 );
        a[ a.size ] = gf_sp( (2168, 18, -45), 154 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-1058, 1587, 178), 38 );
        x[ x.size ] = gf_sp( (-1022, 1974, 124), -1 );
        x[ x.size ] = gf_sp( (-972, 2160, 125), -25 );
        x[ x.size ] = gf_sp( (-1050, 1742, 158), 13 );
        x[ x.size ] = gf_sp( (-825, 2280, 129), -26 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_nuked" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-1641, 471, -63), -14 );
        a[ a.size ] = gf_sp( (-1542, 730, -63), -16 );
        a[ a.size ] = gf_sp( (-1740, 837, -63), -9 );
        a[ a.size ] = gf_sp( (-1827, 554, -66), -19 );
        a[ a.size ] = gf_sp( (-1752, 206, -63), 16 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (1663, 452, -63), -163 );
        x[ x.size ] = gf_sp( (1581, 727, -63), -162 );
        x[ x.size ] = gf_sp( (1808, 597, -63), -158 );
        x[ x.size ] = gf_sp( (1725, 801, -63), -159 );
        x[ x.size ] = gf_sp( (1885, 179, -63), 169 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_array" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (2094, 1436, 415), -108 );
        a[ a.size ] = gf_sp( (2323, 1315, 439), -130 );
        a[ a.size ] = gf_sp( (2156, 1284, 385), -127 );
        a[ a.size ] = gf_sp( (2052, 1238, 364), -127 );
        a[ a.size ] = gf_sp( (2330, 1023, 428), -130 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (332, -2749, 230), 85 );
        x[ x.size ] = gf_sp( (774, -2711, 241), 100 );
        x[ x.size ] = gf_sp( (570, -2757, 241), 92 );
        x[ x.size ] = gf_sp( (983, -2635, 256), 134 );
        x[ x.size ] = gf_sp( (235, -2586, 248), 69 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_mountain" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (2885, 1117, 320), -93 );
        a[ a.size ] = gf_sp( (3197, 1129, 320), -87 );
        a[ a.size ] = gf_sp( (3047, 1317, 320), -90 );
        a[ a.size ] = gf_sp( (3328, 1327, 320), -96 );
        a[ a.size ] = gf_sp( (2791, 1256, 324), -83 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (3295, -2981, 401), 107 );
        x[ x.size ] = gf_sp( (3050, -2946, 376), 94 );
        x[ x.size ] = gf_sp( (3157, -2712, 456), 98 );
        x[ x.size ] = gf_sp( (2966, -2681, 456), 100 );
        x[ x.size ] = gf_sp( (3470, -3048, 371), 126 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_radiation" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (1333, -772, 136), -157 );
        a[ a.size ] = gf_sp( (1342, -878, 136), 170 );
        a[ a.size ] = gf_sp( (1179, -1076, 128), 135 );
        a[ a.size ] = gf_sp( (1159, -871, 128), -177 );
        a[ a.size ] = gf_sp( (1071, -1080, 126), 120 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (1257, 1461, 128), -157 );
        x[ x.size ] = gf_sp( (1247, 1331, 133), 172 );
        x[ x.size ] = gf_sp( (1136, 1468, 128), -144 );
        x[ x.size ] = gf_sp( (939, 1468, 128), -101 );
        x[ x.size ] = gf_sp( (777, 1398, 128), -50 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_hanoi" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (1802, -237, -73), -116 );
        a[ a.size ] = gf_sp( (1646, -117, -78), -107 );
        a[ a.size ] = gf_sp( (1787, -129, -80), -130 );
        a[ a.size ] = gf_sp( (1849, -408, -60), -138 );
        a[ a.size ] = gf_sp( (1414, -135, -74), -63 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-540, -2848, -63), 39 );
        x[ x.size ] = gf_sp( (-663, -2688, -63), 35 );
        x[ x.size ] = gf_sp( (-667, -2817, -63), 43 );
        x[ x.size ] = gf_sp( (-664, -2564, -64), 29 );
        x[ x.size ] = gf_sp( (-357, -2850, -63), 51 );
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

    if ( mapname == "mp_silo" )
        return gf_ot( (543, 919, -25), -46 );

    if ( mapname == "mp_nuked" )
        return gf_ot( (23, 96, -67), -70 );

    if ( mapname == "mp_array" )
        return gf_ot( (985, -612, 318), 40 );

    if ( mapname == "mp_mountain" )
        return gf_ot( (2579, -746, 320), -34 );

    if ( mapname == "mp_radiation" )
        return gf_ot( (2, 25, 137), -48 );

    if ( mapname == "mp_hanoi" )
        return gf_ot( (332, -1040, -63), 45 );

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
