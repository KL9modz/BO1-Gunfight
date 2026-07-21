---
name: sv-timeout-and-connecttimeout-template-defaults
description: "Player join/timeout complaints = TWO separate dvars, not one. sv_timeout (already-in-game packet silence) vs sv_connectTimeout (connecting/loading = the FIRST-JOIN budget). The Pluto T5ServerConfig template ships sv_timeout 15 — 3x STRICTER than the client's own cl_timeout 40. Both raised (240 / 200) on 2026-07-12"
metadata: 
  node_type: memory
  type: project
  originSessionId: 595172d5-cbbd-43fc-bf20-f847ced537ba
---

**Two dvars, two different connection phases. Never conflate them** (doing so is what produced the
wrong "red herring" verdict in [[svtimeout-connect-twice-firstjoin]]).

| dvar | governs | engine default | was live | now |
|---|---|---|---|---|
| `sv_timeout` | a client **already in the game** | 240 | **15** (template) | **240** |
| `sv_connectTimeout` | a client still **connecting / loading** | 80 | 80 | **200** |
| `cl_timeout` | the CLIENT's own in-game patience | 40 | 40 | — |
| `cl_connectTimeout` | the CLIENT's own connect patience | 200 | 200 | — |

**Why `sv_timeout 15` was hostile — two independent ways:**
1. **Alt-tab out of EXCLUSIVE FULLSCREEN.** Windows minimizes the window, the client stops pumping its
   main loop and stops sending, so the server drops it 15s later. (Borderless/windowed keeps running
   while unfocused and never hit this.)
2. **It made the server ~3x STRICTER THAN THE CLIENT.** `cl_timeout` is 40, so on any lag spike or
   packet-loss burst the server dropped a player who was *still sitting there waiting for it*.
   **RULE: a server must never be stricter than its own clients — keep `sv_timeout` >= `cl_timeout`.**

**`sv_connectTimeout` is the FIRST-JOIN budget, and the engine's own 80 is thin.** A first-timer
FastDL-downloads `mod.ff`, then the Plutonium client rebuilds its engine *in place* with no loading UI
(D3D9 device destroyed + recreated, ~180MB of zones reloaded = a 30-60s black screen,
[[fastdl-first-join-black-screen-rebuild]]) and then runs a Demonware stats/CAC re-sync with documented
multi-minute stalls. Blowing 80s mid-rebuild is much of why new players report having to **connect
twice** — attempt 2 finds `mod.ff` cached, skips both the download *and* the rebuild, and loads in
seconds. Raising it costs nothing (it only ever applies before a client finishes loading).

**⚠ DIAGNOSTIC TRAP HIT DURING THIS FIX: the cfg on disk said `60`, the RUNNING server said `15`.**
The cfg had been hand-edited after the server booted, and a cfg value only counts if it was `exec`'d at
boot. **Read the running server, not the file** — the dvar dump in the mod folder's `console_mp.log`, or
the panel's `/api/dvars?fresh=1`. Same lesson as [[connection-interrupted-mitigations]].

**The `T5ServerConfig` template is a repeat offender — audit it, don't trust it.** It also ships
`g_inactivity 190` ([[stock-afk-and-spawn-kick-timers]]) and semicolon-bearing comments that the cfg
parser executes ([[unknown-command-cd-and-cfg-semicolon-parse]]). Both dvars here are engine-registered
(no `gf.gsc` seed needed, cf. [[rcon-connect-sweep-unknown-cmd-spam]]) and **not latched**, so the panel
sets them live.

**Applied 2026-07-12** (panel-first, never raw UDP — [[rcon-panel-queue-saturation]]): live via the
panel's paced `POST /api/rcon`, persisted via `POST /api/savecfg` (loopback-trusted, writes a `.bak`)
into the LIVE cfg at `C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\dedicated.cfg` — **not**
the `C:\gameserver` decoy. Panel rows for both live in ADVANCED → GENERAL (`SRV_SECTIONS` in
`tools/rcon/public/app.js`); tracked copy in `server/dedicated.cfg.example`.

**Still NOT explained by this** (a first join is expensive regardless): the 30-60s black-screen rebuild
itself is a client-engine cost we cannot remove from the server side. This fix stops the server from
*hanging up mid-rebuild*; it does not make the rebuild fast.
