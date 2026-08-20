'use strict';
/*
 * Shared, bounded state the gateway gives us once and never repeats.
 *
 * ── WHY THIS IS CORE AND NOT A FEATURE ─────────────────────────────────────────────────────────
 * The voice-state map started inside the voice log, which was fine while the voice log was the only
 * thing that wanted it. It is not: /moveall needs to know who is in a channel, and a bot with the
 * voice log switched OFF would then have had an empty map and a broken command. State that more
 * than one feature reads has to be maintained by the core, or it acquires a hidden dependency on
 * whichever feature happens to be enabled.
 *
 * bot.js calls observe() for every dispatch BEFORE handing the event to features, so the cache is
 * populated identically whatever is turned on.
 *
 * ── THE ORDERING TRAP ──────────────────────────────────────────────────────────────────────────
 * ⚠ VOICE_STATE_UPDATE reports the channel a user is now IN and never where they came from, so the
 * PREVIOUS channel exists only in this map - and only until the map is updated. If the core updated
 * the map first, every feature would read the new value and "moved from X" would be unrecoverable.
 *
 * transition() therefore MEMOISES its answer on the event object itself (a WeakMap, so nothing
 * leaks). The core calls it, the voice log calls it, and both get the same {prev, now} regardless
 * of order. That is what lets the core own the map without stealing the transition.
 */

const where = new Map();       // userId    -> channelId  (voice presence)
const names = new Map();       // channelId -> name
const seen = new WeakMap();    // VOICE_STATE_UPDATE event -> { prev, now }
// userId -> epoch ms until which OUR OWN moves should not be logged again. See suppress().
const quiet = new Map();

// Messages, for delete/edit logging. Bounded: an unbounded message cache on a long-running process
// is a memory leak with extra steps. Insertion order + shift() is O(1) enough at this size, and the
// cap is what makes the memory ceiling a number rather than a hope.
const MESSAGE_CAP = 2000;
const messages = new Map();    // messageId -> { channelId, authorId, content, at }

function transition(d) {
  if (seen.has(d)) return seen.get(d);
  const prev = where.get(d.user_id) || null;
  const now = d.channel_id || null;
  if (now) where.set(d.user_id, now); else where.delete(d.user_id);
  const r = { prev, now, changed: prev !== now };
  seen.set(d, r);
  return r;
}

function observe(t, d) {
  if (t === 'GUILD_CREATE') {
    // ⚠ Seeded WITHOUT announcing anything. A restart must not report everyone already sitting in
    // a voice channel as a fresh join, which is exactly what a naive rebuild would do.
    for (const c of (d.channels || [])) names.set(c.id, c.name);
    for (const vs of (d.voice_states || [])) if (vs.channel_id) where.set(vs.user_id, vs.channel_id);
    return;
  }
  if (t === 'CHANNEL_CREATE' || t === 'CHANNEL_UPDATE') { names.set(d.id, d.name); return; }
  if (t === 'CHANNEL_DELETE') { names.delete(d.id); return; }
  if (t === 'VOICE_STATE_UPDATE') { transition(d); return; }
  if (t === 'MESSAGE_CREATE') { remember(d); return; }
}

function remember(m) {
  if (!m || !m.id) return;
  // content may be '' when the MESSAGE_CONTENT intent is off; the row is still worth keeping for
  // author/channel attribution on a later delete.
  messages.set(m.id, {
    channelId: m.channel_id,
    authorId: (m.author && m.author.id) || null,
    authorTag: (m.author && (m.author.global_name || m.author.username)) || null,
    content: m.content || '',
    attachments: (m.attachments || []).length,
    at: Date.now(),
  });
  while (messages.size > MESSAGE_CAP) messages.delete(messages.keys().next().value);
}

const voice = {
  transition,

  /*
   * Mark a user's next voice change as ours.
   *
   * ⚠ WHY THIS IS NOT LOG SUPPRESSION IN GENERAL: when an admin runs /moveall, the bot issues one
   * REST call per member, Discord emits one VOICE_STATE_UPDATE per member, and the voice log would
   * faithfully report all of them - as separate messages, because the rest queue paces the moves
   * further apart than the log's burst window. That is DUPLICATE REPORTING of an action the
   * command already summarised in its own card, not an audit trail.
   *
   * Time-based rather than consume-on-read: one move can produce more than one event, and a
   * counter that guesses wrong strands the suppression forever. The cost of the window is that a
   * user who genuinely moves again within it loses one log line - cheap, and it self-heals.
   */
  suppress: (userIds, ms = 10000) => {
    const until = Date.now() + ms;
    for (const u of [].concat(userIds)) quiet.set(String(u), until);
  },
  suppressed: (userId) => {
    const until = quiet.get(String(userId));
    if (!until) return false;
    if (Date.now() > until) { quiet.delete(String(userId)); return false; }
    return true;
  },

  channelOf: (userId) => where.get(userId) || null,
  // A COPY: a caller iterating this while moving people would otherwise mutate what it is walking.
  membersOf: (channelId) => [...where.entries()].filter(([, c]) => c === channelId).map(([u]) => u),
  count: (channelId) => { let n = 0; for (const c of where.values()) if (c === channelId) n++; return n; },
  size: () => where.size,
};

const channels = {
  // ⚠ Falls back to 'voice' rather than to the id: an id in a card title reads as a bug, and the
  // name is only missing for a channel created before we connected or one we cannot see.
  name: (id, fallback = 'voice') => (id ? (names.get(id) || fallback) : fallback),
  known: () => names.size,
  // ⚠ Names only - this cache does NOT keep channel types, so it cannot answer "is that a
  // voice channel". /moveall validates by asking whether anyone is in it, and by letting Discord
  // reject the move otherwise.
  has: (id) => names.has(id),
};

const message = {
  get: (id) => messages.get(id) || null,
  forget: (id) => messages.delete(id),
  size: () => messages.size,
};

module.exports = { observe, voice, channels, message, MESSAGE_CAP };
