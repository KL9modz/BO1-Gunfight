---
name: what-the-democlient-is-for
description: "The [3arc]democlient is BO1 match recording (Theater), gated by demo_enabled. The KILLCAM does NOT depend on it. scr_demorecord_minplayers 0 does NOT disable it — stock forces that back to 1."
metadata: 
  node_type: memory
  type: reference
  originSessionId: b85d4062-756b-4fc8-b599-f2e1b6694e2d
---

**What it is.** `[3arc]democlient` is the client slot BO1's **match-recording (Theater) system** takes
for itself. Stock `maps/mp/_demo.gsc`:

- `_load::init()` → `_demo::init()` → `demoOnce()`, which **returns immediately unless `isDemoEnabled()`**
  (the engine dvar **`demo_enabled`**, engine-registered, `Domain is 0 or 1`, **default 1 = ON**).
- `demoThink()` then polls every 5s: `StartDemoRecording()` once **humans >= scr_demorecord_minplayers**,
  `StopDemoRecording()` when they drop below it.

That is why the democlient **only appears once at least one HUMAN is on** (bots don't count — the log
shows it joining/quitting exactly with humans, `J;0;0;[3arc]democlient`).

**⚠ `scr_demorecord_minplayers 0` does NOT disable it** — `demoOnce()` explicitly forces it back to 1
(`if (!GetDvarInt(#"scr_demorecord_minplayers")) SetDvar(..., 1)`, then `max(1, ...)`).
**`demo_enabled 0` is the real gate.** (Setting minplayers above `sv_maxclients` would also work, but
`demo_enabled` is the root switch and skips threading `demoThink()` at all.)

**Does anything need it? No.**
- **The KILLCAM does NOT depend on it** — `maps/mp/gametypes/_killcam.gsc` contains **zero** demo /
  matchrecord references. Killcam is gated by `scr_game_allowkillcam` / `scr_game_allowfinalkillcam`
  (both live at 1), which are entirely separate.
- Nothing in Gunfight reads the recording. The mod only ever **filters the democlient out** — ~15
  `isdemoclient()` guards across `_gf_rounds` / `_bot` / `_gf_bridge`.
- Stats/persistence (`_persistence.gsc`) is a different system; it also just filters the democlient out.

**What it costs.** A continuous demo write; an `addDemoBookmark()` on **every kill**
(`_globallogic_player.gsc`); one client slot out of `sv_maxclients`; and the
`MatchRecord: Writing final stats` flush, which in `console_mp.log` sits **directly beside**
`Hitch warning: 2466 msec frame time` — making it the prime suspect for the >2s frame stalls
([[vps-prematch-slowmo-framehitch]]). It is also behind the open "democlient round-cam lag" bug and the
"rename the democlient label" TODO — both of which simply vanish if it is off.

**Verdict:** on this server it is pure cost. `demo_enabled 0` is now exposed as a panel toggle
(ADVANCED → ENGINE GAMEPLAY, badged NEXT — read at level load, so it lands on the next round). Only keep
it if someone actually wants to watch server-side Theater demos.
