# The "UNTRACED" team writes are (mostly) unstamped STOCK menu/autoassign paths, not a C-side engine writer

**Date:** 2026-07-20. Reframes the "engine C-side mis-seater" hypothesis. **Status: stamps
shipped (`stockauto`, `stockmenu`); the next traces prove or disprove the remainder.**

## The live capture that cracked it

`GF_TEAMTRACE: UNTRACED human KL9 spectator -> axis - last stamp NONE, at pre-spawn`
(mp_hanoi round 2). KL9 was a user-tagged spectator who clicked **Auto Assign** on the team
menu. The Auto Assign response routes through `[[level.autoassign]]` = the mod's
`gf_autoJoinBalance` — which, for a balanced human split, deliberately falls back to
`[[level.gf_stockAutoassign]]` = stock `menuAutoAssign`. **Stock writes `pers["team"]` with no
writer token**, so the tracer flags the mod's own sanctioned fallback as UNTRACED.

## The bot half

Parked (spectator) bots hit the re-begin team menu (`_globallogic_player.gsc:365`) and test
clients **auto-respond to menus** — the response lands in the mod's own
`gf_menuTeamChoice` wrapper, whose bot/demo branch passes **straight to stock**
(`[[stockFn]]`, unstamped). That is the prime suspect for the every-re-begin
`UNTRACED bot spectator -> team … at pre-spawn` noise previously attributed to a C-side
engine write.

## What shipped

- `gf_stockAutoassignStamped()` (`_gf_rounds.gsc`) wraps all three `gf_stockAutoassign`
  fallback sites (bot/demo passthrough, balanced-split fallback, off-plan joiner) and stamps
  **`stockauto`** with the team stock picked. Stamping AFTER the call is safe here — the target
  is unknowable before stock picks, and `menuAutoAssign`'s team write is synchronous (no yield
  between write and stamp).
- `gf_menuTeamChoice`'s bot/demo passthrough stamps **`stockmenu`** (target known: the menu
  choice) before calling stock.

## How to read future traces

- `by stockauto` / `by stockmenu` = a sanctioned stock path, working as designed — noise, not
  a bug.
- A **remaining** `UNTRACED` line after this change is the real signal: a write that came
  through none of the wrapped paths — only then is the C-side engine writer (or an unknown
  stock path) back on the table.
