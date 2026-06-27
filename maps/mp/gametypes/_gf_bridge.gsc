// GSC Bridge -- RCON -> GSC dispatcher
// RCON sends: set gf_cmd <command>
// This poll loop reads, clears, and dispatches.
//
// Commands (send via RCON: set gf_cmd <cmd>):
//   pause              - freeze match clock + all player controls
//   resume             - resume clock + unfreeze players
//   botdiff_easy/normal/hard/fu  - set bot difficulty
//   endround_allies    - force allies to win this round
//   endround_axis      - force axis to win this round
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
//   pnoclip_<num>      - noclip one player
//
// FUN / SILLY (mined from EnCoReV8 + iMCSx mod menus):
//   vision_<set>       - VisionSetNaked all players: normal/bw/contrast/invert/night
//   thirdperson_1/0    - cg_thirdPerson all players (setClientDvar)
//   fps_1/0            - cg_drawFPS all players (setClientDvar)
//   expbullets_on/off  - every shot detonates on impact (trace + RadiusDamage + FX)
//   longknife_<range>  - aim_automelee_range all players (e.g. 256 on, 64 off)
//   drunk_on/off       - continuous mild EarthQuake on every player's camera
//   invis_on/off       - hide()/show() all player models (troll)
//   quake              - one strong EarthQuake centered on every player
//   tpall              - teleport all players to Player 1 (host/anchor)
//   saymsg             - iPrintLnBold the contents of dvar gf_say to everyone
//
// Telemetry dvar (read-only, updated every 2s):
//   gf_state -> "allies_wins:axis_wins:round:alive_allies:alive_axis"
//   e.g.  "3:2:5:2:1"

#include maps\mp\_utility;
#include maps\mp\gametypes\_globallogic_utils;

gf_bridgeInit()
{
    level endon( "game_ended" );

    if ( getDvar( "gf_cmd" ) == "" )
        setDvar( "gf_cmd", "" );
    if ( getDvar( "gf_say" ) == "" )
        setDvar( "gf_say", "" );
    if ( getDvar( "gf_expbullets_radius" ) == "" )
        setDvar( "gf_expbullets_radius", "200" );   // RCON Blast Radius slider default

    setDvar( "gf_state", "0:0:1:0:0:" + level.gameType );

    level.gf_paused        = false;
    level.gf_infAmmo       = false;
    level.gf_godMode       = false;
    level.gf_radarOn       = false;
    level.gf_headshotsOnly = false;
    level.gf_expBullets    = false;
    level.gf_drunk         = false;
    level.gf_invisible     = false;
    level.gf_defaultVision = getDvar( "mapname" );   // for vision_normal reset

    level thread gf_bridgeTelemetry();

    for ( ;; )
    {
        wait 0.5;
        cmd = getDvar( "gf_cmd" );
        if ( cmd == "" )
            continue;

        setDvar( "gf_cmd", "" );
        level thread gf_bridgeDispatch( cmd );
    }
}

// --- Telemetry ---------------------------------------------------------------
// Writes match state into gf_state every 2s so the RCON tool can display
// a live scoreboard without needing new API endpoints.

gf_bridgeTelemetry()
{
    level endon( "game_ended" );

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

        setDvar( "gf_state", wA + ":" + wX + ":" + rn + ":" + aA + ":" + aX + ":" + level.gameType );
    }
}

// --- Dispatcher --------------------------------------------------------------

gf_bridgeDispatch( cmd )
{
    if ( cmd == "pause"  ) { gf_bridgePause();  return; }
    if ( cmd == "resume" ) { gf_bridgeResume(); return; }

    if ( cmd == "botdiff_easy"   ) { maps\mp\gametypes\_bot::bot_set_difficulty( "easy"   ); iPrintLnBold( "^2Bot: Easy"   ); return; }
    if ( cmd == "botdiff_normal" ) { maps\mp\gametypes\_bot::bot_set_difficulty( "normal" ); iPrintLnBold( "^2Bot: Normal" ); return; }
    if ( cmd == "botdiff_hard"   ) { maps\mp\gametypes\_bot::bot_set_difficulty( "hard"   ); iPrintLnBold( "^1Bot: Hard"   ); return; }
    if ( cmd == "botdiff_fu"     ) { maps\mp\gametypes\_bot::bot_set_difficulty( "fu"     ); iPrintLnBold( "^1Bot: FU"     ); return; }

    if ( cmd == "endround_allies" ) { maps\mp\gametypes\sd::sd_endGame( "allies", "" ); return; }
    if ( cmd == "endround_axis"   ) { maps\mp\gametypes\sd::sd_endGame( "axis",   "" ); return; }

    // Visual tweaks -- setClientDvar sent to all players
    // Format: vis<key>_<value>  e.g. visgamma_1.5
    if ( isSubStr( cmd, "visfog_"        ) ) { gf_bridgeVisSet( "r_fog",                getSubStr( cmd, 7,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "visambient_"    ) ) { gf_bridgeVisSet( "r_lightTweakAmbient",  getSubStr( cmd, 11, cmd.size ) ); return; }
    if ( isSubStr( cmd, "visgridint_"    ) ) { gf_bridgeVisSet( "r_lightGridIntensity", getSubStr( cmd, 11, cmd.size ) ); return; }
    if ( isSubStr( cmd, "visgridcon_"    ) ) { gf_bridgeVisSet( "r_lightGridContrast",  getSubStr( cmd, 11, cmd.size ) ); return; }
    if ( isSubStr( cmd, "visgamma_"      ) ) { gf_bridgeVisSet( "r_gamma",              getSubStr( cmd, 9,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "vishdr_"        ) ) { gf_bridgeVisSet( "r_fullHDRrendering",   getSubStr( cmd, 7,  cmd.size ) ); return; }
    if ( isSubStr( cmd, "viscrosshair_"  ) ) { gf_bridgeVisSet( "cg_drawCrosshair",     getSubStr( cmd, 13, cmd.size ) ); return; }
    if ( isSubStr( cmd, "visnames_"      ) ) { gf_bridgeVisSet( "cg_drawCrosshairNames",getSubStr( cmd, 9,  cmd.size ) ); return; }
    // HUD element toggles
    if ( cmd == "selfbar_on"  ) { gf_bridgeSelfBar( true );  return; }
    if ( cmd == "selfbar_off" ) { gf_bridgeSelfBar( false ); return; }

    if ( cmd == "killstreaks_on"  ) { level.killstreaksenabled = true;  iPrintLnBold( "^3Killstreaks ON"  ); return; }
    if ( cmd == "killstreaks_off" ) { level.killstreaksenabled = false; iPrintLnBold( "^7Killstreaks OFF" ); return; }
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
}

// --- Pause / Resume ----------------------------------------------------------

gf_bridgePause()
{
    if ( level.gf_paused ) return;
    level.gf_paused = true;
    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    players = level.players;
    for ( i = 0; i < players.size; i++ )
        players[i] freezeControls( true );
    iPrintLnBold( "^3-- MATCH PAUSED --" );
}

gf_bridgeResume()
{
    if ( !level.gf_paused ) return;
    level.gf_paused = false;
    maps\mp\gametypes\_globallogic_utils::resumeTimer();
    players = level.players;
    for ( i = 0; i < players.size; i++ )
        players[i] freezeControls( false );
    iPrintLnBold( "^2-- MATCH RESUMED --" );
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
        iPrintLnBold( "^3God Mode ON" );
    else
        iPrintLnBold( "^7God Mode OFF" );
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
        iPrintLnBold( "^2All Perks ON" );
    else
        iPrintLnBold( "^7Perks cleared" );
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
    iPrintLnBold( "^2Perks synced" );
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
        iPrintLnBold( "^3Infinite Ammo ON" );
    }
    else
    {
        setDvar( "sv_FullAmmo", 0 );
        iPrintLnBold( "^7Infinite Ammo OFF" );
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
        iPrintLnBold( "^3Radar: Always ON" );
    }
    else
    {
        setDvar( "scr_game_forceradar", 0 );
        setMatchFlag( "radar_allies", 0 );
        setMatchFlag( "radar_axis",   0 );
        iPrintLnBold( "^7Radar: Normal" );
    }
}

// --- Headshots only ----------------------------------------------------------
// Sets a flag read by gf_onPlayerDamage in _gf_rounds.gsc.
// Non-headshot damage is zeroed out there -- only head/helmet hits kill.

gf_bridgeHeadshots( enable )
{
    level.gf_headshotsOnly = enable;
    if ( enable )
        iPrintLnBold( "^3Headshots Only: ON" );
    else
        iPrintLnBold( "^7Headshots Only: OFF" );
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
        iPrintLnBold( "^2Self Bar: ON" );
    else
        iPrintLnBold( "^7Self Bar: OFF" );
}

// --- Visual tweaks -----------------------------------------------------------
// Pushes a client dvar to every connected player.

gf_bridgeVisSet( dvar, value )
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
        players[i] setClientDvar( dvar, value );
    iPrintLnBold( "^3Vis: " + dvar + " = " + value );
}

// --- Health regen ------------------------------------------------------------

gf_bridgeRegen( enable )
{
    level.healthRegenDisabled = !enable;
    if ( enable )
    {
        setDvar( "scr_player_healthregentime", "5" );
        iPrintLnBold( "^3Health Regen ON" );
    }
    else
    {
        setDvar( "scr_player_healthregentime", "0" );
        iPrintLnBold( "^7Health Regen OFF" );
    }
}

// --- Per-player commands -----------------------------------------------------

gf_bridgePlayerCmd( action, numStr )
{
    pNum = int( numStr );
    target = undefined;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( players[i] getEntityNumber() == pNum )
        {
            target = players[i];
            break;
        }
    }
    if ( !isDefined( target ) ) return;

    name = target.name;
    if ( action == "god"      ) { target enableInvulnerability(); iPrintLnBold( "^3God: "      + name ); }
    if ( action == "freeze"   ) { target freezeControls( true );  iPrintLnBold( "^1Frozen: "   + name ); }
    if ( action == "unfreeze" ) { target freezeControls( false ); iPrintLnBold( "^2Unfrozen: " + name ); }
    if ( action == "perks"    )
    {
        target SetPerk( "specialty_longersprint"   );
        target SetPerk( "specialty_movefaster"     );
        target SetPerk( "specialty_gpsjammer"      );
        target SetPerk( "specialty_fastreload"     );
        target SetPerk( "specialty_bulletaccuracy" );
        iPrintLnBold( "^2Perks: " + name );
    }
}

// ============================================================================
// FUN / SILLY -- mined from EnCoReV8 + iMCSx mod menus
// ============================================================================

// --- Vision sets -------------------------------------------------------------
// visionSetNaked swaps the post-process vision. In the MP server VM it is a
// BARE (non-method) builtin -- _globallogic/_killcam/_pregame all call it with
// no entity prefix, and bare = global vision applied to every client. (Calling
// it as a per-player method `player visionSetNaked()` throws "unknown function"
// because no method builtin of that name is registered in MP.) We use the
// cheat_* sets (always loaded) plus the map's default vision for "normal".

gf_bridgeVision( vkey )
{
    set = level.gf_defaultVision;          // "normal" -> map default
    if ( vkey == "bw"       ) set = "cheat_bw";
    if ( vkey == "contrast" ) set = "cheat_bw_contrast";
    if ( vkey == "invert"   ) set = "cheat_bw_invert";
    if ( vkey == "night"    ) set = "default_night";

    visionSetNaked( set, 0.5 );            // bare = global, all clients
    iPrintLnBold( "^5Vision: " + vkey );
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
        iPrintLnBold( "^1Explosive Bullets ON" );
    }
    else
    {
        level.gf_expBullets = false;
        level notify( "gf_expbullets_stop" );
        iPrintLnBold( "^7Explosive Bullets OFF" );
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
        iPrintLnBold( "^5Drunk Mode ON" );
    }
    else
    {
        level.gf_drunk = false;
        level notify( "gf_drunk_stop" );
        iPrintLnBold( "^7Drunk Mode OFF" );
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
        iPrintLnBold( "^5Players Invisible" );
    else
        iPrintLnBold( "^7Players Visible" );
}

// --- One-shot earthquake -----------------------------------------------------

gf_bridgeQuake()
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
        EarthQuake( 0.7, 2.0, players[i].origin, 1200 );
    iPrintLnBold( "^1*** EARTHQUAKE ***" );
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
    iPrintLnBold( "^3Gathered all players -> " + anchor.name );
}

// --- Broadcast message -------------------------------------------------------
// Reads dvar gf_say (set by RCON just before this command) and bold-prints it.

gf_bridgeBroadcast()
{
    msg = getDvar( "gf_say" );
    if ( msg == "" ) return;
    iPrintLnBold( msg );
}
