---
name: dlc-map-scripts-call-stock-bot-is-idle
description: "mp_hotel + mp_outskirts call maps\\mp\\gametypes\\_bot::bot_is_idle(); our _bot.gsc shadows stock's and lacked it → those two maps failed the WHOLE server with a compile error"
metadata:
  type: project
---

**Symptom (2026-07-22, laptop listen host).** Loading **`mp_hotel`** died at level load:

```
------- Game Initialization -------
Error:
******* Server script compile error *******
Error: unknown function
SV_Shutdown:  Server script compile error
```

`mp_kowloon` had run fine minutes earlier, the working tree was clean, and no mod GSC had been touched
since the previous day's successful sessions — so the fault looked impossible. It is **map-specific**.

**Cause.** `mp_hotel` ships its own elevator script inside `mp_hotel.ff`
(`maps/mp/mp_hotel_elevators.gsc` — **not** the generic `maps/mp/_elevator.gsc`;
[[extract-dlc-map-gsc-from-fastfile]] is how to read it). Its `elevator_prox_think()` — the ambient
behavior that makes idle bots wander over and ride the lift — calls:

```gsc
if ( players[i] maps\mp\gametypes\_bot::bot_is_idle() && cointoss() )
```

Our mod ships **`maps/mp/gametypes/_bot.gsc`** (the fill reconciler, vendored from BotWarfare), which
**overrides stock's `_bot.gsc`** and never defined `bot_is_idle()`. This is the
`unknown function` rule (d) in the T5 cheatsheet: **GSC resolves symbols at COMPILE time**, so the map
script links against our file unconditionally and the whole server fails to compile.

⚠ **`scr_elevator_failsafe 1` does NOT protect against it.** `elevator_prox_think()` returns on that
dvar at *runtime*, but the call is still compiled. **A dvar can never fix a compile error** — which is
also the reasoning that rules the dvar out as a suspect: a compile error cannot be value-dependent.

⚠ **The base-game `raw/` dump has ZERO `gametypes\_bot::` references**, so the usual grep-the-dump check
comes back clean and proves nothing. Only **DLC** map scripts (which are not in the dump) use it.

**Fix.** A documented stub in `_bot.gsc`, returning `false` (BotWarfare bots always have a goal, and GF
deliberately runs Hotel with the elevators dead — we never want a bot pathing to a lift):

```gsc
bot_is_idle()
{
	return false;
}
```

**Scope — swept all 12 DLC fastfiles** (inflate the zone, inflate each per-map rawfile, grep for
`_bot::`). Exactly **two** maps call it: **`mp_hotel`** and **`mp_outskirts`** (same idle-bot ambient
pattern). area51 / berlinwall2 / discovery / drivein / golfcourse / gridlock / kowloon / silo / stadium
/ zoo are clean, and `bot_is_idle` is the only stock `_bot::` symbol any map script reaches — so the one
stub closes the whole class.

**Public builds were never affected** — `_bot.gsc` is dev-only and stripped by `package_release.ps1`, so
a public server uses stock's `_bot.gsc`. This was a **dev + VPS** fault: the live server would have died
the same way the moment either map came up in rotation.

**Rule (generalizes past `_bot.gsc`).** Any stock script this mod shadows must keep its **entire public
surface**, and "the raw dump has no callers" is **not** proof — DLC map scripts live only inside their
`.ff`. Same family as the `_pregame.gsc` trap
([[gf-stuck-after-prematch-two-gates]] context; cheatsheet rule (d)).
