// Gunfight HUD
// Health panels are event-driven: damage, death, spawn, spectator changes,
// round end, and disconnects notify waiting clients instead of polling.

#include maps\mp\gametypes\_hud_util;

gf_startHealthHUD()
{
    self notify( "gf_restart_health_hud" );
    self gf_destroyHealthHUD();
    self endon( "gf_restart_health_hud" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    // Delay creation until the temporary loadout HUD has slid away.
    wait 0.05;

    if ( isDefined( self.sessionstate ) && self.sessionstate == "playing" )
        wait 5.85;
    else
        wait 0.2;

    self.gf_healthHudElems = [];
    self.gf_healthHudPanelBg = self gf_createHealthPanelBackground();
    self.gf_healthHudRows = [];
    self.gf_healthHudRows[0] = self gf_createTeamAliveRow( -45, 10 );
    self.gf_healthHudRows[1] = self gf_createTeamAliveRow( -27, 10 );
    self.gf_healthHudSlideOffset = -230;
    self gf_offsetHealthHUDElems( self.gf_healthHudSlideOffset, 0 );

    self gf_updateHealthHUD();
    self gf_slideHealthHUDIn();
    wait 0.75;
    self gf_showHealthHUDMenuNumbers();

    while ( true )
    {
        level waittill( "gf_health_hud_update" );
        self gf_updateHealthHUD();
    }
}

gf_createHealthPanelBackground()
{
    panel = spawnstruct();
    panel.bg = self gf_createHealthIcon( -70, -39, 180, 42, "hud_frame_faction_fade", ( 1, 1, 1 ), 37 );
    panel.bg.alpha = 0;
    panel.bg fadeOverTime( 0.25 );
    panel.bg.alpha = 0.34;

    panel.lines = self gf_createHealthIcon( -162, -45, 250, 52, "hud_frame_faction_lines", ( 1, 1, 1 ), 38 );
    panel.lines.alpha = 0;
    panel.lines fadeOverTime( 0.25 );
    panel.lines.alpha = 0.30;
    return panel;
}

gf_createTeamAliveRow( y, height )
{
    row = spawnstruct();
    row.x = -12;
    row.y = y;
    row.height = height;
    row.width = 88;
    row.fill = self gf_createHealthBarAt( "CENTER LEFT", "CENTER LEFT", row.x, y, row.width, height, ( 1, 1, 1 ), 40, "hud_score_progress", 0, 0, 0.80 );

    row.icons = [];
    for ( i = 0; i < 3; i++ )
    {
        row.icons[i] = self gf_createHealthIcon( 4 + i * 9, y, 7, 7, "hud_death_suicide", ( 1, 1, 1 ), 42 );
        row.icons[i].alpha = 0;
    }

    return row;
}

gf_offsetHealthHUDElems( xOffset, moveTime )
{
    if ( !isDefined( self.gf_healthHudElems ) )
        return;

    for ( i = 0; i < self.gf_healthHudElems.size; i++ )
        gf_offsetHealthHUDElem( self.gf_healthHudElems[i], xOffset, moveTime );
}

gf_slideHealthHUDIn()
{
    if ( !isDefined( self.gf_healthHudSlideOffset ) )
        return;

    self gf_offsetHealthHUDElems( 0 - self.gf_healthHudSlideOffset, 0.75 );
    self.gf_healthHudSlideOffset = 0;
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

gf_createHealthIcon( x, y, width, height, shader, color, sort )
{
    return self gf_createHealthIconAt( "CENTER LEFT", "CENTER LEFT", x, y, width, height, shader, color, sort );
}

gf_createHealthIconAt( point, relativePoint, x, y, width, height, shader, color, sort )
{
    elem = self maps\mp\gametypes\_hud_util::createIcon( shader, width, height );
    elem setPoint( point, relativePoint, x, y );
    elem.color = color;
    gf_styleHealthElem( elem, sort );
    self gf_registerHealthElem( elem );
    return elem;
}

gf_createHealthBarAt( point, relativePoint, x, y, width, height, color, sort, fillShader, bgAlpha, frameAlpha, fillAlpha )
{
    if ( !isDefined( fillShader ) )
        fillShader = "progress_bar_fill";
    if ( !isDefined( bgAlpha ) )
        bgAlpha = 0.45;
    if ( !isDefined( frameAlpha ) )
        frameAlpha = 0.85;
    if ( !isDefined( fillAlpha ) )
        fillAlpha = 1;

    bar = self maps\mp\gametypes\_hud_util::createBar( color, width, height );
    bar setPoint( point, relativePoint, x, y );
    bar.bar.shader = fillShader;
    bar.bar setShader( fillShader, width, height );
    bar.barFrame setShader( "progress_bar_fg", width, height );
    bar.gf_bgAlpha = bgAlpha;
    bar.gf_frameAlpha = frameAlpha;
    bar.gf_fillAlpha = fillAlpha;

    gf_styleHealthElem( bar, sort );
    gf_styleHealthElem( bar.bar, sort + 1 );
    gf_styleHealthElem( bar.barFrame, sort + 2 );
    self gf_registerHealthElem( bar );
    self gf_setHealthBarFraction( bar, 0, false );
    return bar;
}

gf_registerHealthElem( elem )
{
    self.gf_healthHudElems[self.gf_healthHudElems.size] = elem;
    return elem;
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
    if ( !isDefined( self.gf_healthHudRows ) )
        return;

    firstTeam = "allies";
    secondTeam = "axis";

    if ( isDefined( self.pers["team"] ) && self.pers["team"] == "axis" )
    {
        firstTeam = "axis";
        secondTeam = "allies";
    }

    self gf_updateTeamAliveRow( self.gf_healthHudRows[0], firstTeam, ( 0.42, 0.68, 0.46 ), 0 );
    self gf_updateTeamAliveRow( self.gf_healthHudRows[1], secondTeam, ( 0.73, 0.29, 0.19 ), 1 );
}

gf_updateTeamAliveRow( row, team, color, rowIndex )
{
    if ( !isDefined( row ) )
        return;

    stats = gf_getTeamHealthStats( team );
    frac = gf_getTeamHealthBarFraction( stats.current, stats.max );
    if ( isDefined( row.fill ) && isDefined( row.fill.bar ) )
        row.fill.bar.color = color;
    self gf_setHealthBarFraction( row.fill, frac, stats.current > 0 );

    self gf_updateHealthHUDMenuNumber( row, rowIndex, stats, frac );

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
}

gf_updateHealthHUDMenuNumber( row, rowIndex, stats, frac )
{
    prefix = "ui_gf_health_hp" + rowIndex;
    self setClientDvar( prefix, int( stats.current ) + "" );
    self setClientDvar( prefix + "_x", row.x + int( row.width * frac + 0.5 ) + 4 );

    if ( stats.max > 0 )
        self setClientDvar( prefix + "_show", "1" );
    else
        self setClientDvar( prefix + "_show", "0" );
}

gf_showHealthHUDMenuNumbers()
{
    self setClientDvar( "ui_gf_health_hp_visible", "1" );
}

gf_hideHealthHUDMenuNumbers()
{
    self setClientDvar( "ui_gf_health_hp_visible", "0" );
    self setClientDvar( "ui_gf_health_hp0_show", "0" );
    self setClientDvar( "ui_gf_health_hp1_show", "0" );
    self setClientDvar( "ui_gf_health_hp0", "" );
    self setClientDvar( "ui_gf_health_hp1", "" );
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
        if ( !isDefined( player ) || !isPlayer( player ) )
            continue;

        if ( !isDefined( player.pers["team"] ) || player.pers["team"] != team )
            continue;

        stats.players[stats.players.size] = player;
        maxHP = player gf_getPlayerMaxHealth();
        stats.max += maxHP;

        if ( player.sessionstate == "playing" && isDefined( player.health ) && player.health > 0 )
        {
            stats.current += player.health;
        }
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

gf_destroyHealthHUD()
{
    self gf_hideHealthHUDMenuNumbers();

    if ( !isDefined( self.gf_healthHudElems ) )
        return;

    for ( i = 0; i < self.gf_healthHudElems.size; i++ )
    {
        if ( isDefined( self.gf_healthHudElems[i] ) )
            self.gf_healthHudElems[i] destroyElem();
    }

    self.gf_healthHudElems = undefined;
    self.gf_healthHudPanelBg = undefined;
    self.gf_healthHudRows = undefined;
    self.gf_healthHudSlideOffset = undefined;
}

// ─── Self HP Bar ──────────────────────────────────────────────────────────

gf_startSelfHealthBar()
{
    self notify( "gf_restart_self_health" );
    self gf_destroySelfHealthBar();
    self endon( "gf_restart_self_health" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    wait 0.1;

    if ( !isDefined( self.sessionstate ) || self.sessionstate != "playing" )
        return;

    maxHP = self gf_getPlayerMaxHealth();

    self.gf_selfBar = self maps\mp\gametypes\_hud_util::createBar( ( 1, 1, 1 ), 160, 7 );
    self.gf_selfBar setPoint( "BOTTOM CENTER", "BOTTOM CENTER", 0, -20 );
    if ( isDefined( self.gf_selfBar.bar ) )
    {
        self.gf_selfBar.bar.shader = "hud_score_progress";
        self.gf_selfBar.bar setShader( "hud_score_progress", 160, 7 );
        self.gf_selfBar.bar.color = ( 1, 1, 1 );
    }
    self.gf_selfBar.sort                      = 50;
    self.gf_selfBar.foreground                = true;
    self.gf_selfBar.hidewheninmenu            = true;
    self.gf_selfBar.hidewheninkillcam         = true;
    self.gf_selfBar.hidewhileremotecontrolling = true;
    self.gf_selfBar.archived                  = false;

    if ( isDefined( self.gf_selfBar.bar ) )
    {
        self.gf_selfBar.bar.sort                      = 51;
        self.gf_selfBar.bar.foreground                = true;
        self.gf_selfBar.bar.hidewheninmenu            = true;
        self.gf_selfBar.bar.hidewheninkillcam         = true;
        self.gf_selfBar.bar.hidewhileremotecontrolling = true;
        self.gf_selfBar.bar.archived                  = false;
    }
    if ( isDefined( self.gf_selfBar.barFrame ) )
    {
        self.gf_selfBar.barFrame.sort                      = 52;
        self.gf_selfBar.barFrame.foreground                = true;
        self.gf_selfBar.barFrame.hidewheninmenu            = true;
        self.gf_selfBar.barFrame.hidewheninkillcam         = true;
        self.gf_selfBar.barFrame.hidewhileremotecontrolling = true;
        self.gf_selfBar.barFrame.archived                  = false;
    }

    while ( true )
    {
        if ( !isDefined( self.health ) || self.health <= 0 )
        {
            self gf_destroySelfHealthBar();
            return;
        }
        self gf_updateSelfHealthBar( maxHP );
        wait 0.05;
    }
}

gf_updateSelfHealthBar( maxHP )
{
    if ( !isDefined( self.gf_selfBar ) )
        return;

    frac = gf_getHealthFraction( self.health, maxHP );
    self.gf_selfBar maps\mp\gametypes\_hud_util::updateBar( frac );
}

gf_destroySelfHealthBar()
{
    if ( !isDefined( self.gf_selfBar ) )
        return;

    if ( isDefined( self.gf_selfBar.barFrame ) )
        self.gf_selfBar.barFrame destroy();
    if ( isDefined( self.gf_selfBar.bar ) )
        self.gf_selfBar.bar destroy();
    self.gf_selfBar destroy();
    self.gf_selfBar = undefined;
}

// ─── Loadout HUD ─────────────────────────────────────────────────────────────

gf_showWeaponHUD( load )
{
    if ( !isDefined( load ) )
        return;

    self notify( "gf_kill_loadout_hud" );
    self gf_destroyLoadoutHUD();
    self endon( "gf_kill_loadout_hud" );
    self endon( "disconnect" );
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

    names = [];
    names[0] = load["primaryName"];
    names[1] = load["secondaryName"];
    names[2] = load["lethalName"];
    names[3] = load["tacticalName"];
    names[4] = load["equipName"];
    names[5] = "Lightweight";
    names[6] = "Hardened";
    names[7] = "Marathon";

    // createLoadoutIcon uses setPoint("BOTTOM RIGHT","BOTTOM RIGHT") so y is pixels
    // upward from the screen bottom. We clamp verIndex to 4 (designed max) for all
    // rows and control vertical position entirely through yPos.
    // Formula with verIndex=4: rendered_y = yPos - 58.
    // 8 rows × 40px spacing = 280px stack, centered at y=-220 → spans y=-360 to y=-80.
    yPos = [];
    yPos[0] = -342;   // y=-400  (top)
    yPos[1] = -302;   // y=-360
    yPos[2] = -262;   // y=-320
    yPos[3] = -222;   // y=-280
    yPos[4] = -182;   // y=-240
    yPos[5] = -142;   // y=-200
    yPos[6] = -102;   // y=-160
    yPos[7] = -62;    // y=-120  (bottom)

    icons = [];
    texts = [];

    for ( i = 0; i < 8; i++ )
    {
        icons[i] = self maps\mp\gametypes\_hud_util::createLoadoutIcon( 4, 0, 200, yPos[i] );
        texts[i] = self maps\mp\gametypes\_hud_util::createLoadoutText( icons[i], 160 );
        self maps\mp\gametypes\_hud_util::showLoadoutAttribute( icons[i], shaders[i], 1, texts[i], names[i] );

        if ( i < 2 )
            icons[i] setShader( shaders[i], 64, 32 );

        icons[i] moveOverTime( 0.75 );
        icons[i].x = -5;
        icons[i].hidewheninmenu = true;
        icons[i].hidewheninkillcam = true;
        icons[i].hidewhileremotecontrolling = true;

        texts[i] moveOverTime( 0.75 );
        texts[i].x = -72;
        texts[i].hidewheninmenu = true;
        texts[i].hidewheninkillcam = true;
        texts[i].hidewhileremotecontrolling = true;

        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = icons[i];
        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = texts[i];
    }

    wait 5;

    for ( i = 0; i < 8; i++ )
    {
        icons[i] moveOverTime( 0.75 );
        icons[i].x = 400;
        texts[i] moveOverTime( 0.75 );
        texts[i].x = 400;
    }

    wait 0.8;
    self gf_destroyLoadoutHUD();
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
            self.gf_loadoutHudElems[i] destroy();
    }

    self.gf_loadoutHudElems = undefined;
}
