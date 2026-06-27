'use strict';
// GF RCON Server — zero npm dependencies (built-in modules only)
const http = require('http');
const dgram = require('dgram');
const fs   = require('fs');
const path = require('path');
const cp   = require('child_process');

const WEB_PORT   = 3000;
const RCON_TIMEOUT = 3000;
const COLLECT_MS   = 350;
const DVAR_COLLECT_MS = 120;   // shorter window for single-value dvar reads (one small packet)
const DVAR_CHUNK   = 8;        // concurrent dvar reads per batch
const PUBLIC_DIR   = path.join(__dirname, 'public');
// dedicated.cfg lives at storage/t5/dedicated.cfg; this file is at
// storage/t5/mods/mp_gunfight/tools/rcon/server.js → four levels up.
const CFG_PATH     = path.resolve(__dirname, '..', '..', '..', '..', 'dedicated.cfg');

// ─── RCON UDP ─────────────────────────────────────────────────────────────────

const OOB = Buffer.from([0xff, 0xff, 0xff, 0xff]);

function buildPacket(password, command) {
  return Buffer.concat([OOB, Buffer.from(`rcon ${password} ${command}`, 'utf8')]);
}

function sendRcon(host, port, password, command, collectMs = COLLECT_MS) {
  return new Promise((resolve, reject) => {
    const sock   = dgram.createSocket('udp4');
    const chunks = [];
    let collectTimer, mainTimer;

    const cleanup = () => { clearTimeout(mainTimer); clearTimeout(collectTimer); try { sock.close(); } catch (_) {} };
    const finish  = () => { cleanup(); resolve(Buffer.concat(chunks)); };

    mainTimer = setTimeout(() => {
      if (chunks.length > 0) finish();
      else { cleanup(); reject(new Error('Server not responding (timeout)')); }
    }, RCON_TIMEOUT);

    sock.on('message', (msg) => {
      chunks.push(msg);
      clearTimeout(collectTimer);
      collectTimer = setTimeout(finish, collectMs);
    });
    sock.on('error', (err) => { cleanup(); reject(err); });

    sock.bind(0, () => {
      const pkt = buildPacket(password, command);
      sock.send(pkt, 0, pkt.length, port, host, (err) => { if (err) { cleanup(); reject(err); } });
    });
  });
}

function parseRconResponse(buf) {
  const s  = buf.toString('utf8');
  const nl = s.indexOf('\n');
  return nl === -1 ? s.slice(4) : s.slice(nl + 1).trimEnd();
}

// ─── Status parsing ───────────────────────────────────────────────────────────
// T5 Plutonium listen-server status format:
//   map: mp_russianbase
//   num score ping guid   name            lastmsg address               qport rate
//   --- ----- ---- --------- --------------- ------- --------------------- ------ -----
//     1     0   12 2223048 KL9                   0 loopback              -20175 25000
//     2   857    0       0 LiMi7ED         1092400 unknown                   42  5000
//
// Bot detection: guid == "0" AND address == "unknown"
// Local player:  address == "loopback"

function stripColors(s) { return String(s).replace(/\^[0-9a-zA-Z]/g, '').trim(); }

function parseStatusText(text) {
  const lines  = text.split('\n');
  const result = { map: 'unknown', gametype: '', listenServer: false, players: [] };

  for (const raw of lines) {
    const line = raw.trim();
    const mMap = line.match(/^map:\s*(.+)/i);
    if (mMap) { result.map = mMap[1].trim(); continue; }
    const mGt = line.match(/^gametype:\s*(.+)/i);
    if (mGt) { result.gametype = mGt[1].trim(); continue; }
  }

  const sepIdx = lines.findIndex(l => /^---/.test(l.trim()));
  if (sepIdx !== -1) {
    for (let i = sepIdx + 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;
      // Split by whitespace; T5 player names have no spaces
      const p = line.split(/\s+/);
      // expect: [num, score, ping, guid, name, lastmsg, address, ...]
      if (p.length < 7 || !/^\d+$/.test(p[0])) continue;
      const isBot   = p[3] === '0' && p[6] === 'unknown';
      const isLocal = p[6] === 'loopback';
      if (isLocal) result.listenServer = true;
      const ip      = isBot ? null : isLocal ? 'local' : p[6].split(':')[0];
      result.players.push({
        num:   parseInt(p[0]),
        score: parseInt(p[1]),
        ping:  parseInt(p[2]),
        guid:  p[3],
        name:  stripColors(p[4]),
        bot:   isBot,
        local: isLocal,
        addr:  p[6],
        ip,
      });
    }
  }
  return result;
}

function parseDvarValue(text, dvarName) {
  // Matches: "g_gametype" is "gf"  OR  g_gametype is gf
  const m = text.match(new RegExp('"?' + dvarName + '"?\\s+is\\s+"?([^"\\n]+)"?'));
  return m ? m[1].trim() : null;
}

// Read many dvars and return { name: value|null }. Reads in chunks of DVAR_CHUNK
// concurrently with a short collect window so a ~100-dvar sweep finishes in ~2-3s
// instead of ~35s. A per-dvar timeout/parse-miss yields null (frontend keeps its default).
async function readDvars(host, port, password, names) {
  const values = {};
  for (let i = 0; i < names.length; i += DVAR_CHUNK) {
    const chunk = names.slice(i, i + DVAR_CHUNK);
    await Promise.all(chunk.map(async (name) => {
      try {
        const buf  = await sendRcon(host, port, password, name, DVAR_COLLECT_MS);
        const text = parseRconResponse(buf);
        values[name] = parseDvarValue(text, name);
      } catch (_) {
        values[name] = null;
      }
    }));
  }
  return values;
}

function parseGfState(stateStr) {
  // format: "wA:wX:round:aliveA:aliveX:gametype"
  const parts = String(stateStr).split(':');
  if (parts.length < 5) return null;
  return {
    winsAllies: parseInt(parts[0]) || 0,
    winsAxis:   parseInt(parts[1]) || 0,
    round:      parseInt(parts[2]) || 1,
    aliveAllies:parseInt(parts[3]) || 0,
    aliveAxis:  parseInt(parts[4]) || 0,
    gametype:   parts[5] || '',
  };
}

// ─── dedicated.cfg persistence ────────────────────────────────────────────────
// Upsert `set <name> "<value>"` lines into existing cfg text, preserving every other
// line. A name already present (set/seta/sets, quoted or not) is replaced in place;
// otherwise it's appended under a managed marker. Returns { text, updated, added }.
function upsertCfg(text, dvars, eol) {
  const lines = text.split(/\r?\n/);
  let updated = 0, added = 0;
  const toAppend = [];
  for (const name of Object.keys(dvars)) {
    const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re  = new RegExp('^(\\s*)set[as]?\\s+"?' + esc + '"?\\s', 'i');
    const line = `set ${name} "${dvars[name]}"`;
    let found = false;
    for (let i = 0; i < lines.length; i++) {
      if (re.test(lines[i])) {
        const cm = lines[i].match(/(\s+\/\/.*)$/);   // keep an aligned trailing // comment
        lines[i] = line + (cm ? cm[1] : '');
        updated++; found = true; break;
      }
    }
    if (!found) toAppend.push(line);
  }
  if (toAppend.length) {
    const marker = '// --- GF RCON tool ---';
    if (!lines.some(l => l.trim() === marker)) { lines.push('', marker); }
    for (const l of toAppend) { lines.push(l); added++; }
  }
  return { text: lines.join(eol), updated, added };
}

// ─── HTTP helpers ─────────────────────────────────────────────────────────────

function readBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', c => { body += c.toString(); });
    req.on('end', () => resolve(body));
  });
}

function sendJson(res, data, status = 200) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type':                'application/json',
    'Access-Control-Allow-Origin': '*',
    'Content-Length':              Buffer.byteLength(body),
  });
  res.end(body);
}

function serveFile(res, filePath) {
  try {
    const data = fs.readFileSync(filePath);
    const ext  = path.extname(filePath).toLowerCase();
    const mime = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css',
      '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
      '.gif': 'image/gif', '.webp': 'image/webp', '.ico': 'image/x-icon' };   // drop extracted game art in public/ and <img> it
    res.writeHead(200, { 'Content-Type': mime[ext] || 'application/octet-stream' });
    res.end(data);
  } catch (_) { res.writeHead(404); res.end('Not found'); }
}

// ─── HTTP server ──────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const parsed   = new URL(req.url, 'http://localhost');
  const pathname = parsed.pathname;
  const query    = Object.fromEntries(parsed.searchParams);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' });
    return res.end();
  }

  // ── Static files ──
  if (req.method === 'GET' && !pathname.startsWith('/api/')) {
    const file     = pathname === '/' ? 'index.html' : pathname.slice(1);
    const filePath = path.join(PUBLIC_DIR, file);
    if (!filePath.startsWith(PUBLIC_DIR)) { res.writeHead(403); return res.end(); }
    return serveFile(res, filePath);
  }

  // ── GET /api/status ──
  if (req.method === 'GET' && pathname === '/api/status') {
    const { host = '127.0.0.1', port = '28960', password = '' } = query;
    const p = parseInt(port);
    try {
      const statusBuf = await sendRcon(host, p, password, 'status');
      const text = parseRconResponse(statusBuf);
      const data = parseStatusText(text);
      return sendJson(res, { ok: true, ...data, raw: text });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/gfstate ── reads gf_state telemetry dvar (works on dedicated; times out on listen)
  if (req.method === 'GET' && pathname === '/api/gfstate') {
    const { host = '127.0.0.1', port = '28960', password = '' } = query;
    try {
      const buf  = await sendRcon(host, parseInt(port), password, 'gf_state');
      const text = parseRconResponse(buf);
      const val  = parseDvarValue(text, 'gf_state');
      const state = val ? parseGfState(val) : null;
      return sendJson(res, { ok: !!state, state });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/dvars ── batch-read dvar values: ?names=a,b,c (read-only, chunked)
  if (req.method === 'GET' && pathname === '/api/dvars') {
    const { host = '127.0.0.1', port = '28960', password = '', names = '' } = query;
    const list = names.split(',').map(s => s.trim()).filter(Boolean);
    if (!list.length) return sendJson(res, { ok: false, error: 'No dvar names' }, 400);
    try {
      const values = await readDvars(host, parseInt(port), password, list);
      return sendJson(res, { ok: true, values });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── POST /api/rcon ──
  if (req.method === 'POST' && pathname === '/api/rcon') {
    let body;
    try { body = JSON.parse(await readBody(req)); } catch (_) { return sendJson(res, { ok: false, error: 'Bad JSON' }, 400); }
    const { host = '127.0.0.1', port = '28960', password = '', command } = body;
    if (!command) return sendJson(res, { ok: false, error: 'Missing command' }, 400);
    try {
      const buf      = await sendRcon(host, parseInt(port), password, command);
      const response = parseRconResponse(buf);
      return sendJson(res, { ok: true, response });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── POST /api/savecfg ── persist dvars to dedicated.cfg (upsert; makes a .bak)
  if (req.method === 'POST' && pathname === '/api/savecfg') {
    let body;
    try { body = JSON.parse(await readBody(req)); } catch (_) { return sendJson(res, { ok: false, error: 'Bad JSON' }, 400); }
    const dvars   = body.dvars || {};
    const cfgPath = body.path || CFG_PATH;
    if (!Object.keys(dvars).length) return sendJson(res, { ok: false, error: 'No dvars to save' }, 400);
    try {
      if (!fs.existsSync(cfgPath)) return sendJson(res, { ok: false, error: 'dedicated.cfg not found at ' + cfgPath }, 404);
      const orig = fs.readFileSync(cfgPath, 'utf8');
      fs.writeFileSync(cfgPath + '.bak', orig);                       // safety backup (last save)
      const eol = orig.includes('\r\n') ? '\r\n' : '\n';
      const { text, updated, added } = upsertCfg(orig, dvars, eol);
      fs.writeFileSync(cfgPath, text);
      return sendJson(res, { ok: true, updated, added, count: Object.keys(dvars).length, path: cfgPath });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── POST /api/batch ──
  if (req.method === 'POST' && pathname === '/api/batch') {
    let body;
    try { body = JSON.parse(await readBody(req)); } catch (_) { return sendJson(res, { ok: false, error: 'Bad JSON' }, 400); }
    const { host = '127.0.0.1', port = '28960', password = '', commands = [], delayMs = 80 } = body;
    const results = [];
    for (let i = 0; i < commands.length; i++) {
      const command = commands[i];
      try {
        const buf      = await sendRcon(host, parseInt(port), password, command);
        const response = parseRconResponse(buf);
        results.push({ ok: true, command, response });
      } catch (err) {
        results.push({ ok: false, command, error: err.message });
      }
      if (delayMs > 0 && i < commands.length - 1) await new Promise(r => setTimeout(r, delayMs));
    }
    return sendJson(res, { ok: true, results });
  }

  res.writeHead(404); res.end('Not found');
});

server.listen(WEB_PORT, '127.0.0.1', () => {
  const addr = `http://127.0.0.1:${WEB_PORT}`;
  console.log(`\n  GF RCON Tool  →  ${addr}\n`);
  try { cp.exec(`start ${addr}`); } catch (_) {}
});
