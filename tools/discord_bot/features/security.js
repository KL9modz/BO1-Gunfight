'use strict';
/*
 * Security watch - the raid alarm, and alerts on the guild changes that actually matter.
 *
 * Enabled by setting `securityChannelId` (falls back to `modChannelId`).
 *
 * ── WHAT THIS IS FOR ───────────────────────────────────────────────────────────────────────────
 * Two different threats, both invisible in an ordinary log:
 *
 *   A RAID is a burst of joins, usually fresh throwaway accounts, and it is obvious in hindsight
 *   and easy to miss live. So joins are counted in a window and the alarm names the accounts and
 *   how old they are.
 *
 *   A TAKEOVER is quiet. Someone grants a role Administrator, adds a bot, or creates a webhook -
 *   one action, no noise, and the server is no longer yours. Those live in the audit log next to a
 *   hundred boring entries, so this pulls out a curated few and shouts about the dangerous ones.
 *
 * ── ⚠ IT ALERTS, IT NEVER ACTS ─────────────────────────────────────────────────────────────────
 * Nothing here kicks, bans, or changes a permission, and that is deliberate rather than unfinished.
 * Every automated response to a raid has a failure mode that is worse than the raid: lockdown during
 * a legitimate influx, kicking real players who joined from a stream. The bot's edge is NOTICING
 * within seconds; the decision stays with a human who now has the facts.
 *
 * ── THE ONE PLACE A PING IS EARNED ─────────────────────────────────────────────────────────────
 * `securityAlertRoleId` is pinged for CRITICAL only. Every other card in this bot deliberately
 * cannot ping (lib/rest.js sets allowed_mentions parse:[] on every write), because a mention chip
 * that notifies nobody is what makes it safe to show names. This overrides that centrally-applied
 * default ON PURPOSE and in exactly one place: "someone just granted a role Administrator" is worth
 * a phone buzzing at 3am, and nothing else in this bot is.
 */

const { COLOR, card, clamp, userTag, roleTag, chanChip, plural, FIELD_MAX } = require('../lib/brand.js');
const { BITS } = require('../lib/intents.js');
const { ageDays } = require('../lib/snowflake.js');

// Audit log action types worth surfacing. Everything not listed is noise for this purpose.
// ⚠ CRITICAL means "this can hand someone the server". NOTABLE means "a human should see it".
const CRITICAL = {
  1:  'server settings changed',
  28: 'a BOT was added to the server',
  30: 'a role was created',
  31: 'a role was changed',
  25: 'a member\'s roles were changed',
  50: 'a WEBHOOK was created',
  80: 'an integration was added',
};
const NOTABLE = {
  32: 'a role was deleted',
  12: 'a channel was deleted',
  14: 'channel permissions were changed',
  20: 'a member was kicked',
  21: 'members were pruned',
  22: 'a member was banned',
  23: 'a member was unbanned',
  51: 'a webhook was changed',
  52: 'a webhook was deleted',
};

// Permission bits that turn a role into a takeover. ⚠ ADMINISTRATOR implies all of them, which is
// why it is checked first and reported alone - listing twelve permissions when one word covers it
// makes the alert harder to read, not more informative.
const DANGEROUS_PERMS = [
  [0x8n, 'ADMINISTRATOR'],
  [0x10n, 'MANAGE_CHANNELS'],
  [0x20n, 'MANAGE_GUILD'],
  [0x10000000n, 'MANAGE_ROLES'],
  [0x20000000n, 'MANAGE_WEBHOOKS'],
  [0x4n, 'BAN_MEMBERS'],
  [0x2n, 'KICK_MEMBERS'],
  [0x2000n, 'MANAGE_MESSAGES'],
];

/*
 * Which dangerous permissions a change ADDED. PURE, and it answers "what is newly granted", not
 * "what does this role have" - a role that already had Administrator being renamed is not news.
 */
function grantedPerms(changes) {
  const perm = (changes || []).find((c) => c.key === 'permissions');
  if (!perm) return [];
  let before = 0n, after = 0n;
  try { before = BigInt(perm.old_value || 0); } catch { before = 0n; }
  try { after = BigInt(perm.new_value || 0); } catch { after = 0n; }
  const added = after & ~before;
  if (added & 0x8n) return ['ADMINISTRATOR'];
  return DANGEROUS_PERMS.filter(([bit]) => added & bit).map(([, name]) => name);
}

module.exports = function security(ctx) {
  const { cfg, log, rest } = ctx;
  const channelId = cfg.securityChannelId || cfg.modChannelId || '';
  const enabled = Boolean(channelId);
  const alertRole = cfg.securityAlertRoleId || '';

  const raidJoins = Number(cfg.securityRaidJoins || 5);
  const raidWindowMs = Number(cfg.securityRaidWindowSeconds || 60) * 1000;
  const raidCooldownMs = Number(cfg.securityRaidCooldownMinutes || 10) * 60000;

  let selfId = null;              // our own bot, so our moderation actions are not "suspicious"
  let joins = [];                 // recent { id, name, age }
  let lastRaidAlert = 0;

  async function alert(embed, critical) {
    const payload = { embeds: [embed] };
    // ⚠ The ONE deliberate override of the no-ping default, and only for CRITICAL. See the header.
    if (critical && alertRole) {
      payload.content = `${roleTag(alertRole)} security alert`;
      payload.allowed_mentions = { roles: [String(alertRole)] };
    }
    try { await rest.postMessage(channelId, payload); }
    catch (e) { log('security alert failed:', e.message); }
  }

  function onJoin(d) {
    const u = d.user || {};
    const now = Date.now();
    joins = joins.filter((j) => now - j.at < raidWindowMs);
    joins.push({ id: u.id, name: u.username || u.id, age: ageDays(u.id, now), at: now });
    if (joins.length < raidJoins) return;
    if (now - lastRaidAlert < raidCooldownMs) return;   // one alarm per wave, not one per joiner
    lastRaidAlert = now;

    const fresh = joins.filter((j) => j.age !== null && j.age < 1).length;
    const roster = joins.map((j) =>
      `${userTag(j.id)} — ${j.age === null ? 'age unknown' : (j.age < 1 ? '**less than a day old**' : plural(Math.floor(j.age), 'day') + ' old')}`
    ).join('\n');

    log(`SECURITY: raid alarm - ${joins.length} joins in ${raidWindowMs / 1000}s, ${fresh} brand new`);
    alert(card({
      title: `🚨 ${plural(joins.length, 'join')} in ${plural(raidWindowMs / 1000, 'second')}`,
      color: COLOR.DANGER,
      description: clamp(roster, FIELD_MAX),
      details: [
        ['Brand-new accounts', `${fresh} of ${joins.length}`],
        // ⚠ Says what it is NOT doing. An alarm that looks like it acted, but did not, is worse than
        // no alarm - somebody would assume it was handled.
        ['Action taken', '**none** - this is an alert only'],
        ['If this is real', 'Server Settings → Moderation → raise the verification level, or pause invites'],
      ],
      footer: true,
    }), true);
  }

  function onAudit(d) {
    if (d.guild_id && d.guild_id !== cfg.guildId) return;
    // ⚠ Our own actions are not suspicious. /moveall and the moderation timeouts both write audit
    // entries, and alerting on them would train everyone to ignore this channel within a day.
    if (selfId && d.user_id === selfId) return;

    const isCritical = Object.prototype.hasOwnProperty.call(CRITICAL, d.action_type);
    const what = CRITICAL[d.action_type] || NOTABLE[d.action_type];
    if (!what) return;

    const details = [
      ['Actor', d.user_id ? userTag(d.user_id) : '_unknown_'],
      ['Target', d.target_id ? `\`${d.target_id}\`` : '_none_'],
    ];

    // The high-signal case: a permission change that hands out real power.
    const granted = grantedPerms(d.changes);
    if (granted.length) details.push(['⚠ Permissions GRANTED', granted.map((p) => `**${p}**`).join(', ')]);

    const named = (d.changes || []).find((c) => c.key === 'name');
    if (named) details.push(['Name', `${named.old_value || '_none_'} → ${named.new_value || '_none_'}`]);
    if (d.reason) details.push(['Reason', d.reason]);

    // ⚠ An Administrator grant is escalated to CRITICAL even from a NOTABLE action type: the action
    // matters less than what it handed over.
    const critical = isCritical || granted.includes('ADMINISTRATOR');
    if (critical) log(`SECURITY: ${what}${granted.length ? ' granting ' + granted.join(',') : ''} by ${d.user_id}`);

    alert(card({
      title: `${critical ? '🚨' : '🔎'} ${what}`,
      color: critical ? COLOR.DANGER : COLOR.WARN,
      details,
    }), critical);
  }

  return {
    name: 'security',
    enabled,
    // GUILD_MEMBERS (privileged) for the raid alarm; GUILD_MODERATION for the audit stream.
    intents: enabled ? (BITS.GUILD_MEMBERS | BITS.GUILD_MODERATION) : 0,
    permissions: ['View Audit Log'],
    commands: {},

    on: {
      READY: (d) => { selfId = d.user && d.user.id; },

      GUILD_CREATE: (d) => {
        if (d.id !== cfg.guildId) return;
        log(`security ready: raid alarm at ${plural(raidJoins, 'join')} in ${raidWindowMs / 1000}s, ` +
            `${alertRole ? 'pinging <@&' + alertRole + '> on critical' : 'no alert role configured'}`);
      },

      GUILD_MEMBER_ADD: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        onJoin(d);
      },

      GUILD_AUDIT_LOG_ENTRY_CREATE: (d) => onAudit(d),
    },
  };
};

module.exports.grantedPerms = grantedPerms;
module.exports.CRITICAL = CRITICAL;
module.exports.NOTABLE = NOTABLE;
