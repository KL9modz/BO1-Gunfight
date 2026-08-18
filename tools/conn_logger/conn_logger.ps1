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
# IN-GAME ADMIN NOTICE (added 2026-08-09): on a CONNECT this also puts ONE coloured line -
# name, city/country, ISP, a [VPN/HOST] tag - into the KILLFEED of whoever holds the panel's
# admin star, via the bridge's adminmsg verb. Admins only; nobody else sees it. Both calls go
# through the panel on loopback (geo + the rcon write), so it adds no rcon poller and no second
# ip-api client. Off with -AdminNotice $false; the full IP is opt-in (-AdminNoticeIp $true).
# It is strictly a notification: a failure warns and is dropped, never costing the day-file line.
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
    [int]    $StaleSeconds    = 30,
    # Loopback port of the RCON panel. When admin.json is stale/absent this logger asks the
    # panel's /api/status directly instead of going blind - see the fallback note below. Set 0
    # to disable the fallback and restore file-only behaviour.
    [int]    $PanelPort       = 3000,
    # The panel's /api/status needs the target server + rcon password like any other caller
    # (it proxies rcon, it does not guess). Password is read from dedicated.cfg at runtime,
    # never stored here - same contract as status_service and join-notify.
    [string] $RconHost        = '127.0.0.1',
    [int]    $RconPort        = 28960,
    [string] $CfgPath         = '',
    # In-game admin notice: on a CONNECT, put a one-line "who joined and from where" into the
    # KILLFEED of whoever holds the panel's admin star (gf_admin_guids), via the bridge's adminmsg
    # verb. Nobody else sees it. $false = off (the day-file + ntfy paths are untouched either way).
    [bool]   $AdminNotice     = $true,
    # Include the joiner's full IP in that line. OFF by default ON PURPOSE: the line renders on the
    # admin's screen, so a screenshot or a stream publishes a player's address - and the geo below
    # is the part that is actually readable at a glance. The IP is always in the day-file and one
    # panel click away, so this only ever buys convenience, never access.
    [bool]   $AdminNoticeIp   = $false,
    # Mute list (shared with GF-StatusService / GF-JoinNotify): an ignored player's join raises no
    # in-game notice. Chiefly so the owner's own connects don't announce themselves.
    [string] $IgnoreFile      = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\common.ps1')       # Resolve-T5Root
# Shared with GF-StatusService / GF-JoinNotify: Get-GfIgnoreList (mtime-cached) + Test-GfIgnored.
# ⚠ Used ONLY to suppress the in-game notice. The day-files stay complete for an ignored player -
# same contract as status_service, which filters at the projection and never at the source.
. (Join-Path $PSScriptRoot '..\ignore_list.ps1')

# --- Resolve default paths ----------------------------------------------------
# storage\t5\ (where the logs\ folder lives); common.ps1 resolves it from its fixed location.
$storageT5 = Resolve-T5Root

if ([string]::IsNullOrEmpty($LogDir))     { $LogDir     = Join-Path $storageT5 'logs' }
if ([string]::IsNullOrEmpty($IgnoreFile)) { $IgnoreFile = Join-Path $PSScriptRoot '..\ignore.local.json' }

$stateFile = Join-Path $LogDir '.connstate.json'

# --- Panel fallback: why this exists ------------------------------------------
# Reading admin.json is the cheap path (zero rcon), but it has a SILENT DATA-LOSS mode. When the
# file is stale/absent/offline this logger skips its diff (correctly - a missing snapshot must
# never read as "everyone left"), and a player who joins AND leaves inside that window is never
# recorded at all. Measured 2026-08-06: 4/9/15/16 blind stretches per day across 08-03..08-06,
# and 2 of 52 players announced by GF-JoinNotify in that window (AdrianRGamer, "Mr") appear
# NOWHERE in the day-files. The connect history is the one dataset on this box nothing else
# reproduces (MIGRATION.md calls it irreplaceable), so a 4% silent loss rate is not acceptable.
#
# GF-JoinNotify never went blind through any of it because it reads the panel's /api/status
# directly. So does this logger now, but ONLY when the file path fails - the file stays the
# default, and the fallback costs one extra request to a queue that is already coalescing.
# ⚠ This is NOT a second rcon poller: it goes through the panel's paced/coalescing queue, the
# same sanctioned route status_service and join-notify use. Never point it at rcon directly.
# ⚠ The panel PROXIES rcon - it does not guess a target. Called with no query params it falls
# back to loopback defaults with an EMPTY password, rcon auth fails, and the fallback silently
# returns nothing (caught end-to-end 2026-08-07: the first cut did exactly this and logged
# "no data from admin.json OR the panel" while the panel was perfectly healthy). Pass
# host/port/password explicitly, exactly as join-notify and status_service do.
if ([string]::IsNullOrEmpty($CfgPath)) { $CfgPath = Join-Path $storageT5 'dedicated.cfg' }
$script:PanelUrl  = ''
$script:PanelBase = ''
$script:PanelPw   = ''
if ($PanelPort -gt 0) {
    $pw = ''
    try { $pw = Get-RconPassword -CfgPath $CfgPath } catch { $pw = '' }
    if ([string]::IsNullOrEmpty($pw)) {
        Write-Warning "no rcon_password found in $CfgPath - panel fallback DISABLED (file-only, blind windows return)"
    } else {
        $script:PanelBase = 'http://127.0.0.1:{0}' -f $PanelPort
        $script:PanelPw   = $pw
        $script:PanelUrl  = '{0}/api/status?host={1}&port={2}&password={3}' -f `
                            $script:PanelBase, $RconHost, $RconPort, [uri]::EscapeDataString($pw)
    }
}

# --- In-game admin notice -----------------------------------------------------
# One line into the admin star's killfeed when a human connects. Everything it needs already
# existed; this only joins them up:
#   * this logger already has name / IP / GUID for every connect (the diff below),
#   * the panel already resolves geo (its disk-cached, rate-paced ip-api client),
#   * the bridge already prints privately to gf_admin_guids (gf_bridgeNotify).
# ⚠ Panel-first: BOTH calls go through the panel on loopback. This adds no rcon poller and no
#   second ip-api client - the two rules this box's services are built around.

# Strip what would break the line. EVERY caret goes, not just well-formed ^<digit> codes: a
# player-supplied ^1 would recolour the rest of our line, and a trailing bare ^ would swallow the
# first character of the tag we append after it. Then the two characters the cfg/rcon parser treats
# as structure: " ends the dvar value early and ; splits the command - a name carrying either is a
# PLAYER injecting an rcon command by renaming themselves, so this one is a security strip, not
# cosmetics. Finally clamp the length: the whole line is one dvar value over rcon, and window 0
# only holds ~4 lines.
function Format-NoticeField {
    param([string]$s, [int]$max = 24)
    if ($null -eq $s) { return '' }
    $t = $s -replace '\^', ''
    $t = $t -replace '["\;\r\n]', ''
    $t = $t.Trim()
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max) }
    return $t
}

# BLOCKING single lookup (?ip=), not the roster's non-blocking ?ips= batch. This is exactly the
# case that mode is documented for - one lookup, once, with somebody waiting on the answer - and
# it is what makes the FIRST join from a new IP carry a location instead of an empty tag. Called
# only after the day-file write has already succeeded, so geo can never delay the record itself.
function Get-GeoTag {
    param([string]$ipPort)
    if ([string]::IsNullOrEmpty($script:PanelBase)) { return '' }
    $ip = ($ipPort -split ':')[0]
    if ([string]::IsNullOrEmpty($ip)) { return '' }
    try {
        $r = Invoke-RestMethod -UseBasicParsing -TimeoutSec 6 -Uri ('{0}/api/geoip?ip={1}' -f $script:PanelBase, $ip)
    } catch { return '' }
    if ($null -eq $r -or -not $r.ok) { return '' }

    $where = @()
    if ($r.city)    { $where += (Format-NoticeField $r.city 20) }
    if ($r.country) { $where += (Format-NoticeField $r.country 20) }
    $tag = ''
    if ($where.Count) { $tag = '^5' + ($where -join ', ') }
    if ($r.isp)      { $tag += '  ^7' + (Format-NoticeField $r.isp 22) }
    # Worth an admin's attention on sight: a connection from a datacentre / known proxy is the
    # shape a ban evader or a booter arrives in.
    if ($r.proxy -or $r.hosting) { $tag += '  ^1[VPN/HOST]' }
    return $tag
}

# One batched rcon send: two separate packets race on the panel's paced queue, which is what the
# panel's own Say learned the hard way (app.js "two separate packets raced"). Unstamped (no
# "<seq>:") on purpose - seq 0 is never deduped by gf_bridgePoll and never touches the panel's
# high-water mark, so this can never collide with a seq the panel is waiting on an ack for.
function Send-AdminNotice {
    param([string]$msg)
    if ([string]::IsNullOrEmpty($script:PanelBase)) { return }
    try {
        # Through common.ps1's shared panel-rcon POST (same priority-lane semantics the hand-rolled
        # body here used to duplicate; the helper grew -RconHost/-RconPort so nothing was lost).
        Invoke-GfPanelRcon -Pw $script:PanelPw -PanelPort $PanelPort -TimeoutSec 10 `
                           -RconHost $RconHost -RconPort $RconPort `
                           -Command ('set gf_adminsay "{0}";set gf_cmd adminmsg' -f $msg) | Out-Null
    } catch {
        # Cosmetic channel: the day-file record is already written and ntfy already fired. A failed
        # notice must never cost us the log line, and must never take the service down.
        Write-Warning ("admin notice send failed: {0}" -f $_.Exception.Message)
    }
}

# Shape-convert the panel's /api/status JSON into the same object Read-AdminSnapshot returns, so
# the diff downstream cannot tell which source it came from. The panel's parsed players carry
# the identical field names (num/name/ping/guid/bot/addr) via tools\status_parse.js.
function Convert-PanelStatus {
    param($panel)
    if ($null -eq $panel -or -not $panel.ok) { return $null }
    $players = @()
    foreach ($p in @($panel.players)) {
        if ($null -eq $p) { continue }
        # bot -eq $false is a POSITIVE human claim; $null (unclassifiable) must not be logged.
        if ($p.bot -ne $false) { continue }
        $players += ,([pscustomobject]@{
            num  = $p.num
            name = [string]$p.name
            ping = $(if ($null -ne $p.ping) { $p.ping } else { 0 })
            guid = [string]$p.guid
            ip   = [string]$p.addr
        })
    }
    return [pscustomobject]@{ updated = (Get-Date).ToString('o'); online = $true; players = $players }
}

function Get-PanelSnapshot {
    if ([string]::IsNullOrEmpty($script:PanelUrl)) { return $null }
    try {
        $r = Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 -Uri $script:PanelUrl
        return (Convert-PanelStatus $r)
    } catch { return $null }   # panel down too -> genuinely no data this tick
}

# --- Read the admin.json snapshot ---------------------------------------------
# Returns the parsed object, or $null when there is no trustworthy data this tick
# (missing / locked-mid-write / bad JSON / stale). $null => caller SKIPS the diff.
function Read-AdminSnapshot {
    param([string]$path, [int]$staleSeconds)
    # EVERY filesystem touch is inside the try, Test-Path included. Under this script's
    # $ErrorActionPreference='Stop' a transient "Access is denied" from Test-Path is TERMINATING,
    # and that is exactly what killed the service at 2026-08-07 08:29:04 - while the Get-Content
    # one line below was ALREADY guarded against the same status_service file-swap race. Probing
    # a file another process is actively replacing can fail just as readily as reading it, so the
    # probe needs the same guard as the read. Any failure here means the same thing either way:
    # no trustworthy snapshot this tick, so return $null and let the caller skip the diff.
    try {
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $obj = Get-Content -Raw -Path $path -ErrorAction Stop | ConvertFrom-Json
    } catch {
        return $null   # missing, locked mid-swap, access denied, torn read, or bad JSON
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
    # Test-Path INSIDE the try - same reason as Read-AdminSnapshot. A throw here would kill the
    # process before its first tick, and Task Scheduler's RestartOnFailure would then crash-loop
    # it. An unreadable state file is harmless: an empty $state just re-emits CONNECT for whoever
    # is already online, which is strictly better than not starting.
    try {
        if (Test-Path -LiteralPath $path) {
            $arr = Get-Content -Raw -Path $path | ConvertFrom-Json
            foreach ($r in $arr) {
                if ($null -ne $r -and $r.key) {
                    $state[$r.key] = @{ key = $r.key; name = $r.name; ip = $r.ip; guid = $r.guid; firstSeen = $r.firstSeen }
                }
            }
        }
    } catch { }
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
    # ⚠ STRIP QUOTES (and newlines) FROM THE NAME. name="..." is the one free-text field in this
    # record, so a name containing a double quote makes the whole line AMBIGUOUS to every reader:
    # a player called  x"  guid=<someone-else>  ping=1  writes a line that parses, correctly, as a
    # record for THAT other guid. No reader-side regex can undo it (greedy, lazy and [^"]* all
    # match the forged reading), so the fix has to be here, at the writer. Same reasoning as the
    # admin-notice sanitizer, which strips " and ; before a name can reach an rcon command.
    $safeName = ([string]$p.name) -replace '["\r\n]', "'"
    $line  = '{0}  {1,-8} ip={2}  name="{3}"  guid={4}  ping={5}{6}' -f `
             $stamp, $verb, $p.ip, $safeName, $p.guid, $p.ping, $extra
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
# The last two unguarded filesystem probes. These run once per process rather than every 5s, so
# they are far less likely to hit a race - but a throw here is WORSE than one in the loop: the
# service dies before its first tick and RestartOnFailure turns that into a crash-loop, retrying
# 999 times a minute apart. A missing log dir is fatal anyway (Write-Event would fail), so let
# that one propagate; the coldStart probe is cosmetic and must never be fatal - failing to read
# it merely mislabels the first batch ONLINE vs CONNECT.
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

$coldStart = $true
try { $coldStart = -not (Test-Path -LiteralPath $stateFile) } catch { $coldStart = $false }
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
    $src     = 'admin.json'
    $snap    = Read-AdminSnapshot -path $AdminJson -staleSeconds $StaleSeconds
    $current = Get-CurrentPlayers -snap $snap

    # File path gave nothing usable -> ask the panel before declaring a blind tick. This is the
    # whole point of the fallback: the old code went blind here and lost sessions outright.
    if ($null -eq $current) {
        $snap = Get-PanelSnapshot
        $current = Get-CurrentPlayers -snap $snap
        if ($null -ne $current) { $src = 'panel' }
    }

    if ($null -eq $current) {
        # BOTH sources failed - genuinely no data (server down, or panel down too). Skipping the
        # diff is still right: a missing snapshot must never read as a mass LEFT.
        if ($hadData) {
            Write-Warning 'no data from admin.json OR the panel; skipping diff (server offline?)'
            $hadData = $false
            $script:blindSince = Get-Date
        }
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }
    # Recovery was previously SILENT, so a blind stretch had no measurable duration and this
    # whole data-loss class went unnoticed until a player was spotted missing by hand. Say how
    # long we were blind - that number is the thing to watch.
    if (-not $hadData) {
        $blindFor = 0
        if ($script:blindSince) { $blindFor = [int]((Get-Date) - $script:blindSince).TotalSeconds }
        Write-Host ("[{0}] data RECOVERED via {1} after {2}s blind (any session that started AND ended in that window is lost)" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $src, $blindFor)
        $script:blindSince = $null
    }
    if ($src -eq 'panel') {
        Write-Host ("[{0}] admin.json unusable this tick - roster read from the panel instead" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
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
                # CONNECT only, never ONLINE: the cold-start batch is "who was already here", and
                # announcing six of those the moment the service restarts would flood the killfeed
                # of an admin who is mid-round - and evict the obituaries while doing it.
                if ($AdminNotice -and $verb -eq 'CONNECT' -and
                    -not (Test-GfIgnored (Get-GfIgnoreList $IgnoreFile) $p.guid $p.name)) {
                    $line = '^2JOIN ^7{0}' -f (Format-NoticeField $p.name)
                    $geo  = Get-GeoTag $p.ip
                    if ($geo)            { $line += '  ' + $geo }
                    if ($AdminNoticeIp)  { $line += '  ^7' + (($p.ip -split ':')[0]) }
                    Send-AdminNotice $line
                }
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
