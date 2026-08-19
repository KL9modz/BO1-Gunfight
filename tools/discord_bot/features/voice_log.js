'use strict';
/*
 * Voice activity log - who joined, left, moved, and WHO DID IT when a moderator moved or
 * disconnected someone.
 *
 * Enabled by setting `voiceLogChannelId`. Unset = the feature is off and its intent is not
 * requested (see bot.js: never ask for an intent a disabled feature would use).
 *
 * ── POSTING MODEL: INSTANT, THEN CORRECTED IN PLACE ────────────────────────────────────────────
 * The first event of a burst posts IMMEDIATELY - no waiting. Later events in the same burst are
 * appended to that same message as further CARDS, and when an audit entry reveals that a moderator
 * caused one of those changes, that card is rewritten in place. So:
 *
 *     t+0.0s   👋 KL9 ➔ Left: General
 *     t+0.9s   ⛔ KL9 ➔ Disconnected: General     + a **By:** line   (same message, edited)
 *
 * The alternative designs were both worse. A coalescing delay (the first cut used 2.5s) makes every
 * line late to buy attribution that usually arrives in under a second. Splitting instant lines and
 * attributed lines across two channels splits the ONE case anyone cares about across two places, so
 * you would read "KL9 left" in one and "disconnected by X" in the other and correlate by hand.
 *
 * ⚠ Edits do not re-notify. That is deliberate: the notification fires on the instant card, and the
 * correction arrives quietly.
 *
 * Bursts also keep the request count sane: a call ending emits one event per participant within the
 * same second, and Discord's REST budget is a few requests per second. One message plus a couple of
 * edits beats eight posts.
 *
 * ── WHY THERE IS A CACHE ───────────────────────────────────────────────────────────────────────
 * VOICE_STATE_UPDATE reports the state a user is now IN, never where they came from, and "left" and
 * "moved" arrive as the same event shape:
 *     -/X joined X   X/- left X   X/Y moved X->Y   X/X mute or stream toggle (ignored)
 * Seeded from GUILD_CREATE's voice_states WITHOUT logging, so a restart does not announce everyone
 * already in a channel as a fresh join.
 *
 * ── WHY THERE IS AN AUDIT CORRELATION ──────────────────────────────────────────────────────────
 * ⚠ A gateway event says WHAT changed, never WHO changed it. The actor exists only in the audit log
 * (GUILD_AUDIT_LOG_ENTRY_CREATE, 26 MEMBER_MOVE / 27 MEMBER_DISCONNECT), which needs VIEW AUDIT LOG
 * and no intent. Those entries are AGGREGATE - actor, a count, and for a move the destination - and
 * may not name each user, because one drag can move eight people. So an entry credits up to `count`
 * matching changes to that actor, consuming a slot per match, within ATTRIB_MS.
 *
 * ⚠ Without the permission, a **By:** line can never appear - so the module PROBES at startup and
 * says which mode it is in IN THE SERVICE LOG, not in the channel. The card is the same either way:
 * a plain "Left"/"Moved" already reads as the self case, and only gains an actor when one is
 * proven. A missing permission therefore costs detail, never accuracy.
 */

// ⚠ These two decide whether a line is INSTANT or merely fast, so they are not arbitrary.
// BURST_GAP_MS is measured from the PREVIOUS EVENT, not from the start of the message: an event a
// few seconds after the last one is a separate happening and must get its own message, posted
// immediately, which also means it NOTIFIES. Appending is only for events landing on top of each
// other - a call emptying, a mass move - where eight posts would hit the rate limit and eight
// notifications would be worse than one.
const APPEND_MS    = 400;    // debounce for appending within a burst
const BURST_GAP_MS = 1500;   // quiet longer than this and the next event starts a fresh message
const ATTRIB_MS  = 8000;   // how long an audit entry may explain a state change
// ⚠ Was 15 when a burst was 15 TEXT LINES. A burst is now one embed per event, and Discord caps a
// message at TEN embeds - exceeding it is a rejected request, not a truncation. A protocol limit.
const MAX_CARDS  = 10;     // per message, then start a new one
const GUILD_VOICE_STATES = 1 << 7;
const A_MEMBER_MOVE = 26, A_MEMBER_DISCONNECT = 27;

// Sapphire's own label. Field NAMES render markdown, so the underscores underline it (the bold is
// the field-name default). ONE field holds the whole detail block, which is what makes the card
// read as a labelled list instead of a wall of text.
const DETAILS = '__Details__';
// Discord's hard caps. A card that exceeds either is rejected outright, so a hostile display name
// gets clamped rather than trusted.
const TITLE_MAX = 256, FIELD_MAX = 1024;
// The stripe carries the severity the title cannot: a self-leave and a moderator disconnect are
// nearly the same sentence, and the colour is what separates them at a glance.
const C_JOIN = 0x57F287, C_LEFT = 0x99AAB5, C_KICK = 0xED4245, C_MOVE = 0x5865F2, C_MOVED_BY = 0xFEE75C;

const clamp = (t, n) => (t.length > n ? t.slice(0, n - 1) + '…' : t);
// <@id> / <#id> render as chips and cannot ping: every write also sets allowed_mentions parse:[].
const userTag = (id) => `<@${id}>`;
const chanChip = (id) => (id ? `<#${id}>` : 'voice');
// ⚠ AN EMBED TITLE IS PLAIN TEXT - it renders no mention and no channel chip, it would print a raw
// <#123>. So the title takes the channel NAME and only the field gets chips. That split is the
// whole reason this module keeps a channel-name cache.
const chanName = (names, id) => (id ? (names.get(id) || 'voice') : 'voice');

// ── THE CARD ───────────────────────────────────────────────────────────────────────────────────
// Module-level and PURE (all state arrives as arguments) so the rendering can be tested without a
// gateway, a token or a live guild - see tools/tests/discord_bot.test.js.
//
// ⚠ WHY AN EMBED AND NOT `content`: a mobile push shows `content` VERBATIM when it is present, and
// only falls back to flattening the embed TITLE + DESCRIPTION when it is absent. The old plain-text
// lines therefore pushed their own markup ("🔊 **KL9** joined **Gunfight**") to the lock screen. A
// card with a title, NO description, and its detail in FIELDS pushes exactly the title - a field
// never reaches the push. Same finding the join card is built on (tools/ntfy.ps1 Send-GfDiscord).
function buildCard(ev, names) {
  const title = (() => {
    if (ev.kind === 'joined') return `🔊 ${ev.who} ➔ Joined: ${chanName(names, ev.now)}`;
    if (ev.kind === 'left') {
      return ev.actor
        ? `⛔ ${ev.who} ➔ Disconnected: ${chanName(names, ev.prev)}`
        : `👋 ${ev.who} ➔ Left: ${chanName(names, ev.prev)}`;
    }
    return `${ev.actor ? '↔️' : '➡️'} ${ev.who} ➔ Moved: ${chanName(names, ev.prev)} → ${chanName(names, ev.now)}`;
  })();

  const count = (typeof ev.count === 'number' ? ` (${ev.count})` : '');
  const lines = [`**User:** ${userTag(ev.user)}${ev.username ? ` (${ev.username})` : ''}`];
  if (ev.kind === 'moved') {
    lines.push(`**From:** ${chanChip(ev.prev)}`);
    lines.push(`**To:** ${chanChip(ev.now)}${count}`);
  } else {
    lines.push(`**Channel:** ${chanChip(ev.kind === 'left' ? ev.prev : ev.now)}${count}`);
  }
  // ⚠ Only ever added when an actor is PROVEN. Its absence covers the self case AND the quiet-actor
  // case deliberately: withholding who did it must never become a claim that nobody did.
  if (ev.actor) lines.push(`**By:** ${userTag(ev.actor)}`);

  const card = {
    title: clamp(title, TITLE_MAX),
    color: ev.kind === 'joined' ? C_JOIN
         : ev.kind === 'left'   ? (ev.actor ? C_KICK : C_LEFT)
         :                        (ev.actor ? C_MOVED_BY : C_MOVE),
    fields: [{ name: DETAILS, value: clamp(lines.join('\n'), FIELD_MAX) }],
    timestamp: new Date(ev.at).toISOString(),
  };
  // The avatar is what makes this read as Sapphire's card rather than a bare embed. Absent on a
  // default-avatar account, so it is optional and never assumed.
  if (ev.avatar) card.thumbnail = { url: ev.avatar };
  return card;
}

module.exports = voiceLog;
// Exported for the tests: the card shape is the contract with Discord, and it is worth pinning
// without standing up a gateway.
module.exports.buildCard = buildCard;

function voiceLog(ctx) {
  const { cfg, log, post, patch, api } = ctx;
  const enabled = Boolean(cfg.voiceLogChannelId);

  const where = new Map();        // userId -> channelId
  const chanNames = new Map();    // channelId -> name
  let hints = [];                 // recent audit entries awaiting a match
  let canAttribute = false;

  // ── quiet actors ─────────────────────────────────────────────────────────────────────────────
  // Discord ids whose ACTIONS are never named. The event is still logged - "matzues ➔ Left" still
  // appears - only the **By:** half is withheld. Intended for the owner, whose routine moderation
  // is noise rather than news, and reused by later features that log actions.
  // ⚠ A quiet actor's hint is still CONSUMED. Skipping the claim would leave the slot free for the
  // next unattributed line in the window and blame the wrong person for it.
  // ⚠ And a suppressed line must NOT fall through to "(themselves)": we are hiding who did it, not
  // asserting nobody did. Saying less is fine; saying something untrue is not.
  const quiet = new Set((cfg.quietActorIds || []).map(String));

  // The open message: { id, events[], dirty, timer, at }
  let burst = null;

  const nameOf = (d) => {
    const m = d.member || {}, u = m.user || {};
    return m.nick || u.global_name || u.username || `user ${d.user_id}`;
  };
  const cardOf = (ev) => buildCard(ev, chanNames);
  // Who is in a voice channel RIGHT NOW, off the same cache the join/leave logic runs on.
  const inChannel = (id) => { let n = 0; for (const c of where.values()) if (c === id) n++; return n; };

  async function probeAuditAccess() {
    try {
      const r = await api(`/guilds/${cfg.guildId}/audit-logs?limit=1`);
      canAttribute = r.ok;
      log(canAttribute
        ? 'voice log: audit access OK - moderator moves/disconnects will be attributed'
        : `voice log: no audit access (HTTP ${r.status}) - grant View Audit Log to name who moved or disconnected someone`);
    } catch (e) { log('voice log: audit probe failed:', e.message); }
  }

  function addHint(entry) {
    hints.push({
      actor: entry.user_id,
      type: entry.action_type,
      target: entry.target_id || null,
      channelId: (entry.options && entry.options.channel_id) || null,
      remaining: Number((entry.options && entry.options.count) || 1) || 1,
      at: Date.now(),
    });
    hints = hints.filter((h) => Date.now() - h.at < ATTRIB_MS);
    // A hint can arrive AFTER its line was already posted - that is the whole point of editing.
    applyHints();
  }

  // Try to attribute any still-unattributed event in the open message.
  function applyHints() {
    if (!burst || !canAttribute) return;
    let changed = false;
    const now = Date.now();
    hints = hints.filter((h) => now - h.at < ATTRIB_MS && h.remaining > 0);
    for (const ev of burst.events) {
      if (ev.actor || ev.byQuietActor || ev.kind === 'joined') continue;
      if (now - ev.at > ATTRIB_MS) continue;
      const want = ev.kind === 'left' ? A_MEMBER_DISCONNECT : A_MEMBER_MOVE;
      const h = hints.find((x) => x.type === want
        && (!x.target || x.target === ev.user)
        && (want === A_MEMBER_DISCONNECT || !x.channelId || x.channelId === ev.now));
      if (!h) continue;
      h.remaining -= 1;
      if (quiet.has(String(h.actor))) {
        // Claimed, so the slot cannot blame someone else - but rendered without the actor, and
        // flagged so it does not claim the user did it to themselves either.
        ev.actor = null;
        ev.byQuietActor = true;
      } else {
        ev.actor = h.actor;
      }
      changed = true;
    }
    if (changed) schedule();
  }

  // One card per event. The wording IS the self case - no "(themselves)" tag; a card says what
  // happened and only gains a **By:** line if an audit entry proves someone else caused it (and
  // that actor is not quiet). So the text never depends on whether we can read the audit log: a
  // missing permission degrades to "less detail", never to "different sentences".
  const cardsOf = (b) => b.events.map(cardOf);
  // Signature for the "did anything actually change?" test. Cards are rebuilt from scratch on every
  // pass, so identity is worthless and the VALUE is what has to be compared.
  const sigOf = (b) => JSON.stringify(cardsOf(b));

  function schedule() {
    if (!burst || burst.timer) return;
    burst.timer = setTimeout(() => { burst.timer = null; writeBurst(); }, APPEND_MS);
  }

  async function writeBurst() {
    const b = burst;
    if (!b || !b.id) return;
    const embeds = cardsOf(b);
    const sig = JSON.stringify(embeds);
    if (sig === b.written) return;
    b.written = sig;
    try {
      await patch(cfg.voiceLogChannelId, b.id, { embeds, allowed_mentions: { parse: [] } });
    } catch (e) { log('voice log edit failed:', e.message); }
  }

  async function emit(ev) {
    const now = Date.now();
    // burst.at is the time of the LAST event in it, so this is a gap test, not an age test.
    const stale = burst && (now - burst.at > BURST_GAP_MS || burst.events.length >= MAX_CARDS);
    if (stale) burst = null;

    if (burst) {
      burst.events.push(ev);
      burst.at = now;
      applyHints();
      schedule();
      return;
    }

    // First card of a burst: post it straight away, no debounce. This is the latency that matters.
    burst = { id: null, events: [ev], at: now, timer: null, written: null };
    const b = burst;
    try {
      const first = cardsOf(b);
      const msg = await post(cfg.voiceLogChannelId, { embeds: first, allowed_mentions: { parse: [] } });
      b.written = JSON.stringify(first);
      b.id = msg.id;
      // Events and hints can land while the POST is in flight; flush anything that accumulated.
      if (sigOf(b) !== b.written) schedule();
    } catch (e) {
      log('voice log post failed:', e.message);
      if (burst === b) burst = null;      // do not strand later lines against a message that never existed
    }
  }

  return {
    name: 'voice_log',
    enabled,
    intents: enabled ? GUILD_VOICE_STATES : 0,

    onEvent(t, d) {
      if (!enabled) return;

      if (t === 'GUILD_CREATE') {
        if (d.id !== cfg.guildId) return;
        for (const c of (d.channels || [])) chanNames.set(c.id, c.name);
        let seeded = 0;
        for (const vs of (d.voice_states || [])) if (vs.channel_id) { where.set(vs.user_id, vs.channel_id); seeded++; }
        log(`voice log ready: ${chanNames.size} channels known, ${seeded} user(s) already in voice`);
        probeAuditAccess();
        return;
      }
      if (t === 'CHANNEL_CREATE' || t === 'CHANNEL_UPDATE') { chanNames.set(d.id, d.name); return; }
      if (t === 'CHANNEL_DELETE') { chanNames.delete(d.id); return; }

      if (t === 'GUILD_AUDIT_LOG_ENTRY_CREATE') {
        if (d.guild_id && d.guild_id !== cfg.guildId) return;
        if (d.action_type === A_MEMBER_MOVE || d.action_type === A_MEMBER_DISCONNECT) addHint(d);
        return;
      }

      if (t !== 'VOICE_STATE_UPDATE' || d.guild_id !== cfg.guildId) return;

      const user = d.user_id;
      const now = d.channel_id || null;
      const prev = where.get(user) || null;

      const isBot = Boolean(d.member && d.member.user && d.member.user.bot);
      if (isBot && !cfg.voiceLogBots) { if (now) where.set(user, now); else where.delete(user); return; }

      if (now) where.set(user, now); else where.delete(user);
      if (prev === now) return;

      const who = nameOf(d);
      const kind = !prev && now ? 'joined' : (prev && !now ? 'left' : 'moved');
      const u = (d.member && d.member.user) || {};
      // ⚠ The channel count is snapshotted HERE, not at render time. A card describes a moment, and
      // every edit in the burst re-renders it - by which point the channel has moved on. `where` is
      // already updated above, so a join counts the joiner and a leave does not.
      const count = inChannel(kind === 'left' ? prev : now);
      const avatar = u.avatar ? `https://cdn.discordapp.com/avatars/${user}/${u.avatar}.png?size=128` : null;
      emit({ kind, who, username: u.username || '', avatar, count, user, prev, now, at: Date.now(), actor: null })
        .catch((e) => log('voice log emit failed:', e.message));
    },
  };
}
