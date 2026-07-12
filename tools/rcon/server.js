'use strict';
// GF RCON Server — zero npm dependencies (built-in modules only)
const http = require('http');
const dgram = require('dgram');
const fs   = require('fs');
const path = require('path');
const cp   = require('child_process');

// Web UI port. Override with the PORT env var to run a 2nd instance alongside another (e.g. keep
// an SSH tunnel to the VPS panel on 3000 while a local panel serves the laptop listen server on
// 3001): `set PORT=3001 && node server.js`. The host/origin allowlist below derives from this,
// so it adapts automatically. Falls back to 3000 if unset or not a valid port.
const WEB_PORT   = (function(){ const p = parseInt(process.env.PORT, 10); return (p >= 1 && p <= 65535) ? p : 3000; })();
const RCON_TIMEOUT = 3000;
const COLLECT_MS   = 350;
// This server RATE-LIMITS rcon replies to ~1 per 0.7s (measured): a command sent sooner than
// that after the previous reply is silently dropped. So dvar reads are (a) BATCHED — many
// dvar queries chained into one rcon command (`a;b;c`), one reply carries all their values —
// and (b) PACED at ~1s between commands. ~100 dvars become ~5 replies (~10s) at near-100%.
const DVAR_BATCH_SIZE = 24;        // dvars chained per rcon command (keeps the request under MTU)
const DVAR_BATCH_COLLECT_MS = 350; // quiet window to gather the multi-packet batched reply
const DVAR_BATCH_HARD_MS = 1300;   // batched replies land in ~400ms; a miss retries without a long stall
const DVAR_BATCH_ROUNDS = 3;       // re-query passes; each re-asks only the names still missing
                                   // (command pacing is handled globally by sendRconQueued / RCON_MIN_GAP)
const DVAR_DEAD_BATCH_MAX = 12;    // in a re-query batch this small the reply can't be truncated, so a
                                   // name that comes back UNparsed is a genuine unknown/unset dvar —
                                   // mark it dead and stop retrying (avoids burning every round on it)
const PUBLIC_DIR   = path.join(__dirname, 'public');
// dedicated.cfg lives at storage/t5/dedicated.cfg; this file is at
// storage/t5/mods/mp_gunfight/tools/rcon/server.js → four levels up.
const CFG_PATH     = path.resolve(__dirname, '..', '..', '..', '..', 'dedicated.cfg');
// Per-profile rcon_password lives HERE, next to server.js, and is GITIGNORED — it never
// enters the repo. Shape: { "profiles": { "<profile name>": "<rcon_password>" } }. The panel
// reads/writes it over the loopback-only API so passwords never sit in browser localStorage
// or in any tracked file. See secrets.local.json.example.
const SECRETS_PATH = path.join(__dirname, 'secrets.local.json');
// Panel UI state (today: the FAVORITES pinboard) — gitignored, box-local, and kept HERE rather
// than in browser localStorage so it follows the PANEL PROCESS, not the browser. The VPS panel
// then shows one pinboard whether you reach it by RDP on the box or over the SSH tunnel from a
// laptop, and a laptop's own local panel keeps its own. deploy.ps1 /XF-excludes it so a deploy's
// /MIR can't delete it. Shape: { "favs": ["dv:scr_gf_scorelimit", ...] }.
const PREFS_PATH   = path.join(__dirname, 'prefs.local.json');

// ─── RCON UDP ─────────────────────────────────────────────────────────────────

const OOB = Buffer.from([0xff, 0xff, 0xff, 0xff]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function buildPacket(password, command) {
  return Buffer.concat([OOB, Buffer.from(`rcon ${password} ${command}`, 'utf8')]);
}

function sendRcon(host, port, password, command, collectMs = COLLECT_MS, hardMs = RCON_TIMEOUT) {
  return new Promise((resolve, reject) => {
    const sock   = dgram.createSocket('udp4');
    const chunks = [];
    let collectTimer, mainTimer;

    const cleanup = () => { clearTimeout(mainTimer); clearTimeout(collectTimer); try { sock.close(); } catch (_) {} };
    const finish  = () => { cleanup(); resolve(Buffer.concat(chunks)); };

    mainTimer = setTimeout(() => {
      if (chunks.length > 0) finish();
      else { cleanup(); reject(new Error('Server not responding (timeout)')); }
    }, hardMs);

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

// ── Global rcon send throttle (priority-aware) ────────────────────────────────
// This server rate-limits rcon replies (~1 per 0.7s) and silently DROPS commands sent
// faster. The web UI issues many concurrent rcon calls (dvar sweeps + status/score ticks
// overlap on connect), so we serialize EVERY send through one queue with a minimum gap,
// measured from the previous send's completion — the server is never outrun no matter how
// many HTTP requests arrive at once. This is what makes the batched dvar sync land ~100%.
//
// PRIORITY: a user click (bridge command write) and its ack read go on a HIGH-priority lane so
// they jump ahead of the background status/score/roster ticks and the ~100-dvar connect sweep —
// otherwise a click could sit multiple seconds behind an in-flight read burst. The ≥850ms gap is
// still enforced globally (it's a hard server limit); priority only reorders WHO goes next.
const RCON_MIN_GAP = 850;
let _rconActive = false;
let _rconLastDone = 0;
let _rconSeq = 0;                 // tiebreak: FIFO within the same priority
const _rconQ = [];               // pending jobs: { priority, seq, args, key, waiters, resolve, reject }
function _rconEnqueue(priority, args, key) {
  // COALESCE: an idempotent read (dashboard tick / ack poll) whose twin is already queued
  // piggybacks on that job's reply instead of adding queue depth. The browser issues these on
  // timers regardless of backlog, so without this a busy stretch (dvar sweep, packet loss)
  // stacked identical reads faster than the 850ms-gap lane could drain them — the queue, and
  // every click behind it, fell minutes behind and never recovered.
  if (key) {
    const twin = _rconQ.find((j) => j.key === key);
    if (twin) return new Promise((resolve, reject) => twin.waiters.push({ resolve, reject }));
  }
  return new Promise((resolve, reject) => {
    _rconQ.push({ priority, seq: _rconSeq++, args, key, waiters: [], resolve, reject });
    _rconDrain();
  });
}
async function _rconDrain() {
  if (_rconActive || !_rconQ.length) return;
  _rconActive = true;
  // Pick the highest priority; oldest (lowest seq) wins ties → FIFO within a lane.
  let bi = 0;
  for (let i = 1; i < _rconQ.length; i++) {
    const a = _rconQ[i], b = _rconQ[bi];
    if (a.priority > b.priority || (a.priority === b.priority && a.seq < b.seq)) bi = i;
  }
  const job = _rconQ.splice(bi, 1)[0];
  const gap = RCON_MIN_GAP - (Date.now() - _rconLastDone);
  if (gap > 0) await sleep(gap);
  try { const buf = await sendRcon(...job.args); job.resolve(buf); for (const w of job.waiters) w.resolve(buf); }
  catch (e) { job.reject(e); for (const w of job.waiters) w.reject(e); }
  finally { _rconLastDone = Date.now(); _rconActive = false; _rconDrain(); }
}
// Background reads (status/score/roster/dvar sweep) — normal lane.
function sendRconQueued(...args)   { return _rconEnqueue(0, args); }
// User clicks + ack reads — high lane, preempt background work at the next free slot.
function sendRconPriority(...args) { return _rconEnqueue(10, args); }
// Keyed variants: same lanes, but identical queued reads coalesce (see _rconEnqueue).
function sendRconQueuedKeyed(key, ...args)   { return _rconEnqueue(0, args, key); }
function sendRconPriorityKeyed(key, ...args) { return _rconEnqueue(10, args, key); }

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
//     3     0    0       0 MCG Gordon            0 unknown                   43  5000
//
// Bot detection: the ADDRESS column is not a real ip:port (and not a listen-server
// loopback). We do NOT key off guid=="0" && p[6]=="unknown" anymore: player NAMES
// CAN CONTAIN SPACES (e.g. the bot "MCG Gordon"), so name is not a single token —
// a fixed p[4]/p[6] split misreads a spaced name AND shifts the address one column
// right, so a spaced-name bot (guid 0, but the shifted col != "unknown") leaked in
// as a human. Instead we index the fixed trailing columns from the END and take
// everything between guid and lastmsg as the name (matches status_service.ps1).
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
      // Columns: num score ping guid  NAME(may contain spaces)  lastmsg address qport rate
      // Front columns (num/score/ping/guid) are a fixed count, so read them by index.
      // The name can hold spaces, so read the trailing columns from the END: address is
      // the 3rd-from-last token, and the name is everything between guid and lastmsg.
      const p = line.split(/\s+/);
      if (p.length < 8 || !/^\d+$/.test(p[0])) continue;
      const addr    = p[p.length - 3];
      const name    = stripColors(p.slice(4, p.length - 4).join(' '));
      if (!name) continue;
      const isLocal = addr === 'loopback' || addr === 'local';
      // Human = a real ip:port (or a listen-server loopback). Anything else — "unknown",
      // a still-connecting client's lastmsg value, etc. — is treated as a bot/non-human.
      const isBot   = !(isLocal || /^\d{1,3}(\.\d{1,3}){3}:\d+$/.test(addr));
      if (isLocal) result.listenServer = true;
      const ip      = isBot ? null : isLocal ? 'local' : addr.split(':')[0];
      result.players.push({
        num:   parseInt(p[0]),
        score: parseInt(p[1]),
        ping:  parseInt(p[2]),
        guid:  p[3],
        name,
        bot:   isBot,
        local: isLocal,
        addr,
        ip,
      });
    }
  }
  return result;
}

function parseDvarValue(text, dvarName) {
  // Plutonium T5 dvar echo:  "sv_floodprotect" is: "20^7" default: "4^7" Domain is ...
  // - Case-INSENSITIVE: the server echoes the dvar's REGISTERED name (all-lowercase,
  //   e.g. sv_floodprotect) regardless of the queried case (sv_floodProtect) — a
  //   case-sensitive match nulled every mixed-case dvar (most of the panel).
  // - The ':' after "is" and the whitespace after it are both optional (r5328 varies
  //   between `is:"x"` and `is: "x"`).
  // - Value may be quoted or bare; strip trailing ^N color codes (they blank number inputs).
  const esc = dvarName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let m = text.match(new RegExp('"?' + esc + '"?\\s+is:?\\s*"([^"]*)"', 'i'));      // quoted value
  if (!m) m = text.match(new RegExp('"?' + esc + '"?\\s+is:?\\s*([^\\s"]+)', 'i')); // bare value
  if (!m) return null;
  return m[1].replace(/\^[0-9a-zA-Z]/g, '').trim();
}

// Read many dvars and return { name: value|null }. Reads are PACED (sequential, small gap,
// short timeout, one retry) rather than bursted concurrently — Plutonium flood-drops rapid
// OOB rcon packets, so an 8-wide concurrent sweep lost ~90% of reads to timeout. A ~100-dvar
// sweep now takes a few seconds but the reads actually land. Timeout/parse-miss yields null
// (frontend keeps its default and flags the field "not read").
// Persistent per-profile cache of dvars this server rejects as "Unknown command". Reading a dvar
// by bare name over rcon makes the GAME server print `Unknown cmd <name>` for any UNregistered one
// (the panel sweeps ~100 controls, and stock/Plutonium dvars not present on a given build error) —
// which renders on a listen-host's screen as connect spam. We can't know registered-ness without
// sending, so the FIRST sweep of a fresh profile still probes them once; the reply echoes the
// `Unknown cmd` line, we learn the exact names, cache them (keyed by host:port, file-backed so it
// survives a panel restart) and never bare-send them again. The panel's ↻ Read passes fresh=1 to
// clear the cache and re-probe (so a dvar that later becomes registered is picked back up).
const DVAR_DEAD_FILE = path.join(__dirname, '.dvarcache.json');
const deadDvarCache = (function loadDeadDvarCache() {
  try {
    const obj = JSON.parse(fs.readFileSync(DVAR_DEAD_FILE, 'utf8'));
    const m = new Map();
    for (const k of Object.keys(obj)) if (Array.isArray(obj[k])) m.set(k, new Set(obj[k]));
    return m;
  } catch (_) { return new Map(); }
})();
function saveDeadDvarCache() {
  try {
    const obj = {};
    for (const [k, set] of deadDvarCache) obj[k] = [...set];
    fs.writeFileSync(DVAR_DEAD_FILE, JSON.stringify(obj));
  } catch (_) {}
}

async function readDvars(host, port, password, names, fresh) {
  const key = host + ':' + port;
  if (fresh) { deadDvarCache.delete(key); saveDeadDvarCache(); }
  const cached = deadDvarCache.get(key) || new Set();

  const values = {};
  for (const n of names) values[n] = null;
  const DBG = process.env.GF_RCON_DEBUG;
  const T0 = Date.now();
  const ts = () => '+' + (Date.now() - T0) + 'ms';

  // `dead` = names to skip for the rest of THIS call (seeded from the persistent cache so known
  // unknowns are never re-sent by bare name). `confirmed` = names the server EXPLICITLY rejected
  // this call (from the reply's `Unknown cmd` echo) — only these get persisted, so a real dvar
  // that merely dropped a packet can never be permanently skipped.
  const dead = new Set(cached);
  const confirmed = new Set();
  for (let round = 0; round < DVAR_BATCH_ROUNDS; round++) {
    const pending = names.filter((n) => values[n] === null && !dead.has(n));
    if (!pending.length) break;
    for (let i = 0; i < pending.length; i += DVAR_BATCH_SIZE) {
      const need = pending.slice(i, i + DVAR_BATCH_SIZE);
      try {
        const buf  = await sendRconQueued(host, port, password, need.join(';'), DVAR_BATCH_COLLECT_MS, DVAR_BATCH_HARD_MS);
        const text = parseRconResponse(buf);
        let hit = 0;
        for (const name of need) { const v = parseDvarValue(text, name); if (v !== null) { values[name] = v; hit++; } }
        // Authoritative: the reply echoes `Unknown cmd <name>` / `Unknown command "<name>"` for
        // each unregistered dvar. Mark exactly those (intersected with this batch) dead + persist.
        if (/Unknown\s+(?:command|cmd)/i.test(text)) {
          const unknown = new Set();
          let mm; const re = /Unknown\s+(?:command|cmd)\s+"?([A-Za-z0-9_]+)"?/gi;
          while ((mm = re.exec(text)) !== null) unknown.add(mm[1]);
          for (const name of need) if (unknown.has(name)) { dead.add(name); confirmed.add(name); }
        }
        // Secondary signal (in case a build doesn't echo the "Unknown cmd" text into the reply):
        // in a small batch where at least one name DID parse, the reply provably arrived intact,
        // so any still-null name is genuinely unknown — safe to skip AND persist. `hit > 0` is
        // what distinguishes this from a whole-batch timeout (which must NOT be treated as dead).
        if (hit < need.length && need.length <= DVAR_DEAD_BATCH_MAX) {
          for (const name of need) if (values[name] === null) {
            dead.add(name);
            if (hit > 0) confirmed.add(name);
          }
        }
        if (DBG) console.error(ts() + ' [r' + round + '] need=' + need.length + ' bytes=' + (buf ? buf.length : 0) + ' hit=' + hit + ' dead=' + dead.size + ' confirmed=' + confirmed.size);
      } catch (e) {
        if (DBG) console.error(ts() + ' [r' + round + '] need=' + need.length + ' ERR ' + (e && e.message));
      }
    }
  }
  // Persist any newly-confirmed unknowns for this profile so the next sweep skips them.
  if (confirmed.size) {
    const set = deadDvarCache.get(key) || new Set();
    let grew = false;
    for (const n of confirmed) if (!set.has(n)) { set.add(n); grew = true; }
    if (grew) { deadDvarCache.set(key, set); saveDeadDvarCache(); }
  }
  if (DBG) { const miss = names.filter((n) => values[n] === null); console.error(ts() + ' [done] got ' + (names.length - miss.length) + '/' + names.length + ' cachedSkip=' + cached.size + (miss.length ? ' MISSING: ' + miss.join(',') : '')); }
  return values;
}

// Parse the gf_roster telemetry dvar into per-player team/alive/pending/bot.
// format: "<num>,<team>,<alive>,<pending>,<bot>;..."  team/pending: a=allies x=axis s=spectator
// -=none; alive 1/0; bot 1/0 (5th field added 2026-07-08; older servers omit it -> bot:false).
function parseGfRoster(str) {
  const map = { a: 'allies', x: 'axis', s: 'spectator', '-': '' };
  const out = [];
  for (const seg of String(str).split(';')) {
    if (!seg) continue;
    const f = seg.split(',');
    if (f.length < 2 || !/^\d+$/.test(f[0])) continue;
    out.push({
      num:     parseInt(f[0]),
      team:    map[f[1]] || '',
      alive:   f[2] === '1',
      pending: map[f[3]] || '',
      bot:     f[4] === '1',
    });
  }
  return out;
}

// Parse a CoD map-rotation string ("gametype gf map mp_array gametype gf map mp_cairo …") into
// [{ gametype, map }]. Tolerates a bare leading `map` (inherits the last gametype, else '') and
// stray tokens. Used for both sv_maprotation (the full configured order) and sv_maprotationcurrent
// (the not-yet-played remainder — its head is the next map the engine will load).
function parseMapRotation(str) {
  // Split on whitespace, then sanitize each token to [A-Za-z0-9_]. Rotation keywords/map ids are
  // all word-chars, so this is lossless for clean data — but it also strips stray bytes that creep
  // into a hand-edited sv_maprotation (observed live: 0x93/0x94 Windows-1252 smart-quotes from a doc
  // paste) which would otherwise glue onto a `map` keyword (dropping the next map) or a map id
  // (corrupting it, then persisting the corruption on save). A token that was all garbage → '' → dropped.
  const toks = String(str).trim().split(/\s+/).map(t => t.replace(/[^A-Za-z0-9_]/g, '')).filter(Boolean);
  const out = [];
  let gt = '';
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i].toLowerCase();
    if (t === 'gametype' && i + 1 < toks.length) gt = toks[++i];
    else if (t === 'map' && i + 1 < toks.length) out.push({ gametype: gt, map: toks[++i] });
  }
  return out;
}

function parseGfState(stateStr) {
  // format: "wA:wX:round:aliveA:aliveX:gametype:hold:fillN:pAllies:pAxis:parked"
  // (hold added 2026-07-05, fill fields 8-11 added 2026-07-08; older servers omit trailing
  // fields → parts[i] undefined → sane defaults, so this stays back-compatible)
  const parts = String(stateStr).split(':');
  if (parts.length < 5) return null;
  const num = (v, d) => (v === undefined || v === '' ? d : (parseInt(v) || 0));
  return {
    winsAllies: parseInt(parts[0]) || 0,
    winsAxis:   parseInt(parts[1]) || 0,
    round:      parseInt(parts[2]) || 1,
    aliveAllies:parseInt(parts[3]) || 0,
    aliveAxis:  parseInt(parts[4]) || 0,
    gametype:   (parts[5] || '').replace(/\^\d/g, ''),   // strip color codes (gf^7 -> gf)
    lobbyHold:  parts[6] === '1',                          // pre-prematch admin/load hold is active
    fillN:      parts[7] !== undefined ? num(parts[7], 0) : null,   // per-team fill target (null = server predates fill telemetry)
    playAllies: num(parts[8], 0),                          // current playing count (humans+bots) allies
    playAxis:   num(parts[9], 0),                          // current playing count axis
    parked:     num(parts[10], 0),                         // bots benched in spectator for reuse
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

// ─── Secrets (gitignored rcon_password store) ─────────────────────────────────
// A profile-name → rcon_password map kept OUT of git in secrets.local.json. Missing
// file / bad JSON is not an error — a fresh clone just has no saved passwords yet.
function loadSecrets() {
  try {
    const obj = JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf8'));
    if (obj && obj.profiles && typeof obj.profiles === 'object') return obj.profiles;
  } catch (_) {}
  return {};
}
function saveSecret(name, pass) {
  let obj = { profiles: {} };
  try {
    const cur = JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf8'));
    if (cur && typeof cur === 'object') obj = cur;
  } catch (_) {}
  if (!obj.profiles || typeof obj.profiles !== 'object') obj.profiles = {};
  if (pass === '') delete obj.profiles[name];   // don't persist blank entries
  else obj.profiles[name] = pass;
  fs.writeFileSync(SECRETS_PATH, JSON.stringify(obj, null, 2) + '\n');
}

// ─── Panel prefs (gitignored UI state — see PREFS_PATH) ───────────────────────
// Missing file / bad JSON is not an error: a fresh clone simply has no pinboard yet, and the UI
// falls back to its localStorage cache (and to the seeded defaults) in that case.
function loadPrefs() {
  try {
    const obj = JSON.parse(fs.readFileSync(PREFS_PATH, 'utf8'));
    if (obj && typeof obj === 'object') return obj;
  } catch (_) {}
  return {};
}
function savePrefs(prefs) {
  fs.writeFileSync(PREFS_PATH, JSON.stringify(prefs, null, 2) + '\n');
}

// ─── Geo IP (the box's ONE ip-api client: disk-cached + rate-paced) ───────────
// Every box-side "where is this player from" consumer reads through here:
//   • the panel UI's right-click "Locate" (single IP, admin-initiated)
//   • status_service, which stamps a country code on the public roster + activity feed
// ip-api.com free is HTTP-only, no key, and hard-limits at 45 req/min PER SOURCE IP, so a
// second independent client on the box would burn the same budget re-resolving IPs this one
// already knows — the same reason the rcon lane has exactly one queue. Lookups are therefore
// serialized behind GEO_MIN_GAP, deduped while in flight, and cached to disk so a panel
// restart doesn't re-resolve the whole roster.
//
// PRIVACY: the cache maps IP -> location and lives ONLY on the box (gitignored, never in a web
// root). Callers that publish (status_service) take the 2-letter country CODE and nothing else;
// the IP itself never reaches the public snapshot.
const GEO_CACHE_FILE = path.join(__dirname, '.geocache.json');
const GEO_TTL_MS     = 30 * 24 * 3600 * 1000;   // re-resolve a good entry once it's a month old
// A FAILURE is cached only briefly. Failures here are usually transient (ip-api rate-limited us,
// or a network blip), so caching one for the full TTL would blank that player's flag for a month;
// but not caching it at all would re-hit the API for the same dead IP every single 5s poll.
const GEO_NEG_TTL_MS = 30 * 60 * 1000;          // 30 min
const GEO_MIN_GAP    = 1500;                    // ms between outbound lookups (ip-api: 45/min)
const GEO_PRIVATE_RX = /^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|0\.)/;

const geoCache = (function loadGeoCache() {
  try {
    const obj = JSON.parse(fs.readFileSync(GEO_CACHE_FILE, 'utf8'));
    return new Map(Object.entries(obj));
  } catch (_) { return new Map(); }
})();
let geoDirty = false;
function saveGeoCache() {
  if (!geoDirty) return;
  geoDirty = false;
  try { fs.writeFileSync(GEO_CACHE_FILE, JSON.stringify(Object.fromEntries(geoCache))); } catch (_) {}
}
setInterval(saveGeoCache, 30000).unref();   // batch writes; never fsync per lookup

// Strip an optional :port, then reject anything that isn't a routable IPv4 literal.
function geoNormIp(addr) {
  const ip = String(addr || '').trim().split(':')[0];
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) return '';
  if (GEO_PRIVATE_RX.test(ip)) return '';     // LAN / loopback: no useful answer, don't spend a call
  return ip;
}

// Cache read. Returns the entry, or null when unknown / stale (=> caller may resolve).
function geoCached(ip) {
  const e = geoCache.get(ip);
  if (!e) return null;
  const ttl = e.ok ? GEO_TTL_MS : GEO_NEG_TTL_MS;
  if (Date.now() - (e.at || 0) > ttl) return null;
  return e;
}

const geoInflight = new Map();   // ip -> Promise (dedups concurrent asks for the same IP)
let geoNextSlot = 0;             // earliest wall-clock ms the next outbound GET may leave

// Resolve ONE ip through ip-api, honouring the shared rate gap. Always settles (never throws);
// a failure caches a short-lived negative entry so a dead IP isn't retried every single tick.
function geoResolve(ip) {
  const hit = geoCached(ip);
  if (hit) return Promise.resolve(hit);
  if (geoInflight.has(ip)) return geoInflight.get(ip);

  const wait = Math.max(0, geoNextSlot - Date.now());
  geoNextSlot = Date.now() + wait + GEO_MIN_GAP;

  const p = sleep(wait).then(() => new Promise((resolve) => {
    const store = (entry) => {
      entry.at = Date.now();
      geoCache.set(ip, entry);
      geoDirty = true;
      geoInflight.delete(ip);
      resolve(entry);
    };
    const url = `http://ip-api.com/json/${ip}?fields=status,message,countryCode,country,regionName,city,isp,proxy,hosting`;
    const req2 = http.get(url, (r) => {
      let data = '';
      r.on('data', (c) => { data += c; if (data.length > 65536) r.destroy(); });
      r.on('end', () => {
        try {
          const j = JSON.parse(data);
          if (j.status === 'success') {
            store({ ok: true, cc: (j.countryCode || '').toLowerCase(), country: j.country || '',
                    region: j.regionName || '', city: j.city || '', isp: j.isp || '',
                    proxy: !!j.proxy, hosting: !!j.hosting });
          } else {
            store({ ok: false, cc: '', error: j.message || 'lookup failed' });
          }
        } catch (_) { store({ ok: false, cc: '', error: 'bad geo response' }); }
      });
    });
    req2.setTimeout(4000, () => { req2.destroy(); store({ ok: false, cc: '', error: 'geo timeout' }); });
    req2.on('error', (e) => store({ ok: false, cc: '', error: e.message }));
  }));

  geoInflight.set(ip, p);
  return p;
}

// ─── HTTP helpers ─────────────────────────────────────────────────────────────

function readBody(req, maxBytes = 262144) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', c => {
      body += c.toString();
      if (body.length > maxBytes) { body = ''; try { req.destroy(); } catch (_) {} resolve(''); }
    });
    req.on('end', () => resolve(body));
  });
}

function sendJson(res, data, status = 200) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type':   'application/json',
    'Content-Length': Buffer.byteLength(body),
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
    // No caching: this is a live-edited local dev tool served over loopback. Without this the
    // browser keeps serving a stale index.html after an edit (looked fine in VSCode but not the
    // browser). Tiny files on 127.0.0.1 — always re-fetch so edits show on a normal reload.
    res.writeHead(200, {
      'Content-Type':  mime[ext] || 'application/octet-stream',
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      'Pragma':        'no-cache',
      'Expires':       '0',
    });
    res.end(data);
  } catch (_) { res.writeHead(404); res.end('Not found'); }
}

// ─── HTTP server ──────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const parsed   = new URL(req.url, 'http://localhost');
  const pathname = parsed.pathname;
  const query    = Object.fromEntries(parsed.searchParams);

  // ── Local-only guard (anti-CSRF / anti-DNS-rebinding) ──
  // The API is loopback-only. Reject any request whose Host header isn't localhost (a
  // DNS-rebinding page reaches 127.0.0.1 but carries its own hostname as Host), and any
  // cross-origin request (a visited page POSTing here carries its Origin). Same-origin
  // browser requests send Host=127.0.0.1:PORT and either no Origin (GET) or the matching
  // Origin (POST), so the panel itself is unaffected.
  const allowedHosts   = [`127.0.0.1:${WEB_PORT}`, `localhost:${WEB_PORT}`];
  const allowedOrigins = [`http://127.0.0.1:${WEB_PORT}`, `http://localhost:${WEB_PORT}`];
  const hostHdr = String(req.headers.host || '').toLowerCase();
  const origin  = req.headers.origin;
  if (!allowedHosts.includes(hostHdr) || (origin && !allowedOrigins.includes(origin))) {
    res.writeHead(403); return res.end('Forbidden');
  }

  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  // ── Static files ──
  if (req.method === 'GET' && !pathname.startsWith('/api/')) {
    const file     = pathname === '/' ? 'index.html' : pathname.slice(1);
    const filePath = path.join(PUBLIC_DIR, file);
    if (!filePath.startsWith(PUBLIC_DIR)) { res.writeHead(403); return res.end(); }
    return serveFile(res, filePath);
  }

  // ── GET /api/tick ── the whole dashboard refresh in ONE rcon send: `status;gf_state;gf_roster`
  // chained into a single command (one reply carries all three, same trick as the batched dvar
  // reads). Replaces three separate reads per UI tick — those alone demanded ~1.4x the queue's
  // 850ms-gap drain rate on a dedicated server, so the rcon queue (and every click behind it)
  // fell minutes behind. On a listen server the gf_* tokens echo nothing (state/roster → null);
  // the status part still lands.
  if (req.method === 'GET' && pathname === '/api/tick') {
    const { host = '127.0.0.1', port = '28960', password = '' } = query;
    const p = parseInt(port);
    try {
      const buf  = await sendRconQueuedKeyed(`tick:${host}:${p}`, host, p, password, 'status;gf_state;gf_roster');
      const text = parseRconResponse(buf);
      const data = parseStatusText(text);
      const sv   = parseDvarValue(text, 'gf_state');
      const rv   = parseDvarValue(text, 'gf_roster');
      return sendJson(res, {
        ok: true, ...data,
        state:  sv ? parseGfState(sv) : null,
        roster: rv !== null ? parseGfRoster(rv) : null,
      });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/status ──
  if (req.method === 'GET' && pathname === '/api/status') {
    const { host = '127.0.0.1', port = '28960', password = '' } = query;
    const p = parseInt(port);
    try {
      const statusBuf = await sendRconQueuedKeyed(`status:${host}:${p}`, host, p, password, 'status');
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
      const buf  = await sendRconQueuedKeyed(`gfstate:${host}:${port}`, host, parseInt(port), password, 'gf_state');
      const text = parseRconResponse(buf);
      const val  = parseDvarValue(text, 'gf_state');
      const state = val ? parseGfState(val) : null;
      return sendJson(res, { ok: !!state, state });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/gfroster ── reads gf_roster telemetry dvar (dedicated only; times out on listen)
  if (req.method === 'GET' && pathname === '/api/gfroster') {
    const { host = '127.0.0.1', port = '28960', password = '' } = query;
    try {
      const buf  = await sendRconQueuedKeyed(`gfroster:${host}:${port}`, host, parseInt(port), password, 'gf_roster');
      const text = parseRconResponse(buf);
      const val  = parseDvarValue(text, 'gf_roster');
      return sendJson(res, { ok: val !== null, roster: val !== null ? parseGfRoster(val) : [] });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/maprotation ── the live server rotation. Reads two plain engine dvars in one send:
  //   sv_maprotation        — the full configured order ("gametype gf map mp_array …")
  //   sv_maprotationcurrent — the not-yet-played remainder; its HEAD is the next map the engine
  //                           loads at match end. Both are writable over rcon, so the panel drives
  //                           the engine's own rotation instead of racing it with a reactive `map`.
  // Answers on dedicated AND listen (engine dvars, unlike gf_state). Coalesced under a keyed lane.
  if (req.method === 'GET' && pathname === '/api/maprotation') {
    const { host = '127.0.0.1', port = '28960', password = '' } = query;
    try {
      const buf  = await sendRconQueuedKeyed(`maprot:${host}:${port}`, host, parseInt(port), password, 'sv_maprotation;sv_maprotationcurrent');
      const text = parseRconResponse(buf);
      const full = parseDvarValue(text, 'sv_maprotation');
      const cur  = parseDvarValue(text, 'sv_maprotationcurrent');
      return sendJson(res, {
        ok: full !== null,
        rotation:    full !== null ? parseMapRotation(full) : [],
        current:     cur  !== null ? parseMapRotation(cur)  : [],
        rawRotation: full || '',
        rawCurrent:  cur  || '',
      });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/geoip ── two modes over the shared, disk-cached resolver above.
  //
  //   ?ip=<one>    BLOCKING single lookup — the panel UI's right-click "Locate". An admin is
  //                watching a spinner, so it's fine to wait for a cache miss to resolve.
  //
  //   ?ips=a,b,c   NON-BLOCKING batch — status_service, every 5s, for the whole roster. Returns
  //                only what is ALREADY cached and kicks off background resolution for the rest,
  //                so a cold IP costs the caller nothing: its flag simply appears a poll or two
  //                later. Blocking here instead would stall the public status snapshot behind a
  //                rate-paced queue (GEO_MIN_GAP per miss) — a slow geo API must never be able to
  //                hold up the scoreboard.
  if (req.method === 'GET' && pathname === '/api/geoip') {
    const batch = String(query.ips || '').trim();
    if (batch) {
      const ips = [...new Set(batch.split(',').map(geoNormIp).filter(Boolean))].slice(0, 64);
      const geo = {};
      for (const ip of ips) {
        const hit = geoCached(ip);
        if (hit) { if (hit.ok) geo[ip] = { cc: hit.cc, country: hit.country, city: hit.city }; }
        else geoResolve(ip).catch(() => {});   // warm it for a later tick; do not await
      }
      return sendJson(res, { ok: true, geo });
    }

    const ip = geoNormIp(query.ip);
    if (!ip) return sendJson(res, { ok: false, error: 'Bad IP' }, 400);
    try {
      return sendJson(res, await geoResolve(ip));
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/dvars ── batch-read dvar values: ?names=a,b,c (read-only, chunked)
  if (req.method === 'GET' && pathname === '/api/dvars') {
    const { host = '127.0.0.1', port = '28960', password = '', names = '', fresh = '' } = query;
    const list = names.split(',').map(s => s.trim()).filter(Boolean);
    if (!list.length) return sendJson(res, { ok: false, error: 'No dvar names' }, 400);
    try {
      const values = await readDvars(host, parseInt(port), password, list, fresh === '1' || fresh === 'true');
      return sendJson(res, { ok: true, values });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── POST /api/rcon ──
  // `priority:true` (bridge command writes) uses the high lane + short reply window: a `set`
  // echoes nothing useful, so we don't hold the lane for the full RCON_TIMEOUT — the panel marks
  // the command "sent" optimistically and confirms it via the gf_ack poll (/api/ack) anyway.
  if (req.method === 'POST' && pathname === '/api/rcon') {
    let body;
    try { body = JSON.parse(await readBody(req)); } catch (_) { return sendJson(res, { ok: false, error: 'Bad JSON' }, 400); }
    const { host = '127.0.0.1', port = '28960', password = '', command, priority = false } = body;
    if (!command) return sendJson(res, { ok: false, error: 'Missing command' }, 400);
    try {
      const buf = priority
        ? await sendRconPriority(host, parseInt(port), password, command, 150, 700)
        : await sendRconQueued(host, parseInt(port), password, command);
      const response = parseRconResponse(buf);
      return sendJson(res, { ok: true, response });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── GET /api/ack ── high-priority read of gf_ack (last processed command seq). The panel polls
  // this right after sending a bridge command to flip it from "sent" to "received".
  if (req.method === 'GET' && pathname === '/api/ack') {
    const { host = '127.0.0.1', port = '28960', password = '' } = query;
    try {
      const buf  = await sendRconPriorityKeyed(`ack:${host}:${port}`, host, parseInt(port), password, 'gf_ack', 150, 700);
      const text = parseRconResponse(buf);
      const val  = parseDvarValue(text, 'gf_ack');
      return sendJson(res, { ok: val !== null, ack: val !== null ? (parseInt(val) || 0) : 0 });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message });
    }
  }

  // ── POST /api/savecfg ── persist dvars to dedicated.cfg (upsert; makes a .bak)
  if (req.method === 'POST' && pathname === '/api/savecfg') {
    let body;
    try { body = JSON.parse(await readBody(req)); } catch (_) { return sendJson(res, { ok: false, error: 'Bad JSON' }, 400); }
    const rawDvars = body.dvars || {};
    // Only accept identifier-shaped dvar names, and strip quotes/newlines from values, so a
    // crafted name/value can't inject extra cfg lines or break out of the quoted value.
    // 1024-char cap (raised from 256): sv_maprotation is a legit long value (~600 chars for a full
    // 26-map rotation). Injection safety comes from stripping " \r \n ; — a longer value still can't
    // break out of the quoted `set x "v"` line or chain a second command — not from the length.
    const dvars = {};
    for (const k of Object.keys(rawDvars)) {
      if (/^[A-Za-z0-9_]+$/.test(k)) dvars[k] = String(rawDvars[k]).replace(/["\r\n;]/g, '').slice(0, 1024);
    }
    const cfgPath = CFG_PATH;   // pinned: never honor a caller-supplied path (arbitrary-write guard)
    if (!Object.keys(dvars).length) return sendJson(res, { ok: false, error: 'No valid dvars to save' }, 400);
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

  // ── GET /api/secrets ── profile-name → rcon_password map from the gitignored file
  if (req.method === 'GET' && pathname === '/api/secrets') {
    return sendJson(res, { ok: true, profiles: loadSecrets() });
  }

  // ── POST /api/secrets ── upsert one profile's password into the gitignored file
  if (req.method === 'POST' && pathname === '/api/secrets') {
    let body;
    try { body = JSON.parse(await readBody(req)); } catch (_) { return sendJson(res, { ok: false, error: 'Bad JSON' }, 400); }
    const name = String(body.name == null ? '' : body.name).slice(0, 64).trim();
    if (!name) return sendJson(res, { ok: false, error: 'Missing profile name' }, 400);
    const pass = String(body.pass == null ? '' : body.pass).slice(0, 256);
    try { saveSecret(name, pass); return sendJson(res, { ok: true }); }
    catch (err) { return sendJson(res, { ok: false, error: err.message }); }
  }

  // ── GET /api/prefs ── panel UI state (the FAVORITES pinboard)
  if (req.method === 'GET' && pathname === '/api/prefs') {
    return sendJson(res, { ok: true, prefs: loadPrefs() });
  }

  // ── POST /api/prefs ── replace the pinboard. Bounded on purpose: the entries are row keys
  // ("dv:<dvar>" / "lb:<tab>|<block>|<label>"), not free text, so cap the count and the length.
  if (req.method === 'POST' && pathname === '/api/prefs') {
    let body;
    try { body = JSON.parse(await readBody(req)); } catch (_) { return sendJson(res, { ok: false, error: 'Bad JSON' }, 400); }
    if (!Array.isArray(body.favs)) return sendJson(res, { ok: false, error: 'favs must be an array' }, 400);
    const favs = body.favs.filter(k => typeof k === 'string').slice(0, 200).map(k => k.slice(0, 120));
    try {
      const prefs = loadPrefs();
      prefs.favs = favs;
      savePrefs(prefs);
      return sendJson(res, { ok: true });
    } catch (err) { return sendJson(res, { ok: false, error: err.message }); }
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
        // Batch commands are writes (`set ...`, bridge triggers) that don't echo a reply, so
        // don't wait the full RCON_TIMEOUT for one — a short window keeps them snappy.
        const buf      = await sendRconQueued(host, parseInt(port), password, command, 200, 700);
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
