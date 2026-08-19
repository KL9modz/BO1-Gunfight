# Black Ops Bot — design + roadmap

What the bot does today, and what it takes to grow it into an all-in-one server bot (activity
logging, spam control, and the music question). Written 2026-08-19 after verifying the API details
against Discord's current docs, because three of them have changed or are commonly mis-remembered.

*Part of the [Black Ops Gunfight](../README.md) documentation. Ops runbooks: [VPS_DEPLOY](VPS_DEPLOY.md),
[VPS_HARDENING](VPS_HARDENING.md).*

---

## Today

`tools/discord_bot/bot.js`, run as **GF-DiscordBot** through `run_service.ps1`, watched by
`watchdog.ps1`. Zero npm dependencies: Node 24's native `WebSocket` + `fetch` cover the gateway.

| | |
|---|---|
| Commands | `/status` `/players` (open) · `/say` `/map` `/restart` `/pause` `/resume` (Admin role) |
| Relay | one configured channel → in-game broadcast (off until a channel is set) |
| Game access | **only** the panel's `/api/rcon` on loopback — the panel is the single rcon pacer |
| Intents | `GUILDS`, plus `GUILD_MESSAGES` + `MESSAGE_CONTENT` **only when a relay channel is set** |

⚠ **The four gates** (verb whitelist, role gate, guild/channel allowlist, sanitiser) are the security
model, not decoration — see the header of `bot.js`. Every feature below must pass through them too.

---

## The architecture change that comes first

`bot.js` is one file with a `COMMANDS` table and two event handlers. That is right for two features
and wrong for ten. Before adding anything, split it:

```
tools/discord_bot/
  bot.js            gateway (identify/heartbeat/resume/reconnect) + event router. No features.
  lib/rest.js       REST calls + the rate-limit queue (see below)
  lib/cache.js      bounded message + voice-state caches
  features/ops.js         the slash commands that exist today
  features/relay.js       Discord -> game
  features/audit.js       activity logging
  features/moderation.js  spam handling + AutoMod glue
  config.local.json  (gitignored)
```

Each feature module exports `{ name, intents, permissions, commands, on: { EVENT: handler } }`, and
`bot.js` unions the intents of the **enabled** modules. That preserves the property already earned
the hard way: **never request an intent a feature does not need**, because identifying with a
privileged intent that is not enabled in the portal closes the gateway with **4014**, which is fatal.

---

## 1. Activity logging (the "audit log" feature)

### What each event needs

| Want to log | Event | Intent | Privileged? |
|---|---|---|---|
| Voice join / leave / move / mute | `VOICE_STATE_UPDATE` | `GUILD_VOICE_STATES` | no |
| Message deleted | `MESSAGE_DELETE`, `MESSAGE_DELETE_BULK` | `GUILD_MESSAGES` (+ `MESSAGE_CONTENT` for content) | content: **yes** |
| Message edited | `MESSAGE_UPDATE` | same | same |
| Member joined / left | `GUILD_MEMBER_ADD` / `_REMOVE` | `GUILD_MEMBERS` | **yes** |
| Channels, roles, server settings | `CHANNEL_*`, `GUILD_ROLE_*`, `GUILD_UPDATE` | `GUILDS` (already have) | no |
| **Who** performed an action | `GUILD_AUDIT_LOG_ENTRY_CREATE` | none — needs **View Audit Log** permission | no |

### The two facts that shape the whole feature

⚠ **`MESSAGE_DELETE` does not include the message.** Verified against the current docs: the payload
is `{ id, channel_id, guild_id }` and nothing else. Discord does not hand you what was deleted. So a
"deleted message" log is only possible if **the bot cached the message when it was posted** — which
means:
- content logging starts when the bot starts; anything older is unrecoverable, and the log line must
  say so (`(not cached)`) rather than silently omitting the message;
- the cache is memory, bounded, and lossy by design — a ring of the last N messages per channel;
- `MESSAGE_DELETE_BULK` can drop hundreds at once, so the handler must summarise, not spam.

⚠ **Gateway events say WHAT changed, not WHO did it.** A deleted message looks identical whether the
author removed it or a moderator did. `GUILD_AUDIT_LOG_ENTRY_CREATE` carries the actor, and it needs
only the **View Audit Log** permission. Correlating the two (same target id, within a couple of
seconds) is what turns "a message was deleted" into "Bob deleted Alice's message" — and it is
inherently best-effort, because Discord does not emit an audit entry for a self-delete.

### Rate limits are the practical constraint

A busy server generates far more events than a log channel can absorb: Discord's REST limit is a
handful of requests per second, and posting one message per event will queue, then drop behind.
Every serious log bot batches. Do the same: a per-destination queue that coalesces events for ~2-5
seconds and posts one embed with several lines. This also makes the log readable.

### ⚠ Privacy — the part worth deciding before writing code

Message-content logging on a 621-member server means the bot persists, in a channel, things people
deliberately deleted. That is a bigger commitment than any feature so far, and it interacts with the
project's existing stance (player IPs and GUIDs are kept out of git, muting is honoured, the joins
channel is private). Decide up front:
- log channel **private to staff**, always;
- retention: prune log messages older than N days (the bot can delete its own messages);
- consider logging *metadata only* (who/where/when + length) for ordinary channels and content only
  where it is justified;
- never log DMs, and never log a channel the staff themselves would not want quoted back.

---

## 2. Spam filtering

### Use Discord's own AutoMod first

Discord ships server-side **Auto Moderation**, and it is strictly better than a bot loop for the
common cases: it blocks the message *before* it is posted, costs no process, and cannot be outrun by
a fast spammer. Verified capabilities:

| Trigger | What it catches | Limit per guild |
|---|---|---|
| `KEYWORD` | custom word/regex lists | 6 rules |
| `SPAM` | generic spam content | 1 |
| `KEYWORD_PRESET` | Discord's profanity / sexual-content / slur sets | 1 |
| `MENTION_SPAM` | too many unique mentions in one message | 1 |
| `MEMBER_PROFILE` | banned words in names/profiles | 1 |

Actions: **block message**, **send alert to a channel**, **timeout** (timeout only on `KEYWORD` and
`MENTION_SPAM`). Managing rules needs **Manage Server**; the timeout action needs **Moderate
Members**.

This mirrors the mod's own native-first rule: *does a stock system already express this?* For spam,
it does. The bot's job is then the part AutoMod cannot do:

- **subscribe to `AUTO_MODERATION_ACTION_EXECUTION`** (no intent, needs Manage Server) and write
  every hit into the activity log, so moderation is visible and reviewable;
- **cross-channel and cross-time patterns** AutoMod does not model: the same message posted in 5
  channels in 10 seconds, a brand-new account posting a link, join-then-immediately-post, repeated
  near-identical messages with small mutations;
- **escalation policy**: first hit = delete + warn, second = 10-minute timeout, third = kick, all
  logged with the reason. Discord's own timeout is the right primitive (`PATCH` member with
  `communication_disabled_until`), and it needs **Moderate Members**.

⚠ **Never auto-ban.** A false positive that bans a real player costs more than any spam wave, and
this bot already has enough power. Timeout is reversible; ban is a decision a human should make from
a log line the bot provided.

---

## 3. Music — the honest answer

**Do not run it on this box.** The research, so the "why" is concrete rather than a preference:

**What implementing voice actually requires** (verified against the current voice docs): a second
WebSocket (voice gateway), a **UDP** socket, IP discovery through that socket, RTP packetisation, and
encryption in **`aead_xchacha20_poly1305_rtpsize`** (mandatory to support) or
**`aead_aes256_gcm_rtpsize`** (preferred where available) — every older mode, including the
`xsalsa20_poly1305` family every old tutorial uses, was **discontinued on 2024-11-18**. Audio must be
Opus, 48 kHz, stereo, with silence frames on pause and a `Speaking` opcode before transmitting.

Node 24 can do AES-256-GCM natively, and Opus **passthrough** (demuxing an already-Opus WebM/Ogg
stream rather than encoding) avoids needing an encoder — so a zero-dependency implementation is
*technically* possible. It is still roughly an order of magnitude more code than everything in
`bot.js` today, and it is the part of Discord's API that changes most.

The decisive objections are not about difficulty:

1. **This box runs the game server.** It is 4 **shared** Contabo vCPUs with documented multi-second
   steal-time stalls (`GF_HITCH`, ~2,800 in 10 days, 15 of them mid-gameplay). A music stream is
   continuous CPU plus a continuous 64-128 kbps UDP flow on the same NIC as a latency-sensitive game
   server. Trading player experience for a jukebox is a bad trade on a server whose whole selling
   point is that it plays well.
2. **Sourcing.** Practically every music bot streams YouTube via `yt-dlp`, which is against YouTube's
   ToS and routinely gets IPs throttled or blocked. That IP is your game server's IP and its
   reputation is already load-bearing (FastDL, the site, the server browser).
3. **It is a solved commodity.** Hosted music bots exist and cost nothing to run.

**If you want it anyway**, in order of preference: (a) add an existing music bot to the guild and
keep BOB for things only BOB can do; (b) run a separate cheap VPS for a music bot, with no game
server on it; (c) build it here only if (a) and (b) are unacceptable, accepting the game-server cost.

---

## Suggested order

1. **Refactor to modules** — small, unblocks everything, no new permissions.
2. **Activity logging, metadata first**: voice join/leave, member join/leave, channel/role changes,
   plus `GUILD_AUDIT_LOG_ENTRY_CREATE` for the actor. Adds `GUILD_VOICE_STATES` + `GUILD_MEMBERS`
   (privileged — enable in the portal) and **View Audit Log**. Batched, private log channel.
3. **AutoMod glue**: create the SPAM / MENTION_SPAM / KEYWORD_PRESET rules, subscribe to
   `AUTO_MODERATION_ACTION_EXECUTION`, log every hit. Adds **Manage Server**.
4. **Message delete/edit logging** with the bounded cache — deliberately after (2) and (3), because it
   is the one that carries the privacy decision and needs `MESSAGE_CONTENT`.
5. **Custom spam heuristics + escalation** (timeout, never ban). Adds **Moderate Members**, and
   **Manage Messages** if the bot deletes offending messages itself.
6. **Music** — separately hosted, or not at all.

⚠ Add permissions and intents **one step at a time**, matching the step that needs them. The current
invite is deliberately minimal (View Channels, Send Messages, Embed Links, Read Message History, Use
Slash Commands); an Administrator tick would make every later audit meaningless.

## Sources

- [Gateway events and intents](https://docs.discord.com/developers/events/gateway-events)
- [Voice connections](https://docs.discord.com/developers/topics/voice-connections)
- [Auto Moderation](https://docs.discord.com/developers/resources/auto-moderation)
