'use strict';
/*
 * Discord ids carry their own creation time. The top 42 bits of a snowflake are milliseconds since
 * Discord's epoch, so account age is readable from the id alone - no API call, no cache, and it
 * works for a user the bot has never seen before.
 *
 * ⚠ In lib/, not in a feature: the join card flags new accounts and the link filter refuses them,
 * and a second copy of this arithmetic is how the two would drift.
 */

const DISCORD_EPOCH = 1420070400000n;

// Returns epoch ms, or null for anything that is not a snowflake. ⚠ Never throws: ids arrive from
// the gateway and from config, and a malformed one must not take a handler down.
function createdAt(id) {
  try {
    const n = BigInt(id);
    if (n <= 0n) return null;
    return Number((n >> 22n) + DISCORD_EPOCH);
  } catch { return null; }
}

// ⚠ null when the id is unreadable, NOT 0 or Infinity. A caller asking "is this account younger
// than 7 days" must be able to tell "no" from "cannot say", because those want opposite defaults.
function ageDays(id, nowMs = Date.now()) {
  const born = createdAt(id);
  return born === null ? null : (nowMs - born) / 86400000;
}

module.exports = { createdAt, ageDays, DISCORD_EPOCH };
