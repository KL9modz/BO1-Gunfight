# "JOIN GUNFIGHT" main-menu button — dead after leaving a match, until the game restarts

**Date:** 2026-08-20. **Status: NOT root-caused.** Three hardening changes are in `ui_mp/main.menu`,
one of which is a live hypothesis for the real repro. **One cheap test settles it and has not been
run yet** — see *The test that is still owed*. ⚠ Two earlier theories were written up in this file as
"root cause" and both were wrong; the history is kept below precisely so nobody re-runs them.

## The actual repro (owner, and it is the thing to explain)

> Sometimes after leaving the match and returning to the main menu, it won't work until I restart my
> game and rejoin manually.

Two properties any correct explanation must have, and which killed both earlier theories:

1. **It only breaks after having been in a match.** Not on a cold main menu.
2. **A game restart is required.** It does not clear on its own.

⚠ And one observation that narrows it hard: **in the broken state the rest of our `main.menu` fork
still renders** — the gunfight.us ad block and our ticker are both on screen (owner, confirmed). So
the menu is OURS, the itemDef is live, and **only the action does nothing.** That is the whole
remaining surface.

## Not related to the ESC/pause bug

Asked and answered: not the `g_scriptMainMenu` fault
([quiet-seating-skipped-g-scriptmainmenu-esc-dead](quiet-seating-skipped-g-scriptmainmenu-esc-dead.md)).
That dvar is read **in game** for ESC's menu; this is a pre-connect main-menu itemDef. Two separate
faults that merely arrived together.

## The test that is still owed

**In the broken state, open the console at the main menu and type `connect gunfight.us:28960`.**

- **It connects** → the client is fine and only the *menu action path* is broken. The `execNow` →
  `exec` change is then the likely cure (a re-entrant `EXEC_NOW` from inside a click, on a UI that
  was just torn down and rebuilt by the return-to-menu zone reload).
- **It does nothing** → the whole client cannot connect until restart; the button is a victim, not a
  cause. Then the `exec "disconnect";` prefix is the thing to watch, and if that does not do it, the
  problem is engine/session state a menu cannot reach — at which point the honest options are to
  accept the button as unreliable or drop it.

⚠ **Record the answer here.** Everything below is hardening; this is the only step that discriminates.

## What is in `ui_mp/main.menu` now (three changes, one rebuild)

1. **`exec "disconnect";` before the connect** — the live hypothesis, because it is the only change
   whose shape matches the repro: the button breaks *only once there is a session to go stale*, and a
   restart is exactly what clears one. Stock never issues a bare connection change either —
   `exec "disconnect"` appears **30** times across the shipped menus (every leave-game path is
   literally `close popup; exec "disconnect"`) and `execNow "disconnect"` **zero**. At a main menu
   with nothing connected it is a no-op, so it is free on the healthy path.
2. **Stock's Demonware readiness gate** (`IsSignedInToLive` → `isDemonwareFetchingDone` → else
   `popup_connectingtodwhandler`), as the macro `GF_JOIN_ACTION`. ⚠ **Hardening, NOT the diagnosis** —
   see the retracted theory below. Still right to have: stock wraps every networked main-menu action
   in it (7 uses, including the PLAY/OPERATIONS/THEATER buttons directly below ours) and ours was the
   only one that did not, and its `else` branch turns a dead click into a "still connecting" popup no
   matter what the root cause turns out to be.
3. **`execNow` → `exec`** for the connect. `execNow` is `Cbuf_ExecuteText( EXEC_NOW )`: synchronous
   and re-entrant from inside the click handler; `exec` queues to the next command-buffer flush.
   Stock's split for connection-state commands is total (`disconnect` 30/0, `map` 1/0, `connect` never
   issued from a menu at all), and Plutonium replaces connect with an async pipeline (DW address
   handle → resolve → mod-list → FastDL → `joining server...`) that is a poor thing to start
   re-entrantly.

## Eliminated — do not re-run any of these

- **The build.** Inflating the shipped `mod.ff` (`tools/inflate_fastfile_zlib.ps1`) showed the action
  compiled **intact**, quoted multi-word argument and all.
- **The macro.** `TEMP_CHOICE_BUTTON_VIS` is the one stock's own working buttons use.
- **The address, port, and command.** **`connect gunfight.us:28960` typed at the main-menu console
  connects** (2026-08-20). DNS resolves in-game, the hostname form is accepted, the port is right.
- ⚠ **The `:8305` red herring.** Every client-log resolution reads `…:8305`, never `:28960`, though
  the server certainly binds 28960. It is the session endpoint Plutonium negotiates *after* the
  connect (Demonware address handle; placeholder `0.255.0.255:3074`) — **not an address a player
  names.** The console test above disproves it in one step. **Do not chase the port again.**
- ⚠ **RETRACTED THEORY 1 — "Demonware wasn't ready yet."** The idea was that a click landing before
  `Can play online` goes true dies silently. It does not fit the repro (a cold-start race clears
  itself in seconds; this needs a *restart*), and the logs do not support it either: across every
  captured client log there are **45 readiness dumps and `Can play online` is `true` in all 45**,
  including one *after* a disconnect. The only `false` term is `Live_UserIsGuest`, which is supposed
  to be false. The gate stays in as hardening; it is not the diagnosis.
- ⚠ **RETRACTED THEORY 2 — "the `mod` zone loses to the UI-zone reload."** Real and worth knowing (see
  the load-order correction below), but **disproved for this bug** by the owner's observation that the
  ad block and ticker still render in the broken state. If the fork had lost registration the whole
  block would be gone, not just the button.

## Genuine side-finding: the load-order rule had a hole (CLAUDE.md corrected)

The UI zones are loaded **three times** per session and `mod` is in only one of those passes (live
client log, 2026-08-20):

| pass | zones | `mod` present? |
|---|---|---|
| game startup | `patch_ui_mp` → `plutonium_ui_mp` → `en_ui_mp` → `ui_mp` | **no** — `mod` never appears before them |
| connect | **`mod`** (logs `Overridden rawfile: … from zone mod`) → then the four UI zones | **yes** — the only pass our overrides win |
| return to main menu after a match | UI zones unload (`creating default assets stubs`) and reload | **no** — `mod` is not reloaded (nor unloaded) |

CLAUDE.md's override table described pass 2 and implied it was the whole story. It now carries all
three. ⚠ This does **not** affect `cgame.str` or the HUD menus — those are consumed in game, inside
pass 2's lifetime, which is why they have always worked.

## Shipping — none of it is in a built artifact yet

⚠ A `mod.ff` built at 21:33 still inflated to the OLD `execNow`, **31 seconds after** the source edit
landed. `build_ff.ps1` **stages** menus to the zone-source paths and the linker reads the staged copy,
so a build already in flight bakes the pre-edit file regardless of source mtime. **A newer `mod.ff`
mtime is NOT evidence an edit is in it.** Inflate and read the action string:

```
tools\inflate_fastfile_zlib.ps1 -FastFile mod.ff -OutFile <tmp>\mod.zone
# then grep the printable strings for: connect gunfight
```

Sequence: rebuild → **inflate and confirm** → publish to `origin/release` → `deploy.ps1 -Mod`. Players
get it on their next FastDL sync, and only clients that already hold our `mod.ff` render the fork at
all — retention, not acquisition.

## Why this cost three passes

The button was added in `2c0f135` (2026-08-16) with no record of it ever having been verified working.
⚠ **A menu action that fires a console command is not testable by reading it** — it compiles clean,
renders clean, and fails silently. Anything added to a `.menu` that execs a command needs a real click
before the commit claims it works, and a *stateful* one (connect/disconnect) needs a click in each
state: cold menu, and back-from-a-match.
