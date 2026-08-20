'use strict';
/*
 * Ops slash commands - the read-only pair anyone in the guild may run, and the match controls the
 * admin role gates.
 *
 * ⚠ EVERY entry here is a FIXED TEMPLATE. Nothing accepts a caller-supplied rcon string, which is
 * what makes the whitelist a whitelist: a caller cannot reach a dvar this file does not name. The
 * role gate, the guild allowlist and the per-user bucket all live in bot.js, because they are
 * security properties of the ROUTER and must not be re-implemented per feature.
 */

// ⚠ THE shared status parser, the same module the panel and join-notify use. Its column handling is
// hard-won (bot names containing spaces, signed-16-bit negative ports, unreadable rows that must
// never be CLAIMED as bots) - a fresh regex here would re-earn those bugs one at a time.
const { parseStatusText, stripColors } = require('../../status_parse.js');
const { MAPS, mapName, labels, idOf } = require('../lib/maps.js');

module.exports = function ops(ctx) {
  const { panel } = ctx;
  const rcon = panel.rcon;

  const commands = {
    status: {
      admin: false, description: 'Who is on, which map, what score',
      run: async () => {
        const st = await rcon('gf_state', false);
        const sv = await rcon('status', false);
        if (!st.ok && !sv.ok) return 'Server did not answer (is it up?).';
        const s = parseStatusText(sv.response || '');
        // bot === null means the row could not be classified; it is deliberately NOT counted as a
        // bot, the same rule the panel and conn_logger follow.
        const humans = s.players.filter((p) => p.bot === false).length;
        const bots   = s.players.filter((p) => p.bot === true).length;
        const f = (st.response || '').match(/gf_state.*?"([^"]*)"/);
        const parts = f ? f[1].split(':') : [];
        const who = `${humans} player${humans === 1 ? '' : 's'}${bots ? ` + ${bots} bots` : ''}`;
        return parts.length >= 5
          ? `**${mapName(s.map)}** - round ${parts[2]}, Allies ${parts[0]} - ${parts[1]} Axis, ${who}`
          : `**${mapName(s.map)}** - ${who}`;
      },
    },

    players: {
      admin: false, description: 'List the players currently connected',
      run: async () => {
        const r = await rcon('status', false);
        if (!r.ok) return 'Server did not answer.';
        const s = parseStatusText(r.response || '');
        if (!s.players.length) return 'Nobody is on right now.';
        // TICK rather than escaped backticks inside a template literal: the escaping is a trap in
        // every shell that edits this file, and the result is identical.
        const TICK = String.fromCharCode(96);
        const line = (p) => TICK + stripColors(p.name) + TICK
          + (p.score !== null ? ' - ' + p.score : '')
          + (p.ping !== null ? ' (' + p.ping + 'ms)' : '')
          + (p.bot === true ? ' *[bot]*' : '');
        const humans = s.players.filter((p) => p.bot !== true).map(line);
        const bots   = s.players.filter((p) => p.bot === true).map(line);
        return `**${mapName(s.map)}** - ${humans.length} player${humans.length === 1 ? '' : 's'}` +
          `${bots.length ? ' + ' + bots.length + ' bots' : ''}\n${humans.concat(bots).join('\n')}`;
      },
    },

    say: {
      admin: true, description: 'Send a message to everyone in game',
      options: [{ name: 'message', description: 'What to say', type: 3, required: true }],
      run: async (opts, user) => {
        const msg = panel.sanitiseForGame(`${user}: ${opts.message}`);
        if (!msg) return 'Nothing left to send after sanitising.';
        // ONE chained write: two packets can race on the paced queue and print an empty message.
        const r = await rcon(`set gf_say "${msg}";set gf_cmd saymsg`);
        const TICK = String.fromCharCode(96);
        return r.ok ? `Sent: ${TICK}${msg}${TICK}` : `Failed: ${r.error || 'no reply'}`;
      },
    },

    map: {
      admin: true, description: 'Change the map',
      options: [{ name: 'name', description: 'Map name', type: 3, required: true,
                  choices: labels().slice(0, 25).map((k) => ({ name: k, value: k })) }],
      run: async (opts) => {
        const id = idOf(opts.name);
        if (!id) return `Unknown map. Known: ${labels().join(', ')}`;
        const r = await rcon(`map ${id}`);
        return r.ok ? `Changing map to **${opts.name}** (${id}).` : `Failed: ${r.error || 'no reply'}`;
      },
    },

    restart: {
      admin: true, description: 'Restart the current match (same map, scores reset)',
      run: async () => {
        const r = await rcon('set gf_cmd matchrestart');
        return r.ok ? 'Match restarting.' : `Failed: ${r.error || 'no reply'}`;
      },
    },

    pause:  { admin: true, description: 'Pause the match',
              run: async () => (await rcon('set gf_cmd pause')).ok ? 'Match paused.' : 'Failed.' },
    resume: { admin: true, description: 'Resume the match',
              run: async () => (await rcon('set gf_cmd resume')).ok ? 'Match resumed.' : 'Failed.' },
  };

  return {
    name: 'ops',
    enabled: true,           // the reason the bot exists; never conditional
    intents: 0,              // slash commands arrive as INTERACTION_CREATE, which needs no intent
    permissions: [],         // nothing beyond the default invite
    commands,
    on: {},
  };
};

// Exported for the tests, which assert the whitelist properties without standing up a gateway.
module.exports.MAPS = MAPS;
