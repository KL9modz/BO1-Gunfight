/*
 * mp_gunfight.gsc  --  Plutonium T5 (Black Ops 1 MP) Gunfight mode
 *
 * RULES
 *   2v2 | 1 life per player | 60-second round timer
 *
 *   Round ends when:
 *     a) One team is fully eliminated    -> other team wins
 *     b) Timer expires with HP advantage -> lower-HP team eliminated, round ends
 *     c) Timer expires with equal HP     -> draw (no round point)
 *
 *   Every 2 rounds   : teams switch sides + new shared random loadout
 *   First to 6 wins  : match ends (max 11 rounds; 5-5 goes to a decider)
 *   All 4 players share the same randomly selected primary/secondary/equipment
 *
 * SETUP
 *   g_gametype must be "sd"
 *   Menu: Mods -> mp_gunfight  |  Console: loadMod mp_gunfight | map_restart
 *
 * LOCATION
 *   %appdata%\Plutonium\storage\t5\mods\mp_gunfight\scripts\mp\mp_gunfight.gsc
 */

#include maps\mp\_utility;
#include common_scripts\utility;

main()
{
	init();
}

// ============================================================
// INIT
// ============================================================

init()
{
	wait 0.05;

	// Config dvars -- set via server config or console before map loads
	//   gf_round_time          seconds per round          (default 60)
	//   gf_rounds_per_loadout  rounds before new loadout  (default 2)
	//   gf_win_limit           rounds to win the match    (default 6)
	level.gf_cfg_roundTime        = getDvarInt( "gf_round_time"         );
	level.gf_cfg_roundsPerLoadout = getDvarInt( "gf_rounds_per_loadout" );
	level.gf_cfg_winLimit         = getDvarInt( "gf_win_limit"          );
	if ( level.gf_cfg_roundTime        <= 0 ) level.gf_cfg_roundTime        = 60;
	if ( level.gf_cfg_roundsPerLoadout <= 0 ) level.gf_cfg_roundsPerLoadout = 2;
	if ( level.gf_cfg_winLimit         <= 0 ) level.gf_cfg_winLimit         = 6;

	// SD configuration ------------------------------------------------
	setDvar( "scr_sd_timelimit",    "" + (level.gf_cfg_roundTime / 60.0) );
	// Neutralise bomb if somehow planted; detonation impossible in 60 s
	setDvar( "scr_sd_bombtimer",    "9999" );
	setDvar( "scr_sd_planttime",    "9999" );
	setDvar( "scr_sd_defusetime",   "9999" );
	// One life per player per round
	setDvar( "scr_sd_numlives",     "1"    );
	// Disable SD's automatic halftime; we swap sides every gf_rounds_per_loadout rounds
	setDvar( "scr_sd_switchenable", "0"    );
	// Skip class-select menu entirely; auto-assign default class and spawn
	setDvar( "scr_disable_cac",     "1"    );
	setDvar( "scr_sd_selectclass",  "0"    );
	// Disable health regeneration
	level.playerHealth_RegularRegenDelay = 0;
	level.healthRegenDisabled            = true;

	// Gunfight state
	level.gf_alliesWins    = 0;
	level.gf_axisWins      = 0;
	level.gf_roundNum      = 0;
	level.gf_roundActive   = false;
	level.gf_loadoutIdx    = -1;     // index of currently active loadout (-1 = none)

	// Build the shared loadout pool, precache all weapon variants, then pick first loadout
	gf_initLoadouts();
	gf_precacheWeapons();
	gf_pickLoadout();

	// Scoreboard: kills / deaths — damage dealt goes into the score column
	setscoreboardcolumns( "kills", "deaths", "none", "none" );
	level.onPlayerDamage = ::gf_onPlayerDamage;
	level.onOneLeftEvent = ::gf_onOneLeft;

	// level.onTimeLimit is assigned per-round in gf_roundLoop (after prematch_over)
	// so SD's onStartGameType cannot overwrite it first.

	replacefunc( maps\mp\gametypes\_globallogic_ui::beginClassChoice, ::gf_bypassClassChoice );

	level thread onPlayerConnect();
	level thread gf_roundLoop();
	level thread gf_bombPlantedWatch();
}

gf_bypassClassChoice( forceNewChoice )
{
	if ( self.pers["team"] != "axis" && self.pers["team"] != "allies" )
		return;
	self.pers["class"] = level.defaultClass;
	self.class = level.defaultClass;
	// Don't spawn mid-round — wait for the next round start.
	// Applies to both new joins and team switches.
	if ( self.sessionstate != "playing" && game["state"] == "playing" && !level.gf_roundActive )
		self thread [[level.spawnClient]]();
	level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
	self thread maps\mp\gametypes\_spectating::setSpectatePermissionsForMachine();
}

// self = victim, eAttacker = shooter. Must return iDamage.
gf_onPlayerDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime )
{
	if ( isDefined( eAttacker ) && isPlayer( eAttacker ) && eAttacker != self )
	{
		if ( isDefined( eAttacker.pers["team"] ) && isDefined( self.pers["team"] ) &&
		     eAttacker.pers["team"] != self.pers["team"] )
		{
			// Cap to remaining health so overkill damage doesn't inflate the stat
			actual = iDamage;
			if ( actual > self.health ) actual = self.health;

			if ( !isDefined( eAttacker.pers["gf_damage"] ) )
				eAttacker.pers["gf_damage"] = 0;
			eAttacker.pers["gf_damage"] += actual;
			[[level._setPlayerScore]]( eAttacker, eAttacker.pers["gf_damage"] );
		}
	}
	return iDamage;
}

// ============================================================
// LOADOUT SYSTEM
// ============================================================

// Defines every available shared loadout.
// All players receive the same randomly selected loadout for 2 rounds.
// Weapon strings are T5 (Black Ops 1) MP format.
gf_initLoadouts()
{
	level.gf_loadouts = [];
	n = 0;

	// ---- Assault Rifles ----
	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "FAMAS / Python";
	level.gf_loadouts[n]["primary"]       = "famas_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Galil / Colt 45";
	level.gf_loadouts[n]["primary"]       = "galil_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "colt45_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "M16 / Python";
	level.gf_loadouts[n]["primary"]       = "m16_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Enfield / Makarov";
	level.gf_loadouts[n]["primary"]       = "enfield_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "makarovdw_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "AUG / Colt 45";
	level.gf_loadouts[n]["primary"]       = "aug_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "colt45_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Commando / Python";
	level.gf_loadouts[n]["primary"]       = "commando_mp";
	level.gf_loadouts[n]["primary_atts"]  = "silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	// ---- Submachine Guns ----
	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "AK74u / Colt 45";
	level.gf_loadouts[n]["primary"]       = "ak74u_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex acog silencer extclip";
	level.gf_loadouts[n]["second"]        = "colt45_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "MP5K / Makarov";
	level.gf_loadouts[n]["primary"]       = "mp5k_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex silencer extclip rapidfire";
	level.gf_loadouts[n]["second"]        = "makarovdw_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Spectre / Python";
	level.gf_loadouts[n]["primary"]       = "spectre_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex silencer extclip";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "Uzi / Colt 45";
	level.gf_loadouts[n]["primary"]       = "uzi_mp";
	level.gf_loadouts[n]["primary_atts"]  = "reflex silencer extclip";
	level.gf_loadouts[n]["second"]        = "colt45_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	// ---- Snipers / Shotguns ----
	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "L96A1 / Python";
	level.gf_loadouts[n]["primary"]       = "l96a1_mp";
	level.gf_loadouts[n]["primary_atts"]  = "silencer extclip variable";
	level.gf_loadouts[n]["second"]        = "python_speed_mp";
	level.gf_loadouts[n]["lethal"]        = "frag_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "concussion_grenade_mp";
	n++;

	level.gf_loadouts[n]                  = [];
	level.gf_loadouts[n]["name"]          = "SPAS / Makarov";
	level.gf_loadouts[n]["primary"]       = "spas_mp";
	level.gf_loadouts[n]["primary_atts"]  = "grip";
	level.gf_loadouts[n]["second"]        = "makarovdw_mp";
	level.gf_loadouts[n]["lethal"]        = "semtex_grenade_mp";
	level.gf_loadouts[n]["tactical"]      = "flash_grenade_mp";
	n++;

	level.gf_loadoutCount   = n;
	level.gf_usedLoadouts   = [];   // tracks which indices have been played
	level.gf_currentLoadout = undefined;
}

// Picks a random loadout from the unused pool, never repeating until all
// loadouts have been played, then resets.  Current loadout is always excluded
// from the next pick so the same one never plays back-to-back.
gf_pickLoadout()
{
	if ( level.gf_loadoutCount <= 0 )
		return;

	if ( level.gf_loadoutCount == 1 )
	{
		level.gf_loadoutIdx     = 0;
		level.gf_currentLoadout = level.gf_loadouts[0];
		return;
	}

	// Build pool of unused indices, skipping the one currently active
	pool = [];
	for ( i = 0; i < level.gf_loadoutCount; i++ )
	{
		if ( i == level.gf_loadoutIdx ) continue;
		if ( isDefined( level.gf_usedLoadouts[i] ) && level.gf_usedLoadouts[i] ) continue;
		pool[pool.size] = i;
	}

	// All loadouts exhausted — reset and rebuild pool (still skip current)
	if ( pool.size == 0 )
	{
		level.gf_usedLoadouts = [];
		for ( i = 0; i < level.gf_loadoutCount; i++ )
		{
			if ( i != level.gf_loadoutIdx )
				pool[pool.size] = i;
		}
		iprintln( "^3[Gunfight] All loadouts played — reshuffling." );
	}

	newIdx = pool[ randomInt( pool.size ) ];
	level.gf_usedLoadouts[newIdx] = true;
	level.gf_loadoutIdx     = newIdx;
	level.gf_currentLoadout = level.gf_loadouts[newIdx];
}

// Precaches all weapon variants (base + each attachment combo) used by the loadout pool.
// Must be called after gf_initLoadouts() and during game init (before map load completes).
gf_precacheWeapons()
{
	for ( i = 0; i < level.gf_loadoutCount; i++ )
	{
		lo = level.gf_loadouts[i];
		precacheItem( lo["primary"] );
		precacheItem( lo["second"]  );

		if ( !isDefined( lo["primary_atts"] ) || lo["primary_atts"] == "" )
			continue;

		atts = strTok( lo["primary_atts"], " " );
		base = getSubStr( lo["primary"], 0, lo["primary"].size - 3 );
		for ( j = 0; j < atts.size; j++ )
			precacheItem( base + "_" + atts[j] + "_mp" );
	}
}

// Announces the active loadout name to all players.
gf_announceLoadout()
{
	if ( !isDefined( level.gf_currentLoadout ) )
		return;
	iprintlnbold( "^3Loadout: ^7" + level.gf_currentLoadout["name"] );
}

// Gives the active shared loadout to self.
// Called from onPlayerSpawned after the 0.5 s settle wait.
gf_giveLoadout()
{
	if ( !isDefined( level.gf_currentLoadout ) )
		return;

	lo = level.gf_currentLoadout;

	self takeAllWeapons();
	wait 0.05;

	primary = gf_addRandomAttachment( lo["primary"], lo["primary_atts"] );
	iprintln( "^3[GF] giving: ^7" + primary + " / " + lo["second"] );
	self giveWeapon( primary         );
	self giveWeapon( lo["second"]    );
	self GiveOffhandWeapon( lo["lethal"]   );
	self SetActionSlot( 1, "weapon", lo["tactical"] );

	self switchToWeapon( primary );
	self giveMaxAmmo( primary        );
	self giveMaxAmmo( lo["second"]   );

	self SetPerk( "specialty_movefaster"       );
	self SetPerk( "specialty_bulletpenetration" );
	self SetPerk( "specialty_longersprint"     );

	self thread gf_displayPerks();
}

// Shows the 3 active perks on the right side of the HUD after spawn,
// styled after Sharpshooter's perk-unlock notification (icon + name,
// scaling pop-in, 5s display, fade out).
// Icon material names sourced from _wager::addPowerup calls in shrp.gsc.
gf_displayPerks()
{
	self endon( "disconnect" );
	self endon( "death" );

	wait 1.5;

	iconSize    = 32;
	bigIconSize = 40;
	startY      = 280;
	spacing     = 40;

	perkNames    = [];
	perkNames[0] = "Lightweight";
	perkNames[1] = "Hardened";
	perkNames[2] = "Marathon";

	perkIcons    = [];
	perkIcons[0] = "perk_lightweight_pro";
	perkIcons[1] = "perk_hardened_pro";
	perkIcons[2] = "perk_marathon_pro";

	hudText = [];
	hudIcon = [];

	for ( i = 0; i < 3; i++ )
	{
		y = startY - spacing * i;

		// Name label
		hudText[i] = newClientHudElem( self );
		hudText[i].fontScale         = 1.5;
		hudText[i].x                 = -125;
		hudText[i].y                 = y;
		hudText[i].alignX            = "left";
		hudText[i].alignY            = "middle";
		hudText[i].horzAlign         = "user_right";
		hudText[i].vertAlign         = "user_top";
		hudText[i].color             = ( 1, 1, 1 );
		hudText[i].foreground        = true;
		hudText[i].hidewhendead      = false;
		hudText[i].hidewheninmenu    = true;
		hudText[i].hidewheninkillcam = true;
		hudText[i].archived          = false;
		hudText[i].alpha             = 0;
		hudText[i] setText( perkNames[i] );

		// Perk icon — starts at bigIconSize, scales down on reveal
		hudIcon[i] = newClientHudElem( self );
		hudIcon[i].x                 = -125 - 5 - bigIconSize;
		hudIcon[i].y                 = y - bigIconSize / 2;
		hudIcon[i].alignX            = "left";
		hudIcon[i].alignY            = "top";
		hudIcon[i].horzAlign         = "user_right";
		hudIcon[i].vertAlign         = "user_top";
		hudIcon[i].color             = ( 1, 1, 1 );
		hudIcon[i].foreground        = true;
		hudIcon[i].hidewhendead      = false;
		hudIcon[i].hidewheninmenu    = true;
		hudIcon[i].hidewheninkillcam = true;
		hudIcon[i].archived          = false;
		hudIcon[i].alpha             = 0;
		hudIcon[i] setShader( perkIcons[i], bigIconSize, bigIconSize );

		// Pop in: fade text, scale icon down from big to normal size
		hudText[i] fadeOverTime( 0.5 );
		hudText[i].alpha = 1.0;
		hudIcon[i] fadeOverTime( 0.5 );
		hudIcon[i].alpha = 1.0;
		hudIcon[i] scaleOverTime( 0.5, iconSize, iconSize );
		hudIcon[i].x = -125 - 5 - iconSize;
		hudIcon[i].y = y - iconSize / 2;

		wait 0.5;
	}

	wait 4.0;

	for ( i = 0; i < 3; i++ )
	{
		hudText[i] fadeOverTime( 0.5 );
		hudText[i].alpha = 0;
		hudIcon[i] fadeOverTime( 0.5 );
		hudIcon[i].alpha = 0;
	}

	wait 0.5;

	for ( i = 0; i < 3; i++ )
	{
		hudText[i] destroy();
		hudIcon[i] destroy();
	}
}

// Returns baseWeapon with a randomly chosen attachment appended, or the
// base weapon unchanged if attList is empty or the "no attachment" slot wins.
// attList is a space-separated string e.g. "reflex acog silencer extclip".
// Two empty slots are added so ~2/(N+2) of picks give no attachment.
gf_addRandomAttachment( baseWeapon, attList )
{
	if ( !isDefined( attList ) || attList == "" )
		return baseWeapon;

	atts = strTok( attList, " " );
	if ( atts.size <= 0 )
		return baseWeapon;

	atts[atts.size] = "";
	atts[atts.size] = "";

	att = atts[ randomInt( atts.size ) ];
	if ( att == "" )
		return baseWeapon;

	// Strip "_mp", insert attachment, re-add "_mp"
	// e.g. "famas_mp" + "reflex" -> "famas_reflex_mp"
	base = getSubStr( baseWeapon, 0, baseWeapon.size - 3 );
	return base + "_" + att + "_mp";
}

// ============================================================
// HUD — BACKGROUND PANEL
// ============================================================

// Threads gf_showBgHud on every currently connected player (playing + spectators).
gf_spawnBgHuds()
{
	for ( i = 0; i < level.players.size; i++ )
		level.players[i] thread gf_showBgHud();
}

// Creates a small dark panel on the left-center of the screen.
// Solid body on the left, three stepped strips on the right that fade
// to transparent (approximates a gradient since T5 has no gradient shader).
// sort=0 so info elements layered on top use higher sort values.
// hidewhendead=false so spectators always see it.
// Destroys itself when the round ends.
gf_showBgHud()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	// Tear down any leftover element from a previous round
	if ( isDefined( self.gf_hudBg ) ) self.gf_hudBg destroy();
	if ( isDefined( self.gf_hudBgFade ) )
	{
		for ( j = 0; j < self.gf_hudBgFade.size; j++ )
			if ( isDefined( self.gf_hudBgFade[j] ) ) self.gf_hudBgFade[j] destroy();
	}

	panelX     = 5;
	panelW     = 140;
	panelH     = 44;
	panelColor = ( 0.04, 0.04, 0.08 );   // near-black with slight blue tint
	panelAlpha = 0.65;

	// --- Solid body ---
	self.gf_hudBg = newClientHudElem( self );
	self.gf_hudBg.horzAlign         = "left";
	self.gf_hudBg.vertAlign         = "middle";
	self.gf_hudBg.alignX            = "left";
	self.gf_hudBg.alignY            = "middle";
	self.gf_hudBg.x                 = panelX;
	self.gf_hudBg.y                 = 0;
	self.gf_hudBg.color             = panelColor;
	self.gf_hudBg.alpha             = panelAlpha;
	self.gf_hudBg.sort              = 0;
	self.gf_hudBg.foreground        = true;
	self.gf_hudBg.hidewhendead      = false;
	self.gf_hudBg.hidewheninmenu    = false;
	self.gf_hudBg.hidewheninkillcam = false;
	self.gf_hudBg.archived          = false;
	self.gf_hudBg setShader( "white", panelW, panelH );

	// --- Stepped right-edge fade (3 strips, decreasing alpha) ---
	// T5 has no gradient shader in its native HUD system, so we approximate
	// the fade with thin slices at diminishing opacity.
	fadeW      = [];
	fadeW[0]   = 12;
	fadeW[1]   = 10;
	fadeW[2]   = 8;
	fadeAlpha  = [];
	fadeAlpha[0] = panelAlpha * 0.7;    // ~0.46
	fadeAlpha[1] = panelAlpha * 0.35;   // ~0.23
	fadeAlpha[2] = panelAlpha * 0.1;    // ~0.065

	self.gf_hudBgFade = [];
	xOff = panelX + panelW;
	for ( i = 0; i < 3; i++ )
	{
		self.gf_hudBgFade[i] = newClientHudElem( self );
		self.gf_hudBgFade[i].horzAlign         = "left";
		self.gf_hudBgFade[i].vertAlign         = "middle";
		self.gf_hudBgFade[i].alignX            = "left";
		self.gf_hudBgFade[i].alignY            = "middle";
		self.gf_hudBgFade[i].x                 = xOff;
		self.gf_hudBgFade[i].y                 = 0;
		self.gf_hudBgFade[i].color             = panelColor;
		self.gf_hudBgFade[i].alpha             = fadeAlpha[i];
		self.gf_hudBgFade[i].sort              = 0;
		self.gf_hudBgFade[i].foreground        = true;
		self.gf_hudBgFade[i].hidewhendead      = false;
		self.gf_hudBgFade[i].hidewheninmenu    = false;
		self.gf_hudBgFade[i].hidewheninkillcam = false;
		self.gf_hudBgFade[i].archived          = false;
		self.gf_hudBgFade[i] setShader( "white", fadeW[i], panelH );
		xOff += fadeW[i];
	}

	level waittill( "gf_round_result" );

	if ( isDefined( self.gf_hudBg ) ) self.gf_hudBg destroy();
	for ( j = 0; j < self.gf_hudBgFade.size; j++ )
		if ( isDefined( self.gf_hudBgFade[j] ) ) self.gf_hudBgFade[j] destroy();
}

// ============================================================
// HUD — SELF HEALTH BAR
// ============================================================

// Shows the player's own name and a HP bar in the bottom-right corner.
// Spectators following this player see it automatically via newClientHudElem.
// Grey background bar (full width) + white foreground bar (scales with HP).
// Spawns on player spawn, destroys on death.
gf_selfHealthBar()
{
	self endon( "disconnect" );

	barMaxW = 120;
	barH    = 5;
	maxHp   = 100;  // BO1 MP default max health

	// Player name — right-aligned above the bar
	hudName = newClientHudElem( self );
	hudName.horzAlign         = "user_right";
	hudName.vertAlign         = "bottom";
	hudName.alignX            = "right";
	hudName.alignY            = "bottom";
	hudName.x                 = -5;
	hudName.y                 = -11;
	hudName.fontScale          = 0.9;
	hudName.font               = "smallfixed";
	hudName.color              = ( 1, 1, 1 );
	hudName.alpha              = 1;
	hudName.sort               = 5;
	hudName.foreground         = true;
	hudName.hidewhendead       = true;
	hudName.hidewheninmenu     = false;
	hudName.hidewheninkillcam  = false;
	hudName.archived           = false;
	hudName setText( self.name );

	// Grey background bar — full width, always visible behind the fill
	hudBg = newClientHudElem( self );
	hudBg.horzAlign         = "user_right";
	hudBg.vertAlign         = "bottom";
	hudBg.alignX            = "right";
	hudBg.alignY            = "middle";
	hudBg.x                 = -5;
	hudBg.y                 = -6;
	hudBg.color             = ( 0.4, 0.4, 0.4 );
	hudBg.alpha             = 0.9;
	hudBg.sort              = 3;
	hudBg.foreground         = true;
	hudBg.hidewhendead       = true;
	hudBg.hidewheninmenu     = false;
	hudBg.hidewheninkillcam  = false;
	hudBg.archived           = false;
	hudBg setShader( "white", barMaxW, barH );

	// White foreground bar — right edge pinned; shrinks from left as HP drops
	hudFg = newClientHudElem( self );
	hudFg.horzAlign         = "user_right";
	hudFg.vertAlign         = "bottom";
	hudFg.alignX            = "right";
	hudFg.alignY            = "middle";
	hudFg.x                 = -5;
	hudFg.y                 = -6;
	hudFg.color             = ( 1, 1, 1 );
	hudFg.alpha             = 1;
	hudFg.sort              = 4;
	hudFg.foreground         = true;
	hudFg.hidewhendead       = true;
	hudFg.hidewheninmenu     = false;
	hudFg.hidewheninkillcam  = false;
	hudFg.archived           = false;
	hudFg setShader( "white", barMaxW, barH );

	self thread gf_selfHealthBarUpdate( hudFg, barMaxW, barH, maxHp );

	self waittill( "death" );

	if ( isDefined( hudName ) ) hudName destroy();
	if ( isDefined( hudBg   ) ) hudBg   destroy();
	if ( isDefined( hudFg   ) ) hudFg   destroy();
}

// Polls self.health every 0.1 s and resizes the foreground bar to match.
// Runs as a sibling thread, terminates automatically on death or disconnect.
gf_selfHealthBarUpdate( hudFg, barMaxW, barH, maxHp )
{
	self endon( "disconnect" );
	self endon( "death" );

	for ( ;; )
	{
		wait 0.1;
		if ( !isDefined( hudFg ) ) return;

		hp = self.health;
		if ( hp < 0 ) hp = 0;

		w = ( hp * barMaxW ) / maxHp;
		if ( w < 1       ) w = 1;
		if ( w > barMaxW ) w = barMaxW;

		hudFg setShader( "white", w, barH );
	}
}

// ============================================================
// PLAYER LIFECYCLE
// ============================================================


onPlayerConnect()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "connected", player );
		player thread onPlayerConnected();
	}
}

onPlayerConnected()
{
	self endon( "disconnect" );

	// Give mid-round joins (including spectators) the background panel immediately
	wait 1;
	if ( level.gf_roundActive )
		self thread gf_showBgHud();

	for ( ;; )
	{
		self waittill( "spawned_player" );
		self thread onPlayerSpawned();
	}
}

onPlayerSpawned()
{
	self endon( "disconnect" );
	self endon( "death" );

	// Strip SD's class loadout immediately to prevent attachment bone-tag errors
	self TakeAllWeapons();

	// Wait for SD's remaining spawn-time logic to settle
	wait 0.5;

	// Destroy SD's per-attacker suitcase carry-icon
	if ( isDefined( self.carryIcon ) ) self.carryIcon destroy();

	// Restore damage into score column after map_restart
	if ( isDefined( self.pers["gf_damage"] ) )
		[[level._setPlayerScore]]( self, self.pers["gf_damage"] );

	// Give the shared Gunfight loadout
	gf_giveLoadout();

	// Self health bar (bottom-right). Spectators following this player see it
	// automatically because newClientHudElem elements are visible to spectators
	// watching that player in BO1's spectate system.
	self thread gf_selfHealthBar();
}

// ============================================================
// ROUND MANAGEMENT
// ============================================================

gf_roundLoop()
{
	level endon( "game_ended" );
	level waittill( "prematch_over" );

	// Assign our time-limit override AFTER SD's onStartGameType has run
	// so SD cannot overwrite it
	level.onTimeLimit = ::gf_onTimeLimit;

	iprintln( "^2[Gunfight] ^72v2 | " + level.gf_cfg_roundTime + " s rounds | first to " + level.gf_cfg_winLimit );
	gf_announceLoadout();

	for ( ;; )
	{
		// Block until both teams have at least one alive player
		gf_waitForRoundActive();

		// Re-suppress bomb each round; SD re-inits its bomb state on round start
		gf_suppressBomb();

		level.gf_roundActive = true;
		level.gf_roundNum++;

		// Spin up background HUD panel for every connected player (incl. spectators)
		gf_spawnBgHuds();


		// Re-arm the hook each round (fired once then swapped to noop)
		level.onTimeLimit = ::gf_onTimeLimit;

		iprintlnbold( "^3Round " + level.gf_roundNum
		              + " ^7-- Fight!  ^8(" + level.gf_currentLoadout["name"] + ")" );

		// gf_eliminationWatch races against SD's clock (gf_onTimeLimit).
		// gf_overtimeWatch is started inside gf_onTimeLimit if needed.
		level thread gf_eliminationWatch();

		level waittill( "gf_round_result", winner );
		level notify( "gf_cancel_watchers" );
		level.gf_roundActive = false;

		if ( gf_processRoundResult( winner ) )
			return;  // match won; endGame handles the rest

		// Every 2 rounds: switch sides and rotate loadout
		if ( level.gf_roundNum % level.gf_cfg_roundsPerLoadout == 0 )
		{
			gf_swapTeams();
			gf_pickLoadout();
			gf_announceLoadout();
		}

		// Allow SD's round-end sequence (scoreboard / intermission) to play
		wait 5;
	}
}

// Blocks until at least one alive player exists on each team.
gf_waitForRoundActive()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		wait 0.5;
		if ( gf_getAliveCount( "allies" ) > 0 && gf_getAliveCount( "axis" ) > 0 ) return;
	}
}

// ============================================================
// TEAM QUERY HELPERS
// ============================================================

gf_getAliveCount( team )
{
	count = 0;
	for ( i = 0; i < level.players.size; i++ )
	{
		p = level.players[i];
		if ( !isDefined( p ) || !isDefined( p.pers["team"] ) ) continue;
		if ( p.pers["team"] == team && p.health > 0 ) count++;
	}
	return count;
}

gf_getTeamHP( team )
{
	hp = 0;
	for ( i = 0; i < level.players.size; i++ )
	{
		p = level.players[i];
		if ( !isDefined( p ) || !isDefined( p.pers["team"] ) ) continue;
		if ( p.pers["team"] == team && p.health > 0 ) hp += p.health;
	}
	return hp;
}

// ============================================================
// END-CONDITION WATCHERS
// ============================================================

// Called by SD's timer system when the 60-second clock expires.
// Swaps to noop immediately to prevent _globallogic's poll loop re-entering.
gf_onTimeLimit()
{
	level.onTimeLimit = ::gf_onTimeLimitNoop;
	maps\mp\gametypes\_globallogic_audio::leaderDialog( "timesup" );

	alliesHp = gf_getTeamHP( "allies" );
	axisHp   = gf_getTeamHP( "axis"   );

	if ( alliesHp > axisHp )
	{
		iprintln( "^3Time! ^4Allies ^7win by HP (" + alliesHp + " vs " + axisHp + ")" );
		gf_eliminateTeam( "axis" );
		level notify( "gf_round_result", "allies" );
	}
	else if ( axisHp > alliesHp )
	{
		iprintln( "^3Time! ^1Axis ^7win by HP (" + axisHp + " vs " + alliesHp + ")" );
		gf_eliminateTeam( "allies" );
		level notify( "gf_round_result", "axis" );
	}
	else
	{
		// Equal HP -> draw
		gf_eliminateTeam( "allies" );
		gf_eliminateTeam( "axis"   );
		level notify( "gf_round_result", "draw" );
	}
}

// Absorbs repeated calls from _globallogic's polling loop after gf_onTimeLimit fires.
gf_onTimeLimitNoop() { }

// Polls every 0.1 s; fires gf_round_result when a team reaches zero alive players.
// gf_roundActive guard prevents false positives during between-round windows.
gf_eliminationWatch()
{
	level endon( "game_ended"         );
	level endon( "gf_cancel_watchers" );

	for ( ;; )
	{
		wait 0.1;
		if ( !level.gf_roundActive ) continue;

		alliesAlive = gf_getAliveCount( "allies" );
		axisAlive   = gf_getAliveCount( "axis"   );

		if ( alliesAlive == 0 && axisAlive == 0 )
		{
			level notify( "gf_round_result", "draw" );
			return;
		}
		else if ( alliesAlive == 0 )
		{
			level notify( "gf_round_result", "axis" );
			return;
		}
		else if ( axisAlive == 0 )
		{
			level notify( "gf_round_result", "allies" );
			return;
		}
	}
}

// Deals lethal environment damage to every living player on the given team.
// DoDamage(damage, origin) attributes the kill to the world, not the opposing
// team, so no kill credit is awarded on timer-expiry eliminations.
gf_eliminateTeam( team )
{
	for ( i = 0; i < level.players.size; i++ )
	{
		p = level.players[i];
		if ( !isDefined( p ) || !isDefined( p.pers["team"] ) ) continue;
		if ( p.pers["team"] != team || p.health <= 0 ) continue;

		p DoDamage( p.health + 100, p.origin );
	}
}

// Returns true if the match is over (a team hit the win limit).
gf_processRoundResult( winner )
{
	if ( winner == "draw" )
	{
		iprintlnbold( "^3DRAW ^7| no round point awarded" );
	}
	else if ( winner == "allies" )
	{
		level.gf_alliesWins++;
		[[level._setTeamScore]]( "allies", level.gf_alliesWins );
		iprintlnbold( "^4Allies ^7win round " + level.gf_roundNum );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_success", "allies" );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_failure", "axis"   );
	}
	else
	{
		level.gf_axisWins++;
		[[level._setTeamScore]]( "axis", level.gf_axisWins );
		iprintlnbold( "^1Axis ^7win round " + level.gf_roundNum );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_success", "axis"   );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_failure", "allies" );
	}

	iprintln( "^3Score: ^4" + level.gf_alliesWins + " ^7- ^1" + level.gf_axisWins );

	if ( level.gf_alliesWins >= level.gf_cfg_winLimit )
	{
		iprintlnbold( "^4Allies ^7win the match!" );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "winning", "allies" );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "losing",  "axis"   );
		maps\mp\gametypes\_globallogic::endGame( "allies", "" );
		return true;
	}
	if ( level.gf_axisWins >= level.gf_cfg_winLimit )
	{
		iprintlnbold( "^1Axis ^7win the match!" );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "winning", "axis"   );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "losing", "allies" );
		maps\mp\gametypes\_globallogic::endGame( "axis", "" );
		return true;
	}
	return false;
}

// ============================================================
// AUDIO
// ============================================================

// Fires when one player is left alive on a team.
// Plays the "last alive" callout and switches both teams to suspense music.
gf_onOneLeft( team )
{
	maps\mp\gametypes\_globallogic_audio::leaderDialog( "last_one" );
	maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "allies" );
	maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "axis"   );
}

// ============================================================
// TEAM SWAP
// ============================================================

// Flips every player between allies and axis.
// Called every 2 rounds alongside a new loadout pick.
gf_swapTeams()
{
	for ( i = 0; i < level.players.size; i++ )
	{
		p = level.players[i];
		if ( !isDefined( p ) || !isDefined( p.pers["team"] ) ) continue;

		if      ( p.pers["team"] == "allies" ) p.pers["team"] = "axis";
		else if ( p.pers["team"] == "axis"   ) p.pers["team"] = "allies";
	}

	// Flip SD's attacker/defender roles so spawn-point selection swaps correctly.
	// SD spawns game["attackers"] at mp_sd_spawn_attacker and game["defenders"]
	// at mp_sd_spawn_defender; without this flip both teams reuse the same side.
	oldAttackers          = game["attackers"];
	game["attackers"]     = game["defenders"];
	game["defenders"]     = oldAttackers;

	level thread maps\mp\gametypes\_globallogic::updateTeamStatus();

	iprintlnbold( "^3Sides switched!" );
}

// ============================================================
// BOMB SUPPRESSION
// ============================================================

// Called once per round after gf_waitForRoundActive().
// SD re-inits its bomb state each round, so we re-hide and re-lock
// the bomb object and all plant zones here rather than polling.
gf_suppressBomb()
{
	if ( isDefined( level.sdBomb ) )
	{
		level.sdBomb maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );
		level.sdBomb maps\mp\gametypes\_gameobjects::allowCarry( "none" );
	}

	if ( isDefined( level.bombZones ) )
	{
		for ( i = 0; i < level.bombZones.size; i++ )
		{
			if ( !isDefined( level.bombZones[i] ) ) continue;
			level.bombZones[i] maps\mp\gametypes\_gameobjects::setVisibleTeam( "none" );
			level.bombZones[i] maps\mp\gametypes\_gameobjects::allowUse( "none" );
		}
	}

	level.bombCarrier = undefined;
}

// Last-resort log if a plant somehow fires despite suppression.
gf_bombPlantedWatch()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "bomb_planted" );
		iprintln( "^1[Gunfight] WARNING: bomb planted -- bombtimer 9999 prevents detonation" );
	}
}
