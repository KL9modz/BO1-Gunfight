'use strict';
/*
 * Discord's native Auto Moderation: log what it catches, and report what is not configured.
 *
 * Enabled by setting `automodChannelId` (or it falls back to `modChannelId`).
 *
 * ── WHY THE BOT DOES NOT DO THIS PART ITSELF ───────────────────────────────────────────────────
 * AutoMod runs SERVER-SIDE and blocks a message before it is ever posted. A bot loop cannot match
 * that: it sees the message only after everyone else has, deletes it a beat later, and can be
 * outrun by a fast spammer. So for keywords, presets, mention spam and generic spam the right
 * answer is Discord's own system, and this module's job is only the two things it cannot do:
 * make its decisions VISIBLE in one place, and say what is missing.
 *
 * That mirrors the project's native-first rule: does a stock system already express this? For text
 * spam it does. features/moderation.js owns the parts it genuinely cannot express (attachments,
 * account age, escalation with memory).
 *
 * ── ⚠ THE INTENT CORRECTION ────────────────────────────────────────────────────────────────────
 * An earlier draft of docs/DISCORD_BOT.md recorded that AUTO_MODERATION_ACTION_EXECUTION needs "no
 * intent". THAT IS WRONG and it is the expensive kind of wrong - the events simply never arrive and
 * everything looks healthy. It needs AUTO_MODERATION_EXECUTION (1 << 21). The saving grace is that
 * this intent is NOT privileged, so it needs no portal toggle and cannot cause a 4014.
 *
 * ⚠ Receiving the events, and listing rules at all, additionally needs the MANAGE SERVER permission.
 * Without it the probe below says so in the service log rather than leaving a silent dead feature.
 */

const { COLOR, card, chanChip, userTag, clamp, plural, FIELD_MAX } = require('../lib/brand.js');

const AUTO_MODERATION_EXECUTION = 1 << 21;

// Trigger types, for reporting what a guild has and what it is missing.
const TRIGGER = { 1: 'Keyword', 3: 'Spam', 4: 'Keyword preset', 5: 'Mention spam', 6: 'Member profile' };
// What a server like this one wants, in the order worth adding them. Reported, never created: the
// guild's moderation config belongs to its owner, and a bot that silently rewrites it is a bot
// nobody can reason about.
const RECOMMENDED = [
  { type: 4, why: 'Discord\'s own profanity / sexual-content / slur lists' },
  { type: 3, why: 'generic spam detection' },
  { type: 5, why: 'mass-mention raids' },
  { type: 1, why: 'a keyword rule blocking discord.gg invite links' },
];

const ACTION = { 1: 'blocked the message', 2: 'sent an alert', 3: 'timed the member out', 4: 'blocked member interaction' };

module.exports = function automod(ctx) {
  const { cfg, log, rest } = ctx;
  const channelId = cfg.automodChannelId || cfg.modChannelId || '';
  const enabled = Boolean(channelId);

  let rules = null;      // last known rule list, refreshed on connect and on any rule change

  async function refresh() {
    try {
      rules = await rest.get(`/guilds/${cfg.guildId}/auto-moderation/rules`);
      const have = new Set(rules.map((r) => r.trigger_type));
      const missing = RECOMMENDED.filter((r) => !have.has(r.type));
      log(`automod: ${plural(rules.length, 'rule')} configured` +
          (missing.length ? `, missing ${missing.map((m) => TRIGGER[m.type]).join(', ')}` : ', all recommended types present'));
    } catch (e) {
      // ⚠ Almost always the missing MANAGE SERVER permission. Said out loud, because the symptom
      // otherwise is a feature that appears to work and reports nothing forever.
      rules = null;
      log(`automod: cannot list rules (${e.message}) - grant Manage Server, or this feature is blind`);
    }
  }

  const commands = {
    automod: {
      admin: true,
      description: 'Show which Discord AutoMod rules this server has, and what is missing',
      run: async () => {
        await refresh();
        if (rules === null) {
          return 'Cannot read AutoMod rules. The bot needs the **Manage Server** permission.';
        }
        const have = new Set(rules.map((r) => r.trigger_type));
        const lines = rules.map((r) =>
          `${r.enabled ? '🟢' : '⚪'} **${r.name}** — ${TRIGGER[r.trigger_type] || 'type ' + r.trigger_type}` +
          `, ${r.actions.map((a) => ACTION[a.type] || 'action ' + a.type).join(' + ')}`);
        const missing = RECOMMENDED.filter((r) => !have.has(r.type));

        const details = [];
        if (missing.length) {
          details.push(['Not configured', missing.map((m) => `**${TRIGGER[m.type]}** — ${m.why}`).join('\n')]);
          // ⚠ Deliberately a recommendation, not a button. Creating rules would rewrite the guild's
          // moderation config from a chat command, and an owner should make that change knowingly
          // in Server Settings where they can see exactly what it does.
          details.push(['To add them', 'Server Settings → AutoMod. This bot reports, it does not edit.']);
        }
        return { embeds: [card({
          title: `🛡 AutoMod: ${plural(rules.length, 'rule')}`,
          color: missing.length ? COLOR.WARN : COLOR.OK,
          description: lines.length ? clamp(lines.join('\n'), FIELD_MAX) : '_no rules configured_',
          details,
          footer: true,
        })] };
      },
    },
  };

  return {
    name: 'automod',
    enabled,
    // ⚠ 1 << 21, non-privileged. Without it the ACTION_EXECUTION events never arrive at all.
    intents: enabled ? AUTO_MODERATION_EXECUTION : 0,
    permissions: ['Manage Server'],
    commands,

    on: {
      GUILD_CREATE: (d) => {
        if (d.id !== cfg.guildId) return;
        refresh().catch(() => {});
      },

      // Keeping the cached list honest costs nothing and makes /automod truthful right after
      // someone edits a rule in Server Settings.
      AUTO_MODERATION_RULE_CREATE: () => { refresh().catch(() => {}); },
      AUTO_MODERATION_RULE_UPDATE: () => { refresh().catch(() => {}); },
      AUTO_MODERATION_RULE_DELETE: () => { refresh().catch(() => {}); },

      AUTO_MODERATION_ACTION_EXECUTION: (d) => {
        if (d.guild_id !== cfg.guildId) return;
        const details = [
          ['User', userTag(d.user_id)],
          ['Channel', d.channel_id ? chanChip(d.channel_id) : '_unknown_'],
          ['Rule', d.rule_trigger_type ? (TRIGGER[d.rule_trigger_type] || 'type ' + d.rule_trigger_type) : '_unknown_'],
          ['Action', ACTION[d.action && d.action.type] || 'unknown'],
          ['Matched', d.matched_keyword ? `\`${d.matched_keyword}\`` : '_not reported_'],
        ];
        rest.postMessage(channelId, { embeds: [card({
          title: '🛡 AutoMod blocked a message',
          color: COLOR.WARN,
          // ⚠ The content Discord blocked, quoted. It reached nobody in the channel, but a moderator
          // reviewing a false positive needs to see what the rule actually caught.
          description: d.content
            ? clamp(String(d.content).split('\n').map((l) => '> ' + l).join('\n').slice(0, 900), FIELD_MAX)
            : undefined,
          details,
        })] }).catch((e) => log('automod log failed:', e.message));
      },
    },
  };
};

module.exports.TRIGGER = TRIGGER;
module.exports.RECOMMENDED = RECOMMENDED;
