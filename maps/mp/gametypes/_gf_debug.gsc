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

// gf_debugPrintPerks() lived here. DELETED (2026-07-13) — it was dead code (no caller), and it had
// gone stale in the worst way: it probed a hardcoded 18-token list that still contained the FAKE
// "specialty_blindeye" and was missing 10 of the perks the mod actually grants today, so it would
// have reported the wrong answer with total confidence. Replaced by the bridge's READ-ONLY
// `pperkdump_<num>` (gf_bridgeDumpPerks, _gf_bridge.gsc), which probes the FULL engine specialty
// table and can be aimed at any player from the RCON panel.
// ⚠ NOT `pperks_<num>` — that is the WRITE (it GRANTS a fixed extra perk set). Don't reach for it
// when you meant to inspect.

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
    // ⚠ NO endon("game_ended") — that notify fires at EVERY ROUND END, not at match end
    // (gf_endRound threads _globallogic::endGame, which runs yield-free to it). Carrying it
    // meant this sampler DIED the instant a round ended and did not come back until the next
    // onStartGameType — so every GF_HITCH statistic we have has a hole across exactly the
    // killcam -> roundEndWait -> map_restart window, which is where clients report the
    // "Connection Interrupted" plug. The ~700ms "phase=prematch" hitches are what the sampler
    // saw AFTER it woke back up; they are not a measurement of the restart itself.
    // gf_hitch_reinit (fired from onStartGameType) is what collapses this to one live copy.
    // The one sample in flight when that notify lands is lost; gf_roundEndProbe covers the
    // same window at 20 Hz, so nothing is left unmeasured. Same trap as gf_boundaryListener
    // (_bot.gsc) and gf_postRoundWatchdog (_gf_rounds.gsc) — do not "restore" this endon.
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
// "killcam" splits the round-end window in two, which is the whole point of the probe
// below: a stall BEFORE the final killcam (phase=roundend) is our own endRound work, a
// stall INSIDE it (phase=killcam) is the bot-fill connect / demo / VM, and the hole after
// it (phase=restart) is the engine's map_restart. level.inFinalKillcam is stock
// (_killcam.gsc: set true in play_final_killcam, false when the last viewer exits).
gf_hitchPhase()
{
    if ( isDefined( level.inOvertime ) && level.inOvertime )              return "overtime";
    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )  return "prematch";
    if ( isDefined( level.inFinalKillcam ) && level.inFinalKillcam )      return "killcam";
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

// ─── Round-end timeline probe (the "Connection Interrupted" investigation) ───
// Clients report the engine's CG_DrawDisconnect plug on the round-ending killcam, and
// until now NOTHING measured that window (see the endon note in gf_hitchMonitor above).
// Threaded from gf_endRound, this samples at 20 Hz through the entire stock end sequence
//   endGame -> displayRoundEnd -> executePostRoundEvents -> finalKillcamWaiter -> map_restart
// and logs every window where the server went dark for >= gf_endgap_ms. Threads survive
// map_restart, so the sample that SPANS the restart is measured too: the gap is logged
// BEFORE the generation check retires the thread, which is the one measurement the current
// tooling structurally cannot take.
//
// Reading the output (logs\games_mp.log), by phase:
//   GF_ENDGAP ... phase=roundend  -> stall before the killcam = our own endRound work
//   GF_ENDGAP ... phase=killcam   -> stall inside it          = bot-fill connect / demo / VM
//   GF_ENDGAP ... phase=restart   -> the engine's map_restart(true) hole itself
//   GF_ENDMARK ...                -> a named suspect event, to time-align against the gaps
//   GF_ENDTL ...                  -> one summary line per round end
//
// ⚠ The DECISIVE read is a NEGATIVE one. If a client draws the plug during a window where
// no GF_ENDGAP was logged, the server never stalled — so the cause is NOT a server hole,
// and the remaining candidates are bandwidth (sv_maxRate) or the engine's own client-side
// check misfiring on killcam playback (where the replayed snapshots carry a rewound
// serverTime and the local player stops being simulated). That fork is what this exists to
// settle; do not conclude "map_restart" from a plug alone, which is what we did before.
//
// Tunable (dvar, no rebuild): set gf_endgap_ms N  -> gap threshold in ms (default 150,
// i.e. ~3 dark server frames at sv_fps 20, where a healthy tick is ~50ms).
gf_roundEndProbe( myGen )
{
    // NO endon("game_ended") — it fires within a frame of us being threaded (gf_endRound
    // threads endGame right after us). NO endon("gf_round_over") either: that is the notify
    // that OPENS this window. The generation check below is the only correct retirement.
    t0    = gettime();
    prev  = t0;
    worst = 0;
    gaps  = 0;

    thresh = getDvarInt( "gf_endgap_ms" );
    if ( thresh <= 0 )
        thresh = 150;

    // ⚠ THERE IS NO IN-VM TIMESCALE PROBE, AND THERE CANNOT BE ONE. A previous version of this
    // thread edge-logged getDvarFloat("timescale") to catch stock's final-killcam SetTimeScale(0.25).
    // It was DELETED (2026-07-13) because it can never work, and its silence was actively
    // misleading — it read a steady 1 straight through a round end that an external wall-clock
    // sampler measured at 0.27x. Two independent reasons it is impossible:
    //
    //   1. SetTimeScale does not mirror into a readable dvar. (No stock GSC reads one either — that
    //      should have been the tell.)
    //   2. Even if it did: a dilation compresses game time against WALL time without ever creating a
    //      game-clock gap, and gettime(), wait() and the log timestamps are ALL on the game clock.
    //      A `wait 0.05` still advances gettime() by a healthy 50ms while burning 200ms of wall
    //      clock. So GF_ENDGAP/GF_HITCH are structurally blind to it too: their zeros were never
    //      evidence the killcam was clean, they are what a dilation LOOKS like from inside the sim.
    //
    // The only clock the dilation cannot touch is one outside the VM. Use RCON: tools/ts_sample.ps1
    // diffs the gf_endprobe_last heartbeat below against a wall-clock stopwatch, and d(game)/d(wall)
    // IS the timescale. That is how the killcam floor (scr_gf_killcam_slowmo) was measured and sized.

    // HEARTBEAT INTO A DVAR — the map_restart hole, and the wall-clock sampler's only input.
    // Proven live on the VPS 2026-07-13: this thread logs its in-window lines fine, but its
    // RETIREMENT line never appears — neither from the gen check nor from the 60s ceiling.
    // A thread parked in a timed wait() does NOT come back from map_restart(true) (a thread
    // parked in a waittill does — gf_boundaryListener survives every round, which is why the
    // codebase believed "threads survive both restarts" without qualification). So the thread
    // simply dies somewhere inside the restart, and it cannot report the very gap it exists to
    // measure. Dvars are the ONLY thing that survives, so stamp the heartbeat into one: the
    // last beat before the VM went dark, compared against gettime() on the far side by
    // gf_reportRoundEndGap() (called from onStartGameType), IS the dark window.
    // ⚠ gf_postRoundWatchdog leans on the same assumption (wait 1 + gen check). That is
    // harmless there — dying at the restart is exactly when it SHOULD retire, and the hang it
    // guards is the case where no restart happens at all — but do not "fix" it by copying this.
    setDvar( "gf_endprobe_t0",   "" + t0 );
    setDvar( "gf_endprobe_last", "" + t0 );

    // Unconditional, so the log distinguishes "armed and then died" from "never armed at all".
    // Both of this thread's other outputs are conditional, which is why the first VPS run could
    // not tell those two apart.
    logPrint( "GF_ENDARM: round-end probe armed  gen=" + myGen + " gt=" + t0 + "\n" );

    for ( ;; )
    {
        wait 0.05;

        now  = gettime();
        gap  = now - prev;
        prev = now;

        setDvar( "gf_endprobe_last", "" + now );

        // Log BEFORE the gen check: map_restart is exactly what changes the generation, so
        // checking first would discard the restart-spanning gap — the most interesting one.
        if ( gap >= thresh )
        {
            gaps++;
            if ( gap > worst )
                worst = gap;

            logPrint( "GF_ENDGAP: " + gap + "ms dark  phase=" + gf_hitchPhase()
                      + " t+" + ( now - t0 ) + "ms"
                      + " humans=" + gf_hitchHumans() + " bots=" + gf_hitchBots()
                      + " gt=" + now + "\n" );
        }

        // Gen check inlined rather than calling _gf_rounds::gf_roundGenChanged — this file
        // carries NO #include (and _gf_rounds already includes IT, so an include here would
        // be a cycle). Same predicate: onStartGameType re-stamps gf_roundGen after the
        // restart, and level.* is wiped, so an undefined gen also means "the restart landed".
        if ( !isDefined( level.gf_roundGen ) || level.gf_roundGen != myGen )
        {
            logPrint( "GF_ENDTL: thread SURVIVED the restart - round end took " + ( now - t0 ) + "ms  gaps=" + gaps
                      + " worst=" + worst + "ms"
                      + " humans=" + gf_hitchHumans() + " bots=" + gf_hitchBots() + "\n" );
            return;
        }

        // gf_postRoundWatchdog owns the deadlock case (orphaned .killcam / .doingNotify) and
        // breaks it at 20s. Don't keep sampling behind it forever.
        if ( now - t0 > 60000 )
        {
            logPrint( "GF_ENDTL: probe gave up after " + ( now - t0 )
                      + "ms - the round end never reached map_restart  gaps=" + gaps
                      + " worst=" + worst + "ms\n" );
            return;
        }
    }
}

// The far side of the hole. Called from onStartGameType — i.e. the first mod code to run AFTER
// map_restart — it reads the heartbeat gf_roundEndProbe stamped into a dvar on the near side.
//
//   dark = now - last heartbeat  ->  the wall-clock window in which the server ran NO script at
//                                    all: the tail of the round end + the whole map_restart.
//                                    THIS is the number the "Connection Interrupted" theory has
//                                    always assumed and never measured.
//   roundEndTotal                ->  gf_endRound -> next round init, end to end.
//
// If dark is small (a few frames) yet clients still draw the plug on the killcam, the server
// never went silent and the cause is NOT snapshot starvation from map_restart — which is the
// assumption the whole current memory rests on.
// (humans/bots read 0 here: level.players is still empty this early in onStartGameType. That is
// expected — the counts on the GF_ENDGAP lines are the populated ones.)
gf_reportRoundEndGap()
{
    if ( getDvar( "gf_endprobe_last" ) == "" )
        return;

    now  = gettime();
    dark = now - getDvarInt( "gf_endprobe_last" );
    tot  = now - getDvarInt( "gf_endprobe_t0" );

    // ⚠ A "did the killcam leak a timescale into this round?" check lived here, reading the
    // `timescale` dvar. DELETED — the dvar does not track SetTimeScale, so it could only ever have
    // reported the value it already assumed (see the note in gf_roundEndProbe). gf_resetTimeScale()
    // in gf.gsc still closes the leak itself; it is unconditional and costs nothing, so a detector
    // for it buys nothing anyway. If the leak is ever suspected again, measure it from OUTSIDE the
    // sim with tools/ts_sample.ps1 — a round that STARTS dilated shows up as a game/wall ratio
    // below 1.0 before the first killcam.
    logPrint( "GF_ENDTL: dark=" + dark + "ms (no script ran)  roundEndTotal=" + tot
              + "ms  gt=" + now + "\n" );

    setDvar( "gf_endprobe_last", "" );
    setDvar( "gf_endprobe_t0",   "" );
}

// Time-align a suspect event against the GF_ENDGAP lines: same log, same clock. Cheap enough
// to call from anything that fires inside the round-end window.
gf_endProbeMark( label )
{
    logPrint( "GF_ENDMARK: " + label + "  phase=" + gf_hitchPhase()
              + " humans=" + gf_hitchHumans() + " bots=" + gf_hitchBots()
              + " gt=" + gettime() + "\n" );
}

// ─── Spawn-yaw probe ───────────────────────────────────────────────────────
//
// "Rare wrong-facing spawn": the location is right, the yaw is not. The curated table and the
// selection path are both deterministic (one hardcoded yaw per point, round-robin cursor), so the
// question is not WHICH yaw we chose — it is whether the engine kept the one we handed it.
//
// Two samples answer that, and they distinguish the two hypotheses on their own:
//   t0 (one frame after spawn) — the client cannot have turned meaningfully yet, so a large delta
//      here means the engine never applied our angles. Immune to player input by construction.
//   t1 (+1s) — a delta that is ~0 at t0 and LARGE at t1 means the server applied the yaw but the
//      client's view came from somewhere else (stale deltaangles / the round-end killcam camera)
//      and the client then told the server where it was really looking.
//
// Bots are skipped (the AI drives its own angles every frame; every sample would be noise).
// set gf_debug_spawnyaw 1. Grep the log for GF_SPAWNYAW.
gf_yawDelta( a, b )
{
    d = a - b;
    while ( d > 180 )
        d -= 360;
    while ( d <= -180 )
        d += 360;
    return d;
}

gf_probeSpawnYaw( intendedYaw, source )
{
    self endon( "disconnect" );

    if ( getDvarInt( "gf_debug_spawnyaw" ) <= 0 )
        return;

    if ( self istestclient() )
        return;

    org = self.origin;

    wait 0.05;
    d0 = gf_yawDelta( intendedYaw, self getPlayerAngles()[1] );

    wait 1.0;
    d1 = gf_yawDelta( intendedYaw, self getPlayerAngles()[1] );

    // Log every spawn, not just the bad ones: the baseline is what proves a flagged line is real.
    // A rare bug needs the boring lines around it to be trustworthy.
    flag = "";
    if ( abs( d0 ) > 60 )
        flag = "  ENGINE_DROPPED_ANGLES";
    else if ( abs( d1 ) > 60 )
        flag = "  CLIENT_VIEW_OVERRODE";

    // Concatenating an undefined into a string is a runtime error, so resolve the flag first.
    prematch = 0;
    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
        prematch = 1;

    logPrint( "GF_SPAWNYAW: " + self.name + " src=" + source
              + " intended=" + int( intendedYaw )
              + " d0=" + int( d0 ) + " d1=" + int( d1 )
              + " prematch=" + prematch
              + " org=" + int( org[0] ) + "," + int( org[1] ) + "," + int( org[2] )
              + flag + "\n" );
}
