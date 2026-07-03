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

# Parse map/gametype + human players from `status`. Bot = guid "0" AND addr "unknown".
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
      if ($p.Length -lt 7 -or $p[0] -notmatch '^\d+$') { continue }
      $isBot = ($p[3] -eq '0' -and $p[6] -eq 'unknown')
      [void]$players.Add([pscustomobject]@{
        num = [int]$p[0]; guid = $p[3]; name = (Strip-Colors $p[4]); addr = $p[6]; bot = $isBot
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

# ── Poll tick ─────────────────────────────────────────────────────────────────
$script:known      = $null   # hashtable key->name; $null until first poll seeds it
$script:lastOnline = 0
$script:lastCtx    = ''

function Do-Tick($cfg) {
  try { $raw = Send-Rcon $cfg.host $cfg.port $cfg.password 'status' }
  catch { Write-Log "status poll failed ($($_.Exception.Message)) - keeping last baseline"; return }

  $st   = Parse-Status (Parse-RconResponse $raw)
  $real = @($st.players | Where-Object { -not $_.bot })
  $cur  = @{}
  foreach ($p in $real) { $cur[(P-Key $p)] = $p.name }

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
      if ($wasEmpty -and -not $firstDone) {
        $firstDone = $true
        Write-Log "FIRST $($p.name)  (server now active, $($cur.Count) online)"
        if ($cfg.notifyFirstJoin) {
          [void](Send-Ntfy $cfg "$($cfg.serverName) - server now active" `
            "$($p.name) joined an empty server$ctxSuffix" 'high' 'green_circle,bust_in_silhouette')
          continue
        }
      }
      Write-Log "JOIN  $($p.name)  ($($cur.Count) online)"
      [void](Send-Ntfy $cfg "$($cfg.serverName) - player joined" `
        "$($p.name) joined  ($($cur.Count) online)$ctxSuffix" 'default' 'bust_in_silhouette')
    }
  }

  if ($cfg.notifyLeaves) {
    foreach ($k in @($script:known.Keys)) {
      if (-not $cur.ContainsKey($k)) {
        $nm = $script:known[$k]
        Write-Log "LEAVE $nm  ($($cur.Count) online)"
        [void](Send-Ntfy $cfg "$($cfg.serverName) - player left" `
          "$nm left  ($($cur.Count) online)" 'low' 'wave')
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
