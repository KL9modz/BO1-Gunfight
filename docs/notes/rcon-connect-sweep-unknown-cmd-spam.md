---
name: rcon-connect-sweep-unknown-cmd-spam
description: "\"Unknown cmd <dvar>\" burst printed in-game when connecting the RCON panel — the connect-sweep reads every panel dvar by BARE NAME, and any dvar the server hasn't registered echoes \"Unknown cmd\" (visible on a listen-host screen / server console)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 75f54476-1b35-4d2a-bcaa-36c6594e1c5e
---

**Symptom:** a plethora of `Unknown cmd scr_team_maxsize` / `scr_teamchange` / `scr_gf_*_large` /
`gf_debug_*` lines print on connect (screenshot showed the TEAMS batch — only ~3-4 fit per line).
Distinct from the client-side "unknown cmd cd" TODO ([[unknown-command-cd-and-cfg-semicolon-parse]]).

**Mechanism:** the RCON panel's connect-sweep (`readServerDvars`+`readMatchDvars` in
`tools/rcon/public/index.html`; server-side `readDvars` in `tools/rcon/server.js`) reads each
control's value by sending the **bare dvar name** over rcon (`need.join(';')`). T5/CoD's
`Cmd_ExecuteString` echoes the value for a *registered* dvar but prints `Unknown command "<name>"`
for an **unregistered** one. That print goes to the rcon reply AND the server console — and on a
**listen server** (host playing locally) the server console renders on the host's screen, hence the
in-game spam. On a **dedicated** server it only hits the console log, so players never see it (the
user seeing it = local listen-server testing).

**Root cause = swept dvars the server never registered.** Three classes found 2026-07-06:
1. **Non-existent (CoD4/WaW) dvars** that don't exist in Black Ops (T5) at all: `scr_teamchange`,
   `scr_autobalanceteams`, `scr_teamup` — verified absent from the T5 raw dump; nothing reads them
   (setting = no-op). Also `gf_debug` (the panel's "Debug Level" sel) is read NOWHERE in the mod.
   → **Removed from the panel** (dead controls that also spammed).
2. **Mod dvars registered only lazily.** `gf_cfgFloat` (`_gf_rounds.gsc`) seeds a dvar (setDvar
   if-empty) only when CALLED, and the team-size-mode variants are only called in THEIR mode — so
   in small mode `scr_gf_timelimit_large`/`scr_gf_overtimelimit_large`/`gf_capture_time_large` are
   unregistered (and vice-versa in large mode). `gf_debug_spawns`/`_hud_pool`/`_elem_probe` are read
   via `getDvarInt` which never registers. `scr_team_maxsize` is read via `getDvarInt` (registered
   only when dedicated.cfg sets it → errored on a cfg-less listen server).
   → **Seeded with defaults in `gf.gsc` onStartGameType** (both mode variants + team_maxsize;
   gf_debug_* seeded dev-only inside `#strip-begin/#strip-end`). Defaults mirror the read sites.
3. **Plutonium engine dvars** (`g_*`, `sv_*`, `bullet_*`, `sv_bot*`) — CONFIRMED phantom on this
   Plutonium T5 build: `sv_allowFriendlyThrowback`, `g_fix_viewkick_dupe`, `sv_sayName` (user
   screenshot), and the whole GAMEPLAY panel section (`g_playerCollision`/`g_playerEjection`/
   `g_fix_*`/`g_patchRocketJumps`/`bullet_penetration_affected_by_team`) looks T6/BO2-derived and
   likely doesn't exist on T5. NOT auditable statically (runtime additions, not in the raw dump) and
   too many to whack-a-mole — so handled by the universal cache below instead of removing controls.

**Universal fix (server.js `readDvars`, 2026-07-06):** a **persistent per-profile dead-dvar cache**
(`tools/rcon/.dvarcache.json`, gitignored, keyed by `host:port`). The rcon REPLY echoes
`Unknown cmd <name>` for each unregistered dvar (standard idTech: the reply IS the console output),
so the server parses those names out, caches them, and never bare-sends them again. Secondary signal
if a build doesn't echo the text: a still-null name in a small batch where ≥1 other name parsed
(`hit > 0` proves the reply arrived, so it's genuinely unknown — not packet loss). The FIRST sweep
of a fresh profile still probes once (unavoidable — detection needs the send); after that every
connect is clean, and the file survives panel restarts so it's a one-time-ever spam per server.
Panel ↻ Read passes `fresh=1` → server clears that profile's cache and re-probes (picks up a dvar
that later became registered). Connect (`doConn`) uses the cache (quiet). No frontend value-handling
change: skipped dvars return null → the panel already shows them as "NOT READ"/default.
RULE: never add a direct rcon reader that bare-sends dvar names without going through this cache.

**RULE when adding a new panel dvar control:** if it's a MOD dvar, make the mod register it
(setDvar-if-empty in onStartGameType) so the sweep reads it cleanly; if it's not a real dvar on the
target engine, don't add the control. Always test the panel against the **dedicated** server
(CLAUDE.md rule) — a listen server surfaces this as on-screen spam, a dedicated one hides it in the log.

Already-known related behavior: `server.js` `readDvars` marks a name "dead" (stops re-querying) when
a small batch reply arrives with the name unparsed — but the FIRST read still fires the print, so
dead-marking alone never prevented the connect-time spam. Registering/removing at the source does.
