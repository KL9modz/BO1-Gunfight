# Quiet team move cleared `pers["class"]` → next round's spawn blocked behind the class menu

**Date:** 2026-07-20 (live repro: basscar101 on `mp_villa`; same bug as the YooDyl `mp_silo`
report 2026-07-19). **Status: root-caused and FIXED** (`gf_quietSetTeam` + `gf_forceTeamQuiet`).

## Symptom

A player auto-balanced (or otherwise quiet-moved) to the other team at a round boundary could not
spawn at the next round start — the game held them at a menu ("forced to choose a class / team")
until they manually made a selection. Every OTHER player auto-spawned normally.

## Mechanism — three facts that only bite in combination

1. **`gf_quietSetTeam` cleared `pers["class"]`** (mirroring stock `_teams::changeTeam`, which also
   clears it). Stock gets away with the clear because `changeTeam` always follows with
   `beginClassChoice()`; the mod's *quiet* primitive skips that call **by design** (it runs during
   the killcam — no menus, no spawn driving).
2. **Stock's re-begin auto-spawn is gated on a valid class.** `map_restart(true)` keeps `pers[]`,
   and the re-begin re-runs `Callback_PlayerConnect`; a player with a defined team hits
   `_globallogic_player.gsc:386`:
   `if ( isValidClass( self.pers["class"] ) ) spawnClient(); else showMainMenuForTeam();`
   A normal dead player still carries last round's class → auto-spawns. A quiet-moved player
   carried `undefined` → the menu branch.
3. **`showMainMenuForTeam` (`_globallogic_ui.gsc:374`) does NOT honor `scr_disable_cac`** — unlike
   `beginClassChoice` (`:335`), which under `scr_disable_cac 1` assigns `level.defaultClass` and
   auto-spawns without any UI, `showMainMenuForTeam` unconditionally `openMenu(menu_changeclass_
   <team>)`. So on a disable-cac server (this mod, every round) the engine shows a create-a-class
   menu that "shouldn't exist", and the player is stuck behind it until they click.

## The fix

`gf_quietSetTeam` (`_gf_rounds.gsc`) and its mirror `gf_forceTeamQuiet` (`_gf_bridge.gsc`) now do
what `beginClassChoice` would have done: moving to a **real team** under
`level.oldschool || scr_disable_cac == 1` sets `pers["class"] = level.defaultClass` (instead of
clearing), so the moved player passes the `:386` gate and auto-spawns like everyone else. Class
*content* is irrelevant here — `gf_giveCustomLoadout` overrides the whole loadout at spawn — it
just has to pass `isValidClass`. Spectator moves keep the clear (no class gate on the spectator
branches). `_bot::gf_botQuietSetTeam` is deliberately untouched: bots demonstrably spawn fine
(BotWarfare drives their class/spawn), and touching a working path is pure risk.

## How it was caught

`gf_trace_teams 2` (attributed-move logging, enabled earlier the same day — level 1 logged only
UNTRACED writes and was blind to this):

```
71:55 GF_TEAMTRACE: human basscar101 axis -> allies by quietset (at boundary-out, round 8)
```

…and `GF_TEAMWATCH` / `GF_RECLAIM` at **0 lines**, proving the player was never in spectator — which
killed the "stranded in spectator → team menu at `:365`" hypothesis for this report and pointed at
the class gate instead.

## Broader reframe of the "team menu after move/join" reports

- The **spectator-strand** shape (`pers["team"]=="spectator"` at a boundary → `:365` team menu) has
  **never been observed by instrumentation** (TEAMWATCH: 0 lines ever) — it was inferred from the
  same player reports this bug now explains. It may not exist for humans at all. The reclaim
  containment + needteam/stamp forensics stay armed in case it does.
- The **bot mis-seater** is confirmed routine engine behavior: parked (spectator) bots are re-seated
  by a stampless write (`UNTRACED … last stamp NONE, at pre-spawn`) at nearly **every** re-begin —
  the engine's C-side re-begin auto-assign of spectator test clients. `GF_FILLGUARD` re-parks them
  immediately; that containment is working as designed and is the permanent answer (GSC cannot hook
  the engine write).

## Rules to keep

- **A quiet team write to a real team must leave `pers["class"]` valid.** Any new quiet-placement
  primitive must copy the `level.defaultClass` assignment, or its target blocks at the next
  re-begin behind `showMainMenuForTeam`.
- `showMainMenuForTeam` ignoring `scr_disable_cac` is a stock asymmetry to design around, not a
  thing to patch (overriding `_globallogic_ui.gsc` means keeping its entire public surface).
- Player reports of "choose a team" vs "choose a class" are interchangeable — the class menu's ESC
  path lands on the team menu, so witnesses describe either. Don't fork hypotheses on that wording.
