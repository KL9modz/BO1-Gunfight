// Gunfight — Loadout Editor (local, no-code)
// A tiny loopback web tool that reads the 54 loadouts out of
// maps/mp/gametypes/_gf_loadouts.gsc, lets you edit every slot + camo in a
// browser with dropdowns, and writes the .gsc back for you. Dev-only (lives
// under tools/, stripped from public release builds).
//
//   node server.js            -> http://127.0.0.1:3100
//
// No external dependencies (Node built-ins only). It only ever rewrites the
// `pool[n] = gf_load( ... ); n++;` lines BETWEEN the two markers:
//     // #gf-loadout-editor-begin ... // #gf-loadout-editor-end
// Everything else in the file (comments, helpers, the resolver tables) is left
// untouched. A rolling backup is written to _gf_loadouts.gsc.editorbak on save.

const http = require( "http" );
const fs   = require( "fs" );
const path = require( "path" );

const PORT     = 3100;
const HOST     = "127.0.0.1";
const GSC_PATH = path.join( __dirname, "..", "..", "maps", "mp", "gametypes", "_gf_loadouts.gsc" );
const BEGIN    = "#gf-loadout-editor-begin";
const END      = "#gf-loadout-editor-end";

// One gf_load pool line:
//   pool[n] = gf_load( "p", "s", "e", "l", "t", camo, camoSec, "perks" ); n++;
// camoSec (7th) and perks (8th) are both OPTIONAL, so this still matches every older line shape.
const LINE_RE = /pool\[n\]\s*=\s*gf_load\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(-?\d+)\s*(?:,\s*(-?\d+)\s*)?(?:,\s*"([^"]*)"\s*)?\)\s*;\s*n\+\+\s*;/;
const TOKEN_RE = /^[a-z0-9_]+$/;   // whitelist — tokens are the only thing we inject into code

// Max perks a loadout may ADD. Only a sanity ceiling now — the overview shows just 3 of them
// (base perks preferred over Pros, never the same icon twice), the rest are silent buffs.
// Removals are not capped.
const MAX_PERK_ADDS = 8;

// Every specialty the ENGINE actually knows, straight out of BlackOpsMP.exe's specialty table.
// This list is the whole point of the dropdowns: SetPerk on a name the engine doesn't know is a
// SILENT NO-OP, which is how a bogus "specialty_blindeye" sat in the RCON panel doing nothing for
// months. Anything not on this list is rejected at save time rather than shipped as a dead perk.
// Display names are BO1's own create-a-class names; "Pro" entries are the extra tokens a Pro
// upgrade adds (a perk is just a group of these). Grouped as the game groups them.
const PERKS = [
    // Perk 1
    { t: "specialty_movefaster",        n: "Lightweight",          g: "Perk 1" },
    { t: "specialty_fallheight",        n: "Lightweight Pro",      g: "Perk 1", pro: 1, d: "No fall damage" },
    { t: "specialty_scavenger",         n: "Scavenger",            g: "Perk 1" },
    { t: "specialty_extraammo",         n: "Scavenger Pro",        g: "Perk 1", pro: 1, d: "Extra mags; replenish tacticals" },
    { t: "specialty_gpsjammer",         n: "Ghost",                g: "Perk 1" },
    { t: "specialty_nottargetedbyai",   n: "Ghost Pro",            g: "Perk 1", pro: 1, d: "Not targeted by dogs/sentries/aircraft" },
    { t: "specialty_noname",            n: "Ghost Pro",            g: "Perk 1", pro: 1, d: "No red name / crosshair when targeted" },
    { t: "specialty_killstreak",        n: "Hardline",             g: "Perk 1", d: "Killstreaks are OFF in Gunfight — this does nothing" },
    { t: "specialty_flakjacket",        n: "Flak Jacket",          g: "Perk 1", d: "Reduced explosive damage. BASE perk." },
    { t: "specialty_fireproof",         n: "Flak Jacket Pro",      g: "Perk 1", pro: 1, d: "Immune to fire damage" },
    { t: "specialty_pin_back",          n: "Flak Jacket Pro",      g: "Perk 1", pro: 1, d: "Longer grenade throw-back time" },
    // Perk 2
    { t: "specialty_bulletpenetration", n: "Hardened",             g: "Perk 2" },
    { t: "specialty_armorpiercing",     n: "Hardened Pro",         g: "Perk 2", pro: 1, d: "More damage to aircraft/turrets" },
    { t: "specialty_bulletflinch",      n: "Hardened Pro",         g: "Perk 2", pro: 1, d: "Reduced reaction/recoil when shot" },
    { t: "specialty_holdbreath",        n: "Scout",                g: "Perk 2" },
    { t: "specialty_fastweaponswitch",  n: "Scout Pro",            g: "Perk 2", pro: 1, d: "Faster weapon switch / raise / drop" },
    { t: "specialty_bulletaccuracy",    n: "Steady Aim",           g: "Perk 2" },
    { t: "specialty_sprintrecovery",    n: "Steady Aim Pro",       g: "Perk 2", pro: 1, d: "Faster ADS after sprinting" },
    { t: "specialty_fastmeleerecovery", n: "Steady Aim Pro",       g: "Perk 2", pro: 1, d: "Faster recovery after a knife lunge" },
    { t: "specialty_fastreload",        n: "Sleight of Hand",      g: "Perk 2" },
    { t: "specialty_fastads",           n: "Sleight of Hand Pro",  g: "Perk 2", pro: 1, d: "Faster ADS (non-scoped)" },
    { t: "specialty_twoattach",         n: "Warlord",              g: "Perk 2" },
    { t: "specialty_twogrenades",       n: "Warlord Pro",          g: "Perk 2", pro: 1, d: "+1 lethal and +1 tactical" },
    // Perk 3
    { t: "specialty_gas_mask",          n: "Tactical Mask",        g: "Perk 3" },
    { t: "specialty_shades",            n: "Tactical Mask Pro",    g: "Perk 3", pro: 1, d: "Flash resist. BASE perk." },
    { t: "specialty_stunprotection",    n: "Tactical Mask Pro",    g: "Perk 3", pro: 1, d: "Stun resist. BASE perk." },
    { t: "specialty_longersprint",      n: "Marathon",             g: "Perk 3", d: "BASE perk." },
    { t: "specialty_unlimitedsprint",   n: "Marathon Pro",         g: "Perk 3", pro: 1, d: "Unlimited sprint. BASE perk." },
    { t: "specialty_quieter",           n: "Ninja",                g: "Perk 3" },
    { t: "specialty_loudenemies",       n: "Ninja Pro",            g: "Perk 3", pro: 1, d: "Enemy movement is louder" },
    { t: "specialty_pistoldeath",       n: "Second Chance",        g: "Perk 3", warn: "Last-stand in a ONE-LIFE round: a downed player may desync round-end / the alive-count HUD. Untested." },
    { t: "specialty_finalstand",        n: "Second Chance Pro",    g: "Perk 3", pro: 1, warn: "Same last-stand risk as Second Chance, and revivable." },
    { t: "specialty_detectexplosive",   n: "Hacker",               g: "Perk 3" },
    { t: "specialty_disarmexplosive",   n: "Hacker Pro",           g: "Perk 3", pro: 1, d: "Sabotage enemy equipment" },
    { t: "specialty_nomotionsensor",    n: "Hacker Pro",           g: "Perk 3", pro: 1, d: "Invisible to motion sensors" },
    // Engine leftovers — real, working tokens that are NOT any of Black Ops' 15 perks (no
    // create-a-class row, no icon of their own). Named for their effect, never given a
    // BO1-sounding name.
    { t: "specialty_armorvest",         n: "Body Armor",           g: "Non-BO1", d: "-20% NON-HEADSHOT BULLET damage. BASE perk. Not a Black Ops perk — engine leftover." },
    { t: "specialty_bulletdamage",      n: "Extra Bullet Damage",  g: "Non-BO1", d: "WaW Stopping Power. Not a Black Ops perk." },
    { t: "specialty_rof",               n: "Faster Fire Rate",     g: "Non-BO1", d: "WaW Double Tap. Not a Black Ops perk." },
    { t: "specialty_twoprimaries",      n: "Two Primaries",        g: "Non-BO1", d: "WaW Overkill. Not a Black Ops perk." },
    { t: "specialty_grenadepulldeath",  n: "Drop Live Grenade on Death", g: "Non-BO1", d: "WaW Martyrdom. Not a Black Ops perk." },
    { t: "specialty_explosivedamage",   n: "Extra Explosive Damage", g: "Non-BO1", d: "Not a Black Ops perk." },
];
const PERK_TOKENS = new Set( PERKS.map( p => p.t ) );

// The perks EVERY player already gets, from gf_giveCustomLoadout's base set. Only these can
// meaningfully be removed by a loadout (UnSetPerk on a perk nobody has is a no-op), so the
// editor's "remove" pickers are built from exactly this list.
// ⚠ Keep in lockstep with the SetPerk block in _gf_loadouts.gsc.
const BASE_PERKS = [
    "specialty_movefaster", "specialty_fallheight",       // Lightweight + Pro
    "specialty_longersprint", "specialty_unlimitedsprint",// Marathon + Pro
    "specialty_flakjacket",                               // Flak Jacket
    "specialty_armorvest",                                // Body Armor (-20% bullet, non-BO1 token)
    "specialty_shades", "specialty_stunprotection",       // Tactical Mask Pro (both halves)
    "specialty_loudenemies",                              // Ninja Pro half (everyone's footsteps louder)
    "specialty_fastmeleerecovery",                        // Steady Aim Pro half (faster melee-lunge recovery)
];
// ⚠ specialty_bulletflinch (Hardened Pro) is NOT a base perk and must not be added back here: it
// gates perk_damageKickReduction (default 0.2 = an 80% flinch cut), a SECOND multiplier under
// scr_gf_flinch. It belongs to the sniper/heavy package alone.

// One-click presets for the editor. The sniper/heavy package hands the weakest archetypes
// (scoped rifles, and the Minigun/M202 that can't ADS at all) full weapon handling: penetration,
// hip-fire, scope control and reload/swap speed. Every token is still written out explicitly on
// the pool line — the preset is just a fast way to select them, never a runtime indirection.
const PACKAGES = {
    sniper_heavy: {
        label: "Sniper / Heavy package",
        perks: [
            "specialty_bulletpenetration",   // Hardened
            "specialty_bulletflinch",        // Hardened Pro — reduced flinch when shot. The ONLY
                                             // loadouts that get it: it gates perk_damageKickReduction
                                             // (0.2 = an 80% cut) ON TOP of scr_gf_flinch, so it is a
                                             // class trait here, never a base perk.
            "specialty_bulletaccuracy",      // Steady Aim
            "specialty_sprintrecovery",      // Steady Aim Pro — faster ADS after sprint
            // specialty_fastmeleerecovery (Steady Aim Pro's melee half) is NOT here — it is a BASE
            // perk now, so every loadout already has it. Re-adding it would just be a duplicate SetPerk.
            "specialty_holdbreath",          // Scout
            "specialty_fastweaponswitch",    // Scout Pro — faster weapon switch
            "specialty_fastreload",          // Sleight of Hand
            "specialty_fastads",             // Sleight of Hand Pro — faster ADS
        ],
    },
};

function readFile()  { return fs.readFileSync( GSC_PATH, "utf8" ); }
function detectEol(s){ return s.indexOf( "\r\n" ) !== -1 ? "\r\n" : "\n"; }

// Pull the current loadouts out of the file (only lines between the markers).
function parseLoadouts()
{
    const text  = readFile();
    const eol    = detectEol( text );
    const lines  = text.split( /\r?\n/ );
    const out    = [];
    let inRegion = false, seenBegin = false, seenEnd = false;

    for ( const line of lines )
    {
        if ( line.indexOf( BEGIN ) !== -1 ) { inRegion = true;  seenBegin = true; continue; }
        if ( line.indexOf( END   ) !== -1 ) { inRegion = false; seenEnd   = true; continue; }
        if ( !inRegion ) continue;

        const m = line.match( LINE_RE );
        if ( m )
            out.push( { primary: m[1], secondary: m[2], equip: m[3], lethal: m[4], tactical: m[5],
                        camo:    parseInt( m[6], 10 ),
                        camoSec: m[7] !== undefined ? parseInt( m[7], 10 ) : parseInt( m[6], 10 ),
                        perks:   m[8] !== undefined ? m[8] : "" } );
    }

    if ( !seenBegin || !seenEnd )
        throw new Error( "editor markers not found in " + GSC_PATH + " (looked for " + BEGIN + " / " + END + ")" );

    return { loadouts: out, eol };
}

function pad( str, width ) { return str.length >= width ? str : str + " ".repeat( width - str.length ); }

// Regenerate one aligned pool line from an edited entry.
function formatLine( lo )
{
    const col  = ( tok, w ) => pad( '"' + tok + '",', w );
    const pnum = v => { const s = String( v ); return s.length < 3 ? " ".repeat( 3 - s.length ) + s : s; };
    // The perks field is only emitted when non-empty. That keeps a perk-less loadout's line
    // byte-identical to what it was before this feature, so migrating the file changes nothing
    // for the 53 lines you haven't touched.
    const perks = normPerks( lo.perks );
    return "    pool[n] = gf_load( " +
        col( lo.primary,   29 ) +
        col( lo.secondary, 27 ) +
        col( lo.equip,     23 ) +
        col( lo.lethal,    21 ) +
        col( lo.tactical,  25 ) +
        pnum( lo.camo ) + ", " + pnum( lo.camoSec ) +
        ( perks === "" ? "" : ', "' + perks + '"' ) +
        " ); n++;";
}

// "  a , -b ,, " -> "a,-b". Tolerates whitespace and stray commas from a hand-edited line.
function normPerks( perks )
{
    if ( typeof perks !== "string" ) return "";
    return perks.split( "," ).map( s => s.trim() ).filter( s => s !== "" ).join( "," );
}

// Validate the perk list: every token must be one the ENGINE actually knows (an unknown name is a
// silent no-op at runtime, so a typo here would ship a perk that simply never fires), and adds are
// capped at MAX_PERK_ADDS so the 3-slot overview can still show a base perk. A leading '-' removes.
function validPerks( perks )
{
    const list = normPerks( perks ).split( "," ).filter( s => s !== "" );
    let adds = 0;
    const seen = new Set();

    for ( const raw of list )
    {
        const remove = raw.startsWith( "-" );
        const tok    = remove ? raw.slice( 1 ) : raw;

        if ( !TOKEN_RE.test( tok ) )
            return "perk '" + raw + "' is not a valid token";
        if ( !PERK_TOKENS.has( tok ) )
            return "perk '" + tok + "' is not a specialty this engine knows — SetPerk would silently do nothing";
        if ( seen.has( tok ) )
            return "perk '" + tok + "' is listed twice";
        seen.add( tok );

        if ( !remove && ++adds > MAX_PERK_ADDS )
            return "too many added perks (max " + MAX_PERK_ADDS + ") — the overview only has 3 perk slots";
    }
    return null;
}

function validEntry( lo )
{
    const slots = [ "primary", "secondary", "equip", "lethal", "tactical" ];
    for ( const s of slots )
    {
        if ( typeof lo[s] !== "string" || !TOKEN_RE.test( lo[s] ) )
            return "slot '" + s + "' is not a valid weapon token: " + JSON.stringify( lo[s] );
        // "none" is the empty-slot token, and equipment is the only slot that may be empty
        // (_gf_loadouts.gsc skips the give for it). Anywhere else the engine would hand out
        // the finger-gun fallback instead of nothing.
        if ( lo[s] === "none" && s !== "equip" )
            return "slot '" + s + "' cannot be 'none' — only equipment may be empty";
    }
    for ( const key of [ "camo", "camoSec" ] )
    {
        const c = lo[key];
        if ( !Number.isInteger( c ) || c < -1 || c > 15 )
            return key + " must be an integer -1..15 (got " + JSON.stringify( c ) + ")";
    }
    return validPerks( lo.perks );
}

// Rewrite each pool line between the markers, in order, from the posted entries.
function writeLoadouts( entries )
{
    if ( !Array.isArray( entries ) )
        throw new Error( "expected an array of loadouts" );

    // Back-compat: an older editor page posts 6 fields (no camoSec). Default it to the
    // primary camo so a save from a pre-secondary-camo page still goes through. Likewise a
    // page with no perk pickers posts no perks — treat that as "no perks", never as a delete.
    for ( const lo of entries )
    {
        if ( lo && lo.camoSec === undefined ) lo.camoSec = lo.camo;
        if ( lo && lo.perks   === undefined ) lo.perks   = "";
    }

    for ( let i = 0; i < entries.length; i++ )
    {
        const err = validEntry( entries[i] );
        if ( err ) throw new Error( "loadout #" + ( i + 1 ) + ": " + err );
    }

    const text  = readFile();
    const eol    = detectEol( text );
    const lines  = text.split( /\r?\n/ );
    const result = [];
    let inRegion = false, idx = 0;

    for ( const line of lines )
    {
        if ( line.indexOf( BEGIN ) !== -1 ) { inRegion = true;  result.push( line ); continue; }
        if ( line.indexOf( END   ) !== -1 ) { inRegion = false; result.push( line ); continue; }

        if ( inRegion && LINE_RE.test( line ) )
        {
            if ( idx >= entries.length )
                throw new Error( "file has more loadout lines than were submitted (" + entries.length + ")" );
            result.push( formatLine( entries[ idx++ ] ) );
        }
        else
            result.push( line );
    }

    if ( idx !== entries.length )
        throw new Error( "count mismatch: file has " + idx + " loadout lines, submitted " + entries.length + " (no changes written)" );

    // Rolling backup, then write.
    fs.copyFileSync( GSC_PATH, GSC_PATH + ".editorbak" );
    fs.writeFileSync( GSC_PATH, result.join( eol ), "utf8" );
    return idx;
}

function sendJson( res, code, obj )
{
    const body = JSON.stringify( obj );
    res.writeHead( code, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } );
    res.end( body );
}

const server = http.createServer( ( req, res ) =>
{
    try
    {
        if ( req.method === "GET" && ( req.url === "/" || req.url === "/index.html" ) )
        {
            const html = fs.readFileSync( path.join( __dirname, "index.html" ) );
            res.writeHead( 200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } );
            res.end( html );
            return;
        }

        if ( req.method === "GET" && req.url === "/api/loadouts" )
        {
            const parsed = parseLoadouts();
            // The perk catalog rides along with the loadouts so the page's dropdowns are built
            // from the SAME list the save-time validator checks against — they cannot drift apart.
            sendJson( res, 200, { ok: true, path: GSC_PATH, count: parsed.loadouts.length,
                                  loadouts: parsed.loadouts, perks: PERKS, basePerks: BASE_PERKS,
                                  packages: PACKAGES, maxPerkAdds: MAX_PERK_ADDS } );
            return;
        }

        if ( req.method === "POST" && req.url === "/api/loadouts" )
        {
            let raw = "";
            req.on( "data", c => { raw += c; if ( raw.length > 2e6 ) req.destroy(); } );
            req.on( "end", () =>
            {
                try
                {
                    const body    = JSON.parse( raw );
                    const written = writeLoadouts( body.loadouts );
                    sendJson( res, 200, { ok: true, written: written } );
                }
                catch ( e ) { sendJson( res, 400, { ok: false, error: String( e.message || e ) } ); }
            } );
            return;
        }

        sendJson( res, 404, { ok: false, error: "not found" } );
    }
    catch ( e )
    {
        sendJson( res, 500, { ok: false, error: String( e.message || e ) } );
    }
} );

server.listen( PORT, HOST, () =>
{
    console.log( "" );
    console.log( "  Gunfight Loadout Editor" );
    console.log( "  Editing: " + GSC_PATH );
    console.log( "  Open:    http://" + HOST + ":" + PORT );
    console.log( "" );
    console.log( "  (Ctrl+C to stop. A backup is saved to _gf_loadouts.gsc.editorbak on each save.)" );
} );
