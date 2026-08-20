// Node test-runner suite for the Discord bot's SECURITY BOUNDARY.
//
//   node --test tools/tests/discord_bot.test.js
//
// The bot takes untrusted Discord text and interpolates it into `set gf_say "<here>"` on an rcon
// console. Everything below pins that boundary; the gateway plumbing is deliberately untested here
// (it needs a live socket, and its failure mode is loud rather than silent).
'use strict';
const test = require('node:test');
const assert = require('node:assert');

// bot.js exits on a missing config, so point it at the example before requiring it.
const fs = require('fs');
const path = require('path');
const botDir = path.join(__dirname, '..', 'discord_bot');
const local = path.join(botDir, 'config.local.json');
let madeTemp = false;
if (!fs.existsSync(local)) {
  const ex = JSON.parse(fs.readFileSync(path.join(botDir, 'config.example.json'), 'utf8'));
  ex.token = 'test'; ex.applicationId = '1'; ex.guildId = '2'; ex.adminRoleId = '3';
  fs.writeFileSync(local, JSON.stringify(ex));
  madeTemp = true;
}
process.argv.push('--register');            // stops main() from opening a gateway on require
// bot.js now owns the gateway and the router; the whitelist it serves is MERGED from the enabled
// feature modules, so importing COMMANDS from here is what proves the merge itself is sane.
const { COMMANDS, FEATURES, ENABLED, INTENTS } = require(path.join(botDir, 'bot.js'));
const { sanitiseForGame } = require(path.join(botDir, 'lib', 'panel.js'));
const { MAPS } = require(path.join(botDir, 'lib', 'maps.js'));
if (madeTemp) fs.unlinkSync(local);

test('sanitiser removes the rcon injection characters', () => {
  // THE case this exists for: a quote closes the value and a semicolon starts a new command, so
  // this input would otherwise change the rcon password from a chat message.
  const evil = 'hi";set rcon_password "pwned';
  const out = sanitiseForGame(evil);
  assert.ok(!out.includes('"'), 'quote survived');
  assert.ok(!out.includes(';'), 'semicolon survived');
  assert.ok(!/set rcon_password "pwned/.test(out), 'a whole chained command survived');
});

test('sanitiser strips newlines, which would split the rcon line', () => {
  const out = sanitiseForGame('one\r\nset gf_cmd matchrestart');
  assert.ok(!out.includes('\n') && !out.includes('\r'), 'newline survived');
});

test('sanitiser strips Treyarch colour codes and Discord mentions', () => {
  assert.ok(!sanitiseForGame('^1RED ^7text').includes('^1'), 'colour code survived');
  const m = sanitiseForGame('hey <@123456789012345678> and <@&987> and @everyone');
  assert.ok(!m.includes('<@'), 'mention survived');
  assert.ok(!/@everyone/i.test(m), 'everyone survived');
});

test('sanitiser caps length', () => {
  assert.ok(sanitiseForGame('x'.repeat(500)).length <= 120, 'no length cap');
});

test('sanitiser keeps ordinary text usable', () => {
  assert.strictEqual(sanitiseForGame('[D] KL9: anyone up for a game?'), '[D] KL9: anyone up for a game?');
});

test('every state-changing command requires the admin role', () => {
  // Read-only commands are open to the guild, so this asserts the split rather than a blanket rule:
  // if a new command touches the server it must be admin:true, and this fails until it is.
  for (const [name, c] of Object.entries(COMMANDS)) {
    const readOnly = name === 'status' || name === 'players';
    assert.strictEqual(c.admin, !readOnly, `${name} has the wrong admin gate`);
  }
});

test('no command accepts a free-text rcon string', () => {
  // The whitelist IS the design: an option named anything like "command"/"rcon"/"cmd" would mean
  // someone had added a passthrough, which defeats every other gate in the file.
  for (const [name, c] of Object.entries(COMMANDS)) {
    for (const o of (c.options || [])) {
      assert.ok(!/^(cmd|command|rcon|raw|dvar)$/i.test(o.name), `${name} exposes a passthrough option`);
    }
  }
});

test('the map list resolves only to real BO1 map ids', () => {
  for (const [label, id] of Object.entries(MAPS)) {
    assert.match(id, /^mp_[a-z0-9]+$/, `${label} -> ${id} is not a map id`);
  }
  assert.strictEqual(Object.keys(MAPS).length, 26, 'expected all 26 maps');
});

test('the map choice list stays inside Discord\'s 25-choice cap', () => {
  // Discord rejects a command registration with >25 choices, and the failure is at REGISTRATION
  // time - i.e. every command disappears, not just this one.
  const opt = (COMMANDS.map.options || [])[0];
  assert.ok(opt.choices.length <= 25, `${opt.choices.length} choices exceeds the cap`);
});

// ── voice log cards ────────────────────────────────────────────────────────────────────────────
// The card shape IS the contract with Discord, and one part of it is a notification decision
// rather than a styling one: a mobile push shows `content` verbatim when present and otherwise
// flattens the embed TITLE + DESCRIPTION. So a card with a title, NO description and its detail in
// a FIELD pushes exactly the title. These pin that, and the wording rules the module promises.
const { buildCard } = require(path.join(botDir, 'features', 'voice_log.js'));
const NAMES = new Map([['456', 'Gunfight'], ['789', 'General']]);
// buildCard takes a resolver function so the module can hand it the core cache's lookup.
const NAMEOF = (id) => NAMES.get(id) || 'voice';
const AT = Date.parse('2026-08-19T13:05:00Z');
const evt = (over) => Object.assign(
  { kind: 'joined', who: 'jjsetfree', username: 'jjsetfreeof', user: '123',
    prev: null, now: '456', count: 1, at: AT, actor: null, avatar: null }, over);
const details = (c) => c.fields.find((f) => f.name === '__Details__').value;

test('a card carries NO description - that is what keeps detail out of the push', () => {
  const c = buildCard(evt({}), NAMEOF);
  assert.ok(!('description' in c), 'a description would be flattened into the mobile push');
  assert.strictEqual(c.fields.length, 1, 'the detail block is ONE field');
  assert.strictEqual(c.fields[0].name, '__Details__');
});

test('the title names the channel in PLAIN TEXT, the field uses a chip', () => {
  // An embed title renders no <#id>, it would print the raw token. The field does render it.
  const c = buildCard(evt({}), NAMEOF);
  assert.ok(c.title.includes('Gunfight'), 'title should carry the channel NAME');
  assert.ok(!/<#\d+>/.test(c.title), 'a raw channel token leaked into the title');
  assert.ok(details(c).includes('<#456>'), 'the field should carry the chip');
});

test('a join reads like Sapphire: user mention, username, channel and count', () => {
  const c = buildCard(evt({}), NAMEOF);
  assert.strictEqual(c.title, '🔊 jjsetfree ➔ Joined: Gunfight');
  assert.strictEqual(details(c), '**User:** <@123> (jjsetfreeof)\n**Channel:** <#456> (1)');
});

test('an unknown channel degrades to "voice" rather than an id', () => {
  const c = buildCard(evt({ now: '999' }), NAMEOF);
  assert.ok(c.title.endsWith('voice'), `unknown channel rendered as ${c.title}`);
});

test('a self-leave and a moderator disconnect differ in wording AND colour', () => {
  const self = buildCard(evt({ kind: 'left', prev: '789', now: null, count: 0 }), NAMEOF);
  const kick = buildCard(evt({ kind: 'left', prev: '789', now: null, count: 0, actor: '777' }), NAMEOF);
  assert.ok(self.title.includes('Left:'), self.title);
  assert.ok(kick.title.includes('Disconnected:'), kick.title);
  assert.notStrictEqual(self.color, kick.color, 'the stripe is what separates them at a glance');
  assert.ok(!details(self).includes('**By:**'), 'a self-leave must not name an actor');
  assert.ok(details(kick).includes('**By:** <@777>'), 'a proven actor must be named');
});

test('a QUIET actor removes the By line without claiming the user did it', () => {
  // applyHints() consumes the hint but sets actor=null + byQuietActor. The card must then read
  // exactly like the self case: withholding who did it is not a claim that nobody did.
  const q = buildCard(evt({ kind: 'left', prev: '789', now: null, count: 0, actor: null, byQuietActor: true }), NAMEOF);
  assert.ok(!details(q).includes('**By:**'), 'a quiet actor must not be named');
  assert.ok(!/themselves/i.test(details(q) + q.title), 'and must not assert the self case either');
});

test('a move carries From and To, and the count belongs to the destination', () => {
  const c = buildCard(evt({ kind: 'moved', prev: '789', now: '456', count: 3 }), NAMEOF);
  assert.strictEqual(c.title, '➡️ jjsetfree ➔ Moved: General → Gunfight');
  assert.ok(details(c).includes('**From:** <#789>'), details(c));
  assert.ok(details(c).includes('**To:** <#456> (3)'), details(c));
});

test('a hostile display name cannot exceed Discord\'s title or field caps', () => {
  // Over either cap Discord rejects the whole message, so the card would simply never appear.
  const c = buildCard(evt({ who: 'x'.repeat(4000), username: 'y'.repeat(4000) }), NAMEOF);
  assert.ok(c.title.length <= 256, `title ${c.title.length} > 256`);
  assert.ok(details(c).length <= 1024, `field ${details(c).length} > 1024`);
});

test('the burst never exceeds the ten embeds Discord allows in one message', () => {
  // A protocol limit, not a taste one: an eleventh embed is a rejected request, not a truncation.
  const src = fs.readFileSync(path.join(botDir, 'features', 'voice_log.js'), 'utf8');
  const m = src.match(/const MAX_CARDS\s*=\s*(\d+)/);
  assert.ok(m, 'MAX_CARDS not found - renamed?');
  assert.ok(Number(m[1]) <= 10, `MAX_CARDS is ${m[1]}, over Discord's 10-embed cap`);
});

test('the voice log never posts `content` - that would push verbatim', () => {
  // The regression this guards: `content` reaches the lock screen with its markup intact, which is
  // the whole reason these are embeds. Fields do not.
  const src = fs.readFileSync(path.join(botDir, 'features', 'voice_log.js'), 'utf8');
  assert.ok(!/\bcontent:/.test(src), 'a content: payload came back into the voice log');
});

// ── bot presence ───────────────────────────────────────────────────────────────────────────────
// The member-list line. Gateway op 3, so no intent and no permission - but it is a CLAIM about the
// live server made to everyone who looks at the sidebar, and these pin the two ways a claim can be
// wrong: counting bots as players, and reading a dead writer's last file as the current roster.
const { buildPresence } = require(path.join(botDir, 'features', 'presence.js'));
const NOW = Date.parse('2026-08-19T20:00:00Z');
const snap = (over) => Object.assign(
  { updated: new Date(NOW - 3000).toISOString(), online: true, mapName: 'Nuketown',
    humans: 3, bots: 4 }, over);
const line = (p) => p.activities[0].name;

test('presence renders the live human count and the map', () => {
  const p = buildPresence(snap({}), NOW);
  assert.strictEqual(line(p), '3 players on Nuketown');
  assert.strictEqual(p.status, 'online');
  assert.strictEqual(p.activities[0].type, 3, 'type 3 = Watching, so the text completes that verb');
});

test('presence reads singular for one player', () => {
  assert.strictEqual(line(buildPresence(snap({ humans: 1 }), NOW)), '1 player on Nuketown');
});

test('BOTS ARE NOT PLAYERS - a bot-padded server reads empty', () => {
  // Bot fill is on by default, so counting bots would make the line permanently say "busy" and
  // mean nothing. Same rule the match stats and the join alerts follow.
  const p = buildPresence(snap({ humans: 0, bots: 6 }), NOW);
  assert.strictEqual(line(p), 'an empty server');
  assert.strictEqual(p.status, 'idle');
});

test('an offline server is never dressed up as a quiet one', () => {
  const p = buildPresence(snap({ online: false }), NOW);
  assert.ok(/offline/.test(line(p)), line(p));
  assert.strictEqual(p.status, 'dnd');
});

test('a STALE snapshot reports unknown, never the frozen roster', () => {
  // THE case this guards: status_service dies and its last file sits on disk claiming players are
  // on. Presence would then advertise a server that may be empty or down, indefinitely.
  const p = buildPresence(snap({ updated: new Date(NOW - 10 * 60000).toISOString() }), NOW);
  assert.ok(/unknown/.test(line(p)), line(p));
  assert.ok(!/Nuketown|3 players/.test(line(p)), 'a stale roster leaked into the line');
  assert.strictEqual(p.status, 'idle');
});

test('an unreadable timestamp counts as stale, not as fresh', () => {
  const p = buildPresence(snap({ updated: 'not a date' }), NOW);
  assert.ok(/unknown/.test(line(p)), line(p));
});

test('a missing or unparseable status file degrades, it does not throw', () => {
  for (const bad of [null, undefined, 'nonsense', 42]) {
    const p = buildPresence(bad, NOW);
    assert.ok(/unknown/.test(line(p)), `${JSON.stringify(bad)} produced ${line(p)}`);
  }
});

test('presence stays inside Discord\'s 128-char activity name cap', () => {
  const p = buildPresence(snap({ mapName: 'M'.repeat(400) }), NOW);
  assert.ok(line(p).length <= 128, `activity name ${line(p).length} > 128`);
});

test('presence never polls rcon - it reads the status projection', () => {
  // The project rule is that the panel is the box's ONE rcon pacer. A 20s presence refresh over
  // HTTP would be a second poller, permanently, for a cosmetic feature. The guard is therefore on
  // the MECHANISM - any outbound call at all - not on a path string that also appears in prose.
  const src = fs.readFileSync(path.join(botDir, 'features', 'presence.js'), 'utf8');
  assert.ok(!src.includes('panelRcon'), 'presence reached for rcon');
  assert.ok(!src.includes('http.request'), 'presence opened an HTTP request');
  assert.ok(!src.includes('fetch('), 'presence opened an HTTP request');
  assert.ok(src.includes('status.json'), 'presence should read the status projection');
});

// ── the module contract ────────────────────────────────────────────────────────────────────────
// bot.js is now a router over feature modules. The contract is what keeps a new feature from
// quietly costing a privilege or shadowing someone else's command, so it is worth pinning.
const cache = require(path.join(botDir, 'lib', 'cache.js'));
const brand = require(path.join(botDir, 'lib', 'brand.js'));

test('every feature declares the full contract', () => {
  for (const f of FEATURES) {
    assert.ok(typeof f.name === 'string' && f.name, 'a feature has no name');
    assert.strictEqual(typeof f.enabled, 'boolean', `${f.name}.enabled must be a boolean`);
    assert.strictEqual(typeof f.intents, 'number', `${f.name}.intents must be a number`);
    assert.ok(Array.isArray(f.permissions), `${f.name}.permissions must be an array`);
    assert.strictEqual(typeof f.commands, 'object', `${f.name}.commands must be an object`);
    assert.strictEqual(typeof f.on, 'object', `${f.name}.on must be an object`);
  }
});

test('no two features claim the same command name', () => {
  // bot.js refuses to start on a collision; this catches it at test time instead of at 3am.
  const seen = new Set();
  for (const f of FEATURES) {
    for (const name of Object.keys(f.commands || {})) {
      assert.ok(!seen.has(name), `/${name} is declared by more than one feature`);
      seen.add(name);
    }
  }
});

test('a DISABLED feature contributes neither intents nor commands', () => {
  // THE property that keeps a switched-off feature from costing a privileged intent - which would
  // close the gateway with 4014 and take every other feature down with it.
  for (const f of FEATURES) {
    if (f.enabled) continue;
    assert.ok(!ENABLED.includes(f), `${f.name} is disabled but still in ENABLED`);
    for (const name of Object.keys(f.commands || {})) {
      assert.ok(!(name in COMMANDS), `disabled ${f.name} still registered /${name}`);
    }
  }
});

test('the intent union always carries GUILDS and nothing unrequested', () => {
  assert.ok(INTENTS & 1, 'GUILDS is what seeds the channel and voice caches');
  let expected = 1;
  for (const f of ENABLED) expected |= f.intents;
  assert.strictEqual(INTENTS, expected, 'INTENTS is not the union of the enabled features');
});

test('MESSAGE_CONTENT is only ever requested when a relay channel exists', () => {
  // Privileged. Asking for it on an install where nobody has flipped the portal toggle is a fatal
  // 4014, so it must track the config rather than being hardcoded.
  const relay = FEATURES.find((f) => f.name === 'relay');
  const wantsContent = Boolean(relay.intents & (1 << 15));
  assert.strictEqual(wantsContent, relay.enabled, 'relay asks for MESSAGE_CONTENT while disabled');
});

// ── lib/cache.js ───────────────────────────────────────────────────────────────────────────────
test('a voice transition is memoised, so core and feature read the SAME prev', () => {
  // THE ordering trap: the core updates the map before features run. If transition() were not
  // memoised on the event object, the feature would read the NEW channel as prev and "moved from X"
  // would be unrecoverable.
  const ev = { user_id: 'u1', channel_id: 'c2', guild_id: 'g' };
  cache.observe('VOICE_STATE_UPDATE', { user_id: 'u1', channel_id: 'c1', guild_id: 'g' });
  const core = cache.voice.transition(ev);        // as the core sees it
  const feature = cache.voice.transition(ev);     // as the feature sees it, afterwards
  assert.strictEqual(core.prev, 'c1');
  assert.deepStrictEqual(core, feature, 'the second read disagreed with the first');
});

test('membersOf and count see everyone in a channel', () => {
  for (const u of ['a', 'b', 'c']) cache.observe('VOICE_STATE_UPDATE', { user_id: u, channel_id: 'room' });
  assert.strictEqual(cache.voice.count('room'), 3);
  assert.deepStrictEqual(cache.voice.membersOf('room').sort(), ['a', 'b', 'c']);
  cache.observe('VOICE_STATE_UPDATE', { user_id: 'b', channel_id: null });   // b leaves
  assert.strictEqual(cache.voice.count('room'), 2);
});

test('suppression hides our own moves and then expires', () => {
  cache.voice.suppress(['z1'], 50);
  assert.ok(cache.voice.suppressed('z1'), 'should be suppressed inside the window');
  assert.ok(!cache.voice.suppressed('z2'), 'an unrelated user must not be suppressed');
  return new Promise((r) => setTimeout(() => {
    assert.ok(!cache.voice.suppressed('z1'), 'the window must expire on its own');
    r();
  }, 70));
});

test('the message cache is BOUNDED - an unbounded one is a slow leak', () => {
  for (let i = 0; i < cache.MESSAGE_CAP + 50; i++) {
    cache.observe('MESSAGE_CREATE', { id: 'm' + i, channel_id: 'c', author: { id: 'u' }, content: 'x' });
  }
  assert.ok(cache.message.size() <= cache.MESSAGE_CAP, `cache grew to ${cache.message.size()}`);
  assert.ok(cache.message.get('m0') === null, 'the oldest entry should have been evicted');
});

// ── lib/brand.js ───────────────────────────────────────────────────────────────────────────────
test('brand.card puts detail in a FIELD and never in the description', () => {
  // The house rule, centralised: a description is flattened into the mobile push, a field is not.
  const c = brand.card({ title: 'T', details: [['User', '<@1>'], ['Channel', '<#2>']] });
  assert.ok(!('description' in c), 'card added a description');
  assert.strictEqual(c.fields.length, 1);
  assert.strictEqual(c.fields[0].name, brand.DETAILS);
  assert.strictEqual(c.fields[0].value, '**User:** <@1>\n**Channel:** <#2>');
});

test('brand.card drops empty detail rows rather than printing blanks', () => {
  const c = brand.card({ title: 'T', details: [['User', '<@1>'], ['Reason', ''], ['By', null]] });
  assert.strictEqual(c.fields[0].value, '**User:** <@1>');
});

test('brand.card clamps a hostile title and field to Discord\'s caps', () => {
  const c = brand.card({ title: 'x'.repeat(900), details: [['A', 'y'.repeat(4000)]] });
  assert.ok(c.title.length <= brand.TITLE_MAX, `title ${c.title.length}`);
  assert.ok(c.fields[0].value.length <= brand.FIELD_MAX, `field ${c.fields[0].value.length}`);
});

test('the footer is opt-in - a burst of cards must not each carry branding', () => {
  assert.ok(!('footer' in brand.card({ title: 'T' })), 'footer should be off by default');
  assert.strictEqual(brand.card({ title: 'T', footer: true }).footer.text, brand.FOOTER);
});
