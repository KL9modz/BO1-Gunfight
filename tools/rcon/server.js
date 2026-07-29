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
// enters the repo. Shape: { "profiles": { "<profile name>": "<rcon_password>" } }. The browser
// never receives these values (see "Credentials" below): it sends profile=<name> and THIS
// process does the lookup. See secrets.local.json.example.
const SECRETS_PATH = path.join(__dirname, 'secrets.local.json');
// Per-profile host/port, GITIGNORED for a different reason: a real server IP is infrastructure
// disclosure and must not sit in a tracked file. This is the ONLY place a non-loopback host
// lives — the built-in fallback (here and in app.js) is loopback-only, so a fresh clone of this
// repo names no machine at all. Shape:
//   { "profiles": [ { "name": "Local", "host": "127.0.0.1", "port": "28960" }, … ] }
// Absent is normal → the loopback-only fallback. See servers.local.json.example.
const SERVERS_PATH = path.join(__dirname, 'servers.local.json');
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
// Column reading: END-ANCHORED, always. Player NAMES CAN CONTAIN SPACES (the bot "MCG
// Gordon" is the canonical case), so the name is not a single token — a fixed p[4]/p[6]
// split misreads a spaced name AND shifts every trailing column one right. So we index
// the fixed trailing columns from the END (address = 3rd-from-last) and take everything
// between guid and lastmsg as the name (matches status_service.ps1).
//
// Bot detection: a POSITIVE identification, never a fallback. Three states:
//   bot === false  — addr is a real ip:port, or a listen-server loopback  → a human
//   bot === true   — guid is 0 AND addr is a known non-routable bot marker ("unknown")
//   bot === null   — WE COULD NOT TELL. A row we can't read: a still-connecting client, a
//                    reply split across UDP packets, a column shape we don't know.
//
// That third state is the whole point, and it is load-bearing. This used to be
//     isBot = !(isLocal || isIpPort(addr))          // "not provably human ⇒ bot"
// and the panel's Kick All Bots button clientkick'd everything the flag marked — so ANY row
// the parser failed to read got a REAL PLAYER kicked. (The end-anchoring above was the right
// fix for the spaced-name bug; flipping the polarity to negative alongside it was not, and
// nobody caught it because the bug being chased ran the OTHER way, bot-counted-as-human.)
// A guess must never be able to drive a destructive action: bot===true is now a claim, and
// callers that act on it must require exactly that — never `!p.bot`, never a truthiness test.
// The kick path no longer reads this at all; it goes through the GSC bridge (botkickall),
// which resolves identity server-side with istestclient(). Keep it that way.
// Local player:  address == "loopback"

// ⚠ The port may be NEGATIVE: Plutonium prints it as a signed 16-bit value, so any client
// whose source port is >32767 shows as `ip:-NNNNN` (e.g. 52978 → :-12558). `-?` on the port
// is load-bearing — without it ~half of all real players fail this test and lose IP/notify/
// history. The IP itself is always valid; extraction is split(':')[0], so the sign is dropped.
const IP_PORT_RE  = /^\d{1,3}(\.\d{1,3}){3}:-?\d+$/;
const BOT_ADDR_RE = /^(unknown|bot|0\.0\.0\.0(:\d+)?)$/i;

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
      const isHuman = isLocal || IP_PORT_RE.test(addr);
      // Positive on BOTH signals, or we don't claim it. A bot is guid 0 at a non-routable
      // address; a human is a routable one. Anything else stays null (unclassifiable) and no
      // caller may act on it — see the header. Failing to classify must never kick someone.
      const isBot   = !isHuman && p[3] === '0' && BOT_ADDR_RE.test(addr);
      const bot     = isHuman ? false : (isBot ? true : null);
      if (isLocal) result.listenServer = true;
      const ip      = isHuman ? (isLocal ? 'local' : addr.split(':')[0]) : null;
      result.players.push({
        num:   parseInt(p[0]),
        score: parseInt(p[1]),
        ping:  parseInt(p[2]),
        guid:  p[3],
        name,
        bot,
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
  const obj = readJsonFile(DVAR_DEAD_FILE);   // hoisted; see the Credentials section below
  const m = new Map();
  if (obj) for (const k of Object.keys(obj)) if (Array.isArray(obj[k])) m.set(k, new Set(obj[k]));
  return m;
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
  // format: "wA:wX:round:aliveA:aliveX:gametype:hold:fillN:pAllies:pAxis:parked:botDiff"
  // (hold added 2026-07-05, fill fields 8-11 added 2026-07-08, botDiff added 2026-07-16; older
  // servers omit trailing fields → parts[i] undefined → sane defaults, so this stays back-compatible)
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
    botDiff:    parts[11] !== undefined                    // live bot difficulty preset (null = server predates it)
                  ? String(parts[11]).replace(/\^\d/g, '').trim().toLowerCase()
                  : null,
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

// ─── Credentials: how a request resolves to host / port / rcon_password ───────
//
// GOAL: nobody types a password or an IP, in any of the three contexts —
//   1) laptop browser  → this laptop's own listen / local dedicated server (loopback)
//   2) laptop browser  → the VPS. PREFERRED: an SSH tunnel to the VPS's OWN panel, which resolves
//      its credentials box-side and never puts anything on the wire in the clear:
//        ssh -L 3000:127.0.0.1:3000 gf-vps    → http://127.0.0.1:3000, profile "Local"
//      Direct public rcon is supported but OPT-IN (add the host to servers.local.json), because
//      buildPacket() puts the password in a CLEARTEXT UDP payload — no challenge, no replay
//      protection — so anyone on-path recovers it from one packet.
//   3) the VPS box's own browser → that box's dedicated server (loopback)
//
// TWO gitignored side-files, joined on the profile NAME:
//   servers.local.json   name → host/port        (the only place a real IP lives)
//   secrets.local.json   name → rcon_password
// Absent is always normal. With NEITHER file the panel still covers contexts 1 and 3 unassisted:
// the fallback profile is Local → 127.0.0.1:28960, and seedLoopbackPasswords() below lifts its
// password straight out of dedicated.cfg.
//
// PRECEDENCE — decided by PRESENCE, never by truthiness. A request may carry `profile`, or
// explicit `host`/`port`/`password`, or both:
//   • an explicitly PRESENT password wins, EVEN WHEN IT IS THE EMPTY STRING. A server with no
//     rcon_password is a supported config, so '' cannot be overloaded to mean "unset". This is
//     also the backward-compat path that keeps the box services working untouched — status_service,
//     join-notify, watchdog and ts_sample all send an explicit password= and must keep doing so.
//   • otherwise `profile` resolves the password here, so it never enters a URL or a POST body.
//   • explicit host/port likewise override the profile's; an UNKNOWN profile is a hard 400, never
//     a silent fall-through to the loopback defaults (that would fire rcon at whatever server is
//     running on this box — on the VPS, the live one).
//   • a KNOWN profile with NO entry in secrets.local.json is a hard 400 for the same reason, and
//     never a blank password on the wire. Plutonium answers a wrong-or-blank rcon password with
//     NOTHING AT ALL, so such a packet's only visible outcome is "Server not responding (timeout)"
//     — byte-identical to a server that is down, which sends the operator hunting the wrong thing.
//     The two side-files are joined on a free-text NAME, so a rename in only one of them lands
//     exactly here. An explicit "" entry stays valid: that is a server with no rcon_password.
//   • a PRESENT-but-empty `profile` key is a hard 400 too, never a fall-through to the loopback
//     defaults. The browser holds profile='' until GET /api/servers resolves, so a Connect click
//     in that window would otherwise fire a blank-password packet at 127.0.0.1:28960.
// ⚠ The browser must OMIT the password key entirely when the user has not typed one. Sending
// `password=` (empty) reads as an explicit blank override and profile resolution never runs.

// Read + parse a JSON side-file. ABSENT is normal (a fresh clone has no local files) → null,
// silently. PRESENT-but-unparseable is NOT, and is reported once PER CORRUPTION EVENT — otherwise
// the symptom is invisible (no passwords / no profiles / a re-probed dvar cache, with nothing in
// any log).
// ⚠ "Once" is ENFORCED here, not merely intended. EVERY reader goes through this function and BOTH
// credential files are read on EVERY HTTP request (resolveConnParams → findServer → loadServers,
// and → secretFor → loadSecrets), so an unconditional report is one log line PER API CALL (measured:
// exactly 1.00/call) — and since saveSecret below now REFUSES to overwrite a store it cannot parse,
// that state persists until a human fixes it instead of self-healing destructively on the next save.
// With the panel's stdout redirected to an unpruned log file and the UI ticking ~1 Hz, that is
// ~6.6 MB/day of one repeated line. Dedupe key = the file's mtime+size, so a report fires AGAIN
// whenever the file changes and is STILL corrupt (every fix attempt stays visible), and the entry is
// dropped the moment it parses or the file disappears — a plain "already reported" flag would also
// mute the next, different corruption, forever.
// ⚠ The dedupe state hangs off the FUNCTION OBJECT, not a module-level `const` beside it:
// readJsonFile is called during module init (the dead-dvar cache ~230 lines above), where a `const`
// declared down here is still in its temporal dead zone — reading one from that call is a
// ReferenceError before listen(), i.e. the panel never boots at all (verified).
// ⚠ A leading BOM makes JSON.parse THROW. PowerShell's `Set-Content -Encoding UTF8` writes one,
// so every writer of these files must use UTF-8 WITHOUT a BOM (setup_rcon_vps.ps1 does); we strip
// one defensively here so a hand-edited file can't silently blank the panel's credentials.
// ⚠ EVERY reader of these files goes through here — including the ones on a WRITE path (saveSecret
// reads the current store before rewriting it). A second, raw JSON.parse anywhere makes the two
// paths disagree about the same file: a BOM'd store that READS fine would fail only on write, and
// a swallowed failure there is silent data loss rather than a loud, uniform "no passwords".
// ⚠ The failure report prints e.NAME, never e.message. V8 quotes the offending INPUT back inside a
// parse message whenever the failure sits at or near position 0 — `JSON.parse('PASSWORDLEAK{…}')`
// yields `Unexpected token 'P', "PASSWORDLE"... is not valid JSON` (measured, node v24). This
// reader runs over secrets.local.json, so a store mangled at the head would echo its own leading
// bytes to the console, and to disk behind any log redirect. "SyntaxError" says all we need.
function readJsonFile(file) {
  const fails = readJsonFile._fails || (readJsonFile._fails = new Map());   // file -> reported signature
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); } catch (_) { fails.delete(file); return null; }
  try { const obj = JSON.parse(raw.replace(/^\uFEFF/, '')); fails.delete(file); return obj; }
  catch (e) {
    // The signature of THIS corruption. A rewrite (new mtime/size) is a new event and reports
    // again; a failed stat can't mute anything either, since the length moves as the file changes.
    let sig;
    try { const st = fs.statSync(file); sig = st.mtimeMs + ':' + st.size; } catch (_) { sig = 'nostat:' + raw.length; }
    if (fails.get(file) !== sig) {
      fails.set(file, sig);
      console.error(`  ! ${path.basename(file)} is present but unreadable (${(e && e.name) || 'parse error'}) — ignoring it`);
    }
    return null;
  }
}

// ─── Secrets (gitignored rcon_password store) ─────────────────────────────────
// A profile-name → rcon_password map kept OUT of git in secrets.local.json. A missing file is
// not an error — a fresh clone just has no saved passwords yet. A file that is present but
// unparseable is (readJsonFile says so once): it looks identical from here, and silently having
// zero passwords is how "Connect fails auth for no reason" happened.
function loadSecrets() {
  const obj = readJsonFile(SECRETS_PATH);
  if (obj && obj.profiles && typeof obj.profiles === 'object') return obj.profiles;
  return {};
}
// Passwords this PROCESS is holding for the session because the store refused the write (a corrupt
// or unwritable secrets.local.json — see saveSecret). Memory only, never persisted, gone on restart.
// It exists so the credential does not have to live in the BROWSER on that path: the page would then
// have to attach it to every request, and the polled ones are GETs, which puts a password in a query
// string ~1 Hz for the whole session. Registered ONCE via POST /api/secrets (a JSON body) and
// resolved here from the profile name, exactly like the on-disk store.
// ⚠ Same blank rule as saveSecret: '' means "this server has no rcon_password", so it CLEARS the
// held value rather than holding an empty one — a blank must never be dressed up as a credential.
// ⚠ GET /api/secrets deliberately still reports the DISK store only: it answers "what is saved".
const sessionSecrets = new Map();   // lowercased profile name -> password
function rememberSessionSecret(name, pass) {
  const k = String(name).toLowerCase();
  if (pass === '') sessionSecrets.delete(k);
  else sessionSecrets.set(k, pass);
}
// One profile's password, or undefined if it has none saved. Case-insensitive fallback: the two
// side-files are joined on a free-text name, so a case drift between them would otherwise read as
// "no password saved" and surface only as an auth timeout.
function secretFor(name) {
  const s = loadSecrets();
  if (Object.prototype.hasOwnProperty.call(s, name)) return s[name];
  const k = Object.keys(s).find((k2) => k2.toLowerCase() === String(name).toLowerCase());
  if (k !== undefined) return s[k];
  // Nothing on disk: fall back to a session-held password. The disk store always WINS — a saved
  // credential is the authoritative one, and a stale held value must never shadow it.
  const sk = String(name).toLowerCase();
  return sessionSecrets.has(sk) ? sessionSecrets.get(sk) : undefined;
}
// Upsert ONE profile's password, preserving every other entry in the store.
// ⚠ The read-before-write MUST use readJsonFile — the same BOM-tolerant reader loadSecrets() uses —
// and a present-but-unreadable store MUST refuse the write. This used to be a raw JSON.parse inside
// a swallow-everything catch, which made the two paths disagree about the same file: a BOM'd store
// (PowerShell's `Set-Content -Encoding UTF8` writes one) READ perfectly, so the panel showed every
// profile as having a password, while the next write threw on the BOM, fell into the empty catch and
// rewrote the whole file with only the profile being saved — every other password gone, reply
// {ok:true}. It also fires UNATTENDED: seedLoopbackPasswords() calls this before listen(), so merely
// restarting the panel could destroy the store with no user action. A destructive rewrite must never
// be reachable from a parse failure — the throw below surfaces via handle() as { ok:false, error }.
function saveSecret(name, pass) {
  let obj = { profiles: {} };
  if (fs.existsSync(SECRETS_PATH)) {
    const cur = readJsonFile(SECRETS_PATH);
    if (!cur || typeof cur !== 'object' || Array.isArray(cur)) {
      throw new Error('secrets.local.json is present but unreadable — refusing to overwrite it (fix or remove the file, then retry)');
    }
    obj = cur;
  }
  if (!obj.profiles || typeof obj.profiles !== 'object') obj.profiles = {};
  if (pass === '') delete obj.profiles[name];   // don't persist blank entries
  else obj.profiles[name] = pass;
  // ATOMIC: write a sibling temp file, then RENAME it over the store. A truncate-in-place
  // writeFileSync leaves a half-written file if the process dies mid-write — and this process is
  // killed routinely (Task Scheduler stop, deploy.ps1's panel recycle, a reboot). That used to
  // self-heal destructively on the next save; with the refusal above it is now PERMANENT: the store
  // reads as zero passwords and every subsequent save is refused until a human repairs it by hand.
  // rename() within a volume is atomic, so a kill at any instant leaves either the whole old file or
  // the whole new one — never a truncated store.
  // ⚠ The temp MUST stay a sibling (same folder = same volume). A %TEMP% path would make this a
  // cross-volume copy, which is exactly the non-atomic write we are removing.
  // ⚠ `secrets.local.json.tmp` is covered by all three secret-store layers — .gitignore's
  // `tools/rcon/secrets.local.*`, the pre-commit hook's `*secrets.local.*` case, and
  // release_common.ps1's `secrets.local.*` glob — and it does NOT end in `.example`, so the
  // committable-template exemption does not reach it. Any rename here must keep that true.
  // fs.writeFileSync defaults to UTF-8 with NO BOM — keep it that way (see readJsonFile).
  const tmp = SECRETS_PATH + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n');
  try { fs.renameSync(tmp, SECRETS_PATH); }
  catch (e) { try { fs.unlinkSync(tmp); } catch (_) {} throw e; }   // never leave the temp behind
}

// ─── Server list (gitignored host/port store) ─────────────────────────────────
// The panel's profile dropdown. Read PER REQUEST (like prefs/secrets) so editing the file takes
// effect on the next page load — on the VPS the panel is a SYSTEM scheduled task, and needing a
// restart to add a server would make a 10-second edit a two-command detour.
// Missing file → the loopback-only fallback, which is the whole point: a clone with no local
// files still drives the server on its own box, and names no other machine.
const FALLBACK_SERVER = { name: 'Local', host: '127.0.0.1', port: '28960' };
function loadServers() {
  const obj = readJsonFile(SERVERS_PATH);
  const out = [];
  const seen = new Set();
  if (obj && Array.isArray(obj.profiles)) {
    for (const e of obj.profiles) {
      if (!e || typeof e !== 'object') continue;
      const name = String(e.name == null ? '' : e.name).trim().slice(0, 64);
      if (!name || seen.has(name.toLowerCase())) continue;   // the name is the join key — no dupes
      seen.add(name.toLowerCase());
      out.push({
        name,
        host: String(e.host == null ? '' : e.host).trim() || FALLBACK_SERVER.host,
        port: String(e.port == null ? '' : e.port).trim() || FALLBACK_SERVER.port,
      });
    }
  }
  return out.length ? out : [FALLBACK_SERVER];
}
function findServer(name) {
  const want = String(name).trim().toLowerCase();
  return loadServers().find((s) => s.name.toLowerCase() === want) || null;
}

// ─── Auto-seed: the loopback profile's password, straight from dedicated.cfg ───
// setup_rcon_vps.ps1 does this ON the VPS; this is the laptop-side equivalent, so a fresh clone
// needs zero typing to drive the server on its own box. Runs ONCE at startup, before listen().
// ⚠ Never overwrites a password already saved, and never throws — no cfg at all is the normal
// case for a clone with no server on the machine.
// ⚠ On the LAPTOP this is a best guess, not a fact: the local dedicated server is launcher-started
// WITHOUT `+exec dedicated.cfg`, and an in-game listen server takes its rcon_password from the
// client's own config — so the cfg's value may never have been the live one. A wrong password
// reads as a bare "Server not responding (timeout)", indistinguishable from a server that is down.
// Typing the real one into the panel once saves it over this seed permanently (the seed then never
// fires again — `secretFor(...) == null` is false forever after).
// ⚠ Because the guess is one-shot and permanent, it fires ONLY for a lobby with exactly ONE
// loopback profile — which is every zero-typing context by construction (laptop → its own server;
// VPS box's own browser; laptop → VPS over the SSH tunnel, where the tunnel lands on the BOX's
// panel and its one 'Local'). List two loopback servers and the cfg's single rcon_password can
// belong to at most one of them, so seeding both would hand one a foreign credential that then
// looks permanent and typed. In that case nothing is seeded and the log says why.
// ⚠ The guess is not invisible either: GET /api/servers reports `seeded` for a saved password that
// still equals the cfg's, so the panel can say WHERE the credential came from and a timeout points
// at the credential instead of at the server.
const CFG_CANDIDATES = [
  CFG_PATH,                                                          // storage/t5/dedicated.cfg — the real one
  path.resolve(__dirname, '..', '..', '..', '..', 'main', 'dedicated.cfg'),
  path.resolve(__dirname, '..', '..', 'dedicated.cfg'),              // mod root
  path.join(__dirname, 'dedicated.cfg'),                             // beside the panel
];
// Same shape as tools/common.ps1's Get-RconPassword: `seta` counts, quotes around the NAME are
// optional, and the ^ anchor is what stops a commented-out line from matching.
const RCON_PW_RE = /^\s*set[as]?\s+"?rcon_password"?\s+"([^"]*)"/im;
const LOOPBACK_RX = /^(127\.\d+\.\d+\.\d+|localhost|::1|\[::1\])$/i;
// The cfg's rcon_password and which cfg it came from, or { pw: null }. Read on DEMAND, like the two
// side-files: the seed calls it once at startup, GET /api/servers calls it per page load to tell a
// cfg-DERIVED password from a typed one.
function cfgRconPassword() {
  for (const f of CFG_CANDIDATES) {
    let txt; try { txt = fs.readFileSync(f, 'utf8'); } catch (_) { continue; }
    if (txt.charCodeAt(0) === 0xFEFF) txt = txt.slice(1);   // same BOM tolerance as readJsonFile
    const m = txt.match(RCON_PW_RE);
    if (m) return { pw: m[1], from: f };
  }
  return { pw: null, from: null };
}
function seedLoopbackPasswords() {
  try {
    const loopbacks = loadServers().filter((s) => LOOPBACK_RX.test(s.host));
    const targets   = loopbacks.filter((s) => secretFor(s.name) == null);
    if (!targets.length) return;                       // nothing to seed / already saved
    // ONE cfg password, so at most ONE loopback profile may claim it. With two local servers listed
    // we would be guessing which — and the guess writes itself in permanently. Seed nothing, say why.
    if (loopbacks.length > 1) {
      console.log(`  ${loopbacks.length} loopback profiles (${loopbacks.map((s) => `'${s.name}'`).join(', ')}) — the cfg's rcon_password belongs to at most one of them, so nothing was seeded. Type each one into the panel once.`);
      return;
    }
    const { pw, from } = cfgRconPassword();
    if (pw === null) { console.log(`  no rcon_password found in a dedicated.cfg (looked from ${CFG_PATH}) — nothing seeded`); return; }
    if (pw === '') return;                             // cfg sets a blank password: nothing to save
    saveSecret(targets[0].name, pw);                   // NEVER logged, only its length
    console.log(`  seeded rcon_password for '${targets[0].name}' from ${from} (${pw.length} chars) — the panel flags it as cfg-derived until one is typed`);
  } catch (e) { console.error('  ! rcon_password auto-seed skipped: ' + (e && e.message)); }
}

// ─── Panel prefs (gitignored UI state — see PREFS_PATH) ───────────────────────
// A missing file is not an error: a fresh clone simply has no pinboard yet, and the UI falls back
// to its localStorage cache (and to the seeded defaults) in that case. A present-but-unparseable
// one is reported by readJsonFile, then treated the same way.
function loadPrefs() {
  const obj = readJsonFile(PREFS_PATH);
  return (obj && typeof obj === 'object') ? obj : {};
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

// ─── Shared endpoint helpers ────────────────────────────────────────────────────
// Resolve a request's connection params from a GET query object OR a POST body — see the
// "Credentials" section above for the precedence rules. Returns { host, port, p, password } with
// `p` the parsed integer port and `port` its string twin (they always agree), or { error } for an
// unknown profile.
// ⚠ PRESENCE, not truthiness: `password` is only defaulted when the key is ABSENT. A destructuring
// default (`password = ''`) fires on undefined only, so it silently erased the difference between
// "no password supplied, resolve it" and "this server has no rcon_password" — the second is a
// supported config, so the two must stay distinguishable.
// ⚠ Every coalescing key downstream is built from the RESOLVED host/p, never from the raw query.
// Keying off the raw fields would (a) collapse every profile onto one key once the browser stopped
// sending host/port, merging two panels' replies, and (b) split the browser's key from the box
// services' explicit-host key, quietly doubling rcon load on the one 850ms lane.
function resolveConnParams(src) {
  const q = src || {};
  const has = (k) => Object.prototype.hasOwnProperty.call(q, k) && q[k] !== undefined;
  let host     = has('host')     && String(q.host).trim()     !== '' ? String(q.host).trim()     : undefined;
  let port     = has('port')     && String(q.port).trim()     !== '' ? String(q.port).trim()     : undefined;
  let password = has('password') ? String(q.password) : undefined;   // '' is an explicit override
  // PRESENCE again, not truthiness: `profile` PRESENT-but-blank is an error, not "no profile".
  // Truthiness sent `?profile=` down the no-profile path, i.e. straight to the loopback defaults
  // with a blank password — reachable from the browser, which initialises its active profile to ''
  // and only fills it in once GET /api/servers answers.
  const rawProfile = has('profile') ? q.profile : undefined;
  const wanted = rawProfile == null ? '' : String(rawProfile).trim();
  if (rawProfile !== undefined && wanted === '') {
    return { error: 'Empty server profile — send profile=<name>, or omit the key entirely for the loopback default' };
  }
  if (wanted) {
    const prof = findServer(wanted);
    if (!prof) return { error: `Unknown server profile "${wanted}" (see servers.local.json)` };
    if (host === undefined)     host = prof.host;
    if (port === undefined)     port = prof.port;
    if (password === undefined) {
      const s = secretFor(prof.name);
      // '' is a real config ("this server has no rcon_password"); NO ENTRY is not, and must not be
      // flattened into it — see the Credentials header. Name the profile and both remedies, because
      // the wire symptom of guessing here is a bare timeout that accuses the server instead.
      if (s == null) return { error: `No rcon_password saved for server profile "${prof.name}" — type it into the panel's password box once (it is stored in secrets.local.json, never in the browser), or add "${prof.name}": "" to that file if this server genuinely has none` };
      password = String(s);
    }
  }
  // Normalise the port ONCE so every cache/coalescing key agrees ('28960' from one caller and
  // 28960 from another used to build two different key strings for the same server).
  const p = parseInt(port === undefined ? '28960' : port, 10) || 28960;
  return { host: host === undefined ? '127.0.0.1' : host, port: String(p), p, password: password === undefined ? '' : password };
}
// Same, but responds 400 and returns null on an unknown profile — so an endpoint reads
// `const c = resolveConn(x, res); if (!c) return;` (same "already responded, bail" shape as
// readJsonBody). ⚠ An unresolvable profile must NEVER fall through to the loopback defaults: that
// would aim rcon at whatever server happens to run on this box (on the VPS, the live one).
function resolveConn(src, res) {
  const c = resolveConnParams(src);
  if (c.error) { sendJson(res, { ok: false, error: c.error }, 400); return null; }
  return c;
}

// Read + JSON-parse a request body. On malformed JSON, respond 400 and return undefined — since
// JSON.parse never yields undefined, `body === undefined` uniquely means "already responded, bail".
async function readJsonBody(req, res) {
  try { return JSON.parse(await readBody(req)); }
  catch (_) { sendJson(res, { ok: false, error: 'Bad JSON' }, 400); return undefined; }
}

// Run an async endpoint body, funnelling any throw into the standard { ok:false, error } tail so
// each endpoint no longer repeats the same try/catch.
async function handle(res, fn) {
  try { return await fn(); }
  catch (err) { return sendJson(res, { ok: false, error: err.message }); }
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
    const c = resolveConn(query, res); if (!c) return;
    const { host, password, p } = c;
    return handle(res, async () => {
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
    });
  }

  // ── GET /api/status ──
  if (req.method === 'GET' && pathname === '/api/status') {
    const c = resolveConn(query, res); if (!c) return;
    const { host, password, p } = c;
    return handle(res, async () => {
      const statusBuf = await sendRconQueuedKeyed(`status:${host}:${p}`, host, p, password, 'status');
      const text = parseRconResponse(statusBuf);
      const data = parseStatusText(text);
      return sendJson(res, { ok: true, ...data, raw: text });
    });
  }

  // ── GET /api/maprotation ── the live server rotation. Reads two plain engine dvars in one send:
  //   sv_maprotation        — the full configured order ("gametype gf map mp_array …")
  //   sv_maprotationcurrent — the not-yet-played remainder; its HEAD is the next map the engine
  //                           loads at match end. Both are writable over rcon, so the panel drives
  //                           the engine's own rotation instead of racing it with a reactive `map`.
  // Answers on dedicated AND listen (engine dvars, unlike gf_state). Coalesced under a keyed lane.
  if (req.method === 'GET' && pathname === '/api/maprotation') {
    const c = resolveConn(query, res); if (!c) return;
    const { host, password, p } = c;
    return handle(res, async () => {
      const buf  = await sendRconQueuedKeyed(`maprot:${host}:${p}`, host, p, password, 'sv_maprotation;sv_maprotationcurrent');
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
    });
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
    return handle(res, async () => sendJson(res, await geoResolve(ip)));
  }

  // ── GET /api/dvars ── batch-read dvar values: ?names=a,b,c (read-only, chunked)
  if (req.method === 'GET' && pathname === '/api/dvars') {
    const c = resolveConn(query, res); if (!c) return;
    const { host, password, p } = c;   // p (not the raw query port) also keys the dead-dvar cache
    const { names = '', fresh = '' } = query;
    const list = names.split(',').map(s => s.trim()).filter(Boolean);
    if (!list.length) return sendJson(res, { ok: false, error: 'No dvar names' }, 400);
    return handle(res, async () => {
      const values = await readDvars(host, p, password, list, fresh === '1' || fresh === 'true');
      return sendJson(res, { ok: true, values });
    });
  }

  // ── POST /api/rcon ──
  // `priority:true` (bridge command writes) uses the high lane + short reply window: a `set`
  // echoes nothing useful, so we don't hold the lane for the full RCON_TIMEOUT — the panel marks
  // the command "sent" optimistically and confirms it via the gf_ack poll (/api/ack) anyway.
  if (req.method === 'POST' && pathname === '/api/rcon') {
    const body = await readJsonBody(req, res);
    if (body === undefined) return;
    const c = resolveConn(body, res); if (!c) return;
    const { host, password, p } = c;
    const { command, priority = false } = body;
    if (!command) return sendJson(res, { ok: false, error: 'Missing command' }, 400);
    return handle(res, async () => {
      const buf = priority
        ? await sendRconPriority(host, p, password, command, 150, 700)
        : await sendRconQueued(host, p, password, command);
      const response = parseRconResponse(buf);
      return sendJson(res, { ok: true, response });
    });
  }

  // ── GET /api/ack ── high-priority read of gf_ack (last processed command seq). The panel polls
  // this right after sending a bridge command to flip it from "sent" to "received".
  if (req.method === 'GET' && pathname === '/api/ack') {
    const c = resolveConn(query, res); if (!c) return;
    const { host, password, p } = c;
    return handle(res, async () => {
      const buf  = await sendRconPriorityKeyed(`ack:${host}:${p}`, host, p, password, 'gf_ack', 150, 700);
      const text = parseRconResponse(buf);
      const val  = parseDvarValue(text, 'gf_ack');
      return sendJson(res, { ok: val !== null, ack: val !== null ? (parseInt(val) || 0) : 0 });
    });
  }

  // ── POST /api/savecfg ── persist dvars to dedicated.cfg (upsert; makes a .bak)
  if (req.method === 'POST' && pathname === '/api/savecfg') {
    const body = await readJsonBody(req, res);
    if (body === undefined) return;
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
    return handle(res, async () => {
      if (!fs.existsSync(cfgPath)) return sendJson(res, { ok: false, error: 'dedicated.cfg not found at ' + cfgPath }, 404);
      const orig = fs.readFileSync(cfgPath, 'utf8');
      fs.writeFileSync(cfgPath + '.bak', orig);                       // safety backup (last save)
      const eol = orig.includes('\r\n') ? '\r\n' : '\n';
      const { text, updated, added } = upsertCfg(orig, dvars, eol);
      fs.writeFileSync(cfgPath, text);
      return sendJson(res, { ok: true, updated, added, count: Object.keys(dvars).length, path: cfgPath });
    });
  }

  // ── GET /api/servers ── the panel's profile list: name + host/port, and whether a password is
  // saved for it. NEVER a password. This replaces the hardcoded profile list the page used to
  // carry, so the gitignored servers.local.json is the single source of truth for every browser
  // pointed at this panel — fixing the file fixes the panel, with no localStorage to clear.
  // `seeded` is PROVENANCE, not doubt: this profile's saved password is still the one sitting in
  // dedicated.cfg, i.e. it was auto-read rather than typed. On the VPS the cfg IS authoritative and
  // the flag is inert; on the laptop the cfg's value may never have been live (the local server is
  // launcher-started without `+exec dedicated.cfg`), and a wrong password answers with silence, so
  // the panel can point a timeout at the credential. Derived by comparison — no extra state, no
  // change to the secrets file shape, and it clears itself the moment a different one is typed.
  if (req.method === 'GET' && pathname === '/api/servers') {
    const list  = loadServers();
    const cfgPw = list.some((s) => LOOPBACK_RX.test(s.host)) ? cfgRconPassword().pw : null;
    const profiles = list.map((s) => {
      const saved = secretFor(s.name);
      return { name: s.name, host: s.host, port: s.port, hasPass: saved != null,
               seeded: cfgPw !== null && cfgPw !== '' && saved === cfgPw };
    });
    return sendJson(res, { ok: true, profiles });
  }

  // ── GET /api/secrets ── PRESENCE ONLY: { "<profile>": true }. Never the values.
  // This used to hand the browser every stored password in one JSON reply, which the page then
  // planted in a DOM input — so anything running on the page origin (an extension with page
  // access, an injected snippet) could read the whole store in a single request. The panel no
  // longer needs them at all: it sends profile=<name> and this process does the lookup.
  if (req.method === 'GET' && pathname === '/api/secrets') {
    const have = {};
    for (const k of Object.keys(loadSecrets())) have[k] = true;
    return sendJson(res, { ok: true, profiles: have });
  }

  // ── POST /api/secrets ── upsert one profile's password into the gitignored file.
  // This POST body is the ONE channel a credential travels on, by design: a named profile's request
  // then carries only profile=<name>, so nothing ends up in a GET query string (see the app.js
  // conn() note). When the store REFUSES the write — corrupt file, read-only folder — the password
  // is held in this process for the session instead of being handed back to the page to re-send on
  // every poll, and the reply says so with `session:true` so the panel can label it accurately
  // ("held, not saved") rather than claiming a save that did not happen.
  if (req.method === 'POST' && pathname === '/api/secrets') {
    const body = await readJsonBody(req, res);
    if (body === undefined) return;
    const name = String(body.name == null ? '' : body.name).slice(0, 64).trim();
    if (!name) return sendJson(res, { ok: false, error: 'Missing profile name' }, 400);
    const pass = String(body.pass == null ? '' : body.pass).slice(0, 256);
    return handle(res, async () => {
      try { saveSecret(name, pass); }
      catch (e) { rememberSessionSecret(name, pass); return sendJson(res, { ok: false, session: true, error: e.message }); }
      rememberSessionSecret(name, '');   // saved: the disk store is authoritative, drop any held copy
      return sendJson(res, { ok: true });
    });
  }

  // ── GET /api/prefs ── panel UI state (the FAVORITES pinboard)
  if (req.method === 'GET' && pathname === '/api/prefs') {
    return sendJson(res, { ok: true, prefs: loadPrefs() });
  }

  // ── POST /api/prefs ── replace the pinboard. Bounded on purpose: the entries are row keys
  // ("dv:<dvar>" / "lb:<tab>|<block>|<label>"), not free text, so cap the count and the length.
  if (req.method === 'POST' && pathname === '/api/prefs') {
    const body = await readJsonBody(req, res);
    if (body === undefined) return;
    if (!Array.isArray(body.favs)) return sendJson(res, { ok: false, error: 'favs must be an array' }, 400);
    const favs = body.favs.filter(k => typeof k === 'string').slice(0, 200).map(k => k.slice(0, 120));
    return handle(res, async () => {
      const prefs = loadPrefs();
      prefs.favs = favs;
      savePrefs(prefs);
      return sendJson(res, { ok: true });
    });
  }

  // ── POST /api/batch ──
  if (req.method === 'POST' && pathname === '/api/batch') {
    const body = await readJsonBody(req, res);
    if (body === undefined) return;
    const c = resolveConn(body, res); if (!c) return;
    const { host, password, p } = c;
    const { commands = [], delayMs = 80 } = body;
    const results = [];
    for (let i = 0; i < commands.length; i++) {
      const command = commands[i];
      try {
        // Batch commands are writes (`set ...`, bridge triggers) that don't echo a reply, so
        // don't wait the full RCON_TIMEOUT for one — a short window keeps them snappy.
        const buf      = await sendRconQueued(host, p, password, command, 200, 700);
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

// Start the panel only when run directly (`node server.js`). Under require() — the test
// suite (test/server.test.js, node:test) — nothing binds and nothing opens a browser, so
// the pure functions below are testable without a live panel. Module init still reads the
// two box-local caches (harmless), but no socket is opened on this path.
if (require.main === module) {
  seedLoopbackPasswords();   // one shot, before we listen — never throws, never overwrites

  server.listen(WEB_PORT, '127.0.0.1', () => {
    const addr = `http://127.0.0.1:${WEB_PORT}`;
    console.log(`\n  GF RCON Tool  →  ${addr}\n`);
    try { cp.exec(`start ${addr}`); } catch (_) {}
  });
}

// Pure-function surface for the test suite. Every export encodes a past live incident
// (spaced bot names miscounted as humans, the signed 16-bit port dropping half of real
// players' IPs, the bot-flag polarity kicking real players, smart-quote bytes corrupting
// sv_maprotation on save) — the tests are the regression net those incidents never had.
// Exporting is behaviour-neutral: nothing reads module.exports at runtime.
module.exports = {
  parseStatusText, parseGfRoster, parseGfState, parseMapRotation,
  parseDvarValue, parseRconResponse, stripColors, upsertCfg, resolveConnParams,
};
