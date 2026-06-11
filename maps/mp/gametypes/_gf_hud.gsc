// Gunfight HUD
//
// Both the Health HUD and the Loadout HUD are CLIENT-SIDE (newClientHudElem), built
// per player in the player's own thread. This is deliberate: T5 server team-HUD
// elements (newTeamHudElem) do NOT live-update their text/alpha/color mid-round — the
// change only flushes to clients on a round transition — and client elements created
// from a level thread never network at all. So per-player + player-thread is the only
// pattern that updates reliably during a round.
//
// Health HUD:
//   - Level thread gf_startHealthHUD() ONLY computes the team totals (HP / fill
//     fraction / player count / alive count) and publishes them to level.gf_* vars.
//   - Each player runs gf_runHealthHUD() (singleton via self notify/endon), which
//     builds the panel (faction frame + 2 team bars + skull icons + HP numbers), slides
//     it in, and updates it every 0.1s from the published vars. Row 0 = own team
//     (green), row 1 = enemy (red). map_restart wipes the panel between rounds; it's
//     recreated on the next spawn.
//
// Loadout HUD: gf_showWeaponHUD(), also per-player / self thread.

#include maps\mp\gametypes\_hud_util;

// ─── Health HUD ──────────────────────────────────────────────────────────────

gf_startHealthHUD()
{
    // The health HUD is fully client-side per player (gf_runHealthHUD). This level
    // thread only computes the team totals and publishes them for the player panels
    // to read — T5 client HUD elements can't be created or updated from a level thread.
    level notify( "gf_restart_health_hud" );
    level endon( "gf_restart_health_hud" );
    level endon( "game_ended" );

    gf_updateHealthHUD();
    level thread gf_periodicHealthHUDUpdate();

    while ( true )
    {
        level waittill( "gf_health_hud_update" );
        gf_updateHealthHUD();
    }
}

gf_periodicHealthHUDUpdate()
{
    level endon( "gf_restart_health_hud" );
    level endon( "game_ended" );
    while ( true )
    {
        wait 0.5;
        gf_updateHealthHUD();
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
    alliesStats = gf_getTeamHealthStats( "allies" );
    axisStats   = gf_getTeamHealthStats( "axis" );

    // Published for the per-player client health panels (gf_runHealthHUD) to read.
    level.gf_hpAllies    = alliesStats.current;
    level.gf_hpAxis      = axisStats.current;
    level.gf_fracAllies  = gf_getTeamHealthBarFraction( alliesStats.current, alliesStats.max );
    level.gf_fracAxis    = gf_getTeamHealthBarFraction( axisStats.current,   axisStats.max );
    level.gf_cntAllies   = alliesStats.players.size;
    level.gf_aliveAllies = alliesStats.alive;
    level.gf_cntAxis     = axisStats.players.size;
    level.gf_aliveAxis   = axisStats.alive;

    // Live diagnostics surfaced on the HUD pool overlay (gf_debug_hud_pool 1).
    level.gf_dbg_alliesHP = alliesStats.current;
    level.gf_dbg_alliesN  = alliesStats.players.size;
    level.gf_dbg_axisHP   = axisStats.current;
    level.gf_dbg_axisN    = axisStats.players.size;
}

// ─── Per-player client health panel ──────────────────────────────────────────
// The entire health HUD is client-side per viewer (newClientHudElem): faction frame,
// two team bars, alive-skull icons, and HP numbers. Created / updated / destroyed in
// the player's own thread (gf_runHealthHUD) — T5 client elements don't network if
// touched from a level thread. Reads the team totals published by gf_updateHealthHUD.
// Row 0 = own team (green), row 1 = enemy (red). Everything slides in together.

gf_HP_ROW0_Y()       { return -45; }
gf_HP_ROW1_Y()       { return -27; }
gf_HP_SLIDE_OFFSET() { return -230; }

gf_runHealthHUD()
{
    self notify( "gf_kill_health_hud" );
    self gf_destroyHealthPanel();
    self endon( "gf_kill_health_hud" );
    self endon( "disconnect" );

    // Wait BEFORE creating the panel — the loadout intro owns ~18 client HUD elements
    // and the client pool is shared. Hidden elements still occupy slots, so we must not
    // build the panel until the loadout HUD has been destroyed and freed its slots.
    self gf_waitLoadoutIntroDone();

    gf_updateHealthHUD();              // seed the published totals
    self gf_createHealthPanel();       // pool is free now that the loadout intro is gone
    self gf_updateHealthPanel();       // fill values + target alphas in before revealing
    self gf_hideHealthPanelForIntro(); // park off-screen + transparent
    self gf_revealHealthPanel();       // slide + fade in together
    wait 0.75;                         // let the reveal finish before the loop retargets

    for ( ;; )
    {
        self gf_updateHealthPanel();
        wait 0.1;
    }
}

gf_createHealthPanel()
{
    self.gf_hudElems = [];
    self.gf_rows = [];

    self.gf_bg    = self gf_clCreateFrame( -70,  -39, 180, 42, "hud_frame_faction_fade",  0.34, 37 );
    self.gf_lines = self gf_clCreateFrame( -162, -45, 250, 52, "hud_frame_faction_lines", 0.30, 38 );

    self.gf_rows[0] = self gf_clCreateRow( gf_HP_ROW0_Y(), 40 );
    self.gf_rows[1] = self gf_clCreateRow( gf_HP_ROW1_Y(), 50 );
}

gf_clCreateRow( y, sortBase )
{
    row = spawnstruct();
    row.y = y;
    row.x = -12;
    row.width = 88;
    row.height = 10;

    row.bar = self gf_clCreateBar( row.x, y, row.width, row.height, sortBase );

    row.icons = [];
    for ( i = 0; i < 3; i++ )
        row.icons[i] = self gf_clCreateIcon( 4 + i * 9, y, sortBase + 5 );

    row.number = self gf_clCreateNumber( y, sortBase + 6 );
    return row;
}

gf_clCreateFrame( x, y, w, h, shader, alpha, sort )
{
    icon = self createIcon( shader, w, h );
    icon setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    icon.color = ( 1, 1, 1 );
    gf_styleHealthElem( icon, sort );
    icon.alpha = alpha;
    self.gf_hudElems[self.gf_hudElems.size] = icon;
    return icon;
}

gf_clCreateBar( x, y, w, h, sort )
{
    bar = self createBar( ( 1, 1, 1 ), w, h );
    bar setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    bar.bar.shader = "hud_score_progress";
    bar.bar setShader( "hud_score_progress", w, h );
    bar.barFrame setShader( "progress_bar_fg", w, h );
    bar.gf_bgAlpha    = 0;
    bar.gf_frameAlpha = 0;
    bar.gf_fillAlpha  = 0.80;
    gf_styleHealthElem( bar, sort );
    gf_styleHealthElem( bar.bar, sort + 1 );
    gf_styleHealthElem( bar.barFrame, sort + 2 );
    self.gf_hudElems[self.gf_hudElems.size] = bar;
    gf_setHealthBarFraction( bar, 0, false );
    return bar;
}

gf_clCreateIcon( x, y, sort )
{
    icon = self createIcon( "hud_death_suicide", 7, 7 );
    icon setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    icon.color = ( 1, 1, 1 );
    gf_styleHealthElem( icon, sort );
    icon.alpha = 0;
    self.gf_hudElems[self.gf_hudElems.size] = icon;
    return icon;
}

gf_clCreateNumber( y, sort )
{
    num = self createFontString( "default", 1.2 );
    num setPoint( "CENTER LEFT", "CENTER LEFT", 80, y );   // initial x; retargeted to the fill edge each tick
    gf_styleHealthElem( num, sort );
    num.alpha = 0;
    self.gf_hudElems[self.gf_hudElems.size] = num;
    return num;
}

// Park the whole panel off-screen left and stash each element's target alpha so the
// reveal can both slide it in and fade it up to that alpha.
gf_hideHealthPanelForIntro()
{
    if ( !isDefined( self.gf_hudElems ) )
        return;

    offset = gf_HP_SLIDE_OFFSET();
    for ( i = 0; i < self.gf_hudElems.size; i++ )
    {
        elem = self.gf_hudElems[i];
        gf_offsetHealthHUDElem( elem, offset, 0 );
        gf_stashAndClearAlpha( elem );
        if ( isDefined( elem.elemType ) && elem.elemType == "bar" )
        {
            if ( isDefined( elem.bar ) )      gf_stashAndClearAlpha( elem.bar );
            if ( isDefined( elem.barFrame ) ) gf_stashAndClearAlpha( elem.barFrame );
        }
    }
}

gf_stashAndClearAlpha( elem )
{
    if ( !isDefined( elem ) )
        return;
    elem.gf_targetAlpha = elem.alpha;
    elem.alpha = 0;
}

// Slide back to home and fade up to the stashed alpha, both over the same 0.75s.
gf_revealHealthPanel()
{
    if ( !isDefined( self.gf_hudElems ) )
        return;

    offset = gf_HP_SLIDE_OFFSET();
    for ( i = 0; i < self.gf_hudElems.size; i++ )
    {
        elem = self.gf_hudElems[i];
        gf_offsetHealthHUDElem( elem, 0 - offset, 0.75 );
        gf_fadeToTarget( elem );
        if ( isDefined( elem.elemType ) && elem.elemType == "bar" )
        {
            if ( isDefined( elem.bar ) )      gf_fadeToTarget( elem.bar );
            if ( isDefined( elem.barFrame ) ) gf_fadeToTarget( elem.barFrame );
        }
    }
}

gf_fadeToTarget( elem )
{
    if ( !isDefined( elem ) )
        return;
    target = 0;
    if ( isDefined( elem.gf_targetAlpha ) )
        target = elem.gf_targetAlpha;
    elem fadeOverTime( 0.75 );
    elem.alpha = target;
}

// Hold the panel reveal until the per-player loadout intro has finished and slid out
// (gf_showWeaponHUD notifies "gf_loadout_intro_done" when it destroys). 7s fallback in
// case the loadout HUD never ran this spawn.
gf_waitLoadoutIntroDone()
{
    self endon( "disconnect" );
    self endon( "gf_kill_health_hud" );

    self thread gf_loadoutIntroTimeout();
    self waittill( "gf_loadout_intro_done" );
}

gf_loadoutIntroTimeout()
{
    self endon( "disconnect" );
    self endon( "gf_kill_health_hud" );
    self endon( "gf_loadout_intro_done" );
    wait 7.0;
    self notify( "gf_loadout_intro_done" );
}

gf_updateHealthPanel()
{
    if ( !isDefined( self.gf_rows ) )
        return;

    team = undefined;
    if ( isDefined( self.pers["team"] ) )
        team = self.pers["team"];

    if ( team != "allies" && team != "axis" )
    {
        self gf_hideHealthRow( self.gf_rows[0] );
        self gf_hideHealthRow( self.gf_rows[1] );
        return;
    }

    if ( team == "allies" )
    {
        friendlyTeam = "allies";
        enemyTeam    = "axis";
    }
    else
    {
        friendlyTeam = "axis";
        enemyTeam    = "allies";
    }

    self gf_setHealthRow( self.gf_rows[0], friendlyTeam, ( 0.42, 0.68, 0.46 ) );
    self gf_setHealthRow( self.gf_rows[1], enemyTeam,    ( 0.73, 0.29, 0.19 ) );
}

gf_setHealthRow( row, team, color )
{
    if ( !isDefined( row ) )
        return;

    hp    = gf_readTeamHP( team );
    frac  = gf_readTeamFrac( team );
    count = gf_readTeamCount( team );
    alive = gf_readTeamAlive( team );

    if ( isDefined( row.bar ) && isDefined( row.bar.bar ) )
        row.bar.bar.color = color;
    gf_setHealthBarFraction( row.bar, frac, hp > 0 );

    gf_setHealthNumber( row.number, hp, frac, color );

    if ( count > 3 ) count = 3;
    if ( alive > 3 ) alive = 3;
    for ( i = 0; i < 3; i++ )
    {
        icon = row.icons[i];
        if ( !isDefined( icon ) )
            continue;
        if ( i >= count )
        {
            icon.alpha = 0;
            continue;
        }
        icon.alpha = 0.95;
        if ( i < alive )
            icon.color = color;
        else
            icon.color = ( 1, 1, 1 );
    }
}

gf_hideHealthRow( row )
{
    if ( !isDefined( row ) )
        return;

    gf_setHealthBarFraction( row.bar, 0, false );
    if ( isDefined( row.number ) )
        row.number.alpha = 0;
    for ( i = 0; i < 3; i++ )
        if ( isDefined( row.icons[i] ) )
            row.icons[i].alpha = 0;
}

gf_readTeamHP( team )
{
    if ( team == "allies" && isDefined( level.gf_hpAllies ) )
        return level.gf_hpAllies;
    if ( team == "axis" && isDefined( level.gf_hpAxis ) )
        return level.gf_hpAxis;
    return 0;
}

gf_readTeamFrac( team )
{
    if ( team == "allies" && isDefined( level.gf_fracAllies ) )
        return level.gf_fracAllies;
    if ( team == "axis" && isDefined( level.gf_fracAxis ) )
        return level.gf_fracAxis;
    return 0;
}

gf_readTeamCount( team )
{
    if ( team == "allies" && isDefined( level.gf_cntAllies ) )
        return level.gf_cntAllies;
    if ( team == "axis" && isDefined( level.gf_cntAxis ) )
        return level.gf_cntAxis;
    return 0;
}

gf_readTeamAlive( team )
{
    if ( team == "allies" && isDefined( level.gf_aliveAllies ) )
        return level.gf_aliveAllies;
    if ( team == "axis" && isDefined( level.gf_aliveAxis ) )
        return level.gf_aliveAxis;
    return 0;
}

gf_setHealthNumber( num, hp, frac, color )
{
    if ( !isDefined( num ) )
        return;

    if ( hp > 0 )
    {
        // Ride the bar's fill edge: the bar spans x -12..76 (width 88), so the fill tip
        // is at -12 + 88*frac. +3 leaves a small gap so the number sits just off the edge.
        // The bar's bg/frame are alpha 0, so past the fill only the faint faction frame
        // overlaps — the number stays readable.
        num setText( int( hp ) + "" );
        num.x = -12 + int( 88.0 * frac + 0.5 ) + 3;
        num.color = color;
        num.alpha = 1;
    }
    else
    {
        num.alpha = 0;
    }
}

gf_destroyHealthPanel()
{
    if ( !isDefined( self.gf_hudElems ) )
        return;

    for ( i = 0; i < self.gf_hudElems.size; i++ )
    {
        elem = self.gf_hudElems[i];
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

    self.gf_hudElems = undefined;
    self.gf_rows = undefined;
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
        if ( !isDefined( player ) )
            continue;

        if ( !isDefined( player.pers["team"] ) || player.pers["team"] != team )
            continue;

        stats.players[stats.players.size] = player;
        maxHP = player gf_getPlayerMaxHealth();
        stats.max += maxHP;

        if ( isDefined( player.health ) && player.health > 0 )
        {
            stats.current += player.health;
            stats.alive++;
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

    // Cue the health panel to slide/fade in now that the loadout intro has cleared.
    self notify( "gf_loadout_intro_done" );
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
