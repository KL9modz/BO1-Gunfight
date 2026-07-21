---
name: killfeed-duration-client-archived
description: "Killfeed = engine game-message window 0; duration = con_gameMsgWindow0MsgTime (seconds, stock 5). CLIENT-side + archived -> a server setClientDvar push is REFUSED (proven on the VPS with a control). Also: never use an archived dvar as the control in a push test"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 55448e2d-9d8d-4be0-9a43-ec0fcf48d69c
---

**The BO1 killfeed is not a hudelem — it is the engine's game-message window 0.** Windows are routed by
their `Filter` dvar, and window 0's filter is what carries the obituary type (verified in both the boot
dvar dump and a client's `config_mp.cfg`):

```
con_gameMsgWindow0Filter      "gamenotify obituary"   <- window 0 IS the killfeed
con_gameMsgWindow0MsgTime     "5"     <- on-screen time, SECONDS (the knob)
con_gameMsgWindow0LineCount   "4"
con_gameMsgWindow0FadeInTime  "0.25"
con_gameMsgWindow0FadeOutTime "0.5"
con_gameMsgWindow0ScrollTime  "0.25"
```
Window 1 = `boldgame` (bold center messages), window 2 = `subtitle`. The names are built from a
`con_gameMsgWindow%dMsgTime` format string in `BlackOpsMP.exe`, so they are real engine dvars
(live read: `Domain is any number 0 or bigger`), not cfg-created placebos.

**A player CAN retime their own killfeed, today, with no mod:** `/con_gameMsgWindow0MsgTime 20` in their
console. It's `seta`, so it persists in `config_mp.cfg`.

**A SERVER CANNOT.** Proven live on the dedicated VPS 2026-07-13 with a human client connected, via a dev
bridge verb `killfeed_<sec>` → `gf_bridgeVisSet( "con_gameMsgWindow0MsgTime", … )` → `setClientDvar`:
- bridge dispatched (`gf_ack` advanced 0→2),
- **control**: `thirdperson_1` (`cg_thirdPerson`, non-archived) pushed in the same session **landed** —
  the client's camera flipped, so the server→client push path was demonstrably alive,
- **treatment**: the client's `con_gameMsgWindow0MsgTime` **stayed at 5**.

That is the archived-dvar refusal, isolated: `con_*` is client-owned AND archived, the class Plutonium
blocks server writes to ([[rcon-dedicated-dvar-push-limits]]). Only two ways to own killfeed timing:
hand players the console line, or render our own killfeed in the menu layer.

⚠ **METHOD LESSON — never use an archived dvar as the control in a push test.** The first run of this
experiment used `fps_1` (`cg_drawFPS`) as the control. `cg_drawFPS` is *itself* `seta`/archived, i.e. the
same blocked class as the thing under test — so "no FPS counter appeared" is equally consistent with
"push blocked" and "push path dead" and distinguishes nothing. A control must differ from the treatment
in exactly the variable being tested. Known-good non-archived controls on this server: `cg_thirdPerson`,
`cg_drawCrosshairNames`.

⚠ **The listen-host trap applies here too**: this must be tested on a DEDICATED server with a real remote
client. On a listen host the console *is* a client's, which masks exactly this refusal.
