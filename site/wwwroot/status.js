// Live status page logic. External file so the site CSP can stay strict
// (script-src 'self' - no 'unsafe-inline'). Fetches the public status.json
// snapshot and renders a read-only scoreboard. Player names are rendered via
// textContent only (never innerHTML), so a hostile name can't inject markup.
var URL = 'live/status.json';
var REFRESH_MS = 5000;
var lastUpdated = null;

function el(tag, cls, text){
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;   // textContent = safe against name injection
  return e;
}

// Country flag for a 2-letter code, as a SELF-HOSTED SVG (assets/flags/us.svg).
// NOT emoji: regional-indicator flag emoji don't render on Windows (Chrome/Edge/Firefox
// fall back to the bare letter pair) and that's most of the player base. Self-hosting also
// keeps the strict CSP intact — img-src is 'self', so no external flag host is allowed.
// The server sends '' when it hasn't resolved the IP yet, which renders no flag at all.
// Returns an <img>, or an equally-wide EMPTY span when the country isn't known (a fresh IP the
// box hasn't resolved yet). Never returns null: dropping the element instead would let the name
// slide left into the flag column and break alignment with every other row.
function flagImg(cc){
  cc = String(cc || '').toLowerCase();
  if (!/^[a-z]{2}$/.test(cc)) return el('span', 'flag flag-none');
  var im = document.createElement('img');
  im.className = 'flag';
  im.src = 'assets/flags/' + cc + '.svg';
  im.alt = cc.toUpperCase();
  im.title = cc.toUpperCase();
  im.loading = 'lazy';
  // Unknown/absent code -> the neutral placeholder, never a broken-image icon.
  im.onerror = function(){ this.onerror = null; this.src = 'assets/flags/xx.svg'; };
  return im;
}
function prettyGt(g){
  var m = { gf:'Gunfight', dm:'Team Deathmatch', dom:'Domination', sd:'Search & Destroy' };
  return m[g] || (g || '').toUpperCase();
}
function ago(iso){
  if(!iso) return '';
  var s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime())/1000));
  if (s < 60) return s + 's ago';
  var m = Math.floor(s/60); return m + 'm ago';
}
function hhmm(iso){
  try{ var d = new Date(iso);
    return ('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2);
  }catch(e){ return ''; }
}

function renderRoster(parent, teamKey, label, players){
  var group = players.filter(function(p){ return p.team === teamKey; });
  var box = el('div');
  var head = el('div', 'rhead ' + (teamKey==='allies'?'allies':teamKey==='axis'?'axis':'spec'));
  head.appendChild(el('span', null, label));
  head.appendChild(el('span', null, String(group.length)));
  box.appendChild(head);
  var ul = el('ul', 'plist ' + teamKey);
  if (!group.length){ ul.appendChild(el('li', 'empty', '—')); }
  group.forEach(function(p){
    var li = el('li');
    li.appendChild(el('span', 'pdot' + (p.alive?' alive':'')));
    li.appendChild(flagImg(p.cc));
    var nm = el('span', 'pname' + (p.alive?'':' pdead'), p.name);
    li.appendChild(nm);
    li.appendChild(el('span', 'ping', (p.ping!=null? p.ping+' ms':'')));
    ul.appendChild(li);
  });
  box.appendChild(ul);
  parent.appendChild(box);
}

function render(d){
  var dot = document.getElementById('liveDot');
  var txt = document.getElementById('liveTxt');
  var meta = document.getElementById('metaLine');
  var content = document.getElementById('content');
  content.innerHTML = '';
  lastUpdated = d.updated;

  if (!d.online){
    dot.className = 'dot off'; txt.textContent = 'Offline';
    meta.textContent = '';
    var off = el('div', 'offline');
    off.appendChild(el('div', 'big', 'Server offline'));
    off.appendChild(el('div', null, 'The Gunfight server is not responding right now.'));
    content.appendChild(off);
    return;
  }

  dot.className = 'dot on'; txt.textContent = 'Online';
  meta.textContent = (d.mapName || d.map || '') + '  ·  ' + prettyGt(d.gametype) +
                     (d.round ? '  ·  Round ' + d.round : '');

  // Scoreboard
  var scard = el('div', 'card');
  scard.appendChild(el('p', 'kick', 'Match score'));
  var score = el('div', 'score');
  var a = el('div', 'team allies');
  a.appendChild(el('div', 'name', 'Allies'));
  a.appendChild(el('div', 'wins', String((d.score&&d.score.allies)||0)));
  a.appendChild(el('div', 'alive', ((d.alive&&d.alive.allies)||0) + ' alive'));
  var vs = el('div', 'vs', 'vs');
  var x = el('div', 'team axis');
  x.appendChild(el('div', 'name', 'Axis'));
  x.appendChild(el('div', 'wins', String((d.score&&d.score.axis)||0)));
  x.appendChild(el('div', 'alive', ((d.alive&&d.alive.axis)||0) + ' alive'));
  score.appendChild(a); score.appendChild(vs); score.appendChild(x);
  scard.appendChild(score);
  content.appendChild(scard);

  // Rosters
  var players = d.players || [];
  var rcard = el('div', 'card');
  rcard.appendChild(el('p', 'kick', 'Players  (' + (d.humans||players.length) +
    (d.bots ? ' + ' + d.bots + ' bots' : '') + ')'));
  if (!players.length){
    rcard.appendChild(el('div', 'empty', 'No players online right now.'));
  } else {
    var grid = el('div', 'rosters');
    renderRoster(grid, 'allies', 'Allies', players);
    renderRoster(grid, 'axis', 'Axis', players);
    rcard.appendChild(grid);
    var specs = players.filter(function(p){ return p.team!=='allies' && p.team!=='axis'; });
    if (specs.length){
      var sg = el('div'); sg.style.marginTop = '12px';
      renderRoster(sg, 'spectator', 'Spectators', players);
      rcard.appendChild(sg);
    }
  }
  content.appendChild(rcard);

  // Recent activity moved OUT of #content into its own #activity container (below): #content is
  // wiped and rebuilt every 5s, which would clear the feed's search box and steal focus mid-type.
  // The live in-memory ring stays as the fallback for when the durable feed has no data.
  liveRecent = d.recent || [];
  if (!actAll.length) renderActivity();
}

// ---- Activity feed (persistent, multi-day, searchable) ---------------------
// Reads live/activity.json — the box rebuilds it every ~60s from the connect-log day-files,
// so it survives a service restart and spans days (the `recent` ring in status.json is only
// the last handful of events since the status service last started).
//
// PRIVACY: this file carries name / time / event / session / country code. The IP the country
// was derived from is dropped on the box and never served here — that lives in the auth-gated
// admin history.
var AURL = 'live/activity.json';
var ACT_REFRESH_MS = 60000;   // matches the box's rebuild cadence; no point polling faster
var ACT_PAGE = 40;            // rows shown before "show more"

var actAll = [];        // every event in the file, newest first
var actDays = 7;        // window the box built the file over (shown in the footer)
var actShown = ACT_PAGE;
var actBuilt = false;
var actInput = null, actList = null, actCount = null;
var liveRecent = [];    // fallback: the in-memory ring out of status.json

function actMatches(){
  var q = (actInput && actInput.value || '').trim().toLowerCase();
  if (!q) return actAll;
  return actAll.filter(function(e){
    return String(e.name||'').toLowerCase().indexOf(q) !== -1 ||
           String(e.cc||'').toLowerCase().indexOf(q) !== -1;
  });
}

var MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

// "2026-07-11" -> "Today" / "Yesterday" / "Jul 11". Days are grouped under a divider rather than
// prefixing the date onto the first row of each day: a wider first cell would push that row's
// name out of line with every other row's.
function dayLabel(d){
  var s = String(d || '');
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return s;
  var now = new Date();
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  var that  = new Date(+m[1], +m[2] - 1, +m[3]);
  var days  = Math.round((today - that) / 86400000);
  if (days === 0) return 'Today';
  if (days === 1) return 'Yesterday';
  return MONTHS[+m[2] - 1] + ' ' + m[3];
}

// One event row: [time] [flag] name  joined/left  (session)
function actRow(e){
  var li = el('li');
  li.appendChild(el('span', 'ft', String(e.time || '').slice(0, 5)));
  li.appendChild(flagImg(e.cc));
  li.appendChild(el('span', 'fname', e.name));
  // ONLINE = "already on when the logger started" — read it as a join, not a third state.
  var left = (e.event === 'LEFT');
  li.appendChild(el('span', left ? 'left' : 'join', left ? 'left' : 'joined'));
  if (e.session) li.appendChild(el('span', 'sess', e.session));
  return li;
}

function renderActivity(){
  var host = document.getElementById('activity');
  if (!host) return;

  // No durable feed (conn_logger not running / no day-files yet): fall back to the live ring.
  if (!actAll.length){
    host.innerHTML = '';
    actBuilt = false;
    if (!liveRecent.length) return;
    var fcard = el('div', 'card');
    fcard.appendChild(el('p', 'kick', 'Recent activity'));
    var ful = el('ul', 'feed');
    liveRecent.forEach(function(r){
      var li = el('li');
      li.appendChild(el('span', 'ft', hhmm(r.t)));
      li.appendChild(flagImg(r.cc));
      li.appendChild(el('span', 'fname', r.name));
      li.appendChild(el('span', r.event==='joined'?'join':'left', r.event));
      ful.appendChild(li);
    });
    fcard.appendChild(ful);
    host.appendChild(fcard);
    return;
  }

  // Build the card ONCE, so re-rendering results never recreates (and unfocuses) the search box.
  if (!actBuilt){
    host.innerHTML = '';
    var card = el('div', 'card');
    card.appendChild(el('p', 'kick', 'Recent activity'));
    actInput = document.createElement('input');
    actInput.type = 'search';
    actInput.className = 'search';
    actInput.placeholder = 'Search a player or country…';
    actInput.addEventListener('input', function(){ actShown = ACT_PAGE; renderActivity(); });
    card.appendChild(actInput);
    actList  = el('ul', 'feed');
    card.appendChild(actList);
    actCount = el('div', 'fcount');
    card.appendChild(actCount);
    host.appendChild(card);
    actBuilt = true;
  }

  var m = actMatches();
  actList.innerHTML = '';
  if (!m.length){
    actList.appendChild(el('li', 'empty', 'No matches.'));
  } else {
    var lastDate = null;
    m.slice(0, actShown).forEach(function(e){
      if (e.date !== lastDate){
        lastDate = e.date;
        actList.appendChild(el('li', 'day', dayLabel(e.date)));
      }
      actList.appendChild(actRow(e));
    });
  }

  actCount.innerHTML = '';
  var shown = Math.min(actShown, m.length);
  actCount.appendChild(el('span', null,
    'Showing ' + shown + ' of ' + m.length + (actAll.length !== m.length ? ' matching' : '') +
    '  ·  last ' + (actDays || 7) + ' days'));
  if (shown < m.length){
    var more = el('button', 'more', 'Show more');
    more.addEventListener('click', function(){ actShown += ACT_PAGE * 2; renderActivity(); });
    actCount.appendChild(more);
  }
}

function actTick(){
  fetch(AURL + '?t=' + Date.now(), { cache:'no-store' })
    .then(function(r){ if(!r.ok) throw new Error(r.status); return r.json(); })
    .then(function(d){
      // Array.isArray, not a truthiness check: PowerShell's ConvertTo-Json can emit a lone event
      // as a bare object rather than a 1-element array, and .filter/.slice on that would throw and
      // kill the feed. Anything unexpected degrades to the live fallback instead.
      actAll  = (d && Array.isArray(d.events)) ? d.events : [];
      actDays = (d && d.days) ? d.days : 7;
      renderActivity();
    })
    .catch(function(){
      // No activity.json (older box, or the service hasn't written one yet) -> keep whatever we
      // have; renderActivity falls back to the live ring on its own.
      if (!actAll.length) renderActivity();
    });
}

function tick(){
  fetch(URL + '?t=' + Date.now(), { cache:'no-store' })
    .then(function(r){ if(!r.ok) throw new Error(r.status); return r.json(); })
    .then(render)
    .catch(function(){
      var dot = document.getElementById('liveDot');
      var txt = document.getElementById('liveTxt');
      dot.className = 'dot off'; txt.textContent = 'No data';
      document.getElementById('content').innerHTML =
        '<div class="offline"><div class="big">Status unavailable</div>' +
        '<div>Live status isn\'t being published yet.</div></div>';
    });
}
function updFoot(){
  document.getElementById('foot').textContent =
    (lastUpdated ? 'Updated ' + ago(lastUpdated) + '  ·  ' : '') + 'auto-refreshes every 5s';
}
tick();    setInterval(tick,    REFRESH_MS);
actTick(); setInterval(actTick, ACT_REFRESH_MS);
setInterval(updFoot, 1000);
