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
    # Gameplay stats (kills/deaths/assists/damage/round wins) aggregated from the GF_STAT /
    # GF_MATCH lines the mod logPrints into games_mp.log at round/match end. The accumulator
    # ($GameStatsState, box-local beside the day-files, NEVER deployed or served) sums every
    # delta line ever ingested into per-day per-GUID buckets; the projection ($GameStatsFile)
    # is written beside the admin snapshot behind the same .secured gate - it carries GUIDs,
    # so it must never land in the open web root. Ingest runs on the history cadence
    # (static file tail, zero rcon); '' derives both paths below.
    [string] $GameStatsFile  = '',
    [string] $GameStatsState = '',
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
# Shared with GF-JoinNotify: Get-GfMapName (map id -> display name).
. (Join-Path $PSScriptRoot '..\map_names.ps1')
# Shared path helpers + Get-RconPassword.
. (Join-Path $PSScriptRoot '..\common.ps1')
# ConvertFrom-GfStatus + Remove-GfColors: the shared `status` parser (PS twin of the panel's
# status_parse.js). Only the panel-down FALLBACK below parses status text at all - the happy
# path consumes the panel's already-parsed /api/tick JSON, which carries the same player shape.
. (Join-Path $PSScriptRoot '..\status_parse.ps1')
if ([string]::IsNullOrEmpty($IgnoreFile)) { $IgnoreFile = Join-Path $PSScriptRoot '..\ignore.local.json' }

# storage\t5 (…\mods\mp_gunfight\tools\common.ps1 resolves it, independent of this subdir).
$storageT5 = Resolve-T5Root
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
# folder's own logs\ dir, distinct from $LogDir (players_*.log).
$modFolder    = Resolve-ModRoot
$gamesLogPath = Join-Path $modFolder 'logs\games_mp.log'

# Gameplay-stat paths: the accumulator sits beside the players_*.log day-files (box-local,
# outside the deploy mirror and the web root); the projection sits beside the admin snapshot
# (GUID-keyed, so it needs the .secured gate exactly like admin_history.json).
if ([string]::IsNullOrEmpty($GameStatsState)) { $GameStatsState = Join-Path $LogDir 'gamestats.local.json' }
if ([string]::IsNullOrEmpty($GameStatsFile) -and -not [string]::IsNullOrEmpty($AdminOutFile)) {
    $GameStatsFile = Join-Path (Split-Path -Parent $AdminOutFile) 'gamestats.json'
}

# --- RCON password (explicit -> $env:GF_RCON_PW -> cfg; Get-RconPassword in common.ps1) -------
$rconPw = Get-RconPassword -Explicit $RconPassword -CfgPath $CfgPath
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

# --- Parsers ------------------------------------------------------------------
# (Status-text parsing lives in the shared ..\status_parse.ps1 dot-sourced above.)
# Read one dvar's value out of a chained "name" is:"value" reply.
function Get-DvarValue {
    param([string]$reply, [string]$name)
    $m = [regex]::Match($reply, ('"{0}"\s+is:\s*"([^"]*)"' -f [regex]::Escape($name)))
    if ($m.Success) { return (Remove-GfColors $m.Groups[1].Value) }
    return ''
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
    # ⚠ Move-Item -Force is NOT an atomic replace on Windows: it fails outright with "Cannot
    # create a file when that file already exists" whenever ANOTHER process holds the destination
    # open without FILE_SHARE_DELETE - which is exactly what conn_logger's Get-Content does, on
    # its own 5s cycle against this file's 5s cycle. Structural collision, ~1-2 lost writes/day
    # observed 08-03..08-06, and each loss ages admin.json toward conn_logger's 30s staleness
    # cutoff, where it stops diffing and silently misses whole sessions.
    # Retry briefly rather than dropping the write; the reader's handle is open for milliseconds.
    $moved = $false
    foreach ($attempt in 1, 2, 3) {
        try { Move-Item -Path $tmp -Destination $path -Force -ErrorAction Stop; $moved = $true; break }
        catch { if ($attempt -lt 3) { Start-Sleep -Milliseconds 120 } }
    }
    if (-not $moved) {
        # Last resort: copy over the destination in place (works against an open reader because
        # it never needs to DELETE the destination), then clean up the temp file.
        try {
            [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Write-Warning "snapshot move contended on $(Split-Path -Leaf $path) - fell back to in-place write"
        } catch {
            Write-Warning "snapshot write FAILED for $(Split-Path -Leaf $path): $($_.Exception.Message)"
        }
    }
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
#
# $ignore (the PUBLIC feed passes it; the admin history does NOT) drops muted players HERE,
# during the read, so $maxEvents caps the events that will actually be PUBLISHED - filtering
# after the cap would let a muted player's events eat cap slots and silently shorten the feed's
# reach. It filters the projection, never the source: conn_logger still writes every connect to
# the day-files, so the admin history stays complete and un-muting is retroactive.
function Build-ConnHistory {
    param([string]$dir, [int]$days, [int]$maxEvents, $ignore = $null)
    $events = New-Object System.Collections.ArrayList
    $files = @(Get-ChildItem (Join-Path $dir 'players_*.log') -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | Select-Object -First $days)   # newest day first
    foreach ($f in $files) {
        $lines = @(Get-Content -Path $f.FullName -ErrorAction SilentlyContinue)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {   # bottom-up = newest line first
            $m = $script:ConnLineRx.Match($lines[$i])
            if (-not $m.Success) { continue }
            if ($null -ne $ignore -and (Test-GfIgnored $ignore $m.Groups[6].Value $m.Groups[5].Value)) { continue }
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
# PRIVACY: only the 2-letter country CODE and the region (state / province) name cross back into
# this process. The IP is never published - it stays in the box-local cache and the .secured admin
# files. The region is finer-grained than the code, so it is stamped ONLY on the .secured admin
# history; Build-PublicActivity below deliberately takes the country code and nothing else.
#
# Returns ip -> @{ cc; region }. Callers that only want the code read .cc: a bare $geo[$ip] is a
# hashtable now, not a string, so every consumer must pick a field.
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
                    if ($prop.Value.cc) {
                        $out[$prop.Name] = @{
                            cc     = [string]$prop.Value.cc
                            region = [string]$prop.Value.region   # '' on a pre-region cache entry
                        }
                    }
                }
            }
        } catch { }   # panel down / slow: no flags this pass, snapshot still ships
    }
    return $out
}

# Project the shared day-file event list into the PUBLIC activity feed: drop ip/guid/ping,
# keep time/name/event/session, and stamp the country code resolved from the (dropped) IP.
# This is the ONLY place a log IP is turned into something publishable.
# Muted players are already gone by here - Build-ConnHistory dropped them during the read.
function Build-PublicActivity {
    param($events, [hashtable]$geo)
    $out = New-Object System.Collections.ArrayList
    foreach ($e in $events) {
        $bare = ([string]$e.ip -split ':')[0]
        $cc   = if ($geo.ContainsKey($bare)) { $geo[$bare].cc } else { '' }
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

# --- Gameplay stats (GF_STAT / GF_MATCH lines out of games_mp.log) ------------
# The mod logPrints one DELTA line per human per round (kills/deaths/assists/headshots/
# damage/captures/roundwin) and one W|L|T line per human at match end - same transport as
# stock's own J;/Q; connect lines, name LAST so it parses end-anchored whatever it contains.
# Because the lines are deltas, aggregation is a plain sum of every line ever ingested:
# no dedup, no per-match reconciliation. This service tails the file incrementally (byte
# offset persisted in the accumulator), so each pass reads only what is new.
#
# Load the accumulator. ConvertFrom-Json gives PSCustomObjects; walk them back into nested
# hashtables (5.1 has no -AsHashtable) so the merge below can index and add freely.
function Read-GfStatState {
    param([string]$path)
    $state = @{ offset = [long]0; ctime = [long]0; days = @{} }
    if (-not (Test-Path -LiteralPath $path)) { return $state }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -ne $raw.offset) { $state.offset = [long]$raw.offset }
        if ($null -ne $raw.ctime)  { $state.ctime  = [long]$raw.ctime }
        if ($null -ne $raw.days) {
            foreach ($dp in $raw.days.PSObject.Properties) {
                $g = @{}
                foreach ($gp in $dp.Value.PSObject.Properties) {
                    $e = $gp.Value
                    $g[$gp.Name] = @{
                        k = [int]$e.k; d = [int]$e.d; a = [int]$e.a; hs = [int]$e.hs
                        dmg = [int]$e.dmg; cap = [int]$e.cap; rw = [int]$e.rw
                        mw = [int]$e.mw; ml = [int]$e.ml; mt = [int]$e.mt
                        rounds = [int]$e.rounds; name = [string]$e.name
                    }
                }
                $state.days[$dp.Name] = $g
            }
        }
    } catch { Write-Warning ("gamestats state unreadable, starting fresh: {0}" -f $_.Exception.Message) }
    return $state
}

# Incremental tail: read from $offset through the last complete line (a partial line mid-write
# is left for the next pass - g_logSync flushes per line, but never bet on catching a boundary).
# Returns @{ lines; newOffset; newCtime }. ROTATION (the engine renames the live log to
# games_mp.log.NNN at restart and starts fresh) is detected by the file's CREATION time
# changing - size-shrunk alone is not enough, a fresh log can outgrow the old offset between
# two passes ($ctime 0 = unknown, e.g. a pre-upgrade state file: size is the only tell then).
# On rotation it first tries to recover the unread tail from the newest archive big enough to
# hold it, then restarts at 0 on the fresh file.
# WARN An archive is ONLY "<leaf>.NNN" - match it with a regex and exclude the live path, never
# with -Filter alone. Win32's trailing ".*" also matches the EXTENSIONLESS live file, which is by
# definition the newest-written, so it won the newest-first sort and got read as its own archive:
# the real tail was silently lost on every rotation, and the bytes past $offset were read twice
# (once as the "archive", once from 0) - double-counted, since Merge-GfStatLines sums with no dedup.
function Read-GfStatChunk {
    param([string]$path, [long]$offset, [long]$ctime = 0)
    $out = @{ lines = @(); newOffset = $offset; newCtime = $ctime }
    if (-not (Test-Path -LiteralPath $path)) { return $out }

    $readTail = {
        param([string]$p, [long]$from)
        $fs = [System.IO.File]::Open($p, 'Open', 'Read', 'ReadWrite,Delete')
        try {
            if ($from -ge $fs.Length) { return @{ text = ''; consumed = [long]0 } }
            [void]$fs.Seek($from, 'Begin')
            $buf = New-Object byte[] ($fs.Length - $from)
            $got = $fs.Read($buf, 0, $buf.Length)
            # Only consume through the last newline; the remainder is a line still being written.
            $last = -1
            for ($i = $got - 1; $i -ge 0; $i--) { if ($buf[$i] -eq 10) { $last = $i; break } }
            if ($last -lt 0) { return @{ text = ''; consumed = [long]0 } }
            return @{
                text     = [System.Text.Encoding]::UTF8.GetString($buf, 0, $last + 1)
                consumed = [long]($last + 1)
            }
        } finally { $fs.Close() }
    }

    try {
        $fi = Get-Item -LiteralPath $path
        $curCtime = $fi.CreationTimeUtc.Ticks
        if (($ctime -ne 0 -and $curCtime -ne $ctime) -or ($fi.Length -lt $offset)) {
            # Rotated. Best-effort tail recovery from the newest archive that could hold the
            # unread bytes; a miss just loses the lines between the last pass and the restart.
            try {
                # -Filter stays as the cheap FS-level prefilter; the regex is what actually
                # defines an archive (see the WARN above), and the live file is excluded by
                # full path as well so neither guard is load-bearing on its own.
                $leaf   = Split-Path -Leaf $path
                $archRx = [regex]('^' + [regex]::Escape($leaf) + '\.\d+$')
                $arch = @(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -Filter ($leaf + '.*') -ErrorAction SilentlyContinue |
                          Where-Object { $archRx.IsMatch($_.Name) -and $_.FullName -ne $fi.FullName -and $_.Length -ge $offset } |
                          Sort-Object LastWriteTime -Descending | Select-Object -First 1)
                if ($arch.Count -gt 0) {
                    $rec = & $readTail $arch[0].FullName $offset
                    if ($rec.text.Length -gt 0) { $out.lines += ($rec.text -split "`r?`n") }
                }
            } catch {}
            $offset = 0
        }
        $r = & $readTail $path $offset
        if ($r.text.Length -gt 0) { $out.lines += ($r.text -split "`r?`n") }
        $out.newOffset = $offset + $r.consumed
        $out.newCtime  = $curCtime
    } catch { Write-Warning ("gamestats tail read failed: {0}" -f $_.Exception.Message) }
    return $out
}

# Sum parsed lines into the day->guid accumulator. Day = INGEST day (box local): the engine
# prefix is game-relative minutes, not wall clock, so ingest time is the only calendar there
# is - at most one cadence interval late, which day-granular windows cannot feel.
function Merge-GfStatLines {
    param($state, [string[]]$lines, [string]$day)
    # The regexes are ANCHORED behind the engine's "min:sec " logPrint prefix on purpose: a
    # player NAME in some other line (a stock J; line, say) could contain the literal text
    # "GF_STAT;..." - anchoring to line start means only lines the GSC actually emitted
    # parse, and the name field itself is the trailing (.*) so nothing in it can add
    # fields. Locals (not script scope) so the Pester net can lift this function whole.
    # Team is [^;]* (not an allies|axis enum): a human who played the round and then went to
    # spectator still owns their deltas, and the line-start anchor is the forgery defence here.
    $statRx  = [regex]'^\s*\d+:\d{2}\s+GF_STAT;([^;]*);(\d+);([^;]+);([^;]*);(\d+);(\d+);(\d+);(\d+);(\d+);(\d+);([01]);(.*)$'
    $matchRx = [regex]'^\s*\d+:\d{2}\s+GF_MATCH;([^;]*);([^;]*);([^;]+);(W|L|T);(.*)$'
    $n = 0
    foreach ($line in $lines) {
        $m = $statRx.Match($line)
        if ($m.Success) {
            $guid = $m.Groups[3].Value
            if (-not $state.days.ContainsKey($day)) { $state.days[$day] = @{} }
            $bucket = $state.days[$day]
            if (-not $bucket.ContainsKey($guid)) {
                $bucket[$guid] = @{ k=0; d=0; a=0; hs=0; dmg=0; cap=0; rw=0; mw=0; ml=0; mt=0; rounds=0; name='' }
            }
            $e = $bucket[$guid]
            $e.k   += [int]$m.Groups[5].Value
            $e.d   += [int]$m.Groups[6].Value
            $e.a   += [int]$m.Groups[7].Value
            $e.hs  += [int]$m.Groups[8].Value
            $e.dmg += [int]$m.Groups[9].Value
            $e.cap += [int]$m.Groups[10].Value
            $e.rw  += [int]$m.Groups[11].Value
            $e.rounds += 1
            $nm = Remove-GfColors $m.Groups[12].Value
            if ($nm) { $e.name = $nm }
            $n++
            continue
        }
        $m = $matchRx.Match($line)
        if ($m.Success) {
            $guid = $m.Groups[3].Value
            if (-not $state.days.ContainsKey($day)) { $state.days[$day] = @{} }
            $bucket = $state.days[$day]
            if (-not $bucket.ContainsKey($guid)) {
                $bucket[$guid] = @{ k=0; d=0; a=0; hs=0; dmg=0; cap=0; rw=0; mw=0; ml=0; mt=0; rounds=0; name='' }
            }
            $e = $bucket[$guid]
            switch ($m.Groups[4].Value) {
                'W' { $e.mw += 1 }
                'L' { $e.ml += 1 }
                'T' { $e.mt += 1 }
            }
            $nm = Remove-GfColors $m.Groups[5].Value
            if ($nm) { $e.name = $nm }
            $n++
        }
    }
    return $n
}

# Map id -> display name now comes from the shared tools\map_names.ps1 (dot-sourced at the top),
# so the website, the phone alerts and the admin console cannot drift apart. The local table this
# replaced had two faults: it called mp_havoc "Hazard" (it is JUNGLE - Hazard is mp_golfcourse),
# and it knew none of the 12 DLC maps, which fell through to a raw "mp_*" on the site.
function Map-Name {
    param([string]$raw)
    return (Get-GfMapName $raw)
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
# Gameplay-stat accumulator, loaded once; the ingest pass below mutates it in place and
# persists it (atomically) every history cadence, so a service restart resumes at the
# stored byte offset instead of re-summing lines it already counted.
$gfStatState = Read-GfStatState $GameStatsState

# Round-advancement tracking for the stuck detector (persist across iterations).
$lastRound         = -1
$lastRoundChangeAt = Get-Date

while ($true) {
    # ── loop stall instrument ─────────────────────────────────────────────────
    # WHY: conn_logger needed its panel fallback 19-27x/DAY (measured 08-07..08-10) because
    # admin.json goes stale - i.e. THIS loop stalls past 30s - and nothing named the phase that
    # ate the time. Every consumer downstream inherits those stalls. One warning line per slow
    # iteration, with the per-phase split, turns the next stall from a theory into a filename.
    # Suspect on current evidence: the 60s history rebuild runs INLINE here, and its two geo
    # batches are ~9 chunks x 5s HTTP timeout at today's 564 unique IPs - up to ~90s worst case.
    $swLoop = [System.Diagnostics.Stopwatch]::StartNew()
    $msAcq = 0; $msSnap = 0; $msHist = 0; $msHealth = 0

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
            # Projection shared with the fallback branch below: STRING num keys; bot stays
            # THREE-STATE ($null = unclassifiable, falsy everywhere it is read); ip carries
            # addr:port only for a POSITIVE human claim (bot -eq $false, never a truthiness
            # test) / '' otherwise; missing roster num -> team 'unknown'.
            foreach ($p in @($tick.players)) {
                if ($null -eq $p) { continue }
                $players[[string]$p.num] = @{ name = [string]$p.name; ping = [int]$p.ping; bot = $p.bot;
                                              guid = [string]$p.guid;
                                              ip = $(if ($p.bot -eq $false) { [string]$p.addr } else { '' }) }
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
                $st     = ConvertFrom-GfStatus $statusReply
                $mapRaw = [string]$st.map
                $state   = Get-DvarValue $dvarReply 'gf_state'
                $rosterV = Get-DvarValue $dvarReply 'gf_roster'
                $roster  = Parse-Roster $rosterV
                # Same projection as the /api/tick branch above (that branch consumes the
                # panel's parse of the SAME shared parser, so the two paths cannot drift).
                foreach ($p in @($st.players)) {
                    $players[[string]$p.num] = @{ name = $p.name; ping = [int]$p.ping; bot = $p.bot;
                                                  guid = [string]$p.guid;
                                                  ip = $(if ($p.bot -eq $false) { [string]$p.addr } else { '' }) }
                }
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
                if ([string]$p.ip -ne 'local' -and [string]$p.ip -ne 'loopback' -and [string]$p.ip -notmatch '^\d{1,3}(\.\d{1,3}){3}:-?\d+$') { continue }   # -? : port prints signed-16-bit, can be negative
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
                $cc   = if ($geo.ContainsKey($bare)) { $geo[$bare].cc } else { '' }
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

    $msAcq = $swLoop.ElapsedMilliseconds

    try { Write-Snapshot -path $OutFile -obj $snapshot } catch { Write-Warning ("write failed: {0}" -f $_.Exception.Message) }

    # Admin snapshot (with IPs) only when explicitly enabled AND the folder is
    # provably auth-protected (.secured marker). Otherwise it is never written.
    if (Test-AdminEnabled $AdminOutFile) {
        try { Write-Snapshot -path $AdminOutFile -obj $adminSnapshot } catch { Write-Warning ("admin write failed: {0}" -f $_.Exception.Message) }
    }
    $msSnap = $swLoop.ElapsedMilliseconds - $msAcq

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
                # -ignore ONLY here: muted players are dropped during the read, so $ActivityMax
                # caps publishable events (they can't eat cap slots and shorten the feed's reach).
                # The admin history call below deliberately passes no ignore - it stays complete.
                $pev  = Build-ConnHistory -dir $LogDir -days $ActivityDays -maxEvents $ActivityMax `
                                          -ignore (Get-GfIgnoreList $IgnoreFile)
                $pgeo = Get-GeoBatch -ips @($pev | ForEach-Object { $_.ip }) -panelPort $PanelPort
                Write-Snapshot -path $ActivityOutFile -obj ([ordered]@{
                    updated = $now.ToString('o')
                    days    = $ActivityDays
                    count   = $pev.Count
                    events  = (Build-PublicActivity -events $pev -geo $pgeo)
                })
            } catch { Write-Warning ("activity write failed: {0}" -f $_.Exception.Message) }
        }

        if ((Test-AdminEnabled $AdminOutFile) -and -not [string]::IsNullOrEmpty($AdminHistoryFile)) {
            try {
                $ev   = Build-ConnHistory -dir $LogDir -days $AdminHistoryDays -maxEvents $AdminHistoryMax
                $ageo = Get-GeoBatch -ips @($ev | ForEach-Object { $_.ip }) -panelPort $PanelPort
                # The admin history is the ONE feed that carries the region (state / province)
                # alongside the code - it is already behind the .secured gate with the full IP,
                # so a coarser location adds no exposure. activity.json stays country-only.
                foreach ($e in $ev) {
                    $bare     = ([string]$e.ip -split ':')[0]
                    $hit      = if ($ageo.ContainsKey($bare)) { $ageo[$bare] } else { $null }
                    $e.cc     = if ($hit) { $hit.cc } else { '' }
                    $e.region = if ($hit) { $hit.region } else { '' }
                }
                Write-Snapshot -path $AdminHistoryFile -obj ([ordered]@{
                    updated = $now.ToString('o')
                    days    = $AdminHistoryDays
                    count   = $ev.Count
                    events  = $ev
                })
            } catch { Write-Warning ("history write failed: {0}" -f $_.Exception.Message) }
        }

        # --- Gameplay stats: ingest new GF_STAT/GF_MATCH lines, project the leaderboard ---
        # Ingest runs UNGATED (the accumulator is box-local and must not lose lines while the
        # admin gate is down); only the GUID-carrying projection waits for the .secured marker.
        try {
            $chunk = Read-GfStatChunk -path $gamesLogPath -offset $gfStatState.offset -ctime $gfStatState.ctime
            $added = 0
            if ($chunk.lines.Count -gt 0) {
                $added = Merge-GfStatLines -state $gfStatState -lines $chunk.lines -day ($now.ToString('yyyy-MM-dd'))
            }
            if ($chunk.newOffset -ne $gfStatState.offset -or $chunk.newCtime -ne $gfStatState.ctime -or $added -gt 0) {
                $gfStatState.offset = $chunk.newOffset
                $gfStatState.ctime  = $chunk.newCtime
                Write-Snapshot -path $GameStatsState -obj ([ordered]@{
                    offset = $gfStatState.offset
                    ctime  = $gfStatState.ctime
                    days   = $gfStatState.days
                })
            }
            if ((Test-AdminEnabled $AdminOutFile) -and -not [string]::IsNullOrEmpty($GameStatsFile)) {
                Write-Snapshot -path $GameStatsFile -obj ([ordered]@{
                    updated = $now.ToString('o')
                    days    = $gfStatState.days
                })
            }
        } catch { Write-Warning ("gamestats ingest failed: {0}" -f $_.Exception.Message) }
    }
    $msHist = $swLoop.ElapsedMilliseconds - $msAcq - $msSnap

    # --- Health snapshot (ops/detailed status: admin page + box watchdog) --------
    # No PII (round/map/counts/stuck-state), but written to the same .secured-gated
    # admin folder so the whole ops surface stays behind Basic auth.
    if ((Test-AdminEnabled $AdminOutFile) -and -not [string]::IsNullOrEmpty($HealthOutFile)) {
        # Track round advancement. The stuck detector trips only while the server is up,
        # SOMEONE is on, it is NOT a legitimate pregame lobby hold, and the round number
        # has not moved for $RoundStuckSecs. Down/lobby resets the clock so a fresh start
        # or an intentional hold never reads as stuck.
        #
        # The population gate counts BOTS TOO, deliberately. Round activation is
        # spawn-driven, so a server with nobody on it (0 humans AND 0 bots) legitimately
        # never advances a round and must not trip the detector — that is the only thing
        # this gate is defending against. Gating on humans alone made a bots-only server
        # invisible: it could sit frozen for hours, and the flag only tripped when a human
        # finally joined, so the first player to arrive WAS the trigger — they walked into
        # the frozen round and then watched the map_rotate. (2026-07-12: a round froze at
        # 13:31 with 0 humans and was not rescued until a human joined 85 min later.)
        if ($online -and -not $lobbyHold) {
            if ($round -ne $lastRound) { $lastRound = $round; $lastRoundChangeAt = Get-Date }
        } else {
            $lastRound = $round
            $lastRoundChangeAt = Get-Date
        }
        $secsSinceRoundChange = [int]((Get-Date) - $lastRoundChangeAt).TotalSeconds
        $playersOnline = $humansOnline + $botCount
        $roundStuck = ($online -and $playersOnline -gt 0 -and -not $lobbyHold -and $secsSinceRoundChange -ge $RoundStuckSecs)

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

    # ── stall verdict. >10s means this iteration alone can push admin.json toward consumers'
    # staleness cutoffs (conn_logger skips its diff at 30s). The phase split names the culprit.
    $swLoop.Stop()
    $msHealth = $swLoop.ElapsedMilliseconds - $msAcq - $msSnap - $msHist
    if ($swLoop.ElapsedMilliseconds -gt 10000) {
        Write-Warning ("SLOW POLL: {0:N1}s total (acquire={1:N1}s snapshots={2:N1}s history+geo={3:N1}s health={4:N1}s) - this is what makes admin.json stale for consumers" -f `
            ($swLoop.ElapsedMilliseconds/1000), ($msAcq/1000), ($msSnap/1000), ($msHist/1000), ($msHealth/1000))
    }

    Start-Sleep -Seconds $IntervalSeconds
}
