'use strict';
/*
 * Bot presence - the live line under the bot in the member list:
 *
 *     Black Ops Gunfight
 *     Watching 3 players on Nuketown
 *
 * ── WHAT THIS IS NOT ───────────────────────────────────────────────────────────────────────────
 * ⚠ This is NOT Rich Presence, and the Developer Portal's Rich Presence Art Assets page has no
 * bearing on it. Rich Presence is published by the GAME PROCESS on a player's own PC over the
 * Discord desktop client's local IPC pipe, and BO1/Plutonium does not speak it - a server cannot
 * set a player's presence, because presence belongs to the machine it runs on. Reaching it would
 * take a helper app every player installs, which is why it is parked.
 *
 * What IS reachable is our OWN process's presence: gateway op 3, no privileged intent, no
 * permission, no art assets, nothing for anyone to install. It carries most of the same value -
 * "is anyone on right now" - to everyone who looks at the member list.
 *
 * ── WHERE THE NUMBERS COME FROM ────────────────────────────────────────────────────────────────
 * ⚠ status.json, NOT rcon. GF-StatusService is the box's single rcon reader and already projects
 * this file every ~5s; reading it costs nothing and cannot saturate the panel's paced queue. The
 * project rule is "never add another rcon poller", and a 20s presence refresh through /api/rcon
 * would have been exactly that, permanently, for a cosmetic feature. Same reasoning that makes
 * GF-ConnLogger diff admin.json instead of polling.
 *
 * ── COUNTING ───────────────────────────────────────────────────────────────────────────────────
 * ⚠ HUMANS only. Bot fill is on by default, so a bot-padded server would otherwise always read
 * busy and the line would mean nothing. Same rule the match stats and the join alerts follow: a
 * number that counts bots is a number nobody can trust.
 */

const fs = require('fs');

/*
 * Discord activity types. For 0/2/3/5 the client prints a VERB and then `name`, so the text has to
 * complete that sentence ("Watching 3 players on Nuketown").
 *
 * ⚠ TYPE 4 (Custom) is the odd one and the reason this is selectable at all: it prints NO verb, and
 * it reads `state` rather than `name` - `name` still has to be present but is ignored by the
 * client. That frees the line from sounding like a sentence someone else started, and it is the only
 * type that can carry an emoji.
 */
const TYPES = { playing: 0, listening: 2, watching: 3, custom: 4, competing: 5 };
const WATCHING = 3;
const NAME_MAX = 128;
// ⚠ status_service writes every ~5s, so anything approaching a minute means the writer is dead or
// stuck. conn_logger calls the same file stale at 30s; this is deliberately more forgiving because
// presence is cosmetic - flapping the member list to "status unknown" on a brief hiccup reads worse
// than being a minute behind.
const STALE_MS = 60000;
// The refresh is what BOUNDS THE RATE. Discord allows ~5 presence updates per 20s per session, and
// a timer that can fire at most once per 20s cannot exceed that however busy the server gets. The
// change check below is a second, cheaper guard - not the safety one.
const REFRESH_MS = 20000;
const DEFAULT_STATUS_JSON = 'C:\\inetpub\\wwwroot\\live\\status.json';

const clamp = (t, n) => (t.length > n ? t.slice(0, n - 1) + '…' : t);
/*
 * 🛑 MAP ART ON A BOT PROFILE DOES NOT RENDER. SETTLED 2026-08-20 - see
 * docs/notes/bot-presence-is-text-only.md. Kept, off, in case Discord ever changes.
 *
 * The activity object has an `assets` field (large_image / large_text). For a GAME's rich presence
 * it renders the big picture on a profile. For a BOT it is IGNORED, which the buttons probe below
 * settled: buttons are the same rich-presence family and the MORE permissive of the two, and a
 * well-formed two-button payload was accepted by the gateway and rendered as text only.
 *
 * ⚠ So do NOT go and source 26 map images for this. Map art in an EMBED is unaffected and works
 * fine - that takes any public https URL and is a completely different mechanism.
 *
 * (Uploading an asset would need the Portal anyway: the API answers a bot token with
 * "Bots cannot use this endpoint", 403 code 20001.)
 *
 * ⚠ The key is an ASSET NAME uploaded to OUR application (Portal -> Rich Presence -> Art Assets),
 * NOT a URL. This is the one place a gunfight.us image does NOT work - unlike an embed thumbnail,
 * which takes any public https URL. Two different mechanisms, easy to conflate.
 *
 * The key used is the ENGINE map id straight out of status.json (mp_nuked), so an uploaded asset
 * named mp_nuked just starts working with no second lookup table to drift.
 */
// ⚠ Max TWO, labels capped at 32. Discord rejects the whole payload on a malformed button rather
// than dropping it, so it is clamped here instead of trusted from config.
const BUTTON_MAX = 2, LABEL_MAX = 32;

const shape = (name, status, art, style, buttons) => {
  const type = Object.prototype.hasOwnProperty.call(TYPES, style) ? TYPES[style] : WATCHING;
  // ⚠ `name` is mandatory on every activity, even type 4 where nothing renders it. Omitting it is a
  // malformed payload, not a shorter one.
  const activity = type === TYPES.custom
    ? { name: 'Custom Status', type, state: clamp(name, NAME_MAX) }
    : { name: clamp(name, NAME_MAX), type };
  if (art && art.key) {
    activity.application_id = art.appId;
    activity.assets = { large_image: art.key, large_text: clamp(art.text || art.key, NAME_MAX) };
  }
  // 🛑 PROVEN IGNORED for a bot's own presence, 2026-08-20. Two well-formed buttons were sent, the
  // gateway ACCEPTED the payload (the text half updated normally, no disconnect), and the profile
  // rendered "Watching / Launch" and nothing else. So this is Discord dropping the field for bots,
  // not rejecting our message - and it is what settles the assets question above too.
  // ⚠ Do not re-run this experiment: docs/notes/bot-presence-is-text-only.md.
  // Kept and defaulted OFF because it costs nothing and Discord may change; the validation below
  // stays for the same reason - a malformed button would cost the WHOLE presence, not just itself.
  const btns = (buttons || [])
    .filter((b) => b && b.label && typeof b.url === 'string' && /^https?:/i.test(b.url))
    .slice(0, BUTTON_MAX)
    .map((b) => ({ label: clamp(b.label, LABEL_MAX), url: b.url }));
  if (btns.length) activity.buttons = btns;
  return { since: null, afk: false, status, activities: [activity] };
};

// Module-level and PURE so the wording and the never-lie rules can be tested without a gateway or
// a live server - see tools/tests/discord_bot.test.js.
//
// ⚠ A STALE SNAPSHOT MUST NEVER RENDER AS A CONFIDENT ROSTER. If status_service dies, the last
// file it wrote stays on disk saying "4 players on Zoo" forever, and presence would advertise a
// server that may be empty or down. Unknown is the honest answer, and the dot going yellow is the
// only warning anyone gets. Same rule the status embed follows (New-StatusEmbed, PS suite).
// ⚠ THREE phrasings, one per grammatical shape. "Playing 3 players on Nuketown" is what you get if
// the type changes and the words do not, so the words are chosen per type rather than reused.
// ⚠ And each must ALSO read standalone: the member list prints "Watching for players" inline, but
// the PROFILE CARD stacks them - "Watching" on one line, the text under it - where a fragment like
// "for players" reads broken. Proven on a real profile 2026-08-20. That is why the empty state
// names the MAP: it stands alone, says the server is alive, and never advertises the emptiness.
//   verb    - completes "Watching ..."
//   branded - completes "Playing ..." / "Competing in ...", and gets the game name into the line
//   plain   - stands alone under type 4, which prints no verb at all
const SAY = {
  verb:    { unknown: 'the server (status unknown)', offline: 'the server (offline)', empty: (s) => (s.mapName || s.map ? (s.mapName || s.map) : 'Gunfight'),
             busy: (n, m) => `${n} player${n === 1 ? '' : 's'} on ${m}` },
  branded: { unknown: 'Gunfight - status unknown',   offline: 'Gunfight - server offline', empty: (s) => `Gunfight - ${s.mapName || 'open now'}`,
             busy: (n, m) => `Gunfight - ${n} on ${m}` },
  plain:   { unknown: 'Status unknown',              offline: 'Server offline',       empty: (s) => (s.mapName || s.map || 'Gunfight'),
             busy: (n, m) => `${n} player${n === 1 ? '' : 's'} on ${m}` },
};
const SAY_FOR = (style) => (style === 'custom' ? SAY.plain
                          : (style === 'playing' || style === 'competing') ? SAY.branded
                          : SAY.verb);

function buildPresence(snap, nowMs, art, style, buttons, opts) {
  const o = opts || {};
  // ⚠ Pinning the activity to branding MOVES the live line into the custom status, where it stands
  // alone and the brand is already one line above it. So it takes the PLAIN phrasing - otherwise
  // "Playing gunfight.us" sits over "Gunfight - 3 on Nuketown" and says Gunfight twice, which is
  // the "Play appeared twice" bug for the third time in one day.
  const say = o.text ? SAY.plain : SAY_FOR(style);
  if (!snap || typeof snap !== 'object') return withOverrides(shape(say.unknown, 'idle', null, style, buttons), o, say.unknown);

  const stamped = Date.parse(snap.updated);
  if (!Number.isFinite(stamped) || nowMs - stamped > STALE_MS) {
    return withOverrides(shape(say.unknown, 'idle', null, style, buttons), o, say.unknown);
  }
  if (!snap.online) return withOverrides(shape(say.offline, 'dnd', null, style, buttons), o, say.offline);

  const humans = Number(snap.humans) || 0;
  // ⚠ AN EMPTY SERVER IS NOT ADVERTISED AS EMPTY. This line sits on a public profile, so "an empty
  // server" prints a reason not to join exactly where prospective players read it. "for players" is
  // equally true - the bot IS watching for them - without selling the emptiness.
  // ⚠ Still no lie: it never claims anyone is on, and it never counts bots to pad a number.
  // ⚠ The dot goes GREEN rather than idle for the same reason. That does cost a signal - green no
  // longer means "someone is playing" - but red still means offline and idle still means the data
  // cannot be vouched for, so both states that indicate a PROBLEM are untouched.
  // The map is dropped here on purpose: which map an empty server sits on helps nobody.
  if (humans === 0) { const live = say.empty(snap); return withOverrides(shape(live, 'online', null, style, buttons), o, live); }

  const map = snap.mapName || snap.map || 'Gunfight';
  // ⚠ Art only on the ONLINE path. An empty or offline server has no map worth picturing, and a
  // stale snapshot must not put a confident map image on the profile.
  const withArt = art && snap.map ? Object.assign({}, art, { key: snap.map, text: map }) : null;
  const live = say.busy(humans, map);
  return withOverrides(shape(live, 'online', withArt, style, buttons), o, live);
}

/*
 * The presence the gateway actually receives.
 *
 * ⚠ TWO SEPARATE SURFACES, and they are easy to conflate:
 *   - the ACTIVITY  ("Playing gunfight.us")   - a verb plus `name`, types 0/2/3/5
 *   - the CUSTOM STATUS                       - type 4, prints NO verb and reads `state`
 * A user can show both at once. Whether a BOT can is undocumented, so this sends both when both
 * are configured and the answer is whatever the profile renders.
 *
 * `presenceText` pins the activity to a fixed string (branding), which frees the LIVE line to
 * move into the custom status via the {status} token - so the profile can advertise and report at
 * the same time instead of choosing.
 */
function withOverrides(p, o, liveLine) {
  const a = p.activities[0];
  if (o.text) {
    // A static activity: the verb still applies, so "gunfight.us" reads "Playing gunfight.us".
    if (a.type === TYPES.custom) { a.state = clamp(o.text, NAME_MAX); } else { a.name = clamp(o.text, NAME_MAX); }
  }
  if (o.custom) {
    // {status} is what keeps the live half alive when the activity has been pinned to branding.
    const text = String(o.custom).replace(/{status}/g, liveLine);
    // ⚠ FIRST in the array: a client rendering only one takes the first, and the custom status is
    // the one carrying the live information once the activity is a fixed advert.
    p.activities.unshift({ name: 'Custom Status', type: TYPES.custom, state: clamp(text, NAME_MAX) });
  }
  return p;
}

module.exports = presence;
module.exports.buildPresence = buildPresence;

function presence(ctx) {
  const { cfg, log, setPresence } = ctx;
  // Default ON: it needs no intent, no permission and no portal toggle, so demanding a config key
  // would only be a step to discover. `"presence": false` turns it off.
  const enabled = cfg.presence !== false;
  const statusPath = cfg.statusJson || DEFAULT_STATUS_JSON;
  // Off until someone uploads art in the Portal and confirms a bot profile actually renders it.
  const art = cfg.presenceMapArt ? { appId: cfg.applicationId } : null;
  const style = cfg.presenceStyle || 'watching';
  const buttons = cfg.presenceButtons || [];
  const opts = { text: cfg.presenceText || '', custom: cfg.presenceCustom || '' };

  let timer = null;
  let lastSent = null;      // full payload signature: suppresses a resend of an identical line
  let lastStatus = null;    // just the dot: what is worth a log line

  function read() {
    try {
      // BOM-tolerant for the same reason config.local.json is: anything on this box may have been
      // touched by a PowerShell or Notepad write.
      return JSON.parse(fs.readFileSync(statusPath, 'utf8').replace(/^\uFEFF/, ''));
    } catch {
      return null;          // absent or mid-write; buildPresence turns that into "status unknown"
    }
  }

  function tick() {
    const p = buildPresence(read(), Date.now(), art, style, buttons, opts);
    const sig = JSON.stringify(p);
    if (sig === lastSent) return;
    lastSent = sig;
    setPresence(p);
    // ⚠ Logged on a STATE change, not on every push. The player count changes all evening, and a
    // line per change would bury the gateway's own messages in a cosmetic feature's chatter.
    if (p.status !== lastStatus) {
      lastStatus = p.status;
      const a = p.activities[0];
      log(`presence: ${a.state || a.name} [${p.status}, type ${a.type}]`);
    }
  }

  return {
    name: 'presence',
    enabled,
    intents: 0,               // presence is something we SEND; receiving anything is not required
    permissions: [],
    commands: {},

    on: {
      // ⚠ READY, not RESUMED. A fresh IDENTIFY clears whatever presence the old session had, so
      // the memo has to be dropped or the change check would suppress the re-push and the bot
      // would sit blank until the next time the count happened to move. A RESUME keeps presence,
      // and correctly does nothing here.
      READY: () => {
        lastSent = null;
        tick();
        if (!timer) timer = setInterval(tick, REFRESH_MS);   // guarded: reconnects must not stack timers
      },
    },
  };
}
