/*
 * probe_presence_art.js - Does a bot's own presence render `assets` (the map picture)?
 *
 * 🛑 ANSWERED 2026-08-21: NO. The activity card renders, the picture never does - proven with both
 * reference forms (an `mp:` proxy path, and an asset name resolved through an `application_id`
 * whose app really owns that name). `assets` is accepted and silently dropped, exactly like
 * `buttons`. Full result + the probe-design lessons: docs/notes/bot-presence-is-text-only.md.
 * Kept, not deleted, for the ONE shape left untested: our own app id + an asset WE own, which needs
 * a Portal upload because a bot token is 403 on both upload endpoints.
 *
 * WHY THIS EXISTS: docs/notes/bot-presence-is-text-only.md settled that BUTTONS are ignored on a
 * bot presence, and inferred that `assets` would be too - flagged with a ⚠ as inference, not proof.
 * The stated reason not to test it was that sourcing 26 map images was a day's work on a hope. That
 * cost is now zero (tools/fetch_map_art.ps1), so the inference is worth converting into an answer.
 *
 * ⚠ WE CANNOT UPLOAD ART. Both routes answer a bot token with 403:
 *     POST /oauth2/applications/{id}/assets           - "Bots cannot use this endpoint" (20001)
 *     POST /applications/{id}/external-assets         - 403, no body
 * So this probe references PLUTONIUM's application and THEIR asset, which needs no upload at all.
 * That is a diagnostic borrow, not a shipping design: if the field turns out to render, the real
 * version uploads our own copies to our own app in the Portal.
 *
 * ⚠ RUN WITH GF-DiscordBot STOPPED. Two gateway sessions on one token both claim shard 0 and their
 * presences fight - the service re-asserts its own line on its next poll and would stomp the probe
 * mid-look, which reads as "the art did not render".
 *
 * 🛑 AND STOPPING IT IS NOT ENOUGH ON ITS OWN - GF-Watchdog RESTARTS IT WITHIN 3 MINUTES.
 * Learned the expensive way on the first run: the watchdog saw the task Ready, called it DOWN,
 * relaunched it 2m45s into a 4m30s probe and PAGED the owner with a false "GF-DiscordBot down".
 * The service's custom status then won the profile (a custom status beats every activity - see the
 * note), so the last two variants were never on screen at all and looked like failures.
 * So this probe drops the same self-expiring maintenance marker deploy.ps1 uses, and clears it on
 * the way out. The marker stands the watchdog down for EVERY check (watchdog.ps1:180), which is
 * also why it must be short and must be removed - it auto-expires so an aborted run cannot leave
 * the box unwatched.
 *
 *   node probe_presence_art.js          # ~3 min, cycles all variants, then exits
 *   node probe_presence_art.js 2        # HOLD variant 2 until Ctrl-C - no deadline to catch
 *
 * 🛑 PREFER THE HOLD. A timed cycle asks a human to catch a 45-second slot on a profile popout,
 * and a slot missed is indistinguishable from a slot that did not render - which is how run 2
 * produced nothing usable. Hold one state, look whenever, then switch.
 */

const fs = require('fs');
const path = require('path');

const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.local.json'), 'utf8').replace(/^﻿/, ''));

const PLUTO_APP   = '924614901975117834';   // Plutonium T5: Multiplayer
const PLUTO_NUKED = '924740217620004945';   // their mp_nuked asset id

// Each variant holds long enough for a human to open the profile and look. The TEXT differs per
// variant so the profile itself says which one is on screen - otherwise a look at the wrong moment
// is indistinguishable from a variant that did not render.
/*
 * 🛑 THE CONTROL RUNS FIRST, AND THAT IS THE WHOLE LESSON OF RUN 1.
 * Run 1 put it last, where the watchdog's restart had already stomped it - so when the profile
 * showed NO ACTIVITY AT ALL, there was no way to tell "Discord ignores assets" from "this probe's
 * presence never rendered in the first place". A probe whose control is unobserved answers nothing.
 *
 * The variants now isolate one variable each, so the pattern of which ones appear IS the answer:
 *   1 renders, 2 does not  -> `assets` alone kills the activity
 *   1,2 render, 4 does not -> a FOREIGN application_id kills it (the run-1 suspect)
 *   3 renders with no art  -> the field is accepted and silently ignored, as the note inferred
 */
const VARIANTS = [
  { hold: 45, label: '1 CONTROL: plain text, no assets, no app id',
    activity: { name: '1 - control (no art)', type: 0 } },
  { hold: 45, label: '2: assets only, NO application_id',
    activity: { name: '2 - assets, no app id', type: 0,
                assets: { large_image: `mp:app-assets/${PLUTO_APP}/${PLUTO_NUKED}`, large_text: 'Nuketown' } } },
  // Our app owns ZERO assets, so the image cannot resolve - that is fine and deliberate. The
  // question here is only whether the ACTIVITY survives an assets field pointing at our own app,
  // which separates "bad app id" from "assets rejected outright".
  { hold: 45, label: '3: assets + OUR app id (image will not resolve - activity survival only)',
    activity: { name: '3 - assets, our app id', type: 0, application_id: cfg.applicationId,
                assets: { large_image: 'mp_nuked', large_text: 'Nuketown' } } },
  { hold: 45, label: '4: assets + THEIR app id (the run-1 shape)',
    activity: { name: '4 - assets, their app id', type: 0, application_id: PLUTO_APP,
                assets: { large_image: 'mp_nuked', large_text: 'Nuketown' } } },
];

// Same file and shape as toolscommon.ps1's Write-GfMaintenanceMarker, read by watchdog.ps1.
const MARKER = path.join(__dirname, '..', 'vps_services', 'watchdog_maintenance.json');
function standDownWatchdog(minutes) {
  try {
    fs.writeFileSync(MARKER, JSON.stringify({
      until: new Date(Date.now() + minutes * 60000).toISOString(), reason: 'presence art probe' }));
    log(`watchdog stood down for ${minutes} min`);
  } catch (e) { log(`⚠ could not set the maintenance marker (${e.message}) - the watchdog WILL restart the bot mid-probe`); }
}
function resumeWatchdog() { try { fs.unlinkSync(MARKER); log('maintenance marker cleared'); } catch {} }

let ws, hb = null, idx = -1, timer = null;
const log = (m) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${m}`);
const send = (op, d) => ws.send(JSON.stringify({ op, d }));

function presence(v) {
  return { since: null, afk: false, status: 'online', activities: [v.activity] };
}

// The marker expires by design (an aborted run must not leave the box unwatched), so a HOLD that
// outlives it would get the bot restarted underneath it - the exact contamination of run 1, just
// slower. Re-stamping keeps the window open only while this process is alive to do it.
function keepWatchdogDown() { setInterval(() => standDownWatchdog(8), 5 * 60 * 1000).unref(); }

function holdOne(n) {
  const v = VARIANTS[n - 1];
  if (!v) { log(`no variant ${n} - there are ${VARIANTS.length}`); process.exit(1); }
  send(3, presence(v));
  keepWatchdogDown();
  log(`>>> HOLDING ${v.label}`);
  log(`    the profile should read "${v.activity.name}" until this is stopped - look whenever`);
  setInterval(() => {}, 1 << 30);   // stay alive
}

function next() {
  idx++;
  if (idx >= VARIANTS.length) {
    log('all variants shown - closing');
    resumeWatchdog();
    clearInterval(hb);
    try { ws.close(1000); } catch {}
    setTimeout(() => process.exit(0), 500);
    return;
  }
  const v = VARIANTS[idx];
  send(3, presence(v));
  log(`>>> ${v.label}  (${v.hold}s) - profile should read "${v.activity.name}"`);
  timer = setTimeout(next, v.hold * 1000);
}

// Generous enough to cover the whole cycle plus the service restart afterwards; it self-expires,
// so over-estimating costs nothing and under-estimating costs the run.
standDownWatchdog(8);
process.on('SIGINT', () => { resumeWatchdog(); process.exit(1); });

ws = new WebSocket('wss://gateway.discord.gg/?v=10&encoding=json');
ws.addEventListener('open', () => log('gateway connecting'));
ws.addEventListener('message', (ev) => {
  const p = JSON.parse(ev.data);
  switch (p.op) {
    case 10:
      hb = setInterval(() => send(1, null), p.d.heartbeat_interval);
      // GUILDS only - this probe reads nothing, it just needs a session to hold a presence on.
      send(2, { token: cfg.token, intents: 1, properties: { os: 'windows', browser: 'gf', device: 'gf' },
                presence: presence(VARIANTS[0]) });
      break;
    case 0:
      if (p.t === 'READY') {
        const only = Number(process.argv[2]);
        log(`READY as ${p.d.user.username}`);
        if (Number.isFinite(only) && only > 0) setTimeout(() => holdOne(only), 1500);
        else { log('cycling all variants - open the profile now'); setTimeout(next, 3000); }
      }
      break;
    case 9: log('INVALID SESSION - is GF-DiscordBot still running?'); process.exit(1); break;
  }
});
ws.addEventListener('close', (e) => { log(`gateway closed ${e.code}`); clearInterval(hb); clearTimeout(timer); });
