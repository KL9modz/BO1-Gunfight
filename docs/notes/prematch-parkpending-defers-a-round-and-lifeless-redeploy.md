# Match start: dead teammate bot + enemy over-fill (prematch parkPending defers a round; redeploy left a lifeless bot)

**Date:** 2026-07-20, live on the VPS, `mp_berlinwall2` match start (KL9 + basscar101, fill 2).
Round 1 started **2v3 with the allies bot dead**: allies = KL9 + AKrauss(dead), axis = basscar101 +
2 alive bots. **Status: both defects FIXED** (`gf_parkBots`, `gf_botQuietSetTeam`).

## Timeline (from `GF_TEAMTRACE` level 2 + K/J lines, 74:10–74:58)

1. Map change; roster-settle pass pads the **empty** server 2v2 (allies JBojorquez+AKrauss, axis
   DAA Anthony+MDonlon). Bots auto-spawn frozen (disable-cac) while the load gate holds for the
   two loading humans.
2. KL9 loads onto allies (villa pers) → 3rd body → seat-priority displacement **suicide-parks
   JBojorquez** (correct).
3. basscar101 loads onto allies too → 3rd body again → displacement **suicide-parks AKrauss**
   (correct at that instant).
4. Load gate releases → boundary pass: balancer moves basscar → axis (sequenced move), then the
   deploy stage **re-seats the just-parked AKrauss onto allies** (botquiet)…

## Defect 1 — redeploy of a suicide-parked bot never restored its life

AKrauss's park was a **suicide**-park → `pers["lives"]` consumed. The deploy's quiet reassign
(`gf_botQuietSetTeam`) flipped his team but restored nothing → the round-1 spawn wave hit stock
maySpawn **gate A (no lives) → denied** → he sat DEAD on the scoreboard the entire round ("the bot
on my team started the match already out").

**Fix:** `gf_botQuietSetTeam` seating a bot on a **real team** restores `pers["lives"] =
level.numLives` — the same semantic as `gf_seqTeamMove(restoreLife=true)`. (Within-round it only
matters in exactly this park→redeploy window; `map_restart` re-deals lives anyway.)

## Defect 2 — `parkPending` on a PREMATCH bot is a round-long lie

The same pass computed the axis surplus (basscar + 2 bots = 3 > T=2) and, because the surplus bot
was "playing" (prematch-frozen), gave it the **deferred** `pers["gf_parkPending"]` mark. That mark
means "parks at its next spawn" — right for a mid-round/killcam survivor (next spawn = next round's
pre-spawn), but a prematch bot **already spawned this round**: its next spawn is ALSO next round, so
it plays the whole round over-size. Worse, the mark makes `gf_teamRosterCount` /
`gf_pickDisplaceableBot` treat the bot as already retired — so when basscar spawned onto axis, the
seat-priority displacer recomputed `over = 0` and **no-op'd**. Net: "the other team had 2 bots
alive (1 too many)". (The next boundary's `gf_clearAllParkPending` then wiped the mark — by then
basscar had left, 2 axis bots became legal, and nothing ever fired.)

**Fix:** `gf_parkBots` splits the alive case: **prematch-frozen → immediate sequenced suicide-park**
(`gf_seqTeamMove("spectator", false)` — the displacer's own primitive; frozen bots are safely
killable and the bot is retired *this* round); **mid-round survivor → deferred mark** (unchanged,
correct).

## Second lifeless-bot mechanism (2026-07-20, `mp_nuked` round 7 — AFTER the fixes above shipped)

A human spectated **mid-killcam, after the boundary pass had already planned the next round** — so
the pass never saw the seat open. At the re-begin, an **unstamped stock-path team switch** moved a
bot cross-team to fill the hole (`UNTRACED bot BLMercado axis -> allies … state dead` +
`K;…;MOD_SUICIDE`): stock `changeTeam` `suicide()`s even a `"dead"` client, burning the **fresh
life the re-begin had just dealt** → seated but lifeless all round. `gf_botQuietSetTeam`'s restore
can't see a stock write, so the net moved to the one door every spawn passes through: **the
maySpawn hook restores any BOT's lives at pre-spawn during the PREMATCH** (the round hasn't
started; a consumed life there is always pre-round suicide debris). Mid-displacement/park bots are
excluded (their suicide IS the retirement); humans untouched.

## Rules to keep

- **`parkPending` is only valid on a client whose next spawn is still ahead of it this cycle.**
  A prematch-frozen client's next spawn is next round — deferring is equivalent to not parking.
- **Any same-round re-seat of a bot that went through a suicide-park must restore the life**, or
  gate A silently strands it dead (the bot equivalent of
  [[stock-teamswitch-suicide-no-life-restore]]).
- The `K;…;MOD_SUICIDE` lines during a countdown are the displacement/trim parks — expected, off
  the books (`switching_teams`), not combat.
- basscar101's spectator stint that match was reason `user` (own menu choice at 74:44) — the
  reclaim correctly left him alone; no reclaim bug.
