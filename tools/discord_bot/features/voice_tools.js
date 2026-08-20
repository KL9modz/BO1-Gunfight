'use strict';
/*
 * Bulk voice moves - drag a whole channel somewhere else in one command. Written for running
 * tournaments and scrims, where "everyone into your team channel" happens between every match and
 * doing it by hand is twenty drags.
 *
 *   /moveall from:#Lobby to:#Team A
 *
 * ── HOW IT KNOWS WHO TO MOVE ───────────────────────────────────────────────────────────────────
 * From lib/cache.js, which the CORE maintains. That matters: the voice map used to live inside the
 * voice log, so this command would have silently moved nobody on a bot with the log switched off.
 * Shared state belongs to the core precisely so a feature cannot depend on another being enabled.
 *
 * ── PERMISSION ─────────────────────────────────────────────────────────────────────────────────
 * Needs MOVE MEMBERS on the bot's role, and the bot must be able to see both channels. Without it
 * every move fails with a 403 and the card says so per member rather than claiming success.
 */

const { COLOR, card, chanChip, plural } = require('../lib/brand.js');

const { BITS } = require('../lib/intents.js');
const CH_VOICE = 2, CH_STAGE = 13;         // Discord channel types the picker should offer
// ⚠ A ceiling, not a limit anyone should hit. Fifty moves is already ~25s through the paced REST
// queue; a request for more is far likelier to be a mistake than an intention, and a bot that
// silently starts a five-minute job is worse than one that asks you to confirm what you meant.
const MAX_MOVE = 50;

module.exports = function voiceTools(ctx) {
  const { cfg, log, rest, cache } = ctx;

  const commands = {
    moveall: {
      admin: true,
      description: 'Move everyone from one voice channel into another',
      options: [
        { name: 'from', description: 'Channel to empty', type: 7, required: true, channel_types: [CH_VOICE, CH_STAGE] },
        { name: 'to',   description: 'Channel to fill',  type: 7, required: true, channel_types: [CH_VOICE, CH_STAGE] },
      ],
      run: async (opts, who) => {
        const from = String(opts.from), to = String(opts.to);
        if (from === to) return 'Those are the same channel.';

        const members = cache.voice.membersOf(from);
        if (!members.length) return `Nobody is in ${chanChip(from)}.`;
        if (members.length > MAX_MOVE) {
          return `${members.length} people are in ${chanChip(from)}, over the ${MAX_MOVE} cap. Move them in smaller groups.`;
        }

        // ⚠ Suppressed BEFORE the first move, not after: the events start arriving while the loop
        // is still running, and a window opened afterwards would miss the early ones.
        cache.voice.suppress(members);

        let moved = 0;
        const failed = [];
        for (const id of members) {
          try {
            // The reason lands in Discord's own audit log beside the action, so a human reading it
            // later sees which admin asked rather than just "the bot did it".
            await rest.modifyMember(cfg.guildId, id, { channel_id: to }, `/moveall by ${who}`);
            moved++;
          } catch (e) {
            // Individually, so one member who left mid-run cannot abort the rest.
            failed.push(id);
            log(`moveall: ${id} failed - ${e.message}`);
          }
        }

        const details = [
          ['From', chanChip(from)],
          ['To', chanChip(to)],
          ['Moved', `${moved} of ${members.length}`],
        ];
        if (failed.length) {
          // Named, not counted: "3 failed" is unactionable, and the usual cause is one person who
          // disconnected mid-run rather than a permission problem.
          details.push(['Failed', failed.map((id) => `<@${id}>`).join(' ')]);
        }

        return {
          embeds: [card({
            title: `Moved ${plural(moved, 'member')}`,
            color: failed.length ? COLOR.WARN : COLOR.OK,
            details,
            footer: true,
          })],
        };
      },
    },
  };

  return {
    name: 'voice_tools',
    enabled: true,
    // Reads the shared voice cache, which only stays warm while the core receives voice events.
    intents: BITS.GUILD_VOICE_STATES,
    permissions: ['Move Members'],
    commands,
    on: {},
  };
};
