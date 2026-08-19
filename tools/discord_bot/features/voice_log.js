'use strict';
/*
 * Voice activity log - posts a line when anyone joins, leaves or moves between voice channels.
 *
 * Enabled by setting `voiceLogChannelId` in config.local.json. Unset = the whole feature is off and
 * its intent is not requested, which is the pattern every feature here follows (see bot.js: asking
 * for an intent you do not need is both a privilege grab and, if it is privileged and disabled in
 * the portal, a fatal 4014 on connect).
 *
 * ── WHY THERE IS A CACHE ───────────────────────────────────────────────────────────────────────
 * VOICE_STATE_UPDATE reports the state a user is now IN. It does not say where they came from, and
 * "left voice entirely" and "moved to another channel" arrive as the same event shape. So the
 * previous channel has to be remembered locally:
 *
 *     prev  now   meaning
 *     ----  ----  --------------------------------
 *     -     X     joined X
 *     X     -     left X
 *     X     Y     moved X -> Y
 *     X     X     mute/deaf/stream toggle - ignored, or every mute press becomes a log line
 *
 * The cache is seeded from GUILD_CREATE, which carries the guild's current voice_states, so a
 * restart does not report everyone already sitting in a channel as a fresh join.
 *
 * ── WHY THERE IS A QUEUE ───────────────────────────────────────────────────────────────────────
 * Voice events are bursty: a Discord call ending emits one per participant within the same second,
 * and someone with a flaky connection can rejoin repeatedly. Discord's REST limits are a handful of
 * requests per second, so one POST per event queues, then falls behind, then 429s. Lines are
 * therefore coalesced into one message per flush window - which also reads better than eight
 * near-identical lines.
 */

const FLUSH_MS = 2500;      // coalescing window
const MAX_LINES = 20;       // per message; beyond this the flush summarises the remainder
const GUILD_VOICE_STATES = 1 << 7;

module.exports = function voiceLog(ctx) {
  const { cfg, log, post } = ctx;
  const enabled = Boolean(cfg.voiceLogChannelId);

  // userId -> channelId they are currently in. Only ever holds users in a voice channel.
  const where = new Map();
  // channelId -> name, so a log line can say #General rather than a snowflake.
  const chanNames = new Map();
  let outbox = [];
  let timer = null;

  const nameOf = (d) => {
    const m = d.member || {};
    const u = m.user || {};
    return m.nick || u.global_name || u.username || `user ${d.user_id}`;
  };
  const chan = (id) => (id ? (chanNames.get(id) ? `**${chanNames.get(id)}**` : `<#${id}>`) : 'voice');

  function queue(line) {
    outbox.push(line);
    if (timer) return;
    timer = setTimeout(flush, FLUSH_MS);
  }

  async function flush() {
    timer = null;
    const lines = outbox.splice(0, outbox.length);
    if (!lines.length) return;
    let body = lines.slice(0, MAX_LINES).join('\n');
    if (lines.length > MAX_LINES) body += `\n…and ${lines.length - MAX_LINES} more`;
    try {
      await post(cfg.voiceLogChannelId, { content: body, allowed_mentions: { parse: [] } });
    } catch (e) {
      // Never throw out of a log feature: losing a log line must not take the bot down.
      log('voice log post failed:', e.message);
    }
  }

  return {
    name: 'voice_log',
    enabled,
    // Not privileged, so this needs no portal toggle - unlike GUILD_MEMBERS or MESSAGE_CONTENT.
    intents: enabled ? GUILD_VOICE_STATES : 0,

    onEvent(t, d) {
      if (!enabled) return;

      if (t === 'GUILD_CREATE') {
        if (d.id !== cfg.guildId) return;
        for (const c of (d.channels || [])) chanNames.set(c.id, c.name);
        // Seed WITHOUT logging: these people were already in voice before we connected, and
        // announcing them as joins on every restart is the classic cold-start false positive.
        let seeded = 0;
        for (const vs of (d.voice_states || [])) {
          if (vs.channel_id) { where.set(vs.user_id, vs.channel_id); seeded++; }
        }
        log(`voice log ready: ${chanNames.size} channels known, ${seeded} user(s) already in voice`);
        return;
      }

      if (t === 'CHANNEL_CREATE' || t === 'CHANNEL_UPDATE') { chanNames.set(d.id, d.name); return; }
      if (t === 'CHANNEL_DELETE') { chanNames.delete(d.id); return; }

      if (t !== 'VOICE_STATE_UPDATE' || d.guild_id !== cfg.guildId) return;

      const user = d.user_id;
      const now = d.channel_id || null;
      const prev = where.get(user) || null;

      // Bots (music players, soundboards) churn voice constantly and are not what "who is around"
      // is asking about. Opt in with voiceLogBots if you ever want them.
      const isBot = Boolean(d.member && d.member.user && d.member.user.bot);
      if (isBot && !cfg.voiceLogBots) {
        if (now) where.set(user, now); else where.delete(user);
        return;
      }

      if (now) where.set(user, now); else where.delete(user);

      if (prev === now) return;                                   // mute/deaf/stream toggle
      const who = nameOf(d);
      if (!prev && now)  queue(`🔊 **${who}** joined ${chan(now)}`);
      else if (prev && !now) queue(`👋 **${who}** left ${chan(prev)}`);
      else queue(`➡️ **${who}** moved ${chan(prev)} → ${chan(now)}`);
    },
  };
};
