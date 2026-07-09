#include maps\mp\gametypes\_hud_util;

gf_startHealthHUD()
{
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

    level.gf_hpAllies    = alliesStats.current;
    level.gf_hpAxis      = axisStats.current;
    level.gf_fracAllies  = gf_getHealthFraction( alliesStats.current, alliesStats.max );
    level.gf_fracAxis    = gf_getHealthFraction( axisStats.current,   axisStats.max );
    level.gf_cntAllies   = alliesStats.players.size;
    level.gf_aliveAllies = alliesStats.alive;
    level.gf_cntAxis     = axisStats.players.size;
    level.gf_aliveAxis   = axisStats.alive;

    level.gf_dbg_alliesHP = alliesStats.current;
    level.gf_dbg_alliesN  = alliesStats.players.size;
    level.gf_dbg_axisHP   = axisStats.current;
    level.gf_dbg_axisN    = axisStats.players.size;
}

gf_REVEAL_TIME() { return 0.6; }

gf_hudRevealStagger()
{
    return ( self getEntityNumber() % 6 ) * 0.05;
}

gf_runHealthHUD()
{
    self notify( "gf_kill_health_hud" );
    self gf_destroyHealthPanel();
    self endon( "gf_kill_health_hud" );
    self endon( "disconnect" );

    staggerDelay = self gf_hudRevealStagger();
    if ( staggerDelay > 0 )
        wait staggerDelay;

    self setClientDvar( "ui_gf_hp_alpha", 0 );

    gf_updateHealthHUD();
    self gf_createHealthPanel();
    self gf_updateHealthPanel();
    self gf_hideHealthPanelForIntro();
    self gf_revealHealthPanel();
    self thread gf_hidePanelChromeOnRoundEnd();
    wait gf_REVEAL_TIME();

    for ( ;; )
    {
        self gf_updateHealthPanel();
        wait 0.1;
    }
}

gf_createHealthPanel()
{
    self.gf_panelActive = true;
    self.gf_dvarCache = [];

    self setClientDvar( "ui_gf_self_name", self.name );
    self.gf_sbHp = undefined;
    self.gf_sbShow = undefined;

    self gf_pushPanelChrome();
}

gf_pushPanelChrome()
{
    self setClientDvar( "ui_gf_panel_x", -22 );
    self setClientDvar( "ui_gf_panel_y", 142 );

    self setClientDvar( "ui_gf_skull_mat", "hud_death_suicide" );
    self setClientDvar( "ui_gf_fade_mat",  "hud_frame_faction_fade" );
}

gf_hidePanelChromeOnRoundEnd()
{
    self endon( "disconnect" );
    self endon( "gf_kill_health_hud" );

    level waittill( "gf_round_over" );
    self setClientDvar( "ui_gf_panel_show", 0 );
}

gf_HP_BAR_W() { return 45; }

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
            self thread gf_slideSelfBarIn();
        else
            self setClientDvar( "ui_gf_self_show", 0 );
    }
}

gf_slideSelfBarIn()
{
    self notify( "gf_sb_slide" );
    self endon( "gf_sb_slide" );
    self endon( "disconnect" );

    self setClientDvar( "ui_gf_self_off", 0 );
    self setClientDvar( "ui_gf_self_show", 1 );
}

gf_hideHealthPanelForIntro()
{
    self setClientDvar( "ui_gf_hp_alpha", 0 );
}

gf_revealHealthPanel()
{
    self setClientDvar( "ui_gf_panel_show", 1 );
    self setClientDvar( "ui_gf_hp_alpha", 1 );
}

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

    self gf_updateSelfBar();

    friendlyTeam = "allies";
    enemyTeam    = "axis";
    if ( isDefined( self.pers["team"] ) && self.pers["team"] == "axis" )
    {
        friendlyTeam = "axis";
        enemyTeam    = "allies";
    }

    hpMode = 0;
    if ( gf_readTeamCount( friendlyTeam ) > 4 || gf_readTeamCount( enemyTeam ) > 4 )
        hpMode = 1;
    self gf_setRowDvar( "ui_gf_hp_mode", hpMode );

    self gf_pushHealthRow( 0, friendlyTeam );
    self gf_pushHealthRow( 1, enemyTeam );
}

gf_pushHealthRow( r, team )
{
    hp    = gf_readTeamHP( team );
    frac  = gf_readTeamFrac( team );
    count = gf_readTeamCount( team );
    alive = gf_readTeamAlive( team );

    fw = int( gf_HP_BAR_W() * frac + 0.5 );
    if ( hp <= 0 )
        fw = 0;
    else if ( fw < 1 )
        fw = 1;

    self gf_setRowDvar( "ui_gf_r" + r + "_hp",         int( hp ) );
    self gf_setRowDvar( "ui_gf_r" + r + "_fw",         fw );
    self gf_setRowDvar( "ui_gf_r" + r + "_cnt",        count );
    self gf_setRowDvar( "ui_gf_r" + r + "_alive",      alive );
    self gf_setRowDvar( "ui_gf_r" + r + "_alivecount", "Alive: " + alive );
}

gf_setRowDvar( name, val )
{
    if ( !isDefined( self.gf_dvarCache ) )
        self.gf_dvarCache = [];
    if ( isDefined( self.gf_dvarCache[name] ) && self.gf_dvarCache[name] == val )
        return;
    self.gf_dvarCache[name] = val;
    self setClientDvar( name, val );
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

gf_destroyHealthPanel()
{
    self setClientDvar( "ui_gf_panel_show", 0 );
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

gf_showWeaponHUD( load )
{
    if ( !isDefined( load ) )
        return;

    self notify( "gf_kill_loadout_hud" );
    self endon( "gf_kill_loadout_hud" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    staggerDelay = self gf_hudRevealStagger();
    if ( staggerDelay > 0 )
        wait staggerDelay;

    self setClientDvar( "ui_gf_lo_icon0", load["primaryShader"] );
    self setClientDvar( "ui_gf_lo_icon1", load["secondaryShader"] );
    self setClientDvar( "ui_gf_lo_icon2", load["lethalShader"] );
    self setClientDvar( "ui_gf_lo_icon3", load["tacticalShader"] );
    self setClientDvar( "ui_gf_lo_icon4", load["equipShader"] );
    self setClientDvar( "ui_gf_lo_icon5", gf_getPerkShader( "specialty_flakjacket" ) );
    self setClientDvar( "ui_gf_lo_icon6", gf_getPerkShader( "specialty_longersprint" ) );
    self setClientDvar( "ui_gf_lo_icon7", gf_getPerkShader( "specialty_movefaster" ) );

    if ( load["secondaryShader"] == "hud_death_suicide" )
        self setClientDvar( "ui_gf_lo_w1", 36 );
    else
        self setClientDvar( "ui_gf_lo_w1", 72 );

    self setClientDvar( "ui_gf_lo_name0", load["primaryName"] );
    self setClientDvar( "ui_gf_lo_name1", load["secondaryName"] );
    self setClientDvar( "ui_gf_lo_name2", load["lethalName"] );
    self setClientDvar( "ui_gf_lo_name3", load["tacticalName"] );
    self setClientDvar( "ui_gf_lo_name4", load["equipName"] );
    self setClientDvar( "ui_gf_lo_name5", "Flak Jacket" );
    self setClientDvar( "ui_gf_lo_name6", "Marathon" );
    self setClientDvar( "ui_gf_lo_name7", "Lightweight" );

    self setClientDvar( "ui_gf_lo_cx", -104 );
    self setClientDvar( "ui_gf_lo_cy", -6 );

    self setClientDvar( "ui_gf_lo_off", 0 );
    self setClientDvar( "ui_gf_lo_alpha", 1 );
    self setClientDvar( "ui_gf_lo_show", 1 );

    wait 8;

    self gf_slideLoadout( 0, 70, 1, 0, 0.5 );
    self setClientDvar( "ui_gf_lo_show", 0 );
}

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
    if ( isDefined( self.gf_loadoutHudElems ) )
    {
        for ( i = 0; i < self.gf_loadoutHudElems.size; i++ )
            if ( isDefined( self.gf_loadoutHudElems[i] ) )
                self.gf_loadoutHudElems[i] destroyElem();
        self.gf_loadoutHudElems = undefined;
    }

    self setClientDvar( "ui_gf_lo_show", 0 );
}

gf_popupSize() { return 1.5; }
gf_popupX()    { return 170; }
gf_popupY()    { return 0; }

gf_showScorePopup( popupType, pri )
{
    self endon( "disconnect" );

    if ( !isDefined( pri ) )
        pri = 1;

    now = getTime();
    if ( isDefined( self.gf_popupExpire ) && now < self.gf_popupExpire
        && isDefined( self.gf_popupPri ) && self.gf_popupPri > pri )
        return;

    self.gf_popupPri    = pri;
    self.gf_popupExpire = now + 1000;

    self gf_ensureScorePopupElem();

    text = &"GF_POPUP_ASSIST";
    if ( popupType == 2 )
        text = &"GF_POPUP_ELIMINATION";

    self notify( "gf_dmg_popup" );
    self endon( "gf_dmg_popup" );

    self.gf_popupElem.label = &"";
    self.gf_popupElem.color = ( 1, 1, 0.5 );
    self.gf_popupElem.baseFontScale = gf_popupSize();
    self.gf_popupElem.maxFontScale  = gf_popupSize() * 2;
    self.gf_popupElem.fontScale     = gf_popupSize();
    self.gf_popupElem.x             = gf_popupX();
    self.gf_popupElem.y             = gf_popupY();
    self.gf_popupElem setText( text );
    self.gf_popupElem.alpha = 0.85;
    self.gf_popupElem thread maps\mp\gametypes\_hud::fontPulse( self );

    wait 1;
    self.gf_popupElem fadeOverTime( 0.75 );
    self.gf_popupElem.alpha = 0;
}

gf_ensureScorePopupElem()
{
    if ( isDefined( self.gf_popupElem ) )
        return;

    self.gf_popupElem = NewScoreHudElem( self );
    self.gf_popupElem.horzAlign = "center";
    self.gf_popupElem.vertAlign = "middle";
    self.gf_popupElem.alignX    = "center";
    self.gf_popupElem.alignY    = "middle";
    self.gf_popupElem.x         = 0;
    self.gf_popupElem.y         = -60;
    self.gf_popupElem.font      = "default";
    self.gf_popupElem.fontscale = 2.0;
    self.gf_popupElem.archived  = false;
    self.gf_popupElem.color     = ( 1, 1, 0.5 );
    self.gf_popupElem.alpha     = 0;
    self.gf_popupElem.sort      = 50;
    self.gf_popupElem maps\mp\gametypes\_hud::fontPulseInit();
    self.gf_popupElem.overrridewhenindemo = true;
}

gf_welcomeMessage()
{
    self endon( "disconnect" );

    wait 2;

    self maps\mp\gametypes\_hud_message::oldNotifyMessage(
        "Welcome " + self.name + "!",
        "visit us at ^5gunfight.us",
        undefined,
        undefined,
        undefined,
        7 );
}

gf_parkStockScorePopup()
{
    self endon( "disconnect" );

    for ( i = 0; i < 50; i++ )
    {
        if ( isDefined( self.hud_rankscroreupdate ) )
        {
            self.hud_rankscroreupdate.x = -2000;
            return;
        }
        wait 0.1;
    }
}
