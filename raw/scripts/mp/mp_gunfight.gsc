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
 * ROUND ARCHITECTURE
 *   Each round is a separate map load via map_restart(false).
 *   SD's native prematch countdown runs at the start of every round.
 *   Round state (wins, round number, loadout index, team sides) is persisted
 *   across restarts via dvars prefixed gf_state_*.
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
	// Disable SD's automatic halftime; we control side swaps via gf_state_attackers
	setDvar( "scr_sd_switchenable", "0"    );
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
	gf_restoreState();

	if ( level.gf_loadoutIdx < 0 )
		gf_pickLoadout();

	setscoreboardcolumns( "kills", "deaths", "none", "none" );
	level.onPlayerDamage = ::gf_onPlayerDamage;
	level.onOneLeftEvent = ::gf_onOneLeft;

	replacefunc( maps\mp\gametypes\_globallogic_ui::beginClassChoice, ::gf_bypassClassChoice );

	level thread onPlayerConnect();
	level thread gf_roundStart();
	level thread gf_bombSuppressLoop();
	level thread gf_bombPlantedWatch();
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
// STATE PERSISTENCE
// ============================================================

// Reads round state from dvars set by the previous round's gf_saveState().
// On the very first load gf_state_initialized is 0, so all level vars get
// safe defaults and gf_loadoutIdx is set to -1 so init() picks a fresh one.
gf_restoreState()
{
	if ( getDvarInt( "gf_state_initialized" ) == 0 )
	{
		level.gf_alliesWins = 0;
		level.gf_axisWins   = 0;
		level.gf_roundNum   = 0;
		level.gf_loadoutIdx = -1;
		level.gf_roundActive = false;
		return;
	}

	level.gf_alliesWins  = getDvarInt( "gf_state_allies_wins" );
	level.gf_axisWins    = getDvarInt( "gf_state_axis_wins"   );
	level.gf_roundNum    = getDvarInt( "gf_state_round_num"   );
	level.gf_loadoutIdx  = getDvarInt( "gf_state_loadout_idx" );
	level.gf_roundActive = false;

	if ( level.gf_loadoutIdx >= 0 && level.gf_loadoutIdx < level.gf_loadoutCount )
		level.gf_currentLoadout = level.gf_loadouts[level.gf_loadoutIdx];

	// Restore which team is attackers/defenders, overriding SD's default.
	savedAttackers = getDvar( "gf_state_attackers" );
	if ( savedAttackers == "allies" || savedAttackers == "axis" )
	{
		game["attackers"] = savedAttackers;
		if ( savedAttackers == "allies" )
			game["defenders"] = "axis";
		else
			game["defenders"] = "allies";
	}
}

// Writes the current round state to dvars so the next map_restart can restore it.
gf_saveState()
{
	setDvar( "gf_state_initialized", "1"                    );
	setDvar( "gf_state_allies_wins",  level.gf_alliesWins   );
	setDvar( "gf_state_axis_wins",    level.gf_axisWins     );
	setDvar( "gf_state_round_num",    level.gf_roundNum     );
	setDvar( "gf_state_loadout_idx",  level.gf_loadoutIdx   );
	setDvar( "gf_state_attackers",    game["attackers"]     );
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

	// Reset per-round damage score
	self.pers["gf_damage"] = 0;
	[[level._setPlayerScore]]( self, 0 );

	gf_giveLoadout();
	self thread gf_hud();
}
