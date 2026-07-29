---
name: status-parser-name-spaces-bot-miscount
description: "RCON `status` parsers must read name/addr END-anchored — player names can contain spaces (e.g. bot \"MCG Gordon\"), which shifts fixed columns and makes bots count as humans"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1392a9bc-1ae2-4f2a-96d6-e857ed21e40e
---

Any parser of the Plutonium T5 `status` reply MUST read the player NAME and ADDRESS
**end-anchored**, never as fixed token indices. Columns are
`num score ping guid  NAME  lastmsg address qport rate`, and the NAME can contain spaces
(the bot **"MCG Gordon"** is the canonical case; human names too).

**The bug (FIXED 2026-07-08):** naive parsers split the line on `\s+` and used `p[4]` as
the name + `p[6]` as the address, with bot detection `guid=="0" && p[6]=="unknown"`. A
spaced name splits into two tokens → name reads as just "MCG" AND every trailing column
shifts right one, so `p[6]` holds the *lastmsg* value (not `"unknown"`) → the bot leaks in
as a human. Symptom: a phone ntfy "MCG joined" (note the truncated first word) and the RCON
panel/logs miscounting a bot as a person.

**The fix (mirrors the already-correct `status_service.ps1`):**
- address = 3rd-from-last token (`p[len-3]`)
- name = everything between guid and lastmsg (`p.slice(4, len-4)` / `$p[4..($len-5)]`)

⚠ **CORRECTION (2026-07-13) — this memory used to end with "bot = the address column is NOT a real
`ip:port`; do not key off `guid=="0"` or `addr=="unknown"`." That guidance was WRONG and it cost
real players.** Only the **end-anchoring** above was the fix. The same commit also flipped the
classifier from POSITIVE to NEGATIVE ("not provably human ⇒ bot"), which made every unreadable row
a bot — and the RCON panel's Kick All Bots button `clientkick`'d whatever that flag marked. A
**still-connecting client presents with guid 0 and a lastmsg value in the address column**, so it
scored as a bot and **got kicked**. Keep the end-anchored read; make the test **POSITIVE and
three-state**: `true` = guid 0 at a non-routable addr, `false` = a real ip:port/loopback,
`null` = couldn't classify (never actionable). Full incident + the kick rules →
[[kick-all-bots-kicked-real-players]].

**CONSOLIDATED (2026-07-29): the parser is single-sourced per language — share the module,
never copy the form.** `tools/status_parse.js` (required by the panel's `server.js` and by
`join-notify.js`) and its PowerShell twin `tools/status_parse.ps1` (dot-sourced by
`status_service.ps1` and `join-notify.ps1`) are the only two implementations — change one,
change both. The two PS services reach their copy ONLY on the panel-down fallback path: the
happy path consumes the panel's already-parsed `/api/tick` / `/api/status` JSON, so the .js
copy does the parsing box-wide. Both twins are pinned to ONE fixture
(`tools/tests/fixtures/status_reply.txt`) by mirrored test suites
(`tools/rcon/test/server.test.js` + `tools/tests/status_parse.Tests.ps1`) — a one-sided edit
fails the other side's mirror case. The consolidation also retired the LAST diverged copy:
`status_service.ps1`'s fallback still carried the banned NEGATIVE polarity
(`bot = -not isHuman`) and an unguarded `[int]` ping cast that threw the whole poll on a
non-numeric column. `conn_logger` (admin.json diffing) stays separate — it never parses
status text, only re-validates address shapes.

RULE: any NEW `status` consumer requires/dot-sources the shared parser — never a fresh copy.
Deploy note (corrected 2026-07-29): ALL of these ship with `deploy.ps1 -Mod` — the
GF-RconPanel / GF-StatusService / GF-JoinNotify / GF-ConnLogger scheduled tasks execute from
the MODS-FOLDER MIRROR (verified against the live task definitions), so the deploy's service
recycle is what loads a parser change; this note's old "scp box-side, not in the mod mirror"
caveat was stale. Related: [[gf-admin-connection-history]], [[rcon-connect-sweep-unknown-cmd-spam]].
