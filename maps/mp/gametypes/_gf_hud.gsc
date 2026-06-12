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
    level.gf_fracAllies  = gf_getHealthFraction( alliesStats.current, alliesStats.max );
    level.gf_fracAxis    = gf_getHealthFraction( axisStats.current,   axisStats.max );
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

// Row y is the SKULL center; the strip hangs 6 below, so the combined block's visual
// center is ~y+2. These are pre-shifted up 2 so the block centers on the background
// band art (which was tuned around -45/-27).
gf_HP_ROW0_Y()       { return -47; }
gf_HP_ROW1_Y()       { return -29; }

// Whole-panel vertical offset (applied to frames + rows at creation). Negative = up.
// -50 parks the panel just below the minimap instead of at mid-screen-left.
gf_HP_PANEL_Y_OFF()  { return -50; }

// Skull icon size (square). blockWidth derives from this + the pitch.
gf_HP_ICON_SIZE()    { return 8; }
gf_HP_SLIDE_OFFSET() { return -420; }   // past the ultrawide left edge — parked elements
                                        // stay invisible at full alpha (pure-slide reveal)

// skipIntroWait: spectators get no loadout intro, so their panel shows immediately.
// Team players wait until the loadout intro has cleared before the panel is CREATED:
// the intro owns ~18 client HUD elements and the pool is shared — when the two
// coexisted, the loadout intro visibly lost elements. A 7.5s timeout fallback fires
// the wait even if the intro-done signal is dropped, so the panel can't be stranded.
gf_runHealthHUD( skipIntroWait )
{
    self notify( "gf_kill_health_hud" );
    self gf_destroyHealthPanel();
    self endon( "gf_kill_health_hud" );
    self endon( "disconnect" );

    if ( !isDefined( skipIntroWait ) || !skipIntroWait )
        self gf_waitLoadoutIntroDone();

    gf_updateHealthHUD();              // seed the published totals
    self gf_createHealthPanel();       // pool is free now that the loadout intro is gone
    self gf_updateHealthPanel();       // fill values + target alphas in before revealing
    self gf_hideHealthPanelForIntro(); // park off-screen (full opacity)
    self gf_revealHealthPanel();       // pure slide in — all elements move together
    wait 0.75;                         // let the reveal finish before the loop retargets

    for ( ;; )
    {
        self gf_updateHealthPanel();
        wait 0.1;
    }
}

// Hold until the per-player loadout intro has finished and slid out (gf_showWeaponHUD
// notifies "gf_loadout_intro_done" when it tears down). The timeout makes a dropped
// signal cost at most 7.5s instead of stranding the panel.
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
    wait 7.5;
    self notify( "gf_loadout_intro_done" );
}

gf_createHealthPanel()
{
    self.gf_hudElems = [];
    self.gf_rows = [];

    off = gf_HP_PANEL_Y_OFF();

    self.gf_bg    = self gf_clCreateFrame( -70,  -39 + off, 180, 42, "hud_frame_faction_fade",  0.34, 37 );
    self.gf_lines = self gf_clCreateFrame( -162, -45 + off, 250, 52, "hud_frame_faction_lines", 0.30, 38 );

    self.gf_rows[0] = self gf_clCreateRow( gf_HP_ROW0_Y() + off, 40 );
    self.gf_rows[1] = self gf_clCreateRow( gf_HP_ROW1_Y() + off, 50 );

    // Self bar is menu-rendered (hud_gf_health.menu) — just seed its name dvar; the
    // hp/show dvars are pushed on change from gf_updateSelfBar.
    self setClientDvar( "ui_gf_self_name", self.name );
    self.gf_sbHp = undefined;
    self.gf_sbShow = undefined;

    // Completion checkpoint: if this line is missing from the log after a spawn, the
    // creation thread died partway (e.g., a setText configstring overflow error).
    logPrint( "GF_HUD: panel built for " + self.name + " elems=" + self.gf_hudElems.size + "\n" );
}

// Row layout (reference-image style): up to 4 skull icons (4v4 support) on the left,
// then a fixed column with the white HP number on top and the health bar underneath.
// Skulls fill in left-to-right as the team populates; the number/bar column is fixed at
// gf_HP_BAR_X so both rows stay aligned regardless of team size. The bar = hairline
// border + semi-transparent black background + team-colored fill (green/red).
gf_HP_MAX_SKULLS()   { return 4; }
gf_HP_ICON_STEP()    { return 11; }   // integer pitch — fractional steps round to uneven pixel gaps
gf_HP_ROW_CENTER_X() { return 32; }   // visual center of the frame/lines art (right-biased in its
                                      // quad — the old tuned layout centered content here, not at
                                      // the quad midpoint)

// True span of N skull quads: (N-1) steps + one icon width.
gf_HP_blockWidth( count ) { return ( count - 1 ) * gf_HP_ICON_STEP() + gf_HP_ICON_SIZE(); }
gf_HP_blockLeft( count )  { return gf_HP_ROW_CENTER_X() - int( gf_HP_blockWidth( count ) / 2 ); }

// Bar geometry (reference-image layout): a fixed-length bar sits UNDER the HP number,
// to the right of the skull block. Both rows' bars are column-aligned at the same x
// regardless of team size; the bar is ~3x the number's width. The bar has its own
// semi-transparent black background and a hairline border behind it.
gf_HP_BAR_X() { return gf_HP_blockLeft( gf_HP_MAX_SKULLS() ) + gf_HP_blockWidth( gf_HP_MAX_SKULLS() ) + 6; }
gf_HP_BAR_W() { return 45; }
gf_HP_BAR_H() { return 3; }

// Inner-assembly x nudge: the border sits at a half-unit offset, and sub-unit
// positions round asymmetrically at some resolutions, biasing the bg+fill LEFT
// inside the ring. This shifts them right a fraction to re-center visually.
gf_HP_BAR_INNER_NUDGE() { return 0.3; }

// ─── Self health bar (bottom-center) ─────────────────────────────────────────
// FULLY CLIENT-RENDERED via ui_mp/hud_gf_health.menu (in mod.ff): the bar, name, and
// HP number are menu itemDefs driven by client dvars. The server only pushes
// ui_gf_self_hp / ui_gf_self_show (here, on change) and ui_gf_self_name (once per
// panel build). No HUD elements, no string table, no per-tick networking — immune to
// every failure mode the script-HUD path has hit.
gf_updateSelfBar()
{
    hp = 0;
    if ( isDefined( self.health ) && self.health > 0 )
        hp = self.health;

    show = 0;
    if ( hp > 0 && self.sessionstate == "playing" )
        show = 1;

    if ( !isDefined( self.gf_sbHp ) || self.gf_sbHp != hp )
    {
        self.gf_sbHp = hp;
        self setClientDvar( "ui_gf_self_hp", hp );
    }

    if ( !isDefined( self.gf_sbShow ) || self.gf_sbShow != show )
    {
        self.gf_sbShow = show;
        if ( show )
            self thread gf_slideSelfBarIn();   // reveals via animated ui_gf_self_off
        else
            self setClientDvar( "ui_gf_self_show", 0 );
    }
}

// Slide-from-bottom reveal: the menu items add dvarFloat("ui_gf_self_off") to their Y,
// so animating the dvar 40→0 slides the whole bar up from below the screen edge.
// Runs once per reveal (~10 setClientDvar pushes over 0.5s) — negligible traffic.
gf_slideSelfBarIn()
{
    self notify( "gf_sb_slide" );
    self endon( "gf_sb_slide" );
    self endon( "disconnect" );

    self setClientDvar( "ui_gf_self_off", 40 );
    self setClientDvar( "ui_gf_self_show", 1 );

    for ( off = 35; off > 0; off -= 5 )
    {
        wait 0.05;
        self setClientDvar( "ui_gf_self_off", off );
    }

    wait 0.05;
    self setClientDvar( "ui_gf_self_off", 0 );
}

gf_clCreateRow( y, sortBase )
{
    row = spawnstruct();
    row.y = y;

    left = gf_HP_blockLeft( gf_HP_MAX_SKULLS() );

    row.icons = [];
    for ( i = 0; i < gf_HP_MAX_SKULLS(); i++ )
        row.icons[i] = self gf_clCreateIcon( left + i * gf_HP_ICON_STEP(), y, sortBase + 5 );

    // Bar block (reference layout): number above, bar below, both left-aligned at
    // gf_HP_BAR_X. Layering bottom-up: hairline border (1px larger all around),
    // semi-transparent black background, then the team-colored fill.
    barX = gf_HP_BAR_X();
    barY = y + 4;
    // 0.5-unit ring ≈ 1px at 1080p — about the practical floor; sub-unit sizes can
    // round unevenly per side at some resolutions, so check it looks symmetric.
    inX = barX + gf_HP_BAR_INNER_NUDGE();   // bg + fill nudged right to center in the ring
    row.barBorder = self gf_clCreateRect( barX - 0.5, barY, gf_HP_BAR_W() + 1, gf_HP_BAR_H() + 1, ( 0.7, 0.7, 0.7 ), 0.5, sortBase );
    row.barBg     = self gf_clCreateRect( inX,        barY, gf_HP_BAR_W(),     gf_HP_BAR_H(),     ( 0, 0, 0 ),       0.45, sortBase + 1 );
    row.fill      = self gf_clCreateRect( inX,        barY, 1,                 gf_HP_BAR_H(),     ( 1, 1, 1 ),       0,    sortBase + 2 );

    row.number = self gf_clCreateNumber( y - 4, sortBase + 6 );
    return row;
}

// ─── Guarded client element construction ────────────────────────────────────
// newClientHudElem returns undefined when the per-client pool is exhausted, and
// _hud_util's createIcon/createFontString then crash setting fields on undefined —
// killing the whole panel-creation thread partway (symptom: partial chrome, no
// updates). These guarded builders log the exhaustion and let the panel degrade
// gracefully instead.

gf_clNewElem()
{
    elem = newClientHudElem( self );
    if ( !isDefined( elem ) )
        logPrint( "GF_HUD: CLIENT ELEM POOL EXHAUSTED for " + self.name + "\n" );
    return elem;
}

gf_clIcon( shader, w, h )
{
    icon = self gf_clNewElem();
    if ( !isDefined( icon ) )
        return undefined;

    icon.elemType = "icon";
    icon.x = 0;
    icon.y = 0;
    icon.width = w;
    icon.height = h;
    icon.xOffset = 0;
    icon.yOffset = 0;
    icon.children = [];
    icon setParent( level.uiParent );
    icon.hidden = false;
    icon setShader( shader, w, h );
    return icon;
}

gf_clText( font, scale )
{
    t = self gf_clNewElem();
    if ( !isDefined( t ) )
        return undefined;

    t.elemType = "font";
    t.font = font;
    t.fontscale = scale;
    t.x = 0;
    t.y = 0;
    t.width = 0;
    t.height = int( level.fontHeight * scale );
    t.xOffset = 0;
    t.yOffset = 0;
    t.children = [];
    t setParent( level.uiParent );
    t.hidden = false;
    return t;
}

// Debug probe (set gf_debug_elem_probe 1): counts how many client HUD elements are
// still free once the panel is up, by allocating until failure and freeing them.
gf_debugElemProbe()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    wait 9;   // after the loadout intro AND the health panel have both built

    probe = [];
    for ( i = 0; i < 40; i++ )
    {
        e = newClientHudElem( self );
        if ( !isDefined( e ) )
            break;
        probe[probe.size] = e;
    }

    for ( i = 0; i < probe.size; i++ )
        probe[i] destroy();

    self iPrintLnBold( "^3free client HUD elems: " + probe.size );
    logPrint( "GF_HUD: free client elems for " + self.name + " = " + probe.size + "\n" );
}

gf_clCreateFrame( x, y, w, h, shader, alpha, sort )
{
    icon = self gf_clIcon( shader, w, h );
    if ( !isDefined( icon ) )
        return undefined;
    icon setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    icon.color = ( 1, 1, 1 );
    gf_styleHealthElem( icon, sort );
    icon.alpha = alpha;
    self.gf_hudElems[self.gf_hudElems.size] = icon;
    return icon;
}

// Generic solid rectangle (tinted "white" shader). Used for the bar's border, its
// background, and the fill (which is resized each tick via setShader).
gf_clCreateRect( x, y, w, h, color, alpha, sort )
{
    rect = self gf_clIcon( "white", w, h );
    if ( !isDefined( rect ) )
        return undefined;
    rect setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    rect.color = color;
    gf_styleHealthElem( rect, sort );
    rect.alpha = alpha;
    self.gf_hudElems[self.gf_hudElems.size] = rect;
    return rect;
}

gf_clCreateIcon( x, y, sort )
{
    icon = self gf_clIcon( "hud_death_suicide", gf_HP_ICON_SIZE(), gf_HP_ICON_SIZE() );
    if ( !isDefined( icon ) )
        return undefined;
    icon setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    icon.color = ( 1, 1, 1 );
    gf_styleHealthElem( icon, sort );
    icon.alpha = 0;
    self.gf_hudElems[self.gf_hudElems.size] = icon;
    return icon;
}

gf_clCreateNumber( y, sort )
{
    num = self gf_clText( "default", 1.0 );
    if ( !isDefined( num ) )
        return undefined;
    num setPoint( "CENTER LEFT", "CENTER LEFT", 80, y );   // initial x; retargeted just past the skull block each tick
    gf_styleHealthElem( num, sort );
    num.alpha = 0;
    self.gf_hudElems[self.gf_hudElems.size] = num;
    return num;
}

// Park the whole panel off-screen left at FULL opacity. The old version also faded
// alphas 0→target during the slide, which made small elements (numbers, skulls, thin
// bars) read as "fading in at their spot" instead of sliding with the frames. Pure
// slide like the loadout HUD — the park offset is past the widescreen edge so parked
// elements can't be seen.
gf_hideHealthPanelForIntro()
{
    if ( !isDefined( self.gf_hudElems ) )
        return;

    offset = gf_HP_SLIDE_OFFSET();
    for ( i = 0; i < self.gf_hudElems.size; i++ )
        gf_offsetHealthHUDElem( self.gf_hudElems[i], offset, 0 );
}

// Slide everything back to home together over 0.75s — no fade, visible motion on
// every element.
gf_revealHealthPanel()
{
    if ( !isDefined( self.gf_hudElems ) )
        return;

    offset = gf_HP_SLIDE_OFFSET();
    for ( i = 0; i < self.gf_hudElems.size; i++ )
        gf_offsetHealthHUDElem( self.gf_hudElems[i], 0 - offset, 0.75 );
}

gf_updateHealthPanel()
{
    if ( !isDefined( self.gf_rows ) )
        return;

    // Runs for everyone — hides itself while dead/spectating.
    self gf_updateSelfBar();

    team = undefined;
    if ( isDefined( self.pers["team"] ) )
        team = self.pers["team"];

    if ( team == "axis" )
    {
        friendlyTeam = "axis";
        enemyTeam    = "allies";
    }
    else
    {
        // Allies viewer — and also spectators/unassigned, who always see the whole HUD
        // with a fixed mapping: allies in the green row, axis in the red row.
        friendlyTeam = "allies";
        enemyTeam    = "axis";
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

    if ( count > gf_HP_MAX_SKULLS() ) count = gf_HP_MAX_SKULLS();
    if ( alive > gf_HP_MAX_SKULLS() ) alive = gf_HP_MAX_SKULLS();

    // Fixed left anchor: the block always starts where the leftmost skull of a full
    // team would sit, so skulls fill in left-to-right as the team populates instead of
    // re-centering for each count.
    blockLeft = gf_HP_blockLeft( gf_HP_MAX_SKULLS() );

    // Fill: fixed-length bar, fraction of gf_HP_BAR_W. The bg/border stay visible even
    // when the team is dead — an empty bar reads as "wiped".
    if ( isDefined( row.fill ) )
    {
        if ( hp > 0 )
        {
            w = int( gf_HP_BAR_W() * frac + 0.5 );
            if ( w < 1 )
                w = 1;
            row.fill setShader( "white", w, gf_HP_BAR_H() );
            row.fill.color = color;
            row.fill.alpha = 0.9;
        }
        else
        {
            row.fill.alpha = 0;
        }
    }

    gf_setHealthNumber( row.number, hp );

    for ( i = 0; i < gf_HP_MAX_SKULLS(); i++ )
    {
        icon = row.icons[i];
        if ( !isDefined( icon ) )
            continue;
        if ( i >= count )
        {
            icon.alpha = 0;
            continue;
        }
        icon.x = blockLeft + i * gf_HP_ICON_STEP();
        icon.alpha = 0.95;
        if ( i < alive )
            icon.color = color;
        else
            icon.color = ( 1, 1, 1 );
    }
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

gf_setHealthNumber( num, hp )
{
    if ( !isDefined( num ) )
        return;

    if ( hp > 0 )
    {
        // White, left-aligned with the bar below it (reference-image layout). The bar
        // fill color carries the team identity; the number stays neutral.
        // setValue, NOT setText: setText burns engine configstring slots and the table
        // survives map_restart — repeated per-tick setText overflows it over a session,
        // after which every setText throws and kills the calling thread.
        num setValue( int( hp ) );
        num.x = gf_HP_BAR_X();
        num.color = ( 1, 1, 1 );
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

        // Only players who spawned into THIS round count. Excludes mid-round joiners who
        // are team-assigned but spectating — they'd inflate stats.max and halve the bar.
        if ( !isDefined( player.pers["gf_spawnedRound"] ) || player.pers["gf_spawnedRound"] != game["roundsplayed"] )
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

    // Cue the health panel to build + slide in now that the intro freed its pool slots.
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

// ─── Damage popup ────────────────────────────────────────────────────────────
// Mod-owned replacement for _rank::updateRankScoreHUD. The stock popup batches
// into self.rankUpdateTotal, which only resets when a popup finishes its full 1s
// display — any interrupted popup (next kill, killcam transition) leaves a stale
// total that inflates the next number, and its shared hud element can silently
// fail. This one owns its element and shows exactly what it is given; amounts
// arriving within the display window stack, and the total expires by timestamp
// so it can never go stale.

gf_showDamagePopup( amount )
{
    self endon( "disconnect" );

    if ( !isDefined( self.gf_dmgPopup ) )
    {
        elem = newClientHudElem( self );
        elem.horzAlign = "center";
        elem.vertAlign = "middle";
        elem.alignX    = "center";
        elem.alignY    = "middle";
        elem.x         = 0;
        elem.y         = -60;
        elem.font      = "default";
        elem.fontscale = 2.0;
        elem.archived  = false;
        elem.sort      = 50;
        elem.color     = ( 1, 1, 0.5 );
        elem.alpha     = 0;
        elem.overrridewhenindemo = true;   // keep visible during the round-end killcam
        elem maps\mp\gametypes\_hud::fontPulseInit();
        self.gf_dmgPopup = elem;
    }

    now = getTime();
    if ( !isDefined( self.gf_dmgPopupExpire ) || now > self.gf_dmgPopupExpire )
        self.gf_dmgPopupTotal = 0;
    self.gf_dmgPopupTotal += amount;
    self.gf_dmgPopupExpire = now + 1000;

    self notify( "gf_dmg_popup" );
    self endon( "gf_dmg_popup" );

    self.gf_dmgPopup.label = &"MP_PLUS";
    self.gf_dmgPopup setValue( self.gf_dmgPopupTotal );
    self.gf_dmgPopup.alpha = 0.85;
    self.gf_dmgPopup thread maps\mp\gametypes\_hud::fontPulse( self );

    wait 1;
    self.gf_dmgPopup fadeOverTime( 0.75 );
    self.gf_dmgPopup.alpha = 0;
}
