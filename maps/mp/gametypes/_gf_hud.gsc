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

    // Stagger creation so all players' spawns finish before the HUD allocation spike
    wait 0.05;

    self.gf_healthHudElems = [];
    self.gf_healthHudPanelBg = self gf_createHealthPanelBackground();
    self.gf_healthHudRows = [];
    self.gf_healthHudRows[0] = self gf_createTeamAliveRow( -45, 13 );
    self.gf_healthHudRows[1] = self gf_createTeamAliveRow( -27, 10 );
    self.gf_selfHealthHud = self gf_createSelfHealthHud();

    self gf_updateHealthHUD();

    while ( true )
    {
        level waittill( "gf_health_hud_update" );
        self gf_updateHealthHUD();
    }
}

gf_createHealthPanelBackground()
{
    panel = spawnstruct();
    panel.bg = self gf_createHealthIcon( 0, -39, 82, 42, "hud_frame_faction_fade", ( 1, 1, 1 ), 37 );
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
    for ( i = 0; i < 4; i++ )
    {
        row.icons[i] = self gf_createHealthIcon( 4 + i * 9, y, 7, 7, "hud_death_suicide", ( 1, 1, 1 ), 42 );
        row.icons[i].alpha = 0;
    }

    return row;
}

gf_createSelfHealthHud()
{
    panel = spawnstruct();
    panel.name = self gf_createHealthTextAt( "BOTTOM RIGHT", "BOTTOM RIGHT", -34, -80, "default", 1.0, ( 1, 1, 1 ), 45 );
    panel.name.alignX = "right";
    panel.bar = self gf_createHealthBarAt( "BOTTOM LEFT", "BOTTOM RIGHT", -194, -64, 160, 8, ( 0.42, 0.68, 0.46 ), 43 );

    return panel;
}

gf_createHealthText( x, y, font, scale, color, sort )
{
    return self gf_createHealthTextAt( "CENTER LEFT", "CENTER LEFT", x, y, font, scale, color, sort );
}

gf_createHealthTextAt( point, relativePoint, x, y, font, scale, color, sort )
{
    elem = self maps\mp\gametypes\_hud_util::createFontString( font, scale );
    elem setPoint( point, relativePoint, x, y );
    elem.color = color;
    gf_styleHealthElem( elem, sort );
    self gf_registerHealthElem( elem );
    return elem;
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

gf_createHealthBar( x, y, width, height, color, sort )
{
    return self gf_createHealthBarAt( "CENTER LEFT", "CENTER LEFT", x, y, width, height, color, sort );
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
    if ( !isDefined( self.gf_healthHudRows ) || !isDefined( self.gf_selfHealthHud ) )
        return;

    firstTeam = "allies";
    secondTeam = "axis";

    if ( isDefined( self.pers["team"] ) && self.pers["team"] == "axis" )
    {
        firstTeam = "axis";
        secondTeam = "allies";
    }

    self gf_updateTeamAliveRow( self.gf_healthHudRows[0], firstTeam, ( 0.42, 0.68, 0.46 ), true );
    self gf_updateTeamAliveRow( self.gf_healthHudRows[1], secondTeam, ( 0.73, 0.29, 0.19 ), false );
    self gf_updateSelfHealthHUD();
}

gf_updateTeamAliveRow( row, team, color, friendly )
{
    if ( !isDefined( row ) )
        return;

    stats = gf_getTeamHealthStats( team );
    frac = gf_getHealthFraction( stats.current, stats.max );
    if ( isDefined( row.fill ) && isDefined( row.fill.bar ) )
        row.fill.bar.color = color;
    self gf_setHealthBarFraction( row.fill, frac, stats.current > 0 );

    visibleIcons = stats.players.size;
    if ( visibleIcons > 4 )
        visibleIcons = 4;

    for ( i = 0; i < 4; i++ )
    {
        if ( i >= visibleIcons )
        {
            row.icons[i].alpha = 0;
            continue;
        }

        player = stats.players[i];
        row.icons[i].alpha = 0.95;

        playerAlive = false;
        if ( isDefined( player.sessionstate ) && player.sessionstate == "playing" && isDefined( player.health ) && player.health > 0 )
        {
            playerAlive = true;
        }
        else
        {
            pregameActive = false;
            if ( isDefined( level.gf_preRoundCountdownActive ) && level.gf_preRoundCountdownActive )
                pregameActive = true;
            else if ( isDefined( level.gf_preMatchHealthHUDActive ) && level.gf_preMatchHealthHUDActive )
                pregameActive = true;

            if ( pregameActive )
                playerAlive = true;
        }

        if ( playerAlive )
            row.icons[i].color = color;
        else
            row.icons[i].color = ( 1, 1, 1 );
    }
}

gf_updateSelfHealthHUD()
{
    panel = self.gf_selfHealthHud;
    visible = isDefined( self.sessionstate ) && self.sessionstate == "playing";

    if ( !visible )
    {
        if ( isDefined( panel.name ) )
            panel.name.alpha = 0;
        self gf_setHealthBarFraction( panel.bar, 0, false );
        return;
    }

    maxHP = self gf_getPlayerMaxHealth();
    hp = 0;
    if ( isDefined( self.health ) && self.health > 0 )
        hp = self.health;

    panel.name setText( self.name );
    panel.name.alpha = 1;
    self gf_setHealthBarFraction( panel.bar, gf_getHealthFraction( hp, maxHP ), true );
}

gf_getTeamHealthStats( team )
{
    stats = spawnstruct();
    stats.current = 0;
    stats.max = 0;
    stats.alive = 0;
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
            stats.alive++;
        }
        else
        {
            pregameActive = false;
            if ( isDefined( level.gf_preRoundCountdownActive ) && level.gf_preRoundCountdownActive )
                pregameActive = true;
            else if ( isDefined( level.gf_preMatchHealthHUDActive ) && level.gf_preMatchHealthHUDActive )
                pregameActive = true;

            if ( pregameActive )
            {
                stats.current += maxHP;
                stats.alive++;
            }
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

gf_getHealthTeamName( team )
{
    if ( team == "allies" )
    {
        name = getDvar( "scr_allies" );
        if ( name != "" )
            return name;
        return "allies";
    }

    name = getDvar( "scr_axis" );
    if ( name != "" )
        return name;
    return "axis";
}

gf_getHealthTeamColor( team )
{
    if ( team == "allies" )
        return ( 0.4, 0.7, 1.0 );

    return ( 1.0, 0.45, 0.45 );
}

gf_destroyHealthHUD()
{
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
    self.gf_selfHealthHud = undefined;
}

gf_startHealthIconGalleryWatcher()
{
    self notify( "gf_restart_health_icon_gallery" );
    self gf_destroyHealthIconGallery();
    self endon( "gf_restart_health_icon_gallery" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    while ( true )
    {
        if ( getDvarInt( "gf_debug_health_icons" ) == 1 )
        {
            if ( !isDefined( self.gf_healthIconGalleryElems ) )
                self gf_createHealthIconGallery();
        }
        else
        {
            self gf_destroyHealthIconGallery();
        }

        wait 0.5;
    }
}

gf_createHealthIconGallery()
{
    self.gf_healthIconGalleryElems = [];

    bg = self gf_createHealthIconGalleryIcon( "hud_frame_black_back_fade", 0, 0, 520, 286, ( 0, 0, 0 ), 90 );
    bg.alpha = 0.72;

    frame = self gf_createHealthIconGalleryIcon( "hud_frame_faction_lines", 0, -116, 500, 50, ( 0.85, 0.85, 0.85 ), 91 );
    frame.alpha = 0.25;

    title = self gf_createHealthIconGalleryText( -232, -124, "default", 1.0, ( 1, 1, 1 ), 93 );
    title setText( "Icon candidates" );

    shaders = [];
    sizes = [];
    i = 0;

    shaders[i] = "headicon_dead"; sizes[i] = 18; i++;
    shaders[i] = "hud_death_suicide"; sizes[i] = 18; i++;
    shaders[i] = "waypoint_kill"; sizes[i] = 18; i++;
    shaders[i] = "waypoint_defend"; sizes[i] = 18; i++;
    shaders[i] = "waypoint_bomb"; sizes[i] = 18; i++;
    shaders[i] = "waypoint_target"; sizes[i] = 18; i++;
    shaders[i] = "waypoint_defuse"; sizes[i] = 18; i++;
    shaders[i] = "waypoint_bombsquad"; sizes[i] = 18; i++;
    shaders[i] = "waypoint_revive"; sizes[i] = 18; i++;
    shaders[i] = "objpoint_default"; sizes[i] = 18; i++;
    shaders[i] = "hud_suitcase_bomb"; sizes[i] = 18; i++;
    shaders[i] = "hud_scavenger_pickup"; sizes[i] = 24; i++;
    shaders[i] = "score_bar_allies"; sizes[i] = 18; i++;
    shaders[i] = "hud_icon_satchelcharge"; sizes[i] = 18; i++;
    shaders[i] = "hud_icon_sticky_grenade"; sizes[i] = 18; i++;
    shaders[i] = "hud_hatchet"; sizes[i] = 18; i++;
    shaders[i] = "menu_mp_weapons_crossbow"; sizes[i] = 28; i++;
    shaders[i] = "menu_mp_weapons_python"; sizes[i] = 28; i++;
    shaders[i] = "menu_mp_weapons_makarov"; sizes[i] = 28; i++;
    shaders[i] = "menu_mp_weapons_asp"; sizes[i] = 28; i++;
    shaders[i] = "hud_icon_bomb"; sizes[i] = 18; i++;
    shaders[i] = "hud_icon_bomb_defuse"; sizes[i] = 18; i++;
    shaders[i] = "white"; sizes[i] = 18; i++;

    for ( row = 0; row < shaders.size; row++ )
    {
        col = row % 4;
        slot = int( row / 4 );
        x = -198 + col * 132;
        y = -78 + slot * 38;
        size = sizes[row];

        num = self gf_createHealthIconGalleryNumber( x - 42, y - 2, row + 1 );
        self gf_createHealthIconGalleryIcon( shaders[row], x - 14, y, size, size, ( 0.4, 0.7, 1.0 ), 94 );
        self gf_createHealthIconGalleryIcon( shaders[row], x + 14, y, size, size, ( 1.0, 0.45, 0.45 ), 94 );
        self gf_createHealthIconGalleryIcon( shaders[row], x + 42, y, size, size, ( 1, 1, 1 ), 94 );
    }
}

gf_createHealthIconGalleryIcon( shader, x, y, width, height, color, sort )
{
    elem = self maps\mp\gametypes\_hud_util::createIcon( shader, width, height );
    elem setPoint( "CENTER", "CENTER", x, y );
    elem.color = color;
    gf_styleHealthElem( elem, sort );
    self gf_registerHealthIconGalleryElem( elem );
    return elem;
}

gf_createHealthIconGalleryText( x, y, font, scale, color, sort )
{
    elem = self maps\mp\gametypes\_hud_util::createFontString( font, scale );
    elem setPoint( "CENTER", "CENTER", x, y );
    elem.alignX = "left";
    elem.color = color;
    gf_styleHealthElem( elem, sort );
    self gf_registerHealthIconGalleryElem( elem );
    return elem;
}

gf_createHealthIconGalleryNumber( x, y, value )
{
    elem = self maps\mp\gametypes\_hud_util::createFontString( "default", 0.72 );
    elem setPoint( "CENTER", "CENTER", x, y );
    elem.color = ( 0.82, 0.82, 0.82 );
    gf_styleHealthElem( elem, 94 );
    elem setValue( value );
    self gf_registerHealthIconGalleryElem( elem );
    return elem;
}

gf_registerHealthIconGalleryElem( elem )
{
    self.gf_healthIconGalleryElems[self.gf_healthIconGalleryElems.size] = elem;
    return elem;
}

gf_destroyHealthIconGallery()
{
    if ( !isDefined( self.gf_healthIconGalleryElems ) )
        return;

    for ( i = 0; i < self.gf_healthIconGalleryElems.size; i++ )
    {
        if ( isDefined( self.gf_healthIconGalleryElems[i] ) )
            self.gf_healthIconGalleryElems[i] destroyElem();
    }

    self.gf_healthIconGalleryElems = undefined;
}

gf_showCustomPerks()
{
    self notify( "gf_kill_perk_hud" );
    self endon( "gf_kill_perk_hud" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    self maps\mp\gametypes\_hud_util::showPerk( 0, "specialty_movefaster", 10 );
    self maps\mp\gametypes\_hud_util::showPerk( 1, "specialty_bulletpenetration", 10 );
    self maps\mp\gametypes\_hud_util::showPerk( 2, "specialty_longersprint", 10 );

    wait 3;

    self thread maps\mp\gametypes\_hud_util::hidePerk( 0, 0.4 );
    self thread maps\mp\gametypes\_hud_util::hidePerk( 1, 0.4 );
    self thread maps\mp\gametypes\_hud_util::hidePerk( 2, 0.4 );
}

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

    names = [];
    names[0] = load["primaryName"];
    names[1] = load["secondaryName"];
    names[2] = load["lethalName"];
    names[3] = load["tacticalName"];

    yPos = [];
    yPos[0] = -128;
    yPos[1] = -120;
    yPos[2] = -112;
    yPos[3] = -104;

    icons = [];
    texts = [];

    for ( i = 0; i < 4; i++ )
    {
        icons[i] = self maps\mp\gametypes\_hud_util::createLoadoutIcon( i + 1, 0, 200, yPos[i] );
        texts[i] = self maps\mp\gametypes\_hud_util::createLoadoutText( icons[i], 160 );
        self maps\mp\gametypes\_hud_util::showLoadoutAttribute( icons[i], shaders[i], 1, texts[i], names[i] );

        if ( i < 2 )
            icons[i] setShader( shaders[i], 64, 32 );

        icons[i] moveOverTime( 0.3 );
        icons[i].x = -5;
        icons[i].hidewheninmenu = true;
        icons[i].hidewheninkillcam = true;
        icons[i].hidewhileremotecontrolling = true;

        texts[i] moveOverTime( 0.3 );
        texts[i].x = -72;
        texts[i].hidewheninmenu = true;
        texts[i].hidewheninkillcam = true;
        texts[i].hidewhileremotecontrolling = true;

        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = icons[i];
        self.gf_loadoutHudElems[self.gf_loadoutHudElems.size] = texts[i];
    }

    wait 5;

    for ( i = 0; i < 4; i++ )
    {
        icons[i] moveOverTime( 0.3 );
        icons[i].x = 400;
        texts[i] moveOverTime( 0.3 );
        texts[i].x = 400;
    }

    wait 0.35;
    self gf_destroyLoadoutHUD();
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
