# status_service.ps1 - public server-status snapshot for the website (run ON the VPS)
# ------------------------------------------------------------------------------
# Polls the dedicated server over loopback RCON and writes a small, PUBLIC-SAFE
# JSON snapshot that the static status page (site\wwwroot\status.html) fetches and
# renders as a read-only scoreboard: map, gametype, match score, per-team roster
# (alive/ping), and a short recent-activity feed.
#
# It also writes activity.json beside it: a PUBLIC, 7-day connect/leave history parsed from the
# same players_*.log day-files that feed the admin page's searchable history.
#
# PRIVACY: both public files are world-readable (served by IIS). They carry player NAMES - the
# same info anyone sees in the in-game server browser - plus a 2-letter COUNTRY CODE. They do NOT
# include IP addresses or GUIDs. The country code is derived from the IP on the box (via the RCON
# panel's cached ip-api resolver) and the IP is dropped before anything is written here; the raw
# IP connect log (conn_logger) and admin_history.json stay behind the .secured/Basic-auth gate.
#
# Merges the same three sources the RCON panel uses:
#   gf_state  -> "alliesWins:axisWins:round:aliveAllies:aliveAxis:gametype"
#   gf_roster -> "<num>,<team>,<alive>,<pending>;..."  (team a/x/s/-, alive 1/0)
#   status    -> per-client num / name / ping (IP column is read but DROPPED)
#
# The RCON password is read from dedicated.cfg at runtime (never written out).
# Windows PowerShell 5.1 compatible. ASCII-only source.
#
#   powershell -ExecutionPolicy Bypass -File status_service.ps1
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string] $RconHost      = '127.0.0.1',
    [int]    $RconPort      = 28960,
    [int]    $IntervalSeconds = 5,
    [string] $RconPassword  = '',
    [string] $CfgPath       = '',
    [string] $OutFile       = 'C:\inetpub\wwwroot\live\status.json',
    # Admin (with-IP) snapshot. Written ONLY if -AdminOutFile is set AND a
    # ".secured" marker exists in its parent folder (created by setup_admin_auth.ps1
    # once IIS Basic auth is confirmed on that folder). Fail-safe: no marker = no
    # IP data ever reaches the web root.
    [string] $AdminOutFile  = '',
    [string] $LogDir        = '',
    [int]    $AdminLogTail  = 40,
    # Multi-day searchable connect history (with IPs) for the admin page. Written next
    # to $AdminOutFile as admin_history.json (same folder, same .secured gate). It only
    # reads the static players_*.log day-files, so it is rebuilt every
    # $AdminHistoryEverySec seconds - NOT every poll - and adds zero rcon load.
    [int]    $AdminHistoryDays     = 60,
    [int]    $AdminHistoryMax      = 5000,
    [int]    $AdminHistoryEverySec = 60,
    [string] $AdminHistoryFile     = '',
    # PUBLIC connect/leave history for the website's status page, written beside $OutFile as
    # activity.json. Built from the SAME players_*.log day-files as the admin history, but
    # PII-STRIPPED: time, name, event, session length and a 2-letter country code only - never
    # an IP or GUID. That is what makes it safe to serve unauthenticated, unlike admin_history.json.
    # Rebuilt on the $AdminHistoryEverySec cadence (static day-files; zero rcon cost).
    # NOTE: it inherits conn_logger's dependency chain - no .secured marker => no admin.json =>
    # conn_logger writes no day-files => this feed is empty. status.js falls back to the live
    # in-memory `recent` ring in that case, so the page degrades instead of going blank.
    [string] $ActivityOutFile      = '',
    [int]    $ActivityDays         = 7,
    [int]    $ActivityMax          = 500,
    # Ops/detailed health snapshot for the admin page + the box watchdog. Written beside
    # $AdminOutFile as health.json (same .secured gate). Carries no PII (round/map/counts/
    # stuck-state), so it's safe there. $RoundStuckSecs = how long the round number may sit
    # unchanged (while humans are on and it's NOT a pregame lobby hold) before roundStuck
    # trips. The in-GSC watchdog self-heals a stuck round in ~65s, so keep this well above
    # that so the box signal only fires if the in-game net also failed.
    [string] $HealthOutFile        = '',
    [int]    $RoundStuckSecs       = 300,
    # Box-local list of players muted from the ACTIVITY surfaces (the recent ring + the public
    # activity feed). They stay in the live player list and in the admin snapshot/history - see
    # tools\ignore_list.ps1. Defaults to tools\ignore.local.json; absent = ignore nobody.
    [string] $IgnoreFile    = '',
    [int]    $RecvTimeoutMs = 1200,
    [int]    $RecentMax     = 15,
    # Loopback port of the RCON panel (tools\rcon\server.js). When the panel is running,
    # this service reads through its /api/tick instead of sending raw rcon — the panel's
    # queue paces + coalesces ALL box-side rcon, so independent pollers stop tripping the
    # server's ~1-reply-per-0.7s rcon limit and eating each other's replies.
    [int]    $PanelPort     = 3000
)

$ErrorActionPreference = 'Stop'

# Shared with GF-JoinNotify: Get-GfIgnoreList (mtime-cached) + Test-GfIgnored.
. (Join-Path $PSScriptRoot '..\ignore_list.ps1')
if ([string]::IsNullOrEmpty($IgnoreFile)) { $IgnoreFile = Join-Path $PSScriptRoot '..\ignore.local.json' }

# storage\t5\mods\mp_gunfight\tools\status_service\ -> four parents = storage\t5\
$storageT5 = $PSScriptRoot
for ($i = 0; $i -lt 4; $i++) { $storageT5 = Split-Path -Parent $storageT5 }
if ([string]::IsNullOrEmpty($CfgPath)) { $CfgPath = Join-Path $storageT5 'dedicated.cfg' }
if ([string]::IsNullOrEmpty($LogDir))  { $LogDir  = Join-Path $storageT5 'logs' }
# admin_history.json lives beside the admin snapshot (same .secured-gated folder), so
# it inherits the exact same IIS Basic-auth protection and never leaks IPs unprotected.
if ([string]::IsNullOrEmpty($AdminHistoryFile) -and -not [string]::IsNullOrEmpty($AdminOutFile)) {
    $AdminHistoryFile = Join-Path (Split-Path -Parent $AdminOutFile) 'admin_history.json'
}
# health.json lives beside the admin snapshot too (same .secured-gated folder).
if ([string]::IsNullOrEmpty($HealthOutFile) -and -not [string]::IsNullOrEmpty($AdminOutFile)) {
    $HealthOutFile = Join-Path (Split-Path -Parent $AdminOutFile) 'health.json'
}
# activity.json is PUBLIC (no IP/GUID), so it lives beside status.json in the open web root -
# deliberately NOT in the .secured admin folder.
if ([string]::IsNullOrEmpty($ActivityOutFile)) {
    $ActivityOutFile = Join-Path (Split-Path -Parent $OutFile) 'activity.json'
}
# The engine's games_mp.log (advances on game events = a liveness proxy) lives in the MOD
# folder's own logs\ dir, distinct from $LogDir (players_*.log). $PSScriptRoot =
# ...\mods\mp_gunfight\tools\status_service -> two parents up = the mod folder.
$modFolder    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gamesLogPath = Join-Path $modFolder 'logs\games_mp.log'

# --- RCON password ------------------------------------------------------------
function Get-RconPassword {
    param([string]$explicit, [string]$cfg)
    if (-not [string]::IsNullOrEmpty($explicit)) { return $explicit }
    if (-not [string]::IsNullOrEmpty($env:GF_RCON_PW)) { return $env:GF_RCON_PW }
    if (Test-Path $cfg) {
        $m = Select-String -Path $cfg -Pattern 'set\s+rcon_password\s+"([^"]*)"' -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return ''
}
$rconPw = Get-RconPassword -explicit $RconPassword -cfg $CfgPath
if ([string]::IsNullOrEmpty($rconPw)) {
    Write-Error "No rcon_password found. Set it in $CfgPath, pass -RconPassword, or set env GF_RCON_PW."
    exit 1
}

# --- RCON send/receive (mirrors tools\rcon\server.js) -------------------------
function Send-Rcon {
    param([string]$ipHost, [int]$port, [string]$password, [string]$command, [int]$timeoutMs)
    $udp = New-Object System.Net.Sockets.UdpClient
    $sb  = New-Object System.Text.StringBuilder
    try {
        $udp.Client.ReceiveTimeout = $timeoutMs
        $udp.Connect($ipHost, $port)
        $oob     = [byte[]](0xff, 0xff, 0xff, 0xff)
        $payload = [System.Text.Encoding]::UTF8.GetBytes("rcon $password $command")
        $packet  = New-Object 'byte[]' ($oob.Length + $payload.Length)
        [Array]::Copy($oob, 0, $packet, 0, $oob.Length)
        [Array]::Copy($payload, 0, $packet, $oob.Length, $payload.Length)
        [void]$udp.Send($packet, $packet.Length)
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        while ($true) {
            try { $data = $udp.Receive([ref]$remote) } catch { break }
            if ($data.Length -gt 4) {
                $text = [System.Text.Encoding]::UTF8.GetString($data, 4, $data.Length - 4)
                if ($text.StartsWith('print')) { $text = $text.Substring(5) }
                [void]$sb.Append($text)
            }
        }
    } finally { $udp.Close() }
    return $sb.ToString()
}

function Strip-Color { param([string]$s) return ($s -replace '\^[0-9]', '') }

# --- Parsers ------------------------------------------------------------------
# Read one dvar's value out of a chained "name" is:"value" reply.
function Get-DvarValue {
    param([string]$reply, [string]$name)
    $m = [regex]::Match($reply, ('"{0}"\s+is:\s*"([^"]*)"' -f [regex]::Escape($name)))
    if ($m.Success) { return (Strip-Color $m.Groups[1].Value) }
    return ''
}

# status -> hashtable num -> @{ name; ping }  (IP intentionally dropped)
function Parse-StatusPlayers {
    param([string]$text)
    $byNum = @{}
    foreach ($line in ($text -split "`n")) {
        $t = $line.Trim()
        if ($t -eq '' -or $t -notmatch '^\d+\s') { continue }
        $tok = $t -split '\s+'
        if ($tok.Count -lt 8) { continue }
        $num  = $tok[0]
        $guid = $tok[3]
        $ping = $tok[2]
        $address = $tok[$tok.Count - 3]
        $nameEnd = $tok.Count - 5
        $name = ''
        if ($nameEnd -ge 4) { $name = ($tok[4..$nameEnd] -join ' ') }
        $name = (Strip-Color $name).Trim()
        if ($name -eq '') { continue }
        $isHuman = ($address -match '^\d{1,3}(\.\d{1,3}){3}:\d+$')
        $ip = if ($isHuman) { $address } else { '' }
        $byNum[$num] = @{ name = $name; ping = [int]$ping; bot = (-not $isHuman); ip = $ip; guid = $guid }
    }
    return $byNum
}

# gf_roster -> hashtable num -> @{ team; alive }
function Parse-Roster {
    param([string]$val)
    $byNum = @{}
    if ([string]::IsNullOrEmpty($val)) { return $byNum }
    foreach ($rec in ($val -split ';')) {
        if ($rec -eq '') { continue }
        $f = $rec -split ','
        if ($f.Count -lt 3) { continue }
        $team = switch ($f[1]) { 'a' { 'allies' } 'x' { 'axis' } 's' { 'spectator' } default { 'unknown' } }
        $byNum[$f[0]] = @{ team = $team; alive = ($f[2] -eq '1') }
    }
    return $byNum
}

# --- Atomic JSON write --------------------------------------------------------
function Write-Snapshot {
    param([string]$path, $obj)
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $json = $obj | ConvertTo-Json -Depth 6
    $tmp  = "$path.tmp"
    # No-BOM UTF-8: a leading BOM is legal but trips strict JSON consumers (jq, some
    # parsers). Browsers strip it, but keep the served file clean.
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tmp -Destination $path -Force
}

# Admin snapshot: written ONLY when -AdminOutFile is set AND a ".secured" marker
# exists in its parent folder. The marker is created by setup_admin_auth.ps1 after
# it confirms IIS Basic auth on that folder, so IP data can never land in an
# unprotected web path.
function Test-AdminEnabled {
    param([string]$adminOut)
    if ([string]::IsNullOrEmpty($adminOut)) { return $false }
    $marker = Join-Path (Split-Path -Parent $adminOut) '.secured'
    return (Test-Path $marker)
}
function Get-LogTail {
    param([string]$dir, [int]$n)
    $lines = @()
    $todays = Join-Path $dir ('players_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
    if (Test-Path $todays) {
        # "$_" forces a NEW plain string - Get-Content tags each line with ETS
        # note-properties (PSPath/PSDrive/...) that ConvertTo-Json would otherwise
        # emit as bloated objects instead of bare log strings.
        try { $lines = @(Get-Content -Path $todays -Tail $n -ErrorAction SilentlyContinue | ForEach-Object { "$_" }) } catch { }
    }
    return $lines
}

# Parse the last $days players_*.log day-files into a flat, NEWEST-FIRST event list
# (each line: "<date> <time>  <VERB> ip=... name="..." guid=... ping=... [session=...]").
# Banner "----- conn_logger started -----" lines never match the verb group -> skipped.
# Capped at $maxEvents so the JSON stays small (events are ~120 bytes each).
$script:ConnLineRx = [regex]'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\s+(ONLINE|CONNECT|LEFT)\s+ip=(\S+)\s+name="(.*?)"\s+guid=(\S+)\s+ping=(\S+)(?:\s+session=(\S+))?\s*$'
function Build-ConnHistory {
    param([string]$dir, [int]$days, [int]$maxEvents)
    $events = New-Object System.Collections.ArrayList
    $files = @(Get-ChildItem (Join-Path $dir 'players_*.log') -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | Select-Object -First $days)   # newest day first
    foreach ($f in $files) {
        $lines = @(Get-Content -Path $f.FullName -ErrorAction SilentlyContinue)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {   # bottom-up = newest line first
            $m = $script:ConnLineRx.Match($lines[$i])
            if (-not $m.Success) { continue }
            [void]$events.Add([ordered]@{
                date    = $m.Groups[1].Value
                time    = $m.Groups[2].Value
                event   = $m.Groups[3].Value
                ip      = $m.Groups[4].Value
                name    = $m.Groups[5].Value
                guid    = $m.Groups[6].Value
                ping    = $m.Groups[7].Value
                session = $m.Groups[8].Value
            })
            if ($events.Count -ge $maxEvents) { break }
        }
        if ($events.Count -ge $maxEvents) { break }
    }
    return @($events.ToArray())
}

# --- Country codes via the RCON panel's shared geo resolver -------------------
# We ask the PANEL for country codes rather than calling ip-api.com ourselves. The panel is the
# box's single ip-api client: it caches IP -> location on disk and paces outbound lookups under
# the free tier's 45 req/min cap. A second client here would burn that shared budget re-resolving
# IPs the panel already knows - the same "one queue on the box" rule the rcon lane follows.
#
# The batch endpoint is CACHE-FIRST and NON-BLOCKING: unknown IPs come back absent and are
# resolved in the background, so a cold IP simply has no flag for a poll or two. Geo can never
# delay the status snapshot, and a dead panel just means no flags (cosmetic, never fatal).
#
# PRIVACY: only the 2-letter country CODE crosses back into this process. The IP is never
# published - it stays in the box-local cache and the .secured admin files.
function Get-GeoBatch {
    param([string[]]$ips, [int]$panelPort)
    $out = @{}
    # Log/status IPs carry a :port - strip it, the resolver keys on the bare address.
    $uniq = @($ips | Where-Object { $_ } | ForEach-Object { ($_ -split ':')[0] } |
              Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Sort-Object -Unique)
    if ($uniq.Count -eq 0) { return $out }
    # The endpoint caps one batch at 64 IPs; chunk so a multi-day history rebuild still resolves.
    for ($i = 0; $i -lt $uniq.Count; $i += 64) {
        $chunk = $uniq[$i..([Math]::Min($i + 63, $uniq.Count - 1))]
        try {
            $u = 'http://127.0.0.1:{0}/api/geoip?ips={1}' -f $panelPort, ($chunk -join ',')
            $r = Invoke-RestMethod -UseBasicParsing -TimeoutSec 5 -Uri $u
            if ($r.ok -and $r.geo) {
                foreach ($prop in $r.geo.PSObject.Properties) {
                    if ($prop.Value.cc) { $out[$prop.Name] = [string]$prop.Value.cc }
                }
            }
        } catch { }   # panel down / slow: no flags this pass, snapshot still ships
    }
    return $out
}

# Project the shared day-file event list into the PUBLIC activity feed: drop ip/guid/ping,
# keep time/name/event/session, and stamp the country code resolved from the (dropped) IP.
# This is the ONLY place a log IP is turned into something publishable.
#
# Ignored players (tools\ignore.local.json) are dropped HERE, at the projection - never at the
# source. conn_logger still writes every connect to the day-files, so the private admin history
# stays complete and un-muting someone retroactively restores their whole 7 days.
function Build-PublicActivity {
    param($events, [hashtable]$geo, $ignore)
    $out = New-Object System.Collections.ArrayList
    foreach ($e in $events) {
        if (Test-GfIgnored $ignore $e.guid $e.name) { continue }
        $bare = ([string]$e.ip -split ':')[0]
        $cc   = if ($geo.ContainsKey($bare)) { $geo[$bare] } else { '' }
        [void]$out.Add([ordered]@{
            date    = $e.date
            time    = $e.time
            event   = $e.event
            name    = $e.name
            session = $e.session
            cc      = $cc
        })
    }
    return @($out.ToArray())
}

function Map-Name {
    param([string]$raw)
    switch ($raw) {
        'mp_nuked'       { 'Nuketown' } 'mp_havoc' { 'Hazard' } 'mp_cairo' { 'Havana' }
        'mp_cosmodrome'  { 'Launch' }   'mp_firingrange' { 'Firing Range' }
        'mp_duga'        { 'Grid' }      'mp_hanoi' { 'Hanoi' }  'mp_array' { 'Array' }
        'mp_cracked'     { 'Cracked' }   'mp_crisis' { 'Crisis' } 'mp_radiation' { 'Radiation' }
        'mp_mountain'    { 'Summit' }    'mp_villa' { 'Villa' }  'mp_russianbase' { 'WMD' }
        default { $raw }
    }
}

# --- Recent-activity feed (name-only, in-memory ring, no IP) -------------------
# Kept as the LIVE fallback for the status page: it needs no day-files, so it still works when
# conn_logger isn't running (no .secured marker). The durable multi-day feed is activity.json.
$recent   = New-Object System.Collections.ArrayList
$prevSet  = @{}     # name -> country code ('' if unresolved) for humans currently online
$firstRun = $true

function Push-Recent {
    param([string]$name, [string]$event, [string]$cc = '')
    $stamp = (Get-Date).ToString('o')
    [void]$recent.Insert(0, @{ t = $stamp; name = $name; event = $event; cc = $cc })
    while ($recent.Count -gt $RecentMax) { $recent.RemoveAt($recent.Count - 1) }
}

# --- Main loop ----------------------------------------------------------------
if (-not (Test-Path (Split-Path -Parent $OutFile))) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
}
Write-Host ("status_service -> $OutFile (host $RconHost`:$RconPort, every ${IntervalSeconds}s)")

$lastHistoryBuild = $null   # rebuild the multi-day admin history at most every $AdminHistoryEverySec

# Round-advancement tracking for the stuck detector (persist across iterations).
$lastRound         = -1
$lastRoundChangeAt = Get-Date

while ($true) {
    $online = $false
    $snapshot = $null
    $adminSnapshot = $null
    $lobbyHold    = $false   # from gf_state field 7 (pregame lobby hold) — suppresses roundStuck
    $humansOnline = 0
    $botCount     = 0
    $round        = 0
    try {
        # PREFERRED SOURCE: the RCON panel's /api/tick on this box — status+gf_state+gf_roster
        # in ONE rcon send through the panel's paced, coalescing queue (if the admin panel has
        # the same read queued, they merge into a single send). Direct rcon only as fallback:
        # a second unpaced sender races the panel for the server's ~1-reply-per-0.7s rcon
        # limit and both randomly lose replies.
        $tick = $null; $panelSaysDown = $false
        try {
            $u  = 'http://127.0.0.1:{0}/api/tick?host={1}&port={2}&password={3}' -f $PanelPort, $RconHost, $RconPort, [uri]::EscapeDataString($rconPw)
            $pj = Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 -Uri $u
            if ($pj.ok) { $tick = $pj } else { $panelSaysDown = $true }   # panel reached rcon, server gave nothing -> down; don't double-poll
        } catch { $tick = $null }

        $mapRaw = ''; $players = @{}; $roster = @{}
        $alliesWins = 0; $axisWins = 0; $round = 0; $aliveA = 0; $aliveX = 0; $gametype = ''

        if ($tick) {
            $online = $true
            $mapRaw = [string]$tick.map
            # Same shapes the text parsers produce: STRING num keys; ip carries addr:port for
            # humans / '' for bots; missing roster num -> team 'unknown'.
            foreach ($p in @($tick.players)) {
                if ($null -eq $p) { continue }
                $players[[string]$p.num] = @{ name = [string]$p.name; ping = [int]$p.ping; bot = [bool]$p.bot;
                                              guid = [string]$p.guid;
                                              ip = $(if ($p.bot) { '' } else { [string]$p.addr }) }
            }
            foreach ($e in @($tick.roster)) {
                if ($null -eq $e) { continue }
                $tm = if ([string]$e.team -ne '') { [string]$e.team } else { 'unknown' }
                $roster[[string]$e.num] = @{ team = $tm; alive = [bool]$e.alive }
            }
            if ($tick.state) {
                $alliesWins = [int]$tick.state.winsAllies; $axisWins = [int]$tick.state.winsAxis
                $round      = [int]$tick.state.round
                $aliveA     = [int]$tick.state.aliveAllies; $aliveX = [int]$tick.state.aliveAxis
                $gametype   = [string]$tick.state.gametype
                if ($null -ne $tick.state.lobbyHold) { $lobbyHold = [bool]$tick.state.lobbyHold }
            }
        }
        elseif (-not $panelSaysDown) {
            # FALLBACK (panel not running): direct rcon — gf_state + gf_roster in one chained
            # read; status separately (paced for the server's ~0.7s rcon reply rate limit).
            $dvarReply = Send-Rcon -ipHost $RconHost -port $RconPort -password $rconPw -command 'gf_state;gf_roster' -timeoutMs $RecvTimeoutMs
            Start-Sleep -Milliseconds 800
            $statusReply = Send-Rcon -ipHost $RconHost -port $RconPort -password $rconPw -command 'status' -timeoutMs $RecvTimeoutMs
            if ($statusReply -match 'map:') {
                $online = $true
                $mm = [regex]::Match($statusReply, 'map:\s*(\S+)')
                if ($mm.Success) { $mapRaw = $mm.Groups[1].Value }
                $state   = Get-DvarValue $dvarReply 'gf_state'
                $rosterV = Get-DvarValue $dvarReply 'gf_roster'
                $roster  = Parse-Roster $rosterV
                $players = Parse-StatusPlayers $statusReply
                $sf = $state -split ':'
                $alliesWins = if ($sf.Count -ge 1 -and $sf[0] -ne '') { [int]$sf[0] } else { 0 }
                $axisWins   = if ($sf.Count -ge 2 -and $sf[1] -ne '') { [int]$sf[1] } else { 0 }
                $round      = if ($sf.Count -ge 3 -and $sf[2] -ne '') { [int]$sf[2] } else { 0 }
                $aliveA     = if ($sf.Count -ge 4 -and $sf[3] -ne '') { [int]$sf[3] } else { 0 }
                $aliveX     = if ($sf.Count -ge 5 -and $sf[4] -ne '') { [int]$sf[4] } else { 0 }
                $gametype   = if ($sf.Count -ge 6) { $sf[5] } else { '' }
                # gf_state field 7 (index 6) = pregame lobby hold flag (see gf_bridgeTelemetry).
                $lobbyHold  = if ($sf.Count -ge 7 -and $sf[6] -ne '') { $sf[6] -eq '1' } else { $false }
            }
        }

        if ($online) {
            # Collect the humans first (with their IPs), so the whole roster's country codes can
            # be resolved in ONE batch call below rather than one call per player per poll.
            $humansRaw = @()
            foreach ($num in $players.Keys) {
                $p = $players[$num]
                if ($p.bot) { continue }
                # A real human has an ip:port (or a listen-server host's local/loopback). Skip
                # bots the panel's guid/'unknown' check missed AND clients still connecting
                # (guid 0, the address column holding a lastmsg value) - otherwise they inflate
                # the human count and log spurious connects.
                if ([string]$p.ip -ne 'local' -and [string]$p.ip -ne 'loopback' -and [string]$p.ip -notmatch '^\d{1,3}(\.\d{1,3}){3}:\d+$') { continue }
                $r = $roster[$num]
                $humansRaw += ,@{
                    name  = $p.name
                    team  = if ($r) { $r.team } else { 'unknown' }
                    alive = if ($r) { $r.alive } else { $true }
                    ping  = $p.ping
                    ip    = $p.ip
                    guid  = $p.guid
                }
            }

            # One cache-first, non-blocking geo call for the whole roster.
            $geo = Get-GeoBatch -ips @($humansRaw | ForEach-Object { $_.ip }) -panelPort $PanelPort

            # Build the public player list (humans only). $adminList is the same PLUS ip/guid,
            # used only for the protected admin snapshot. NOTE the asymmetry: both carry the
            # country code, only the admin one carries the IP it was derived from.
            $list = @()
            $adminList = @()
            $humanNames = @{}
            $ignore = Get-GfIgnoreList $IgnoreFile
            foreach ($h in $humansRaw) {
                $bare = ([string]$h.ip -split ':')[0]
                $cc   = if ($geo.ContainsKey($bare)) { $geo[$bare] } else { '' }
                $list      += ,([ordered]@{ name = $h.name; team = $h.team; alive = $h.alive; ping = $h.ping; cc = $cc })
                $adminList += ,([ordered]@{ name = $h.name; team = $h.team; alive = $h.alive; ping = $h.ping; cc = $cc; ip = $h.ip; guid = $h.guid })
                # $humanNames feeds ONLY the recent-activity diff below, so an ignored player is
                # withheld here and nowhere else: they stay in $list (visible on the live player
                # list, counted in `humans`) but never produce a joined/left entry.
                if (Test-GfIgnored $ignore $h.guid $h.name) { continue }
                $humanNames[$h.name] = $cc
            }

            # Diff human names for the recent-activity feed (skip the very first poll
            # so a cold start doesn't spam "joined" for everyone already on).
            if (-not $firstRun) {
                foreach ($n in $humanNames.Keys) { if (-not $prevSet.ContainsKey($n)) { Push-Recent $n 'joined' $humanNames[$n] } }
                foreach ($n in $prevSet.Keys)    { if (-not $humanNames.ContainsKey($n)) { Push-Recent $n 'left' $prevSet[$n] } }
            }
            $prevSet = $humanNames
            $firstRun = $false

            $botCount = 0
            foreach ($num in $players.Keys) { if ($players[$num].bot) { $botCount++ } }
            $humansOnline = $list.Count

            $snapshot = [ordered]@{
                updated  = (Get-Date).ToString('o')
                online   = $true
                map      = $mapRaw
                mapName  = (Map-Name $mapRaw)
                gametype = $gametype
                round    = $round
                score    = [ordered]@{ allies = $alliesWins; axis = $axisWins }
                alive    = [ordered]@{ allies = $aliveA; axis = $aliveX }
                humans   = $list.Count
                bots     = $botCount
                players  = $list
                recent   = @($recent.ToArray())
            }

            $adminSnapshot = [ordered]@{
                updated  = (Get-Date).ToString('o')
                online   = $true
                map      = $mapRaw
                mapName  = (Map-Name $mapRaw)
                gametype = $gametype
                round    = $round
                score    = [ordered]@{ allies = $alliesWins; axis = $axisWins }
                alive    = [ordered]@{ allies = $aliveA; axis = $aliveX }
                humans   = $adminList.Count
                bots     = $botCount
                players  = $adminList
                logTail  = @(Get-LogTail $LogDir $AdminLogTail)
            }
        }
    } catch {
        Write-Warning ("poll failed: {0}" -f $_.Exception.Message)
    }

    if (-not $online) {
        $snapshot = [ordered]@{
            updated = (Get-Date).ToString('o')
            online  = $false
            players = @()
            recent  = @($recent.ToArray())
        }
        $adminSnapshot = [ordered]@{
            updated = (Get-Date).ToString('o')
            online  = $false
            players = @()
            logTail = @(Get-LogTail $LogDir $AdminLogTail)
        }
    }

    try { Write-Snapshot -path $OutFile -obj $snapshot } catch { Write-Warning ("write failed: {0}" -f $_.Exception.Message) }

    # Admin snapshot (with IPs) only when explicitly enabled AND the folder is
    # provably auth-protected (.secured marker). Otherwise it is never written.
    if (Test-AdminEnabled $AdminOutFile) {
        try { Write-Snapshot -path $AdminOutFile -obj $adminSnapshot } catch { Write-Warning ("admin write failed: {0}" -f $_.Exception.Message) }
    }

    # --- Day-file derived histories ----------------------------------------------
    # Both feeds are parsed from the SAME static players_*.log files, so they rebuild on a slow
    # cadence rather than every poll, and cost zero rcon. They differ only in reach and privacy:
    #   activity.json      PUBLIC  - 7 days, no IP/GUID, country code only -> NO .secured gate
    #   admin_history.json PRIVATE - 60 days, full IP + GUID               -> .secured gate
    $now = Get-Date
    if ($null -eq $lastHistoryBuild -or ($now - $lastHistoryBuild).TotalSeconds -ge $AdminHistoryEverySec) {
        # Stamp FIRST: a throwing build must not re-run flat out on every 5s poll.
        $lastHistoryBuild = $now

        if (-not [string]::IsNullOrEmpty($ActivityOutFile)) {
            try {
                $pev  = Build-ConnHistory -dir $LogDir -days $ActivityDays -maxEvents $ActivityMax
                $pgeo = Get-GeoBatch -ips @($pev | ForEach-Object { $_.ip }) -panelPort $PanelPort
                # count is the PUBLISHED count, so it can't advertise events the feed withholds.
                $pub  = @(Build-PublicActivity -events $pev -geo $pgeo -ignore (Get-GfIgnoreList $IgnoreFile))
                Write-Snapshot -path $ActivityOutFile -obj ([ordered]@{
                    updated = $now.ToString('o')
                    days    = $ActivityDays
                    count   = $pub.Count
                    events  = $pub
                })
            } catch { Write-Warning ("activity write failed: {0}" -f $_.Exception.Message) }
        }

        if ((Test-AdminEnabled $AdminOutFile) -and -not [string]::IsNullOrEmpty($AdminHistoryFile)) {
            try {
                $ev   = Build-ConnHistory -dir $LogDir -days $AdminHistoryDays -maxEvents $AdminHistoryMax
                $ageo = Get-GeoBatch -ips @($ev | ForEach-Object { $_.ip }) -panelPort $PanelPort
                foreach ($e in $ev) {
                    $bare = ([string]$e.ip -split ':')[0]
                    $e.cc = if ($ageo.ContainsKey($bare)) { $ageo[$bare] } else { '' }
                }
                Write-Snapshot -path $AdminHistoryFile -obj ([ordered]@{
                    updated = $now.ToString('o')
                    days    = $AdminHistoryDays
                    count   = $ev.Count
                    events  = $ev
                })
            } catch { Write-Warning ("history write failed: {0}" -f $_.Exception.Message) }
        }
    }

    # --- Health snapshot (ops/detailed status: admin page + box watchdog) --------
    # No PII (round/map/counts/stuck-state), but written to the same .secured-gated
    # admin folder so the whole ops surface stays behind Basic auth.
    if ((Test-AdminEnabled $AdminOutFile) -and -not [string]::IsNullOrEmpty($HealthOutFile)) {
        # Track round advancement. The stuck detector trips only while the server is up,
        # humans are on, it is NOT a legitimate pregame lobby hold, and the round number
        # has not moved for $RoundStuckSecs. Down/lobby resets the clock so a fresh start
        # or an intentional hold never reads as stuck.
        if ($online -and -not $lobbyHold) {
            if ($round -ne $lastRound) { $lastRound = $round; $lastRoundChangeAt = Get-Date }
        } else {
            $lastRound = $round
            $lastRoundChangeAt = Get-Date
        }
        $secsSinceRoundChange = [int]((Get-Date) - $lastRoundChangeAt).TotalSeconds
        $roundStuck = ($online -and $humansOnline -gt 0 -and -not $lobbyHold -and $secsSinceRoundChange -ge $RoundStuckSecs)

        # games_mp.log mtime = engine-liveness proxy (advances on game events).
        $gamesLogAge = -1
        if (Test-Path $gamesLogPath) {
            try { $gamesLogAge = [int]((Get-Date) - (Get-Item $gamesLogPath).LastWriteTime).TotalSeconds } catch { }
        }
        # Dedicated-server uptime (from the bootstrapper process).
        $uptimeMins = $null
        try {
            $bp = Get-Process -Name 'plutonium-bootstrapper-win32' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($bp) { $uptimeMins = [int]((Get-Date) - $bp.StartTime).TotalMinutes }
        } catch { }

        $health = [ordered]@{
            updated              = (Get-Date).ToString('o')
            online               = $online
            map                  = $mapRaw
            mapName              = (Map-Name $mapRaw)
            gametype             = $gametype
            round                = $round
            humans               = $humansOnline
            bots                 = $botCount
            lobbyHold            = $lobbyHold
            roundStuck           = $roundStuck
            secsSinceRoundChange = $secsSinceRoundChange
            roundStuckSecs       = $RoundStuckSecs
            score                = [ordered]@{ allies = $alliesWins; axis = $axisWins }
            alive                = [ordered]@{ allies = $aliveA; axis = $aliveX }
            gamesLogAgeSecs      = $gamesLogAge
            serverUptimeMins     = $uptimeMins
        }
        try { Write-Snapshot -path $HealthOutFile -obj $health } catch { Write-Warning ("health write failed: {0}" -f $_.Exception.Message) }
    }

    Start-Sleep -Seconds $IntervalSeconds
}
