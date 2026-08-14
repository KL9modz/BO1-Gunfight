// Regression net for the admin page's COMBAT stats layer (gamestats.json: the day-bucketed
// per-GUID kills/deaths/damage/wins aggregate status_service builds from the mod's GF_STAT/
// GF_MATCH log lines). Zero dependencies, node:test.
//
//   node --test "site/test/**/*.test.js"        (glob or explicit file, never a bare directory)
//
// Covers the three ways this layer can be wrong: the DAY WINDOW (cut on the box calendar,
// not the viewer's), the AGGREGATION (summing buckets, newest-name-wins, W-L-T records),
// and the RENDER (card only when data exists, shared drill-down selection, sortable headers).

const test = require('node:test');
const assert = require('node:assert/strict');
const { walk, textOf, load, here, ev } = require('./harness.js');

// Box clock is UTC-07:00; "now" is 21:30 box time on 2026-08-14.
const UPDATED = '2026-08-14T21:30:00.0000000-07:00';

const entry = (over) => Object.assign(
  { k:0, d:0, a:0, hs:0, dmg:0, cap:0, rw:0, mw:0, ml:0, mt:0, rounds:0, name:'' }, over);

// alice on three days (renamed on the newest), bob on one old day.
const DAYS = {
  '2026-08-14': {
    'GUIDA': entry({ k:5, d:2, a:1, hs:2, dmg:520, rw:4, mw:1, rounds:6, name:'alice2' }),
  },
  '2026-08-10': {
    'GUIDA': entry({ k:3, d:4, a:0, hs:0, dmg:300, rw:2, ml:1, rounds:5, name:'alice' }),
    'GUIDB': entry({ k:7, d:1, a:2, hs:3, dmg:700, rw:5, mw:1, rounds:6, name:'bob' }),
  },
  '2026-07-01': {
    'GUIDA': entry({ k:1, d:1, a:0, hs:0, dmg:80, rw:0, mt:1, rounds:2, name:'alice' }),
  },
};

// Connection events so the drill-down has an identity to open and flags to join.
const CONN = [
  ev('2026-08-14','20:30:00','LEFT',   '203.0.113.5:27015','alice2','GUIDA','65m0s','US','California'),
  ev('2026-08-14','19:25:00','CONNECT','203.0.113.5:27015','alice2','GUIDA','',     'US','California'),
  ev('2026-08-10','03:10:00','LEFT',   '198.51.100.4:27015','bob',  'GUIDB','30m0s','CA','Ontario'),
  ev('2026-08-10','02:40:00','CONNECT','198.51.100.4:27015','bob',  'GUIDB','',     'CA','Ontario'),
];

function seeded(hostIds){
  const h = load(hostIds);
  h.sb.histAll = CONN.map(e => Object.assign({}, e));
  h.sb.histUpdated = UPDATED;
  h.sb.combatDays = JSON.parse(JSON.stringify(DAYS));
  return h;
}

// ---------------------------------------------------------------------------
test('the day window cuts on the BOX calendar, newest day first', () => {
  const { sb } = seeded();

  sb.statWinH = 0;
  assert.deepEqual(here(sb.combatWindowDayKeys()), ['2026-08-14','2026-08-10','2026-07-01']);

  // 7d back from 2026-08-14 21:30 -07:00 reaches 2026-08-07: keeps 14th and 10th.
  sb.statWinH = 168;
  assert.deepEqual(here(sb.combatWindowDayKeys()), ['2026-08-14','2026-08-10']);

  sb.statWinH = 24;
  assert.deepEqual(here(sb.combatWindowDayKeys()), ['2026-08-14'],
    '24h keeps every day the window touches (day granularity)');
});

test('the same instant expressed as UTC yields the same day window', () => {
  const a = seeded(); a.sb.statWinH = 168;
  const want = here(a.sb.combatWindowDayKeys());
  const b = seeded(); b.sb.statWinH = 168;
  b.sb.histUpdated = '2026-08-15T04:30:00.0000000+00:00';   // identical instant, UTC
  assert.deepEqual(here(b.sb.combatWindowDayKeys()), want,
    'the cutoff calendar comes from the box offset, not the viewer zone');
});

test('computeCombat sums buckets and the newest name wins', () => {
  const { sb } = seeded();
  sb.statWinH = 0;
  const all = sb.computeCombat();
  assert.equal(all.length, 2);

  const alice = all.find(p => p.guid === 'GUIDA');
  assert.equal(alice.name, 'alice2', 'renamed player carries the newest name');
  assert.equal(alice.k, 9);
  assert.equal(alice.d, 7);
  assert.equal(alice.dmg, 900);
  assert.equal(alice.rw, 6);
  assert.deepEqual(here([alice.mw, alice.ml, alice.mt]), [1, 1, 1], 'W-L-T summed across days');
  assert.equal(alice.rounds, 13);

  sb.statWinH = 24;
  const day = sb.computeCombat();
  assert.equal(day.length, 1, 'bob has no activity in the last day');
  assert.equal(day[0].k, 5, 'only the newest bucket counted');
});

test('K/D handles the zero-death case and sortCombat orders every column', () => {
  const { sb } = seeded();
  sb.statWinH = 0;
  const all = sb.computeCombat();

  const flawless = { k: 3, d: 0 };
  assert.equal(sb.kdOf(flawless), 3, 'no deaths: K/D degrades to kills, not Infinity');
  assert.equal(sb.fmtKd({ k: 9, d: 7 }), '1.29');

  sb.combSort = 'k'; sb.combDir = -1;
  assert.deepEqual(here(sb.sortCombat(all).map(p => p.name)), ['alice2','bob']);
  sb.combSort = 'kd';
  assert.deepEqual(here(sb.sortCombat(all).map(p => p.name)), ['bob','alice2'], 'bob 7.0 beats alice 1.29');
  sb.combSort = 'name'; sb.combDir = 1;
  assert.deepEqual(here(sb.sortCombat(all).map(p => p.name)), ['alice2','bob']);
});

// ---------------------------------------------------------------------------
test('the combat card renders with data, and not at all without it', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();
  let txt = textOf(hosts.stats.kids[1]);
  assert.ok(txt.includes('Combat leaderboard'), 'card present with data');
  assert.ok(txt.includes('Kills') && txt.includes('Rd wins') && txt.includes('Matches'));
  assert.ok(txt.includes('1-1-1T'), "alice's W-L-T record rendered");

  sb.combatDays = null;
  sb.renderStats();
  txt = textOf(hosts.stats.kids[1]);
  assert.ok(!txt.includes('Combat leaderboard'), 'no gamestats.json yet: no card, no error');
});

test('clicking a combat row opens the SHARED drill-down with combat tiles', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();

  const rows = walk(hosts.stats.kids[1], []).filter(n => n.tag === 'tr' && /rowlink/.test(n.className));
  const bobRow = rows.filter(r => textOf(r).includes('bob'))
                     .find(r => textOf(r).includes('700'));   // his combat row, not his conn row
  assert.ok(bobRow, "bob's combat row exists");
  bobRow.click();
  assert.equal(sb.statPick, 'g:GUIDB', 'combat rows select by the same g:<guid> key');

  const txt = textOf(hosts.stats.kids[1]);
  assert.ok(txt.includes('Headshots'), 'drill-down carries the combat tile block');
  assert.ok(txt.includes('Round wins'), 'round wins tile present');
  bobRow.click();   // note: stale node, but its handler still toggles the module state
  assert.equal(sb.statPick, null, 'clicking again closes');
});

test('combat headers sort without disturbing the connection leaderboard sort', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();
  const before = sb.statSort;

  // The combat table is the SECOND .lb table; its Kills header is sortable.
  const tables = walk(hosts.stats.kids[1], []).filter(n => n.tag === 'table' && n.className === 'lb');
  assert.equal(tables.length, 2, 'connection + combat leaderboards');
  const ths = walk(tables[1], []).filter(n => n.tag === 'th' && /srt/.test(n.className));
  const deaths = ths.find(t => textOf(t).includes('Deaths'));
  deaths.click();
  assert.equal(sb.combSort, 'd', 'combat sort moved');
  assert.equal(sb.statSort, before, 'connection sort untouched');
});
