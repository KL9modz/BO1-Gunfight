/*
 * mp_gunfight.gsc  --  Plutonium T5 (Black Ops 1 MP) Gunfight mode
 *
 * RULES
 *   1 life per player | 60-second round timer | no team size limit
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
 * ROUND ARCHITECTURE
 *   No map_restart between rounds. SD's prematch runs once at match start.
 *   gf_roundStart() loops indefinitely: run round -> gf_roundBetween (5s
 *   intermission + respawn all players) -> next round.
 *   Win tracking uses SD's game["roundswon"] + hitRoundWinLimit().
 *   scr_sd_winlimit controls wins needed (default 6).
 *
 * LOCATION
 *   %appdata%\Plutonium\storage\t5\raw\scripts\mp\mp_gunfight.gsc
 */

#include maps\mp\_utility;
#include common_scripts\utility;
#include scripts\mp\_gf_loadouts;
#include scripts\mp\_gf_hud;
#include scripts\mp\_gf_rounds;

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
	//   scr_sd_winlimit        rounds to win the match    (default 6)
	level.gf_cfg_roundTime        = getDvarInt( "gf_round_time"         );
	level.gf_cfg_roundsPerLoadout = getDvarInt( "gf_rounds_per_loadout" );
	if ( level.gf_cfg_roundTime        <= 0 ) level.gf_cfg_roundTime        = 60;
	if ( level.gf_cfg_roundsPerLoadout <= 0 ) level.gf_cfg_roundsPerLoadout = 2;

	// SD configuration ------------------------------------------------
	// Our gf_roundTimer owns the clock; disable SD's native timer
	setDvar( "scr_sd_timelimit",    "9999" );
	// Neutralise bomb if somehow planted; detonation impossible in 60 s
	setDvar( "scr_sd_bombtimer",    "9999" );
	setDvar( "scr_sd_planttime",    "9999" );
	setDvar( "scr_sd_defusetime",   "9999" );
	// One life per player per round
	setDvar( "scr_sd_numlives",     "1"    );
	// Disable SD's automatic halftime; we control side swaps in gf_processRoundResult
	setDvar( "scr_sd_switchenable", "0"    );
	// SD win limit — hitRoundWinLimit() reads this; default 6 (first to 6)
	setDvar( "scr_sd_winlimit",     "6"    );
	// Skip class-select menu entirely; auto-assign default class and spawn
	setDvar( "scr_disable_cac",     "1"    );
	setDvar( "scr_sd_selectclass",  "0"    );
	// Disable health regeneration
	level.playerHealth_RegularRegenDelay = 0;
	level.healthRegenDisabled            = true;

	// Prevent SD's onStartGameType from flipping sides on its own.
	game["switchedsides"] = false;

	gf_initLoadouts();
	gf_precacheWeapons();
	level.gf_loadoutIdx = -1;
	gf_pickLoadout();

	setscoreboardcolumns( "kills", "deaths", "none", "none" );
	level.onPlayerDamage = ::gf_onPlayerDamage;
	level.onOneLeftEvent = ::gf_onOneLeft;
	level.onDeadEvent    = ::gf_onDeadEvent;

	replacefunc( maps\mp\gametypes\_globallogic_ui::beginClassChoice, ::gf_bypassClassChoice );

	level thread onPlayerConnect();
	level thread gf_roundStart();
	level thread gf_bombSuppressLoop();
	level thread gf_bombPlantedWatch();
}

// SD fires this when a team reaches zero alive players (via updateTeamStatus).
// Translate into our gf_round_result notify so gf_roundStart can handle it.
// Guard against SD firing it outside an active round (e.g. during intermission).
gf_onDeadEvent( team )
{
	if ( !level.gf_roundActive ) return;
	winner = getOtherTeam( team );
	level notify( "gf_round_result", winner );
}

gf_bypassClassChoice( forceNewChoice )
{
	if ( self.pers["team"] != "axis" && self.pers["team"] != "allies" )
		return;
	self.pers["class"] = level.defaultClass;
	self.class = level.defaultClass;
	// Don't spawn mid-round — wait for the next round start.
	if ( self.sessionstate != "playing" && game["state"] == "playing" && !level.gf_roundActive )
		self thread [[level.spawnClient]]();
	level thread maps\mp\gametypes\_globallogic::updateTeamStatus();
	self thread maps\mp\gametypes\_spectating::setSpectatePermissionsForMachine();
}

// self = victim, eAttacker = shooter. Must return iDamage.
// Tracks cumulative damage on the victim (capped at 100) so burst-fire bullets
// that all arrive before self.health decrements can't inflate the score.
gf_onPlayerDamage( eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, psOffsetTime )
{
	if ( isDefined( eAttacker ) && isPlayer( eAttacker ) && eAttacker != self )
	{
		if ( isDefined( eAttacker.pers["team"] ) && isDefined( self.pers["team"] ) &&
		     eAttacker.pers["team"] != self.pers["team"] )
		{
			if ( !isDefined( self.pers["gf_hp_lost"] ) )
				self.pers["gf_hp_lost"] = 0;

			remaining = 100 - self.pers["gf_hp_lost"];
			if ( remaining > 0 )
			{
				actual = iDamage;
				if ( actual > remaining ) actual = remaining;
				self.pers["gf_hp_lost"] += actual;

				if ( !isDefined( eAttacker.pers["gf_score"] ) )
					eAttacker.pers["gf_score"] = 0;
				eAttacker.pers["gf_score"] += actual;
				[[level._setPlayerScore]]( eAttacker, eAttacker.pers["gf_score"] );
			}
		}
	}
	return iDamage;
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

	self.pers["gf_score"]   = 0;
	self.pers["gf_hp_lost"] = 0;
	[[level._setPlayerScore]]( self, 0 );

	gf_giveLoadout();
	self thread gf_hud();
}
