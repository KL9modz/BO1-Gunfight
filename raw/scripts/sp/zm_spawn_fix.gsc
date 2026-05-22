#include maps\_utility;
#include common_scripts\utility;

main()
{
	if ( GetDvarInt( "scr_disableHotJoinFixes" ) )
	{
		return;
	}
	
	if ( getDvarInt( "onlinegame" ) )
	{
		// always coop
		replaceFunc( getFunction( "maps/_utility", "is_coop" ), ::alwaysTrue, -1 );
		
		// allow cg_mature in onlinegame
		replaceFunc( getFunction( "common_scripts/utility", "is_mature" ), ::is_mature_stub, -1 );
		
		if ( isDedicated() )
		{
			// host is not players[0] on dedi
			replaceFunc( getFunction( "maps/_utility", "get_host" ), ::getHostDedi, -1 );
			
			// prevent force end exploit
			replaceFunc( getFunction( "maps/_cooplogic", "forceEnd" ), ::noop, -1 );
			
			// add a timeout for all_players_connected
			replaceFunc( getFunction( "maps/_load_common", "all_players_connected" ), ::all_players_connected, -1 );
		}
		else
		{
			// reset backspeed and strafe if onlinegame
			cmdExec( "reset player_backSpeedScale; reset player_strafeSpeedScale\n" );
		}
		
		if ( getDvarInt( "zombietron" ) )
		{
			// fix hotjoining on doa
			replaceFunc( getFunction( "maps/_zombietron_main", "update_next_arena" ), ::update_next_arena );
			replaceFunc( getFunction( "maps/_zombietron_main", "player_reset_score" ), ::player_reset_score );
			replaceFunc( getFunction( "maps/_zombietron_pickups", "extra_life_spawner" ), ::extra_life_spawner );
		}
		else if ( getDvarInt( "zombiemode" ) )
		{
			// make sure quickrevive is coop
			replaceFunc( getFunction( "maps/_zombiemode_perks", "vending_trigger_think" ), ::vending_trigger_think, -1 );
			replaceFunc( getFunction( "maps/_zombiemode_perks", "turn_revive_on" ), ::turn_revive_on, -1 );
			replaceFunc( getFunction( "maps/_zombiemode_perks", "give_perk" ), ::give_perk, -1 );
			replaceFunc( getFunction( "maps/_zombiemode_score", "team_score_init" ), ::team_score_init, -1 );
			
			// cotd ee is coop
			if ( getdvar( "mapname" ) == "zombie_coast" )
			{
				replaceFunc( getFunction( "maps/zombie_coast_eggs", "c_overseer" ), ::c_overseer, -1 );
			}
			
			// fix nacht
			if ( getdvar( "mapname" ) == "zombie_cod5_prototype" )
			{
				replaceFunc( getFunction( "maps/zombie_cod5_prototype", "pistol_rank_setup" ), ::pistol_rank_setup, -1 );
				replaceFunc( getFunction( "maps/zombie_cod5_prototype", "check_solo_game" ), ::check_solo_game, -1 );
			}
			
			if ( isDedicated() )
			{
				// fix box error/leak on dedis
				replaceFunc( getFunction( "maps/_zombiemode_weapons", "decide_hide_show_hint" ), ::decide_hide_show_hint, -1 );
			}
			else
			{
				// force mulekick enabled for coops
				replaceFunc( getFunction( "maps/_zombiemode_ffotd", "disable_additionalprimaryweapon_machine_locations" ), ::noop, -1 );
			}
		}
	}
}

decide_hide_show_hint( endon_notify )
{
	self notify( "decide_hide_show_hint_leak_fix" );
	self endon( "decide_hide_show_hint_leak_fix" );
	
	func = getFunction( "maps/_zombiemode_weapons", "decide_hide_show_hint" );
	disableDetourOnce( func );
	self [[func]]( endon_notify );
}

is_mature_stub()
{
	return GetDvarInt( #"cg_mature" );
}

getHostDedi()
{
	return get_players()[0];
}

alwaysTrue()
{
	return true;
}

noop()
{
}

isZombieMode()
{
	return ( isDefined( level.is_zombie_level ) && level.is_zombie_level );
}

isZombietronMode()
{
	return ( isDefined( level.zombietron_mode ) && level.zombietron_mode );
}

shouldEnableWater()
{
	if ( isZombietronMode() )
	{
		return true;
	}
	
	if ( level.script == "zombie_coast" || level.script == "zombie_cod5_sumpf" || level.script == "zombie_cosmodrome" || level.script == "zombie_moon" || level.script == "zombie_temple" )
	{
		return true;
	}
	
	return false;
}

init()
{
	if ( GetDvarInt( "scr_disableHotJoinFixes" ) )
	{
		return;
	}
	
	PreCacheString( &"PLUTONIUM_MP_CONNECTED" );
	
	if ( level.onlinegame )
	{
		// prevent randomized solo players
		setDvar( "zombiefive_norandomchar", 1 );
	}
	
	// do prints, handle hotjoining and leavers
	level thread onPlayerConnect();
	
	if ( level.onlinegame )
	{
		if ( isZombieMode() )
		{
			// make late joiners into spectators
			thread other_players_spectate();
			
			// fix spawning
			if ( !isZombietronMode() )
			{
				thread endOfRoundSpectatorRespawnWatch();
			}
			
			// fix water on dedi
			if ( isDedicated() )
			{
				setDvar( "playerPushAmount", 1 );
				
				if ( shouldEnableWater() )
				{
					setDvar( "phys_buoyancy", true );
				}
			}
		}
		
		// lets be the last to setup func ptrs
		for ( i = 0; i < 10; i++ )
		{
			waittillframeend;
		}
		
		if ( isZombieMode() && !isZombietronMode() )
		{
			// make dead players into spectators
			level.oldOverridePlayerKilled = level.overridePlayerKilled;
			level.overridePlayerKilled = ::playerKilledOverride;
			
			// setup this callback
			if ( level.spawnSpectator == GetFunction( "maps/_callbackglobal", "spawnspectator" ) )
			{
				level.spawnSpectator = ::spawn_spectator;
			}
			
			// fix moon model hot joining
			if ( level.script == "zombie_moon" )
			{
				level.zombiemode_give_player_model_override_old = level.zombiemode_give_player_model_override;
				level.zombiemode_give_player_model_override = ::zombiemode_give_player_model_override_func;
			}
		}
	}
}

zombiemode_give_player_model_override_func( entity_num )
{
	if ( level.ever_been_on_the_moon && !IsDefined( self.zm_random_char ) )
	{
		nums = [];
		nums[0] = 0;
		nums[1] = 1;
		nums[2] = 2;
		nums[3] = 3;
		players = get_players();
		
		for ( i = 0; i < players.size; i++ )
		{
			if ( players[i] == self )
			{
				continue;
			}
			
			nums = array_remove( nums, players[i].zm_random_char );
		}
		
		// prio richt
		if ( is_in_array( nums, 3 ) )
		{
			self.zm_random_char = 3;
		}
		else
		{
			assert( nums.size >= 1 );
			self.zm_random_char = nums[0];
		}
	}
	
	self [[ level.zombiemode_give_player_model_override_old ]]( entity_num );
}

other_players_spectate()
{
	flag_wait( "all_players_spawned" );
	level.otherPlayersSpectate = true;
}

playerKilledOverride()
{
	self [[ level.player_becomes_zombie ]]();
	[[ getFunction( "maps/_zombiemode", "checkForAllDead" ) ]]();
	self [[ level.oldOverridePlayerKilled ]]();
}

spawn_spectator()
{
	// we do it like this cause we dont want the player_died_penalty to call for this instance
	if ( IsDefined( level.deathcard_spawn_func ) )
	{
		self [[ level.deathcard_spawn_func ]]();
	}
	
	if ( !IsDefined( level.zombie_vars[ "zombify_player" ] ) || !level.zombie_vars[ "zombify_player" ] )
	{
		if ( !is_true( self.solo_respawn ) )
		{
			self thread [[ getFunction( "maps/_zombiemode", "spawnSpectator" ) ]]();
		}
		
		return;
	}
	
	self [[ level.player_becomes_zombie ]]();
}

endOfRoundSpectatorRespawnWatch()
{
	flag_wait( "all_players_spawned" );
	
	for ( ;; )
	{
		level waittill( "end_of_round" );
		
		if ( level.script != "zombie_moon" || !flag( "teleporter_used" ) )
		{
			level thread [[ getFunction( "maps/_zombiemode", "spectators_respawn" ) ]]();
		}
	}
}

update_spawn_points()
{
	// we do it like this cause we dont want to teleport the existing players
	if ( level.script != "zombie_cod5_asylum" )
	{
		structs = getstructarray( "initial_spawn_points", "targetname" );
		
		if ( level.script != "zombie_cod5_sumpf" )
		{
			temp_ent = Spawn( "script_model", ( 0, 0, 0 ) );
			
			for ( i = 0; i < structs.size; i++ )
			{
				temp_ent.origin = structs[ i ].origin;
				temp_ent placeSpawnpoint();
				structs[ i ].origin = temp_ent.origin;
			}
			
			temp_ent Delete();
		}
		
		players = get_players();
		
		for ( i = 0; i < players.size; i++ )
		{
			players[i].spectator_respawn = structs[i];
		}
	}
	else
	{
		players = get_players();
		north_structs = getstructarray( "north_spawn", "script_noteworthy" );
		south_structs = getstructarray( "south_spawn", "script_noteworthy" );
		
		side1 = north_structs;
		side2 = south_structs;
		
		if ( players.size && isdefined( players[ 0 ].spawn_side ) && players[ 0 ].spawn_side == "south_spawn" )
		{
			side1 = south_structs;
			side2 = north_structs;
		}
		
		for ( i = 0; i < players.size; i++ )
		{
			if ( i < 2 )
			{
				players[i].respawn_point = side1[i];
				players[i].spawn_side = side1[i].script_noteworthy;
				players[i].spectator_respawn = side1[i];
			}
			else
			{
				players[i].respawn_point = side2[i];
				players[i].spawn_side = side2[i].script_noteworthy;
				players[i].spectator_respawn = side2[i];
			}
		}
	}
}

onDisconnect()
{
	lpselfnum = self getentitynumber();
	lpguid = self getguid();
	name = self.playername;
	
	self waittill( "disconnect" );
	
	logprint( "Q;" + lpguid + ";" + lpselfnum + ";" + name + "\n" );
}

onPlayerConnect()
{
	for ( ;; )
	{
		level waittill( "connected", player );
		
		if ( isZombieMode() && !isZombietronMode() && flag( "all_players_spawned" ) )
		{
			player thread update_spawn_points();
		}
		
		if ( level.script != "frontend" )
		{
			iprintln( &"PLUTONIUM_MP_CONNECTED", player.playername );
		}

		player thread onDisconnect();
		player thread onConnect();
	}
}

watch_player_maxfps()
{
	self endon( "disconnect" );
	
	for ( ;; )
	{
		wait 1.5;
		
		maxfps = self getreportedmaxfps();
		
		if ( maxfps < 20 || maxfps > 250 )
		{
			if ( getdvar( "fs_game" ) == "" )
			{
				setcheatstate();
			}
		}
	}
}

saveFate()
{
	self waittill( "disconnect" );
	
	if ( isdefined( self.fate ) )
	{
		if ( !isdefined( level.fate_cache ) )
		{
			level.fate_cache = [];
		}
		
		level.fate_cache[ self.entity_num + "" ] = self.fate;
	}
}

onConnect()
{
	self endon( "disconnect" );
	
	if ( isZombietronMode() )
	{
		self thread saveFate();
	}
	
	if ( !isDedicated() && !self isbot() )
	{
		self thread watch_player_maxfps();
	}
	
	logprint( "J;" + self getguid() + ";" + self getentitynumber() + ";" + self.playername + "\n" );
	
	if ( isZombieMode() && !isZombietronMode() && flag( "all_players_spawned" ) )
	{
		// init all the stuff that was missed
		self setClientDvars( "ammoCounterHide", "0", "miniscoreboardhide", "0" );
		
		if ( level.round_number > 6 )
		{
			self.score = 1500;
		}
		else
		{
			self.score = 500;
		}
		
		self.score_total = self.score;
		self.old_score = self.score;
		
		self.zombie_vars[ "zombie_powerup_minigun_on" ] = false;
		self.zombie_vars[ "zombie_powerup_minigun_time" ] = 0;
		
		self.zombie_vars[ "zombie_powerup_tesla_on" ] = false;
		self.zombie_vars[ "zombie_powerup_tesla_time" ] = 0;
		
		self.solo_powerup_hud_array = [];
		self.solo_powerup_hud_array[ self.solo_powerup_hud_array.size ] = true;
		self.solo_powerup_hud_array[ self.solo_powerup_hud_array.size ] = true;
		
		self.solo_powerup_hud = [];
		self.solo_powerup_hud_cover = [];
		
		for ( i = 0; i < self.solo_powerup_hud_array.size; i++ )
		{
			self.solo_powerup_hud[i] = [[ GetFunction( "maps/_zombiemode_utility", "create_simple_hud" ) ]]( self );
			self.solo_powerup_hud[i].foreground = true;
			self.solo_powerup_hud[i].sort = 2;
			self.solo_powerup_hud[i].hidewheninmenu = false;
			self.solo_powerup_hud[i].alignX = "center";
			self.solo_powerup_hud[i].alignY = "bottom";
			self.solo_powerup_hud[i].horzAlign = "user_center";
			self.solo_powerup_hud[i].vertAlign = "user_bottom";
			self.solo_powerup_hud[i].x = -32 + ( i * 15 );
			self.solo_powerup_hud[i].y = self.solo_powerup_hud[i].y - 5;
			self.solo_powerup_hud[i].alpha = 0.8;
		}
		
		self thread [[ GetFunction( "maps/_zombiemode_powerups", "solo_power_up_hud" ) ]]( "zom_icon_minigun", self.solo_powerup_hud[0], 76, "zombie_powerup_minigun_time", "zombie_powerup_minigun_on" );
		self thread [[ GetFunction( "maps/_zombiemode_powerups", "solo_power_up_hud" ) ]]( "zom_icon_minigun", self.solo_powerup_hud[1], 76, "zombie_powerup_tesla_time", "zombie_powerup_tesla_on" );
		
		self thread [[ getFunction( "maps/_zombiemode_audio", "zombie_behind_vox" ) ]]();
		self thread [[ getFunction( "maps/_zombiemode_audio", "player_killstreak_timer" ) ]]();
		self thread [[ getFunction( "maps/_zombiemode_audio", "oh_shit_vox" ) ]]();
		
		if ( shouldEnableWater() )
		{
			self setClientDvars( "phys_buoyancy", true );
		}
		
		if ( level.script == "zombie_temple" )
		{
			self thread [[ getFunction( "maps/_zombiemode_ai_monkey", "monkey_grenade_watch" ) ]]();
			self.moveSpeedScale = 1.0;
		}
		
		if ( level.script == "zombie_coast" )
		{
			self thread [[ getFunction( "maps/zombie_coast_water", "water_watch_freeze" ) ]]();
			self.player_damage_override = getFunction( "maps/_zombiemode_ai_director", "player_damage_watcher" );
		}
		
		if ( level.script == "zombie_moon" )
		{
			self._padded = false;
			self.lander = false;
			self thread [[ getFunction( "maps/zombie_moon_utility", "check_for_grenade_throw" ) ]]();
			self thread [[ getFunction( "maps/zombie_moon_gravity", "player_throw_grenade" ) ]]();
			self thread [[ getFunction( "maps/zombie_moon_gravity", "low_gravity_watch" ) ]]();
			self thread [[ getFunction( "maps/zombie_moon_gravity", "zombie_moon_update_player_float" ) ]]();
			self [[ getFunction( "maps/_zombiemode_equipment", "set_equipment_invisibility_to_player" ) ]]( "equip_gasmask_zm", false );
		}
		
		if ( level.script == "zombie_pentagon" )
		{
			self thread [[ getFunction( "maps/zombie_pentagon", "wait_for_laststand_notify" ) ]]();
			self thread [[ getFunction( "maps/zombie_pentagon", "bleedout_listener" ) ]]();
		}
		
		if ( level.script == "zombie_cosmodrome" )
		{
			self.lander = false;
		}
		
		self waittill( "spawned_player" );
		
		if ( level.script == "zombie_theater" )
		{
			if ( flag( "curtains_done" ) )
			{
				curtains = getent( "theater_curtains", "targetname" );
				curtains animscripted( "curtains_move_done", curtains.origin, curtains.angles, level.scr_anim[ "curtains_move" ], "normal", undefined, 3, 3 );
			}
		}
		
		if ( level.script == "zombie_coast" )
		{
			self thread [[ getFunction( "maps/_zombiemode_player_zipline", "jump_button_monitor" ) ]]();
		}
		
		wait 0.05;
		self freezecontrols( false );
		wait_network_frame();
		
		if ( level.script == "zombie_cosmodrome" )
		{
			self ClientNotify( "ZID" );
		}
		
		if ( flag( "power_on" ) )
		{
			self ClientNotify( "ZPO" );
			
			if ( level.script == "zombie_theater" )
			{
				setclientsysstate( "box_indicator", [[ getFunction( "maps/zombie_theater_magic_box", "get_location_from_chest_index" ) ]]( level.chest_index ), self );
			}
			
			if ( level.script == "zombie_cosmodrome" )
			{
				setclientsysstate( "box_indicator", [[ getFunction( "maps/zombie_cosmodrome_magic_box", "get_location_from_chest_index" ) ]]( level.chest_index ), self );
			}
			
			if ( level.script == "zombie_pentagon" )
			{
				setclientsysstate( "box_indicator", [[ getFunction( "maps/zombie_pentagon_magic_box", "get_location_from_chest_index" ) ]]( level.chest_index ), self );
			}
		}
		else
		{
			if ( level.script == "zombie_cosmodrome" )
			{
				setclientsysstate( "box_indicator", level._cosmodrome_no_power, self );
			}
			
			if ( level.script == "zombie_pentagon" )
			{
				setclientsysstate( "box_indicator", level._pentagon_no_power, self );
			}
		}
	}
}

delay_give_back_fate( time )
{
	self endon( "disconnect" );
	
	wait time;
	
	if ( isdefined( level.fate_cache ) && isdefined( level.fate_cache[ self.entity_num + "" ] ) )
	{
		switch ( level.fate_cache[ self.entity_num + "" ] )
		{
			case "fortune":
				self [[ getFunction( "maps/_zombietron_fate", "fortune_fate" ) ]]();
				break;
				
			case "firepower":
				self [[ getFunction( "maps/_zombietron_fate", "firepower_fate" ) ]]();
				break;
				
			case "friendship":
				self [[ getFunction( "maps/_zombietron_fate", "friendship_fate" ) ]]();
				break;
				
			case "furious_feet":
				self [[ getFunction( "maps/_zombietron_fate", "furious_feet_fate" ) ]]();
				
				if ( self.boosters < 3 )
				{
					self.boosters = 3;
					self [[ getFunction( "maps/_zombietron_score", "update_hud" ) ]]();
				}
				
				break;
		}
	}
}

delay_reapply_fx_light( time )
{
	self endon( "disconnect" );
	
	wait time;
	
	players = get_players();
	
	for ( i = 0; i < players.size; i++ )
	{
		if ( players[ i ] != self && isdefined( players[ i ].light_playFX ) )
		{
			PlayFxOnTag( level._effect[ players[ i ].light_playFX ], players[ i ], "tag_origin" );
		}
	}
}

player_reset_score()
{
	self.score = 0;
	
	// scripts wait 1, so flag for all_players_spawned will already be set...
	if ( !isdefined( self.lives ) || self.lives != 0 )
	{
		self.lives = 3;
		self.bombs = 1;
		self.boosters = 2;
	}
	else
	{
		// hotjoined
		self thread delay_give_back_fate( 1 );
		self thread delay_reapply_fx_light( 1 );
	}
	
	self [[ getFunction( "maps/_zombietron_score", "update_multiplier_bar" ) ]]( 0 );
	self [[ getFunction( "maps/_zombietron_score", "update_hud" ) ]]();
}

spawn_the_spectators_doa()
{
	players = get_players();
	
	for ( i = 0; i < players.size; i++ )
	{
		if ( players[i].sessionstate == "spectator" )
		{
			players[i].lives = 0;
			players[i].bombs = 0;
			players[i].boosters = 0;
			players[i] thread [[ level.spawnPlayer ]]();
		}
	}
}

update_next_arena()
{
	spawn_the_spectators_doa();
	
	func = getFunction( "maps/_zombietron_main", "update_next_arena" );
	disableDetourOnce( func );
	self [[ func ]]();
}

all_players_connected()
{
	timeout_started = false;
	timeout_point = 0;
	
	while ( 1 )
	{
		num_con = getnumconnectedplayers();
		num_exp = getnumexpectedplayers();
		println( "all_players_connected(): getnumconnectedplayers=", num_con, "getnumexpectedplayers=", num_exp );
		
		if ( num_con == num_exp && ( num_exp != 0 ) )
		{
			break;
		}
		
		if ( num_con > 0 )
		{
			if ( !timeout_started )
			{
				timeout_started = true;
				timeout_point = getDvarFloat( "sv_connecttimeout" ) * 1000 + getTime();
			}
			
			if ( getTime() > timeout_point )
			{
				break;
			}
		}
		else
		{
			timeout_started = false;
		}
		
		wait( 0.05 );
	}
	
	flag_set( "all_players_connected" );
	// CODER_MOD: GMJ (08/28/08): Setting dvar for use by code
	SetDvar( "all_players_are_connected", "1" );
}

vending_trigger_think()
{
	// only do patches for revive
	if ( !IsDefined( self.script_noteworthy ) || ( self.script_noteworthy != "specialty_quickrevive" && self.script_noteworthy != "specialty_quickrevive_upgrade" ) )
	{
		func = getFunction( "maps/_zombiemode_perks", "vending_trigger_think" );
		disableDetourOnce( func );
		self [[ func ]]();
		return;
	}
	
	printf( "Replaced vending_trigger_think for nonsolo quickrevive" );
	
	flag_init( "_start_zm_pistol_rank" );
	
	flag_wait( "all_players_connected" );
	
	flag_set( "_start_zm_pistol_rank" );
	
	self SetHintString( &"ZOMBIE_NEED_POWER" );
	self SetCursorHint( "HINT_NOICON" );
	self UseTriggerRequireLookAt();
	
	self.cost = 1500;
	
	level waittill( self.script_noteworthy + "_power_on" );
	
	if ( !IsDefined( level._perkmachinenetworkchoke ) )
	{
		level._perkmachinenetworkchoke = 0;
	}
	else
	{
		level._perkmachinenetworkchoke++;
	}
	
	for ( i = 0; i < level._perkmachinenetworkchoke; i ++ )
	{
		wait_network_frame();
	}
	
	self thread [[ getFunction( "maps/_zombiemode_audio", "perks_a_cola_jingle_timer" ) ]]();
	
	perk_hum = spawn( "script_origin", self.origin );
	perk_hum playloopsound( "zmb_perks_machine_loop" );
	
	self thread [[ getFunction( "maps/_zombiemode_perks", "check_player_has_perk" ) ]]( self.script_noteworthy );
	
	self SetHintString( &"ZOMBIE_PERK_QUICKREVIVE", self.cost );
	
	for ( ;; )
	{
		self waittill( "trigger", player );
		
		if ( player [[ getFunction( "maps/_laststand", "player_is_in_laststand" ) ]]() || is_true( player.intermission ) )
		{
			continue;
		}
		
		if ( player [[ getFunction( "maps/_zombiemode_utility", "in_revive_trigger" ) ]]() )
		{
			continue;
		}
		
		if ( player isThrowingGrenade() )
		{
			wait( 0.1 );
			continue;
		}
		
		if ( player isSwitchingWeapons() )
		{
			wait( 0.1 );
			continue;
		}
		
		if ( player [[ getFunction( "maps/_zombiemode_utility", "is_drinking" ) ]]() )
		{
			wait( 0.1 );
			continue;
		}
		
		if ( player HasPerk( self.script_noteworthy ) )
		{
			cheat = false;
			
			/#
			if ( GetDvarInt( #"zombie_cheat" ) >= 5 )
			{
				cheat = true;
			}
			#/
			
			if ( cheat != true )
			{
				self playsound( "deny" );
				player [[ getFunction( "maps/_zombiemode_audio", "create_and_play_dialog" ) ]]( "general", "perk_deny", undefined, 1 );
				continue;
			}
		}
		
		if ( player.score < self.cost )
		{
			self playsound( "evt_perk_deny" );
			player [[ getFunction( "maps/_zombiemode_audio", "create_and_play_dialog" ) ]]( "general", "perk_deny", undefined, 0 );
			continue;
		}
		
		if ( player.num_perks >= 4 )
		{
			self playsound( "evt_perk_deny" );
			player [[ getFunction( "maps/_zombiemode_audio", "create_and_play_dialog" ) ]]( "general", "sigh" );
			continue;
		}
		
		playsoundatposition( "evt_bottle_dispense", self.origin );
		player [[ getFunction( "maps/_zombiemode_score", "minus_to_player_score" ) ]]( self.cost );
		
		player.perk_purchased = self.script_noteworthy;
		
		self thread [[ getFunction( "maps/_zombiemode_audio", "play_jingle_or_stinger" ) ]]( self.script_label );
		
		gun = player [[ getFunction( "maps/_zombiemode_perks", "perk_give_bottle_begin" ) ]]( self.script_noteworthy );
		player waittill_any( "fake_death", "death", "player_downed", "weapon_change_complete" );
		player [[ getFunction( "maps/_zombiemode_perks", "perk_give_bottle_end" ) ]]( gun, self.script_noteworthy );
		
		if ( player [[ getFunction( "maps/_laststand", "player_is_in_laststand" ) ]]() || is_true( player.intermission ) )
		{
			continue;
		}
		
		if ( isDefined( level.perk_bought_func ) )
		{
			player [[ level.perk_bought_func ]]( self.script_noteworthy );
		}
		
		player.perk_purchased = undefined;
		
		player [[ getFunction( "maps/_zombiemode_perks", "give_perk" ) ]]( self.script_noteworthy, true );
		
		bbPrint( "zombie_uses: playername %s playerscore %d teamscore %d round %d cost %d name %s x %f y %f z %f type perk", player.playername, player.score, level.team_pool[ player.team_num ].score, level.round_number, self.cost, self.script_noteworthy, self.origin );
	}
}

turn_revive_on()
{
	machine = getentarray( "vending_revive", "targetname" );
	machine_model = undefined;
	machine_clip = undefined;
	
	flag_wait( "all_players_connected" );
	level waittill( "revive_on" );
	
	for ( i = 0; i < machine.size; i++ )
	{
		if ( IsDefined( machine[i].classname ) && machine[i].classname == "script_model" )
		{
			machine[i] setmodel( "zombie_vending_revive_on" );
			machine[i] playsound( "zmb_perks_power_on" );
			machine[i] vibrate( ( 0, -100, 0 ), 0.3, 0.4, 3 );
			machine[i] thread [[ getFunction( "maps/_zombiemode_perks", "perk_fx" ) ]]( "revive_light" );
		}
	}
	
	level notify( "specialty_quickrevive_power_on" );
}

c_overseer()
{
	wait( 0.2 );
	
	flag_wait( "all_players_connected" );
	level._e_group = true;
	
	level [[ getFunction( "maps/zombie_coast_eggs", "summon_the_shamans" ) ]]();
	
	level thread [[ getFunction( "maps/zombie_coast_eggs", "knock_on_door" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "engage" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "noisemakers" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "rotary_styles" ) ]]();
	
	level thread [[ getFunction( "maps/zombie_coast_eggs", "cancer" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "aries" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "pisces" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "leo" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "capricorn" ) ]]();
	
	level thread [[ getFunction( "maps/zombie_coast_eggs", "virgo" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "denlo" ) ]]();
	level thread [[ getFunction( "maps/zombie_coast_eggs", "libra" ) ]]();
}

pistol_rank_setup()
{
	flag_init( "_start_zm_pistol_rank" );
	
	flag_wait( "all_players_connected" );
	
	flag_set( "_start_zm_pistol_rank" );
}

check_solo_game()
{
	flag_wait( "all_players_connected" );
}

team_score_init()
{
	//	NOTE: Make sure all players have connected before doing this.
	flag_wait( "all_players_connected" );
	
	level.team_pool = [];
	
	if ( IsDefined( level.zombiemode_versus ) && level.zombiemode_versus )
	{
		num_pools = 2;
	}
	else
	{
		num_pools = 1;
	}
	
	for ( i = 0; i < num_pools; i++ )
	{
		level.team_pool[i] = SpawnStruct();
		pool	= level.team_pool[i];
		pool.team_num	= i;
		pool.score	= 0;
		pool.old_score	= pool.score;
		pool.score_total	= pool.score;
		
		// Based on the Location of the player score from hud.menu
		pool.hud_x	= -103 + 5;	// 2nd # is an offset from the menu position to get it to line up
		pool.hud_y	= -71 - 36;	// 2nd # is spacing away from the player score
		
		if ( !IsSplitScreen() )
		{
			num = getDvarInt( "sv_maxclients" ) - 1;
			pool.hud_y += ( num + ( num_pools - 1 - i ) ) * -18;	// last number is a spacing gap from the player scores
		}
		
		//MM (3/10/10)	Disable team points
		//	pool.hud = create_team_hud( pool.score, pool );
	}
}

give_perk( perk, bought )
{
	self SetPerk( perk );
	self.num_perks++;
	
	if ( is_true( bought ) )
	{
		//AUDIO: Ayers - Sending Perk Name over to audio common script to play VOX
		self thread [[ getFunction( "maps/_zombiemode_audio", "perk_vox" ) ]]( perk );
		self setblur( 4, 0.1 );
		wait( 0.1 );
		self setblur( 0, 0.1 );
		//earthquake (0.4, 0.2, self.origin, 100);
		
		self notify( "perk_bought", perk );
	}
	
	if ( perk == "specialty_armorvest" )
	{
		self.preMaxHealth = self.maxhealth;
		self SetMaxHealth( level.zombie_vars["zombie_perk_juggernaut_health"] );
	}
	else if ( perk == "specialty_armorvest_upgrade" )
	{
		self.preMaxHealth = self.maxhealth;
		self SetMaxHealth( level.zombie_vars["zombie_perk_juggernaut_health_upgrade"] );
	}
	
	// WW (02-03-11): Deadshot csc call
	if ( perk == "specialty_deadshot" )
	{
		self SetClientFlag( level._ZOMBIE_PLAYER_FLAG_DEADSHOT_PERK );
	}
	else if ( perk == "specialty_deadshot_upgrade" )
	{
		self SetClientFlag( level._ZOMBIE_PLAYER_FLAG_DEADSHOT_PERK );
	}
	
	self [[ getFunction( "maps/_zombiemode_perks", "perk_hud_create" ) ]]( perk );
	
	//stat tracking
	self.stats["perks"]++;
	
	self thread [[ getFunction( "maps/_zombiemode_perks", "perk_think" ) ]]( perk );
}

extra_life_spawner()
{
	while ( 1 )
	{
		waittime = RandomFloatRange( level.zombie_vars["min_extra_life_spawn_time"], level.zombie_vars["max_extra_life_spawn_time"] );
		
		while ( waittime > 0 )
		{
			while ( !flag( "round_is_active" ) )
			{
				wait 5;
			}
			
			wait 5;
			waittime -= 5;
		}
		
		// extra wait if you have a lot of lives
		players = get_players();
		lives = 0;
		
		for ( i = 0; i < players.size; i++ )
		{
			if ( isdefined( players[i].lives ) )
			{
				lives += players[i].lives;
			}
		}
		
		waittime = lives * 10;
		
		while ( waittime > 0 )
		{
			while ( !flag( "round_is_active" ) )
			{
				wait 5;
			}
			
			wait 5;
			waittime -= 5;
		}
		
		if ( flag( "all_players_dead" ) )
		{
			continue;
		}
		
		spawn_point = [[ getFunction( "maps/_zombietron_pickups", "get_random_pickup_location" ) ]]();
		
		if ( isDefined( spawn_point ) )
		{
			type = "extra_life";
			
			origin = spawn_point.origin;
			
			pickup = Spawn( "script_model", origin );
			pickup.script_noteworthy = "a_pickup_item";
			
			yaw = RandomInt( 360 );
			pickup.angles = ( 0, yaw, 0 );
			pickup SetModel( level.extra_life_model );
			
			trigger = spawn( "trigger_radius", origin, 0, 30, 128 );
			
			pickup setclientflag( level._ZT_SCRIPTMOVER_CF_POWERUP );
			pickup.type = type;
			pickup thread [[ getFunction( "maps/_zombietron_pickups", "wait_for_pickup" ) ]]( type, trigger );
			pickup thread [[ getFunction( "maps/_zombietron_pickups", "powerup_timeout" ) ]]( trigger );
			pickup thread [[ getFunction( "maps/_zombietron_pickups", "powerup_wobble" ) ]]( trigger );
			
			pickup.trigger = trigger;
		}
	}
}
