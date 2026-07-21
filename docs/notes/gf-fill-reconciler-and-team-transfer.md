---
name: gf-fill-reconciler-and-team-transfer
description: Round-boundary TEAM reconciler (gf_fill_n target + human balancing + lock queue) + lobby->match team transfer; the three engine facts that make/break them (threads survive map_restart(false); level.players is EMPTY during onStartGameType; a live cross-team move always kills)
metadata: 
  node_type: memory
  type: project
  originSessionId: c493396a-e42c-4554-92f4-647c97ad579a
---

Built 2026-07-08; **rewritten to ROUND-BOUNDARY-ONLY 2026-07-11** after live symptoms (VPS, fill mode):
bots suiciding during prematch countdowns and at match start after the lobby, and bot counts
overshooting the per-team target. Replaced BotWarfare's `addBots()`/`teamBots()`/`doNonDediBots()`
(now DELETED from `_bot.gsc`, not just unthreaded) with ONE Gunfight reconciler (`gf_reconcilerInit`),
driven by the dvar **`gf_fill_n`** = per-team TARGET size (default 2).

**2026-07-16 team-system refactor:** the pass became a 3-stage TEAM reconciler — (1) seat the
team-size-lock queue (`gf_team_lock`: gf_fill_n = hard HUMAN cap, overflow spectates queued in join
order via `pers["gf_seatQueued"]`); (2) **even the HUMAN split to off-by-1** (`gf_team_balance` 1,
most recent joiner by `pers["gf_joinSeq"]` moves — "humans are never auto-moved" is RETIRED as an
absolute; the off-by-1 evener is the one sanctioned mover, and `gf_team_balance 0` restores the old
never-move behavior); (3) bots pad to `max(bigger human side, gf_fill_n)`. `gf_fill_n 0` = NO bot
fill but stages 1-2 still run (manual bot placement sticks). Alive-at-boundary humans move via
`pers["gf_movePending"]` (consumed pre-spawn in the maySpawn hook, like `gf_parkPending`);
prematch-frozen ones via `_gf_rounds::gf_seqTeamMove` (sequenced suicide -> death SETTLES -> quiet
reassign -> respawn — the primitive that replaced every raw stock-switch use and killed the rare
"spawned at enemy spawns / spawned at 1 HP" post-move bug; `gf_reseatRespawn` is deleted, absorbed
into it). Self-switching is immediate via level.allies/axis/spectator wrappers (`gf_team_switch` 0
disables; alive mid-round switcher dies + sits out); `scr_gf_latespawn` 1 lets a first spawn enter a
LIVE round while the team has >=1 alive (never OT) by pre-setting `hasSpawned` in the maySpawn hook.
Auto large-map mode now triggers on **9+ seated humans** (bots never trigger it). Full design in
`.claude/CLAUDE.md` -> "Team system" and the header block in `_bot.gsc`.

**Why the always-on model failed (the 2026-07-11 lesson):** a 0.5s driver + connect/disconnect event
passes had to act mid-round/mid-prematch, which forced stock team switches behind a "switch-safe"
gate — and that gate raced the ENGINE'S ASYNC SPAWN COMMIT across thread yields (check-then-switch
TOCTOU): sessionstate/health read as safe, the stock switch landed on a client whose spawn was
committing, and the switch's `suicide()` killed it as it finished spawning => "bots kill themselves
during the countdown" (worse on the VPS's 20fps frames + hitches, hence "sometimes works"). Repeated
passes racing mid-connect adds + wrong-team autoassign landings ("leave it, it still counts") =>
"bots exceed the target". The fix is structural, not a better gate: **act only at round boundaries,
only with suicide-free primitives** — there is no mid-round actor left to race anything.

**The boundary model:** ONE yield-free `gf_boundaryPass` (atomic — GSC has no preemption), triggered
by (1) `gf_round_over` +0.5s (inside the killcam: every eliminated bot is un-"playing" there; adds get
seconds to connect before the next spawn wave), (2) `gf_load_gate_reset` with players present (the
match-start pre-prematch hold retiring — pre-spawn window, pass runs synchronously so the round-1
wave reads the finished plan; the Auto/Manual lobby-release fire — detectable by `gf_matchArmed=="1"`
— instead KICKS all bots pre-restart, because pers is about to be wiped and survivors would
re-autoassign anywhere and insta-spawn wrong-side; the post-restart pass rebuilds the fill clean),
(3) one roster-settle pass after init (waits for `level.players.size` stable ~1.5s — covers empty-
server pre-fill, the holding lobby, and the post-restart rebuild, where the gate notify never fires
because the armed pass skips the gate wholesale). Primitives: **quiet pers reassign**
(`gf_botQuietSetTeam`, mirror of `_gf_bridge::gf_forceTeamQuiet`) for un-"playing" bots; the deferred
`pers["gf_parkPending"]` mark (consumed pre-spawn by `gf_lobbyMaySpawn`) for alive ones — an alive
"playing" bot (incl. prematch-frozen and the mid-spawn undefined-health window) is NEVER touched;
kicks; and 0.5s-staggered adds that are **generation-stamped** (`level.gf_fillGen`; a newer pass
bumps it and the older add loop stands down — level.* wipe by map_restart also invalidates) and
**steer-marked** (`.gf_fillPending = team`, counted toward the TARGET team while mid-connect so no
pass double-fills a travelling slot). `gf_botDeployWhenReady` quiet-corrects a landed bot only while
un-"playing"; a bot the engine already spawned wrong-side is LEFT for the next boundary.

**Three non-obvious engine facts this all rests on** — each one was a real bug when violated:

1. **Threads SURVIVE `map_restart(false)`** even though `game[]`/`pers[]`/`level[]` are all wiped.
   That's why the lobby's fast-restart branch blocks forever instead of returning. Consequence: the
   once-per-match `game["gf_botInit"]` gate in `gf.gsc` re-fires after the lobby restart and would
   stack a SECOND set of bot managers. Fix idiom = `level notify("bot_reinit")` at the top of
   `_bot::init` + `level endon("bot_reinit")` on every persistent bot loop. This is also the real
   cause of the old "fast restart clears the bots" bug.

2. **`level.players` is EMPTY during `onStartGameType`** (`_spawnlogic::init` empties it;
   `Callback_PlayerConnect` repopulates only after the callback returns). Anything threaded from
   there that inspects the roster MUST wait before its first check (`gf_matchStartPass` waits for a
   QUIET roster, not just a non-empty one — post-restart clients re-begin over several seconds and a
   half-reconnected count mis-plans). Also why the `gf_armLoadGate` fire of `gf_load_gate_reset` is
   skipped on an empty roster.

3. **A live (spawned) player can NEVER be moved across teams without dying.** A quiet
   `pers["team"]` reassign of a `sessionstate=="playing"` client fires a false `onDeadEvent`
   (moving the last-alive player off a side reads as a team wipe -> premature round end) and nulls
   `self.class`, corrupting alive counts. Stock `menuAllies/menuAxis/menuSpectator` `suicide()` a
   playing client by design. So: quiet reassign is ONLY valid for not-yet-spawned/parked/dead
   clients; live moves are next-spawn-deferred (`pers["gf_parkPending"]` for bots,
   `pers["gf_pendingTeam"]` for the bridge's human moves) or admin force-now (respawn). The
   boundary model exists precisely so the reconciler only ever meets bots in the quiet states.

Related: [[gf-stuck-after-prematch-two-gates]] (the lobby / `gf_matchArmed` fast-restart it plugs
into), [[round-freeze-activation-race-and-rails]] (`gf_round_over` / the round-end path the boundary
listener keys off), [[onstartgametype-perround-thread-accumulation]] (the same thread-stacking
hazard class).
