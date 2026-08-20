'use strict';
/*
 * Discord -> in-game chat relay. One channel, optionally one role, and a sanitiser between the two.
 *
 * ⚠ The privileged MESSAGE_CONTENT intent is requested CONDITIONALLY - that is why this module
 * declares its intent rather than bot.js hardcoding it. Identifying with an intent that is not
 * enabled in the Developer Portal closes the gateway with 4014, which is fatal for EVERY feature,
 * so a bot with no relay configured must not ask for it at all. That keeps the ops half working on
 * a fresh install before anyone has touched the portal toggle, and it is least-privilege besides:
 * we ask to read message text only while a relay channel actually exists.
 */

const GUILD_MESSAGES = 1 << 9;
const MESSAGE_CONTENT = 1 << 15;

module.exports = function relay(ctx) {
  const { cfg, log, panel, allow } = ctx;
  const enabled = Boolean(cfg.relayChannelId);

  async function onMessage(d) {
    if (d.channel_id !== cfg.relayChannelId) return;                  // gate: channel allowlist
    if (!d.content || (d.author && d.author.bot)) return;
    if (d.guild_id !== cfg.guildId) return;
    const roles = (d.member && d.member.roles) || [];
    // relayRoleId is optional: unset means anyone in that channel can talk to the server, which is a
    // deliberate choice for a private channel and a bad one for a public one.
    if (cfg.relayRoleId && !roles.includes(cfg.relayRoleId) && !roles.includes(cfg.adminRoleId)) return;
    if (!allow(d.author.id)) return;

    const nick = (d.member && d.member.nick) || d.author.global_name || d.author.username;
    const line = panel.sanitiseForGame(`[D] ${nick}: ${d.content}`);
    if (!line) return;
    const r = await panel.rcon(`set gf_say "${line}";set gf_cmd saymsg`);
    log(`relay ${r.ok ? 'ok' : 'FAILED'}: ${line}`);
  }

  return {
    name: 'relay',
    enabled,
    intents: enabled ? (GUILD_MESSAGES | MESSAGE_CONTENT) : 0,
    permissions: ['Read Message History'],
    commands: {},
    on: {
      MESSAGE_CREATE: (d) => onMessage(d).catch((e) => log('relay error:', e.message)),
    },
  };
};
