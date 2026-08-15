---
name: bocl-readyup-timeout-execmenu-designs
description: "Worked designs distilled from Classixz/bo1-competitiveleaguemod (2026-08-14): lobby READY-UP (use-button poll + statusicon scoreboard mirror + all-ready release, on OUR spectator-lobby hold), rationed TEAM TIMEOUTS (applied as a one-round prematch extension at the boundary - no mid-round freeze), lobby ALL-TALK (SetMatchTalkFlag, stock-proven at halftime/podium), and the menu-execNow client-console experiment (the only in-game client-exec channel on our server, since sv_disableClientConsole 1 blocks typing). Designs only - none implemented."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0206234e-9e40-5448-9815-c6fbd96d8e2d
---

Source: the BOCL deep-dive (clone at `%TEMP%\bo1-clm`; their `maps/BOCL/_pregame.gsc` is
the reference implementation). These are **designs, not code** — each names its open
verification points. Shared context: our lobby holds players as **team-assigned free-look
spectators** (`sessionstate "spectator"`, `allowSpectateTeam` both false, bodyless
overview cam), unlike BOCL's playable warmup bodies — that difference drives most of the
adaptation below.

## 1. Ready-up on the lobby hold (the "Lobby ready-up UI" TODO)

BOCL's shape, adapted to ours:
- **Input:** per-human 20 Hz `UseButtonPressed()` toggle loop, threaded at hold entry,
  `endon` lobby-release + disconnect. Use/Attack/Jump/Melee are all proven MP-safe
  builtins. ⚠ Verify live that Use in our locked free-look cam doesn't fight a spectate
  binding — with `allowSpectateTeam` false there should be nothing to cycle.
- **Per-player feedback:** NOT BOCL's per-player `createFontString` (their `setText`
  hudelem habit is exactly what [[settext-configstring-exhaustion]] retired) — our lobby
  menuDef (`gf_lobby_hud`) reads `ui_gf_*` dvars, so a "READY N/M — press [USE]" line is
  one shared dvar push per change + one per-client `ui_gf_ready` push per toggle, batched
  like everything else. ⚠ If the lobby menuDef needs a new itemDef (vs re-pointing an
  existing dvar-driven line), that is a `mod.ff` structure rebuild — ride the next build.
- **The steal-worthy trick:** mirror ready state into **`self.statusicon`**
  (`"compassping_decoyfiring"` ready / `"compassping_enemy"` not — BOCL's exact pair), so
  the **scoreboard itself** shows readiness. Zero HUD elements, zero reliable commands.
  ⚠ Verify those two materials render client-side on Plutonium (stock compass materials,
  expected resident) and that spectator-state rows draw statusicon on our scoreboard.
- **Release rule**, gated by a new dvar (`scr_gf_lobby_readyup`, default 0):
  - Manual lobby (`scr_gf_lobby 2`): all seated humans ready ⇒ acts as the admin START.
    Admin START and the `scr_gf_lobby_timer` ceiling still win — the ceiling is what
    keeps one AFK player from holding the match hostage (BOCL solved hostage-taking only
    for the demo client; the ceiling is our stronger version).
  - Auto lobby (`1`): ready-up ADDS a hold beyond load+min until all-ready — a semantics
    change, which is why the dvar defaults 0.
  - Bots/democlient: excluded from tracking entirely (`istestclient`/`isdemoclient`, our
    standard filters) — no BOCL-style auto-ready needed.
- Late joiner mid-hold: tracked, starts unready — the count just grows. Leaver: their
  loop dies on disconnect; recount on next poll tick.

## 2. Rationed team timeouts (competitive pause, without pausing)

BOCL freezes mid-game (`bocl_timeout`, a dvar its loop watches, set from a script menu).
Ours should NOT: a 42s one-life round is unpausable in practice, and `gf_pauseMatch`
drags vision/clock/control state with it. The clean adaptation: **a timeout is a
one-round prematch extension applied at the round boundary.**
- Dvars: `scr_gf_timeouts` (per team per match, default 1; 0 = feature off),
  `scr_gf_timeout_seconds` (default 30, clamp 5-120).
- Flow: request lands any time (marks `game["gf_timeout_<team>"]`, decrements the
  ration); at the next round's `onStartGameType` the prematch length for THAT round is
  `scr_gf_prematch_seconds + timeout_seconds` (both teams requested ⇒ sum, capped 120);
  the pause-banner menuDef (`gf_pause_hud` infra) shows "TIMEOUT — <TEAM> (Ns)" instead
  of a frozen match. No clock tampering, no mid-round freeze, native prematch does the
  freezing — the same reuse philosophy as the round clock.
- Callers: bridge verb `timeout_<a|x>` (admin-granted, buildable today). Player-callable
  needs a menu-response channel — same `mod.ff` menu train as §4; don't block on it.
- Lifecycle: ration lives in `game[]` (wiped at match end by construction); a map_rotate
  mid-request just loses the request — degrade-to-stock, acceptable.

## 3. Lobby all-talk (one builtin)

`SetMatchTalkFlag( "EveryoneHearsEveryone", 1 )` at hold entry, `0` at release. Proven
MP-registered — **stock** `_globallogic.gsc` flips it at halftime display (`:662`) and the
match-end podium (`:689`), so relaxed-voice-at-social-moments is stock's own pattern;
BOCL's warmup ran it too (their `endPreGame` turns it off). Server posture is ready:
`sv_voice 1` live. ⚠ Whether Plutonium T5 VOIP actually functions end-to-end is unverified
from this box — test by ear before advertising it.

## 4. The menu-`execNow` experiment (client-console access we thought we didn't have)

BOCL's `connect.menu:38` runs `execNow "exec disabledDvars"` — commands executing in the
**client's own console context** at connect (their `writeconfig.menu`/`clientdvar.menu`
are the full promod-style cfg writer; retail pairs it with the `setmoddvar` server
command, which Plutonium lacks). Stock's own `main.menu` uses the same keywords, so the
menu VM has them; the open question is whether Plutonium honors them from a
**server-delivered mod menu**, and whether that context can write an **archived** dvar
(the class Plutonium blocks on the `setClientDvar` path — [[killfeed-duration-client-archived]]).
- **Why it matters MORE on our server:** `sv_disableClientConsole 1` means players cannot
  type console commands while connected ([[league-dvar-probe-2011-rulesets]]) — a menu is
  the ONLY in-game client-exec channel we have. If it works, an **opt-in** "recommended
  settings" menu (killfeed 20s, `cl_maxpackets 100`) becomes possible in-game instead of
  main-menu-only instructions.
- **Probe (listen host, laptop — the VPS blocks the console needed to read the result):**
  a minimal `gf_probe_exec.menu` whose `onOpen` runs `execNow "set gf_exec_probe 1"` +
  `execNow "seta gf_exec_probe_seta 1"` then closes; `menufile,` line; bridge verb opens
  it on the tester. Tester reads both dvars in their own console: plain-set landing =
  exec works at all; `seta` landing + persisting = the archived class is writable from
  menu context. Rides the same `mod.ff` rebuild train as the material spike.
- ⚠ **Consent line, non-negotiable:** if it works, it ships only behind an explicit
  player YES in the menu itself. Writing a player's archived dvars uninvited is the
  behavior we refuse `setClientDvar` for; a working bypass doesn't change the ethics.

## What we deliberately did NOT adopt

The fork-everything architecture (whole `_globallogic` family + `sd.gsc` +
`_callbacksetup`) — right for their total-conversion, wrong against our native-first
rule and the keep-the-whole-public-surface tax. Their per-player `setText` hudelem HUD —
retired here for configstring reasons. Their mid-game freeze timeout — replaced by the
boundary design above. Their custom rank stack (30 icons, XP handler, log persistence) —
that was the *cost of unranked retail*, which we don't pay on Plutonium; its one export
is the `logPrint("XP;guid;...;name")` line format that independently matches `GF_STAT`.
