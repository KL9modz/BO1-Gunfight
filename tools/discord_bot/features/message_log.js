'use strict';
/*
 * Message logging - deletes, edits, bulk purges, and the media that went with them.
 *
 * Enabled by setting `messageLogChannelId`. Unset = the feature is off and its intents are not
 * requested.
 *
 * ── ⚠ THIS FEATURE STORES WHAT PEOPLE WROTE, AND RE-PUBLISHES IT ───────────────────────────────
 * A deleted message can only be reported if its content was already held, so this keeps recent
 * message text in memory (lib/cache.js) and recent attachments as bytes (lib/attachments.js), and
 * reposts both into the log channel when something is removed. That is a deliberate, owner-made
 * decision on 2026-08-19, not a default: someone who deletes a message has decided they did not
 * want it seen, and this overrides that for the log channel's audience.
 *
 * Consequences to keep in view rather than discover later:
 *   - The log channel must be PRIVATE. It will contain things people deleted on purpose, including
 *     messages deleted immediately after posting by mistake.
 *   - The bot holds user uploads in memory for a few minutes. lib/attachments.js caps that.
 *   - Turning it off is one config key. There is no way to un-log what has already been posted.
 *
 * ── WHAT IT CAN AND CANNOT KNOW ────────────────────────────────────────────────────────────────
 * ⚠ MESSAGE_DELETE carries ONLY {id, channel_id, guild_id}. Everything else - who wrote it, what it
 * said - comes from our own cache, so a message posted before the bot started, or evicted since,
 * genuinely cannot be recovered. The card says so plainly instead of implying the message was empty.
 *
 * ⚠ The gateway never says WHO deleted a message. That is in the audit log
 * (GUILD_AUDIT_LOG_ENTRY_CREATE, action 72 MESSAGE_DELETE) and only when a MODERATOR did it -
 * self-deletes generate no audit entry at all. So the card posts immediately with what is known and
 * is EDITED IN PLACE if an actor turns up, the same instant-then-corrected model the voice log uses.
 * No entry therefore means "the author deleted it", which is the common case and needs no words.
 */

const { COLOR, card, clamp, chanChip, userTag, FIELD_MAX, plural } = require('../lib/brand.js');
const makeAttachments = require('../lib/attachments.js');

const { BITS } = require('../lib/intents.js');
const A_MESSAGE_DELETE = 72;
// How long after a delete an audit entry may still explain it. Discord batches these, so they can
// trail the gateway event by a second or two.
const ATTRIB_MS = 8000;
// Discord truncates a field at 1024. Content longer than that is clipped with a marker rather than
// silently cut, so nobody reads a partial message as the whole one.
const BODY_MAX = 900;

const preview = (text) => {
  const t = String(text || '');
  if (!t) return '';
  return t.length > BODY_MAX ? t.slice(0, BODY_MAX) + '\n… (truncated)' : t;
};

// ⚠ Content is quoted, never interpolated raw: a deleted message can contain backticks, @everyone
// or markdown that would otherwise reformat the card or ping the channel. The mention half is
// already covered by allowed_mentions in lib/rest.js; this covers the layout half.
const quote = (text) => preview(text).split('\n').map((l) => '> ' + l).join('\n');

module.exports = function messageLog(ctx) {
  const { cfg, log, rest, cache } = ctx;
  const channelId = cfg.messageLogChannelId;
  const enabled = Boolean(channelId);
  const withMedia = cfg.messageLogMedia !== false;

  const media = makeAttachments(log);
  // One lifetime for metadata and bytes: when the cache evicts a message, its buffered files go too.
  if (enabled && withMedia) cache.setEvictListener((id) => media.forget(id));

  // Channels never logged. ⚠ The log channel itself is ALWAYS excluded - without that, the bot's own
  // card is a message, deleting one would log the log, and a purge in there would recurse.
  const ignored = new Set([String(channelId), ...(cfg.messageLogIgnoreChannels || []).map(String)]);

  // messageId -> { cardId, at, authorId, channelId } for the ones we have posted and might correct
  const posted = new Map();
  let hints = [];
  let canAttribute = false;

  async function probeAuditAccess() {
    const r = await rest.probe(`/guilds/${cfg.guildId}/audit-logs?limit=1`);
    canAttribute = r.ok;
    log(canAttribute
      ? 'message log: audit access OK - moderator deletions will be attributed'
      : `message log: no audit access (HTTP ${r.status}) - deletions cannot name a moderator`);
  }

  function sweep() {
    const cutoff = Date.now() - ATTRIB_MS;
    for (const [id, p] of posted) if (p.at < cutoff) posted.delete(id);
    hints = hints.filter((h) => Date.now() - h.at < ATTRIB_MS && h.remaining > 0);
  }

  // An audit entry names the AUTHOR whose messages were removed and how many, never which ones. So
  // it is matched against what we just posted by author + channel, consuming one slot per card.
  async function applyHints() {
    if (!canAttribute) return;
    sweep();
    for (const [id, p] of posted) {
      if (p.actor) continue;
      const h = hints.find((x) => (!x.target || x.target === p.authorId)
        && (!x.channelId || x.channelId === p.channelId));
      if (!h) continue;
      h.remaining -= 1;
      p.actor = h.actor;
      try {
        await rest.editMessage(channelId, p.cardId, { embeds: [p.render(h.actor)] });
      } catch (e) { log('message log edit failed:', e.message); }
    }
  }

  async function onDelete(id, chanId) {
    if (ignored.has(String(chanId))) return;
    const known = cache.message.get(id);
    // ⚠ A bot's own message being deleted is noise - and ours especially, since the log channel is
    // full of them. The author is only knowable when the message was cached.
    if (known && known.authorBot) return;

    const files = withMedia ? await media.take(id) : [];
    cache.message.forget(id);

    const render = (actor) => {
      const details = [
        ['Author', known && known.authorId ? `${userTag(known.authorId)} (${known.authorTag || '?'})` : '_not cached_'],
        ['Channel', chanChip(chanId)],
      ];
      if (actor) details.push(['Deleted by', userTag(actor)]);
      if (known && known.attachments.length) {
        details.push(['Attachments', known.attachments
          .map((a) => `${a.filename} (${Math.round(a.size / 1024)}kB)`).join(', ')]);
      }
      // ⚠ Says WHY it has no content rather than showing an empty quote. "Not in the cache" and
      // "the message really was empty" are different facts and must not look the same.
      const body = known
        ? (known.content ? quote(known.content) : '_no text_')
        : '_posted before the bot started, or aged out of the cache_';
      return card({
        title: '🗑 Message deleted',
        color: COLOR.DANGER,
        description: clamp(body, FIELD_MAX),
        details,
      });
    };

    try {
      const payload = { embeds: [render(null)] };
      const msg = files.length
        ? await rest.postMessageWithFiles(channelId, payload, files)
        : await rest.postMessage(channelId, payload);
      posted.set(id, { cardId: msg.id, at: Date.now(), render,
                       authorId: known && known.authorId, channelId: chanId, actor: null });
      await applyHints();
    } catch (e) { log('message log post failed:', e.message); }
  }

  async function onEdit(d) {
    if (ignored.has(String(d.channel_id))) return;
    if (d.author && d.author.bot) return;
    // ⚠ MESSAGE_UPDATE also fires when Discord finishes unfurling a link preview, with no content
    // change at all. Without this the log fills with edits nobody made.
    if (typeof d.content !== 'string') return;
    const known = cache.message.get(d.id);
    const before = known ? known.content : null;
    if (before === d.content) return;
    cache.message.update(d.id, d.content);

    const link = `https://discord.com/channels/${cfg.guildId}/${d.channel_id}/${d.id}`;
    try {
      await rest.postMessage(channelId, { embeds: [card({
        title: '✏️ Message edited',
        url: link,
        color: COLOR.WARN,
        description: clamp(
          `**Before**\n${before === null ? '_not cached_' : (before ? quote(before) : '_no text_')}\n` +
          `**After**\n${d.content ? quote(d.content) : '_no text_'}`, FIELD_MAX),
        details: [
          ['Author', d.author ? `${userTag(d.author.id)} (${d.author.username})` : '_unknown_'],
          ['Channel', chanChip(d.channel_id)],
        ],
      })] });
    } catch (e) { log('message log edit-card failed:', e.message); }
  }

  async function onBulkDelete(d) {
    if (ignored.has(String(d.channel_id))) return;
    const ids = d.ids || [];
    // Summarised, not one card per message: a purge of 100 would otherwise be 100 posts, and the
    // interesting fact is that a purge happened and who was in it.
    const rows = ids.map((id) => cache.message.get(id)).filter(Boolean);
    const authors = [...new Set(rows.map((r) => r.authorId).filter(Boolean))];
    for (const id of ids) { media.forget(id); cache.message.forget(id); }
    try {
      await rest.postMessage(channelId, { embeds: [card({
        title: `🧹 Bulk delete: ${plural(ids.length, 'message')}`,
        color: COLOR.DANGER,
        details: [
          ['Channel', chanChip(d.channel_id)],
          ['Cached', `${rows.length} of ${ids.length}`],
          ['Authors', authors.length ? authors.map(userTag).join(' ') : '_none cached_'],
        ],
        footer: true,
      })] });
    } catch (e) { log('message log bulk failed:', e.message); }
  }

  return {
    name: 'message_log',
    enabled,
    // ⚠ MESSAGE_CONTENT is PRIVILEGED and must be enabled in the Developer Portal, or the gateway
    // closes with 4014 and every other feature dies with it. Requested only while this is on.
    // ⚠ GUILD_MODERATION delivers the audit entries that name a moderator who deleted someone
    // else's message. Missing it does not error - the "Deleted by" line simply never appears.
    intents: enabled ? (BITS.GUILD_MESSAGES | BITS.MESSAGE_CONTENT | BITS.GUILD_MODERATION) : 0,
    permissions: ['View Audit Log', 'Attach Files'],
    commands: {},

    on: {
      GUILD_CREATE: (d) => {
        if (d.id !== cfg.guildId) return;
        log(`message log ready: channel ${channelId}, media ${withMedia ? 'on' : 'off'}`);
        probeAuditAccess().catch((e) => log('message log: audit probe failed:', e.message));
      },

      // ⚠ The CORE already cached this message before we ran (bot.js dispatch order), so this only
      // has to deal with the bytes.
      MESSAGE_CREATE: (d) => {
        if (!withMedia) return;
        if (d.guild_id !== cfg.guildId) return;
        if (ignored.has(String(d.channel_id))) return;
        if (d.author && d.author.bot) return;
        media.remember(d.id, (d.attachments || []).map((a) => ({
          filename: a.filename, size: a.size, contentType: a.content_type || null, url: a.url,
        })));
      },

      MESSAGE_UPDATE: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        onEdit(d).catch((e) => log('message log edit failed:', e.message));
      },

      MESSAGE_DELETE: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        onDelete(d.id, d.channel_id).catch((e) => log('message log delete failed:', e.message));
      },

      MESSAGE_DELETE_BULK: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        onBulkDelete(d).catch((e) => log('message log bulk failed:', e.message));
      },

      GUILD_AUDIT_LOG_ENTRY_CREATE: (d) => {
        if (d.guild_id && d.guild_id !== cfg.guildId) return;
        if (d.action_type !== A_MESSAGE_DELETE) return;
        hints.push({
          actor: d.user_id,
          target: d.target_id || null,
          channelId: (d.options && d.options.channel_id) || null,
          remaining: Number((d.options && d.options.count) || 1) || 1,
          at: Date.now(),
        });
        applyHints().catch((e) => log('message log attribute failed:', e.message));
      },
    },
  };
};

module.exports.quote = quote;
module.exports.preview = preview;
