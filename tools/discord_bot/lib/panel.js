'use strict';
/*
 * The game bridge, and the injection boundary that guards it.
 *
 * ⚠ ONLY through the panel's /api/rcon on loopback. The panel is the single rcon pacer on this box
 * (Plutonium answers ~1 reply per 0.7s and silently drops faster sends), and a second poller is the
 * one thing the project rule forbids. Nothing here holds an rcon socket or a schedule.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');

/*
 * ⚠ THE INJECTION BOUNDARY. The result is interpolated into `set gf_say "<here>"`, so a `"` ends
 * the value and a `;` starts a new rcon command - that pair is the whole exploit. Colour codes are
 * stripped because ^1 etc. would let anyone paint the server messages, and mentions are stripped
 * because they mean nothing in game and read as noise. Newlines would split the rcon line.
 *
 * Exported from here, not from a feature, because more than one caller needs it and a second copy
 * is how a sanitiser goes stale.
 */
function sanitiseForGame(s, max = 120) {
  return String(s || '')
    .replace(/<@!?\d+>|<@&\d+>|<#\d+>/g, '')      // mentions: meaningless in game
    .replace(/@(everyone|here)/gi, '')
    .replace(/\^\d/g, '')                          // Treyarch colour codes
    .replace(/[";\r\n]/g, ' ')                     // THE injection characters
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

module.exports = function makePanel(cfg) {
  const PANEL_PORT = cfg.panelPort || 3000;
  const RCON_HOST  = cfg.rconHost  || '127.0.0.1';
  const RCON_PORT  = cfg.rconPort  || 28960;

  // The rcon password is READ FROM dedicated.cfg, never stored in our config: one copy of a
  // credential is one place to rotate, and tools/rotate_secrets.ps1 already knows about that file.
  // Re-read per call so a rotation lands without restarting the bot.
  function rconPassword() {
    // ⚠ Resolve the T5 root from THIS FILE'S location, not from %LOCALAPPDATA%. A scheduled task
    // does not necessarily run as the profile that owns the storage tree (GF-GameServer has to pin
    // LOCALAPPDATA explicitly for exactly this reason), and the env-derived path silently produced
    // "no rcon password found" the first time this ran as a service. This file lives at
    // ...\t5\mods\mp_gunfight\tools\discord_bot\lib, so t5 is FIVE levels up - true for any account.
    const t5 = path.resolve(__dirname, '..', '..', '..', '..', '..');
    const envT5 = process.env.LOCALAPPDATA
      ? path.join(process.env.LOCALAPPDATA, 'Plutonium', 'storage', 't5') : null;
    const candidates = [cfg.dedicatedCfgPath, path.join(t5, 'dedicated.cfg'),
                        envT5 && path.join(envT5, 'dedicated.cfg')].filter(Boolean);
    const cfgFile = candidates.find((f) => { try { return fs.existsSync(f); } catch { return false; } }) || candidates[0];
    try {
      const m = fs.readFileSync(cfgFile, 'utf8').match(/^\s*set\s+rcon_password\s+"?([^"\r\n]+)"?/mi);
      return m ? m[1].trim() : '';
    } catch { return ''; }
  }

  function rcon(command, priority = true) {
    const body = JSON.stringify({ host: RCON_HOST, port: RCON_PORT, password: rconPassword(), command, priority });
    return new Promise((resolve) => {
      const req = http.request({
        host: '127.0.0.1', port: PANEL_PORT, path: '/api/rcon', method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
        timeout: 15000,
      }, (res) => {
        let data = '';
        res.on('data', (c) => data += c);
        res.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve({ ok: false, error: 'bad panel reply' }); } });
      });
      req.on('error', (e) => resolve({ ok: false, error: e.message }));
      req.on('timeout', () => { req.destroy(); resolve({ ok: false, error: 'panel timeout' }); });
      req.end(body);
    });
  }

  return { rcon, rconPassword, sanitiseForGame };
};

module.exports.sanitiseForGame = sanitiseForGame;
