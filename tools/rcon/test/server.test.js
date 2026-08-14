// Regression net for tools/rcon/server.js's pure functions — zero dependencies, node:test.
//
//   node --test "tools/rcon/test/**/*.test.js"     (or name the file explicitly)
//
// WARNING: a BARE DIRECTORY (node --test tools/rcon/test/) reports "fail 1" on node 24 while the
// suite is actually green - it tries to LOAD the directory as a module (MODULE_NOT_FOUND) instead
// of scanning it. That WAS the documented command here, so a green suite read as broken. Verified
// on node v24.18.0, 2026-08-11: glob and explicit-file forms both pass 34/34, all directory forms
// fail identically.
//
// Every block below encodes a PAST LIVE INCIDENT (the case name says which); these are the
// regression tests those incidents never had. server.js exports its pure surface behind a
// `require.main === module` guard, so requiring it here binds no socket and opens no browser.
//
// ⚠ Deliberately NOT tested: anything file-backed or machine-dependent — profile resolution
// against servers.local.json/secrets.local.json (their presence differs per box; only the
// machine-independent error paths are covered), the rcon queue (network), geo cache (network).

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const srv = require('../server.js');
const shared = require('../../status_parse.js');

// ─── parseStatusText ─────────────────────────────────────────────────────────
// The fixture is SHARED with the PowerShell twin's suite (tools/tests/status_parse.Tests.ps1
// parses the same file), so the two implementations are pinned to one input — a one-sided
// parser edit fails the other side's mirror case. The color-coded row is appended here as a
// string literal rather than living in the fixture: a bare `^N` roster row in a text file is
// exactly the shape the pre-commit status-roster guard exists to block.
const FIXTURE = fs.readFileSync(
  path.join(__dirname, '..', '..', 'tests', 'fixtures', 'status_reply.txt'), 'utf8');
const COLOR_ROW = '  2   857    0       0 ^1LiMi7ED       1092400 unknown                   42  5000';
const STATUS = FIXTURE.trimEnd() + '\n' + COLOR_ROW;

test('parseStatusText: server.js re-exports the SHARED tools/status_parse.js copy (single source)', () => {
  assert.equal(srv.parseStatusText, shared.parseStatusText);
  assert.equal(srv.stripColors, shared.stripColors);
});

test('parseStatusText: map/gametype header', () => {
  const r = srv.parseStatusText(STATUS);
  assert.equal(r.map, 'mp_nuked');
  assert.equal(r.gametype, 'gf');
});

test('parseStatusText: spaced bot name reads as ONE bot, not a shifted human (MCG Gordon incident)', () => {
  const r = srv.parseStatusText(STATUS);
  const gordon = r.players.find(p => p.name === 'MCG Gordon');
  assert.ok(gordon, 'spaced name parsed whole');
  assert.equal(gordon.bot, true);       // guid 0 + addr "unknown" = positive bot claim
  assert.equal(gordon.ip, null);
});

test('parseStatusText: signed 16-bit NEGATIVE port still yields the IP (half-of-all-players incident)', () => {
  const r = srv.parseStatusText(STATUS);
  const p = r.players.find(x => x.name === 'Player One');
  assert.ok(p, 'spaced human name parsed whole');
  assert.equal(p.bot, false);
  assert.equal(p.ip, '203.0.113.7');    // sign dropped, IP kept
});

test('parseStatusText: positive-port human classified with IP', () => {
  const p = srv.parseStatusText(STATUS).players.find(x => x.name === 'Dude');
  assert.equal(p.bot, false);
  assert.equal(p.ip, '198.51.100.3');
});

test('parseStatusText: loopback row marks the listen server and local player', () => {
  const r = srv.parseStatusText(STATUS);
  assert.equal(r.listenServer, true);
  const p = r.players.find(x => x.name === 'KL9');
  assert.equal(p.local, true);
  assert.equal(p.ip, 'local');
  assert.equal(p.bot, false);
});

test('parseStatusText: unreadable row is bot===null, NEVER a claim (kick-a-real-player incident)', () => {
  const p = srv.parseStatusText(STATUS).players.find(x => x.name === 'Joining');
  assert.equal(p.bot, null);            // guid 0 but addr "CNCT" is not a known bot marker
  // The polarity rule: a caller may act only on bot === true. A truthiness test on null
  // is false (safe), but !p.bot on a HUMAN row must never be how a kick decides — assert
  // the three states stay three states.
  const states = new Set(srv.parseStatusText(STATUS).players.map(x => x.bot));
  assert.deepEqual(states, new Set([false, null, true]));
});

test('parseStatusText: nonzero-guid row at a bot address is NOT claimed as a bot', () => {
  const s = STATUS + '\n  7     0    0 1234567 Ghost                 0 unknown                  44  5000';
  const p = srv.parseStatusText(s).players.find(x => x.name === 'Ghost');
  assert.equal(p.bot, null);
});

test('parseStatusText: color codes stripped from names', () => {
  const p = srv.parseStatusText(STATUS).players.find(x => x.name === 'LiMi7ED');
  assert.ok(p, '^1 prefix stripped');
});

test('parseStatusText: malformed/short rows are skipped, not misread', () => {
  const s = STATUS + '\nnot a row\n  9  12\n';
  assert.equal(srv.parseStatusText(s).players.length, 6);
});

test('parseStatusText: non-numeric ping ("CNCT") is null, not NaN', () => {
  const p = srv.parseStatusText(STATUS).players.find(x => x.name === 'Joining');
  assert.equal(typeof p.ping === 'number' ? 'number' : p.ping, 'number');   // 999 in the fixture
  const s = STATUS + '\n  8     0 CNCT       0 MidConnect            0 CNCT                     78  5000';
  const q = srv.parseStatusText(s).players.find(x => x.name === 'MidConnect');
  assert.equal(q.ping, null);
});

test('parseStatusText: headerless reply yields empty map (falsy), and map/gametype strip colors', () => {
  const r = srv.parseStatusText('gametype: gf^7\nno separator here');
  assert.equal(r.map, '');            // '' — a notifier context check must read it as absent
  assert.equal(r.gametype, 'gf');     // ^7 stripped
  assert.equal(r.players.length, 0);
});

// ─── parseGfState ────────────────────────────────────────────────────────────
test('parseGfState: full 12-field telemetry', () => {
  const r = srv.parseGfState('3:2:5:2:1:gf^7:0:3:3:3:1:fu');
  assert.equal(r.winsAllies, 3);
  assert.equal(r.winsAxis, 2);
  assert.equal(r.round, 5);
  assert.equal(r.gametype, 'gf');       // ^7 stripped
  assert.equal(r.lobbyHold, false);
  assert.equal(r.fillN, 3);
  assert.equal(r.parked, 1);
  assert.equal(r.botDiff, 'fu');
});

test('parseGfState: older server omitting trailing fields stays back-compatible', () => {
  const r = srv.parseGfState('0:0:1:2:2:gf:1');
  assert.equal(r.lobbyHold, true);
  assert.equal(r.fillN, null);          // null = server predates fill telemetry (not 0)
  assert.equal(r.botDiff, null);
});

test('parseGfState: under 5 fields is null (not a half-parsed object)', () => {
  assert.equal(srv.parseGfState('1:2:3'), null);
  assert.equal(srv.parseGfState(''), null);
});

// ─── parseGfRoster ───────────────────────────────────────────────────────────
test('parseGfRoster: teams, alive, pending, bot flags', () => {
  const r = srv.parseGfRoster('0,a,1,-,0;3,x,0,a,1;5,s,0,-,0');
  assert.equal(r.length, 3);
  assert.deepEqual(r[0], { num: 0, team: 'allies', alive: true,  pending: '',       bot: false });
  assert.deepEqual(r[1], { num: 3, team: 'axis',   alive: false, pending: 'allies', bot: true  });
  assert.deepEqual(r[2], { num: 5, team: 'spectator', alive: false, pending: '',    bot: false });
});

test('parseGfRoster: garbage segments skipped', () => {
  assert.equal(srv.parseGfRoster('junk;;x,y;7,a,1,-,0').length, 1);
});

// ─── parseMapRotation ────────────────────────────────────────────────────────
test('parseMapRotation: normal rotation string', () => {
  const r = srv.parseMapRotation('gametype gf map mp_array gametype gf map mp_cairo');
  assert.deepEqual(r, [{ gametype: 'gf', map: 'mp_array' }, { gametype: 'gf', map: 'mp_cairo' }]);
});

test('parseMapRotation: bare leading map inherits the running gametype (empty at start)', () => {
  const r = srv.parseMapRotation('map mp_nuked gametype gf map mp_villa');
  assert.deepEqual(r, [{ gametype: '', map: 'mp_nuked' }, { gametype: 'gf', map: 'mp_villa' }]);
});

test('parseMapRotation: Windows-1252 smart-quote bytes stripped, not glued onto tokens (live corruption incident)', () => {
  // A doc paste once put 0x93/0x94 smart quotes into sv_maprotation; unsanitized they glue
  // onto `map` or a map id, dropping/corrupting the next map AND persisting on save.
  const r = srv.parseMapRotation('gametype gf “map” mp_array map mp_cairo');
  assert.deepEqual(r, [{ gametype: 'gf', map: 'mp_array' }, { gametype: 'gf', map: 'mp_cairo' }]);
});

// ─── parseDvarValue ──────────────────────────────────────────────────────────
test('parseDvarValue: quoted value with color code, case-insensitive echo', () => {
  const echo = '"sv_floodprotect" is: "20^7" default: "4^7" Domain is any integer';
  assert.equal(srv.parseDvarValue(echo, 'sv_floodProtect'), '20');   // queried mixed-case
});

test('parseDvarValue: bare value and no-colon form', () => {
  assert.equal(srv.parseDvarValue('"g_speed" is 190 default: 190', 'g_speed'), '190');
});

test('parseDvarValue: miss is null', () => {
  assert.equal(srv.parseDvarValue('Unknown cmd foo', 'sv_hostname'), null);
});

// ─── parseRconResponse ───────────────────────────────────────────────────────
test('parseRconResponse: strips the OOB header line', () => {
  const buf = Buffer.concat([Buffer.from([0xff, 0xff, 0xff, 0xff]), Buffer.from('print\npayload line\n')]);
  assert.equal(srv.parseRconResponse(buf), 'payload line');
});

test('parseRconResponse: no newline falls back to a 4-byte strip', () => {
  const buf = Buffer.concat([Buffer.from([0xff, 0xff, 0xff, 0xff]), Buffer.from('bare')]);
  assert.equal(srv.parseRconResponse(buf), 'bare');
});

// ─── upsertCfg ───────────────────────────────────────────────────────────────
test('upsertCfg: replaces set/seta lines in place, keeps a trailing aligned comment', () => {
  const cfg = ['seta sv_hostname "old"   // shown in the browser', 'set g_speed 190', 'unrelated line'].join('\n');
  const r = srv.upsertCfg(cfg, { sv_hostname: 'new name', g_speed: '200' }, '\n');
  const lines = r.text.split('\n');
  assert.equal(lines[0], 'set sv_hostname "new name"   // shown in the browser');
  assert.equal(lines[1], 'set g_speed "200"');
  assert.equal(lines[2], 'unrelated line');
  assert.equal(r.updated, 2);
  assert.equal(r.added, 0);
});

test('upsertCfg: appends unknown dvars under the managed marker exactly once', () => {
  const r1 = srv.upsertCfg('set g_speed 190', { scr_gf_flinch: '0.5', scr_gf_timelimit: '0.7' }, '\n');
  assert.equal(r1.added, 2);
  const markers = r1.text.split('\n').filter(l => l.trim() === '// --- GF RCON tool ---');
  assert.equal(markers.length, 1);
  // A second upsert into that output must UPDATE, not duplicate.
  const r2 = srv.upsertCfg(r1.text, { scr_gf_flinch: '1.0' }, '\n');
  assert.equal(r2.updated, 1);
  assert.equal(r2.added, 0);
  assert.equal(r2.text.split('\n').filter(l => /scr_gf_flinch/.test(l)).length, 1);
});

test('upsertCfg: a name that PREFIXES another never clobbers the longer line', () => {
  // The replace regex requires whitespace after the name, so scr_gf_timelimit must not
  // match scr_gf_timelimit_large's line.
  const cfg = 'set scr_gf_timelimit_large "1.5"';
  const r = srv.upsertCfg(cfg, { scr_gf_timelimit: '0.7' }, '\n');
  assert.equal(r.updated, 0);
  assert.equal(r.added, 1);
  assert.match(r.text, /set scr_gf_timelimit_large "1\.5"/);
});

// ─── resolveConnParams (machine-independent paths only) ──────────────────────
test('resolveConnParams: bare request falls back to loopback defaults', () => {
  const c = srv.resolveConnParams({});
  assert.equal(c.host, '127.0.0.1');
  assert.equal(c.port, '28960');
  assert.equal(c.password, '');
});

test('resolveConnParams: an explicit EMPTY password is an override, not "unset"', () => {
  const c = srv.resolveConnParams({ host: '203.0.113.9', port: '28961', password: '' });
  assert.equal(c.password, '');
  assert.equal(c.host, '203.0.113.9');
  assert.equal(c.port, '28961');
});

test('resolveConnParams: PRESENT-but-blank profile is a hard error, never loopback fall-through', () => {
  const c = srv.resolveConnParams({ profile: '' });
  assert.ok(c.error && /Empty server profile/.test(c.error));
});

test('resolveConnParams: unknown profile is a hard error, never loopback fall-through', () => {
  const c = srv.resolveConnParams({ profile: 'no-such-profile-xyz' });
  assert.ok(c.error && /Unknown server profile/.test(c.error));
});

test('resolveConnParams: port normalised once (string/number agree on the cache key)', () => {
  assert.equal(srv.resolveConnParams({ port: 28960 }).port, '28960');
  assert.equal(srv.resolveConnParams({ port: 'garbage' }).port, '28960');   // fallback
});

// ─── stripColors ─────────────────────────────────────────────────────────────
test('stripColors: Treyarch ^N codes removed, text trimmed', () => {
  assert.equal(srv.stripColors('  ^1Red^7Name  '), 'RedName');
});
