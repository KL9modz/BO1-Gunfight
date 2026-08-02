# conn_logger.ps1 - Gunfight VPS connection logger (reads status_service's admin.json)
# ------------------------------------------------------------------------------
# Appends a clean, grep-friendly record of every player connect / disconnect -
# including their IP and GUID - to a dated log file on the box
# (storage\t5\logs\players_YYYY-MM-DD.log). The RCON web admin page's searchable
# history (admin_history.json) is built from these files by status_service.
#
# SOURCE (changed 2026-07-05): this logger NO LONGER polls RCON itself. It diffs
# the roster snapshot that status_service already writes every 5s to admin.json
# (the auth-gated admin page's data file, which carries per-player IP + GUID).
# WHY: status_service is the single box-side RCON reader; a second poller here only
# competed for the server's ~1-reply-per-0.7s rcon limit (and could eat replies).
# Reading its output file adds ZERO rcon load AND inherits its 5s cadence (was 15s),
# so short sessions are caught more reliably. admin.json is written atomically
# (temp + Move), so reads are never torn.
#
# DEPENDENCY: needs status_service running with -AdminOutFile set AND the .secured
# marker present (that is what makes admin.json exist). If admin.json is missing or
# stale (older than -StaleSeconds) or reports the server offline, this logger simply
# skips that tick - it never misreads "no snapshot" as "everyone left".
#
# Windows PowerShell 5.1 compatible. ASCII-only source.
#
# Usage (interactive test):
#   powershell -ExecutionPolicy Bypass -File conn_logger.ps1
# Usage (as a boot service): registered by tools\vps_services\register_services.ps1.
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    # Roster snapshot written by status_service (carries IP + GUID for humans).
    [string] $AdminJson       = 'C:\inetpub\wwwroot\admin\live\admin.json',
    [int]    $IntervalSeconds = 5,
    [string] $LogDir          = '',
    # Ignore an admin.json older than this many seconds (status_service dead / stuck)
    # so a stale file is not mistaken for the live roster.
    [int]    $StaleSeconds    = 30
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\common.ps1')   # Resolve-T5Root

# --- Resolve default paths ----------------------------------------------------
# storage\t5\ (where the logs\ folder lives); common.ps1 resolves it from its fixed location.
$storageT5 = Resolve-T5Root

if ([string]::IsNullOrEmpty($LogDir)) { $LogDir = Join-Path $storageT5 'logs' }

$stateFile = Join-Path $LogDir '.connstate.json'

# --- Read the admin.json snapshot ---------------------------------------------
# Returns the parsed object, or $null when there is no trustworthy data this tick
# (missing / locked-mid-write / bad JSON / stale). $null => caller SKIPS the diff.
function Read-AdminSnapshot {
    param([string]$path, [int]$staleSeconds)
    if (-not (Test-Path $path)) { return $null }
    try {
        $obj = Get-Content -Raw -Path $path -ErrorAction Stop | ConvertFrom-Json
    } catch {
        return $null   # torn read while status_service swaps the file, or bad JSON
    }
    if ($obj.updated) {
        try {
            $age = ((Get-Date) - [DateTime]::Parse($obj.updated)).TotalSeconds
            if ($age -gt $staleSeconds) { return $null }
        } catch { }
    }
    return $obj
}

# Build a key -> player hashtable from a FRESH+ONLINE snapshot. Returns $null when
# the snapshot is absent or the server is offline (so the loop skips the diff and
# never emits a spurious "everyone left"). An ONLINE snapshot with an empty roster
# correctly returns an empty hashtable (=> anyone still in state is logged LEFT).
function Get-CurrentPlayers {
    param($snap)
    if ($null -eq $snap) { return $null }
    if (-not $snap.online) { return $null }
    $players = @{}
    foreach ($p in @($snap.players)) {
        if ($null -eq $p) { continue }
        $ip   = [string]$p.ip
        # Real humans only: require an ip:port. Skips bots (ip='') AND clients still
        # connecting / mis-tokenized status rows (guid 0, the address column holding a
        # lastmsg value, changing every tick) - which would otherwise key on a moving
        # bogus "ip" and spam CONNECT/LEFT. Restores the old direct-status logger's guard.
        if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}:-?\d+$') { continue }   # -? : port prints signed-16-bit, can be negative (ip:-NNNNN)
        $guid = if ($p.guid) { [string]$p.guid } else { '' }
        $name = if ($p.name) { [string]$p.name } else { '(unknown)' }
        $ping = if ($null -ne $p.ping) { [string]$p.ping } else { '-' }
        # Key by GUID when present (survives name/port changes); else the ip:port.
        $key = if ($guid -and $guid -ne '0') { $guid } else { $ip }
        if ([string]::IsNullOrEmpty($key)) { continue }
        $players[$key] = @{ key = $key; name = $name; ip = $ip; guid = $guid; ping = $ping }
    }
    return $players
}

# --- State persistence (survives a logger restart, avoids duplicate CONNECTs) --
function Load-State {
    param([string]$path)
    $state = @{}
    if (Test-Path $path) {
        try {
            $arr = Get-Content -Raw -Path $path | ConvertFrom-Json
            foreach ($r in $arr) {
                if ($null -ne $r -and $r.key) {
                    $state[$r.key] = @{ key = $r.key; name = $r.name; ip = $r.ip; guid = $r.guid; firstSeen = $r.firstSeen }
                }
            }
        } catch { }
    }
    return $state
}

function Save-State {
    param([string]$path, [hashtable]$state)
    $arr = @()
    foreach ($k in $state.Keys) { $arr += ,$state[$k] }
    # Wrap single-element arrays so ConvertFrom-Json still yields an array next load.
    ,$arr | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
}

# --- Logging ------------------------------------------------------------------
function Get-LogPath {
    param([string]$dir)
    return (Join-Path $dir ('players_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')))
}

# Returns $true only when the line actually reached the day-file. Under the script-wide
# $ErrorActionPreference='Stop', an unguarded Add-Content here was a process-killer: one
# transient lock (AV scan, a reader mid-sweep) and the whole service died with no evidence
# (the 2026-08-02 death). One short retry absorbs the transient case; on a real failure the
# CALLER leaves $state untouched, so the very same event re-derives from the next tick's
# diff - a failed write delays the record by one tick, it never loses it.
function Write-Event {
    param([string]$dir, [string]$verb, [hashtable]$p, [string]$extra = '')
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = '{0}  {1,-8} ip={2}  name="{3}"  guid={4}  ping={5}{6}' -f `
             $stamp, $verb, $p.ip, $p.name, $p.guid, $p.ping, $extra
    foreach ($attempt in 1, 2) {
        try {
            Add-Content -Path (Get-LogPath $dir) -Value $line -Encoding UTF8
            Write-Host $line
            return $true
        } catch {
            if ($attempt -eq 1) { Start-Sleep -Milliseconds 250 }
            else { Write-Warning ("event write failed ({0}); state untouched, event re-derives next tick: {1}" -f $_.Exception.Message, $line) }
        }
    }
    return $false
}

# --- Startup ------------------------------------------------------------------
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

$coldStart = -not (Test-Path $stateFile)
$state     = Load-State $stateFile
$firstPoll = $true
$hadData   = $true    # only warn on the transition into a no-data stretch

$banner = ('{0}  ----- conn_logger started (source={1} interval={2}s) -----' -f `
           (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $AdminJson, $IntervalSeconds)
# Best-effort: a locked day-file at startup must not kill the service before its first tick.
# The Write-Host copy still reaches the per-service log via run_service.ps1 either way.
try { Add-Content -Path (Get-LogPath $LogDir) -Value $banner -Encoding UTF8 }
catch { Write-Warning ("startup banner write failed ({0}); continuing" -f $_.Exception.Message) }
Write-Host $banner

# --- Poll loop ----------------------------------------------------------------
while ($true) {
    $snap    = Read-AdminSnapshot -path $AdminJson -staleSeconds $StaleSeconds
    $current = Get-CurrentPlayers -snap $snap

    if ($null -eq $current) {
        # No fresh, online snapshot this tick. Do NOT diff - skip so a missing/stale
        # admin.json (status_service down, or server offline) is not read as a mass LEFT.
        if ($hadData) {
            Write-Warning 'no fresh online admin.json this tick (status_service down or server offline); skipping diff'
            $hadData = $false
        }
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }
    $hadData = $true

    # New connections. State is updated ONLY on a successful write - a failed write leaves
    # the player out of $state, so the next tick's diff re-emits the CONNECT (delayed, never
    # lost). Same pattern for departures below.
    foreach ($key in $current.Keys) {
        if (-not $state.ContainsKey($key)) {
            $p = $current[$key]
            $verb = if ($firstPoll -and $coldStart) { 'ONLINE' } else { 'CONNECT' }
            if (Write-Event -dir $LogDir -verb $verb -p $p) {
                $state[$key] = @{ key = $key; name = $p.name; ip = $p.ip; guid = $p.guid; firstSeen = (Get-Date).ToString('o') }
            }
        }
    }

    # Departures
    $goneKeys = @()
    foreach ($key in $state.Keys) { if (-not $current.ContainsKey($key)) { $goneKeys += $key } }
    foreach ($key in $goneKeys) {
        $s = $state[$key]
        $extra = ''
        if ($s.firstSeen) {
            try {
                $dur = (Get-Date) - [DateTime]::Parse($s.firstSeen)
                $extra = '  session={0}m{1:00}s' -f [int]$dur.TotalMinutes, $dur.Seconds
            } catch { }
        }
        $p = @{ ip = $s.ip; name = $s.name; guid = $s.guid; ping = '-' }
        if (Write-Event -dir $LogDir -verb 'LEFT' -p $p -extra $extra) {
            $state.Remove($key)
        }
    }

    # In-memory state is authoritative; a failed persist just means this tick's bookmark is
    # stale on disk. Retried naturally next tick - do not let it kill the process (the state
    # file shares the same transient-lock exposure as the day-file writes above).
    try { Save-State -path $stateFile -state $state }
    catch { Write-Warning ("state save failed ({0}); keeping in-memory state, retrying next tick" -f $_.Exception.Message) }
    $firstPoll = $false
    Start-Sleep -Seconds $IntervalSeconds
}
