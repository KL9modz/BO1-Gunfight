#include maps\mp\gametypes\_gf_hud;
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

    if ( isDefined( level.gf_largeMode ) && level.gf_largeMode )
        value = gf_cfgFloat( level.gf_overtimeLimitDvar + "_large", 30, 0, 120 );
    else
        value = gf_cfgFloat( level.gf_overtimeLimitDvar, 15, 0, 120 );

    level.gf_cfg_overtimeLimit = value;
    return value;
}

gf_getCaptureTime()
{
    if ( isDefined( level.gf_largeMode ) && level.gf_largeMode )
        return gf_cfgFloat( "gf_capture_time_large", 5, 0.5, 60 );
    return gf_cfgFloat( "gf_capture_time", 3, 0.5, 60 );
}

gf_cfgFloat( dvar, def, lo, hi )
{
    if ( GetDvar( dvar ) == "" )
        setDvar( dvar, def );

    v = GetDvarFloat( dvar );
    clamped = maps\mp\gametypes\_globallogic_utils::getValueInRange( v, lo, hi );
    if ( clamped != v )
        setDvar( dvar, clamped );
    return clamped;
}

gf_applyFlinch()
{
    scale = gf_cfgFloat( "scr_gf_flinch", 1, 0, 3 );
    setDvar( "bg_viewKickScale", 0.2 * scale );
    return scale;
}

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

gf_armLoadGate()
{
    if ( game["roundsplayed"] > 0 )
        return;
    if ( getDvar( "gf_matchArmed" ) == "1" )
        return;
    loadOn  = ( gf_cfgFloat( "scr_gf_load_wait", 0, 0, 120 ) > 0 );
    minOn   = ( int( gf_cfgFloat( "scr_gf_min_players", 1, 1, 8 ) ) > 1 );
    lobbyOn = ( int( gf_cfgFloat( "scr_gf_lobby", 0, 0, 2 ) ) >= 1 );
    if ( !loadOn && !minOn && !lobbyOn )
        return;

    level.gf_lobbyStart = false;

    level notify( "gf_load_gate_reset" );
    level.gf_loadGateSeen = [];
    level.gf_loadGateGen  = gettime();
    level thread gf_loadGateTracker();
}

gf_loadGateTracker()
{
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    for ( ;; )
    {
        level waittill( "connecting", p );
        if ( !isDefined( p ) )
            continue;

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

gf_waitForLoadingClients()
{
    if ( game["roundsplayed"] > 0 )
        return;
    if ( getDvar( "gf_matchArmed" ) == "1" )
    {
        setDvar( "gf_matchArmed", "0" );
        return;
    }

    loadWait    = gf_cfgFloat( "scr_gf_load_wait", 0, 0, 120 );
    minP        = int( gf_cfgFloat( "scr_gf_min_players", 1, 1, 8 ) );
    lobby       = int( gf_cfgFloat( "scr_gf_lobby", 0, 0, 2 ) );
    restartMode = ( lobby >= 1 );
    manualMode  = ( lobby == 2 );
    loadGateOn  = ( loadWait > 0 );
    minGateOn   = ( minP > 1 );
    if ( !loadGateOn && !minGateOn && !restartMode )
        return;
    if ( !isDefined( level.gf_loadGateSeen ) )
        return;

    myGen         = level.gf_loadGateGen;
    start         = gettime();
    loadDeadline  = start + int( loadWait * 1000 );
    minDeadline   = start + 90000;
    lobbyDeadline = start + 600000;
    floorEnd      = start + 3000;

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

    if ( restartMode )
        for ( ei = 0; ei < elems.size; ei++ )
            elems[ei].alpha = 0;

    shownCount   = false;
    lastLoaded   = -1;
    lastTotal    = -1;
    stillLoading = 0;

    level.gf_inLobbyHold = true;

    if ( restartMode )
    {
        visionSetNaked( "mpIntro", 0 );
        setmatchflag( "cg_drawSpectatorMessages", 0 );
        setscoreboardcolumns( "none", "none", "none", "none" );
        level.forceAutoAssign = true;
        level.gf_lobbyRestartHold = true;
        level.livesDoNotReset = true;
        level thread gf_lobbyCamWatcher();
        level thread gf_lobbyRosterLoop();
        level thread gf_lobbyIconCycler();
    }

    for ( ;; )
    {
        if ( !isDefined( level.gf_loadGateGen ) || level.gf_loadGateGen != myGen )
            return;

        stillLoading = 0;
        humans       = 0;
        for ( i = 0; i < level.gf_loadGateSeen.size; i++ )
        {
            p = level.gf_loadGateSeen[i];
            if ( !isDefined( p ) )
                continue;
            if ( isDefined( p.statusicon ) && p.statusicon == "hud_status_connecting" )
            {
                humans++;
                stillLoading++;
            }
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
            if ( !shownCount && !restartMode )
            {
                cntLoaded.alpha = 1;
                cntSlash.alpha  = 1;
                cntTotal.alpha  = 1;
                shownCount = true;
            }
        }

        now = gettime();
        if ( isDefined( level.gameEnded ) && level.gameEnded )
            break;

        startClicked = ( isDefined( level.gf_lobbyStart ) && level.gf_lobbyStart );

        if ( manualMode )
        {
            if ( startClicked || now >= lobbyDeadline )
                break;
        }
        else
        {
            loadOk = ( !loadGateOn ) || ( stillLoading == 0 ) || ( now >= loadDeadline );
            minOk  = ( !minGateOn ) || ( humans >= minP ) || ( humans == 0 ) || ( now >= minDeadline );
            if ( startClicked || ( now >= floorEnd && loadOk && minOk ) )
                break;
        }

        wait 0.25;
    }

    level.gf_inLobbyHold = false;
    level.gf_lobbyRestartHold = false;
    level.livesDoNotReset = false;

    if ( restartMode )
    {
        setmatchflag( "cg_drawSpectatorMessages", 1 );
        for ( ri = 0; ri < level.players.size; ri++ )
        {
            if ( getDvarInt( "gf_diag_cd_no_lobby_dvars" ) != 1 )
            {
                level.players[ri] setClientDvar( "compass", "1" );
                level.players[ri] setClientDvar( "ui_gf_lobby_show", "0" );
            }
        }
    }

    if ( restartMode && !( isDefined( level.gameEnded ) && level.gameEnded ) )
    {
        setDvar( "gf_matchArmed", "1" );
        for ( i = 0; i < elems.size; i++ )
            if ( isDefined( elems[i] ) )
                elems[i] destroyElem();
        level notify( "gf_load_gate_reset" );
        logPrint( "GF_LOADGATE: lobby released -> map_restart(false) into match (roundsplayed=" + game["roundsplayed"] + ")\n" );
        map_restart( false );
        for ( ;; )
            wait 1;
    }

    if ( stillLoading > 0 )
    {
        loadGrace = gf_cfgFloat( "scr_gf_load_grace", 20, 0, 60 );
        if ( loadGrace > level.gracePeriod )
            level.gracePeriod = loadGrace;
    }

    logPrint( "GF_LOADGATE: released after " + ( gettime() - start ) + "ms, " + stillLoading + " client(s) still loading\n" );

    for ( i = 0; i < elems.size; i++ )
    {
        if ( isDefined( elems[i] ) )
            elems[i] destroyElem();
    }

    level notify( "gf_load_gate_reset" );
}

gf_anyTrackedClientLoading()
{
    if ( !isDefined( level.gf_loadGateSeen ) )
        return false;
    for ( i = 0; i < level.gf_loadGateSeen.size; i++ )
    {
        p = level.gf_loadGateSeen[i];
        if ( !isDefined( p ) )
            continue;
        if ( p istestclient() || p isdemoclient() )
            continue;
        if ( isDefined( p.statusicon ) && p.statusicon == "hud_status_connecting" )
            return true;
    }
    return false;
}

gf_lobbyCamWatcher()
{
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    if ( getEntArray( "mp_global_intermission", "classname" ).size == 0 )
        return;

    while ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold )
    {
        for ( i = 0; i < level.players.size; i++ )
            level.players[i] thread gf_lobbyCamPut();
        wait 0.25;
    }
}

gf_lobbyCamPut()
{
    self endon( "disconnect" );

    if ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold )
        return;
    if ( self istestclient() || self isdemoclient() )
        return;

    self gf_hideLobbyHUD();

    if ( isDefined( self.gf_inLobbyCam ) && self.gf_inLobbyCam )
        return;
    self.gf_inLobbyCam = true;

    if ( getDvarInt( "gf_diag_cd_no_lobby_dvars" ) != 1 )
        self setClientDvar( "compass", "0" );

    self [[level.spawnSpectator]]();
    self allowSpectateTeam( "allies",   false );
    self allowSpectateTeam( "axis",     false );
    self allowSpectateTeam( "freelook", true  );
    self allowSpectateTeam( "none",     true  );
    self.spectatorclient = -1;

    if ( getDvarInt( "gf_diag_cd_no_lobby_dvars" ) != 1 )
    {
        statusText = "The match will begin shortly";
        if ( int( gf_cfgFloat( "scr_gf_lobby", 0, 0, 2 ) ) == 2 )
            statusText = "Waiting for the host to start";

        self setClientDvar( "ui_gf_lobby_eyebrow", "PREGAME LOBBY" );
        self setClientDvar( "ui_gf_lobby_title",   "GUNFIGHT" );
        self setClientDvar( "ui_gf_lobby_map",     gf_mapDisplayName( getDvar( "mapname" ) ) );
        self setClientDvar( "ui_gf_lobby_welcome", "Welcome, " + self.name );
        self setClientDvar( "ui_gf_lobby_status",  statusText );
        self setClientDvar( "ui_gf_lobby_icon",    "menu_mp_weapons_famas" );
        self setClientDvar( "ui_gf_lobby_icon_on", "1" );
        self setClientDvar( "ui_gf_lobby_ic_home", "rank_prestige14" );
        self setClientDvar( "ui_gf_lobby_ic_disc", "rank_prestige15" );
        self setClientDvar( "ui_gf_lobby_show",    "1" );
    }
}

gf_lobbyRosterLoop()
{
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    lastSig = "___init___";
    while ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold )
    {
        if ( getDvarInt( "gf_diag_cd_no_lobby_dvars" ) == 1 )
        {
            wait 0.5;
            continue;
        }

        names = [];
        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( !isDefined( p ) )
                continue;
            if ( p isdemoclient() )
                continue;
            if ( isDefined( p.statusicon ) && p.statusicon == "hud_status_connecting" )
                continue;
            nm = p.name;
            if ( p istestclient() )
                nm = nm + "  (bot)";
            names[ names.size ] = nm;
        }

        sig = "" + names.size;
        for ( i = 0; i < names.size; i++ )
            sig = sig + "|" + names[i];

        if ( sig != lastSig )
        {
            lastSig = sig;
            for ( i = 0; i < level.players.size; i++ )
            {
                pl = level.players[i];
                if ( !isDefined( pl ) || pl istestclient() || pl isdemoclient() )
                    continue;
                pl setClientDvar( "ui_gf_lobby_pcount", "" + names.size );
                for ( s = 0; s < 12; s++ )
                {
                    if ( s < names.size )
                        pl setClientDvar( "ui_gf_lobby_p" + s, names[s] );
                    else
                        pl setClientDvar( "ui_gf_lobby_p" + s, "" );
                }
            }
        }

        wait 0.5;
    }
}

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

    idx = 0;
    while ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold )
    {
        wait 1.2;
        if ( getDvarInt( "gf_diag_cd_no_lobby_dvars" ) == 1 )
            continue;

        idx++;
        if ( idx >= icons.size )
            idx = 0;

        for ( i = 0; i < level.players.size; i++ )
        {
            pl = level.players[i];
            if ( !isDefined( pl ) || pl istestclient() || pl isdemoclient() )
                continue;
            pl setClientDvar( "ui_gf_lobby_icon", icons[idx] );
        }
    }
}

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

gf_hideLobbyHUD()
{
    if ( getDvarInt( "gf_diag_cd_no_lobby_dvars" ) == 1 )
        return;

    self setClientDvar( "ui_gf_lo_show",    "0" );
    self setClientDvar( "ui_gf_panel_show", "0" );
    self setClientDvar( "ui_gf_self_show",  "0" );
    self setClientDvar( "ui_gf_popup_show", "0" );
}

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

    level.gf_largeMode = gf_autoLargeFromCounts( level.playerCount["allies"], level.playerCount["axis"] );
}

gf_updateAutoTeamMode()
{
    if ( GetDvar( "scr_" + level.gameType + "_teamspawnmode" ) != "auto" )
        return;

    game["gf_autoLargeMode"] = gf_autoLargeFromCounts( level.playerCount["allies"], level.playerCount["axis"] );
}

gf_hudSkullCap() { return 4; }

gf_autoLargeFromCounts( alliesCount, axisCount )
{
    larger = alliesCount;
    if ( axisCount > larger )
        larger = axisCount;
    return ( larger > gf_hudSkullCap() );
}

gf_playerSpawnedCB()
{
    level notify( "spawned_player" );

    self.enableText = false;

    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self thread gf_parkStockScorePopup();

    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        && !isDefined( self.pers["gf_welcomed"] )
        && ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold ) )
    {
        self.pers["gf_welcomed"] = true;
        self thread gf_welcomeMessage();
    }

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

    self.pers["gf_spawnedRound"] = game["roundsplayed"];

    if ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold )
    {
        if ( !isDefined( level.gf_healthHudStartRound ) || level.gf_healthHudStartRound != game["roundsplayed"] )
        {
            level.gf_healthHudStartRound = game["roundsplayed"];
            level thread gf_startHealthHUD();
        }
        gf_queueHealthHUDUpdate();
    }
    if ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        self gf_applyVisTweaks();
    self thread gf_onSpawned();

    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        && ( !isDefined( level.gf_inLobbyHold ) || !level.gf_inLobbyHold )
        && getDvarInt( "gf_diag_cd_no_health_hud" ) != 1 )
        self thread gf_runHealthHUD();

}

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

gf_onSpawnSpectator( origin, angles )
{
    maps\mp\gametypes\_globallogic_defaults::default_onSpawnSpectator( origin, angles );

    if ( isDefined( level.gf_inLobbyHold ) && level.gf_inLobbyHold
        && !( self istestclient() ) && !( self isdemoclient() ) )
    {
        self gf_hideLobbyHUD();
        return;
    }

    gf_queueHealthHUDUpdate();

    if ( ( !isDefined( self.pers["isBot"] ) || !self.pers["isBot"] )
        && getDvarInt( "gf_diag_cd_no_health_hud" ) != 1 )
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

gf_tryActivateRound()
{
    if ( level.gf_activatingRound )
        return;

    level.gf_activatingRound = true;
    level endon( "game_ended" );
    level endon( "gf_load_gate_reset" );

    wait 0.2;

    if ( level.gf_roundActive )
    {
        level.gf_activatingRound = false;
        return;
    }

    level.gf_roundEnding     = false;
    level.gf_roundActive     = true;
    level.gf_activatingRound = false;
    level.gf_warnedLastPlayer = [];
    gf_forceHealthHUDUpdate();

    if ( isDefined( level.inPrematchPeriod ) && level.inPrematchPeriod )
        level waittill( "prematch_over" );

    maps\mp\gametypes\_globallogic_utils::pauseTimer();
    level.grenadeLauncherDudTime = -1;
    level.thrownGrenadeDudTime   = -1;

    graceFloor = gettime() + 3000;

    level thread gf_closeGraceEarly( graceFloor );

    gf_updateAutoTeamMode();

    gf_startRoundClock();
}

gf_closeGraceEarly( floorTime )
{
    level endon( "game_ended" );

    while ( gettime() < floorTime )
        wait 0.1;

    loadGrace = gf_cfgFloat( "scr_gf_load_grace", 20, 0, 60 );
    if ( loadGrace > 0 )
    {
        graceCeiling = ( floorTime - 3000 ) + int( loadGrace * 1000 );
        while ( gf_anyTrackedClientLoading() && gettime() < graceCeiling )
            wait 0.2;
    }

    level.inGracePeriod = false;
    level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
}

gf_startRoundClock()
{
    roundLen = 0.75;
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

    level.grenadeLauncherDudTime = -1;
    level.thrownGrenadeDudTime   = -1;

    level thread gf_roundClock();
}

gf_roundClock()
{
    level endon( "game_ended" );
    level endon( "gf_round_over" );

    while ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        gf_syncRoundRemaining();

        if ( level.gf_roundRemaining <= 0 )
        {
            level.gf_roundClockRunning = false;
            gf_cleanupRoundTimerState();
            gf_onTimeLimit();
            return;
        }

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

    if ( remaining <= 15000 && ( !isDefined( level.gf_roundWarned ) || !level.gf_roundWarned ) )
    {
        level.gf_roundWarned = true;
        maps\mp\gametypes\_globallogic_audio::leaderDialog( "timesup" );
    }

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

gf_pauseMatch()
{
    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
        gf_pauseOvertimeForCapture();
    else if ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        if ( !isDefined( level.gf_roundPaused ) || !level.gf_roundPaused )
        {
            gf_syncRoundRemaining();
            level.gf_roundPaused = true;
            setGameEndTime( 0 );
        }
    }

    setDvar( "bots_play_move", 0 );

    players = level.players;
    for ( i = 0; i < players.size; i++ )
        players[i] freezeControls( true );
}

gf_resumeMatch()
{
    if ( isDefined( level.gf_overtimeActive ) && level.gf_overtimeActive )
        gf_resumeOvertimeForCapture();
    else if ( isDefined( level.gf_roundClockRunning ) && level.gf_roundClockRunning )
    {
        if ( isDefined( level.gf_roundPaused ) && level.gf_roundPaused )
        {
            level.gf_roundLastTime = gettime();
            level.gf_roundPaused   = false;
            gf_updateRoundGameEndTime();
        }
    }

    setDvar( "bots_play_move", 1 );

    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        players[i] freezeControls( false );
        if ( isDefined( players[i].pers["isBot"] ) && players[i].pers["isBot"] )
            players[i] notify( "botStopMove" );
    }
}

gf_endRound( winner )
{
    if ( gf_resolveOvertime( winner ) )
        return;

    level.gf_roundEnding = true;
    level.gf_roundActive = false;
    level notify( "gf_round_over" );

    gf_cleanupRoundTimerState();

    gf_forceHealthHUDUpdate();

    if ( isDefined( winner ) && winner != "tie" )
        [[level._setTeamScore]]( winner, [[level._getTeamScore]]( winner ) + 1 );

    reasonText = "";
    if ( isDefined( level.gf_endReasonText ) )
        reasonText = level.gf_endReasonText;
    level.gf_endReasonText = undefined;

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

    if ( !isDefined( level.numGametypeReservedObjectives ) )
        level.numGametypeReservedObjectives = 0;
    if ( !isDefined( level.releasedObjectives ) )
        level.releasedObjectives = [];

    zone = gf_createOvertimeZone();

    level thread gf_overtimeZoneGameEndCleanup( zone );

    if ( isDefined( zone ) )
        level thread gf_botOvertimeAI( zone );

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

    maps\mp\gametypes\_globallogic_audio::leaderDialog( "overtime" );
    maps\mp\gametypes\_globallogic_audio::leaderDialog( "gf_overtime_cue" );

    titleText = &"MP_OVERTIME_CAPS";
    if ( isDefined( game["strings"] ) && isDefined( game["strings"]["overtime"] ) )
        titleText = game["strings"]["overtime"];

    overtimeMsgDuration = 5.0;

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        player thread maps\mp\gametypes\_hud_message::oldNotifyMessage( titleText, undefined, undefined, ( 1, 0, 0 ), undefined, overtimeMsgDuration );
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
    if ( remaining <= 0 || remaining > 10000 )
        return;

    if ( remaining > 5000 )  interval = 1000;
    else                     interval = 500;

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
    setGameEndTime( 0 );
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

    if ( isDefined( zone.baseFxPos ) )
    {
        if ( isDefined( zone.baseFxHandle ) )
        {
            zone.baseFxHandle delete();
            zone.baseFxHandle = undefined;
        }

        fxAsset = level.gf_ot_baseFx_neutral;
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

    if ( team == "allies" || team == "axis" )
    {
        zone maps\mp\gametypes\_gameobjects::setOwnerTeam( team );
        gf_setOvertimeZoneIcons( zone, "defend", "capture" );
    }
    else
    {
        zone maps\mp\gametypes\_gameobjects::setOwnerTeam( "neutral" );
        gf_setOvertimeZoneIcons( zone, "captureneutral", "captureneutral" );
    }
}

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

    zone maps\mp\gametypes\_gameobjects::setOwnerTeam( "neutral" );
    zone maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );

    if ( isDefined( zone.objIDAllies ) )
        objective_delete( zone.objIDAllies );
    if ( isDefined( zone.objIDAxis ) )
        objective_delete( zone.objIDAxis );

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

gf_loadOvertimeApronFx()
{
    whiteFx = loadfx( "misc/fx_ui_flagbase_gf_white" );
    goldFx  = loadfx( "env/light/fx_ray_grnd_loc_marker_ylw_mp" );
    redFx   = loadfx( "env/light/fx_ray_grnd_loc_marker_red_mp" );

    level.gf_ot_baseFx_neutral   = whiteFx;
    level.gf_ot_baseFx_allies    = goldFx;
    level.gf_ot_baseFx_axis      = goldFx;
    level.gf_ot_baseFx_contested = redFx;
}

gf_createOvertimeZone()
{
    flagTrigger = gf_getOvertimeFlagTrigger();
    if ( !isDefined( flagTrigger ) )
        return undefined;

    gf_loadOvertimeApronFx();

    traceStart = flagTrigger.origin + ( 0, 0, 32 );
    traceEnd   = flagTrigger.origin + ( 0, 0, -256 );
    trace      = bulletTrace( traceStart, traceEnd, false, undefined );
    upAngles   = vectorToAngles( trace["normal"] );
    fxFwd      = anglesToForward( upAngles );
    fxRight    = anglesToRight( upAngles );
    fxPos      = trace["position"] + ( 0, 0, 1 );

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
    zone.gf_flagTrigger = flagTrigger;
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

    radius = 32;

    self.bot_lock_goal = true;
    self gf_botSetGoal( flagTrigger.origin, radius );

    for ( ;; )
    {
        wait 1;

        if ( !isDefined( flagTrigger ) )
            break;

        if ( !self isTouching( flagTrigger ) )
            self gf_botSetGoal( flagTrigger.origin, radius );
    }
}

gf_botSetGoal( origin, radius )
{
    self SetScriptGoal( origin, radius );
    waittillframeend;
    self notify( "new_goal" );
}

gf_onRoundEndGame()
{
    if ( game["roundswon"]["allies"] == game["roundswon"]["axis"] )
        return "tie";
    else if ( game["roundswon"]["axis"] > game["roundswon"]["allies"] )
        return "axis";
    return "allies";
}

gf_onPlayerKilled( eInflictor, attacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration )
{
    victimKey = "v" + int( self.entnum );

    cap = 100;
    if ( isDefined( self.maxhealth ) && self.maxhealth > 0 )
        cap = self.maxhealth;

    if ( isDefined( self.gf_assisters ) )
    {
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

            if ( !isDefined( damager.pers["isBot"] ) || !damager.pers["isBot"] )
            {
                if ( isDefined( attacker ) && damager == attacker )
                    damager thread gf_showScorePopup( 2, 2 );
                else
                    damager thread gf_showScorePopup( 1, 1 );
            }
        }

        for ( i = 0; i < self.gf_assisters.size; i++ )
        {
            damager = self.gf_assisters[i];
            if ( !isDefined( damager ) || !isPlayer( damager ) ) continue;

            damager gf_syncDamageScore();

            if ( !isDefined( attacker ) || damager != attacker )
                maps\mp\gametypes\_globallogic_score::givePlayerScore( "assist", damager );
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

        victimKey = "v" + int( self.entnum );
        if ( !isDefined( eAttacker.gf_dmgOnTarget ) )
            eAttacker.gf_dmgOnTarget = [];
        if ( !isDefined( eAttacker.gf_dmgOnTarget[victimKey] ) )
            eAttacker.gf_dmgOnTarget[victimKey] = 0;
        eAttacker.gf_dmgOnTarget[victimKey] += damage;

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

gf_reasonText( reason, winner )
{
    isTie = ( !isDefined( winner ) || winner == "tie" );

    if ( reason == "capture" )
        return "Objective captured";

    if ( reason == "elim" )
    {
        if ( isTie )
            return "Both teams eliminated";
        return "Team eliminated";
    }

    if ( isTie )
        return "Time expired - equal health";
    return "Time expired - health advantage";
}
