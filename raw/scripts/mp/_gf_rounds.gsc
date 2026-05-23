#include maps\mp\_utility;
#include common_scripts\utility;
#include scripts\mp\_gf_loadouts;

// ============================================================
// ROUND MANAGEMENT
// ============================================================

// Waits for SD's first prematch, then loops indefinitely:
// run round -> gf_roundBetween (intermission + respawn) -> next round.
// No map_restart between rounds. All state lives in level vars.
// Win counting uses SD's game["roundswon"] + hitRoundWinLimit().
gf_roundStart()
{
	level endon( "game_ended" );

	level waittill( "prematch_over" );

	level.gf_roundActive        = false;
	level.gf_roundNum           = 0;
	game["roundswon"]["allies"] = 0;
	game["roundswon"]["axis"]   = 0;

	iprintln( "^2[Gunfight] ^7" + level.gf_cfg_roundTime + " s rounds | first to "
	          + getDvarInt( "scr_sd_winlimit" ) );

	for ( ;; )
	{
		gf_waitForRoundActive();

		// Reset per-round scores now that players are spawned
		for ( i = 0; i < level.players.size; i++ )
		{
			p = level.players[i];
			if ( !isDefined( p ) ) continue;
			p.pers["gf_score"]   = 0;
			p.pers["gf_hp_lost"] = 0;
			p.score = 0;
		}

		level.gf_roundActive = true;
		level.gf_roundNum++;

		iprintlnbold( "^3Round " + level.gf_roundNum
		              + " ^7-- Fight!  ^8(" + level.gf_currentLoadout["name"] + ")" );
		gf_announceLoadout();

		level thread gf_roundTimer();
		level thread gf_eliminationWatch();

		level waittill( "gf_round_result", winner );
		level notify( "gf_cancel_watchers" );
		level.gf_roundActive = false;

		gf_processRoundResult( winner );
		// If match over, endGame fires game_ended and loop exits.
		// Otherwise gf_roundBetween returns and we loop into the next round.
	}
}

// ============================================================
// TEAM QUERY HELPERS
// ============================================================

gf_waitForRoundActive()
{
	level endon( "game_ended" );
	for ( ;; )
	{
		wait 0.5;
		if ( gf_getAliveCount( "allies" ) > 0 && gf_getAliveCount( "axis" ) > 0 ) return;
	}
}

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

// Own round timer thread. SD's clock (scr_sd_timelimit=9999) is disabled.
// Fires gf_round_result with HP tiebreaker on expiry.
gf_roundTimer()
{
	level endon( "game_ended"         );
	level endon( "gf_cancel_watchers" );

	wait level.gf_cfg_roundTime;

	if ( !level.gf_roundActive ) return;

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
		gf_eliminateTeam( "allies" );
		gf_eliminateTeam( "axis"   );
		level notify( "gf_round_result", "draw" );
	}
}

// Polls every 0.1 s; fires gf_round_result when a team reaches zero alive players.
// Backup for gf_onDeadEvent which fires async (one frame lag via updateTeamStatus).
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

// Updates SD's native round-win counter, checks win limit via hitRoundWinLimit(),
// handles side-swap + loadout rotation, then either ends the match or calls
// gf_roundBetween to start the next round in-place.
gf_processRoundResult( winner )
{
	if ( winner == "draw" )
	{
		iprintlnbold( "^3DRAW ^7| no round point awarded" );
	}
	else if ( winner == "allies" )
	{
		game["roundswon"]["allies"]++;
		[[level._setTeamScore]]( "allies", 1 );
		iprintlnbold( "^4Allies ^7win round " + level.gf_roundNum );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_success", "allies" );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_failure", "axis"   );
	}
	else
	{
		game["roundswon"]["axis"]++;
		[[level._setTeamScore]]( "axis", 1 );
		iprintlnbold( "^1Axis ^7win round " + level.gf_roundNum );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_success", "axis"   );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "round_failure", "allies" );
	}

	iprintln( "^3Score: ^4" + game["roundswon"]["allies"] + " ^7- ^1" + game["roundswon"]["axis"] );

	if ( winner != "draw" && hitRoundWinLimit() )
	{
		if ( winner == "allies" )
		{
			iprintlnbold( "^4Allies ^7win the match!" );
			maps\mp\gametypes\_globallogic_audio::leaderDialog( "winning", "allies" );
			maps\mp\gametypes\_globallogic_audio::leaderDialog( "losing",  "axis"   );
		}
		else
		{
			iprintlnbold( "^1Axis ^7win the match!" );
			maps\mp\gametypes\_globallogic_audio::leaderDialog( "winning", "axis"   );
			maps\mp\gametypes\_globallogic_audio::leaderDialog( "losing",  "allies" );
		}
		maps\mp\gametypes\_globallogic::endGame( winner, "" );
		return;
	}

	// Every N rounds: flip spawn sides and rotate to a new loadout
	if ( level.gf_roundNum % level.gf_cfg_roundsPerLoadout == 0 )
	{
		if ( game["attackers"] == "allies" )
		{
			game["attackers"] = "axis";
			game["defenders"] = "allies";
		}
		else
		{
			game["attackers"] = "allies";
			game["defenders"] = "axis";
		}
		iprintlnbold( "^3Sides switching next round!" );
		gf_pickLoadout();
		gf_announceLoadout();
	}

	gf_roundBetween();
}

// 5-second intermission then respawns all team players for the next round.
// onPlayerSpawned handles weapons + perks as normal.
gf_roundBetween()
{
	level endon( "game_ended" );

	wait 5;

	// Kill any survivors still standing
	for ( i = 0; i < level.players.size; i++ )
	{
		p = level.players[i];
		if ( !isDefined( p ) || !isDefined( p.pers["team"] ) ) continue;
		if ( p.pers["team"] != "allies" && p.pers["team"] != "axis" ) continue;
		if ( p.health > 0 ) p DoDamage( p.health + 100, p.origin );
	}

	wait 0.5;

	// Restore each player's life count then respawn.
	// With scr_sd_numlives=1, pers["lives"] reaches 0 after death and spawnClient
	// refuses to spawn — reset it here so the new round's spawn goes through.
	for ( i = 0; i < level.players.size; i++ )
	{
		p = level.players[i];
		if ( !isDefined( p ) || !isDefined( p.pers["team"] ) ) continue;
		if ( p.pers["team"] != "allies" && p.pers["team"] != "axis" ) continue;
		if ( isDefined( level.numlives ) && level.numlives > 0 )
			p.pers["lives"] = level.numlives;
		p thread [[level.spawnClient]]();
	}
}

// ============================================================
// AUDIO
// ============================================================

gf_onOneLeft( team )
{
	maps\mp\gametypes\_globallogic_audio::leaderDialog( "last_one" );
	maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "allies" );
	maps\mp\gametypes\_globallogic_audio::set_music_on_team( "MP_LAST_STAND", "axis"   );
}

// ============================================================
// BOMB SUPPRESSION
// ============================================================

gf_bombSuppressLoop()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		wait 0.1;

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
}

gf_bombPlantedWatch()
{
	level endon( "game_ended" );

	for ( ;; )
	{
		level waittill( "bomb_planted" );
		iprintln( "^1[Gunfight] WARNING: bomb planted -- bombtimer 9999 prevents detonation" );
	}
}
