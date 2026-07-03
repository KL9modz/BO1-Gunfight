'use strict';
// GF Join Notifier — runs ON the VPS, pushes a phone notification via ntfy.sh on player
// activity. Zero npm dependencies: built-in dgram (RCON UDP) + https (ntfy POST) only,
// matching tools/rcon/server.js.
//
// Events:
//   • JOIN            a human joins (bots excluded)                    → default priority
//   • FIRST / active  first human joins an EMPTY server                → high priority
//   • LEAVE           a human leaves            (notifyLeaves)          → low priority
//   • EMPTY           last human leaves, server now 0                  (notifyEmpty)  low
//   • HEARTBEAT       periodic "still alive — N online"  (heartbeatMins) min priority
//
// It polls `status` over loopback RCON, diffs the human-player set by GUID, and POSTs to
// your ntfy topic. Runs 24/7 independently of the browser RCON panel.
//
// Config: env vars override config.json (next to this file) override defaults.
// The rcon_password defaults to the value read out of ../../../../dedicated.cfg.
//
// Run:   node join-notify.js
// See README.md in this folder for the scheduled-task (auto-start) setup.

const dgram = require('dgram');
const http  = require('http');
const https = require('https');
const fs    = require('fs');
const path  = require('path');

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// ─── Config ─────────────────────────────────────────────────────────────────
function readRconPwFromCfg() {
  try {
    // this file: storage/t5/mods/mp_gunfight/tools/notify/join-notify.js → 4 up = storage/t5
    const cfgPath = path.resolve(__dirname, '..', '..', '..', '..', 'dedicated.cfg');
    const t = fs.readFileSync(cfgPath, 'utf8');
    const m = t.match(/^\s*set[as]?\s+"?rcon_password"?\s+"([^"]*)"/im);
    return m ? m[1] : '';
  } catch (_) { return ''; }
}

const asBool = (v, def) =>
  v == null ? def : (v === true || String(v).toLowerCase() === 'true' || String(v) === '1');

function loadConfig() {
  let fileCfg = {};
  const cfgFile = path.join(__dirname, 'config.json');
  if (fs.existsSync(cfgFile)) {
    try { fileCfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8')); }
    catch (e) { console.error('[cfg] bad config.json:', e.message); }
  }
  const e = process.env;
  const pick = (envKey, fileKey, def) =>
    (e[envKey] != null && e[envKey] !== '') ? e[envKey]
    : (fileCfg[fileKey] != null ? fileCfg[fileKey] : def);

  return {
    host:            pick('GF_HOST', 'host', '127.0.0.1'),
    port:            parseInt(pick('GF_PORT', 'port', 28960), 10),
    password:        pick('GF_RCON_PW', 'password', '') || readRconPwFromCfg(),
    ntfyServer:      String(pick('GF_NTFY_SERVER', 'ntfyServer', 'https://ntfy.sh')).replace(/\/+$/, ''),
    ntfyTopic:       pick('GF_NTFY_TOPIC', 'ntfyTopic', ''),
    ntfyToken:       pick('GF_NTFY_TOKEN', 'ntfyToken', ''),   // optional (auth-protected topics)
    pollMs:          parseInt(pick('GF_POLL_MS', 'pollMs', 12000), 10),
    notifyLeaves:    asBool(pick('GF_NOTIFY_LEAVES', 'notifyLeaves', false), false),
    notifyFirstJoin: asBool(pick('GF_NOTIFY_FIRST', 'notifyFirstJoin', true), true),
    notifyEmpty:     asBool(pick('GF_NOTIFY_EMPTY', 'notifyEmpty', false), false),
    heartbeatMins:   parseInt(pick('GF_HEARTBEAT_MINS', 'heartbeatMins', 0), 10),
    serverName:      pick('GF_SERVER_NAME', 'serverName', 'Gunfight'),
    quiet:           asBool(pick('GF_QUIET_START', 'quietStart', false), false),
  };
}

// ─── RCON (UDP OOB) ─────────────────────────────────────────────────────────
const OOB = Buffer.from([0xff, 0xff, 0xff, 0xff]);

function sendRcon(host, port, password, command, collectMs = 350, hardMs = 3000) {
  return new Promise((resolve, reject) => {
    const sock = dgram.createSocket('udp4');
    const chunks = [];
    let collectTimer, mainTimer;
    const cleanup = () => { clearTimeout(mainTimer); clearTimeout(collectTimer); try { sock.close(); } catch (_) {} };
    const finish  = () => { cleanup(); resolve(Buffer.concat(chunks)); };
    mainTimer = setTimeout(() => {
      if (chunks.length) finish();
      else { cleanup(); reject(new Error('timeout')); }
    }, hardMs);
    sock.on('message', (msg) => { chunks.push(msg); clearTimeout(collectTimer); collectTimer = setTimeout(finish, collectMs); });
    sock.on('error', (err) => { cleanup(); reject(err); });
    sock.bind(0, () => {
      const pkt = Buffer.concat([OOB, Buffer.from(`rcon ${password} ${command}`, 'utf8')]);
      sock.send(pkt, 0, pkt.length, port, host, (err) => { if (err) { cleanup(); reject(err); } });
    });
  });
}

function parseRconResponse(buf) {
  const s = buf.toString('utf8');
  const nl = s.indexOf('\n');
  return nl === -1 ? s.slice(4) : s.slice(nl + 1).trimEnd();
}

function stripColors(s) { return String(s).replace(/\^[0-9a-zA-Z]/g, '').trim(); }

// Parse map/gametype + the human players out of `status`. Bot = guid "0" AND addr "unknown".
function parseStatus(text) {
  const lines = text.split('\n');
  const out = { map: '', gametype: '', players: [] };
  for (const raw of lines) {
    const line = raw.trim();
    let m = line.match(/^map:\s*(.+)/i);      if (m) { out.map = stripColors(m[1]); continue; }
    m = line.match(/^gametype:\s*(.+)/i);      if (m) { out.gametype = stripColors(m[1]); continue; }
  }
  const sepIdx = lines.findIndex(l => /^---/.test(l.trim()));
  if (sepIdx !== -1) {
    for (let i = sepIdx + 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;
      const p = line.split(/\s+/);
      if (p.length < 7 || !/^\d+$/.test(p[0])) continue;
      const isBot = p[3] === '0' && p[6] === 'unknown';
      out.players.push({ num: parseInt(p[0], 10), guid: p[3], name: stripColors(p[4]), addr: p[6], bot: isBot });
    }
  }
  return out;
}

// ─── ntfy push ──────────────────────────────────────────────────────────────
// Player name goes in the BODY (utf8-safe); the Title header stays plain ASCII so a
// fancy player name can never break HTTP header encoding.
function sendNtfy(cfg, { title, message, priority, tags }) {
  return new Promise((resolve) => {
    if (!cfg.ntfyTopic) { console.error('[ntfy] no topic configured — cannot send'); return resolve(false); }
    let url;
    try { url = new URL(cfg.ntfyServer + '/' + cfg.ntfyTopic); }
    catch (e) { console.error('[ntfy] bad server URL:', e.message); return resolve(false); }
    const body = Buffer.from(message || '', 'utf8');
    const headers = { 'Content-Type': 'text/plain; charset=utf-8', 'Content-Length': body.length };
    if (title)    headers['Title']    = title;
    if (priority) headers['Priority'] = String(priority);
    if (tags)     headers['Tags']     = tags;
    if (cfg.ntfyToken) headers['Authorization'] = 'Bearer ' + cfg.ntfyToken;
    const lib = url.protocol === 'http:' ? http : https;
    const req = lib.request(url, { method: 'POST', headers }, (res) => {
      res.resume();
      res.on('end', () => {
        const ok = res.statusCode >= 200 && res.statusCode < 300;
        if (!ok) console.error('[ntfy] HTTP ' + res.statusCode);
        resolve(ok);
      });
    });
    req.on('error', (e) => { console.error('[ntfy] error:', e.message); resolve(false); });
    req.write(body); req.end();
  });
}

// ─── Poll loop ──────────────────────────────────────────────────────────────
function log(msg) {
  const t = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`[${t}] ${msg}`);
}
function pKey(p) { return (p.guid && p.guid !== '0') ? 'g:' + p.guid : 'n:' + p.name; }

let known = null;      // Map(key -> name); null until first successful poll seeds it
let lastOnline = 0;    // last human count (for heartbeat)
let lastCtx = '';      // last "map / gametype" string (for message context)

async function tick(cfg) {
  let st;
  try {
    st = parseStatus(parseRconResponse(await sendRcon(cfg.host, cfg.port, cfg.password, 'status')));
  } catch (e) {
    log('status poll failed (' + e.message + ') — keeping last baseline');
    return;   // don't reset baseline on a transient miss → no false joins on recovery
  }
  const real = st.players.filter(p => !p.bot);
  const cur = new Map(real.map(p => [pKey(p), p.name]));
  const ctx = st.map ? (st.map + (st.gametype ? ' / ' + st.gametype : '')) : '';
  const ctxSuffix = ctx ? '  —  ' + ctx : '';
  lastOnline = cur.size;
  lastCtx = ctx;

  if (known === null) {                     // seed silently — no alerts for who's already on
    known = cur;
    log('baseline seeded: ' + real.length + ' human player(s) online' + (ctx ? '  [' + ctx + ']' : ''));
    return;
  }

  const wasEmpty  = known.size === 0;
  const newJoins  = [...cur].filter(([k]) => !known.has(k));
  const departed  = [...known].filter(([k]) => !cur.has(k));

  for (let i = 0; i < newJoins.length; i++) {
    const nm = newJoins[i][1];
    const first = wasEmpty && i === 0;      // first human onto a previously empty server
    if (first) {
      log('FIRST ' + nm + '  (server now active, ' + cur.size + ' online)');
      if (cfg.notifyFirstJoin) {
        await sendNtfy(cfg, {
          title: cfg.serverName + ' — server now active',
          message: nm + ' joined an empty server' + ctxSuffix,
          priority: 'high', tags: 'green_circle,bust_in_silhouette',
        });
        continue;   // this player already announced by the "active" alert
      }
    }
    log('JOIN  ' + nm + '  (' + cur.size + ' online)');
    await sendNtfy(cfg, {
      title: cfg.serverName + ' — player joined',
      message: nm + ' joined  (' + cur.size + ' online)' + ctxSuffix,
      priority: 'default', tags: 'bust_in_silhouette',
    });
  }

  if (cfg.notifyLeaves) {
    for (const [, nm] of departed) {
      log('LEAVE ' + nm + '  (' + cur.size + ' online)');
      await sendNtfy(cfg, {
        title: cfg.serverName + ' — player left',
        message: nm + ' left  (' + cur.size + ' online)',
        priority: 'low', tags: 'wave',
      });
    }
  }

  // Server transitioned to empty (last human left).
  if (cfg.notifyEmpty && cur.size === 0 && known.size > 0) {
    log('EMPTY server now has 0 players');
    await sendNtfy(cfg, {
      title: cfg.serverName + ' — server empty',
      message: 'Last player left — 0 online' + ctxSuffix,
      priority: 'low', tags: 'zzz',
    });
  }

  known = cur;
}

async function main() {
  const cfg = loadConfig();
  log('GF Join Notifier starting');
  log(`  server     ${cfg.host}:${cfg.port}`);
  log(`  rcon pw    ${cfg.password ? '(' + cfg.password.length + ' chars)' : 'MISSING'}`);
  log(`  ntfy       ${cfg.ntfyServer}/${cfg.ntfyTopic || '(NO TOPIC SET)'}`);
  log(`  poll       ${cfg.pollMs}ms   leaves=${cfg.notifyLeaves}  firstJoin=${cfg.notifyFirstJoin}  empty=${cfg.notifyEmpty}`);
  log(`  heartbeat  ${cfg.heartbeatMins > 0 ? cfg.heartbeatMins + ' min' : 'off'}`);

  if (!cfg.ntfyTopic) {
    console.error('\nFATAL: no ntfy topic set. Put your topic in config.json (ntfyTopic) or env GF_NTFY_TOPIC.\n');
    process.exit(1);
  }
  if (!cfg.password) {
    console.error('\nFATAL: no rcon_password (not in config/env and not found in dedicated.cfg).\n');
    process.exit(1);
  }

  if (!cfg.quiet) {
    await sendNtfy(cfg, {
      title: cfg.serverName + ' — notifier online',
      message: 'Join notifier started and watching the server.',
      priority: 'low', tags: 'satellite_antenna',
    });
  }

  let lastHeartbeat = Date.now();

  // Loop forever. tick() awaits its own ntfy sends, so overlapping ticks can't interleave.
  for (;;) {
    await tick(cfg);

    if (cfg.heartbeatMins > 0 && Date.now() - lastHeartbeat >= cfg.heartbeatMins * 60000) {
      lastHeartbeat = Date.now();
      const msg = 'Watcher alive — ' + lastOnline + ' player(s) online' + (lastCtx ? '  —  ' + lastCtx : '');
      log('HEARTBEAT ' + msg);
      await sendNtfy(cfg, {
        title: cfg.serverName + ' — heartbeat',
        message: msg,
        priority: 'min', tags: 'green_heart',
      });
    }

    await sleep(cfg.pollMs);
  }
}

process.on('unhandledRejection', (e) => log('unhandledRejection: ' + (e && e.message)));
main();
