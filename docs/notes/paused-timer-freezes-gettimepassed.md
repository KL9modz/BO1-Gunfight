---
name: paused-timer-freezes-gettimepassed
description: "GF's pauseTimer() (custom round clock) freezes getTimePassed() at ~0 all round, silently breaking any stock system keyed off match-elapsed time — notably the grenade-launcher/thrown-grenade dud window"
metadata: 
  node_type: memory
  type: project
  originSessionId: 60a056bb-c921-46aa-97d8-9d1e9b6d64aa
---

GF runs a custom round clock that calls `_globallogic_utils::pauseTimer()` (sets
`level.timerStopped`) to silence the native 30s time-out VO/music. Side effect:
`_globallogic_utils::getTimePassed()` returns the FROZEN `(timerPauseTime - startTime) -
discardTime` whenever `level.timerStopped` is true — so for the whole round it sits at ~0,
not real elapsed time. Anything stock that gates on match-elapsed time via `getTimePassed()`
misbehaves under GF.

First instance found (2026-06-19): the engine grenade-dud system
(`_weapons::turnGrenadeIntoADud`) duds frags/semtex and launchers (`gl_*`, `china_lake_mp`)
while `dudTime >= getTimePassed()/1000`. With the clock frozen at ~0 and GF never registering
a dud dvar (defaults 0), `0 >= ~0` stayed true permanently → those weapons fired DUDS (no
explosion) and spammed "lethal grenades / grenade launcher unavailable for 1 second" (timeLeft
clamps to 1) on every use, all match. NOT the spawn anti-nade lockout, and NOT a missing
`setOffhandPrimaryClass` binding (both were wrong early guesses — the "for N seconds" suffix is
the `_UNAVAILABLE_FOR_N` + `EXE_SECONDS` dud printout, the tell).

Fix: in `gf_startRoundClock` (right after `pauseTimer()`), set
`level.grenadeLauncherDudTime = -1; level.thrownGrenadeDudTime = -1;` — negative disables the
window since no value elapses against a frozen clock. Set each round (map_restart wipes
`level.*`); persists through overtime in the same round.

**How to apply:** before reusing any stock MP system in GF, check whether it reads
`getTimePassed()` — if so, it's frozen and needs an explicit override. Related: the timer/pause
model in [[gf-timer-prematch-and-pause-model]].
