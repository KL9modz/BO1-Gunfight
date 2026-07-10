/*
	_bot
	Author: INeedGames
	Date: 12/20/2020
	The entry point and manager of the bots.
*/

#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\bots\_bot_utility;

/*
	Entry point to the bots
*/
init()
{
	level.bw_VERSION = "1.1.1";

	level.bot_offline = false;

	if(getDvar("bots_main") == "")
		setDvar("bots_main", true);

	if (!getDvarInt("bots_main"))
		return;

	// Kill any bot threads left over from a PRIOR init. The lobby's map_restart(false)
	// wipes game[]/level[] (so the once-per-match game["gf_botInit"] gate in gf.gsc re-fires
	// and re-threads this init) but does NOT stop running threads — so without this the stock
	// manager loops (onPlayerConnect, watchers) and the fill reconciler would DOUBLE after every
	// lobby fast-restart. Every persistent loop below carries endon("bot_reinit"); firing it here,
	// before we re-thread, collapses to exactly one live set. (No-op on the first match — a notify
	// with no listeners does nothing.) Between rounds (map_restart(true)) game[] survives, the gate
	// does NOT re-fire, and the managers keep running — so this only triggers on a real re-init.
	level notify("bot_reinit");

	if(getDvar("bots_main_waitForHostTime") == "")
		setDvar("bots_main_waitForHostTime", 10.0);//how long to wait to wait for the host player

	if(getDvar("bots_manage_add") == "")
		setDvar("bots_manage_add", 0);//amount of bots to add to the game
	if(getDvar("bots_manage_fill") == "")
		setDvar("bots_manage_fill", 0);//amount of bots to maintain
	if(getDvar("bots_manage_fill_spec") == "")
		setDvar("bots_manage_fill_spec", true);//to count for fill if player is on spec team
	if(getDvar("bots_manage_fill_mode") == "")
		setDvar("bots_manage_fill_mode", 0);//fill mode, 0 adds everyone, 1 just bots, 2 maintains at maps, 3 is 2 with 1
	if(getDvar("bots_manage_fill_kick") == "")
		setDvar("bots_manage_fill_kick", false);//kick bots if too many
		
	if(getDvar("bots_team") == "")
		setDvar("bots_team", "autoassign");//which team for bots to join
	if(getDvar("bots_team_amount") == "")
		setDvar("bots_team_amount", 0);//amount of bots on axis team
	if(getDvar("bots_team_force") == "")
		setDvar("bots_team_force", false);//force bots on team
	if(getDvar("bots_team_mode") == "")
		setDvar("bots_team_mode", 0);//counts just bots when 1

	if(getDvar("bots_loadout_reasonable") == "")//filter out the bad 'guns' and perks
		setDvar("bots_loadout_reasonable", false);
	if(getDvar("bots_loadout_allow_op") == "")//allows jug, marty and laststand
		setDvar("bots_loadout_allow_op", true);
	if(getDvar("bots_loadout_rank") == "")// what rank the bots should be around, -1 is around the players, 0 is all random
		setDvar("bots_loadout_rank", -1);
	if(getDvar("bots_loadout_codpoints") == "")// how much cod points a bot should have, -1 is around the players, 0 is all random
		setDvar("bots_loadout_codpoints", -1);
	if(getDvar("bots_loadout_prestige") == "")// what pretige the bots will be, -1 is the players, -2 is random
		setDvar("bots_loadout_prestige", -1);

	if(getDvar("bots_play_target_other") == "")//bot target non play ents (vehicles)
		setDvar("bots_play_target_other", true);
	if(getDvar("bots_play_killstreak") == "")//bot use killstreaks
		setDvar("bots_play_killstreak", true);
	if(getDvar("bots_play_nade") == "")//bots grenade
		setDvar("bots_play_nade", true);
	if(getDvar("bots_play_knife") == "")//bots knife
		setDvar("bots_play_knife", true);
	if(getDvar("bots_play_fire") == "")//bots fire
		setDvar("bots_play_fire", true);
	if(getDvar("bots_play_move") == "")//bots move
		setDvar("bots_play_move", true);
	if(getDvar("bots_play_take_carepackages") == "")//bots take carepackages
		setDvar("bots_play_take_carepackages", true);
	if(getDvar("bots_play_obj") == "")//bots play the obj
		setDvar("bots_play_obj", true);
	if(getDvar("bots_play_camp") == "")//bots camp and follow
		setDvar("bots_play_camp", true);

	level.bots = [];
	level.bot_decoys = [];
	level.bot_planes = [];

	if(!isDefined(game["botWarfare"]))
		game["botWarfare"] = true;

	thread fixGamemodes();
	thread onPlayerConnect();
	thread bot_watch_planes();

	thread handleBots();
	// doNonDediBots() is RETIRED — it drove the old teamBots() rebalance (bots_team custom /
	// bots_team_force) which the reconciler replaces. Local "Basic Training" now just sets
	// gf_fill_n to the desired per-team N.
}

/*
	Thread when any player connects. Starts the threads needed.
*/
onPlayerConnect()
{
	level endon("bot_reinit");   // die if _bot::init re-runs (lobby map_restart(false)) so we don't double-handle connects

	for(;;)
	{
		level waittill("connected", player);

		player thread watch_shoot();
		player thread watch_grenade();
		player thread connected();
	}
}

/*
	Starts the threads for bots.

	diffBots keeps setting bot difficulty (unrelated to counts/teams). The OLD count loop
	(addBots) and team-balance loop (teamBots) are RETIRED — replaced by gf_reconcilerInit(),
	the Gunfight fill reconciler (see the big block below). The reconciler is the single
	authority over how many bots are on each team and which team each bot is on.
*/
handleBots()
{
	thread diffBots();
	thread gf_reconcilerInit();
}

// ============================================================================
// GUNFIGHT DYNAMIC FILL RECONCILER
// ----------------------------------------------------------------------------
// Replaces the stock BotWarfare addBots()/teamBots() loops (both retired, left as dead
// code below) with ONE authority over bot COUNTS and PLACEMENT. Source of truth = the
// dvar gf_fill_n (per-team target N; each side is padded to N *playing* clients, humans+
// bots, with bots absorbing the variance). It MUST be a dvar — the only state that
// survives the lobby's map_restart(false).
//
// Invariant: each team = exactly N playing, BOTS-ONLY. Humans are NEVER moved — if the
// humans on a side exceed N, that side's bots drop to 0 and it may exceed N; the OTHER
// side still fills to N. A joining human displaces a bot on his side (that bot PARKS in
// spectator for reuse; it is KICKED instead under client-slot pressure so a human can
// always connect, and REDUCING the fill number kicks the freed bots too). Displacement
// is event-driven (human connect/disconnect) with a slow safety poll as the backstop.
//
// gf_fill_n == 0 => reconciler INERT (fill off): bots are left alone so the RCON panel's
// manual per-team add/kick/move sticks. That is why "move a bot and have it stick" needs
// fill off; with fill on, bot placement is reconciler-owned (counts stick, identity doesn't).
//
// Counts key off level.players + istestclient() (NOT level.bots), so the reconciler stays
// correct even if a restart disturbs BotWarfare's own bookkeeping. Overshoot-free: parked
// bots are reused from a finite pool, and NEW bots are added at most one-in-flight-at-a-time.
// Every persistent loop carries endon("bot_reinit") so a lobby map_restart(false) (which
// re-runs _bot::init but does NOT stop threads) collapses back to exactly one live set.
// ============================================================================

gf_reconcilerInit()
{
	level endon("bot_reinit");

	// Clear any stale in-flight deploy marker. bot_reinit kills gf_botDeployWhenReady watchers
	// without running their cleanup, but the BOT ENTITY survives a map_restart(false) — a leftover
	// .gf_fillPending would count that bot as forever-inflight and wedge the one-add-at-a-time
	// throttle (no bot could ever be added again). Sweep it here, right after the notify.
	for(i = 0; i < level.players.size; i++)
		if(isDefined(level.players[i]))
			level.players[i].gf_fillPending = undefined;

	level.gf_reconcileDirty = true;      // request an immediate first pass
	thread gf_reconcilerDriver();
	thread gf_reconcilerEvents();
}

// Single serialized driver: runs at most ONE reconcile pass per tick. GSC has no preemption,
// so a pass runs atomically, but a pass THREADS its team-switches/adds (async) — the 0.5s tick
// lets those land before the next count, so we never re-act on a not-yet-applied change.
// Coalesces event requests via level.gf_reconcileDirty and force-passes every ~3s as a backstop.
gf_reconcilerDriver()
{
	level endon("game_ended");
	level endon("bot_reinit");

	sinceForced = 0;
	for(;;)
	{
		wait 0.5;
		sinceForced += 0.5;

		doPass = (isDefined(level.gf_reconcileDirty) && level.gf_reconcileDirty);
		if(sinceForced >= 3)
		{
			doPass = true;
			sinceForced = 0;
		}
		if(doPass)
		{
			level.gf_reconcileDirty = false;
			gf_reconcilePass();
		}
	}
}

// Ask the driver to run a pass on its next tick (<=0.5s). Cheap; safe to spam.
gf_reconcileRequest()
{
	level.gf_reconcileDirty = true;
}

// Event-driven displacement: a HUMAN joining team T must make a bot on T yield promptly, and a
// human LEAVING must let a bot re-pad. Bots/democlients don't trigger it.
gf_reconcilerEvents()
{
	level endon("game_ended");
	level endon("bot_reinit");

	for(;;)
	{
		level waittill("connecting", p);
		if(!isDefined(p))
			continue;
		if(p istestclient() || p isdemoclient())
			continue;
		p thread gf_reconcileOnHumanConnect();
		p thread gf_reconcileOnHumanDisconnect();
	}
}

gf_reconcileOnHumanConnect()
{
	self endon("disconnect");
	level endon("bot_reinit");

	// Wait until the human lands on a real team (autoassign / team pick), then request a pass so
	// a bot on his side yields. Bounded so a team-menu camper can't wedge the thread.
	ticks = 0;
	while(ticks < 300 && !(isDefined(self.pers["team"]) && (self.pers["team"] == "allies" || self.pers["team"] == "axis")))
	{
		wait 0.1;
		ticks++;
	}
	gf_reconcileRequest();
}

gf_reconcileOnHumanDisconnect()
{
	level endon("bot_reinit");

	self waittill("disconnect");
	gf_reconcileRequest();               // freed a slot -> re-pad next pass
}

// Classify level.players. Buckets: <team>_human / <team>_bot (on a real team), parked (a
// CONNECTED bot in spectator — the reusable pool, listed in parkedBots), inflight (a bot still
// connecting with no team yet — throttles new adds). A human in spectator is neutral.
gf_reconcileCount()
{
	r = [];
	r["allies_human"] = 0; r["allies_bot"] = 0;
	r["axis_human"]   = 0; r["axis_bot"]   = 0;
	r["parked"]       = 0; r["inflight"]   = 0; r["clients"] = 0;
	r["parkedBots"]   = [];

	players = level.players;
	for(i = 0; i < players.size; i++)
	{
		p = players[i];
		if(!isDefined(p))
			continue;
		if(p isdemoclient())             // server-side democlient: never counted, never touched
			continue;
		r["clients"]++;
		t = p.pers["team"];
		onTeam = (isDefined(t) && (t == "allies" || t == "axis"));

		if(p istestclient())
		{
			// A bot still being STEERED to its target team by gf_botDeployWhenReady is in flight
			// regardless of where it currently sits. This matters because the stock connect path
			// parks a fresh bot in "spectator" (and teamWatch may then autoassign it to the WRONG
			// team) before the watcher lands it — without this, the parked pool would steal it, or
			// the wrong-team count would skew the deficit, causing a double-switch / overshoot.
			if(isDefined(p.gf_fillPending))
			{
				r["inflight"]++;
				continue;
			}
			if(onTeam)
				r[t + "_bot"]++;
			else if(isDefined(t) && t == "spectator")
			{
				r["parked"]++;
				r["parkedBots"][r["parkedBots"].size] = p;
			}
			else
				r["inflight"]++;         // connecting / no team resolved yet
			continue;
		}

		if(onTeam)
			r[t + "_human"]++;
		// human in spectator: ignored (don't pad against a slot he isn't using)
	}
	return r;
}

// One reconcile pass. Runs to completion without yielding (all switches/adds are threaded), so
// it is atomic vs. other passes.
gf_reconcilePass()
{
	n = gf_fillTarget();
	if(n <= 0)
		return;                          // fill OFF -> reconciler inert (manual bot control sticks)

	c = gf_reconcileCount();

	maxClients = getDvarInt("sv_maxclients");
	if(maxClients < 1) maxClients = 18;
	ceiling = maxClients - gf_fillKickFloor();

	teams = [];
	teams[0] = "allies";
	teams[1] = "axis";

	// --- DEPLOY: fill each team's deficit. Reuse parked bots first (one shared index across both
	// teams -> no double-assign), then add NEW bots but only while nothing is in flight
	// (overshoot-free: the next pass adds more once this add lands and stops being "inflight"). ---
	pool     = c["parkedBots"];
	pi       = pool.size;
	inflight = c["inflight"];
	totalDeficit = 0;
	for(ti = 0; ti < 2; ti++)
	{
		team = teams[ti];
		need = n - (c[team + "_human"] + c[team + "_bot"]);
		if(need <= 0)
			continue;
		totalDeficit += need;

		while(need > 0 && pi > 0)
		{
			pi--;
			b = pool[pi];
			if(isDefined(b))
			{
				b thread gf_botSwitchTeam(team);
				need--;
			}
		}
		if(need > 0 && inflight <= 0)
		{
			bot = add_bot();
			if(isDefined(bot))
			{
				bot.gf_fillPending = team;   // in flight until the watcher lands it on `team`
				bot thread gf_botDeployWhenReady(team);
				inflight++;              // one add in flight at a time -> overshoot-free
			}
		}
	}

	// --- PARK: trim each team's bot surplus (bots-only). Runs EVERY pass, but gf_parkBots only
	// ever moves a SWITCH-SAFE bot (dead / spectator / limbo — see gf_botSwitchSafe). That is what
	// removes both old bugs at once: (1) it never spectates a live prematch-frozen bot, so no
	// "bot suicides at spawn"; (2) it never removes a team's last-ALIVE bot, so no phantom
	// round-end — which is why the old "between rounds only" gate is no longer needed. In one-life
	// gunfight a surplus bot is trimmed the moment it DIES during the round (invisible — already
	// dead), so a human who joined mid-round has his side back at exactly N by the next round. A
	// surplus bot that survives the whole round simply trims a round later; it never suicides. ---
	for(ti = 0; ti < 2; ti++)
	{
		team    = teams[ti];
		bots    = c[team + "_bot"];
		surplus = (c[team + "_human"] + bots) - n;
		if(surplus > bots)               // humans-only overflow: leave the side big, never move a human
			surplus = bots;
		if(surplus > 0)
			gf_parkBots(team, surplus);
	}

	// --- CLEANUP (only when no team still needs bots): keep a parked RESERVE == the humans
	// currently playing (each could leave and reopen a slot) and stay under the client ceiling;
	// KICK the excess. This makes "reduce the fill number" kick the freed bots (0 humans -> 0
	// reserve -> all parked kicked) while a human-displaced bot still PARKS for instant reuse. ---
	if(totalDeficit == 0 && pi > 0)
	{
		reserve = c["allies_human"] + c["axis_human"];   // one parked bot per playing human (each could leave)
		// ...but never keep so many parked that total clients breach the ceiling (this also relieves
		// slot pressure so a human can always connect). clients-parked = every non-parked client.
		maxReserve = ceiling - (c["clients"] - c["parked"]);
		if(reserve > maxReserve)
			reserve = maxReserve;
		if(reserve < 0)
			reserve = 0;
		excess = pi - reserve;           // pi == parked here (deploy consumed none: no deficit)
		for(k = 0; k < excess; k++)
		{
			b = pool[k];
			if(isDefined(b))
				kick(b getEntityNumber(), "EXE_PLAYERKICKED");
		}
	}
}

// Move a bot to `team`. Bots are fungible, so the stock switch is fine (a not-yet-playing bot is
// assigned+spawned; a playing bot is respawned — harmless). Threaded by callers.
gf_botSwitchTeam(team)
{
	if(team == "allies")        self [[level.allies]]();
	else if(team == "axis")     self [[level.axis]]();
	else                        self [[level.spectator]]();
}

// Is it safe to stock-switch this bot's team RIGHT NOW without a VISIBLE suicide or a phantom
// round-end? The stock switch (level.allies/axis/spectator == menuAllies/menuAxis/menuSpectator)
// calls suicide() on a "playing" client. So it's only unsafe while the bot is a LIVE, playing
// entity — spawned AND alive, which includes the prematch-frozen state (that is exactly the
// "bot suicides at spawn" the retired teamBots hit). A DEAD bot (one-life gunfight: eliminated
// for the round) or a spectator/limbo bot can be moved with zero visible suicide AND without
// touching the live alive-count, so moving it can never phantom-end the round. This single gate
// is the invariant the RCON bridge + the retired teamBots both settled on.
gf_botSwitchSafe()
{
	if(isDefined(self.sessionstate) && self.sessionstate == "playing" && isDefined(self.health) && self.health > 0)
		return false;
	return true;
}

// A freshly add_bot()'d bot connects async; wait for it to land, then place it on `team`. It is
// marked .gf_fillPending (counted in-flight) for the whole trip so no pass can steal or miscount
// it. If it never connects (timeout with no team) drop it so a wedged connect can't block the
// fill's one-in-flight throttle forever. On completion we clear the marker and request the NEXT
// pass immediately — that's what makes a cold fill converge at ~one bot per driver tick (0.5s)
// instead of crawling on the 3s safety backstop.
gf_botDeployWhenReady(team)
{
	self endon("disconnect");
	level endon("bot_reinit");

	ticks = 0;
	while(ticks < 100 && !isDefined(self.pers["team"]))
	{
		wait 0.1;
		ticks++;
	}
	if(!isDefined(self))
		return;
	if(!isDefined(self.pers["team"]))
	{
		kick(self getEntityNumber(), "EXE_PLAYERKICKED");   // never connected -> unwedge the throttle
		return;
	}
	// Autoassign (bots_team "autoassign") usually drops the fresh bot straight onto the deficit
	// team we targeted; when it doesn't, correct it — but ONLY while the bot is still limbo/
	// spectator (switch-safe). If autoassign already SPAWNED it (alive) on the wrong side, do NOT
	// stock-switch it: that's a visible spawn-suicide. Leave it on that team (it still counts) and
	// let the next pass rebalance composition — the wrong-side surplus parks as its bots die. ---
	if(self.pers["team"] != team && self gf_botSwitchSafe())
		self gf_botSwitchTeam(team);

	self.gf_fillPending = undefined;     // landed: release the throttle...
	gf_reconcileRequest();               // ...and let the driver deploy the next one right away
}

// Park `count` DISTINCT surplus bots from `team` (collected up front so the async switches don't
// re-pick the same bot): move each to spectator for reuse, or KICK it under slot pressure so
// parked bots can't lock a human out. Only SWITCH-SAFE bots (dead / spectator / limbo) are
// eligible — a live/prematch-frozen bot is skipped so we never spawn-suicide it or pull a team's
// last-alive bot (phantom round-end). Fewer-than-count eligible just trims fewer now; the surplus
// keeps getting recomputed each pass and finishes trimming as its bots die.
gf_parkBots(team, count)
{
	picks = [];
	players = level.players;
	for(i = 0; i < players.size && picks.size < count; i++)
	{
		p = players[i];
		if(!isDefined(p) || !(p istestclient()))
			continue;
		if(!(p gf_botSwitchSafe()))       // live/frozen bot: leave it, trim it when it dies
			continue;
		if(isDefined(p.pers["team"]) && p.pers["team"] == team)
			picks[picks.size] = p;
	}

	maxClients = getDvarInt("sv_maxclients");
	if(maxClients < 1) maxClients = 18;
	ceiling = maxClients - gf_fillKickFloor();
	for(i = 0; i < picks.size; i++)
	{
		if(level.players.size >= ceiling)
			kick(picks[i] getEntityNumber(), "EXE_PLAYERKICKED");
		else
			picks[i] thread gf_botSwitchTeam("spectator");
	}
}

// Per-team fill target N (clamped 0-6). 0 = fill off.
gf_fillTarget()
{
	n = getDvarInt("gf_fill_n");
	if(n < 0) n = 0;
	if(n > 6) n = 6;
	return n;
}

// Client-slot headroom to keep free for humans (>=0).
gf_fillKickFloor()
{
	f = getDvarInt("gf_fill_kick_floor");
	if(f < 0) f = 0;
	return f;
}

/*
	When a bot disconnects.
*/
onDisconnect()
{
	self waittill("disconnect");
		
	level.bots = array_remove(level.bots, self);
}

/*
	Whena	player connects
*/
connected()
{
	self endon("disconnect");

	if (!self is_bot())
		return;

	self thread maps\mp\bots\_bot_script::connected();

	level.bots[level.bots.size] = self;
	self thread onDisconnect();

	level notify("bot_connected", self);
}

/*
	Handles the diff of the bots
*/
diffBots()
{
	level endon("bot_reinit");   // one copy only across a lobby re-init

	for (;;)
	{
		wait 1.5;

		bot_set_difficulty(GetDvar( #"bot_difficulty" ));
	}
}

/*
	Setup bot dvars for non dedicated clients
*/
doNonDediBots()
{
	if (!GetDvarInt( #"xblive_basictraining" ))
		return;

	if (isDefined(game[ "bots_spawned" ]))
		return;

	game[ "bots_spawned" ] = true;

	if(getDvar("bot_enemies_extra") == "")
		setDvar("bot_enemies_extra", 0);
	if(getDvar("bot_friends_extra") == "")
		setDvar("bot_friends_extra", 0);

	bot_friends = GetDvarInt( #"bot_friends" );
	bot_enemies = GetDvarInt( #"bot_enemies" );

	bot_enemies += GetDvarInt("bot_enemies_extra");
	bot_friends += GetDvarInt("bot_friends_extra");

	bot_wait_for_host();
	host = GetHostPlayer();

	team = "allies";
	if(isDefined(host) && isDefined(host.pers[ "team" ]) && (host.pers[ "team" ] == "allies" || host.pers[ "team" ] == "axis"))
		team = host.pers[ "team" ];

	setDvar("bots_manage_add", bot_enemies + bot_friends - 1);
	setDvar("bots_manage_fill", bot_enemies + bot_friends);
	setDvar("bots_manage_fill_mode", 0);
	setDvar("bots_manage_fill_kick", true);
	setDvar("bots_manage_fill_spec", false);

	setDvar("bots_team", "custom");

	if (team == "axis")
		setDvar("bots_team_amount", bot_friends);
	else
		setDvar("bots_team_amount", bot_enemies);

	setDvar("bots_team_force", true);
	setDvar("bots_team_mode", 0);
}

/*
	Sets the difficulty of the bots
*/
bot_set_difficulty( difficulty )
{
	if ( difficulty == "fu" )
	{
		SetDvar( "sv_botMinDeathTime",		"250" );
		SetDvar( "sv_botMaxDeathTime",		"500" );
		SetDvar( "sv_botMinFireTime",		"100" );
		SetDvar( "sv_botMaxFireTime",		"300" );
		SetDvar( "sv_botYawSpeed",			"14" );
		SetDvar( "sv_botYawSpeedAds",		"14" );
		SetDvar( "sv_botPitchUp",			"-5" );
		SetDvar( "sv_botPitchDown",			"10" );
		SetDvar( "sv_botFov",				"160" );
		SetDvar( "sv_botMinAdsTime",		"3000" );
		SetDvar( "sv_botMaxAdsTime",		"5000" );
		SetDvar( "sv_botMinCrouchTime",		"100" );
		SetDvar( "sv_botMaxCrouchTime",		"400" );
		SetDvar( "sv_botTargetLeadBias",	"2" );
		SetDvar( "sv_botMinReactionTime",	"30" );
		SetDvar( "sv_botMaxReactionTime",	"100" );
		SetDvar( "sv_botStrafeChance",		"1" );
		SetDvar( "sv_botMinStrafeTime",		"3000" );
		SetDvar( "sv_botMaxStrafeTime",		"6000" );
		SetDvar( "scr_help_dist",			"512" );
		SetDvar( "sv_botAllowGrenades",		"1"	);
		SetDvar( "sv_botMinGrenadeTime",	"1500" );
		SetDvar( "sv_botMaxGrenadeTime",	"4000" );
		SetDvar( "sv_botSprintDistance",	"512"	);
		SetDvar( "sv_botMeleeDist",			"80" );
	}
	else if ( difficulty == "hard" )
	{
		SetDvar( "sv_botMinDeathTime",		"250" );
		SetDvar( "sv_botMaxDeathTime",		"500" );
		SetDvar( "sv_botMinFireTime",		"400" );
		SetDvar( "sv_botMaxFireTime",		"600" );
		SetDvar( "sv_botYawSpeed",			"8" );
		SetDvar( "sv_botYawSpeedAds",		"10" );
		SetDvar( "sv_botPitchUp",			"-5" );
		SetDvar( "sv_botPitchDown",			"10" );
		SetDvar( "sv_botFov",				"100" );
		SetDvar( "sv_botMinAdsTime",		"3000" );
		SetDvar( "sv_botMaxAdsTime",		"5000" );
		SetDvar( "sv_botMinCrouchTime",		"100" );
		SetDvar( "sv_botMaxCrouchTime",		"400" );
		SetDvar( "sv_botTargetLeadBias",	"2" );
		SetDvar( "sv_botMinReactionTime",	"400" );
		SetDvar( "sv_botMaxReactionTime",	"700" );
		SetDvar( "sv_botStrafeChance",		"0.9" );
		SetDvar( "sv_botMinStrafeTime",		"3000" );
		SetDvar( "sv_botMaxStrafeTime",		"6000" );
		SetDvar( "scr_help_dist",			"384" );
		SetDvar( "sv_botAllowGrenades",		"1"	);
		SetDvar( "sv_botMinGrenadeTime",	"1500" );
		SetDvar( "sv_botMaxGrenadeTime",	"4000" );
		SetDvar( "sv_botSprintDistance",	"512"	);
		SetDvar( "sv_botMeleeDist",			"80" );
	}
	else if ( difficulty == "easy" )
	{
		SetDvar( "sv_botMinDeathTime",		"1000" );
		SetDvar( "sv_botMaxDeathTime",		"2000" );
		SetDvar( "sv_botMinFireTime",		"900" );
		SetDvar( "sv_botMaxFireTime",		"1000" );
		SetDvar( "sv_botYawSpeed",			"2" );
		SetDvar( "sv_botYawSpeedAds",		"2.5" );
		SetDvar( "sv_botPitchUp",			"-20" );
		SetDvar( "sv_botPitchDown",			"40" );
		SetDvar( "sv_botFov",				"50" );
		SetDvar( "sv_botMinAdsTime",		"3000" );
		SetDvar( "sv_botMaxAdsTime",		"5000" );
		SetDvar( "sv_botMinCrouchTime",		"4000" );
		SetDvar( "sv_botMaxCrouchTime",		"6000" );
		SetDvar( "sv_botTargetLeadBias",	"8" );
		SetDvar( "sv_botMinReactionTime",	"1200" );
		SetDvar( "sv_botMaxReactionTime",	"1600" );
		SetDvar( "sv_botStrafeChance",		"0.1" );
		SetDvar( "sv_botMinStrafeTime",		"3000" );
		SetDvar( "sv_botMaxStrafeTime",		"6000" );
		SetDvar( "scr_help_dist",			"256" );
		SetDvar( "sv_botAllowGrenades",		"0"	);
		SetDvar( "sv_botSprintDistance",	"1024"	);
		SetDvar( "sv_botMeleeDist",			"40" );
	}
	else // 'normal' difficulty
	{
		SetDvar( "sv_botMinDeathTime",		"500" );
		SetDvar( "sv_botMaxDeathTime",		"1000" );
		SetDvar( "sv_botMinFireTime",		"600" );
		SetDvar( "sv_botMaxFireTime",		"800" );
		SetDvar( "sv_botYawSpeed",			"4" );
		SetDvar( "sv_botYawSpeedAds",		"5" );
		SetDvar( "sv_botPitchUp",			"-10" );
		SetDvar( "sv_botPitchDown",			"20" );
		SetDvar( "sv_botFov",				"70" );
		SetDvar( "sv_botMinAdsTime",		"3000" );
		SetDvar( "sv_botMaxAdsTime",		"5000" );
		SetDvar( "sv_botMinCrouchTime",		"2000" );
		SetDvar( "sv_botMaxCrouchTime",		"4000" );
		SetDvar( "sv_botTargetLeadBias",	"4" );
		SetDvar( "sv_botMinReactionTime",	"800" );
		SetDvar( "sv_botMaxReactionTime",	"1200" );
		SetDvar( "sv_botStrafeChance",		"0.6" );
		SetDvar( "sv_botMinStrafeTime",		"3000" );
		SetDvar( "sv_botMaxStrafeTime",		"6000" );
		SetDvar( "scr_help_dist",			"256" );
		SetDvar( "sv_botAllowGrenades",		"1"	);
		SetDvar( "sv_botMinGrenadeTime",	"1500" );
		SetDvar( "sv_botMaxGrenadeTime",	"4000" );
		SetDvar( "sv_botSprintDistance",	"512"	);
		SetDvar( "sv_botMeleeDist",			"80" );
		difficulty = "normal";
	}

	if ( level.gameType == "oic" && difficulty == "fu" )
	{
		SetDvar( "sv_botMinReactionTime",		"400" );
		SetDvar( "sv_botMaxReactionTime",		"500" );
		SetDvar( "sv_botMinAdsTime",		"1000" );
		SetDvar( "sv_botMaxAdsTime",		"2000" );
	}

	if ( level.gameType == "oic" && ( difficulty == "hard" || difficulty == "fu" ) )
	{
		SetDvar( "sv_botSprintDistance",	"256" );
	}

	if (!getDvarInt("bots_play_nade"))
		SetDvar( "sv_botAllowGrenades",		"0"	);
		
	SetDvar( "bot_difficulty", difficulty );
	SetDvar( "scr_bot_difficulty", difficulty );
	SetDvar( "splitscreen_botDifficulty", difficulty );
}

/*
	A server thread for monitoring all bot's teams for custom server settings.
*/
teamBots()
{
	for(;;)
	{
		wait 1.5;

		// Never move bots between teams while a round is live — a mid-round team
		// change triggers [[level.allies/axis]]() which respawns the bot, which
		// is what causes bots to appear on the wrong side during round 1.
		if ( isDefined( level.gf_roundActive ) && level.gf_roundActive )
			continue;

		teamAmount = getDvarInt("bots_team_amount");
		toTeam = getDvar("bots_team");
		
		alliesbots = 0;
		alliesplayers = 0;
		axisbots = 0;
		axisplayers = 0;
		
		playercount = level.players.size;
		for(i = 0; i < playercount; i++)
		{
			player = level.players[i];
			
			if(!isDefined(player.pers["team"]))
				continue;
			
			if(player is_bot())
			{
				if(player.pers["team"] == "allies")
					alliesbots++;
				else if(player.pers["team"] == "axis")
					axisbots++;
			}
			else
			{
				if(player.pers["team"] == "allies")
					alliesplayers++;
				else if(player.pers["team"] == "axis")
					axisplayers++;
			}
		}
		
		allies = alliesbots;
		axis = axisbots;
		
		if(!getDvarInt("bots_team_mode"))
		{
			allies += alliesplayers;
			axis += axisplayers;
		}
		
		if(toTeam != "custom")
		{
			if(getDvarInt("bots_team_force"))
			{
				if(toTeam == "autoassign")
				{
					if(abs(axis - allies) > 1)
					{
						toTeam = "axis";
						if(axis > allies)
							toTeam = "allies";
					}
				}
				
				if(toTeam != "autoassign")
				{
					playercount = level.players.size;
					for(i = 0; i < playercount; i++)
					{
						player = level.players[i];
						
						if(!isDefined(player.pers["team"]))
							continue;
						
						if(!player is_bot())
							continue;

						// Only ever switch a bot that is NOT yet in-world this round.
						// [[level.allies/axis/spectator]]() (stock menuAllies/menuAxis)
						// suicide()s the player if sessionstate == "playing" — and during
						// the connect/fill window every already-spawned bot is "playing"
						// (frozen in prematch), so re-balancing them here is the "bots
						// suicide mid-connect" bug. A spectator/limbo bot is safe to place.
						if(player.sessionstate == "playing")
							continue;

						if(player.pers["team"] == toTeam)
							continue;

						if (toTeam == "allies")
							player thread [[level.allies]]();
						else if (toTeam == "axis")
							player thread [[level.axis]]();
						else
							player thread [[level.spectator]]();
						break;
					}
				}
			}
		}
		else
		{
			playercount = level.players.size;
			for(i = 0; i < playercount; i++)
			{
				player = level.players[i];
				
				if(!isDefined(player.pers["team"]))
					continue;
				
				if(!player is_bot())
					continue;

				// Same guard as the force branch: never switch an already-spawned
				// ("playing") bot — the stock team switch suicide()s it. Placing a
				// not-yet-spawned (spectator/limbo) bot is harmless, so custom-amount
				// assignment of freshly-connected bots still works.
				if(player.sessionstate == "playing")
					continue;

				if(player.pers["team"] == "axis")
				{
					if(axis > teamAmount)
					{
						player thread [[level.allies]]();
						break;
					}
				}
				else
				{
					if(axis < teamAmount)
					{
						player thread [[level.axis]]();
						break;
					}
					else if(player.pers["team"] != "allies")
					{
						player thread [[level.allies]]();
						break;
					}
				}
			}
		}
	}
}

/*
	A server thread for monitoring all bot's in game. Will add and kick bots according to server settings.

	Dedis only spawn bots when developer is not 0
	This makes the dedi unstable and can crash

	Patch the executable to skip the pregame and make it so bots can spawn

	pregame:
		in the ShouldDoPregame sub:
					 B8 01 00 00 00: mov eax, 1
change to: B8 00 00 00 00: mov eax, 0
			0x4F6C77 in rektmp
			0x4598A7 in bg


	spawnbots:
		in the SV_AddTestClient sub:
					 0F 85 A4 00 00 00: jnz
change to: 0F 84 A4 00 00 00: jz
			0x6B6180 in rektmp
			0x4682F0 in bg


	allow changing g_antilag dvar:
		set the byte from 0x40 to 0x00
		
		0x53B1B2 in rekt
		0x59B6F2 in bg
*/
addBots()
{
	level endon ( "game_ended" );

	bot_wait_for_host();

	for (;;)
	{
		wait 1.5;
		
		botsToAdd = GetDvarInt("bots_manage_add");
		
		if(botsToAdd > 0)
		{
			SetDvar("bots_manage_add", 0);
			
			if(botsToAdd > 64)
				botsToAdd = 64;
				
			// Spread the fill: each add_bot() is a connect + gf_giveCustomLoadout +
			// HUD reveal, and the whole round-1 deficit drains here back-to-back. At
			// 0.25s/bot a 6v6 fill packs ~3s of that into the wait(1.0)-driven prematch
			// countdown, and on the VPS that spike stalls a few server frames -> the
			// countdown dilates into visible slow-mo (the wait-scaled prematch is the one
			// visible timer not gettime()-anchored). 0.5s halves the peak add-rate; safe
			// now that bots are excluded from the roster + load gates, so the fill no
			// longer has to beat prematch_over. (Real fix = gettime()-own the countdown.)
			for(; botsToAdd > 0; botsToAdd--)
			{
				level add_bot();
				wait 0.5;
			}
		}
		
		fillMode = getDVarInt("bots_manage_fill_mode");
		
		if(fillMode == 2 || fillMode == 3)
			setDvar("bots_manage_fill", getGoodMapAmount());
		
		fillAmount = getDvarInt("bots_manage_fill");
		
		players = 0;
		bots = 0;
		spec = 0;
		
		playercount = level.players.size;
		for(i = 0; i < playercount; i++)
		{
			player = level.players[i];

			if (player isdemoclient())
				continue;
			
			if(player is_bot())
				bots++;
			else if(!isDefined(player.pers["team"]) || (player.pers["team"] != "axis" && player.pers["team"] != "allies"))
				spec++;
			else
				players++;
		}
		
		if(fillMode == 4)
		{
			axisplayers = 0;
			alliesplayers = 0;
			
			playercount = level.players.size;
			for(i = 0; i < playercount; i++)
			{
				player = level.players[i];
				
				if(player is_bot())
					continue;
				
				if(!isDefined(player.pers["team"]))
					continue;
				
				if(player.pers["team"] == "axis")
					axisplayers++;
				else if(player.pers["team"] == "allies")
					alliesplayers++;
			}
			
			result = fillAmount - abs(axisplayers - alliesplayers) + bots;
			
			if (players == 0)
			{
				if(bots < fillAmount)
					result = fillAmount-1;
				else if (bots > fillAmount)
					result = fillAmount+1;
				else
					result = fillAmount;
			}
			
			bots = result;
		}

		if (!randomInt(999))
		{
			setDvar("testclients_doreload", true);
			wait 0.1;
			setDvar("testclients_doreload", false);
			doExtraCheck();
		}
		
		amount = bots;
		if(fillMode == 0 || fillMode == 2)
			amount += players;
		if(getDVarInt("bots_manage_fill_spec"))
			amount += spec;
			
		if(amount < fillAmount)
			setDvar("bots_manage_add", fillAmount - amount);//whole deficit in one batch (0.25s/bot); one-per-1.5s-pass lost the round-1 prematch race
		else if(amount > fillAmount && getDvarInt("bots_manage_fill_kick"))
		{
			tempBot = PickRandom(getBotArray());
			if (isDefined(tempBot))
				kick( tempBot getEntityNumber(), "EXE_PLAYERKICKED" );
		}
	}
}

/*
	Adds a bot to the game.
*/
add_bot()
{
	bot = addtestclient();

	if (isdefined(bot))
	{
		bot.pers["isBot"] = true;
		bot.equipment_enabled = true;
		bot.pers[ "bot_perk" ] = true;
		bot.pers["isBotWarfare"] = true;
		bot thread maps\mp\bots\_bot_script::added();
	}

	return bot;   // callers may ignore; the RCON per-team add uses it to place the bot (_gf_bridge)
}

/*
	Gives the bot loadout
*/
bot_give_loadout()
{
	self maps\mp\bots\_bot_loadout::bot_give_loadout();
}

/*
	Fired when the bot is damaged
*/
bot_damage_callback( eAttacker, iDamage, sMeansOfDeath, sWeapon, eInflictor, sHitLoc )
{
	self maps\mp\bots\_bot_script::bot_damage_callback( eAttacker, iDamage, sMeansOfDeath, sWeapon, eInflictor, sHitLoc );
}

/*
	Bot is idle
*/
bot_is_idle()
{
	if ( !IsDefined( self ) )
	{
		return false;
	}

	if ( !IsAlive( self ) )
	{
		return false;
	}

	if ( !self is_bot() )
	{
		return false;
	}

	if ( self inLastStand() )
	{
		return false;
	}

	if ( self HasScriptGoal() )
	{
		return false;
	}

	if ( IsDefined( self GetThreat() ) )
	{
		return false;
	}
	
	if ( self IsRemoteControlling() || self.bot_lock_goal )
	{
		return false;
	}
	
	if(self UseButtonPressed())
		return false;
		
	if(self isPlanting())
		return false;
			
	if(self isDefusing())
		return false;

	return true;
}

/*
	Watch all players grenades
*/
watch_grenade()
{
	self endon("disconnect");
		
	self.bot_scrambled = false;
	for(;;)
	{
		self waittill("grenade_fire", g, name);
		if(name == "scrambler_mp")
		{
			g thread watch_scrambler();
		}
		else if(name == "nightingale_mp")
		{
			self thread watch_decoy(g);
		}
	}
}

/*
	Watch the decoy grenade
*/
watch_decoy(g)
{
	g.team = self.team;
		
	level.bot_decoys[level.bot_decoys.size] = g;
		
	g waittill("death");
		
	for ( entry = 0; entry < level.bot_decoys.size; entry++ )
	{
		if ( level.bot_decoys[entry] == g )
		{
			while ( entry < level.bot_decoys.size-1 )
			{
				level.bot_decoys[entry] = level.bot_decoys[entry+1];
				entry++;
			}
			level.bot_decoys[entry] = undefined;
			break;
		}
	}
}

/*
	Attach a trigger to the scrambler
*/
watch_scrambler()
{
	trig = spawn( "trigger_radius", self.origin + (0, 0, -1000), 0, 1000, 2000 );
		
	self scramble_nearby(trig);
		
	trig delete();
}

/*
	Watch when players enter the scrambler trigger
*/
scramble_nearby(trig)
{
	self endon("death");
	self endon("hacked");
		
	while(!isDefined(self.owner) || !isDefined(self.owner.team))
		wait 0.05;
		
	self.team = self.owner.team;
	for(;;)
	{
		trig waittill("trigger", player);

		if (!isDefined(player) || !isDefined(player.team))
			continue;
		
		if(self maps\mp\gametypes\_weaponobjects::isStunned())
			continue;
		
		if(isDefined(self.owner) && player == self.owner)
			continue;
		
		if(level.teamBased && self.team == player.team)
			continue;
		
		player thread scramble_player();
	}
}

/*
	Scramble this player
*/
scramble_player()
{
	self notify("scramble_nearby");
	self endon("scramble_nearby");
		
	self.bot_scrambled = true;
	wait 0.1;
		
	if(isDefined(self))
		self.bot_scrambled = false;
}

/*
	Watch when a player shoots
*/
watch_shoot()
{
	self endon("disconnect");
		
	self.bot_firing = false;
	for(;;)
	{
		self waittill( "weapon_fired" );
		self thread doFiringThread();
	}
}

/*
	When a player fires
*/
doFiringThread()
{
	self endon("disconnect");
	self endon("weapon_fired");
		
	self.bot_firing = true;
	wait 1;
	self.bot_firing = false;
}

/*
	Watches the planes
*/
bot_watch_planes()
{
	level endon("bot_reinit");   // one copy only across a lobby re-init

	for(;;)
	{
		level waittill("uav_update");
		
		ents = GetEntArray("script_model", "classname");
		for(i = 0; i < ents.size; i++)
		{
			ent = ents[i];
			
			if(isDefined(ent.bot_plane))
				continue;
			
			if(ent.model != level.spyplanemodel)
				continue;
			
			thread watch_plane(ent);
		}
	}
}

/*
	Watches the plane
*/
watch_plane(ent)
{
	ent.bot_plane = true;
		
	level.bot_planes[level.bot_planes.size] = ent;
		
	ent waittill_any("death", "delete", "leaving");
		
	for ( entry = 0; entry < level.bot_planes.size; entry++ )
	{
		if ( level.bot_planes[entry] == ent )
		{
			while ( entry < level.bot_planes.size-1 )
			{
				level.bot_planes[entry] = level.bot_planes[entry+1];
				entry++;
			}
			level.bot_planes[entry] = undefined;
			break;
		}
	}
}

/*
	Fix xp in sd
*/
bot_killBoost()
{
	return false;
}

/*
	Fixes sd
*/
fixGamemodes()
{
	level endon("bot_reinit");   // one copy only across a lobby re-init

	for(i=0;i<19;i++)
	{
		if(isDefined(level.bombZones) && level.gametype == "sd")
		{
			level.isKillBoosting = ::bot_killBoost;
			for(i = 0; i < level.bombZones.size; i++)
				level.bombZones[i].onUse = ::bot_onUsePlantObjectFix;
			break;
		}
		
		wait 0.05;
	}
}
