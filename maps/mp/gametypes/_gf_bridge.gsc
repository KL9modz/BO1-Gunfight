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
//   infammo_on         - start infinite ammo loop
//   infammo_off        - stop infinite ammo loop
//   radar_on / radar_off       - all players visible on minimap
//   headshots_on / headshots_off - non-headshot damage zeroed
//   pgod_<num>         - god mode one player by entitynum
//   pfreeze_<num>      - freeze one player
//   punfreeze_<num>    - unfreeze one player
//   pperks_<num>       - give perks to one player
//   pnoclip_<num>      - noclip one player
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

    setDvar( "gf_state", "0:0:1:0:0:" + level.gameType );

    level.gf_paused        = false;
    level.gf_infAmmo       = false;
    level.gf_godMode       = false;
    level.gf_radarOn       = false;
    level.gf_headshotsOnly = false;

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

// --- Infinite ammo -----------------------------------------------------------

gf_bridgeInfAmmo( enable )
{
    if ( enable )
    {
        if ( level.gf_infAmmo ) return;
        level.gf_infAmmo = true;
        level thread gf_infAmmoLoop();
        iPrintLnBold( "^3Infinite Ammo ON" );
    }
    else
    {
        level.gf_infAmmo = false;
        level notify( "gf_infammo_stop" );
        iPrintLnBold( "^7Infinite Ammo OFF" );
    }
}

gf_infAmmoLoop()
{
    level endon( "game_ended" );
    level endon( "gf_infammo_stop" );
    for ( ;; )
    {
        wait 0.5;
        players = level.players;
        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];
            if ( p.health <= 0 ) continue;
            weapons = p getWeaponsListPrimaries();
            for ( j = 0; j < weapons.size; j++ )
                p setWeaponAmmoClip( weapons[j], 9999 );
        }
    }
}

// --- Radar always on ---------------------------------------------------------
// setMatchFlag mirrors the UAV state flags the engine reads for minimap display.

gf_bridgeRadar( enable )
{
    level.gf_radarOn = enable;
    if ( enable )
    {
        setMatchFlag( "radar_allies", 1 );
        setMatchFlag( "radar_axis",   1 );
        iPrintLnBold( "^3Radar: Always ON" );
    }
    else
    {
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
