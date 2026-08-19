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
const { sanitiseForGame, COMMANDS, MAPS } = require(path.join(botDir, 'bot.js'));
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
const AT = Date.parse('2026-08-19T13:05:00Z');
const evt = (over) => Object.assign(
  { kind: 'joined', who: 'jjsetfree', username: 'jjsetfreeof', user: '123',
    prev: null, now: '456', count: 1, at: AT, actor: null, avatar: null }, over);
const details = (c) => c.fields.find((f) => f.name === '__Details__').value;

test('a card carries NO description - that is what keeps detail out of the push', () => {
  const c = buildCard(evt({}), NAMES);
  assert.ok(!('description' in c), 'a description would be flattened into the mobile push');
  assert.strictEqual(c.fields.length, 1, 'the detail block is ONE field');
  assert.strictEqual(c.fields[0].name, '__Details__');
});

test('the title names the channel in PLAIN TEXT, the field uses a chip', () => {
  // An embed title renders no <#id>, it would print the raw token. The field does render it.
  const c = buildCard(evt({}), NAMES);
  assert.ok(c.title.includes('Gunfight'), 'title should carry the channel NAME');
  assert.ok(!/<#\d+>/.test(c.title), 'a raw channel token leaked into the title');
  assert.ok(details(c).includes('<#456>'), 'the field should carry the chip');
});

test('a join reads like Sapphire: user mention, username, channel and count', () => {
  const c = buildCard(evt({}), NAMES);
  assert.strictEqual(c.title, '🔊 jjsetfree ➔ Joined: Gunfight');
  assert.strictEqual(details(c), '**User:** <@123> (jjsetfreeof)\n**Channel:** <#456> (1)');
});

test('an unknown channel degrades to "voice" rather than an id', () => {
  const c = buildCard(evt({ now: '999' }), NAMES);
  assert.ok(c.title.endsWith('voice'), `unknown channel rendered as ${c.title}`);
});

test('a self-leave and a moderator disconnect differ in wording AND colour', () => {
  const self = buildCard(evt({ kind: 'left', prev: '789', now: null, count: 0 }), NAMES);
  const kick = buildCard(evt({ kind: 'left', prev: '789', now: null, count: 0, actor: '777' }), NAMES);
  assert.ok(self.title.includes('Left:'), self.title);
  assert.ok(kick.title.includes('Disconnected:'), kick.title);
  assert.notStrictEqual(self.color, kick.color, 'the stripe is what separates them at a glance');
  assert.ok(!details(self).includes('**By:**'), 'a self-leave must not name an actor');
  assert.ok(details(kick).includes('**By:** <@777>'), 'a proven actor must be named');
});

test('a QUIET actor removes the By line without claiming the user did it', () => {
  // applyHints() consumes the hint but sets actor=null + byQuietActor. The card must then read
  // exactly like the self case: withholding who did it is not a claim that nobody did.
  const q = buildCard(evt({ kind: 'left', prev: '789', now: null, count: 0, actor: null, byQuietActor: true }), NAMES);
  assert.ok(!details(q).includes('**By:**'), 'a quiet actor must not be named');
  assert.ok(!/themselves/i.test(details(q) + q.title), 'and must not assert the self case either');
});

test('a move carries From and To, and the count belongs to the destination', () => {
  const c = buildCard(evt({ kind: 'moved', prev: '789', now: '456', count: 3 }), NAMES);
  assert.strictEqual(c.title, '➡️ jjsetfree ➔ Moved: General → Gunfight');
  assert.ok(details(c).includes('**From:** <#789>'), details(c));
  assert.ok(details(c).includes('**To:** <#456> (3)'), details(c));
});

test('a hostile display name cannot exceed Discord\'s title or field caps', () => {
  // Over either cap Discord rejects the whole message, so the card would simply never appear.
  const c = buildCard(evt({ who: 'x'.repeat(4000), username: 'y'.repeat(4000) }), NAMES);
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
