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
	// Bot counts + placement are owned by the round-boundary reconciler (threaded from
	// handleBots). BotWarfare's own managers (addBots/teamBots/doNonDediBots) are DELETED —
	// see handleBots(). Local "Basic Training" just sets gf_fill_n to the desired per-team N.
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

	diffBots keeps setting bot difficulty (unrelated to counts/teams). Bot COUNTS and
	PLACEMENT are owned by gf_reconcilerInit(), the Gunfight round-boundary reconciler
	(see the big block below). BotWarfare's own managers are DELETED, not just unthreaded:
	addBots (total-count fill, kick-a-random-bot overflow), teamBots (a live rebalance loop
	whose stock switch on a "playing" bot was the original spawn-suicide bug) and
	doNonDediBots all fight the one-life round model.
*/
handleBots()
{
	thread diffBots();
	thread gf_reconcilerInit();
}

// ============================================================================
// GUNFIGHT ROUND-BOUNDARY BOT RECONCILER
// ----------------------------------------------------------------------------
// ONE authority over bot COUNTS and PLACEMENT, acting only at ROUND BOUNDARIES. Source of
// truth = the dvar gf_fill_n (per-team target N; each side is padded to N *playing* clients,
// humans+bots, with bots absorbing the variance). It MUST be a dvar — the only state that
// survives the lobby's map_restart(false).
//
// WHY boundary-only (this replaced an always-on 0.5s driver + human connect/disconnect
// watchers): reconciling mid-round/mid-prematch forced stock team switches ([[level.allies]]()
// suicide()s any "playing" client) behind a switch-safe gate, and that gate raced the engine's
// async spawn commit across thread yields — the "bots kill themselves during the countdown"
// bug. Repeated passes racing mid-connect adds and wrong-team autoassign landings were the
// "bots exceed the fill target" bug. At a boundary neither race exists: everything is planned
// in ONE yield-free pass, placement is a QUIET pers reassign (gf_botQuietSetTeam — no suicide
// path even exists), and an alive round-winner is never touched at all (deferred mark).
//
// Invariant: each team = exactly N playing at round start, BOTS-ONLY variance. Humans are
// NEVER moved — if the humans on a side exceed N, that side's bots drop to 0 and it stays
// big; the OTHER side still fills to N. A displaced bot PARKS in spectator for reuse (KICKED
// instead under client-slot pressure so a human can always connect; REDUCING the fill number
// kicks the freed bots too). Mid-round roster changes (a human joins/leaves) are deliberately
// ignored until the next boundary — worst case one ~45s round — which is also why a manual
// panel move with fill ON only lasts until that boundary (fill OFF = manual mode sticks).
//
// Triggers (all run the same gf_boundaryPass):
//   1. gf_round_over  — every round end; runs 0.5s in, INSIDE the killcam/intermission, where
//      every eliminated bot is already un-"playing" and fresh adds get seconds to connect
//      before the next spawn wave (kinder to server frames than a prematch add burst).
//   2. gf_load_gate_reset — the match-start pre-prematch hold retiring; players are connected
//      but nothing has spawned yet, so the pass runs synchronously in that window and the
//      round-1 spawn wave reads the finished team plan. (The Auto/Manual lobby-release fire
//      instead KICKS all bots pre-restart — the post-restart pass rebuilds the fill clean.)
//   3. One roster-settle pass shortly after init — pads an empty server / a holding pregame
//      lobby so the fill is visible without waiting for a boundary, and rebuilds the fill
//      after the lobby fast-restart.
//
// Counts key off level.players + istestclient() (NOT level.bots), so the reconciler stays
// correct even if a restart disturbs BotWarfare's own bookkeeping. gf_fill_n == 0 =>
// reconciler INERT (manual bot control sticks). Every persistent loop carries
// endon("bot_reinit") so a lobby map_restart(false) (which re-runs _bot::init but does NOT
// stop threads) collapses back to exactly one live set.
// ============================================================================

gf_reconcilerInit()
{
	level endon("bot_reinit");

	// Clear any stale in-flight steer marker. bot_reinit kills gf_botDeployWhenReady watchers
	// without running their cleanup, but the BOT ENTITY survives a map_restart(false) — a
	// leftover .gf_fillPending would keep attributing that bot to a team nothing is steering
	// it to. Sweep here, right after the notify.
	for(i = 0; i < level.players.size; i++)
		if(isDefined(level.players[i]))
			level.players[i].gf_fillPending = undefined;

	thread gf_boundaryListener();
	thread gf_gateListener();
	thread gf_matchStartPass();
}

// Trigger 1: every round end. gf_endRound fires gf_round_over BEFORE it posts the winner's
// score and threads the killcam, so wait a beat: the score lands (for the match-over check)
// and the pass runs inside the killcam window. Skip the final boundary — the map rotate drops
// every bot anyway, so adds there would just churn during the podium.
gf_boundaryListener()
{
	level endon("game_ended");           // match end tears it down; gf.gsc's game[] gate re-inits next match
	level endon("bot_reinit");

	for(;;)
	{
		level waittill("gf_round_over");
		wait 0.5;
		if(gf_matchIsOver())
			continue;
		gf_boundaryPass();
	}
}

// Trigger 2: the match-start hold retiring. The notify fires from three sites in _gf_rounds:
//   a. gf_armLoadGate retiring a prior tracker — early in a fresh match's onStartGameType,
//      where level.players is still EMPTY (a pass there would misread 0 humans and over-add):
//      skipped by the empty-roster guard.
//   b. The Auto/Manual lobby RELEASING into map_restart(false) — gf_matchArmed was just set.
//      pers[] is about to be wiped, so placing anything now is pointless, and a surviving bot
//      would re-autoassign anywhere post-restart and insta-spawn into the real prematch, stuck
//      wrong-side for all of round 1. With fill on we KICK every bot instead (they are lobby
//      spectators — an invisible exit) and let the post-restart matchStartPass rebuild the
//      whole fill steered at the right teams, so round 1 starts exactly NvN. (Fill off: bots
//      are carried by gf_botplan — never touch them.)
//   c. The gate completing into the prematch (no restart) — players are connected but nothing
//      has spawned yet, the one window where even a full re-seat is a pure quiet reassign. The
//      pass runs synchronously (it never yields), so the spawn wave reads the finished plan.
gf_gateListener()
{
	level endon("game_ended");
	level endon("bot_reinit");

	for(;;)
	{
		level waittill("gf_load_gate_reset");
		if(gf_fillTarget() <= 0)
			continue;                    // fill off: gates are none of our business
		if(getDvar("gf_matchArmed") == "1")
		{
			players = level.players;
			for(i = 0; i < players.size; i++)
			{
				p = players[i];
				if(isDefined(p) && p istestclient() && !(p isdemoclient()))
					kick(p getEntityNumber(), "EXE_PLAYERKICKED");
			}
			continue;
		}
		if(level.players.size == 0)
			continue;
		gf_boundaryPass();
	}
}

// Trigger 3: one roster-settle pass shortly after init (init is once per MATCH). Pads an empty
// dedicated server / a holding pregame lobby so the browser and the lobby roster show the fill
// without waiting for a boundary, and rebuilds the fill after the lobby fast-restart (the gate
// notify never fires for the armed post-restart pass — the gate is skipped wholesale). Waits
// for the roster to go QUIET (size unchanged ~1.5s, bounded ~12s) instead of a fixed delay:
// after map_restart(false) every surviving client re-begins over the first seconds, and a pass
// counting mid-reconnect would plan against half a roster. A genuinely empty server is stable
// immediately and just pre-fills both sides.
gf_matchStartPass()
{
	level endon("game_ended");
	level endon("bot_reinit");

	last   = -1;
	stable = 0;
	ticks  = 0;
	while(ticks < 24 && stable < 3)
	{
		wait 0.5;
		ticks++;
		if(level.players.size == last)
			stable++;
		else
		{
			stable = 0;
			last = level.players.size;
		}
	}
	gf_boundaryPass();
}

// True once a team has hit the match win threshold — the same scr_gf_scorelimit-on-
// game["teamScores"] check stock hitScoreLimit runs (scorelimit IS the match length here;
// RoundWinLimit is registered 0/inert — see CLAUDE.md).
gf_matchIsOver()
{
	limit = getDvarInt("scr_gf_scorelimit");
	if(limit <= 0)
		return false;
	if(!isDefined(game["teamScores"]))
		return false;
	if(isDefined(game["teamScores"]["allies"]) && game["teamScores"]["allies"] >= limit)
		return true;
	if(isDefined(game["teamScores"]["axis"]) && game["teamScores"]["axis"] >= limit)
		return true;
	return false;
}

// Classify level.players. Buckets: <team>_human / <team>_bot (on a real team), parked (a
// CONNECTED bot benched in spectator — the reusable pool), inflight (a bot mid-connect with
// no team resolved and no steer target). A bot still being STEERED by gf_botDeployWhenReady
// (.gf_fillPending = target team) counts as a bot ON that team wherever the connect flow has
// it right now — it lands before the next spawn wave — so a pass never re-fills the slot it
// is already travelling to and the parked pool can't steal it. A human in spectator is
// neutral. Also feeds the bridge's gf_state fill telemetry (the keys are load-bearing).
gf_reconcileCount()
{
	r = [];
	r["allies_human"] = 0; r["allies_bot"] = 0;
	r["axis_human"]   = 0; r["axis_bot"]   = 0;
	r["parked"]       = 0; r["inflight"]   = 0; r["clients"] = 0;

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
			if(isDefined(p.gf_fillPending))
			{
				tgt = p.gf_fillPending;
				if(tgt == "allies" || tgt == "axis")
					r[tgt + "_bot"]++;
				else
					r["inflight"]++;
				continue;
			}
			if(onTeam)
				r[t + "_bot"]++;
			else if(isDefined(t) && t == "spectator")
				r["parked"]++;
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

// ONE reconcile pass: plan the next round's composition from the live roster, acting only
// through suicide-free primitives (quiet pers reassign / deferred pers mark / kick / staggered
// add). Yield-free, so it is atomic vs. all other script (GSC has no preemption) — and it is
// the ONLY writer, so two passes can never race a half-applied change. gen-stamped so a newer
// pass cancels an older pass's still-staggering add thread (the old overshoot source).
gf_boundaryPass()
{
	n = gf_fillTarget();
	if(n <= 0)
	{
		gf_clearAllParkPending();        // fill OFF: drop any stale defer marks so a manually
		return;                          // managed bot never spectates a round on an old mark
	}                                    // fill OFF -> reconciler inert (manual bot control sticks)

	if(!isDefined(level.gf_fillGen))     // level.* is wiped each map_restart; a surviving stale
		level.gf_fillGen = 0;            // add thread compares against the fresh value and quits
	level.gf_fillGen++;

	gf_clearAllParkPending();            // recompute deferred parks fresh from THIS roster
	c = gf_reconcileCount();

	maxClients = getDvarInt("sv_maxclients");
	if(maxClients < 1) maxClients = 18;
	ceiling = maxClients - gf_fillKickFloor();

	teams = [];
	teams[0] = "allies";
	teams[1] = "axis";

	// --- PARK first: trim each team's bot surplus (bots-only; a humans-only overflow leaves
	// the side big — humans are NEVER moved). Parking before deploying grows the pool the
	// deploy below reuses, so a lopsided roster fixes itself without an add+kick churn. An
	// alive surplus bot gets the deferred mark and leaves at its next spawn instead (it still
	// counts on its team in `c`, which is correct: surplus and deficit are mutually exclusive
	// on a team, so the mark never skews another team's deficit math this pass).
	for(ti = 0; ti < 2; ti++)
	{
		team    = teams[ti];
		bots    = c[team + "_bot"];
		surplus = (c[team + "_human"] + bots) - n;
		if(surplus > bots)               // humans-only overflow: leave the side big, never move a human
			surplus = bots;
		if(surplus > 0)
			gf_parkBots(team, surplus, ceiling);
	}

	// --- DEPLOY: fill each team's deficit. Reuse parked bots first (quiet reassign — the next
	// spawn wave reads the new pers["team"] and the bot simply spawns there), then thread ONE
	// staggered add loop for the remainder. The pool is derived AFTER parking (quiet moves are
	// synchronous, so freshly-parked bots are immediately reusable), one shared index across
	// both teams so nothing is double-assigned.
	pool = [];
	players = level.players;
	for(i = 0; i < players.size; i++)
	{
		p = players[i];
		if(!isDefined(p) || !(p istestclient()) || p isdemoclient())
			continue;
		if(isDefined(p.gf_fillPending))  // mid-connect: already steered at a team
			continue;
		if(isDefined(p.pers["team"]) && p.pers["team"] == "spectator")
			pool[pool.size] = p;
	}

	pi = pool.size;
	totalDeficit = 0;
	for(ti = 0; ti < 2; ti++)
	{
		team = teams[ti];
		need = n - (c[team + "_human"] + c[team + "_bot"]);
		if(need <= 0)
			continue;
		while(need > 0 && pi > 0)
		{
			pi--;
			b = pool[pi];
			if(isDefined(b) && !(isDefined(b.sessionstate) && b.sessionstate == "playing"))
			{
				b gf_botQuietSetTeam(team);
				need--;
			}
		}
		if(need > 0)
		{
			totalDeficit += need;
			thread gf_addFillBots(team, need, level.gf_fillGen);
		}
	}

	// --- TRIM (only when no team still needs bots): keep a parked RESERVE == the humans
	// currently playing (each could leave and reopen a slot) and stay under the client ceiling;
	// KICK the excess. This makes "reduce the fill number" kick the freed bots (0 humans -> 0
	// reserve -> all parked kicked) while a human-displaced bot still PARKS for instant reuse.
	if(totalDeficit == 0 && pi > 0)
	{
		reserve = c["allies_human"] + c["axis_human"];   // one parked bot per playing human (each could leave)
		// ...but never keep so many parked that total clients breach the ceiling (this also
		// relieves slot pressure so a human can always connect). clients - pi approximates the
		// non-parked clients; a boundary later self-corrects any drift.
		maxReserve = ceiling - (c["clients"] - pi);
		if(reserve > maxReserve)
			reserve = maxReserve;
		if(reserve < 0)
			reserve = 0;
		excess = pi - reserve;           // deploys consumed from the END of pool; kicks take the FRONT
		for(k = 0; k < excess; k++)
		{
			b = pool[k];
			if(isDefined(b))
				kick(b getEntityNumber(), "EXE_PLAYERKICKED");
		}
	}
}

// Quiet team placement for a NOT-"playing" bot: the persistent-state half of the stock
// menuAllies/menuAxis/menuSpectator (no suicide, no respawn, no menus). The next spawn wave
// reads pers["team"] and the bot simply spawns on the new side. Mirrors
// _gf_bridge::gf_forceTeamQuiet (duplicated so _bot.gsc needs no bridge include). Yield-free,
// and every caller classifies-then-places with no wait in between — GSC has no preemption, so
// the engine's spawn pipeline can never interleave (the old check-then-STOCK-switch raced
// exactly there and suicided bots mid-spawn).
gf_botQuietSetTeam(team)
{
	self.pers["team"]       = team;
	self.team               = team;
	self.pers["class"]      = undefined;
	self.class              = undefined;
	self.pers["weapon"]     = undefined;
	self.pers["savedmodel"] = undefined;
	self.sessionteam        = team;
}

// Add `count` fresh bots for `team`, staggered 0.5s apart (each add is a full client connect;
// a back-to-back burst is the classic server-frame spike — see the VPS prematch slow-mo note
// in CLAUDE.md). Threaded from a pass with that pass's generation stamp: a NEWER pass re-plans
// from live state and bumps level.gf_fillGen, making any still-staggering older add loop stand
// down — two overlapping planners was the old overshoot source. Each bot carries
// .gf_fillPending = team from birth so counts attribute it correctly for its whole connect.
gf_addFillBots(team, count, gen)
{
	level endon("game_ended");
	level endon("bot_reinit");

	for(k = 0; k < count; k++)
	{
		if(!isDefined(level.gf_fillGen) || level.gf_fillGen != gen)
			return;                      // superseded (newer pass, or a map_restart wiped the gen)
		bot = add_bot();
		if(isDefined(bot))
		{
			bot.gf_fillPending = team;
			bot thread gf_botDeployWhenReady(team);
		}
		wait 0.5;
	}
}

// A freshly add_bot()'d bot connects async: wait for the stock connect flow to land it on
// SOME team (bots_team "autoassign" usually picks our deficit team anyway — it seats the
// smaller side), then quiet-correct it if needed. It is marked .gf_fillPending (attributed to
// `team` in counts) for the whole trip; if it never lands, kick it so a wedged connect can't
// hold a phantom slot. If the engine already SPAWNED it (possible only in the match-start
// prematch — boundary adds run while nothing spawns), LEAVE it: it still counts where it
// stands and the round-1 boundary rebalances. NEVER stock-switch here — that suicide racing
// the async spawn commit was the old "bots kill themselves as they pour in".
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
		kick(self getEntityNumber(), "EXE_PLAYERKICKED");   // never connected -> free the slot
		return;
	}

	if(self.pers["team"] != team && !(isDefined(self.sessionstate) && self.sessionstate == "playing"))
		self gf_botQuietSetTeam(team);

	self.gf_fillPending = undefined;     // landed: counts now read its real pers["team"]
}

// Trim `count` surplus bots from `team`, quietest first. A bot that is NOT "playing"
// (eliminated this round, or never spawned) is parked to spectator NOW with the quiet
// reassign — or KICKED instead under client-slot pressure so parked bots can't lock a human
// out. An alive "playing" bot (a round survivor, or prematch-frozen — and the mid-spawn
// window where health isn't set yet is ALSO "playing") cannot be moved without the stock
// switch's suicide, so it is DEFERRED: pers["gf_parkPending"] makes gf_lobbyMaySpawn (gf.gsc)
// route it to a clean spectator in its next PRE-spawn window — invisible, next round. pers
// survives map_restart(true), so the mark always reaches that spawn. Synchronous throughout.
gf_parkBots(team, count, ceiling)
{
	quiet = [];                          // not "playing": park (or kick) immediately
	alive = [];                          // alive / prematch-frozen: defer to next spawn via the mark
	players = level.players;
	for(i = 0; i < players.size; i++)
	{
		p = players[i];
		if(!isDefined(p) || !(p istestclient()) || p isdemoclient())
			continue;
		if(!(isDefined(p.pers["team"]) && p.pers["team"] == team))
			continue;
		if(isDefined(p.sessionstate) && p.sessionstate == "playing")
			alive[alive.size] = p;
		else
			quiet[quiet.size] = p;
	}

	done = 0;
	for(i = 0; i < quiet.size && done < count; i++)
	{
		if(level.players.size >= ceiling)
			kick(quiet[i] getEntityNumber(), "EXE_PLAYERKICKED");
		else
			quiet[i] gf_botQuietSetTeam("spectator");
		done++;
	}
	// Remaining surplus is alive right now -> it finishes this round (or sits out the prematch)
	// on its old team and leaves at its next spawn.
	for(i = 0; done < count && i < alive.size; i++)
	{
		alive[i].pers["gf_parkPending"] = true;
		done++;
	}
}

// Drop every bot's deferred-park mark. Called at the top of each PARK derivation (and when fill is
// off) so a surplus that resolved before the bot's next spawn never wrongly spectates a round.
gf_clearAllParkPending()
{
	players = level.players;
	for(i = 0; i < players.size; i++)
	{
		p = players[i];
		if(isDefined(p) && p istestclient() && isDefined(p.pers["gf_parkPending"]))
			p.pers["gf_parkPending"] = undefined;
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

		// bot_set_difficulty rewrites the WHOLE sv_bot* set from the difficulty preset, and this
		// loop re-runs it every 1.5s — so an individual sv_bot* override (the RCON panel's BOT
		// TUNING sliders) was silently reverted within a second and a half. THAT, not the cheat
		// gate, is why those sliders never appeared to do anything: two controls owned the same
		// dvars and the preset always won.
		//
		// Re-apply the explicit overrides on top, so Difficulty is a BASELINE and a tuned slider
		// actually sticks. Cheap: an unset override is a single getDvar and no write, and this
		// loop already does ~15 setDvars per pass. Fully-qualified call (no #include needed);
		// _bot.gsc and _gf_bridge.gsc are both dev-only and are stripped together.
		maps\mp\gametypes\_gf_bridge::gf_bridgeApplyServerDvars();
	}
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
