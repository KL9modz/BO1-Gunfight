'use strict';
/*
 * Member logging - joins, leaves, and name changes.
 *
 * Enabled by setting `memberLogChannelId`. Unset = off and the intent is not requested.
 *
 * ⚠ Needs the PRIVILEGED GUILD_MEMBERS intent, which must be enabled in the Developer Portal
 * (Bot -> Privileged Gateway Intents -> Server Members). Identifying with it while the toggle is
 * off closes the gateway with 4014 and takes every other feature down, which is why it is only
 * requested while this feature has a channel to post to.
 *
 * ── THE ACCOUNT-AGE FLAG ───────────────────────────────────────────────────────────────────────
 * A join card carries the account's creation date, derived from the user id itself - a Discord
 * snowflake has the timestamp in its high bits, so this needs no API call and works for a user we
 * have never seen. A brand-new account is the single cheapest raid and ban-evasion signal there is,
 * so an account younger than `memberLogNewAccountDays` is flagged on the card.
 *
 * ⚠ It is a FLAG, not a verdict. Plenty of real people make an account to join one server. The card
 * says how old it is and lets a human decide; nothing here kicks anybody.
 */

const { COLOR, card, userTag, plural } = require('../lib/brand.js');

const GUILD_MEMBERS = 1 << 1;
// Discord's epoch. A snowflake's top 42 bits are milliseconds since this instant.
const DISCORD_EPOCH = 1420070400000n;

const createdAt = (id) => {
  try { return Number((BigInt(id) >> 22n) + DISCORD_EPOCH); } catch { return null; }
};
// Discord renders <t:seconds:R> as a live relative time ("3 days ago") in every reader's own zone,
// which beats us formatting a date badly.
const stamp = (ms, style = 'f') => `<t:${Math.floor(ms / 1000)}:${style}>`;

const nameOf = (u) => (u ? (u.global_name || u.username || u.id) : 'unknown');

module.exports = function memberLog(ctx) {
  const { cfg, log, rest, cache } = ctx;
  const channelId = cfg.memberLogChannelId;
  const enabled = Boolean(channelId);
  const newAccountDays = Number(cfg.memberLogNewAccountDays || 7);

  // userId -> { nick, name } as we last saw them. GUILD_MEMBER_UPDATE reports the NEW state only,
  // so the previous value has to be remembered or "renamed" has nothing to compare against.
  const seen = new Map();

  const post = (embed) => rest.postMessage(channelId, { embeds: [embed] })
    .catch((e) => log('member log post failed:', e.message));

  return {
    name: 'member_log',
    enabled,
    intents: enabled ? GUILD_MEMBERS : 0,
    permissions: [],
    commands: {},

    on: {
      GUILD_CREATE: (d) => {
        if (d.id !== cfg.guildId) return;
        // Seeded WITHOUT logging, exactly like the voice cache: a restart must not announce every
        // member's current nickname as a fresh rename.
        for (const m of (d.members || [])) {
          if (m.user) seen.set(m.user.id, { nick: m.nick || null, name: nameOf(m.user) });
        }
        log(`member log ready: channel ${channelId}, ${seen.size} member(s) seeded, ` +
            `new-account flag at ${plural(newAccountDays, 'day')}`);
      },

      GUILD_MEMBER_ADD: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        const u = d.user || {};
        seen.set(u.id, { nick: d.nick || null, name: nameOf(u) });

        const born = createdAt(u.id);
        const ageDays = born ? (Date.now() - born) / 86400000 : null;
        const isNew = ageDays !== null && ageDays < newAccountDays;

        const details = [
          ['User', `${userTag(u.id)} (${u.username || '?'})`],
          ['Account created', born ? `${stamp(born)} (${stamp(born, 'R')})` : '_unreadable id_'],
        ];
        if (isNew) details.push(['⚠ Flag', `account is less than ${plural(newAccountDays, 'day')} old`]);

        post(card({
          title: `📥 ${nameOf(u)} joined the server`,
          // The stripe is the flag anyone actually notices in a scroll-back.
          color: isNew ? COLOR.WARN : COLOR.OK,
          details,
          thumbnail: u.avatar ? `https://cdn.discordapp.com/avatars/${u.id}/${u.avatar}.png?size=128` : null,
        }));
      },

      GUILD_MEMBER_REMOVE: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        const u = d.user || {};
        seen.delete(u.id);
        // ⚠ This fires for a leave, a kick AND a ban - the gateway does not distinguish them, and
        // the difference is only in the audit log. The card says "left" because that is what is
        // actually known; claiming a kick we cannot prove would be worse than saying less.
        post(card({
          title: `📤 ${nameOf(u)} left the server`,
          color: COLOR.MUTED,
          details: [
            ['User', `${userTag(u.id)} (${u.username || '?'})`],
            ['In voice at the time', cache.voice.channelOf(u.id) ? 'yes' : 'no'],
          ],
        }));
      },

      GUILD_MEMBER_UPDATE: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        const u = d.user || {};
        const was = seen.get(u.id) || { nick: null, name: null };
        const now = { nick: d.nick || null, name: nameOf(u) };
        seen.set(u.id, now);

        // ⚠ This event ALSO fires for role changes, timeouts and avatar changes. Only names are this
        // feature's business, so anything that did not change a name is dropped rather than posted
        // as a contentless "member updated".
        const nickChanged = was.nick !== now.nick;
        const nameChanged = was.name !== null && was.name !== now.name;
        if (!nickChanged && !nameChanged) return;

        const details = [['User', `${userTag(u.id)} (${u.username || '?'})`]];
        if (nickChanged) details.push(['Nickname', `${was.nick || '_none_'} → ${now.nick || '_none_'}`]);
        if (nameChanged) details.push(['Display name', `${was.name} → ${now.name}`]);

        post(card({
          title: `📝 ${now.name} changed ${nickChanged && nameChanged ? 'names' : (nickChanged ? 'nickname' : 'display name')}`,
          color: COLOR.INFO,
          details,
        }));
      },
    },
  };
};

module.exports.createdAt = createdAt;
