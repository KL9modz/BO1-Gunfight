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

  // Recent activity
  var recent = d.recent || [];
  if (recent.length){
    var fcard = el('div', 'card');
    fcard.appendChild(el('p', 'kick', 'Recent activity'));
    var ul = el('ul', 'feed');
    recent.forEach(function(r){
      var li = el('li');
      li.appendChild(el('span', 'ft', hhmm(r.t)));
      var nm = el('span', null, r.name); nm.style.color = '#e7ebf0';
      li.appendChild(nm);
      li.appendChild(el('span', r.event==='joined'?'join':'left', r.event));
      ul.appendChild(li);
    });
    fcard.appendChild(ul);
    content.appendChild(fcard);
  }
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
tick(); setInterval(tick, REFRESH_MS); setInterval(updFoot, 1000);
