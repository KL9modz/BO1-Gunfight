// Admin console logic. External file so the site CSP can stay strict
// (script-src 'self'). Fetches the auth-gated admin.json (roster + IPs +
// connection-log tail). All values rendered via textContent, never innerHTML.
var URL = 'live/admin.json';
var lastUpdated = null;

function el(tag, cls, text){
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;   // textContent = safe vs. name/log injection
  return e;
}
function prettyGt(g){ var m={gf:'Gunfight',dm:'Team Deathmatch',dom:'Domination',sd:'Search & Destroy'}; return m[g]||(g||'').toUpperCase(); }
function ago(iso){ if(!iso) return ''; var s=Math.max(0,Math.round((Date.now()-new Date(iso).getTime())/1000)); return s<60? s+'s ago' : Math.floor(s/60)+'m ago'; }
function teamTag(t){ return t==='allies'?'allies':t==='axis'?'axis':'other'; }

function render(d){
  var dot=document.getElementById('liveDot');
  var meta=document.getElementById('metaLine');
  var content=document.getElementById('content');
  content.innerHTML=''; lastUpdated=d.updated;
  dot.className='dot'+(d.online?' on':'');

  meta.textContent = d.online
    ? ((d.mapName||d.map||'')+'  ·  '+prettyGt(d.gametype)+(d.round?'  ·  Round '+d.round:'')+
       '  ·  Allies '+((d.score&&d.score.allies)||0)+' – '+((d.score&&d.score.axis)||0)+' Axis')
    : 'Server offline';

  // Live roster with IPs
  var rc=el('div','card');
  var players=d.players||[];
  rc.appendChild(el('p','kick','Live roster  ('+players.length+' online)'));
  if(!players.length){ rc.appendChild(el('div','empty', d.online?'No players online.':'—')); }
  else{
    var tbl=el('table');
    var thead=el('tr');
    ['','Player','Team','Ping','IP address'].forEach(function(h){ thead.appendChild(el('th',null,h)); });
    tbl.appendChild(thead);
    players.forEach(function(p){
      var tr=el('tr');
      var td0=el('td'); td0.appendChild(el('span','pdot'+(p.alive?' alive':''))); tr.appendChild(td0);
      tr.appendChild(el('td','name',p.name));
      var tt=el('td'); tt.appendChild(el('span','tag '+teamTag(p.team), p.team||'—')); tr.appendChild(tt);
      tr.appendChild(el('td',null,(p.ping!=null?p.ping+' ms':'')));
      tr.appendChild(el('td','ip', p.ip||''));
      tbl.appendChild(tr);
    });
    rc.appendChild(tbl);
  }
  content.appendChild(rc);

  // Full connection log tail (with IPs + session), newest last
  var lc=el('div','card');
  var log=d.logTail||[];
  lc.appendChild(el('p','kick','Connection log  ('+log.length+' recent lines, today)'));
  if(!log.length){ lc.appendChild(el('div','empty','No log lines yet today.')); }
  else{
    var box=el('div','mono');
    log.forEach(function(line){ box.appendChild(el('div',null,line)); });
    lc.appendChild(box);
  }
  content.appendChild(lc);
}

function tick(){
  fetch(URL+'?t='+Date.now(),{cache:'no-store'})
    .then(function(r){ if(!r.ok) throw new Error(r.status); return r.json(); })
    .then(render)
    .catch(function(){
      document.getElementById('content').innerHTML=
        '<div class="card"><div class="empty">Admin snapshot unavailable. '+
        'It is only written after setup_admin_auth.ps1 has secured this folder '+
        '(the .secured marker). Check the GF-StatusService task.</div></div>';
    });
}
function updFoot(){ document.getElementById('foot').textContent=(lastUpdated?'Updated '+ago(lastUpdated)+'  ·  ':'')+'auto-refreshes every 5s'; }
tick(); setInterval(tick,5000); setInterval(updFoot,1000);
