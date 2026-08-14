// Shared vm/DOM harness for the site/test suites (not a *.test.js - the runner glob
// skips it). admin.js is a browser script with no module system: load() runs the real
// file inside a vm context carrying a minimal DOM, so tests exercise the shipped text
// while every render stays inert until a test drives it.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ADMIN_JS = path.join(__dirname, '..', 'wwwroot', 'admin', 'admin.js');

// Strict about innerHTML on purpose: the page's contract is textContent-only rendering
// (safe against a hostile player name); the one sanctioned innerHTML use is clearing.
function mkNode(tag){
  const n = {
    tag, className:'', textContent:'', title:'', type:'', style:{}, kids:[], handlers:{},
    set innerHTML(v){ if(v !== '') throw new Error('innerHTML used with markup: '+v); n.kids.length = 0; },
    get innerHTML(){ return ''; },
    appendChild(c){ n.kids.push(c); return c; },
    addEventListener(ev, fn){ (n.handlers[ev] = n.handlers[ev] || []).push(fn); },
    setAttribute(){},
    click(){ (n.handlers.click || []).forEach(f => f()); },
  };
  return n;
}
function walk(n, out){ out.push(n); (n.kids||[]).forEach(k => walk(k, out)); return out; }
function textOf(n){ return walk(n, []).map(x => x.textContent || '').join('|'); }

// hostIds: which getElementById lookups resolve to a node; everything else is null,
// which is how the file's own guards keep unrelated cards inert. Stub ONLY what a vm
// context genuinely lacks - injecting host intrinsics (Array, Date, ...) makes
// cross-realm comparisons misbehave.
function load(hostIds){
  const hosts = {};
  (hostIds || []).forEach(id => { hosts[id] = mkNode('div'); });
  const sandbox = {
    document: {
      getElementById: (id) => (id in hosts ? hosts[id] : null),
      createElement: (t) => mkNode(t),
      createTextNode: (s) => { const n = mkNode('#text'); n.textContent = String(s); return n; },
    },
    fetch: () => new Promise(() => {}),     // never settles: no fetch-driven render runs
    setInterval: () => 0, setTimeout: () => 0, clearTimeout: () => {},
    console,
  };
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(ADMIN_JS, 'utf8'), sandbox, { filename:'admin.js' });
  return { sb: sandbox, hosts };
}

// An array that crossed the vm boundary carries the SANDBOX's Array.prototype, so strict
// deepEqual rejects it against a host array. Copy into this realm before comparing.
const here = (arr) => Array.from(arr);

// One day-file connect event, shaped exactly like Build-ConnHistory emits it.
const ev = (date, time, event, ip, name, guid, session, cc, region) =>
  ({ date, time, event, ip, name, guid, ping:'50', session: session||'', cc: cc||'', region: region||'' });

module.exports = { mkNode, walk, textOf, load, here, ev };
