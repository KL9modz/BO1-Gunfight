# GF Join Notifier (PowerShell) — runs ON the VPS, pushes a phone notification via
# ntfy.sh on player activity. Native Windows PowerShell 5.1, no Node/npm required.
#
# Events:
#   JOIN            a human joins (bots excluded)               -> default priority
#   FIRST / active  first human joins an EMPTY server           -> high priority
#   LEAVE           a human leaves           (notifyLeaves)     -> low priority
#   EMPTY           last human leaves, server now 0 (notifyEmpty) low
#   HEARTBEAT       periodic "still alive - N online" (heartbeatMins) min priority
#
# Polls `status` over loopback RCON, diffs the human-player set by GUID, POSTs to your
# ntfy topic. Config: env vars (GF_*) override config.json (next to this file) override
# defaults. rcon_password defaults to the value read out of ..\..\..\..\dedicated.cfg.
#
# Run:   powershell -ExecutionPolicy Bypass -File join-notify.ps1
# See README.md for the scheduled-task (auto-start) setup.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) {
  Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
}

function Strip-Colors($s) {
  return ([regex]::Replace([string]$s, '\^[0-9a-zA-Z]', '')).Trim()
}

function As-Bool($v, $def) {
  if ($null -eq $v) { return $def }
  if ($v -is [bool]) { return $v }
  $s = ([string]$v).ToLower()
  return ($s -eq '1' -or $s -eq 'true')
}

function Get-CfgVal($fileCfg, $envKey, $fileKey, $def) {
  $ev = [Environment]::GetEnvironmentVariable($envKey)
  if ($null -ne $ev -and $ev -ne '') { return $ev }
  if ($fileCfg -and ($fileCfg.PSObject.Properties.Name -contains $fileKey)) {
    $v = $fileCfg.$fileKey
    if ($null -ne $v -and $v -ne '') { return $v }
  }
  return $def
}

function Read-RconPw {
  # this file: storage\t5\mods\mp_gunfight\tools\notify -> 4 up = storage\t5
  $cfgPath = Join-Path $PSScriptRoot '..\..\..\..\dedicated.cfg'
  if (Test-Path $cfgPath) {
    $t = Get-Content $cfgPath -Raw
    $m = [regex]::Match($t, '(?im)^\s*set[as]?\s+"?rcon_password"?\s+"([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value }
  }
  return ''
}

# ── RCON (UDP OOB) ────────────────────────────────────────────────────────────
# Loopback port of the RCON panel (tools\rcon\server.js). Polls prefer the panel's
# /api/status — its queue paces + coalesces ALL box-side rcon so independent pollers
# don't trip the server's ~1-reply-per-0.7s rcon limit and eat each other's replies.
# Direct Send-Rcon below is the fallback when the panel isn't running.
$script:PanelPort = 3000

function Send-Rcon($ip, $port, $pw, $command, $timeoutMs = 3000, $collectMs = 300) {
  $udp = New-Object System.Net.Sockets.UdpClient
  try {
    $udp.Connect($ip, [int]$port)
    $prefix  = [byte[]](255, 255, 255, 255)
    $payload = [System.Text.Encoding]::ASCII.GetBytes("rcon $pw $command")
    $packet  = New-Object 'byte[]' ($prefix.Length + $payload.Length)
    [Array]::Copy($prefix, 0, $packet, 0, $prefix.Length)
    [Array]::Copy($payload, 0, $packet, $prefix.Length, $payload.Length)
    [void]$udp.Send($packet, $packet.Length)

    $sb  = New-Object System.Text.StringBuilder
    $ep  = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $udp.Client.ReceiveTimeout = $timeoutMs
    $got = $false
    while ($true) {
      try { $data = $udp.Receive([ref]$ep) }
      catch { break }   # timeout ends collection
      [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($data))
      if (-not $got) { $got = $true; $udp.Client.ReceiveTimeout = $collectMs }
    }
    if (-not $got) { throw 'timeout' }
    return $sb.ToString()
  }
  finally { $udp.Close() }
}

function Parse-RconResponse($s) {
  $nl = $s.IndexOf("`n")
  if ($nl -lt 0) { return $s.Substring([Math]::Min(4, $s.Length)) }
  return $s.Substring($nl + 1).TrimEnd()
}

# Parse map/gametype + human players from `status`. Bot = the ADDRESS column is not a
# real ip:port (and not a listen-server loopback). Player names CAN contain spaces (e.g.
# the bot "MCG Gordon"), so name is not a single token: index the fixed trailing columns
# from the END and take everything between guid and lastmsg as the name. The old fixed
# p[4]/p[6] split misread a spaced name AND shifted the address column, leaking spaced-
# name bots in as humans (that was the "MCG joined" false phone alert).
function Parse-Status($text) {
  $lines   = $text -split "`n"
  $map = ''; $gt = ''; $sepIdx = -1
  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^map:\s*(.+)')      { $map = Strip-Colors $Matches[1]; continue }
    if ($line -match '^gametype:\s*(.+)') { $gt  = Strip-Colors $Matches[1]; continue }
    if ($sepIdx -lt 0 -and $line -match '^---') { $sepIdx = $i }
  }
  $players = New-Object System.Collections.ArrayList
  if ($sepIdx -ge 0) {
    for ($i = $sepIdx + 1; $i -lt $lines.Length; $i++) {
      $line = $lines[$i].Trim()
      if ($line -eq '') { continue }
      $p = $line -split '\s+'
      if ($p.Length -lt 8 -or $p[0] -notmatch '^\d+$') { continue }
      $addr    = $p[$p.Length - 3]                 # address = 3rd-from-last (name may hold spaces)
      $nameEnd = $p.Length - 5
      $name    = ''
      if ($nameEnd -ge 4) { $name = ($p[4..$nameEnd] -join ' ') }   # name = between guid and lastmsg
      $name = (Strip-Colors $name)
      if ($name -eq '') { continue }
      # Human = a real ip:port (or a listen-server loopback); anything else is a bot/non-human.
      $isBot = -not ($addr -eq 'loopback' -or $addr -eq 'local' -or $addr -match '^\d{1,3}(\.\d{1,3}){3}:\d+$')
      $pg = $null; if ($p[2] -match '^\d+$') { $pg = [int]$p[2] }   # "CNCT"/"ZMBI" -> null
      [void]$players.Add([pscustomobject]@{
        num = [int]$p[0]; guid = $p[3]; name = $name; addr = $addr; ping = $pg; bot = $isBot
      })
    }
  }
  return [pscustomobject]@{ map = $map; gametype = $gt; players = $players }
}

function P-Key($p) {
  if ($p.guid -and $p.guid -ne '0') { return "g:$($p.guid)" }
  return "n:$($p.name)"
}

# ── ntfy push ─────────────────────────────────────────────────────────────────
# Player name goes in the BODY (utf8-safe); Title header stays ASCII so a fancy name
# can never break header encoding.
function Send-Ntfy($cfg, $title, $message, $priority, $tags) {
  if (-not $cfg.ntfyTopic) { Write-Log '[ntfy] no topic configured - cannot send'; return $false }
  $uri = "$($cfg.ntfyServer)/$($cfg.ntfyTopic)"
  $headers = @{ Title = $title; Priority = $priority; Tags = $tags }
  if ($cfg.ntfyToken) { $headers['Authorization'] = "Bearer $($cfg.ntfyToken)" }
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$message)
    Invoke-RestMethod -Uri $uri -Method Post -Body $bytes -Headers $headers `
      -ContentType 'text/plain; charset=utf-8' -TimeoutSec 15 | Out-Null
    return $true
  }
  catch { Write-Log "[ntfy] error: $($_.Exception.Message)"; return $false }
}

# ── GeoIP (region from IP) ──────────────────────────────────────────────────────
# One HTTP GET to ip-api.com per UNIQUE IP, cached for the process lifetime. 2s timeout
# + graceful '' fallback: a slow/down lookup never delays a push by more than 2s (and
# never at all for a repeat IP). LAN/loopback/link-local IPs are skipped.
$script:geoCache = @{}
function Get-Region($addr) {
  $ip = ([string]$addr).Split(':')[0]
  if (-not $ip -or $ip -eq 'unknown') { return '' }
  if ($ip -match '^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)') { return '' }
  if ($script:geoCache.ContainsKey($ip)) { return $script:geoCache[$ip] }
  $region = ''
  try {
    $r = Invoke-RestMethod -UseBasicParsing -TimeoutSec 2 -Uri "http://ip-api.com/json/${ip}?fields=status,country,city"
    if ($r.status -eq 'success') {
      $parts = @($r.city, $r.country | Where-Object { $_ })
      $region = ($parts -join ', ')
    }
  } catch { $region = '' }
  $script:geoCache[$ip] = $region
  return $region
}

# Human-readable session length. 45 -> "45s", 1830000ms -> "30m 30s", 3720000 -> "1h 2m".
function Format-Duration($ms) {
  $s = [int][Math]::Max(0, [Math]::Round($ms / 1000))
  if ($s -lt 60) { return "${s}s" }
  $m = [int][Math]::Floor($s / 60)
  if ($m -lt 60) { $r = $s % 60; if ($r) { return "${m}m ${r}s" } else { return "${m}m" } }
  $h = [int][Math]::Floor($m / 60); $rm = $m % 60
  if ($rm) { return "${h}h ${rm}m" } else { return "${h}h" }
}

# region + ping -> parts appended to a JOIN alert (empty array if we have neither).
function Get-DetailBits($region, $ping) {
  $bits = New-Object System.Collections.ArrayList
  if ($region) { [void]$bits.Add([string]$region) }
  if ($null -ne $ping) { [void]$bits.Add("${ping}ms") }
  return $bits
}
function Get-JoinDetail($region, $ping) {
  $bits = Get-DetailBits $region $ping
  if ($bits.Count -gt 0) { return "`n" + ($bits -join '  |  ') }
  return ''
}
function Get-LogDetail($region, $ping) {
  $bits = Get-DetailBits $region $ping
  if ($bits.Count -gt 0) { return "  [" + ($bits -join ', ') + "]" }
  return ''
}

# ── Poll tick ─────────────────────────────────────────────────────────────────
$script:known      = $null   # hashtable key-> {name,joinedAt,ping,addr}; $null until first poll seeds it
$script:lastOnline = 0
$script:lastCtx    = ''

function Do-Tick($cfg) {
  # Panel-first (paced/coalesced box-wide rcon queue), direct rcon only if the panel is down.
  $text = $null
  try {
    $u = 'http://127.0.0.1:{0}/api/status?host={1}&port={2}&password={3}' -f $script:PanelPort, $cfg.host, $cfg.port, [uri]::EscapeDataString([string]$cfg.password)
    $j = Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 -Uri $u
    if ($j.ok) { $text = [string]$j.raw }
    else { Write-Log "status poll failed via panel ($($j.error)) - keeping last baseline"; return }
  } catch { $text = $null }
  if ($null -eq $text) {
    try { $text = Parse-RconResponse (Send-Rcon $cfg.host $cfg.port $cfg.password 'status') }
    catch { Write-Log "status poll failed ($($_.Exception.Message)) - keeping last baseline"; return }
  }

  $st   = Parse-Status $text
  $now  = Get-Date
  $real = @($st.players | Where-Object { -not $_.bot })
  $cur  = @{}
  foreach ($p in $real) {
    $k = P-Key $p
    $joined = $now
    if ($null -ne $script:known -and $script:known.ContainsKey($k)) { $joined = $script:known[$k].joinedAt }
    $cur[$k] = [pscustomobject]@{ name = $p.name; joinedAt = $joined; ping = $p.ping; addr = $p.addr }
  }

  $ctx = ''
  if ($st.map) { $ctx = $st.map; if ($st.gametype) { $ctx = "$($st.map) / $($st.gametype)" } }
  $ctxSuffix = ''
  if ($ctx) { $ctxSuffix = "  -  $ctx" }
  $script:lastOnline = $cur.Count
  $script:lastCtx    = $ctx

  if ($null -eq $script:known) {           # seed silently
    $script:known = $cur
    $b = "baseline seeded: $($real.Count) human player(s) online"
    if ($ctx) { $b += "  [$ctx]" }
    Write-Log $b
    return
  }

  $wasEmpty  = ($script:known.Count -eq 0)
  $firstDone = $false
  foreach ($p in $real) {
    $k = P-Key $p
    if (-not $script:known.ContainsKey($k)) {
      $region = ''
      if ($cfg.geoLookup) { $region = Get-Region $p.addr }   # <=2s, cached per IP
      $detail = Get-JoinDetail $region $p.ping
      $logd   = Get-LogDetail  $region $p.ping
      if ($wasEmpty -and -not $firstDone) {
        $firstDone = $true
        Write-Log "FIRST $($p.name)  (server now active, $($cur.Count) online)$logd"
        if ($cfg.notifyFirstJoin) {
          [void](Send-Ntfy $cfg "$($cfg.serverName) - server now active" `
            "$($p.name) joined an empty server$ctxSuffix$detail" 'high' 'green_circle,bust_in_silhouette')
          continue
        }
      }
      Write-Log "JOIN  $($p.name)  ($($cur.Count) online)$logd"
      [void](Send-Ntfy $cfg "$($cfg.serverName) - player joined" `
        "$($p.name) joined  ($($cur.Count) online)$ctxSuffix$detail" 'default' 'bust_in_silhouette')
    }
  }

  if ($cfg.notifyLeaves) {
    foreach ($k in @($script:known.Keys)) {
      if (-not $cur.ContainsKey($k)) {
        $info = $script:known[$k]
        $sess = Format-Duration (($now - $info.joinedAt).TotalMilliseconds)
        Write-Log "LEAVE $($info.name)  ($($cur.Count) online, played $sess)"
        [void](Send-Ntfy $cfg "$($cfg.serverName) - player left" `
          "$($info.name) left after $sess  ($($cur.Count) online)" 'low' 'wave')
      }
    }
  }

  if ($cfg.notifyEmpty -and $cur.Count -eq 0 -and $script:known.Count -gt 0) {
    Write-Log 'EMPTY server now has 0 players'
    [void](Send-Ntfy $cfg "$($cfg.serverName) - server empty" `
      "Last player left - 0 online$ctxSuffix" 'low' 'zzz')
  }

  $script:known = $cur
}

# ── Load config ───────────────────────────────────────────────────────────────
$fileCfg = $null
$cfgFile = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $cfgFile) {
  try { $fileCfg = Get-Content $cfgFile -Raw | ConvertFrom-Json }
  catch { Write-Log "[cfg] bad config.json: $($_.Exception.Message)" }
}

$cfg = [pscustomobject]@{
  host            = Get-CfgVal $fileCfg 'GF_HOST' 'host' '127.0.0.1'
  port            = [int](Get-CfgVal $fileCfg 'GF_PORT' 'port' 28960)
  password        = ''
  ntfyServer      = ([string](Get-CfgVal $fileCfg 'GF_NTFY_SERVER' 'ntfyServer' 'https://ntfy.sh')).TrimEnd('/')
  ntfyTopic       = Get-CfgVal $fileCfg 'GF_NTFY_TOPIC' 'ntfyTopic' ''
  ntfyToken       = Get-CfgVal $fileCfg 'GF_NTFY_TOKEN' 'ntfyToken' ''
  pollMs          = [int](Get-CfgVal $fileCfg 'GF_POLL_MS' 'pollMs' 12000)
  notifyLeaves    = As-Bool (Get-CfgVal $fileCfg 'GF_NOTIFY_LEAVES' 'notifyLeaves' $false) $false
  notifyFirstJoin = As-Bool (Get-CfgVal $fileCfg 'GF_NOTIFY_FIRST' 'notifyFirstJoin' $true) $true
  notifyEmpty     = As-Bool (Get-CfgVal $fileCfg 'GF_NOTIFY_EMPTY' 'notifyEmpty' $false) $false
  heartbeatMins   = [int](Get-CfgVal $fileCfg 'GF_HEARTBEAT_MINS' 'heartbeatMins' 0)
  serverName      = Get-CfgVal $fileCfg 'GF_SERVER_NAME' 'serverName' 'Gunfight'
  quiet           = As-Bool (Get-CfgVal $fileCfg 'GF_QUIET_START' 'quietStart' $false) $false
  geoLookup       = As-Bool (Get-CfgVal $fileCfg 'GF_GEO_LOOKUP' 'geoLookup' $true) $true
}
$pw = Get-CfgVal $fileCfg 'GF_RCON_PW' 'password' ''
if (-not $pw) { $pw = Read-RconPw }
$cfg.password = $pw

$pwLen = 0; if ($cfg.password) { $pwLen = $cfg.password.Length }
Write-Log 'GF Join Notifier starting'
Write-Log "  server     $($cfg.host):$($cfg.port)"
Write-Log "  rcon pw    $(if ($pwLen) { "($pwLen chars)" } else { 'MISSING' })"
Write-Log "  ntfy       $($cfg.ntfyServer)/$(if ($cfg.ntfyTopic) { $cfg.ntfyTopic } else { '(NO TOPIC SET)' })"
Write-Log "  poll       $($cfg.pollMs)ms   leaves=$($cfg.notifyLeaves)  firstJoin=$($cfg.notifyFirstJoin)  empty=$($cfg.notifyEmpty)"
Write-Log "  heartbeat  $(if ($cfg.heartbeatMins -gt 0) { "$($cfg.heartbeatMins) min" } else { 'off' })"
Write-Log "  geo        $(if ($cfg.geoLookup) { 'on (ip-api.com)' } else { 'off' })"

if (-not $cfg.ntfyTopic) { Write-Host "`nFATAL: no ntfy topic set. Put ntfyTopic in config.json or env GF_NTFY_TOPIC.`n"; exit 1 }
if (-not $cfg.password)  { Write-Host "`nFATAL: no rcon_password (not in config/env, not found in dedicated.cfg).`n"; exit 1 }

if (-not $cfg.quiet) {
  [void](Send-Ntfy $cfg "$($cfg.serverName) - notifier online" `
    'Join notifier started and watching the server.' 'low' 'satellite_antenna')
}

$lastHeartbeat = Get-Date
while ($true) {
  Do-Tick $cfg
  if ($cfg.heartbeatMins -gt 0 -and ((Get-Date) - $lastHeartbeat).TotalMinutes -ge $cfg.heartbeatMins) {
    $lastHeartbeat = Get-Date
    $msg = "Watcher alive - $($script:lastOnline) player(s) online"
    if ($script:lastCtx) { $msg += "  -  $($script:lastCtx)" }
    Write-Log "HEARTBEAT $msg"
    [void](Send-Ntfy $cfg "$($cfg.serverName) - heartbeat" $msg 'min' 'green_heart')
  }
  Start-Sleep -Milliseconds $cfg.pollMs
}
