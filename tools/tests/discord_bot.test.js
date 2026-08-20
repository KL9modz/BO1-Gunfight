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

test('BOTS ARE NOT PLAYERS - a bot-padded server never claims a player count', () => {
  // Bot fill is on by default, so counting bots would make the line permanently say "busy" and
  // mean nothing. Same rule the match stats and the join alerts follow.
  const p = buildPresence(snap({ humans: 0, bots: 6 }), NOW);
  assert.ok(!/\d+ player/.test(line(p)), `claimed players with none on: "${line(p)}"`);
});

test('an EMPTY server is never advertised as empty', () => {
  // The line sits on a public profile, so "an empty server" prints a reason not to join exactly
  // where prospective players read it. It must stop selling the emptiness WITHOUT becoming a lie.
  const p = buildPresence(snap({ humans: 0, bots: 6 }), NOW);
  assert.ok(!/empty|nobody|no one|0 player/i.test(line(p)), `still selling it: "${line(p)}"`);
  assert.strictEqual(line(p), 'for players');
  assert.strictEqual(p.status, 'online', 'the dot must not read dormant either');
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

// ── logging family ─────────────────────────────────────────────────────────────────────────────
// These features REPUBLISH things people deleted, so the tests are mostly about the guards: what is
// never logged, what is never claimed, and what is never downloaded.
const messageLog = require(path.join(botDir, 'features', 'message_log.js'));
const memberLog = require(path.join(botDir, 'features', 'member_log.js'));
const makeAttachments = require(path.join(botDir, 'lib', 'attachments.js'));

const noop = () => {};
const fakeRest = {
  probe: async () => ({ ok: false, status: 403 }),
  postMessage: async () => ({ id: 'card1' }),
  editMessage: async () => ({}),
  postMessageWithFiles: async () => ({ id: 'card1' }),
};
const mkMsgLog = (over) => messageLog({
  cfg: Object.assign({ guildId: 'g1', messageLogChannelId: 'LOG' }, over),
  log: noop, rest: fakeRest, cache,
});

test('message logging is OFF without a channel, and asks for no intent', () => {
  // MESSAGE_CONTENT is privileged: requesting it while the portal toggle is off is a fatal 4014 for
  // every feature, so a feature with nowhere to post must not ask.
  const off = mkMsgLog({ messageLogChannelId: '' });
  assert.strictEqual(off.enabled, false);
  assert.strictEqual(off.intents, 0);
});

test('message logging asks for MESSAGE_CONTENT only when it is on', () => {
  assert.ok(mkMsgLog({}).intents & (1 << 15), 'enabled log needs MESSAGE_CONTENT');
});

test('the log channel is ALWAYS excluded from logging itself', async () => {
  // Without this the bot's own cards are messages, deleting one logs the log, and a purge in there
  // recurses. Probed through the media path: an ignored channel buffers nothing.
  const m = mkMsgLog({});
  m.on.MESSAGE_CREATE({ id: 'x1', guild_id: 'g1', channel_id: 'LOG',
                        author: { id: 'u1' }, attachments: [{ filename: 'a.png', size: 10, url: 'http://x' }] });
  await new Promise((r) => setTimeout(r, 20));
  // Nothing was fetched, so nothing can be taken back out.
  assert.deepStrictEqual(await makeAttachments(noop).take('x1'), []);
});

test('a deleted message quotes its content instead of interpolating it', () => {
  // Deleted text can contain markdown, backticks or @everyone. Quoting keeps it from reformatting
  // the card; allowed_mentions in lib/rest.js covers the pinging half.
  const q = messageLog.quote('hello\n@everyone');
  assert.ok(q.split('\n').every((l) => l.startsWith('> ')), q);
});

test('an over-long message is truncated with a visible marker', () => {
  // A partial message must never read as the whole message.
  const out = messageLog.preview('x'.repeat(5000));
  assert.ok(out.length < 1024, `preview was ${out.length}`);
  assert.ok(/truncated/.test(out), 'truncation must be visible');
});

test('an empty message and an uncached one are not the same fact', () => {
  // Both would render as "nothing to show" if the code were lazy, but one means the message had no
  // text and the other means we never had it - and only the second is a gap in the log.
  assert.strictEqual(messageLog.preview(''), '');
  assert.strictEqual(messageLog.preview(null), '');
});

test('member logging is OFF without a channel, and never asks for GUILD_MEMBERS', () => {
  const off = memberLog({ cfg: { guildId: 'g1', memberLogChannelId: '' }, log: noop, rest: fakeRest, cache });
  assert.strictEqual(off.enabled, false);
  assert.strictEqual(off.intents, 0, 'GUILD_MEMBERS is privileged - never request it while off');
  const on = memberLog({ cfg: { guildId: 'g1', memberLogChannelId: 'M' }, log: noop, rest: fakeRest, cache });
  assert.strictEqual(on.intents, 1 << 1);
});

test('account age comes from the snowflake itself, no API call', () => {
  // Discord's epoch is 2015-01-01. This id is the documented example.
  const ms = memberLog.createdAt('175928847299117063');
  assert.ok(Math.abs(ms - Date.parse('2016-04-30T11:18:25.796Z')) < 2, `got ${new Date(ms).toISOString()}`);
  assert.strictEqual(memberLog.createdAt('not-a-snowflake'), null, 'a bad id must not throw');
});

// ── lib/attachments.js ─────────────────────────────────────────────────────────────────────────
test('an oversized attachment is never downloaded', async () => {
  // THE safety property: the input is arbitrary user uploads onto the box that runs the game server.
  const a = makeAttachments(noop);
  a.remember('big', [{ filename: 'huge.mp4', size: a.MAX_FILE + 1, url: 'http://never-fetched' }]);
  assert.strictEqual(a.stats().messages, 0, 'an over-cap file must not even be tracked');
  assert.deepStrictEqual(await a.take('big'), []);
});

test('taking an unknown message yields nothing rather than throwing', async () => {
  assert.deepStrictEqual(await makeAttachments(noop).take('never-seen'), []);
});

test('the caps are real numbers, not aspirations', () => {
  const a = makeAttachments(noop);
  assert.ok(a.MAX_FILE > 0 && a.MAX_FILE <= 10 * 1024 * 1024, 'per-file cap within Discord upload limits');
  assert.ok(a.MAX_TOTAL >= a.MAX_FILE, 'total cap must fit at least one file');
  assert.ok(a.TTL_MS > 0 && a.TTL_MS <= 3600000, 'TTL must be minutes, not hours');
});

// ── the extended message cache ─────────────────────────────────────────────────────────────────
test('the cache keeps attachment METADATA even when the bytes are not held', () => {
  // So a card can say a 40MB video was deleted rather than silently omitting it.
  cache.observe('MESSAGE_CREATE', { id: 'meta1', channel_id: 'c', author: { id: 'u', username: 'n' },
    content: 'hi', attachments: [{ filename: 'clip.mp4', size: 40e6, content_type: 'video/mp4', url: 'u' }] });
  const row = cache.message.get('meta1');
  assert.strictEqual(row.attachments.length, 1);
  assert.strictEqual(row.attachments[0].filename, 'clip.mp4');
});

test('an edit overwrites the cached content, so the NEXT edit diffs against what was on screen', () => {
  cache.observe('MESSAGE_CREATE', { id: 'e1', channel_id: 'c', author: { id: 'u' }, content: 'first' });
  cache.message.update('e1', 'second');
  assert.strictEqual(cache.message.get('e1').content, 'second');
});

test('a bot author is recorded, so the log can skip its own cards', () => {
  cache.observe('MESSAGE_CREATE', { id: 'b1', channel_id: 'c', author: { id: 'x', bot: true }, content: 'card' });
  assert.strictEqual(cache.message.get('b1').authorBot, true);
});

// ── moderation ─────────────────────────────────────────────────────────────────────────────────
// judge() is a pure decision, so every rule is pinned individually. These matter more than most:
// a false positive here DELETES someone's message and can time them out.
const moderation = require(path.join(botDir, 'features', 'moderation.js'));
const automod = require(path.join(botDir, 'features', 'automod.js'));
const snowflake = require(path.join(botDir, 'lib', 'snowflake.js'));

const RULES = (over) => Object.assign({
  blocked: moderation.DEFAULT_BLOCKED, maxBytes: 0, maxMB: 0,
  allowDomains: [], denyDomains: [], linkMinAge: 0,
}, over);
const msg = (over) => Object.assign({ content: '', attachments: [] }, over);

test('an executable attachment is refused', () => {
  const v = moderation.judge(msg({ attachments: [{ filename: 'cheat.exe', size: 10 }] }), null, RULES());
  assert.ok(v && /blocked file type/.test(v.reason), JSON.stringify(v));
});

test('the DOUBLE EXTENSION trick does not work', () => {
  // The whole reason a filename cannot be trusted from the left.
  const v = moderation.judge(msg({ attachments: [{ filename: 'screenshot.png.exe', size: 10 }] }), null, RULES());
  assert.ok(v, 'screenshot.png.exe must be judged on .exe');
});

test('an ordinary screenshot passes', () => {
  assert.strictEqual(moderation.judge(msg({ attachments: [{ filename: 'clip.png', size: 10 }] }), null, RULES()), null);
});

test('an oversized attachment is refused, and says the limit', () => {
  const v = moderation.judge(msg({ attachments: [{ filename: 'big.mp4', size: 30e6 }] }), null,
                             RULES({ maxBytes: 8e6, maxMB: 8 }));
  assert.ok(/too large/.test(v.reason) && /8MB/.test(v.detail), JSON.stringify(v));
});

test('a message with no link and no attachment is always fine', () => {
  assert.strictEqual(moderation.judge(msg({ content: 'gg wp everyone' }), 0.1, RULES({ linkMinAge: 7 })), null);
});

test('ALLOWLIST mode removes a message carrying any host not on the list', () => {
  const r = RULES({ allowDomains: ['youtube.com', 'gunfight.us'] });
  assert.strictEqual(moderation.judge(msg({ content: 'see https://www.youtube.com/watch?v=1' }), null, r), null,
                     'a subdomain of an allowed host must pass');
  const v = moderation.judge(msg({ content: 'https://youtube.com/ok and https://sketchy.tld/x' }), null, r);
  assert.ok(v && /allowlist/.test(v.reason), 'one disallowed host must remove the message');
});

test('DENYLIST mode only removes the hosts named', () => {
  const r = RULES({ denyDomains: ['sketchy.tld'] });
  assert.strictEqual(moderation.judge(msg({ content: 'https://example.com/x' }), null, r), null);
  assert.ok(moderation.judge(msg({ content: 'https://a.sketchy.tld/x' }), null, r), 'subdomains of a blocked host count');
});

test('a NEW ACCOUNT cannot post links, even to an allowed domain', () => {
  // THE anti-spam rule, and the ordering that makes it work: an allow-listed host must not smuggle
  // a three-hour-old account past the age check.
  const r = RULES({ linkMinAge: 7, allowDomains: ['youtube.com'] });
  const v = moderation.judge(msg({ content: 'https://youtube.com/x' }), 0.2, r);
  assert.ok(v && /new account/.test(v.reason), JSON.stringify(v));
});

test('an established account posts the same link freely', () => {
  const r = RULES({ linkMinAge: 7, allowDomains: ['youtube.com'] });
  assert.strictEqual(moderation.judge(msg({ content: 'https://youtube.com/x' }), 400, r), null);
});

test('an UNREADABLE account age never triggers the age rule', () => {
  // null means "cannot say", and cannot-say must not become a deletion.
  assert.strictEqual(moderation.judge(msg({ content: 'https://x.tld/a' }), null, RULES({ linkMinAge: 7 })), null);
});

test('host matching covers subdomains without covering lookalikes', () => {
  assert.ok(moderation.hostMatches('www.youtube.com', 'youtube.com'));
  assert.ok(moderation.hostMatches('m.youtube.com', 'youtube.com'));
  assert.ok(!moderation.hostMatches('notyoutube.com', 'youtube.com'), 'a lookalike must not match');
  assert.ok(!moderation.hostMatches('youtube.com.evil.tld', 'youtube.com'), 'a suffix trick must not match');
});

test('link extraction finds every host and drops the port', () => {
  const hosts = moderation.hostsIn('a https://one.tld/x b http://two.tld:8080/y');
  assert.deepStrictEqual(hosts, ['one.tld', 'two.tld']);
});

test('MODERATION NEVER BANS OR KICKS - the escalation ceiling is structural', () => {
  // The stated ceiling is delete then timeout. This fails if anyone ever reaches for the ban or
  // kick endpoints, which is the change that would need a human argument rather than a commit.
  const src = fs.readFileSync(path.join(botDir, 'features', 'moderation.js'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  assert.ok(!/\/bans\//.test(src) && !/\bban\(/.test(src), 'moderation reached for a ban');
  assert.ok(!/\/members\/[^)]*\/?['"`]\s*,\s*'DELETE'/.test(src) && !/kick/i.test(src), 'moderation reached for a kick');
  assert.ok(/communication_disabled_until/.test(src), 'timeout is the intended top of the ladder');
});

test('moderation and automod are OFF without a channel', () => {
  const ctxOff = { cfg: { guildId: 'g' }, log: () => {}, rest: {}, cache };
  assert.strictEqual(moderation(ctxOff).enabled, false);
  assert.strictEqual(moderation(ctxOff).intents, 0);
  assert.strictEqual(automod(ctxOff).enabled, false);
  assert.strictEqual(automod(ctxOff).intents, 0);
});

test('automod pays for BOTH of its intents, and neither is privileged', () => {
  // Recorded wrong twice. First as "no intent needed", then as EXECUTION alone - but the RULE_*
  // subscriptions need the SEPARATE CONFIGURATION intent, and without it /automod would quietly go
  // stale the moment someone edited a rule in Server Settings.
  const on = automod({ cfg: { guildId: 'g', automodChannelId: 'A' }, log: () => {}, rest: {}, cache });
  assert.ok(on.intents & (1 << 21), 'ACTION_EXECUTION delivers the hits');
  assert.ok(on.intents & (1 << 20), 'CONFIGURATION delivers RULE_CREATE/UPDATE/DELETE');
  assert.strictEqual(on.intents & intents.PRIVILEGED, 0, 'neither costs a portal toggle');
});

test('snowflake age says "cannot say" rather than guessing', () => {
  assert.strictEqual(snowflake.ageDays('nonsense'), null);
  assert.strictEqual(snowflake.ageDays('0'), null);
  assert.ok(snowflake.ageDays('175928847299117063') > 3000, 'a 2016 account should read as years old');
});

// ── the intent table ───────────────────────────────────────────────────────────────────────────
// ⚠ THE GUARD THAT MAKES THE WHOLE CLASS IMPOSSIBLE. A feature that subscribes to an event without
// requesting its intent does not error, does not warn and does not retry - the event just never
// arrives. That shipped twice before this test existed (audit-log attribution in voice_log and
// message_log, and the AutoMod RULE_* events), both times found by reading docs rather than by
// anything failing.
const intents = require(path.join(botDir, 'lib', 'intents.js'));

test('every subscribed event has its intent paid for', () => {
  for (const f of ENABLED) {
    for (const event of Object.keys(f.on || {})) {
      const need = intents.EVENT_INTENT[event];
      assert.notStrictEqual(need, undefined,
        `${f.name} subscribes to ${event}, which is not in lib/intents.js - add it there`);
      if (!need) continue;
      assert.ok(f.intents & need,
        `${f.name} subscribes to ${event} but does not request ${intents.names(need).join('|')} - ` +
        `the event would never arrive, silently`);
    }
  }
});

test('audit-log attribution actually pays for GUILD_MODERATION', () => {
  // Named separately because it is the one that shipped broken: both features probe the audit-log
  // REST endpoint and would report "audit access OK" while the gateway sent them nothing.
  for (const f of FEATURES) {
    if (!f.on || !f.on.GUILD_AUDIT_LOG_ENTRY_CREATE || !f.enabled) continue;
    assert.ok(f.intents & intents.BITS.GUILD_MODERATION,
      `${f.name} correlates audit entries without GUILD_MODERATION`);
  }
});

test('no feature requests a privileged intent it has not been switched on for', () => {
  // A privileged intent that is not enabled in the portal is a 4014: fatal for EVERY feature, not
  // just the one that asked. So a disabled feature must contribute none of them.
  for (const f of FEATURES) {
    if (f.enabled) continue;
    assert.strictEqual(f.intents & intents.PRIVILEGED, 0,
      `disabled ${f.name} still asks for ${intents.names(f.intents & intents.PRIVILEGED).join('|')}`);
  }
});

// ── security watch ─────────────────────────────────────────────────────────────────────────────
const security = require(path.join(botDir, 'features', 'security.js'));

const permChange = (oldV, newV) => [{ key: 'permissions', old_value: oldV, new_value: newV }];

test('a permission diff reports what was GRANTED, not what a role already had', () => {
  // "This role has Administrator" is not news; "this role was JUST given Administrator" is the
  // whole alert. Renaming an admin role must not read as a takeover.
  assert.deepStrictEqual(security.grantedPerms(permChange('8', '8')), [], 'already had it');
  assert.deepStrictEqual(security.grantedPerms(permChange('8', '0')), [], 'removing power is not a grant');
  assert.deepStrictEqual(security.grantedPerms(permChange('0', '8')), ['ADMINISTRATOR']);
});

test('ADMINISTRATOR is reported alone, since it implies the rest', () => {
  // Listing twelve permissions when one word covers it makes an alert harder to read, not better.
  assert.deepStrictEqual(security.grantedPerms(permChange('0', '2147483647')), ['ADMINISTRATOR']);
});

test('lesser dangerous grants are named individually', () => {
  assert.deepStrictEqual(security.grantedPerms(permChange('0', '6')).sort(), ['BAN_MEMBERS', 'KICK_MEMBERS']);
});

test('a change with no permissions key is not a permission grant', () => {
  assert.deepStrictEqual(security.grantedPerms([{ key: 'name', old_value: 'a', new_value: 'b' }]), []);
  assert.deepStrictEqual(security.grantedPerms(undefined), []);
});

test('an unparseable permission value degrades to zero rather than throwing', () => {
  // These arrive from the gateway as strings and a malformed one must not kill the handler.
  assert.deepStrictEqual(security.grantedPerms(permChange('nonsense', 'also nonsense')), []);
});

test('the raid alarm fires once per wave, not once per joiner', async () => {
  const posts = [];
  const rest = { postMessage: async (c, p) => { posts.push(p); return { id: 'x' }; } };
  const s = security({
    cfg: { guildId: 'g', securityChannelId: 'S', securityRaidJoins: 3,
           securityRaidWindowSeconds: 60, securityRaidCooldownMinutes: 10 },
    log: () => {}, rest, cache,
  });
  for (let i = 0; i < 6; i++) {
    s.on.GUILD_MEMBER_ADD({ guild_id: 'g', user: { id: String(175928847299117063n + BigInt(i)), username: 'u' + i } });
  }
  await new Promise((r) => setTimeout(r, 30));
  assert.strictEqual(posts.length, 1, `expected one alarm, got ${posts.length}`);
  assert.ok(/join/i.test(posts[0].embeds[0].title), posts[0].embeds[0].title);
});

test('the raid alarm says out loud that it did NOT act', async () => {
  // An alarm that looks like it handled something, but did not, is worse than no alarm.
  const posts = [];
  const rest = { postMessage: async (c, p) => { posts.push(p); return { id: 'x' }; } };
  const s = security({ cfg: { guildId: 'g', securityChannelId: 'S', securityRaidJoins: 2 }, log: () => {}, rest, cache });
  for (let i = 0; i < 2; i++) {
    s.on.GUILD_MEMBER_ADD({ guild_id: 'g', user: { id: String(200000000000000000n + BigInt(i)), username: 'u' } });
  }
  await new Promise((r) => setTimeout(r, 30));
  const fields = posts[0].embeds[0].fields.map((f) => f.value).join(' ');
  assert.ok(/none/i.test(fields) && /alert only/i.test(fields), fields);
});

test('the bot never alerts on its OWN audit entries', async () => {
  // /moveall and moderation timeouts both write audit entries. Alerting on them would train
  // everyone to ignore this channel inside a day.
  const posts = [];
  const rest = { postMessage: async (c, p) => { posts.push(p); return { id: 'x' }; } };
  const s = security({ cfg: { guildId: 'g', securityChannelId: 'S' }, log: () => {}, rest, cache });
  s.on.READY({ user: { id: 'SELF' } });
  s.on.GUILD_AUDIT_LOG_ENTRY_CREATE({ guild_id: 'g', action_type: 25, user_id: 'SELF', target_id: 'v' });
  await new Promise((r) => setTimeout(r, 20));
  assert.strictEqual(posts.length, 0, 'the bot alerted on its own action');
  s.on.GUILD_AUDIT_LOG_ENTRY_CREATE({ guild_id: 'g', action_type: 25, user_id: 'SOMEONE', target_id: 'v' });
  await new Promise((r) => setTimeout(r, 20));
  assert.strictEqual(posts.length, 1, 'a real actor should alert');
});

test('an Administrator grant pings, an ordinary audit event does not', async () => {
  // The single justified override of the no-ping default in this entire bot.
  const posts = [];
  const rest = { postMessage: async (c, p) => { posts.push(p); return { id: 'x' }; } };
  const s = security({ cfg: { guildId: 'g', securityChannelId: 'S', securityAlertRoleId: 'R9' }, log: () => {}, rest, cache });
  s.on.GUILD_AUDIT_LOG_ENTRY_CREATE({ guild_id: 'g', action_type: 31, user_id: 'X', changes: permChange('0', '8') });
  s.on.GUILD_AUDIT_LOG_ENTRY_CREATE({ guild_id: 'g', action_type: 23, user_id: 'X' });   // unban, NOTABLE
  await new Promise((r) => setTimeout(r, 30));
  assert.deepStrictEqual(posts[0].allowed_mentions, { roles: ['R9'] }, 'a granted Administrator must ping');
  assert.ok(!posts[1].allowed_mentions || !posts[1].allowed_mentions.roles, 'an unban must not ping');
});

test('SECURITY ALERTS NEVER ACT - no kick, ban, prune or permission write', () => {
  const src = fs.readFileSync(path.join(botDir, 'features', 'security.js'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  for (const forbidden of ['/bans/', 'modifyMember', 'deleteMessage', 'PUT', 'DELETE']) {
    assert.ok(!src.includes(forbidden), `security reached for ${forbidden}`);
  }
});

test('security is OFF without a channel and asks for no privileged intent', () => {
  const off = security({ cfg: { guildId: 'g' }, log: () => {}, rest: {}, cache });
  assert.strictEqual(off.enabled, false);
  assert.strictEqual(off.intents & intents.PRIVILEGED, 0);
  const on = security({ cfg: { guildId: 'g', securityChannelId: 'S' }, log: () => {}, rest: {}, cache });
  assert.ok(on.intents & intents.BITS.GUILD_MEMBERS, 'raid alarm needs member events');
  assert.ok(on.intents & intents.BITS.GUILD_MODERATION, 'audit stream needs GUILD_MODERATION');
});

// ── presence map art (unproven, gated off) ─────────────────────────────────────────────────────
test('map art is absent unless explicitly switched on', () => {
  const snap = { updated: new Date().toISOString(), online: true, map: 'mp_nuked', mapName: 'Nuketown', humans: 3 };
  assert.ok(!buildPresence(snap, Date.now(), null).activities[0].assets, 'art must be opt-in');
});

test('map art keys off the ENGINE map id, so an uploaded asset just works', () => {
  // The Portal asset is named mp_nuked; status.json already carries mp_nuked. No second table.
  const snap = { updated: new Date().toISOString(), online: true, map: 'mp_nuked', mapName: 'Nuketown', humans: 3 };
  const a = buildPresence(snap, Date.now(), { appId: 'APP' }).activities[0];
  assert.strictEqual(a.assets.large_image, 'mp_nuked');
  assert.strictEqual(a.assets.large_text, 'Nuketown');
  assert.strictEqual(a.application_id, 'APP', 'assets resolve against an application id');
});

test('an empty, offline or stale server carries NO map picture', () => {
  // A confident map image on a profile the data cannot support is the same lie as a frozen roster.
  const art = { appId: 'APP' };
  const now = Date.now();
  const cases = [
    { updated: new Date().toISOString(), online: true, humans: 0, map: 'mp_nuked' },
    { updated: new Date().toISOString(), online: false, humans: 3, map: 'mp_nuked' },
    { updated: new Date(now - 10 * 60000).toISOString(), online: true, humans: 3, map: 'mp_nuked' },
  ];
  for (const snap of cases) {
    assert.ok(!buildPresence(snap, now, art).activities[0].assets,
      `art leaked onto ${JSON.stringify(snap).slice(0, 60)}`);
  }
});

// ── activity line style ────────────────────────────────────────────────────────────────────────
test('the shipped default is Watching, type 3', () => {
  // Chosen 2026-08-20. The type is selectable, but this is what goes out of the box.
  const p = require(path.join(botDir, 'features', 'presence.js'));
  const snap = { updated: new Date().toISOString(), online: true, map: 'mp_nuked', mapName: 'Nuketown', humans: 3 };
  const a = p.buildPresence(snap, Date.now(), null, undefined).activities[0];
  assert.strictEqual(a.type, 3);
  assert.strictEqual(a.name, '3 players on Nuketown');
});

test('type 4 puts the text in STATE, and still carries a name', () => {
  // Custom prints no verb and reads `state`; `name` is ignored by the client but mandatory on the
  // wire, so omitting it is a malformed payload rather than a shorter one.
  const p = require(path.join(botDir, 'features', 'presence.js'));
  const snap = { updated: new Date().toISOString(), online: true, map: 'mp_nuked', mapName: 'Nuketown', humans: 3 };
  const a = p.buildPresence(snap, Date.now(), null, 'custom').activities[0];
  assert.strictEqual(a.type, 4);
  assert.strictEqual(a.state, '3 players on Nuketown');
  assert.ok(a.name, 'name is mandatory even when nothing renders it');
});

test('changing the TYPE repicks the WORDS - no "Playing 3 players on"', () => {
  // THE bug this guards: a verb type with fragment phrasing reads broken. Each type gets phrasing
  // that completes its own verb.
  const p = require(path.join(botDir, 'features', 'presence.js'));
  const snap = { updated: new Date().toISOString(), online: true, map: 'mp_nuked', mapName: 'Nuketown', humans: 3 };
  for (const style of ['playing', 'competing']) {
    const a = p.buildPresence(snap, Date.now(), null, style).activities[0];
    assert.ok(/^Gunfight/.test(a.name), `${style} should lead with the game name, got "${a.name}"`);
    assert.ok(!/^\d+ player/.test(a.name), `${style} kept the Watching fragment: "${a.name}"`);
  }
});
