'use strict';
/*
 * The REST transport. ONE place holds the token and the base URL, and EVERY call goes through one
 * queue that respects Discord's rate limits.
 *
 * ── WHY A QUEUE ────────────────────────────────────────────────────────────────────────────────
 * Before this, each caller ran its own bare fetch and a 429 simply threw - so a burst (a call
 * emptying and the voice log editing its card, a /moveall walking twenty members) lost writes and
 * reported failure for something that only needed to wait 200ms. Discord tells you exactly how long
 * to wait; not reading that reply is the whole bug.
 *
 * Three things it handles, all of them observed behaviour rather than theory:
 *   429 with retry_after  - wait that long and retry. `global: true` means EVERY route is paused,
 *                           not just this one, so it is tracked separately.
 *   5xx                   - Discord's own hiccup. Retried with backoff.
 *   4xx (not 429)         - OUR bug (bad payload, missing permission). Thrown immediately: retrying
 *                           a malformed request just earns the same 400 three times.
 *
 * ⚠ Concurrency is deliberately low. This bot is never the busy client on this box, and a small
 * window means one misbehaving feature cannot starve the others or trip the global limit.
 */

const API = 'https://discord.com/api/v10';
const MAX_CONCURRENT = 2;
const MAX_ATTEMPTS = 4;

// ⚠ allowed_mentions parse:[] on EVERY message write, applied here rather than by callers. A
// mention inside an embed renders its chip and pings nobody, which is what makes it safe to show a
// player's @name in a join card - but that property depends on this being set, and a feature that
// forgets it would silently start pinging people. Enforcing it centrally means it cannot be
// forgotten. A feature that genuinely needs to ping passes `mentions` explicitly.
const noPing = { parse: [] };

module.exports = function makeRest(token, log) {
  let active = 0;
  let globalUntil = 0;             // epoch ms - a global 429 pauses every route
  const queue = [];

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function pump() {
    while (active < MAX_CONCURRENT && queue.length) {
      const job = queue.shift();
      active++;
      job().finally(() => { active--; pump(); });
    }
  }

  const enqueue = (fn) => new Promise((resolve, reject) => {
    queue.push(() => fn().then(resolve, reject));
    pump();
  });

  async function attempt(method, path, body, headers) {
    const wait = globalUntil - Date.now();
    if (wait > 0) await sleep(wait);

    const res = await fetch(API + path, {
      method,
      headers: Object.assign(
        { Authorization: 'Bot ' + token },
        body === undefined ? {} : { 'Content-Type': 'application/json' },
        headers || {}),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return res;
  }

  async function request(method, path, body, opts = {}) {
    return enqueue(async () => {
      let lastErr = null;
      for (let i = 0; i < MAX_ATTEMPTS; i++) {
        const headers = {};
        // Shows up in Discord's own audit log next to the action. Worth setting on anything that
        // changes the guild, so a human reading the audit log sees WHY and not just "the bot did it".
        if (opts.reason) headers['X-Audit-Log-Reason'] = String(opts.reason).slice(0, 512);

        let res;
        try { res = await attempt(method, path, body, headers); }
        catch (e) { lastErr = e; await sleep(300 * (i + 1)); continue; }   // socket-level, retry

        if (res.status === 429) {
          let info = {};
          try { info = await res.json(); } catch { /* empty body on a 429 is legal */ }
          const ms = Math.ceil((Number(info.retry_after) || 1) * 1000) + 100;
          if (info.global) globalUntil = Date.now() + ms;
          log(`rate limited${info.global ? ' (GLOBAL)' : ''} on ${method} ${path} - waiting ${ms}ms`);
          await sleep(ms);
          continue;
        }
        if (res.status >= 500) { await sleep(400 * Math.pow(2, i)); lastErr = new Error('HTTP ' + res.status); continue; }
        if (!res.ok) throw new Error(`HTTP ${res.status} ${method} ${path} ${await res.text()}`);

        if (res.status === 204) return null;
        try { return await res.json(); } catch { return null; }
      }
      throw lastErr || new Error(`gave up after ${MAX_ATTEMPTS} attempts: ${method} ${path}`);
    });
  }

  const withMentions = (p) => Object.assign({ allowed_mentions: noPing }, p);

  return {
    request,

    // Non-throwing capability probe. A feature asking "can I read the audit log?" wants an answer,
    // not an exception - the whole point is to adapt what it claims rather than to fail.
    async probe(path) {
      try {
        const res = await enqueue(() => attempt('GET', path, undefined, {}));
        return { ok: res.ok, status: res.status };
      } catch (e) { return { ok: false, status: 0, error: e.message }; }
    },

    get:  (path) => request('GET', path),

    postMessage: (channelId, payload) =>
      request('POST', `/channels/${channelId}/messages`, withMentions(payload)),
    editMessage: (channelId, messageId, payload) =>
      request('PATCH', `/channels/${channelId}/messages/${messageId}`, withMentions(payload)),
    deleteMessage: (channelId, messageId, reason) =>
      request('DELETE', `/channels/${channelId}/messages/${messageId}`, undefined, { reason }),

    // Member edits: voice channel moves today, timeouts when moderation lands. ⚠ channel_id null
    // DISCONNECTS the member from voice, which is a legitimate and destructive use of the same call.
    modifyMember: (guildId, userId, payload, reason) =>
      request('PATCH', `/guilds/${guildId}/members/${userId}`, payload, { reason }),

    // GUILD commands, not global: guild registration is instant, global takes up to an hour to
    // propagate, and this bot serves exactly one guild.
    putCommands: (appId, guildId, payload) =>
      request('PUT', `/applications/${appId}/guilds/${guildId}/commands`, payload),

    interaction: {
      // Deferred FIRST: Discord requires a reply within 3s, and an rcon round trip through the
      // panel's paced queue can exceed that. flags 64 = ephemeral, so ops chatter stays private.
      // ⚠ Deliberately NOT queued - the 3s clock is running and this must not sit behind a burst
      // of voice-log edits. It is one tiny request per command, so it cannot threaten the limit.
      defer: (id, itoken, ephemeral = true) =>
        fetch(`${API}/interactions/${id}/${itoken}/callback`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ type: 5, data: ephemeral ? { flags: 64 } : {} }),
        }).catch(() => {}),
      edit: (appId, itoken, payload) =>
        request('PATCH', `/webhooks/${appId}/${itoken}/messages/@original`, withMentions(payload)),
    },

    stats: () => ({ queued: queue.length, active, globalPausedMs: Math.max(0, globalUntil - Date.now()) }),
  };
};
