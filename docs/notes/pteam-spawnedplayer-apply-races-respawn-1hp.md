# Bridge deferred team move (pteam ⏭) applied on `spawned_player` → raced the re-begin wave → 1 HP spawn

**Date:** 2026-07-20, live on the VPS: admin clicked the panel's ⏭ "change team (next round)" on
KL9 (playing `mp_cairo`); at the next round start KL9 spawned **at 1 HP**. **Status: FIXED** —
`pers["gf_pendingTeam"]` is now consumed in the pre-spawn maySpawn window.

## Mechanism

The deferred move was applied by `gf_bridgeWatchPendingTeam`, a `level waittill("spawned_player")`
loop that swept ALL players for a pending flag. Three properties combined into the race:

1. `spawned_player` fires for **every** spawn — so a **bot's** re-begin spawn could trigger the
   sweep at the exact moment the target's own re-begin `spawnClient` was **mid-flight** (queued by
   stock `_globallogic_player.gsc:388`, not yet committed).
2. The sweep called `gf_applyTeamMove` → `gf_seqTeamMove`. For a not-yet-"playing" target that
   skips the suicide and runs `gf_seatJoinTeam` → `beginClassChoice` → (disable-cac branch)
   **`thread spawnClient()`** — a **second** spawn racing the first, with the team fields flipped
   between them. For a just-spawned target it instead **suicided them mid-spawn-pipeline**
   (`spawned_player` fires at step 3 of 5; class/loadout give hasn't run yet).
3. Two spawnClients + a mid-flight team flip is the exact anatomy of the OLD raced stock-switch bug
   ("spawned at the enemy spawns / spawned with 1 HP") that `gf_seqTeamMove` was built to kill —
   the bridge's deferred path was simply never migrated onto a safe mechanism.

The log signature that pinned it: `GF_TEAMTRACE: human KL9 allies -> axis by seatjoin` at the round
boundary with **no** `K;…;MOD_SUICIDE` line for KL9 — i.e., the not-playing branch ran (double
spawnClient variant), during the re-begin wave.

## The fix

`pers["gf_pendingTeam"]` is consumed in **`gf_lobbyMaySpawn`** (gf.gsc), immediately after the
balancer's `gf_movePending` block and via the same pattern: the team flips **before the one spawn
commits** — no suicide, no second spawnClient, nothing to race. Details:

- Consumed AFTER `gf_movePending`, so a same-round balancer move loses to admin intent.
- `"spectator"` target parks like `gf_parkPending` (flip + `return false`), breadcrumbed
  `gf_specReason = "moved"` so GF_TEAMWATCH / the reclaim treat it as intentional.
- Class is KEPT (the in-flight spawnClient already validated it) — also avoids the
  [[quiet-team-move-cleared-class-blocks-respawn]] class gate.
- The watcher (`gf_bridgeWatchPendingTeam` / `gf_applyPendingTeamMoves`) is **deleted**; the
  panel's roster "pending" column still works (it reads the pers flag, which now lives until the
  pre-spawn consume).
- The over-cap recheck the old apply did is dropped — `gf_playerSpawnedCB`'s `scr_team_maxsize`
  overflow net already bounces an over-cap landing (breadcrumbed `maxsize`).

## Rules to keep

- **Never apply team state from a `spawned_player` (or any spawn-time) event** — that window has
  in-flight spawnClients to race. Pre-spawn (maySpawn) is the one safe consume point; it is how
  `gf_parkPending`, `gf_movePending`, and now `gf_pendingTeam` all land.
- A "deferred to next round" primitive must be **pull-based at the target's own spawn**, not
  push-based from someone else's event.
