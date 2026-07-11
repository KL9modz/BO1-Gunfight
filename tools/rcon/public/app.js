'use strict';
const API='/api';   // same-origin (relative): works whether the page is opened via 127.0.0.1 or localhost, no CORS needed

// ─── Maps data ────────────────────────────────────────────────────────────────
const MAPS=[
  // Base game (14) — all gunfight-ready
  {id:'mp_array',n:'Array',gf:1},{id:'mp_cairo',n:'Havana',gf:1},
  {id:'mp_cosmodrome',n:'Launch',gf:1},{id:'mp_cracked',n:'Cracked',gf:1},
  {id:'mp_crisis',n:'Crisis',gf:1},{id:'mp_duga',n:'Grid',gf:1},
  {id:'mp_firingrange',n:'Firing Range',gf:1},{id:'mp_hanoi',n:'Hanoi',gf:1},
  {id:'mp_havoc',n:'Jungle',gf:1},{id:'mp_mountain',n:'Summit',gf:1},
  {id:'mp_nuked',n:'Nuketown',gf:1},{id:'mp_radiation',n:'Radiation',gf:1},
  {id:'mp_russianbase',n:'WMD',gf:1},{id:'mp_villa',n:'Villa',gf:1},
  // First Strike (4)
  {id:'mp_berlinwall2',n:'Berlin Wall',gf:1,dlc:1},{id:'mp_discovery',n:'Discovery',gf:1,dlc:1},
  {id:'mp_kowloon',n:'Kowloon',gf:1,dlc:1},{id:'mp_stadium',n:'Stadium',gf:1,dlc:1},
  // Escalation (4)
  {id:'mp_gridlock',n:'Convoy',gf:1,dlc:1},{id:'mp_hotel',n:'Hotel',gf:1,dlc:1},
  {id:'mp_outskirts',n:'Stockpile',gf:1,dlc:1},{id:'mp_zoo',n:'Zoo',gf:1,dlc:1},
  // Annihilation (4)
  {id:'mp_drivein',n:'Drive-In',gf:1,dlc:1},{id:'mp_area51',n:'Hangar 18',gf:1,dlc:1},
  {id:'mp_golfcourse',n:'Hazard',gf:1,dlc:1},{id:'mp_silo',n:'Silo',gf:1,dlc:1},
];

// ─── Set All ──────────────────────────────────────────────────────────────────
function sdve(dv,id){sdvv(dv,g(id).value);}
// Read the current value of a row's control (first input/select inside a [data-dvar] row).
function _rowVal(row){
  const el=row.querySelector('input,select'); if(!el)return null;
  if(el.type==='checkbox') return el.checked?'1':'0';
  return el.value!==''?el.value:null;
}
// A row flagged .unsynced never got a value back from the server (read timed out, or the dvar is
// unregistered), so its control is still showing the HARDCODED DEFAULT — not a live value. Writing
// that back is how a missed read silently reconfigures the server: e.g. a dropped
// sv_disableClientConsole read + Set All would push the default and re-open the console on a live
// public lobby. Never write a value we never read. Applies to Set All AND 💾 Save.
function _skipUnsynced(row){ return row.classList.contains('unsynced') || (row.closest('.srow')||row).classList.contains('unsynced'); }
async function setAllInBlock(btn){
  const block=btn.closest('.block');
  const cmds=[],seen={};
  let skipped=0,svset=0;
  // Data-driven rows carry their dvar declaratively (data-dvar, emitted by srvRow).
  // data-also = a rider dvar kept in lockstep (e.g. the scr_gf_team_fftype FF override) —
  // it MUST be written too, or a stale override would silently win over the base dvar.
  // data-mirror = a cheat-protected dvar the engine will NOT let us `set` directly; we write its
  // plain gf_* mirror instead and fire one `svsync` below so GSC copies the mirrors across.
  block.querySelectorAll('[data-dvar]').forEach(row=>{
    if(_skipUnsynced(row)){skipped++;return;}
    const mirror=row.getAttribute('data-mirror');
    const dv=mirror||row.getAttribute('data-dvar'),v=_rowVal(row);
    if(mirror&&v!==null) svset++;
    if(dv&&v!==null&&!seen[dv]){seen[dv]=1;cmds.push(`set ${dv} ${v}`);}
    const also=row.getAttribute('data-also');
    if(also&&v!==null&&!seen[also]){seen[also]=1;cmds.push(`set ${also} ${v}`);}
  });
  // One unstamped bridge call applies every mirror at once (seq 0 = no dedup, always runs).
  if(svset) cmds.push('set gf_cmd svsync');
  // Legacy static rows: scrape the sdve('dvar','inputId') onclick pattern.
  block.querySelectorAll('[onclick^="sdve("]').forEach(el=>{
    const m=el.getAttribute('onclick').match(/sdve\('([^']+)','([^']+)'\)/);
    if(m&&!seen[m[1]]){const inp=g(m[2]);if(inp){seen[m[1]]=1;cmds.push(`set ${m[1]} ${inp.value}`);}}
  });
  if(skipped) actLog(`Set All: skipped ${skipped} unread row(s) — ↻ Read first`,'wn');
  if(!cmds.length){toast(skipped?'Nothing synced to set — ↻ Read first':'Nothing to set','info');return;}
  const r=await batchCmds(cmds,50);
  const ok=r.results?r.results.filter(x=>x.ok).length:0;
  actLog(`Set All: ${ok}/${cmds.length}`,'ok');toast(`Set All (${cmds.length})`,'ok');
}
// ─── Save to dedicated.cfg ────────────────────────────────────────────────────
// Set All applies a block live (this session); Save writes it to dedicated.cfg so it
// persists across restarts (effective on next server start / `exec dedicated.cfg`).
// Collects a block's dvars from data-dvar rows first (data-driven controls), then scans
// static rows for the sdve('dv','inputId') / sdvv('dv',…) patterns. Skips bridge buttons.
function collectBlockDvars(block){
  const out={};
  block.querySelectorAll('[data-dvar]').forEach(row=>{
    if(_skipUnsynced(row)) return;   // never persist a value we never read (see _skipUnsynced)
    // A cheat-protected dvar cannot be persisted directly: dedicated.cfg is executed as console
    // commands at startup, so `set sv_botFov 50` there is refused exactly like an rcon set. Persist
    // the plain gf_* mirror instead — gf_bridgeApplyServerDvars() copies it onto the real dvar from
    // GSC on the first round after the restart, which is the only path that works.
    const dv=row.getAttribute('data-mirror')||row.getAttribute('data-dvar'),v=_rowVal(row);
    if(dv&&v!==null) out[dv]=v;
    const also=row.getAttribute('data-also');
    if(also&&v!==null) out[also]=v;
  });
  block.querySelectorAll('[onclick],[onchange]').forEach(el=>{
    const a=(el.getAttribute('onclick')||'')+' '+(el.getAttribute('onchange')||'');
    let m=a.match(/sdve\('([^']+)','([^']+)'\)/);
    if(m){if(out[m[1]]===undefined){const inp=g(m[2]); if(inp&&inp.value!=='') out[m[1]]=inp.value;} return;}
    m=a.match(/sdvv\('([^']+)'/);
    if(m&&out[m[1]]===undefined){const dv=m[1];
      if(el.type==='checkbox') out[dv]=el.checked?'1':'0';
      else if(el.tagName==='SELECT'||el.type==='range'||el.type==='number'||el.type==='text') out[dv]=el.value;
    }
  });
  return out;
}
async function saveCfgDvars(dvars){
  return (await fetch(API+'/savecfg',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({dvars})})).json();
}
async function saveBlockToCfg(btn){
  const dvars=collectBlockDvars(btn.closest('.block'));
  const n=Object.keys(dvars).length;
  if(!n){toast('Nothing saveable in this block','info');return;}
  const r=await saveCfgDvars(dvars);
  if(r&&r.ok){
    toast(`Saved ${n} dvar(s) to dedicated.cfg`,'ok');
    actLog(`Saved to cfg: ${r.updated} updated, ${r.added} added`,'ok');
  } else toast('Save failed: '+((r&&r.error)||'?'),'err');
}

// ─── State ───────────────────────────────────────────────────────────────────
let live=false, paused=false, hist=[], histI=-1, lastMap=null;
// Map-rotation editor state. `rotation` is the working copy of sv_maprotation ([{gametype,map}]);
// `rotCurrentHead` is the map id at the head of sv_maprotationcurrent (what the engine loads next);
// `rotLoadedSig` snapshots the server-loaded order so we can flag unsaved edits.
let rotation=[], rotCurrentHead='', rotLoadedSig='';

// ─── Persistence (server profiles) ────────────────────────────────────────────
// Each profile remembers its host/port in localStorage; the rcon_password lives in the
// GITIGNORED secrets.local.json on the server side (keyed by profile name) and is fetched
// over the loopback API — so a password NEVER sits in localStorage or in any tracked file.
// Two profiles:
//   VPS   = reach the remote VPS over its public IP (used from the laptop).
//   Local = reach THIS machine's own server over loopback. It "just works" per machine — on the
//           laptop that's your listen (or local dedicated) server; on the VPS (via RDP) it's the
//           VPS's own dedicated server. The password comes from that machine's secrets.local.json,
//           and listen-vs-dedicated is auto-detected from `status`, so one loopback profile covers
//           every case. (A 2nd loopback profile would only make sense to store a 2nd password on the
//           same machine — not needed here.)
let _profiles=[], _activeProfile=0, _secrets={};
function defaultProfiles(){return[
  {name:'Local', host:'127.0.0.1',  port:'28960'},   // DEFAULT: this machine's own server (loopback) — laptop listen server OR VPS dedicated server, whichever box the panel runs on
  {name:'VPS',   host:'94.72.121.4',port:'28960'},   // optional: drive the remote VPS directly over public rcon (from the laptop, no tunnel)
];}
function loadProfiles(){
  try{
    const raw=JSON.parse(localStorage.getItem('gf_rcon_profiles')||'null');
    if(raw&&Array.isArray(raw.profiles)&&raw.profiles.length){
      _profiles=raw.profiles; _activeProfile=raw.active||0;
    }else{
      _profiles=defaultProfiles();
      _activeProfile=0;
    }
  }catch(_){_profiles=defaultProfiles();_activeProfile=0;}
  if(_activeProfile>=_profiles.length||_activeProfile<0)_activeProfile=0;
  // remember the active profile by NAME so the dedupe below can't point at the wrong one
  const activeName=(_profiles[_activeProfile]||{}).name;
  // ensure every built-in profile exists, in canonical order; keep any custom profiles after them
  const canon={}; defaultProfiles().forEach(d=>canon[d.name]=d);
  const byName={}; _profiles.forEach(p=>byName[p.name]=p);
  const ordered=[];
  defaultProfiles().forEach(d=>ordered.push(byName[d.name]||{name:d.name,host:d.host,port:d.port}));
  _profiles.forEach(p=>{ if(!canon[p.name])ordered.push(p); });
  _profiles=ordered;
  _activeProfile=Math.max(0,_profiles.findIndex(p=>p.name===activeName));
  _profiles.forEach(p=>{delete p.pass;});   // passwords never live in localStorage
  // backfill canonical host/port for built-in profiles if a stale entry lost them
  _profiles.forEach(p=>{ const d=canon[p.name]; if(d){ if(!p.host)p.host=d.host; if(!p.port)p.port=d.port; } });
}
function persistProfiles(){
  // store name/host/port only — the secret is in secrets.local.json, not here
  const clean=_profiles.map(p=>({name:p.name,host:p.host,port:p.port}));
  localStorage.setItem('gf_rcon_profiles',JSON.stringify({profiles:clean,active:_activeProfile}));
}
function renderProfiles(){
  const sel=g('iProfile');
  sel.innerHTML=_profiles.map((p,i)=>`<option value="${i}"${i===_activeProfile?' selected':''}>${p.name}</option>`).join('');
}
function fillFromProfile(){
  const p=_profiles[_activeProfile]||{};
  g('iHost').value=p.host||'';g('iPort').value=p.port||'28960';
  g('iPass').value=(_secrets[p.name]!=null?_secrets[p.name]:'');
}
// server-side secrets store (gitignored) ──────────────────────────────
async function fetchSecrets(){
  try{const r=await (await fetch(API+'/secrets')).json();return (r&&r.ok&&r.profiles)||{};}catch(_){return {};}
}
async function saveSecret(name,pass){
  try{await fetch(API+'/secrets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,pass})});}catch(_){}
}
// Copy the current input fields back into the active profile (called on connect / field edit).
// host/port → localStorage; rcon_password → gitignored secrets.local.json (never localStorage).
function captureToProfile(){
  const p=_profiles[_activeProfile]; if(!p)return;
  p.host=g('iHost').value.trim();p.port=g('iPort').value.trim();
  persistProfiles();
  const pass=g('iPass').value;
  _secrets[p.name]=pass;
  saveSecret(p.name,pass);
}
function switchProfile(){
  captureToProfile();                       // save edits to the profile we're leaving
  _activeProfile=parseInt(g('iProfile').value)||0;
  fillFromProfile();
  persistProfiles();
  if(live)disconnect();                      // switching servers drops the current connection
}
async function loadCfg(){
  loadProfiles(); renderProfiles(); fillFromProfile();   // host/port immediately
  _secrets=await fetchSecrets();
  fillFromProfile();                                     // now with the password
  // URL-driven convenience for the VPS desktop shortcut: ?profile=NAME selects a saved profile and
  // ?autoconnect (or ?connect) clicks Connect once credentials are filled. Nothing sensitive is in
  // the URL — the password still comes from the gitignored secrets file via the loopback API.
  try{
    const q=new URLSearchParams(location.search);
    const prof=q.get('profile');
    if(prof){
      const i=_profiles.findIndex(p=>p.name.toLowerCase()===prof.toLowerCase());
      if(i>=0){ _activeProfile=i; renderProfiles(); persistProfiles(); fillFromProfile(); }
    }
    if((q.has('autoconnect')||q.has('connect')) && !live) doConn();
  }catch(_){}
}
function saveCfg(){ captureToProfile(); }
function conn(){return{host:g('iHost').value.trim()||'127.0.0.1',port:parseInt(g('iPort').value)||28960,password:g('iPass').value}}

// ─── API ────────────────────────────────────────────────────────────────────
async function rcon(command,priority){
  const c=conn();
  return (await fetch(API+'/rcon',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...c,command,priority:!!priority})})).json();
}
async function batchCmds(commands,delay=80){
  const c=conn();
  return (await fetch(API+'/batch',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...c,commands,delayMs:delay})})).json();
}
async function fetchStatus(){
  const c=conn();const p=new URLSearchParams({host:c.host,port:c.port,password:c.password});
  return (await fetch(API+'/status?'+p)).json();
}
async function fetchTick(){
  // ONE rcon send for the whole dashboard refresh (status + gf_state + gf_roster chained
  // server-side). state/roster come back null on a listen server — status still lands.
  const c=conn();const p=new URLSearchParams({host:c.host,port:c.port,password:c.password});
  return (await fetch(API+'/tick?'+p)).json();
}
async function fetchDvars(names,fresh){
  const c=conn();const q={host:c.host,port:c.port,password:c.password,names:names.join(',')};
  if(fresh)q.fresh='1';   // re-probe: server clears its cached "unregistered" set for this profile
  const p=new URLSearchParams(q);
  return (await fetch(API+'/dvars?'+p)).json();
}

// ─── Connect ────────────────────────────────────────────────────────────────
async function doConn(){
  if(live){disconnect();return;}
  saveCfg();
  const btn=g('cBtn');btn.disabled=true;btn.textContent='…';
  try{
    const d=await fetchStatus();
    if(d.ok){setLive(true);tick(d);actLog('Connected to '+((_profiles[_activeProfile]||{}).name||conn().host)+' ('+conn().host+')','ok');reqNotifyPerm();pushAdminGuid();seedCmdSeq();readServerDvars();readMatchDvars();loadRotation();}
    else{toast('Failed: '+d.error,'err');setLive(false);}
  }catch(e){toast('Error: '+e.message,'err');setLive(false);}
  btn.disabled=false;
}
function setLive(v){
  live=v;
  const btn=g('cBtn'),bdg=g('badge');
  const hr=g('hdrRead'),hk=g('hdrKill');
  if(v){
    btn.textContent='Disconnect';btn.className='disc';
    bdg.textContent='● Connected';bdg.className='bdg on';
    if(hr)hr.style.display='';if(hk)hk.style.display='';   // header Read + Kill Server
    setCtrl(true);
    // Default bot difficulty is normal — highlight until user changes it
    ['easy','normal','hard','fu'].forEach(k=>g('d-'+k).classList.toggle('sel',k==='normal'));
    startPoll();
  }else{
    btn.textContent='Connect';btn.className='';
    bdg.textContent='● Disconnected';bdg.className='bdg off';
    g('modeBadge').style.display='none';
    if(hr)hr.style.display='none';if(hk)hk.style.display='none';
    setCtrl(false);stopPoll();
    setLobbyHold(false);   // don't leave START MATCH stuck visible after a disconnect
    _knownPlayers=null;   // re-seed the join baseline on next connect (no spam on reconnect)
  }
  updateSyncUI();
}
// ─── Sync (dvar-read) progress indicator ──────────────────────────────────────
// Reads are single fetches that resolve only when the whole paced sweep finishes, so the
// bar is indeterminate. A counter tracks overlapping reads (connect fires several at once).
let _syncN=0;
function syncBegin(){ _syncN++; updateSyncUI(); }
function syncEnd(){ _syncN=Math.max(0,_syncN-1); updateSyncUI(); }
function updateSyncUI(){
  const on=_syncN>0;
  const bar=g('syncBar'); if(bar) bar.classList.toggle('on',on);
  const hr=g('hdrRead'); if(hr){ hr.classList.toggle('b-busy',on); hr.disabled=on||!live; }
  const bdg=g('badge'); if(bdg&&live) bdg.textContent=on?'● Syncing…':'● Connected';
}
// Header ↻ Read: refresh every live dvar block (SERVER + MATCH), same as on connect.
// fresh=true (the ↻ Read button) tells the server to CLEAR its cached "unregistered dvar" set for
// this profile and re-probe every name — so a dvar that became registered since connect is picked
// back up. Connect (doConn) calls the no-arg readServerDvars/readMatchDvars → cached (quiet).
function readAllFromServer(fresh){ readServerDvars(fresh); readMatchDvars(fresh); }
function disconnect(){
  setLive(false);
  _roster={};_rosterSig='';_lastPlayers=[];_grouped=false;_playersSig='';
  g('ptbody').innerHTML='<tr class="empty"><td colspan="6">Not connected</td></tr>';
  g('sMap').textContent=g('sGt').textContent=g('sPl').textContent='—';
  g('scA').textContent=g('scX').textContent=g('scRound').textContent='—';
  g('scAA').textContent=g('scAX').textContent='—';
}
// ONE self-scheduling poll drives the whole dashboard: a single /api/tick per cycle, and the
// next cycle is armed only after this one RESOLVES — the loop can never stack requests. The old
// shape (status @3s + gf_state/gf_roster @2.5s on two setIntervals) enqueued three rcon sends
// per cycle ≈ 1.4x what the 850ms-gap lane can drain on a dedicated server, so the rcon queue
// grew without bound; the hanging fetches then exhausted the browser's 6-connection pool, which
// stalled even the PRIORITY lane (clicks, ack polls) behind the backlog — commands took minutes.
// A listen server returns state/roster null (score card stays muted, grouping stays off).
let _pollGen=0,_pollTimer=null;
function startPoll(){ stopPoll(); pollTick(_pollGen); }
function stopPoll(){ _pollGen++; clearTimeout(_pollTimer); _pollTimer=null; }
async function pollTick(gen){
  if(gen!==_pollGen||!live)return;
  try{
    const d=await fetchTick();
    if(gen!==_pollGen||!live)return;
    if(d.ok){
      // Map changed → the engine advanced its own rotation. Refresh the "next" badge from the live
      // sv_maprotationcurrent, but only while the Maps tab is open (event-driven, not a poll). The
      // grid/list LIVE highlight follows d.map every tick via tick()→markCurrentMap(); no reactive
      // `map` override here — the rotation editor drives the engine's rotation directly instead.
      if(lastMap!==d.map){
        const first=(lastMap===null); lastMap=d.map;
        if(rotation.length) renderRotation();
        if(!first && live && g('p-maps').classList.contains('active')) loadRotation();
      }
      tick(d);
      if(d.state){
        const s=d.state;
        g('scA').textContent=s.winsAllies;
        g('scX').textContent=s.winsAxis;
        g('scRound').textContent='R '+s.round;
        g('scAA').textContent=s.aliveAllies;
        g('scAX').textContent=s.aliveAxis;
        if(s.gametype) g('sGt').textContent=s.gametype;
        setLobbyHold(s.lobbyHold);
        updateFillReadout(s);
      }
      if(d.roster){
        _roster={}; for(const e of d.roster) _roster[e.num]=e;
        // Only rebuild the table when the team/pending mapping actually changed (tick(d)'s
        // status render already repaints on its own cadence).
        const sig=d.roster.map(e=>e.num+':'+e.team+':'+(e.pending||'')).join('|');
        if(sig!==_rosterSig){ _rosterSig=sig; renderPlayers(); }
      }
    }else{g('badge').className='bdg err';}
  }catch(_){}
  if(gen!==_pollGen||!live)return;
  _pollTimer=setTimeout(()=>pollTick(gen),2500);
}
// num -> {num,team,alive,pending} from gf_roster; empty until first successful roster read.
let _roster={}, _rosterSig='';
let _listenServer=false;
function tick(d){
  _listenServer=!!d.listenServer;
  g('sMap').textContent=d.map||'—';
  markCurrentMap(d.map);
  g('sGt').textContent=d.gametype||(d.listenServer?'Listen Server':'—');
  g('sPl').textContent=d.players.length+' online';
  buildPlayers(d.players);
  notifyJoins(d.players);
  g('scoreCard').classList.toggle('listen-muted',_listenServer);
  g('scoreListenNote').style.display=_listenServer?'':'none';
  applyServerMode();
}
// Surface the detected server mode + auto-grey controls that don't apply to it.
// .ded-only (Kill Server) is greyed on listen; .listen-only (host Noclip) greyed on dedicated.
function applyServerMode(){
  const b=g('modeBadge');
  if(!live){ b.style.display='none'; return; }
  b.style.display='';
  b.textContent=_listenServer?'LISTEN':'DEDICATED';
  b.className='bdg '+(_listenServer?'mode-listen':'mode-ded');
  document.querySelectorAll('.ded-only').forEach(el=>el.disabled=_listenServer);
  document.querySelectorAll('.listen-only').forEach(el=>el.disabled=!_listenServer);
  // Controls that only work off a dedicated server: saved client dvars (FOV / view bob /
  // drawfps — host-only) and cheat-protected r_* pushes (Visual Tweaks — need sv_cheats,
  // which the mod only sets on a listen server). Grey them on a dedicated server.
  document.querySelectorAll('.ded-lockable').forEach(el=>el.classList.toggle('ded-locked',!_listenServer));
}
function setCtrl(en){
  document.querySelectorAll('.ctrl').forEach(el=>el.disabled=!en);
}

// ─── Players + right-click ────────────────────────────────────────────────────
let ctxPlayer=null;
// GUID that receives PRIVATE in-game bridge feedback (via gf_admin_guids). Set by right-clicking
// your own player → "Send feedback to me". Persisted locally and re-pushed to the server on connect.
let _adminGuid=localStorage.getItem('gf_admin_guid')||'';
function pushAdminGuid(){ if(_adminGuid&&live) rcon('set gf_admin_guids '+_adminGuid,true); }
let _lastPlayers=[];   // last status roster (names/ping/etc); merged with _roster (teams) to render
let _grouped=false;    // true when we have team data and render grouped-by-team headers
// Status tick hands us the player list; renderPlayers() merges it with the team roster.
// Skip the innerHTML rebuild when nothing visible changed — the status tick fires every
// 2.5s and a no-op repaint both wastes DOM work and wipes an in-progress text selection
// (e.g. selecting a GUID/IP from the table). Signature covers every rendered field.
let _playersSig='';
function buildPlayers(ps){
  _lastPlayers=ps||[];
  const sig=_lastPlayers.map(p=>[p.num,p.name,p.score,p.ping,p.guid,p.ip,p.bot,p.local].join('~')).join('|');
  if(sig===_playersSig) return;
  _playersSig=sig;
  renderPlayers();
}
// Render the PLAYERS table. With gf_roster team data (dedicated), players are grouped under
// ALLIES / AXIS / SPECTATOR headers (with counts) so you can read the teams at a glance and
// balance them. Without team data (listen server, or roster not read yet) it falls back to a
// flat list. Called from the poll tick, both via buildPlayers (status) and on roster changes.
function renderPlayers(){
  const tb=g('ptbody');
  const ps=_lastPlayers;
  if(!ps||!ps.length){tb.innerHTML='<tr class="empty"><td colspan="6">No players</td></tr>';_grouped=false;return;}
  const groups={allies:[],axis:[],spectator:[],unknown:[]};
  for(const p of ps){ const t=(_roster[p.num]||{}).team||'unknown'; (groups[t]||groups.unknown).push(p); }
  _grouped = !!(groups.allies.length||groups.axis.length||groups.spectator.length);
  let html;
  if(!_grouped){
    html=ps.map(rowHtml).join('');
  }else{
    const sec=(key,label,cls)=>{
      const a=groups[key]; if(!a.length) return '';
      return `<tr class="grp ${cls}"><td colspan="6">${label}<span class="grp-n">${a.length}</span></td></tr>`+a.map(rowHtml).join('');
    };
    html = sec('allies','◆ ALLIES','grp-a')
         + sec('axis','◆ AXIS','grp-x')
         + sec('spectator','◇ SPECTATOR','grp-s')
         + sec('unknown','◇ —','grp-u');
  }
  tb.innerHTML=html;
  paintTeams();
}
function rowHtml(p){
  const adminStar=(!p.bot && _adminGuid && p.guid===_adminGuid)?'<span class="adm-star" title="Private bridge feedback goes to this player">★</span>':'';
  const tag=p.bot?'<span class="bot-t">BOT</span>':p.local?'<span class="you-t">YOU</span>':'';
  const pg=p.bot?'<span class="bot-t">BOT</span>':`<span class="${p.ping<80?'p-ok':p.ping<150?'p-mid':'p-bad'}">${p.ping}ms</span>`;
  const ipCell=p.ip?`<span class="dm" style="font-size:10px">${x(p.ip)}</span>`:`<span class="dm">-</span>`;
  const guidCell=p.bot?'<span class="dm">-</span>':`<span class="dm" style="font-size:10px;user-select:all">${p.guid||'-'}</span>`;
  return`<tr data-num="${p.num}" data-name="${x(p.name)}" data-bot="${p.bot}" oncontextmenu="showCtx(event,${p.num},'${x(p.name)}',${p.bot})">
    <td>${p.num}</td><td>${adminStar}${tag}${p.bot?x(p.name):`<span class="real-n">${x(p.name)}</span>`}<span class="tm-slot" data-tm="${p.num}"></span></td><td>${p.score}</td><td>${pg}</td><td>${ipCell}</td><td>${guidCell}</td></tr>`;
}
// Per-row indicator from the last gf_roster read. When the list is grouped, the team is already
// shown by the section header, so the row only carries a pending-move hint (→ Axis). When flat
// (no team data), we show nothing extra. Empty string when there's no roster entry for that num.
function teamBadgeHtml(num){
  const e=_roster[num];
  if(!e) return '';
  let h='';
  if(!_grouped && e.team){
    const code=e.team==='allies'?'a':e.team==='axis'?'x':'s';
    const lbl=e.team==='allies'?'ALLIES':e.team==='axis'?'AXIS':'SPEC';
    h+=`<span class="tm tm-${code}">${lbl}</span>`;
  }
  if(e.pending && e.pending!==e.team){
    const pl=e.pending==='allies'?'Allies':e.pending==='axis'?'Axis':'Spec';
    h+=`<span class="tm-pend">→ ${pl}</span>`;
  }
  return h;
}
// Re-fill the team-badge slots in the current player rows from _roster (kept across the
// status rebuild so badges don't flicker between the 3s status tick and 2.5s roster tick).
function paintTeams(){
  document.querySelectorAll('#ptbody .tm-slot').forEach(sl=>{
    sl.innerHTML=teamBadgeHtml(parseInt(sl.getAttribute('data-tm')));
  });
}
function x(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/'/g,'&#39;')}

function showCtx(e,num,name,isBot){
  e.preventDefault();
  const pl=_lastPlayers.find(p=>p.num===num)||{};
  const ip=(!isBot && pl.ip && pl.ip!=='local')?pl.ip:'';   // real routable IP only (not bots/host)
  const guid=(!isBot && pl.guid && pl.guid!=='0')?pl.guid:'';   // stable id for the feedback-admin allowlist
  ctxPlayer={num,name,isBot,ip,guid};
  const ct=(_roster[num]||{}).team||'';   // current team (grays its own move item)
  const teamItem=(t,code,label)=>`<div class="ctx-item ${ct===t?'cur':''}" onclick="ctxAction('team_${code}',event)">${label}</div>`;
  const ipItems=ip?`<div class="ctx-sep"></div>
    <div class="ctx-item" onclick="ctxAction('copyip')">Copy IP</div>
    <div class="ctx-item" onclick="ctxAction('locate')">Locate (city)</div>`:'';
  // Route private in-game bridge feedback to this player (by GUID). Only offered for real players.
  const adminItem=guid?`<div class="ctx-sep"></div>
    <div class="ctx-item ${guid===_adminGuid?'cur':''}" onclick="ctxAction('setadmin')">★ ${guid===_adminGuid?'Feedback admin (you)':'Send feedback to me'}</div>`:'';
  // Noclip is a CHEAT-PROTECTED console command that acts on the LOCAL player — a dedicated server
  // has neither (sv_cheats is 0 there, and there is no local player at all). It used to fire
  // `noclip <num>` unconditionally and log "Noclip toggled" regardless. T5 has no scriptable noclip,
  // so there is nothing to route through the bridge either: grey it off-listen and say why.
  const noclipItem=_listenServer
    ? `<div class="ctx-item" onclick="ctxAction('pnoclip')">Noclip</div>`
    : `<div class="ctx-item cur" title="Listen server only — noclip is cheat-protected (sv_cheats is 0 on a dedicated server) and acts on the local player, which a dedicated server does not have.">Noclip <span style="opacity:.6">— listen only</span></div>`;
  const m=g('ctx-menu');
  m.innerHTML=`<div class="ctx-header">${x(name)}</div>
    <div class="ctx-item" onclick="ctxAction('kick')">Kick</div>
    <div class="ctx-item red" onclick="ctxAction('ban')">Ban</div>
    <div class="ctx-sep"></div>
    ${teamItem('allies','allies','<span class="tm tm-a">A</span> Move to Allies')}
    ${teamItem('axis','axis','<span class="tm tm-x">X</span> Move to Axis')}
    ${teamItem('spectator','spec','<span class="tm tm-s">S</span> Move to Spectator')}
    <div class="ctx-hint">Shift+click a move = ⚠ force now (respawns)</div>
    <div class="ctx-sep"></div>
    <div class="ctx-item green" onclick="ctxAction('pgod')">God Mode</div>
    <div class="ctx-item yellow" onclick="ctxAction('pfreeze')">Freeze</div>
    <div class="ctx-item yellow" onclick="ctxAction('punfreeze')">Unfreeze</div>
    <div class="ctx-item" onclick="ctxAction('pperks')">Give Perks</div>
    ${noclipItem}${ipItems}${adminItem}`;
  m.style.display='block';
  // Position near cursor, keep in viewport
  const vw=window.innerWidth,vh=window.innerHeight;
  let lft=e.clientX+4,top=e.clientY+4;
  if(lft+170>vw) lft=e.clientX-174;
  if(top+360>vh) top=Math.max(4,vh-364);
  m.style.left=lft+'px';m.style.top=top+'px';
}
async function ctxAction(act,ev){
  hideCtx();
  if(!ctxPlayer)return;
  const{num,name,ip}=ctxPlayer;
  if(act==='kick'){
    const r=await rcon(`clientkick ${num}`);
    r.ok?actLog('Kicked '+name,'wn'):toast('Kick failed','err');
  }else if(act==='ban'){
    if(!confirm(`Ban ${name}? This kicks them and blocks reconnects.`))return;
    const r=await rcon(`banClient ${num}`);
    r.ok?actLog('Banned '+name,'wn'):toast('Ban failed','err');
  }else if(act==='pgod'){
    await bridge(`pgod_${num}`,'God → '+name);actLog('God → '+name,'ok');
  }else if(act==='pfreeze'){
    await bridge(`pfreeze_${num}`,'Freeze → '+name);actLog('Frozen: '+name,'wn');
  }else if(act==='punfreeze'){
    await bridge(`punfreeze_${num}`,'Unfreeze → '+name);actLog('Unfrozen: '+name,'ok');
  }else if(act==='pperks'){
    await bridge(`pperks_${num}`,'Perks → '+name);actLog('Perks → '+name,'ok');
  }else if(act==='setadmin'){
    const guid=ctxPlayer&&ctxPlayer.guid;
    if(!guid){toast('No GUID for this player','err');return;}
    _adminGuid=guid; localStorage.setItem('gf_admin_guid',guid);
    await rcon('set gf_admin_guids '+guid,true);   // push live; re-pushed on every reconnect
    actLog('Feedback admin → '+name+' ('+guid+')','ok'); toast('Private feedback → '+name,'ok');
    if(_lastPlayers.length)renderPlayers();   // repaint the ★ marker
  }else if(act==='team_allies'||act==='team_axis'||act==='team_spec'){
    // Normal: applies live during prematch, else the mod defers to the next round (never suicides
    // a live player). Shift+click FORCES it now (pteamforce_) — respawns the player this round.
    const code=act.slice(5);   // allies | axis | spec
    const lbl={allies:'Allies',axis:'Axis',spec:'Spectator'}[code];
    const force=!!(ev&&ev.shiftKey);
    if(force && !confirm(`Force ${name} to ${lbl} NOW?\nThis respawns them — during a live round it costs them the round.`))return;
    await bridge(`${force?'pteamforce':'pteam'}_${num}_${code}`,(force?'⚠ Force → ':'Team → ')+lbl+': '+name);
    actLog((force?'Force team → ':'Team → ')+lbl+': '+name,force?'wn':(code==='spec'?'wn':'ok'));
  }else if(act==='pnoclip'){
    // Listen only (see noclipItem). Even there, verify the reply — noclip is cheat-protected, so it
    // is refused the moment sv_cheats is 0, and the old code logged success unconditionally.
    if(!_listenServer){ toast('Noclip needs a listen server — cheat-protected, and no local player on a dedicated server','err'); return; }
    const r=await rcon(`noclip ${num}`);
    const err=(!r||!r.ok)?((r&&r.error)||'send failed'):dvarWriteError(r.response);
    if(err){ toast('Noclip refused: '+err,'err'); actLog('✗ Noclip '+name+': '+err,'err'); return; }
    actLog('Noclip toggled: '+name,'ok');
  }else if(act==='copyip'){
    if(!ip){toast('No IP for this player','err');return;}
    try{ await navigator.clipboard.writeText(ip); actLog('Copied IP '+ip+' ('+name+')','ok'); }
    catch(_){ toast('Clipboard blocked — IP: '+ip,'err'); }
  }else if(act==='locate'){
    if(!ip){toast('No IP for this player','err');return;}
    actLog('Locating '+name+' ('+ip+')…','in');
    try{
      const r=await (await fetch(API+'/geoip?ip='+encodeURIComponent(ip))).json();
      if(r.ok){ const loc=[r.city,r.region,r.country].filter(Boolean).join(', ')||'unknown';
        actLog(name+' @ '+loc+(r.isp?' · '+r.isp:''),'ok'); }
      else toast('Locate failed: '+(r.error||'unknown'),'err');
    }catch(e){ toast('Locate failed: '+e.message,'err'); }
  }
}
function hideCtx(){g('ctx-menu').style.display='none';}
document.addEventListener('click',hideCtx);
document.addEventListener('keydown',e=>{if(e.key==='Escape')hideCtx();});

// ─── Tabs ───────────────────────────────────────────────────────────────────
const TABS=['match','maps','srv','con'];
function tab(n){
  document.querySelectorAll('.panel').forEach(e=>e.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(e=>e.classList.remove('active'));
  g('p-'+n).classList.add('active');
  const i=TABS.indexOf(n);
  document.querySelectorAll('.tab')[i].classList.add('active');
  layoutColumns(g('p-'+n));   // first reveal of a settings panel lays out its columns
  if(n==='maps' && live) loadRotation();
}

// ─── Global settings search ───────────────────────────────────────────────────
// Indexes every labelled control in the DASHBOARD + ADVANCED tabs (DOM scan), plus the
// per-gametype dvars that aren't rendered until their mode is picked (from the data
// model). Typing filters by label / dvar / section / tooltip; picking a result jumps
// to its tab (switching the ADVANCED gametype dropdown if needed) and flashes the row.
let _gsIndex=[], _gsResults=[], _gsSel=-1;
// Text of an element minus any injected behavior pills.
function _gsClean(el){ if(!el) return ''; const c=el.cloneNode(true); c.querySelectorAll('.pills').forEach(p=>p.remove()); return c.textContent.replace(/\s+/g,' ').trim(); }
// Best-effort dvar name for a row: the declarative data-dvar attribute (data-driven rows),
// else the set* call it drives, else the tooltip's first line.
function _gsDvar(row){
  if(row.dataset&&row.dataset.dvar) return row.dataset.dvar;
  const h=row.innerHTML;
  let m=h.match(/sdve?\('([^']+)'/)||h.match(/sdvv\('([^']+)'/);
  if(m) return m[1];
  const first=((row.getAttribute('data-tip')||'').split(/&#10;|\n/)[0]||'').trim();
  return /^[a-z_][a-z0-9_]*$/i.test(first)?first:'';
}
function buildSearchIndex(){
  _gsIndex=[];
  document.querySelectorAll('#p-match .srow, #p-match .slider-row, #p-srv .srow, #p-srv .slider-row').forEach(row=>{
    const lblEl=row.querySelector('.slbl'); if(!lblEl) return;
    const label=_gsClean(lblEl); if(!label) return;
    const blk=row.closest('.block'); const block=blk?_gsClean(blk.querySelector('.btitle')):'';
    const tab=row.closest('#p-srv')?'srv':'match';
    const dvar=_gsDvar(row);
    const tip=(row.getAttribute('data-tip')||'').replace(/&#10;/g,' ');
    _gsIndex.push({label,dvar,block,tab,el:row,hay:(label+' '+dvar+' '+block+' '+tip).toLowerCase()});
  });
  // Per-gametype dvars (gf excluded — it renders on DASHBOARD/ADVANCED) aren't in the DOM
  // until selected, so index them from the data model and re-render on navigate.
  Object.keys(GT_SECTIONS).forEach(key=>{
    if(key==='gf') return;
    const opt=GT_OPTS.find(o=>o.val===key), gtl=opt?opt.lbl:key;
    GT_SECTIONS[key].forEach(v=>{
      if(v.type==='btn'||v.type==='perk') return;
      _gsIndex.push({label:v.lbl,dvar:v.n,block:gtl.toUpperCase(),tab:'srv',gt:key,
        hay:(v.lbl+' '+v.n+' '+gtl+' '+(v.tip||'')).toLowerCase()});
    });
  });
}
function _gsScore(e,q){
  let s=0; const l=e.label.toLowerCase(), d=(e.dvar||'').toLowerCase();
  if(l.startsWith(q)) s+=100; else if(l.includes(q)) s+=40;
  if(d===q) s+=120; else if(d.startsWith(q)) s+=70; else if(d.includes(q)) s+=30;
  return s;
}
function gSearchRun(){
  const inp=g('gSearch'), box=g('gSearchResults'), raw=inp.value.trim(), q=raw.toLowerCase();
  if(!q){ box.classList.remove('open'); return; }
  const terms=q.split(/\s+/);
  _gsResults=_gsIndex.filter(e=>terms.every(t=>e.hay.includes(t)))
                     .sort((a,b)=>_gsScore(b,q)-_gsScore(a,q)).slice(0,14);
  _gsSel=_gsResults.length?0:-1;
  box.innerHTML=_gsResults.length
    ? _gsResults.map((e,i)=>`<div class="gsr-item${i===0?' sel':''}" onmousedown="event.preventDefault();gSearchGo(${i})">`
        +`<span class="gsr-lbl">${x(e.label)}${e.dvar?`<span class="gsr-dvar">${x(e.dvar)}</span>`:''}</span>`
        +`<span class="gsr-loc">${e.tab==='srv'?'ADVANCED':'DASHBOARD'} › ${x(e.block)}</span></div>`).join('')
    : `<div class="gsr-empty">No settings match “${x(raw)}”</div>`;
  const r=inp.getBoundingClientRect();
  box.style.top=(r.bottom+4)+'px'; box.style.right=(window.innerWidth-r.right)+'px';
  box.classList.add('open');
}
function _gsMove(d){
  const items=g('gSearchResults').querySelectorAll('.gsr-item'); if(!items.length) return;
  if(items[_gsSel]) items[_gsSel].classList.remove('sel');
  _gsSel=(_gsSel+d+items.length)%items.length;
  items[_gsSel].classList.add('sel'); items[_gsSel].scrollIntoView({block:'nearest'});
}
function gSearchKey(e){
  const box=g('gSearchResults');
  if(e.key==='Escape'){ g('gSearch').value=''; box.classList.remove('open'); g('gSearch').blur(); return; }
  if(!box.classList.contains('open')) return;
  if(e.key==='ArrowDown'){ e.preventDefault(); _gsMove(1); }
  else if(e.key==='ArrowUp'){ e.preventDefault(); _gsMove(-1); }
  else if(e.key==='Enter'){ e.preventDefault(); if(_gsSel>=0) gSearchGo(_gsSel); }
}
function gSearchGo(i){
  const e=_gsResults[i]; if(!e) return;
  g('gSearchResults').classList.remove('open');
  tab(e.tab);
  let el=e.el;
  if(e.gt){                                 // synthetic gametype entry — render its block first
    buildGtSection(e.gt);
    const inp=document.getElementById('srv_'+e.dvar.replace(/[^a-zA-Z0-9]/g,'_'));
    el=inp?inp.closest('.srow'):null;
  }
  if(el){
    el.scrollIntoView({behavior:'smooth',block:'center'});
    el.classList.remove('gsr-flash'); void el.offsetWidth; el.classList.add('gsr-flash');
    setTimeout(()=>el.classList.remove('gsr-flash'),1800);
  }
  g('gSearch').blur();
}
// "/" focuses search from anywhere; click outside closes the dropdown.
document.addEventListener('keydown',e=>{
  if(e.key==='/' && !/^(INPUT|SELECT|TEXTAREA)$/.test(document.activeElement.tagName)){ e.preventDefault(); g('gSearch').focus(); }
});
document.addEventListener('click',e=>{
  if(!e.target.closest('.gsearch') && !e.target.closest('#gSearchResults')) g('gSearchResults').classList.remove('open');
});

// Once the user edits a flagged (unsynced) field, the value becomes authoritative —
// drop the "not read" flag. Programmatic srvApplyValues writes don't fire these events.
document.addEventListener('input',e=>{const r=e.target.closest&&e.target.closest('.srow.unsynced');if(r)r.classList.remove('unsynced');});
document.addEventListener('change',e=>{const r=e.target.closest&&e.target.closest('.srow.unsynced');if(r)r.classList.remove('unsynced');});

// ─── Write verification ───────────────────────────────────────────────────────
// The engine ANSWERS a refused `set` — it never fails silently. Observed replies:
//   ^1Error: <dvar> is cheat protected             needs sv_cheats 1 (and 0 is the CORRECT value on
//                                                  a dedicated server, so this is expected there)
//   '<v>' is not a valid value for dvar '<dvar>'   value outside the dvar's declared domain
//   ... is read only / is write protected
// The panel used to DISCARD that reply and toast "ok" on any successful HTTP round-trip, so a
// refused write looked exactly like an applied one. That is the single biggest reason a control
// "doesn't work": it did nothing and said it worked. Parsing the reply costs zero extra rcon
// traffic (we already have it in hand) and stays correct as Plutonium changes underneath us.
const _DVAR_ERR=[
  [/is cheat protected/i,   'cheat-protected — the engine refused it. sv_cheats is 0 (correct on a dedicated server); route it through the GSC bridge instead.'],
  [/is not a valid value/i, 'value is outside the dvar’s allowed domain — the engine kept the old one.'],
  [/is read.?only/i,        'read-only dvar — cannot be set at runtime.'],
  [/is write protected/i,   'write-protected dvar — the engine refused it.'],
  [/unknown cmd/i,          'no such dvar on this server.'],
];
function dvarWriteError(resp){
  const s=String(resp||'');
  if(!s.trim()) return null;                    // a successful `set` echoes nothing back
  for(const [re,msg] of _DVAR_ERR) if(re.test(s)) return msg;
  return null;
}
// A refused write means the control no longer reflects the server — which is exactly what
// .unsynced already means, so reuse it: the row gets flagged AND Set All / 💾 Save will now
// refuse to push that stale value back (see _skipUnsynced).
function flagDvarRow(dv){
  const id=String(dv).replace(/[^a-zA-Z0-9]/g,'_');
  ['srv_','mt_'].forEach(p=>{
    const el=g(p+id), row=el&&el.closest('.srow');
    if(row) row.classList.add('unsynced');
  });
}
// Report one dvar write. Returns true only if the server actually took the value.
function reportWrite(dv,v,r){
  if(!r||!r.ok){ toast((r&&r.error)||'send failed','err'); return false; }
  const err=dvarWriteError(r.response);
  if(err){
    toast(dv+' — '+err,'err');
    actLog('✗ '+dv+': '+err,'err');
    flagDvarRow(dv);
    return false;
  }
  toast(dv+'='+v,'ok'); actLog(dv+' → '+v,'ok');
  return true;
}

// ─── Gunfight ────────────────────────────────────────────────────────────────
async function sdv(dv,id){
  const v=g(id).value;
  return reportWrite(dv,v,await rcon(`set ${dv} ${v}`));
}
async function sdvv(dv,v){
  return reportWrite(dv,v,await rcon(`set ${dv} ${v}`));
}
// Cheat-protected SERVER dvars (bot tuning, timescale) go through the GSC bridge, not a raw
// `set`: GSC setDvar runs with engine authority and is NOT cheat-gated, so these keep working on
// the dedicated VPS with sv_cheats 0. The bridge also mirrors the value into a plain gf_<dvar>
// dvar, which is what 💾 Save persists to dedicated.cfg — a cfg `set sv_botFov 50` line would be
// cheat-refused at startup exactly like an rcon one, so the mirror is the only thing that CAN
// persist. gf_bridgeApplyServerDvars() copies the mirrors back each round.
async function bridgeSvSet(dv,id){
  const v=g(id).value;
  const ok=await bridge(`svset_${dv}=${v}`,`${dv} = ${v}`);
  if(ok){ toast(dv+'='+v+' (bridge)','ok'); actLog(dv+' → '+v+' (GSC bridge — cheat-protected)','ok'); }
  return ok;
}
// Set two dvars to the same value in one chained send (used by rows with an `also:` dvar,
// e.g. Friendly Fire = scr_team_fftype + the scr_gf_team_fftype live override — the engine
// re-polls the override every ~5s, so the change lands mid-match without a restart).
async function sdvv2(dv,dv2,v){
  const r=await batchCmds([`set ${dv} ${v}`,`set ${dv2} ${v}`],50);
  r&&r.ok?(toast(dv+'='+v,'ok'),actLog(dv+' + '+dv2+' → '+v,'ok')):toast('Set failed','err');
}
// Toggle that owns BOTH a sticky dvar and a live GSC-bridge flag (killstreaks, headshots,
// radar): one switch sets the dvar (sticks for next rounds / 💾 Save) AND fires the bridge
// so the running round changes immediately.
async function togDvarBridge(el,dv,prefix){
  const on=el.checked;
  sdvv(dv,on?'1':'0');
  bridge(prefix+'_'+(on?'on':'off'));
}
// Pure bridge on/off toggle (no dvar behind it), for data-driven rows (type:'bridgetog').
function bridgeTog(el,prefix){ bridge(prefix+'_'+(el.checked?'on':'off')); }
async function doPause(){
  const btn=g('pauseBtn');
  const want=paused?'resume':'pause';
  const ok=await bridge(want,want==='pause'?'Pause match':'Resume match');
  if(ok){
    paused=!paused;
    btn.textContent=paused?'▶  RESUME MATCH':'⏸  PAUSE MATCH';
    btn.className=paused?'b-ok b-lg ctrl':'b-wn b-lg ctrl';
    actLog(paused?'Match paused':'Match resumed',paused?'wn':'ok');
    toast(paused?'Paused':'Resumed',paused?'wn':'ok');
  }
}
async function endRound(team){
  const ok=await bridge('endround_'+team,'End round → '+team);
  if(ok){ actLog('End round → '+team,'wn'); toast('Ending round — '+team,'info'); }
}
// ─── Lobby hold (pre-prematch) ────────────────────────────────────────────────
// The GSC gate holds the FIRST round before the prematch countdown when Lobby Hold=Manual
// (or a load / min-players hold is up). gf_state's 7th field (lobbyHold) tells us it's live;
// we reveal START MATCH so the admin can arrange teams, then release it via bridge lobbystart.
let _lobbyHold=false;
async function startMatch(){
  const ok=await bridge('lobbystart','Start match');
  if(ok){ actLog('Start match — release lobby hold','ok'); toast('Starting match…','info'); }
}
function setLobbyHold(active){
  active=!!active;
  if(active===_lobbyHold)return;   // churn guard — poll fires every 2.5s
  _lobbyHold=active;
  const b=g('startBtn'); if(b) b.style.display=active?'':'none';
}
async function cmd(c){
  const r=await rcon(c);
  r.ok?(actLog(c,'in'),clogAdd(r.response||'(ok)','li')):toast(r.error,'err');
}

// ─── Bridge helper (seq-stamped, ack-tracked) ─────────────────────────────────
// Each bridge command is stamped "<seq>:<cmd>" so the GSC bridge can echo the seq back in gf_ack.
// The command shows in the bottom-left queue as ⏳ "sent" instantly, then flips to ✓ "received"
// (with round-trip ms) once the ack lands — or ✗ if it never does. High-priority lane so the
// click jumps ahead of background status/score polling.
let _cmdSeq=parseInt(localStorage.getItem('gf_cmdseq')||'0')||0;
// On connect, lift our seq counter above the game's current gf_ack. Without this, a panel whose
// localStorage was cleared could send seq 1 while the game still reports a higher ack from an
// earlier session, which would mark the new command "received" before it was even processed.
async function seedCmdSeq(){
  try{
    const c=conn();const p=new URLSearchParams({host:c.host,port:c.port,password:c.password});
    const r=await (await fetch(API+'/ack?'+p)).json();
    if(r.ok && r.ack>=_cmdSeq){ _cmdSeq=r.ack; localStorage.setItem('gf_cmdseq',String(_cmdSeq)); }
  }catch(_){}
}
async function bridge(bcmd,label){
  const seq=++_cmdSeq; localStorage.setItem('gf_cmdseq',String(_cmdSeq));
  cqAdd(seq,label||bcmd,bcmd);
  ensureAckPoll();
  const r=await rcon(`set gf_cmd ${seq}:${bcmd}`,true);
  if(!r.ok){ cqFail(seq,r.error||'send failed'); toast('Bridge error: '+r.error,'err'); return false; }
  return true;
}

// ─── Command queue (sent → received tracker, with auto-retry) ─────────────────
// Auto-retry: an unacked command is resent with the SAME seq up to CQ_MAX_TRIES times, ~CQ_RETRY_AFTER
// apart, to self-heal a dropped rcon packet. Safe because the GSC bridge dedups by seq (a resend of an
// already-processed command is re-acked, not re-run) — so even endround/quake never double-fire.
const CQ_MAX=6, CQ_RETRY_AFTER=1500, CQ_MAX_TRIES=3;
const _cmdQ=[];   // newest first: {seq,label,bcmd,t0,tSent,tries,state:'sent'|'ack'|'timeout'|'fail',ms,err}
function cqAdd(seq,label,bcmd){ _cmdQ.unshift({seq,label,bcmd,t0:Date.now(),tSent:Date.now(),tries:1,state:'sent',ms:0}); if(_cmdQ.length>CQ_MAX)_cmdQ.length=CQ_MAX; cqRender(); }
function cqResolve(ack){
  let ch=false;
  for(const e of _cmdQ) if(e.state==='sent'&&e.seq<=ack){ e.state='ack'; e.ms=Date.now()-e.t0; ch=true; cqScheduleRemove(e.seq,4000); }
  if(ch)cqRender();
}
function cqTimeout(seq){ const e=_cmdQ.find(x=>x.seq===seq); if(e&&e.state==='sent'){ e.state='timeout'; cqRender(); cqScheduleRemove(seq,6000); } }
function cqFail(seq,err){ let e=_cmdQ.find(x=>x.seq===seq); if(!e){ cqAdd(seq,'cmd'); e=_cmdQ.find(x=>x.seq===seq); } if(e){ e.state='fail'; e.err=err; cqRender(); cqScheduleRemove(seq,6000); } }
function cqScheduleRemove(seq,delay){ setTimeout(()=>{ const i=_cmdQ.findIndex(x=>x.seq===seq); if(i>=0){ _cmdQ.splice(i,1); cqRender(); } }, delay); }
function cqRender(){
  const c=g('cmdq'); if(!c)return;
  if(!_cmdQ.length){ c.className='cmdq'; c.innerHTML=''; return; }
  c.className='cmdq on';
  c.innerHTML=_cmdQ.map(e=>{
    const ic=e.state==='ack'?'✓':e.state==='timeout'?'✗':e.state==='fail'?'⚠':'⏳';
    const st=e.state==='ack'?(e.ms?('received · '+(e.ms/1000).toFixed(1)+'s'):'confirmed')
            :e.state==='timeout'?'no ack (timeout)'
            :e.state==='fail'?('failed'+(e.err?' · '+e.err:''))
            :('sent…'+(e.tries>1?(' · retry '+e.tries+'/'+CQ_MAX_TRIES):''));
    return `<div class="cq-row cq-${e.state}"><span class="cq-ic">${ic}</span><span class="cq-lbl">${x(e.label||'cmd')}</span><span class="cq-st">${x(st)}</span></div>`;
  }).join('');
}
// Ack poll: runs only while a command is pending. Reads gf_ack (high-priority lane) and resolves
// every queued command whose seq ≤ the ack; marks any still-unacked command timed out after ~3.5s.
let _ackPoll=null,_ackBusy=false;
function ensureAckPoll(){ if(_ackPoll)return; _ackPoll=setInterval(ackTick,450); ackTick(); }
async function ackTick(){
  if(!_cmdQ.some(e=>e.state==='sent')){ clearInterval(_ackPoll); _ackPoll=null; return; }
  const now=Date.now();
  // Listen server: single-token telemetry reads (gf_ack, like gf_state) time out there, so we can't
  // measure a real round-trip. The command still executed — confirm optimistically a beat after send.
  if(_listenServer){
    let ch=false;
    for(const e of _cmdQ) if(e.state==='sent'&&now-e.t0>500){ e.state='ack'; e.ms=0; ch=true; cqScheduleRemove(e.seq,4000); }
    if(ch)cqRender();
    return;
  }
  // Read the ack (high-priority lane) and resolve any commands it covers.
  if(!_ackBusy&&live){
    _ackBusy=true;
    try{
      const c=conn();const p=new URLSearchParams({host:c.host,port:c.port,password:c.password});
      const r=await (await fetch(API+'/ack?'+p)).json();
      if(r.ok) cqResolve(r.ack);
    }catch(_){}
    finally{ _ackBusy=false; }
  }
  // Auto-retry unacked commands (dropped-packet self-heal), then give up after the last try's window.
  let ch=false;
  for(const e of _cmdQ){
    if(e.state!=='sent') continue;
    if(Date.now()-e.tSent < CQ_RETRY_AFTER) continue;   // still within this attempt's ack window
    if(e.tries < CQ_MAX_TRIES && e.bcmd){
      e.tries++; e.tSent=Date.now(); ch=true;
      rcon(`set gf_cmd ${e.seq}:${e.bcmd}`,true).catch(()=>{});   // same seq → GSC dedups, never double-runs
    }else if(Date.now()-e.t0 > CQ_RETRY_AFTER*CQ_MAX_TRIES + 600){
      cqTimeout(e.seq);
    }
  }
  if(ch)cqRender();
}
// FUN tab: broadcast a chat-style bold message to all players via gf_say + saymsg.
// Both sets go in ONE chained rcon command so gf_say is guaranteed set in the same server
// execution as gf_cmd=saymsg — two separate packets raced on the rate-limited server and the
// gf_say one could drop, leaving the bridge to print an empty message (i.e. nothing). Strip
// quotes/semicolons/backslashes so the message can't break out of the chained command.
async function broadcastMsg(){
  const inp=g('vSay'),m=inp.value.trim().replace(/["'`;\\]/g,'');
  if(!m){toast('Enter a message','err');return;}
  const r=await batchCmds([`set gf_say "${m}";set gf_cmd saymsg`],60);
  if(r&&r.ok){toast('Broadcast sent','ok');actLog('Broadcast: '+m,'in');inp.value='';}
  else toast('Broadcast failed','err');
}

// ─── Perks ─────────────────────────────────────────────────────────────────
// Perks the GF loadout already grants every spawn. Toggling one of these OFF
// goes in the force-OFF list; toggling a non-base perk ON goes in force-ON.
// The loadout applies base perks, then ON list, then OFF list (OFF wins).
// Mirror of the hardcoded base perk set in _gf_loadouts.gsc gf_giveCustomLoadout (every player
// gets these). Keep in sync with that SetPerk list — a base perk renders checked and unchecking it
// adds it to gf_perk_off to remove it; a non-base perk checked adds it to gf_perk_on.
const BASE_PERKS=['specialty_movefaster','specialty_fallheight','specialty_longersprint','specialty_armorvest','specialty_flakjacket','specialty_shades','specialty_stunprotection'];
async function perkTog(){
  const on=[],off=[];
  document.querySelectorAll('[data-perk]').forEach(cb=>{
    const p=cb.getAttribute('data-perk'),base=BASE_PERKS.includes(p);
    if(cb.checked&&!base)on.push(p);
    else if(!cb.checked&&base)off.push(p);
  });
  const r=await batchCmds([
    `set gf_perk_on ${on.length?on.join(','):'""'}`,
    `set gf_perk_off ${off.length?off.join(','):'""'}`,
    `set gf_cmd perksync`
  ],60);
  if(r&&r.ok){toast('Perks updated','ok');actLog(`Perks +${on.length} / -${off.length}`,'ok');}
  else toast('Perk update failed','err');
}
function perkReset(){
  document.querySelectorAll('[data-perk]').forEach(cb=>{cb.checked=BASE_PERKS.includes(cb.getAttribute('data-perk'));});
  perkTog();actLog('Perks reset to GF default','in');
}

// ─── Bots ────────────────────────────────────────────────────────────────────
async function addBot(){const ok=await bridge('botadd','Bot added');if(ok){actLog('Bot added','ok');toast('Bot added','ok');}}
async function kickBots(){
  const sr=await fetchStatus();
  if(!sr||!sr.ok){toast('Could not read status','err');return;}
  const bots=sr.players.filter(p=>p.bot);
  if(!bots.length){toast('No bots to kick','info');return;}
  for(const b of bots) await rcon(`clientkick ${b.num}`);
  actLog(`Kicked ${bots.length} bot(s)`,'wn');toast(`Kicked ${bots.length} bot(s)`,'ok');
}
async function applyFillN(){
  // Clamp to the same 0-6 the server clamps to (HTML max= only limits the spinner, not a typed value),
  // so the input, the sent value and the telemetry echo can never disagree.
  const n=Math.max(0,Math.min(6,parseInt(g('vFillN').value)||0));
  g('vFillN').value=n;
  const r=await rcon(`set gf_fill_n ${n}`);
  const lbl=n>0?(n+'v'+n):'off';
  r.ok?(actLog('Fill → '+lbl,'ok'),toast('Fill → '+lbl,'ok')):toast('Failed','err');
}
// Reflect live fill state (from gf_state fields 8-11) in the BOT MANAGEMENT readout, and seed the
// input from the live value unless the admin is editing it. fillN null = server predates fill telemetry.
function updateFillReadout(s){
  const el=g('fillReadout'); if(!el) return;
  if(s.fillN===null||s.fillN===undefined){ el.textContent=''; return; }
  const inp=g('vFillN');
  if(inp && document.activeElement!==inp) inp.value=s.fillN;
  el.textContent = s.fillN<=0 ? 'off'
    : `${s.fillN}v${s.fillN} · now ${s.playAllies}v${s.playAxis}`+(s.parked?` · ${s.parked} parked`:'');
}
// Even out the teams via the GSC bridge. Server-side pick (bots first) + safe apply (immediate in
// prematch/lobby, deferred to next round mid-round). Feedback is the private bridge notify in-game.
async function balanceTeams(){
  const ok=await bridge('balanceteams','Balance teams');
  if(ok){ actLog('Balance teams','ok'); toast('Balancing teams…','info'); }
}
// Per-team add/remove via the GSC bridge (botadd_<team> / botkick_<team>). Server-side so it
// works on listen + dedicated and uses authoritative team data. Only STICKS with Fill (per team)
// at 0 — with fill on, the reconciler owns bot placement and re-derives it.
async function botTeam(act,team){
  const ok=await bridge(`bot${act}_${team}`);
  if(ok){
    const lbl=(act==='add'?'Add':'Kick')+' bot '+(act==='add'?'→ ':'from ')+team;
    actLog(lbl,act==='add'?'ok':'wn');toast(lbl,'info');
  }
}
async function botDiff(d){
  const ok=await bridge(`botdiff_${d}`);
  if(ok){
    ['easy','normal','hard','fu'].forEach(k=>g('d-'+k).classList.toggle('sel',k===d));
    actLog('Bot diff: '+d.toUpperCase(),'ok');toast('Bot diff: '+d.toUpperCase(),'info');
  }
}

// ─── Maps ────────────────────────────────────────────────────────────────────
const MAP_BY_ID={}; MAPS.forEach(m=>MAP_BY_ID[m.id]=m);
function mapName(id){return (MAP_BY_ID[id]&&MAP_BY_ID[id].n)||id;}
function buildMapGrid(){
  g('mgrid').innerHTML=MAPS.map(m=>{
    const bs=(m.gf?'<span class="mb gfb">GF ★</span>':'')+(m.dlc?'<span class="mb dlcb">DLC</span>':'');
    return`<div class="mt${m.gf?' mgf':''}" id="mt-${m.id}" data-gf="${m.gf}" onclick="rotAdd('${m.id}')" title="Add ${m.n} to the rotation">
      <div class="mn">${m.n} <span class="mt-live" id="mtl-${m.id}" style="display:none">● LIVE</span></div><div class="mi">${m.id}</div><div class="mbs">${bs}</div></div>`;
  }).join('');
}
function mf(f){
  g('fall').classList.toggle('active',f==='all');g('fgf').classList.toggle('active',f==='gf');
  document.querySelectorAll('.mt').forEach(t=>t.classList.toggle('hidden',f==='gf'&&t.dataset.gf!=='1'));
}
// Highlight the current live map on the palette grid (● LIVE badge + border).
function markCurrentMap(map){
  const cur=(map||'').toLowerCase();
  MAPS.forEach(m=>{
    const is=m.id.toLowerCase()===cur;
    const tile=g('mt-'+m.id), lbl=g('mtl-'+m.id);
    if(tile)tile.classList.toggle('mt-cur',is);
    if(lbl)lbl.style.display=is?'':'none';
  });
}
// Wager gametypes (codes match the "— Wager —" group in GT_OPTS) need
// xblive_wagermatch 1 set BEFORE the map loads — the map's main() reads it to pick
// the wager minimap + framework, and Plutonium never sets it itself. Everything
// else, Gunfight included, must be 0. So every gametype/map switch sets the flag
// first. (gf.gsc also force-resets it to 0 as a belt-and-suspenders.)
const WAGER_GTS=['gun','oic','shrp','hlnd'];
function wagerFlag(gt){return WAGER_GTS.indexOf(gt)>=0?'1':'0';}
async function setGt(){await sdvv('xblive_wagermatch',wagerFlag(_gtVal));await sdvv('g_gametype',_gtVal);}

// ─── Map rotation editor ──────────────────────────────────────────────────────
// Reads/edits the LIVE server rotation directly (sv_maprotation) instead of the old browser-side
// queue that reactively fired `map` AFTER the engine had already rotated (the double-load / wrong-
// map-flash that felt "too late"). Saving writes sv_maprotation + sv_maprotationcurrent so the new
// order drives the engine's own next rotation — one clean load, no flash.
async function fetchMapRotation(){
  const c=conn();const p=new URLSearchParams({host:c.host,port:c.port,password:c.password});
  return (await fetch(API+'/maprotation?'+p)).json();
}
async function loadRotation(force){
  if(!live)return;
  let d; try{ d=await fetchMapRotation(); }catch(_){ if(force)toast('Rotation read failed','err'); return; }
  if(!d||!d.ok){ if(force)toast('Could not read rotation','err'); return; }
  rotation=(d.rotation||[]).map(e=>({gametype:e.gametype||'gf',map:e.map}));
  rotCurrentHead=(d.current&&d.current.length)?d.current[0].map:(rotation[0]?rotation[0].map:'');
  rotLoadedSig=rotSig();
  renderRotation();
  if(force)toast('Rotation loaded ('+rotation.length+' maps)','ok');
}
function rotSig(){return rotation.map(e=>e.gametype+':'+e.map).join('|');}
function renderRotation(){
  const el=g('rotList'); if(!el)return;
  const cur=(lastMap||'').toLowerCase();
  const dirty=rotSig()!==rotLoadedSig;
  g('rotDirty').style.display=dirty?'':'none';
  if(!rotation.length){
    el.innerHTML='<div class="rot-empty">Rotation is empty — click a map below to add it, then Save Order.</div>';
    g('rotStatus').textContent=''; return;
  }
  g('rotStatus').textContent=rotation.length+' maps';
  let nextShown=false;
  el.innerHTML=rotation.map((e,i)=>{
    const isCur=e.map.toLowerCase()===cur;
    const isNext=!isCur && !nextShown && rotCurrentHead!=='' && e.map===rotCurrentHead;
    if(isNext)nextShown=true;
    const badge=isCur?'<span class="ri-badge">● LIVE</span>':(isNext?'<span class="ri-badge">NEXT</span>':'');
    return `<div class="ri${isCur?' cur':''}${isNext?' next':''}">
      <span class="ri-idx">${i+1}</span>
      <span class="ri-map">${mapName(e.map)}<span class="ri-id">${e.map}</span></span>
      <span class="ri-gt">${e.gametype}</span>${badge}
      <span class="ri-btns">
        <button class="ri-nx" title="Play next — sets sv_maprotationcurrent so this loads at the next match end (no flash)" onclick="rotPlayNext(${i})">⏭</button>
        <button class="ri-now" title="Load this map NOW (hard change, resets the current match)" onclick="rotLoadNow(${i})">▶</button>
        <button title="Move up" onclick="rotMove(${i},-1)">↑</button>
        <button title="Move down" onclick="rotMove(${i},1)">↓</button>
        <button class="ri-rm" title="Remove from rotation" onclick="rotRemove(${i})">✕</button>
      </span></div>`;
  }).join('');
}
function rotAdd(id){
  const gt=_gtVal||'gf';
  rotation.push({gametype:gt,map:id});
  renderRotation();
  actLog('Added to rotation: '+mapName(id)+' ('+gt+')','in');
  toast('Added '+mapName(id)+' — Save Order to apply','info');
}
function rotMove(i,dir){
  const j=i+dir; if(j<0||j>=rotation.length)return;
  const t=rotation[i]; rotation[i]=rotation[j]; rotation[j]=t;
  renderRotation();
}
function rotRemove(i){ rotation.splice(i,1); renderRotation(); }
// Serialize back to a rotation string. Omit the `gametype` token when an entry has none, so a
// server whose rotation is the bare `map X map Y` form (no per-entry gametype — relies on
// g_gametype) round-trips unchanged instead of getting malformed `gametype  map X` (empty gametype).
// Grid-added entries carry _gtVal (e.g. 'gf') so they emit an explicit `gametype gf map X`.
function buildRotStr(entries){return entries.map(e=>e.gametype?`gametype ${e.gametype} map ${e.map}`:`map ${e.map}`).join(' ');}
// The remainder to write to sv_maprotationcurrent so the edited order takes effect from the NEXT
// map while the current one keeps running: everything AFTER the current map's slot (or the whole
// list if the current map isn't in the rotation). Empty → engine refills from sv_maprotation.
function rotRemainderAfterCurrent(){
  const cur=(lastMap||'').toLowerCase();
  const idx=rotation.findIndex(e=>e.map.toLowerCase()===cur);
  return idx>=0?rotation.slice(idx+1):rotation.slice(0);
}
async function rotSaveOrder(){
  if(!rotation.length){toast('Rotation is empty','info');return;}
  const full=buildRotStr(rotation);
  const rest=rotRemainderAfterCurrent();
  // Write the persistent template AND the live remainder. Writing only sv_maprotation would defer
  // the change a whole cycle (the engine drains sv_maprotationcurrent first); writing the remainder
  // too makes the new order effective on the very next rotation.
  const r=await batchCmds([`set sv_maprotation "${full}"`,`set sv_maprotationcurrent "${buildRotStr(rest)}"`],150);
  if(r&&r.ok){
    rotLoadedSig=rotSig();
    rotCurrentHead=rest.length?rest[0].map:(rotation[0]?rotation[0].map:'');
    renderRotation();
    actLog('Saved rotation ('+rotation.length+' maps) — live','ok');
    toast('Rotation saved (live)','ok');
    return true;
  }
  toast('Save failed','err'); return false;
}
async function rotSaveOrderCfg(){
  if(!(await rotSaveOrder()))return;
  const r=await saveCfgDvars({sv_maprotation:buildRotStr(rotation)});
  if(r&&r.ok){actLog('Saved rotation to dedicated.cfg ('+r.updated+' updated, '+r.added+' added)','ok');toast('Saved to dedicated.cfg','ok');}
  else toast('cfg save failed: '+((r&&r.error)||'?'),'err');
}
// Set an entry as the next map WITHOUT loading now: sv_maprotationcurrent = the order starting at
// entry i. The engine loads it at the next match end (exitLevel → map_rotate) — one clean load.
async function rotPlayNext(i){
  if(i<0||i>=rotation.length)return;
  const rest=rotation.slice(i);
  const r=await rcon(`set sv_maprotationcurrent "${buildRotStr(rest)}"`,true);
  if(r&&r.ok){
    rotCurrentHead=rotation[i].map; renderRotation();
    actLog('Next map → '+mapName(rotation[i].map)+' (loads on match end)','ok');
    toast('Next: '+mapName(rotation[i].map),'ok');
  } else toast('Failed','err');
}
// Advance the engine's rotation NOW. `map_rotate` consumes the head of sv_maprotationcurrent — i.e.
// loads exactly the map badged NEXT — via the same code path the engine takes at match end, so there
// is no wrong-map flash and the rotation position stays consistent (unlike a hard `map <id>`, which
// jumps without consuming the remainder). Ends the live match, so it confirms first.
async function rotSkipNow(){
  const nm=rotCurrentHead?mapName(rotCurrentHead):'the next map in rotation';
  if(!confirm('Play '+nm+' now?\n\nThis ends the current match immediately and advances the rotation.'))return;
  const r=await rcon('map_rotate',true);
  if(r&&r.ok){
    actLog('map_rotate → '+nm+' (now)','ok');
    toast('Loading '+nm+'…','info');
    // The engine consumed the head; refresh once the new map is up (pollTick's map-change hook also
    // refreshes, but only while this tab is open — this covers the immediate case).
    setTimeout(()=>{ if(live) loadRotation(); },4000);
  } else toast('Failed','err');
}
// Hard-load an entry immediately (resets the current match). Sets the wager flag + gametype first.
async function rotLoadNow(i){
  if(i<0||i>=rotation.length)return;
  const e=rotation[i];
  const r=await batchCmds([`set xblive_wagermatch ${wagerFlag(e.gametype)}`,`set g_gametype ${e.gametype}`,`map ${e.map}`],200);
  r.ok?(actLog('Map → '+mapName(e.map)+' ('+e.gametype+') now','ok'),toast('Loading '+mapName(e.map)+'…','info')):toast('Failed','err');
}

// ─── Mods ────────────────────────────────────────────────────────────────────
function sv(sid,vid){g(vid).value=g(sid).value;}
function su(vid,sid,mn,mx){
  let v=parseFloat(g(vid).value);
  v=Math.max(mn,Math.min(mx,v||0));
  g(sid).value=v;
}
async function resetDv(dv,def,vid,sid){
  g(vid).value=def;g(sid).value=def;
  await sdvv(dv,def);
}
async function visBridge(prefix,vid){
  const v=g(vid).value;
  const ok=await bridge(prefix+v);
  if(ok) actLog(prefix.replace('_','')+'='+v,'ok');
}
async function visReset(prefix,def,vid,sid){
  // "stock" clears the gf_vis_* persistence server-side and one-shots the engine
  // default to players in the session; def is that engine default (for the UI).
  g(vid).value=def;if(sid)g(sid).value=def;
  await bridge(prefix+'stock');
  actLog(prefix.replace('_','')+'=stock','ok');
}
async function visResetAll(){
  const ok=await bridge('visreset');
  g('sAmb').value=g('vAmb').value=0;
  g('sGridI').value=g('vGridI').value=1;
  g('sGridC').value=g('vGridC').value=0;
  g('cbFog').checked=true;g('cbHDR').checked=true;
  if(ok){actLog('Visuals reset to stock','ok');toast('Visuals reset to stock','ok');}
}
async function toggleFallDmg(){
  const on=g('cbFall').checked;
  await batchCmds([`set bg_fallDamageMinHeight ${on?256:9999}`,`set bg_fallDamageMaxHeight ${on?512:9999}`],50);
  actLog('Fall damage '+(on?'ON':'OFF'),on?'ok':'wn');
}
// ─── Dev ─────────────────────────────────────────────────────────────────────
async function customDv(){
  const n=g('dvName').value.trim(),v=g('dvVal').value.trim();
  if(!n)return;
  await sdvv(n,v);
}
async function readDv(){
  const n=g('dvName').value.trim();if(!n)return;
  const r=await rcon(n);
  if(r.ok){clogAdd(r.response,'li');tab('con');}
  else toast(r.error,'err');
}

// ─── Client binds (clipboard helpers — these run on the player's machine, not the server) ──
const MOUSE2_ADS = 'bind MOUSE2 "+speed_throw; -breath_sprint; -sprint"';
const SPRINT_ADS_FIX = 'bind SHIFT "+breath_sprint"\n'+MOUSE2_ADS;
const DEBUG_DVARS = 'com_drawFps 1\ndeveloper 1\ncl_showSnaps 1';
async function copyText(text){
  try{ if(navigator.clipboard&&navigator.clipboard.writeText){ await navigator.clipboard.writeText(text); return true; } }catch(_){}
  try{ const ta=document.createElement('textarea');ta.value=text;ta.style.position='fixed';ta.style.opacity='0';
    document.body.appendChild(ta);ta.focus();ta.select();const ok=document.execCommand('copy');document.body.removeChild(ta);return ok;
  }catch(_){ return false; }
}
async function copyMouse2Ads(){
  if(await copyText(MOUSE2_ADS)){
    toast('MOUSE2 ADS bind copied — paste into the in-game console','ok');
    actLog('Copied MOUSE2 ADS bind to clipboard','in');
    clogAdd(MOUSE2_ADS,'ls');
  } else toast('Clipboard copy failed','err');
}
async function copySprintAdsFix(){
  if(await copyText(SPRINT_ADS_FIX)){
    toast('Sprint-ADS Fix (MOUSE2 + SHIFT) copied — paste into the in-game console','ok');
    actLog('Copied Sprint-ADS Fix binds (MOUSE2 + SHIFT) to clipboard','in');
    clogAdd(SPRINT_ADS_FIX,'ls');
  } else toast('Clipboard copy failed','err');
}
async function copyClientDvar(dv,val){
  const cmd=dv+' '+val;
  if(await copyText(cmd)){
    toast('Copied "'+cmd+'" — paste into your in-game console','ok');
    actLog('Copied client cmd: '+cmd,'in');
    clogAdd(cmd,'ls');
  } else toast('Clipboard copy failed','err');
}
async function copyExecAutoexec(){
  if(await copyText('exec autoexec')){
    toast('"exec autoexec" copied — paste into the in-game console','ok');
    actLog('Copied "exec autoexec" to clipboard','in');
    clogAdd('exec autoexec','ls');
  } else toast('Clipboard copy failed','err');
}
async function copyDebugDvars(){
  if(await copyText(DEBUG_DVARS)){
    toast('Debug dvars copied — paste into the in-game console','ok');
    actLog('Copied debug dvars to clipboard','in');
    clogAdd(DEBUG_DVARS,'ls');
  } else toast('Clipboard copy failed','err');
}

// ─── Console ─────────────────────────────────────────────────────────────────
function clogAdd(t,cls){
  const el=g('clog'),d=document.createElement('div');
  d.className='ll '+cls;d.textContent=t||'(empty)';el.appendChild(d);el.scrollTop=el.scrollHeight;
}
function cClear(){g('clog').innerHTML='';}
async function cSend(){
  const inp=g('cin'),c=inp.value.trim();if(!c)return;
  hist.unshift(c);if(hist.length>100)hist.length=100;histI=-1;inp.value='';
  clogAdd(c,'lo');
  try{const r=await rcon(c);r.ok?clogAdd(r.response||'(ok)','li'):clogAdd(r.error,'le');}
  catch(e){clogAdd(e.message,'le');}
}
function qc(c){g('cin').value=c;tab('con');cSend();}
function qf(c){tab('con');const inp=g('cin');inp.value=c;inp.focus();}
function cKey(e){
  const inp=g('cin');
  if(e.key==='Enter'){cSend();return;}
  if(e.key==='ArrowUp'){e.preventDefault();histI=Math.min(histI+1,hist.length-1);if(hist[histI]!=null)inp.value=hist[histI];}
  if(e.key==='ArrowDown'){e.preventDefault();histI=Math.max(histI-1,-1);inp.value=histI===-1?'':hist[histI];}
}

// ─── Activity log ─────────────────────────────────────────────────────────────
const MAX_ACT=30;const actEntries=[];
function actLog(msg,cls='in'){
  const now=new Date();
  const ts=String(now.getHours()).padStart(2,'0')+':'+String(now.getMinutes()).padStart(2,'0')+':'+String(now.getSeconds()).padStart(2,'0');
  actEntries.unshift({ts,msg,cls});
  if(actEntries.length>MAX_ACT)actEntries.length=MAX_ACT;
  renderAct();
}
function renderAct(){
  g('actEntries').innerHTML=actEntries.map(a=>
    `<div class="al-entry"><span class="al-time">${a.ts}</span><span class="al-msg al-${a.cls}">${x(a.msg)}</span></div>`
  ).join('');
}

// ─── Player join/leave notifications ─────────────────────────────────────────
// Diff the real-player set (bots excluded) each status tick. First tick after a
// connect seeds the baseline silently so already-connected players aren't announced;
// afterwards a new key -> "joined", a vanished key -> "left". Keyed by GUID (stable
// across reconnects/name changes), falling back to name for the rare guid-less case.
let _knownPlayers=null;   // Map(key -> name); null until seeded, reset on disconnect
function _pKey(p){ return (p.guid && p.guid!=='0') ? 'g:'+p.guid : 'n:'+p.name; }
function notifyJoins(players){
  const real=(players||[]).filter(p=>!p.bot);
  const cur=new Map(real.map(p=>[_pKey(p),p.name]));
  if(_knownPlayers===null){ _knownPlayers=cur; return; }   // seed silently
  for(const [k,nm] of cur){
    if(!_knownPlayers.has(k)){
      actLog(nm+' joined','ok');
      toast(nm+' joined','ok');
      joinBeep();
      desktopNotify('Player joined', nm+' connected');
    }
  }
  for(const [k,nm] of _knownPlayers){
    if(!cur.has(k)) actLog(nm+' left','wn');
  }
  _knownPlayers=cur;
}
let _ac=null;
function joinBeep(){
  try{
    const AC=window.AudioContext||window.webkitAudioContext; if(!AC)return;
    _ac=_ac||new AC(); if(_ac.state==='suspended') _ac.resume();
    const t=_ac.currentTime, o=_ac.createOscillator(), gn=_ac.createGain();
    o.type='sine'; o.frequency.setValueAtTime(660,t); o.frequency.setValueAtTime(990,t+0.09);
    gn.gain.setValueAtTime(0.0001,t);
    gn.gain.exponentialRampToValueAtTime(0.12,t+0.02);
    gn.gain.exponentialRampToValueAtTime(0.0001,t+0.28);
    o.connect(gn); gn.connect(_ac.destination); o.start(t); o.stop(t+0.3);
  }catch(_){}
}
function reqNotifyPerm(){
  try{ if(window.Notification && Notification.permission==='default') Notification.requestPermission(); }catch(_){}
}
function desktopNotify(title,body){
  try{ if(window.Notification && Notification.permission==='granted') new Notification(title,{body,icon:'ops.png',silent:true}); }catch(_){}
}

// ─── Toasts ──────────────────────────────────────────────────────────────────
function toast(msg,type='info'){
  const c=g('toasts'),d=document.createElement('div');
  d.className='toast '+(type==='ok'?'ok':type==='err'?'err':type==='wn'?'wn':'info');
  d.textContent=msg;c.appendChild(d);
  setTimeout(()=>{d.style.opacity='0';d.style.transition='opacity .3s';},2600);
  setTimeout(()=>d.remove(),2900);
}

// ─── Helper ──────────────────────────────────────────────────────────────────
function g(id){return document.getElementById(id);}

// ─── Init ─────────────────────────────────────────────────────────────────────
loadCfg();
buildMapGrid();
setCtrl(false);
clogAdd('GF RCON Tool ready. Enter server details and click Connect.','ls');
renderAct();
renderRotation();

// ─── Server CFG panel ────────────────────────────────────────────────────────
const SRV_SECTIONS = [
  { title: 'GENERAL', eff: 'live', per: 'dvar', vars: [
    { n:'g_password',               lbl:'Join Password',          type:'text',   def:'',    tip:'g_password\nServer join password. Blank = open to all.' },
    { n:'g_allowvote',              lbl:'Allow Voting',           type:'tog',    def:'1',   tip:'g_allowvote\nLet players call /callvote in console. GF default: 1' },
    { n:'g_inactivity',             lbl:'AFK Kick Timer (s)',     type:'num',    def:'190', tip:'g_inactivity\nSeconds of inactivity before auto-kick. 0 = disabled.' },
    { n:'party_minplayers',         lbl:'Lobby Min Players (pregame)', type:'num', def:'2',   tip:'party_minplayers\nEngine PREGAME-lobby dvar — does NOT gate the Gunfight match (stock waitForPlayers() is an empty stub; party_minplayers only affects the _pregame lobby gametype + the wager bet calc). For Gunfight’s min-players-to-start, use Min Players in ADVANCED → MATCH START (scr_gf_min_players). Left here for non-gf gametypes.' },
    { n:'sv_maxclients',            lbl:'Max Players',            type:'num',    def:'14',  eff:'restart', tip:'sv_maxclients\nMaximum simultaneous connections the server accepts. GF: 14 = 12 playing (up to 6v6) + 2 spectator headroom.' },
    { n:'sv_floodProtect',          lbl:'Chat Flood Protection',  type:'num',    def:'4',   tip:'sv_floodProtect\nThrottle rapid chat messages. Set to 20 when using an RCON tool.' },
    { n:'sv_kickBanTime',           lbl:'Kick Ban Duration (s)',  type:'num',    def:'300', tip:'sv_kickBanTime\nHow long a kicked player must wait before reconnecting.' },
    { n:'sv_maxPing',               lbl:'Max Ping (0=any)',       type:'num',    def:'0',   tip:'sv_maxPing\nKick players whose ping exceeds this. 0 = no limit.' },
    { n:'sv_pure',                  lbl:'Pure Server',            type:'tog',    def:'0',   eff:'restart', tip:'sv_pure\nVerify client files match server files. Blocks modded clients.' },
    // def '1' (was '0'): the shipped dedicated.cfg blocks the console, and a WRONG default here is
    // dangerous — if the connect-sweep read misses this dvar the row keeps its default, and Set All /
    // 💾 Save would then push it, silently re-opening the console on a live public server. Defaults
    // for security dvars must match the hardened cfg, never the engine default. (Set All now also
    // skips .unsynced rows, so a missed read can't be written back at all — belt and braces.)
    { n:'sv_disableClientConsole',  lbl:'Block Player Console',   type:'tog',    def:'1',   tip:'sv_disableClientConsole\n1 = players cannot open the in-game console. SHIPPED DEFAULT: 1.\nThis is the main thing standing between a player and any cheat-protected command, so leave it ON for a public lobby.' },
    { n:'sv_doubleCoDPoints',       lbl:'Double CoD Points',      type:'tog',    def:'1',   tip:'sv_doubleCoDPoints\nAward double CoD Points for completed matches.' },
    { n:'sv_voice',                 lbl:'Voice Chat',             type:'tog',    def:'1',   tip:'sv_voice\nEnable in-game voice chat.' },
    { n:'sv_voicequality',          lbl:'Voice Quality (1–9)',    type:'num',    def:'9',   tip:'sv_voicequality\n1 = lowest (least bandwidth), 9 = highest quality.' },
    { n:'sv_sayName',               lbl:'Console Chat Name',      type:'text',   def:'Console', tip:'sv_sayName\nName shown in chat when the server sends a message.' },
    { n:'scr_xpscale',              lbl:'XP Multiplier',          type:'num',    def:'1',   tip:'scr_xpscale\nRound-end XP = score × scr_xpscale.' },
    { n:'scr_wagerbet',             lbl:'Wager Bet Amount',       type:'num',    def:'100', tip:'scr_wagerbet\nCoD Points cost to enter a wager match.' },
  ]},
  { title: 'ENGINE GAMEPLAY', eff: 'live', per: 'dvar', vars: [
    { n:'g_playerCollision',           lbl:'Player Collision',         type:'sel', def:'0', opts:[['0','Everyone'],['1','Enemies only'],['2','Nobody']], tip:'g_playerCollision\nWho players physically collide with.' },
    { n:'g_playerEjection',            lbl:'Player Ejection Source',   type:'sel', def:'0', opts:[['0','Everyone'],['1','Enemies only'],['2','Nobody']], tip:'g_playerEjection\nWho pushes players apart when overlapping.' },
    { n:'g_playerCollisionEjectSpeed', lbl:'Ejection Speed',           type:'num', def:'25',  tip:'g_playerCollisionEjectSpeed\nHow fast players are pushed apart. Range: 0–32000.' },
    { n:'sv_allowFriendlyThrowback',   lbl:'Friendly Grenade Throwback',type:'tog',def:'1',  tip:'sv_allowFriendlyThrowback\nAllow players to throw back friendly grenades.' },
    { n:'g_patchRocketJumps',          lbl:'Rocket Jump Knockback',    type:'tog', def:'1',   tip:'g_patchRocketJumps\nEnable upward knockback from rocket self-damage.' },
    { n:'bullet_penetration_affected_by_team', lbl:'Team Counts for Penetration', type:'tog', def:'1', tip:'bullet_penetration_affected_by_team\nTeammates reduce bullet penetration damage output.' },
    { n:'g_fix_viewkick_dupe',         lbl:'Fix Viewkick Duplicate',   type:'tog', def:'0',   tip:'g_fix_viewkick_dupe\nFix a bug where viewkick is applied twice.' },
    { n:'g_fixBulletDamageDupe',       lbl:'Fix Bullet Damage Dupe',   type:'tog', def:'0',   tip:'g_fixBulletDamageDupe\nFix double damage when two players intersect.' },
    { n:'g_fix_entity_leaks',          lbl:'Fix Entity Leaks',         type:'tog', def:'0',   tip:'g_fix_entity_leaks\nFix engine entity leak issues across rounds.' },
  ]},
  { title: 'GAME RULES', eff: 'restart', per: 'dvar', vars: [
    // Killstreaks / Headshots Only / Force UAV moved to DASHBOARD → GAMEPLAY as single
    // combined controls (sticky dvar + live bridge in one switch) — no duplicate rows here.
    { n:'scr_game_bulletdamage',    lbl:'Bullet Damage Scale',    type:'flt',  def:'1.0', tip:'scr_game_bulletdamage\nGlobal bullet damage multiplier. 1.0 = normal, 0.5 = half, 2.0 = double.' },
    { n:'scr_game_hardpoints',      lbl:'Scorestreaks',           type:'tog',  def:'1',   tip:'scr_game_hardpoints\nEnable scorestreak (hardpoint) system.' },
    { n:'scr_game_perks',           lbl:'Perks',                  type:'tog',  def:'1',   tip:'scr_game_perks\nAllow players to use perks.' },
    { n:'scr_game_graceperiod',     lbl:'Grace Period (s)',       type:'num',  def:'15',  tip:'scr_game_graceperiod\nInvincibility window at the start of each round.' },
    { n:'scr_game_prematchperiod',  lbl:'Prematch Period (s)',    type:'num',  def:'15',  tip:'scr_game_prematchperiod\nFreeze time before the round goes live.\n(Gunfight overrides this with scr_gf_match_prematch_seconds — see MATCH START.)' },
    { n:'scr_game_allowkillcam',    lbl:'Killcam',                type:'tog',  def:'1',   tip:'scr_game_allowkillcam\nShow killcam replay after death.' },
    { n:'scr_game_spectatetype',    lbl:'Spectate Mode',          type:'sel',  def:'1',   opts:[['0','Disabled'],['1','Own team'],['2','All players'],['3','All + freecam']], tip:'scr_game_spectatetype\nWho dead players can spectate.' },
    { n:'scr_game_deathpointloss',  lbl:'Points Lost on Death',  type:'num',  def:'0',   tip:'scr_game_deathpointloss\nScore penalty applied on each death.' },
    { n:'scr_game_suicidepointloss',lbl:'Points Lost on Suicide', type:'num', def:'0',   tip:'scr_game_suicidepointloss\nScore penalty applied on suicide.' },
    { n:'scr_intermission_time',    lbl:'Post-Game Screen (s)',   type:'num',  def:'15',  tip:'scr_intermission_time\nTime spent on the end-of-match scoreboard.' },
    { n:'scr_killstreak_stacking',  lbl:'Killstreak Rollover',    type:'tog',  def:'0',   tip:'scr_killstreak_stacking\nAllow killstreak kills to count toward the next streak.' },
  ]},
  { title: 'PERK MULTIPLIERS', eff: 'live', per: 'dvar', vars: [
    { n:'perk_weapSwitchMultiplier',     lbl:'Weapon Switch Speed',  type:'sld', def:'1.0', min:'0.25', max:'1.5', step:'0.001', tip:'perk_weapSwitchMultiplier\nWeapon-swap time multiplier. LOWER = FASTER: 0.833 ≈ 1.2x, 0.5 = 2x, 0.25 = 4x, 1.0 = stock (default).\nNeeds Fast Weapon Switch enabled in the PERKS section below — OFF by default, so this slider is inert until you enable it.' },
    { n:'perk_weapReloadMultiplier',     lbl:'Reload Speed',         type:'sld', def:'1.0',   min:'0.25', max:'1.5', step:'0.01',  tip:'perk_weapReloadMultiplier\nReload time multiplier. LOWER = FASTER.\nNeeds Sleight of Hand enabled in the PERKS section below.' },
    { n:'perk_weapAdsMultiplier',        lbl:'ADS Speed',            type:'sld', def:'1.0',   min:'0.25', max:'1.5', step:'0.01',  tip:'perk_weapAdsMultiplier\nAim-down-sight time multiplier. LOWER = FASTER.\nNeeds Sleight of Hand Pro enabled in the PERKS section below.' },
    { n:'perk_sprintMultiplier',         lbl:'Sprint Speed',         type:'sld', def:'1.0',   min:'0.5',  max:'2.0', step:'0.01',  tip:'perk_sprintMultiplier\nSprint speed multiplier. 1.0 = stock. Direction is engine-defined — adjust and test.\nGated by Lightweight (granted to all players).' },
    { n:'perk_sprintRecoveryMultiplier', lbl:'Sprint Recovery',      type:'sld', def:'1.0',   min:'0.25', max:'2.0', step:'0.01',  tip:'perk_sprintRecoveryMultiplier\nTime before you can sprint again. LOWER = FASTER recovery.\nNeeds Extreme Conditioning enabled in the PERKS section.' },
    { n:'perk_weapRateMultiplier',       lbl:'Fire Rate',            type:'sld', def:'1.0',   min:'0.5',  max:'2.0', step:'0.01',  tip:'perk_weapRateMultiplier\nRate-of-fire multiplier. 1.0 = stock. Adjust and test.\nGated by the Rapid Fire effect (specialty_rof).' },
    { n:'perk_weapSpreadMultiplier',     lbl:'Hip-fire Spread',      type:'sld', def:'1.0',   min:'0.25', max:'1.5', step:'0.01',  tip:'perk_weapSpreadMultiplier\nHip-fire spread multiplier. LOWER = TIGHTER.\nNeeds Steady Aim enabled in the PERKS section.' },
    { n:'perk_weapMeleeMultiplier',      lbl:'Melee Reach',          type:'sld', def:'1.0',   min:'0.5',  max:'2.0', step:'0.01',  tip:'perk_weapMeleeMultiplier\nMelee charge/reach multiplier. 1.0 = stock. Adjust and test.' },
  ]},
  { title: 'PERKS — give / remove for all players', vars: [
    { n:'specialty_movefaster',        lbl:'Lightweight',              type:'perk', def:'1', tip:'specialty_movefaster\nFaster movement. BASE perk (on by default).' },
    { n:'specialty_fallheight',        lbl:'No Fall Damage',           type:'perk', def:'1', tip:'specialty_fallheight\nRemoves fall damage (Lightweight Pro). BASE perk.' },
    { n:'specialty_longersprint',      lbl:'Marathon',                 type:'perk', def:'1', tip:'specialty_longersprint\nLonger sprint duration. BASE perk.' },
    { n:'specialty_armorvest',         lbl:'Flak Jacket',              type:'perk', def:'1', tip:'specialty_armorvest\nReduced explosive damage. BASE perk.' },
    { n:'specialty_flakjacket',        lbl:'Flak Jacket Pro',          type:'perk', def:'1', tip:'specialty_flakjacket\nThrow back live grenades. BASE perk.' },
    { n:'specialty_fastweaponswitch',  lbl:'Fast Weapon Switch',       type:'perk', def:'0', tip:'specialty_fastweaponswitch\nFaster weapon swaps. OFF by default. Enable to make the Weapon Switch Speed slider work.' },
    { n:'specialty_fastreload',        lbl:'Sleight of Hand',          type:'perk', def:'0', tip:'specialty_fastreload\nFaster reloads. Enable to make the Reload Speed slider work.' },
    { n:'specialty_fastads',           lbl:'Sleight of Hand Pro',      type:'perk', def:'0', tip:'specialty_fastads\nFaster ADS. Enable to make the ADS Speed slider work.' },
    { n:'specialty_gpsjammer',         lbl:'Ghost',                    type:'perk', def:'0', tip:'specialty_gpsjammer\nInvisible to UAV / radar.' },
    { n:'specialty_holdbreath',        lbl:'Scout',                    type:'perk', def:'0', tip:'specialty_holdbreath\nHold breath longer when scoped.' },
    { n:'specialty_bulletpenetration', lbl:'Hardened (Deep Impact)',   type:'perk', def:'0', tip:'specialty_bulletpenetration\nShoot through surfaces. Removed from the base loadout.' },
    { n:'specialty_bulletaccuracy',    lbl:'Steady Aim',               type:'perk', def:'0', tip:'specialty_bulletaccuracy\nTighter hip-fire. Pairs with the Hip-fire Spread slider.' },
    { n:'specialty_quieter',           lbl:'Ninja',                    type:'perk', def:'0', tip:'specialty_quieter\nQuieter footsteps.' },
    { n:'specialty_scavenger',         lbl:'Scavenger',                type:'perk', def:'0', tip:'specialty_scavenger\nReplenish ammo from dead bodies.' },
    { n:'specialty_twoattach',         lbl:'Warlord',                  type:'perk', def:'0', tip:'specialty_twoattach\nTwo attachments per weapon.' },
    { n:'specialty_detectexplosive',   lbl:'Hacker',                   type:'perk', def:'0', tip:'specialty_detectexplosive\nDetect enemy equipment.' },
    { n:'specialty_gas_mask',          lbl:'Tactical Mask',            type:'perk', def:'0', tip:'specialty_gas_mask\nReduces GAS (tabun) effect only. In this mod, flash/concussion resistance rides on the separate Flash Resist / Stun Resist perks below (the CAC Pro-upgrade that would grant them is bypassed here).' },
    { n:'specialty_shades',            lbl:'Flash Resist',             type:'perk', def:'1', tip:'specialty_shades\nCuts flashbang blind DURATION to 10% (_flashgrenades.gsc keys off this perk). BASE perk (on by default) — uncheck to remove it from everyone.' },
    { n:'specialty_stunprotection',    lbl:'Stun Resist',              type:'perk', def:'1', tip:'specialty_stunprotection\nCuts concussion-grenade stun DURATION to 10% (_weapons.gsc keys off this perk). BASE perk (on by default) — uncheck to remove it from everyone.' },
    { n:'specialty_pistoldeath',       lbl:'Second Chance',            type:'perk', def:'0', tip:'specialty_pistoldeath\nDrop into last-stand with a pistol on death.' },
    { n:'specialty_blindeye',          lbl:'Cold Blooded',             type:'perk', def:'0', tip:'specialty_blindeye\nUndetectable by AI killstreaks; no red name.' },
    { n:'specialty_sprintrecovery',    lbl:'Extreme Conditioning',     type:'perk', def:'0', tip:'specialty_sprintrecovery\nFaster sprint recovery. Pairs with the Sprint Recovery slider.' },
    { n:'specialty_extraammo',         lbl:'Extra Ammo',               type:'perk', def:'0', tip:'specialty_extraammo\nExtra starting magazines.' },
    { n:'specialty_killstreak',        lbl:'Hardline',                 type:'perk', def:'0', tip:'specialty_killstreak\nKillstreaks need one fewer kill. (Killstreaks are off in GF by default.)' },
    { n:'__perkreset',                 lbl:'Reset perks to GF default', type:'btn', act:'perkReset()', btxt:'Reset', tip:'Clears all perk overrides and restores the base Gunfight loadout perks.' },
  ]},
  { title: 'PLAYER', eff: 'restart', per: 'dvar', vars: [
    { n:'scr_player_maxhealth',       lbl:'Max Health',              type:'num', def:'100', tip:'scr_player_maxhealth\nPlayer HP cap. Default: 100.' },
    { n:'scr_player_healthregentime', lbl:'Health Regen Delay (s)',  type:'num', def:'5',   tip:'scr_player_healthregentime\nSeconds without damage before regen begins. 0 = instant.' },
    { n:'scr_player_numlives',        lbl:'Lives per Player',        type:'num', def:'0',   tip:'scr_player_numlives\nLives per player per game. 0 = unlimited.' },
    { n:'scr_player_forcerespawn',    lbl:'Force Instant Respawn',   type:'tog', def:'1',   tip:'scr_player_forcerespawn\nSkip the respawn hold timer — players respawn immediately.' },
    { n:'scr_player_respawndelay',    lbl:'Respawn Delay (s)',       type:'num', def:'0',   tip:'scr_player_respawndelay\nSeconds a player must wait before respawning.' },
    { n:'scr_player_sprinttime',      lbl:'Sprint Time (s)',         type:'num', def:'4',   tip:'scr_player_sprinttime\nBase sprint duration without Marathon perk.' },
    { n:'scr_player_allowrevive',     lbl:'Allow Revive',            type:'tog', def:'1',   tip:'scr_player_allowrevive\nAllow teammates to revive downed players.' },
    { n:'scr_player_suicidespawndelay',lbl:'Suicide Penalty (s)',    type:'num', def:'0',   tip:'scr_player_suicidespawndelay\nExtra respawn delay after suiciding.' },
  ]},
  { title: 'TEAMS', eff: 'live', per: 'dvar', vars: [
    // Max Players / Team and Friendly Fire moved to DASHBOARD → GAMEPLAY (single home).
    // NOTE: scr_teamchange / scr_autobalanceteams / scr_teamup were removed 2026-07-06 — they are
    // CoD4/WaW dvar names that do NOT exist in Black Ops (T5). Nothing reads them (setting is a
    // no-op) and the connect-sweep's bare-name READ of an unregistered dvar prints "Unknown cmd
    // <name>" to the server console / listen-host screen. Only real T5 team dvars stay here.
    { n:'scr_teambalance',            lbl:'Block Joining Larger Team',type:'tog',def:'0',   tip:'scr_teambalance\nPrevent players from joining the already-larger team. GF default: 0.' },
    { n:'scr_team_kickteamkillers',   lbl:'Kick Team Killers',       type:'tog', def:'0',   tip:'scr_team_kickteamkillers\nAuto-kick players who team kill.' },
    { n:'scr_team_teamkillspawndelay',lbl:'TK Spawn Penalty (s)',    type:'num', def:'20',  tip:'scr_team_teamkillspawndelay\nExtra respawn delay imposed on team killers.' },
    { n:'scr_team_teamkillpointloss', lbl:'TK Point Loss',          type:'tog', def:'1',   tip:'scr_team_teamkillpointloss\nDeduct points for team kills.' },
    { n:'scr_teamKillPunishCount',    lbl:'TK Kick Threshold',       type:'num', def:'4',   tip:'scr_teamKillPunishCount\nNumber of team kills before automatic punishment.' },
  ]},
  { title: 'DEBUG', eff: 'live', per: 'dvar', vars: [
    // gf_debug (Debug Level) removed 2026-07-06 — the mod reads it nowhere (dead control; its
    // bare-name read just printed "Unknown cmd gf_debug"). The gf_debug_* toggles below ARE read
    // (getDvarInt) and are now seeded to 0 by the mod so they read cleanly.
    { n:'gf_debug_spawns',        lbl:'Spawn Debug',          type:'tog', def:'0', tip:'gf_debug_spawns\nDraw spawn point entities + team assignments each round.' },
    { n:'gf_debug_hud_pool',      lbl:'HUD Pool Debug',       type:'tog', def:'0', tip:'gf_debug_hud_pool\nLog HUD element pool allocation counts each round.' },
    { n:'gf_debug_elem_probe',    lbl:'Elem Probe',           type:'tog', def:'0', tip:'gf_debug_elem_probe\nProbe available client HUD element slots; prints count.' },
    { n:'gf_force_camo',          lbl:'Force Camo (test)',    type:'sel', def:'-1', opts:[['-1','Off'],['0','Default'],['1','Dusty'],['2','Ice'],['3','Red'],['4','OD Green'],['5','Desert Nevada'],['6','Desert Sahara'],['7','Jungle ERDL'],['8','Jungle Tiger'],['9','Urban German'],['10','Urban Warsaw'],['11','Winter Siberia'],['12','Winter Yukon'],['13','Woodland'],['14','Woodland Flora'],['15','Gold']], tip:'gf_force_camo\nDEV/TEST: force this camo index on BOTH guns every spawn, overriding each loadout’s own camo. Off = use the loadout camo. Handy for checking which secondaries actually RENDER camo (e.g. set Gold and watch the pistols). Works on the dedicated server too — no sv_cheats needed.' },
    { n:'gf_force_loadout',       lbl:'Force Loadout (-1=off)', type:'num', def:'-1', tip:'gf_force_loadout\nDEV/TEST: lock ONE loadout on every spawn instead of the round rotation, to inspect it without waiting. Value = index into the live (SHUFFLED) pool, 0-53 — NOT the editor row number, so cycle 0,1,2… and read the on-screen loadout HUD to find the one you want. -1 = off (normal rotation).' },
    // (duplicate Killcam row removed — the one control lives in GAME RULES)
    { n:'compass',                lbl:'Minimap',              type:'tog', def:'1', tip:'compass\n1 = show minimap, 0 = hide.' },
    // def '0' (was '1'): 0 is both the engine default AND the correct production value. sv_cheats 1
    // on a dedicated server makes noclip/god/give/r_* reachable from any player console, leaving
    // sv_disableClientConsole as the only line of defence. The mod forces sv_cheats 1 on a LISTEN
    // server only (gf.gsc, dev block) — it must never be 1 on the VPS.
    { n:'sv_cheats',              lbl:'Allow Cheat Commands', type:'tog', def:'0', tip:'sv_cheats\nAllow cheat-protected dvars + commands (noclip, god, give, timescale, r_* renderer tweaks, sv_bot* tuning).\n\n• LISTEN: the mod force-sets this to 1 every round (dev block) — cheat controls work.\n• DEDICATED (VPS): must be 0. A 1 here exposes every cheat command to any player who can open a console.\n\nTurning this OFF disables the BOT TUNING sliders, the Timescale slider and the r_* Visual Tweaks — those are cheat-protected and the engine will silently refuse them.' },
    { n:'scr_disable_cac',        lbl:'Disable Class Select', type:'tog', def:'1', tip:'scr_disable_cac\nDisable Create-a-Class; players auto-spawn with the default class.' },
    { n:'scr_disable_weapondrop', lbl:'Disable Weapon Drop',  type:'tog', def:'1', tip:'scr_disable_weapondrop\n1 = weapons do not drop on death.' },
  ]},
  // BOT TUNING — the sv_bot* sliders are CHEAT-PROTECTED: the engine refuses a raw rcon `set`
  // ("Error: sv_botFov is cheat protected") whenever sv_cheats is 0, which is the only correct value
  // on a dedicated server. They used to appear to work here purely because the mod was force-setting
  // sv_cheats 1 on EVERY server (a broken `dedicated` guard in gf.gsc — since fixed).
  //
  // svset:true routes them through the GSC bridge instead. GSC setDvar is NOT cheat-gated (verified:
  // rcon `set bg_viewKickScale 0.9` refused while the bridge wrote the same dvar in the same round),
  // and these are SERVER dvars read by the bot AI — no client replication involved — so this works
  // on the VPS with cheats off. The bridge also mirrors each into a plain gf_<dvar> that 💾 Save can
  // persist to dedicated.cfg; the real dvar can't be, since the cfg is cheat-gated too.
  //
  // ⚠ These are OVERRIDES ON TOP OF the Difficulty preset, not independent settings. _bot.gsc's
  // diffBots() loop re-applies bot_set_difficulty() every 1.5s, which rewrites the WHOLE sv_bot*
  // set — so before 2026-07-11 every slider here was silently reverted within a second and a half
  // (the real reason they "did nothing"; the cheat gate was a red herring). diffBots now re-applies
  // these overrides right after the preset, so Difficulty = baseline and a tuned slider sticks.
  { title: 'BOT TUNING', eff: 'live', per: 'dvar', vars: [
    { n:'sv_botFov',             lbl:'Bot FOV (deg)',         type:'num', def:'65',   svset:true, tip:'sv_botFov\nField of view bots use to acquire targets. Higher = they see you sooner.\nCheat-protected — set via the GSC bridge, so it works on the dedicated VPS with sv_cheats 0.' },
    { n:'sv_botMinReactionTime', lbl:'Reaction Min (ms)',     type:'num', def:'500',  svset:true, tip:'sv_botMinReactionTime\nFastest reaction time on spotting a target. Lower = harder bots.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botMaxReactionTime', lbl:'Reaction Max (ms)',     type:'num', def:'1000', svset:true, tip:'sv_botMaxReactionTime\nSlowest reaction time. Lower = harder bots.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botMinFireTime',     lbl:'Fire Burst Min (ms)',   type:'num', def:'400',  svset:true, tip:'sv_botMinFireTime\nShortest continuous-fire burst.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botMaxFireTime',     lbl:'Fire Burst Max (ms)',   type:'num', def:'600',  svset:true, tip:'sv_botMaxFireTime\nLongest continuous-fire burst.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botStrafeChance',    lbl:'Strafe Chance (0–1)',   type:'flt', def:'0.1',  svset:true, tip:'sv_botStrafeChance\nProbability a bot strafes during a fight.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botSprintDistance',  lbl:'Sprint Distance',       type:'num', def:'512',  svset:true, tip:'sv_botSprintDistance\nRange beyond which bots sprint toward targets/objectives.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botMeleeDist',       lbl:'Melee Distance',        type:'num', def:'80',   svset:true, tip:'sv_botMeleeDist\nRange at which bots attempt a melee.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botYawSpeed',        lbl:'Aim Turn Speed',        type:'num', def:'4',    svset:true, tip:'sv_botYawSpeed\nAim turn speed. Higher = snappier.\nCheat-protected — set via the GSC bridge.' },
    { n:'sv_botAllowGrenades',   lbl:'Bots Throw Grenades',   type:'tog', def:'1',    tip:'sv_botAllowGrenades\nAllow bots to throw lethal grenades.' },
    { n:'sv_randomizeBotNames',  lbl:'Randomize Bot Names',   type:'tog', def:'1',    tip:'sv_randomizeBotNames\nGive bots random player-style names.' },
    { n:'sv_botUseFriendNames',  lbl:'Bots Use Friend Names', type:'tog', def:'1',    tip:'sv_botUseFriendNames\nBots borrow names from your friends list.' },
  ]},
];
// ADVANCED tab section order — declared here (was a mutate-at-load IIFE matching titles
// by prefix). Titles are matched by prefix so the em-dash PERKS title still resolves.
const SRV_ORDER = ['GAME RULES','PLAYER','TEAMS','PERK MULTIPLIERS','PERKS','GENERAL','ENGINE GAMEPLAY','BOT TUNING','DEBUG'];
SRV_SECTIONS.sort((a,b)=>{
  const k=t=>{const i=SRV_ORDER.findIndex(o=>t.indexOf(o)===0);return i<0?99:i;};
  return k(a.title)-k(b.title);
});

// Per-gametype dvar blocks — shown one at a time via the ADVANCED-tab gametype dropdown
// (default gf). Keys match GT_OPTS vals. Wager modes inherit the wager framework and
// expose few unique dvars; seeded values are best-effort and confirmed live by the Read button.
//
// The gf set is split in two: GF_MATCH_VARS renders as the DASHBOARD → GUNFIGHT block
// (the per-match rules you actually retune), GF_START_VARS as ADVANCED → MATCH START
// (the lobby / load-gate machinery you configure once). GT_SECTIONS.gf stays the concat
// so the dvar sweep + search index still see the full set in one place.
const GF_MATCH_VARS = [
    { grp:'Match',
      n:'scr_gf_scorelimit',          lbl:'Rounds to Win',            type:'num', def:'6',    tip:'scr_gf_scorelimit\nRound wins needed to win the match.' },
    { n:'scr_gf_roundlimit',          lbl:'Max Rounds (0=off)',       type:'num', def:'0',    tip:'scr_gf_roundlimit\nHard round cap regardless of score. 0 = scorelimit only.' },
    { n:'scr_gf_roundswitch',         lbl:'Sides Switch Every (rounds)', type:'num', def:'2',    tip:'scr_gf_roundswitch\nSwap attacker/defender sides every N rounds. 0 = never.' },
    { n:'scr_gf_roundsperloadout',    lbl:'Rounds Per Loadout',       type:'num', def:'2', tip:'scr_gf_roundsperloadout\nRounds the shared random loadout stays before rotating to the next. Clamped 1-9. Independent of Side Switch.' },
    { n:'scr_gf_numlives',            lbl:'Lives / Round',            type:'num', def:'1',    tip:'scr_gf_numlives\nLives per player per round.' },

    { grp:'Spawns &amp; Round Time',
      n:'scr_gf_teamspawnmode',       lbl:'Team Spawn Mode',          type:'sel', def:'auto', opts:[['auto','Auto (5+/team → large)'],['large','Force Large'],['small','Force Small']], tip:'scr_gf_teamspawnmode\nauto = switch by the larger team (5+ on a team → large, hard-wired to the HUD skulls→readout switch); large/small = force the mode. (scr_gf_largemode_minplayers is retired.)' },
    { n:'scr_gf_timelimit',           lbl:'Round Time — Small (min)', type:'num', def:'0.75', tip:'scr_gf_timelimit\nRound time for SMALL mode (<=4v4). 0 = no limit.' },
    { n:'scr_gf_timelimit_large',     lbl:'Round Time — Large (min)', type:'num', def:'1.5',  tip:'scr_gf_timelimit_large\nRound time for LARGE mode (any team of 5+).' },

    { grp:'Overtime',
      n:'scr_gf_overtimelimit',       lbl:'OT Duration — Small (s)',  type:'num', def:'15',   tip:'scr_gf_overtimelimit\nOT countdown for SMALL mode. Pauses while contested.' },
    { n:'scr_gf_overtimelimit_large', lbl:'OT Duration — Large (s)',  type:'num', def:'30',   tip:'scr_gf_overtimelimit_large\nOT countdown for LARGE mode. Pauses while contested.' },
    { n:'gf_capture_time',            lbl:'OT Capture — Small (s)',   type:'num', def:'3',    tip:'gf_capture_time\nSeconds to capture the OT zone in SMALL mode.' },
    { n:'gf_capture_time_large',      lbl:'OT Capture — Large (s)',   type:'num', def:'5',    tip:'gf_capture_time_large\nSeconds to capture the OT zone in LARGE mode.' },
];
const GF_START_VARS = [
    { n:'scr_gf_lobby',               lbl:'Match Start',               type:'sel', def:'0', opts:[['0','Normal (no lobby)'],['1','Auto lobby (min-players)'],['2','Manual lobby (START)']], tip:'scr_gf_lobby\nHow the match FIRST round starts (before the prematch countdown):\n• Normal = no lobby; the match starts in place (still waits for loaders / Min Players, then the countdown plays).\n• Auto = hold a pregame lobby (desaturated screen) until everyone is loaded and Min Players humans are in, then FAST-RESTART into a fresh match — re-firing the full start presentation (gun-rack, music, welcome). ~1s, no map reload.\n• Manual = hold the lobby until you click START MATCH (Match Control rail) — arrange teams first — then fast-restart. Auto-starts on its own after Manual Lobby Timer seconds (scr_gf_lobby_timer, default 600; 0 = never) so a forgotten hold can’t wedge the server.\nAuto/Manual: START MATCH is an instant override. Match-start only. Manual needs the RCON bridge (this panel).' },
    { n:'scr_gf_lobby_timer',         lbl:'Manual Lobby Timer (s, 0=off)', type:'num', def:'600', tip:'scr_gf_lobby_timer\nMANUAL lobby only (Match Start = Manual). Seconds the pregame lobby waits before it AUTO-STARTS the match on its own, if you never click START MATCH. Replaces the old hardcoded 10-min backstop.\nThe lobby HUD shows a live "auto-starts in M:SS" countdown while this is running.\n0 = never auto-start — the lobby holds until you click START MATCH (a forgotten lobby then sits there indefinitely).\nDefault 600 (10 min). Clamped 0-3600. Has no effect in Normal or Auto (Auto releases on its own load/min-players gates).' },
    { n:'scr_gf_min_players',         lbl:'Min Players to Start',      type:'num', def:'1',  tip:'scr_gf_min_players\nHold the FIRST round (BEFORE the prematch countdown) until at least this many HUMAN players are here (bots do not count). Match-start only — once live it never re-holds, even if players leave. Nobody is spawned yet during the hold, so there is no freeze/damage-void. By default the lobby holds until enough humans arrive or an admin clicks START (a pure-bot lobby never stalls); set Min Players Timer below for a start-anyway ceiling. 1 = effectively off. Clamped 1-8.\n(This is Gunfight’s min-players gate. The ADVANCED → GENERAL party_minplayers does NOT affect gf.)' },
    { n:'scr_gf_minplayers_timer',    lbl:'Min Players Timer (s, 0=off)', type:'num', def:'0', tip:'scr_gf_minplayers_timer\nMin-players "start anyway" ceiling. Seconds the FIRST-round hold waits for enough humans (Min Players) before it STARTS THE MATCH ANYWAY with too few players.\n0 = never auto-start (DEFAULT) — the lobby holds until Min Players humans arrive or an admin clicks START MATCH. Replaces the old hardcoded 90s ceiling that started too-thin matches on its own.\nA pure-bot lobby (0 humans) always releases regardless. Clamped 0-3600. Has no effect if Min Players is 1 (gate off).' },
    { n:'scr_gf_load_wait',           lbl:'Load Wait (s, 0=off)',      type:'num', def:'0', tip:'scr_gf_load_wait\nMax seconds the match FIRST round holds BEFORE the prematch countdown until every map-loading client is in, so everyone sees the intro/countdown together (and slow loaders are not grace-locked into spectating round 1). Bots + demo clients excluded. Shows a "Waiting for teams N/M" readout. First-time FastDL downloaders are not fully absorbed. Default 0 = off (no wait; a slow loader may miss the intro / spectate round 1, and Load Grace goes inert). Clamped 0-120.\nSame hold also enforces Min Players above.' },
    { n:'scr_gf_match_prematch_seconds', lbl:'Prematch (s)',          type:'num', def:'15', tip:'scr_gf_match_prematch_seconds\nIntro countdown before the first round of the match (MATCH STARTING IN). Runs AFTER the Match Start hold. Clamped 2-30. (Stock scr_game_prematchperiod is overridden by this and has no effect.)' },
    { n:'scr_gf_prematch_seconds',    lbl:'Preround (s)',             type:'num', def:'7',  tip:'scr_gf_prematch_seconds\nCountdown before each later round (ROUND BEGINS IN). Clamped 2-20.' },
    { n:'scr_gf_load_grace',          lbl:'Load Grace (s, adv)',       type:'num', def:'20', tip:'scr_gf_load_grace\nADVANCED / edge case. When Load Wait gives up with a client still loading (e.g. a FastDL first-timer), keep the grace period open this many seconds past the countdown so they can still spawn INTO round 1 instead of spectating. Cost: a round-1 team wipe cannot end the round until grace closes. 0 = off (they spectate). Clamped 0-60.' },
];
const GT_SECTIONS = {
  gf: GF_MATCH_VARS.concat(GF_START_VARS),
  tdm: [
    { n:'scr_tdm_scorelimit', lbl:'Score Limit', type:'num', def:'17500', tip:'scr_tdm_scorelimit\nTeam score needed to win.' },
    { n:'scr_tdm_timelimit',  lbl:'Time Limit (min)', type:'num', def:'10', tip:'scr_tdm_timelimit\nMatch duration if score limit not reached.' },
    { n:'scr_tdm_numlives',   lbl:'Lives (0=∞)',  type:'num', def:'0',  tip:'scr_tdm_numlives\nLives per player. 0 = unlimited.' },
  ],
  dm: [
    { n:'scr_dm_scorelimit', lbl:'Score Limit', type:'num', def:'1500', tip:'scr_dm_scorelimit\nFirst player to reach this score wins.' },
    { n:'scr_dm_timelimit',  lbl:'Time Limit (min)', type:'num', def:'10', tip:'scr_dm_timelimit\nMatch duration if score limit not reached.' },
    { n:'scr_dm_numlives',   lbl:'Lives (0=∞)',  type:'num', def:'0',  tip:'scr_dm_numlives\nLives per player. 0 = unlimited.' },
  ],
  sd: [
    { n:'scr_sd_scorelimit', lbl:'Round Win Limit', type:'num', def:'4',   tip:'scr_sd_scorelimit\nRound wins needed to win the match.' },
    { n:'scr_sd_timelimit',  lbl:'Round Time (min)',type:'num', def:'2.5', tip:'scr_sd_timelimit\nTime per round.' },
    { n:'scr_sd_bombtimer',  lbl:'Bomb Timer (s)',  type:'num', def:'45',  tip:'scr_sd_bombtimer\nSeconds until planted bomb detonates.' },
    { n:'scr_sd_defusetime', lbl:'Defuse Time (s)', type:'num', def:'5',   tip:'scr_sd_defusetime\nSeconds to defuse the bomb.' },
    { n:'scr_sd_planttime',  lbl:'Plant Time (s)',  type:'num', def:'5',   tip:'scr_sd_planttime\nSeconds to plant the bomb.' },
    { n:'scr_sd_roundswitch',lbl:'Sides Switch Every (rounds)', type:'num', def:'1', tip:'scr_sd_roundswitch\nRounds before teams switch attacker/defender roles.' },
  ],
  dom: [
    { n:'scr_dom_scorelimit',     lbl:'Score Limit',          type:'num', def:'200', tip:'scr_dom_scorelimit\nTeam score needed to win.' },
    { n:'scr_dom_timelimit',      lbl:'Time Limit (min)',     type:'num', def:'0',   tip:'scr_dom_timelimit\nMatch duration. 0 = score-limit only.' },
    { n:'scr_dom_flagcapturetime',lbl:'Flag Capture Time (s)',type:'num', def:'10',  tip:'scr_dom_flagcapturetime\nSeconds to capture a flag.' },
  ],
  dem: [
    { n:'scr_dem_scorelimit', lbl:'Round Win Limit', type:'num', def:'2',   tip:'scr_dem_scorelimit\nRound wins needed to win the match.' },
    { n:'scr_dem_timelimit',  lbl:'Round Time (min)',type:'num', def:'2.5', tip:'scr_dem_timelimit\nTime per round.' },
    { n:'scr_dem_bombtimer',  lbl:'Bomb Timer (s)',  type:'num', def:'45',  tip:'scr_dem_bombtimer\nSeconds until planted bomb detonates.' },
    { n:'scr_dem_defusetime', lbl:'Defuse Time (s)', type:'num', def:'5',   tip:'scr_dem_defusetime\nSeconds to defuse.' },
    { n:'scr_dem_planttime',  lbl:'Plant Time (s)',  type:'num', def:'5',   tip:'scr_dem_planttime\nSeconds to plant.' },
  ],
  sab: [
    { n:'scr_sab_timelimit',         lbl:'Time Limit (min)',    type:'num', def:'10',  tip:'scr_sab_timelimit\nMatch duration.' },
    { n:'scr_sab_bombtimer',         lbl:'Bomb Timer (s)',      type:'num', def:'45',  tip:'scr_sab_bombtimer\nSeconds until bomb detonates.' },
    { n:'scr_sab_defusetime',        lbl:'Defuse Time (s)',     type:'num', def:'5',   tip:'scr_sab_defusetime\nSeconds to defuse.' },
    { n:'scr_sab_planttime',         lbl:'Plant Time (s)',      type:'num', def:'2.5', tip:'scr_sab_planttime\nSeconds to plant.' },
    { n:'scr_sab_playerrespawndelay',lbl:'Respawn Delay (s)',   type:'num', def:'7.5', tip:'scr_sab_playerrespawndelay\nTime before respawn.' },
  ],
  ctf: [
    { n:'scr_ctf_scorelimit',        lbl:'Score Limit',             type:'num', def:'3',  tip:'scr_ctf_scorelimit\nCaptures needed to win.' },
    { n:'scr_ctf_timelimit',         lbl:'Time Limit (min)',        type:'num', def:'5',  tip:'scr_ctf_timelimit\nRound duration.' },
    { n:'scr_ctf_flagrespawntime',   lbl:'Flag Respawn Time (s)',   type:'num', def:'0',  tip:'scr_ctf_flagrespawntime\nTime before a captured flag respawns. 0 = immediate.' },
    { n:'scr_ctf_idleflagreturntime',lbl:'Idle Flag Return (s)',    type:'num', def:'30', tip:'scr_ctf_idleflagreturntime\nSeconds before a dropped flag auto-returns to base.' },
    { n:'scr_ctf_touchreturn',       lbl:'Touch to Return Flag',    type:'tog', def:'1',  tip:'scr_ctf_touchreturn\nAllow players to return their own flag by touching it.' },
  ],
  koth: [
    { n:'scr_koth_scorelimit', lbl:'Score Limit',      type:'num', def:'250', tip:'scr_koth_scorelimit\nPoints needed to win.' },
    { n:'scr_koth_timelimit',  lbl:'Time Limit (min)', type:'num', def:'15',  tip:'scr_koth_timelimit\nMatch duration if score limit not reached.' },
    { n:'scr_koth_winlimit',   lbl:'Round Win Limit',  type:'num', def:'1',   tip:'scr_koth_winlimit\nRounds needed to win the match.' },
  ],
  gun: [
    { n:'scr_gun_scorelimit', lbl:'Weapon Tiers to Win', type:'num', def:'0',  tip:'scr_gun_scorelimit\nGun Game progression length (0 = full weapon list). Verify via: dvarlist scr_gun' },
    { n:'scr_gun_timelimit',  lbl:'Time Limit (min)',    type:'num', def:'10', tip:'scr_gun_timelimit\nMatch duration. Wager framework — confirm with the Read button.' },
  ],
  oic: [
    { n:'scr_oic_scorelimit', lbl:'Round Win Limit', type:'num', def:'5',   tip:'scr_oic_scorelimit\nOne in the Chamber round wins to win. Verify via: dvarlist scr_oic' },
    { n:'scr_oic_timelimit',  lbl:'Round Time (min)',type:'num', def:'2.5', tip:'scr_oic_timelimit\nTime per round. Wager framework — confirm with the Read button.' },
  ],
  shrp: [
    { n:'scr_shrp_scorelimit', lbl:'Score Limit',     type:'num', def:'0',  tip:'scr_shrp_scorelimit\nSharpshooter score to win (0 = time-based). Verify via: dvarlist scr_shrp' },
    { n:'scr_shrp_timelimit',  lbl:'Time Limit (min)',type:'num', def:'10', tip:'scr_shrp_timelimit\nMatch duration. Wager framework — confirm with the Read button.' },
  ],
  hlnd: [
    { n:'scr_hlnd_scorelimit', lbl:'Score Limit',     type:'num', def:'0',  tip:'scr_hlnd_scorelimit\nSticks & Stones score to win (0 = time-based). Verify via: dvarlist scr_hlnd' },
    { n:'scr_hlnd_timelimit',  lbl:'Time Limit (min)',type:'num', def:'10', tip:'scr_hlnd_timelimit\nMatch duration. Wager framework — confirm with the Read button.' },
  ],
};

// Build one row (control) from a var def. prefix scopes the element id so the same
// var set can be rendered in two tabs without id collisions (SERVER='srv', MATCH='mt').
//
// ── Behavior pills ───────────────────────────────────────────────────────────
// Two orthogonal axes an operator actually reasons about, surfaced as small tags:
//   eff (when it takes hold): live | next (next round) | restart (needs map_restart)
//   per (how long it sticks): dvar (survives map_restart; 💾 Save persists to cfg)
//                             transient (runtime/bridge state, wiped on map_restart)
//                             client (pushed per-client via setClientDvar, not saved)
// A blank axis renders no pill. Data-driven rows get section defaults (srvBlock args),
// overridable per-var via v.eff / v.per; static blocks use data-eff/data-per + hydrateBadges().
const _EFF = {
  live:    ['LIVE',    'Applies immediately to the running match.'],
  next:    ['NEXT',    'Applies on the next round.'],
  restart: ['RESTART', 'Needs a map_restart to take effect on the running match.'],
};
const _PER = {
  dvar:      ['STICKY', 'Survives map_restart. Use the block’s 💾 Save to persist across a full server restart.'],
  transient: ['TEMP',   'Runtime / GSC-bridge state — resets to the mod default on map_restart.'],
  client:    ['CLIENT', 'Pushed to each client (setClientDvar); not stored server-side.'],
};
function badges(eff, per) {
  let h = '';
  if (eff && _EFF[eff]) h += `<span class="pill eff-${eff}" title="${_EFF[eff][1]}">${_EFF[eff][0]}</span>`;
  if (per && _PER[per]) h += `<span class="pill per-${per}" title="${_PER[per][1]}">${_PER[per][0]}</span>`;
  return h ? `<span class="pills">${h}</span>` : '';
}
// One-line key for the pills; rendered into the collapsible legend footer of each settings tab.
const LEGEND_HTML =
  '<div class="pill-legend"><span class="dm">When:</span>'
  + '<span class="pill eff-live">LIVE</span><span class="dm">now</span>'
  + '<span class="pill eff-next">NEXT</span><span class="dm">next round</span>'
  + '<span class="pill eff-restart">RESTART</span><span class="dm">needs map_restart</span>'
  + '<span class="lg-sep">|</span><span class="dm">Sticks:</span>'
  + '<span class="pill per-dvar">STICKY</span><span class="dm">survives map_restart · 💾 Save → cfg</span>'
  + '<span class="pill per-transient">TEMP</span><span class="dm">resets on map_restart</span>'
  + '<span class="pill per-client">CLIENT</span><span class="dm">per-client, not saved</span></div>';
// Static (hand-written) blocks/rows opt in via data-eff/data-per. A .block badges its
// title (whole section behaves the same); any other element badges its .slbl (mixed rows).
function hydrateBadges() {
  document.querySelectorAll('[data-eff],[data-per]').forEach(el => {
    const pills = badges(el.dataset.eff, el.dataset.per);
    if (!pills) return;
    const host = el.classList.contains('block') ? el.querySelector('.btitle') : el.querySelector('.slbl');
    if (host) host.insertAdjacentHTML('beforeend', pills);
  });
}
const PANEL_CAP=2100;   // keep in sync with the #p-* max-width in app.css

// ─── Behavior-pill legend footer ──────────────────────────────────────────────
// One collapsed-by-default strip per settings tab, pinned under the columns. Its open/closed
// state has its OWN key (gf_legend) rather than riding the .block collapse list, because
// restoreCollapse() only ever ADDS `collapsed` — a default-collapsed .block could never
// persist an "expanded" choice.
function buildLegendFooters(){
  let open=false; try{ open=localStorage.getItem('gf_legend')==='1'; }catch(_){}
  ['p-match','p-srv'].forEach(id=>{
    const p=g(id); if(!p||p.querySelector(':scope > .legend-foot')) return;
    const d=document.createElement('div');
    d.className='legend-foot'+(open?'':' collapsed');
    d.innerHTML='<div class="lf-title" onclick="toggleLegend()">Legend — what the pills mean</div>'
              + '<div class="lf-body">'+LEGEND_HTML+'</div>';
    p.appendChild(d);
  });
}
function toggleLegend(){
  const els=document.querySelectorAll('.legend-foot'); if(!els.length) return;
  const opening=els[0].classList.contains('collapsed');
  els.forEach(e=>e.classList.toggle('collapsed',!opening));
  try{ localStorage.setItem('gf_legend',opening?'1':'0'); }catch(_){}
}

// ─── Two-column block layout (DASHBOARD + ADVANCED) ───────────────────────────
// Why not CSS multi-columns: they balance by HEIGHT, so any height change (browser zoom,
// collapsing a block, a live readout growing a row) reshuffles which block sits in which
// column — sections visibly jump. Instead each block is assigned to a column ONCE and only
// redistributed when the column COUNT changes (2 <-> 1). Zooming then just narrows columns.
//
// Blocks are built by JS into .flow wrappers (display:contents); this re-parents them into
// .pcol containers. Safe because every builder runs before the first layout, and the only
// later re-render (buildGtSection) targets #srv-gt-body INSIDE the #srv-gt-wrap unit, which
// travels between columns whole.
// COL_MIN 400: with the wider 380px side-by-side sidebar this still yields TWO ~422px columns
// at a 1270-1280px half-screen window (the panel beside Discord), and falls to one column
// below that. MAX_COLS is 3 because retiring the right-hand rail freed ~850px on a 2560px
// display — set it to 2 to go back to a strict two-column layout.
const COL_MIN=400, COL_GAP=12, MAX_COLS=3;
function _wantCols(){
  const main=document.querySelector('.main'); if(!main) return 2;
  const w=Math.min(PANEL_CAP,main.clientWidth)-28;   // minus the panel's 14px side padding
  let n=Math.floor((w+COL_GAP)/(COL_MIN+COL_GAP));
  return Math.max(1,Math.min(MAX_COLS,n));
}
function layoutColumns(panel,force){
  if(!panel||!panel.classList.contains('active')) return;   // a hidden panel can't be measured
  if(panel.id!=='p-match'&&panel.id!=='p-srv') return;      // MAPS/CONSOLE keep their own flow
  const cols=_wantCols();
  if(!panel._items){
    // Canonical order, captured BEFORE any re-parenting (afterwards DOM order is col1+col2).
    // Blocks inside #srv-gt-wrap travel with the wrapper, so they're not separate items.
    panel._items=Array.from(panel.querySelectorAll('.block, #srv-gt-wrap'))
      .filter(el=>el.id==='srv-gt-wrap'||!el.closest('#srv-gt-wrap'));
  }
  if(!force && panel._cols===cols) return;
  panel._cols=cols;
  // .cols is the row wrapper holding the columns; the panel itself stays a column flex so the
  // legend footer can sit beneath them. Emptying it detaches the blocks, but panel._items
  // still holds the references, so re-appending below is safe.
  let colsEl=panel.querySelector(':scope > .cols');
  if(!colsEl){ colsEl=document.createElement('div'); colsEl.className='cols'; panel.appendChild(colsEl); }
  colsEl.innerHTML='';
  const colEls=[];
  for(let i=0;i<cols;i++){ const c=document.createElement('div'); c.className='pcol'; colsEl.appendChild(c); colEls.push(c); }
  const finish=()=>{ const lf=panel.querySelector(':scope > .legend-foot'); if(lf) panel.appendChild(lf); };  // keep the legend last
  if(cols===1){ panel._items.forEach(el=>colEls[0].appendChild(el)); finish(); return; }
  // Stage everything in column 0 (already at its final width — the empty sibling columns are
  // flex:1 too, so all columns share the row equally) so the measured heights match the final
  // layout, then greedily drop each block into whichever column is currently shortest.
  panel._items.forEach(el=>colEls[0].appendChild(el));
  const hs=panel._items.map(el=>el.getBoundingClientRect().height);
  const tot=new Array(cols).fill(0);
  panel._items.forEach((el,i)=>{
    let c=0; for(let j=1;j<cols;j++) if(tot[j]<tot[c]) c=j;   // shortest column wins (ties -> leftmost)
    colEls[c].appendChild(el); tot[c]+=hs[i]+COL_GAP;
  });
  finish();
}
function layoutActivePanel(force){ layoutColumns(document.querySelector('#p-match.active, #p-srv.active'),force); }
let _relayoutT=null;
window.addEventListener('resize',()=>{ clearTimeout(_relayoutT); _relayoutT=setTimeout(()=>layoutActivePanel(),120); });

// ─── Resizable sidebar + activity log (drag handles, persisted) ────────────────
// The sidebar width (--sbw) and activity-log height (--alh) are CSS vars on <html>.
// Drag #sbDrag / #alDrag to resize; double-click a handle resets to the default.
const SB_DEF=380, SB_MIN=260, SB_MAX=680, AL_DEF=220, AL_MIN=80;
function _alMax(){ return Math.max(140, Math.round(window.innerHeight*0.6)); }
function setSidebarW(px){
  px=Math.max(SB_MIN,Math.min(SB_MAX,Math.round(px)));
  document.documentElement.style.setProperty('--sbw',px+'px');
  try{ localStorage.setItem('gf_sbw',String(px)); }catch(_){}
  layoutActivePanel();   // a narrower/wider main area may cross the 2 <-> 1 column threshold
}
function setActlogH(px){
  px=Math.max(AL_MIN,Math.min(_alMax(),Math.round(px)));
  document.documentElement.style.setProperty('--alh',px+'px');
  try{ localStorage.setItem('gf_alh',String(px)); }catch(_){}
}
function initResizers(){
  try{ const w=parseInt(localStorage.getItem('gf_sbw')); if(w) document.documentElement.style.setProperty('--sbw',Math.max(SB_MIN,Math.min(SB_MAX,w))+'px'); }catch(_){}
  try{ const h=parseInt(localStorage.getItem('gf_alh')); if(h) document.documentElement.style.setProperty('--alh',Math.max(AL_MIN,Math.min(_alMax(),h))+'px'); }catch(_){}
  const sb=g('sbDrag'), al=g('alDrag');
  if(sb) sb.addEventListener('mousedown',e=>startDrag(e,'col'));
  if(al) al.addEventListener('mousedown',e=>startDrag(e,'row'));
  if(sb) sb.addEventListener('dblclick',()=>setSidebarW(SB_DEF));
  if(al) al.addEventListener('dblclick',()=>setActlogH(AL_DEF));
}
let _drag=null;
function startDrag(e,axis){
  e.preventDefault();
  const bar=document.querySelector('.sidebar'), log=g('actlog');
  _drag={axis, startX:e.clientX, startY:e.clientY,
         startW:bar?bar.getBoundingClientRect().width:SB_DEF,
         startH:log?log.getBoundingClientRect().height:AL_DEF};
  document.body.classList.add('resizing'); if(axis==='row') document.body.classList.add('rowres');
  g(axis==='col'?'sbDrag':'alDrag').classList.add('drag');
  window.addEventListener('mousemove',onDrag);
  window.addEventListener('mouseup',endDrag);
}
function onDrag(e){
  if(!_drag) return;
  if(_drag.axis==='col') setSidebarW(_drag.startW+(e.clientX-_drag.startX));
  else setActlogH(_drag.startH-(e.clientY-_drag.startY));   // handle sits ABOVE the log → drag up grows it
}
function endDrag(){
  _drag=null;
  document.body.classList.remove('resizing','rowres');
  const s=g('sbDrag'),a=g('alDrag'); if(s)s.classList.remove('drag'); if(a)a.classList.remove('drag');
  window.removeEventListener('mousemove',onDrag);
  window.removeEventListener('mouseup',endDrag);
}

// ─── Brand logo picker ────────────────────────────────────────────────────────
// Click the header brand to swap the logo (header + sidebar footer + favicon).
// Drop any transparent PNG into tools/rcon/public/ and add it to LOGOS below.
const LOGOS=[
  {f:'ops.png',      n:'OPS'},
  {f:'3rch.png',     n:'Treyarch'},
  {f:'15.png',       n:'Pirate Skull'},
  {f:'14.png',       n:'Prestige Skull'},
  {f:'blackops.png', n:'Black Ops'},
];
function setLogo(f){
  ['brandLogo','footLogo'].forEach(id=>{ const e=g(id); if(e) e.src=f; });
  const fav=g('favicon'); if(fav) fav.href=f;
  try{ localStorage.setItem('gf_logo',f); }catch(_){}
  document.querySelectorAll('.logo-opt').forEach(o=>o.classList.toggle('sel',o.dataset.f===f));
}
function buildLogoPicker(){
  const p=g('logoPicker'); if(!p) return;
  p.innerHTML=LOGOS.map(l=>`<img class="logo-opt" src="${l.f}" data-f="${l.f}" title="${l.n}" alt="${l.n}" onclick="event.stopPropagation();setLogo('${l.f}');g('logoPicker').classList.remove('open')">`).join('');
  let saved='ops.png'; try{ saved=localStorage.getItem('gf_logo')||'ops.png'; }catch(_){}
  setLogo(saved);
}
function toggleLogoPicker(e){ e.stopPropagation(); g('logoPicker').classList.toggle('open'); }
document.addEventListener('click',e=>{ if(!e.target.closest('.brand')){ const p=g('logoPicker'); if(p) p.classList.remove('open'); } });

// ─── Collapsible sections ─────────────────────────────────────────────────────
// Click any block title to fold it. Delegated so it covers static + generated blocks.
// State is keyed by the title text and persisted in localStorage.
function _blockKey(b){ const t=b.querySelector('.btitle'); return t ? t.textContent.replace(/\s+/g,' ').trim().slice(0,48) : ''; }
function saveCollapse(){
  const c=[]; document.querySelectorAll('.block.collapsed').forEach(b=>{ const k=_blockKey(b); if(k) c.push(k); });
  try{ localStorage.setItem('gf_collapsed', JSON.stringify(c)); }catch(_){}
}
function restoreCollapse(){
  let saved; try{ saved=JSON.parse(localStorage.getItem('gf_collapsed')||'[]'); }catch(_){ return; }
  const set=new Set(saved||[]);
  document.querySelectorAll('.block').forEach(b=>{ if(set.has(_blockKey(b))) b.classList.add('collapsed'); });
}
document.addEventListener('click',e=>{
  const t=e.target.closest('.btitle'); if(!t) return;
  const b=t.closest('.block'); if(!b) return;
  b.classList.toggle('collapsed'); saveCollapse();
});

function srvRow(v, prefix, dEff, dPer) {
  const tip = `data-tip="${v.tip.replace(/"/g,'&quot;').replace(/\n/g,'&#10;')}"`;
  const id  = (prefix || 'srv') + '_' + v.n.replace(/[^a-zA-Z0-9]/g,'_');
  let ctrl;
  // Optional row extensions:
  //   v.also   — a second dvar set to the same value on every change (tog/sel), e.g. the
  //              scr_gf_team_fftype live override that rides along with scr_team_fftype.
  //   v.bridge — a GSC-bridge on/off prefix fired alongside the dvar set (tog only), so one
  //              switch is both sticky (dvar) and immediate (bridge), e.g. killstreaks/radar.
  //   type 'bridgetog' — pure bridge on/off toggle with NO dvar behind it (v.n = bridge prefix);
  //              excluded from dvar reads / Set All / 💾 Save.
  if (v.type === 'tog') {
    // Toggles apply immediately — no queuing
    const chk = v.def === '1' ? 'checked' : '';
    const oc = v.bridge ? `togDvarBridge(this,'${v.n}','${v.bridge}')`
             : v.also   ? `sdvv2('${v.n}','${v.also}',this.checked?'1':'0')`
             :            `sdvv('${v.n}',${id}.checked?'1':'0')`;
    ctrl = `<label class="tog ctrl"><input type="checkbox" id="${id}" ${chk} onchange="${oc}"><span class="tog-t"></span><span class="tog-th"></span></label>`;
  } else if (v.type === 'bridgetog') {
    const chk = v.def === '1' ? 'checked' : '';
    ctrl = `<label class="tog ctrl"><input type="checkbox" id="${id}" ${chk} onchange="bridgeTog(this,'${v.n}')"><span class="tog-t"></span><span class="tog-th"></span></label>`;
  } else if (v.type === 'perk') {
    // Perk give/remove for all players — recomputes override lists + live-syncs
    const chk = v.def === '1' ? 'checked' : '';
    ctrl = `<label class="tog ctrl"><input type="checkbox" id="${id}" data-perk="${v.n}" ${chk} onchange="perkTog()"><span class="tog-t"></span><span class="tog-th"></span></label>`;
  } else if (v.type === 'sld') {
    // Range slider — applies the dvar live on release, value readout updates on drag
    const mn = v.min || '0.1', mx = v.max || '2', st = v.step || '0.05';
    const dv = parseFloat(v.def).toFixed(3).replace(/0+$/,'').replace(/\.$/,'');
    ctrl = `<input type="range" id="${id}" class="ctrl sld" min="${mn}" max="${mx}" step="${st}" value="${v.def}" oninput="g('${id}_v').textContent=parseFloat(this.value).toFixed(3).replace(/0+$/,'').replace(/\.$/,'')" onchange="sdvv('${v.n}',this.value)"><span class="sldval" id="${id}_v">${dv}</span>`;
  } else if (v.type === 'btn') {
    ctrl = `<button class="b-gh b-sm ctrl" onclick="${v.act}">${v.btxt || 'Run'}</button>`;
  } else if (v.type === 'sel') {
    const opts = v.opts.map(o => `<option value="${o[0]}"${o[0]===v.def?' selected':''}>${o[1]}</option>`).join('');
    const oc = v.also ? `sdvv2('${v.n}','${v.also}',this.value)` : `sdvv('${v.n}',this.value)`;
    ctrl = `<select id="${id}" class="ctrl" onchange="${oc}">${opts}</select>`;
  } else if (v.type === 'text') {
    ctrl = `<input id="${id}" type="text" class="ctrl" value="${v.def}" style="flex:1;min-width:80px"><button class="b-ac b-sm ctrl" onclick="sdve('${v.n}','${id}')">Set</button>`;
  } else {
    const step = v.type === 'flt' ? '0.1' : '1';
    // v.svset — a CHEAT-PROTECTED server dvar. A raw rcon `set` is refused by the engine whenever
    // sv_cheats is 0 (i.e. always, on a correctly-configured dedicated server), so the Set button
    // routes through the GSC bridge, which is not cheat-gated.
    const setCall = v.svset ? `bridgeSvSet('${v.n}','${id}')` : `sdve('${v.n}','${id}')`;
    ctrl = `<input id="${id}" type="number" class="num ctrl" value="${v.def}" step="${step}"><button class="b-ac b-sm ctrl" onclick="${setCall}">Set</button>`;
  }
  const noDvar = (v.type === 'perk' || v.type === 'btn' || v.type === 'bridgetog');
  // data-dvar stays the REAL dvar (reads + search key off it — a READ is never cheat-gated).
  // data-mirror is the plain gf_<dvar> the WRITERS must use: Set All pushes it over rcon and 💾 Save
  // persists it to dedicated.cfg, because the real dvar can be written by NEITHER (both are
  // cheat-refused). One `svsync` bridge call then copies the mirrors onto the real dvars from GSC.
  const dd = noDvar ? '' : ` data-dvar="${v.n}"` + (v.also ? ` data-also="${v.also}"` : '')
                                                 + (v.svset ? ` data-mirror="gf_${v.n}"` : '');
  const sp = (v.type === 'tog' || v.type === 'bridgetog' || v.type === 'perk' || v.type === 'btn') ? '<span style="flex:1"></span>' : '';
  const pills = (v.type === 'perk' || v.type === 'btn') ? '' : badges(v.eff || dEff, v.per || dPer);
  return `<div class="srow"${dd} ${tip}><span class="slbl">${v.lbl}${pills}</span>${sp}${ctrl}</div>`;
}
// Build a titled .block from a vars array (adds a Set All row when it has number/text fields).
// dEff/dPer = section-level behavior-pill defaults (per-var v.eff / v.per override them).
function srvBlock(title, vars, prefix, dEff, dPer) {
  // A var may carry an optional grp:'Label' to open a sub-group header before its row
  // (purely additive — every consumer still sees normal dvar entries with .n intact).
  const rows = vars.map(v => (v.grp ? `<div class="sgroup">${v.grp}</div>` : '') + srvRow(v, prefix, dEff, dPer)).join('');
  const hasSetAll = vars.some(v => v.type === 'text' || v.type === 'num' || v.type === 'flt');
  const setAllRow = hasSetAll ? '<div class="set-all-row"><button class="b-gh b-sm ctrl" data-tip="Write this block&#39;s values to dedicated.cfg (persists across restarts).&#10;A .bak backup is made; takes effect on next server start or `exec dedicated.cfg`." onclick="saveBlockToCfg(this)">💾 Save</button><button class="b-ac b-sm ctrl" onclick="setAllInBlock(this)">Set All</button></div>' : '';
  return `<div class="block"><div class="btitle">${title}</div>${rows}${setAllRow}</div>`;
}

function buildServerPanel() {
  // Read-from-server + Kill Server now live in the header (see #hdrRead / #hdrKill).
  // Shared (always-visible) sections → #srv-body (an ADVANCED-tab flow wrapper)
  g('srv-body').innerHTML = SRV_SECTIONS.map(sec => srvBlock(sec.title, sec.vars, undefined, sec.eff, sec.per)).join('');
  // Gametype picker (native select, grouped) — swaps the per-mode block below it.
  // Rendered into its own wrapper (#srv-gt-wrap) so picker + block stay together in the
  // two-column layout.
  let selHtml = '<select id="srvGtSel" class="ctrl" onchange="buildGtSection(this.value)">';
  let grpOpen = false;
  for (const o of GT_OPTS) {
    if (o.grp) { if (grpOpen) selHtml += '</optgroup>'; selHtml += `<optgroup label="${o.grp.replace(/—/g,'').trim()}">`; grpOpen = true; }
    else if (GT_SECTIONS[o.val]) selHtml += `<option value="${o.val}"${o.val==='gf'?' selected':''}>${o.lbl}</option>`;
  }
  if (grpOpen) selHtml += '</optgroup>';
  selHtml += '</select>';
  g('srv-gt-wrap').innerHTML =
    `<div class="mact"><label>Gametype settings</label>${selHtml}`
    + `<span class="dm" style="font-size:11px">one mode at a time · gf settings live in the DASHBOARD tab</span></div>`
    + `<div id="srv-gt-body"></div>`;
  buildGtSection('gf');
}
// Render a single gametype's dvar block into #srv-gt-body (and live-read it if connected).
// gf is intentionally NOT editable here — its round/OT dvars have a single home in the
// DASHBOARD/ADVANCED (GT_SECTIONS.gf is consumed once, by buildMatchGf). Selecting gf shows a pointer.
function buildGtSection(key) {
  const sel = g('srvGtSel'); if (sel) sel.value = key;
  if (key === 'gf') {
    g('srv-gt-body').innerHTML =
      '<div class="block"><div class="btitle">GUNFIGHT</div>'
      + '<div class="dm" style="font-style:italic;line-height:1.6">Gunfight round &amp; overtime dvars live in the '
      + '<b style="color:var(--ac)">DASHBOARD</b> tab → GUNFIGHT block (single source, no duplicate copy here); '
      + 'the lobby / load-gate knobs are above in MATCH START. Use each block’s 💾 Save to write them to dedicated.cfg.</div></div>';
    setCtrl(live); applyServerMode();
    return;
  }
  const vars = GT_SECTIONS[key] || [];
  const opt  = GT_OPTS.find(o => o.val === key);
  const title = (opt ? opt.lbl : key).toUpperCase();
  g('srv-gt-body').innerHTML = vars.length
    ? srvBlock(title, vars, undefined, 'restart', 'dvar')
    : '<div class="block"><div class="dm" style="font-style:italic">No tunable dvars for this gametype.</div></div>';
  setCtrl(live);                 // keep new controls' enabled-state in sync with connection
  applyServerMode();             // re-grey any mode-specific controls after setCtrl re-enabled them
  if (live) readGtDvars(key);
}

// ─── ADVANCED tab live dvar read ──────────────────────────────────────────────
// Write a { name: value } map onto the matching srv_* controls. Skips perk/btn rows
// and any value that came back null (timeout / unset) so the seeded default stays.
function srvApplyValues(vars, values, prefix) {
  const pf = prefix || 'srv';
  vars.forEach(v => {
    if (v.type === 'perk' || v.type === 'btn' || v.type === 'bridgetog') return;
    const base = pf + '_' + v.n.replace(/[^a-zA-Z0-9]/g,'_');
    const el = g(base);
    if (!el) return;
    const row = el.closest('.srow');
    const val = values[v.n];
    if (val === null || val === undefined) {
      // Read missed (timeout/parse-miss): field still shows its hardcoded default, not a
      // live value. Flag the row so the two aren't confused.
      if (row) row.classList.add('unsynced');
      return;
    }
    if (row) row.classList.remove('unsynced');
    if (v.type === 'tog') { el.checked = (val === '1' || val === 1 || val === 'true'); }
    else if (v.type === 'sld') {
      el.value = val;
      const vv = g(base + '_v');
      if (vv) vv.textContent = parseFloat(val).toFixed(3).replace(/0+$/,'').replace(/\.$/,'');
    } else { el.value = val; }   // num / flt / text / sel
  });
}
// Read every shared dvar + the currently-shown gametype block from the server.
async function readServerDvars(fresh) {
  if (!live) return;
  let vars = [];
  SRV_SECTIONS.forEach(s => { vars = vars.concat(s.vars); });
  const gtKey = (g('srvGtSel') && g('srvGtSel').value) || 'gf';
  if (gtKey !== 'gf') vars = vars.concat(GT_SECTIONS[gtKey] || []);   // gf is read via readMatchDvars, not here
  const names = vars.filter(v => v.type !== 'perk' && v.type !== 'btn').map(v => v.n);
  if (!names.length) return;
  actLog('Reading ' + names.length + ' server dvars…', 'in');
  syncBegin();
  try {
    const r = await fetchDvars(names, fresh);
    if (r && r.ok) {
      srvApplyValues(vars, r.values);
      const got = Object.values(r.values).filter(x => x !== null).length;
      actLog('Synced ' + got + '/' + names.length + ' dvars from server', 'ok');
      toast('ADVANCED values synced', 'ok');
    } else toast('Dvar read failed', 'err');
  } catch (e) { toast('Dvar read error: ' + e.message, 'err'); }
  finally { syncEnd(); }
}
// Read only one gametype block (used when switching the dropdown while connected).
async function readGtDvars(key) {
  if (!live) return;
  const vars = GT_SECTIONS[key] || [];
  const names = vars.map(v => v.n);
  if (!names.length) return;
  syncBegin();
  try { const r = await fetchDvars(names); if (r && r.ok) srvApplyValues(vars, r.values); } catch (_) {}
  finally { syncEnd(); }
}

// ─── DASHBOARD GUNFIGHT block + ADVANCED MATCH START block ───────────────────
// Same data family (GT_SECTIONS.gf = GF_MATCH_VARS + GF_START_VARS), same mt_ id prefix
// for both, so the one readMatchDvars() sweep fills them wherever they render.
function buildMatchGf() {
  g('mt-gf-body').innerHTML = srvBlock('GUNFIGHT', GF_MATCH_VARS, 'mt', 'next', 'dvar');
  g('adv-start-body').innerHTML = srvBlock('MATCH START', GF_START_VARS, 'mt', 'next', 'dvar');
  setCtrl(live);
}
// DASHBOARD GAMEPLAY block — the single home of the controls that used to exist twice
// (MATCH toggle + SERVER dvar row). Each is ONE control that owns every mechanism behind
// the concept: dvar + live override (FF) or dvar + GSC bridge (killstreaks/headshots/radar).
const DASH_GAMEPLAY = [
  { n:'scr_team_fftype',        lbl:'Friendly Fire',   type:'sel', def:'0', also:'scr_gf_team_fftype', eff:'live', per:'dvar',
    opts:[['0','Off'],['1','On'],['2','Reflect'],['3','Shared']],
    tip:'scr_team_fftype + scr_gf_team_fftype (live override)\n0=off, 1=on, 2=damage reflected to shooter, 3=shared with team.\nSets BOTH the stock dvar and the gf per-gametype override — the engine re-polls the override every ~5s, so it applies to the RUNNING match (the old MATCH toggle wrote scr_gf_ff/scr_team_ff, which nothing reads — that was the "FF re-enables itself" bug).' },
  { n:'scr_team_maxsize',       lbl:'Max Team Size',   type:'num', def:'6', eff:'next', per:'dvar',
    tip:'scr_team_maxsize\nPlayers per team max; overflow goes to spectator on spawn. 0 = unlimited.\nGF server ships 6 (up to 6v6). Auto spawn mode is per-team roster driven, not this.' },
  { n:'scr_game_killstreaks',   lbl:'Killstreaks',     type:'tog', def:'0', bridge:'killstreaks', eff:'live', per:'dvar',
    tip:'scr_game_killstreaks + bridge killstreaks_on/off\nONE switch: sets the sticky dvar (future rounds, 💾 Save persists it) AND flips level.killstreaksenabled live via the GSC bridge so the running round changes too. GF default: off.' },
  { n:'regen',                  lbl:'Health Regen',    type:'bridgetog', def:'0', eff:'live', per:'transient',
    tip:'level.healthRegenDisabled + scr_player_healthregentime\nBridge regen_on/off sets both. On = 5s delay. Off = disabled (GF default).\nThe delay itself is tunable in ADVANCED → PLAYER → Health Regen Delay.' },
  { n:'scr_game_onlyheadshots', lbl:'Headshots Only',  type:'tog', def:'0', bridge:'headshots', eff:'live', per:'dvar',
    tip:'scr_game_onlyheadshots + bridge headshots_on/off\nONE switch: sets the stock dvar AND the mod\'s live level.gf_headshotsOnly flag (non-head/helmet hits deal 0 damage immediately).' },
  { n:'scr_game_forceradar',    lbl:'Radar Always On', type:'tog', def:'0', bridge:'radar', eff:'live', per:'dvar',
    tip:'scr_game_forceradar + bridge radar_on/off\nForce UAV for everyone — both teams see each other on the minimap. Sets the sticky dvar AND the live match flags so it applies immediately.' },
];
function buildDashGameplay() {
  g('mt-dash-body').innerHTML = srvBlock('GAMEPLAY', DASH_GAMEPLAY, 'mt', 'live', 'dvar');
  setCtrl(live);
}
// DASHBOARD GAME MODIFIERS block — Plutonium server cheat/fun dvars (mt_ id prefix).
function buildMatchModifiers() {
  g('mt-mod-body').innerHTML = srvBlock('GAME MODIFIERS', MATCH_MODIFIERS, 'mt', 'next', 'dvar');
  setCtrl(live);
}
// Set every modifier toggle back to 0 (off) and uncheck the UI.
async function resetModifiers() {
  const dvars = MATCH_MODIFIERS.filter(v => v.type === 'tog').map(v => v.n);
  await batchCmds(dvars.map(d => `set ${d} 0`), 40);
  dvars.forEach(n => { const el = g('mt_' + n.replace(/[^a-zA-Z0-9]/g,'_')); if (el) el.checked = false; });
  actLog('Game modifiers reset', 'ok'); toast('Modifiers reset', 'ok');
}
// Live-read the gunfight + gameplay + modifier dvars into their mt_-prefixed blocks
// (GUNFIGHT + GAMEPLAY on DASHBOARD, MATCH START + GAME MODIFIERS on ADVANCED).
async function readMatchDvars(fresh) {
  if (!live) return;
  const vars = GT_SECTIONS.gf.concat(DASH_GAMEPLAY, MATCH_MODIFIERS);
  const names = vars.filter(v => v.type !== 'btn' && v.type !== 'bridgetog').map(v => v.n);
  syncBegin();
  try { const r = await fetchDvars(names, fresh); if (r && r.ok) srvApplyValues(vars, r.values, 'mt'); } catch (_) {}
  finally { syncEnd(); }
}

// ─── Gametype custom dropdown ─────────────────────────────────────────────────
const GT_OPTS = [
  { grp: '— Custom —' },
  { val:'gf',   lbl:'gf — Gunfight',                 desc:'Eliminate enemies to win the round. 6 rounds to win. Random loadouts. No respawns. No health regen.' },
  { grp: '— Standard —' },
  { val:'tdm',  lbl:'tdm — Team Deathmatch',          desc:'Straight up Team Deathmatch on all maps. Use teamwork to kill enemy players and reach the score limit.' },
  { val:'dm',   lbl:'dm — Free For All',              desc:'Straight up Deathmatch. Every man for himself. Kill everyone.' },
  { val:'sd',   lbl:'sd — Search & Destroy',          desc:'Defend and destroy the objective. No respawning.' },
  { val:'dom',  lbl:'dom — Domination',               desc:'3 flags in the level must be captured. Your team gets points for having control of a flag. The more flags your team holds, the more points you gain.' },
  { val:'koth', lbl:'koth — Headquarters',            desc:'A neutral base to capture is marked in the level. Capture and hold it to gain points. The team that holds the HQ doesn\'t respawn.' },
  { val:'ctf',  lbl:'ctf — Capture the Flag',         desc:'Get the enemy flag and return it to yours to capture it.' },
  { val:'sab',  lbl:'sab — Sabotage',                 desc:'A neutral bomb is in the center of the level and teams fight to destroy the enemy team\'s objective. First team to successfully bomb the enemy objective wins.' },
  { val:'dem',  lbl:'dem — Demolition',               desc:'Teams alternate in attacking and defending two bomb sites, both of which must be destroyed by the attacking team equipped with bombs.' },
  { grp: '— Wager —' },
  { val:'gun',  lbl:'gun — Gun Game',                 desc:'Gun Game. Get a kill with each weapon to advance. First player to finish the full weapon sequence wins.' },
  { val:'oic',  lbl:'oic — One in the Chamber',       desc:'One in the Chamber. One bullet, one life. Kill to earn another bullet. Last player standing wins the round.' },
  { val:'shrp', lbl:'shrp — Sharpshooter',            desc:'Sharpshooter. Everyone shares the same randomly rotating weapon. Most kills when time runs out wins.' },
  { val:'hlnd', lbl:'hlnd — Sticks and Stones',       desc:'Sticks and Stones. Crossbow and ballistic knife only. Melee kills bankrupt an enemy\'s score. First to the score limit wins.' },
];

// Server modifier dvars surfaced on ADVANCED (GAME MODIFIERS block). Only dvars with a
// verified engine mechanism live here. The old sv_BigHeadMode / sv_TripleBullet / sv_SuperPenetrate
// / sv_InfiniteSprint / sv_InstantReload / sv_QuickHealthRecharge toggles were removed: none of
// those dvars exist in the T5 engine, the mod, or any config (big head was confirmed dead in-game),
// so they did nothing. scr_oldschool IS a real engine dvar (level.oldschool is read throughout the
// stock source); it needs a map_restart. Toggles call sdvv directly (no GSC bridge).
const MATCH_MODIFIERS = [
  { n:'scr_oldschool',          lbl:'Old School Mode',       type:'tog', def:'0', eff:'restart', tip:'scr_oldschool\nClassic high-jump / map-pickup movement feel (real engine dvar).\nChanges movement + enables map weapon pickups, so it fights the curated one-life design — test before using.\nNeeds a map_restart to take effect.' },
  { n:'__modreset',             lbl:'Reset all modifiers',   type:'btn', act:'resetModifiers()', btxt:'Reset', tip:'Sets every modifier above back to 0 (off).' },
];

// Built here (not at the function def) because buildServerPanel() reads GT_OPTS above.
buildServerPanel();
buildMatchGf();
buildDashGameplay();
buildMatchModifiers();
hydrateBadges();   // badge the static (hand-written) blocks/rows via their data-eff/data-per
buildSearchIndex();// index every DASHBOARD + ADVANCED setting for the global search bar
buildLegendFooters();// collapsible pill-legend strip at the bottom of each settings tab
buildLogoPicker(); // brand logo swatches + restore the saved choice
restoreCollapse(); // re-apply any folded sections from a previous session
initResizers();    // restore + wire the sidebar-width / activity-height drag handles
layoutActivePanel();// distribute the visible panel's blocks into stable columns (after collapse state)
// Deep-link a tab: ?tab=match|maps|srv|con (composable with ?profile= / ?autoconnect).
try{ const _t=new URLSearchParams(location.search).get('tab'); if(_t&&TABS.indexOf(_t)>=0) tab(_t); }catch(_){}

let _gtVal = 'gf';

function _buildGtList() {
  const list = g('vGtList');
  list.innerHTML = GT_OPTS.map(o => {
    if (o.grp) return `<div class="csel-grp">${o.grp}</div>`;
    return `<div class="csel-item${o.val===_gtVal?' active':''}" data-val="${o.val}" data-tip="${o.val}&#10;${o.desc}" onclick="gtSelect('${o.val}',this.textContent.split('\\n')[0])">${o.lbl}</div>`;
  }).join('');
}
function gtToggle() {
  const btn = g('vGtBtn'), list = g('vGtList');
  const open = list.classList.toggle('open');
  btn.classList.toggle('open', open);
  if (open) _buildGtList();
}
function gtSelect(val, _) {
  _gtVal = val;
  const opt = GT_OPTS.find(o => o.val === val);
  g('vGtLabel').textContent = opt ? opt.lbl : val;
  g('vGtList').classList.remove('open');
  g('vGtBtn').classList.remove('open');
  _tip.style.display = 'none';
}
document.addEventListener('click', e => {
  if (!g('vGtWrap').contains(e.target)) {
    g('vGtList').classList.remove('open');
    g('vGtBtn').classList.remove('open');
  }
});
_buildGtList();

// ─── Tooltip ─────────────────────────────────────────────────────────────────
const _tip=document.createElement('div');
_tip.style.cssText='position:fixed;background:#0a0c14;border:1px solid #252840;color:#9aa0c0;padding:5px 9px;border-radius:5px;font-size:11px;pointer-events:none;z-index:99999;max-width:320px;display:none;line-height:1.5;white-space:pre-wrap;box-shadow:0 3px 12px rgba(0,0,0,.6)';
document.body.appendChild(_tip);
document.addEventListener('mousemove',e=>{
  if(_tip.style.display==='none')return;
  let lx=e.clientX+14,ly=e.clientY+14;
  if(lx+_tip.offsetWidth>window.innerWidth) lx=e.clientX-_tip.offsetWidth-10;
  if(ly+_tip.offsetHeight>window.innerHeight) ly=e.clientY-_tip.offsetHeight-10;
  _tip.style.left=lx+'px';_tip.style.top=ly+'px';
});
document.addEventListener('mouseover',e=>{
  const el=e.target.closest('[data-tip]');
  if(el){_tip.textContent=el.dataset.tip;_tip.style.display='block';}
});
document.addEventListener('mouseout',e=>{
  const el=e.target.closest('[data-tip]');
  if(el&&!el.contains(e.relatedTarget))_tip.style.display='none';
});
