# "I can't set anyone's prestige" — the cheat gate re-locks on every server restart, and the panel says otherwise

**Date:** 2026-08-20 (owner report: *"it was working the other day but now i cant set anyones
prestige"*). **Status: root-caused and FIXED** panel-side in `tools/rcon/public/app.js`
(`funBridge` / `refreshFunGate`) + `index.html`.

⚠ This is the **total-failure** half of that report. The separate "it changes then reverts" half was
a wrong DStat key path — [[dstat-key-path-must-match-stock-reader]].

## Symptom

Every verb in the panel's CHAOS & ACCOUNT block silently does nothing. The command queue shows a
clean ✓ (`gf_ack` advances normally), no error, no toast. The Cheat Verbs checkbox is showing **ON**.

## Root cause, in two halves

**1. The gate re-seeds to 0 on every fresh server process.** `gf_fun_cheats` has **no
`dedicated.cfg` line** — only a comment — so `gf_funInit`'s seed-if-empty
(`_gf_fun.gsc`: `if ( getDvar("gf_fun_cheats") == "" ) setDvar("gf_fun_cheats","0")`) sets it to `0`
at every server start. `funreset` re-locks it too, which was the documented path; the restart path
was not.

**2. The refusal is invisible from the panel.** `gf_funCheatGate()` reports via `gf_bridgeNotify`,
which is private to `gf_admin_guids` and renders with `iPrintLn` into the **in-game killfeed**. An
admin clicking from the panel is by definition not reading the killfeed. And because the GSC *did*
consume the command, `gf_ack` advances and the panel marks it received.

**3. …and the checkbox lies.** `#cbFunCheats` is filled only by `readServerDvars()`, a connect /
manual sweep that never re-reads. A browser tab left open across a server restart keeps rendering
the pre-restart value.

## How it was dated (reusable method)

⚠ **The engine's per-round dvar dump in `console_mp.log` is a free timeline.** It prints the full
table at every `map_restart`, so a run-length encode of one dvar across the file dates any change to
the round. Live evidence on the VPS:

```
gf_fun_cheats:  0 x323  ->  1 x46
modStats:       0 x370
```

`console_mp.log.001` closed 15:40:47 and the bootstrapper started 15:40:52, so the live log is
exactly one server session: the gate was **locked for the first 323 rounds after the restart** and
was flipped on for the last 46 — which is the moment the owner reported "now it's working".

⚠ The same table **exonerated the prime suspect**. `modStats` read `0` for all 370 dumps, i.e.
identical while it was failing and while it worked, killing the theory that the `modStats 0` ship
(commit `3fd02ea`, two days earlier — a seductive timing match) had anything to do with it.
See [[engine-dvar-defaults-from-log-dump]] for what that dump can and cannot prove.

## The fix

Panel-side, because the GSC behaviour is correct — a gate that defaults closed after a restart is
the right default for persistent, no-undo writes on real accounts.

- **`refreshFunGate(fresh)`** re-reads `gf_fun_cheats` and syncs the checkbox. Called on every reveal
  of the ADVANCED tab, so the control stops going stale.
- **`funBridge(bcmd,label)`** wraps `bridge()` for the 7 gated verbs (`pfunaim`, `funadventure`,
  `functeamgod`, `funprestige`, `funlevel50`, `funcodpoints`, `fununlockpro` — the ones that call
  `gf_funCheatGate()`). It re-reads the gate **fresh at click time** and refuses locally with a
  toast naming the reason, instead of firing a command whose refusal only exists in game.
- ⚠ **Anti-Quit is deliberately NOT wrapped** — `funantiquit_` does not call the gate in GSC, and
  wrapping it would invent a restriction the server does not have.

⚠ **A failed gate read must NOT block the send.** Absent evidence is not evidence of a locked gate,
and the GSC gate is authoritative anyway; refusing on a dropped rcon packet would invent an outage.
`funBridge` warns and sends. (Same principle as watchdog check 1d, which degrades to *no judgement*
rather than to "gone".)

Cost is one paced rcon slot per gated click. These are rare admin actions and it is not a poller, so
it does not touch the [[rcon-panel-queue-saturation]] budget.

## The generalisable trap

⚠ **A panel control that is written on change but only read on connect will eventually lie**, and it
lies hardest right after a server restart — precisely when the server-side value has just been reset
underneath it. Any row whose dvar the *server* can change on its own (a GSC seed, a `funreset`, a
map-load default) needs a re-read on reveal, not just a read on connect.

⚠ Second-order lesson: **a private-to-admin in-game notify is not feedback for a panel action.** If a
verb can refuse, the refusal has to reach the surface the click came from.
