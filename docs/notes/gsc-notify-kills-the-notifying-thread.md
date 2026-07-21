---
name: gsc-notify-kills-the-notifying-thread
description: "A GSC notify terminates EVERY thread that endon()s it — including the thread that fires it. This froze rounds forever; gf_endRound died at its own level notify(\"gf_round_over\")."
metadata: 
  node_type: memory
  type: project
  originSessionId: b85d4062-756b-4fc8-b599-f2e1b6694e2d
---

**`level notify("X")` kills every thread with `level endon("X")` — including the thread that CALLS the
notify.** So a function that fires a notify must never be invoked *inline* from a thread that endons it:
execution stops at the notify statement and **everything after it silently never runs**.

Found 2026-07-12 as the cause of the "round frozen forever with a team wiped" bug on the VPS.

**The bug.** `gf_endRound()` fired `level notify("gf_round_over")` in the *middle* of its body. Two
threads carry `level endon("gf_round_over")` and **both call `gf_endRound`**:
- `gf_roundClock` → `gf_onTimeLimit()` → `gf_endRound()`  (clock expiry / HP-decides path)
- `gf_roundWatchdog` → `gf_endRound()`                     (team-wipe force-end)

On those paths `gf_endRound` died at its own notify, so the winner never scored, `gf_postRoundWatchdog`
was never armed, and `_globallogic::endGame` was never called → **no `map_restart`, round hangs forever,
every watchdog already dead.** Server otherwise healthy (RCON fine, script VM alive).

**How it was proven** — bracket the death between two observable side effects on either side of the
notify. Round 2 on mp_kowloon: allies wiped axis, yet
- `phase=roundend` (hitch monitor) ⇒ `gf_roundEnding=true` + `gf_roundActive=false` ran — the lines
  *before* the notify;
- `score {allies:0}` despite allies winning ⇒ `_setTeamScore`, *after* the notify, never ran;
- zero `GF_ENDWATCH` lines ever ⇒ `gf_postRoundWatchdog` never armed;
- no `InitGame` for 75 min ⇒ `endGame` never called.

**The fix** (all three):
1. `gf_roundClock`: `level thread gf_onTimeLimit();` — a fresh thread holds no endon, so it survives.
2. `gf_roundWatchdog`: `level thread gf_endRound( winner );` — same.
3. `gf_endRound`: reordered so the score + `gf_postRoundWatchdog` arming happen **before** the notify
   (defense in depth). Stock `_globallogic::endGame` has the same shape and is careful for the same
   reason — it writes all its state *before* `notify("game_ended")`.

**This hazard was already known in this codebase and just never generalized:** `_gf_bridge.gsc`
(`matchrestart`) already works around it for `game_ended` — *"Yield once before the notify: gf_bridgePoll
endons game_ended… Notifying synchronously would kill the poll before that write."*

**Audit rule.** For every `level notify("X")`, list the threads holding `level endon("X")` and confirm
none of them can reach the notifier via an *inline* call (a `thread` call is safe). Two safe idioms:
- **collapse-to-one-copy**: `notify("X")` FIRST, then `endon("X")` — the new thread kills the old one and
  registers its own endon afterwards, so it never kills itself (`gf_startHealthHUD` does this correctly).
- notifier is a plain init/handler holding no endon at all (`gf_bridgeInit`, `gf_armLoadGate`).

A full audit of the mod's 10 notify/endon pairs found `gf_round_over` was the **only** violation.
Related: [[infinite-round-orphaned-killcam-flag]] (a *different*, still-unproven round-end hang),
[[round-freeze-activation-race-and-rails]], [[onstartgametype-perround-thread-accumulation]].
