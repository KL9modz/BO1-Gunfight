---
name: silo-background-missiles-are-client-side
description: "mp_silo's background missile launches are 100% CLIENT-side (mp_silo.csc rocket_manager) — no server dvar, no server entity, nothing GSC can reach. Unlike Launch, which HAS scr_rocket_event_off"
metadata: 
  node_type: memory
  type: project
  originSessionId: b84324e5-b6fe-4b4c-a2ad-e6ef44c7cf1f
  modified: 2026-07-20T10:49:16.440Z
---

**The server cannot control Silo's background missiles.** Verified by extracting the map's own scripts
from `mp_silo.ff` ([[extract-dlc-map-gsc-from-fastfile]]).

- Server-side `maps/mp/mp_silo.gsc` has **zero** rocket/missile references — it only threads a swinging
  `crane_container`.
- The whole sequence lives in **`clientscripts/mp/mp_silo.csc`**: `main()` does `level thread
  rocket_manager()`, which fires exploders **100-105** — first at `RandomIntRange(20,40)`s after level
  load, then ~`RandomIntRange(50,80)`s apart (20% chance of 20-40s) + a 20s tail, then `rocket_finish`.
  **6 launches, self-terminating.** `rocket_launch_think` (hatch rotate, `evt_missile_launch`, the
  `MoveTo(+100000z)` and the exhaust FX) is all client-side.
- Both `createfx/mp_silo_fx.gsc` **and** `.csc` *define* exploders 100-107, which is misleading — only the
  **client** ever triggers them (`clientscripts\mp\_fx::exploder`).
- Each client runs its own random schedule, so **the launches aren't even synced between players**. Purely
  cosmetic: no damage, no collision, no gameplay hook.
- The only knob is `silo_rocket_test`, and it is a **CLIENT** dvar wrapped in a `/# … #/` **dev block**
  (inert on retail clients) — and it *fires all 6 faster*, it doesn't disable them.

**Contrast — Launch (`mp_cosmodrome`) DOES expose server dvars** for its rocket, via the stock
`maps/mp/_events.gsc` timed/score-event system: `scr_rocket_event` (`end`/`time`/`percent`/`random_time`/
`random_percent`), `scr_rocket_event_trigger1`/`2`, and the kill switch **`scr_rocket_event_off`** (a
0-100 % chance to abort; `100` = never launches). Same family: `scr_rocket_arm_*`, `scr_radar_dish_rotate_secs`.
Don't generalize from Launch to Silo — Silo simply never got wired to `_events`.

**The kill attempt is NOW STAGED (2026-07-20), pending in-game verification.** The only lever is
overriding `clientscripts/mp/mp_silo.csc` as a rawfile in `mod.ff` (clients get `mod.ff` via FastDL):
the repo now carries `clientscripts/mp/mp_silo.csc` — the stock script re-extracted verbatim from
`mp_silo.ff`, with ONE change: `main()` no longer threads `rocket_manager()` (every function kept, so
the public surface is intact — `main()` itself references `mp_silo::on_player_connect`). `mod.csv` has
the `rawfile,clientscripts/mp/mp_silo.csc` entry (build_ff stages arbitrary rawfile paths generically;
built clean, name confirmed inside the zone). ⚠ Still unverified whether the mod.ff copy beats the map
zone's copy at client compile time — the map .ff loads *after* mod.ff, so it may win, in which case
this is a harmless no-op. **Verify by eye on Silo:** stock fires the first launch 20-40s after level
load; the two ambient OPEN hatches (exploders 106/107, `rocket_init`) still run in the patched copy, so
hatches-open + no launches = our copy won; launches at round 1 = map .ff won (then the only fallback is
a loose `raw\clientscripts\mp\mp_silo.csc` on each client — not distributable).
