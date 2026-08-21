# BO1 map id -> display name - the single source of truth shared by GF-JoinNotify
# (join-notify.ps1) and GF-StatusService (status_service.ps1), so a map reads the same on
# your phone, on the website and in the admin console.
#
# This mirrors the MAPS table in tools\rcon\public\app.js. The admin console is a browser app
# and cannot dot-source PowerShell, so those two copies are unavoidable - app.js is the
# authority (it also carries the gf/dlc flags this table has no use for). Keep them in sync.
#
# An unknown id falls through to the RAW id unchanged, so a new or custom map degrades to
# "mp_whatever" in an alert rather than blanking the map out of it.

$script:GfMapNames = @{
    # Base game (14)
    'mp_array'      = 'Array'        ; 'mp_cairo'    = 'Havana'
    'mp_cosmodrome' = 'Launch'       ; 'mp_cracked'  = 'Cracked'
    'mp_crisis'     = 'Crisis'       ; 'mp_duga'     = 'Grid'
    'mp_firingrange'= 'Firing Range' ; 'mp_hanoi'    = 'Hanoi'
    'mp_havoc'      = 'Jungle'       ; 'mp_mountain' = 'Summit'
    'mp_nuked'      = 'Nuketown'     ; 'mp_radiation'= 'Radiation'
    'mp_russianbase'= 'WMD'          ; 'mp_villa'    = 'Villa'
    # First Strike (4)
    'mp_berlinwall2'= 'Berlin Wall'  ; 'mp_discovery'= 'Discovery'
    'mp_kowloon'    = 'Kowloon'      ; 'mp_stadium'  = 'Stadium'
    # Escalation (4)
    'mp_gridlock'   = 'Convoy'       ; 'mp_hotel'    = 'Hotel'
    'mp_outskirts'  = 'Stockpile'    ; 'mp_zoo'      = 'Zoo'
    # Annihilation (4)
    'mp_drivein'    = 'Drive-In'     ; 'mp_area51'   = 'Hangar 18'
    'mp_golfcourse' = 'Hazard'       ; 'mp_silo'     = 'Silo'
}

# Where the rehosted map art is served from. tools\fetch_map_art.ps1 stages the files into
# site\wwwroot\assets\maps and deploy.ps1 -Web publishes them; the pictures themselves come from
# Plutonium's own rich-presence assets (see that script for the source, and for why we rehost
# rather than hotlink their CDN).
$script:GfMapArtBase = 'https://gunfight.us/assets/maps'

# PowerShell hashtable lookups are case-insensitive, so a `status` line reporting MP_Nuked
# resolves the same as mp_nuked.
function Get-GfMapName {
    param([string]$Raw)

    $k = ([string]$Raw).Trim()
    if (-not $k) { return '' }
    if ($script:GfMapNames.ContainsKey($k)) { return $script:GfMapNames[$k] }
    return $k
}

# The map picture for an alert embed, or '' when there is nothing to show.
#
# ⚠ Keyed off the TABLE ABOVE, deliberately - the art set and that table are the same 26 maps by
# construction (both are the stock game's map list), so a hit here is a guaranteed image and a miss
# is a guaranteed 404. Building a URL for an unknown id anyway would send every reader's Discord
# client off to fetch a file we already know is not there.
#
# ⚠ LOWERCASED on the way out. The lookup above is case-insensitive but a web server's paths are
# not, so a `status` line reading MP_Nuked must not produce /assets/maps/MP_Nuked.jpg.
#
# ⚠ This is the ONE image mechanism available to us: an embed thumbnail takes any public https URL,
# whereas the bot's own PRESENCE ignores art entirely (docs/notes/bot-presence-is-text-only.md).
function Get-GfMapThumb {
    param([string]$Raw)

    $k = ([string]$Raw).Trim()
    if (-not $k) { return '' }
    if (-not $script:GfMapNames.ContainsKey($k)) { return '' }
    return "$script:GfMapArtBase/$($k.ToLower()).jpg"
}
