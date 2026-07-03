# conn_logger.ps1 - Gunfight VPS connection logger (standalone RCON status poller)
# ------------------------------------------------------------------------------
# Polls the local dedicated server's RCON `status` on an interval and appends a
# clean, grep-friendly record of every player connect / disconnect - including
# their IP - to a dated log file on the box.
#
# WHY RCON status (and not GSC): Plutonium T5 GSC cannot read a player's IP.
# The RCON `status` reply is the only native place the IP (its `address` column)
# is exposed, so this runs OUTSIDE the mod - no mod change, no mod.ff rebuild,
# zero gameplay risk.
#
# The RCON password is read at runtime from dedicated.cfg (never hard-coded here
# and never written to the log), keeping it out of git per the project's secrets
# handling. Run it as the account that runs the game server (Administrator on the
# current VPS) so LOCALAPPDATA resolves to the right Plutonium storage.
#
# Windows PowerShell 5.1 compatible. ASCII-only source.
#
# Usage (interactive test):
#   powershell -ExecutionPolicy Bypass -File conn_logger.ps1
# Usage (as a boot service): see install_task.ps1 in this folder.
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string] $RconHost      = '127.0.0.1',
    [int]    $RconPort      = 28960,
    [int]    $IntervalSeconds = 15,
    # RCON password source (in priority order): -RconPassword, then env GF_RCON_PW,
    # then parsed from the rcon_password line in -CfgPath.
    [string] $RconPassword  = '',
    [string] $CfgPath       = '',
    [string] $LogDir        = '',
    [int]    $RecvTimeoutMs = 1500
)

$ErrorActionPreference = 'Stop'

# --- Resolve default paths ----------------------------------------------------
# This script lives at storage\t5\mods\mp_gunfight\tools\conn_logger\ ; walk four
# parents to reach storage\t5\ (where dedicated.cfg and the logs\ folder live).
$storageT5 = $PSScriptRoot
for ($i = 0; $i -lt 4; $i++) { $storageT5 = Split-Path -Parent $storageT5 }

if ([string]::IsNullOrEmpty($CfgPath)) { $CfgPath = Join-Path $storageT5 'dedicated.cfg' }
if ([string]::IsNullOrEmpty($LogDir))  { $LogDir  = Join-Path $storageT5 'logs' }

$stateFile = Join-Path $LogDir '.connstate.json'

# --- Resolve RCON password ----------------------------------------------------
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
    Write-Error "No rcon_password found. Set it in $CfgPath (set rcon_password `"...`"), pass -RconPassword, or set env GF_RCON_PW."
    exit 1
}

# --- RCON send/receive --------------------------------------------------------
# Mirrors tools\rcon\server.js: 4x 0xFF out-of-band header + "rcon <pw> <cmd>".
# Reads all reply packets until the socket read times out (status can span
# several UDP packets); strips each packet's 0xFF header + "print" marker.
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
            try {
                $data = $udp.Receive([ref]$remote)
            } catch {
                break   # ReceiveTimeout -> no more packets
            }
            if ($data.Length -gt 4) {
                $text = [System.Text.Encoding]::UTF8.GetString($data, 4, $data.Length - 4)
                if ($text.StartsWith('print')) { $text = $text.Substring(5) }
                [void]$sb.Append($text)
            }
        }
    } finally {
        $udp.Close()
    }
    return $sb.ToString()
}

# --- Parse `status` output ----------------------------------------------------
# T5 columns: num score ping guid name lastmsg address qport rate
# Name may contain spaces + ^color codes, so parse num/score/ping/guid from the
# LEFT and lastmsg/address/qport/rate from the RIGHT; the middle is the name.
# Only humans are kept (address must be ip:port); bots/loopback are skipped.
function Parse-StatusPlayers {
    param([string]$text)
    $players = @{}
    foreach ($line in ($text -split "`n")) {
        $t = $line.Trim()
        if ($t -eq '') { continue }
        if ($t -notmatch '^\d+\s') { continue }   # skip "map:", header, dashes
        $tok = $t -split '\s+'
        if ($tok.Count -lt 8) { continue }

        $guid    = $tok[3]
        $rate    = $tok[$tok.Count - 1]
        $qport   = $tok[$tok.Count - 2]
        $address = $tok[$tok.Count - 3]
        $ping    = $tok[2]

        if ($address -notmatch '^\d{1,3}(\.\d{1,3}){3}:\d+$') { continue }  # humans only

        $nameEnd = $tok.Count - 5
        $name = ''
        if ($nameEnd -ge 4) { $name = ($tok[4..$nameEnd] -join ' ') }
        $name = ($name -replace '\^[0-9]', '').Trim()
        if ($name -eq '') { $name = '(unknown)' }

        $key = if ($guid -and $guid -ne '0') { $guid } else { $address }
        $players[$key] = @{ key = $key; name = $name; ip = $address; guid = $guid; ping = $ping }
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

function Write-Event {
    param([string]$dir, [string]$verb, [hashtable]$p, [string]$extra = '')
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = '{0}  {1,-8} ip={2}  name="{3}"  guid={4}  ping={5}{6}' -f `
             $stamp, $verb, $p.ip, $p.name, $p.guid, $p.ping, $extra
    Add-Content -Path (Get-LogPath $dir) -Value $line -Encoding UTF8
    Write-Host $line
}

# --- Startup ------------------------------------------------------------------
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

$coldStart = -not (Test-Path $stateFile)
$state     = Load-State $stateFile
$firstPoll = $true

$banner = ('{0}  ----- conn_logger started (host={1}:{2} interval={3}s) -----' -f `
           (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $RconHost, $RconPort, $IntervalSeconds)
Add-Content -Path (Get-LogPath $LogDir) -Value $banner -Encoding UTF8
Write-Host $banner

# --- Poll loop ----------------------------------------------------------------
while ($true) {
    $raw = ''
    try {
        $raw = Send-Rcon -ipHost $RconHost -port $RconPort -password $rconPw -command 'status' -timeoutMs $RecvTimeoutMs
    } catch {
        Write-Warning ("rcon send failed: {0}" -f $_.Exception.Message)
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    # A valid status reply always contains "map:". Anything else = failed poll;
    # skip the diff so a dropped reply is NOT misread as "everyone left".
    if ($raw -notmatch 'map:') {
        Write-Warning 'no valid status reply this poll (server down or rcon refused); skipping diff'
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    $current = Parse-StatusPlayers $raw

    # New connections
    foreach ($key in $current.Keys) {
        if (-not $state.ContainsKey($key)) {
            $p = $current[$key]
            $verb = if ($firstPoll -and $coldStart) { 'ONLINE' } else { 'CONNECT' }
            Write-Event -dir $LogDir -verb $verb -p $p
            $state[$key] = @{ key = $key; name = $p.name; ip = $p.ip; guid = $p.guid; firstSeen = (Get-Date).ToString('o') }
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
        Write-Event -dir $LogDir -verb 'LEFT' -p $p -extra $extra
        $state.Remove($key)
    }

    Save-State -path $stateFile -state $state
    $firstPoll = $false
    Start-Sleep -Seconds $IntervalSeconds
}
