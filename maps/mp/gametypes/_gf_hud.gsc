// Gunfight HUD
//
// The Health HUD is CLIENT-SIDE (newClientHudElem), built per player in the player's own thread
// (the Loadout HUD is now fully menu-rendered — see below). This is deliberate: T5 server team-HUD
// elements (newTeamHudElem) do NOT live-update their text/alpha/color mid-round — the
// change only flushes to clients on a round transition — and client elements created
// from a level thread never network at all. So per-player + player-thread is the only
// pattern that updates reliably during a round.
//
// Health HUD:
//   - Level thread gf_startHealthHUD() ONLY computes the team totals (HP / fill
//     fraction / player count / alive count) and publishes them to level.gf_* vars.
//   - Each player runs gf_runHealthHUD() (singleton via self notify/endon), which
//     builds the panel (faction frame + 2 team bars + skull icons + HP numbers), cross-
//     fades it in, and updates it every 0.1s from the published vars. Row 0 = own team
//     (green), row 1 = enemy (red). map_restart wipes the panel between rounds; it's
//     recreated on the next spawn.
//
// Loadout HUD: gf_showWeaponHUD() pushes a centered-column create-a-class overview
//   (primary, secondary, 3 equipment, 3 perks — each icon + bracket + name) that is
//   fully MENU-rendered (ui_mp/hud_gf_health.menu, ui_gf_lo_* dvars). It uses ZERO
//   client hudelems, so it can't hit the ~17 drawn-per-player render cap and never
//   touches setText/configstrings. The slide is driven by ui_gf_lo_off.

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
// Row 0 = own team (green), row 1 = enemy (red). Everything cross-fades in together.

// Row y is the SKULL center; the strip hangs 6 below, so the combined block's visual
// center is ~y+2. These are pre-shifted up 2 so the block centers on the background
// band art (which was tuned around -45/-27).
gf_HP_ROW0_Y()       { return -47; }
gf_HP_ROW1_Y()       { return -27; }

// Whole-panel vertical offset (applied to frames + rows at creation). Negative = up.
// -40 parks the panel just below the minimap instead of at mid-screen-left.
gf_HP_PANEL_Y_OFF()  { return -40; }

// Skull icon size (square). blockWidth derives from this + the pitch.
gf_HP_ICON_SIZE()    { return 10; }

// Shared spawn-in reveal duration. The health panel slide, the loadout overview
// slide+fade, and the self bar slide all animate over this so they reveal in sync.
// Both panels are kicked off on spawn, so equal duration = synced. Tune here (GSC
// rawfile — map_restart, no mod.ff rebuild).
gf_REVEAL_TIME() { return 0.6; }

// The loadout overview is now fully menu-rendered (0 client hudelems), so it no longer competes with
// the health panel for the ~17 drawn-per-player client-hudelem render cap. The panel is therefore
// built IMMEDIATELY on spawn and coexists with the loadout intro — no more waiting for the intro to
// finish (that wait was only needed when the intro was ~18 client hudelems). This also removes the
// ~6s post-round window where the panel was absent during the intro.
gf_runHealthHUD()
{
    self notify( "gf_kill_health_hud" );
    self gf_destroyHealthPanel();
    self endon( "gf_kill_health_hud" );
    self endon( "disconnect" );

    self setClientDvar( "ui_gf_hp_alpha", 0 );   // menu chrome (border + self bar) starts invisible; reveal fades it in

    gf_updateHealthHUD();              // seed the published totals
    self gf_createHealthPanel();       // build now — loadout HUD is menu-rendered, no client-elem conflict
    self gf_updateHealthPanel();       // fill values + target alphas in before revealing
    self gf_hideHealthPanelForIntro(); // park off-screen (full opacity)
    self gf_revealHealthPanel();       // slide in — all elements move together, synced with loadout
    self thread gf_hidePanelChromeOnRoundEnd();   // hide menu border in sync with the round-end wipe
    wait gf_REVEAL_TIME();             // let the reveal finish before the loop retargets

    for ( ;; )
    {
        self gf_updateHealthPanel();
        wait 0.1;
    }
}

gf_createHealthPanel()
{
    // FULLY MENU-RENDERED now (ui_mp/hud_gf_health.menu): bg fade + border + every skull / bar /
    // number is a menu itemDef driven by per-client dvars (ui_gf_panel_*, ui_gf_rN_*, ui_gf_hp_alpha).
    // ZERO client hudelems. The panel used to be 17 client hudelems, and ALL hudelem types share one
    // global per-client DRAWN cap (~17-20) — so the panel + stock HUD + score popup + overtime flag
    // objpoint together blew past it, silently starving the popup and flag (they only appeared once
    // the round-end teardown freed slots). Menu items are a separate rendering system, exempt from
    // that cap, so moving the panel there frees the whole budget. Enemy-team data is fine to show:
    // it's computed server-side (gf_updateHealthHUD) and pushed per-client via setClientDvar — the
    // client only displays a server-pushed value, it never reads enemy health itself.
    self.gf_panelActive = true;
    self.gf_dvarCache = [];               // force the first per-row push to send

    self setClientDvar( "ui_gf_self_name", self.name );
    self.gf_sbHp = undefined;
    self.gf_sbShow = undefined;

    self gf_pushPanelChrome();            // ui_gf_panel_x/y — the border-box anchor the menu lays out from

    logPrint( "GF_HUD: menu panel activated for " + self.name + "\n" );
}

// Seeds the menu-rendered panel chrome position (hud_gf_health.menu reads these). bg fade + border
// lines are drawn by the menu at ZERO client-hudelem cost. ui_gf_panel_x/y = border-box top-left in
// menu/screen space; the menu lays the bg fade and the 4 lines out relative to that point. Tunable
// here with a map_restart only (no mod.ff rebuild — only the menu STRUCTURE needs the linker).
// ui_gf_panel_show (set in reveal/destroy) gates visibility.
gf_pushPanelChrome()
{
    self setClientDvar( "ui_gf_panel_x", -22 );   // border-box left
    self setClientDvar( "ui_gf_panel_y", 142 );   // border-box top

    // Material names pushed as dvars so the menu uses exp material(dvarString(...)) — a DYNAMIC
    // (runtime-resolved) material reference. A static background "hud_..." makes the linker try to
    // bundle the image (.iwi missing → build error); dynamic resolves from base fastfiles at runtime.
    self setClientDvar( "ui_gf_skull_mat", "hud_death_suicide" );        // alive/dead skull icon
    self setClientDvar( "ui_gf_fade_mat",  "hud_frame_faction_fade" );   // soft panel bg fade
}

// The bg fade + rows are client hudelems wiped instantly by map_restart at round end, but the
// menu-rendered border (gated by ui_gf_panel_show) would otherwise linger until the NEXT spawn's
// gf_destroyHealthPanel. gf_endRound fires "gf_round_over" just before that wipe, so hide the
// border there to keep it in sync. gf_revealHealthPanel re-shows it with the rows next round.
gf_hidePanelChromeOnRoundEnd()
{
    self endon( "disconnect" );
    self endon( "gf_kill_health_hud" );

    level waittill( "gf_round_over" );
    self setClientDvar( "ui_gf_panel_show", 0 );
}

// Row layout (reference-image style): up to 4 skull icons (4v4 support) on the left,
// then a fixed column with the white HP number on top and the health bar underneath.
// Skulls fill in left-to-right as the team populates; the number/bar column is fixed at
// gf_HP_BAR_X so both rows stay aligned regardless of team size. The bar = hairline
// border + semi-transparent black background + team-colored fill (green/red).
gf_HP_MAX_SKULLS()   { return 4; }
gf_HP_ICON_STEP()    { return 13; }   // integer pitch — fractional steps round to uneven pixel gaps
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
// Runs over gf_REVEAL_TIME() to match the panel/loadout reveals (synced spawn-in).
gf_slideSelfBarIn()
{
    self notify( "gf_sb_slide" );
    self endon( "gf_sb_slide" );
    self endon( "disconnect" );

    // INTRO ANIM DISABLED (snap in): was a slide of ui_gf_self_off 40->0 over gf_REVEAL_TIME().
    self setClientDvar( "ui_gf_self_off", 0 );
    self setClientDvar( "ui_gf_self_show", 1 );
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

// Debug probe (set gf_debug_elem_probe 1): counts client HUD elems that can still be ALLOCATED.
// WARNING: this is the allocation pool only (~900+ free) — it is NOT the binding limit. T5 silently
// stops DRAWING client hudelems past ~17/player, and that render cap is invisible to allocation
// (and to .alpha/.x). For the real budget watch the HUD pool overlay's DRAWN counter
// (gf_debug_hud_pool). Kept only as an allocation sanity check.
gf_debugElemProbe()
{
    self endon( "disconnect" );
    level endon( "game_ended" );

    wait 9;   // after the loadout intro AND the health panel have both built

    panelUsed = 0;
    if ( isDefined( self.gf_hudElems ) )
        panelUsed = self.gf_hudElems.size;

    // Allocate plain client HUD elems until the pool runs out, then free them. No on-screen grid:
    // the grid was misleading (it implied the alloc count was meaningful, but only ~17 of those
    // would actually DRAW). This just confirms the allocation pool is huge (it is).
    probe = [];
    for ( i = 0; i < 1024; i++ )
    {
        e = newClientHudElem( self );
        if ( !isDefined( e ) )
            break;
        probe[probe.size] = e;
    }

    for ( i = 0; i < probe.size; i++ )
        probe[i] destroy();

    free = probe.size;
    self iPrintLnBold( "^3ALLOC free: ^2" + free + " ^7(pool only — NOT the ~17 DRAWN cap)" );
    logPrint( "GF_HUD: alloc probe for " + self.name + " - panelUsed=" + panelUsed
              + " allocFree=" + free + " (allocation pool, not the render cap)\n" );
}

gf_clCreateFrame( x, y, w, h, shader, color, alpha, sort )
{
    icon = self gf_clIcon( shader, w, h );
    if ( !isDefined( icon ) )
        return undefined;
    icon setPoint( "CENTER LEFT", "CENTER LEFT", x, y );
    icon.color = color;
    gf_styleHealthElem( icon, sort );
    icon.alpha = alpha;
    self.gf_hudElems[self.gf_hudElems.size] = icon;
    return icon;
}

// Panel framing lines drawn from thin "white" rects, replacing the stock hud_frame_faction_lines so
// we control alignment exactly. Layout: a LEFT vertical cap + three horizontal rules (top, middle,
// bottom) and NO right line, so the panel reads as open/anchored on the left. The middle rule runs
// between the two team rows (at cy). Rects are added to self.gf_hudElems by gf_clCreateRect, so they
// slide in and tear down with the rest of the panel. Same element count as the old 4-side box.
gf_clCreatePanelLines( cx, cy, w, h, thick, color, alpha, sort )
{
    left = cx - w / 2;
    self gf_clCreateRect( left, cy - h / 2,     w,     thick, color, alpha, sort );   // top
    self gf_clCreateRect( left, cy,             w,     thick, color, alpha, sort );   // middle divider (between rows)
    self gf_clCreateRect( left, cy + h / 2 - 1, w,     thick, color, alpha, sort );   // bottom (1px up to sit flush)
    self gf_clCreateRect( left, cy,             thick, h,     color, alpha, sort );   // left vertical cap (no right)
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

// Fade reveal: capture each element's target alpha, then hide it (alpha 0) AT its home
// position. gf_revealHealthPanel fades each back to its captured target over the shared
// reveal time, in sync with the loadout overview and the menu-rendered chrome. (Earlier
// this parked the panel off-screen for a pure slide; the user asked for a cross-fade.)
gf_hideHealthPanelForIntro()
{
    self setClientDvar( "ui_gf_hp_alpha", 0 );   // panel starts invisible; reveal fades it in
}

// Cross-fade the whole panel in: every client-hudelem piece fades 0 -> its captured
// target alpha, and the menu-rendered chrome (border + self bar) fades via ui_gf_hp_alpha
// — both over gf_REVEAL_TIME(), so the health HUD and loadout overview reveal in sync.
gf_revealHealthPanel()
{
    self setClientDvar( "ui_gf_panel_show", 1 );
    // INTRO ANIM DISABLED (snap in) — testing whether the HUD just being there on spawn looks cleaner.
    // Was: self thread gf_fadeDvar( "ui_gf_hp_alpha", 0, 1, gf_REVEAL_TIME() );
    self setClientDvar( "ui_gf_hp_alpha", 1 );
}

// Linear fade of a client dvar from->to over dur (0.05s frames) — cross-fades the menu-
// rendered health chrome (border + self bar) via ui_gf_hp_alpha, matching the client
// panel's fadeOverTime and the loadout fade.
gf_fadeDvar( dvarName, from, to, dur )
{
    self notify( "gf_fade_" + dvarName );
    self endon( "gf_fade_" + dvarName );
    self endon( "disconnect" );

    steps = int( dur / 0.05 );
    if ( steps < 1 )
        steps = 1;

    self setClientDvar( dvarName, from );
    for ( i = 1; i <= steps; i++ )
    {
        wait 0.05;
        self setClientDvar( dvarName, from + ( to - from ) * i / steps );
    }
    self setClientDvar( dvarName, to );
}

gf_updateHealthPanel()
{
    if ( !isDefined( self.gf_panelActive ) )
        return;

    // Self bar (its own menu dvars); hides itself while dead/spectating.
    self gf_updateSelfBar();

    // Row 0 = friendly (green in the menu), row 1 = enemy (red). The viewer's own team maps to row 0,
    // so spectators/unassigned get a fixed allies=green / axis=red layout. Data is server-side
    // (level.gf_*) and pushed per-client, so the viewer sees BOTH teams — enemy included.
    friendlyTeam = "allies";
    enemyTeam    = "axis";
    if ( isDefined( self.pers["team"] ) && self.pers["team"] == "axis" )
    {
        friendlyTeam = "axis";
        enemyTeam    = "allies";
    }

    self gf_pushHealthRow( 0, friendlyTeam );
    self gf_pushHealthRow( 1, enemyTeam );
}

// Push one row's data (hp number, bar fill width, skull count, alive count) as per-client dvars the
// menu reads. The menu fixes row 0 = green, row 1 = red, so colour isn't pushed. Fill width is in
// pixels (0..gf_HP_BAR_W) so the menu just does exp rect W( dvar ).
gf_pushHealthRow( r, team )
{
    hp    = gf_readTeamHP( team );
    frac  = gf_readTeamFrac( team );
    count = gf_readTeamCount( team );
    alive = gf_readTeamAlive( team );

    if ( count > gf_HP_MAX_SKULLS() ) count = gf_HP_MAX_SKULLS();
    if ( alive > gf_HP_MAX_SKULLS() ) alive = gf_HP_MAX_SKULLS();

    fw = int( gf_HP_BAR_W() * frac + 0.5 );
    if ( hp <= 0 )
        fw = 0;
    else if ( fw < 1 )
        fw = 1;

    self gf_setRowDvar( "ui_gf_r" + r + "_hp",    int( hp ) );
    self gf_setRowDvar( "ui_gf_r" + r + "_fw",    fw );
    self gf_setRowDvar( "ui_gf_r" + r + "_cnt",   count );
    self gf_setRowDvar( "ui_gf_r" + r + "_alive", alive );
}

// setClientDvar only on change (cached on self) — the 0.1s update loop would otherwise spam 8
// pushes/tick. gf_createHealthPanel resets gf_dvarCache so the first push each spawn always sends.
gf_setRowDvar( name, val )
{
    if ( !isDefined( self.gf_dvarCache ) )
        self.gf_dvarCache = [];
    if ( isDefined( self.gf_dvarCache[name] ) && self.gf_dvarCache[name] == val )
        return;
    self.gf_dvarCache[name] = val;
    self setClientDvar( name, val );
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
        // Team wiped — show a literal 0 instead of hiding the number, so the panel
        // reads "0" next to the empty bar rather than going blank.
        num setValue( 0 );
        num.x = gf_HP_BAR_X();
        num.color = ( 1, 1, 1 );
        num.alpha = 1;
    }
}

gf_destroyHealthPanel()
{
    self setClientDvar( "ui_gf_panel_show", 0 );   // hide menu-rendered chrome with the panel

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

// ─── Loadout HUD ─────────────────────────────────────────────────────────────

gf_showWeaponHUD( load )
{
    if ( !isDefined( load ) )
        return;

    self notify( "gf_kill_loadout_hud" );
    self endon( "gf_kill_loadout_hud" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    // The loadout overview is fully MENU-rendered (ui_mp/hud_gf_health.menu): a
    // centered-column create-a-class summary — big primary, secondary, a 3-across
    // equipment row, a 3-across perk row, each item icon + bracket + name. It costs
    // ZERO client hudelems (no createIcon/createFontString, no setText), so it can't
    // hit T5's ~17 drawn-per-player render cap or burn the configstring table the old
    // client-elem version risked. We push the 8 icon materials + 8 names + the anchor,
    // then animate the unified slide via ui_gf_lo_off (added to every item's X).

    // Icons (materials). All precached — weapons/equipment in gf.gsc, perks in stock
    // _class.gsc:421 — so the menu's material(dvarString) resolves every one.
    self setClientDvar( "ui_gf_lo_icon0", load["primaryShader"] );
    self setClientDvar( "ui_gf_lo_icon1", load["secondaryShader"] );
    self setClientDvar( "ui_gf_lo_icon2", load["lethalShader"] );
    self setClientDvar( "ui_gf_lo_icon3", load["tacticalShader"] );
    self setClientDvar( "ui_gf_lo_icon4", load["equipShader"] );
    self setClientDvar( "ui_gf_lo_icon5", gf_getPerkShader( "specialty_flakjacket" ) );    // Flak Jacket
    self setClientDvar( "ui_gf_lo_icon6", gf_getPerkShader( "specialty_longersprint" ) );   // Marathon
    self setClientDvar( "ui_gf_lo_icon7", gf_getPerkShader( "specialty_movefaster" ) );     // Lightweight

    // Names (plain client dvars — NOT setText, so no configstring exhaustion).
    self setClientDvar( "ui_gf_lo_name0", load["primaryName"] );
    self setClientDvar( "ui_gf_lo_name1", load["secondaryName"] );
    self setClientDvar( "ui_gf_lo_name2", load["lethalName"] );
    self setClientDvar( "ui_gf_lo_name3", load["tacticalName"] );
    self setClientDvar( "ui_gf_lo_name4", load["equipName"] );
    self setClientDvar( "ui_gf_lo_name5", "Flak Jacket" );
    self setClientDvar( "ui_gf_lo_name6", "Marathon" );
    self setClientDvar( "ui_gf_lo_name7", "Lightweight" );

    // Anchor: center-right column. cx = column center (px left of the right safe
    // edge), cy = block vertical center (px from the reticle). Both retune live with
    // a map_restart — no mod.ff rebuild (only the item sizes/spacing are baked in).
    self setClientDvar( "ui_gf_lo_cx", -104 );
    self setClientDvar( "ui_gf_lo_cy", -6 );

    // INTRO ANIM DISABLED (snap in) — testing whether the HUD just being there on spawn looks cleaner.
    // Was: self gf_slideLoadout( 70, 0, 0, 1, gf_REVEAL_TIME() );  // slide+fade in. Outro below is kept.
    self setClientDvar( "ui_gf_lo_off", 0 );
    self setClientDvar( "ui_gf_lo_alpha", 1 );
    self setClientDvar( "ui_gf_lo_show", 1 );

    wait 7;

    // Slide back out + fade (off 0 -> 70, alpha 1 -> 0) over 0.5s. The intro is a snap now, so this
    // is the only loadout animation left.
    self gf_slideLoadout( 0, 70, 1, 0, 0.5 );
    self setClientDvar( "ui_gf_lo_show", 0 );
}

// Linear slide+fade of the overview over `dur` seconds (0.05s frames). The menu
// adds ui_gf_lo_off to every item's X and multiplies ui_gf_lo_alpha into every
// item's alpha, so this drives the whole block in/out as one. The fade masks the
// 20Hz stepping that made a long pure-slide look choppy. ui_gf_lo_show is raised on
// the first frame so the block is never seen parked. ui_gf_lo_off is kept FRACTIONAL
// (no int() rounding) so each 20Hz step moves an equal distance — int() truncation
// made the steps alternate (e.g. 4px,3px,4px,3px) and read as extra stutter.
gf_slideLoadout( offFrom, offTo, alphaFrom, alphaTo, dur )
{
    steps = int( dur / 0.05 );
    if ( steps < 1 )
        steps = 1;

    self setClientDvar( "ui_gf_lo_off", offFrom );
    self setClientDvar( "ui_gf_lo_alpha", alphaFrom );
    self setClientDvar( "ui_gf_lo_show", 1 );

    for ( i = 1; i <= steps; i++ )
    {
        wait 0.05;
        frac = i / steps;
        self setClientDvar( "ui_gf_lo_off",   offFrom   + ( offTo - offFrom ) * frac );
        self setClientDvar( "ui_gf_lo_alpha", alphaFrom + ( alphaTo - alphaFrom ) * frac );
    }

    self setClientDvar( "ui_gf_lo_off",   offTo );
    self setClientDvar( "ui_gf_lo_alpha", alphaTo );
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
    // The overview is menu-rendered now (no client hudelems), so teardown is just
    // hiding it. The legacy client-elem cleanup is kept to tolerate any stale state.
    if ( isDefined( self.gf_loadoutHudElems ) )
    {
        for ( i = 0; i < self.gf_loadoutHudElems.size; i++ )
            if ( isDefined( self.gf_loadoutHudElems[i] ) )
                self.gf_loadoutHudElems[i] destroyElem();
        self.gf_loadoutHudElems = undefined;
    }

    self setClientDvar( "ui_gf_lo_show", 0 );
}

// ─── Score popup ─────────────────────────────────────────────────────────────
// "Elimination" / "Assist" center-screen popup. Reuses the ENGINE'S own score popup element
// (self.hud_rankscroreupdate, a NewScoreHudElem created at _rank spawn init) so it matches the stock
// yellow score popup EXACTLY — same font / scale / glow / fontPulse — AND renders at any lobby size:
// NewScoreHudElem is a dedicated score-element pool, NOT the newClientHudElem pool with the ~17
// per-player DRAWN render cap (our old lazily-created client hudelem hit that cap and vanished as the
// lobby grew). The mod sets score with the popup suppressed (zeroed kill/assist values + a no-popup
// score setter), so the stock rank popup never fires on its own — the element is free to reuse.
// popupType: 2 = elimination, 1 = assist. pri keeps Elimination from being stomped by Assist.
// SIZE knob: gf_popupSize() (resting fontscale). It's applied via baseFontScale/maxFontScale, NOT
// .fontscale — fontPulse (_hud.gsc) always animates the element back to baseFontScale, so a plain
// .fontscale set is immediately overwritten by the pulse.
gf_popupSize() { return 1.5; }   // popup resting fontscale (the engine stock score popup is 2.0)
gf_popupX()    { return 170; }   // horizontal offset from screen centre (+ = right; element is centre-aligned)
gf_popupY()    { return 0; }     // vertical offset from screen centre (+ = down, - = up; 0 = middle screen)

gf_showScorePopup( popupType, pri )
{
    self endon( "disconnect" );

    if ( !isDefined( pri ) )
        pri = 1;

    now = getTime();
    if ( isDefined( self.gf_popupExpire ) && now < self.gf_popupExpire
        && isDefined( self.gf_popupPri ) && self.gf_popupPri > pri )
        return;   // higher-priority popup still on screen — don't stomp it

    self.gf_popupPri    = pri;
    self.gf_popupExpire = now + 1000;

    self gf_ensureScorePopupElem();

    text = &"GF_POPUP_ASSIST";
    if ( popupType == 2 )
        text = &"GF_POPUP_ELIMINATION";

    self notify( "update_score" );   // cancel any in-flight stock rank popup sharing this element
    self notify( "gf_dmg_popup" );
    self endon( "gf_dmg_popup" );

    self.hud_rankscroreupdate.label = &"";
    self.hud_rankscroreupdate.color = ( 1, 1, 0.5 );
    self.hud_rankscroreupdate.baseFontScale = gf_popupSize();       // resting size — fontPulse returns here
    self.hud_rankscroreupdate.maxFontScale  = gf_popupSize() * 2;   // pulse peak (stock 2x ratio)
    self.hud_rankscroreupdate.fontScale     = gf_popupSize();       // start the pulse from the resting size
    self.hud_rankscroreupdate.x             = gf_popupX();          // shift right of centre
    self.hud_rankscroreupdate.y             = gf_popupY();          // vertical position (0 = middle screen)
    self.hud_rankscroreupdate setText( text );
    self.hud_rankscroreupdate.alpha = 0.85;
    self.hud_rankscroreupdate thread maps\mp\gametypes\_hud::fontPulse( self );

    wait 1;
    self.hud_rankscroreupdate fadeOverTime( 0.75 );
    self.hud_rankscroreupdate.alpha = 0;
}

// The engine's _rank::onPlayerSpawned makes self.hud_rankscroreupdate on spawn; mirror that creation
// as a fallback so the popup works even if that init didn't run for this player. NewScoreHudElem is
// the dedicated score-element pool (render-cap-exempt). Matches the stock properties verbatim.
gf_ensureScorePopupElem()
{
    if ( isDefined( self.hud_rankscroreupdate ) )
        return;

    self.hud_rankscroreupdate = NewScoreHudElem( self );
    self.hud_rankscroreupdate.horzAlign = "center";
    self.hud_rankscroreupdate.vertAlign = "middle";
    self.hud_rankscroreupdate.alignX    = "center";
    self.hud_rankscroreupdate.alignY    = "middle";
    self.hud_rankscroreupdate.x         = 0;
    self.hud_rankscroreupdate.y         = -60;
    self.hud_rankscroreupdate.font      = "default";
    self.hud_rankscroreupdate.fontscale = 2.0;
    self.hud_rankscroreupdate.archived  = false;
    self.hud_rankscroreupdate.color     = ( 1, 1, 0.5 );
    self.hud_rankscroreupdate.alpha     = 0;
    self.hud_rankscroreupdate.sort      = 50;
    self.hud_rankscroreupdate maps\mp\gametypes\_hud::fontPulseInit();
    self.hud_rankscroreupdate.overrridewhenindemo = true;
}
