---
name: ""
metadata: 
  node_type: memory
  originSessionId: 46023d59-7454-43f3-a346-e04b44bedd59
---

Reported 2026-07-12: `Com_ERROR: Server Disconnected - Server command overflow` on a client, at the
moment an admin clicked **START** in a Manual pregame lobby on the VPS.

## ⚠ THE BUDGET HAS TWO ERROR MESSAGES, NOT ONE

Reported 2026-07-13, **same lobby START window**, after the batching fix below was already live:

    Com_ERROR: CL_CGameNeedsServerCommand: EXE_ERR_RELIABLE_CYCLED_OUT
    ERROR: CL_CGameNeedsServerCommand: A reliable command was cycled out.

**Same disease, opposite end of the wire.** Do not treat it as a new bug:

| | who detects it | what it means |
|---|---|---|
| `Server command overflow` | the **SERVER** | the client stopped acking and the server's outgoing queue overran → `SV_DropClient` |
| `A reliable command was cycled out` | the **CLIENT** | the client *received* everything, but cgame went to execute command N and found it already overwritten in its own fixed ring — i.e. >`MAX_RELIABLE_COMMANDS` arrived in a window where cgame wasn't pumping snapshots |

Both mean **too many reliable commands in a window where the client isn't executing them**. The
"cycled out" variant is the one you get when the client is *alive and receiving* but **frozen** —
which is precisely `map_restart(false)`. So seeing it means the budget is still over, not that a
different subsystem broke.

## The mechanism (this is a CLIENT-side error, not a server one)

- **Every `setClientDvar` is one reliable server command.** So is every configstring change, print,
  and client connect/disconnect notice.
- The client's ring buffer for them is **fixed** (`MAX_RELIABLE_COMMANDS`). The client raises a
  **`Com_Error` — a hard disconnect, not a warning** — the moment the server's command sequence
  outruns the last one it *executed* by more than that ring.
- Therefore overflow needs **two things at once**: a **burst** of commands, AND a client that has
  **stopped acking**. Either alone is harmless. This is why it is intermittent and why it had never
  fired in normal round cycling.

## Why the lobby START specifically

`map_restart(false)` (the Auto/Manual lobby's fast-restart, `_gf_rounds::gf_waitForLoadingClients`)
is *the* stall: every client fully re-inits — that is the whole point of `false` over `true`, it's
what re-fires the gun-rack / spawn music / welcome splash. The spawn wave's HUD push burst lands
**inside** that stall window. Unbatched that was **~45 reliable commands per human** (~24 health
panel + ~21 loadout overview), plus bot kick-all before the restart and bot re-adds after — right at
the ring's edge.

⚠ **`gf_hudRevealStagger` does not save you.** It spreads the burst across ~0.25s of *server* frames,
but a stalled client isn't acking during any of them — the commands still queue up. Staggering
addresses the *snapshot gap* ("Connection Interrupted"), a different problem.

## The fix: `setClientDvarS` (plural)

Stock's variadic builtin. Carries **every** name/value pair in a **SINGLE** reliable command:

    self setClientDvars( "ui_gf_lo_icon0", shader0,
                         "ui_gf_lo_icon1", shader1, ... );   // 1 command, not 2

Precedent: `_globallogic_player.gsc:91` (4 pairs), `_zombiemode_challenges.gsc:217` (**9 pairs**) — so
the 8-pair groups used here are comfortably inside the engine + compiler limits. Watch the 1024-char
command limit for long string values.

Applied in `_gf_hud.gsc` (loadout overview, panel chrome, pause banner, reveal, self bar, health rows)
and `_gf_rounds.gsc` (lobby cam-put, lobby HUD hide, lobby release). **~45 → ~12 commands per human
per spawn.**

`gf_pushHealthRow` now pushes its whole row as ONE command whenever *any* of its 5 values changes
(`gf_rowChanged` signature check). This is fewer commands than the old per-dvar cached path on **both**
paths — spawn burst 5→1, and in a firefight (hp+fw change together every 0.1s tick) 2→1. Re-sending an
unchanged pair inside a batch is **free**; it is the command **COUNT** that is scarce, not the bytes.

⚠ **Never expand a batch back into individual `setClientDvar` calls**, and never add an unbatched
per-player push loop.

## The one the first pass MISSED: an O(players) unbatched loop in the lobby

The 2026-07-12 fix batched the **spawn burst** and declared victory. It missed
`gf_lobbyRosterLoop` (`_gf_rounds.gsc`) — which pushed `pcount` **plus one command per occupied
name slot**, per human, on every roster change. **The only push stream in the mod whose cost scales
with player count**, and it lives *in the pregame lobby* — the exact window that was already the
tightest.

Worse, it compounds with the bot fill: the reconciler adds bots on a **0.5s stagger** and this loop
ticks at **0.5s**, so a fill produced roughly **one roster change per bot**. A 12-bot fill cost
~12 changes × ~13 commands = **~156 reliable commands per human** — on its own more than the ring.

Fixed by padding the 12 fixed slots and pushing them as flat batched groups (1 command for a ≤6
lobby, 2 for 7-12). Re-sending unchanged/empty pairs inside a batch is free.

**The lesson that generalizes:** when auditing a reliable-command budget, `grep setClientDvar` is not
enough — you must find the calls **inside a loop over players AND a loop over data**. A per-player
push is O(n); a per-player push of a per-item list is O(n²) and is what actually blows the ring.

## What is still NOT proven

The mod is **not necessarily the dominant emitter** in the lobby-START window. `map_restart(false)`
makes the engine re-send configstrings (`cs` commands are themselves reliable commands), and the bot
kick-all fires immediately before it. Those are engine traffic we don't control and were never
measured. Everything above reduces *our* share; if "cycled out" recurs after this, the next step is
to **stop churning bots across the restart**, not to shave more mod pushes.

## Related trap: a GSC dvar animation is a reliable-command STREAM

`gf_slideLoadout` / `gf_fadeDvar` push at 20 Hz for the animation's whole duration — the 0.5s loadout
outro is now **~13 commands/human/**round** (batching the off+alpha pair per step halved it from ~26),
forever. The menu layer could in principle own time-based animation for free:
`milliseconds()` is available in menu `exp`s (stock `after_action_report.menu` /
`game_summary.menu` use `ui_time_marker` + `exec "setdvartotime"`).

⚠ **RESOLVED UNVIABLE:** `milliseconds()` in a menu `exp` is the **client's UI-realtime clock, not
server `cg.time`** (proof: `raw/ui/main.menu` scrolls fog with `milliseconds() % PERIOD` *before any
server connection*), so the server **cannot** stamp the start marker in its own `gettime()` base. Stock
only ever stamps it **client-side** in a menu's `onOpen` (`exec "setdvartotime"`), and our always-loaded
`loadMenu`'d HUD menu has **no per-round client event** to hang the stamp on. So the free menu-owned slide
is dead — don't re-open it or burn a `mod.ff` rebuild on the probe; batching is the floor here, an
animation is a reliable-command stream by construction ([[menu-milliseconds-client-local-no-per-round-event]]).

See [[connection-interrupted-mitigations]] (the *other*, distinct symptom of push volume — the
snapshot gap), [[settext-configstring-exhaustion]], [[rcon-panel-queue-saturation]] (same "the
transport has a hard budget, coalesce into it" lesson, one layer up).
