// Gunfight v2 — HUD
// Loadout icon slide-in display, adapted from Xinerki t5-gunfight/duel.gsc

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

gf_showLoadoutHUD( load )
{
    if ( !isDefined( load ) )
        return;

    // kill any lingering instance from previous spawn
    self notify( "gf_kill_loadout_hud" );
    self endon( "gf_kill_loadout_hud" );
    self endon( "disconnect" );
    self endon( "death" );
    level endon( "game_ended" );

    // weapon rows: primary, secondary, lethal, tactical
    wYPos    = [];   wYPos[0]    = -168;   wYPos[1]    = -140;   wYPos[2]    = -112;   wYPos[3]    = -84;
    wIconW   = [];   wIconW[0]   = 64;     wIconW[1]   = 64;     wIconW[2]   = 32;     wIconW[3]   = 32;

    wShaders = [];
    wShaders[0] = load["primaryShader"];
    wShaders[1] = load["secondaryShader"];
    wShaders[2] = load["lethalShader"];
    wShaders[3] = load["tacticalShader"];

    wNames = [];
    wNames[0] = load["primaryName"];
    wNames[1] = load["secondaryName"];
    wNames[2] = load["lethalName"];
    wNames[3] = load["tacticalName"];

    // perk rows: lightweight, hardened, marathon
    // shader names are unverified in T5 — icon shows blank if wrong, no crash
    pYPos    = [];   pYPos[0]    = -56;    pYPos[1]    = -28;    pYPos[2]    = 0;

    pShaders = [];
    pShaders[0] = "perk_lightweight";    // Lightweight
    pShaders[1] = "perk_deep_impact";   // Hardened (Deep Impact in BO1)
    pShaders[2] = "perk_marathon";      // Marathon

    pNames = [];
    pNames[0] = "Lightweight";
    pNames[1] = "Hardened";
    pNames[2] = "Marathon";

    wIcons = [];   wTexts = [];
    pIcons = [];   pTexts = [];

    for ( i = 0; i < 4; i++ )
    {
        e = newClientHudElem( self );
        e.horzAlign = "right";   e.vertAlign = "middle";
        e.alignX    = "right";   e.alignY    = "middle";
        e.hidewheninmenu = true;   e.sort = 2;
        e.x = 400;   e.y = wYPos[i];
        e setShader( wShaders[i], wIconW[i], 32 );
        e moveOverTime( 0.4 );
        e.x = -5;
        wIcons[i] = e;

        t = newClientHudElem( self );
        t.horzAlign = "right";   t.vertAlign = "middle";
        t.alignX    = "right";   t.alignY    = "middle";
        t.font = "default";   t.fontScale = 1.3;
        t.hidewheninmenu = true;   t.sort = 2;
        t.x = 400;   t.y = wYPos[i];
        t setText( wNames[i] );
        t moveOverTime( 0.4 );
        t.x = -72;
        wTexts[i] = t;
    }

    for ( i = 0; i < 3; i++ )
    {
        e = newClientHudElem( self );
        e.horzAlign = "right";   e.vertAlign = "middle";
        e.alignX    = "right";   e.alignY    = "middle";
        e.hidewheninmenu = true;   e.sort = 2;
        e.x = 400;   e.y = pYPos[i];
        e setShader( pShaders[i], 32, 24 );
        e moveOverTime( 0.4 );
        e.x = -5;
        pIcons[i] = e;

        t = newClientHudElem( self );
        t.horzAlign = "right";   t.vertAlign = "middle";
        t.alignX    = "right";   t.alignY    = "middle";
        t.font = "default";   t.fontScale = 1.3;
        t.hidewheninmenu = true;   t.sort = 2;
        t.x = 400;   t.y = pYPos[i];
        t setText( pNames[i] );
        t moveOverTime( 0.4 );
        t.x = -72;
        pTexts[i] = t;
    }

    wait 5.5;

    for ( i = 0; i < 4; i++ )
    {
        wIcons[i] moveOverTime( 0.4 );   wIcons[i].x = 400;
        wTexts[i] moveOverTime( 0.4 );   wTexts[i].x = 400;
    }
    for ( i = 0; i < 3; i++ )
    {
        pIcons[i] moveOverTime( 0.4 );   pIcons[i].x = 400;
        pTexts[i] moveOverTime( 0.4 );   pTexts[i].x = 400;
    }

    wait 0.4;

    for ( i = 0; i < 4; i++ )
    {
        wIcons[i].alpha = 0;   wTexts[i].alpha = 0;
    }
    for ( i = 0; i < 3; i++ )
    {
        pIcons[i].alpha = 0;   pTexts[i].alpha = 0;
    }
}
