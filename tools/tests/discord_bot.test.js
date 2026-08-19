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
