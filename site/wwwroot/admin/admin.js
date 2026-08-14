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
      histUpdated = (d && d.updated) ? d.updated : null;
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
var STATS_ROWS = 25;          // leaderboard rows shown
var STATS_TOP_REGIONS = 12;   // the region list is unbounded; the country list is not
var STATS_DAYS = 14;          // per-day activity rows
var STATS_EVENTS = 40;        // events listed in a player drill-down

// Window / sort / selection are MODULE state, not DOM state, so the 60s history
// refresh re-renders into whatever the admin last chose instead of snapping back.
var WINDOWS  = [ { k:'24h', h:24 }, { k:'7d', h:168 }, { k:'30d', h:720 }, { k:'All', h:0 } ];
var statWinH = 0;             // active window in hours; 0 = everything on file
var statSort = 'sec';         // sec | sessions | avg | conns | last | name
var statDir  = -1;            // -1 = descending
var statPick = null;          // statKey() of the drilled-down player, or null
var statsBody = null, segBtns = [];

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

// ---- Clocks: the box stamps local time, the viewer asks in theirs ----------
// A day-file line carries the BOX's local wall clock with no zone ("2026-08-13
// 21:14:05"), so comparing it against the viewer's Date.now() is off by the
// difference between the two machines: a US admin on a UTC box would see a "24h"
// window that is really 17h or 31h. admin_history.json's `updated` is ISO-with-
// offset written by that SAME clock, so its offset is exactly the missing piece:
// stamp it onto an event string and Date.parse yields a true instant, wherever
// the admin is sitting. With no `updated` yet we fall back to offset-less
// parsing, which ES5.1+ reads as viewer-local: right whenever the two agree, and
// the only honest guess when the box has not said otherwise.
var histUpdated = null;
function boxOffset(){
  var m = /(Z|[+-]\d{2}:\d{2})$/.exec(String(histUpdated||''));
  return m ? m[1] : '';
}
// Memoised per event object. Events are rebuilt wholesale by each fetch, so the
// stamp can never outlive the offset it was computed under.
function evTime(e){
  if(e._t === undefined){
    e._t = (e.date && e.time) ? Date.parse(e.date+'T'+e.time+boxOffset()) : NaN;
  }
  return e._t;
}
// "Now" is the box's, not the viewer's, for the same reason.
function statNow(){ var t=Date.parse(String(histUpdated||'')); return isNaN(t)? Date.now() : t; }
function agoLong(t){
  if(t==null || isNaN(t)) return 'n/a';
  var s=Math.max(0,Math.round((statNow()-t)/1000));
  if(s<60) return s+'s ago';
  if(s<3600) return Math.floor(s/60)+'m ago';
  if(s<86400) return Math.floor(s/3600)+'h ago';
  return Math.floor(s/86400)+'d ago';
}
function winLabel(){
  for(var i=0;i<WINDOWS.length;i++){ if(WINDOWS[i].h===statWinH) return WINDOWS[i].k; }
  return 'All';
}
// A row whose time will not parse is EXCLUDED from a bounded window: a window is
// a claim about time, and an unstampable row cannot support it. (The day-file
// regex fixes both fields, so this is a guard, not a live path.)
function windowEvents(){
  if(!statWinH) return histAll;
  var cut=statNow()-statWinH*3600000, out=[], i, t;
  for(i=0;i<histAll.length;i++){ t=evTime(histAll[i]); if(!isNaN(t) && t>=cut) out.push(histAll[i]); }
  return out;
}
function playerEvents(events, key){
  var out=[], i;
  for(i=0;i<events.length;i++){ if(statKey(events[i])===key) out.push(events[i]); }
  return out;
}
function keyList(o){ var a=[], k; for(k in o){ if(o.hasOwnProperty(k)) a.push(k); } return a; }
function pad2(n){ return (n<10?'0':'')+n; }

function computeStats(events){
  var P={}, totSec=0, totLeft=0, connects=0, days={}, hours=[], longest=null, i;
  for(i=0;i<24;i++) hours.push(0);
  // events are NEWEST-FIRST, so the first sighting of a key is its most recent
  // name; take the most recent non-empty country the same way.
  for(i=0;i<events.length;i++){
    var e=events[i], k=statKey(e), p=P[k], t=evTime(e);
    if(!p){ p=P[k]={ key:k, name:e.name||'?', cc:'', region:'', sec:0, sessions:0, conns:0,
                     longest:0, first:null, last:null, names:{}, ips:{}, guids:{} }; }
    if(!p.cc && e.cc) p.cc=e.cc;
    // Region is stamped only on admin_history (never the public feed), and only for IPs the
    // panel's geo cache has already resolved, so it can be absent on an otherwise good row.
    if(!p.region && e.region) p.region=e.region;
    // Identity spread: every name/IP/GUID this key was ever seen under. statKey folds on
    // GUID, so a rename shows up here as a second alias rather than a second player.
    if(e.name) p.names[e.name]=1;
    var bare=String(e.ip||'').split(':')[0]; if(bare) p.ips[bare]=1;
    if(e.guid && e.guid!=='0') p.guids[e.guid]=1;
    if(!isNaN(t)){ if(p.first===null||t<p.first) p.first=t; if(p.last===null||t>p.last) p.last=t; }
    if(e.date && !days[e.date]) days[e.date]={ connects:0, sec:0 };
    if(e.event==='CONNECT'){
      connects++; p.conns++;
      if(e.date) days[e.date].connects++;
      // Hour comes off the raw stamp, so the histogram is in SERVER local time and
      // needs no offset maths: it answers "when is the box busy", not "when is it
      // busy where I happen to be reading this".
      var hh=parseInt(String(e.time||'').slice(0,2),10);
      if(hh>=0 && hh<24) hours[hh]++;
    }
    if(e.event==='LEFT'){
      var s=parseSession(e.session);
      if(s>0){
        p.sec+=s; p.sessions++; totSec+=s; totLeft++;
        if(s>p.longest) p.longest=s;
        if(e.date) days[e.date].sec+=s;
        if(!longest || s>longest.sec) longest={ sec:s, name:e.name||'?', date:e.date||'' };
      }
    }
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
  // Per-day rollup, newest day first (ISO dates sort lexically).
  var dayList=[], dk;
  for(dk in days){ if(days.hasOwnProperty(dk)) dayList.push({ date:dk, connects:days[dk].connects, sec:days[dk].sec }); }
  dayList.sort(function(a,b){ return a.date<b.date?1:(a.date>b.date?-1:0); });
  var peakDay=null;
  dayList.forEach(function(d){ if(!peakDay || d.sec>peakDay.sec) peakDay=d; });
  var peakHour=0, anyHour=0;
  for(i=0;i<24;i++){ anyHour+=hours[i]; if(hours[i]>hours[peakHour]) peakHour=i; }
  return { unique:arr.length, connects:connects, totSec:totSec, totLeft:totLeft,
           days:dayList.length, countries:cc, regions:rg, noRegion:noRG,
           players:arr, hours:hours, peakHour:peakHour, anyHour:anyHour,
           dayList:dayList, peakDay:peakDay, longest:longest };
}

// Leaderboard ordering. Every column is numeric except Player, and each falls
// back to the name so equal values keep a stable, readable order.
function sortPlayers(arr){
  var val = { sec:      function(p){ return p.sec; },
              sessions: function(p){ return p.sessions; },
              avg:      function(p){ return p.sessions ? p.sec/p.sessions : 0; },
              conns:    function(p){ return p.conns; },
              last:     function(p){ return p.last || 0; } }[statSort];
  var out=arr.slice();
  if(!val){
    out.sort(function(a,b){
      return statDir * String(a.name||'').toLowerCase().localeCompare(String(b.name||'').toLowerCase());
    });
    return out;
  }
  out.sort(function(a,b){
    return statDir*(val(a)-val(b)) || String(a.name||'').localeCompare(String(b.name||''));
  });
  return out;
}

// The window buttons live in a bar that is built ONCE and never re-rendered, so
// the 60s history refresh cannot steal a click mid-press or drop focus. Only the
// body below it is rebuilt. Same reason the history search box has its own
// container: a periodic re-render must never own an interactive control.
function statsChrome(host){
  if(statsBody) return;
  var bar=el('div','sbar');
  bar.appendChild(el('span','skick','Player stats'));
  var seg=el('div','seg');
  WINDOWS.forEach(function(w){
    var b=document.createElement('button');
    b.type='button'; b.textContent=w.k;
    b.addEventListener('click', function(){
      if(statWinH===w.h) return;
      statWinH=w.h; statPick=null; segPaint(); renderStats();
    });
    seg.appendChild(b); segBtns.push({ b:b, h:w.h });
  });
  bar.appendChild(seg);
  host.appendChild(bar);
  statsBody=el('div'); host.appendChild(statsBody);
  segPaint();
}
function segPaint(){
  segBtns.forEach(function(o){ o.b.className = (o.h===statWinH) ? 'on' : ''; });
}

// A sortable header: clicking re-sorts, clicking the active column flips it.
function sortTh(label, key, cls){
  var th=el('th', 'srt'+(cls?' '+cls:''));
  th.appendChild(document.createTextNode(label));
  if(statSort===key) th.appendChild(el('span','arw', statDir<0?'▾':'▴'));
  th.addEventListener('click', function(){
    if(statSort===key){ statDir=-statDir; }
    else { statSort=key; statDir = (key==='name') ? 1 : -1; }
    renderStats();
  });
  return th;
}

function renderStats(){
  var host=document.getElementById('stats'); if(!host) return;
  if(!histAll.length) return;   // nothing to summarise yet
  statsChrome(host);
  statsBody.innerHTML='';
  var events=windowEvents();
  var s=computeStats(events);

  // ---- Summary tiles ----
  var c1=el('div','card');
  c1.appendChild(el('p','kick', (statWinH? 'Last '+winLabel() : 'All time')+
    '  ·  '+s.days+' day'+(s.days===1?'':'s')+' with activity  ·  '+events.length+' events'));
  var g=el('div','hstat');
  function cell(k,v){ var c=el('div','cell'); c.appendChild(el('div','k',k));
    c.appendChild(el('div','v',String(v))); g.appendChild(c); }
  cell('Unique players', s.unique);
  cell('Connects', s.connects);
  cell('Total sessions', s.totLeft);
  cell('Total playtime', fmtDur(s.totSec));
  cell('Avg session', s.totLeft ? fmtDur(s.totSec/s.totLeft) : 'n/a');
  cell('Longest session', s.longest ? fmtDur(s.longest.sec) : 'n/a');
  cell('Busiest day', s.peakDay ? s.peakDay.date : 'n/a');
  cell('Busiest hour', s.anyHour ? (pad2(s.peakHour)+':00') : 'n/a');
  cell('Countries', s.countries.length);
  cell('States / provinces', s.regions.length);
  c1.appendChild(g);
  if(s.longest){
    c1.appendChild(el('div','stnote','Longest session: '+s.longest.name+', '+
      fmtDur(s.longest.sec)+' on '+s.longest.date+'.'));
  }
  statsBody.appendChild(c1);

  // ---- Player leaderboard (sortable, click a row to drill in) ----
  var c2=el('div','card');
  var ranked=sortPlayers(s.players);
  c2.appendChild(el('p','kick','Player leaderboard  ·  '+ranked.length+
    ' player'+(ranked.length===1?'':'s')+' in this window'));
  if(!ranked.length){ c2.appendChild(el('div','empty','No players in this window.')); }
  else{
    var tbl=el('table','lb'), th=el('tr');
    th.appendChild(el('th','rank','#'));
    th.appendChild(sortTh('Player','name'));
    th.appendChild(sortTh('Playtime','sec'));
    th.appendChild(sortTh('Sessions','sessions'));
    th.appendChild(sortTh('Avg','avg'));
    th.appendChild(sortTh('Connects','conns'));
    th.appendChild(sortTh('Last seen','last'));
    tbl.appendChild(th);
    ranked.slice(0,STATS_ROWS).forEach(function(p,idx){
      var tr=el('tr','rowlink'+(statPick===p.key?' picked':''));
      tr.appendChild(el('td','rank', String(idx+1)));
      var nt=el('td','name');
      nt.appendChild(statFlag(p.cc));
      nt.appendChild(document.createTextNode(p.name||'?'));
      if(keyList(p.names).length>1) nt.appendChild(el('span','alias','+'+(keyList(p.names).length-1)));
      tr.appendChild(nt);
      tr.appendChild(el('td','dur', p.sec? fmtDur(p.sec) : 'n/a'));
      tr.appendChild(el('td',null, String(p.sessions)));
      tr.appendChild(el('td','dur', p.sessions? fmtDur(p.sec/p.sessions) : 'n/a'));
      tr.appendChild(el('td',null, String(p.conns)));
      tr.appendChild(el('td','dur', agoLong(p.last)));
      tr.addEventListener('click', function(){
        statPick = (statPick===p.key) ? null : p.key;
        renderStats();
      });
      tbl.appendChild(tr);
    });
    c2.appendChild(tbl);
  }
  var lnote='Click a column to sort, click a row to open that player. Playtime counts '+
            'completed sessions only, so anyone online right now is added when they leave.';
  if(ranked.length>STATS_ROWS) lnote+=' Showing the top '+STATS_ROWS+' of '+ranked.length+'.';
  if(statWinH) lnote+=' A session counts toward the window it ENDED in.';
  c2.appendChild(el('div','stnote', lnote));
  statsBody.appendChild(c2);

  // ---- Drill-down for the picked player ----
  if(statPick){
    var pick=null;
    ranked.forEach(function(p){ if(p.key===statPick) pick=p; });
    if(pick) statsBody.appendChild(playerCard(pick, events));
    else statPick=null;   // they fell out of the window; drop the selection
  }

  // ---- Connects by hour of day ----
  var c6=el('div','card');
  c6.appendChild(el('p','kick','Connects by hour  ·  server local time'));
  if(!s.anyHour){ c6.appendChild(el('div','empty','No connects in this window.')); }
  else{
    var hmax=1, hi;
    for(hi=0;hi<24;hi++){ if(s.hours[hi]>hmax) hmax=s.hours[hi]; }
    var hrow=el('div','hours'), hlab=el('div','hlab');
    for(hi=0;hi<24;hi++){
      var col=el('div','hb'+(hi===s.peakHour?' pk':''));
      var bar=document.createElement('i');
      bar.style.height=Math.max(2, Math.round(s.hours[hi]/hmax*100))+'%';
      col.title=pad2(hi)+':00  ·  '+s.hours[hi]+' connect'+(s.hours[hi]===1?'':'s');
      col.appendChild(bar); hrow.appendChild(col);
      hlab.appendChild(el('span',null, (hi%6===0)? pad2(hi) : ''));
    }
    c6.appendChild(hrow); c6.appendChild(hlab);
    c6.appendChild(el('div','stnote','Peak at '+pad2(s.peakHour)+':00 with '+
      s.hours[s.peakHour]+' connect'+(s.hours[s.peakHour]===1?'':'s')+
      '. Hours come off the game server clock, not yours.'));
  }
  statsBody.appendChild(c6);

  // ---- Activity by day ----
  var c7=el('div','card');
  c7.appendChild(el('p','kick','Activity by day  ('+s.dayList.length+')'));
  if(!s.dayList.length){ c7.appendChild(el('div','empty','No days with activity yet.')); }
  else{
    var dshown=s.dayList.slice(0,STATS_DAYS), dmax=1;
    dshown.forEach(function(d){ if(d.sec>dmax) dmax=d.sec; });
    var dlist=el('div','clist');
    dshown.forEach(function(d){
      var row=el('div','crow drow');
      row.appendChild(el('span','cname', d.date));
      var bar=el('div','cbar'), fill=document.createElement('i');
      fill.style.width=Math.round(d.sec/dmax*100)+'%'; bar.appendChild(fill); row.appendChild(bar);
      row.appendChild(el('span','csub', d.connects+' conn'));
      row.appendChild(el('span','cn', d.sec? fmtDur(d.sec) : '0m'));
      dlist.appendChild(row);
    });
    c7.appendChild(dlist);
    if(s.dayList.length>STATS_DAYS){
      c7.appendChild(el('div','stnote','Showing the '+STATS_DAYS+' most recent of '+s.dayList.length+' days.'));
    }
  }
  statsBody.appendChild(c7);

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
      var bar=el('div','cbar'), fill=document.createElement('i'); fill.style.width=Math.round(o.n/max*100)+'%'; bar.appendChild(fill); row.appendChild(bar);
      row.appendChild(el('span','cn', String(o.n)));
      list.appendChild(row);
    });
    c3.appendChild(list);
  }
  statsBody.appendChild(c3);

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
      var bar=el('div','cbar'), fill=document.createElement('i'); fill.style.width=Math.round(o.n/rmax*100)+'%';
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
  statsBody.appendChild(c5);
}

// One player, expanded: the identity spread (aliases / IPs / GUIDs) an admin
// needs to tell an alt from a rename, plus their own event tail. Everything is
// scoped to the SAME window as the leaderboard that opened it.
function playerCard(p, events){
  var card=el('div','card pcard');
  var head=el('div','hhead');
  var ttl=el('p','kick');
  ttl.appendChild(statFlag(p.cc));
  ttl.appendChild(document.createTextNode(p.name||'?'));
  head.appendChild(ttl);
  var x=document.createElement('button');
  x.type='button'; x.className='xbtn'; x.textContent='close';
  x.addEventListener('click', function(){ statPick=null; renderStats(); });
  head.appendChild(x);
  card.appendChild(head);

  var g=el('div','hstat');
  function cell(k,v){ var c=el('div','cell'); c.appendChild(el('div','k',k));
    c.appendChild(el('div','v',(v==null||v==='')?'n/a':String(v))); g.appendChild(c); }
  cell('Playtime', p.sec? fmtDur(p.sec) : 'n/a');
  cell('Sessions', p.sessions);
  cell('Avg session', p.sessions? fmtDur(p.sec/p.sessions) : 'n/a');
  cell('Longest', p.longest? fmtDur(p.longest) : 'n/a');
  cell('Connects', p.conns);
  cell('First seen', agoLong(p.first));
  cell('Last seen', agoLong(p.last));
  cell('Location', p.region ? (p.region+', '+countryName(p.cc)) : countryName(p.cc));
  card.appendChild(g);

  var names=keyList(p.names), ips=keyList(p.ips), guids=keyList(p.guids);
  function chips(label, arr, cls){
    if(!arr.length) return;
    var row=el('div','chips');
    row.appendChild(el('span','clab', label));
    arr.forEach(function(v){ row.appendChild(el('span','chip'+(cls?' '+cls:''), v)); });
    card.appendChild(row);
  }
  if(names.length>1) chips('Names', names);
  chips('IPs', ips, 'mono1');
  chips('GUIDs', guids, 'mono1');

  var mine=playerEvents(events, p.key);
  var tbl=el('table'), th=el('tr');
  ['When','Event','Name','IP address','Session'].forEach(function(h){ th.appendChild(el('th',null,h)); });
  tbl.appendChild(th);
  mine.slice(0,STATS_EVENTS).forEach(function(e){
    var tr=el('tr');
    tr.appendChild(el('td',null,(e.date||'')+' '+(e.time||'')));
    var te=el('td'); te.appendChild(el('span','ev '+evClass(e.event), e.event||'')); tr.appendChild(te);
    tr.appendChild(el('td','name', e.name||''));
    tr.appendChild(el('td','ip', e.ip||''));
    tr.appendChild(el('td',null, e.session||''));
    tbl.appendChild(tr);
  });
  card.appendChild(tbl);
  var n='Showing '+Math.min(mine.length,STATS_EVENTS)+' of '+mine.length+' events in this window.';
  if(names.length>1) n+=' This player has used '+names.length+' names; they are folded together by GUID.';
  if(ips.length>1)   n+=' '+ips.length+' distinct IPs seen.';
  card.appendChild(el('div','stnote', n));
  return card;
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
