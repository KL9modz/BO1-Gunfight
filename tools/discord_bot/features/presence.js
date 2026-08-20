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

// Discord activity types. 3 = Watching, so the client renders "Watching <name>" and `name` has to
// complete that sentence.
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
 * ⚠ MAP ART ON THE BOT'S PROFILE IS UNPROVEN, AND OFF BY DEFAULT.
 *
 * The activity object has an `assets` field (large_image / large_text). For a GAME's rich presence
 * it renders the big picture on a profile. Whether Discord honours it for a BOT's own presence is
 * not something the gateway docs state, and it cannot be tested from here: uploading an asset needs
 * the Developer Portal, because the API answers a bot token with
 * "Bots cannot use this endpoint" (403, code 20001).
 *
 * ⚠ The key is an ASSET NAME uploaded to OUR application (Portal -> Rich Presence -> Art Assets),
 * NOT a URL. This is the one place a gunfight.us image does NOT work - unlike an embed thumbnail,
 * which takes any public https URL. Two different mechanisms, easy to conflate.
 *
 * The key used is the ENGINE map id straight out of status.json (mp_nuked), so an uploaded asset
 * named mp_nuked just starts working with no second lookup table to drift.
 */
const shape = (name, status, art) => {
  const activity = { name: clamp(name, NAME_MAX), type: WATCHING };
  if (art && art.key) {
    activity.application_id = art.appId;
    activity.assets = { large_image: art.key, large_text: clamp(art.text || art.key, NAME_MAX) };
  }
  return { since: null, afk: false, status, activities: [activity] };
};

// Module-level and PURE so the wording and the never-lie rules can be tested without a gateway or
// a live server - see tools/tests/discord_bot.test.js.
//
// ⚠ A STALE SNAPSHOT MUST NEVER RENDER AS A CONFIDENT ROSTER. If status_service dies, the last
// file it wrote stays on disk saying "4 players on Zoo" forever, and presence would advertise a
// server that may be empty or down. Unknown is the honest answer, and the dot going yellow is the
// only warning anyone gets. Same rule the status embed follows (New-StatusEmbed, PS suite).
function buildPresence(snap, nowMs, art) {
  if (!snap || typeof snap !== 'object') return shape('the server (status unknown)', 'idle');

  const stamped = Date.parse(snap.updated);
  if (!Number.isFinite(stamped) || nowMs - stamped > STALE_MS) {
    return shape('the server (status unknown)', 'idle');
  }
  if (!snap.online) return shape('the server (offline)', 'dnd');

  const humans = Number(snap.humans) || 0;
  // The map is dropped here on purpose: which map an empty server sits on helps nobody, and the
  // shorter line reads better in a member list.
  if (humans === 0) return shape('an empty server', 'idle');

  const map = snap.mapName || snap.map || 'Gunfight';
  // ⚠ Art only on the ONLINE path. An empty or offline server has no map worth picturing, and a
  // stale snapshot must not put a confident map image on the profile.
  const withArt = art && snap.map ? Object.assign({}, art, { key: snap.map, text: map }) : null;
  return shape(`${humans} player${humans === 1 ? '' : 's'} on ${map}`, 'online', withArt);
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
    const p = buildPresence(read(), Date.now(), art);
    const sig = JSON.stringify(p);
    if (sig === lastSent) return;
    lastSent = sig;
    setPresence(p);
    // ⚠ Logged on a STATE change, not on every push. The player count changes all evening, and a
    // line per change would bury the gateway's own messages in a cosmetic feature's chatter.
    if (p.status !== lastStatus) {
      lastStatus = p.status;
      log(`presence: ${p.activities[0].name} [${p.status}]`);
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
