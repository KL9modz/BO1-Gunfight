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

// ---- Connection history (multi-day, searchable) --------------------------
// Lives in its OWN container (#history), NOT #content — so the 5s roster
// re-render never wipes the search box / steals focus. Fetches the separate
// admin_history.json (IPs, same .secured-gated folder), refreshed every 60s.
var HURL = 'live/admin_history.json';
var HIST_SHOW = 300;
var histAll = [];
var histInput = null, histResults = null, histCount = null, histFoot = null;

function evClass(ev){ return ev==='CONNECT'?'connect':ev==='LEFT'?'left':'online'; }

function renderHist(){
  if (!histResults) return;
  var q = (histInput.value||'').trim().toLowerCase();
  var matches = !q ? histAll : histAll.filter(function(e){
    return (e.name||'').toLowerCase().indexOf(q)>=0
        || (e.ip||'').toLowerCase().indexOf(q)>=0
        || (e.guid||'').toLowerCase().indexOf(q)>=0;
  });
  var shown = Math.min(matches.length, HIST_SHOW);
  histCount.textContent = 'Showing '+shown+' of '+matches.length+
    (q ? ' match'+(matches.length===1?'':'es') : ' events')+
    (matches.length>HIST_SHOW ? ' (refine to see older)' : '')+
    '  ·  '+histAll.length+' on file';
  histResults.innerHTML='';
  if(!matches.length){ histResults.appendChild(el('div','empty', q?'No matches.':'No history yet.')); return; }
  var tbl=el('table');
  var thead=el('tr');
  ['When','Event','Player','IP address','GUID','Session'].forEach(function(h){ thead.appendChild(el('th',null,h)); });
  tbl.appendChild(thead);
  matches.slice(0,HIST_SHOW).forEach(function(e){
    var tr=el('tr');
    tr.appendChild(el('td',null,(e.date||'')+' '+(e.time||'')));
    var te=el('td'); te.appendChild(el('span','ev '+evClass(e.event), e.event||'')); tr.appendChild(te);
    tr.appendChild(el('td','name', e.name||''));
    tr.appendChild(el('td','ip', e.ip||''));
    tr.appendChild(el('td','gid', e.guid||''));
    tr.appendChild(el('td',null, e.session||''));
    tbl.appendChild(tr);
  });
  histResults.appendChild(tbl);
}

function fetchHist(){
  fetch(HURL+'?t='+Date.now(),{cache:'no-store'})
    .then(function(r){ if(!r.ok) throw new Error(r.status); return r.json(); })
    .then(function(d){
      histAll = (d && d.events) ? d.events : [];
      if (histFoot) histFoot.textContent = 'History '+(d&&d.updated?ago(d.updated):'')+
        '  ·  spans up to '+((d&&d.days)||'?')+' days  ·  refreshes every 60s';
      renderHist();
    })
    .catch(function(){
      if (histAll.length) return;   // keep last good data on a transient error
      if (histResults){ histResults.innerHTML=''; histResults.appendChild(
        el('div','empty','History file not available yet — it is written after the status service picks up the update.')); }
    });
}

function initHist(){
  var host=document.getElementById('history');
  if(!host) return;
  var card=el('div','card');
  card.appendChild(el('p','kick','Connection history — search name / IP / GUID across every day on file'));
  histInput=document.createElement('input');
  histInput.type='search'; histInput.className='search';
  histInput.placeholder='Search a player name, IP, or GUID…';
  histInput.setAttribute('autocomplete','off'); histInput.spellcheck=false;
  card.appendChild(histInput);
  histCount=el('div','hcount'); card.appendChild(histCount);
  histResults=el('div','htable'); card.appendChild(histResults);
  histFoot=el('div','hfoot'); card.appendChild(histFoot);
  host.appendChild(card);
  var deb=null;
  histInput.addEventListener('input',function(){ if(deb)clearTimeout(deb); deb=setTimeout(renderHist,120); });
  fetchHist(); setInterval(fetchHist,60000);
}
initHist();

// ---- Server health (ops status) ------------------------------------------
// Own container (#health) + own 5s interval, separate from the roster tick so
// neither re-render disturbs the other. Fetches live/health.json (no PII:
// round/map/counts/stuck-state), written by status_service every 5s.
var HEALTHURL = 'live/health.json';
function fmtAge(s){ if(s==null||s<0) return '—'; s=Math.round(s); return s<90? s+'s' : Math.floor(s/60)+'m'; }
function fmtUp(m){ if(m==null) return '—'; if(m<60) return m+'m'; return Math.floor(m/60)+'h '+(m%60)+'m'; }

function renderHealth(d){
  var host=document.getElementById('health');
  if(!host) return;
  host.innerHTML='';
  var card=el('div','card');

  var head=el('div','hhead');
  head.appendChild(el('p','kick','Server health'));
  var pill;
  if(!d.online){ pill=el('span','pill bad','OFFLINE'); }
  else if(d.roundStuck){ pill=el('span','pill warn live','MATCH STUCK'); }
  else if(d.lobbyHold){ pill=el('span','pill warn','PREGAME LOBBY'); }
  else{ pill=el('span','pill ok','LIVE'); }
  head.appendChild(pill);
  card.appendChild(head);

  if(d.online && d.roundStuck){
    card.appendChild(el('div','hbanner',
      'Round '+d.round+' has not advanced in '+fmtAge(d.secsSinceRoundChange)+
      '. The in-game and box watchdogs should auto-recover (map_rotate may fire).'));
  }

  var g=el('div','hstat');
  function cell(k,v){ var c=el('div','cell'); c.appendChild(el('div','k',k));
    c.appendChild(el('div','v',(v==null||v==='')?'—':String(v))); g.appendChild(c); }
  if(d.online){
    cell('Map', d.mapName||d.map||'—');
    cell('Mode', prettyGt(d.gametype));
    cell('Round', d.round!=null? d.round : '—');
    cell('Score', ((d.score&&d.score.allies)||0)+' – '+((d.score&&d.score.axis)||0));
    cell('Players', (d.humans!=null?d.humans:'?')+' + '+(d.bots!=null?d.bots:'?')+' bots');
    cell('Alive', ((d.alive&&d.alive.allies)||0)+' / '+((d.alive&&d.alive.axis)||0));
    cell('Uptime', fmtUp(d.serverUptimeMins));
    cell('Engine log', fmtAge(d.gamesLogAgeSecs)+' ago');
    cell('Round age', fmtAge(d.secsSinceRoundChange));
  } else {
    cell('Status', 'Not answering RCON');
    cell('Uptime', fmtUp(d.serverUptimeMins));
  }
  card.appendChild(g);
  host.appendChild(card);
}

function fetchHealth(){
  fetch(HEALTHURL+'?t='+Date.now(),{cache:'no-store'})
    .then(function(r){ if(!r.ok) throw new Error(r.status); return r.json(); })
    .then(renderHealth)
    .catch(function(){ /* health.json appears once status_service writes it; keep prior card */ });
}
fetchHealth(); setInterval(fetchHealth,5000);
