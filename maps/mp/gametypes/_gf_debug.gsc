// Gunfight Debug Tools
//
// SPAWN RECORDER  --  set gf_debug_spawns 1 before loading the map.
//   [1] ActionSlot1  record current position for active team
//   [2] ActionSlot2  toggle active team (allies/axis)
//   [3] ActionSlot3  print recorded spawns to console
//   [4] ActionSlot4  clear recorded spawns
//
// COORDS HUD  --  auto-starts alongside the spawn recorder.
//   Shows live X/Y/Z and yaw in the bottom-left corner.

gf_startCoordsHUD()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    elem = newClientHudElem( self );
    elem.horzAlign    = "left";
    elem.vertAlign    = "bottom";
    elem.alignX       = "left";
    elem.alignY       = "bottom";
    elem.x            = 10;
    elem.y            = -10;
    elem.font         = "smallfixed";
    elem.fontScale    = 1.0;
    elem.color        = ( 0.9, 0.9, 0.6 );
    elem.foreground   = true;
    elem.hidewheninmenu = false;

    while ( true )
    {
        org = self.origin;
        yaw = int( self.angles[1] );
        elem setText( int( org[0] ) + "  " + int( org[1] ) + "  " + int( org[2] ) + "  yaw:" + yaw );
        wait 0.1;
    }
}

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
