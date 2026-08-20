'use strict';
/*
 * Gateway intents, and WHICH EVENT NEEDS WHICH ONE.
 *
 * ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────────────────────────
 * ⚠ It exists because getting this wrong is SILENT. A feature that subscribes to an event without
 * requesting its intent does not error, does not warn, and does not retry - the event simply never
 * arrives, and everything looks healthy forever.
 *
 * That happened twice here before this table existed, both times found by reading the docs rather
 * than by anything failing:
 *   - voice_log and message_log both correlate GUILD_AUDIT_LOG_ENTRY_CREATE to name who moved,
 *     disconnected or deleted. It needs GUILD_MODERATION, which neither declared - so the "By:"
 *     line could never have appeared. Both even PROBE the audit-log REST endpoint at startup and
 *     would happily report "audit access OK", because the permission was fine; it was the gateway
 *     subscription that was missing.
 *   - automod subscribes to AUTO_MODERATION_RULE_CREATE/UPDATE/DELETE, which need
 *     AUTO_MODERATION_CONFIGURATION, while it declared only AUTO_MODERATION_EXECUTION.
 *
 * So the table is the source of truth and tools/tests/discord_bot.test.js walks every feature's
 * `on` keys against it. A feature that subscribes to something it did not pay for now fails a test
 * instead of quietly doing nothing.
 *
 * Verified against https://docs.discord.com/developers/events/gateway (2026-08-19).
 */

const BITS = {
  GUILDS:                       1 << 0,
  GUILD_MEMBERS:                1 << 1,    // PRIVILEGED
  GUILD_MODERATION:             1 << 2,    // audit log entries + bans. Formerly GUILD_BANS.
  GUILD_VOICE_STATES:           1 << 7,
  GUILD_PRESENCES:              1 << 8,    // PRIVILEGED
  GUILD_MESSAGES:               1 << 9,
  MESSAGE_CONTENT:              1 << 15,   // PRIVILEGED
  AUTO_MODERATION_CONFIGURATION: 1 << 20,
  AUTO_MODERATION_EXECUTION:    1 << 21,
};

// ⚠ These three need a Developer Portal toggle. Identifying with one that is not enabled closes the
// gateway with 4014, which is FATAL for every feature, not just the one that asked. Everything else
// in the table above costs nothing to request.
const PRIVILEGED = BITS.GUILD_MEMBERS | BITS.GUILD_PRESENCES | BITS.MESSAGE_CONTENT;

/*
 * Event -> the intent required to RECEIVE it. 0 means it always arrives.
 *
 * ⚠ MESSAGE_CONTENT is NOT in here, deliberately. It does not gate whether a message event arrives,
 * only whether `content` is populated on it - so it is a per-feature decision ("do I need to read
 * the text?"), not a per-event requirement, and a table entry would make it look mandatory.
 */
const EVENT_INTENT = {
  READY: 0,
  RESUMED: 0,
  INTERACTION_CREATE: 0,

  GUILD_CREATE: BITS.GUILDS,
  GUILD_UPDATE: BITS.GUILDS,
  CHANNEL_CREATE: BITS.GUILDS,
  CHANNEL_UPDATE: BITS.GUILDS,
  CHANNEL_DELETE: BITS.GUILDS,
  GUILD_ROLE_CREATE: BITS.GUILDS,
  GUILD_ROLE_UPDATE: BITS.GUILDS,
  GUILD_ROLE_DELETE: BITS.GUILDS,

  GUILD_MEMBER_ADD: BITS.GUILD_MEMBERS,
  GUILD_MEMBER_REMOVE: BITS.GUILD_MEMBERS,
  GUILD_MEMBER_UPDATE: BITS.GUILD_MEMBERS,

  GUILD_AUDIT_LOG_ENTRY_CREATE: BITS.GUILD_MODERATION,
  GUILD_BAN_ADD: BITS.GUILD_MODERATION,
  GUILD_BAN_REMOVE: BITS.GUILD_MODERATION,

  VOICE_STATE_UPDATE: BITS.GUILD_VOICE_STATES,

  MESSAGE_CREATE: BITS.GUILD_MESSAGES,
  MESSAGE_UPDATE: BITS.GUILD_MESSAGES,
  MESSAGE_DELETE: BITS.GUILD_MESSAGES,
  MESSAGE_DELETE_BULK: BITS.GUILD_MESSAGES,

  AUTO_MODERATION_RULE_CREATE: BITS.AUTO_MODERATION_CONFIGURATION,
  AUTO_MODERATION_RULE_UPDATE: BITS.AUTO_MODERATION_CONFIGURATION,
  AUTO_MODERATION_RULE_DELETE: BITS.AUTO_MODERATION_CONFIGURATION,
  AUTO_MODERATION_ACTION_EXECUTION: BITS.AUTO_MODERATION_EXECUTION,
};

// Human-readable, for the startup line and for a test failure that has to be actionable.
const names = (mask) => Object.entries(BITS).filter(([, b]) => mask & b).map(([n]) => n);

module.exports = { BITS, PRIVILEGED, EVENT_INTENT, names };
