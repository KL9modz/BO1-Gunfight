// Regression net for site/wwwroot/admin/admin.js's stats layer - zero dependencies, node:test.
//
//   node --test "site/test/**/*.test.js"        (or name the file explicitly)
//
// ⚠ Use the GLOB or an explicit file, never a bare directory (node --test site/test/): on node 24
// that reports a phantom "fail 1" because it tries to LOAD the directory as a module instead of
// scanning it. Same trap already documented in tools/rcon/test/server.test.js.
//
// ⚠ This file lives in site/test/, NOT site/wwwroot/ - deploy.ps1 -Web /MIRrors wwwroot into IIS,
// so anything under it is PUBLISHED. Tests belong outside the published tree.
//
// admin.js is a browser script with no module system: it is loaded into a vm sandbox carrying a
// null/minimal DOM, which both exercises the real file and keeps the render paths inert until a
// test asks for them. The two groups below cover the two ways this code can be wrong:
//   1. the AGGREGATION (who played how long, folded by identity) and the TIME WINDOW
//   2. the RENDER (builds without throwing, the window bar is built once, handlers work)

const test = require('node:test');
const assert = require('node:assert/strict');

// The vm/DOM harness (mkNode's innerHTML strictness, the cross-realm `here` rule, the
// Build-ConnHistory event shape) is shared with admin_combat.test.js - see harness.js.
const { walk, textOf, load, here, ev } = require('./harness.js');

// Doc addresses are RFC 5737 with invented names/GUIDs, per the repo's address rule.
// alice: 2 sessions (10m + 65m), renamed once, one GUID, two IPs.
// bob:   1 session (30m), guid 0 -> keyed by bare IP.
// carol: connected, never left -> a connect but no playtime.
const FIXTURE = [
  ev('2026-08-13','21:00:00','CONNECT','198.51.100.9:27015','carol', 'GUIDC','',     'GB','England'),
  ev('2026-08-13','20:30:00','LEFT',   '203.0.113.5:27015', 'alice2','GUIDA','65m0s','US','California'),
  ev('2026-08-13','19:25:00','CONNECT','203.0.113.5:27015', 'alice2','GUIDA','',     'US','California'),
  ev('2026-08-10','03:10:00','LEFT',   '198.51.100.4:27015','bob',   '0',    '30m0s','CA','Ontario'),
  ev('2026-08-10','02:40:00','CONNECT','198.51.100.4:27015','bob',   '0',    '',     'CA','Ontario'),
  ev('2026-08-01','12:10:00','LEFT',   '203.0.113.7:27015', 'alice', 'GUIDA','10m0s','US','California'),
  ev('2026-08-01','12:00:00','CONNECT','203.0.113.7:27015', 'alice', 'GUIDA','',     'US','California'),
  ev('2026-08-01','11:59:00','ONLINE', '203.0.113.7:27015', 'alice', 'GUIDA','',     'US','California'),
];
// The box clock is UTC-07:00; "now" is 21:30 box time, 30 minutes after the last event.
const UPDATED = '2026-08-13T21:30:00.0000000-07:00';

function seeded(hostIds){
  const h = load(hostIds);
  h.sb.histAll = FIXTURE.map(e => Object.assign({}, e));   // fresh objects: evTime memoises onto them
  h.sb.histUpdated = UPDATED;
  return h;
}

// ---------------------------------------------------------------------------
test('aggregation folds identity, counts only completed sessions', () => {
  const { sb } = seeded();
  const s = sb.computeStats(sb.windowEvents());

  assert.equal(s.unique, 3, 'alice + alice2 fold to one player via GUID');
  assert.equal(s.connects, 4, 'four CONNECTs; the ONLINE cold-start row is not one');
  assert.equal(s.totLeft, 3, 'three completed sessions');
  assert.equal(s.totSec, (65+30+10)*60);
  assert.equal(s.days, 3, 'three distinct days with activity');
  assert.equal(s.longest.sec, 65*60);
  assert.equal(s.peakDay.date, '2026-08-13');

  const alice = s.players.find(p => p.key === 'g:GUIDA');
  assert.equal(alice.name, 'alice2', 'events are newest-first, so the newest name wins');
  assert.equal(alice.sec, 75*60);
  assert.equal(alice.sessions, 2);
  assert.equal(alice.conns, 2);
  assert.equal(alice.longest, 65*60);
  assert.deepEqual(here(alice.names && sb.keyList(alice.names)).sort(), ['alice','alice2'],
    'a rename shows as an alias');
  assert.deepEqual(here(sb.keyList(alice.ips)).sort(), ['203.0.113.5','203.0.113.7']);

  const bob = s.players.find(p => p.name === 'bob');
  assert.equal(bob.key, 'i:198.51.100.4', 'guid 0 falls back to the bare IP as the identity');

  const carol = s.players.find(p => p.name === 'carol');
  assert.deepEqual(here([carol.conns, carol.sec, carol.sessions]), [1, 0, 0],
    'still online: a connect but no playtime until they leave');
});

test('the hour histogram buckets by the SERVER stamp, and ignores ONLINE rows', () => {
  const { sb } = seeded();
  const s = sb.computeStats(sb.windowEvents());
  assert.equal(s.anyHour, 4, 'only CONNECTs enter the histogram');
  assert.deepEqual(here([s.hours[21], s.hours[19], s.hours[2], s.hours[12], s.hours[11]]), [1,1,1,1,0]);
});

test('peak hour picks the busiest bucket', () => {
  const { sb } = load();
  sb.histUpdated = UPDATED;
  sb.histAll = [
    ev('2026-08-12','19:05:00','CONNECT','203.0.113.5:27015','a','GUIDA'),
    ev('2026-08-12','19:45:00','CONNECT','203.0.113.6:27015','b','GUIDB'),
    ev('2026-08-12','19:55:00','CONNECT','203.0.113.7:27015','c','GUIDC'),
    ev('2026-08-12','04:00:00','CONNECT','203.0.113.8:27015','d','GUIDD'),
  ];
  const s = sb.computeStats(sb.windowEvents());
  assert.equal(s.peakHour, 19);
  assert.equal(s.hours[19], 3);
});

// THE case this whole time layer exists for. A day-file line carries the BOX's local wall clock
// with no zone; a window compared against the VIEWER's clock would be wrong by the difference
// between the two machines. The offset is recovered from admin_history.json's `updated`.
test('the time window uses the BOX clock, not the viewer clock', () => {
  const { sb } = seeded();

  sb.statWinH = 24;
  assert.equal(sb.windowEvents().length, 3, '24h keeps only the 2026-08-13 events');
  assert.equal(sb.computeStats(sb.windowEvents()).totSec, 65*60);
  assert.equal(sb.computeStats(sb.windowEvents()).unique, 2);

  sb.statWinH = 168;
  const s7 = sb.computeStats(sb.windowEvents());
  assert.equal(s7.unique, 3, '7d reaches back to bob');
  assert.equal(s7.totSec, 95*60);

  sb.statWinH = 0;
  assert.equal(sb.windowEvents().length, FIXTURE.length, 'All keeps everything on file');
});

test('the same instant in another zone yields the same window', () => {
  const a = seeded();  a.sb.statWinH = 24;
  const before = a.sb.windowEvents().length;

  const b = seeded();  b.sb.statWinH = 24;
  b.sb.histUpdated = '2026-08-14T04:30:00.0000000+00:00';   // identical instant, expressed as UTC
  assert.equal(b.sb.windowEvents().length, before,
    'the offset comes from `updated`, so the answer cannot depend on where the admin sits');
});

test('a row with no parseable stamp is excluded from a bounded window only', () => {
  const { sb } = load();
  sb.histUpdated = UPDATED;
  sb.histAll = [ ev('', '', 'LEFT', '203.0.113.5:27015', 'ghost', 'GUIDZ', '5m0s') ];
  sb.statWinH = 24;
  assert.equal(sb.windowEvents().length, 0, 'a window is a claim about time an unstamped row cannot support');
  sb.statWinH = 0;
  assert.equal(sb.windowEvents().length, 1, 'All makes no such claim, so it keeps the row');
});

test('sorting covers every column and both directions', () => {
  const { sb } = seeded();
  const players = sb.computeStats(sb.windowEvents()).players;
  const names = () => here(sb.sortPlayers(players).map(p => p.name));

  sb.statSort = 'sec';   sb.statDir = -1; assert.deepEqual(names(), ['alice2','bob','carol']);
                         sb.statDir =  1; assert.deepEqual(names(), ['carol','bob','alice2']);
  sb.statSort = 'name';  sb.statDir =  1; assert.deepEqual(names(), ['alice2','bob','carol']);
  sb.statSort = 'conns'; sb.statDir = -1; assert.equal(sb.sortPlayers(players)[0].name, 'alice2');
  sb.statSort = 'avg';   sb.statDir = -1; assert.equal(sb.sortPlayers(players)[0].name, 'alice2');
  sb.statSort = 'last';  sb.statDir = -1; assert.equal(sb.sortPlayers(players)[0].name, 'carol',
    'carol has the most recent event');
});

test('empty history aggregates to zero rather than throwing', () => {
  const { sb } = load();
  const s = sb.computeStats([]);
  assert.equal(s.unique, 0);
  assert.equal(s.connects, 0);
  assert.equal(s.days, 0);
  assert.equal(s.peakDay, null);
  assert.equal(s.longest, null);
});

// ---------------------------------------------------------------------------
test('renderStats builds the whole stats block without throwing', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();

  assert.equal(hosts.stats.kids.length, 2, 'the persistent window bar + the rebuildable body');
  const [bar, body] = hosts.stats.kids;
  assert.equal(bar.className, 'sbar');
  const seg = bar.kids.find(k => k.className === 'seg');
  assert.equal(seg.kids.length, 4, '24h / 7d / 30d / All');
  assert.equal(seg.kids[3].className, 'on', 'All is the default window');

  const txt = textOf(body);
  for (const card of ['Player leaderboard','Connects by hour','Activity by day',
                      'Players by country','Players by state / province']) {
    assert.ok(txt.includes(card), 'missing card: '+card);
  }
  assert.ok(txt.includes('alice2'), 'the leaderboard lists players');
});

// The window bar owns interactive controls, so a re-render that rebuilt it would steal focus
// mid-click every 60s. That is why it is built once and only the body is replaced.
test('a re-render reuses the one window bar', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();
  sb.renderStats();
  sb.renderStats();
  assert.equal(hosts.stats.kids.length, 2, 'still exactly one bar and one body');
});

test('the window buttons switch the window and repaint themselves', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();
  const seg = hosts.stats.kids[0].kids.find(k => k.className === 'seg');

  seg.kids[1].click();                       // 7d
  assert.equal(sb.statWinH, 168);
  assert.equal(seg.kids[1].className, 'on');
  assert.equal(seg.kids[3].className, '', 'All is no longer active');

  seg.kids[0].click();                       // 24h
  assert.equal(sb.statWinH, 24);
  assert.ok(textOf(hosts.stats.kids[1]).includes('Last 24h'));
});

test('clicking a leaderboard row opens and closes the drill-down', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();
  const rows = () => walk(hosts.stats.kids[1], []).filter(n => n.tag === 'tr' && /rowlink/.test(n.className));
  assert.equal(rows().length, 3, 'one clickable row per player');

  rows()[0].click();
  assert.ok(sb.statPick, 'a player is selected');
  const t = textOf(hosts.stats.kids[1]);
  assert.ok(t.includes('First seen') && t.includes('Longest'), 'the drill-down tiles rendered');
  assert.ok(t.includes('203.0.113.5'), 'the IP chips rendered');
  assert.ok(t.includes('alice'), 'the alias chips rendered');

  rows()[0].click();                          // clicking the same row again closes it
  assert.equal(sb.statPick, null);
});

test('a selection that falls out of the window is dropped, not left dangling', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();
  const rows = walk(hosts.stats.kids[1], []).filter(n => n.tag === 'tr' && /rowlink/.test(n.className));
  // Pick bob, whose only activity is 3 days old, then narrow to 24h.
  const bobRow = rows.find(r => textOf(r).includes('bob'));
  bobRow.click();
  assert.ok(sb.statPick);

  sb.statWinH = 24;
  sb.renderStats();
  assert.equal(sb.statPick, null, 'the drill-down clears rather than rendering a stale player');
});

test('sortable headers open a new column, and flip the active one', () => {
  const { sb, hosts } = seeded(['stats']);
  sb.renderStats();
  // Each render rebuilds the table, so the headers must be re-queried after every click.
  const ths = () => walk(hosts.stats.kids[1], []).filter(n => n.tag === 'th' && /srt/.test(n.className));
  assert.equal(ths().length, 6, 'every column except the rank is sortable');

  // Playtime IS the default sort, so clicking it flips rather than opens.
  assert.equal(sb.statSort, 'sec');
  assert.equal(sb.statDir, -1, 'the page opens on playtime, descending');
  ths()[1].click();
  assert.equal(sb.statDir, 1, 'clicking the ACTIVE column reverses it');

  ths()[0].click();                            // Player: a different column
  assert.equal(sb.statSort, 'name');
  assert.equal(sb.statDir, 1, 'a name column opens ascending');

  ths()[4].click();                            // Connects: a different numeric column
  assert.equal(sb.statSort, 'conns');
  assert.equal(sb.statDir, -1, 'a numeric column opens descending');
});

test('an empty history renders nothing and does not throw', () => {
  const { sb, hosts } = load(['stats']);
  sb.histAll = [];
  sb.renderStats();
  assert.equal(hosts.stats.kids.length, 0, 'no chrome is built before there is data');
});
