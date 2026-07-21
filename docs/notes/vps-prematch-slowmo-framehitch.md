---
name: vps-prematch-slowmo-framehitch
description: "GF_HITCH RESOLVED with 10 days of VPS data: gettime() IS wall-clock (monitor valid); the hitch is game-time dilation from the engine's own map_restart — 99.3% prematch, ~one per round, FLAT across bot count (so NOT our bots/HUD/loadouts). Not ours to delete → fix = make the countdown immune"
metadata: 
  node_type: memory
  type: project
  originSessionId: b85d4062-756b-4fc8-b599-f2e1b6694e2d
---

"Prematch countdown runs in slow motion" (VPS). **Measured and resolved 2026-07-12** from 10 days of
`GF_HITCH` logs (2,803 hitches) + live RCON reads. This supersedes the earlier guesses in this file.

## What GF_HITCH actually means (the old open question — now ANSWERED)
`gf_hitchMonitor` does `t0 = gettime(); wait 0.5; real = gettime() - t0`. `wait` counts **game time**;
the open caveat was whether `gettime()` is wall-clock or game-time (if game-time, the monitor would read
~+0% even during a slow-mo and be worthless).

**ANSWERED: `gettime()` IS wall-clock.** The monitor logs real values of 650–3650ms against a 500ms
window, so it does register dilation. The monitor is valid, and the "our gettime-anchored clocks are
immune" claim is **confirmed**. So a `GF_HITCH: 750ms vs 500ms` means the server took 750ms of wall time
to advance 500ms of game time — **the whole simulation ran at ~65% speed**. The slow-mo is real
time-dilation, not a rendering artifact, and the stock prematch countdown is simply the last clock still
driven by a game-time `wait(1.0)`.

## The measured shape
- **99.3% are `phase=prematch`** (2,784) — roughly **one per round**, ~700–750ms.
- **FLAT across bot count: 694ms @ 0 bots vs 746ms @ 6 bots.** ⚠ This **disproves** the old claim in this
  file that the round-1 bot fill is a contributor. It is not the bots, not the HUD `setClientDvar` pushes,
  not the loadout giving — it is the engine's **`map_restart(true)`** itself. **Not ours to delete.**
- **226 hitches > 2s** (map load, and the `MatchRecord` stat flush — console shows `MatchRecord: Writing
  final stats` sitting right beside `Hitch warning: 2466 msec frame time`).
- **15 landed mid-gameplay** (`phase=live`) at ~2.8s. These are the only ones that actually hurt players.
- Engine's own `Hitch warning` fires just 25× (avg 2.9s, max 9.2s) — so the common ~700ms per-round hitch
  is *below* the engine's own warning threshold.

## What to do about it
1. **Fix the symptom, not the hitch**: gettime()-own the prematch countdown. The hitch is the engine
   restarting the level; the countdown is the only thing that visibly suffers. (Still the REAL FIX.)
2. **`scr_allowbattlechatter 0`** — stock, pure flavour, nothing in GF reads it. Its
   `CheckDistanceToEvent` scans `level.alivePlayers` on EVERY kill, and the GSC VM has killed that exact
   thread with "potential infinite loop" 3×, each landing on a 2.4–2.5s frame hitch. Now a panel toggle.
3. **`demo_enabled 0`** — the `[3arc]democlient` + `MatchRecord` flush; prime suspect for the >2s stalls.
   ⚠ The killcam does **NOT** depend on it. Now a panel toggle. See [[what-the-democlient-is-for]].
4. ⚠ **Do NOT raise sv_fps.** The stall is a fixed lump of wall-clock work; more frames/sec on a starved
   box buys more overhead and *more* dilation. Delete the "sv_fps 30 experiment" idea.
5. **Ceiling: the box.** 4 **shared** Contabo vCPUs (AMD EPYC, 8GB). Hypervisor steal produces
   multi-second stalls no config fixes. If the >2s stalls survive 2+3, this is what is left.

## Corrections to older notes in this file
- ⚠ The VPS cfg path quoted here before (`C:\gameserver\T5\T5ServerConfig-master\...`) is the **DECOY**.
  The **live** cfg is the Administrator-profile one:
  `C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\dedicated.cfg` — see
  [[connection-interrupted-mitigations]] and [[read-the-server-not-the-file]].
- sv_fps is confirmed **20** (engine default) by a live RCON read, not just a cfg grep.

Related: [[gf-timer-prematch-and-pause-model]], [[paused-timer-freezes-gettimepassed]],
[[vps-server-provisioned]], [[engine-dvar-defaults-from-log-dump]].
