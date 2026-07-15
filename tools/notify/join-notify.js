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
    geoLookup:       asBool(pick('GF_GEO_LOOKUP', 'geoLookup', true), true),
  };
}

// ─── Ignore list (shared with GF-StatusService) ─────────────────────────────
// tools/ignore.local.json — the same file tools/ignore_list.ps1 reads. An ignored player is
// treated as NOT CONNECTED here: no JOIN/LEAVE push, and they don't count toward "N online",
// "server now active" or "server empty" — so the owner idling on his own server can't suppress
// the high-priority alert that fires when a real player shows up. Re-read on mtime change, so
// an edit lands within one poll with no restart. Missing/bad file = ignore nobody.
const IGNORE_FILE = path.resolve(__dirname, '..', 'ignore.local.json');
let ignoreCache = { guids: [], names: [] };
let ignoreStamp = null;   // mtimeMs of the loaded file; 0 = absent

function getIgnore() {
  let stamp = 0;
  try { stamp = fs.statSync(IGNORE_FILE).mtimeMs; } catch (_) { stamp = 0; }
  if (stamp === ignoreStamp) return ignoreCache;
  ignoreStamp = stamp;
  let guids = [], names = [];
  if (stamp !== 0) {
    try {
      const j = JSON.parse(fs.readFileSync(IGNORE_FILE, 'utf8'));
      guids = (j.guids || []).map(String).map(s => s.trim()).filter(Boolean);
      names = (j.names || []).map(String).map(s => s.trim().toLowerCase()).filter(Boolean);
    } catch (e) { console.error('[ignore] bad ' + IGNORE_FILE + ':', e.message); }
  }
  ignoreCache = { guids, names };
  return ignoreCache;
}

function isIgnored(ign, guid, name) {
  const g = String(guid || '').trim();
  if (g && g !== '0' && ign.guids.includes(g)) return true;   // guid 0 = still connecting: identifies nobody
  const n = String(name || '').trim().toLowerCase();
  return !!(n && ign.names.includes(n));
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

// Parse map/gametype + the human players out of `status`. Bot = a POSITIVE match on the ADDRESS
// column (guid 0 at a non-routable address); a row we can't read is null, NOT a bot — see below.
// Player names CAN contain spaces (e.g. the bot "MCG Gordon"), so name is not a single token:
// index the fixed trailing columns from the END and take everything between guid and lastmsg as
// the name. The old fixed p[4]/p[6] split misread a spaced name AND shifted the address column,
// leaking spaced-name bots in as humans (the "MCG joined" false alert).
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
      if (p.length < 8 || !/^\d+$/.test(p[0])) continue;
      const addr = p[p.length - 3];                          // address = 3rd-from-last
      const name = stripColors(p.slice(4, p.length - 4).join(' '));   // between guid and lastmsg
      if (!name) continue;
      // Bot = a POSITIVE identification (guid 0 at a non-routable address), never a fallback.
      // This was `!(isLocal || isIpPort(addr))` — "not provably human ⇒ bot" — so every row we
      // couldn't read (above all a STILL-CONNECTING client: guid 0, with the address column
      // holding a lastmsg value) came back bot=true. Announcing is unaffected either way — the
      // filter below wants positively-identified humans and a mid-connect player should not be
      // pushed to a phone until they're actually in — but the same flag on the RCON panel drove
      // "Kick All Bots", and there it kicked REAL PLAYERS. The flag is now three-state so no
      // consumer can inherit that footgun: null means "couldn't tell", and it is never actionable.
      const isHuman = addr === 'loopback' || addr === 'local' || /^\d{1,3}(\.\d{1,3}){3}:\d+$/.test(addr);
      const isBot   = !isHuman && p[3] === '0' && /^(unknown|bot|0\.0\.0\.0(:\d+)?)$/i.test(addr);
      const bot     = isHuman ? false : (isBot ? true : null);
      const ping  = /^\d+$/.test(p[2]) ? parseInt(p[2], 10) : null;   // "CNCT"/"ZMBI" → null
      out.players.push({ num: parseInt(p[0], 10), guid: p[3], name, addr, ping, bot });
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

// ─── GeoIP (region from IP) ───────────────────────────────────────────────────
// One HTTP GET to ip-api.com per UNIQUE IP, cached for the process lifetime. A 2s
// timeout + graceful '' fallback means a slow/down lookup never delays a push by more
// than 2s (and never at all for a repeat IP). LAN/loopback/link-local IPs are skipped.
// Format: "City, State 🇺🇸" — city + `region` (the short state/province code, e.g. CA)
// + a flag emoji derived from the ISO2 `countryCode`. The flag renders in the ntfy phone
// app (the "emoji flags don't render on Windows" caveat is a website-only concern). If
// the country code is missing/odd, fall back to the plain country name.
const geoCache = new Map();   // ip -> region string ('' = looked up, nothing useful)

// ISO2 country code → flag emoji (two regional-indicator symbols). '' for anything not
// exactly two ASCII letters, so a junk/absent code never emits a broken glyph.
function ccToFlag(cc) {
  if (!/^[A-Za-z]{2}$/.test(cc || '')) return '';
  return cc.toUpperCase().replace(/./g, (c) => String.fromCodePoint(0x1F1E6 + c.charCodeAt(0) - 65));
}

function geoLookup(addr) {
  return new Promise((resolve) => {
    const ip = String(addr || '').split(':')[0];
    if (!ip || ip === 'unknown' ||
        /^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/.test(ip)) {
      return resolve('');
    }
    if (geoCache.has(ip)) return resolve(geoCache.get(ip));
    let settled = false;
    const finish = (val) => { if (settled) return; settled = true; geoCache.set(ip, val); resolve(val); };
    let req;
    try {
      req = http.get('http://ip-api.com/json/' + ip + '?fields=status,country,countryCode,region,city', (res) => {
        let data = '';
        res.on('data', (c) => { data += c; });
        res.on('end', () => {
          try {
            const j = JSON.parse(data);
            if (j && j.status === 'success') {
              const place = [j.city, j.region].filter(Boolean).join(', ');
              const flag  = ccToFlag(j.countryCode);
              // flag → "City, State 🇺🇸"; no flag → "City, State, Country" (name fallback).
              finish(flag ? (place ? place + ' ' + flag : flag)
                          : [place, j.country].filter(Boolean).join(', '));
            } else finish('');
          } catch (_) { finish(''); }
        });
      });
    } catch (_) { return finish(''); }
    req.on('error', () => finish(''));
    req.setTimeout(2000, () => { try { req.destroy(); } catch (_) {} finish(''); });
  });
}

// Human-readable session length. 45 → "45s", 1830000ms → "30m 30s", 3720000 → "1h 2m".
function fmtDuration(ms) {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return s + 's';
  const m = Math.floor(s / 60);
  if (m < 60) return (s % 60) ? m + 'm ' + (s % 60) + 's' : m + 'm';
  const h = Math.floor(m / 60);
  return (m % 60) ? h + 'h ' + (m % 60) + 'm' : h + 'h';
}

// region + ping → the parts appended to a JOIN alert (empty if we have neither).
// A ping ≥ 999 is the connect-time placeholder (the client hasn't settled a real RTT
// yet at the moment we first see it in `status`), so it's dropped rather than shown as
// a misleading "999ms" — join alerts simply omit the ping until it's a real reading.
function detailBits(region, ping) {
  const bits = [];
  if (region) bits.push(region);
  if (ping != null && !isNaN(ping) && ping < 999) bits.push(ping + 'ms');
  return bits;
}

// ─── Poll loop ──────────────────────────────────────────────────────────────
function log(msg) {
  const t = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`[${t}] ${msg}`);
}
function pKey(p) { return (p.guid && p.guid !== '0') ? 'g:' + p.guid : 'n:' + p.name; }

let known = null;      // Map(key -> {name, joinedAt, ping, addr}); null until first poll seeds it
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
  const now  = Date.now();
  // Bots AND ignored players drop out in one place, so the join/leave diff, the counts,
  // wasEmpty, the EMPTY transition and the heartbeat never see them.
  const ign  = getIgnore();
  // bot===false, NOT !p.bot: demand a POSITIVE human ID. A row we couldn't classify (bot===null —
  // in practice a client still connecting, guid 0) must not fire a push yet; it would key by name,
  // then re-key by GUID once it lands, and push twice. Same set as before, said explicitly.
  const real = st.players.filter(p => p.bot === false && !isIgnored(ign, p.guid, p.name));
  // Carry each staying player's joinedAt forward; stamp newly-seen players with `now`.
  const cur = new Map();
  for (const p of real) {
    const k = pKey(p);
    const prev = known && known.get(k);
    cur.set(k, { name: p.name, joinedAt: prev ? prev.joinedAt : now, ping: p.ping, addr: p.addr });
  }
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
    const info = newJoins[i][1];
    const nm = info.name;
    const region = cfg.geoLookup ? await geoLookup(info.addr) : '';   // ≤2s, cached per IP
    const bits = detailBits(region, info.ping);
    const detail = bits.length ? '\n' + bits.join('  |  ') : '';
    const logd   = bits.length ? '  [' + bits.join(', ') + ']' : '';
    const first = wasEmpty && i === 0;      // first human onto a previously empty server
    if (first) {
      log('FIRST ' + nm + '  (server now active, ' + cur.size + ' online)' + logd);
      if (cfg.notifyFirstJoin) {
        await sendNtfy(cfg, {
          title: cfg.serverName + ' — server now active',
          message: nm + ' joined an empty server' + ctxSuffix + detail,
          priority: 'high', tags: 'green_circle,bust_in_silhouette',
        });
        continue;   // this player already announced by the "active" alert
      }
    }
    log('JOIN  ' + nm + '  (' + cur.size + ' online)' + logd);
    await sendNtfy(cfg, {
      title: cfg.serverName + ' — player joined',
      message: nm + ' joined  (' + cur.size + ' online)' + ctxSuffix + detail,
      priority: 'default', tags: 'bust_in_silhouette',
    });
  }

  if (cfg.notifyLeaves) {
    for (const [, info] of departed) {
      const sess = fmtDuration(now - info.joinedAt);
      log('LEAVE ' + info.name + '  (' + cur.size + ' online, played ' + sess + ')');
      await sendNtfy(cfg, {
        title: cfg.serverName + ' — player left',
        message: info.name + ' left after ' + sess + '  (' + cur.size + ' online)',
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
  log(`  geo        ${cfg.geoLookup ? 'on (ip-api.com)' : 'off'}`);

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
