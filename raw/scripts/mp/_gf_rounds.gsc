#include maps\mp\_utility;
#include common_scripts\utility;

// ============================================================
// ROUND MANAGEMENT
// ============================================================

// Runs once per map load. Waits for SD's native prematch countdown, then
// manages a single round. At round end it either calls endGame (match won)
// or saves state and calls map_restart(false) to start the next round.
gf_roundStart()
{
	level endon( "game_ended" );
	level waittill( "prematch_over" );

	// Assign our time-limit hook after prematch so SD's onStartGameType
	// callback cannot overwrite it first.
	level.onTimeLimit  = ::gf_onTimeLimit;
	level.gf_roundActive = false;

	// Restore scoreboard values now that the game is in playing state.
	[[level._setTeamScore]]( "allies", level.gf_alliesWins );
	[[level._setTeamScore]]( "axis",   level.gf_axisWins   );

	iprintln( "^2[Gunfight] ^72v2 | " + level.gf_cfg_roundTime + " s rounds | first to " + level.gf_cfg_winLimit );

	gf_waitForRoundActive();

	level.gf_roundActive = true;
	level.gf_roundNum++;

	iprintlnbold( "^3Round " + level.gf_roundNum
	              + " ^7-- Fight!  ^8(" + level.gf_currentLoadout["name"] + ")" );
	gf_announceLoadout();

	level thread gf_eliminationWatch();

	level waittill( "gf_round_result", winner );
	level notify( "gf_cancel_watchers" );
	level.gf_roundActive = false;

	gf_processRoundResult( winner );
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
		gf_eliminateTeam( "allies" );
		gf_eliminateTeam( "axis"   );
		level notify( "gf_round_result", "draw" );
	}
}

// Absorbs repeated calls from _globallogic's polling loop after gf_onTimeLimit fires.
gf_onTimeLimitNoop() { }

// Polls every 0.1 s; fires gf_round_result when a team reaches zero alive players.
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

// Processes the result of the round that just ended.
// Updates win counters, checks for match win, handles side-swap + loadout
// rotation every N rounds, then saves state and restarts into the next round.
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
		return;
	}
	if ( level.gf_axisWins >= level.gf_cfg_winLimit )
	{
		iprintlnbold( "^1Axis ^7win the match!" );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "winning", "axis"   );
		maps\mp\gametypes\_globallogic_audio::leaderDialog( "losing",  "allies" );
		maps\mp\gametypes\_globallogic::endGame( "axis", "" );
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

	gf_saveState();

	wait 5;
	map_restart( false );
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

// Polls every 0.1 s so it catches SD re-initialising the bomb each round
// before players ever see the objective.
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
