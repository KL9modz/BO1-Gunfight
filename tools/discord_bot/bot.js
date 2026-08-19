'use strict';
/*
 * GF-DiscordBot - slash commands for ops, and a Discord -> in-game chat relay.
 *
 *   node bot.js            (normally run by the GF-DiscordBot scheduled task)
 *   node bot.js --register (register/refresh the slash commands, then exit)
 *
 * ── WHY ZERO DEPENDENCIES ──────────────────────────────────────────────────────────────────────
 * discord.js is the obvious choice and is deliberately NOT used. This process can restart the game
 * server and speak to every player, and it runs on the box that holds the rcon password - so a
 * transitive dependency tree is a supply-chain surface aimed at the worst possible target. Node 24
 * ships native WebSocket and fetch, and the slice of the gateway needed here is small: identify,
 * heartbeat, resume, and two dispatch events. The panel next door is dependency-free for the same
 * reason. Cost, stated honestly: reconnect/resume logic is ours to get right (see connect()).
 *
 * ── HOW IT TALKS TO THE GAME ───────────────────────────────────────────────────────────────────
 * ⚠ ONLY through the panel's /api/rcon on loopback. The panel is the single rcon pacer on this box
 * (Plutonium answers ~1 reply per 0.7s and silently drops faster sends), and a second poller is
 * the one thing the project rule forbids. The bot therefore holds no rcon socket and no schedule.
 *
 * ── SECURITY MODEL ─────────────────────────────────────────────────────────────────────────────
 * A Discord message is UNTRUSTED INPUT that reaches an rcon console. Four gates, all of them load-
 * bearing, none of them optional:
 *   1. VERB WHITELIST. Commands map to fixed templates - there is no passthrough. A caller cannot
 *      reach a dvar this file does not name.
 *   2. ROLE GATE. Anything that changes the server needs adminRoleId. Read-only commands are open
 *      to the guild, which is why they must stay genuinely read-only.
 *   3. GUILD + CHANNEL ALLOWLIST. The bot ignores every other guild and every other channel, so
 *      being added to a second server grants nothing.
 *   4. SANITISER. Relay text is stripped of quotes, semicolons, newlines and colour codes before it
 *      is interpolated into `set gf_say "..."`. Without that, a chat message ends the quoted value
 *      and chains its own rcon command - the same injection the panel's savecfg guards against.
 * Every accepted command is logged with the invoking Discord user, so the audit trail exists in
 * storage\t5\logs\services\GF-DiscordBot.log.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');

const API = 'https://discord.com/api/v10';
// GUILDS(1) | GUILD_MESSAGES(1<<9) | MESSAGE_CONTENT(1<<15). MESSAGE_CONTENT is a PRIVILEGED intent
// and must be enabled in the Developer Portal, or the gateway closes with 4014 on identify. It is
// needed only by the relay: slash commands carry their own payload.
const INTENTS = 1 | (1 << 9) | (1 << 15);

// ── config ─────────────────────────────────────────────────────────────────────────────────────
const CFG_PATH = path.join(__dirname, 'config.local.json');
if (!fs.existsSync(CFG_PATH)) {
  console.error(`FATAL: ${CFG_PATH} not found - copy config.example.json and fill it in.`);
  process.exit(1);
}
const cfg = JSON.parse(fs.readFileSync(CFG_PATH, 'utf8'));
for (const k of ['token', 'applicationId', 'guildId', 'adminRoleId']) {
  if (!cfg[k]) { console.error(`FATAL: config.local.json is missing "${k}"`); process.exit(1); }
}
const PANEL_PORT = cfg.panelPort || 3000;
const RCON_HOST  = cfg.rconHost  || '127.0.0.1';
const RCON_PORT  = cfg.rconPort  || 28960;

// The rcon password is READ FROM dedicated.cfg, never stored here: one copy of a credential is one
// place to rotate, and tools/rotate_secrets.ps1 already knows about that file. Re-read per call so
// a rotation lands without restarting the bot.
function rconPassword() {
  const t5 = process.env.LOCALAPPDATA
    ? path.join(process.env.LOCALAPPDATA, 'Plutonium', 'storage', 't5')
    : null;
  const cfgFile = cfg.dedicatedCfgPath || (t5 && path.join(t5, 'dedicated.cfg'));
  try {
    const m = fs.readFileSync(cfgFile, 'utf8').match(/^\s*set\s+rcon_password\s+"?([^"\r\n]+)"?/mi);
    return m ? m[1].trim() : '';
  } catch { return ''; }
}

const log = (...a) => console.log(`[${new Date().toISOString()}]`, ...a);

// ── the panel bridge ───────────────────────────────────────────────────────────────────────────
function panelRcon(command, priority = true) {
  const body = JSON.stringify({ host: RCON_HOST, port: RCON_PORT, password: rconPassword(), command, priority });
  return new Promise((resolve) => {
    const req = http.request({
      host: '127.0.0.1', port: PANEL_PORT, path: '/api/rcon', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      timeout: 15000,
    }, (res) => {
      let data = '';
      res.on('data', (c) => data += c);
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve({ ok: false, error: 'bad panel reply' }); } });
    });
    req.on('error', (e) => resolve({ ok: false, error: e.message }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, error: 'panel timeout' }); });
    req.end(body);
  });
}

// ── sanitising ─────────────────────────────────────────────────────────────────────────────────
// ⚠ THE INJECTION BOUNDARY. The result is interpolated into `set gf_say "<here>"`, so a `"` ends
// the value and a `;` starts a new rcon command - that pair is the whole exploit. Colour codes are
// stripped because ^1 etc. would let anyone paint the server messages, and mentions are stripped
// because they mean nothing in game and read as noise. Newlines would split the rcon line.
function sanitiseForGame(s, max = 120) {
  return String(s || '')
    .replace(/<@!?\d+>|<@&\d+>|<#\d+>/g, '')      // mentions: meaningless in game
    .replace(/@(everyone|here)/gi, '')
    .replace(/\^\d/g, '')                          // Treyarch colour codes
    .replace(/[";\r\n]/g, ' ')                     // THE injection characters
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

// ── slash commands ─────────────────────────────────────────────────────────────────────────────
// Each entry is a FIXED template. `run` returns the text to show; nothing here accepts a
// caller-supplied rcon string, which is what makes the whitelist a whitelist.
const MAPS = {
  array: 'mp_array', cracked: 'mp_cracked', crisis: 'mp_crisis', firingrange: 'mp_firingrange',
  grid: 'mp_duga', hanoi: 'mp_hanoi', havana: 'mp_cairo', jungle: 'mp_havoc', launch: 'mp_cosmodrome',
  nuketown: 'mp_nuked', radiation: 'mp_radiation', summit: 'mp_mountain', villa: 'mp_villa',
  wmd: 'mp_russianbase', berlinwall: 'mp_berlinwall2', discovery: 'mp_discovery', kowloon: 'mp_kowloon',
  stadium: 'mp_stadium', convoy: 'mp_gridlock', hotel: 'mp_hotel', stockpile: 'mp_outskirts',
  zoo: 'mp_zoo', drivein: 'mp_drivein', hangar18: 'mp_area51', hazard: 'mp_golfcourse', silo: 'mp_silo',
};

const COMMANDS = {
  status: {
    admin: false, description: 'Who is on, which map, what score',
    run: async () => {
      const st = await panelRcon('gf_state', false);
      const sv = await panelRcon('status', false);
      if (!st.ok && !sv.ok) return 'Server did not answer (is it up?).';
      const f = (st.response || '').match(/gf_state.*?"([^"]*)"/);
      const parts = f ? f[1].split(':') : [];
      const map = (sv.response || '').match(/map:\s*(\S+)/i);
      const humans = ((sv.response || '').match(/\n\s*\d+\s+/g) || []).length;
      return parts.length >= 5
        ? `**${map ? map[1] : 'unknown map'}** - round ${parts[2]}, Allies ${parts[0]} - ${parts[1]} Axis, ${humans} connected`
        : `**${map ? map[1] : 'unknown map'}** - ${humans} connected`;
    },
  },
  players: {
    admin: false, description: 'List the players currently connected',
    run: async () => {
      const r = await panelRcon('status', false);
      if (!r.ok) return 'Server did not answer.';
      const rows = (r.response || '').split(/\r?\n/).slice(3)
        .map((l) => l.match(/^\s*\d+\s+(-?\d+)\s+\S+\s+(.+?)\s{2,}/))
        .filter(Boolean)
        .map((m) => `\`${m[2].replace(/\^\d/g, '').trim()}\` (${m[1]})`);
      return rows.length ? `**${rows.length} connected**\n${rows.join('\n')}` : 'Nobody is on right now.';
    },
  },
  say: {
    admin: true, description: 'Send a message to everyone in game',
    options: [{ name: 'message', description: 'What to say', type: 3, required: true }],
    run: async (opts, user) => {
      const msg = sanitiseForGame(`${user}: ${opts.message}`);
      if (!msg) return 'Nothing left to send after sanitising.';
      // ONE chained write: two packets can race on the paced queue and print an empty message.
      const r = await panelRcon(`set gf_say "${msg}";set gf_cmd saymsg`);
      return r.ok ? `Sent: \`${msg}\`` : `Failed: ${r.error || 'no reply'}`;
    },
  },
  map: {
    admin: true, description: 'Change the map',
    options: [{ name: 'name', description: 'Map name', type: 3, required: true,
                choices: Object.keys(MAPS).slice(0, 25).map((k) => ({ name: k, value: k })) }],
    run: async (opts) => {
      const id = MAPS[String(opts.name).toLowerCase()];
      if (!id) return `Unknown map. Known: ${Object.keys(MAPS).join(', ')}`;
      const r = await panelRcon(`map ${id}`);
      return r.ok ? `Changing map to **${opts.name}** (${id}).` : `Failed: ${r.error || 'no reply'}`;
    },
  },
  restart: {
    admin: true, description: 'Restart the current match (same map, scores reset)',
    run: async () => {
      const r = await panelRcon('set gf_cmd matchrestart');
      return r.ok ? 'Match restarting.' : `Failed: ${r.error || 'no reply'}`;
    },
  },
  pause:  { admin: true, description: 'Pause the match',
            run: async () => (await panelRcon('set gf_cmd pause')).ok ? 'Match paused.' : 'Failed.' },
  resume: { admin: true, description: 'Resume the match',
            run: async () => (await panelRcon('set gf_cmd resume')).ok ? 'Match resumed.' : 'Failed.' },
};

async function registerCommands() {
  const payload = Object.entries(COMMANDS).map(([name, c]) => ({
    name, description: c.description, options: c.options || [],
  }));
  const res = await fetch(`${API}/applications/${cfg.applicationId}/guilds/${cfg.guildId}/commands`, {
    method: 'PUT',
    headers: { Authorization: `Bot ${cfg.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  // GUILD commands, not global: guild registration is instant, global takes up to an hour to
  // propagate - and this bot is only ever meant to serve one guild anyway.
  log(res.ok ? `registered ${payload.length} slash commands` : `command registration FAILED: ${res.status} ${await res.text()}`);
  return res.ok;
}

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

// ── gateway ────────────────────────────────────────────────────────────────────────────────────
let ws = null, heartbeat = null, seq = null, sessionId = null, resumeUrl = null, acked = true, backoff = 1000;

function send(op, d) { if (ws && ws.readyState === 1) ws.send(JSON.stringify({ op, d })); }

async function respond(interaction, content) {
  // Deferred first: Discord requires a reply within 3s and an rcon round trip through the paced
  // queue can exceed that. Ephemeral (flags 64) so ops chatter does not fill the channel.
  await fetch(`${API}/interactions/${interaction.id}/${interaction.token}/callback`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 5, data: { flags: 64 } }),
  }).catch(() => {});
  const text = await content;
  await fetch(`${API}/webhooks/${cfg.applicationId}/${interaction.token}/messages/@original`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: String(text).slice(0, 1900) }),
  }).catch((e) => log('interaction reply failed:', e.message));
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
  return respond(d, cmd.run(opts, who).catch((e) => `Error: ${e.message}`));
}

async function onMessage(d) {
  if (!cfg.relayChannelId || d.channel_id !== cfg.relayChannelId) return;   // gate 3: channel
  if (!d.content || (d.author && d.author.bot)) return;
  if (d.guild_id !== cfg.guildId) return;
  const roles = (d.member && d.member.roles) || [];
  // relayRoleId is optional: unset means anyone in that channel can talk to the server, which is a
  // deliberate choice for a private channel and a bad one for a public server.
  if (cfg.relayRoleId && !roles.includes(cfg.relayRoleId) && !roles.includes(cfg.adminRoleId)) return;
  if (!allow(d.author.id)) return;

  const nick = (d.member && d.member.nick) || d.author.global_name || d.author.username;
  const line = sanitiseForGame(`[D] ${nick}: ${d.content}`);
  if (!line) return;
  const r = await panelRcon(`set gf_say "${line}";set gf_cmd saymsg`);
  log(`relay ${r.ok ? 'ok' : 'FAILED'}: ${line}`);
}

function connect(resume = false) {
  const url = (resume && resumeUrl) ? `${resumeUrl}/?v=10&encoding=json` : 'wss://gateway.discord.gg/?v=10&encoding=json';
  ws = new WebSocket(url);

  ws.addEventListener('open', () => log(resume ? 'gateway reconnecting (resume)' : 'gateway connecting'));

  ws.addEventListener('message', async (ev) => {
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
        else if (p.t === 'INTERACTION_CREATE') { onInteraction(p.d).catch((e) => log('interaction error:', e.message)); }
        else if (p.t === 'MESSAGE_CREATE')     { onMessage(p.d).catch((e) => log('relay error:', e.message)); }
        break;
    }
  });

  ws.addEventListener('close', (ev) => {
    clearInterval(heartbeat);
    // 4004 bad token, 4014 disallowed intent: retrying cannot fix either, and a hot loop against
    // Discord earns a ban. Die loudly and let the task's restart policy surface it.
    if (ev.code === 4004 || ev.code === 4014) {
      log(`FATAL gateway close ${ev.code} - ${ev.code === 4004 ? 'bad token' : 'MESSAGE CONTENT intent not enabled in the Developer Portal'}`);
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
    if (!rconPassword()) log('WARNING: no rcon password found - game commands will fail');
    await registerCommands();   // idempotent, and keeps the command list in step with this file
    connect(false);
  })();
}

module.exports = { sanitiseForGame, COMMANDS, MAPS };
