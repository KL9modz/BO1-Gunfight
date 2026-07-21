---
name: stock-afk-and-spawn-kick-timers
description: "Three stock/template drop timers, none of them the mod: g_inactivity 190 (AFK), scr_kick_time 60 (spawn-or-be-dropped, armed by rankedMatch), and sv_timeout 15 (packet silence — drops anyone who alt-tabs out of exclusive fullscreen)"
metadata: 
  node_type: memory
  type: project
  originSessionId: c90650dd-5a78-43bc-bdf0-8c61ebe7a24c
---

Reported 2026-07-12: "there seems to be an AFK timer for spectators and it's shorter than 5 min."
**The mod does not contain a single `kick()` call.** Two independent stock/engine timers do:

1. **`g_inactivity` — the actual AFK kick.** Kicks on *input* inactivity, and it does NOT spare
   spectators. The engine default is `0` (off), but the Plutonium **`T5ServerConfig-master` template**
   ships `set g_inactivity "190"` (3 min 10 s) — and the live VPS was still running that template's cfg
   verbatim at `C:\gameserver\T5\T5ServerConfig-master\localappdata\Plutonium\storage\t5\dedicated.cfg`
   (note: **not** our `server/dedicated.cfg.example`, which already said 300 — the example had drifted
   from what was deployed). Set to **300** on the box 2026-07-12 (backup `dedicated.cfg.bak-afk`);
   `tools/rcon` exposes it as "AFK Kick Timer (s)" in ADVANCED. **The cfg is only read at server boot** —
   a change there needs a restart, or set it live via the panel.

2. **`scr_kick_time` — stock spawn-or-be-dropped**
   (`_globallogic_spawn::kickIfIDontSpawnInternal` → `kick(..., "GAME_DROPPEDFORINACTIVITY")`). The GSC
   default in the source reads 90, but **the engine registers the dvar at 60**, so 60 is what's live. The
   thread is only armed when `level.rankedMatch` is true — and **it IS on our dedicated server**
   (`level.rankedMatch = onlineGame && !xblive_privatematch && !xblive_wagermatch`; our InitGame line
   shows `onlinegame 1` + `xblive_privatematch 0`). It returns early if `pers["team"] == "spectator"`, so
   a *real* spectator is safe — but it kicks anyone Gunfight holds **team-assigned without spawning**:
   every human in an Auto/Manual pregame lobby hold (`level.forceAutoAssign` seats them on a team and
   nobody spawns for up to `scr_gf_lobby_timer` = 600 s), and a large-mode late joiner (90 s round +
   killcam outlasts 60 s). Latent, masked only because the default lobby mode is Normal. `gf.gsc`
   `onStartGameType` now pins `scr_kick_time 3600` (in the force-every-`map_restart` stock-dvar block —
   a `== ""` seed guard would never stick, since the engine already registered it).

3. **`sv_timeout` — the fullscreen alt-tab drop** (added 2026-07-12, same template, same shape). Reported
   as "when I'm in fullscreen and minimize the game it kicks me out." `sv_timeout` is seconds of **packet
   silence from a client** before the server drops it — nothing to do with input, AFK or the mod. Engine
   default **240** (domain 0-1800); the `T5ServerConfig` template ships **15**, and the template's own
   comment even says "(Defualt 240)". In **exclusive fullscreen** an alt-tab makes Windows minimize the
   window and the T5 client stops pumping its main loop → it stops sending → dropped 15 s later.
   Borderless/windowed keeps running while unfocused, so it never hit this — that asymmetry is the tell.
   Set to **240** on the live box + `server/dedicated.cfg.example` (backup `dedicated.cfg.bak-svtimeout`),
   and exposed in the panel's ADVANCED → GENERAL as "Client Timeout (s)". **Not latched** — an rcon `set`
   applies immediately, no restart. The only cost of raising it is how long a hard-crashed client keeps
   its player slot (plus `sv_zombietime`).

**Why:** all three were invisible from the mod source; grepping the mod for `kick` finds nothing, and the
"spectator" in the bug report was really either a true spectator (timer 1) or a team-assigned
not-yet-spawned player (timer 2). The engine-registered default (60) also differs from the value written
in the stock GSC (90) — read the dvar dump in `console_mp.log`, not the script's fallback.

**How to apply:** when a player is dropped and the mod has no `kick()` for it, dump the server's dvars
(`console_mp.log` has a full registered-dvar list with live values) and check `g_inactivity` /
`scr_kick_time` / `sv_timeout` / `sv_zombietime` before suspecting the mod. Anything inherited from the
`T5ServerConfig` template on the VPS is suspect in the same way — it is upstream's config, not ours.
Related: [[vps-launch-bat-and-maxclients-latch]], [[gf-stuck-after-prematch-two-gates]].
