// Gunfight — HUD
// Weapon loadout slide-in uses stock _hud_util functions (same pattern as duel.gsc).
// Perk icons are handled entirely by the stock spawnPlayer() pipeline.

gf_healthHUD()
{
    self notify( "gf_kill_health_hud" );
    self endon( "gf_kill_health_hud" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    aLabel = newClientHudElem( self );
    aLabel.horzAlign = "left";   aLabel.vertAlign = "top";
    aLabel.alignX    = "left";   aLabel.alignY    = "top";
    aLabel.x = -300;   aLabel.y = 170;
    aLabel.font = "default";   aLabel.fontScale = 1.1;
    aLabel.color = ( 0.4, 0.7, 1.0 );
    aLabel.hidewheninmenu = true;
    aLabel setText( "ALLIES" );
    aLabel moveOverTime( 0.4 );
    aLabel.x = 10;

    xLabel = newClientHudElem( self );
    xLabel.horzAlign = "left";   xLabel.vertAlign = "top";
    xLabel.alignX    = "left";   xLabel.alignY    = "top";
    xLabel.x = -300;   xLabel.y = 250;
    xLabel.font = "default";   xLabel.fontScale = 1.1;
    xLabel.color = ( 1.0, 0.45, 0.45 );
    xLabel.hidewheninmenu = true;
    xLabel setText( "AXIS" );
    xLabel moveOverTime( 0.4 );
    xLabel.x = 10;

    aHp = [];
    xHp = [];
    for ( i = 0; i < 4; i++ )
    {
        e = newClientHudElem( self );
        e.horzAlign = "left";   e.vertAlign = "top";
        e.alignX    = "left";   e.alignY    = "top";
        e.x = -300;   e.y = 185 + i * 14;
        e.font = "default";   e.fontScale = 1.1;
        e.hidewheninmenu = true;
        e moveOverTime( 0.4 );
        e.x = 10;
        aHp[i] = e;

        e2 = newClientHudElem( self );
        e2.horzAlign = "left";   e2.vertAlign = "top";
        e2.alignX    = "left";   e2.alignY    = "top";
        e2.x = -300;   e2.y = 265 + i * 14;
        e2.font = "default";   e2.fontScale = 1.1;
        e2.hidewheninmenu = true;
        e2 moveOverTime( 0.4 );
        e2.x = 10;
        xHp[i] = e2;
    }

    while ( true )
    {
        wait 0.2;

        allies = [];
        axis   = [];
        for ( i = 0; i < level.players.size; i++ )
        {
            p = level.players[i];
            if ( !isDefined( p.pers["team"] ) ) continue;
            if ( p.pers["team"] == "allies" )
                allies[ allies.size ] = p;
            else if ( p.pers["team"] == "axis" )
                axis[ axis.size ] = p;
        }

        for ( i = 0; i < 4; i++ )
        {
            if ( i < allies.size )
            {
                p  = allies[i];
                hp = p.health;
                if ( hp < 0 ) hp = 0;
                if ( p == self ) prefix = "> ";
                else             prefix = "  ";
                aHp[i] setText( prefix + p.name + "  " + hp );
                if      ( p == self ) aHp[i].color = ( 1,    1,    1    );
                else if ( hp > 0 )    aHp[i].color = ( 0.4,  0.7,  1.0  );
                else                  aHp[i].color = ( 0.45, 0.45, 0.45 );
            }
            else
            {
                aHp[i] setText( "" );
            }

            if ( i < axis.size )
            {
                p  = axis[i];
                hp = p.health;
                if ( hp < 0 ) hp = 0;
                if ( p == self ) prefix = "> ";
                else             prefix = "  ";
                xHp[i] setText( prefix + p.name + "  " + hp );
                if      ( p == self ) xHp[i].color = ( 1,    1,    1    );
                else if ( hp > 0 )    xHp[i].color = ( 1.0,  0.45, 0.45 );
                else                  xHp[i].color = ( 0.45, 0.45, 0.45 );
            }
            else
            {
                xHp[i] setText( "" );
            }
        }
    }
}

// Overrides the stock perk display with our actual assigned perks.
// The stock spawnPlayer() calls showPerk() using getPerks() which reads from
// CLASS data (CLASS_ASSAULT defaults), not from live SetPerk() state.
// Threading with a one-frame wait lets the stock call run first, then we
// overwrite its elements with the correct perk strings.
gf_showCustomPerks()
{
    self endon( "disconnect" );
    self endon( "death" );
    wait 0.05;
    self maps\mp\gametypes\_hud_util::showPerk( 0, "specialty_movefaster",       10 );
    self maps\mp\gametypes\_hud_util::showPerk( 1, "specialty_bulletpenetration", 10 );
    self maps\mp\gametypes\_hud_util::showPerk( 2, "specialty_longersprint",      10 );
}

// Weapon icon slide-in on spawn — primary, secondary, lethal.
// Uses the same _hud_util infrastructure as duel.gsc (createLoadoutIcon /
// createLoadoutText / showLoadoutAttribute).  Perk icons are shown by the
// stock spawnPlayer() pipeline and deliberately not duplicated here.
gf_showWeaponHUD( load )
{
    if ( !isDefined( load ) )
        return;

    self notify( "gf_kill_loadout_hud" );
    self endon( "gf_kill_loadout_hud" );
    self endon( "disconnect" );
    self endon( "death" );
    level endon( "game_ended" );

    shaders = [];
    shaders[0] = load["primaryShader"];
    shaders[1] = load["secondaryShader"];
    shaders[2] = load["lethalShader"];

    names = [];
    names[0] = load["primaryName"];
    names[1] = load["secondaryName"];
    names[2] = load["lethalName"];

    // yPos values position the three rows above the stock perk icons.
    // Indices 1-3 match duel.gsc showWeaponInfo() layout.
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

        // Primary and secondary get wider icon (64×32); lethal stays 32×32
        if ( i < 2 )
            icons[i] setShader( shaders[i], 64, 32 );

        icons[i] moveOverTime( 0.3 );
        icons[i].x = -5;
        icons[i].hidewheninmenu = true;
        texts[i] moveOverTime( 0.3 );
        texts[i].x = -72;
        texts[i].hidewheninmenu = true;
    }

    wait 5;

    for ( i = 0; i < 3; i++ )
    {
        icons[i] moveOverTime( 0.3 );
        icons[i].x = 400;
        texts[i] moveOverTime( 0.3 );
        texts[i].x = 400;
    }
}
