'use strict';
/*
 * Voice activity log - who joined, left, moved, and WHO DID IT when a moderator moved or
 * disconnected someone.
 *
 * Enabled by setting `voiceLogChannelId` in config.local.json. Unset = the feature is off and its
 * intent is not requested (see bot.js: never ask for an intent a disabled feature would use).
 *
 * ── WHY THERE IS A CACHE ───────────────────────────────────────────────────────────────────────
 * VOICE_STATE_UPDATE reports the state a user is now IN. It never says where they came from, and
 * "left voice" and "moved channel" arrive as the same event shape. So the previous channel is
 * remembered locally and diffed:
 *
 *     prev  now   meaning
 *     ----  ----  --------------------------------
 *     -     X     joined X
 *     X     -     left X
 *     X     Y     moved X -> Y
 *     X     X     mute/deaf/stream toggle - ignored, or every mute press is a log line
 *
 * Seeded from GUILD_CREATE's voice_states WITHOUT logging, so a restart does not announce everyone
 * already sitting in a channel as a fresh join.
 *
 * ── WHY THERE IS AN AUDIT CORRELATION ──────────────────────────────────────────────────────────
 * ⚠ A gateway event says WHAT changed, never WHO changed it. A user who left and a user a moderator
 * disconnected produce byte-identical VOICE_STATE_UPDATEs. The actor only exists in the audit log
 * (GUILD_AUDIT_LOG_ENTRY_CREATE, action 26 MEMBER_MOVE / 27 MEMBER_DISCONNECT), which needs the
 * VIEW AUDIT LOG permission and no intent.
 *
 * Those entries are also AGGREGATE: they carry the actor, a `count`, and (for a move) the
 * destination `channel_id` - and may not name each affected user, because one drag can move eight
 * people. So attribution is by correlation inside a short window: an entry credits up to `count`
 * matching state changes to that actor, consuming one per match. Exact when `target_id` is present,
 * best-effort when it is not, and never a guess older than ATTRIB_MS.
 *
 * ⚠ WITHOUT the permission this cannot distinguish the two cases at all - so the module PROBES for
 * it at startup and changes its wording rather than lying. With access: "left" vs "was disconnected
 * by X". Without: a neutral "left", which is true either way. Silently reporting a moderator
 * disconnect as a self-action would be worse than saying less.
 */

const FLUSH_MS   = 2500;   // coalescing window for the log message
const ATTRIB_MS  = 8000;   // how long an audit entry may explain a state change
const MAX_LINES  = 20;
const GUILD_VOICE_STATES = 1 << 7;
const A_MEMBER_MOVE = 26, A_MEMBER_DISCONNECT = 27;

module.exports = function voiceLog(ctx) {
  const { cfg, log, post, api } = ctx;
  const enabled = Boolean(cfg.voiceLogChannelId);

  const where = new Map();        // userId  -> channelId they are in
  const chanNames = new Map();    // channelId -> name
  let hints = [];                 // recent audit entries awaiting a match
  let pending = [];               // state changes awaiting flush
  let timer = null;
  let canAttribute = false;       // set by the startup probe

  const nameOf = (d) => {
    const m = d.member || {}, u = m.user || {};
    return m.nick || u.global_name || u.username || `user ${d.user_id}`;
  };
  const chan = (id) => (id ? (chanNames.get(id) ? `**${chanNames.get(id)}**` : `<#${id}>`) : 'voice');
  // <@id> renders as the member's name. It cannot ping: every post sets allowed_mentions parse:[].
  const actorTag = (id) => `<@${id}>`;

  // ── capability probe ─────────────────────────────────────────────────────────────────────────
  // One REST call at startup. 403 here is not an error to retry - it is a fact about what this log
  // is able to say, and the wording depends on it.
  async function probeAuditAccess() {
    try {
      const r = await api(`/guilds/${cfg.guildId}/audit-logs?limit=1`);
      canAttribute = r.ok;
      log(canAttribute
        ? 'voice log: audit access OK - moderator moves/disconnects will be attributed'
        : `voice log: no audit access (HTTP ${r.status}) - grant View Audit Log to name who moved or disconnected someone`);
    } catch (e) {
      log('voice log: audit probe failed:', e.message);
    }
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
  }

  // Find an audit entry that explains this change, and consume one of its slots.
  function claim(ev) {
    const now = Date.now();
    hints = hints.filter((h) => now - h.at < ATTRIB_MS && h.remaining > 0);
    const want = ev.kind === 'left' ? A_MEMBER_DISCONNECT : A_MEMBER_MOVE;
    const h = hints.find((x) => x.type === want
      && (!x.target || x.target === ev.user)                       // exact when Discord names the target
      && (want === A_MEMBER_DISCONNECT || !x.channelId || x.channelId === ev.now));
    if (!h) return null;
    h.remaining -= 1;
    return h.actor;
  }

  function queue(ev) {
    pending.push(ev);
    if (!timer) timer = setTimeout(flush, FLUSH_MS);
  }

  function render(ev) {
    const actor = canAttribute ? claim(ev) : null;
    const self = canAttribute && !actor;     // only assertable when we can see the audit log
    if (ev.kind === 'joined') return `🔊 **${ev.who}** joined ${chan(ev.now)}`;
    if (ev.kind === 'left') {
      if (actor) return `⛔ **${ev.who}** was disconnected from ${chan(ev.prev)} by ${actorTag(actor)}`;
      return `👋 **${ev.who}** left ${chan(ev.prev)}${self ? ' (themselves)' : ''}`;
    }
    if (actor) return `↔️ **${ev.who}** was moved ${chan(ev.prev)} → ${chan(ev.now)} by ${actorTag(actor)}`;
    return `➡️ **${ev.who}** moved ${chan(ev.prev)} → ${chan(ev.now)}${self ? ' (themselves)' : ''}`;
  }

  async function flush() {
    timer = null;
    const evs = pending.splice(0, pending.length);
    if (!evs.length) return;
    const lines = evs.map(render);
    let body = lines.slice(0, MAX_LINES).join('\n');
    if (lines.length > MAX_LINES) body += `\n…and ${lines.length - MAX_LINES} more`;
    try {
      await post(cfg.voiceLogChannelId, { content: body, allowed_mentions: { parse: [] } });
    } catch (e) {
      // A log feature must never take the bot down over a failed post.
      log('voice log post failed:', e.message);
    }
  }

  return {
    name: 'voice_log',
    enabled,
    intents: enabled ? GUILD_VOICE_STATES : 0,   // not privileged: no portal toggle needed

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

      // Audit entries can arrive slightly BEFORE or after the voice event, which is why hints are
      // kept in a window instead of being matched on arrival.
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
      if (prev === now) return;                       // mute/deaf/stream toggle

      const who = nameOf(d);
      if (!prev && now) queue({ kind: 'joined', who, user, prev, now });
      else if (prev && !now) queue({ kind: 'left', who, user, prev, now });
      else queue({ kind: 'moved', who, user, prev, now });
    },
  };
};
