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

Applied to the three still-naive parsers: `tools/rcon/server.js::parseStatusText`,
`tools/notify/join-notify.ps1::Parse-Status`, `tools/notify/join-notify.js::parseStatus`.
`status_service.ps1` + `conn_logger` (admin.json) were already safe via their own
end-anchored ip:port check — which is also why the belt-and-suspenders IP filter in
status_service's main loop kept bad bot flags from `/api/tick` out of the connect log.

RULE: any NEW box-side `status` consumer copies the end-anchored form above. Deploy note:
the RCON panel ships with `deploy.ps1 -Mod`; the notify/status services are box-side
(scp + restart the GF-JoinNotify / GF-StatusService tasks), not in the mod mirror.
Related: [[gf-admin-connection-history]], [[rcon-connect-sweep-unknown-cmd-spam]].
