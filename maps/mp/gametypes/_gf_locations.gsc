// Gunfight custom map locations.
//
// Use gf_debug_spawns 1, stand on the desired points, then press ActionSlot3
// to print paste-ready spawn and overtime snippets to the console.

gf_initCustomLocations()
{
    // The curated per-map spawn sets and OT flag spot are MAP-CONSTANT, but onStartGameType
    // re-runs on every map_restart (SD round cycling), so this used to rebuild + re-normalize +
    // re-validate them every round - redundant work landing on the exact frame the between-rounds
    // snapshot gap ("Connection Interrupted") appears. Build once, cache in game[] (survives
    // map_restart, resets on a real new-map load - same idiom as game["gf_init"] / game["gf_botInit"]),
    // then just restore the reference on later rounds. Safe against GSC array aliasing: nothing
    // mutates level.gf_customSpawns during a round (gf_getCustomSpawnPoint only advances the separate
    // level.gf_customSpawnCursor), so the game[]/level[] shared reference is read-only in play.
    if ( !isDefined( game["gf_customLocCached"] ) )
    {
        level.gf_customSpawns           = gf_getCustomSpawnLocations();
        level.gf_customOvertimeLocation = gf_getCustomOvertimeLocation();

        gf_normalizeCustomSpawnLocations();
        gf_validateCustomLocations();
        gf_validateCustomOvertimeLocation();

        game["gf_customLocCached"]     = true;
        game["gf_customSpawnsCache"]   = level.gf_customSpawns;
        game["gf_customOvertimeCache"] = level.gf_customOvertimeLocation;   // may be undefined (map has no curated OT); restore preserves that
    }
    else
    {
        level.gf_customSpawns           = game["gf_customSpawnsCache"];
        level.gf_customOvertimeLocation = game["gf_customOvertimeCache"];
    }

    // Per-round runtime state - always reset fresh (cheap; the round-robin cursor must restart).
    level.gf_customSpawnRound  = -1;
    level.gf_customSpawnCursor = [];
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
        a[ a.size ] = gf_sp( (82, 1913, -172), -91 );
        a[ a.size ] = gf_sp( (299, 1912, -177), -92 );
        a[ a.size ] = gf_sp( (163, 2000, -175), -90 );
        a[ a.size ] = gf_sp( (133, 1847, -175), -91 );
        a[ a.size ] = gf_sp( (154, 2098, -175), -90 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-36, -1185, -169), 86 );
        x[ x.size ] = gf_sp( (218, -1203, -167), 91 );
        x[ x.size ] = gf_sp( (120, -1248, -169), 91 );
        x[ x.size ] = gf_sp( (2, -1346, -170), 88 );
        x[ x.size ] = gf_sp( (142, -1359, -167), 90 );
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

    if ( mapname == "mp_cracked" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-569, 1374, -199), -50 );
        a[ a.size ] = gf_sp( (-741, 1252, -192), -49 );
        a[ a.size ] = gf_sp( (-720, 1369, -191), -58 );
        a[ a.size ] = gf_sp( (-734, 1130, -192), -51 );
        a[ a.size ] = gf_sp( (-939, 1018, -198), -27 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (1694, -1174, -127), -166 );
        x[ x.size ] = gf_sp( (1688, -1483, -127), 150 );
        x[ x.size ] = gf_sp( (1703, -1357, -127), 170 );
        x[ x.size ] = gf_sp( (1593, -1429, -127), 175 );
        x[ x.size ] = gf_sp( (1575, -1255, -127), -179 );
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

    if ( mapname == "mp_havoc" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (1997, -1651, 221), 37 );
        a[ a.size ] = gf_sp( (2122, -1718, 236), 62 );
        a[ a.size ] = gf_sp( (1966, -1561, 236), 16 );
        a[ a.size ] = gf_sp( (2238, -1679, 263), 45 );
        a[ a.size ] = gf_sp( (2155, -1484, 243), 1 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (1266, 1189, 112), -64 );
        x[ x.size ] = gf_sp( (1405, 1252, 98), -44 );
        x[ x.size ] = gf_sp( (1531, 1279, 88), -50 );
        x[ x.size ] = gf_sp( (1698, 1551, 96), -59 );
        x[ x.size ] = gf_sp( (1675, 1364, 93), -53 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_golfcourse" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-620, -1921, -12), 112 );
        a[ a.size ] = gf_sp( (-758, -2018, 30), 113 );
        a[ a.size ] = gf_sp( (-639, -2064, 17), 113 );
        a[ a.size ] = gf_sp( (-662, -1808, -20), 61 );
        a[ a.size ] = gf_sp( (-813, -1876, 33), 146 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-1809, 1776, -194), -40 );
        x[ x.size ] = gf_sp( (-2033, 1733, -187), -46 );
        x[ x.size ] = gf_sp( (-2054, 1629, -179), -44 );
        x[ x.size ] = gf_sp( (-1906, 1675, -181), -29 );
        x[ x.size ] = gf_sp( (-1671, 1752, -187), -51 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_area51" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (1128, 373, 0), -145 );
        a[ a.size ] = gf_sp( (1144, 248, 0), 168 );
        a[ a.size ] = gf_sp( (1063, 302, 0), -156 );
        a[ a.size ] = gf_sp( (941, 373, 0), -146 );
        a[ a.size ] = gf_sp( (976, 223, 0), -133 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-648, -2970, 0), 80 );
        x[ x.size ] = gf_sp( (-354, -2975, 0), 99 );
        x[ x.size ] = gf_sp( (-490, -2983, 0), 92 );
        x[ x.size ] = gf_sp( (-588, -2896, 0), 89 );
        x[ x.size ] = gf_sp( (-407, -2886, 0), 95 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_drivein" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-812, -1678, 83), 74 );
        a[ a.size ] = gf_sp( (-1091, -1644, 78), 57 );
        a[ a.size ] = gf_sp( (-998, -1703, 82), 73 );
        a[ a.size ] = gf_sp( (-1110, -1541, 76), 42 );
        a[ a.size ] = gf_sp( (-917, -1626, 79), 62 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (499, 2069, -2), -113 );
        x[ x.size ] = gf_sp( (190, 2121, 2), -94 );
        x[ x.size ] = gf_sp( (325, 2125, -3), -102 );
        x[ x.size ] = gf_sp( (404, 2037, 0), -106 );
        x[ x.size ] = gf_sp( (269, 2041, 0), -99 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_zoo" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-1158, 2271, -87), -73 );
        a[ a.size ] = gf_sp( (-939, 2297, -87), -94 );
        a[ a.size ] = gf_sp( (-1070, 2325, -87), -71 );
        a[ a.size ] = gf_sp( (-1090, 2198, -87), -73 );
        a[ a.size ] = gf_sp( (-983, 2213, -87), -81 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-1060, -1025, -143), 90 );
        x[ x.size ] = gf_sp( (-1167, -1048, -142), 95 );
        x[ x.size ] = gf_sp( (-1288, -1050, -142), 87 );
        x[ x.size ] = gf_sp( (-855, -922, -119), 94 );
        x[ x.size ] = gf_sp( (-994, -914, -143), 90 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_outskirts" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-1017, 1539, 0), -64 );
        a[ a.size ] = gf_sp( (-802, 1539, -7), -94 );
        a[ a.size ] = gf_sp( (-914, 1558, -7), -85 );
        a[ a.size ] = gf_sp( (-987, 1457, 0), -88 );
        a[ a.size ] = gf_sp( (-871, 1434, -5), -88 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (2448, 249, 157), 147 );
        x[ x.size ] = gf_sp( (2320, 109, 144), 146 );
        x[ x.size ] = gf_sp( (2389, 187, 151), 151 );
        x[ x.size ] = gf_sp( (2369, 327, 161), 157 );
        x[ x.size ] = gf_sp( (2252, 215, 154), 164 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_hotel" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (1758, -503, -31), 7 );
        a[ a.size ] = gf_sp( (1761, -398, -31), 4 );
        a[ a.size ] = gf_sp( (1760, -262, -31), 0 );
        a[ a.size ] = gf_sp( (1754, -97, -31), -1 );
        a[ a.size ] = gf_sp( (1746, 22, -31), -1 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (4158, -846, -31), 178 );
        x[ x.size ] = gf_sp( (4157, -680, -31), 174 );
        x[ x.size ] = gf_sp( (4151, -522, -31), -178 );
        x[ x.size ] = gf_sp( (4076, -597, -31), 178 );
        x[ x.size ] = gf_sp( (4058, -759, -31), -177 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_gridlock" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-2515, 179, -7), -14 );
        a[ a.size ] = gf_sp( (-2496, 299, -7), -16 );
        a[ a.size ] = gf_sp( (-2467, 430, -7), -9 );
        a[ a.size ] = gf_sp( (-2384, 585, -7), -9 );
        a[ a.size ] = gf_sp( (-2534, -57, -9), 6 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (809, 1140, -109), -175 );
        x[ x.size ] = gf_sp( (807, 1299, -124), -171 );
        x[ x.size ] = gf_sp( (852, 1434, -120), -167 );
        x[ x.size ] = gf_sp( (846, 1587, -119), -167 );
        x[ x.size ] = gf_sp( (755, 1447, -124), -169 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_stadium" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (128, -187, 4), 38 );
        a[ a.size ] = gf_sp( (-8, -29, 0), 37 );
        a[ a.size ] = gf_sp( (-35, -173, 5), 45 );
        a[ a.size ] = gf_sp( (-24, 259, -4), -5 );
        a[ a.size ] = gf_sp( (222, -199, 0), 62 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (2064, 1718, 0), -141 );
        x[ x.size ] = gf_sp( (1940, 1853, 0), -136 );
        x[ x.size ] = gf_sp( (2025, 1847, 0), -145 );
        x[ x.size ] = gf_sp( (1693, 2015, 0), -138 );
        x[ x.size ] = gf_sp( (1839, 1852, 0), -133 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_kowloon" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-407, 1873, -79), 1 );
        a[ a.size ] = gf_sp( (-408, 1673, -79), 5 );
        a[ a.size ] = gf_sp( (-399, 1543, -79), 3 );
        a[ a.size ] = gf_sp( (-394, 2071, -79), -26 );
        a[ a.size ] = gf_sp( (-227, 2088, -79), -64 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (2709, 1730, -167), -178 );
        x[ x.size ] = gf_sp( (2715, 1922, -167), -179 );
        x[ x.size ] = gf_sp( (2732, 2178, -167), -175 );
        x[ x.size ] = gf_sp( (2704, 1531, -167), 179 );
        x[ x.size ] = gf_sp( (2605, 2325, -167), -145 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_discovery" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (375, -109, 76), -138 );
        a[ a.size ] = gf_sp( (105, -31, 69), -149 );
        a[ a.size ] = gf_sp( (194, -109, 79), -135 );
        a[ a.size ] = gf_sp( (528, -207, 69), -166 );
        a[ a.size ] = gf_sp( (349, -374, 55), -128 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (-2178, -1940, 132), 35 );
        x[ x.size ] = gf_sp( (-2115, -2041, 143), 38 );
        x[ x.size ] = gf_sp( (-2217, -1999, 144), 15 );
        x[ x.size ] = gf_sp( (-2035, -2072, 139), 53 );
        x[ x.size ] = gf_sp( (-2261, -1765, 145), 46 );
        set["axis"] = x;
        result["sets"][ result["sets"].size ] = set;

        return result;
    }

    if ( mapname == "mp_berlinwall2" )
    {
        // set 0
        set = gf_spawnSet();
        a = set["allies"];
        a[ a.size ] = gf_sp( (-420, -1645, 6), 6 );
        a[ a.size ] = gf_sp( (-382, -1484, 6), 3 );
        a[ a.size ] = gf_sp( (-443, -1589, 4), 8 );
        a[ a.size ] = gf_sp( (-343, -1527, 6), 3 );
        a[ a.size ] = gf_sp( (-293, -1804, 14), -33 );
        set["allies"] = a;
        x = set["axis"];
        x[ x.size ] = gf_sp( (2494, -1234, 105), -168 );
        x[ x.size ] = gf_sp( (2520, -1418, 101), -164 );
        x[ x.size ] = gf_sp( (2509, -1328, 103), -166 );
        x[ x.size ] = gf_sp( (2472, -1132, 106), -159 );
        x[ x.size ] = gf_sp( (2437, -992, 106), -145 );
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

    if ( mapname == "mp_cracked" )
        return gf_ot( (370, -187, -127), 174 );

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

    if ( mapname == "mp_havoc" )
        return gf_ot( (1740, -351, 80), -41 );

    if ( mapname == "mp_golfcourse" )
        return gf_ot( (-1295, -199, -317), -34 );

    if ( mapname == "mp_area51" )
        return gf_ot( (-416, -801, 12), 124 );

    if ( mapname == "mp_drivein" )
        return gf_ot( (-107, 227, 22), -116 );

    if ( mapname == "mp_zoo" )
        return gf_ot( (-1162, 731, -143), 90 );

    if ( mapname == "mp_outskirts" )
        return gf_ot( (280, 845, 107), 115 );

    if ( mapname == "mp_hotel" )
        return gf_ot( (2939, -687, -87), -177 );

    if ( mapname == "mp_gridlock" )
        return gf_ot( (-625, 1093, -5), 87 );

    if ( mapname == "mp_stadium" )
        return gf_ot( (1127, 938, 32), -87 );

    if ( mapname == "mp_kowloon" )
        return gf_ot( (932, 1513, 8), 171 );

    if ( mapname == "mp_discovery" )
        return gf_ot( (-710, -1070, 31), 49 );

    if ( mapname == "mp_berlinwall2" )
        return gf_ot( (759, -1781, 59), 4 );

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
    start = level.gf_customSpawnCursor[team];
    level.gf_customSpawnCursor[team]++;

    // Spawning onto an occupied point kills the occupant in this engine, which is why
    // stock _spawnlogic runs positionWouldTelefrag() in every selection path. The bare
    // round-robin cursor could wrap onto point 0 during round-start churn (overflow
    // spawns diverted to spectator, team-move respawns) — where the round's first
    // spawner is still standing frozen in prematch — and telefrag them. Scan forward
    // for the first free point.
    for ( offset = 0; offset < spawns.size; offset++ )
    {
        candidate = spawns[ ( start + offset ) % spawns.size ];
        if ( !positionWouldTelefrag( candidate["origin"] ) )
            return candidate;
    }

    // Every curated point is occupied — possible now that a small-mode side can hold up to 6
    // players on 5 curated points (team size 5-6 / a 4v4-human + late-seat round). Returning
    // undefined sends the caller (gf.gsc onSpawnPlayer) down its stock mp_tdm_spawn_<team>_start
    // fallback, whose selectors are telefrag-aware — never spawn ONTO an occupied curated point,
    // which would kill the frozen occupant (the old raw-cursor fallback did exactly that).
    return undefined;
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
