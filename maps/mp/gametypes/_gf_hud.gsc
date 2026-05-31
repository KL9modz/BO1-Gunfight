// Gunfight HUD
// Health rows are event-driven: damage, death, spawn, and spectator changes
// notify waiting clients instead of every client polling all players.

gf_startHealthHUD()
{
    self notify( "gf_restart_health_hud" );
    self gf_destroyHealthHUD();
    self endon( "gf_restart_health_hud" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    self.gf_healthHudElems = [];
    self.gf_healthHudAllies = [];
    self.gf_healthHudAxis = [];

    aLabel = self gf_createHealthElem( 170, ( 0.4, 0.7, 1.0 ) );
    aLabel setText( "ALLIES" );
    self.gf_healthHudElems[self.gf_healthHudElems.size] = aLabel;

    xLabel = self gf_createHealthElem( 250, ( 1.0, 0.45, 0.45 ) );
    xLabel setText( "AXIS" );
    self.gf_healthHudElems[self.gf_healthHudElems.size] = xLabel;

    for ( i = 0; i < 4; i++ )
    {
        row = self gf_createHealthElem( 185 + i * 14, ( 0.4, 0.7, 1.0 ) );
        self.gf_healthHudAllies[i] = row;
        self.gf_healthHudElems[self.gf_healthHudElems.size] = row;

        row = self gf_createHealthElem( 265 + i * 14, ( 1.0, 0.45, 0.45 ) );
        self.gf_healthHudAxis[i] = row;
        self.gf_healthHudElems[self.gf_healthHudElems.size] = row;
    }

    self gf_updateHealthHUD();

    while ( true )
    {
        level waittill( "gf_health_hud_update" );
        self gf_updateHealthHUD();
    }
}

gf_createHealthElem( y, color )
{
    elem = newClientHudElem( self );
    elem.horzAlign = "left";
    elem.vertAlign = "top";
    elem.alignX = "left";
    elem.alignY = "top";
    elem.x = -300;
    elem.y = y;
    elem.font = "default";
    elem.fontScale = 1.1;
    elem.color = color;
    elem.sort = 20;
    elem.foreground = true;
    elem.hidewheninmenu = true;
    elem.hidewheninkillcam = true;
    elem.hidewhileremotecontrolling = true;
    elem moveOverTime( 0.4 );
    elem.x = 10;
    return elem;
}

gf_updateHealthHUD()
{
    if ( !isDefined( self.gf_healthHudAllies ) || !isDefined( self.gf_healthHudAxis ) )
        return;

    allies = [];
    axis = [];

    for ( i = 0; i < level.players.size; i++ )
    {
        player = level.players[i];
        if ( !isDefined( player.pers["team"] ) )
            continue;

        if ( player.pers["team"] == "allies" )
            allies[allies.size] = player;
        else if ( player.pers["team"] == "axis" )
            axis[axis.size] = player;
    }

    for ( i = 0; i < 4; i++ )
    {
        self gf_updateHealthRow( self.gf_healthHudAllies[i], allies, i, "allies" );
        self gf_updateHealthRow( self.gf_healthHudAxis[i], axis, i, "axis" );
    }
}

gf_updateHealthRow( elem, players, index, team )
{
    if ( !isDefined( elem ) )
        return;

    if ( index >= players.size )
    {
        elem setText( "" );
        return;
    }

    player = players[index];
    hp = 0;

    if ( player.sessionstate == "playing" && isDefined( player.health ) && player.health > 0 )
        hp = player.health;

    prefix = "  ";
    if ( player == self )
        prefix = "> ";

    elem setText( prefix + player.name + "  " + hp );

    if ( hp <= 0 )
        elem.color = ( 0.45, 0.45, 0.45 );
    else if ( player == self )
        elem.color = ( 1, 1, 1 );
    else if ( team == "allies" )
        elem.color = ( 0.4, 0.7, 1.0 );
    else
        elem.color = ( 1.0, 0.45, 0.45 );
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
    self.gf_healthHudAllies = undefined;
    self.gf_healthHudAxis = undefined;
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

    names = [];
    names[0] = load["primaryName"];
    names[1] = load["secondaryName"];
    names[2] = load["lethalName"];

    yPos = [];
    yPos[0] = -128;
    yPos[1] = -120;
    yPos[2] = -112;

    icons = [];
    texts = [];

    for ( i = 0; i < 3; i++ )
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

    for ( i = 0; i < 3; i++ )
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
            self.gf_loadoutHudElems[i] destroyElem();
    }

    self.gf_loadoutHudElems = undefined;
}
