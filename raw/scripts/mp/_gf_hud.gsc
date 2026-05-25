// Gunfight v2 — HUD
// Loadout icon slide-in display, adapted from Xinerki t5-gunfight/duel.gsc

gf_showLoadoutHUD()
{
    if ( !isDefined( level.gf_currentLoad ) )
        return;

    // kill any lingering instance from previous spawn
    self notify( "gf_kill_loadout_hud" );
    self endon( "gf_kill_loadout_hud" );
    self endon( "disconnect" );
    self endon( "death" );
    level endon( "game_ended" );

    load = level.gf_currentLoad;

    yPos = [];
    yPos[0] = -128;
    yPos[1] = -114;
    yPos[2] = -100;

    shaders = [];
    shaders[0] = load["primaryShader"];
    shaders[1] = load["secondaryShader"];
    shaders[2] = load["lethalShader"];

    names = [];
    names[0] = load["primaryName"];
    names[1] = load["secondaryName"];
    names[2] = load["lethalName"];

    iconW = [];
    iconW[0] = 64; iconW[1] = 64; iconW[2] = 32;

    icons = [];
    texts = [];

    for ( i = 0; i < 3; i++ )
    {
        e = newClientHudElem( self );
        e.horzAlign      = "right";
        e.vertAlign      = "middle";
        e.alignX         = "right";
        e.alignY         = "middle";
        e.hidewheninmenu = true;
        e.sort           = 2;
        e.x              = 400;
        e.y              = yPos[i];
        e setShader( shaders[i], iconW[i], 32 );
        e moveOverTime( 0.3 );
        e.x = -5;
        icons[i] = e;

        t = newClientHudElem( self );
        t.horzAlign      = "right";
        t.vertAlign      = "middle";
        t.alignX         = "right";
        t.alignY         = "middle";
        t.font           = "smallfixed";
        t.fontScale      = 1.0;
        t.hidewheninmenu = true;
        t.sort           = 2;
        t.x              = 400;
        t.y              = yPos[i];
        t setText( names[i] );
        t moveOverTime( 0.3 );
        t.x = -72;
        texts[i] = t;
    }

    wait 5.5;

    for ( i = 0; i < 3; i++ )
    {
        icons[i] moveOverTime( 0.3 );
        icons[i].x = 400;
        texts[i] moveOverTime( 0.3 );
        texts[i].x = 400;
    }

    wait 0.4;

    for ( i = 0; i < 3; i++ )
    {
        icons[i].alpha = 0;
        texts[i].alpha = 0;
    }
}
