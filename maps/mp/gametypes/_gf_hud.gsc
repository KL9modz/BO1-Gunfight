// Gunfight HUD
// Health HUD uses newTeamHudElem (server-side) — one element pair per team covers
// the full lobby without consuming per-player client HUD pool slots.
// Loadout HUD uses newClientHudElem (client-side) — per-player, self thread only.
//
// HOW TO REVERT HEALTH HUD TO CLIENT-SIDE
// ----------------------------------------
//   - Delete gf_createHealthHUDSet, gf_sv_createTeamAliveRow, gf_sv_createIcon,
//     gf_sv_createText, gf_sv_createBar, gf_sv_offsetElems, gf_sv_slideHealthHUDIn,
//     gf_sv_showHealthHUDMenuNumbers, gf_healthHUDCatchupRefresh.
//   - Restore the old per-player helpers (gf_createHealthPanelBackground,
//     gf_createTeamAliveRow, gf_createHealthIconAt, gf_createHealthIcon,
//     gf_createHealthText, gf_createHealthBarAt, gf_registerHealthElem,
//     gf_offsetHealthHUDElems, gf_slideHealthHUDIn, gf_showHealthHUDMenuNumbers,
//     gf_hideHealthHUDMenuNumbers).
//   - In gf_startHealthHUD: restore self notify/endon, self.gf_healthHudElems/Rows,
//     self gf_createHealthPanelBackground(), etc.
//   - In gf_updateHealthHUD: restore self.gf_healthHudRows + self.pers["team"] check.
//   - In gf_destroyHealthHUD: restore self.gf_healthHudElems loop + self.gf_healthHudRows loop.
//   - In _gf_rounds.gsc: restore per-player calls with bot guard:
//       if (!isDefined(self.pers["isBot"]) || !self.pers["isBot"]) self thread gf_startHealthHUD();
//     and restore the gf_startHealthHUD call in gf_onSpawnSpectator.
// HOW TO REVERT LOADOUT HUD TO SERVER-SIDE
// -----------------------------------------
//   - In gf_showWeaponHUD: change self notify/endon to level notify/endon,
//     self.gf_loadoutHudElems to level.gf_loadoutHudElems, createIcon/
//     createFontString to createServerIcon/createServerFontString(shader,w,h,team).
//     Wrap element creation in for(t=0;t<2;t++) teams loop; index as [t*9+i].
//   - In gf_destroyLoadoutHUD: change self.gf_loadoutHudElems to level.gf_loadoutHudElems.
//   - In _gf_loadouts.gsc: change self thread to level thread for gf_showWeaponHUD.

#include maps\mp\gametypes\_hud_util;

// ─── Health HUD ──────────────────────────────────────────────────────────────

gf_startHealthHUD()
{
    level notify( "gf_restart_health_hud" );
    gf_destroyHealthHUD();
    level endon( "gf_restart_health_hud" );
    level endon( "game_ended" );

    wait 0.75;

    level.gf_hudCreatedRound = game["roundsplayed"];
    level.gf_healthHud = [];
    level.gf_healthHud["allies"] = gf_createHealthHUDSet( "allies" );
    level.gf_healthHud["axis"]   = gf_createHealthHUDSet( "axis" );

    gf_sv_slideHealthHUDIn();
    wait 0.75;
    gf_updateHealthHUD();
    level thread gf_healthHUDCatchupRefresh();
    level thread gf_healthHUDRoundCleanup();
    level thread gf_periodicHealthHUDUpdate();

    while ( true )
    {
        level waittill( "gf_health_hud_update" );
        gf_updateHealthHUD();
    }
}

gf_healthHUDRoundCleanup()
{
    level endon( "gf_restart_health_hud" );
    level waittill( "game_ended" );
    gf_destroyHealthHUD();
}

gf_periodicHealthHUDUpdate()
{
    level endon( "gf_restart_health_hud" );
    level endon( "game_ended" );
    while ( true )
    {
        wait 1.0;
        gf_updateHealthHUD();
    }
}

gf_healthHUDCatchupRefresh()
{
    level endon( "gf_restart_health_hud" );
    level endon( "game_ended" );
    i = 0;
    while ( i < 6 )
    {
        wait 0.5;
        level notify( "gf_health_hud_update" );
        i++;
    }
}

gf_createHealthHUDSet( viewerTeam )
{
    set = spawnstruct();
    set.team = viewerTeam;
    set.elems = [];
    set.slideOffset = -230;

    bg = gf_sv_createIcon( viewerTeam, set.elems, -70, -39, 180, 42, "hud_frame_faction_fade", ( 1, 1, 1 ), 37 );
    bg.alpha = 0;
    bg fadeOverTime( 0.25 );
    bg.alpha = 0.34;

    lines = gf_sv_createIcon( viewerTeam, set.elems, -162, -45, 250, 52, "hud_frame_faction_lines", ( 1, 1, 1 ), 38 );
    lines.alpha = 0;
    lines fadeOverTime( 0.25 );
    lines.alpha = 0.30;

    set.rows = [];
    set.rows[0] = gf_sv_createTeamAliveRow( viewerTeam, set.elems, -45, 10 );
    set.rows[1] = gf_sv_createTeamAliveRow( viewerTeam, set.elems, -27, 10 );

    gf_sv_offsetElems( set.elems, set.slideOffset, 0 );
    return set;
}

gf_sv_createTeamAliveRow( team, elems, y, height )
{
    row = spawnstruct();
    row.x = -12;
    row.y = y;
    row.height = height;
    row.width = 88;
    row.fill = gf_sv_createBar( team, elems, "CENTER LEFT", "CENTER LEFT", row.x, y, row.width, height, ( 1, 1, 1 ), 40, "hud_score_progress", 0, 0, 0.80 );

    row.icons = [];
    for ( i = 0; i < 3; i++ )
    {
        row.icons[i] = gf_sv_createIcon( team, elems, 4 + i * 9, y, 7, 7, "hud_death_suicide", ( 1, 1, 1 ), 45 );
        row.icons[i].alpha = 0;
    }

    row.hpText = gf_sv_createText( team, elems, -12, y, 46 );
    return row;
}

gf_sv_createIcon( team, elems, x, y, w, h, shader, color, sort )
{
    elem = createServerIcon( shader, w, h, team );
    elem setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    elem.color = color;
    gf_styleHealthElem( elem, sort );
    elems[elems.size] = elem;
    if ( !isDefined( level.gf_sv_elem_count ) ) level.gf_sv_elem_count = 0;
    level.gf_sv_elem_count++;
    return elem;
}

gf_sv_createText( team, elems, x, y, sort )
{
    elem = createServerFontString( "default", 1.4, team );
    elem setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    gf_styleHealthElem( elem, sort );
    elem.alpha = 0;
    elems[elems.size] = elem;
    if ( !isDefined( level.gf_sv_elem_count ) ) level.gf_sv_elem_count = 0;
    level.gf_sv_elem_count++;
    return elem;
}

gf_sv_createBar( team, elems, point, relPoint, x, y, w, h, color, sort, fillShader, bgAlpha, frameAlpha, fillAlpha )
{
    if ( !isDefined( fillShader ) )
        fillShader = "progress_bar_fill";
    if ( !isDefined( bgAlpha ) )
        bgAlpha = 0.45;
    if ( !isDefined( frameAlpha ) )
        frameAlpha = 0.85;
    if ( !isDefined( fillAlpha ) )
        fillAlpha = 1;

    bar = createServerBar( color, w, h, undefined, team );
    bar setPoint( point, relPoint, x, y );
    bar.bar.shader = fillShader;
    bar.bar setShader( fillShader, w, h );
    bar.barFrame setShader( "progress_bar_fg", w, h );
    bar.gf_bgAlpha = bgAlpha;
    bar.gf_frameAlpha = frameAlpha;
    bar.gf_fillAlpha = fillAlpha;

    gf_styleHealthElem( bar, sort );
    gf_styleHealthElem( bar.bar, sort + 1 );
    gf_styleHealthElem( bar.barFrame, sort + 2 );
    elems[elems.size] = bar;
    gf_setHealthBarFraction( bar, 0, false );
    if ( !isDefined( level.gf_sv_elem_count ) ) level.gf_sv_elem_count = 0;
    level.gf_sv_elem_count += 3;  // bg + fill + frame
    return bar;
}

gf_sv_offsetElems( elems, xOffset, moveTime )
{
    for ( i = 0; i < elems.size; i++ )
        gf_offsetHealthHUDElem( elems[i], xOffset, moveTime );
}

gf_sv_slideHealthHUDIn()
{
    teams = [];
    teams[0] = "allies";
    teams[1] = "axis";

    for ( t = 0; t < 2; t++ )
    {
        team = teams[t];
        if ( !isDefined( level.gf_healthHud ) || !isDefined( level.gf_healthHud[team] ) )
            continue;
        set = level.gf_healthHud[team];
        if ( set.slideOffset == 0 )
            continue;
        gf_sv_offsetElems( set.elems, 0 - set.slideOffset, 0.75 );
        set.slideOffset = 0;
    }
}

gf_styleHealthElem( elem, sort )
{
    if ( !isDefined( elem ) )
        return;

    elem.sort = sort;
    elem.foreground = true;
    elem.hidewheninmenu = true;
    elem.hidewheninkillcam = true;
    elem.hidewhileremotecontrolling = true;
    elem.archived = false;
}

gf_updateHealthHUD()
{
    if ( !isDefined( level.gf_healthHud ) )
        return;

    alliesStats = gf_getTeamHealthStats( "allies" );
    axisStats   = gf_getTeamHealthStats( "axis" );

    if ( !isDefined( level.gf_hudDbgCount ) ) level.gf_hudDbgCount = 0;
    level.gf_hudDbgCount++;
    if ( level.gf_hudDbgCount <= 12 || level.gf_hudDbgCount % 30 == 0 )
        logPrint( "GF_HUD update#" + level.gf_hudDbgCount + " allies=" + alliesStats.current + "/" + alliesStats.players.size + " axis=" + axisStats.current + "/" + axisStats.players.size + " totalPlayers=" + level.players.size + "\n" );

    if ( isDefined( level.gf_healthHud["allies"] ) )
    {
        set = level.gf_healthHud["allies"];
        gf_updateTeamAliveRow( set.rows[0], alliesStats, ( 0.42, 0.68, 0.46 ) );
        gf_updateTeamAliveRow( set.rows[1], axisStats,   ( 0.73, 0.29, 0.19 ) );
    }

    if ( isDefined( level.gf_healthHud["axis"] ) )
    {
        set = level.gf_healthHud["axis"];
        gf_updateTeamAliveRow( set.rows[0], axisStats,   ( 0.42, 0.68, 0.46 ) );
        gf_updateTeamAliveRow( set.rows[1], alliesStats, ( 0.73, 0.29, 0.19 ) );
    }
}

gf_updateTeamAliveRow( row, stats, color )
{
    if ( !isDefined( row ) )
        return;
    frac = gf_getTeamHealthBarFraction( stats.current, stats.max );
    if ( isDefined( row.fill ) && isDefined( row.fill.bar ) )
        row.fill.bar.color = color;
    gf_setHealthBarFraction( row.fill, frac, stats.current > 0 );

    visibleIcons = stats.players.size;
    if ( visibleIcons > 3 )
        visibleIcons = 3;

    aliveCount = 0;
    for ( i = 0; i < visibleIcons; i++ )
    {
        player = stats.players[i];
        if ( isDefined( player.sessionstate ) && player.sessionstate == "playing" && isDefined( player.health ) && player.health > 0 )
            aliveCount++;
    }

    for ( i = 0; i < 3; i++ )
    {
        if ( i >= visibleIcons )
        {
            row.icons[i].alpha = 0;
            continue;
        }

        row.icons[i].alpha = 0.95;

        if ( i < aliveCount )
            row.icons[i].color = color;
        else
            row.icons[i].color = ( 1, 1, 1 );
    }

    if ( isDefined( row.hpText ) )
    {
        if ( stats.current > 0 )
        {
            row.hpText setText( int( stats.current ) + "" );
            row.hpText.x = -12 + int( 88.0 * frac + 0.5 ) + 4;
            row.hpText.color = color;
            row.hpText.alpha = 0.9;
        }
        else
        {
            row.hpText.alpha = 0;
        }
    }
}

gf_getTeamHealthStats( team )
{
    stats = spawnstruct();
    stats.current = 0;
    stats.max = 0;
    stats.players = [];

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player ) )
            continue;

        if ( !isDefined( player.pers["team"] ) || player.pers["team"] != team )
            continue;

        stats.players[stats.players.size] = player;
        maxHP = player gf_getPlayerMaxHealth();
        stats.max += maxHP;

        if ( isDefined( player.health ) && player.health > 0 )
            stats.current += player.health;
    }

    return stats;
}

gf_getPlayerMaxHealth()
{
    if ( isDefined( self.maxhealth ) && self.maxhealth > 0 )
        return self.maxhealth;

    return 100;
}

gf_getHealthFraction( current, maxHealth )
{
    if ( maxHealth <= 0 )
        return 0;

    frac = current / maxHealth;
    if ( frac < 0 )
        return 0;
    if ( frac > 1 )
        return 1;

    return frac;
}

gf_getTeamHealthBarFraction( current, maxHealth )
{
    frac = gf_getHealthFraction( current, maxHealth );
    if ( frac <= 0 || frac >= 1 )
        return frac;

    frac = frac + ( ( 1 - frac ) * frac * 0.45 );
    if ( current > 0 && frac < 0.10 )
        return 0.10;

    return frac;
}

gf_setHealthBarFraction( bar, frac, visible )
{
    if ( !isDefined( bar ) )
        return;

    if ( frac < 0 )
        frac = 0;
    if ( frac > 1 )
        frac = 1;

    bar maps\mp\gametypes\_hud_util::updateBar( frac );

    if ( !visible )
    {
        bar maps\mp\gametypes\_hud_util::hideElem();
        return;
    }

    bar maps\mp\gametypes\_hud_util::showElem();

    bgAlpha = 0.45;
    if ( isDefined( bar.gf_bgAlpha ) )
        bgAlpha = bar.gf_bgAlpha;

    frameAlpha = 0.85;
    if ( isDefined( bar.gf_frameAlpha ) )
        frameAlpha = bar.gf_frameAlpha;

    fillAlpha = 1;
    if ( isDefined( bar.gf_fillAlpha ) )
        fillAlpha = bar.gf_fillAlpha;

    bar.alpha = bgAlpha;

    if ( isDefined( bar.bar ) )
    {
        if ( frac <= 0 )
            bar.bar.alpha = 0;
        else
            bar.bar.alpha = fillAlpha;
    }

    if ( isDefined( bar.barFrame ) )
        bar.barFrame.alpha = frameAlpha;
}

gf_offsetHealthHUDElem( elem, xOffset, moveTime )
{
    if ( !isDefined( elem ) )
        return;

    if ( isDefined( moveTime ) && moveTime > 0 )
        elem moveOverTime( moveTime );
    elem.x += xOffset;

    if ( isDefined( elem.elemType ) && elem.elemType == "bar" )
    {
        if ( isDefined( elem.bar ) )
        {
            if ( isDefined( moveTime ) && moveTime > 0 )
                elem.bar moveOverTime( moveTime );
            elem.bar.x += xOffset;
        }

        if ( isDefined( elem.barFrame ) )
        {
            if ( isDefined( moveTime ) && moveTime > 0 )
                elem.barFrame moveOverTime( moveTime );
            elem.barFrame.x += xOffset;
        }
    }
}

gf_refreshHealthHUD()
{
    wait 0.05;
    if ( !isDefined( level.gf_healthHud ) )
        return;
    gf_updateHealthHUD();
}

gf_destroyHealthHUD()
{
    if ( !isDefined( level.gf_healthHud ) )
        return;

    teams = [];
    teams[0] = "allies";
    teams[1] = "axis";

    for ( t = 0; t < 2; t++ )
    {
        team = teams[t];
        if ( !isDefined( level.gf_healthHud[team] ) )
            continue;
        set = level.gf_healthHud[team];
        if ( !isDefined( set.elems ) )
            continue;
        for ( i = 0; i < set.elems.size; i++ )
        {
            elem = set.elems[i];
            if ( !isDefined( elem ) )
                continue;
            if ( isDefined( elem.elemType ) && elem.elemType == "bar" )
            {
                if ( isDefined( elem.bar ) )
                    elem.bar destroyElem();
                if ( isDefined( elem.barFrame ) )
                    elem.barFrame destroyElem();
            }
            elem destroyElem();
        }
    }

    level.gf_healthHud = undefined;
    level.gf_sv_elem_count = 0;
}

// ─── Loadout HUD ─────────────────────────────────────────────────────────────

gf_showWeaponHUD( load )
{
    if ( !isDefined( load ) )
        return;

    self notify( "gf_kill_loadout_hud" );
    gf_destroyLoadoutHUD();
    self endon( "gf_kill_loadout_hud" );
    level endon( "game_ended" );

    self.gf_loadoutHudElems = [];

    shaders = [];
    shaders[0] = load["primaryShader"];
    shaders[1] = load["secondaryShader"];
    shaders[2] = load["lethalShader"];
    shaders[3] = load["tacticalShader"];
    shaders[4] = load["equipShader"];
    shaders[5] = gf_getPerkShader( "specialty_movefaster" );
    shaders[6] = gf_getPerkShader( "specialty_bulletpenetration" );
    shaders[7] = gf_getPerkShader( "specialty_longersprint" );
    shaders[8] = gf_getPerkShader( "specialty_flakjacket" );

    names = [];
    names[0] = load["primaryName"];
    names[1] = load["secondaryName"];
    names[2] = load["lethalName"];
    names[3] = load["tacticalName"];
    names[4] = load["equipName"];
    names[5] = "Lightweight";
    names[6] = "Hardened";
    names[7] = "Marathon";
    names[8] = "Flak Jacket";

    // yPos: row position in user_bottom coords.
    // Weapon icon rendered_y = yPos - 58; perk text yText = yIcon - 16.
    yPos = [];
    yPos[0] = -262;
    yPos[1] = -222;
    yPos[2] = -182;
    yPos[3] = -142;
    yPos[4] = -102;
    yPos[5] = -242;
    yPos[6] = -202;
    yPos[7] = -162;
    yPos[8] = -122;

    icons = [];
    texts = [];

    // Weapon rows — right side (slots 0-4)
    for ( i = 0; i < 5; i++ )
    {
        yRendered = yPos[i] - 58;

        icon = createIcon( shaders[i], 32, 32 );
        icon.horzAlign = "user_right";
        icon.vertAlign = "user_bottom";
        icon.alignX    = "right";
        icon.alignY    = "middle";
        icon.x         = 400;
        icon.y         = yRendered;
        icon.archived  = false;
        icon.foreground = true;
        icon.hidewheninmenu = true;
        icon.hidewheninkillcam = true;
        icon.hidewhileremotecontrolling = true;

        if ( i < 2 )
            icon setShader( shaders[i], 64, 32 );

        text = createFontString( "default", 1.4 );
        text.horzAlign = "user_right";
        text.vertAlign = "user_bottom";
        text.alignX    = "right";
        text.alignY    = "middle";
        text.x         = 400;
        text.y         = yRendered;
        text.archived  = false;
        text.foreground = true;
        text.hidewheninmenu = true;
        text.hidewheninkillcam = true;
        text.hidewhileremotecontrolling = true;
        text setText( names[i] );
        text.alpha = 1;

        icon moveOverTime( 0.75 );
        icon.x = -5;
        text moveOverTime( 0.75 );
        text.x = -72;

        icons[i] = icon;
        texts[i] = text;
        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = icon;
        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = text;
    }

    // Perk rows — left side (slots 5-8)
    for ( i = 5; i < 9; i++ )
    {
        yIcon = yPos[i] - 58;
        yText = yIcon - 16;

        icon = createIcon( shaders[i], 32, 32 );
        icon.horzAlign = "user_left";
        icon.vertAlign = "user_bottom";
        icon.alignX    = "left";
        icon.alignY    = "bottom";
        icon.x         = -200;
        icon.y         = yIcon;
        icon.archived  = false;
        icon.foreground = true;
        icon.hidewheninmenu = true;
        icon.hidewheninkillcam = true;
        icon.hidewhileremotecontrolling = true;

        text = createFontString( "default", 1.4 );
        text.horzAlign = "user_left";
        text.vertAlign = "user_bottom";
        text.alignX    = "left";
        text.alignY    = "middle";
        text.x         = -200;
        text.y         = yText;
        text.archived  = false;
        text.foreground = true;
        text.hidewheninmenu = true;
        text.hidewheninkillcam = true;
        text.hidewhileremotecontrolling = true;
        text setText( names[i] );
        text.alpha = 1;

        icon moveOverTime( 0.75 );
        icon.x = 5;
        text moveOverTime( 0.75 );
        text.x = 42;

        icons[i] = icon;
        texts[i] = text;
        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = icon;
        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = text;
    }

    wait 5;

    for ( i = 0; i < 5; i++ )
    {
        icons[i] moveOverTime( 0.75 );
        icons[i].x = 400;
        texts[i] moveOverTime( 0.75 );
        texts[i].x = 400;
    }
    for ( i = 5; i < 9; i++ )
    {
        icons[i] moveOverTime( 0.75 );
        icons[i].x = -400;
        texts[i] moveOverTime( 0.75 );
        texts[i].x = -400;
    }

    wait 0.8;
    gf_destroyLoadoutHUD();
}

gf_getPerkShader( specialty )
{
    if ( isDefined( level.perkReferenceToIndex ) && isDefined( level.perkReferenceToIndex[specialty] ) )
    {
        idx = level.perkReferenceToIndex[specialty];
        if ( isDefined( level.tbl_PerkData[idx] ) )
            return level.tbl_PerkData[idx]["reference_full"];
    }
    return "white";
}

gf_destroyLoadoutHUD()
{
    if ( !isDefined( self.gf_loadoutHudElems ) )
        return;

    for ( i = 0; i < self.gf_loadoutHudElems.size; i++ )
    {
        if ( isDefined( self.gf_loadoutHudElems[i] ) )
            self.gf_loadoutHudElems[i] destroyElem();
    }

    self.gf_loadoutHudElems = undefined;
}
