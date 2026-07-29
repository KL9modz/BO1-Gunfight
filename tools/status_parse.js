'use strict';
// The ONE Node-side parser for the Plutonium T5 `status` reply.
//
// Consumers: tools/rcon/server.js (/api/status + /api/tick — and re-exported there for its
// test suite) and tools/notify/join-notify.js. tools/status_parse.ps1 is this file's
// PowerShell TWIN — it exists only for the two box services' panel-down fallback path (their
// happy path consumes the panel's parsed JSON, so THIS copy does the parsing box-wide).
// ⚠ Change one twin, change both. The shared fixture tools/tests/fixtures/status_reply.txt is
// parsed by BOTH test suites (tools/rcon/test/server.test.js + tools/tests/status_parse.Tests.ps1),
// so a one-sided edit fails the other side's mirror case.
//
// T5 Plutonium status format:
//   map: mp_russianbase
//   num score ping guid   name            lastmsg address               qport rate
//   --- ----- ---- --------- --------------- ------- --------------------- ------ -----
//     1     0   12 2223048 KL9                   0 loopback              -20175 25000
//     2   857    0       0 LiMi7ED         1092400 unknown                   42  5000
//     3     0    0       0 MCG Gordon            0 unknown                   43  5000
//
// Column reading: END-ANCHORED, always. Player NAMES CAN CONTAIN SPACES (the bot "MCG
// Gordon" is the canonical case), so the name is not a single token — a fixed p[4]/p[6]
// split misreads a spaced name AND shifts every trailing column one right. So we index
// the fixed trailing columns from the END (address = 3rd-from-last) and take everything
// between guid and lastmsg as the name.
//
// Bot detection: a POSITIVE identification, never a fallback. Three states:
//   bot === false  — addr is a real ip:port, or a listen-server loopback  → a human
//   bot === true   — guid is 0 AND addr is a known non-routable bot marker ("unknown")
//   bot === null   — WE COULD NOT TELL. A row we can't read: a still-connecting client, a
//                    reply split across UDP packets, a column shape we don't know.
//
// That third state is the whole point, and it is load-bearing. This used to be
//     isBot = !(isLocal || isIpPort(addr))          // "not provably human ⇒ bot"
// and the panel's Kick All Bots button clientkick'd everything the flag marked — so ANY row
// the parser failed to read got a REAL PLAYER kicked. (The end-anchoring above was the right
// fix for the spaced-name bug; flipping the polarity to negative alongside it was not, and
// nobody caught it because the bug being chased ran the OTHER way, bot-counted-as-human.)
// A guess must never be able to drive a destructive action: bot===true is now a claim, and
// callers that act on it must require exactly that — never `!p.bot`, never a truthiness test.
// The kick path no longer reads this at all; it goes through the GSC bridge (botkickall),
// which resolves identity server-side with istestclient(). Keep it that way.
// Local player:  address == "loopback"

// ⚠ The port may be NEGATIVE: Plutonium prints it as a signed 16-bit value, so any client
// whose source port is >32767 shows as `ip:-NNNNN` (e.g. 52978 → :-12558). `-?` on the port
// is load-bearing — without it ~half of all real players fail this test and lose IP/notify/
// history. The IP itself is always valid; extraction is split(':')[0], so the sign is dropped.
const IP_PORT_RE  = /^\d{1,3}(\.\d{1,3}){3}:-?\d+$/;
const BOT_ADDR_RE = /^(unknown|bot|0\.0\.0\.0(:\d+)?)$/i;

function stripColors(s) { return String(s).replace(/\^[0-9a-zA-Z]/g, '').trim(); }

function parseStatusText(text) {
  const lines  = text.split('\n');
  const result = { map: '', gametype: '', listenServer: false, players: [] };

  for (const raw of lines) {
    const line = raw.trim();
    const mMap = line.match(/^map:\s*(.+)/i);
    if (mMap) { result.map = stripColors(mMap[1]); continue; }
    const mGt = line.match(/^gametype:\s*(.+)/i);
    if (mGt) { result.gametype = stripColors(mGt[1]); continue; }
  }

  const sepIdx = lines.findIndex(l => /^---/.test(l.trim()));
  if (sepIdx !== -1) {
    for (let i = sepIdx + 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;
      // Columns: num score ping guid  NAME(may contain spaces)  lastmsg address qport rate
      // Front columns (num/score/ping/guid) are a fixed count, so read them by index.
      // The name can hold spaces, so read the trailing columns from the END: address is
      // the 3rd-from-last token, and the name is everything between guid and lastmsg.
      const p = line.split(/\s+/);
      if (p.length < 8 || !/^\d+$/.test(p[0])) continue;
      const addr    = p[p.length - 3];
      const name    = stripColors(p.slice(4, p.length - 4).join(' '));
      if (!name) continue;
      const isLocal = addr === 'loopback' || addr === 'local';
      const isHuman = isLocal || IP_PORT_RE.test(addr);
      // Positive on BOTH signals, or we don't claim it. A bot is guid 0 at a non-routable
      // address; a human is a routable one. Anything else stays null (unclassifiable) and no
      // caller may act on it — see the header. Failing to classify must never kick someone.
      const isBot   = !isHuman && p[3] === '0' && BOT_ADDR_RE.test(addr);
      const bot     = isHuman ? false : (isBot ? true : null);
      if (isLocal) result.listenServer = true;
      const ip      = isHuman ? (isLocal ? 'local' : addr.split(':')[0]) : null;
      result.players.push({
        num:   parseInt(p[0], 10),
        score: /^-?\d+$/.test(p[1]) ? parseInt(p[1], 10) : null,
        ping:  /^\d+$/.test(p[2])   ? parseInt(p[2], 10) : null,   // "CNCT"/"ZMBI" → null
        guid:  p[3],
        name,
        bot,
        local: isLocal,
        addr,
        ip,
      });
    }
  }
  return result;
}

module.exports = { parseStatusText, stripColors };
