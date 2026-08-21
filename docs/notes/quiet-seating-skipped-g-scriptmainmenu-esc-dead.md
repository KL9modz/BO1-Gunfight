# "Sometimes players can't open the pause menu" — quiet seating skipped `g_scriptMainMenu`

**Date:** 2026-08-20 (owner report: *"sometimes players cant open the pause, maybe as if anti quit
is on but its not"*). **Status: root-caused and FIXED** in `_gf_rounds::gf_setTeamFields` →
`gf_pushEscMenu`.

## Symptom

Intermittent, per-player, and sticky for the whole session: ESC does **nothing**. No pause screen,
no Leave Game, no Settings. Reads exactly like an anti-quit mod, which is why it gets reported that
way. Other players in the same match are fine.

## Mechanism

**`g_scriptMainMenu` is the pause screen's only door.** It is a client dvar holding the *name* of
the scriptmenu the engine opens when ESC is pressed in game. Stock seeds it per team:

| value | resolves to |
|---|---|
| `class_marines` / `class_opfor` (`game["menu_class_<team>"]`) | one-line wrapper menus whose `onOpen` does `open class` — the `class` menuDef in `ui_mp/scriptmenus/class.menu`, **the PC pause screen** (the file we fork for the ticker) |
| `team_marinesopfor` (`game["menu_team"]`) | the team-select menu (what a spectator gets) |
| `""` | **nothing — ESC is dead** |

**Every** stock team-assignment path re-pushes it, and that is not incidental — it is the only place
it is ever written:

- `_globallogic_ui::menuAutoAssign` `:269`
- `_globallogic_ui::menuAllies` `:502` / `menuAxis` `:551` / `menuSpectator` `:591`
- `_globallogic_player::Callback_PlayerConnect` `:344` / `:367` (the team-menu branches)
- `_globallogic.gsc:1023` at **match end** — sets it to `endofgame`, or to `""` on the killserver path

This mod **replaces those handlers** (`level.autoassign` → `gf_autoJoinBalance`, the
`level.allies/axis/spectator` menu wrappers) with *quiet* seating that has no menus by design —
`gf_seatJoinTeam`, `gf_quietSetTeam`, and the pre-spawn `pteam` / `movePending` consumers in
`gf.gsc`. None of them pushed the dvar, so a player seated by any of those kept whatever their
client happened to hold:

- `""` on a fresh game launch → ESC dead for the whole session;
- `endofgame` carried over from a previous match's end → ESC opens the wrong thing.

⚠ **`beginClassChoice` does NOT cover it.** `gf_seatJoinTeam` calls it, which looks like it should
put the player back on the stock rails — but under `scr_disable_cac 1` (which this mod forces every
round) `beginClassChoice` assigns `level.defaultClass` and **returns before any menu work**
(`_globallogic_ui.gsc:335-350`). The dvar push lives in the *callers*, not in it.

## Why "sometimes"

The discriminator is `gf_seatBalancedJoin`'s **exact-parity fall-through**. At an even human split
it hands the joiner to `gf_stockAutoassignStamped` → real stock `menuAutoAssign`, which **does**
push. At any other split it takes `gf_seatJoinTeam`, which did not. So whether a given player ended
up with a working ESC key depended on how the human split happened to sit at the moment they
connected — plus every later quiet move (boundary balance, reclaim, lock-queue seating, admin
`pteam`, the next-match team plan) being another chance to land on the silent path.

## The fix

One push, at `gf_setTeamFields` — the single choke point every sanctioned team write passes through
(the same reason the spectate-breadcrumb clear lives there), so no seating path can drift out of
sync again. Humans only; spectator writes get `menu_team`, real-team writes `menu_class_<team>`,
mirroring stock exactly.

⚠ **Unconditional — no skip-if-unchanged cache.** The client's copy is rewritten underneath us by
stock's own game-end push, so a "we already sent this" cache would skip precisely the push that
repairs it. Same rule, same reason as the per-client flinch push
([flinch-bg-viewkickscale-not-replicated](flinch-bg-viewkickscale-not-replicated.md)).

## Rule

**Any mod path that seats a human must leave `g_scriptMainMenu` valid**, exactly as it must leave
`pers["class"]` valid ([quiet-team-move-cleared-class-blocks-respawn](quiet-team-move-cleared-class-blocks-respawn.md)).
Both are stock post-conditions of team assignment that the quiet primitives silently dropped, and
both fail *later*, on a different screen, for one player at a time.

## Prior sighting, misread at the time

The lobby cam once suppressed the team menu with a per-tick `closeMenu()` + `g_scriptMainMenu ""`,
and the comment at `_gf_rounds::gf_gateEnterLobbyPresentation` records that this "also killed the
ESC/pause overlay every tick". That was fixed locally (by `level.forceAutoAssign` instead) without
anyone generalizing the lesson: the dvar is not lobby plumbing, it is the pause key.
