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
  if(!players.length){ rc.appendChild(el('div','empty', d.online?'No players online.':'Server offline.')); }
  else{
    var tbl=el('table');
    var thead=el('tr');
    ['','Player','Team','Ping','IP address'].forEach(function(h){ thead.appendChild(el('th',null,h)); });
    tbl.appendChild(thead);
    players.forEach(function(p){
      var tr=el('tr');
      var td0=el('td'); td0.appendChild(el('span','pdot'+(p.alive?' alive':''))); tr.appendChild(td0);
      tr.appendChild(el('td','name',p.name));
      var tt=el('td'); tt.appendChild(el('span','tag '+teamTag(p.team), p.team||'n/a')); tr.appendChild(tt);
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
      renderStats();
    })
    .catch(function(){
      if (histAll.length) return;   // keep last good data on a transient error
      if (histResults){ histResults.innerHTML=''; histResults.appendChild(
        el('div','empty','History file not available yet: it is written after the status service picks up the update.')); }
    });
}

function initHist(){
  var host=document.getElementById('history');
  if(!host) return;
  var card=el('div','card');
  card.appendChild(el('p','kick','Connection history: search name / IP / GUID across every day on file'));
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

// ---- All-time stats (aggregated over the history events) ------------------
// Pure client-side summary of the SAME histAll array the history search uses
// (each event carries guid, session, cc), so it costs no extra fetch and no
// server change. Re-rendered from fetchHist() whenever the 60s history refresh
// lands. Scope = whatever admin_history.json holds (up to 60 days / 5000 events).
var STATS_TOP = 10;
var STATS_TOP_REGIONS = 12;   // the region list is unbounded; the country list is not

// Flag SVG, self-hosted like the public page. Admin lives at /admin/, so the
// assets/ dir is one level up. Unknown/absent -> the neutral xx placeholder.
function statFlag(cc){
  cc = String(cc||'').toLowerCase();
  if(!/^[a-z]{2}$/.test(cc)) return el('span','flag-none');
  var im = document.createElement('img');
  im.className='flag'; im.src='../assets/flags/'+cc+'.svg';
  im.alt=cc.toUpperCase(); im.title=cc.toUpperCase(); im.loading='lazy';
  im.onerror=function(){ this.onerror=null; this.src='../assets/flags/xx.svg'; };
  return im;
}
// Player identity: GUID when real, else the bare IP (bots/still-connecting rows
// never reach admin_history — Build-ConnHistory drops guid 0 / no ip:port).
function statKey(e){ var g=(e.guid||'').trim(); return (g && g!=='0') ? 'g:'+g : 'i:'+String(e.ip||'').split(':')[0]; }
// 2-letter code -> full English country name via the browser's built-in
// Intl.DisplayNames (no lookup table needed). Falls back to the upper-case code
// if the API is missing or the code is unknown.
var _regionNames = null;
try { _regionNames = new Intl.DisplayNames(['en'], { type:'region' }); } catch(e){ _regionNames = null; }
function countryName(cc){
  cc = String(cc||'').toUpperCase();
  if(!/^[A-Z]{2}$/.test(cc)) return cc || 'n/a';
  if(_regionNames){ try { var n=_regionNames.of(cc); if(n && n!==cc) return n; } catch(e){} }
  return cc;
}
// Session string is "<minutes>m<ss>s" (minutes can exceed 59; no hours field).
function parseSession(s){ var m=/(\d+)m(\d+)s/.exec(String(s||'')); return m ? (+m[1])*60 + (+m[2]) : 0; }
function fmtDur(s){ s=Math.round(s||0); var h=Math.floor(s/3600), m=Math.floor((s%3600)/60);
  if(h) return h+'h '+(m<10?'0':'')+m+'m'; if(m) return m+'m'; return s+'s'; }

function computeStats(events){
  var P={}, totSec=0, totLeft=0, connects=0, days={};
  // events are NEWEST-FIRST, so the first sighting of a key is its most recent
  // name; take the most recent non-empty country the same way.
  for(var i=0;i<events.length;i++){
    var e=events[i], k=statKey(e), p=P[k];
    if(!p){ p=P[k]={ name:e.name||'?', cc:'', region:'', sec:0, sessions:0, conns:0 }; }
    if(!p.cc && e.cc) p.cc=e.cc;
    // Region is stamped only on admin_history (never the public feed), and only for IPs the
    // panel's geo cache has already resolved, so it can be absent on an otherwise good row.
    if(!p.region && e.region) p.region=e.region;
    if(e.date) days[e.date]=1;
    if(e.event==='CONNECT'){ connects++; p.conns++; }
    if(e.event==='LEFT'){ var s=parseSession(e.session); if(s>0){ p.sec+=s; p.sessions++; totSec+=s; totLeft++; } }
  }
  var arr=[], key; for(key in P){ if(P.hasOwnProperty(key)) arr.push(P[key]); }
  var byCC={}; arr.forEach(function(p){ if(p.cc) byCC[p.cc]=(byCC[p.cc]||0)+1; });
  var cc=[], c; for(c in byCC){ if(byCC.hasOwnProperty(c)) cc.push({cc:c,n:byCC[c]}); }
  cc.sort(function(a,b){ return b.n-a.n; });
  // Same unique-player counting as the country roll-up, one level finer. Keyed on cc+region so
  // two same-named regions in different countries never merge, and players whose IP has no
  // region resolved are counted separately rather than bucketed into a fake "unknown" row.
  var byRG={}, noRG=0;
  arr.forEach(function(p){
    if(!p.region){ noRG++; return; }
    var rk=(p.cc||'')+'|'+p.region;
    if(!byRG[rk]) byRG[rk]={ cc:p.cc||'', region:p.region, n:0 };
    byRG[rk].n++;
  });
  var rg=[], r; for(r in byRG){ if(byRG.hasOwnProperty(r)) rg.push(byRG[r]); }
  rg.sort(function(a,b){ return b.n-a.n || a.region.localeCompare(b.region); });
  var top=arr.filter(function(p){ return p.sec>0; })
             .sort(function(a,b){ return b.sec-a.sec; }).slice(0,STATS_TOP);
  var topConn=arr.filter(function(p){ return p.conns>0; })
             .sort(function(a,b){ return b.conns-a.conns; }).slice(0,STATS_TOP);
  return { unique:arr.length, connects:connects, totSec:totSec, totLeft:totLeft,
           days:Object.keys(days).length, countries:cc, regions:rg, noRegion:noRG,
           top:top, topConn:topConn };
}

function renderStats(){
  var host=document.getElementById('stats'); if(!host) return;
  host.innerHTML='';
  if(!histAll.length) return;   // nothing to summarise yet
  var s=computeStats(histAll);

  // Summary tiles
  var c1=el('div','card');
  c1.appendChild(el('p','kick','All-time stats  ·  from '+s.days+' day'+(s.days===1?'':'s')+' on file'));
  var g=el('div','hstat');
  function cell(k,v){ var c=el('div','cell'); c.appendChild(el('div','k',k));
    c.appendChild(el('div','v',String(v))); g.appendChild(c); }
  cell('Unique players', s.unique);
  cell('Countries', s.countries.length);
  cell('States / provinces', s.regions.length);
  cell('Total sessions', s.totLeft);
  cell('Total playtime', fmtDur(s.totSec));
  cell('Avg session', s.totLeft ? fmtDur(s.totSec/s.totLeft) : 'n/a');
  cell('Connects', s.connects);
  c1.appendChild(g);
  host.appendChild(c1);

  // Most playtime leaderboard
  var c2=el('div','card');
  c2.appendChild(el('p','kick','Most playtime  (top '+STATS_TOP+')'));
  if(!s.top.length){ c2.appendChild(el('div','empty','No completed sessions yet.')); }
  else{
    var tbl=el('table'), th=el('tr');
    ['#','Player','Playtime','Sessions'].forEach(function(h){ th.appendChild(el('th',null,h)); });
    tbl.appendChild(th);
    s.top.forEach(function(p,idx){
      var tr=el('tr');
      tr.appendChild(el('td','rank', String(idx+1)));
      var nt=el('td','name'); nt.appendChild(statFlag(p.cc)); nt.appendChild(document.createTextNode(p.name||'?')); tr.appendChild(nt);
      tr.appendChild(el('td','dur', fmtDur(p.sec)));
      tr.appendChild(el('td',null, String(p.sessions)));
      tbl.appendChild(tr);
    });
    c2.appendChild(tbl);
  }
  c2.appendChild(el('div','stnote','Playtime counts completed sessions only; anyone online right now is added when they leave.'));
  host.appendChild(c2);

  // Most connections leaderboard
  var c4=el('div','card');
  c4.appendChild(el('p','kick','Most connections  (top '+STATS_TOP+')'));
  if(!s.topConn.length){ c4.appendChild(el('div','empty','No connections recorded yet.')); }
  else{
    var tblc=el('table'), thc=el('tr');
    ['#','Player','Connects','Playtime'].forEach(function(h){ thc.appendChild(el('th',null,h)); });
    tblc.appendChild(thc);
    s.topConn.forEach(function(p,idx){
      var tr=el('tr');
      tr.appendChild(el('td','rank', String(idx+1)));
      var nt=el('td','name'); nt.appendChild(statFlag(p.cc)); nt.appendChild(document.createTextNode(p.name||'?')); tr.appendChild(nt);
      tr.appendChild(el('td',null, String(p.conns)));
      tr.appendChild(el('td','dur', p.sec ? fmtDur(p.sec) : 'n/a'));
      tblc.appendChild(tr);
    });
    c4.appendChild(tblc);
  }
  host.appendChild(c4);

  // Players by country
  var c3=el('div','card');
  c3.appendChild(el('p','kick','Players by country  ('+s.countries.length+')'));
  if(!s.countries.length){ c3.appendChild(el('div','empty','No countries resolved yet.')); }
  else{
    var max=s.countries[0].n || 1, list=el('div','clist');
    s.countries.forEach(function(o){
      var row=el('div','crow');
      row.appendChild(statFlag(o.cc));
      var nm=el('span','cname', countryName(o.cc)); nm.title=o.cc.toUpperCase(); row.appendChild(nm);
      var bar=el('div','cbar'), fill=el('i'); fill.style.width=Math.round(o.n/max*100)+'%'; bar.appendChild(fill); row.appendChild(bar);
      row.appendChild(el('span','cn', String(o.n)));
      list.appendChild(row);
    });
    c3.appendChild(list);
  }
  host.appendChild(c3);

  // Players by state / province (ip-api's regionName, one level below the country roll-up)
  var c5=el('div','card');
  c5.appendChild(el('p','kick','Players by state / province  ('+s.regions.length+')'));
  if(!s.regions.length){
    c5.appendChild(el('div','empty', s.noRegion
      ? 'No regions resolved yet: the panel geo cache has country codes but no region for these players.'
      : 'No regions resolved yet.'));
  }
  else{
    var shown=s.regions.slice(0,STATS_TOP_REGIONS);
    var rmax=shown[0].n || 1, rlist=el('div','clist');
    shown.forEach(function(o){
      var row=el('div','crow rrow');
      row.appendChild(statFlag(o.cc));
      var nm=el('span','cname', o.region); nm.title=o.region; row.appendChild(nm);
      row.appendChild(el('span','csub', countryName(o.cc)));
      var bar=el('div','cbar'), fill=el('i'); fill.style.width=Math.round(o.n/rmax*100)+'%';
      bar.appendChild(fill); row.appendChild(bar);
      row.appendChild(el('span','cn', String(o.n)));
      rlist.appendChild(row);
    });
    c5.appendChild(rlist);
  }
  var rnote='State in the US, province in Canada, closest equivalent elsewhere.';
  if(s.regions.length>STATS_TOP_REGIONS) rnote+=' Showing the top '+STATS_TOP_REGIONS+' of '+s.regions.length+'.';
  if(s.noRegion) rnote+=' '+s.noRegion+' player'+(s.noRegion===1?'':'s')+' had no region resolved.';
  c5.appendChild(el('div','stnote', rnote));
  host.appendChild(c5);
}

// ---- Server health (ops status) ------------------------------------------
// Own container (#health) + own 5s interval, separate from the roster tick so
// neither re-render disturbs the other. Fetches live/health.json (no PII:
// round/map/counts/stuck-state), written by status_service every 5s.
var HEALTHURL = 'live/health.json';
function fmtAge(s){ if(s==null||s<0) return 'n/a'; s=Math.round(s); return s<90? s+'s' : Math.floor(s/60)+'m'; }
function fmtUp(m){ if(m==null) return 'n/a'; if(m<60) return m+'m'; return Math.floor(m/60)+'h '+(m%60)+'m'; }

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
    c.appendChild(el('div','v',(v==null||v==='')?'n/a':String(v))); g.appendChild(c); }
  if(d.online){
    cell('Map', d.mapName||d.map||'n/a');
    cell('Mode', prettyGt(d.gametype));
    cell('Round', d.round!=null? d.round : 'n/a');
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
