'use strict';
/*
 * Link and media moderation - the half Discord's own AutoMod cannot express.
 *
 * Enabled by setting `modChannelId`. That channel is not optional decoration: moderation without a
 * log is moderation nobody can review or appeal, so the feature stays off until it has somewhere to
 * report to.
 *
 * ── WHAT LIVES HERE AND WHAT LIVES IN AUTOMOD ──────────────────────────────────────────────────
 * Native AutoMod is strictly better for TEXT: it blocks a message before it is ever posted, costs
 * no process, and cannot be outrun by a fast spammer. It handles keywords, presets, mention spam and
 * generic spam. features/automod.js logs its hits; nothing here duplicates it.
 *
 * What AutoMod has no concept of, and this file therefore owns:
 *   - ATTACHMENTS. There is no attachment condition in AutoMod at all: not type, not size, not
 *     count. An .exe posted in a game server's chat is the single highest-value thing to catch and
 *     AutoMod cannot see it.
 *   - ACCOUNT AGE. "A three-hour-old account may not post links" is the rule that stops the ordinary
 *     spam wave, and it needs the poster's id decoded, which AutoMod does not do.
 *   - ESCALATION with memory. AutoMod acts per message; strikes across a window need state.
 *
 * ── THE ESCALATION, AND ITS CEILING ────────────────────────────────────────────────────────────
 * delete -> strike -> timeout. ⚠ AND IT STOPS THERE. Nothing in this file kicks or bans, and that is
 * a deliberate ceiling rather than an unfinished feature: a false positive that bans a real player
 * costs more than any spam wave, and a timeout is reversible by any moderator while a ban is a
 * decision a human should make from a log line the bot handed them.
 */

const { COLOR, card, clamp, chanChip, userTag, plural, FIELD_MAX } = require('../lib/brand.js');
const { ageDays } = require('../lib/snowflake.js');

const { BITS } = require('../lib/intents.js');

// Executables and script types. ⚠ The check is on the LAST extension, which is what makes
// "screenshot.png.exe" resolve to exe rather than to png - that trick is the whole reason a filename
// cannot be trusted from the left.
const DEFAULT_BLOCKED = [
  'exe', 'scr', 'bat', 'cmd', 'com', 'pif', 'msi', 'msp', 'hta', 'cpl', 'jar', 'apk',
  'vbs', 'vbe', 'js', 'jse', 'wsf', 'wsh', 'ps1', 'psm1', 'reg', 'lnk', 'scf', 'inf', 'dll',
  'sh', 'run', 'bin',
];

// Deliberately loose: this only has to FIND candidate links, and the host is what gets judged.
const URL_RE = /https?:\/\/([^\s/$.?#][^\s/]*)/gi;

const extOf = (name) => {
  const m = String(name || '').toLowerCase().match(/\.([a-z0-9]+)$/);
  return m ? m[1] : '';
};

// A host matches a rule if it IS the rule or is a subdomain of it, so "youtube.com" covers
// "www.youtube.com" without covering "notyoutube.com".
const hostMatches = (host, rule) => {
  const h = String(host || '').toLowerCase().replace(/^www\./, '');
  const r = String(rule || '').toLowerCase().replace(/^www\./, '');
  return Boolean(r) && (h === r || h.endsWith('.' + r));
};

function hostsIn(text) {
  const out = [];
  for (const m of String(text || '').matchAll(URL_RE)) {
    out.push(m[1].toLowerCase().replace(/:\d+$/, ''));
  }
  return out;
}

/*
 * Judge a message. PURE - every rule is a decision over arguments, so each can be tested on its own
 * without a gateway, a token or a config file. Returns null (fine) or { reason, detail }.
 */
function judge(msg, authorAgeDays, rules) {
  const { blocked, maxBytes, maxMB, allowDomains, denyDomains, linkMinAge } = rules;
  for (const a of (msg.attachments || [])) {
    const ext = extOf(a.filename);
    if (ext && blocked.includes(ext)) {
      return { reason: 'blocked file type', detail: `\`${a.filename}\` is a .${ext}` };
    }
    if (maxBytes && a.size > maxBytes) {
      return { reason: 'attachment too large',
               detail: `\`${a.filename}\` is ${Math.round(a.size / 1048576)}MB, over the ${maxMB}MB limit` };
    }
  }

  const hosts = hostsIn(msg.content);
  if (!hosts.length) return null;

  // ⚠ The age rule runs BEFORE the domain lists on purpose. A brand-new account posting any link
  // is the ordinary spam wave, and letting it through because the domain happened to be
  // allow-listed would defeat the rule that actually works.
  if (linkMinAge > 0 && authorAgeDays !== null && authorAgeDays < linkMinAge) {
    return { reason: 'link from a new account',
             detail: `account is ${authorAgeDays < 1 ? 'less than a day' : plural(Math.floor(authorAgeDays), 'day')} old, ` +
                     `links need ${plural(linkMinAge, 'day')}` };
  }

  if (allowDomains.length) {
    const bad = hosts.find((h) => !allowDomains.some((d) => hostMatches(h, d)));
    // ⚠ Allowlist mode is deliberately all-or-nothing per message: one disallowed host makes the
    // message go. A message that is half-allowed is still carrying the link nobody wanted.
    if (bad) return { reason: 'link not on the allowlist', detail: `\`${bad}\`` };
    return null;
  }
  if (denyDomains.length) {
    const bad = hosts.find((h) => denyDomains.some((d) => hostMatches(h, d)));
    if (bad) return { reason: 'blocked domain', detail: `\`${bad}\`` };
  }
  return null;
}

module.exports = function moderation(ctx) {
  const { cfg, log, rest } = ctx;
  const channelId = cfg.modChannelId || '';
  const enabled = Boolean(channelId);

  const blocked = (cfg.modBlockedExtensions || DEFAULT_BLOCKED).map((e) => String(e).toLowerCase().replace(/^\./, ''));
  const maxBytes = Number(cfg.modMaxAttachmentMB || 0) * 1024 * 1024;
  const allowDomains = (cfg.modAllowedDomains || []).map(String);
  const denyDomains = (cfg.modBlockedDomains || []).map(String);
  const linkMinAge = Number(cfg.modLinkMinAccountDays || 0);
  const exemptRoles = new Set((cfg.modExemptRoles || []).map(String));
  const exemptChannels = new Set([
    ...(cfg.modExemptChannels || []).map(String),
    // The log channels are exempt by construction: our own cards quote deleted content and would
    // otherwise trip the very filters that produced them.
    String(channelId), String(cfg.messageLogChannelId || ''), String(cfg.memberLogChannelId || ''),
  ].filter(Boolean));

  const strikeWindowMs = Number(cfg.modStrikeWindowMinutes || 10) * 60000;
  const strikesBeforeTimeout = Number(cfg.modStrikes || 3);
  const timeoutMinutes = Number(cfg.modTimeoutMinutes || 10);

  const strikes = new Map();   // userId -> [epoch ms]

  function strike(userId) {
    const now = Date.now();
    const hits = (strikes.get(userId) || []).filter((t) => now - t < strikeWindowMs);
    hits.push(now);
    strikes.set(userId, hits);
    return hits.length;
  }

  // Everything judge() needs, resolved once. Passing it explicitly is what lets the rules live at
  // module scope and be tested one at a time without a gateway or a config file.
  const rules = { blocked, maxBytes, maxMB: Number(cfg.modMaxAttachmentMB || 0),
                  allowDomains, denyDomains, linkMinAge };

  function exempt(d) {
    if (exemptChannels.has(String(d.channel_id))) return true;
    if (d.author && d.author.bot) return true;
    const roles = (d.member && d.member.roles) || [];
    if (roles.includes(cfg.adminRoleId)) return true;
    return roles.some((r) => exemptRoles.has(String(r)));
  }

  async function act(d, verdict) {
    const userId = d.author.id;
    const count = strike(userId);
    const shouldTimeout = count >= strikesBeforeTimeout;

    let deleted = false, timedOut = false, failure = null;
    try {
      await rest.deleteMessage(d.channel_id, d.id, `automod: ${verdict.reason}`);
      deleted = true;
    } catch (e) { failure = 'delete failed: ' + e.message; }

    if (shouldTimeout) {
      try {
        const until = new Date(Date.now() + timeoutMinutes * 60000).toISOString();
        await rest.modifyMember(cfg.guildId, userId, { communication_disabled_until: until },
                                `automod: ${plural(count, 'strike')} in ${cfg.modStrikeWindowMinutes || 10} minutes`);
        timedOut = true;
      } catch (e) { failure = (failure ? failure + '; ' : '') + 'timeout failed: ' + e.message; }
    }

    const details = [
      ['User', `${userTag(userId)} (${d.author.username || '?'})`],
      ['Channel', chanChip(d.channel_id)],
      ['Reason', `${verdict.reason} - ${verdict.detail}`],
      ['Action', `${deleted ? 'message deleted' : '**not deleted**'}` +
                 `${timedOut ? `, timed out ${plural(timeoutMinutes, 'minute')}` : ''}`],
      ['Strikes', `${count} in the last ${plural(Number(cfg.modStrikeWindowMinutes || 10), 'minute')}`],
    ];
    // ⚠ A failure is REPORTED, never swallowed. A missing permission would otherwise look exactly
    // like a quiet server, and the first anyone would know is a spam wave nothing acted on.
    if (failure) details.push(['⚠ Error', failure]);

    log(`moderation: ${verdict.reason} by ${d.author.username} in ${d.channel_id} ` +
        `(strike ${count}${timedOut ? ', timed out' : ''})${failure ? ' - ' + failure : ''}`);

    await rest.postMessage(channelId, { embeds: [card({
      title: shouldTimeout ? '🛡 Message removed, user timed out' : '🛡 Message removed',
      color: shouldTimeout ? COLOR.DANGER : COLOR.WARN,
      // The content is quoted so a moderator can judge the call without hunting for a message that
      // no longer exists. Same quoting rule as the message log: it can contain markdown.
      description: d.content ? clamp(String(d.content).split('\n').map((l) => '> ' + l).join('\n').slice(0, 900), FIELD_MAX) : undefined,
      details,
    })] });
  }

  return {
    name: 'moderation',
    enabled,
    intents: enabled ? (BITS.GUILD_MESSAGES | BITS.MESSAGE_CONTENT) : 0,
    permissions: ['Manage Messages', 'Moderate Members'],
    commands: {},

    on: {
      GUILD_CREATE: (d) => {
        if (d.id !== cfg.guildId) return;
        log(`moderation ready: ${blocked.length} blocked extensions, ` +
            `links ${allowDomains.length ? 'allowlist' : (denyDomains.length ? 'denylist' : 'unrestricted')}` +
            `${linkMinAge ? `, new accounts under ${plural(linkMinAge, 'day')} may not link` : ''}, ` +
            `timeout after ${plural(strikesBeforeTimeout, 'strike')}`);
      },

      MESSAGE_CREATE: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        if (!d.author || exempt(d)) return;
        const verdict = judge(d, ageDays(d.author.id), rules);
        if (!verdict) return;
        act(d, verdict).catch((e) => log('moderation action failed:', e.message));
      },
    },
  };
};

// Exported for the tests: every rule is a pure decision and worth pinning individually.
module.exports.judge = judge;
module.exports.DEFAULT_BLOCKED = DEFAULT_BLOCKED;
module.exports.extOf = extOf;
module.exports.hostMatches = hostMatches;
module.exports.hostsIn = hostsIn;
