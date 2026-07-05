# status_service.ps1 - public server-status snapshot for the website (run ON the VPS)
# ------------------------------------------------------------------------------
# Polls the dedicated server over loopback RCON and writes a small, PUBLIC-SAFE
# JSON snapshot that the static status page (site\wwwroot\status.html) fetches and
# renders as a read-only scoreboard: map, gametype, match score, per-team roster
# (alive/ping), and a short recent-activity feed.
#
# PRIVACY: this snapshot is world-readable (served by IIS). It carries player
# NAMES only - the same info anyone sees in the in-game server browser. It does
# NOT include IP addresses or GUIDs. The IP connect log (conn_logger) stays
# private on the box and is never written to the web root.
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
    [int]    $RecvTimeoutMs = 1200,
    [int]    $RecentMax     = 15,
    # Loopback port of the RCON panel (tools\rcon\server.js). When the panel is running,
    # this service reads through its /api/tick instead of sending raw rcon — the panel's
    # queue paces + coalesces ALL box-side rcon, so independent pollers stop tripping the
    # server's ~1-reply-per-0.7s rcon limit and eating each other's replies.
    [int]    $PanelPort     = 3000
)

$ErrorActionPreference = 'Stop'

# storage\t5\mods\mp_gunfight\tools\status_service\ -> four parents = storage\t5\
$storageT5 = $PSScriptRoot
for ($i = 0; $i -lt 4; $i++) { $storageT5 = Split-Path -Parent $storageT5 }
if ([string]::IsNullOrEmpty($CfgPath)) { $CfgPath = Join-Path $storageT5 'dedicated.cfg' }
if ([string]::IsNullOrEmpty($LogDir))  { $LogDir  = Join-Path $storageT5 'logs' }

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
        $ping = $tok[2]
        $address = $tok[$tok.Count - 3]
        $nameEnd = $tok.Count - 5
        $name = ''
        if ($nameEnd -ge 4) { $name = ($tok[4..$nameEnd] -join ' ') }
        $name = (Strip-Color $name).Trim()
        if ($name -eq '') { continue }
        $isHuman = ($address -match '^\d{1,3}(\.\d{1,3}){3}:\d+$')
        $ip = if ($isHuman) { $address } else { '' }
        $byNum[$num] = @{ name = $name; ping = [int]$ping; bot = (-not $isHuman); ip = $ip }
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
$recent   = New-Object System.Collections.ArrayList
$prevSet  = @{}     # name -> $true for humans currently online
$firstRun = $true

function Push-Recent {
    param([string]$name, [string]$event)
    $stamp = (Get-Date).ToString('o')
    [void]$recent.Insert(0, @{ t = $stamp; name = $name; event = $event })
    while ($recent.Count -gt $RecentMax) { $recent.RemoveAt($recent.Count - 1) }
}

# --- Main loop ----------------------------------------------------------------
if (-not (Test-Path (Split-Path -Parent $OutFile))) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
}
Write-Host ("status_service -> $OutFile (host $RconHost`:$RconPort, every ${IntervalSeconds}s)")

while ($true) {
    $online = $false
    $snapshot = $null
    $adminSnapshot = $null
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
            }
        }

        if ($online) {
            # Build the public player list (humans only), merging team/alive from roster.
            # $adminList is the same list PLUS ip, used only for the protected admin snapshot.
            $list = @()
            $adminList = @()
            $humanNames = @{}
            foreach ($num in $players.Keys) {
                $p = $players[$num]
                if ($p.bot) { continue }
                $r = $roster[$num]
                $team = if ($r) { $r.team } else { 'unknown' }
                $alive = if ($r) { $r.alive } else { $true }
                $list      += ,([ordered]@{ name = $p.name; team = $team; alive = $alive; ping = $p.ping })
                $adminList += ,([ordered]@{ name = $p.name; team = $team; alive = $alive; ping = $p.ping; ip = $p.ip })
                $humanNames[$p.name] = $true
            }

            # Diff human names for the recent-activity feed (skip the very first poll
            # so a cold start doesn't spam "joined" for everyone already on).
            if (-not $firstRun) {
                foreach ($n in $humanNames.Keys) { if (-not $prevSet.ContainsKey($n)) { Push-Recent $n 'joined' } }
                foreach ($n in $prevSet.Keys)    { if (-not $humanNames.ContainsKey($n)) { Push-Recent $n 'left' } }
            }
            $prevSet = $humanNames
            $firstRun = $false

            $botCount = 0
            foreach ($num in $players.Keys) { if ($players[$num].bot) { $botCount++ } }

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

    Start-Sleep -Seconds $IntervalSeconds
}
