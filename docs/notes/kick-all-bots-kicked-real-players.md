---
name: kick-all-bots-kicked-real-players
description: "The RCON panel's Kick All Bots kicked REAL PLAYERS: its bot flag was fail-open (\"not provably human ⇒ bot\"), and a still-connecting T5 client looks exactly like a bot in `status`. A classifier's DEFAULT must never be the destructive class"
metadata: 
  node_type: memory
  type: project
  originSessionId: 99c4527d-2bc7-481a-9b27-d9a98fe9ba54
---

The panel's **Kick All Bots** button kicked real players (reported live, 2026-07-13). Two
independent defects, either one sufficient.

**1. The bot flag was FAIL-OPEN.** `tools/rcon/server.js::parseStatusText` classified:
```js
const isBot = !(isLocal || /^\d{1,3}(\.\d{1,3}){3}:\d+$/.test(addr));   // "not provably human ⇒ bot"
```
and `kickBots()` `clientkick`'d everything that flag marked. So **any** row the parser couldn't
read was a kick target.

⚠ **The trigger is an engine fact worth memorizing: a STILL-CONNECTING T5 client presents in
`status` with guid `0` and the ADDRESS column holding a lastmsg value** — i.e. indistinguishable
from a bot under an address-only check. `status_service.ps1` already knew this (its main loop
re-checks `ip:port` itself precisely to "skip … clients still connecting (guid 0, the address
column holding a lastmsg value)") and was safe. The panel didn't, and the panel is the one with a
kick button. The window is **wide** on this server: a first-join FastDL client does a 30-60s engine
rebuild ([[fastdl-first-join-black-screen-rebuild]]) and `sv_connectTimeout` is 200s.

**2. It kicked by client NUM from a stale snapshot.** Serially, through the panel's ~850ms-paced
rcon queue (~5s for 6 bots). Client nums are **SLOTS** and a kick frees one instantly — a human
connecting mid-sweep lands in a freed slot and eats a `clientkick` aimed at a bot that is already
gone. A perfect classifier would not have fixed this ([[rcon-panel-queue-saturation]]).

**How it got in:** commit `32990d7` fixed a real bug (spaced names shifting fixed columns → bots
counted as humans) by end-anchoring the address read — correct — but *also* flipped the classifier
from POSITIVE (`p[3]=="0" && p[6]=="unknown"`) to NEGATIVE. The end-anchoring alone was the fix; the
polarity flip was collateral, and nobody caught it because the bug being chased ran the **other**
way (bot-as-human), while the destructive consumer quietly rode the same flag. The button's own
tooltip still described the old, safe behavior — a tell.

**The fix:** a bridge verb **`botkickall`** → `_gf_bridge.gsc::gf_bridgeKickAllBots()`: resolves
identity **server-side** with `istestclient() && !isdemoclient()`, kicks in ONE yield-free pass (no
slot can be freed and refilled inside it). The panel just calls `bridge('botkickall')`. The status
parser is now **three-state** — `bot === true` (positive: guid 0 at a non-routable addr) /
`false` (a real ip:port or loopback) / **`null` = couldn't classify** — and callers must test
`bot === false` / `=== true`, **never** truthiness or `!p.bot`.

**Why:** a heuristic guess was wired to a destructive action, so every parse failure cost a real
player. The bot reconciler (`_bot.gsc`) was always correct here — it gates its kicks on
`istestclient()` — which is exactly the pattern the panel should have copied.

**How to apply:**
- **A classifier's DEFAULT must never be the destructive class.** "I couldn't tell" is a third
  state, and it is never actionable. Bias every failure toward *not* acting on a person.
- **Identity for a destructive action comes from the SERVER** (`istestclient()`), never from parsed
  `status` text. Never re-implement a kick/ban in the panel off a text parse.
- Never kick by **client num** from a snapshot across a paced queue — nums are reused slots. Do the
  whole sweep server-side in one pass.
- A single-player kick the admin explicitly right-clicked is fine — that's a chosen target, not an
  inferred one.

Related: [[status-parser-name-spaces-bot-miscount]] (the commit that flipped the polarity),
[[sv-timeout-and-connecttimeout-template-defaults]], [[read-the-server-not-the-file]].
