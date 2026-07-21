---
name: killcam-slowmo-timescale-usercmd-backlog
description: "The mid-killcam Connection Interrupted plug = a usercmd backlog. Server acks commands only on a GAME FRAME, and game frames/sec = sv_fps x timescale. NO in-VM probe can see a dilation — measure it with RCON"
metadata: 
  node_type: memory
  type: project
  originSessionId: 442909b5-d5c5-4a23-ab9b-8eaaba9c9982
---

The round-end "Connection Interrupted" plug (and the `MAX_PACKET_USERCMDS` console spam that arrives
with it) is **one bug**: during stock's final-killcam slow motion the server stops retiring clients'
usercmds fast enough. Fixed 2026-07-13 by clamping the slow-mo's **depth** (`scr_gf_killcam_slowmo` is
now the killcam **timescale floor**, default **0.6**; `gf_killcamSlowmoClamp` in `_gf_rounds.gsc`).

## The arithmetic (this is the whole thing)

The server retires a client's usercmds only when it runs a **game frame**, and

    game frames per real second = sv_fps x timescale

The game-time quantum is `1000/sv_fps` and a dilation does **NOT** shrink it — it spreads those quanta
apart in **wall** time. Proven directly: at `sv_fps 20` every `gettime()` the server emits is an exact
multiple of **50**, dilated or not; during the killcam those 50ms steps arrive **~185ms apart**.

A client makes one usercmd per client frame (`com_maxfps`) and they drain only that fast, so the queue
is `com_maxfps x frame-gap`. Past **`MAX_PACKET_USERCMDS` (32)** the client truncates its move packet
and prints `MAX_PACKET_USERCMDS`. The same backlog makes `CG_DrawDisconnect` draw the plug — **it fires
when the server stops ACKING your commands, not when data stops arriving.** Two symptoms, one cause.

    stock 0.25 -> 200ms gap -> overruns above ~160 client fps  (i.e. every real client)
    0.6        ->  83ms gap -> overruns above ~385 client fps  (i.e. nobody)

**Fix the DEPTH, not the LENGTH.** The backlog builds within ~300ms of the drop, so shortening the
slow-mo does nothing.

## ⚠ sv_fps is NOT the lever, even though it is the other term

Raising it shrinks the gap **but breaks the killcam**: the replay rewinds through an archived snapshot
ring sized in **FRAMES, not seconds**, so 4x `sv_fps` buys a quarter as much killcam history. Tried live
at `sv_fps 80` — the replay ended early, stock's slowdown never reached its `SetTimeScale` at all, and
the sampler saw no dilation. It "fixes" the plug by deleting the feature. **Leave sv_fps at 20**
(`[[vps-prematch-slowmo-framehitch]]` says the same thing for an unrelated reason).

## ⚠ NO probe inside the GSC VM can ever see a timescale dilation

Two independent reasons, both cost real time to learn:
1. **`SetTimeScale` does not mirror into a readable `timescale` dvar.** It read a steady `1` straight
   through a round end measured at 0.27x. (No stock GSC reads such a dvar either — that was the tell.)
   A whole `GF_TS` probe + `gf_killcam_ts` panel readout were built on this and **deleted**.
2. **`gettime()`, `wait()` and the `games_mp.log` timestamps are ALL on the scaled game clock.** A
   dilation compresses game time against *wall* time without ever creating a game-clock gap — a
   `wait 0.05` still advances `gettime()` by a healthy 50ms while burning 200ms of wall clock.

So `GF_HITCH` / `GF_ENDGAP` are structurally blind to it. **Their zeros were never evidence the killcam
was clean — a zero is what a dilation LOOKS like from inside the sim.** Do not read one as an all-clear.

**Measure it from OUTSIDE: `tools/ts_sample.ps1`.** RCON lives outside the sim, so it diffs
`gf_roundEndProbe`'s `gf_endprobe_last` heartbeat against a wall-clock stopwatch — `d(game)/d(wall)` IS
the timescale. Measured on the VPS: **0.27x held for 8-10 REAL seconds, every single round.** (Goes
through the panel's paced queue, not a new RCON socket — see [[rcon-panel-queue-saturation]].)

## ✅ Shipped and confirmed live — and 🛑 the trap that comes with it

Floor 0.6 is **live and working**: the plug is **gone**, a full lobby plays great, and the sampler shows
the timescale floors at **0.62** (never below) with a **~80ms** frame gap.

🛑 **`MAX_PACKET_USERCMDS` STILL PRINTS ON CLIENTS. THAT IS NOT A REGRESSION. DO NOT "FIX" IT BY
LOWERING THE FLOOR OR RAISING `sv_fps`.** I originally wrote that "zero `MAX_PACKET_USERCMDS`" was the
acceptance test for this fix. **That was WRONG**, and it is a live trap: the spam persists at 0.6 while
the plug is gone, so anyone treating the spam as failure will "fix" a working server and bring the plug
back. It conflated two *different* client limits:

- **`MAX_PACKET_USERCMDS` (32)** — the **per-packet** cap. Overflow truncates the move packet, dropping
  the **oldest** queued commands; the server still gets the newest and keeps acking. Costs a few ms of
  stale input nobody can feel. **Cosmetic console noise.**
- **`CG_DrawDisconnect`** — a **separate, much looser** backlog threshold. **This is the plug**, and this
  is what the floor cleared.

**RESOLVED 2026-07-15 — it is `cl_maxpackets`, client-side.** A live client on `com_maxfps 237` /
`cl_maxpackets 30` (stock) printed ~37 `MAX_PACKET_USERCMDS` per killcam; **`cl_maxpackets 100` on that
client killed the spam, `com_maxfps` untouched.** So the count is **usercmds-per-outgoing-packet** (send
rate), NOT the `com_maxfps × ack-gap` backlog: at 30 packets/sec the client packs enough queued commands
into each packet to cross 32 during the slow-mo ack stall; at 100 it drains in smaller sends and never
does. The suspicion above was right — it's commands since the last **sent packet**, not since the last
**ack**. `cl_maxpackets` is archived (`seta`), so a player sets it once and it persists → this is a
**player-facing recommendation** (put it in `docs/GETTING_STARTED.md`), not a server change. The hard
constraint is vindicated: the floor / `sv_fps` were never the lever.

**Why:** the old memory blamed the `map_restart` snapshot gap ([[connection-interrupted-mitigations]]);
that is now disproven — `GF_ENDTL` reports `dark=0ms`, the server never goes silent, and `map_restart`
runs *after* the killcam anyway. Blanking the banner string ([[stock-engine-string-override-via-modff]])
only ever hid the text, never the cause.

**How to apply:** when a client-side netcode symptom appears only during a specific server-side effect,
check what that effect does to the server's **game-frame cadence** before blaming bandwidth or the
network. And when every instrument reports "nothing happened," suspect the instruments share a blind
spot — here they all shared a *clock*. See also [[read-the-server-not-the-file]].
