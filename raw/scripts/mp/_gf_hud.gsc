// Gunfight v2 — HUD
// Loadout icon slide-in display, adapted from Xinerki t5-gunfight/duel.gsc

gf_debugHealthHUD()
{
    self notify( "gf_kill_debug_hp" );
    self endon(  "gf_kill_debug_hp" );
    self endon(  "disconnect" );
    level endon( "game_ended" );

    for ( ;; )
    {
        self iPrintLn( "HP: " + self.health );
        wait 1;
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

    // weapon rows: primary, secondary, lethal
    wYPos    = [];   wYPos[0]    = -128;   wYPos[1]    = -106;   wYPos[2]    = -84;
    wIconW   = [];   wIconW[0]   = 64;     wIconW[1]   = 64;     wIconW[2]   = 32;

    wShaders = [];
    wShaders[0] = load["primaryShader"];
    wShaders[1] = load["secondaryShader"];
    wShaders[2] = load["lethalShader"];

    wNames = [];
    wNames[0] = load["primaryName"];
    wNames[1] = load["secondaryName"];
    wNames[2] = load["lethalName"];

    // perk rows: lightweight, hardened, marathon
    // shader names are unverified in T5 — icon shows blank if wrong, no crash
    pYPos    = [];   pYPos[0]    = -62;    pYPos[1]    = -40;    pYPos[2]    = -18;

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

    for ( i = 0; i < 3; i++ )
    {
        e = newClientHudElem( self );
        e.horzAlign = "right";   e.vertAlign = "middle";
        e.alignX    = "right";   e.alignY    = "middle";
        e.hidewheninmenu = true;   e.sort = 2;
        e.x = 400;   e.y = wYPos[i];
        e setShader( wShaders[i], wIconW[i], 32 );
        e moveOverTime( 0.3 );
        e.x = -5;
        wIcons[i] = e;

        t = newClientHudElem( self );
        t.horzAlign = "right";   t.vertAlign = "middle";
        t.alignX    = "right";   t.alignY    = "middle";
        t.font = "smallfixed";   t.fontScale = 1.0;
        t.hidewheninmenu = true;   t.sort = 2;
        t.x = 400;   t.y = wYPos[i];
        t setText( wNames[i] );
        t moveOverTime( 0.3 );
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
        e setShader( pShaders[i], 32, 16 );
        e moveOverTime( 0.3 );
        e.x = -5;
        pIcons[i] = e;

        t = newClientHudElem( self );
        t.horzAlign = "right";   t.vertAlign = "middle";
        t.alignX    = "right";   t.alignY    = "middle";
        t.font = "smallfixed";   t.fontScale = 1.0;
        t.hidewheninmenu = true;   t.sort = 2;
        t.x = 400;   t.y = pYPos[i];
        t setText( pNames[i] );
        t moveOverTime( 0.3 );
        t.x = -72;
        pTexts[i] = t;
    }

    wait 5.5;

    for ( i = 0; i < 3; i++ )
    {
        wIcons[i] moveOverTime( 0.3 );   wIcons[i].x = 400;
        wTexts[i] moveOverTime( 0.3 );   wTexts[i].x = 400;
        pIcons[i] moveOverTime( 0.3 );   pIcons[i].x = 400;
        pTexts[i] moveOverTime( 0.3 );   pTexts[i].x = 400;
    }

    wait 0.4;

    for ( i = 0; i < 3; i++ )
    {
        wIcons[i].alpha = 0;   wTexts[i].alpha = 0;
        pIcons[i].alpha = 0;   pTexts[i].alpha = 0;
    }
}
