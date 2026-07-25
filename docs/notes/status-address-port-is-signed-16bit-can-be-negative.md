---
name: status-address-port-is-signed-16bit-can-be-negative
description: "Plutonium T5 `status` prints the client address port as a SIGNED 16-bit value, so a source port >32767 shows as `ip:-NNNNN` — a `:\\d+` regex rejects it and drops ~half of real players from IP/notify/history"
metadata:
  node_type: memory
  type: project
---

The `address` column of the Plutonium T5 `status` reply prints the client's port as a
**signed 16-bit integer**, so any client whose real source port is **>32767** shows up as a
**negative** port:

```
8  126 65 6718240 6foot1geek^7   0  69.244.29.108:524      -25022 25000   ← :524     positive
3    0 80 6426391 MalachiLabs^7  50 172.56.108.235:-12558  -29608 25000   ← :-12558  NEGATIVE
```

`52978 - 65536 = -12558` — the port wrapped. (The `qport` column already shows this openly:
`-24036`, `-29608`, `-25022`.) **The IP itself is always valid** (`172.56.108.235`); only the
port field carries the sign.

**The bug (FIXED 2026-07-24).** Every box-side `status` consumer validated the address with
`^\d{1,3}(\.\d{1,3}){3}:\d+$`, and `\d+` rejects the `-`. A rejected row is classified
`bot = null` (unclassifiable), which cascades:
- **RCON panel** (`server.js`) → `ip = null` → roster shows `-` for that player.
- **Join notifier** (`join-notify.js`/`.ps1`) → the `bot === false` filter drops them → **no
  phone alert on join**.
- **Status service / conn logger** (`status_service.ps1`, `conn_logger.ps1`) → row skipped →
  the player **never reaches `activity.json` / the connection history**.

Because it triggers only when the NAT source port lands above 32767, it hits **roughly half**
of all real players at random — the "regular players often show no IP and I don't get notified"
report. One player showing an IP next to one showing `-`, same snapshot, is the tell.

**The fix:** `\d+` → `-?\d+` on the port in all **six** validation sites, in lockstep
(`tools/rcon/server.js` `IP_PORT_RE`; `tools/notify/join-notify.js`; `tools/notify/join-notify.ps1`;
`tools/status_service/status_service.ps1` ×2; `tools/conn_logger/conn_logger.ps1`). IP extraction
is `split(':')[0]` everywhere, so the sign is discarded where the bare IP is actually used —
the port is only ever validated, never consumed. The two geo normalizers
(`server.js::geoNormIp`, `status_service.ps1` line ~293) strip the port *before* validating a
bare `^\d{1,3}(\.\d{1,3}){3}$`, so they were already immune — leave them.

⚠ RULE: any address-shape regex in a `status` consumer must allow a **negative** port. This is
the second column-parsing footgun in the same code, after the spaced-name one
([[status-parser-name-spaces-bot-miscount]]); the classifier-null cascade that turns a parse
miss into a real-player loss is the same failure family as
[[kick-all-bots-kicked-real-players]].

Deploy: these are **box-side** services (not the mod mirror) — the change reaches the VPS with
the tree, but the four scheduled tasks must be **restarted** to load it: `GF-RconPanel`
(server.js), `GF-StatusService` (status_service.ps1), `GF-JoinNotify` (join-notify), and
`GF-ConnLogger` (conn_logger.ps1). Related: [[gf-admin-connection-history]].
