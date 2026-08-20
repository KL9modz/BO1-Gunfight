# Black Ops Bot — design + roadmap

What the bot does today, and what it takes to grow it into an all-in-one server bot (activity
logging, spam control, and the music question). Written 2026-08-19 after verifying the API details
against Discord's current docs, because three of them have changed or are commonly mis-remembered.

*Part of the [Black Ops Gunfight](../README.md) documentation. Ops runbooks: [VPS_DEPLOY](VPS_DEPLOY.md),
[VPS_HARDENING](VPS_HARDENING.md).*

---

## Today

`tools/discord_bot/`, run as **GF-DiscordBot** through `run_service.ps1`, watched by `watchdog.ps1`.
Zero npm dependencies: Node 24's native `WebSocket` + `fetch` cover the gateway.

| | |
|---|---|
| Commands | `/status` `/players` (open) · `/say` `/map` `/restart` `/pause` `/resume` `/moveall` (Admin role) |
| Relay | one configured channel to in-game broadcast (off until a channel is set) |
| Voice log | joined / left / moved cards, with **who did it** from the audit log (off until a channel is set) |
| Message log | delete / edit / bulk-purge cards **with the content and the media** (off until a channel is set) |
| Member log | join / leave / rename cards, with an account-age flag (off until a channel is set) |
| Moderation | link + attachment filtering, strikes, escalation to timeout (off until a channel is set) |
| AutoMod | logs Discord's own AutoMod hits, `/automod` reports rules and gaps (off until a channel is set) |
| Presence | member-list line, "Watching 3 players on Nuketown", off `status.json` |
| Game access | **only** the panel's `/api/rcon` on loopback, the panel is the single rcon pacer |
| Intents | `GUILDS` + `GUILD_VOICE_STATES`, plus `GUILD_MESSAGES` + `MESSAGE_CONTENT` **only when a relay channel is set** |

⚠ **The four gates** (verb whitelist, role gate, guild/channel allowlist, sanitiser) are the security
model, not decoration. The first three now live in the ROUTER so a feature module cannot forget one;
the sanitiser lives in `lib/panel.js` beside the rcon call it guards.

---

## The architecture — DONE 2026-08-19

`bot.js` was one file with a `COMMANDS` table and two event handlers, which was right for two
features and wrong for ten. It is now a gateway client and an event router with no features in it:

```
tools/discord_bot/
  bot.js                  gateway (identify/heartbeat/resume/reconnect) + router + the security gates
  lib/config.js           load, BOM-tolerant parse, fatal-on-missing
  lib/rest.js             every REST call, through ONE queue that honours 429 / retry_after
  lib/cache.js            shared voice state + channel names + a BOUNDED message cache
  lib/brand.js            the house style: palette, card format, chips, caps
  lib/maps.js             BO1 map table (shared: /map today, the tournament picker next)
  lib/panel.js            the game bridge + the injection sanitiser
  features/ops.js         the slash commands
  features/relay.js       Discord -> game
  features/voice_tools.js /moveall
  features/voice_log.js   voice activity cards
  features/presence.js    member-list line
  config.local.json       (gitignored)
```

A feature is a factory taking `ctx` and returning
`{ name, enabled, intents, permissions, commands, on: { EVENT: handler } }`. `bot.js` unions the
intents and merges the command tables of the **enabled** modules only, which preserves the property
earned the hard way: **never request an intent a feature does not need**, because identifying with a
privileged intent that is not enabled in the portal closes the gateway with **4014**, which is fatal
for every other feature too. A duplicate command name refuses to start rather than silently letting
one module shadow another.

Three things worth knowing about the split:

- **`lib/cache.js` is CORE, not a feature.** The voice map used to live inside the voice log, so
  `/moveall` would have moved nobody on a bot with the log switched off. State two features read has
  to be owned by the core, or it acquires a hidden dependency on what happens to be enabled.
- ⚠ **The transition is memoised on the event object.** `VOICE_STATE_UPDATE` never says where a user
  came from, so the previous channel exists only in the map and only until the map updates. The core
  updates first; `transition(d)` returns the same `{prev, now}` to whoever asks, in any order.
- **`lib/rest.js` honours rate limits.** Before it, each caller ran a bare `fetch` and a 429 simply
  threw, losing the write. It now waits `retry_after`, tracks the separate GLOBAL pause, retries 5xx,
  and throws immediately on a 4xx that is our own bug. `allowed_mentions parse:[]` is applied
  centrally so a feature cannot forget it and start pinging people.

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

### ⚠ Privacy — DECIDED 2026-08-19: log content and media

The owner's call, made explicitly: deleted and edited messages **and their attachments** are logged
in full. What that commits to, recorded here so it is never a surprise:

- The log channel holds things people deleted **on purpose**, including messages deleted seconds
  after posting by mistake. It must be **private to staff**, always.
- Media can only be logged by **buffering it while the message is alive** - a deleted message's CDN
  link is signed and expiring, and refreshing it needs the message to still exist. So the box holds
  a copy of anything anyone uploads, briefly. `lib/attachments.js` caps that: **8MB per file, 64MB
  total, 15 minute TTL, memory only**. Nothing is written to disk, so a crash cannot leave a pile of
  other people's files on the game server, and nothing survives a restart.
- An oversized file is **not** downloaded, but its metadata still appears on the card, so "a 40MB
  video was deleted" is reported rather than silently omitted.
- ⚠ There is no un-logging. Turning the feature off stops new cards; it does not retract old ones.

Not implemented, and deliberately left as later choices rather than assumed: **retention pruning**
(the bot could delete its own cards after N days) and **per-channel content policy** (metadata-only
for ordinary channels). `messageLogIgnoreChannels` covers the blunt version of the second today.
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

- **subscribe to `AUTO_MODERATION_ACTION_EXECUTION`** and write every hit into the log, so
  moderation is visible and reviewable. ⚠ **CORRECTED 2026-08-19: this DOES need an intent** -
  `AUTO_MODERATION_EXECUTION` (`1 << 21`). The earlier "no intent" note here was wrong in the
  expensive way: the events simply never arrive and the feature looks perfectly healthy. The intent
  is **not privileged**, so it needs no portal toggle and cannot cause a 4014; the **Manage Server**
  permission is a separate requirement, and without it the rules cannot even be listed;
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

## Scope, decided 2026-08-19

The owner's feature list, and the two structural calls made while scoping it.

**ONE bot, not two, and not Red-DiscordBot.** Red was considered seriously and rejected on the
evidence of the actual list: Red's value is the commodity engagement pack (levels, welcome cards,
giveaways, reaction roles) and **none of that is on it**. What is on it is either already built,
BOB-only by nature (rcon), or bespoke in any stack (tournaments). Against ~one cheap win it would
have added a Python runtime, a second bot user, and third-party code on the game box. Two items are
actively better owned: **branding**, because Red's command UX carries Red's look, and **tournaments**,
which is the same amount of code in either language. The zero-dep gateway/REST/router machinery is
written and tested; the marginal cost per feature from here is low.

**Music: skipped.** Not "later" - decided. The research below stands, and the conclusion the owner
took is that a jukebox is not worth CPU and UDP on the box running the game server. If it is ever
wanted, add a hosted third-party bot to the guild.

⚠ Two honest limits of staying zero-dep, so nobody is surprised at step 7: bracket **images** and
content-aware media scanning are out of scope. Brackets render as embeds (which read well up to 16
players), the wheel spin is an edit-animation with a branded reveal rather than a GIF, and media
moderation means rules on type/size/extension/channel, not "is this image NSFW" - that last one is
an external API call if it is ever wanted.

## Build order

1. **Module refactor + `lib/brand.js`** — DONE 2026-08-19. Everything below inherits the shape and
   the house style, so features written months apart still match.
2. **Bulk move** — DONE. `/moveall from to`, the first feature built on the new shape and the proof
   it works. Needs **Move Members**. Its own moves are suppressed in the voice log, because the
   command already summarises them and one card per member is duplicate reporting.
3. **Logging family** — DONE 2026-08-19. `features/message_log.js` (delete, edit, bulk purge, media
   re-upload, moderator attribution from `GUILD_AUDIT_LOG_ENTRY_CREATE` action 72) and
   `features/member_log.js` (join, leave, nickname and display-name changes, account-age flag).
   ⚠ Needs **MESSAGE CONTENT** and **SERVER MEMBERS** enabled in the portal, plus **Attach Files**
   and **View Audit Log**. Each feature requests its intent only while it has a channel to post to.
   Channel and role change logging is NOT included yet.
4. **Link and media moderation** — DONE 2026-08-19. `features/moderation.js` owns what AutoMod
   cannot express: attachment type and size (AutoMod has **no** attachment condition at all),
   account age ("a three-hour-old account may not post links", checked BEFORE the domain lists so an
   allow-listed host cannot smuggle one past), and escalation with memory (strikes in a window then
   a timeout). `features/automod.js` logs Discord's native hits and `/automod` reports which rules
   exist and which recommended ones are missing. ⚠ It **reports and never edits** - rule changes
   belong in Server Settings where an owner can see what they do.
   ⚠ The ladder stops at **timeout**, structurally: a test fails if anything here ever reaches for a
   ban or a kick. Adds **Manage Server**, **Manage Messages**, **Moderate Members**.
5. **Security** — join-rate raid alarm, account-age flag on the join card, and alerts on the audit
   events that actually matter (role and permission changes, webhook creation, mass delete).
6. **Stats and leaderboards** — `/stats`, `/leaderboard`, rank cards from the existing `GF_STAT`
   pipeline joined to the GUID link table. No new permissions; it reads files the box already writes.
7. **Tournaments** — the big bespoke one, worth its own design pass: register button to roster,
   seeded single-elimination bracket as embeds, wheel-spin map picker (on `lib/maps.js`), team
   randomiser honouring the registered roster. Buttons and modals, state in a gitignored file.

Then the AI pair the owner scoped: a **Q&A helper** answering from the project's own docs, and
**agentic admin** (natural language mapped ONLY to the existing whitelisted verbs, never free rcon).
Both need an Anthropic API key in the bot's own config. ⚠ The box's Claude Max login cannot back a
bot, and `ANTHROPIC_API_KEY` must never be set globally on this box - it would silently take
precedence over the subscription for `GF-ClaudeRC` too.

⚠ Add permissions and intents **one step at a time**, matching the step that needs them. The invite
stays minimal (View Channels, Send Messages, Embed Links, Read Message History, Use Slash Commands,
plus Move Members from step 2); an Administrator tick would make every later audit meaningless.

## Sources

- [Gateway events and intents](https://docs.discord.com/developers/events/gateway-events)
- [Voice connections](https://docs.discord.com/developers/topics/voice-connections)
- [Auto Moderation](https://docs.discord.com/developers/resources/auto-moderation)
