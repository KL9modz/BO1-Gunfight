// Gunfight Debug Tools
//
// SPAWN RECORDER  --  set gf_debug_spawns 1 before loading the map.
//   [1] ActionSlot1  record current position for active team
//   [2] ActionSlot2  toggle active team (allies/axis)
//   [3] ActionSlot3  print recorded spawns to console
//   [4] ActionSlot4  clear recorded spawns
//
// ENTITY FINDER  --  set gf_debug_ents 1 before loading the map.
//   set gf_do_dump 1  — nearby scan (default 200 units; set gf_dump_radius N to change)
//   set gf_do_dump 2  — full census: every classname + all entities that have a model
//   Both print to ~ console.  Census is the easiest way to find unknown entity types.

// ─── Spawn Recorder ────────────────────────────────────────────────────────

gf_startSpawnRecorder()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    self.gf_rec_allies = [];
    self.gf_rec_axis   = [];
    self.gf_rec_team   = "allies";

    self gf_recUpdateHUD();
    iPrintLnBold( "^2Spawn Recorder ON^7  [1]=record  [2]=toggle  [3]=print  [4]=clear" );

    while ( true )
    {
        wait 0.1;

        if ( self ActionSlotOneButtonPressed() )
        {
            org = self.origin;
            yaw = int( self.angles[1] );

            entry = [];
            entry["origin"] = org;
            entry["yaw"]    = yaw;

            if ( self.gf_rec_team == "allies" )
            {
                idx = self.gf_rec_allies.size;
                self.gf_rec_allies[ idx ] = entry;
                iPrintLnBold( "^4Allies #" + idx + "^7  (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + ")  yaw:" + yaw );
            }
            else
            {
                idx = self.gf_rec_axis.size;
                self.gf_rec_axis[ idx ] = entry;
                iPrintLnBold( "^1Axis #" + idx + "^7  (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + ")  yaw:" + yaw );
            }

            self gf_recUpdateHUD();
            wait 0.3;
        }

        if ( self ActionSlotTwoButtonPressed() )
        {
            if ( self.gf_rec_team == "allies" )
                self.gf_rec_team = "axis";
            else
                self.gf_rec_team = "allies";

            self gf_recUpdateHUD();
            iPrintLnBold( "Now recording: ^3" + self.gf_rec_team );
            wait 0.3;
        }

        if ( self ActionSlotThreeButtonPressed() )
        {
            self gf_recPrint();
            wait 0.3;
        }

        if ( self ActionSlotFourButtonPressed() )
        {
            self.gf_rec_allies = [];
            self.gf_rec_axis   = [];
            self gf_recUpdateHUD();
            iPrintLnBold( "^1Spawns cleared" );
            wait 0.3;
        }
    }
}

gf_recUpdateHUD()
{
    if ( !isDefined( self.gf_rec_hudElem ) )
    {
        self.gf_rec_hudElem             = newClientHudElem( self );
        self.gf_rec_hudElem.horzAlign   = "left";
        self.gf_rec_hudElem.vertAlign   = "top";
        self.gf_rec_hudElem.alignX      = "left";
        self.gf_rec_hudElem.alignY      = "top";
        self.gf_rec_hudElem.x           = 10;
        self.gf_rec_hudElem.y           = 300;
        self.gf_rec_hudElem.font        = "smallfixed";
        self.gf_rec_hudElem.fontScale   = 1.0;
        self.gf_rec_hudElem.foreground  = true;
        self.gf_rec_hudElem.hidewheninmenu = false;
    }

    if ( self.gf_rec_team == "allies" )
        self.gf_rec_hudElem.color = ( 0.4, 0.7, 1.0 );
    else
        self.gf_rec_hudElem.color = ( 1.0, 0.45, 0.45 );

    self.gf_rec_hudElem setText( "REC[" + self.gf_rec_team + "]  A:" + self.gf_rec_allies.size + "  X:" + self.gf_rec_axis.size );
}

gf_recPrint()
{
    map = getDvar( "mapname" );
    PrintLn( "" );
    PrintLn( "// === " + map + " - " + self.gf_rec_allies.size + " allies, " + self.gf_rec_axis.size + " axis ===" );
    PrintLn( "    if ( mapname == \"" + map + "\" )" );
    PrintLn( "    {" );
    PrintLn( "        a = result[\"allies\"];" );

    for ( i = 0; i < self.gf_rec_allies.size; i++ )
    {
        e   = self.gf_rec_allies[i];
        org = e["origin"];
        PrintLn( "        a[ a.size ] = gf_sp( (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + "), " + e["yaw"] + " );" );
    }

    PrintLn( "        x = result[\"axis\"];" );

    for ( i = 0; i < self.gf_rec_axis.size; i++ )
    {
        e   = self.gf_rec_axis[i];
        org = e["origin"];
        PrintLn( "        x[ x.size ] = gf_sp( (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + "), " + e["yaw"] + " );" );
    }

    PrintLn( "        return result;" );
    PrintLn( "    }" );
    PrintLn( "" );
    iPrintLnBold( "^2Spawns printed to console" );
}

// ─── Entity Finder ─────────────────────────────────────────────────────────

gf_startEntityDumper()
{
    if ( isDefined( level.gf_entityDumperRunning ) && level.gf_entityDumperRunning )
        return;
    level.gf_entityDumperRunning = true;

    level endon( "game_ended" );

    iPrintLnBold( "^3Dump ready^7  2=classnames  3=full" );

    while ( true )
    {
        wait 0.5;

        mode = getDvarInt( "gf_do_dump" );
        if ( mode == 1 )
        {
            setDvar( "gf_do_dump", 0 );
            self gf_findNearbyEnts();
        }
        else if ( mode == 2 )
        {
            setDvar( "gf_do_dump", 0 );
            self gf_censusClassnames();
        }
        else if ( mode == 3 )
        {
            setDvar( "gf_do_dump", 0 );
            gf_censusEnts();
        }
    }
}

// Nearby scan — walk to an area of interest, then set gf_do_dump 1.
// Radius controlled by gf_dump_radius dvar (default 200).
gf_findNearbyEnts()
{
    origin = self.origin;
    ents   = getEntArray();
    found  = 0;
    radius = 200;
    if ( getDvar( "gf_dump_radius" ) != "" )
        radius = getDvarInt( "gf_dump_radius" );

    iPrintLnBold( "^2Scanning " + ents.size + " entities within " + radius + " units..." );

    for ( i = 0; i < ents.size; i++ )
    {
        e = ents[i];
        if ( !isDefined( e.origin ) ) continue;

        dist = distance( origin, e.origin );
        if ( dist > radius ) continue;

        cn = "?";
        tn = "";
        md = "";
        if ( isDefined( e.classname  ) ) cn = e.classname;
        if ( isDefined( e.targetname ) ) tn = e.targetname;
        if ( isDefined( e.model      ) ) md = e.model;

        org  = e.origin;
        line = "NEAR|" + int( dist ) + "|" + cn + "|" + tn + "|" + md
             + "|(" + int(org[0]) + "," + int(org[1]) + "," + int(org[2]) + ")";

        iPrintLn( "^3" + line );
        PrintLn( line );
        found++;
    }

    if ( found == 0 )
        iPrintLnBold( "^1Nothing within " + radius + " units - try: set gf_dump_radius 1000" );
    else
        iPrintLnBold( "^2Found " + found + " nearby entities" );
}

// Classname-only summary — small output, fits in ~ console.  set gf_do_dump 2
gf_censusClassnames()
{
    ents = getEntArray();
    map  = getDvar( "mapname" );

    counts = [];
    for ( i = 0; i < ents.size; i++ )
    {
        e  = ents[i];
        cn = "?";
        if ( isDefined( e.classname ) ) cn = e.classname;
        if ( !isDefined( counts[cn] ) ) counts[cn] = 0;
        counts[cn]++;
    }

    iPrintLn( "^2=== " + map + " ents=" + ents.size + " ===" );
    keys = getArrayKeys( counts );
    for ( i = 0; i < keys.size; i++ )
        iPrintLn( "^3CLS " + keys[i] + " ^7x" + counts[ keys[i] ] );

    self iPrintLnBold( "^2Done — scroll ~ up for CLS list" );
}

// Full census — dumps every entity grouped by classname, then all modelled entities.
// set gf_do_dump 2  to trigger.
// Output written to entity_dump.log in the T5 storage dir; also printed to server console.
gf_censusEnts()
{
    ents = getEntArray();
    map  = getDvar( "mapname" );

    fh = -1;
    /# fh = openFile( "entity_dump.log", "write" ); #/

    gf_cOut( fh, "" );
    gf_cOut( fh, "=== CENSUS " + map + " total=" + ents.size + " ===" );

    counts = [];
    for ( i = 0; i < ents.size; i++ )
    {
        e  = ents[i];
        cn = "?";
        if ( isDefined( e.classname ) ) cn = e.classname;
        if ( !isDefined( counts[cn] ) ) counts[cn] = 0;
        counts[cn]++;
    }

    keys = getArrayKeys( counts );
    for ( i = 0; i < keys.size; i++ )
        gf_cOut( fh, "CLS|" + keys[i] + "|" + counts[ keys[i] ] );

    // script_brushmodel entities have no .model field — print them separately
    gf_cOut( fh, "--- script_brushmodel ---" );
    brushes = getEntArray( "script_brushmodel", "classname" );
    for ( i = 0; i < brushes.size; i++ )
    {
        e  = brushes[i];
        tn = "";
        if ( isDefined( e.targetname ) ) tn = e.targetname;
        org = "?";
        if ( isDefined( e.origin ) )
            org = "(" + int(e.origin[0]) + "," + int(e.origin[1]) + "," + int(e.origin[2]) + ")";
        ang = "?";
        if ( isDefined( e.angles ) )
            ang = "(" + int(e.angles[0]) + "," + int(e.angles[1]) + "," + int(e.angles[2]) + ")";
        gf_cOut( fh, "SBM|" + i + "|" + tn + "|origin=" + org + "|angles=" + ang );
    }

    gf_cOut( fh, "--- models ---" );
    for ( i = 0; i < ents.size; i++ )
    {
        e  = ents[i];
        if ( !isDefined( e.model ) ) continue;
        if ( e.model == "" ) continue;

        cn = "?";
        tn = "";
        if ( isDefined( e.classname  ) ) cn = e.classname;
        if ( isDefined( e.targetname ) ) tn = e.targetname;

        org = "?";
        if ( isDefined( e.origin ) )
            org = "(" + int(e.origin[0]) + "," + int(e.origin[1]) + "," + int(e.origin[2]) + ")";

        gf_cOut( fh, "MDL|" + cn + "|" + tn + "|" + e.model + "|" + org );
    }

    gf_cOut( fh, "=== END CENSUS ===" );

    fileWritten = false;
    /# if ( fh != -1 ) { closeFile( fh ); fileWritten = true; } #/

    if ( isDefined( self.sessionstate ) )
    {
        if ( fileWritten )
            self iPrintLnBold( "^2Census → entity_dump.log" );
        else
            self iPrintLnBold( "^2Census → server console (add 'set developer 1' for file)" );
    }
}

// Write to games_mp.log (logString), server console (PrintLn), and file if open.
gf_cOut( fh, line )
{
    PrintLn( line );
    logString( line );
    /# if ( fh != -1 ) fprintln( fh, line ); #/
}
