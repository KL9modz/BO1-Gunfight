---
name: spawn-yaw-carried-camera-input
description: "FIXED 2026-07-27 (commit 6b942fe) — moving the camera on the switching-sides/killcam screen makes you spawn facing wrong next round. NOT the spawn-point bug — this is the VIEW angle: spawn() snaps it once but the stale client view REVERTS the snap ~0.2-1s later. Fix = divergence-gated re-assert of BOTH axes held through prematch, released at prematch_over. Held input during the countdown is the one irreducible edge."
metadata:
  node_type: memory
  type: project
---

Distinct from [[spawn-wrong-facing-usestartspawns-gate]] — that note is about the wrong spawn **point/angle
data** being selected; THIS is the **view angle** the client carries in from its own camera input. Both
present as "spawn facing the wrong way," so check which one you have: a wrong *location* or the right
location with a wrong *facing that the player influenced*.

## Symptom
Look around (or, on a controller, hold the look stick) during the round-end **killcam / "switching sides"
scoreboard** screen, and the next round you spawn **facing whatever you'd turned toward**, not the curated
fight-facing angle. Reported first as yaw ("camera looking in another direction"), later as pitch ("holding
the stick down → spawn facing the ground every round").

## Root cause — deltaangles reconciliation
In the Q3/CoD netcode your on-screen view is `deltaangles + cmd.angles` (your last-reported input).
`self spawn(origin, angles, "gf")` snaps you by issuing a **fixangle**: it sets `deltaangles = intended -
cmd.angles`, i.e. relative to whatever input you last sent. The snap itself lands fine (`GF_SPAWNYAW d0=0`
one frame after spawn, every time). But the camera turn you made on the switch screen is a **stale
client-side view** (buffered input / the round-end killcam camera restore) that the client re-applies
**~0.2–1s AFTER spawn**, overriding the fixangle — then the client reports its own angle and the server
accepts it. Signature: `d0≈0, d1 (at +1s) large, prematch=1` → the probe flags `CLIENT_VIEW_OVERRODE`.
Nothing re-asserts, so it sits wrong the whole round.

⚠ This is a **client-authoritative view** thing: a script probe inside the GSC VM can only see it after the
fact via `getPlayerAngles()`. No listen-host shortcut — the reconciliation only misbehaves with the
round-end camera + real network timing, so it must be proven on the **dedicated** box.

## Fix (final): divergence-gated re-assert of BOTH axes, held through prematch
`gf_lockSpawnYaw(angles)` in `gf.gsc`, threaded right after each `self spawn()` in `onSpawnPlayer` (both the
curated and the `mp_tdm_spawn_*_start` paths; small mode reaches it via `onSpawnPlayerUnified → self
onSpawnPlayer()`). Every 0.05s, **only if** `|yawDiff| > 45 || |pitchDiff| > 45`, re-issue
`setPlayerAngles(angles)`; loop until `level.inPrematchPeriod` clears (stock clears it at `prematch_over`,
`_globallogic.gsc:1539`), then release so live aim is unimpeded. Ships in the **public** build (real gameplay
bug) — stock builtins only. Local `gf_yawDiff` helper because the probe's `_gf_debug::gf_yawDelta` is
stripped from release. `setPlayerAngles` writes a **snapshot field replicated every frame**, NOT a reliable
command, so re-asserting costs nothing against the reliable-command budget
([[server-command-overflow-reliable-command-budget]]).

Two properties are load-bearing and were each learned the hard way:
- **HELD through the whole prematch, not set once.** The revert lands *after* any short burst, so a one-shot
  set (or a 0.2s burst) fails — `d1` still large. It must be re-asserted until go-live.
- **DIVERGENCE-GATED (>45°), not unconditional.** An unconditional 20Hz re-assert *worked* but **shook** the
  camera during the countdown: it fought the player's own small look adjustments and re-issued a redundant
  fixangle every tick. Gated, a still / lightly-adjusting player is never touched — a carried swing corrects
  once, early, then the loop goes quiet.

## The dead ends (don't re-try these)
1. **0.2s burst at spawn** (commit before `dd11a9e`): FAILED — the revert lands 0.2–1s in, after the burst
   stops. Proven by `d0=0 / d1 large`.
2. **Unconditional continuous hold** (`dd11a9e`): worked but produced a **countdown camera shake** (fights
   your own input + redundant fixangles).
3. **Yaw-only divergence gate** (`ec1a15b`): killed the shake but only watched yaw, so a **pitch-only** carry
   (holding the stick down) was never caught → "spawn facing the ground every round." Any gate MUST check
   both axes.
4. **Correct only at go-live, don't police the countdown** (`927367f`, Approach B): REJECTED by playtest — it
   showed the wrong view for the *entire* preround timer and then **snapped** when the round started. The ask
   was explicitly "fix it at the START of preround or not at all," which is what the held-through-prematch
   version delivers.

## The one irreducible edge
If a player **actively holds** a look input off-target for the whole countdown (stick pinned fully down),
the >45° gate keeps pulling them back — a gentle fight — because "keep the countdown facing correct" and
"let the player hold the view off-target" are contradictory. Not reachable by normal play (you don't hold
the look stick during the countdown). The only alternatives are to drop one axis from the gate (which
re-opens dead-end #3) or to not correct at all. Left as-is deliberately.

## Verifying — the `GF_SPAWNYAW` probe
Dev-only, `gf_probeSpawnYaw` in `_gf_debug.gsc`, gated on `gf_debug_spawnyaw 1` (default 0). Logs every spawn
to `logs/games_mp.log` (skips real bots). Both axes now: `intended=<yaw>/<pitch> d0=<yaw>/<pitch>
d1=<yaw>/<pitch>`. **`d0`** proves the initial snap took; **`d1` (+1s, mid-countdown) near 0 on BOTH numbers
is the pass** — a large `d1` means the carried revert beat the hold (`CLIENT_VIEW_OVERRODE`). Small `d1`
values (< the 45° gate) are fine — that's a light look adjustment passing through untouched, exactly the
behavior that avoids the shake. Log every spawn, not just the bad ones: the boring baseline lines are what
make a flagged one trustworthy. ⚠ The probe samples DURING prematch, so it matches the "held through
countdown" design; if a future version ever goes back to correcting at go-live, move the decisive sample
past `prematch_over` or the probe will read a false failure.

## Commit trail
`dd11a9e` (hold, unconditional) → `ec1a15b` (yaw gate, added the shake fix) → `927367f` (go-live snap,
reverted) → **`6b942fe` (final: both-axes gate held through prematch)**. Proven live on the VPS (player KL9):
after `6b942fe`, `d1=0/0` across rounds including deliberate switch-screen camera swings on both axes.
