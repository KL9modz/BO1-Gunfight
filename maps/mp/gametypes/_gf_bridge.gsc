// GSC Bridge -- RCON -> GSC dispatcher
// RCON sends: set gf_cmd <seq>:<command>   (the "<seq>:" prefix is optional; a bare <command>
// still runs but isn't acked). This poll loop (20 Hz) reads, clears, dispatches, and writes the
// processed <seq> into gf_ack so the panel can flip a command from "sent" to "received".
// Feedback is PRIVATE: gf_bridgeNotify prints only to admins listed in gf_admin_guids (not everyone).
//
// Commands (send via RCON: set gf_cmd <seq>:<cmd>):
//   pause              - freeze match clock + all player controls; B&W vision + MATCH PAUSED banner
//   resume             - resume clock + unfreeze players; restore vision + drop the banner
//   botdiff_easy/normal/hard/fu  - set bot difficulty
//   endround_allies    - force allies to win this round
//   endround_axis      - force axis to win this round
//   roundrestart       - replay the current round: nobody scores, the loadout does not
//                        rotate, the sides do not switch
//   matchrestart       - restart the whole match: scores 0-0, back to round 1, same map + teams,
//                        full match-start presentation (map_restart(false), no map reload)
//   god_on / god_off   - toggle invulnerability for all players
//   allperks_on        - give all players a useful dev perk set
//   allperks_off       - remove those perks
//   perksync           - re-apply gf_perk_on / gf_perk_off lists to live players
//                        (rcon Perks tab; loadout re-applies them each spawn)
//   infammo_on         - sv_FullAmmo 1 + one-shot refill of live players
//   infammo_off        - sv_FullAmmo 0
//   radar_on / radar_off       - force UAV: scr_game_forceradar + live radar match flags
//   headshots_on / headshots_off - non-headshot damage zeroed
//   pgod_<num>         - god mode one player by entitynum
//   pfreeze_<num>      - freeze one player
//   punfreeze_<num>    - unfreeze one player
//   pperks_<num>       - give perks to one player
//   (NO pnoclip_: this was documented here for a long time but never implemented, and it can't be —
//    T5 has no scriptable noclip. The engine's `noclip` is a cheat-protected console command acting
//    on the LOCAL player, so it needs sv_cheats 1 AND a listen server. The panel greys it off there.)
//   flinch_<mult>      - damage view-kick scale (scr_gf_flinch -> per-client bg_viewKickScale)
//   jumpfatigue_<0|1>  - post-jump slowdown: scr_gf_jump_fatigue -> jump_slowdownEnable (GF default 0)
//   sprintunlimited_<0|1> - sprint meter never empties: scr_gf_sprint_unlimited -> per-client
//                        player_sprintUnlimited (GF default 0 = stock)
//   svset_<dvar>=<val> - set a CHEAT-PROTECTED server dvar (bot tuning, timescale, jump/fall) from GSC,
//                        which is not cheat-gated — so it works on the dedicated VPS with sv_cheats 0.
//                        Also mirrors the value into gf_<dvar> so it can persist via dedicated.cfg.
//   svsync             - re-apply every gf_<dvar> mirror onto its real dvar (Set All / after restart)
//   pteam_<num>_<allies|axis|spec>  - move one player to a team. Applies LIVE only during the
//                        native prematch countdown (players frozen, round unscored); any other
//                        time (live round / killcam / min-players hold) it's DEFERRED to the next
//                        round via pers["gf_pendingTeam"] (survives map_restart) and applied in
//                        that round's prematch, so a fighting player is never suicided and
//                        friendly-fire teams are never flipped mid-round. Over-cap moves
//                        (scr_team_maxsize) are refused with feedback.
//   pteamforce_<num>_<allies|axis|spec> - same, but applied IMMEDIATELY even mid-round (stock
//                        switch -> respawns the player, costing them the round). Admin override
//                        for the next-round defer; cap still enforced. Panel: Shift+click a move.
//
// FUN / SILLY (mined from EnCoReV8 + iMCSx mod menus):
//   vision_<set>       - VisionSetNaked all players: normal/enhance/bw/berserk/
//                        thermal/hotsnow/nuke/film/bleak (all in common_vision.csv);
//                        persists across rounds via gf_vis_vision (re-applied by
//                        gf_bridgeInit); vision_normal or visreset clears it
//   thirdperson_1/0    - cg_thirdPerson all players (setClientDvar)
//   fps_1/0            - cg_drawFPS all players (setClientDvar)
//   vis<key>_<value>   - video tweak all players (ambient/gridint/gridcon/hdr/fog);
//                        persists via gf_vis_* (re-applied every spawn); value
//                        "stock" clears one tweak back to engine default
//   visreset           - clear ALL gf_vis_* tweaks back to stock
//   expbullets_on/off  - every shot detonates on impact (trace + RadiusDamage + FX)
//   longknife_<range>  - aim_automelee_range all players (e.g. 256 on, 64 off)
//   drunk_on/off       - continuous mild EarthQuake on every player's camera
//   invis_on/off       - hide()/show() all player models (troll)
//   quake              - one strong EarthQuake centered on every player
//   tpall              - teleport all players to Player 1 (host/anchor)
//   saymsg             - iPrintLnBold the contents of dvar gf_say to everyone
//
// Config dvar (panel-managed):
//   gf_admin_guids -> comma-separated player GUID allowlist. gf_bridgeNotify prints command
//                     feedback ONLY to these players (empty = nobody). Set via the panel's
//                     right-click "Set as admin".
//
// Telemetry dvars (read-only):
//   gf_ack    -> sequence id of the last processed gf_cmd (written the instant it's dispatched);
//                the panel polls it to confirm a command was received. "0" = none yet.
//   gf_state  -> "wA:wX:round:aliveA:aliveX:gametype:hold:fillN:pAllies:pAxis:parked" (every 2s)
//                e.g.  "3:2:5:2:1:gf:0:3:3:3:1"  (fields 8-11 = dynamic-fill telemetry: per-team
//                fill target, current playing count per side, parked-bot count)
//   gf_roster -> "<num>,<team>,<alive>,<pending>,<bot>;..." per connected player, e.g.
//                "1,a,1,-,0;2,x,0,x,1"  (team/pending code: a=allies x=axis s=spectator -=none;
//                alive 1/0; bot 1/0). Drives the RCON panel's per-player team badges + move buttons.

#include maps\mp\_utility;
#include maps\mp\gametypes\_globallogic_utils;
#include maps\mp\gametypes\_gf_rounds;

gf_bridgeInit()
{
    level endon( "game_ended" );

    // Clear any stale command left in the slot by a previous match / map_restart (dvars persist
    // across map_restart; a leftover value would fire once on the first poll below).
    setDvar( "gf_cmd", "" );
    if ( getDvar( "gf_say" ) == "" )
        setDvar( "gf_say", "" );
    if ( getDvar( "gf_expbullets_radius" ) == "" )
        setDvar( "gf_expbullets_radius", "200" );   // RCON Blast Radius slider default

    // Ack channel: the poll loop writes the sequence id of each processed command here so the
    // RCON panel can flip a queued command from "sent" to "received" (closed loop), and it doubles as
    // the persistent home of the dedup high-water mark below.
    //
    // ⚠ SEED-IF-EMPTY, never a reset. A command that restarts the match ITSELF (matchrestart, and the
    // lobbystart release — both end in map_restart(false)) tears down the very round that owed it an
    // ack: the poll writes gf_ack = <seq>, the wipe lands, and this callback runs again. Blanking
    // gf_ack to 0 here meant the panel never saw the ack for the command it had just sent, so its
    // dropped-packet auto-retry resent the SAME seq — and with the mark (level state) also back at 0,
    // that resend no longer looked like a duplicate and RE-RAN. One RESTART MATCH click therefore
    // restarted the match once per retry, each restart re-arming the next. The dvar is the only thing
    // map_restart(false) keeps, so carrying the mark in it is what makes the resend dedup and lets the
    // panel confirm a command across the restart it caused.
    if ( getDvar( "gf_ack" ) == "" )
        setDvar( "gf_ack", "0" );
    // Highest command seq processed so far (a "high-water mark"). The panel resends an unacked
    // command with the SAME seq to self-heal a dropped packet; anything with seq <= this was already
    // handled, so we re-ACK it but DON'T re-run it — that makes even non-idempotent commands
    // (endround, quake, tpall, both restarts) safe to retry. Re-seeded from the dvar every round, so
    // it survives map_restart the same way the ack does.
    level.gf_ackSeq = int( getDvar( "gf_ack" ) );
    // Admin GUID allowlist (comma-separated) for PRIVATE feedback: gf_bridgeNotify prints only to
    // players whose getGuid() is in this list, instead of the old bare iPrintLnBold that showed
    // everyone. Managed by the panel (Set as admin); a cfg-set value survives here (only seeded blank).
    if ( getDvar( "gf_admin_guids" ) == "" )
        setDvar( "gf_admin_guids", "" );

    setDvar( "gf_state", "0:0:1:0:0:" + level.gameType );
    setDvar( "gf_roster", "" );

    // Copy every mirrored cheat-protected server dvar (gf_sv_botFov -> sv_botFov, ...) onto the real
    // dvar from GSC, where the sv_cheats gate does not apply. This runs EVERY round, but the load-
    // bearing one is the first round after a full server restart: dedicated.cfg is executed as
    // console commands, so a `set sv_botFov 50` line in it is cheat-refused exactly like an rcon one
    // — the cfg can only ever set the plain gf_* mirror, and this is what makes that mirror mean
    // something. Empty mirror = never configured = leave the engine default alone.
    gf_bridgeApplyServerDvars();

    // Deferred team moves queued mid-round (pers["gf_pendingTeam"], the only state that survives
    // map_restart) are applied at the START of the next round. It CANNOT be a synchronous sweep
    // here: _spawnlogic::init empties level.players BEFORE onStartGameType, and
    // Callback_PlayerConnect only repopulates it later (during prematch, behind the engine's
    // per-client "begin"), so at gf_bridgeInit time level.players is empty. Instead the watcher
    // gf_bridgeWatchPendingTeam (started once-per-match in the guarded block below) applies each
    // pending move when that player fires "spawned_player" (frozen) in the prematch window.

    level.gf_paused        = false;
    level.gf_infAmmo       = false;
    level.gf_godMode       = false;
    level.gf_radarOn       = false;
    level.gf_headshotsOnly = false;
    level.gf_expBullets    = false;
    level.gf_drunk         = false;
    level.gf_invisible     = false;
    // Vision is NOT owned here anymore. level.gf_defaultVision (the map's own set) and the per-round
    // apply both live in _gf_rounds::gf_initRoundVision, because the "enhance" contrast pop is now the
    // mod's DEFAULT look rather than an admin tweak — the public build needs it too, and the bridge is
    // stripped from that build. The bridge only OVERRIDES it: vision_<key> persists a key into
    // gf_vis_vision, which _gf_rounds::gf_roundVisionKey reads back each round. Re-applying it here as
    // well would double-fire the same visionSetNaked at prematch_over.

    // Persistent loops: exactly ONE live set at a time, re-threaded every round with a COLLAPSE
    // NOTIFY (the _bot::init "bot_reinit" idiom), NOT a game[] guard. gf_bridgeInit is re-threaded on
    // every map_restart (gf.gsc) to re-seed the dvars/flags above (level.* is wiped by map_restart);
    // the telemetry loop, the 20 Hz command poll, and the pending-team watcher are for(;;) loops that
    // survive map_restart (only endon("game_ended") = match end). A bare re-thread every round would
    // STACK one copy per round (N pollers racing the gf_cmd read+clear, N telemetry writes, an
    // O(players^2) pending sweep). The OLD fix was a game["gf_bridgeInit"] guard — thread once, never
    // again while game[] survives — but that was fragile the other direction: after game_ended kills
    // these threads, a match that starts on a game[]-PRESERVING path (same-map cycle / lobby
    // fast-restart) left the guard set and the loops DEAD FOR GOOD (telemetry/roster/command-poll all
    // frozen — observed live on the VPS: gf_state pinned at its seed, gf_ack never advancing). Firing
    // "gf_bridge_reinit" before re-threading, with each loop carrying endon("gf_bridge_reinit"),
    // collapses any survivors to exactly one set per round AND self-heals a set that died at the last
    // match end. Same fix _bot::init uses for "fast restart clears the bots". gf_ackSeq is re-seeded
    // per round above, so the surviving poll always reads a defined mark.
    level notify( "gf_bridge_reinit" );
    level thread gf_bridgeWatchPendingTeam();
    level thread gf_bridgeTelemetry();
    level thread gf_bridgePoll();
}

// 20 Hz command poll (was 2 Hz): cuts up to ~450ms off the command latency floor for a single
// getDvar per tick. Exactly ONE copy is live (the gf_bridge_reinit collapse-notify kills the prior
// one each round before a fresh poll is threaded), so it is a single consumer - read+clear are
// adjacent statements with no wait between, so the engine can't slot an incoming `set gf_cmd` into
// the gap and the take is race-free. endon "game_ended" + "gf_bridge_reinit" so it dies with the
// match or when gf_bridgeInit re-threads.
gf_bridgePoll()
{
    level endon( "game_ended" );
    level endon( "gf_bridge_reinit" );   // one consumer only: die when gf_bridgeInit re-threads a fresh poll

    for ( ;; )
    {
        wait 0.05;
        raw = getDvar( "gf_cmd" );
        if ( raw == "" )
            continue;

        setDvar( "gf_cmd", "" );

        // The panel sends "<seq>:<cmd>" so it can match an ack; a bare "<cmd>" (manual console)
        // parses to seq "0" and just isn't acked. Commands never contain ':', so the split is safe.
        sc   = gf_bridgeSplitSeq( raw );
        seq  = sc[0];
        cmd  = sc[1];
        seqN = int( seq );

        // Dedup by high-water seq: a resend of an already-processed command (seqN <= mark) is
        // RE-ACKED but NOT re-run, so the panel's auto-retry of a dropped packet never double-fires
        // a non-idempotent command. seq 0 (unstamped / manual console) has no dedup and always runs.
        if ( seqN > 0 && seqN <= level.gf_ackSeq )
        {
            setDvar( "gf_ack", level.gf_ackSeq );
            continue;
        }
        if ( seqN > 0 )
            level.gf_ackSeq = seqN;

        level thread gf_bridgeDispatch( cmd );

        if ( seqN > 0 )
            setDvar( "gf_ack", seqN );
    }
}

// Split a "<seq>:<cmd>" command value into [ seq, cmd ]. A value with no leading "<digits>:"
// (e.g. a hand-typed `set gf_cmd god_on`) returns seq "0" and the whole string as the command.
// Commands in this bridge never contain ':', so any ':' present is the seq separator; extra ':'
// (defensive) are rejoined into the command.
gf_bridgeSplitSeq( raw )
{
    parts = strTok( raw, ":" );
    out   = [];
    if ( parts.size >= 2 )
    {
        out[0] = parts[0];
        cmd    = parts[1];
        for ( i = 2; i < parts.size; i++ )
            cmd += ":" + parts[i];
        out[1] = cmd;
    }
    else
    {
        out[0] = "0";
        out[1] = raw;
    }
    return out;
}

// Private admin feedback. Prints `text` ONLY to connected players whose GUID is listed in the
// gf_admin_guids allowlist, replacing the old bare iPrintLnBold that center-printed to EVERYONE.
// Read live each call (cheap — only fires on an admin action). Empty allowlist => prints to nobody
// (the panel still logs the action). getGuid() is coerced to a string so the compare is type-safe.
gf_bridgeNotify( text )
{
    guids = getDvar( "gf_admin_guids" );
    if ( guids == "" )
        return;

    admins  = strTok( guids, "," );
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p  = players[i];
        pg = p getGuid();
        pg = "" + pg;          // coerce to string (stock idiom) so the compare is type-safe
        for ( j = 0; j < admins.size; j++ )
        {
            if ( admins[j] == pg )
            {
                p iPrintLnBold( text );
                break;
            }
        }
    }
}

// --- Telemetry ---------------------------------------------------------------
// Writes match state into gf_state every 2s so the RCON tool can display
// a live scoreboard without needing new API endpoints.

gf_bridgeTelemetry()
{
    level endon( "game_ended" );
    level endon( "gf_bridge_reinit" );   // collapse to one live copy when gf_bridgeInit re-threads

    for ( ;; )
    {
        wait 2;

        wA = game["roundswon"]["allies"];
        wX = game["roundswon"]["axis"];
        rn = game["roundsplayed"] + 1;

        aA = 0;
        aX = 0;
        if ( isDefined( level.aliveCount["allies"] ) ) aA = level.aliveCount["allies"];
        if ( isDefined( level.aliveCount["axis"] ) )   aX = level.aliveCount["axis"];

        // 7th field: pre-prematch lobby hold active (1) or not (0) — drives the panel's
        // "Start Match" affordance. Appended after gametype (no colons there), so the
        // server's index-based parseGfState (guards length<5) stays back-compatible.
        hold = 0;
        if ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold )
            hold = 1;

        // Fields 8-11: dynamic-fill telemetry so the panel shows the live fill state. fillN is
        // the per-team target (gf_fill_n); pAllies/pAxis are the current PLAYING counts (humans+
        // bots) per side; parked is the count of bots benched in spectator for reuse. Computed
        // from the reconciler's own classifier so the panel matches exactly what the fill sees.
        // All appended (index-based parse), so older panels ignore them.
        fillN  = maps\mp\gametypes\_bot::gf_fillTarget();   // CLAMPED (0-6) — echo what the fill actually uses, not a raw out-of-range dvar
        fc     = maps\mp\gametypes\_bot::gf_reconcileCount();
        pAll   = fc["allies_human"] + fc["allies_bot"];
        pAxi   = fc["axis_human"]   + fc["axis_bot"];
        parked = fc["parked"];

        setDvar( "gf_state", wA + ":" + wX + ":" + rn + ":" + aA + ":" + aX + ":" + level.gameType + ":" + hold + ":" + fillN + ":" + pAll + ":" + pAxi + ":" + parked );
        setDvar( "gf_roster", gf_bridgeRosterString() );
    }
}

// Per-player roster line for the RCON panel: "<num>,<team>,<alive>,<pending>" joined by
// ';'. team/pending are single-char codes (a/x/s/-), alive is 1/0. No spaces, so the whole
// value reads back as one bare rcon token. Keyed by getEntityNumber() to match the panel's
// status "num" column (the same id the per-player pgod_/pfreeze_/pteam_ commands target).
// The server-side democlient is omitted entirely: it is neither a human nor a bot (it would
// report bot=0, i.e. as a human), and it is never a valid target for a team/god/freeze command.
gf_bridgeRosterString()
{
    s = "";
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) || p isdemoclient() )
            continue;
        if ( s != "" )                       // separator keys off what's emitted, not the loop index
            s += ";";
        alive = "0";
        if ( isDefined( p.health ) && p.health > 0 )
            alive = "1";
        bot = "0";
        if ( p istestclient() )
            bot = "1";
        s += p getEntityNumber() + "," + gf_bridgeTeamShort( p.pers["team"] ) + "," + alive + "," + gf_bridgeTeamShort( p.pers["gf_pendingTeam"] ) + "," + bot;
    }
    return s;
}

gf_bridgeTeamShort( team )
{
    if ( !isDefined( team ) )      return "-";
    if ( team == "allies" )        return "a";
    if ( team == "axis" )          return "x";
    if ( team == "spectator" )     return "s";
    return "-";
}

// --- Dispatcher --------------------------------------------------------------

gf_bridgeDispatch( cmd )
{
    if ( cmd == "pause"  ) { gf_bridgePause();  return; }
    if ( cmd == "resume" ) { gf_bridgeResume(); return; }
    if ( cmd == "lobbystart" ) { gf_bridgeLobbyStart(); return; }

    if ( cmd == "botdiff_easy"   ) { maps\mp\gametypes\_bot::bot_set_difficulty( "easy"   ); gf_bridgeNotify( "^2Bot: Easy"   ); return; }
    if ( cmd == "botdiff_normal" ) { maps\mp\gametypes\_bot::bot_set_difficulty( "normal" ); gf_bridgeNotify( "^2Bot: Normal" ); return; }
    if ( cmd == "botdiff_hard"   ) { maps\mp\gametypes\_bot::bot_set_difficulty( "hard"   ); gf_bridgeNotify( "^1Bot: Hard"   ); return; }
    if ( cmd == "botdiff_fu"     ) { maps\mp\gametypes\_bot::bot_set_difficulty( "fu"     ); gf_bridgeNotify( "^1Bot: FU"     ); return; }

    if ( cmd == "botadd"         ) { gf_bridgeAddBot(); return; }
    if ( cmd == "botadd_allies"  ) { gf_bridgeAddBotToTeam( "allies" ); return; }
    if ( cmd == "botadd_axis"    ) { gf_bridgeAddBotToTeam( "axis"   ); return; }
    if ( cmd == "botkick_allies" ) { gf_bridgeKickBotFromTeam( "allies" ); return; }
    if ( cmd == "botkick_axis"   ) { gf_bridgeKickBotFromTeam( "axis"   ); return; }

    if ( cmd == "balanceteams"   ) { gf_bridgeBalanceTeams(); return; }

    if ( cmd == "endround_allies" ) { maps\mp\gametypes\sd::sd_endGame( "allies", "" ); return; }
    if ( cmd == "endround_axis"   ) { maps\mp\gametypes\sd::sd_endGame( "axis",   "" ); return; }
    if ( cmd == "roundrestart"    ) { gf_bridgeRestartRound(); return; }
    if ( cmd == "matchrestart"    ) { gf_bridgeRestartMatch(); return; }

    // Visual tweaks -- setClientDvar sent to all players
    // Format: vis<key>_<value>  e.g. visambient_0.2
    // gf_vis_* tweaks persist (re-applied on every spawn by gf_applyVisTweaks);
    // value "stock" clears one back to engine default. visreset clears them ALL.
    // visgamma_ was removed: r_gamma is a SAVED client dvar and Plutonium blocks
    // servers from writing those (the push never applied).
    if ( cmd == "visreset" ) { gf_bridgeVisReset(); return; }
    if ( isSubStr( cmd, "visfog_"        ) ) { gf_bridgeVisSet( "r_fog",                getSubStr( cmd, 7,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "visambient_"    ) ) { gf_bridgeVisSet( "r_lightTweakAmbient",  getSubStr( cmd, 11, cmd.size ) ); return; }
    if ( isSubStr( cmd, "visgridint_"    ) ) { gf_bridgeVisSet( "r_lightGridIntensity", getSubStr( cmd, 11, cmd.size ) ); return; }
    if ( isSubStr( cmd, "visgridcon_"    ) ) { gf_bridgeVisSet( "r_lightGridContrast",  getSubStr( cmd, 11, cmd.size ) ); return; }
    if ( isSubStr( cmd, "vishdr_"        ) ) { gf_bridgeVisSet( "r_fullHDRrendering",   getSubStr( cmd, 7,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "viscrosshair_"  ) ) { gf_bridgeVisSet( "cg_drawCrosshair",     getSubStr( cmd, 13, cmd.size ) ); return; }
    if ( isSubStr( cmd, "visnames_"      ) ) { gf_bridgeVisSet( "cg_drawCrosshairNames",getSubStr( cmd, 9,  cmd.size ) ); return; }
    // HUD element toggles
    if ( cmd == "selfbar_on"  ) { gf_bridgeSelfBar( true );  return; }
    if ( cmd == "selfbar_off" ) { gf_bridgeSelfBar( false ); return; }

    if ( cmd == "killstreaks_on"  ) { level.killstreaksenabled = true;  gf_bridgeNotify( "^3Killstreaks ON"  ); return; }
    if ( cmd == "killstreaks_off" ) { level.killstreaksenabled = false; gf_bridgeNotify( "^7Killstreaks OFF" ); return; }
    if ( cmd == "regen_on"        ) { gf_bridgeRegen( true );          return; }
    if ( cmd == "regen_off"       ) { gf_bridgeRegen( false );         return; }

    if ( cmd == "god_on"          ) { gf_bridgeGod( true );          return; }
    if ( cmd == "god_off"         ) { gf_bridgeGod( false );         return; }
    if ( cmd == "allperks_on"     ) { gf_bridgePerks( true );        return; }
    if ( cmd == "allperks_off"    ) { gf_bridgePerks( false );       return; }
    if ( cmd == "perksync"        ) { gf_bridgePerkSync();           return; }
    if ( cmd == "infammo_on"      ) { gf_bridgeInfAmmo( true );      return; }
    if ( cmd == "infammo_off"     ) { gf_bridgeInfAmmo( false );     return; }
    if ( cmd == "radar_on"        ) { gf_bridgeRadar( true );        return; }
    if ( cmd == "radar_off"       ) { gf_bridgeRadar( false );       return; }
    if ( cmd == "headshots_on"    ) { gf_bridgeHeadshots( true );    return; }
    if ( cmd == "headshots_off"   ) { gf_bridgeHeadshots( false );   return; }
    if ( isSubStr( cmd, "flinch_" ) ) { gf_bridgeFlinch( getSubStr( cmd, 7, cmd.size ) ); return; }
    if ( isSubStr( cmd, "jumpfatigue_" ) ) { gf_bridgeJumpFatigue( getSubStr( cmd, 12, cmd.size ) ); return; }
    if ( isSubStr( cmd, "sprintunlimited_" ) ) { gf_bridgeSprintUnlimited( getSubStr( cmd, 16, cmd.size ) ); return; }

    // Cheat-protected SERVER dvars, written from GSC so they work with sv_cheats 0 (the only
    // correct value on a dedicated server). Format: svset_<dvar>=<value>. See gf_bridgeServerDvarSet.
    if ( isSubStr( cmd, "svset_" ) ) { gf_bridgeServerDvarSet( getSubStr( cmd, 6, cmd.size ) ); return; }
    // svsync — copy EVERY gf_* mirror onto its real dvar in one shot. The panel's Set All / 💾 Save
    // write the plain mirrors over rcon (which is allowed) and then fire this once.
    if ( cmd == "svsync" ) { gf_bridgeApplyServerDvars(); gf_bridgeNotify( "^2Server dvars applied" ); return; }

    // --- Fun / silly (EnCoReV8 + iMCSx) ---
    if ( isSubStr( cmd, "vision_"      ) ) { gf_bridgeVision( getSubStr( cmd, 7,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "thirdperson_" ) ) { gf_bridgeVisSet( "cg_thirdPerson",    getSubStr( cmd, 12, cmd.size ) ); return; }
    if ( isSubStr( cmd, "fps_"         ) ) { gf_bridgeVisSet( "cg_drawFPS",        getSubStr( cmd, 4,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "longknife_"   ) ) { gf_bridgeVisSet( "aim_automelee_range", getSubStr( cmd, 10, cmd.size ) ); return; }

    if ( cmd == "expbullets_on"  ) { gf_bridgeExpBullets( true );  return; }
    if ( cmd == "expbullets_off" ) { gf_bridgeExpBullets( false ); return; }
    if ( cmd == "drunk_on"       ) { gf_bridgeDrunk( true );       return; }
    if ( cmd == "drunk_off"      ) { gf_bridgeDrunk( false );      return; }
    if ( cmd == "invis_on"       ) { gf_bridgeInvisible( true );   return; }
    if ( cmd == "invis_off"      ) { gf_bridgeInvisible( false );  return; }
    if ( cmd == "quake"          ) { gf_bridgeQuake();             return; }
    if ( cmd == "tpall"          ) { gf_bridgeTeleportAll();       return; }
    if ( cmd == "saymsg"         ) { gf_bridgeBroadcast();         return; }

    // Per-player commands: pgod_<num>, pfreeze_<num>, punfreeze_<num>, pperks_<num>
    if ( isSubStr( cmd, "pgod_"      ) ) { gf_bridgePlayerCmd( "god",      getSubStr( cmd, 5,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "pfreeze_"   ) ) { gf_bridgePlayerCmd( "freeze",   getSubStr( cmd, 8,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "punfreeze_" ) ) { gf_bridgePlayerCmd( "unfreeze", getSubStr( cmd, 10, cmd.size ) ); return; }
    if ( isSubStr( cmd, "pperks_"    ) ) { gf_bridgePlayerCmd( "perks",    getSubStr( cmd, 7,  cmd.size ) ); return; }

    // Team move: pteam_<num>_<team> (deferred to next round if unsafe) or pteamforce_<num>_<team>
    // (applied NOW even mid-round — respawns the player). Check the longer prefix first.
    if ( isSubStr( cmd, "pteamforce_" ) ) { gf_bridgeTeamCmd( getSubStr( cmd, 11, cmd.size ), true  ); return; }
    if ( isSubStr( cmd, "pteam_"      ) ) { gf_bridgeTeamCmd( getSubStr( cmd, 6,  cmd.size ), false ); return; }
}

// --- Pause / Resume ----------------------------------------------------------

// Delegates to the mod-owned clock in _gf_rounds. The visible round timer is no
// longer the native one, so bare pauseTimer()/resumeTimer() here would (a) fail to
// freeze the HUD clock and (b) resume would re-arm the native "time running out"
// VO/music/beeps the mod suppresses. gf_pauseMatch/gf_resumeMatch freeze the live
// clock (round or overtime), human controls, AND bots (which ignore freezeControls),
// and raises the MATCH PAUSED banner.
//
// The B&W desaturation is the bridge's half: visionSetNaked is level-global (bare
// builtin) and the vision to RESTORE on resume is whatever key the admin has
// persisted in gf_vis_vision — which only the bridge knows about. Doing it here
// keeps _gf_rounds free of a dependency on this dev-only file.
gf_bridgePause()
{
    if ( level.gf_paused ) return;
    level.gf_paused = true;
    maps\mp\gametypes\_gf_rounds::gf_pauseMatch();
    visionSetNaked( maps\mp\gametypes\_gf_rounds::gf_visionSetForKey( "bw" ), 0.5 );   // cheat_bw — bare = all clients
    gf_bridgeNotify( "^3-- MATCH PAUSED --" );
}

gf_bridgeResume()
{
    if ( !level.gf_paused ) return;
    level.gf_paused = false;
    maps\mp\gametypes\_gf_rounds::gf_resumeMatch();
    gf_bridgeRestoreVision( 0.5 );
    gf_bridgeNotify( "^2-- MATCH RESUMED --" );
}

// Drop back to whatever vision is standing — the admin's persisted gf_vis_vision key, or Gunfight's
// own default ("enhance") if none. gf_roundVisionKey owns that fallback, so pause/resume can never
// disagree with what a round start would have applied. Read fresh (not snapshotted at pause time) so
// a vision_<set> issued DURING the pause is what we resume into.
gf_bridgeRestoreVision( blend )
{
    key = maps\mp\gametypes\_gf_rounds::gf_roundVisionKey();
    visionSetNaked( maps\mp\gametypes\_gf_rounds::gf_visionSetForKey( key ), blend );
}

// "Start Match" from the panel: release the pre-prematch lobby hold NOW. The hold
// (gf_waitForLoadingClients in _gf_rounds) polls level.gf_lobbyStart every 0.25s; set
// it and the countdown begins. Only meaningful while a hold is actively up (match's
// first round, before the prematch countdown) — level.gf_inLobbyHold tells us that.
// Harmless if clicked otherwise (gf_armLoadGate clears the flag at each match-start, so
// it can't leak into a later match), but we give clear feedback instead of arming it.
gf_bridgeLobbyStart()
{
    if ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold )
    {
        gf_bridgeNotify( "^3Start Match: no lobby hold is active right now" );
        return;
    }
    level.gf_lobbyStart = true;
    gf_bridgeNotify( "^2-- STARTING MATCH --" );
}

// "Restart Round" from the panel: replay the round from the top — nobody scores, the shared
// loadout does NOT rotate, and the sides do NOT switch.
//
// Routed through the mod's own round-end funnel (gf_endRound -> _globallogic::endGame) on
// purpose. A raw fast_restart / map_restart(true) skips endGame, so "game_ended" never fires —
// and that notify is what tears down every persistent endon("game_ended") thread each round, so
// the old round's clock/HUD/gate loops would survive into the next round as a second copy.
//
// Winner "tie" is the existing no-score path (a mutual wipe / equal-HP draw already uses it).
// The two counters endGame moves have to be neutralized here:
//   - game["roundsplayed"]++ (endGame) would rotate the shared loadout every other restart, so we
//     pre-decrement — the ++ nets it back to the value this round already ran with.
//   - checkRoundSwitch() reads that same counter right after the ++ and would flip sides, so
//     level.roundswitch is zeroed for this cycle only (a level var: the restart re-derives it
//     from scr_gf_roundswitch next round).
// In overtime this still resolves: gf_endRound routes through gf_resolveOvertime, which tears the
// OT clock + zone down and re-enters gf_endRound with the same winner.
gf_bridgeRestartRound()
{
    // endGame() early-returns once the round is already ending (postgame / gameEnded) — but the
    // roundsplayed pre-decrement below would still stick, permanently shifting the loadout
    // rotation and the side-switch cadence. So bail BEFORE touching game[] state.
    if ( gf_bridgeRoundEnding() )
    {
        gf_bridgeNotify( "^3Restart Round: the round is already ending" );
        return;
    }

    // A restart wipes level.* (so the pause state) but the panel's PAUSE/RESUME button tracks its
    // own flag — resume first rather than desync it.
    if ( isDefined( level.gf_paused ) && level.gf_paused )
    {
        gf_bridgeNotify( "^3Restart Round: resume the match first" );
        return;
    }

    level.roundswitch = 0;

    // Round 1 dips to -1 here; endGame's ++ restores it in the same yield-free block (gf_endRound
    // threads endGame, and a GSC thread runs immediately up to its first wait), so it never sticks.
    game["roundsplayed"]--;

    gf_bridgeNotify( "^3-- RESTARTING ROUND --" );
    maps\mp\gametypes\_gf_rounds::gf_endRound( "tie" );
}

// "Restart Match" from the panel: the whole match starts over — scores 0-0, back to round 1, same
// map, same teams — with the full match-start presentation (gun rack, spawn music, welcome splash).
//
// map_restart(FALSE) is the fresh reset: it wipes game[]/pers[] (so the scores and the round counter
// go with them) and re-fires that presentation, and it does NOT reload the map, so it's fast. Same
// call the Auto/Manual lobby fast-restart uses on release — including its team plumbing: gf_teamplan
// / gf_botplan are DVARS precisely because they have to survive this wipe, and gf_matchArmed tells
// the post-restart gate "this pass IS the match" so it skips the lobby hold and applies the plan.
//
// ⚠ The notify below is load-bearing and is why this can't be the raw `fast_restart` / `map_restart`
// console command. GSC threads SURVIVE a map_restart; the only thing that retires them is the
// "game_ended" notify _globallogic::endGame fires at every round end. Restart without it and the
// engine's re-InitGame threads a SECOND startGame() -> prematchPeriod()/gameTimer() on top of the
// survivors (double countdown), plus a second copy of every HUD/gate loop.
gf_bridgeRestartMatch()
{
    // Mid-teardown the round-end thread (endGame -> displayRoundEnd -> map_restart(true)) is already
    // in flight and does NOT endon game_ended — it would survive our wipe and fire its own restart on
    // top of the fresh match. Let the round land first.
    if ( gf_bridgeRoundEnding() )
    {
        gf_bridgeNotify( "^3Restart Match: wait for the round to finish ending" );
        return;
    }

    if ( isDefined( level.gf_paused ) && level.gf_paused )
    {
        gf_bridgeNotify( "^3Restart Match: resume the match first" );
        return;
    }

    gf_bridgeNotify( "^3-- RESTARTING MATCH --" );

    // Snapshot the current sides into the dvars the post-restart gate reads back, so a restart keeps
    // the teams it had instead of re-autoassigning everyone.
    setDvar( "gf_matchArmed", "1" );
    maps\mp\gametypes\_gf_rounds::gf_writeTeamPlan();
    maps\mp\gametypes\_gf_rounds::gf_writeBotPlan();

    // Yield once before the notify: gf_bridgePoll endons "game_ended", and it writes this command's
    // ack right after the dispatch thread first yields. Notifying synchronously would kill the poll
    // before that write, and the panel would show the command as never received.
    wait 0.1;

    level.gameEnded = true;
    level notify( "game_ended" );
    wait 0.05;                     // let the endon'd threads unwind before the wipe

    map_restart( false );
}

// Shared precondition for both restarts: a round end is in flight (or the match is over), so the
// round-cycle machinery owns the next map_restart and we must not touch game[] state or fire one.
gf_bridgeRoundEnding()
{
    if ( isDefined( level.gameEnded ) && level.gameEnded )
        return true;
    if ( game["state"] != "playing" )
        return true;
    if ( isDefined( level.gf_roundEnding ) && level.gf_roundEnding )
        return true;
    return false;
}

// --- God mode ----------------------------------------------------------------

gf_bridgeGod( enable )
{
    level.gf_godMode = enable;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( enable )
            players[i] enableInvulnerability();
        else
            players[i] disableInvulnerability();
    }
    if ( enable )
        gf_bridgeNotify( "^3God Mode ON" );
    else
        gf_bridgeNotify( "^7God Mode OFF" );
}

// --- Perks -------------------------------------------------------------------

gf_bridgePerks( enable )
{
    devPerks = [];
    devPerks[0] = "specialty_longersprint";
    devPerks[1] = "specialty_movefaster";
    devPerks[2] = "specialty_gpsjammer";
    devPerks[3] = "specialty_fastreload";
    devPerks[4] = "specialty_bulletaccuracy";
    devPerks[5] = "specialty_quieter";

    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        for ( j = 0; j < devPerks.size; j++ )
        {
            if ( enable )
                players[i] SetPerk( devPerks[j] );
            else
                players[i] UnSetPerk( devPerks[j] );
        }
    }
    if ( enable )
        gf_bridgeNotify( "^2All Perks ON" );
    else
        gf_bridgeNotify( "^7Perks cleared" );
}

// --- Perk override sync (rcon Perks tab) -------------------------------------
// Re-applies the gf_perk_on / gf_perk_off lists to all LIVE players so a toggle
// takes effect without waiting for respawn. The loadout re-applies the same
// lists on every spawn (gf_applyPerkList), so this is just the live-update half.
// One-shot per toggle — no polling thread, no per-frame work.

gf_bridgePerkSync()
{
    onList  = getDvar( "gf_perk_on"  );
    offList = getDvar( "gf_perk_off" );
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( players[i].health <= 0 )
            continue;
        players[i] maps\mp\gametypes\_gf_loadouts::gf_applyPerkList( onList,  true  );
        players[i] maps\mp\gametypes\_gf_loadouts::gf_applyPerkList( offList, false );
    }
    gf_bridgeNotify( "^2Perks synced" );
}

// --- Infinite ammo (native sv_FullAmmo + one-shot top-up) --------------------
// Consolidated from the old 0.5s refill loop: the engine's sv_FullAmmo flag stops
// depletion (all weapons + reserve, and it persists across map_restart), while a
// single immediate refill of live players makes the toggle apply THIS round
// instead of next spawn. No polling thread.

gf_bridgeInfAmmo( enable )
{
    level.gf_infAmmo = enable;
    if ( enable )
    {
        setDvar( "sv_FullAmmo", 1 );
        players = level.players;
        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];
            if ( p.health <= 0 ) continue;
            weapons = p getWeaponsListPrimaries();
            for ( j = 0; j < weapons.size; j++ )
                p giveMaxAmmo( weapons[j] );
        }
        gf_bridgeNotify( "^3Infinite Ammo ON" );
    }
    else
    {
        setDvar( "sv_FullAmmo", 0 );
        gf_bridgeNotify( "^7Infinite Ammo OFF" );
    }
}

// --- Radar always on (stock scr_game_forceradar + live match flags) ----------
// Consolidated force-UAV: the stock scr_game_forceradar dvar persists the setting
// (survives map_restart, and is the saveable face in SERVER -> Force UAV), while
// setMatchFlag drives the UAV state the engine reads for the minimap THIS round.

gf_bridgeRadar( enable )
{
    level.gf_radarOn = enable;
    if ( enable )
    {
        setDvar( "scr_game_forceradar", 1 );
        setMatchFlag( "radar_allies", 1 );
        setMatchFlag( "radar_axis",   1 );
        gf_bridgeNotify( "^3Radar: Always ON" );
    }
    else
    {
        setDvar( "scr_game_forceradar", 0 );
        setMatchFlag( "radar_allies", 0 );
        setMatchFlag( "radar_axis",   0 );
        gf_bridgeNotify( "^7Radar: Normal" );
    }
}

// --- Headshots only ----------------------------------------------------------
// Sets a flag read by gf_onPlayerDamage in _gf_rounds.gsc.
// Non-headshot damage is zeroed out there -- only head/helmet hits kill.

gf_bridgeHeadshots( enable )
{
    level.gf_headshotsOnly = enable;
    if ( enable )
        gf_bridgeNotify( "^3Headshots Only: ON" );
    else
        gf_bridgeNotify( "^7Headshots Only: OFF" );
}

// --- Flinch (damage view-kick) -----------------------------------------------
// value = multiplier of stock bg_viewKickScale (0.2): 1 = stock, 0 = no flinch.
// Stores it in scr_gf_flinch (so onStartGameType re-applies it every round) and
// applies it live via gf_applyFlinch, which re-reads + clamps to 0..3 and PUSHES
// bg_viewKickScale to each human — the server dvar does not replicate, so the
// server-side setDvar alone would change nothing for anyone on a dedicated server.

gf_bridgeFlinch( value )
{
    setDvar( "scr_gf_flinch", value );
    scale = maps\mp\gametypes\_gf_rounds::gf_applyFlinch();
    if ( scale == 0 )
        gf_bridgeNotify( "^2Flinch: OFF (no view kick)" );
    else
        gf_bridgeNotify( "^3Flinch: " + scale + "x stock" );
}

// --- Jump fatigue ------------------------------------------------------------
// value = 1 (stock post-jump slowdown) or 0 (none — the Gunfight default).
// Stores it in scr_gf_jump_fatigue (the source of truth, so onStartGameType re-applies it every
// round) and applies jump_slowdownEnable live. No mirror needed — scr_gf_jump_fatigue is a plain
// mod dvar the panel can `set` and dedicated.cfg can persist.

gf_bridgeJumpFatigue( value )
{
    setDvar( "scr_gf_jump_fatigue", value );
    on = maps\mp\gametypes\_gf_rounds::gf_applyJumpFatigue();
    if ( on )
        gf_bridgeNotify( "^3Jump fatigue: ON (stock post-jump slowdown)" );
    else
        gf_bridgeNotify( "^2Jump fatigue: OFF" );
}

// --- Unlimited sprint --------------------------------------------------------
// value = 1 (sprint meter never empties) or 0 (stock — the Gunfight default).
// Stores it in scr_gf_sprint_unlimited (the source of truth, so onStartGameType re-applies it
// every round) and applies it live via gf_applySprintUnlimited, which sets the server copy of
// player_sprintUnlimited AND pushes it to each human.
//
// ⚠ Do NOT go back to a bare `set player_sprintUnlimited 1` from the panel. It is a CLIENT dvar:
// stock's only push is at connect and only in the ON direction, so a raw set reaches nobody who
// is already in the server until the next round's connect callback, and 0 never reaches anyone
// at all. That is what made the old panel toggle look like it randomly stopped working.

gf_bridgeSprintUnlimited( value )
{
    setDvar( "scr_gf_sprint_unlimited", value );
    on = maps\mp\gametypes\_gf_rounds::gf_applySprintUnlimited();
    if ( on )
        gf_bridgeNotify( "^3Unlimited sprint: ON" );
    else
        gf_bridgeNotify( "^2Unlimited sprint: OFF (stock sprint meter)" );
}

// --- Cheat-protected SERVER dvars (svset_<dvar>=<value>) ---------------------
// ⚠ CORRECTED 2026-07-12 — this block used to claim that an rcon `set` of a cheat-protected dvar is
// refused on a dedicated server. IT IS NOT. Proven live against the VPS (sv_cheats 0, `dedicated` =
// "dedicated internet server"): rcon `set ragdoll_explode_force 18001` — a dvar on the engine's own
// cheat-protected list — CHANGED the value (read back 18001, restored to 18000). A guaranteed-invalid
// write in the same session (`set bg_gravity 0`, domain starts at 1) DID echo its error back, so the
// silence on the accepted writes was a real accept, not a swallowed reply.
//
// The true model: **cheat protection is a CLIENT-side check.** It bites wherever the console belongs
// to a client — a player's own console, a client exec'ing a cfg (that is where the familiar
// "Error: jump_height is cheat protected" boot spam comes from: the CLIENT exec'ing the stock
// default_xboxlive.cfg), and a setClientDvar arriving at a client. The DEDICATED server's own console
// is not gated, so rcon AND dedicated.cfg can both write cheat-protected SERVER dvars there.
//
// So svset is NOT needed to reach a cheat-protected server dvar on the VPS — a plain rcon `set`
// already does. What it is still good for is the LISTEN/dev host, where the panel's rcon lands on a
// console that IS a client's (that is the setup where `set bg_viewKickScale 0.9` was seen refused),
// plus the gf_<dvar> mirror below, which gives a value cfg-persistence for free. Kept for those two
// reasons — do not add rows to it on the theory that rcon cannot reach them, because it can.
//
// ⚠ SERVER dvars ONLY. This does NOT rescue a cheat-protected CLIENT dvar (the r_* Visual Tweaks,
// and bg_viewKickScale's per-client push): those go out via setClientDvar and the CLIENT applies
// its own cheat check on arrival, which no amount of server-side authority can bypass. THAT is the
// limit that is real on a dedicated server, and it is the one the panel greys out (.ded-lockable).
//
// Allowlisted rather than arbitrary. An rcon holder can already `set sv_cheats 1` directly (that
// dvar is not itself cheat-protected), so this grants no new privilege — the list keeps the surface
// legible and turns a typo into a clear error instead of a silently-created junk dvar.
gf_bridgeServerDvarSet( arg )
{
    parts = strTok( arg, "=" );
    if ( parts.size < 2 )
    {
        gf_bridgeNotify( "^1svset: expected <dvar>=<value>" );
        return;
    }

    name  = parts[0];
    value = parts[1];

    if ( !gf_bridgeServerDvarAllowed( name ) )
    {
        gf_bridgeNotify( "^1svset: " + name + " is not allowlisted" );
        return;
    }

    setDvar( name, value );

    // Mirror into a plain (non-cheat) gf_* dvar so the value can PERSIST. dedicated.cfg is executed
    // as console commands at startup, so a `set sv_botFov 50` line there is refused exactly like the
    // rcon one — cfg-persisting the real dvar is impossible with sv_cheats 0. The panel's 💾 Save
    // therefore writes the mirror, and gf_bridgeApplyServerDvars() (below, every round) copies the
    // mirror back onto the real dvar from GSC, where the cheat gate doesn't apply.
    setDvar( "gf_" + name, value );

    gf_bridgeNotify( "^3" + name + " = " + value );
}

// Re-apply every mirrored cheat-protected server dvar. Called from gf_bridgeInit (so: every round,
// and — critically — on the first round after a full server restart, which is the only way a
// cfg-set value can reach a cheat-protected dvar at all). An unset/empty mirror is skipped, leaving
// the engine default alone.
gf_bridgeApplyServerDvars()
{
    names = gf_bridgeServerDvarList();
    for ( i = 0; i < names.size; i++ )
    {
        v = getDvar( "gf_" + names[i] );
        if ( v == "" )
            continue;
        setDvar( names[i], v );
    }
}

// The allowlist + the mirror list are the SAME set, so they cannot drift apart.
gf_bridgeServerDvarList()
{
    n = [];
    n[ n.size ] = "sv_botFov";
    n[ n.size ] = "sv_botMinReactionTime";
    n[ n.size ] = "sv_botMaxReactionTime";
    n[ n.size ] = "sv_botMinFireTime";
    n[ n.size ] = "sv_botMaxFireTime";
    n[ n.size ] = "sv_botStrafeChance";
    n[ n.size ] = "sv_botSprintDistance";
    n[ n.size ] = "sv_botMeleeDist";
    n[ n.size ] = "sv_botYawSpeed";
    n[ n.size ] = "timescale";
    return n;
}

gf_bridgeServerDvarAllowed( name )
{
    names = gf_bridgeServerDvarList();
    for ( i = 0; i < names.size; i++ )
        if ( names[i] == name )
            return true;
    return false;
}

// --- Self health bar ---------------------------------------------------------
// ui_gf_self_show is the menu dvar that controls visibility of the bottom bar.
// The update loop only re-pushes on change (cached in p.gf_sbShow), so setting
// the dvar to 0 externally sticks until we clear the cache to let it re-show.

gf_bridgeSelfBar( enable )
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( enable )
            p.gf_sbShow = undefined;   // next update tick will re-push show=1
        else
            p setClientDvar( "ui_gf_self_show", "0" );
    }
    if ( enable )
        gf_bridgeNotify( "^2Self Bar: ON" );
    else
        gf_bridgeNotify( "^7Self Bar: OFF" );
}

// --- Visual tweaks -----------------------------------------------------------
// Pushes a client dvar to every connected player. If the dvar is one of the
// persistent gf_vis_* tweaks (gf_visTweakMap in _gf_rounds), the value is also
// stored there so gf_applyVisTweaks re-applies it on every later spawn. The
// special value "stock" clears the persistence and one-shots the engine default
// (fresh clients are always stock — setClientDvar values are session-only and
// never saved to the player's config). Non-mapped dvars (cg_thirdPerson,
// cg_drawFPS, crosshair toggles, ...) stay one-shot, as before.

gf_bridgeVisSet( dvar, value )
{
    m = maps\mp\gametypes\_gf_rounds::gf_visTweakMap();
    keys = getArrayKeys( m );
    for ( i = 0; i < keys.size; i++ )
    {
        if ( m[keys[i]] != dvar )
            continue;
        if ( value == "stock" )
        {
            setDvar( keys[i], "" );
            value = maps\mp\gametypes\_gf_rounds::gf_visEngineDefault( dvar );
        }
        else
            setDvar( keys[i], value );
        break;
    }

    players = level.players;
    for ( i = 0; i < players.size; i++ )
        players[i] setClientDvar( dvar, value );
    gf_bridgeNotify( "^3Vis: " + dvar + " = " + value );
}

// visreset -- return ALL persistent tweaks to stock in one shot: clear every
// gf_vis_* dvar (future spawns untouched), push engine defaults to the players
// already in the session, and restore the map's default vision set.

gf_bridgeVisReset()
{
    m = maps\mp\gametypes\_gf_rounds::gf_visTweakMap();
    keys = getArrayKeys( m );
    players = level.players;
    for ( i = 0; i < keys.size; i++ )
    {
        setDvar( keys[i], "" );
        def = maps\mp\gametypes\_gf_rounds::gf_visEngineDefault( m[keys[i]] );
        for ( j = 0; j < players.size; j++ )
            players[j] setClientDvar( m[keys[i]], def );
    }

    // "Stock" for VISION means Gunfight's default look (the "enhance" contrast pop), NOT the map's
    // bare vision — the pop is part of the mod now, so a reset must land back on it, the same place a
    // fresh round would. Clearing the dvar IS that reset (gf_roundVisionKey falls back to "enhance").
    // An admin who genuinely wants the untouched map vision asks for it explicitly: vision_normal.
    if ( getDvar( "gf_vis_vision" ) != "" )
    {
        setDvar( "gf_vis_vision", "" );
        // Same rule as gf_bridgeVision: a pause owns the vision, so clear the persisted key but let
        // gf_bridgeRestoreVision do the actual restore on resume.
        if ( !isDefined( level.gf_paused ) || !level.gf_paused )
            gf_bridgeRestoreVision( 0.5 );
    }

    gf_bridgeNotify( "^7Visuals: stock" );
}

// --- Health regen ------------------------------------------------------------

gf_bridgeRegen( enable )
{
    level.healthRegenDisabled = !enable;
    if ( enable )
    {
        setDvar( "scr_player_healthregentime", "5" );
        gf_bridgeNotify( "^3Health Regen ON" );
    }
    else
    {
        setDvar( "scr_player_healthregentime", "0" );
        gf_bridgeNotify( "^7Health Regen OFF" );
    }
}

// --- Per-player commands -----------------------------------------------------

// Resolve a connected player by the entity number the RCON panel shows in its status
// "num" column (same id used by every per-player bridge command). undefined if not found.
gf_bridgeFindPlayer( pNum )
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
        if ( players[i] getEntityNumber() == pNum )
            return players[i];
    return undefined;
}

gf_bridgePlayerCmd( action, numStr )
{
    target = gf_bridgeFindPlayer( int( numStr ) );
    if ( !isDefined( target ) ) return;

    name = target.name;
    if ( action == "god"      ) { target enableInvulnerability(); gf_bridgeNotify( "^3God: "      + name ); }
    if ( action == "freeze"   ) { target freezeControls( true );  gf_bridgeNotify( "^1Frozen: "   + name ); }
    if ( action == "unfreeze" ) { target freezeControls( false ); gf_bridgeNotify( "^2Unfrozen: " + name ); }
    if ( action == "perks"    )
    {
        target SetPerk( "specialty_longersprint"   );
        target SetPerk( "specialty_movefaster"     );
        target SetPerk( "specialty_gpsjammer"      );
        target SetPerk( "specialty_fastreload"     );
        target SetPerk( "specialty_bulletaccuracy" );
        gf_bridgeNotify( "^2Perks: " + name );
    }
}

// --- Team management ---------------------------------------------------------
// Move a player between allies / axis / spectator from the RCON panel. The engine's own team
// switch (level.allies/axis/spectator = the team-menu handlers) SUICIDES a player who is
// "playing", so it's only clean while a player is frozen and the round is unscored — i.e. the
// native prematch countdown. A move at any other time (live round, killcam, min-players hold)
// is DEFERRED via pers["gf_pendingTeam"] (the only state that survives the between-round
// map_restart) and applied during the NEXT round's prematch by gf_bridgeWatchPendingTeam. We do
// NOT flip pers["team"] on a live player: gf_onPlayerDamage reads it for friendly-fire, so a
// mid-round flip would break damage teams. scr_team_maxsize is enforced here (mirroring
// gf_playerSpawnedCB's overflow rule) so an over-cap move is refused with feedback, not silently
// bounced to spectator. Moving a bot is allowed.

// arg = "<num>_<allies|axis|spec>". force=true applies the move immediately even mid-round
// (stock switch -> respawns the player), bypassing the next-round defer; the team-size cap still holds.
gf_bridgeTeamCmd( arg, force )
{
    if ( !isDefined( force ) )
        force = false;

    parts = strTok( arg, "_" );
    if ( parts.size < 2 )
        return;

    team = gf_bridgeTeamCode( parts[1] );
    if ( team == "" )
        return;

    target = gf_bridgeFindPlayer( int( parts[0] ) );
    if ( !isDefined( target ) )
        return;

    name = target.name;

    // Team-size cap (mirror gf_playerSpawnedCB): refuse an over-cap move with feedback instead
    // of letting the spawn overflow silently dump the player into spectator. Spectator is uncapped.
    if ( team != "spectator" && gf_bridgeTeamFull( target, team ) )
    {
        gf_bridgeNotify( "^1Team full: " + gf_bridgeTeamLabel( team ) + " (scr_team_maxsize)" );
        return;
    }

    // force applies immediately regardless of round state (admin override — the ⚠ in the panel warns
    // it respawns a live player, costing them the round; during a live round that's a mid-round death).
    if ( force || gf_bridgeTeamSafeNow() )
    {
        target gf_applyTeamMove( team );
        if ( force )
            gf_bridgeNotify( "^1Force team: " + name + " ^7-> " + gf_bridgeTeamLabel( team ) );
        else
            gf_bridgeNotify( "^2Team: " + name + " ^7-> " + gf_bridgeTeamLabel( team ) );
    }
    else
    {
        // Live round / killcam / min-players hold: don't touch the player now (a switch would
        // suicide them and a pers["team"] flip would break friendly-fire). Queue for next round.
        target.pers["gf_pendingTeam"] = team;
        gf_bridgeNotify( "^3Team: " + name + " ^7-> " + gf_bridgeTeamLabel( team ) + " ^3(next round)" );
    }
}

// True if `team` is already at scr_team_maxsize (excluding `target`). Counts by pers["team"] to
// match gf_playerSpawnedCB's overflow check. maxsize <= 0 means uncapped.
gf_bridgeTeamFull( target, team )
{
    maxTeam = getDvarInt( "scr_team_maxsize" );
    if ( maxTeam <= 0 )
        return false;
    count = 0;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( players[i] == target )
            continue;
        if ( players[i].pers["team"] == team )
            count++;
    }
    return count >= maxTeam;
}

// A live switch is only clean while level.inPrematchPeriod is true: players are frozen and the
// round isn't scored, so the stock switch's suicide/respawn is the harmless warmup team-change.
// This deliberately COVERS the pre-prematch lobby/load hold as well — the engine sets
// inPrematchPeriod BEFORE onStartGameType (stock _globallogic sets it true at :1845; our hold is
// the last statement of onStartGameType and it isn't cleared until prematchPeriod ends inside the
// later-threaded startGame), so team moves made while arranging the lobby apply immediately on the
// correct side. (The old POST-prematch min-players hold this once excluded was deleted 2026-07-04.)
gf_bridgeTeamSafeNow()
{
    return isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod;
}

// Apply a team move to self. If the player is already in-world this round (spawned/frozen in
// prematch), use the full stock switch (respawns them on the new side now). Otherwise a quiet
// persistent reassign is enough: the round's spawn wave reads pers["team"] and _globallogic_player
// re-derives self.team from it, so they simply spawn on the new side — no respawn, no double-spawn.
gf_applyTeamMove( team )
{
    if ( self.sessionstate == "playing" )
    {
        if      ( team == "allies" ) self [[level.allies]]();
        else if ( team == "axis"   ) self [[level.axis]]();
        else                         self [[level.spectator]]();

        // The stock switch suicide()s a "playing" (prematch-frozen, alive) player without restoring
        // its life, so an admin move applied during prematch can leave the player DEAD/spectating the
        // round (maySpawn denies the switch's respawn once both teams have existed). gf_reseatRespawn
        // gives the life back so the respawn is admitted. Real teams only (spectator wants no respawn).
        if ( team != "spectator" )
            self thread maps\mp\gametypes\_gf_rounds::gf_reseatRespawn();
    }
    else
        self gf_forceTeamQuiet( team );
}

// The persistent-state half of the stock menuAllies/menuAxis/menuSpectator (minus the suicide +
// beginClassChoice): set pers["team"]/team/sessionteam and clear the cached class/weapon/model so
// the next spawn rebuilds them for the new side. Only ever called on a NOT-yet-spawned player
// (from gf_applyTeamMove's else branch), so touching self.team here can't disturb a live combatant.
gf_forceTeamQuiet( team )
{
    self.pers["team"]       = team;
    self.team               = team;
    self.pers["class"]      = undefined;
    self.class              = undefined;
    self.pers["weapon"]     = undefined;
    self.pers["savedmodel"] = undefined;
    if ( team == "spectator" )
        self.sessionteam = "spectator";
    else
        self.sessionteam = team;
}

// Watches "spawned_player" (fired by gf_playerSpawnedCB on every spawn) and applies any queued
// team move once the player exists and has spawned this round. Re-threaded each round from
// gf_bridgeInit; endon "game_ended" so it dies with the match. This is the deferred-apply engine:
// it fires during the next round's prematch (when players spawn frozen), which is exactly the safe
// window for the stock switch. A pending move applied this way clears its flag first, so the
// switch's respawn (which re-fires "spawned_player") doesn't re-apply it.
gf_bridgeWatchPendingTeam()
{
    level endon( "game_ended" );
    level endon( "gf_bridge_reinit" );   // collapse to one live copy when gf_bridgeInit re-threads
    for ( ;; )
    {
        level waittill( "spawned_player" );
        gf_applyPendingTeamMoves();
    }
}

// Apply every queued team move for players that currently exist. Called on each spawn (see
// gf_bridgeWatchPendingTeam), so it's idempotent: a player with no pending flag is skipped, and
// the flag is cleared before the move so it runs at most once.
gf_applyPendingTeamMoves()
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p.pers["gf_pendingTeam"] ) )
            continue;
        team = p.pers["gf_pendingTeam"];
        p.pers["gf_pendingTeam"] = undefined;   // clear first: the switch below re-fires spawned_player
        if ( team != "allies" && team != "axis" && team != "spectator" )
            continue;
        // Re-check the cap at apply time (roster may have changed since the move was queued).
        if ( team != "spectator" && gf_bridgeTeamFull( p, team ) )
            continue;
        p gf_applyTeamMove( team );
    }
}

// --- Per-team bot add / remove (RCON panel) ----------------------------------
// Precise per-team bot control that reuses the existing move machinery instead of the global
// bots_team dvar. add: spawn one bot, then (once it finishes connecting) place it on `team` via
// gf_applyTeamMove — the same clean switch the panel's team-move uses (stock switch while frozen
// in prematch, quiet pers reassign otherwise). kick: remove ONE bot currently on `team`.
// Bots only (istestclient) — humans are never touched. CAVEAT: with fill ON (gf_fill_n > 0) the
// Gunfight round-boundary reconciler (_bot.gsc) owns bot counts + placement and re-derives them at
// every round boundary, so a manual per-team add/kick/move is TRANSIENT (it lasts at most until
// the current round ends) — set gf_fill_n 0 (fill off = manual mode) to make it stick. Human
// moves always stick (the reconciler never touches humans).
// "+ Add Bot" (teamless): spawn one autoassigned bot. Replaces the old `set bots_manage_add 1`
// path (the addBots loop that consumed it is deleted). With fill on (gf_fill_n>0) the reconciler
// owns counts so a manual add is transient (parked as surplus at the next round boundary); with
// fill off it sticks.
gf_bridgeAddBot()
{
    bot = maps\mp\gametypes\_bot::add_bot();
    if ( isDefined( bot ) )
        gf_bridgeNotify( "^2Bot added" );
    else
        gf_bridgeNotify( "^1Bot add failed" );
}

gf_bridgeAddBotToTeam( team )
{
    // Cap check up front (mirror gf_playerSpawnedCB); the bot doesn't exist yet, so exclude nothing.
    if ( gf_bridgeTeamFull( undefined, team ) )
    {
        gf_bridgeNotify( "^1Team full: " + gf_bridgeTeamLabel( team ) + " (scr_team_maxsize)" );
        return;
    }

    bot = maps\mp\gametypes\_bot::add_bot();
    if ( !isDefined( bot ) )
    {
        gf_bridgeNotify( "^1Bot add failed" );
        return;
    }

    bot thread gf_bridgeMoveBotWhenReady( team );
    gf_bridgeNotify( "^2Bot -> " + gf_bridgeTeamLabel( team ) );
}

// Wait for the freshly-added bot to finish connecting (autoassign sets pers["team"]) before moving
// it, so the switch lands on a real side rather than mid-connect. Bounded ~10s; a no-op if the bot
// already landed on the target team.
gf_bridgeMoveBotWhenReady( team )
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    ticks = 0;
    while ( ticks < 100 && !isDefined( self.pers["team"] ) )
    {
        wait 0.1;
        ticks++;
    }

    if ( !isDefined( self ) || !isDefined( self.pers["team"] ) )
        return;
    if ( self.pers["team"] == team )
        return;

    self gf_applyTeamMove( team );
}

// Kick one bot currently on `team`. Picks the first match; humans are never eligible.
gf_bridgeKickBotFromTeam( team )
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) || !( p istestclient() ) )
            continue;
        if ( p.pers["team"] != team )
            continue;
        kick( p getEntityNumber(), "EXE_PLAYERKICKED" );
        gf_bridgeNotify( "^3Kicked bot from " + gf_bridgeTeamLabel( team ) );
        return;
    }
    gf_bridgeNotify( "^1No bot on " + gf_bridgeTeamLabel( team ) );
}

// --- Balance teams now (RCON panel) ------------------------------------------
// Even out allies vs axis by moving players from the larger team to the smaller. Prefers moving
// BOTS (least disruptive to humans). Uses the same safety as a manual move: applies immediately
// while players are frozen in prematch/the lobby hold (gf_bridgeTeamSafeNow), otherwise DEFERS to
// next round via pers["gf_pendingTeam"] so a live human isn't suicided mid-round. Inherently
// cap-safe: we only move toward the SMALLER team, so the target never exceeds the source's count.
gf_bridgeBalanceTeams()
{
    allies = gf_bridgeTeamMembers( "allies" );
    axis   = gf_bridgeTeamMembers( "axis" );

    diff = allies.size - axis.size;
    if ( diff < 0 )
        diff = 0 - diff;

    if ( diff <= 1 )
    {
        gf_bridgeNotify( "^2Teams balanced (" + allies.size + "v" + axis.size + ")" );
        return;
    }

    if ( allies.size > axis.size )
    {
        from   = allies;
        toTeam = "axis";
    }
    else
    {
        from   = axis;
        toTeam = "allies";
    }

    movers = gf_bridgePickMovers( from, int( diff / 2 ) );   // bots first, then humans

    deferred = 0;
    for ( i = 0; i < movers.size; i++ )
    {
        p = movers[i];
        if ( gf_bridgeTeamSafeNow() )
            p gf_applyTeamMove( toTeam );
        else
        {
            p.pers["gf_pendingTeam"] = toTeam;
            deferred++;
        }
    }

    msg = "^2Balanced ^7-> " + gf_bridgeTeamLabel( toTeam ) + " +" + movers.size;
    if ( deferred > 0 )
        msg += " ^3(" + deferred + " next round)";
    gf_bridgeNotify( msg );
}

// Playing members of `team` (excludes the server-side democlient; bots included).
gf_bridgeTeamMembers( team )
{
    out = [];
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( !isDefined( p ) || p isdemoclient() )
            continue;
        if ( p.pers["team"] == team )
            out[ out.size ] = p;
    }
    return out;
}

// Up to `n` movers from `from`, bots first (least disruptive) then humans to top up.
gf_bridgePickMovers( from, n )
{
    picked = [];
    for ( i = 0; i < from.size && picked.size < n; i++ )
        if ( from[i] istestclient() )
            picked[ picked.size ] = from[i];
    for ( i = 0; i < from.size && picked.size < n; i++ )
        if ( !( from[i] istestclient() ) )
            picked[ picked.size ] = from[i];
    return picked;
}

gf_bridgeTeamCode( s )
{
    if ( s == "allies" )                    return "allies";
    if ( s == "axis" )                      return "axis";
    if ( s == "spec" || s == "spectator" )  return "spectator";
    return "";
}

gf_bridgeTeamLabel( team )
{
    if ( team == "allies" ) return "Allies";
    if ( team == "axis" )   return "Axis";
    return "Spectator";
}

// ============================================================================
// FUN / SILLY -- mined from EnCoReV8 + iMCSx mod menus
// ============================================================================

// --- Vision sets -------------------------------------------------------------
// visionSetNaked swaps the post-process vision. In the MP server VM it is a
// BARE (non-method) builtin -- _globallogic/_killcam/_pregame all call it with
// no entity prefix, and bare = global vision applied to every client. (Calling
// it as a per-player method `player visionSetNaked()` throws "unknown function"
// because no method builtin of that name is registered in MP.)
//
// A vision set only APPLIES if it is loaded for the running level. The
// authoritative loaded-in-every-MP-map list is zone_source/common_vision.csv
// (verified 2026-07-03) -- every set below is in it, so they all work on any
// map. Sets NOT in that list silently no-op, which is why the old "contrast"
// (cheat_bw_contrast) and "night"/"invert" mappings were misleading: cheat_bw_
// invert and default_night are byte-identical (sat 1, contrast 1.2) and do NOT
// invert or darken -- they just pop contrast. That look is now honestly named
// "enhance". A true colour invert is impossible via the r_film* path (no film
// param negates RGB; no loaded .vision uses negative values).
//
// unknown key -> map default (safe restore). "normal" also restores.
//
// PERSISTENCE: vision is level state, so the between-round map_restart resets
// it to the map default — and the stock prematch countdown then forces
// "mpIntro" + blends back to the map vision. The chosen KEY is persisted in
// gf_vis_vision and re-applied AFTER each prematch by _gf_rounds::gf_applyRoundVision.
// The key is stored (not the set name) so re-apply always goes through the same
// mapping (_gf_rounds::gf_visionSetForKey, which also owns the key->set table).
//
// ⚠ EMPTY gf_vis_vision does NOT mean "map default" — it means "the Gunfight DEFAULT" (enhance).
// The map's own vision is reachable only via the EXPLICIT "normal" key, which is why gf_bridgeVision
// below persists "normal" as a string instead of clearing the dvar.

gf_bridgeVision( vkey )
{
    set = maps\mp\gametypes\_gf_rounds::gf_visionSetForKey( vkey );

    if ( set == level.gf_defaultVision )
        setDvar( "gf_vis_vision", "normal" );  // EXPLICIT map default -- clearing would fall back to the gf "enhance" default
    else
        setDvar( "gf_vis_vision", vkey );

    // A pause OWNS the vision (B&W) for as long as it is up, so don't apply now — just persist the
    // key. gf_bridgeRestoreVision re-reads it on resume, so the admin's pick lands the moment the
    // match unfreezes instead of silently un-greying a paused match.
    if ( isDefined( level.gf_paused ) && level.gf_paused )
    {
        gf_bridgeNotify( "^5Vision: " + vkey + " ^7(applies on resume — match is paused)" );
        return;
    }

    visionSetNaked( set, 0.5 );                // bare = global, all clients
    gf_bridgeNotify( "^5Vision: " + vkey );
}

// --- Explosive bullets -------------------------------------------------------
// Each shot traces forward from the eye and detonates at the impact point.
// Per-player watcher survives across rounds (endon disconnect); a connect
// watcher arms late joiners. Throttled so full-auto doesn't lag the server.

gf_bridgeExpBullets( enable )
{
    if ( enable )
    {
        if ( level.gf_expBullets ) return;
        level.gf_expBullets = true;
        if ( !isDefined( level.gf_fxExplode ) )
            level.gf_fxExplode = loadfx( "explosions/fx_default_explosion_mp" );
        players = level.players;
        for ( i = 0; i < players.size; i++ )
            players[i] thread gf_expBulletsPlayer();
        level thread gf_expBulletsConnectWatch();
        gf_bridgeNotify( "^1Explosive Bullets ON" );
    }
    else
    {
        level.gf_expBullets = false;
        level notify( "gf_expbullets_stop" );
        gf_bridgeNotify( "^7Explosive Bullets OFF" );
    }
}

gf_expBulletsConnectWatch()
{
    level endon( "game_ended" );
    level endon( "gf_expbullets_stop" );
    for ( ;; )
    {
        level waittill( "connected", player );
        player thread gf_expBulletsPlayer();
    }
}

gf_expBulletsPlayer()
{
    self endon( "disconnect" );
    level endon( "game_ended" );
    level endon( "gf_expbullets_stop" );

    self.gf_expLast = 0;
    for ( ;; )
    {
        self waittill( "weapon_fired" );
        if ( getTime() - self.gf_expLast < 120 )   // ms throttle vs full-auto
            continue;
        self.gf_expLast = getTime();

        eye     = self getEye();
        forward = anglesToForward( self getPlayerAngles() );
        end     = eye + ( forward[0] * 8000, forward[1] * 8000, forward[2] * 8000 );
        tr      = bulletTrace( eye, end, false, self );
        pos     = tr["position"];

        if ( isDefined( level.gf_fxExplode ) )
            playFx( level.gf_fxExplode, pos );
        r = getDvarInt( "gf_expbullets_radius" );   // RCON Blast Radius slider; live each shot
        if ( r < 1 ) r = 200;
        RadiusDamage( pos, r, 120, 40, self );
    }
}

// --- Drunk mode --------------------------------------------------------------
// Continuous mild camera EarthQuake on every living player -- wobble without
// fighting their input.

gf_bridgeDrunk( enable )
{
    if ( enable )
    {
        if ( level.gf_drunk ) return;
        level.gf_drunk = true;
        level thread gf_drunkLoop();
        gf_bridgeNotify( "^5Drunk Mode ON" );
    }
    else
    {
        level.gf_drunk = false;
        level notify( "gf_drunk_stop" );
        gf_bridgeNotify( "^7Drunk Mode OFF" );
    }
}

gf_drunkLoop()
{
    level endon( "game_ended" );
    level endon( "gf_drunk_stop" );
    for ( ;; )
    {
        players = level.players;
        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];
            if ( p.health <= 0 ) continue;
            EarthQuake( 0.4, 1.2, p.origin, 200 );
        }
        wait 1.0;
    }
}

// --- Invisible players (troll) ----------------------------------------------

gf_bridgeInvisible( enable )
{
    level.gf_invisible = enable;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( enable )
            players[i] hide();
        else
            players[i] show();
    }
    if ( enable )
        gf_bridgeNotify( "^5Players Invisible" );
    else
        gf_bridgeNotify( "^7Players Visible" );
}

// --- One-shot earthquake -----------------------------------------------------

gf_bridgeQuake()
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
        EarthQuake( 0.7, 2.0, players[i].origin, 1200 );
    gf_bridgeNotify( "^1*** EARTHQUAKE ***" );
}

// --- Teleport all to anchor (Player 1 / host) -------------------------------

gf_bridgeTeleportAll()
{
    players = level.players;
    if ( players.size < 2 ) return;

    anchor = players[0];
    org    = anchor.origin;
    ang    = anchor.angles;

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];
        if ( p == anchor )   continue;
        if ( p.health <= 0 ) continue;
        p SetOrigin( org + ( randomInt( 40 ) - 20, randomInt( 40 ) - 20, 0 ) );
        p SetPlayerAngles( ang );
    }
    gf_bridgeNotify( "^3Gathered all players -> " + anchor.name );
}

// --- Broadcast message -------------------------------------------------------
// Reads dvar gf_say (set by RCON just before this command) and bold-prints it.

gf_bridgeBroadcast()
{
    msg = getDvar( "gf_say" );
    if ( msg == "" ) return;
    iPrintLnBold( msg );   // intentional ALL-players broadcast (the panel's "say to everyone"), not admin-only feedback
}
