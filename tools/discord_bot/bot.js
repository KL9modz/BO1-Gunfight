'use strict';
/*
 * GF-DiscordBot - the gateway client and the event router. NO features live here.
 *
 *   node bot.js            (normally run by the GF-DiscordBot scheduled task)
 *   node bot.js --register (register/refresh the slash commands, then exit)
 *
 * ── WHY ZERO DEPENDENCIES ──────────────────────────────────────────────────────────────────────
 * discord.js is the obvious choice and is deliberately NOT used. This process can restart the game
 * server and speak to every player, and it runs on the box that holds the rcon password - so a
 * transitive dependency tree is a supply-chain surface aimed at the worst possible target. Node 24
 * ships native WebSocket and fetch, and the slice of the gateway needed here is small: identify,
 * heartbeat, resume, and a handful of dispatch events. The panel next door is dependency-free for
 * the same reason. Cost, stated honestly: reconnect/resume logic is ours to get right (see connect).
 *
 * ── THE MODULE CONTRACT ────────────────────────────────────────────────────────────────────────
 * A feature is a factory taking `ctx` and returning:
 *
 *   { name, enabled, intents, permissions, commands, on: { GATEWAY_EVENT: handler } }
 *
 * bot.js unions the intents and merges the command tables of the ENABLED modules only. That
 * preserves the property this project earned the hard way: NEVER REQUEST AN INTENT A FEATURE DOES
 * NOT NEED, because identifying with a privileged intent that is not enabled in the Developer
 * Portal closes the gateway with 4014 - which is fatal for every OTHER feature too.
 *
 * `permissions` is documentation: it names what a module needs on the bot's role, so the invite can
 * be assembled from what is actually switched on rather than from an Administrator tick.
 *
 * ── SECURITY MODEL ─────────────────────────────────────────────────────────────────────────────
 * A Discord message is UNTRUSTED INPUT that reaches an rcon console. Four gates, all load-bearing,
 * none optional - and the first three live HERE, in the router, so a feature cannot forget one:
 *   1. VERB WHITELIST. Commands map to fixed templates - there is no passthrough. A caller cannot
 *      reach a dvar a feature does not name.
 *   2. ROLE GATE. Anything that changes the server needs adminRoleId. Read-only commands are open
 *      to the guild, which is why they must stay genuinely read-only.
 *   3. GUILD ALLOWLIST. The bot ignores every other guild, so being added to a second server grants
 *      nothing. Channel scoping is the relay module's own gate.
 *   4. SANITISER. Relay text is stripped of quotes, semicolons, newlines and colour codes before it
 *      is interpolated into `set gf_say "..."` (lib/panel.js). Without that, a chat message ends the
 *      quoted value and chains its own rcon command.
 * Every accepted command is logged with the invoking Discord user, so the audit trail exists in
 * storage\t5\logs\services\GF-DiscordBot.log.
 */

const cfg = require('./lib/config.js').load();

const log = (...a) => console.log(`[${new Date().toISOString()}]`, ...a);

const rest  = require('./lib/rest.js')(cfg.token, log);
const panel = require('./lib/panel.js')(cfg);
const cache = require('./lib/cache.js');

// ── rate limiting ──────────────────────────────────────────────────────────────────────────────
// Cheap per-user bucket. A relay channel is a megaphone into a live match; without this one person
// can flood every player's screen faster than an admin can react.
const buckets = new Map();
function allow(userId, max = 5, windowMs = 10000) {
  const now = Date.now();
  const b = (buckets.get(userId) || []).filter((t) => now - t < windowMs);
  if (b.length >= max) { buckets.set(userId, b); return false; }
  b.push(now); buckets.set(userId, b);
  return true;
}

// ── gateway state ──────────────────────────────────────────────────────────────────────────────
let ws = null, heartbeat = null, seq = null, sessionId = null, resumeUrl = null, acked = true, backoff = 1000;
function send(op, d) { if (ws && ws.readyState === 1) ws.send(JSON.stringify({ op, d })); }

// ── features ───────────────────────────────────────────────────────────────────────────────────
// ⚠ Assembled AFTER `log` and the transports: `log` is a const arrow, so building a module above it
// hits the temporal dead zone and the bot dies on require.
const ctx = {
  cfg, log, rest, panel, cache, allow,
  // ⚠ A NARROW capability, deliberately not the raw gateway `send`. A module holding send() could
  // fire op 2 or op 6 and tear the session down for every other feature; this one can only ever set
  // our own presence.
  setPresence: (payload) => send(3, payload),
};

const FEATURES = [
  require('./features/ops.js')(ctx),
  require('./features/relay.js')(ctx),
  require('./features/voice_tools.js')(ctx),
  require('./features/moderation.js')(ctx),
  require('./features/automod.js')(ctx),
  require('./features/message_log.js')(ctx),
  require('./features/member_log.js')(ctx),
  require('./features/voice_log.js')(ctx),
  require('./features/presence.js')(ctx),
];
const ENABLED = FEATURES.filter((f) => f.enabled);

// GUILDS(1) is always required: GUILD_CREATE is what seeds the channel and voice caches, and
// without it the bot is deaf to the guild it exists to serve.
const INTENTS = 1 | ENABLED.reduce((a, f) => a | (f.intents || 0), 0);

// Merge the command tables. ⚠ A duplicate name would mean one module silently shadowing another's
// command, and the loser would be whichever loaded first - a bug that only surfaces when someone
// runs the wrong thing. Refuse to start instead.
const COMMANDS = {};
for (const f of ENABLED) {
  for (const [name, c] of Object.entries(f.commands || {})) {
    if (COMMANDS[name]) {
      console.error(`FATAL: /${name} is defined by both ${COMMANDS[name].__owner} and ${f.name}`);
      process.exit(1);
    }
    COMMANDS[name] = Object.assign({ __owner: f.name }, c);
  }
}

log('features: ' + (FEATURES.map((f) => f.name + (f.enabled ? '' : ' (off)')).join(', ') || 'none'));
log(`intents 0x${INTENTS.toString(16)}, ${Object.keys(COMMANDS).length} command(s), permissions wanted: ` +
    ([...new Set(ENABLED.flatMap((f) => f.permissions || []))].join(', ') || 'none beyond default'));

async function registerCommands() {
  const payload = Object.entries(COMMANDS).map(([name, c]) => ({
    name, description: c.description, options: c.options || [],
  }));
  try {
    await rest.putCommands(cfg.applicationId, cfg.guildId, payload);
    log(`registered ${payload.length} slash commands`);
    return true;
  } catch (e) {
    log('command registration FAILED:', e.message);
    return false;
  }
}

// ── interactions ───────────────────────────────────────────────────────────────────────────────
async function respond(interaction, result) {
  // Deferred first: Discord requires a reply within 3s and an rcon round trip through the panel's
  // paced queue can exceed that. Ephemeral so ops chatter does not fill the channel.
  await rest.interaction.defer(interaction.id, interaction.token);
  const value = await result;
  // A command may return a plain string (most of them) or a full payload when it wants a card.
  const payload = typeof value === 'string' ? { content: value.slice(0, 1900) } : value;
  await rest.interaction.edit(cfg.applicationId, interaction.token, payload)
    .catch((e) => log('interaction reply failed:', e.message));
}

async function onInteraction(d) {
  if (d.guild_id !== cfg.guildId) return;                    // gate 3: guild allowlist
  const name = d.data && d.data.name;
  const cmd = COMMANDS[name];
  if (!cmd) return;
  const user = (d.member && d.member.user) || d.user || {};
  const roles = (d.member && d.member.roles) || [];
  const who = user.username || user.id;

  if (cmd.admin && !roles.includes(cfg.adminRoleId)) {       // gate 2: role
    log(`DENIED /${name} to ${who} (not admin)`);
    return respond(d, 'You do not have permission for that.');
  }
  if (!allow(user.id)) return respond(d, 'Slow down a moment.');

  const opts = {};
  for (const o of (d.data.options || [])) opts[o.name] = o.value;
  log(`/${name} by ${who}${Object.keys(opts).length ? ' ' + JSON.stringify(opts) : ''}`);
  return respond(d, Promise.resolve()
    .then(() => cmd.run(opts, who))
    .catch((e) => `Error: ${e.message}`));
}

// ── the router ─────────────────────────────────────────────────────────────────────────────────
function dispatch(t, d) {
  // ⚠ The CORE cache updates FIRST, before any feature sees the event, so shared state is identical
  // whatever is enabled. It memoises per-event derived values (the voice transition) on the event
  // object, so a feature reading the same thing afterwards gets the same answer rather than the
  // post-update one.
  try { cache.observe(t, d); } catch (e) { log(`cache failed on ${t}:`, e.message); }

  if (t === 'INTERACTION_CREATE') onInteraction(d).catch((e) => log('interaction error:', e.message));

  // A throwing module must never kill the gateway loop, hence the per-module guard.
  for (const f of ENABLED) {
    const h = f.on && f.on[t];
    if (!h) continue;
    try { h(d); } catch (e) { log(`${f.name} failed on ${t}: ${e.message}`); }
  }
}

// ── gateway ────────────────────────────────────────────────────────────────────────────────────
function connect(resume = false) {
  const url = (resume && resumeUrl) ? `${resumeUrl}/?v=10&encoding=json` : 'wss://gateway.discord.gg/?v=10&encoding=json';
  ws = new WebSocket(url);

  ws.addEventListener('open', () => log(resume ? 'gateway reconnecting (resume)' : 'gateway connecting'));

  ws.addEventListener('message', (ev) => {
    const p = JSON.parse(ev.data);
    if (p.s) seq = p.s;
    switch (p.op) {
      case 10: // HELLO
        clearInterval(heartbeat);
        heartbeat = setInterval(() => {
          // A missed ACK means a zombied connection: the socket looks open and no events arrive.
          // Discord's documented remedy is to tear it down and RESUME, not to keep beating.
          if (!acked) { log('heartbeat not acked - reconnecting'); try { ws.close(4000); } catch {} return; }
          acked = false; send(1, seq);
        }, p.d.heartbeat_interval);
        if (resume && sessionId) send(6, { token: cfg.token, session_id: sessionId, seq });
        else send(2, { token: cfg.token, intents: INTENTS, properties: { os: 'windows', browser: 'gf', device: 'gf' } });
        break;
      case 11: acked = true; break;
      case 7:  log('gateway asked us to reconnect'); try { ws.close(4000); } catch {} break;
      case 9:  // INVALID_SESSION: d===true means it is resumable
        log('invalid session - re-identifying');
        sessionId = null;
        setTimeout(() => { try { ws.close(4000); } catch {} }, 1500);
        break;
      case 0:
        if (p.t === 'READY') {
          sessionId = p.d.session_id; resumeUrl = p.d.resume_gateway_url; backoff = 1000;
          log(`ready as ${p.d.user.username} - guild ${cfg.guildId}, relay ${cfg.relayChannelId || '(off)'}`);
        } else if (p.t === 'RESUMED') { backoff = 1000; log('gateway resumed'); }
        dispatch(p.t, p.d);
        break;
    }
  });

  ws.addEventListener('close', (ev) => {
    clearInterval(heartbeat);
    // 4004 bad token, 4014 disallowed intent: retrying cannot fix either, and a hot loop against
    // Discord earns a ban. Die loudly and let the task's restart policy surface it.
    if (ev.code === 4004 || ev.code === 4014) {
      log(`FATAL gateway close ${ev.code} - ${ev.code === 4004 ? 'bad token' : 'a requested intent is not enabled in the Developer Portal'}`);
      process.exit(1);
    }
    const wait = Math.min(backoff, 60000);
    log(`gateway closed (${ev.code}) - reconnecting in ${wait}ms`);
    setTimeout(() => connect(Boolean(sessionId)), wait);
    backoff = Math.min(backoff * 2, 60000);
  });

  ws.addEventListener('error', (e) => log('gateway error:', e.message || e.type));
}

// ── main ───────────────────────────────────────────────────────────────────────────────────────
// ⚠ require.main guard: without it, `require('bot.js')` from a test opens a gateway connection and
// fires a real command registration. The test suite exists to check the sanitiser and the command
// whitelist - importing this file must have NO side effects.
if (require.main === module) {
  (async () => {
    if (process.argv.includes('--register')) { process.exit((await registerCommands()) ? 0 : 1); }
    if (!panel.rconPassword()) log('WARNING: no rcon password found - game commands will fail');
    await registerCommands();   // idempotent, and keeps the command list in step with the modules
    connect(false);
  })();
}

module.exports = { COMMANDS, FEATURES, ENABLED, INTENTS };
