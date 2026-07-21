---
name: read-the-server-not-the-file
description: "OPERATING RULE: never assert live server state from a config file. A file is an INTENTION; only the running process is REALITY. Read the running server (panel /api/dvars?fresh=1, or the boot dvar dump in console_mp.log) before claiming any dvar/setting value. A file-vs-process divergence is itself a finding."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 595172d5-cbbd-43fc-bf20-f847ced537ba
---

**Never assert what a live server is doing by reading a config file. Read the running process.**

A config file is an **intention**. The running process is **reality**. They diverge constantly, and every
time I have trusted the file I have been wrong.

**Why:** the file and the process fall out of sync through at least five routes, all of which have
actually happened on this box:
- **Edited after boot.** A cfg value only counts if it was `exec`'d at boot. (2026-07-12: `dedicated.cfg`
  on disk said `sv_timeout 60`, the running server said **15** — the edit landed post-boot and I nearly
  reported the file's value as live. → [[sv-timeout-and-connecttimeout-template-defaults]])
- **Set live and never persisted.** An RCON `set` changes the process and not the file, so the value dies
  at the next restart. The reverse of the above, and just as invisible.
- **A decoy file.** There are TWO `dedicated.cfg` on the VPS and only one is live. A recursive
  `dir /s` finds only the stale `C:\gameserver` template, which is exactly how it fools you.
  (→ [[connection-interrupted-mitigations]])
- **Shipped ≠ loaded.** `mod.ff` reaches the box only via `origin/release`, so committed menu/str/FX
  changes are silently NOT live. (→ [[modff-drift-vs-gsc-deploy]])
- **Deployed ≠ compiled.** GSC can deploy and still fail to load. (→ [[vps-gsc-deploy-log-verification]])

**How to apply:** before stating any live value, ask *"did I read that from the thing that's running, or
from a file that merely claims to configure it?"* Then read the process:
- **Dvars** → the panel on `127.0.0.1:3000`: `/api/dvars?fresh=1&names=<a,b,c>&password=<pw>`. Panel-first
  — never add a direct RCON poller ([[rcon-panel-queue-saturation]]).
- **Boot-time values** → the dvar dump in the mod folder's `console_mp.log` (written at level load, so it
  shows what the server *actually started with*).
- **Load/compile reality** → the two logs in the storage-path mod folder ([[vps-gsc-deploy-log-verification]]).

Read the file **only** to answer a different question: *will this value survive a restart?* That is the
file's real job — persistence, not truth.

⚠ **The cfg BEATS a code default, so a cfg line restating a default silently PINS it forever.** Nearly
every mod dvar is seeded **if-empty** (`if ( getDvar( x ) == "" ) setDvar( x, default )`) and
`dedicated.cfg` is exec'd at boot **before** the gametype callback — so a cfg value means the seed never
fires. That is correct by design (an owner must beat a code default), and it is a trap: changing a default
in code does **nothing** to a box whose cfg already sets it. Live 2026-07-16 — the team/bot refactor moved
`gf_fill_n`'s default 0 → 2, but the VPS kept running **3v3** after the deploy because its cfg carried
`set gf_fill_n "3"`, a line written back when the default was 0 purely so a reboot wouldn't come back
bot-free. The old rationale had silently expired; the line outlived it and overrode the new default.
**Rule: `dedicated.cfg` carries only DEVIATIONS from the defaults, never a restatement of one** — delete
the line and let the seed own it, or the same trap re-arms at the next default change. When a deploy
"doesn't take", grep the box's cfg for that dvar FIRST (`deploy.ps1` does not ship `dedicated.cfg` —
the live file is whatever the box has, and a repo grep proves nothing about it).

⚠ **A file-vs-process divergence is not noise, it is a FINDING.** It means someone edited without
restarting, or set a value live without persisting it. Say so out loud instead of silently reconciling to
whichever number looks right.

Same family of error as [[flinch-bg-viewkickscale-not-replicated]] (the dvar was set on the server and
read on the *client* — check both sides) and [[getdvarint-on-enum-dvar-broke-cheat-guard]] (the value
being read was never the value that was there). The common root: **I assumed a read was authoritative
without checking what was actually doing the reading.**
