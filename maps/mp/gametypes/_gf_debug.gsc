// Gunfight Debug Tools
//
// SPAWN RECORDER  --  set gf_debug_spawns 1 before loading the map.
//   [1] ActionSlot1  record current position for active team
//   [2] ActionSlot2  toggle active team (allies/axis)
//   [3] ActionSlot3  save current set, then print all sets and current overtime flag
//   [4] ActionSlot4  undo last recorded point for the active team
//
//   An on-screen legend (these controls) + live state line stay up while active.
//
// COORDS HUD  --  auto-starts alongside the spawn recorder.
//   Shows live X/Y/Z and yaw in the bottom-left corner.
//
// HUD POOL OVERLAY  --  set gf_debug_hud_pool 1 before loading the map.
//   Shows live SV (server team elems) and CL (client elems this player) counts.
//   Note: SV counts elems created by gf_sv_create* helpers only.
//         Limits are approximate — T5 engine cap is not queryable at runtime.

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
    self.gf_rec_sets   = [];
    self.gf_rec_team   = "allies";

    self gf_recCreateLegend();
    self gf_recUpdateHUD();
    iPrintLnBold( "^2Spawn Recorder ON" );

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
                iPrintLnBold( "^4Allies #" + idx + " recorded" );
                logPrint( "  Allies #" + idx + "  (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + ")  yaw:" + yaw + "\n" );
            }
            else
            {
                idx = self.gf_rec_axis.size;
                self.gf_rec_axis[ idx ] = entry;
                iPrintLnBold( "^1Axis #" + idx + " recorded" );
                logPrint( "  Axis #" + idx + "  (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + ")  yaw:" + yaw + "\n" );
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
            self gf_recCommitCurrentSet();
            self gf_recPrint();
            wait 0.3;
        }

        if ( self ActionSlotFourButtonPressed() )
        {
            if ( self.gf_rec_team == "allies" )
            {
                if ( self.gf_rec_allies.size > 0 )
                {
                    removed = self.gf_rec_allies[ self.gf_rec_allies.size - 1 ];
                    newList = [];
                    for ( i = 0; i < self.gf_rec_allies.size - 1; i++ )
                        newList[i] = self.gf_rec_allies[i];
                    self.gf_rec_allies = newList;
                    org = removed["origin"];
                    iPrintLnBold( "^1Undo allies #" + self.gf_rec_allies.size );
                    logPrint( "  Undo allies #" + self.gf_rec_allies.size + "  (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + ")\n" );
                }
                else
                {
                    iPrintLnBold( "^7No allies points to undo" );
                }
            }
            else
            {
                if ( self.gf_rec_axis.size > 0 )
                {
                    removed = self.gf_rec_axis[ self.gf_rec_axis.size - 1 ];
                    newList = [];
                    for ( i = 0; i < self.gf_rec_axis.size - 1; i++ )
                        newList[i] = self.gf_rec_axis[i];
                    self.gf_rec_axis = newList;
                    org = removed["origin"];
                    iPrintLnBold( "^1Undo axis #" + self.gf_rec_axis.size );
                    logPrint( "  Undo axis #" + self.gf_rec_axis.size + "  (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + ")\n" );
                }
                else
                {
                    iPrintLnBold( "^7No axis points to undo" );
                }
            }
            self gf_recUpdateHUD();
            wait 0.3;
        }
    }
}

gf_recCreateLegend()
{
    if ( isDefined( self.gf_rec_legendElem ) )
        return;

    legend                = newClientHudElem( self );
    legend.horzAlign      = "left";
    legend.vertAlign      = "top";
    legend.alignX         = "left";
    legend.alignY         = "top";
    legend.x              = 10;
    legend.y              = 200;
    legend.font           = "smallfixed";
    legend.fontScale      = 1.0;
    legend.color          = ( 0.9, 0.9, 0.9 );
    legend.foreground     = true;
    legend.hidewheninmenu = false;
    // [{+actionslot N}] resolves to the player's actual bound key (not hardcoded 1-4).
    legend setText( "^3SPAWN RECORDER\n^3[{+actionslot 1}]^7 record point\n^3[{+actionslot 2}]^7 toggle team\n^3[{+actionslot 3}]^7 save + print\n^3[{+actionslot 4}]^7 undo last" );

    self.gf_rec_legendElem = legend;
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

    setCount = 0;
    if ( isDefined( self.gf_rec_sets ) )
        setCount = self.gf_rec_sets.size;

    self.gf_rec_hudElem setText( "REC[" + self.gf_rec_team + "]  S:" + setCount + "  A:" + self.gf_rec_allies.size + "  X:" + self.gf_rec_axis.size );
}

gf_recCommitCurrentSet()
{
    if ( !isDefined( self.gf_rec_sets ) )
        self.gf_rec_sets = [];

    if ( self.gf_rec_allies.size <= 0 && self.gf_rec_axis.size <= 0 )
        return;

    if ( self.gf_rec_allies.size <= 0 || self.gf_rec_axis.size <= 0 )
    {
        iPrintLnBold( "^1Set not saved:^7 needs allies and axis points" );
        return;
    }

    set = [];
    allies = [];
    axis   = [];

    for ( i = 0; i < self.gf_rec_allies.size; i++ )
        allies[allies.size] = self.gf_rec_allies[i];

    for ( i = 0; i < self.gf_rec_axis.size; i++ )
        axis[axis.size] = self.gf_rec_axis[i];

    set["allies"] = allies;
    set["axis"]   = axis;

    idx = self.gf_rec_sets.size;
    self.gf_rec_sets[idx] = set;
    self.gf_rec_allies = [];
    self.gf_rec_axis   = [];
    self gf_recUpdateHUD();

    iPrintLnBold( "^2Saved spawn set #" + idx );
}

gf_recPrint()
{
    map = getDvar( "mapname" );
    logPrint( "\n" );
    logPrint( "// === " + map + " - " + self.gf_rec_sets.size + " spawn sets ===\n" );
    logPrint( "    if ( mapname == \"" + map + "\" )\n" );
    logPrint( "    {\n" );

    for ( setIndex = 0; setIndex < self.gf_rec_sets.size; setIndex++ )
    {
        self gf_recPrintSet( self.gf_rec_sets[setIndex], setIndex );
    }

    logPrint( "        return result;\n" );
    logPrint( "    }\n" );
    logPrint( "\n" );

    org = self.origin;
    yaw = int( self.angles[1] );
    logPrint( "// === " + map + " overtime flag at current position ===\n" );
    logPrint( "    if ( mapname == \"" + map + "\" )\n" );
    logPrint( "        return gf_ot( (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + "), " + yaw + " );\n" );
    logPrint( "\n" );

    iPrintLnBold( "^2Spawn sets printed to log" );
}

gf_recPrintSet( set, setIndex )
{
    allies = set["allies"];
    axis   = set["axis"];

    logPrint( "        // set " + setIndex + "\n" );
    logPrint( "        set = gf_spawnSet();\n" );
    logPrint( "        a = set[\"allies\"];\n" );

    for ( i = 0; i < allies.size; i++ )
    {
        e   = allies[i];
        org = e["origin"];
        logPrint( "        a[ a.size ] = gf_sp( (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + "), " + e["yaw"] + " );\n" );
    }

    logPrint( "        set[\"allies\"] = a;\n" );
    logPrint( "        x = set[\"axis\"];\n" );

    for ( i = 0; i < axis.size; i++ )
    {
        e   = axis[i];
        org = e["origin"];
        logPrint( "        x[ x.size ] = gf_sp( (" + int( org[0] ) + ", " + int( org[1] ) + ", " + int( org[2] ) + "), " + e["yaw"] + " );\n" );
    }

    logPrint( "        set[\"axis\"] = x;\n" );
    logPrint( "        result[\"sets\"][ result[\"sets\"].size ] = set;\n" );
    logPrint( "\n" );
}

gf_startHUDPoolOverlay()
{
    // Singleton per player — kill the previous update loop but reuse the element.
    self notify( "gf_hud_pool_overlay_kill" );
    self endon( "disconnect" );
    self endon( "gf_hud_pool_overlay_kill" );

    if ( !isDefined( self.gf_hudPoolOverlayElem ) )
    {
        overlay = newClientHudElem( self );
        overlay.horzAlign      = "left";
        overlay.vertAlign      = "bottom";
        overlay.alignX         = "left";
        overlay.alignY         = "bottom";
        overlay.x              = 10;
        overlay.y              = -30;
        overlay.font           = "smallfixed";
        overlay.fontScale      = 1.0;
        overlay.color          = ( 0.5, 1.0, 0.7 );
        overlay.foreground     = true;
        overlay.hidewheninmenu = false;
        self.gf_hudPoolOverlayElem = overlay;
    }
    overlay = self.gf_hudPoolOverlayElem;

    svMax = 64;
    clMax = 17;   // empirical per-player DRAWN client-hudelem budget — past ~17-20 the engine
                  // silently stops rendering the overflow (a cap allocation probes can't see).

    while ( true )
    {
        svCount = 0;
        if ( isDefined( level.gf_sv_elem_count ) )
            svCount = level.gf_sv_elem_count;

        clCount = 0;
        if ( isDefined( self.gf_loadoutHudElems ) )
            clCount += self.gf_loadoutHudElems.size;
        if ( isDefined( self.gf_hudElems ) )
            clCount += self.gf_hudElems.size;

        aHP = "-"; aN = "-"; xHP = "-"; xN = "-";
        if ( isDefined( level.gf_dbg_alliesHP ) ) aHP = level.gf_dbg_alliesHP;
        if ( isDefined( level.gf_dbg_alliesN ) )  aN  = level.gf_dbg_alliesN;
        if ( isDefined( level.gf_dbg_axisHP ) )   xHP = level.gf_dbg_axisHP;
        if ( isDefined( level.gf_dbg_axisN ) )    xN  = level.gf_dbg_axisN;

        if ( clCount >= clMax )                       // red at/over the DRAWN budget (the real wall)
            overlay.color = ( 1, 0.3, 0.3 );
        else
            overlay.color = ( 0.5, 1.0, 0.7 );

        overlay setText( "SV: " + svCount + "/" + svMax + "  DRAWN: " + clCount + "/" + clMax + "   A " + aHP + "hp/" + aN + "p  X " + xHP + "hp/" + xN + "p" );
        wait 0.2;
    }
}

gf_debugPrintPerks()
{
    self endon( "disconnect" );
    wait 0.1;

    allPerks = [];
    allPerks[0]  = "specialty_movefaster";
    allPerks[1]  = "specialty_bulletpenetration";
    allPerks[2]  = "specialty_longersprint";
    allPerks[3]  = "specialty_fastreload";
    allPerks[4]  = "specialty_gpsjammer";
    allPerks[5]  = "specialty_quieter";
    allPerks[6]  = "specialty_armorvest";
    allPerks[7]  = "specialty_blindeye";
    allPerks[8]  = "specialty_detectexplosive";
    allPerks[9]  = "specialty_sprintrecovery";
    allPerks[10] = "specialty_holdbreath";
    allPerks[11] = "specialty_bulletaccuracy";
    allPerks[12] = "specialty_killstreak";
    allPerks[13] = "specialty_scavenger";
    allPerks[14] = "specialty_extraammo";
    allPerks[15] = "specialty_twoattach";
    allPerks[16] = "specialty_gas_mask";
    allPerks[17] = "specialty_pistoldeath";

    self iPrintLn( "^5-- perks --" );
    for ( i = 0; i < allPerks.size; i++ )
    {
        if ( self hasPerk( allPerks[i] ) )
            self iPrintLn( "^2+ " + allPerks[i] );
    }
}

// ─── Frame-hitch / game-time-dilation monitor ────────────────────────────────
// Chases the report: "the prematch/preround countdown + the WHOLE game run in
// slow-motion until the timer hits 0, then everything snaps back to normal."
//
// Working theory (see CLAUDE.md "prematch countdown in slow motion" + memory
// vps-prematch-slowmo-framehitch): a transient SERVER-FRAME hitch dilates game
// time. GSC `wait` and the entire simulation advance 1/sv_fps per EXECUTED server
// frame, so when the box can't finish its frames in real time, everything (player
// movement, animation, the wait(1.0)-driven stock prematch countdown) runs slow in
// wall-clock and then catches up. On the contended Contabo VPS the restart burst
// (map_restart + the per-player respawn/loadout/HUD work ± bot fill) is the load
// that occasionally can't be kept up with, which is why the stall lines up with,
// and clears at the end of, the countdown.
//
// This measures how much gettime() advances across a fixed `wait W`. It is built
// on ONLY gettime()+wait() — both guaranteed-valid builtins, so ZERO compile risk —
// and it is SELF-VALIDATING about the load-bearing assumption that gettime() is
// WALL-clock (as the notes claim) rather than game-time:
//   • gettime() WALL clock -> during a stall the delta EXCEEDS W*1000; the dilation
//     is measured directly (expected if the notes are right).
//   • gettime() GAME time  -> the delta stays ~W*1000 even during a KNOWN slow-mo
//     (both clocks dilate together). So if a live repro logs ~0% the whole time,
//     gettime is game-time and the reference must move to a real-time builtin
//     (getRealTime) — which we'd confirm is needed before risking that builtin.
//
// Output: GF_HITCH lines in logs\games_mp.log. Tunables (dvars, no rebuild):
//   set gf_hitch_debug 1  -> log EVERY sample (wall-vs-game validation + full
//                            per-window profile through a repro; set back to 0 after)
//   set gf_hitch_pct N    -> log threshold in percent-slower-than-real-time (default 25)
// Singleton across rounds/map_restart via the gf_hitch_reinit notify (gf.gsc);
// level scope, never touches a player.
gf_hitchMonitor()
{
    level endon( "game_ended" );
    level endon( "gf_hitch_reinit" );

    W        = 0.5;              // sample window (game-seconds, nominal)
    expected = W * 1000.0;       // real ms the window SHOULD take at full server speed

    for ( ;; )
    {
        t0 = gettime();
        wait W;
        real = gettime() - t0;   // real ms the window ACTUALLY took (if gettime is wall-clock)

        pct = getDvarInt( "gf_hitch_pct" );
        if ( pct <= 0 )
            pct = 25;

        slow = int( ( ( real - expected ) / expected ) * 100 );   // % slower than real-time

        if ( getDvarInt( "gf_hitch_debug" ) == 1 || slow >= pct )
        {
            logPrint( "GF_HITCH: " + real + "ms vs " + int( expected ) + "ms  (+" + slow
                      + "% slow)  phase=" + gf_hitchPhase()
                      + " humans=" + gf_hitchHumans() + " bots=" + gf_hitchBots()
                      + " gt=" + gettime() + "\n" );
        }
    }
}

// Coarse round-phase label so we can see WHAT a stall coincides with. Overtime is a
// sub-state of a live round, so it is checked first; "restart" catches the
// pre-prematch gate hold and the map_restart transition gap (neither of the flags set).
gf_hitchPhase()
{
    if ( isDefined( level.inOvertime ) && level.inOvertime )              return "overtime";
    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )  return "prematch";
    if ( isDefined( level.gf_roundActive ) && level.gf_roundActive )      return "live";
    if ( isDefined( level.gf_roundEnding ) && level.gf_roundEnding )      return "roundend";
    return "restart";
}

gf_hitchHumans()
{
    if ( !isDefined( level.players ) )
        return 0;
    n = 0;
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( isDefined( p ) && !( p istestclient() ) )
            n++;
    }
    return n;
}

gf_hitchBots()
{
    if ( !isDefined( level.players ) )
        return 0;
    n = 0;
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( isDefined( p ) && p istestclient() )
            n++;
    }
    return n;
}
