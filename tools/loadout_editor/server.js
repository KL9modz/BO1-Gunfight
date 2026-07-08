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

// One gf_load pool line: pool[n] = gf_load( "p", "s", "e", "l", "t", camo ); n++;
const LINE_RE = /pool\[n\]\s*=\s*gf_load\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(-?\d+)\s*(?:,\s*(-?\d+)\s*)?\)\s*;\s*n\+\+\s*;/;
const TOKEN_RE = /^[a-z0-9_]+$/;   // whitelist — tokens are the only thing we inject into code

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
                        camoSec: m[7] !== undefined ? parseInt( m[7], 10 ) : parseInt( m[6], 10 ) } );
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
    return "    pool[n] = gf_load( " +
        col( lo.primary,   29 ) +
        col( lo.secondary, 27 ) +
        col( lo.equip,     23 ) +
        col( lo.lethal,    21 ) +
        col( lo.tactical,  25 ) +
        pnum( lo.camo ) + ", " + pnum( lo.camoSec ) +
        " ); n++;";
}

function validEntry( lo )
{
    const slots = [ "primary", "secondary", "equip", "lethal", "tactical" ];
    for ( const s of slots )
        if ( typeof lo[s] !== "string" || !TOKEN_RE.test( lo[s] ) )
            return "slot '" + s + "' is not a valid weapon token: " + JSON.stringify( lo[s] );
    for ( const key of [ "camo", "camoSec" ] )
    {
        const c = lo[key];
        if ( !Number.isInteger( c ) || c < -1 || c > 15 )
            return key + " must be an integer -1..15 (got " + JSON.stringify( c ) + ")";
    }
    return null;
}

// Rewrite each pool line between the markers, in order, from the posted entries.
function writeLoadouts( entries )
{
    if ( !Array.isArray( entries ) )
        throw new Error( "expected an array of loadouts" );

    // Back-compat: an older editor page posts 6 fields (no camoSec). Default it to the
    // primary camo so a save from a pre-secondary-camo page still goes through.
    for ( const lo of entries )
        if ( lo && lo.camoSec === undefined ) lo.camoSec = lo.camo;

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
            sendJson( res, 200, { ok: true, path: GSC_PATH, count: parsed.loadouts.length, loadouts: parsed.loadouts } );
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
