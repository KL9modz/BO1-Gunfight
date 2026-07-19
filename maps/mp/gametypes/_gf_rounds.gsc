// Gunfight v3 — Round Management
// _globallogic::endGame handles scoring, win-limit, intermission, and respawn.

#include maps\mp\gametypes\_gf_hud;
// #strip-begin - _gf_debug include (dev/main only; stripped from public release)
#include maps\mp\gametypes\_gf_debug;
// #strip-end
#include maps\mp\gametypes\_hud_util;

gf_registerOvertimeLimitDvar()
{
    level.gf_overtimeLimitDvar = "scr_" + level.gameType + "_overtimelimit";
    gf_getOvertimeLimit();
}

gf_getOvertimeLimit()
{
    if ( !isDefined( level.gf_overtimeLimitDvar ) )
        level.gf_overtimeLimitDvar = "scr_" + level.gameType + "_overtimelimit";

    // Each mode reads its own dvar so both are independently tunable (cfg/RCON)
    // and the small-mode value is never clobbered when the mode flips.
    if ( isDefined( level.gf_largeMode ) && level.gf_largeMode )
        value = gf_cfgFloat( level.gf_overtimeLimitDvar + "_large", 30, 0, 120 );
    else
        value = gf_cfgFloat( level.gf_overtimeLimitDvar, 15, 0, 120 );

    level.gf_cfg_overtimeLimit = value;
    return value;
}

// OT zone capture time (seconds), per mode. Reads gf_capture_time /
// gf_capture_time_large so both are tunable; defaults preserve prior behavior.
gf_getCaptureTime()
{
    if ( isDefined( level.gf_largeMode ) && level.gf_largeMode )
        return gf_cfgFloat( "gf_capture_time_large", 5, 0.5, 60 );
    return gf_cfgFloat( "gf_capture_time", 3.5, 0.5, 60 );
}

// Reads a float dvar, registering the default if unset and clamping to [lo,hi].
// Mirrors the register*Dvar pattern (default-if-empty, clamp, persist).
gf_cfgFloat( dvar, def, lo, hi )
{
    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, def );

    v = GetDvarFloat( dvar );
    clamped = maps\mp\gametypes\_globallogic_utils::getValueInRange( v, lo, hi );
    if ( clamped != v )
        setDvar( dvar, clamped );   // persist the clamped value back, as before
    return clamped;
}

// Flinch (damage view-kick) scale. scr_gf_flinch is a MULTIPLIER of the stock
// bg_viewKickScale (0.2): 1 = stock flinch, 0 = no flinch, >1 = more. Called each
// round from onStartGameType (so an RCON change persists across map_restart) and
// live from the RCON bridge (flinch_<mult>). Returns the clamped multiplier.
//
// Gunfight ships 0.5 = HALF stock flinch, and this dvar is the ONLY flinch reducer:
// it is a straight multiplier on bg_viewKickScale, so 1.0 really is stock kick and
// 0 really is none. Nothing else touches flinch — do not add a second reducer.
//
// ⚠ specialty_bulletflinch (Hardened Pro) IS a second reducer, which is why it is no
// longer in the base perk set. It gates the engine's perk_damageKickReduction, whose
// registered default 0.2 is the fraction of kick REMAINING (an 80% cut), so the two
// MULTIPLY: the live VPS ran 0.2 x 0.5 x 0.2 = 10% of stock and flinch felt like zero,
// and at this dvar's clamp ceiling of 3 stock flinch was not even reachable. The perk
// now rides only in the sniper/heavy package, where the extra 0.2x is a deliberate
// class trait ([[hardened-pro-flinch-perk-multiplier]]).
//
// ⚠ bg_viewKickScale does NOT replicate. Each client scales its OWN damage view
// kick from its LOCAL copy, so the server-side setDvar alone changes nothing for
// anyone — verified on the dedicated VPS: server read 0, every client still 0.2,
// players still flinching. (It only ever appeared to work on a listen host, where
// the host IS a client.) So the value is also pushed to each human: live players
// here, and per-spawn in gf_onSpawnPlayer for anyone who joins later. The server
// copy is still set so server-side reads stay truthful.
//
// The push is session-only (bg_viewKickScale is not a SAVED client dvar — it isn't
// in config_mp.cfg — so unlike r_gamma it can be written and never sticks in the
// player's config). Reset-to-stock must push too: a live client is still holding
// whatever we last gave it, so it needs an explicit 0.2 to be put back.
gf_applyFlinch()
{
    scale = gf_cfgFloat( "scr_gf_flinch", 0.5, 0, 3 ); // seeds the dvar if unset
    setDvar( "bg_viewKickScale", 0.2 * scale );        // 0.2 = stock bg_viewKickScale

    // level.players is EMPTY during onStartGameType, so this loop is a no-op on the
    // per-round call — the per-spawn push below is what covers the round-start case.
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( isDefined( p.pers["isBot"] ) && p.pers["isBot"] )
            continue;                                  // bots have no client to push to
        p setClientDvar( "bg_viewKickScale", 0.2 * scale );
    }
    return scale;
}

// Per-spawn half of the flinch push (see gf_applyFlinch). ALWAYS pushes — there is
// deliberately no skip-at-stock shortcut.
// ⚠ Never re-add a skip-at-stock shortcut. The old code returned early when scale == 1,
// on the logic that a fresh client already sits at the engine default 0.2 so the push is
// redundant. It is not: bg_viewKickScale is a plain client dvar a player can set in their
// own autoexec, so anyone running `bg_viewKickScale 0` would take ZERO flinch while
// everyone else took the full kick. A shipped default of 0.5 makes such a skip look
// harmless (we would push anyway) — which is exactly how it survived last time — and a
// future default of 1.0 would silently turn the push off entirely. Pushing unconditionally
// is what makes the server's value authoritative, which is the property this dvar is
// documented to have ([[flinch-bg-viewkickscale-not-replicated]]).
// ⚠ This default must stay in lockstep with the one in gf_applyFlinch above —
// gf_cfgFloat seeds only if the dvar is empty, so a drift here would be silently
// masked by whichever function ran first.
gf_applyFlinchClient()
{
    scale = gf_cfgFloat( "scr_gf_flinch", 0.5, 0, 3 );
    self setClientDvar( "bg_viewKickScale", 0.2 * scale );
}

// "Jump fatigue" is the community name for the engine's post-jump slowdown: jump_slowdownEnable
// (stock 1) drags a player's movement speed after every jump, so consecutive hops decay. Gunfight
// ships it OFF (scr_gf_jump_fatigue default 0) — the rounds are 42s on wager-sized maps and the
// stock drag punishes exactly the short repositioning hops this mode is built on. 1 restores stock.
//
// The mod owns the dvar (rather than leaving jump_slowdownEnable to dedicated.cfg) so that OFF is a
// shipped default: the public build has no cfg of ours and no RCON panel, and a server owner who
// never touches a dvar still gets the intended movement. Stock does the same write for old-school
// mode (_globallogic.gsc: setDvar( "jump_slowdownEnable", 0 )).
//
// ⚠ jump_slowdownEnable IS flagged cheat-protected, but that does NOT stop a plain rcon/cfg `set` on
// a dedicated server — cheat protection is a CLIENT-side check (proven live 2026-07-12; see the
// svset block in _gf_bridge.gsc). So this setDvar is the tidy way to own the default, not a
// workaround for a gate that does not exist on the server side.
//
// No per-client push (unlike gf_applyFlinch): the jump_* family is replicated to clients by the
// engine — it has to be, movement is client-predicted. See
// [[flinch-bg-viewkickscale-not-replicated]] for the opposite case.
gf_applyJumpFatigue()
{
    on = int( gf_cfgFloat( "scr_gf_jump_fatigue", 0, 0, 1 ) );  // seeds the dvar if unset
    setDvar( "jump_slowdownEnable", on );
    return on;
}

// Unlimited sprint (the sprint meter never runs out). scr_gf_sprint_unlimited: 0 = stock
// (the GF default — Marathon is already in the base perk set), 1 = sprint never times out.
//
// ⚠ player_sprintUnlimited is a CLIENT dvar — the player_* family is client-predicted movement,
// the same ownership class as bg_viewKickScale (see gf_applyFlinch above), NOT the replicated
// jump_* family. The server copy is still set, for two reasons: the server's own movement sim
// reads it (a client predicting unlimited sprint against a server that limits it rubber-bands),
// and stock _globallogic_player::Callback_PlayerConnect reads it to decide its own push.
//
// ⚠ Which is exactly why this has to be owned. That stock connect push is the ONLY place in the
// whole game a client ever receives this dvar, and it is one-way:
//     if ( GetDvarInt( #"player_sprintUnlimited" ) ) self setClientDvar( "player_sprintUnlimited", 1 );
// It fires only at connect (it re-runs on map_restart, so it is per-round in practice) and it
// NEVER pushes 0. So stock can turn unlimited sprint on and can never turn it back off: a client
// that was handed a 1 keeps it for the rest of its session no matter what the server dvar says.
// Off is only reachable if WE push it.
gf_applySprintUnlimited()
{
    on = int( gf_cfgFloat( "scr_gf_sprint_unlimited", 0, 0, 1 ) );  // seeds the dvar if unset
    setDvar( "player_sprintUnlimited", on );

    // level.players is EMPTY during onStartGameType, so this loop is a no-op on the per-round
    // call — the per-spawn push below is what covers the round-start case. It matters for the
    // live RCON change (gf_bridgeSprintUnlimited), where the humans are already spawned in.
    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( isDefined( p.pers["isBot"] ) && p.pers["isBot"] )
            continue;                                   // bots have no client to push to
        p setClientDvar( "player_sprintUnlimited", on );
    }
    return on;
}

// Per-spawn half of the sprint push (see gf_applySprintUnlimited). Unlike gf_applyFlinchClient
// this has NO skip-at-stock shortcut, and the difference is load-bearing: a client only reaches
// a non-stock 1 because we (or stock's connect push) put it there, and nothing else in the game
// ever pushes it back down. Skipping the push at 0 would strand any client that had been given a
// 1 earlier in the session at unlimited sprint forever. So push both directions, every spawn —
// the value is what makes it deterministic, not the fact that it changed.
gf_applySprintUnlimitedClient()
{
    self setClientDvar( "player_sprintUnlimited", int( gf_cfgFloat( "scr_gf_sprint_unlimited", 0, 0, 1 ) ) );
}

// ─── Final-killcam slow motion — the mid-killcam "Connection Interrupted" flash ──────────────
// Stock BO1's FINAL killcam drops the WHOLE SERVER to quarter speed for the money shot.
// raw/maps/mp/gametypes/_killcam.gsc:244-258 (waitFinalKillcamSlowdown), threaded per player from
// finalKillcam() at :503 — the ROUND-END killcam only; the ordinary per-death killcam never
// threads it, which is why nobody ever sees this on a normal death:
//     wait( max( 0, secondsUntilDeath - 2 ) );      // park until 2s BEFORE the killing blow
//     SetTimeScale( 0.25, int( deathTime - 500 ) ); // <- server-wide 4x dilation, MID-replay
//     wait( waitBeforeDeath + 1 );
//     SetTimeScale( 1.0, getTime() + 500 );         // <- restore
//
// WHY THIS IS OURS TO OWN: while the server runs at 0.25x it retires each client's usercmds four
// times slower than the client produces them. The engine's "Connection Interrupted" indicator
// (CG_DrawDisconnect, material net_disconnect) is NOT an "am I receiving data" test — in this
// engine lineage it fires when the server has stopped ACKING YOUR COMMANDS. It has, deliberately.
// So the plug flashes mid-replay on a perfectly healthy connection: a FALSE POSITIVE of the
// engine's own check, caused by a time dilation stock asked for. Confirmed live 2026-07-13 — the
// flash coincides exactly with the visible slow-motion.
//
// It is not unique to us (sd.gsc:382 starts the same final killcam every round) — but our rounds
// are 42s, so what is a once-a-match curiosity in TDM lands every ~45s here. That is the whole
// difference between "a quirk nobody mentions" and "our server has a netcode bug".
//
// WHY 0.25 IS THE BUG, MEASURED (2026-07-13, VPS, RCON wall-clock sampler — the only instrument
// that can see this; every probe inside the VM runs on the scaled game clock and is structurally
// blind to a dilation):
//
//   The server retires a client's usercmds only when it runs a GAME FRAME, and
//       game frames per real second = sv_fps × timescale
//   The game-time quantum is 1000/sv_fps and the dilation does NOT shrink it — it spreads those
//   quanta apart in WALL time. Measured at sv_fps 20: gettime() advances in exact 50ms steps, and
//   during the killcam those steps arrive ~185ms apart instead of 50ms (0.27x, for 8-10 REAL
//   seconds, every single round).
//
//   A client generates one usercmd per client frame (com_maxfps) and they drain only that fast, so
//   the queue depth is  com_maxfps × frame-gap.  The client's outbound packet holds at most
//   MAX_PACKET_USERCMDS = 32; past that it truncates and prints MAX_PACKET_USERCMDS to the console
//   (observed on every client, exactly during the slow-mo). The same backlog is what makes the
//   engine draw its "Connection Interrupted" plug — CG_DrawDisconnect fires when the server stops
//   ACKING your commands, not when data stops arriving. Both symptoms, one cause.
//
//       stock 0.25 -> 200ms gap -> overruns above ~160 fps  (i.e. essentially every real client)
//       0.6        ->  83ms gap -> overruns above ~385 fps  (i.e. nobody)
//
// ⚠ sv_fps IS NOT THE LEVER, even though it is the other term. Raising it shrinks the gap, but the
// killcam rewinds through an archived snapshot ring sized in FRAMES, not seconds — so 4x sv_fps
// buys a quarter as much killcam history and the replay gets truncated or skipped outright. Tried
// live at sv_fps 80: the killcam ended early, stock's slowdown never reached its SetTimeScale at
// all, and the sampler saw no dilation. It "fixes" the plug by breaking the feature. Leave sv_fps
// at 20 ([[vps-prematch-slowmo-framehitch]] says the same thing for a different reason).
//
// So the ONLY lever is the timescale itself, and the fix is to make the slow motion SHALLOWER, not
// shorter — shortening it does nothing, because the backlog builds within ~300ms of the drop.
//
// scr_gf_killcam_slowmo is therefore the killcam TIMESCALE FLOOR, not a toggle:
//   0.25 = stock BO1 (the cinematic as shipped — and the plug, on any client above ~160 fps)
//   0.6  = DEFAULT — still a clear slow-motion money shot, no command backlog on any real client
//   1.0  = no slow motion at all (the old "off")
// SHIPPED AND CONFIRMED LIVE (2026-07-13): the plug is GONE and a full lobby plays great. Sampler
// across 4 round-ends: the timescale floors at 0.62 (never below), server game-frame gap ~80ms.
//
// 🛑 MAX_PACKET_USERCMDS STILL PRINTS ON CLIENTS, AND THAT IS NOT A REGRESSION. Do NOT "fix" it by
// dropping this floor below 0.6 or raising sv_fps — both trade a cosmetic console line for a real
// bug (the plug returns / the killcam archive truncates), and the live server is currently CORRECT.
// An earlier comment here called "zero MAX_PACKET_USERCMDS" the acceptance test for this fix. That
// was WRONG: it conflated two different client limits.
//   MAX_PACKET_USERCMDS (32) = the PER-PACKET cap. Overflowing it truncates the move packet, dropping
//     the OLDEST queued commands — the server still gets the newest and keeps acking, so it costs a
//     few ms of stale input nobody can feel. Cosmetic.
//   CG_DrawDisconnect        = a SEPARATE, much looser backlog threshold. THAT is the plug, and that
//     is what this floor cleared.
// Why 32 is still exceeded at an ~80ms gap is genuinely unknown (our model says it would take a
// >400 fps client). Suspect the count is commands since the last SENT PACKET (cl_maxpackets), not
// since the last ack — which would make it mostly client-side. Probe it from a CLIENT
// (cl_maxpackets 100 / com_maxfps 125), never by changing the server. See CLAUDE.md → Open bugs.
gf_killcamFloor()
{
    return gf_cfgFloat( "scr_gf_killcam_slowmo", 0.6, 0.25, 1 );   // seeds the dvar if unset
}

// The final killcam's replay length, mirroring _killcam.gsc::calcKillcamTime() for the FINAL cam
// (which always passes respawn=false and no maxtime). An explicit scr_killcam_time wins; otherwise
// stock's 5.0s. Its other branches are unreachable here: artillery/airstrike/napalm need
// killstreaks (this mod has none) and the grenade branch is gated behind respawn==true.
gf_killcamCamTime()
{
    if ( getDvar( "scr_killcam_time" ) != "" )
        return getDvarFloat( "scr_killcam_time" );

    return 5.0;
}

// Re-assert the floor across stock's dilation window. Stock threads waitFinalKillcamSlowdown()
// per viewer and we cannot unthread it — but SetTimeScale is a plain builtin and the LAST caller
// wins, so we simply overwrite its 0.25 with ours. Do NOT "fix" this by shipping a mod
// _killcam.gsc: overriding a stock script means keeping its ENTIRE public surface or the server
// won't compile.
//
// Stock's schedule, anchored on the play_final_killcam notify (t0):
//     t0 + 0.05                 finalKillcam() finishes its own wait and threads the slowdown
//     t0 + 0.05 + (camtime-2)   SetTimeScale( 0.25, deathTime - 500 )   <- ramps, arg2 is a TIME
//     deathTime + 1000          SetTimeScale( 1.0, getTime() + 500 )    <- restores
// We start one frame BEFORE its drop so our ramp is the one already in flight, re-assert at 10 Hz
// (a viewer whose killcam starts late would otherwise re-drop us to 0.25 mid-window), and hand the
// restore back just before stock's own — which then re-affirms 1.0 harmlessly.
//
// Passing the SAME deathTime target keeps stock's cinematic SHAPE (a smooth ramp reaching the floor
// 500ms before the killing blow) and changes only its depth. A hard snap would be its own hazard:
// an instantaneous 4x step is exactly what desyncs a client's time-delta filter.
gf_killcamSlowmoClamp( myGen )
{
    floor = gf_killcamFloor();
    if ( floor <= 0.25 )
        return;                     // stock depth requested — nothing to clamp

    // ⚠ NOT a bare waittill on a level notify that might never fire: a thread parked in a waittill
    // SURVIVES map_restart (one parked in a timed wait does not), so a round that never fired it
    // would strand one of these forever, one per round. Safe here because stock's
    // postRoundFinalKillcam() fires this EVERY round, killcam or not — which is also why the
    // inFinalKillcam check below is mandatory.
    level waittill( "play_final_killcam" );

    if ( gf_roundGenChanged( myGen ) )
        return;

    // No final killcam this round (nobody died last — the round was decided on the clock, on HP,
    // or by an overtime capture). Stock never dilates, so clamping would SLOW a full-speed round
    // end instead of speeding up a slow one.
    if ( !isDefined( level.inFinalKillcam ) || !level.inFinalKillcam )
        return;

    t0      = gettime();
    camtime = gf_killcamCamTime();

    // Mirrors stock's own deathTime: getTime() + secondsUntilDeath*1000, evaluated inside the
    // slowdown thread at t0+0.05, where secondsUntilDeath = camtime + level.lastKillCam.deathTimeOffset.
    // deathTimeOffset is only non-zero for a last-stand death, which this mod cannot produce (no
    // Second Chance), so it is 0.
    deathTime = t0 + 50 + int( camtime * 1000 );

    // NOT max( 0, ... ): max() lives in common_scripts\utility and this file does not #include it —
    // T5 has no transitive includes, so that would be an `unknown function` that fails the WHOLE
    // server at compile time and would not surface until a client connected.
    delay = camtime - 2.1;
    if ( delay > 0 )
        wait( delay );

    while ( gettime() < deathTime + 900 )        // stock restores at deathTime + 1000
    {
        if ( gf_roundGenChanged( myGen ) )
            return;

        SetTimeScale( floor, int( deathTime - 500 ) );
        wait 0.1;
    }

    SetTimeScale( 1.0, gettime() + 500 );
}

// Belt-and-braces, EVERY round, regardless of the toggle: stock's restore to 1.0 sits AFTER its
// wait, and the thread carries endon("end_killcam") + endon("disconnect"). If every viewer skips
// the killcam (or drops) inside that window, the restore never runs and the server is left at
// 0.25x — which would drag the next round into slow motion. Nothing in stock puts it back. One
// unconditional call at round start costs nothing and closes that hole.
// (Suspected relevance to the open "prematch countdown runs in slow-motion" TODO — unproven, but
// this is the cheap guard either way.)
gf_resetTimeScale()
{
    SetTimeScale( 1.0, gettime() );
}

// The engine's native prematch (matchStartTimer) draws the countdown number but plays NO sound.
// Mirror a per-second tick so the prematch has the same audible cadence as the overtime tick.
// Loops while level.inPrematchPeriod, so it self-stops at prematch_over.
gf_nativePrematchTicker()
{
    level endon( "game_ended" );

    tickObj = spawn( "script_origin", ( 0, 0, 0 ) );
    while ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
    {
        tickObj playSound( "mpl_ui_timer_countdown" );
        wait 1.0;
    }
    tickObj delete();
}

// #strip-begin - MATCH-START HOLD + LOBBY->MATCH TRANSFER (dev/main only; stripped from public release)
//
// This whole region — the pre-prematch load gate, the Auto/Manual pregame lobby it grew into, and
// the team/bot plan that carries arranged sides across the lobby's map_restart(false) — is absent
// from the public build. gf.gsc's single call to gf_waitForLoadingClients() is strip-marked too, so
// with it gone onStartGameType simply returns and the engine threads the prematch immediately: no
// load wait, no min-players hold, no lobby, no fast-restart.
//
// gf_anyTrackedClientLoading() is deliberately kept BELOW this region, outside the markers, because
// gf_roundWatchdog — live round code, always shipped — calls it. It reads level.gf_loadGateSeen, which
// only the tracker in here ever populates, and already returns false when that array is undefined, so
// it degrades to "nobody is loading" exactly as the public build wants. Do not fold it into this region.
// (gf_closeGraceEarly calls it too, but only from a hold that is itself strip-marked, so that second
// caller does not exist in the public build.)
//
// ─── Pre-prematch load gate ─────────────────────────────────────────────────
// Clients carried across a map rotation connect while STILL ON THEIR LOADING
// SCREEN: Callback_PlayerConnect fires immediately (statusicon
// "hud_status_connecting", level notify "connecting"), and the engine fires
// "begin" on the entity — clearing the icon, adding it to level.players, letting
// it spawn — only when that client finishes loading (_globallogic_player.gsc:15).
// The stock prematch never waits for any of that: startGame()'s waitForPlayers()
// is an EMPTY STUB in T5 (matchStartTimer's "Waiting for teams..." phase exists
// but is never seen), so the countdown starts on pure wall clock. Slow loaders
// miss the shared countdown, and — because loading clients are invisible to the
// roster poll, so gf_closeGraceEarly shuts maySpawn's first-spawn window ~3s
// after prematch_over — a slow-enough loader used to SPECTATE the whole first
// round.
//
// gf_waitForLoadingClients() runs as the LAST statement of onStartGameType (the
// engine threads startGame() the moment that callback returns, so holding there
// is exactly "the prematch has not started yet") and waits until every connected
// HUMAN is off the loading screen. level.inPrematchPeriod is already true during
// the hold, so players who finish loading spawn frozen with their own intro
// VO/splash, and when the gate releases the FULL stock countdown plays for
// everyone simultaneously. Match's first round only: between-round map_restarts
// re-begin in ~1-2s and the roster spawn gate already covers those.
//
// Bounds: scr_gf_load_wait = ceiling in seconds (default 20; 0 = gate off,
// clamped <=120), plus a 3s arrival floor so an early poll that runs before the
// engine has delivered the first connect callbacks can't wave the gate through.
// The floor is unconditional once the gate is armed, so a non-zero default costs
// every match start 3s even with nobody loading — that is the price of the gate
// being able to see a client that has not finished connecting yet.
// A first-time FastDL downloader (30-60s+ in-place engine rebuild) is
// deliberately NOT absorbed — they land mid-round-1 like today. Bots are test
// clients (begin instantly) and are excluded from both the wait and the readout,
// so a wedged bot can never hold the gate — same lesson as the roster gate.
//
// "Still loading" is read from statusicon — its ONLY writer is the connect path,
// and "begin" clears it — rather than racing the begin notify with a listener
// that could arm one frame late. The "connecting" notify is only used to COLLECT
// entities, because pre-begin clients exist nowhere else script-visible.

// Threaded early in onStartGameType, BEFORE any helper that might yield the
// Callback_StartGameType slice: the engine can only deliver the "connecting"
// callbacks once that slice first yields, so arming here guarantees the tracker
// is listening before the first one can fire.
gf_armLoadGate()
{
    if ( game["roundsplayed"] > 0 )
        return;
    // The post-restart pass is the REAL match — skip the whole gate so it runs a normal
    // prematch, no second lobby. The flag is a DVAR, not game[]: map_restart(false) (the
    // fast-restart) WIPES game[]/pers[] — that's how it re-fires the fresh presentation —
    // so a game[] flag wouldn't survive and the lobby would re-arm forever (infinite loop).
    if ( getDvar( "gf_matchArmed" ) == "1" )
        return;
    // Arm if ANY purpose of the pre-prematch hold is active: the load gate
    // (scr_gf_load_wait), the min-players gate (scr_gf_min_players > 1), OR a fast-restart
    // lobby (scr_gf_lobby = Auto/Manual). The tracker snapshot feeds all — the min-players
    // count includes still-loading humans, which only the tracker can see (pre-begin clients
    // aren't in level.players).
    loadOn  = ( gf_cfgFloat( "scr_gf_load_wait", 20, 0, 120 ) > 0 );
    minOn   = ( int( gf_cfgFloat( "scr_gf_min_players", 1, 1, 8 ) ) > 1 );
    lobbyOn = ( int( gf_cfgFloat( "scr_gf_lobby", 0, 0, 2 ) ) >= 1 );   // Auto or Manual
    if ( !loadOn && !minOn && !lobbyOn )
        return;

    // Fresh per match-start: a stale "Start Match" click (bridge lobbystart) from a
    // prior match must never auto-release this hold. map_restart wipes level.* too,
    // but clear explicitly so the guarantee doesn't lean on that.
    level.gf_lobbyStart = false;

    // Threads survive map_restart: retire any tracker a prior round left behind,
    // and generation-stamp this arm (gettime() is monotonic across map_restart)
    // so a gate thread orphaned by a mid-hold restart can detect it is stale.
    level notify( "gf_load_gate_reset" );
    level.gf_loadGateSeen = [];
    level.gf_loadGateGen  = gettime();
    level thread gf_loadGateTracker();
}

// Collects every client the engine announces on this map, including those still
// loading. Retired by gf_load_gate_reset (gate release or next arm) / game_ended.
gf_loadGateTracker()
{
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    for ( ;; )
    {
        level waittill( "connecting", p );
        if ( !isDefined( p ) )
            continue;

        // A quick disconnect+reconnect can hand back a reused entity — don't
        // double-count it.
        found = false;
        for ( i = 0; i < level.gf_loadGateSeen.size; i++ )
        {
            if ( isDefined( level.gf_loadGateSeen[i] ) && level.gf_loadGateSeen[i] == p )
            {
                found = true;
                break;
            }
        }
        if ( !found )
            level.gf_loadGateSeen[level.gf_loadGateSeen.size] = p;
    }
}

// One yellow number/glyph in the countdown slot (mirrors matchStartTimer's elem
// style); hidden until the gate has a real count to show.
gf_loadGateCountElem( xOfs )
{
    e = createServerFontString( "extrabig", 1.5 );
    e setPoint( "CENTER", "CENTER", xOfs, 0 );
    e.sort           = 1001;
    e.color          = ( 1, 1, 0 );
    e.foreground     = false;
    e.hidewheninmenu = true;
    e.alpha          = 0;
    return e;
}

// The hold itself — called (not threaded) as the last statement of
// onStartGameType. See the block comment above for the full design.
gf_waitForLoadingClients()
{
    if ( game["roundsplayed"] > 0 )
        return;
    // Fast-restart lobby post-restart pass: the lobby already ran and fast-restarted the
    // map; this pass is the REAL match, so CONSUME the flag + skip the gate and let
    // onStartGameType return into a normal prematch -> gunfight. The flag is a DVAR (survives
    // map_restart(false), which wipes game[]/pers[]); cleared HERE — the last gate touch — so
    // the NEXT match's lobby arms again.
    if ( getDvar( "gf_matchArmed" ) == "1" )
    {
        setDvar( "gf_matchArmed", "0" );
        // Lobby->match team transfer: re-apply the arranged-teams snapshot the lobby wrote before the
        // fast-restart. forceAutoAssign makes returning humans skip the team-select menu; the seating
        // itself happens at CONNECT via the connect-time autoassign override (level.gf_autoJoinBalance,
        // installed every round in gf.gsc onStartGameType — it delegates to gf_autoassignPlanned while
        // a plan is live), while each player is still spectator/dead — so the stock switch's suicide()
        // is invisible and no player visibly dies+respawns at match start. gf_applyTeamPlan stays as a
        // backstop (finds everyone already seated -> no-op; still heals any straggler the override
        // missed, incl. a rare joiner in the window before gf_teamPlanEntries is parsed below). Bots
        // are re-padded by the fill reconciler. Then fall through to a normal prematch -> gunfight.
        level.forceAutoAssign = true;

        // Parse the snapshot ONCE into a level array (consume the dvar here so the NEXT lobby writes a
        // fresh plan). Both gf_autoassignPlanned and the gf_applyTeamPlan backstop read this array. The
        // autoassign override is already installed (gf.gsc) and reads this at connect time, so no
        // separate install here — a re-save of level.autoassign would capture OUR override and recurse.
        plan = getDvar( "gf_teamplan" );
        setDvar( "gf_teamplan", "" );
        if ( plan != "" )
            level.gf_teamPlanEntries = strTok( plan, "," );

        level thread gf_applyTeamPlan();
        level thread gf_applyBotPlan();          // re-seat manually-arranged bots (fill-off); inert when gf_fill_n > 0
        return;
    }

    // This one pre-prematch hold serves THREE release conditions (min-players folded
    // in 2026-07-04, scr_gf_lobby Auto/Manual added 2026-07-05):
    //  (1) LOAD — every tracked client is off its loading screen (bounded by
    //      scr_gf_load_wait), so nobody misses the shared countdown/intro.
    //  (2) MIN-PLAYERS — at least scr_gf_min_players humans are here (bounded by
    //      GF_MINPLAYERS_MAX_HOLD, 90s). This used to be a SEPARATE hold AFTER
    //      prematch that froze players + voided all damage; in front of prematch it
    //      needs neither (nobody has spawned yet), and the intro no longer plays for
    //      a match that then stalls waiting for people to show up.
    //  (3) LOBBY MODE — scr_gf_lobby: Normal (0, in-place hold, no restart), Auto (1,
    //      release on load+min then FAST-RESTART), Manual (2, hold until the admin's
    //      START click -> level.gf_lobbyStart, then fast-restart; 10-min backstop). Auto/
    //      Manual paint the desaturated lobby vision and map_restart(false) on release so
    //      the match begins fresh with its full presentation; START is an instant override
    //      in every mode.
    // All are match-start only (the roundsplayed guard above). The min-players count
    // reads the tracker snapshot (humans, computed in the loop) so it includes
    // still-loading humans — a loader still counts as "here".
    loadWait    = gf_cfgFloat( "scr_gf_load_wait", 20, 0, 120 );
    minP        = int( gf_cfgFloat( "scr_gf_min_players", 1, 1, 8 ) );
    lobby       = int( gf_cfgFloat( "scr_gf_lobby", 0, 0, 2 ) );   // 0 = Normal (default), 1 = Auto lobby, 2 = Manual lobby
    restartMode = ( lobby >= 1 );   // Auto/Manual do the fast map_restart(false) on release
    manualMode  = ( lobby == 2 );   // Manual holds for the admin START click (no min-players auto-release)
    loadGateOn  = ( loadWait > 0 );
    minGateOn   = ( minP > 1 );
    // Run the gate if there's anything to wait for OR a fast-restart lobby is active
    // (Auto/Manual must run the gate so the release can fast-restart, even at min-players 1).
    if ( !loadGateOn && !minGateOn && !restartMode )
        return;
    if ( !isDefined( level.gf_loadGateSeen ) )   // arm didn't run — nothing tracked, nothing to wait on
        return;

    myGen         = level.gf_loadGateGen;
    start         = gettime();
    loadDeadline  = start + int( loadWait * 1000 );   // stop waiting for loaders (only if loadGateOn)
    // Min-players "start anyway" ceiling — RCON-adjustable via scr_gf_minplayers_timer.
    // 0 = never auto-start (DEFAULT): the min-players lobby holds until enough humans arrive OR an
    // admin clicks START, instead of quietly starting a too-thin match on its own. The old hardcoded
    // 90s GF_MINPLAYERS_MAX_HOLD forced a start here, which read as an unintended auto-start once the
    // wait exceeded 90s. A pure-bot lobby (0 humans) still releases via the humans==0 clause below,
    // so 0 can never wedge a bot-only match; only a lobby genuinely short of humans waits.
    minTimer      = int( gf_cfgFloat( "scr_gf_minplayers_timer", 0, 0, 3600 ) );
    minTimerOn    = ( minTimer > 0 );
    minDeadline   = start + ( minTimer * 1000 );        // only consulted when minTimerOn
    // MANUAL lobby auto-start timer (seconds), RCON-adjustable via scr_gf_lobby_timer. Replaces the old
    // hardcoded 10-min GF_LOBBY_MAX_HOLD backstop. 0 = never auto-start: the lobby then holds until the
    // admin clicks START (deliberate — but a forgotten hold will sit there until someone starts it).
    // Manual-only: the Auto lobby releases on its own gates (load/min-players), never on this timer.
    lobbyTimer    = int( gf_cfgFloat( "scr_gf_lobby_timer", 600, 0, 3600 ) );
    lobbyDeadline = start + ( lobbyTimer * 1000 );
    floorEnd      = start + 3000;                       // arrival floor — see block comment

    // Stock look: the exact "waiting for teams" element matchStartTimer() shows
    // while its (stubbed) waitForPlayers() would wait, plus a live
    // "loaded / total" readout in the slot the countdown number will take over.
    // Counts are setValue-driven (no dynamic setText — configstring-safe); the
    // "/" is the only new raw string, once per match.
    elems = [];
    waitText = createServerFontString( "extrabig", 1.5 );
    waitText setPoint( "CENTER", "CENTER", 0, -40 );
    waitText.sort           = 1001;
    waitText.foreground     = false;
    waitText.hidewheninmenu = true;
    waitText setText( game["strings"]["waiting_for_teams"] );
    elems[elems.size] = waitText;

    cntLoaded = gf_loadGateCountElem( -24 );
    cntSlash  = gf_loadGateCountElem( 0 );
    cntSlash setText( "/" );
    cntTotal  = gf_loadGateCountElem( 24 );
    elems[elems.size] = cntLoaded;
    elems[elems.size] = cntSlash;
    elems[elems.size] = cntTotal;

    // In the Auto/Manual lobby the custom lobby HUD (gf_lobby_hud menuDef) owns the "waiting" message
    // + count, so hide this stock load-gate readout to avoid the doubled dead-center text. Keep it in
    // Normal mode (scr_gf_lobby 0), where it's the only start feedback. The count-update logic below
    // still runs on the now-invisible elems (harmless — setValue on a 0-alpha element is a no-op look).
    if ( restartMode )
        for ( ei = 0; ei < elems.size; ei++ )
            elems[ei].alpha = 0;

    shownCount   = false;
    lastLoaded   = -1;
    lastTotal    = -1;
    stillLoading = 0;

    // Live flag: true only while this hold is actively blocking. Read by the bridge
    // (lobbystart feedback) and mirrored into gf_state telemetry so the panel can
    // show/enable "Start Match" exactly when a hold is up. Cleared the instant we break.
    level.gf_inLobbyHold = true;

    // Auto/Manual lobby: paint it with the desaturated pregame vision (the same "mpIntro"
    // string the native prematch uses) AND float everyone in the intermission camera (the
    // locked, bodyless "postgame" map-overview cam) so it reads as a real pregame staging
    // screen instead of players frozen at their spawns. Both are wiped for FREE by the
    // map_restart(false) on release (players re-spawn fresh into the match), so no teardown
    // is needed — which is exactly why this is scoped to restartMode (Normal has no restart
    // and would need explicit per-player camera reversal).
    if ( restartMode )
    {
        visionSetNaked( "mpIntro", 0 );
        // Hide the stock spectator overlay ("SPECTATING <name>" + the follow-key instructions) for a
        // clean lobby — the exact matchflag the stock game-end uses (_globallogic.gsc:685). Level-wide,
        // one call; restored at the release + reset by the map_restart(false) anyway.
        setmatchflag( "cg_drawSpectatorMessages", 0 );
        // Strip the scoreboard to the minimum this builtin can produce for the lobby: NAME + SCORE +
        // PING. setscoreboardcolumns controls only the 4 MIDDLE columns (Score + Ping are engine-fixed
        // and can't be removed without editing the scoreboard .menu). No restore call needed — main()
        // re-runs setscoreboardcolumns("kills","deaths","assists","captures") (gf.gsc) on the
        // post-restart onStartGameType pass, so the real match gets its normal columns back.
        setscoreboardcolumns( "none", "none", "none", "none" );
        // Force teamless connectors to AUTO-ASSIGN instead of popping the team-select menu
        // (_globallogic_player.gsc:338 -> autoassign when forceAutoAssign is set, else openMenu team).
        // This lets the lobby cam drop ALL per-tick menu suppression — the old closeMenu()/
        // g_scriptMainMenu="" swatted the team menu but also killed the ESC/pause overlay every tick.
        // Nobody needs the team menu in the lobby; the fast-restart does the real pick. Wiped by
        // map_restart(false) on release, so the real match (Pass 2) keeps normal team behavior.
        level.forceAutoAssign = true;
        // Restart-lobby ONLY flag. Gates the throwaway-spawn optimizations (skip the spawn music +
        // the whole loadout build) — safe here because map_restart(false) rebuilds everything fresh for
        // the real match. It must NOT key off gf_inLobbyHold: a non-restart Normal-mode hold (load/
        // min-players gate with scr_gf_lobby 0) frozen-spawns players whose spawn IS the match spawn,
        // so skipping their loadout would leave them weaponless. map_restart(false) wipes this level var;
        // the release below clears it for the gameEnded / no-restart exits.
        level.gf_lobbyRestartHold = true;
        // Suppress the stock "You will respawn next round" lower-third the maySpawn-false spectator path
        // sets: livesDoNotReset=true makes shouldShowRespawnMessage false (_globallogic_spawn.gsc:572), so
        // the message is never set (cleaner than clearing it after — the stock auto-clear is aborted by
        // an "end_respawn" notify, which is why it persisted). Safe: gunfight never uses livesDoNotReset,
        // the first-connect lives reset is forced by the isDefined() clause (_globallogic_player.gsc:235),
        // and map_restart(false) wipes level.* + pers[] so the match resets lives normally.
        level.livesDoNotReset = true;
        level thread gf_lobbyCamWatcher();
        level thread gf_lobbyRosterLoop();
        level thread gf_lobbyIconCycler();
    }

    for ( ;; )
    {
        // Superseded by a map_restart during the hold (threads survive it): the
        // new round re-armed the gate and the restart wiped our elements — quit
        // without teardown and WITHOUT the reset notify (that would kill the new
        // round's tracker).
        if ( !isDefined( level.gf_loadGateGen ) || level.gf_loadGateGen != myGen )
        {
            logPrint( "GF_LOBBY_END: superseded - gen changed (external map_restart re-armed the gate) after " + ( gettime() - start ) + "ms\n" );
            return;
        }

        stillLoading = 0;
        humans       = 0;
        for ( i = 0; i < level.gf_loadGateSeen.size; i++ )
        {
            p = level.gf_loadGateSeen[i];
            if ( !isDefined( p ) )        // dropped while loading
                continue;
            if ( isDefined( p.statusicon ) && p.statusicon == "hud_status_connecting" )
            {
                // Still loading. istestclient() is only stock-precedented on begun
                // clients, so don't classify yet — a pre-begin bot is transient
                // (test clients begin within a frame) and at worst flickers the
                // readout for one 0.25s poll.
                humans++;
                stillLoading++;
            }
            // begun: drop bots (istestclient) AND server-side demo clients
            // (isdemoclient — e.g. "[3arc]democlient", guid 0). A demo client is NOT a
            // test client, so without the isdemoclient check it was wrongly counted as a
            // human, inflating the readout and satisfying scr_gf_min_players by itself.
            else if ( !( p istestclient() ) && !( p isdemoclient() ) )
            {
                humans++;
            }
        }

        if ( humans > 0 )
        {
            loaded = humans - stillLoading;
            if ( loaded != lastLoaded )
            {
                cntLoaded setValue( loaded );
                lastLoaded = loaded;
            }
            if ( humans != lastTotal )
            {
                cntTotal setValue( humans );
                lastTotal = humans;
            }
            if ( !shownCount && !restartMode )   // Auto/Manual: keep counts hidden — custom lobby HUD owns the readout
            {
                cntLoaded.alpha = 1;
                cntSlash.alpha  = 1;
                cntTotal.alpha  = 1;
                shownCount = true;
            }
        }

        now = gettime();
        if ( isDefined( level.gameEnded ) && level.gameEnded )
        {
            logPrint( "GF_LOBBY_END: level.gameEnded became true after " + ( now - start ) + "ms\n" );
            break;
        }

        // Admin "Start Match" click (bridge lobbystart) — an immediate override that
        // releases the hold in EITHER mode. Cleared per match in gf_armLoadGate, so a
        // stale click from a prior match can't leak in.
        startClicked = ( isDefined( level.gf_lobbyStart ) && level.gf_lobbyStart );

        // The auto-start timer is deliberately INVISIBLE to players: the lobby keeps
        // gf_lobbyCamPut's static "Waiting for the host to start" for its whole life, and the
        // deadline below fires silently. The countdown is an admin backstop, not a promise to
        // the room — a live "auto-starts in M:SS" reads as a commitment the admin can (and
        // does) pre-empt with START. It stays an RCON-side setting (scr_gf_lobby_timer).
        // Bonus: no per-second ui_gf_lobby_status push = one less reliable-command stream.

        if ( manualMode )
        {
            // MANUAL lobby: hold until the admin clicks START (or the 10-min backstop),
            // regardless of load state / headcount. No 3s floor — a deliberate click
            // starts immediately.
            if ( startClicked )
            {
                logPrint( "GF_LOBBY_END: manual - admin START clicked after " + ( now - start ) + "ms\n" );
                break;
            }
            if ( lobbyTimer > 0 && now >= lobbyDeadline )
            {
                logPrint( "GF_LOBBY_END: manual - auto-start timer (scr_gf_lobby_timer=" + lobbyTimer + "s) elapsed after " + ( now - start ) + "ms\n" );
                break;
            }
        }
        else
        {
            // AUTO / NORMAL: release once everyone is off the loading screen (or the load
            // ceiling hit) AND enough humans are here (or none to wait for / start-anyway
            // ceiling hit). humans counts tracked humans whether loaded or still loading;
            // the load condition then waits for any still loading to finish. An admin START
            // click still force-releases (start now, even below min-players).
            loadOk = ( !loadGateOn ) || ( stillLoading == 0 ) || ( now >= loadDeadline );
            minOk  = ( !minGateOn ) || ( humans >= minP ) || ( humans == 0 ) || ( minTimerOn && now >= minDeadline );
            if ( startClicked )
            {
                logPrint( "GF_LOBBY_END: auto - admin START clicked after " + ( now - start ) + "ms\n" );
                break;
            }
            if ( now >= floorEnd && loadOk && minOk )
            {
                logPrint( "GF_LOBBY_END: auto - gates satisfied (loadOk=" + loadOk + " minOk=" + minOk + " humans=" + humans + " stillLoading=" + stillLoading + ") after " + ( now - start ) + "ms\n" );
                break;
            }
        }

        wait 0.25;
    }

    level.gf_inLobbyHold = false;   // hold is over — the panel's Start affordance hides
    level.gf_lobbyRestartHold = false;   // clear the throwaway-spawn gate (map_restart(false) also wipes it, but the gameEnded / no-restart paths need it explicit)
    level.livesDoNotReset = false;       // undo the lobby respawn-message suppression (gunfight never uses it; map_restart also wipes it, explicit for the gameEnded / no-restart path)

    // Restore the lobby-only presentation tweaks (compass + spectator overlay). The map_restart(false)
    // path also resets both (matchflags reset on re-init; a fresh spawn's reset_clientdvars re-sets
    // compass=1), but restore explicitly so the non-restart / gameEnded path is clean and the compass
    // push has a chance to land before the restart.
    if ( restartMode )
    {
        setmatchflag( "cg_drawSpectatorMessages", 1 );
        for ( ri = 0; ri < level.players.size; ri++ )
        {
            // ONE batched reliable command, not two. These land immediately before the
            // map_restart(false) below — i.e. right at the edge of the stall window that a
            // "Server command overflow" disconnect is counted in. See the batching note in
            // _gf_hud.gsc::gf_showWeaponHUD.
            level.players[ri] setClientDvars( "compass",          "1",
                                              "ui_gf_lobby_show", "0" );   // hide the lobby HUD for the match
        }
    }

    // ── FAST-RESTART LOBBY (scr_gf_lobby = Auto / Manual) ────────────────────────
    // Normal mode holds mid-init: the engine already began the match (InitGame fired,
    // level.inPrematchPeriod set at _globallogic.gsc:1845) BEFORE onStartGameType, so it's a
    // paused-startup, not a true pregame lobby. Auto/Manual treat the hold as a real PREGAME
    // LOBBY and, on release, FAST-RESTART the map so the actual gunfight begins FRESH — re-
    // firing the full match-start presentation (weapon first-raise / "gun rack", spawn music,
    // welcome splash) that the between-rounds restart suppresses.
    //
    // map_restart(FALSE) is the fresh reset (verified in-game 2026-07-05 — racks the gun,
    // plays the music, fast, no map reload); map_restart(true) is the state-preserving one
    // Gunfight uses BETWEEN rounds, which is exactly why the presentation doesn't fire there.
    //
    // Structured to NEVER RETURN: onStartGameType returning is what threads startGame() ->
    // prematchPeriod()/gameTimer(). Those endon "game_ended" (fired each round to tear them
    // down before re-threading — that's how they don't stack). We do NOT fire game_ended, so
    // if startGame() threaded even briefly before the restart, that sliver would survive the
    // map_restart and stack (double countdown). Blocking here forever means startGame() never
    // threads in the lobby pass — nothing to stack. The gf_matchArmed DVAR (dvar, not game[]:
    // map_restart(false) WIPES game[]/pers[], which is how it re-fires the fresh presentation
    // but also why a game[] flag would loop forever) makes the post-restart pass skip this
    // whole gate, so the real match threads its clocks exactly once.
    // Skip the restart if the game ended during the hold (the loop's gameEnded break) — don't
    // fast-restart an already-ended match; fall through to the normal teardown/return instead.
    if ( restartMode && !( isDefined( level.gameEnded ) && level.gameEnded ) )
    {
        setDvar( "gf_matchArmed", "1" );
        gf_writeTeamPlan();                      // snapshot arranged human teams -> gf_teamplan (a dvar, survives the restart)
        gf_writeBotPlan();                       // snapshot arranged bot counts per team -> gf_botplan (fill-off manual bots carry over)
        for ( i = 0; i < elems.size; i++ )
            if ( isDefined( elems[i] ) )
                elems[i] destroyElem();
        level notify( "gf_load_gate_reset" );   // retire the tracker before the restart
        logPrint( "GF_LOADGATE: lobby released -> map_restart(false) into match (roundsplayed=" + game["roundsplayed"] + ")\n" );
        map_restart( false );
        for ( ;; )
            wait 1;   // never return: the restart aborts this thread; blocking keeps startGame() from threading a stale prematch
    }

    // Released with someone still loading (ceiling hit — e.g. a first-time FastDL
    // downloader). Raise the grace ceiling so the first-spawn window stays open
    // past prematch_over and they can still spawn INTO round 1 instead of
    // spectating it: maySpawn only admits a late first-spawn while inGracePeriod,
    // and gf_closeGraceEarly / the stock gracePeriod backstop otherwise shut that
    // window ~3-15s in. onStartGameType hasn't returned yet, so this is seen by
    // the stock gracePeriod() thread (threaded later, in startGame). The wait
    // itself lives in gf_closeGraceEarly, keyed off the same tracker snapshot.
    if ( stillLoading > 0 )
    {
        loadGrace = gf_cfgFloat( "scr_gf_load_grace", 20, 0, 60 );   // 0 = don't hold grace for loaders
        if ( loadGrace > level.gracePeriod )
            level.gracePeriod = loadGrace;
    }

    logPrint( "GF_LOADGATE: released after " + ( gettime() - start ) + "ms, " + stillLoading + " client(s) still loading\n" );

    for ( i = 0; i < elems.size; i++ )
    {
        if ( isDefined( elems[i] ) )
            elems[i] destroyElem();
    }

    level notify( "gf_load_gate_reset" );   // gate done — retire the tracker
}

// ── Lobby -> match team transfer ─────────────────────────────────────────────
// The Auto/Manual lobby releases via map_restart(false), which WIPES pers[]/game[]/level[] — so
// admin-arranged (or autoassigned) lobby teams would be lost and everyone re-autoassigned into the
// real match. gf_writeTeamPlan snapshots each HUMAN's getGuid()->team into the gf_teamplan DVAR
// (the only state that survives the fast-restart) just before the restart; gf_applyTeamPlan
// re-applies it after. Bots: with dynamic fill ON the reconciler re-pads them from gf_fill_n, so
// nothing is snapshotted; with fill OFF (manual bots) gf_writeBotPlan/gf_applyBotPlan carry the
// arranged per-team bot COUNTS across the restart the same way (count-based — bots have no guid).
// Self-contained (no bridge dep) so it works even on a public build with the bridge stripped.

// Snapshot arranged human teams into gf_teamplan: "<guid>:<a|x|s>,<guid>:<a|x|s>,...".
gf_writeTeamPlan()
{
    plan = "";
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) )
            continue;
        if ( p istestclient() || p isdemoclient() )   // humans only
            continue;
        t = p.pers["team"];
        if ( !isDefined( t ) )
            continue;
        code = "";
        if ( t == "allies" )         code = "a";
        else if ( t == "axis" )      code = "x";
        else if ( t == "spectator" ) code = "s";
        else                         continue;          // no real assignment -> skip
        g = "" + p getGuid();                            // string-coerce (stock idiom)
        if ( plan != "" )
            plan += ",";
        plan += g + ":" + code;
    }
    setDvar( "gf_teamplan", plan );
}

// Snapshot arranged bot COUNTS per team into gf_botplan: "<alliesN>,<axisN>". Bots have no stable
// guid (all "0"), so unlike the human plan this is count-based — bots are fungible, we only need to
// reproduce how many sit on each side, not which is which. Companion to gf_writeTeamPlan; written
// just before the lobby's map_restart(false) and consumed once by gf_applyBotPlan after. Only
// meaningful with dynamic fill OFF (gf_fill_n 0) — with fill on the reconciler owns bot placement
// and re-pads from gf_fill_n, so gf_applyBotPlan stands down. Self-contained (no _bot.gsc dep) so it
// compiles in the bot-stripped public build, where level.players holds no test clients -> a no-op.
gf_writeBotPlan()
{
    a = 0;
    x = 0;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) )
            continue;
        // Bots only. NOT the plain inverse of gf_writeTeamPlan's humans-only test: a demo client is
        // neither a human nor a bot (isdemoclient true, istestclient FALSE), so it must be dropped by
        // BOTH filters — matching _bot.gsc's real-bot test.
        if ( !( p istestclient() ) || p isdemoclient() )
            continue;
        t = p.pers["team"];
        if ( !isDefined( t ) )
            continue;
        if      ( t == "allies" ) a++;
        else if ( t == "axis" )   x++;
    }
    setDvar( "gf_botplan", a + "," + x );
}

// Re-apply the gf_teamplan snapshot after the lobby fast-restart. Threaded from the gf_matchArmed
// consume branch; runs during the real match's prematch. Polls until every planned human is on
// their side (or a bound elapses / prematch ends), tolerating the reconnect delay.
gf_applyTeamPlan()
{
    level endon( "game_ended" );

    // The gf_matchArmed branch already parsed + consumed the gf_teamplan dvar into this array (so the
    // connect-time gf_autoassignPlanned override can share it); we are the backstop over the same plan.
    if ( !isDefined( level.gf_teamPlanEntries ) )
        return;
    entries  = level.gf_teamPlanEntries;
    total    = entries.size;
    deadline = gettime() + 45000;        // bound: never run past the intro

    for ( ;; )
    {
        // YIELD FIRST — do not evaluate the roster synchronously. This is threaded from the tail of
        // onStartGameType, where _spawnlogic::init has already emptied level.players and
        // Callback_PlayerConnect only repopulates it after we return. A synchronous first pass would
        // see ZERO players, conclude "nobody left to seat", and silently drop the plan — which is
        // already consumed from the dvar, so the arranged teams would be lost for good.
        wait 0.25;

        if ( gettime() >= deadline )
            return;
        if ( !( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod ) )
            return;                      // prematch over — a live move would suicide the player

        seen   = 0;
        seated = 0;
        players = level.players;
        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];
            if ( !isDefined( p ) )
                continue;
            if ( p istestclient() || p isdemoclient() )
                continue;
            want = gf_teamPlanLookup( entries, "" + p getGuid() );
            if ( want == "" )
                continue;                // not in the plan (a fresh joiner)
            seen++;
            if ( isDefined( p.pers["team"] ) && p.pers["team"] == want )
            {
                seated++;
                continue;                // already on the planned side
            }
            if ( isDefined( p.pers["team"] ) )   // only move once a team is resolved (don't race autoassign)
                p gf_planApplyMove( want );
        }
        // Done only when EVERY planned human is back AND on their side. Someone who never
        // reconnects simply rides out the deadline (harmless 0.25s polls).
        if ( seen >= total && seated >= total )
            return;
    }
}

// Re-apply the gf_botplan bot-count snapshot after the lobby fast-restart. Threaded from the
// gf_matchArmed consume branch alongside gf_applyTeamPlan; runs during the real match's prematch.
// Bots survive map_restart(false) as connected clients (only their team placement is wiped), so we
// just re-seat the SURVIVING bots: first A to allies, next X to axis, any extra to spectator —
// reproducing the arranged per-side counts. Inert when dynamic fill is on (gf_fill_n > 0): the
// reconciler owns bot placement there and this would fight it. Self-contained (reuses gf_planApplyMove,
// not _bot.gsc) so it compiles in the public build, where gf_botplan is empty -> immediate no-op.
gf_applyBotPlan()
{
    level endon( "game_ended" );

    plan = getDvar( "gf_botplan" );
    setDvar( "gf_botplan", "" );         // consume once
    if ( plan == "" )
        return;
    if ( int( gf_cfgFloat( "gf_fill_n", 0, 0, 6 ) ) > 0 )
        return;                          // dynamic fill on -> the reconciler owns bot placement

    counts = strTok( plan, "," );
    if ( counts.size < 2 )
        return;
    wantA = int( counts[0] );
    wantX = int( counts[1] );
    if ( wantA + wantX <= 0 )
        return;

    deadline = gettime() + 45000;        // bound: never run past the intro
    aSeated  = 0;
    xSeated  = 0;

    for ( ;; )
    {
        // Poll FAST so a reconnecting bot is caught the instant autoassign resolves its team (don't
        // race autoassign — wait for pers["team"]) but BEFORE it spawns frozen, so gf_planApplyMove
        // takes the quiet pers-reassign branch (no visible suicide). A bot already spawned gets the
        // same harmless prematch warmup switch + respawn recovery the human transfer uses.
        wait 0.05;

        if ( gettime() >= deadline )
            return;
        if ( !( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod ) )
            return;                      // prematch over — a live switch would suicide the bot for real

        players = level.players;
        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];
            if ( !isDefined( p ) )
                continue;
            if ( !( p istestclient() ) || p isdemoclient() )
                continue;                // bots only — the democlient is NOT one (see gf_writeBotPlan)
            if ( isDefined( p.gf_botPlanSeated ) )
                continue;                // one-shot per bot
            if ( !isDefined( p.pers["team"] ) )
                continue;                // let autoassign resolve first, then override

            if      ( aSeated < wantA ) want = "allies";
            else if ( xSeated < wantX ) want = "axis";
            else                        want = "spectator";

            // Skip the switch if autoassign already landed the bot on its target side — moving a
            // correctly-placed "playing" bot would be a needless warmup suicide.
            if ( p.pers["team"] != want )
                p gf_planApplyMove( want );
            p.gf_botPlanSeated = true;
            if      ( want == "allies" ) aSeated++;
            else if ( want == "axis" )   xSeated++;
        }

        if ( aSeated >= wantA && xSeated >= wantX )
            return;                      // every arranged slot filled
    }
}

// GUID -> planned team ("allies"/"axis"/"spectator"), or "" if not in the plan.
gf_teamPlanLookup( entries, guid )
{
    for ( i = 0; i < entries.size; i++ )
    {
        kv = strTok( entries[i], ":" );
        if ( kv.size < 2 || kv[0] != guid )
            continue;
        if ( kv[1] == "a" ) return "allies";
        if ( kv[1] == "x" ) return "axis";
        if ( kv[1] == "s" ) return "spectator";
        return "";
    }
    return "";
}

// Connect-time autoassign override for the lobby->match transfer (installed as level.autoassign in the
// gf_matchArmed branch, restored to stock by the next round's map_restart(true) -> SetupCallbacks).
// Stock Callback_PlayerConnect calls [[level.autoassign]]() for every human reconnecting into the real
// match; running here — while pers["team"] is still "spectator" and sessionstate is "dead" — lets us
// seat the PLANNED side before the player ever spawns, so gf_applyTeamPlan finds them already correct
// and never runs the VISIBLE prematch suicide()+respawn that flickered each player at match start.
// Unplanned joiners, bots, and any connect after prematch fall through to the stock random autoassign.
gf_autoassignPlanned()
{
    if ( !isDefined( level.gf_teamPlanEntries )
         || self istestclient() || self isdemoclient()
         || !( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod ) )
    {
        self [[level.gf_stockAutoassign]]();     // no plan / bot / past prematch -> stock behaviour
        return;
    }

    want = gf_teamPlanLookup( level.gf_teamPlanEntries, "" + self getGuid() );
    if ( want == "" )
    {
        self [[level.gf_stockAutoassign]]();     // fresh joiner not in the plan
        return;
    }
    if ( want == "spectator" )
        return;                                  // stock connect already parked them spectator

    self gf_seatJoinTeam( want );
}

// Seat `self` on `want` while pre-spawn (spectator/dead), mirroring menuAutoAssign's tail
// (_globallogic_ui.gsc) MINUS the random pick and its suicide() — the player is pre-spawn here, so no
// kill is needed to move them, and beginClassChoice threads the (frozen, prematch) spawn straight
// onto `want`. Shared by the lobby->match plan (gf_autoassignPlanned) and the mid-match human-balance
// autoassign (gf_autoJoinBalance).
gf_seatJoinTeam( want )
{
    self.pers["gf_specReason"] = undefined;    // seated on a real team: drop any spectate breadcrumb
    self.pers["team"]       = want;
    self.team               = want;
    self.pers["class"]      = undefined;
    self.class              = undefined;
    self.pers["weapon"]     = undefined;
    self.pers["savedmodel"] = undefined;
    self maps\mp\gametypes\_globallogic_ui::updateObjectiveText();
    self.sessionteam        = want;
    if ( !isAlive( self ) )
        self.statusicon = "hud_status_dead";
    self notify( "joined_team" );
    level notify( "joined_team" );
    self notify( "end_respawn" );
    self thread maps\mp\gametypes\_globallogic_ui::preventTeamSwitchExploit();
    self maps\mp\gametypes\_globallogic_ui::beginClassChoice();
}

// Connect-time autoassign for a LIVE match — installed as level.autoassign every round in
// onStartGameType (gf.gsc), saving stock's into level.gf_stockAutoassign. Two jobs, in order:
//   1) Lobby->match transfer plan live? delegate to gf_autoassignPlanned (seats the planned side).
//      Its own fallbacks reach level.gf_stockAutoassign = REAL stock (saved once, before this install
//      is active), never back through here — so there is no recursion.
//   2) Otherwise a normal mid-match human joiner: seat the fewer-HUMAN side, but ONLY when the human
//      split is already lopsided (|allies-axis| > 1). A balanced/near-balanced split falls through to
//      the stock team pick, so a player can still choose a side (e.g. to squad with a friend). Bots
//      are IGNORED for this count — the reconciler evens team SIZE with bots at the round boundary;
//      this only steers HUMANS. Suicide-free: the joiner is pre-spawn and can't spawn until the next
//      round anyway (one-life maySpawn), so seating them now costs no death.
// Dev/main only — the install in gf.gsc is strip-wrapped; the public build keeps stock autoassign.
gf_autoJoinBalance()
{
    if ( self istestclient() || self isdemoclient() )
    {
        self [[level.gf_stockAutoassign]]();
        return;
    }
    if ( isDefined( level.gf_teamPlanEntries ) )
    {
        self gf_autoassignPlanned();
        return;
    }

    ha = gf_countTeamHumans( "allies", self );
    hx = gf_countTeamHumans( "axis",   self );

    // An ALIVE player picking Auto Assign from the menu: stock menuAutoAssign would run its racy
    // suicide switch (the wrong-team/1hp bug) — route through the sequenced move instead. The
    // pick is the lighter HUMAN side; already there (or tied) means nothing to do.
    if ( self.sessionstate == "playing" )
    {
        want = "axis";
        if ( hx > ha )
            want = "allies";
        if ( ha == hx || ( isDefined( self.pers["team"] ) && self.pers["team"] == want ) )
            return;
        if ( getDvarInt( "gf_team_switch" ) == 0 )
            return;
        if ( gf_teamLockDenies( self, want ) )
            return;
        restore = ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
                  || ( isDefined( level.inGracePeriod ) && level.inGracePeriod );
        self thread gf_seqTeamMove( want, restore );
        return;
    }

    // Team-size lock: both sides full of humans -> spectate + queue (join order); one side full
    // -> the open side is the only legal seat, so take it regardless of balance.
    if ( gf_teamLockOn() )
    {
        aFull = gf_teamLockDenies( self, "allies" );
        xFull = gf_teamLockDenies( self, "axis" );
        if ( aFull && xFull )
        {
            self gf_lockQueueMark();
            self gf_quietSetTeam( "spectator" );
            return;
        }
        if ( aFull ) { self gf_seatJoinTeam( "axis" );   return; }
        if ( xFull ) { self gf_seatJoinTeam( "allies" ); return; }
    }

    diff = ha - hx;
    if ( diff < 0 )
        diff = hx - ha;                              // abs without unary minus
    if ( diff <= 1 )                                 // balanced enough — let the player pick a side
    {
        self [[level.gf_stockAutoassign]]();
        return;
    }

    want = "axis";
    if ( hx > ha )
        want = "allies";
    self gf_seatJoinTeam( want );                    // seat the lighter HUMAN side (pre-spawn, no kill)
}

// Apply a planned team to self during prematch. Mirrors the bridge's gf_applyTeamMove but is
// self-contained (the bridge is stripped from public builds). A "playing" (prematch-frozen)
// player takes the SEQUENCED move (life restored, respawned); a not-yet-spawned player gets a
// quiet pers reassign.
gf_planApplyMove( team )
{
    if ( self.sessionstate == "playing" )
        self thread gf_seqTeamMove( team, true );
    else
        self gf_quietSetTeam( team );
}

// The quiet persistent-state half of a team change (no suicide, no respawn, no menus): the next
// spawn reads pers["team"] and the player simply spawns on the new side. Only ever safe on a
// NOT-"playing" player (a live body can't change teams without a respawn). Clearing
// pers["savedmodel"] matters: a cached old-side model would render the player in the WRONG TEAM's
// skin after the move. Mirrors _gf_bridge::gf_forceTeamQuiet / _bot::gf_botQuietSetTeam.
gf_quietSetTeam( team )
{
    self.pers["team"]       = team;
    self.team               = team;
    self.pers["class"]      = undefined;
    self.class              = undefined;
    self.pers["weapon"]     = undefined;
    self.pers["savedmodel"] = undefined;
    self.sessionteam        = team;
}

// ─── Sequenced team move — the ONLY way to move a "playing" player ─────────
// Stock menuAllies/menuAxis suicide() a playing player and drive the respawn in the SAME frame,
// while the suicide's kill callback settles asynchronously over the next frames. Racing those two
// (as the old stock-switch + gf_reseatRespawn recovery pair did) is the root cause of the rare
// "spawned at the enemy spawns / spawned with 1 HP" bug seen after team switches/moves: the new
// spawn could commit while team state was half-flipped, and the suicide's death could land AFTER
// the respawn. This primitive strictly SEQUENCES it: suicide -> wait for the death to fully settle
// -> quiet pers reassign -> only then drive the respawn.
//
// restoreLife = true : give the life back and respawn (prematch/grace warmup moves, admin force
//                      moves — the respawn is admitted by maySpawn's late-spawn rules mid-round).
// restoreLife = false: die and sit out the round (a mid-round self-switch costs your life); the
//                      next round's map_restart resets lives so they spawn normally on the new side.
gf_seqTeamMove( team, restoreLife )
{
    self endon( "disconnect" );
    self notify( "gf_seqTeamMove" );     // collapse to one live copy per player
    self endon( "gf_seqTeamMove" );

    if ( self.sessionstate == "playing" )
    {
        // Stock's switch flags: Callback_PlayerKilled reads switching_teams so the death is
        // scored as a team change, not a combat death.
        self.switching_teams = true;
        self.joining_team    = team;
        self.leaving_team    = self.pers["team"];
        self suicide();

        // Wait for the async death to settle BEFORE touching team state — the entire point of
        // this primitive. Bounded ~2s; on fall-through the quiet reassign below is still safe
        // (nothing re-drives a spawn until we do).
        for ( i = 0; i < 40; i++ )
        {
            if ( self.sessionstate != "playing" && !isAlive( self ) )
                break;
            wait 0.05;
        }
    }

    if ( team == "spectator" )
    {
        self gf_quietSetTeam( "spectator" );
        self maps\mp\gametypes\_globallogic_ui::updateObjectiveText();
        self setclientdvar( "g_scriptMainMenu", game["menu_team"] );
        self [[level.spawnSpectator]]();
        self notify( "joined_spectators" );
        return;
    }

    if ( isDefined( restoreLife ) && restoreLife )
        self.pers["lives"] = level.numLives;   // clear maySpawn gate A (the suicide consumed the life)

    self setclientdvar( "g_scriptMainMenu", game["menu_class_" + team] );
    self gf_seatJoinTeam( team );              // quiet seat + beginClassChoice (maySpawn decides the spawn)

    if ( !isDefined( restoreLife ) || !restoreLife )
        return;                                // mid-round self-switch: sits out this round by design

    // Respawn recovery (absorbs the old gf_reseatRespawn): maySpawn's deny path bounces to
    // SPECTATOR with no retry, and during the prematch warmup the deny reasons are transient
    // (async lives decrement racing the restore above). Keep restoring + re-driving while the
    // prematch lasts; past prematch the single beginClassChoice attempt above is the whole story
    // (a denied mid-round late spawn deliberately stays denied — e.g. team wiped / overtime).
    for ( i = 0; i < 20; i++ )
    {
        wait 0.05;
        if ( !( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod ) )
            return;
        if ( self.sessionstate == "playing" && self.health > 0 )
            return;                            // respawned cleanly — done
        self.pers["lives"] = level.numLives;
        if ( self.sessionstate != "playing" && game["state"] == "playing"
             && maps\mp\gametypes\_globallogic_utils::isValidClass( self.class ) )
            self thread [[level.spawnClient]]();
    }
}

// ─── Player-driven team choice (level.allies/axis/spectator wrappers) ──────
// Installed every round in gf.gsc onStartGameType next to the autoassign override (SetupCallbacks
// has just reset the stock handlers, so the saved level.gf_stock* capture REAL stock — no
// recursion). Bots and the democlient pass straight through to stock. For humans these own the
// three things stock can't express: the rcon switch kill-switch (gf_team_switch 0), the team-size
// lock (gf_team_lock: a side already holding gf_fill_n humans refuses the join; locked out of BOTH
// sides queues you, join-order, for the next open seat — the boundary reconciler seats the queue),
// and SAFE immediate switching via gf_seqTeamMove (an ALIVE mid-round switcher dies and sits out
// the round; during the prematch/grace warmup the move is free).
gf_menuAllies()    { self gf_menuTeamChoice( "allies" );    }
gf_menuAxis()      { self gf_menuTeamChoice( "axis" );      }
gf_menuSpectator() { self gf_menuTeamChoice( "spectator" ); }

gf_menuTeamChoice( team )
{
    stockFn = level.gf_stockSpectator;
    if ( team == "allies" )
        stockFn = level.gf_stockAllies;
    else if ( team == "axis" )
        stockFn = level.gf_stockAxis;

    if ( self istestclient() || self isdemoclient() )
    {
        self [[stockFn]]();
        return;
    }

    // Fully qualified: closeMenus is a _globallogic_ui helper, NOT a builtin, and this file does not
    // #include that script (T5 has no transitive includes) — a bare call is an unknown function.
    // Same style as the updateObjectiveText / beginClassChoice / preventTeamSwitchExploit calls above.
    self maps\mp\gametypes\_globallogic_ui::closeMenus();

    if ( isDefined( self.pers["team"] ) && self.pers["team"] == team )
    {
        self [[stockFn]]();                    // same team: stock just re-opens class choice
        return;
    }

    // Stock's own join gate, kept (native-first): it honors g_allow_spectator and an admin's
    // g_allow_teamchange 0. Fully qualified — canJoinTeam is a _globallogic_ui helper, not a builtin.
    // ⚠ Its FOURTH check (level.teamchange_keepbalanced) is a SECOND balance policy that would refuse
    // any join putting a team 2+ ahead — which contradicts this mod's rule that team choice is free
    // and the round-boundary balancer corrects it. gf.gsc zeroes that flag every round so GF's
    // balancer is the single owner; see the note there before re-enabling it.
    if ( !self maps\mp\gametypes\_globallogic_ui::canJoinTeam( team ) )
    {
        self iprintln( &"PATCH_MP_CANNOT_JOIN_TEAM" );
        return;
    }

    if ( team != "spectator" )
    {
        // rcon kill-switch: players stay put (admin pteam/pteamforce route around these wrappers)
        if ( getDvarInt( "gf_team_switch" ) == 0 )
        {
            self iprintln( "^3Team switching is disabled on this server" );
            return;
        }
        if ( gf_teamLockDenies( self, team ) )
        {
            other = "axis";
            if ( team == "axis" )
                other = "allies";
            if ( gf_teamLockDenies( self, other ) )
            {
                self gf_lockQueueMark();
                self iprintln( "^3Teams are full - you are queued for the next open seat" );
            }
            else
                self iprintln( "^3That team is full" );
            return;
        }
    }

    self.pers["gf_seatQueued"] = undefined;    // moving under their own power clears any queued mark

    // Breadcrumb for the GF_TEAMWATCH boundary diagnostic (_bot::gf_teamWatchHumans): tag an
    // INTENTIONAL spectate so the log can tell a human who chose spectator from one the untraced
    // mis-seater stranded there ("took a bot's spot, then next round forced to pick a team").
    if ( team == "spectator" )
        self.pers["gf_specReason"] = "user";

    if ( self.sessionstate == "playing" )
    {
        // Alive: sequenced switch. Free during the prematch/grace warmup (life restored +
        // respawned); mid-round it costs the round — die, sit out, spawn next round.
        restore = ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
                  || ( isDefined( level.inGracePeriod ) && level.inGracePeriod );
        self thread gf_seqTeamMove( team, restore );
        return;
    }

    // Dead or spectating: quiet seat now. A spectator joining a live round still holds their
    // life, so the spawn attempt late-spawns them in (maySpawn admits while their team has >=1
    // alive and it isn't overtime); a dead player seats for the next round.
    if ( team == "spectator" )
    {
        self gf_quietSetTeam( "spectator" );
        self maps\mp\gametypes\_globallogic_ui::updateObjectiveText();
        self setclientdvar( "g_scriptMainMenu", game["menu_team"] );
        self [[level.spawnSpectator]]();
        self notify( "joined_spectators" );
        return;
    }
    self setclientdvar( "g_scriptMainMenu", game["menu_class_" + team] );
    self gf_seatJoinTeam( team );
}

// ─── Team-size lock helpers ─────────────────────────────────────────────────
// gf_fill_n is the per-team TARGET size; gf_team_lock 1 makes it a hard HUMAN cap: a side already
// holding that many humans refuses new humans (they spectate, queued in join order, and the
// boundary reconciler auto-seats them the moment a seat opens). Bots never count against the lock
// (a joining human always displaces a bot instead of spectating). Lock is inert at gf_fill_n 0.

gf_teamTargetSize()
{
    n = getDvarInt( "gf_fill_n" );
    if ( n < 0 ) n = 0;
    if ( n > 6 ) n = 6;
    return n;
}

gf_teamLockOn()
{
    return ( getDvarInt( "gf_team_lock" ) == 1 && gf_teamTargetSize() > 0 );
}

// Humans currently seated on `team`, excluding `exclude` (pass undefined to count everyone).
gf_countTeamHumans( team, exclude )
{
    count = 0;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) || p istestclient() || p isdemoclient() )
            continue;
        if ( isDefined( exclude ) && p == exclude )
            continue;
        if ( isDefined( p.pers["team"] ) && p.pers["team"] == team )
            count++;
    }
    return count;
}

gf_teamLockDenies( who, team )
{
    if ( !gf_teamLockOn() )
        return false;
    return ( gf_countTeamHumans( team, who ) >= gf_teamTargetSize() );
}

// Monotonic per-match join sequence (game[] survives map_restart(true); the lobby's false-restart
// wipes it, and everyone re-stamps in reconnect order — acceptable drift). "Most recent joiner"
// balance picks and the lock queue's seat order both key off this.
gf_joinSeqOf()
{
    if ( !isDefined( self.pers["gf_joinSeq"] ) )
    {
        if ( !isDefined( game["gf_joinSeq"] ) )
            game["gf_joinSeq"] = 0;
        game["gf_joinSeq"]++;
        self.pers["gf_joinSeq"] = game["gf_joinSeq"];
    }
    return self.pers["gf_joinSeq"];
}

// Queue a human locked out of both sides. The boundary reconciler seats queued players in join
// order whenever lock capacity opens; the mark clears when they get seated (or pick a team/
// spectator themselves).
gf_lockQueueMark()
{
    if ( !isDefined( self.pers["gf_seatQueued"] ) )
        self.pers["gf_seatQueued"] = self gf_joinSeqOf();
}
// #strip-end

// True while any load-gate-tracked HUMAN still has the connecting statusicon
// (i.e. is on its loading screen). Reads the frozen level.gf_loadGateSeen
// snapshot the tracker built — the snapshot persists after gf_load_gate_reset
// retires the tracker, and each entity's statusicon updates live (the engine
// clears it on "begin"), so this reflects real-time load status. Undefined
// array (rounds 2+, where map_restart wiped it) => false, so the grace hold is
// inherently round-1-only. A client that disconnects mid-load goes undefined and
// is skipped, so it can never wedge the hold.
gf_anyTrackedClientLoading()
{
    if ( !isDefined( level.gf_loadGateSeen ) )
        return false;
    for ( i = 0; i < level.gf_loadGateSeen.size; i++ )
    {
        p = level.gf_loadGateSeen[i];
        if ( !isDefined( p ) )
            continue;
        if ( p istestclient() || p isdemoclient() )   // bots + demo clients: never hold grace for them
            continue;
        if ( isDefined( p.statusicon ) && p.statusicon == "hud_status_connecting" )
            return true;
    }
    return false;
}

// #strip-begin - PREGAME LOBBY PRESENTATION (dev/main only; stripped from public release)
// The lobby camera, its live roster/icon HUD, the map-name table, and the lobby HUD blanker. All of
// it is driven from gf_waitForLoadingClients (stripped above), so the public build reaches none of
// it. Ends just before the team-size mode section.
//
// ─── Lobby camera (Auto/Manual pregame lobby) ──────────────────────────────
// During the Auto/Manual pregame hold, float every begun HUMAN in the INTERMISSION camera — the fixed
// map-overview the engine uses at match end — so the lobby reads as a real staging screen instead of
// players frozen at their gunfight spawns. Started (restartMode only) from gf_waitForLoadingClients
// right after level.gf_inLobbyHold=true; retires with the hold via the same notifies the load tracker
// uses. Teardown is FREE: the map_restart(false) on release wipes level/pers/entity state and
// re-spawns everyone fresh into the match, so we never un-apply the cam. Mechanism: spawnIntermission
// -> sessionstate "intermission" at mp_global_intermission, follows NOBODY (no "SPECTATING <name>"
// overlay, unlike the spectator variants which stay an active spectate + draw the panel/minimap). It
// auto-shows the scoreboard, which we EMBRACE as the live lobby roster and wrap with the custom HUD.
// See gf_lobbyCamPut. Only ever acts on fully-begun players (a still-loading client is never
// spawn-ready — we poll spawned players, never "connecting").
gf_lobbyCamWatcher()
{
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    // The orbit cam hard-requires an mp_global_intermission entity (every stock MP map ships one;
    // a custom map lacking it makes no-origin spawnSpectator assert inside default_onSpawnSpectator).
    // If absent, skip the cam entirely — players just stay in the stock frozen-in-world lobby.
    if ( getEntArray( "mp_global_intermission", "classname" ).size == 0 )
        return;

    // Poll every begun player into the cam each tick. gf_lobbyCamPut is once-per-player
    // (self.gf_inLobbyCam) and skips still-unspawned clients / bots, so re-sweeping is a cheap
    // no-op after the first pass. We POLL rather than key off "spawned_player" because that
    // notify carries no entity (gf_playerSpawnedCB fires a bare `level notify`), so a listener
    // couldn't identify who spawned — the bridge's pending-team watcher re-sweeps for the same
    // reason. Polling reliably catches everyone, incl. a late loader who begins mid-hold.
    while ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold )
    {
        for ( i = 0; i < level.players.size; i++ )
            level.players[i] thread gf_lobbyCamPut();
        wait 0.25;
    }
}

// Move ONE begun player into the intermission overview cam + keep the lobby clean (no team menu, no HUD).
gf_lobbyCamPut()
{
    self endon( "disconnect" );

    if ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold )   // hold already released
        return;
    if ( self istestclient() || self isdemoclient() )                    // bots + demo clients stay put
        return;

    // CRITICAL: everything below runs ONCE per player (guarded by self.gf_inLobbyCam). It must NOT run
    // every watcher tick. setClientDvar is a reliable server command; re-pushing the HUD-hide (4 dvars)
    // + the content block every 0.25s to every player piled up reliable commands faster than a just-
    // connecting client could ack, overflowing its buffer -> "server command overflow" + disconnect on a
    // first-time join. Once is enough: the pure-spectator lobby never spawns anyone, so nothing re-shows
    // the gunfight HUD or moves the cam mid-hold. The team-select menu is prevented at the source
    // (level.forceAutoAssign at the hold start), so there's no per-tick menu-swat to do here either.
    if ( isDefined( self.gf_inLobbyCam ) && self.gf_inLobbyCam )          // once per player
        return;
    self.gf_inLobbyCam = true;

    // Hide any stale gunfight HUD once on lobby entry (a reconnect could carry ui_gf_panel_show=1 etc.).
    self gf_hideLobbyHUD();

    // Hide the minimap/compass for a clean lobby (stock HUD-hide path uses this exact dvar,
    // _utility.gsc:8414). Client dvar, so restored at the hold release (loop below). CAVEAT: `compass`
    // may be a saved dvar Plutonium blocks servers from writing on a dedicated server — works on a
    // listen server; verify on the VPS (same class as the gf_vis_* r_* tweaks).
    self setClientDvar( "compass", "0" );

    // Vision (desaturation) is LEVEL-scope only in T5 MP — visionSetNaked has no per-player self-method
    // form (it's applied bare at the hold start in gf_waitForLoadingClients), so there's nothing to
    // re-apply per client here.

    // FREE-LOOK SPECTATOR camera — sessionstate "spectator", which (unlike intermission) keeps the HUD
    // layer ON, so our custom lobby HUD menuDef actually renders. Intermission was tried and abandoned:
    // it force-shows the scoreboard and HARD-hides the entire HUD layer client-side (hud_visible can't
    // be held on), so no custom HUD can live there. A no-origin spawnSpectator drops the player at a
    // random mp_global_intermission point (a map overview); we then disable team-follow + force freelook
    // so the engine doesn't auto-attach to a teammate (that auto-follow is the "SPECTATING <name>"
    // overlay). The stock minimap + spectator messages are suppressed separately (compass 0 +
    // cg_drawSpectatorMessages 0); the roster is our own menu list, not the engine scoreboard.
    self [[level.spawnSpectator]]();
    self allowSpectateTeam( "allies",   false );
    self allowSpectateTeam( "axis",     false );
    self allowSpectateTeam( "freelook", true  );
    self allowSpectateTeam( "none",     true  );
    self.spectatorclient = -1;   // force FREE-LOOK, not following any player. allowSpectateTeam only
                                 // gates manual cycling, not the initial auto-attach — the engine still
                                 // latched onto KL9 ("SPECTATING KL9" + that player's minimap). -1 breaks
                                 // the follow and drops the view to the free intermission-point overview.

    // Push the custom lobby HUD content (menu-rendered by the "gf_lobby_hud" menuDef in
    // hud_gf_health.menu, gated on ui_gf_lobby_show). That menuDef is intentionally NOT gated on
    // BIT_HUD_VISIBLE (the engine clears it entering intermission), so ui_gf_lobby_show is the sole
    // gate. Welcome is per-player; map/status are the same for everyone but must go via setClientDvar
    // (a dedicated server's setDvar doesn't replicate). Rules + ad copy are static text in the menu.
    // Static header — every branding line is pushed in FULL (the typewriter reveal was removed).
    statusText = "The match will begin shortly";
    if ( int( gf_cfgFloat( "scr_gf_lobby", 0, 0, 2 ) ) == 2 )
        statusText = "Waiting for the host to start";

    // Batched: two reliable commands, not ten (see _gf_hud.gsc::gf_showWeaponHUD). ui_gf_lobby_show
    // stays LAST so the menuDef is only revealed once every field behind it is populated.
    // lobby_icon seeds a valid material before the icon items show.
    self setClientDvars( "ui_gf_lobby_eyebrow", "PREGAME LOBBY",
                         "ui_gf_lobby_title",   "GUNFIGHT",
                         "ui_gf_lobby_map",     gf_mapDisplayName( getDvar( "mapname" ) ),
                         "ui_gf_lobby_welcome", "Welcome, " + self.name,
                         "ui_gf_lobby_status",  statusText,
                         "ui_gf_lobby_icon",    "menu_mp_weapons_famas" );

    // icon_on: the header is instant now, so reveal the flanking icons immediately.
    // ic_home / ic_disc: ad-rail emblems (14th/15th-prestige badges — faction crests aren't
    // loaded on every map). lobby_show: reveal the fully-populated menuDef.
    self setClientDvars( "ui_gf_lobby_icon_on", "1",
                         "ui_gf_lobby_ic_home", "rank_prestige14",
                         "ui_gf_lobby_ic_disc", "rank_prestige15",
                         "ui_gf_lobby_show",    "1" );
}

// ─── Lobby roster ("IN THE LOBBY" name list) ───────────────────────────────
// Live combined player+bot list for the custom lobby HUD. Level-scope; runs for the Auto/Manual hold
// only (started from gf_waitForLoadingClients alongside gf_lobbyCamWatcher). Rebuilds the roster each
// tick and pushes it — ONLY on change, and BATCHED (setClientDvarS) — to every begun human (menus read
// CLIENT dvars, and a dedicated server's setDvar doesn't replicate). 12 fixed name slots
// (ui_gf_lobby_p0..11) + a count (ui_gf_lobby_pcount) that gates each slot's menu visibility. Retires
// with the hold via the same notifies the load tracker / cam watcher use. Still-connecting + demo
// clients are excluded; bots are listed with a "(bot)" tag per the combined-list design.
gf_lobbyRosterLoop()
{
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    lastSig = "___init___";
    while ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold )
    {
        names = [];
        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( !isDefined( p ) )
                continue;
            if ( p isdemoclient() )
                continue;
            if ( isDefined( p.statusicon ) && p.statusicon == "hud_status_connecting" )
                continue;   // still loading — not standing in the lobby yet
            nm = p.name;
            if ( p istestclient() )
                nm = nm + "  (bot)";
            names[ names.size ] = nm;
        }

        // Push only when the roster actually changes (a join/leave/rename) so a static lobby pushes
        // nothing at all. The change gate is the FIRST line of defence on reliable-command volume;
        // the batching below is the second.
        sig = "" + names.size;
        for ( i = 0; i < names.size; i++ )
            sig = sig + "|" + names[i];

        if ( sig != lastSig )
        {
            lastSig = sig;

            // ⚠ BATCHED ON PURPOSE — setClientDvarS (plural). This loop used to push pcount + one
            // command PER OCCUPIED SLOT (up to 13 reliable commands per human, per roster change),
            // which made it the only push stream in the mod whose COST SCALES WITH PLAYER COUNT —
            // and it lives in the pregame lobby, the exact window where the reliable-command ring is
            // already tightest (the Auto/Manual START does map_restart(false), which stalls every
            // client while the burst keeps queueing). Bots are added on a 0.5s stagger and this loop
            // ticks at 0.5s, so a full bot fill was ~one roster change per bot: a 12-bot fill cost
            // ~156 reliable commands per human. Batched, the same fill costs ~12-24.
            //
            // Re-sending an unchanged pair inside a batch is FREE — it is the command COUNT that is
            // scarce, not the bytes — so we pad the 12 fixed slots and push them as flat groups
            // rather than tailoring the call to the occupied count. Slots past pcount are hidden by
            // the menu (each row is gated on pcount > N), so the padding is never seen.
            // See the batching note in _gf_hud.gsc::gf_showWeaponHUD.
            slot = [];
            for ( s = 0; s < 12; s++ )
            {
                if ( s < names.size )
                    slot[s] = names[s];
                else
                    slot[s] = "";
            }

            for ( i = 0; i < level.players.size; i++ )
            {
                pl = level.players[i];
                if ( !isDefined( pl ) || pl istestclient() || pl isdemoclient() )
                    continue;   // bots/demo render no HUD — don't push to them

                pl setClientDvars( "ui_gf_lobby_pcount", "" + names.size,
                                   "ui_gf_lobby_p0",     slot[0],
                                   "ui_gf_lobby_p1",     slot[1],
                                   "ui_gf_lobby_p2",     slot[2],
                                   "ui_gf_lobby_p3",     slot[3],
                                   "ui_gf_lobby_p4",     slot[4],
                                   "ui_gf_lobby_p5",     slot[5] );

                // Slots 6-11 only exist for a 7+ lobby. Below that the menu has them hidden anyway
                // (pcount gate), so skipping the second command keeps the common small lobby at ONE.
                if ( names.size > 6 )
                    pl setClientDvars( "ui_gf_lobby_p6",  slot[6],
                                       "ui_gf_lobby_p7",  slot[7],
                                       "ui_gf_lobby_p8",  slot[8],
                                       "ui_gf_lobby_p9",  slot[9],
                                       "ui_gf_lobby_p10", slot[10],
                                       "ui_gf_lobby_p11", slot[11] );
            }
        }

        wait 0.5;
    }
}

// ─── Lobby flanking weapon icons ───────────────────────────────────────────
// Cycles the pair of weapon icons flanking the GUNFIGHT title through the arsenal, in sync for
// every viewer (one shared client dvar, pushed to all begun humans each step). Shader names are the
// VERIFIED menu_mp_weapons_* set the loadout overview already renders (incl. the two odd bases:
// colt = M1911, stoner63a = Stoner63). Level-scope; started with the roster loop for the Auto/Manual
// hold only; retires with the hold via the same notifies. The first icon is seeded in gf_lobbyCamPut
// (before the menuDef reveals), and the items stay hidden until the typewriter finishes the title
// (ui_gf_lobby_icon_on).
gf_lobbyIconCycler()
{
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    icons = [];
    icons[icons.size] = "menu_mp_weapons_famas";
    icons[icons.size] = "menu_mp_weapons_python";
    icons[icons.size] = "menu_mp_weapons_spas";
    icons[icons.size] = "menu_mp_weapons_l96a1";
    icons[icons.size] = "menu_mp_weapons_ak47";
    icons[icons.size] = "menu_mp_weapons_mp5k";
    icons[icons.size] = "menu_mp_weapons_crossbow";
    icons[icons.size] = "menu_mp_weapons_m60";
    icons[icons.size] = "menu_mp_weapons_m16";
    icons[icons.size] = "menu_mp_weapons_ak74u";
    icons[icons.size] = "menu_mp_weapons_ithaca";
    icons[icons.size] = "menu_mp_weapons_dragunov";
    icons[icons.size] = "menu_mp_weapons_galil";
    icons[icons.size] = "menu_mp_weapons_uzi";
    icons[icons.size] = "menu_mp_weapons_rpk";
    icons[icons.size] = "menu_mp_weapons_colt";
    icons[icons.size] = "menu_mp_weapons_aug";
    icons[icons.size] = "menu_mp_weapons_spectre";
    icons[icons.size] = "menu_mp_weapons_wa2000";
    icons[icons.size] = "menu_mp_weapons_commando";
    icons[icons.size] = "menu_mp_weapons_hk21";
    icons[icons.size] = "menu_mp_weapons_cz75";
    icons[icons.size] = "menu_mp_weapons_g11";
    icons[icons.size] = "menu_mp_weapons_rottweil72";
    icons[icons.size] = "menu_mp_weapons_fnfal";
    icons[icons.size] = "menu_mp_weapons_stoner63a";

    idx = 0;   // seeded value (famas) is icons[0] — first advance shows icons[1]
    while ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold )
    {
        wait 1.2;
        idx++;
        if ( idx >= icons.size )
            idx = 0;

        for ( i = 0; i < level.players.size; i++ )
        {
            pl = level.players[i];
            if ( !isDefined( pl ) || pl istestclient() || pl isdemoclient() )
                continue;   // bots/demo render no HUD — don't push to them
            pl setClientDvar( "ui_gf_lobby_icon", icons[idx] );
        }
    }
}

// mp_ map code -> the map's display name (user-supplied table). Falls back to the raw code for any
// map not listed (e.g. a custom map), so an unknown map shows its code rather than nothing.
gf_mapDisplayName( code )
{
    if ( code == "mp_array" )       return "Array";
    if ( code == "mp_cairo" )       return "Havana";
    if ( code == "mp_cosmodrome" )  return "Launch";
    if ( code == "mp_cracked" )     return "Cracked";
    if ( code == "mp_crisis" )      return "Crisis";
    if ( code == "mp_duga" )        return "Grid";
    if ( code == "mp_firingrange" ) return "Firing Range";
    if ( code == "mp_hanoi" )       return "Hanoi";
    if ( code == "mp_havoc" )       return "Jungle";
    if ( code == "mp_mountain" )    return "Summit";
    if ( code == "mp_nuked" )       return "Nuketown";
    if ( code == "mp_radiation" )   return "Radiation";
    if ( code == "mp_russianbase" ) return "WMD";
    if ( code == "mp_villa" )       return "Villa";
    if ( code == "mp_berlinwall2" ) return "Berlin Wall";
    if ( code == "mp_discovery" )   return "Discovery";
    if ( code == "mp_kowloon" )     return "Kowloon";
    if ( code == "mp_stadium" )     return "Stadium";
    if ( code == "mp_gridlock" )    return "Convoy";
    if ( code == "mp_hotel" )       return "Hotel";
    if ( code == "mp_outskirts" )   return "Stockpile";
    if ( code == "mp_zoo" )         return "Zoo";
    if ( code == "mp_drivein" )     return "Drive-In";
    if ( code == "mp_area51" )      return "Hangar 18";
    if ( code == "mp_golfcourse" )  return "Hazard";
    return code;
}

// Hide the whole gunfight HUD for this player during the lobby (menu-driven; 0 = hidden). No
// teardown needed — the normal spawn flow re-raises these show gates on the next real spawn after
// map_restart(false). Loadout overview / team health panel / self bar / kill popup.
gf_hideLobbyHUD()
{
    self setClientDvars( "ui_gf_lo_show",    "0",
                         "ui_gf_panel_show", "0",
                         "ui_gf_self_show",  "0",
                         "ui_gf_popup_show", "0" );
}
// #strip-end

// ─── Team-Size Spawn/Barrier Mode ──────────────────────────────────────────
// Resolves "large" (full-map TDM spawns, wager barriers deleted, OT flag at the
// Domination B flag) vs "small" (curated gunfight spawns + wager barriers).
// Re-evaluated every round from onStartGameType, which map_restart re-fires, so
// the result lives in level.* (wiped per round). The spawn/allow-list/wager
// branches in onStartGameType and onSpawnPlayer/gf_getOvertimeFlagTrigger all
// read level.gf_largeMode.
//
// scr_<gametype>_teamspawnmode: auto (default) | large | small. "auto" goes
// large once 9 or more HUMANS are seated on teams (i.e. a 5v4 human split or
// bigger) -- bots NEVER trigger it, so a bot-padded 6v6 stays on the tight
// curated spawns while a genuinely big human lobby opens up to the full map.
// A forced large/small pins the mode for admins/RCON/testing. (The old
// per-team>4 body-count trigger -- which coupled the spawn mode to the health
// panel's skull cap and let bot fill flip the map open -- is RETIRED; the HUD's
// skulls-vs-"Alive: N" readout still switches on per-team body count > 4, in
// _gf_hud, but that is now a pure HUD decision. The old total-count dvar
// scr_gf_largemode_minplayers stays retired/inert.)
//
// onStartGameType (where this runs) snapshots the roster BEFORE bots/late
// joiners connect — _bot::init() is threaded at the end of onStartGameType — so
// a live count here is unreliable. auto therefore prefers game["gf_autoLargeMode"],
// captured at round activation by gf_updateAutoTeamMode() once everyone has
// spawned, and persisted through map_restart in game[]. The live count is only a
// first-setup fallback (e.g. a populated server where players are already
// connected at map load).
gf_resolveTeamMode()
{
    dvar = "scr_" + level.gameType + "_teamspawnmode";
    mode = GetDvar( dvar );
    if ( mode != "auto" && mode != "large" && mode != "small" )
    {
        mode = "auto";
        setDvar( dvar, mode );
    }

    if ( mode == "large" )
    {
        level.gf_largeMode = true;
        return;
    }
    if ( mode == "small" )
    {
        level.gf_largeMode = false;
        return;
    }

    if ( isDefined( game["gf_autoLargeMode"] ) )
    {
        level.gf_largeMode = game["gf_autoLargeMode"];
        return;
    }

    // First-setup fallback only (e.g. a populated server where players are already connected
    // at map load); once a round activates, gf_updateAutoTeamMode persists the decision in game[].
    level.gf_largeMode = gf_autoLargeFromHumans( gf_countSeatedHumans() );
}

// Captures the live HUMAN count once the round is active and everyone has spawned,
// persisting the auto decision in game[] for the next round's onStartGameType setup.
// No-op when the mode is force-pinned.
gf_updateAutoTeamMode()
{
    if ( GetDvar( "scr_" + level.gameType + "_teamspawnmode" ) != "auto" )
        return;

    game["gf_autoLargeMode"] = gf_autoLargeFromHumans( gf_countSeatedHumans() );
}

// HUMANS seated on a real team (spectators don't play, bots don't count). The demo client is
// neither a human nor a bot (istestclient() false!) — exclude it explicitly.
gf_countSeatedHumans()
{
    count = 0;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) || p istestclient() || p isdemoclient() )
            continue;
        if ( !isDefined( p.pers["team"] ) )
            continue;
        if ( p.pers["team"] == "allies" || p.pers["team"] == "axis" )
            count++;
    }
    return count;
}

// Auto-mode large/small: large once 9+ HUMANS are seated (a 5v4 human split or more). Humans
// only, by design — bots pad team SIZE, and a bot-padded 6v6 should keep the tight curated
// wager spawns; only a genuinely large human lobby opens the map up. (The HUD's skulls-vs-
// "Alive: N" readout is a separate, per-team BODY-count decision in _gf_hud — the two no
// longer share a switch point.)
//
// TIMING CAVEAT (unchanged): spawn mode is decided once per round and applied the NEXT round
// (persisted in game["gf_autoLargeMode"], snapshot at round activation -- a live count is
// unreliable inside onStartGameType because bots/late joiners connect after it). So the 9th
// human's join shows up in the spawns one round later. Self-corrects the following round.
gf_autoLargeFromHumans( seatedHumans )
{
    return ( seatedHumans >= 9 );
}

// ─── Player Lifecycle ──────────────────────────────────────────────────────

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );

    // Late-joiner / reconnect backstop: force the lobby HUD off for anyone spawning into the LIVE match.
    // The pregame lobby is pure-spectator (nobody spawns during it), so reaching here is always a real
    // match spawn — clear any stale ui_gf_lobby_show=1 a reconnecting client carried in. gf_onSpawnSpectator
    // already covers the pre-first-spawn spectate window; this catches the spawn path itself. One dvar,
    // humans only, gated !inLobbyHold (spawns are infrequent — no overflow concern).
    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        && ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold ) )
        self setClientDvar( "ui_gf_lobby_show", "0" );

    // Silence the stock "+N" XP popups. _rank::giveRankXP pushes them onto the SAME
    // element our Elimination/Assist popup reuses (self.hud_rankscroreupdate), gated
    // only by self.enableText — the stock per-player "XP text" preference, re-set true
    // by _persistence on every connect (so every map_restart), hence per-spawn here.
    // This is the ONLY thing suppressing them: kill/headshot/assist XP is 5x stock
    // (gf.gsc registerScoreInfo), and medals, challenges and stat milestones pass
    // EXPLICIT XP values anyway. XP itself still accrues (incRankXP runs before the
    // gate); only the engine's popup text is suppressed.
    self.enableText = false;

    // NOTE: the CLIENT half of this toggle used to be pushed here every spawn
    // (`self setClientDvar( "ui_xpText", "0" )`). REMOVED 2026-07-05 — ui_xpText is a
    // stock SAVED dvar, and Plutonium blocks servers from writing saved dvars to
    // clients. It was redundant anyway: self.enableText = false (above) plus the
    // element-level park below are the decisive suppression, so dropping the client
    // push costs nothing.

    // Element-level backstop: park the stock rank-score element offscreen so any
    // stock "+N" that slips past the gates renders invisibly. No stock writer
    // ever re-sets x/y after creation. Humans only — bots draw no HUD.
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self thread gf_parkStockScorePopup();

    // One-time welcome splash, once per CONNECTION (pers[] resets on disconnect,
    // so a rejoiner is greeted again; the between-round map_restart is not a
    // re-greet). Humans only — bots draw no HUD and their names would burn
    // setText configstrings for nothing.
    // Held off during the pregame lobby hold so it fires once — on the match's fresh-start spawn
    // (map_restart(false) wipes pers, so gf_welcomed re-clears) — instead of flashing in the lobby
    // AND again in the match. The lobby's own ads/info will live in the dedicated lobby HUD.
    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        && !isDefined( self.pers["gf_welcomed"] )
        && ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold ) )
    {
        self.pers["gf_welcomed"] = true;
        self thread gf_welcomeMessage();
    }

    // If scr_team_maxsize > 0, redirect to spectator when the team is already full.
    // The notify above still fires so SD and round logic don't stall.
    maxTeam = getDvarInt( "scr_team_maxsize" );
    if ( maxTeam > 0 )
    {
        team = self.pers["team"];
        if ( team == "allies" || team == "axis" )
        {
            count = 0;
            players = level.players;
            for ( i = 0; i < players.size; i++ )
            {
                if ( players[i] == self ) continue;
                if ( players[i].pers["team"] == team ) count++;
            }
            if ( count >= maxTeam )
            {
                self.pers["team"] = "spectator";
                self [[level.spawnSpectator]]( self.origin, self.angles );
                return;
            }
        }
    }

    self gf_syncCaptureScore();
    self gf_initDamageScore();

    // Mark that this player actually spawned into the current round, so the team-health
    // stats only count real participants. A mid-round joiner is team-assigned but never
    // spawns this round (they spectate) — without this they'd inflate the team's max
    // health and shrink the bar even though they contribute no current health.
    self.pers["gf_spawnedRound"] = game["roundsplayed"];

    // Level-side stats publisher — start once per round; the player panels read its output.
    // Skipped during the pregame lobby hold (no panels are shown then, and it would leave an orphaned
    // update loop across the map_restart(false) release); the match's first spawn starts it fresh.
    if ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold )
    {
        if ( !isDefined( level.gf_healthHudStartRound ) || level.gf_healthHudStartRound != game["roundsplayed"] )
        {
            level.gf_healthHudStartRound = game["roundsplayed"];
            level thread gf_startHealthHUD();
        }
        gf_queueHealthHUDUpdate();
    }
    // Video tweaks: STOCK by default — nothing is pushed unless a gf_vis_* dvar has
    // been set (the RCON Visuals sliders persist into them via the bridge), so
    // players keep their own video settings out of the box. Replaces the old
    // scr_gf_visualtweaks force-push (hardcoded r_gamma 1.1 etc. every spawn):
    // r_gamma is a SAVED client dvar Plutonium blocks servers from writing.
    // Humans only — bots have no renderer.
    // Flinch rides along here for the same reason the vis tweaks do: bg_viewKickScale
    // is client-scaled and unreplicated, so a joiner needs it pushed on spawn. Unlimited
    // sprint (player_sprintUnlimited) is the same story — see gf_applySprintUnlimited.
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
    {
        // #strip-begin - RCON gf_vis_* r_* push (dev/main only; the public build never touches client video dvars)
        self gf_applyVisTweaks();
        // #strip-end
        self gf_applyFlinchClient();
        self gf_applySprintUnlimitedClient();

        // Start this player's ambient bed at the round start rather than at spawn+15 — see
        // gf_initRoundMusic. Humans only: a bot has no client to push a music state to. Must be
        // armed from here (playerSpawnedCB), not onSpawnPlayer, because the engine calls only ONE
        // of onSpawnPlayer/onSpawnPlayerUnified (_globallogic_spawn.gsc:157-165) but always calls
        // this one — and because it still runs before stock latches pers["music"].spawn.
        self gf_armRoundUnderscore();
    }
    self thread gf_onSpawned();

    // Drive the entire per-player health panel in the PLAYER's own context (create +
    // update + destroy) — T5 client HUD elements don't network if created from a level
    // thread. Mirrors the loadout HUD pattern. Suppressed during the RESTART lobby hold
    // (the panel would flash in on the throwaway frozen spawn then get hidden by the lobby
    // cam move). Gated on the RESTART hold (not gf_inLobbyHold) for the same reason
    // gf_giveCustomLoadout is: a non-restart Normal-mode hold frozen-spawns players whose
    // spawn IS the match spawn and is never rebuilt, so keying off the broad flag left
    // anyone who loaded in during the load/min gate with no panel for all of round 1.
    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        && ( !isDefined( level.gf_lobbyRestartHold ) || !level.gf_lobbyRestartHold ) )
        self thread gf_runHealthHUD();

    // #strip-begin - spawn recorder + HUD-pool overlays (dev/main only; stripped from public release)
    if ( getDvarInt( "gf_debug_spawns" ) == 1 )
        self thread gf_startSpawnRecorder();

    if ( getDvarInt( "gf_debug_hud_pool" ) == 1 )
    {
        if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
            self thread gf_startHUDPoolOverlay();
    }

    // One-shot ALLOCATION sanity check — prints "ALLOC free: N" ~9s after spawn. Measures the
    // allocation pool only (huge); the real per-player DRAWN cap (~17) shows on the pool overlay.
    if ( getDvarInt( "gf_debug_elem_probe" ) == 1 )
    {
        if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
            self thread gf_debugElemProbe();
    }
    // #strip-end
}


// ─── Round vision (Gunfight's default look) ────────────────────────────────
// Gunfight ships a vision set as its DEFAULT: "enhance" (the engine's "default_night" set —
// saturation 1, contrast 1.2), the contrast pop the mod is meant to look like. This is core, not an
// admin tweak, so it lives here (shipped) rather than in the bridge, and every build gets it.
//
// It CANNOT be applied from onStartGameType: the stock prematch flow stomps vision AFTERWARDS —
// matchStartTimer forces "mpIntro" for the countdown and at T-2s blends back to the MAP vision over
// 3s (_globallogic.gsc:398/424). So we wait for prematch_over and take over the tail of that blend
// (a newer visionSetNaked call retargets the in-progress lerp). The 3.0s transition mirrors the
// stock blend it replaces, so the reveal reads as native rather than as a snap.
//
// visionSetNaked is a BARE builtin in the MP VM (level-global, all clients) — the self-method form
// throws unknown-function ([[vector-scale-in-common-scripts-utility]]).
//
// ⚠ Vision is LEVEL state, so the between-round map_restart resets it to the map default and this
// has to re-run every round. Called from onStartGameType.
gf_initRoundVision()
{
    level.gf_defaultVision = getDvar( "mapname" );   // the map's OWN vision set — what "normal" means
    level thread gf_applyRoundVision();
}

gf_applyRoundVision()
{
    level endon( "game_ended" );

    level waittill( "prematch_over" );

    visionSetNaked( gf_visionSetForKey( gf_roundVisionKey() ), 3.0 );
}

// ─── Round Ambient Music (the UNDERSCORE bed) ──────────────────────────────

// The round's ambient bed is stock's UNDERSCORE music state (sound alias mus_underscore ->
// mus\mp\underscores\*). Stock starts it from sndStartMusicSystem (_globallogic_spawn.gsc:739),
// threaded on each player's FIRST spawn of the round (:97, gated on !hasSpawned — which
// Callback_PlayerConnect re-clears on every map_restart, so it re-arms EVERY round). All it does is
// a bare `wait 15` -> UNDERSCORE.
//
// That 15s is anchored to the SPAWN, and the spawn happens at the START of the prematch countdown,
// so the bed never actually lands on the round:
//   - rounds 2+ (7s countdown):  spawn at T-7  -> bed at T+8, i.e. 8s INTO a 42s round, with the
//     opening fight running under nothing once ROUND_END's jingle has gone.
//   - round 1   (20s countdown): spawn at T-20 -> bed at T-5, i.e. 5s BEFORE the round starts.
//
// We own it instead, with ONE per-player rule:
//
//     the bed starts at   max( prematch_over, own_spawn + cue_floor )
//
// where cue_floor is the room that player's own spawn cue needs. That single rule gives the right
// answer in every case:
//   - round 1, on time        spawn T-20, floor 20  -> T+0       (bed lands on the round start)
//   - rounds 2+, on time      no cue,     floor 0   -> T+0       (bed lands on the round start)
//   - round 1, late joiner    spawn T-3,  floor 20  -> T+17      (their cue is not clipped)
//   - mid-round joiner        SPAWN_SHORT, floor 15 -> spawn+15  (their sting is not clipped)
//
// ⚠ The PER-PLAYER anchor is the whole safety argument, not a style choice. MP music is ONE shared
// client channel (_music::setMusicState -> a single musicCmd client-system state), so a push
// REPLACES whatever that player is still hearing rather than layering under it. A level-wide push
// (everyone at prematch_over, or any global timer) synchronizes the hand-off to one wall-clock
// moment and guillotines whoever spawned late — a level.nextMusicState + prematch_over version was
// written and reverted for exactly that. The max() keeps the floor per-player, which is what makes
// owning the start point safe. ([[intro-sting-killed-by-underscore-shared-channel]])
//
// Called from onStartGameType. level.* is wiped by map_restart, so this re-runs every round.
gf_initRoundMusic()
{
    // Suppress stock's own UNDERSCORE push. BOTH branches of sndStartMusicSystem are gated on
    // !isdefined( level.nextMusicState ), and its VALUE is never read anywhere — it is purely a
    // "someone else owns the music" flag, and nothing in the stock MP tree ever sets it. Without
    // this, stock's wait-15 push lands ON TOP of ours and restarts the bed mid-round.
    level.nextMusicState = "UNDERSCORE";
}

// Seconds of room this player's own spawn cue needs before the bed may replace it.
//
// Read from gf_playerSpawnedCB, which the engine calls at _globallogic_spawn.gsc:169 — BEFORE the
// cue blocks at :199 (prematch) and :245 (live round) latch pers["music"].spawn = true. So this
// sees what the player is ABOUT to be given, not what they were given:
//   - prematch + not cued yet   -> the long match-start cue (mus\mp\spawn\long\*, e.g.
//     Chopperintro_spawn_long_a.wav — picked per FACTION by the _teamset_* scripts). Round 1 only.
//   - live round + not cued yet -> SPAWN_SHORT, a genuine short sting
//     (mus\mp\spawn_short\short\*_sting_a.wav, randomized). A mid-round joiner.
//   - already cued              -> nothing plays this round. pers[] survives map_restart, so .spawn
//     stays latched from round 1 and rounds 2+ run silent up to the bed.
gf_spawnCueFloor()
{
    if ( isDefined( self.pers["music"] ) && isDefined( self.pers["music"].spawn ) && self.pers["music"].spawn )
        return 0;

    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
    {
        // Long match-start cue. Stock allows it 15s. Its real length is UNMEASURED — the wav ships
        // only inside the game's fastfiles, never in raw/ — so this is sized to the round-1
        // countdown (scr_gf_match_prematch_seconds, 20): the most room we can hand it without
        // pushing the bed past the round start. Note this floor only ever BINDS for a round-1 late
        // joiner; for an on-time player prematch_over is the later anchor and wins regardless.
        return 20;
    }

    return 15;   // SPAWN_SHORT sting — keep stock's own allowance.
}

// Arm this player's bed for the round. Once per player per round: self.* survives map_restart (only
// pers[]/game[] are guaranteed to persist, but nothing CLEARS our own vars either), so the guard is
// the round generation token, not a bool — level.gf_roundGen is re-stamped every onStartGameType.
gf_armRoundUnderscore()
{
    if ( isDefined( self.gf_underscoreGen ) && self.gf_underscoreGen == level.gf_roundGen )
        return;

    cueFloor = self gf_spawnCueFloor();
    self.gf_underscoreGen = level.gf_roundGen;
    self thread gf_playerUnderscore( cueFloor );
}

gf_playerUnderscore( cueFloor )
{
    self endon( "disconnect" );

    // ⚠ endon("game_ended") is CORRECT here even though that notify fires at every ROUND end, not at
    // match end ([[game-ended-fires-every-round-end]]) — dying at the round end is exactly the
    // intent. A joiner late enough that spawn+cueFloor would land past the round end must NOT start
    // the bed on top of ROUND_END during the killcam; the next round re-arms them from scratch.
    level endon( "game_ended" );

    myGen = level.gf_roundGen;

    // max( prematch_over, spawn + cueFloor ), expressed as two sequential waits — the later anchor
    // wins on its own, with no arithmetic across two different clocks.
    if ( cueFloor > 0 )
        wait( cueFloor );

    // ⚠ Gate the waittill on the flag — never waittill unconditionally. For a mid-round joiner
    // prematch_over ALREADY fired, and the waittill would park forever (until game_ended). The read
    // is race-free in the safe direction: stock clears inPrematchPeriod (_globallogic.gsc:1539)
    // BEFORE it fires the notify (:1507), so a thread that still sees the flag set is guaranteed to
    // register its waittill ahead of the notify.
    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
        level waittill( "prematch_over" );

    // A lobby map_restart(false) does NOT fire game_ended and threads survive it, so a stale thread
    // from the pre-restart round can wake here alongside the real one.
    if ( gf_roundGenChanged( myGen ) )
        return;

    // Mirror stock's own hand-off (_globallogic_spawn.gsc:769-770): stamp currentState BEFORE the
    // threaded push, so set_music_on_player's previousState bookkeeping matches stock's. The `true`
    // is save_state — it parks UNDERSCORE as this player's returnState, so transient states
    // (LAST_STAND and friends) fall back to the bed rather than to SILENT.
    // Stock creates pers["music"] in Callback_PlayerConnect and asserts it unguarded, but our push
    // lands much later in the spawn than stock's does — guard rather than risk a throw on a client
    // whose connect callback state is not what we assume.
    if ( !isDefined( self.pers["music"] ) )
        return;

    self.pers["music"].currentState = "UNDERSCORE";
    self thread maps\mp\gametypes\_globallogic_audio::set_music_on_player( "UNDERSCORE", true );
}

// The vision key in force this round. The public build has exactly one answer — the Gunfight default.
// Dev/VPS lets an admin override it live (RCON vision_<key>), persisted in gf_vis_vision so it
// survives the between-round map_restart; "normal" is stored EXPLICITLY (not as an empty dvar) so
// that clearing an override means "map default", not "fall back to the gf default" — see
// gf_bridgeVision.
gf_roundVisionKey()
{
    // #strip-begin - RCON vision override (dev/main only; the public build is always the gf default)
    vkey = getDvar( "gf_vis_vision" );
    if ( vkey != "" )
        return vkey;
    // #strip-end
    return "enhance";   // Gunfight's default look
}

gf_visionSetForKey( vkey )
{
    if ( vkey == "enhance"  ) return "default_night";    // sat1/contrast1.2 pop — the GF DEFAULT
    if ( vkey == "bw"       ) return "cheat_bw";         // pure grayscale
    if ( vkey == "berserk"  ) return "berserker";        // warm, contrast 1.5
    if ( vkey == "thermal"  ) return "infrared";         // dark desat night/thermal
    if ( vkey == "hotsnow"  ) return "infrared_snow";    // bright grayscale thermal
    if ( vkey == "nuke"     ) return "mp_nuked";         // warm hazy
    if ( vkey == "film"     ) return "flashpoint";       // warm cinematic / sepia
    if ( vkey == "bleak"    ) return "wmd";              // cold desaturated

    // legacy aliases (old panel keys) -> honest equivalents, so nothing 404s
    if ( vkey == "contrast" ) return "default_night";
    if ( vkey == "invert"   ) return "default_night";
    if ( vkey == "night"    ) return "infrared";

    return level.gf_defaultVision;             // "normal" / unknown -> the map's own vision
}

// #strip-begin - RCON video tweaks (dev/main only; stripped from public release)
// ─── Video tweaks (RCON-tunable, stock by default) ─────────────────────────
// gf_vis_<key> server dvar -> client video dvar. All default UNSET ("") = the
// mod never touches that setting. The RCON Visuals sliders write these through
// the bridge (gf_bridgeVisSet), which both pushes live players AND persists the
// value here so every later spawn re-applies it. Resetting a slider to "stock"
// clears the gf_vis_* dvar and one-shots the engine default (gf_visEngineDefault).
// r_gamma is deliberately NOT in the map: it is a SAVED client dvar and Plutonium
// blocks servers from writing those (the write never applies).
//
// The whole family is RCON-only (nothing else writes a gf_vis_* dvar), so the public build — which
// has no bridge — would never push any of it. Stripped rather than left inert so the public source
// carries no dead r_* machinery.

gf_visTweakMap()
{
    m = [];
    m["gf_vis_ambient"] = "r_lightTweakAmbient";
    m["gf_vis_gridint"] = "r_lightGridIntensity";
    m["gf_vis_gridcon"] = "r_lightGridContrast";
    m["gf_vis_hdr"]     = "r_fullHDRrendering";
    m["gf_vis_fog"]     = "r_fog";
    return m;
}

// Best-known engine defaults, used by the bridge's "stock" reset to visibly undo
// a tweak on players already in the session (a fresh client is always stock —
// setClientDvar values are session-only and never saved to the player's config).
gf_visEngineDefault( clientDvar )
{
    if ( clientDvar == "r_lightTweakAmbient"  ) return "0";
    if ( clientDvar == "r_lightGridIntensity" ) return "1";
    if ( clientDvar == "r_lightGridContrast"  ) return "0";
    if ( clientDvar == "r_fullHDRrendering"   ) return "1";
    if ( clientDvar == "r_fog"                ) return "1";
    return "";
}

gf_applyVisTweaks()
{
    m = gf_visTweakMap();
    keys = getArrayKeys( m );
    for ( i = 0; i < keys.size; i++ )
    {
        v = getDvar( keys[i] );
        if ( v != "" )
            self setClientDvar( m[keys[i]], v );
    }
}
// #strip-end

gf_onSpawnSpectator( origin, angles )
{
    maps\mp\gametypes\_globallogic_defaults::default_onSpawnSpectator( origin, angles );

    // #strip-begin - lobby spectator branch (dev/main only; calls gf_hideLobbyHUD, which the public build strips)
    // ── Pregame lobby (Auto/Manual) ──────────────────────────────────────────
    // Keep this a CLEAN spectator: hide the whole gunfight HUD. The team-select menu the engine would
    // open for a teamless connector is prevented upstream by level.forceAutoAssign (set at the hold
    // start), so there's nothing to swat here — which is what keeps the ESC/pause overlay usable. Do
    // NOT thread the health HUD in this branch (that re-shows the panel). Desaturation is the
    // level-scope visionSetNaked("mpIntro") applied at the hold start (no per-player self-method form
    // in T5 MP). No teardown: map_restart(false) on lobby release respawns everyone fresh.
    if ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold
        && !( self istestclient() ) && !( self isdemoclient() ) )
    {
        self gf_hideLobbyHUD();
        return;
    }
    // #strip-end

    // Re-assert the skull dead-marker. in_spawnSpectator (_globallogic_spawn.gsc:359) stomps
    // statusicon back to "hud_status_dead" a beat before invoking this callback, which is what
    // reverted the icon a few seconds after death (the killcam ending routes the corpse here —
    // one life, so there is no respawn). Mirrors stock's own condition: a real spectator keeps a
    // CLEARED icon, so the guard is what lets a parked bot stay clean (gf.gsc seats it on the
    // spectator team precisely to get that). The lobby-hold branch above already returned — a
    // player waiting in the lobby is not dead and must not be marked as such.
    if ( isDefined( self.pers["team"] ) && self.pers["team"] != "spectator" )
        self.statusicon = "hud_death_suicide";

    // Mid-match spectator (a late joiner or a REJOIN): clear any stale lobby HUD. A client that was in a
    // prior lobby got ui_gf_lobby_show=1; if it left before the release that zeroes it, that 1 persists on
    // the client and nothing outside the lobby clears it — so the whole lobby chrome sticks over their
    // view. The inLobbyHold branch above already returned for real lobby spectators, so reaching here (as
    // a human) means the LIVE match. Humans only.
    if ( !( self istestclient() ) && !( self isdemoclient() ) )
        self setClientDvar( "ui_gf_lobby_show", "0" );

    gf_queueHealthHUDUpdate();

    // Spectators always see the whole health HUD. The panel is fully menu-rendered and the
    // intro is a snap now, so re-threading gf_runHealthHUD on each spectator spawn is cheap
    // and harmless (it re-pushes the per-client dvars).
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self thread gf_runHealthHUD();
}

gf_onSpawned()
{
    if ( self.pers["team"] != "allies" && self.pers["team"] != "axis" )
        return;

    self.gf_assisters = [];
    self.gf_dmgOnTarget = [];

    if ( !level.gf_roundActive )
        level thread gf_tryActivateRound();
}

// ─── Round Activation ──────────────────────────────────────────────────────

// True if a map_restart happened since myGen was captured (level.gf_roundGen is
// re-stamped every onStartGameType, gettime()-based so it's monotonic across
// map_restart). Undefined level gen (never stamped) also reads as "changed".
gf_roundGenChanged( myGen )
{
    return ( !isDefined( level.gf_roundGen ) || level.gf_roundGen != myGen );
}

gf_tryActivateRound()
{
    if ( level.gf_activatingRound )
        return;

    level.gf_activatingRound = true;
    level endon( "game_ended" );

    // Generation token: this activator belongs to the round init that was current when
    // it started. A frozen prematch spawn during an Auto/Manual Pass-1 lobby hold threads
    // this and parks on waittill("prematch_over"); the lobby's map_restart(false) does NOT
    // fire game_ended and threads SURVIVE it, so that stale Pass-1 activator would wake
    // alongside the fresh Pass-2 one and double gf_startRoundClock/gf_closeGraceEarly.
    // We USED to kill it with endon("gf_load_gate_reset") — but that same notify fires on
    // every lobby RE-arm (gf_armLoadGate), so in a bot-only re-lobby loop it could kill a
    // LIVE activator mid-commit, stranding the round with gf_roundActive=true but no
    // grace-close and no round clock: the 24h freeze. The endon is GONE. Instead we commit
    // gf_roundActive AFTER the prematch wait and bail if the generation moved (a stale
    // Pass-1 activator) or a peer already went live — so no stale thread can strand a round
    // and no notify can kill a committing one. gf_roundWatchdog is the final backstop.
    myGen = level.gf_roundGen;

    // 0.2s dedup so a single activation thread wins the spawn burst.
    wait 0.2;

    if ( level.gf_roundActive || gf_roundGenChanged( myGen ) )
    {
        level.gf_activatingRound = false;
        return;
    }

    level.gf_warnedLastPlayer = [];
    gf_forceHealthHUDUpdate();

    // The engine's native per-round prematch (set up in onStartGameType via level.prematchPeriod)
    // owns the countdown, player freeze, intro VO, objective hint, and timer-hide. We reach here
    // ~0.2s INTO it (players spawn frozen during the prematch, and that first spawn is what
    // triggers gf_tryActivateRound), so wait for the prematch to finish before starting the round
    // clock — otherwise it draws the round timer over the countdown AND burns round time. While
    // the clock isn't running, timeLimitOverride stays false, so the engine hides the timer for
    // the whole prematch (clean, no flicker), exactly like SD.
    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
        level waittill( "prematch_over" );

    // COMMIT — atomic from here to gf_startRoundClock (no yields), so nothing can strand a
    // half-activated round. A map_restart during the prematch wait bumped gf_roundGen (stale
    // Pass-1 activator), or a peer activator already went live — either way, bail cleanly.
    if ( level.gf_roundActive || gf_roundGenChanged( myGen ) )
    {
        level.gf_activatingRound = false;
        return;
    }

    level.gf_roundEnding = false;
    level.gf_roundActive = true;

    // Backstop the whole round: a per-round watchdog force-ends a round that gets stranded
    // despite the above (any dropped team-wipe edge, stuck grace, or a clock that never
    // starts). The mod suppresses EVERY native round-end fallback, so this is the only net.
    // Threaded first, before the (non-yielding) setup below, so it is armed even if a future
    // edit adds a yield that an interrupt could exploit.
    level thread gf_roundWatchdog( myGen );

    // Silence the native timeLimitClock across the (usually zero-length) hold below —
    // it starts at prematch_over and on a 45s round timeLeftInt begins inside the stock
    // 40-60s match_ending_soon band, which would set xblive_matchEndingSoon and fire the
    // last-round winning/losing VO at ROUND START during a real hold. Pausing here (same
    // frame position the old code paused from, via gf_startRoundClock) also freezes
    // getTimePassed() at ~0, so disable the stock grenade-dud window now too or grenades
    // thrown during the hold fire as duds (same interaction gf_startRoundClock handles).
    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    level.grenadeLauncherDudTime = -1;
    level.thrownGrenadeDudTime   = -1;

    // The match-start min-players gate AND the load gate both now live in FRONT of
    // prematch (gf_waitForLoadingClients, the last statement of onStartGameType). By
    // the time we reach here the roster has loaded and is spawning during prematch,
    // so the old post-prematch holds are gone: (a) the "wait for min players" hold
    // that froze players + voided damage — unneeded pre-spawn, and it no longer plays
    // the intro for a match that then stalls; (b) the "wait for every teamed player to
    // spawn" roster hold (scr_gf_roster_wait) — redundant once everyone's loaded
    // before prematch. graceFloor still anchors the early grace close 3s past
    // prematch_over.
    graceFloor = gettime() + 3000;

    // Close grace early — 3s past prematch_over instead of the stock 15s mark — so
    // maySpawn's first-spawn window and the onDeadEvent suppression don't outlive the
    // spawn wave. The 3s floor is join slack for a human still in team-select
    // (invisible to any spawn check — no pers["team"] yet). Threaded so the round clock
    // below starts immediately; gf_closeGraceEarly also holds grace open longer for a
    // client still loading past the gate (scr_gf_load_grace).
    level thread gf_closeGraceEarly( graceFloor );

    // Capture the auto team-size decision for next round's setup from the roster as it
    // stands now (post-prematch). Humans are settled (the pre-prematch gate held for
    // them); late bot fill may still be arriving, so a bot-heavy round-1 snapshot can
    // lag by one round — self-corrects round 2 (documented auto-mode lag).
    gf_updateAutoTeamMode();

    // Take over the live-round timer. This silences the native 30s "time running out" sequence
    // (announcer + TIME_OUT music + beeps) and drives our own countdown instead: VO at 15s, beeps
    // in the final 10s, no music.
    gf_startRoundClock();

    level.gf_activatingRound = false;
}

// ─── Round Watchdog (safety net) ───────────────────────────────────────────
// The mod owns the round clock and suppresses EVERY native round-end backstop
// (pauseTimer gates off timeLimitClock; timeLimitOverride early-returns stock
// checkTimeLimit; gf_onDeadEvent is guarded by gf_roundActive/gf_roundEnding;
// grace-close is mod-owned). So a single dropped round-end edge — a team wipe
// that arrives while inGracePeriod is (wrongly) still open, or an activation that
// somehow strands before it closes grace / starts the clock — would hang the round
// FOREVER (observed 2026-07-09: a 24h freeze, engine still running, a wiped team
// that never ended the round, no timer). This gettime()-anchored thread is the only
// net. gettime() is wall-clock, immune to pauseTimer. One per round; retired by
// gf_round_over (normal end), game_ended (match end), or a generation change.
gf_roundWatchdog( myGen )
{
    level endon( "game_ended" );
    level endon( "gf_round_over" );   // a normal round end retires the watchdog

    activeSince = gettime();
    emptySince  = undefined;

    for ( ;; )
    {
        wait 1;

        // A round transition that did NOT route through gf_endRound (no gf_round_over) —
        // bail so we never act on a stale round.
        if ( gf_roundGenChanged( myGen ) )
            return;
        if ( !isDefined( level.gf_roundActive ) || !level.gf_roundActive )
            return;
        if ( isDefined( level.gf_roundEnding ) && level.gf_roundEnding )
            return;

        now     = gettime();
        elapsed = now - activeSince;

        // (1) STRANDED-ACTIVATION RECOVERY. If the round has been "active" well past any
        // legit grace / clock-start window but grace is still open or the clock never
        // started, activation was interrupted — restore normal flow so the round can end
        // on its own. Threshold covers stock 15s grace + scr_gf_load_grace (<=60s) + slack.
        if ( elapsed > 65000 )
        {
            if ( isDefined( level.inGracePeriod ) && level.inGracePeriod && !gf_anyTrackedClientLoading() )
            {
                logPrint( "GF_WATCHDOG: grace overstayed " + elapsed + "ms — force-closing\n" );
                level.inGracePeriod = false;
                level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
            }
            if ( ( !isDefined( level.gf_roundClockRunning ) || !level.gf_roundClockRunning )
                && ( !isDefined( level.gf_overtimeActive ) || !level.gf_overtimeActive ) )
            {
                logPrint( "GF_WATCHDOG: round clock never started — starting it\n" );
                gf_startRoundClock();
            }
        }

        // (2) WIPE-NOT-DETECTED RECOVERY. A team is fully eliminated but the round did
        // not end. Judged only out of grace (during grace a team legitimately reads 0
        // alive mid-spawn) and only after the empty state PERSISTS a few seconds — then
        // force the round decision. Recovery (1) force-closes a stuck grace first, so a
        // grace-suppressed wipe reaches here on the next tick.
        aliveA = 0;
        aliveX = 0;
        if ( isDefined( level.aliveCount ) )
        {
            if ( isDefined( level.aliveCount["allies"] ) ) aliveA = level.aliveCount["allies"];
            if ( isDefined( level.aliveCount["axis"] ) )   aliveX = level.aliveCount["axis"];
        }

        graceOpen = ( isDefined( level.inGracePeriod ) && level.inGracePeriod );

        if ( ( aliveA == 0 || aliveX == 0 ) && !graceOpen )
        {
            if ( !isDefined( emptySince ) )
                emptySince = now;
            else if ( now - emptySince > 3000 )
            {
                if ( aliveA == 0 && aliveX == 0 )
                    winner = "tie";
                else if ( aliveA == 0 )
                    winner = "axis";
                else
                    winner = "allies";

                logPrint( "GF_WATCHDOG: team wipe not ended (allies=" + aliveA + " axis=" + aliveX + ") — forcing round end -> " + winner + "\n" );
                level.gf_endReasonText = gf_reasonText( "elim", winner );
                // THREADED for the same reason as gf_roundClock's gf_onTimeLimit call:
                // gf_endRound notifies "gf_round_over", which THIS thread endon()s, so an
                // inline call would kill the recovery mid-flight and strand the very round
                // it was trying to rescue.
                level thread gf_endRound( winner );
                return;
            }
        }
        else
            emptySince = undefined;
    }
}

// POST-ROUND WATCHDOG — the round-END half of the safety net. gf_roundWatchdog is
// endon("gf_round_over"), so it retires at the exact moment this hazard opens, and
// nothing else watches the stock round-end sequence. That sequence runs SYNCHRONOUSLY
// inside _globallogic::startNextRound and only reaches its map_restart(true) after
//   executePostRoundEvents -> _killcam::postRoundFinalKillcam -> finalKillcamWaiter()
// which spins while level.inFinalKillcam — and THAT only clears once
// _killcam::areAnyPlayersWatchingTheKillcam() reports false, which it does only when NO
// player has .killcam merely DEFINED.
//
// .killcam is set in _killcam::finalKillcam and cleared ONLY by endKillcam() off the
// "end_killcam" notify. finalKillcam carries `self endon("disconnect")`, and its own
// cleanup thread (endedFinalKillcamCleanup) waits on "game_ended" — which endGame ALREADY
// fired, seconds before the final killcam even starts (play_final_killcam lands later,
// past roundEndWait). So the engine's own net is structurally DEAD on this path: once a
// client's .killcam is orphaned, nothing on the box will ever clear it, map_restart is
// never reached, and the round hangs FOREVER with the server otherwise healthy — ticking
// normally, still accepting joins, RCON fine. (Observed 2026-07-11 on the VPS: a human
// left mid-round, the round ended, and the match sat in one round until it was restarted
// by hand.) The same sequence's other unbounded gate is _globallogic::roundEndWait, which
// spins while any player has .doingNotify true — orphaned the same way if a
// showNotifyMessage thread dies before its cleanup.
//
// So: give the round end a generous grace, then break BOTH deadlocks by clearing the
// orphaned flags. A healthy round end restarts the map long before the threshold and the
// gen check retires this thread with it. NOTE: no endon("game_ended") — endGame fires that
// notify within a frame of us being threaded, and this must outlive it. It must also stay
// armed on the LAST round: the same finalKillcamWaiter gates the match end (podium), so
// the identical wedge can hang the intermission.
gf_postRoundWatchdog( myGen )
{
    start = gettime();

    for ( ;; )
    {
        wait 1;

        // map_restart(true) landed -> the round end completed on its own. Threads survive
        // the restart, so this gen check is what retires us on the happy path.
        if ( gf_roundGenChanged( myGen ) )
            return;

        elapsed = gettime() - start;

        // Well past any legit final killcam + roundEndDelay. Under the threshold we never
        // touch a thing, so a normal killcam is never cut short.
        if ( elapsed < 20000 )
            continue;

        if ( gf_breakRoundEndDeadlock( elapsed ) )
            return;

        // Nothing orphaned but the round end still hasn't restarted the map: not a state we
        // know how to fix from here. Stop burning a tick every second (the box-side watchdog
        // map_rotates a match that stays stuck).
        if ( elapsed > 180000 )
        {
            logPrint( "GF_ENDWATCH: round end still hung after " + elapsed + "ms with no orphaned flag — giving up\n" );
            return;
        }
    }
}

// Clear the two flags that can pin the stock round-end sequence open, and LOG exactly who
// and which — this log line is the diagnostic that identifies the leaking client (human vs
// bot vs democlient, and whether it was a fresh mid-round-end connect) the next time this
// fires. Returns the number of clients unwedged.
gf_breakRoundEndDeadlock( elapsed )
{
    cleared = 0;
    players = level.players;

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) )
            continue;

        who = "";
        if ( isDefined( p.name ) )
            who = p.name;
        kind = "human";
        if ( p isdemoclient() )
            kind = "demo";
        else if ( p istestclient() )
            kind = "bot";

        // Orphaned final-killcam flag -> areAnyPlayersWatchingTheKillcam() never goes false
        // -> finalKillcamWaiter() spins -> map_restart never runs.
        if ( isDefined( p.killcam ) )
        {
            p.killcam = undefined;
            p notify( "end_killcam" );   // release a finalKillcam still parked on its waittill
            logPrint( "GF_ENDWATCH: orphaned .killcam on " + kind + " '" + who + "' after "
                      + elapsed + "ms — cleared (round end was deadlocked)\n" );
            cleared++;
        }

        // Orphaned notify flag -> roundEndWait() never completes.
        if ( isDefined( p.doingNotify ) && p.doingNotify )
        {
            p.doingNotify = false;
            logPrint( "GF_ENDWATCH: orphaned .doingNotify on " + kind + " '" + who + "' after "
                      + elapsed + "ms — cleared (round end was deadlocked)\n" );
            cleared++;
        }
    }

    return cleared;
}

// Closes the grace period once floorTime has passed. Closing grace reopens
// onDeadEvent (a wipe can end the round again) and shuts maySpawn's first-spawn
// window. Mirror stock gracePeriod()'s close with an updateTeamStatus pass so a
// wipe that happened WHILE grace was open is still noticed (updateGameEvents only
// re-runs on team-status ticks). The stock gracePeriod() thread still runs its own
// idempotent close at the full 15s as a backstop.
gf_closeGraceEarly( floorTime )
{
    level endon( "game_ended" );

    while ( gettime() < floorTime )
        wait 0.1;

    // #strip-begin - straggler-loader grace hold (dev/main only; the public build has no load gate)
    // Keep grace open past the floor while a rotation-carried client is still
    // loading the map, so it can still take its round-1 first spawn instead of
    // spectating (see gf_waitForLoadingClients, which raised level.gracePeriod so
    // the stock backstop won't close before us). Ceiling = prematch_over
    // (floorTime - 3000) + scr_gf_load_grace. The cost of this hold is that a
    // round-1 team wipe can't END the round until grace closes — bounded by the
    // ceiling and by round length. No-op when nobody is loading (the common case),
    // when scr_gf_load_grace is 0 (off), or on rounds 2+ (snapshot is wiped).
    //
    // Stripped rather than left inert: the only thing that populates the tracker this reads
    // (gf_armLoadGate -> level.gf_loadGateSeen) is itself stripped, so in the public build
    // gf_anyTrackedClientLoading() is always false and the loop can never spin — but the
    // gf_cfgFloat call would still REGISTER scr_gf_load_grace, publishing a knob the public
    // build cannot honour. The enclosing gf_closeGraceEarly stays (live round code calls it);
    // only this hold goes, leaving the stock grace floor.
    loadGrace = gf_cfgFloat( "scr_gf_load_grace", 20, 0, 60 );
    if ( loadGrace > 0 )
    {
        graceCeiling = ( floorTime - 3000 ) + int( loadGrace * 1000 );
        while ( gf_anyTrackedClientLoading() && gettime() < graceCeiling )
            wait 0.2;
    }
    // #strip-end

    level.inGracePeriod = false;
    level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
}

// ─── Live-Round Clock ──────────────────────────────────────────────────────
//
// We own the live-round timer instead of the native one. The stock
// _globallogic::timeLimitClock fires a fixed "time running out" sequence at
// hardcoded thresholds (announcer VO ~32s, TIME_OUT music + countdown beeps at
// 30s), keyed off absolute seconds remaining — so on a 45s round it triggers
// almost immediately and there is no dvar to retune it. pauseTimer() sets
// level.timerStopped, which gates off that native loop entirely (no music, no
// VO, no beeps); we then drive the HUD clock via setGameEndTime and own expiry
// via level.timeLimitOverride. Same proven approach as the overtime clock below.
gf_startRoundClock()
{
    // Round length (minutes) -> ms. level.timeLimit is per-mode (small vs _large),
    // re-derived each round in main()/onStartGameType.
    roundLen = 0.7;
    if ( isDefined( level.timeLimit ) && level.timeLimit > 0 )
        roundLen = level.timeLimit;

    level.gf_roundRemaining    = roundLen * 60 * 1000;
    level.gf_roundLastTime     = gettime();
    level.gf_roundLastTick     = undefined;
    level.gf_roundWarned       = false;
    level.gf_roundClockRunning = true;
    level.gf_roundPaused       = false;
    level.timeLimitOverride    = true;

    if ( isDefined( level.gf_roundTickObject ) )
        level.gf_roundTickObject delete();
    level.gf_roundTickObject = spawn( "script_origin", ( 0, 0, 0 ) );

    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    gf_updateRoundGameEndTime();

    // pauseTimer() freezes getTimePassed() at ~0 for the whole round, which breaks
    // the stock grenade-dud window (_weapons::turnGrenadeIntoADud compares
    // dudTime >= getTimePassed()/1000). With the clock frozen that stays true all
    // round, so frags/semtex AND launchers (gl_*, china_lake_mp) fire as duds and
    // spam "unavailable for 1 second". Negative thresholds disable the dud system
    // entirely (no positive value would ever elapse against a frozen clock). Set
    // here (after map_restart wipes level.*) so it re-applies every round; persists
    // through overtime in the same round.
    level.grenadeLauncherDudTime = -1;
    level.thrownGrenadeDudTime   = -1;

    level thread gf_roundClock();
}

gf_roundClock()
{
    level endon( "game_ended" );
    level endon( "gf_round_over" );   // round ended early by elimination

    while ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        gf_syncRoundRemaining();

        if ( level.gf_roundRemaining <= 0 )
        {
            level.gf_roundClockRunning = false;
            // Leave level.timerStopped / level.timeLimitOverride set: expiry either
            // enters overtime (which re-pauses + keeps the override) or ends the round
            // (map_restart wipes the state). Only clear our own clock vars here.
            gf_cleanupRoundTimerState();

            // THREADED, never called inline. gf_onTimeLimit's HP-decides branch calls
            // gf_endRound, which fires level notify("gf_round_over") — and THIS thread
            // endon()s that notify, so an inline call would kill us mid-gf_endRound (the
            // winner never scores, gf_postRoundWatchdog is never armed, endGame never runs
            // -> the round hangs forever). Handing off to a fresh thread with no endon is
            // what makes the clock-expiry path survive its own notify.
            level thread gf_onTimeLimit();
            return;
        }

        // While admin-paused, skip the HUD push + warning tick so the setGameEndTime(0)
        // from gf_pauseMatch stays sticky (a re-push would re-arm the on-screen clock)
        // and no countdown beep fires on a frozen clock — same guard as gf_overtimeClock.
        if ( !isDefined( level.gf_roundPaused ) || !level.gf_roundPaused )
        {
            gf_updateRoundGameEndTime();
            gf_updateRoundWarning();
        }

        wait 0.1;
    }
}

gf_syncRoundRemaining()
{
    if ( !isDefined( level.gf_roundLastTime ) )
        level.gf_roundLastTime = gettime();

    now = gettime();
    elapsed = now - level.gf_roundLastTime;
    level.gf_roundLastTime = now;

    // While admin-paused (RCON bridge), advance the reference time but hold the
    // remaining ms — same freeze the OT clock does via level.gf_overtimePaused.
    if ( isDefined( level.gf_roundPaused ) && level.gf_roundPaused )
        return;

    if ( elapsed > 0 )
        level.gf_roundRemaining -= elapsed;

    if ( level.gf_roundRemaining < 0 )
        level.gf_roundRemaining = 0;
}

gf_updateRoundGameEndTime()
{
    if ( !isDefined( level.gf_roundRemaining ) )
        return;

    remaining = level.gf_roundRemaining;
    if ( remaining < 0 )
        remaining = 0;

    setGameEndTime( int( gettime() + remaining ) );
}

gf_updateRoundWarning()
{
    if ( !isDefined( level.gf_roundRemaining ) )
        return;

    remaining = level.gf_roundRemaining;

    // Announcer VO once at 15s remaining. No team arg -> leaderDialogBothTeams plays
    // the generic "timesup" callout to everyone (no "squad_30sec" variant). No music:
    // we never fire the native match_ending_* notifies that drive TIME_OUT.
    if ( remaining <= 15000 && ( !isDefined( level.gf_roundWarned ) || !level.gf_roundWarned ) )
    {
        level.gf_roundWarned = true;
        maps\mp\gametypes\_globallogic_audio::leaderDialog( "timesup" );
    }

    // Countdown beeps in the final 10 seconds only (one per second, 10 -> 1).
    if ( remaining <= 0 || remaining > 10000 )
        return;

    tick = int( ( remaining + 999 ) / 1000 );
    if ( tick < 1 || tick > 10 )
        return;

    if ( isDefined( level.gf_roundLastTick ) && level.gf_roundLastTick == tick )
        return;

    level.gf_roundLastTick = tick;

    if ( isDefined( level.gf_roundTickObject ) )
        level.gf_roundTickObject playSound( "mpl_ui_timer_countdown" );
}

gf_cleanupRoundTimerState()
{
    level.gf_roundClockRunning = false;
    level.gf_roundRemaining    = undefined;
    level.gf_roundLastTime     = undefined;
    level.gf_roundLastTick     = undefined;

    if ( isDefined( level.gf_roundTickObject ) )
    {
        level.gf_roundTickObject delete();
        level.gf_roundTickObject = undefined;
    }
}

// #strip-begin - ADMIN MATCH PAUSE (dev/main only; stripped from public release)
// Only the RCON bridge calls gf_pauseMatch / gf_resumeMatch, so the public build — which has no
// bridge — can never enter a pause. NOTE gf_pushPauseBanner() lives in _gf_hud.gsc and is NOT
// stripped: gf_runHealthHUD calls it on every spawn, and with level.gf_matchPaused never set it
// simply clears the banner. Same for the gf_pause_hud menuDef in mod.ff, which stays inert.
//
// ─── Admin Match Pause (RCON bridge) ───────────────────────────────────────
// The live round timer is now mod-owned (gf_roundClock / gf_syncRoundRemaining),
// so the stock pauseTimer() the bridge used to call no longer freezes the visible
// clock — it only sets level.timerStopped, which we already hold true all round
// (and flipping it back via resumeTimer would re-arm the native "time running out"
// VO/music/beeps we deliberately suppress). Instead the bridge delegates here:
// we freeze whichever mod clock is live (overtime takes priority over the round
// clock, matching gf_onTimeLimit), freeze human controls, freeze bots, and raise
// the MATCH PAUSED banner (gf_pause_hud menuDef). The B&W vision that completes
// the look is the bridge's half of the pause — see gf_bridgePause.
//
// Bots ignore freezeControls (they're server-driven by the vendored framework,
// not client input), so we toggle the framework's own bots_play_move dvar — its
// per-bot bot_watch_stop_move loop pins velocity/origin when it's 0.
gf_pauseMatch()
{
    // Freeze whichever mod clock is live. Overtime routes through the capture
    // pause-depth counter (gf_pauseOvertimeForCapture) so an admin pause composes
    // with an in-progress zone capture — the OT clock only resumes once BOTH
    // release it. The round clock has no such counter, so it uses a simple flag.
    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
        gf_pauseOvertimeForCapture();
    else if ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        if ( !isDefined( level.gf_roundPaused ) || !level.gf_roundPaused )
        {
            gf_syncRoundRemaining();
            level.gf_roundPaused = true;
            setGameEndTime( 0 );   // hide the clock while paused (matches capture pause)
        }
    }

    setDvar( "bots_play_move", 0 );   // framework's bot_watch_stop_move pins every bot in place

    // Sole authority for the gf_pause_hud menuDef ("MATCH PAUSED"). Set BEFORE the push loop so
    // gf_pushPauseBanner reads the live state, and it is what a mid-pause joiner's spawn-time push
    // (gf_runHealthHUD) reads too. The B&W vision that goes with it is applied by the caller
    // (gf_bridgePause) — visionSetNaked is level-global and the bridge owns the vision key it has
    // to restore to on resume.
    level.gf_matchPaused = true;

    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        players[i] freezeControls( true );
        players[i] gf_pushPauseBanner();
    }
}

gf_resumeMatch()
{
    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
        gf_resumeOvertimeForCapture();
    else if ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        if ( isDefined( level.gf_roundPaused ) && level.gf_roundPaused )
        {
            // Reset the reference time BEFORE clearing the flag so the paused interval
            // is discarded (no catch-up jump), like gf_resumeOvertimeForCapture.
            level.gf_roundLastTime = gettime();
            level.gf_roundPaused   = false;
            gf_updateRoundGameEndTime();
        }
    }

    setDvar( "bots_play_move", 1 );

    level.gf_matchPaused = false;

    // bots_play_move=1 stops bot_watch_stop_move from re-pinning, but the last-spawned
    // botStopMove(true) loop only ends on this notify (or death/disconnect) — without it
    // a bot that was mid-navigation stays frozen in place for the rest of the round.
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        players[i] freezeControls( false );
        players[i] gf_pushPauseBanner();          // level.gf_matchPaused is false now -> clears the banner
        if ( isDefined( players[i].pers["isBot"] ) && players[i].pers["isBot"] )
            players[i] notify( "botStopMove" );
    }
}
// #strip-end

// ─── Round End ─────────────────────────────────────────────────────────────

// Central round-end helper — mirrors sd_endGame().
// Updates game["teamScores"] so the native score bar HUD reflects the win,
// then hands off to _globallogic::endGame() for round cycling / win-limit.
gf_endRound( winner )
{
    if ( gf_resolveOvertime( winner ) )
        return;

    level.gf_roundEnding = true;
    level.gf_roundActive = false;

    // The gf_round_over notify below retires the round clock before it can self-clean, so
    // tear its tick object + state down here.
    gf_cleanupRoundTimerState();

    gf_forceHealthHUDUpdate();

    if ( isDefined( winner ) && winner != "tie" )
        [[level._setTeamScore]]( winner, [[level._getTeamScore]]( winner ) + 1 );

    // Native WIN/LOSS banner subtitle — reason set at the decision site (carried
    // via level var so it survives the OT gf_ot_done re-entry into gf_endRound).
    reasonText = "";
    if ( isDefined( level.gf_endReasonText ) )
        reasonText = level.gf_endReasonText;
    level.gf_endReasonText = undefined;

    // Arm the round-END net BEFORE handing off to stock. From here the whole restart hangs
    // off _globallogic's synchronous end sequence, which an orphaned .killcam / .doingNotify
    // can pin open forever. Must be threaded before endGame: endGame fires "game_ended"
    // within a frame.
    level thread gf_postRoundWatchdog( level.gf_roundGen );

    // Clamp stock's final-killcam slow motion to scr_gf_killcam_slowmo (the timescale FLOOR), which
    // is what keeps the server's game-frame cadence — and with it every client's usercmd pipeline —
    // inside the engine's own disconnect threshold. Must be threaded BEFORE endGame: stock's
    // per-player slowdown thread is armed from the killcam that endGame's post-round events start.
    level thread gf_killcamSlowmoClamp( level.gf_roundGen );

    // #strip-begin - round-end timeline probe (dev/main only; stripped from public release)
    // Samples the killcam -> map_restart window at 20 Hz and logs every window the server went
    // dark for. Nothing else covers it: gf_hitchMonitor is re-threaded (and collapsed) only on
    // the far side of the restart, and this is exactly the window where clients report the
    // "Connection Interrupted" plug. Retires itself on the generation change. See _gf_debug.gsc.
    level thread gf_roundEndProbe( level.gf_roundGen );
    // #strip-end

    // ⚠ ORDER IS LOAD-BEARING: everything above this line must STAY above it.
    // A GSC notify kills every thread that endon()s it — including the thread that FIRES
    // it. Two threads carry level endon("gf_round_over") and both call this function:
    // gf_roundClock (via gf_onTimeLimit — the clock-expiry / HP-decides path) and
    // gf_roundWatchdog (the team-wipe force-end). Both now `level thread` into here so
    // neither is ever the thread executing this line; keeping the score, the timer teardown
    // and the post-round watchdog ABOVE it means even a future inline caller still gets a
    // scored, watchdog-armed round end.
    // (2026-07-12, mp_kowloon: called inline from gf_roundClock, this notify killed
    // gf_endRound right here. The winner never scored, gf_postRoundWatchdog was never armed
    // and endGame never ran — so map_restart never happened and the round hung FOREVER with
    // every watchdog dead. Stock endGame has the same shape and is careful for the same
    // reason: it writes all its state BEFORE notify("game_ended").)
    level notify( "gf_round_over" );

    level thread maps\mp\gametypes\_killcam::startLastKillcam();
    level thread maps\mp\gametypes\_globallogic::endGame( winner, reasonText );
}

gf_onDeadEvent( team )
{
    if ( level.gf_roundEnding ) return;
    if ( !level.gf_roundActive ) return;

    if ( team == "all" )
        winner = "tie";
    else
        winner = maps\mp\_utility::getOtherTeam( team );

    gf_forceHealthHUDUpdate();
    level.gf_endReasonText = gf_reasonText( "elim", winner );
    gf_endRound( winner );
}

gf_onTimeLimit()
{
    if ( level.gf_roundEnding ) return;

    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
    {
        hpWinner = gf_getHPWinner();
        level.gf_endReasonText = gf_reasonText( "health", hpWinner );
        gf_resolveOvertime( hpWinner );
        return;
    }

    alliesHP = gf_getTeamHP( "allies" );
    axisHP   = gf_getTeamHP( "axis"   );

    // Both sides still alive enter overtime; otherwise HP decides the round.
    if ( alliesHP > 0 && axisHP > 0 )
    {
        overtimeLimit = gf_getOvertimeLimit();
        if ( overtimeLimit <= 0 )
        {
            hpWinner = gf_getHPWinner();
            level.gf_endReasonText = gf_reasonText( "health", hpWinner );
            gf_endRound( hpWinner );
            return;
        }

        gf_beginOvertime( overtimeLimit );
        return;
    }

    hpWinner = gf_getHPWinner();
    level.gf_endReasonText = gf_reasonText( "health", hpWinner );
    gf_endRound( hpWinner );
}

gf_resolveOvertime( winner )
{
    if ( !isDefined( level.gf_overtimeActive ) || !level.gf_overtimeActive )
        return false;

    if ( isDefined( level.gf_overtimeResolving ) && level.gf_overtimeResolving )
        return true;

    level.gf_overtimeResolving = true;
    level notify( "gf_ot_done", winner );
    return true;
}

gf_beginOvertime( overtimeLimit )
{
    level.gf_overtimeActive        = true;
    level.gf_overtimeResolving     = false;
    level.gf_overtimePaused        = false;
    level.gf_overtimePauseDepth    = 0;
    level.gf_overtimeRemaining     = overtimeLimit * 1000;
    level.gf_overtimeLastTime      = gettime();
    level.gf_overtimeLastTickMs    = undefined;
    level.gf_overtimeClockRunning  = true;
    level.inOvertime               = true;
    level.timeLimitOverride        = true;

    if ( isDefined( level.gf_overtimeTickObject ) )
        level.gf_overtimeTickObject delete();
    level.gf_overtimeTickObject = spawn( "script_origin", ( 0, 0, 0 ) );

    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    gf_updateOvertimeGameEndTime();

    level thread gf_overtime();
}

gf_overtime()
{
    level endon( "game_ended" );

    gf_showOvertimeMessage();

    // Ensure _gameobjects vars are ready (guarded in case _gameobjects::init was skipped)
    if ( !isDefined( level.numGametypeReservedObjectives ) )
        level.numGametypeReservedObjectives = 0;
    if ( !isDefined( level.releasedObjectives ) )
        level.releasedObjectives = [];

    zone = gf_createOvertimeZone();

    // Safety net: if the round ends mid-OT via a path that fires game_ended WITHOUT
    // going through gf_resolveOvertime (forfeit, host migration), the endon above kills
    // this thread before the cleanup below runs — leaking the zone's 2 objpoint HUD
    // elements + 2 objective IDs. Engine-side hudelem/objective state SURVIVES
    // map_restart(true) (observed: objective IDs accumulate), so leaks persist for the
    // whole map session and can exhaust the server HUD pool → later OT rounds get no
    // flag icon. This watcher cleans up on game_ended; the gf_ot_done endon makes the
    // two cleanup paths mutually exclusive.
    level thread gf_overtimeZoneGameEndCleanup( zone );

    // #strip-begin - bot OT capture AI (dev/main only; the public build ships no bots)
    // Steer any bots onto the flag so they can win OT by capture, not just HP.
    if ( isDefined( zone ) )
        level thread gf_botOvertimeAI( zone );
    // #strip-end

    level thread gf_overtimeClock();
    level waittill( "gf_ot_done", winner );

    level.gf_roundEnding = true;
    level.gf_overtimeClockRunning = false;
    gf_cleanupOvertimeZone( zone );
    gf_cleanupOvertimeTimerState();

    gf_endRound( winner );
}

gf_overtimeZoneGameEndCleanup( zone )
{
    level endon( "gf_ot_done" );
    level waittill( "game_ended" );
    gf_cleanupOvertimeZone( zone );
}

gf_showOvertimeMessage()
{
    maps\mp\_utility::playSoundOnPlayers( "mpl_hq_cap_us" );

    // Announcer VO: stock "Overtime" callout ("overtime" comes from the shared
    // _globallogic_audio::init() dialog table). No team arg -> both teams hear it.
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "overtime" );

    // The CTF cue follows it — but held by us, not by the stock queue. See gf_overtimeCueVO.
    level thread gf_overtimeCueVO();

    titleText = &"MP_OVERTIME_CAPS";
    if ( isDefined( game["strings"] ) && isDefined( game["strings"]["overtime"] ) )
        titleText = game["strings"]["overtime"];

    // 6th arg = duration (seconds). Without it the message uses
    // level.startMessageDefaultDuration (2.0s), which vanishes too fast.
    overtimeMsgDuration = 5.0;

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        player thread maps\mp\gametypes\_hud_message::oldNotifyMessage( titleText, undefined, undefined, ( 1, 0, 0 ), undefined, overtimeMsgDuration );
    }
}

// The CTF cue ("ctf_start", registered as game["dialog"]["gf_overtime_cue"] in
// gf.gsc::onPrecacheGameType) that follows the stock "Overtime" callout.
//
// It does NOT go through leaderDialog, for two reasons:
//   1. Cancellable. leaderDialog queues the line into self.leaderDialogQueue, and the drain
//      thread (playLeaderDialogOnPlayer) carries only self endon("disconnect") — nothing
//      round-scoped. So a queued line fires even if the round has already ended, which is why
//      a 2-second overtime still announced "capture the flag". Holding the line ourselves lets
//      gf_ot_done / game_ended kill it before it is ever spoken.
//   2. Timing. The queue's spacing is a hardcoded wait(3.0) in playLeaderDialogOnPlayer, so
//      anything behind "Overtime" lands at exactly 3.0s. We want 2.0s.
//
// Playing the alias directly is what the stock path does anyway — faction prefix + dialog key.
gf_overtimeCueVO()
{
    level endon( "gf_ot_done" );
    level endon( "game_ended" );

    // Tune freely — this is the only thing that sets the gap behind the "Overtime" callout.
    // Too low and the two lines talk over each other (stock's queue used a blanket 3.0).
    wait( 1.0 );

    if ( isDefined( level.allowAnnouncer ) && !level.allowAnnouncer )
        return;
    if ( !isDefined( game["dialog"] ) || !isDefined( game["dialog"]["gf_overtime_cue"] ) )
        return;

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        team = player.pers["team"];
        if ( !isDefined( team ) || ( team != "allies" && team != "axis" ) )
            continue;

        if ( isDefined( level.wagerMatch ) && level.wagerMatch )
            faction = "vox_wm_";
        else if ( isDefined( game["voice"] ) && isDefined( game["voice"][team] ) )
            faction = game["voice"][team];
        else
            continue;

        player playLocalSound( faction + game["dialog"]["gf_overtime_cue"] );
    }
}

gf_overtimeClock()
{
    level endon( "game_ended" );

    while ( isDefined( level.gf_overtimeClockRunning ) && level.gf_overtimeClockRunning )
    {
        if ( !level.gf_overtimeActive || level.gf_overtimeResolving )
            return;

        gf_syncOvertimeRemaining();
        if ( level.gf_overtimeRemaining <= 0 )
        {
            hpWinner = gf_getHPWinner();
            level.gf_endReasonText = gf_reasonText( "health", hpWinner );
            gf_resolveOvertime( hpWinner );
            return;
        }

        if ( !isDefined( level.gf_overtimePaused ) || !level.gf_overtimePaused )
        {
            gf_updateOvertimeGameEndTime();
            gf_updateOvertimeTickSound();
        }

        wait 0.1;
    }
}

gf_syncOvertimeRemaining()
{
    if ( !isDefined( level.gf_overtimeLastTime ) )
        level.gf_overtimeLastTime = gettime();

    now = gettime();
    elapsed = now - level.gf_overtimeLastTime;
    level.gf_overtimeLastTime = now;

    if ( isDefined( level.gf_overtimePaused ) && level.gf_overtimePaused )
        return;

    if ( elapsed > 0 )
        level.gf_overtimeRemaining -= elapsed;

    if ( level.gf_overtimeRemaining < 0 )
        level.gf_overtimeRemaining = 0;
}

gf_updateOvertimeGameEndTime()
{
    if ( !isDefined( level.gf_overtimeRemaining ) )
        return;

    remaining = level.gf_overtimeRemaining;
    if ( remaining < 0 )
        remaining = 0;

    setGameEndTime( int( gettime() + remaining ) );
}

gf_updateOvertimeTickSound()
{
    if ( !isDefined( level.gf_overtimeRemaining ) )
        return;

    remaining = level.gf_overtimeRemaining;
    if ( remaining <= 0 || remaining > 10000 )   // tick only in the final 10s
        return;

    // 1 beep/sec from 10s -> 5s (matches the round beeps), then 2 beeps/sec for the final 5s.
    // Driven off the OT remaining time, NOT wall-clock, so it honors the capture pause/resume —
    // gf_overtimeClock only calls this while the clock is running, and remaining freezes during a
    // pause, so the cadence freezes with it.
    if ( remaining > 5000 )  interval = 1000;   // 10s..5s : 1/sec
    else                     interval = 500;    // last 5s : 2/sec

    // First tick fires immediately on entering the 10s window (lastTickMs undefined); after that,
    // tick once the remaining time has dropped by at least the current interval.
    if ( isDefined( level.gf_overtimeLastTickMs ) && ( level.gf_overtimeLastTickMs - remaining ) < interval )
        return;

    level.gf_overtimeLastTickMs = remaining;

    if ( isDefined( level.gf_overtimeTickObject ) )
        level.gf_overtimeTickObject playSound( "mpl_ui_timer_countdown" );
}

gf_pauseOvertimeForCapture()
{
    if ( !isDefined( level.gf_overtimeActive ) || !level.gf_overtimeActive )
        return;

    if ( !isDefined( level.gf_overtimePauseDepth ) )
        level.gf_overtimePauseDepth = 0;

    level.gf_overtimePauseDepth++;
    if ( level.gf_overtimePauseDepth > 1 )
        return;

    gf_syncOvertimeRemaining();
    level.gf_overtimePaused = true;
    setGameEndTime( 0 );   // hide the clock while paused; a re-push "freeze" flickers (engine has no display-hold)
}

gf_resumeOvertimeForCapture()
{
    if ( !isDefined( level.gf_overtimeActive ) || !level.gf_overtimeActive )
        return;

    if ( !isDefined( level.gf_overtimePauseDepth ) || level.gf_overtimePauseDepth <= 0 )
        level.gf_overtimePauseDepth = 0;
    else
        level.gf_overtimePauseDepth--;

    if ( level.gf_overtimePauseDepth > 0 )
        return;

    level.gf_overtimePaused = false;
    level.gf_overtimeLastTime = gettime();
    gf_updateOvertimeGameEndTime();
}

gf_cleanupOvertimeTimerState()
{
    level.gf_overtimeActive       = false;
    level.gf_overtimeResolving    = false;
    level.gf_overtimePaused       = false;
    level.gf_overtimePauseDepth   = 0;
    level.gf_overtimeRemaining    = undefined;
    level.gf_overtimeLastTime     = undefined;
    level.gf_overtimeLastTickMs   = undefined;
    level.gf_overtimeClockRunning = false;
    level.inOvertime              = false;
    level.timeLimitOverride       = false;

    if ( isDefined( level.gf_overtimeTickObject ) )
    {
        level.gf_overtimeTickObject delete();
        level.gf_overtimeTickObject = undefined;
    }

    setGameEndTime( 0 );
}

// Sets the 2D minimap icon and the 3D world icon together, from the SAME native
// _gameobjects path, so they can never disagree. For a given relative-team slot the
// 2D uses "compass_waypoint_X" and the 3D uses "waypoint_X" — the same artwork in
// minimap vs world form, so their colors coincide by construction regardless of the
// shaders' baked colors. dom.gsc convention: "defend" renders in the friendly/owner
// color (green), "capture" in the enemy color (red), "captureneutral" white.
//
// NOTE (engine constraint): the per-team friendly/enemy coloring works here because
// these are native team-routed objective/objpoint elements. It CANNOT be done with
// world-space FX (the apron) — those render identically for every player. So the
// team-relative green/red lives on these icons; the apron is an absolute cue only.
gf_setOvertimeZoneIcons( zone, friendlyIcon, enemyIcon )
{
    zone maps\mp\gametypes\_gameobjects::set2DIcon( "friendly", "compass_waypoint_" + friendlyIcon );
    zone maps\mp\gametypes\_gameobjects::set3DIcon( "friendly", "waypoint_"         + friendlyIcon );
    zone maps\mp\gametypes\_gameobjects::set2DIcon( "enemy",    "compass_waypoint_" + enemyIcon );
    zone maps\mp\gametypes\_gameobjects::set3DIcon( "enemy",    "waypoint_"         + enemyIcon );
}

gf_setOvertimeZoneIconColor( zone, team )
{
    if ( !isDefined( zone ) )
        return;

    if ( isDefined( zone.flagModel ) )
    {
        if ( team == "allies" )
            zone.flagModel setModel( "mp_flag_allies_1" );
        else if ( team == "axis" )
            zone.flagModel setModel( "mp_flag_axis_1" );
        else
            zone.flagModel setModel( "mp_flag_neutral" );
    }

    // Ground apron FX — delete old handle, spawn the color for this state.
    // World-space FX (same for all viewers), so it's an absolute zone-activity cue,
    // NOT team-relative: white idle, gold while a team captures, red contested.
    // Team-relative green/red lives on the 3D icon — see CLAUDE.md OT zone color system.
    if ( isDefined( zone.baseFxPos ) )
    {
        if ( isDefined( zone.baseFxHandle ) )
        {
            zone.baseFxHandle delete();
            zone.baseFxHandle = undefined;
        }

        fxAsset = level.gf_ot_baseFx_neutral;   // white apron when idle
        if ( team == "allies" )
            fxAsset = level.gf_ot_baseFx_allies;
        else if ( team == "axis" )
            fxAsset = level.gf_ot_baseFx_axis;
        else if ( team == "contested" )
            fxAsset = level.gf_ot_baseFx_contested;

        if ( isDefined( fxAsset ) )
        {
            zone.baseFxHandle = spawnFx( fxAsset, zone.baseFxPos, zone.baseFxFwd, zone.baseFxRight );
            triggerFx( zone.baseFxHandle );
        }
    }

    // Icons: the capturing team is set as ownerTeam, so _gameobjects routes that team
    // into the "friendly" slot and the other team into "enemy". Both the 2D minimap and
    // 3D world icon are set together (gf_setOvertimeZoneIcons) so they always coincide.
    // friendly = defend (green), enemy = capture (red), idle/contested = captureneutral.
    if ( team == "allies" || team == "axis" )
    {
        zone maps\mp\gametypes\_gameobjects::setOwnerTeam( team );
        gf_setOvertimeZoneIcons( zone, "defend", "capture" );   // capturers green, defenders red
    }
    else
    {
        // neutral (nobody capturing) and contested both resolve to a white icon for all.
        zone maps\mp\gametypes\_gameobjects::setOwnerTeam( "neutral" );
        gf_setOvertimeZoneIcons( zone, "captureneutral", "captureneutral" );
    }
}

// Polls player positions every 0.1 s and drives all OT zone visuals (FX apron,
// 3D icons, 2D flash, timer pause/resume).  Replaces the onBeginUse / onEndUse /
// onUseUpdate callbacks, which suffered from a _gameobjects numTouching race
// condition that caused flicker and missed-capture visual glitches.
gf_overtimeZoneVisuals( zone, flagTrigger )
{
    level endon( "game_ended" );
    level endon( "gf_ot_done" );

    curState  = "neutral";
    label     = zone maps\mp\gametypes\_gameobjects::getLabel();

    while ( true )
    {
        wait 0.1;

        if ( !isDefined( zone ) || !isDefined( flagTrigger ) )
            return;

        alliesCount = 0;
        axisCount   = 0;

        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( p.sessionstate != "playing" ) continue;
            if ( !isAlive( p ) ) continue;
            if ( !( p isTouching( flagTrigger ) ) ) continue;

            team = p.pers["team"];
            if ( team == "allies" )      alliesCount++;
            else if ( team == "axis" )   axisCount++;
        }

        newState = "neutral";
        if ( alliesCount > 0 && axisCount > 0 )   newState = "contested";
        else if ( alliesCount > 0 )                newState = "allies";
        else if ( axisCount   > 0 )                newState = "axis";

        if ( newState == curState )
            continue;

        oldState = curState;
        curState  = newState;

        gf_setOvertimeZoneIconColor( zone, curState );
        setDvar( "scr_obj" + label + "_flash", int( curState != "neutral" ) );
        setDvar( "scr_obj" + label, curState );

        if ( isDefined( zone.objPoints ) )
        {
            if ( curState != "neutral" && curState != "contested" && isDefined( zone.objPoints[curState] ) )
                zone.objPoints[curState] thread maps\mp\gametypes\_objpoints::startFlashing();
            if ( oldState != "neutral" && oldState != "contested" && isDefined( zone.objPoints[oldState] ) )
                zone.objPoints[oldState] thread maps\mp\gametypes\_objpoints::stopFlashing();
        }

        if ( oldState == "neutral" && curState != "neutral" )
        {
            gf_pauseOvertimeForCapture();
        }
        else if ( oldState != "neutral" && curState == "neutral" )
        {
            if ( !isDefined( level.gf_overtimeResolving ) || !level.gf_overtimeResolving )
                gf_resumeOvertimeForCapture();
        }
    }
}

gf_cleanupOvertimeZone( zone )
{
    if ( !isDefined( zone ) )
        return;

    if ( isDefined( zone.baseFxHandle ) )
        zone.baseFxHandle delete();
    zone.baseFxHandle = undefined;
    zone.baseFxPos    = undefined;

    zone.interactTeam = "none";
    zone.onUse        = undefined;
    zone.curProgress  = 0;
    zone.claimTeam    = "none";
    zone.claimPlayer  = undefined;

    // Reset ownerTeam before hiding so updateCompassIcons sees a clean state.
    zone maps\mp\gametypes\_gameobjects::setOwnerTeam( "neutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );

    // Delete objectives so their IDs are freed each round (they accumulate otherwise).
    if ( isDefined( zone.objIDAllies ) )
        objective_delete( zone.objIDAllies );
    if ( isDefined( zone.objIDAxis ) )
        objective_delete( zone.objIDAxis );

    // Delete 3D objPoint HUD elements. Custom trigger maps spawn a new trigger entity
    // each overtime round (new entNum → new name), so _gameobjects won't recycle them.
    if ( isDefined( zone.objPoints ) )
    {
        if ( isDefined( zone.objPoints["allies"] ) )
            maps\mp\gametypes\_objpoints::deleteObjPoint( zone.objPoints["allies"] );
        if ( isDefined( zone.objPoints["axis"] ) )
            maps\mp\gametypes\_objpoints::deleteObjPoint( zone.objPoints["axis"] );
        zone.objPoints = [];
    }

    if ( isDefined( zone.spawnedModel ) )
        zone.spawnedModel delete();

    if ( isDefined( zone.customTrigger ) )
        zone.customTrigger delete();
}

// Re-registers the OT apron FX handles. MUST run every OT entry, not just at
// precache: onPrecacheGameType runs once per match (guarded by game["gamestarted"]),
// but _globallogic::endGame does map_restart(true) between rounds, which wipes all
// level.* vars — so the handles set at precache are undefined by round 2. loadfx()
// at runtime re-establishes them. The custom .efx live in mod.ff and stay in the
// loaded zone for the whole server session, so loadfx finds them every round.
gf_loadOvertimeApronFx()
{
    // The apron is WORLD-SPACE FX — it renders identically for every player, so it
    // physically cannot be team-relative (T5 has no per-team FX visibility). It is an
    // absolute "zone activity" cue:  idle = white, capturing (either team) = gold,
    // contested = red.  The team-relative friendly/enemy color (green/red) lives on
    // the 3D icon instead (newTeamHudElem, per-team).  White is the custom mod.ff halo;
    // gold/red are stock common_mp_fx ground markers (always runtime-loadable). loadfx
    // is re-called every OT entry because map_restart(true) between rounds wipes these
    // level.* handles.
    whiteFx = loadfx( "misc/fx_ui_flagbase_gf_white" );            // custom (mod.ff)
    goldFx  = loadfx( "env/light/fx_ray_grnd_loc_marker_ylw_mp" ); // stock (yellow ~ gold)
    redFx   = loadfx( "env/light/fx_ray_grnd_loc_marker_red_mp" ); // stock

    level.gf_ot_baseFx_neutral   = whiteFx;   // nobody capturing
    level.gf_ot_baseFx_allies    = goldFx;    // a team is capturing
    level.gf_ot_baseFx_axis      = goldFx;    // ...same gold regardless of which team
    level.gf_ot_baseFx_contested = redFx;     // both teams contesting
}

gf_createOvertimeZone()
{
    flagTrigger = gf_getOvertimeFlagTrigger();
    if ( !isDefined( flagTrigger ) )
        return undefined;

    // Refresh FX handles wiped by the previous round's map_restart.
    gf_loadOvertimeApronFx();

    traceStart = flagTrigger.origin + ( 0, 0, 32 );
    traceEnd   = flagTrigger.origin + ( 0, 0, -256 );
    trace      = bulletTrace( traceStart, traceEnd, false, undefined );
    upAngles   = vectorToAngles( trace["normal"] );
    fxFwd      = anglesToForward( upAngles );
    fxRight    = anglesToRight( upAngles );
    fxPos      = trace["position"] + ( 0, 0, 1 );

    // Use the map-linked visual if it exists; otherwise spawn one
    if ( isDefined( flagTrigger.target ) )
    {
        flagModel        = getEnt( flagTrigger.target, "targetname" );
        spawnedModel     = undefined;
    }
    else
    {
        flagModel        = spawn( "script_model", flagTrigger.origin );
        flagModel.angles = flagTrigger.angles;
        spawnedModel     = flagModel;
    }
    flagModel setModel( "mp_flag_neutral" );

    visuals    = [];
    visuals[0] = flagModel;

    zone = maps\mp\gametypes\_gameobjects::createUseObject( "neutral", flagTrigger, visuals, ( 0, 0, 100 ) );

    zone maps\mp\gametypes\_gameobjects::allowUse( "any" );
    zone maps\mp\gametypes\_gameobjects::setUseTime( gf_getCaptureTime() );
    zone maps\mp\gametypes\_gameobjects::setUseText( &"MP_CAPTURING_FLAG" );
    gf_setOvertimeZoneIcons( zone, "captureneutral", "captureneutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "any" );
    zone.onUse           = ::gf_onZoneCapture;
    zone.spawnedModel    = spawnedModel;
    zone.didStatusNotify = false;

    if ( isDefined( flagTrigger.gf_customOvertimeTrigger ) && flagTrigger.gf_customOvertimeTrigger )
        zone.customTrigger = flagTrigger;

    zone.flagModel   = flagModel;
    zone.gf_flagTrigger = flagTrigger;   // capture point for the bot OT AI
    zone.baseFxPos   = fxPos;
    zone.baseFxFwd   = fxFwd;
    zone.baseFxRight = fxRight;
    gf_setOvertimeZoneIconColor( zone, "neutral" );

    level thread gf_overtimeZoneVisuals( zone, flagTrigger );

    return zone;
}

gf_getOvertimeFlagTrigger()
{
    flag = gf_findDominationBFlag();

    // Large mode plays the full map, so the OT objective sits at the native
    // Domination B (neutral/center) flag. Only small mode moves it to the
    // curated, shrunk-zone overtime spot.
    if ( !level.gf_largeMode && isDefined( level.gf_customOvertimeLocation ) )
    {
        if ( isDefined( flag ) )
        {
            gf_applyCustomOvertimeLocationToFlag( flag, level.gf_customOvertimeLocation );
            return flag;
        }

        return gf_spawnCustomOvertimeTrigger( level.gf_customOvertimeLocation );
    }

    return flag;
}

gf_findDominationBFlag()
{
    flags = getEntArray( "flag_primary", "targetname" );
    flag = undefined;
    for ( i = 0; i < flags.size; i++ )
    {
        if ( isDefined( flags[i].script_label ) && flags[i].script_label == "_b" )
        {
            flag = flags[i];
            break;
        }
    }

    if ( !isDefined( flag ) && flags.size > 0 )
        flag = flags[ int( flags.size / 2 ) ];

    return flag;
}

gf_applyCustomOvertimeLocationToFlag( flag, location )
{
    flag.origin = location["origin"];
    flag.angles = location["angles"];

    if ( !isDefined( flag.target ) )
        return;

    visuals = getEntArray( flag.target, "targetname" );
    for ( i = 0; i < visuals.size; i++ )
    {
        visuals[i].origin = location["origin"];
        visuals[i].angles = location["angles"];
    }
}

gf_spawnCustomOvertimeTrigger( location )
{
    radius = 96;
    height = 96;

    if ( isDefined( location["radius"] ) )
        radius = location["radius"];
    if ( isDefined( location["height"] ) )
        height = location["height"];

    trigger = spawn( "trigger_radius", location["origin"], 0, radius, height );
    trigger.angles = location["angles"];
    trigger.gf_customOvertimeTrigger = true;

    return trigger;
}

gf_onZoneCapture( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) ) return;
    if ( isDefined( level.gf_overtimeResolving ) && level.gf_overtimeResolving ) return;

    player gf_awardOvertimeCapture();
    level.gf_endReasonText = gf_reasonText( "capture", player.pers["team"] );
    gf_resolveOvertime( player.pers["team"] );
}

// #strip-begin - BOT OVERTIME CAPTURE AI (dev/main only; stripped from public release)
// The public build ships no bot framework (_bot.gsc and maps/mp/bots/* are dropped) and no
// reconciler to add bots, so nothing here would ever have a bot to steer.
//
// ─── Bot Overtime Capture AI ───────────────────────────────────────────────
// Bots have no built-in concept of our overtime flag, so during OT we steer
// them onto it the same way stock bots cap a DOM flag (_bot_script::bot_cap_get_flag):
// lock the goal and SetScriptGoal onto the flag. The OT flag is a _gameobjects
// PROXIMITY object (its trigger is a trigger_radius, so createUseObject runs
// useObjectProxThink, NOT the hold-USE useObjectUseThink) — so simply STANDING
// in the trigger accrues curProgress and fires zone.onUse ( = gf_onZoneCapture ).
// No button press, no custom capture logic — just navigation, like a human walking on.
// Threads die on gf_ot_done / game_ended; the leftover goal+lock are reset by
// the round's map_restart, and the killcam hides any brief leftover camp.
gf_botOvertimeAI( zone )
{
    level endon( "game_ended" );
    level endon( "gf_ot_done" );

    if ( !isDefined( zone ) || !isDefined( zone.gf_flagTrigger ) )
        return;

    flagTrigger = zone.gf_flagTrigger;

    for ( i = 0; i < level.players.size; i++ )
    {
        p = level.players[i];
        if ( !isDefined( p ) ) continue;
        if ( !isDefined( p.pers["isBot"] ) || !p.pers["isBot"] ) continue;
        if ( p.pers["team"] != "allies" && p.pers["team"] != "axis" ) continue;
        if ( !isAlive( p ) ) continue;

        p thread gf_botPursueOvertimeZone( flagTrigger );
    }
}

gf_botPursueOvertimeZone( flagTrigger )
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );
    level endon( "gf_ot_done" );

    if ( !isDefined( flagTrigger ) )
        return;

    // Small radius so the bot stops standing ON the flag (well inside the
    // trigger), matching the stock DOM cap goal. Standing is all it takes —
    // useObjectProxThink accrues the capture while the bot touches.
    radius = 32;

    // Lock BEFORE setting the goal; the "new_goal" notify makes any think thread
    // already parked on its own goal release it to us without clearing it.
    self.bot_lock_goal = true;
    self gf_botSetGoal( flagTrigger.origin, radius );

    // Keep the bot camped on the flag for the whole OT; re-assert the goal if it
    // gets knocked off so it walks back. The proximity think does the capturing.
    for ( ;; )
    {
        wait 1;

        if ( !isDefined( flagTrigger ) )
            break;

        if ( !self isTouching( flagTrigger ) )
            self gf_botSetGoal( flagTrigger.origin, radius );
    }
}

// Local copy of the stock _bot_utility::SetBotGoal wrapper so this file carries
// no bot-script dependency. The waittillframeend + "new_goal" notify is what
// lets us take a goal away from a bot's own AI without it being cleared back.
gf_botSetGoal( origin, radius )
{
    self SetScriptGoal( origin, radius );
    waittillframeend;
    self notify( "new_goal" );
}
// #strip-end


// Called by _globallogic to determine the overall match leader at round end.
// Must compare cumulative roundswon — NOT the single-round result.
gf_onRoundEndGame()
{
    if ( game["roundswon"]["allies"] == game["roundswon"]["axis"] )
        return "tie";
    else if ( game["roundswon"]["axis"] > game["roundswon"]["allies"] )
        return "axis";
    return "allies";
}

// ─── Optional Callbacks ────────────────────────────────────────────────────

gf_onPlayerKilled( eInflictor, attacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration )
{
    // Scoreboard dead-marker: our white skull instead of the stock medal. Safe to write
    // here because stock sets "hud_status_dead" early in Callback_PlayerKilled
    // (_globallogic_player.gsc:1292) but does not invoke this hook until line 1698 — so
    // this lands after it, not before. ONLY the dead value is overridden: the match-start
    // load gate identifies still-loading clients by statusicon == "hud_status_connecting"
    // (gf_anyTrackedClientLoading), so that value must keep its stock meaning.
    self.statusicon = "hud_death_suicide";

    // On death, every player who damaged the victim (killer and assisters alike)
    // sees a popup with their own exact damage share — no floor.
    victimKey = "v" + int( self.entnum );

    // Cap: recorded damage can overshoot applied damage (recorded pre-mitigation),
    // so never show more than one player's worth of health for a single death.
    cap = 100;
    if ( isDefined( self.maxhealth ) && self.maxhealth > 0 )
        cap = self.maxhealth;

    if ( isDefined( self.gf_assisters ) )
    {
        // Popups first in their own pass — a hiccup in the score/assist bookkeeping
        // below must never block a later damager's popup.
        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            damager = self.gf_assisters[i];
            if ( !isDefined( damager ) || !isPlayer( damager ) ) continue;
            if ( !isDefined( damager.gf_dmgOnTarget ) || !isDefined( damager.gf_dmgOnTarget[victimKey] ) ) continue;

            popup = damager.gf_dmgOnTarget[victimKey];
            damager.gf_dmgOnTarget[victimKey] = undefined;
            if ( popup > cap )
                popup = cap;

            logPrint( "GF_POPUP: " + self.name + " died, " + damager.name + " share " + popup + "\n" );

            // Text popups instead of damage numbers: killer sees "Elimination"
            // (priority 2), every other damager sees "Assist" (priority 1).
            // Localized istrings from gf.str (mod.ff) — raw string literals here would
            // allocate from the dynamic string table, which can be exhausted (the raw
            // "Elimination" literal silently failed to render for exactly that reason).
            if ( !isDefined( damager.pers["isBot"] ) || !damager.pers["isBot"] )
            {
                if ( isDefined( attacker ) && damager == attacker )
                    damager thread gf_showScorePopup( 2, 2 );   // type 2 = elimination, pri 2
                else
                    damager thread gf_showScorePopup( 1, 1 );   // type 1 = assist, pri 1
            }
        }

        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            damager = self.gf_assisters[i];
            if ( !isDefined( damager ) || !isPlayer( damager ) ) continue;

            damager gf_syncDamageScore();

            // Assist XP. This MUST go straight to _rank::giveRankXP — the stock
            // _globallogic_score::givePlayerScore( "assist", … ) we used to call here returns on
            // its first line because gf.gsc sets level.overridePlayerScore, so it awarded nothing
            // (the killer's own XP is unaffected: giveKillStats fires from Callback_PlayerKilled,
            // which does not go through givePlayerScore). Flat "assist" tier for every damager —
            // the assist_25/50/75 tiers are stock's damage-fraction split, which only giveAssist()
            // can reach, and that is on the dead path too. Bots earn nothing worth spending a
            // reliable command on, but the XP call is server-side and free, so no bot filter.
            if ( !isDefined( attacker ) || damager != attacker )
                damager thread maps\mp\gametypes\_rank::giveRankXP( "assist" );
        }
        self.gf_assisters = [];
    }

    gf_forceHealthHUDUpdate();

    if ( isDefined( level.gf_roundActive ) && level.gf_roundActive )
    {
        victimTeam = self.pers["team"];
        if ( victimTeam == "allies" || victimTeam == "axis" )
        {
            otherTeam = maps\mp\_utility::getOtherTeam( victimTeam );
            maps\mp\_utility::playSoundOnPlayers( "mpl_flagdrop_sting_friend", victimTeam );
            maps\mp\_utility::playSoundOnPlayers( "mpl_flagget_sting_friend",  otherTeam );
        }
    }
}

gf_onPlayerDisconnect()
{
    gf_queueHealthHUDUpdate();
}

gf_onPlayerDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime )
{
    if ( iDamage <= 0 )
        return iDamage;

    if ( self.sessionstate == "playing" && isDefined( self.health ) && self.health > 0 )
        gf_queueHealthHUDUpdate();

    if ( !isDefined( eAttacker ) || !isPlayer( eAttacker ) || eAttacker == self )
        return iDamage;

    if ( !isDefined( self.pers["team"] ) || !isDefined( eAttacker.pers["team"] ) )
        return iDamage;

    if ( self.pers["team"] == eAttacker.pers["team"] )
        return iDamage;

    if ( self.sessionstate != "playing" || eAttacker.sessionstate != "playing" )
        return iDamage;

    hp = self.health;
    if ( hp <= 0 )
        return iDamage;

    if ( isDefined( level.gf_headshotsOnly ) && level.gf_headshotsOnly )
    {
        if ( sHitLoc != "head" && sHitLoc != "helmet" )
            return 0;
    }

    damage = iDamage;
    if ( damage > hp )
        damage = hp;

    if ( damage > 0 )
    {
        if ( !isDefined( eAttacker.pers["gf_damage"] ) )
            eAttacker.pers["gf_damage"] = 0;

        eAttacker.pers["gf_damage"] += damage;
        gf_setPlayerScoreSilent( eAttacker, eAttacker.pers["gf_damage"] );

        // Per-target damage for kill popup
        victimKey = "v" + int( self.entnum );
        if ( !isDefined( eAttacker.gf_dmgOnTarget ) )
            eAttacker.gf_dmgOnTarget = [];
        if ( !isDefined( eAttacker.gf_dmgOnTarget[victimKey] ) )
            eAttacker.gf_dmgOnTarget[victimKey] = 0;
        eAttacker.gf_dmgOnTarget[victimKey] += damage;

        // Track unique assisters on the victim for assist awarding on kill
        if ( !isDefined( self.gf_assisters ) )
            self.gf_assisters = [];
        alreadyTracked = false;
        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            if ( self.gf_assisters[i] == eAttacker ) { alreadyTracked = true; break; }
        }
        if ( !alreadyTracked )
            self.gf_assisters[self.gf_assisters.size] = eAttacker;

        gf_queueHealthHUDUpdate();
    }

    return iDamage;
}

gf_initDamageScoring()
{
    if ( !isDefined( game["gf_damage_match"] ) )
        game["gf_damage_match"] = gettime();

    if ( isDefined( game["gf_damage_init"] ) )
        return;

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        player.pers["gf_damage"] = 0;
        player.pers["gf_damage_match"] = game["gf_damage_match"];
        player gf_syncDamageScore();
    }

    game["gf_damage_init"] = 1;
}

gf_syncCaptureScore()
{
    if ( !isDefined( self.pers["captures"] ) )
        self.pers["captures"] = 0;

    self.captures = self.pers["captures"];
}

gf_awardOvertimeCapture()
{
    if ( !isDefined( self.pers["captures"] ) )
        self.pers["captures"] = 0;

    self.pers["captures"]++;
    self.captures = self.pers["captures"];
}

gf_initDamageScore()
{
    if ( !isDefined( game["gf_damage_match"] ) )
        game["gf_damage_match"] = gettime();

    if ( !isDefined( self.pers["gf_damage_match"] ) || self.pers["gf_damage_match"] != game["gf_damage_match"] )
    {
        self.pers["gf_damage"] = 0;
        self.pers["gf_damage_match"] = game["gf_damage_match"];
    }

    self gf_syncDamageScore();
}

gf_syncDamageScore()
{
    if ( !isDefined( self.pers["gf_damage"] ) )
        self.pers["gf_damage"] = 0;

    gf_setPlayerScoreSilent( self, self.pers["gf_damage"] );
}

// Sets player score without triggering updateRankScoreHUD popup.
// The default _setPlayerScore calls updateRankScoreHUD for private matches,
// which shows a score delta popup on every damage event.
gf_setPlayerScoreSilent( player, score )
{
    if ( score == player.pers["score"] )
        return;
    player.pers["score"] = score;
    player.score         = player.pers["score"];
    player notify( "update_playerscore_hud" );
}

gf_queueHealthHUDUpdate()
{
    if ( isDefined( level.gf_healthUpdateQueued ) && level.gf_healthUpdateQueued )
        return;

    level.gf_healthUpdateQueued = true;
    level thread gf_doQueuedHealthHUDUpdate();
}

gf_doQueuedHealthHUDUpdate()
{
    wait 0.05;
    level.gf_healthUpdateQueued = false;

    gf_forceHealthHUDUpdate();
}

gf_forceHealthHUDUpdate()
{
    level notify( "gf_health_hud_update" );
}

gf_onOneLeftEvent( team )
{
    if ( isDefined( level.gf_roundEnding ) && level.gf_roundEnding )
        return;

    if ( !isDefined( level.gf_roundActive ) || !level.gf_roundActive )
        return;

    if ( team != "allies" && team != "axis" )
        return;

    if ( !isDefined( level.gf_warnedLastPlayer ) )
        level.gf_warnedLastPlayer = [];

    if ( isDefined( level.gf_warnedLastPlayer[team] ) )
        return;

    level.gf_warnedLastPlayer[team] = true;

    // onOneLeftEvent fires when level.aliveCount[team] == 1, so the engine-maintained
    // level.alivePlayers[team] holds exactly that last living player at index 0.
    if ( level.alivePlayers[team].size <= 0 )
        return;
    player = level.alivePlayers[team][0];

    player maps\mp\gametypes\_globallogic_audio::leaderDialogOnPlayer( "last_one" );
    player playLocalSound( "mus_last_stand" );
}

gf_onRoundSwitch()
{
    if ( !isDefined( game["switchedsides"] ) )
        game["switchedsides"] = false;

    game["switchedsides"] = !game["switchedsides"];
    level.halftimeType = "halftime";

    maps\mp\gametypes\_globallogic::resetOutcomeForAllPlayers();
}

// ─── Utilities ─────────────────────────────────────────────────────────────

// Sum of living HP for a team. level.alivePlayers[team] is the engine-maintained array of
// alive, playing players on that team (built in _globallogic::updateTeamStatus), so it's
// exactly the set the old all-players scan filtered to. The health>0 guard is redundant
// (alive implies it) but kept defensive.
gf_getTeamHP( team )
{
    total = 0;
    arr = level.alivePlayers[team];
    for ( i = 0; i < arr.size; i++ )
    {
        p = arr[i];
        if ( isDefined( p ) && isDefined( p.health ) && p.health > 0 )
            total += p.health;
    }
    return total;
}

gf_getHPWinner()
{
    alliesHP = gf_getTeamHP( "allies" );
    axisHP   = gf_getTeamHP( "axis"   );

    if ( alliesHP > axisHP )
        return "allies";
    if ( axisHP > alliesHP )
        return "axis";

    return "tie";
}

// Neutral round-end reason string for the native WIN/LOSS banner subtitle
// (outcomeText in _hud_message::teamOutcomeNotify, fed via endGame's 2nd arg).
// The banner header is already team-relative (ROUND WIN / ROUND LOSS / ROUND DRAW),
// so the subtitle states the absolute reason. Title Case, no trailing period — a GF house
// style, deliberately NOT stock's (the shipped strings are sentence case: "Bomb defused",
// "Score limit reached"; the ALL-CAPS belongs to the HEADER, a separate _CAPS key family).
// The engine setText's the subtitle raw and never re-cases it, so the case lives entirely
// in these literals. ⚠ Stock's own match-end subtitle renders on the SAME banner seconds
// after our final round one, so it is re-cased to match in gf.gsc onStartGameType
// (game["strings"]["score_limit_reached"] et al) — change the case here and there, or the
// last banner of a match reads in two styles.
// reason: "capture" (OT flag taken) | "health" (timer/OT decided by total HP) |
//         "elim" (a team fully wiped out). winner == "tie" => draw wording.
gf_reasonText( reason, winner )
{
    isTie = ( !isDefined( winner ) || winner == "tie" );

    if ( reason == "capture" )
        return "Objective Captured";

    if ( reason == "elim" )
    {
        if ( isTie )
            return "Both Teams Eliminated";
        return "Team Eliminated";
    }

    // health
    if ( isTie )
        return "Time Expired - Equal Health";
    return "Time Expired - Health Advantage";
}
