# GF Join Notifier (PowerShell) — runs ON the VPS, pushes a phone notification via
# ntfy.sh on player activity. Native Windows PowerShell 5.1, no Node/npm required.
#
# Events:
#   JOIN            a human joins (bots excluded)               -> default priority
#   FIRST / active  first human joins an EMPTY server           -> high priority
#   LEAVE           a human leaves           (notifyLeaves)     -> low priority
#   EMPTY           last human leaves, server now 0 (notifyEmpty) low
#   HEARTBEAT       periodic "still alive - N online" (heartbeatMins) min priority
#   ISSUE / recover status poll can't reach the server     (notifyIssues) high / default
#                   edge-triggered after 3 straight failures - see the Poll-failure section
#
# Polls `status` over loopback RCON, diffs the human-player set by GUID, POSTs to your
# ntfy topic. Config: env vars (GF_*) override config.json (next to this file) override
# defaults. rcon_password defaults to the value read out of ..\..\..\..\dedicated.cfg.
#
# Run:   powershell -ExecutionPolicy Bypass -File join-notify.ps1
# See README.md for the scheduled-task (auto-start) setup.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Shared with GF-StatusService: Get-GfIgnoreList (mtime-cached) + Test-GfIgnored. An ignored
# player is treated as NOT CONNECTED here - no JOIN/LEAVE push, and they don't count toward
# "N online", "server now active" or "server empty". So the owner idling on his own server
# can't suppress the high-priority alert that fires when a real player shows up.
# (status_service applies the same list only to its ACTIVITY feed - an ignored player still
# appears in the website's live player list. Different surface, deliberately different rule.)
. (Join-Path $PSScriptRoot '..\ignore_list.ps1')
$script:IgnoreFile = Join-Path $PSScriptRoot '..\ignore.local.json'

# Get-GfMapName: shared map id -> display name, so an alert says "Nuketown", not "mp_nuked".
. (Join-Path $PSScriptRoot '..\map_names.ps1')

# Get-GfPlayerLinks / Get-GfPlayerMention: box-local guid -> Discord user id, so a join card can
# name a known player as themselves in Discord. No table (or an unlinked player) = no mention,
# which is the normal state and never an error.
. (Join-Path $PSScriptRoot '..\player_links.ps1')
$script:PlayerLinkFile = Join-Path $PSScriptRoot '..\players.local.json'

# ORANGE for ALL join activity (owner's choice, 2026-08-18): a join reads the same whether it is
# the first into an empty server or the fifth. It matches the 'high' priority stripe, which is
# what a first join used to render in BY ACCIDENT - but it is set explicitly here, because a
# normal join rides at 'default' priority and would otherwise be blurple.
$script:JoinColor = 0xE67E22
# The call to action, as the last LINE OF THE BODY. Two facts decide the shape: a Discord FOOTER cannot
# be a link (raw text, no markdown, no anchors), while an embed DESCRIPTION does render markdown,
# so [label](url) is clickable there. The embed `url` (whole title blue and clickable) is
# deliberately NOT used as well: two link affordances on a three-line card reads as clutter.
$script:JoinLink = "**Play for free** $([char]0x2794) [gunfight.us](https://gunfight.us/)"

# Send-GfNtfy: the shared ntfy sender (JSON publish, unicode-safe titles).
. (Join-Path $PSScriptRoot '..\ntfy.ps1')

# Resolve-T5Root + Get-RconPassword (shared path/cfg helpers).
. (Join-Path $PSScriptRoot '..\common.ps1')

# ConvertFrom-GfStatus: the shared `status` parser (PS twin of the panel's status_parse.js).
# Only the panel-down FALLBACK path below parses text at all - the happy path consumes the
# panel's already-parsed /api/status JSON, which carries the identical player shape.
. (Join-Path $PSScriptRoot '..\status_parse.ps1')

function Write-Log($msg) {
  Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
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
  # Only reached as a fallback after the GF_RCON_PW env / config password (line ~450) came up
  # empty, so Get-RconPassword's env check is a no-op here — this stays a cfg-only read.
  return (Get-RconPassword -CfgPath (Join-Path (Resolve-T5Root) 'dedicated.cfg'))
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

function P-Key($p) {
  if ($p.guid -and $p.guid -ne '0') { return "g:$($p.guid)" }
  return "n:$($p.name)"
}

# ── ntfy push ─────────────────────────────────────────────────────────────────
# The transport lives in the shared tools\ntfy.ps1 (dot-sourced at the top) - see that file for
# why it is JSON publish and not the X-Title header form. This thin wrapper survives only to keep
# this script's own (cfg, title, message, priority, tags) call shape and to LOG a failure; the
# shared sender deliberately returns $false instead of throwing, so nothing here can be taken
# down by a push.
function Send-Ntfy($cfg, $title, $message, $priority, $tags, $discordColor = 0, $discordPrefix = '', $discordTitle = '', $category = 'default', $discordMessage = '', $discordFields = @()) {
  # Send-GfAlert fans out to every configured transport. $category picks the DISCORD channel and
  # defaults to 'default' deliberately: the joins channel is for PLAYERS JOINING, and only the two
  # join call sites pass 'joins'. This service also emits notifier-online, heartbeat and
  # poll-failure alerts, which are the notifier talking about ITSELF - they belong with the rest
  # of the ops traffic, not in the channel someone watches to see who is playing. It used to
  # hardcode 'joins' here, so every one of them landed in the wrong place (and a service restart
  # put a "notifier online" card in there each time).
  # ⚠ Default to the QUIET channel, never to 'joins': a new call site added later then has to opt
  # IN to the player-facing channel rather than leak into it by inheriting a wrong default.
  $r = Send-GfAlert -Config $cfg -Title ([string]$title) -Message ([string]$message) `
                    -Priority ([string]$priority) -Tags ([string[]]@($tags)) -Category ([string]$category) `
                    -DiscordColor ([int]$discordColor) -DiscordPrefix ([string]$discordPrefix) `
                    -DiscordTitle ([string]$discordTitle) -DiscordMessage ([string]$discordMessage) `
                    -DiscordFields $discordFields
  if ($r.ntfyError)    { Write-Log "[ntfy] send failed: $($r.ntfyError)" }
  if ($r.discordError) { Write-Log "[discord] send failed: $($r.discordError)" }
  return $r.anySent
}

# 👤 one player, 👥 more than one. ntfy renders an emoji-shortcode tag immediately BEFORE the
# title, so this reads as a badge on the alert rather than as text in the body - which is why
# the body only needs the bare "(N)".
function Count-Tag($n) {
  if ([int]$n -gt 1) { return 'busts_in_silhouette' }
  return 'bust_in_silhouette'
}

# ── GeoIP (region from IP) ──────────────────────────────────────────────────────
# One HTTP GET to ip-api.com per UNIQUE IP, cached for the process lifetime. 2s timeout
# + graceful empty fallback: a slow/down lookup never delays a push by more than 2s (and
# never at all for a repeat IP). LAN/loopback/link-local IPs are skipped.
#
# Returns the two halves SEPARATELY - @{ flag = '🇺🇸'; place = 'San Diego, California, United
# States' } - because they land in different parts of the alert: the flag goes in the TITLE,
# the spelled-out place in the BODY. Either can be '' on its own (an odd/missing countryCode
# still yields a place; a city-less result still yields a flag).
# `regionName` is the field that spells the state out ("California"); `region` is the short
# code ("CA") the old single-line format used. Flags render in the ntfy phone app - the
# "emoji flags don't render on Windows" caveat is website-only.
$script:geoCache = @{}

# ISO2 country code -> flag emoji (two regional-indicator symbols, each a 4-byte code point
# built via a surrogate pair). '' for anything not exactly two ASCII letters.
function CC-ToFlag($cc) {
  $u = [string]$cc
  if ($u -notmatch '^[A-Za-z]{2}$') { return '' }
  $u = $u.ToUpper()
  return [char]::ConvertFromUtf32(0x1F1E6 + ([int][char]$u[0] - 65)) + `
         [char]::ConvertFromUtf32(0x1F1E6 + ([int][char]$u[1] - 65))
}

function Get-Region($addr) {
  $none = [pscustomobject]@{ flag = ''; place = '' }
  $ip = ([string]$addr).Split(':')[0]
  if (-not $ip -or $ip -eq 'unknown') { return $none }
  if ($ip -match '^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)') { return $none }
  if ($script:geoCache.ContainsKey($ip)) { return $script:geoCache[$ip] }
  $geo = $none
  try {
    $r = Invoke-RestMethod -UseBasicParsing -TimeoutSec 2 -Uri "http://ip-api.com/json/${ip}?fields=status,country,countryCode,regionName,city"
    if ($r.status -eq 'success') {
      # -Unique keeps first-seen order and collapses a city-state's repeated name, so Berlin
      # reads "Berlin, Germany" rather than "Berlin, Berlin, Germany".
      $geo = [pscustomobject]@{
        flag  = (CC-ToFlag $r.countryCode)
        place = ((@($r.city, $r.regionName, $r.country | Where-Object { $_ }) | Select-Object -Unique) -join ', ')
      }
    }
  } catch { $geo = $none }
  $script:geoCache[$ip] = $geo
  return $geo
}

# ── Connect count ("their 7th connect") ───────────────────────────────────────
# Counted straight out of conn_logger's day-files (storage\t5\logs\players_*.log) - the box's
# only COMPLETE connect record. That is what makes it a lifetime total: this notifier's own
# in-memory state knows nothing before its last restart, and a deploy recycles it routinely.
# Keyed on GUID (stable across name/IP changes), CONNECT lines only:
#   * ONLINE lines are conn_logger's cold-start batch ("who was already here"), so counting
#     them would hand a +1 to whoever happened to be online during a service restart.
#   * LEFT lines are the other half of a session already counted at its CONNECT.
# Cost: one pass over every day-file per JOIN alert (day-files are a few hundred lines and a
# join is a rare event) - deliberately no cache, so the number can't drift from the log.
# Returns $null - NOT 0 - when the log dir/day-files are absent (a laptop run, a box where
# conn_logger never ran): with no record at all, every joiner would read as a first-timer,
# so the alert omits the bit entirely instead of claiming something false.
$script:ConnLogDir = Join-Path (Resolve-T5Root) 'logs'
# How recent a logged CONNECT must be to be THIS join. conn_logger diffs admin.json every 5s
# and we poll every pollMs (12s default), so the line for the join we are announcing may or
# may not be on disk yet - a straight count would read N one time and N+1 the next for the
# same event. So: count what is logged, and add the current join only when the log does not
# already carry it.
$script:ConnCountFreshSec = 120

# ⚠ SELF-CONTAINED ON PURPOSE: tools\tests\service_functions.Tests.ps1 extracts this function by
# AST name and evaluates it alone, so a helper split out of here would fail the tests with
# CommandNotFound. Split it only together with that test's extraction list.
function Get-ConnectCount($guid) {
  $g = ([string]$guid).Trim()
  if (-not $g -or $g -eq '0') { return $null }        # guid 0 = still connecting: identifies nobody
  if (-not (Test-Path -LiteralPath $script:ConnLogDir)) { return $null }
  $files = @(Get-ChildItem (Join-Path $script:ConnLogDir 'players_*.log') -ErrorAction SilentlyContinue)
  if ($files.Count -eq 0) { return $null }
  # ⚠ END-ANCHORED, mirroring status_service's canonical $ConnLineRx over this same format. The
  # old pattern stopped at (?:\s|$) straight after the guid, which is forgeable: name="..." is the
  # one free-text field, so a player renamed to  x"  guid=<victim>  ping=1  writes a line whose
  # FRONT reads as a complete record for the victim while their real one sits at the end. Only the
  # trailing $ can tell those apart -- ping= is the last field on a CONNECT line (conn_logger
  # passes -extra for LEFT only), so the real record is the one that runs to end-of-line.
  # Belt and braces: Write-Event now also strips quotes out of the name, which stops the ambiguous
  # line being written at all. This half is what covers day-files already on disk.
  # name stays .*? (status_service's exact grammar) rather than [^"]*: on a legacy line that DOES
  # carry a quote, the lazy form still resolves the record to its real owner, where [^"]* would
  # throw the whole line away. The end anchor is the part doing the security work.
  # One GUID-agnostic pattern, so a file can be tallied ONCE for every player rather than
  # re-scanned per guid. Same end-anchored grammar as above; group 2 is the guid.
  $rx = [regex]'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+CONNECT\s+ip=\S+\s+name=".*?"\s+guid=(\S+)\s+ping=\S+\s*$'

  # PER-FILE guid->count maps, cached on (length, mtime). The old code opened and regex-scanned
  # EVERY day-file on EVERY call: day-files accrue one per day with no pruning, and a post-match
  # reconnect wave calls this once per joiner inside a single 12s poll tick, so the cost was
  # (players x days) file reads and grew forever. Day-files are append-only and only TODAY's can
  # change, so after the first pass a lookup re-reads one file instead of the whole history.
  # Drift-free by construction - any change to a file's size or timestamp invalidates its entry,
  # which is what the original "deliberately no cache" note was protecting against.
  if ($null -eq $script:ConnFileCache) { $script:ConnFileCache = @{} }

  $n = 0
  $newest = $null
  foreach ($f in $files) {
    $ent = $script:ConnFileCache[$f.FullName]
    if ($null -eq $ent -or $ent.len -ne $f.Length -or $ent.mtime -ne $f.LastWriteTimeUtc) {
      $counts = @{}; $stamps = @{}
      # FileShare::ReadWrite on purpose - conn_logger has today's file open for append on its own
      # 5s cycle, and a sharing violation here would silently UNDERCOUNT rather than fail loudly.
      $fs = $null; $sr = $null
      $read = $false
      try {
        $fs = New-Object System.IO.FileStream($f.FullName, [System.IO.FileMode]::Open,
                                              [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs)
        while ($null -ne ($line = $sr.ReadLine())) {
          $m = $rx.Match($line)
          if (-not $m.Success) { continue }
          $lg = $m.Groups[2].Value
          if ($counts.ContainsKey($lg)) { $counts[$lg]++ } else { $counts[$lg] = 1 }
          $t = [datetime]::MinValue
          if ([datetime]::TryParseExact($m.Groups[1].Value, 'yyyy-MM-dd HH:mm:ss',
                [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) {
            if (-not $stamps.ContainsKey($lg) -or $t -gt $stamps[$lg]) { $stamps[$lg] = $t }
          }
        }
        $read = $true
      } catch { }
      finally { if ($sr) { $sr.Dispose() }; if ($fs) { $fs.Dispose() } }
      # A failed/partial read is NOT cached - it would pin an undercount for the process lifetime.
      if (-not $read) { continue }
      $ent = @{ len = $f.Length; mtime = $f.LastWriteTimeUtc; counts = $counts; stamps = $stamps }
      $script:ConnFileCache[$f.FullName] = $ent
    }
    if ($ent.counts.ContainsKey($g)) {
      $n += $ent.counts[$g]
      if ($ent.stamps.ContainsKey($g)) {
        $t = $ent.stamps[$g]
        if ($null -eq $newest -or $t -gt $newest) { $newest = $t }
      }
    }
  }
  if ($null -eq $newest -or ((Get-Date) - $newest).TotalSeconds -gt $script:ConnCountFreshSec) { $n++ }
  return $n
}

# 1 -> "1st", 2 -> "2nd", 11 -> "11th" (the teens are the reason for the %100 branch).
function Format-Ordinal($n) {
  $i = [int]$n
  $h = $i % 100
  if ($h -ge 11 -and $h -le 13) { return "${i}th" }
  switch ($i % 10) {
    1 { return "${i}st" }
    2 { return "${i}nd" }
    3 { return "${i}rd" }
    default { return "${i}th" }
  }
}

# The bit that lands at the END of a join alert. A brand-new player is spelled out rather than
# rendered "1st connect" - a first-time joiner is the one count worth reading at a glance.
function Format-ConnectCount($n) {
  if ($null -eq $n -or [int]$n -lt 1) { return '' }
  if ([int]$n -eq 1) { return 'first connect' }
  return (Format-Ordinal $n) + ' connect'
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

# location + ping + connect count -> the bits of a JOIN alert's BODY
# ("<flag> City, State, Country  |  42ms  |  7th connect"). Everything scannable (who / how
# many / where) is in the TITLE - this is the detail underneath, and the count sits LAST.
# A ping >= 999 is the connect-time placeholder (no real RTT settled yet at the moment we
# first see the joiner in `status`), so it's dropped rather than shown as a misleading
# "999ms" — join alerts simply omit the ping until it's a real reading.
function Get-DetailBits($loc, $ping, $count) {
  $bits = New-Object System.Collections.ArrayList
  if ($loc) { [void]$bits.Add([string]$loc) }
  if ($null -ne $ping -and $ping -lt 999) { [void]$bits.Add("${ping}ms") }
  $c = Format-ConnectCount $count
  if ($c) { [void]$bits.Add($c) }
  return $bits
}
# Never returns '' — an empty ntfy message renders as a bodyless alert. All three bits drop out
# only when geoLookup is off (or the IP is LAN/loopback), the ping is still the placeholder, and
# there are no day-files to count from.
# THE TWO TRANSPORTS INTENTIONALLY DISAGREE ABOUT THE JOIN HEADLINE. Keep them apart; they are
# not a duplicated string that wants deduplicating.
#
#   ntfy  -> a phone notification, read alone with no surrounding context. It keeps the long-form
#            wording ("joined an empty server (1) Discovery") because everything it does not say
#            is unavailable to the reader.
#   Discord -> a card in a scrolling channel, sitting next to the ones before it. There the same
#            words are clutter, so an empty-server join simply does not mention being empty (the
#            alert IS that news) and the head count trails the map, reading as context rather than
#            as a label stuck to the player's name.
#
# Both are functions so each format is testable without a live server.
function Get-JoinTitleDiscord($name, $mapName, $count) {
  # ⚠ The arrow is built from its CODEPOINT, never pasted as a literal. This file is UTF-8
  # WITHOUT a BOM, and PowerShell 5.1 reads such a file as ANSI - a literal U+2794 would
  # reach Discord as mojibake, and it would look like a Discord problem rather than an
  # encoding one. Same reason the flag emoji are built at runtime, never typed here.
  $t = "$name $([char]0x2794) Joined"
  # SINGLE spaces here. The double-space separators are the ntfy format's, where they group
  # a run-on title on a phone; Discord preserves them literally and they read as a typo.
  # The COLON belongs to the map, not to "Joined" - an unknown map would otherwise leave a
  # dangling "Joined:" with nothing after it (the degenerate path: a map id outside the 26-map
  # table still resolves to its raw mp_* name, so this only bites if the status read has no map).
  if ($mapName)          { $t += ": $mapName" }
  if ([int]$count -gt 1) { $t += " ($count)" }
  return $t
}
# The phone's format, unchanged since before the Discord rework - restored verbatim, including
# the count that is always present and the map trailing everything.
function Get-JoinTitleNtfy($name, $mapName, $count, $isFirst) {
  $mapSuffix = ''
  if ($mapName) { $mapSuffix = "  $mapName" }
  if ($isFirst) { return "$name joined an empty server  ($count)$mapSuffix" }
  return "$name joined  ($count)$mapSuffix"
}
# The DISCORD body. A linked player is shown as their Discord identity INSTEAD of their location
# (owner's choice, 2026-08-19): the mention says who someone is better than a city does, and
# stacking both makes a four-line card out of a two-line event. An UNLINKED player still gets the
# location, because it is the only thing we know about them.
# ⚠ This only works because a mention in an embed DESCRIPTION renders the chip and notifies
# NOBODY. If it ever moves to the message content it starts pinging a player every time they
# join their own server, and then "instead of location" becomes a spam decision, not a layout one.
function Get-JoinFieldsDiscord($loc, $ping, $mention, $link) {
  $fields = @()
  if ($mention)   { $fields += @{ name = 'Discord';  value = $mention } }
  elseif ($loc)   { $fields += @{ name = 'Location'; value = $loc } }
  # ⚠ The call to action is UNLABELLED, and that is the fix for a real bug rather than a style
  # choice: $JoinLink already opens with its own bold lead-in, so a 'Play' heading above it printed
  # the word twice. A Discord field name cannot be empty, so this is a zero-width space - it
  # renders as no heading at all and the CTA reads as its own line.
  # ⚠ Fix the LABEL here, never $JoinLink: that string is the owner's marketing copy.
  if ($link)      { $fields += @{ name = [string][char]0x200B; value = $link } }
  return ,$fields          # comma operator: a 1-element array must not unroll to a bare hashtable
}
function Get-JoinBody($loc, $ping, $count) {
  $bits = Get-DetailBits $loc $ping $count
  if ($bits.Count -gt 0) { return ($bits -join '  |  ') }
  return 'No location data'
}
# The console log takes the place WITHOUT the flag: this lands in a text log on a Windows box,
# where flag emoji don't render.
function Get-LogDetail($place, $ping, $count) {
  $bits = Get-DetailBits $place $ping $count
  if ($bits.Count -gt 0) { return "  [" + ($bits -join ', ') + "]" }
  return ''
}

# ── Poll-failure alerting (🔴) ────────────────────────────────────────────────
# A failed `status` poll means the server - or the RCON panel in front of it - is unreachable.
# Do-Tick runs every pollMs (12s default), so two rules keep this off the spam line:
#   * EDGE-TRIGGERED. One 🔴 when an outage starts, one 🟢 when it clears. Never one per tick.
#   * A STREAK THRESHOLD. A single dropped UDP reply is routine, so the failure must persist
#     $IssueFailStreak consecutive polls (~36s at the default cadence) before it alerts at all.
# A genuinely long outage re-alerts only every $IssueReAlertMins.
#
# ⚠ GF-Watchdog is the AUTHORITY on health, not this: it watches the game process + task states
# and can actually restart them (its checks 3a/3b/3e), and it alerts on trouble AND recovery
# already - including on GF-JoinNotify itself being down. This notifier only reports what its
# own poll sees, so a real outage will buzz once from each. That redundancy is the point (they
# fail independently), but set notifyIssues=false in config.json to leave health to the watchdog.
$script:IssueFailStreak  = 3
$script:IssueReAlertMins = 30
$script:pollFails   = 0      # consecutive failed polls
$script:pollDown    = $false # a 🔴 is outstanding for the current outage
$script:pollAlertAt = $null  # when the current outage last (re-)alerted

function Report-PollFail($cfg, $reason) {
  $script:pollFails++
  Write-Log "status poll failed ($reason) - keeping last baseline  [fail $($script:pollFails)]"
  if (-not $cfg.notifyIssues) { return }
  if ($script:pollFails -lt $script:IssueFailStreak) { return }
  $due = $false
  if (-not $script:pollDown) { $due = $true }
  elseif ($null -ne $script:pollAlertAt -and `
          ((Get-Date) - $script:pollAlertAt).TotalMinutes -ge $script:IssueReAlertMins) { $due = $true }
  if (-not $due) { return }
  $script:pollDown    = $true
  $script:pollAlertAt = Get-Date
  [void](Send-Ntfy $cfg "$($cfg.serverName) - server unreachable" `
    "status poll has failed $($script:pollFails)x`n$reason" 'high' @('red_circle'))
}

function Report-PollOk($cfg) {
  if ($script:pollDown -and $cfg.notifyIssues) {
    Write-Log 'status poll RECOVERED'
    [void](Send-Ntfy $cfg "$($cfg.serverName) - server reachable again" `
      'The status poll is answering again.' 'default' @('green_circle'))
  }
  $script:pollFails   = 0
  $script:pollDown    = $false
  $script:pollAlertAt = $null
}

# ── Poll tick ─────────────────────────────────────────────────────────────────
$script:known      = $null   # hashtable key-> {name,joinedAt,ping,addr}; $null until first poll seeds it
$script:lastOnline = 0
$script:lastCtx    = ''

function Do-Tick($cfg) {
  # Panel-first (paced/coalesced box-wide rcon queue): consume the panel's already-PARSED
  # /api/status JSON - the same shared parser (status_parse.js) the whole box uses, so the
  # notifier and the panel can never drift on how a row classifies. Direct rcon only if the
  # panel is down, parsed by the shared PS twin (status_parse.ps1). Either way $st carries
  # the identical shape: map, gametype, players[{num;guid;name;addr;ping;bot;...}].
  $st = $null
  try {
    $u = 'http://127.0.0.1:{0}/api/status?host={1}&port={2}&password={3}' -f $script:PanelPort, $cfg.host, $cfg.port, [uri]::EscapeDataString([string]$cfg.password)
    $j = Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 -Uri $u
    if ($j.ok) { $st = $j }
    else { Report-PollFail $cfg "panel reached the server but it did not answer: $($j.error)"; return }
  } catch { $st = $null }   # panel itself is down -> fall through to direct rcon
  if ($null -eq $st) {
    try { $st = ConvertFrom-GfStatus (Parse-RconResponse (Send-Rcon $cfg.host $cfg.port $cfg.password 'status')) }
    catch { Report-PollFail $cfg "panel down and direct rcon failed: $($_.Exception.Message)"; return }
  }
  Report-PollOk $cfg   # a poll got through: clears the streak, fires the 🟢 if one is outstanding

  $now  = Get-Date
  # Bots AND ignored players are filtered out in one place, so everything downstream (the
  # join/leave diff, the "N online" count, wasEmpty, the EMPTY transition, the heartbeat)
  # simply never sees them - no per-alert special cases.
  $ign  = Get-GfIgnoreList $script:IgnoreFile
  # -eq $false, NOT -not: demand a POSITIVE human ID. A row we could not classify ($null — in
  # practice a client still connecting, guid 0) must not fire a push yet; it would key by name,
  # then re-key by GUID once it lands, and push twice. Same set as before, said explicitly.
  $real = @($st.players | Where-Object { $_.bot -eq $false -and -not (Test-GfIgnored $ign $_.guid $_.name) })
  $cur  = @{}
  foreach ($p in $real) {
    $k = P-Key $p
    $joined = $now
    if ($null -ne $script:known -and $script:known.ContainsKey($k)) { $joined = $script:known[$k].joinedAt }
    $cur[$k] = [pscustomobject]@{ name = $p.name; joinedAt = $joined; ping = $p.ping; addr = $p.addr }
  }

  # Map reads as its real name ("Nuketown"), same table the admin console + website use; an
  # unlisted id falls through to the raw "mp_*" rather than vanishing.
  $mapName = ''
  if ($st.map) { $mapName = Get-GfMapName $st.map }
  # Join titles carry the map alone (Get-JoinTitle); $ctx (map + gametype) still backs the
  # heartbeat/empty alerts and the watcher's own status line.
  $ctx = ''
  if ($mapName) { $ctx = $mapName; if ($st.gametype) { $ctx = "$ctx / $($st.gametype)" } }
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
      $geo = [pscustomobject]@{ flag = ''; place = '' }
      if ($cfg.geoLookup) { $geo = Get-Region $p.addr }   # <=2s, cached per IP
      # Body leads with the flag and ends with the count:
      # "🇺🇸 San Diego, California, United States  |  42ms  |  7th connect".
      $loc  = ((@($geo.flag, $geo.place) | Where-Object { $_ }) -join ' ')
      $cnt  = $null
      if ($cfg.connectCount) { $cnt = Get-ConnectCount $p.guid }   # day-file scan; $null = no record
      $body = Get-JoinBody $loc $p.ping $cnt
      # Discord drops the connect ordinal (owner's choice, 2026-08-18): in a channel the card is
      # read alongside its neighbours, so "first connect" is clutter. The PHONE keeps it - an
      # ntfy push is read alone, where 'is this someone new' is context it has no other way to
      # convey. Same per-transport split as the titles.
      $dFields = Get-JoinFieldsDiscord $loc $p.ping $mention $script:JoinLink
      $logd = Get-LogDetail $geo.place $p.ping $cnt     # log gets the place without the flag
      $ptag = Count-Tag $cur.Count                      # 👤 / 👥 by TOTAL players online
      $dTitle = Get-JoinTitleDiscord $p.name $mapName $cur.Count
      # Discord-only: a mention is meaningless on ntfy and would render as literal <@123…> there.
      # In an embed description it draws the chip WITHOUT notifying anyone (embeds never notify),
      # which is what we want - the player who just joined does not need their phone buzzed.
      $mention = Get-GfPlayerMention (Get-GfPlayerLinks $script:PlayerLinkFile) $p.guid
      if ($wasEmpty -and -not $firstDone) {
        $firstDone = $true
        Write-Log "FIRST $($p.name)  (server now active, $($cur.Count) online)$logd"
        if ($cfg.notifyFirstJoin) {
          # Named arguments from here on: eight positional slots is how a colour ends up in the
          # mention field.
          [void](Send-Ntfy -cfg $cfg -title (Get-JoinTitleNtfy $p.name $mapName $cur.Count $true) `
                           -message $body -priority 'high' -tags @($ptag) `
                           -discordColor $script:JoinColor -discordTitle $dTitle -discordFields $dFields `
                           -category 'joins')
          continue
        }
      }
      Write-Log "JOIN  $($p.name)  ($($cur.Count) online)$logd"
      [void](Send-Ntfy -cfg $cfg -title (Get-JoinTitleNtfy $p.name $mapName $cur.Count $false) `
                       -message $body -priority 'default' -tags @($ptag) `
                       -discordColor $script:JoinColor -discordTitle $dTitle -discordFields $dFields `
                       -category 'joins')
    }
  }

  if ($cfg.notifyLeaves) {
    foreach ($k in @($script:known.Keys)) {
      if (-not $cur.ContainsKey($k)) {
        $info = $script:known[$k]
        $sess = Format-Duration (($now - $info.joinedAt).TotalMilliseconds)
        Write-Log "LEAVE $($info.name)  ($($cur.Count) online, played $sess)"
        [void](Send-Ntfy $cfg "$($cfg.serverName) - player left" `
          "$($info.name) left after $sess  ($($cur.Count))" 'low' @('wave'))
      }
    }
  }

  if ($cfg.notifyEmpty -and $cur.Count -eq 0 -and $script:known.Count -gt 0) {
    Write-Log 'EMPTY server now has 0 players'
    [void](Send-Ntfy $cfg "$($cfg.serverName) - server empty" `
      "Last player left - 0 online$ctxSuffix" 'low' @('zzz'))
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
  notifyIssues    = As-Bool (Get-CfgVal $fileCfg 'GF_NOTIFY_ISSUES' 'notifyIssues' $true) $true
  heartbeatMins   = [int](Get-CfgVal $fileCfg 'GF_HEARTBEAT_MINS' 'heartbeatMins' 0)
  serverName      = Get-CfgVal $fileCfg 'GF_SERVER_NAME' 'serverName' 'Gunfight'
  quiet           = As-Bool (Get-CfgVal $fileCfg 'GF_QUIET_START' 'quietStart' $false) $false
  geoLookup       = As-Bool (Get-CfgVal $fileCfg 'GF_GEO_LOOKUP' 'geoLookup' $true) $true
  connectCount    = As-Bool (Get-CfgVal $fileCfg 'GF_CONNECT_COUNT' 'connectCount' $true) $true
  # Carried through VERBATIM from the file config. Send-GfAlert reads $Config.discordWebhooks to
  # pick a channel, so a rebuilt config object that DROPS this field silently degrades every alert
  # to ntfy-only - and logs nothing, because an unresolved webhook is indistinguishable from a box
  # that never configured Discord at all. That is exactly how joins reached the phone but not the
  # channel. Deliberately not env-overridable: a webhook URL is a credential and config.json is
  # the one place it lives.
  discordWebhooks = $(if ($fileCfg) { $fileCfg.discordWebhooks } else { $null })
  discordFooter   = $(if ($fileCfg) { $fileCfg.discordFooter } else { $null })
}
$pw = Get-CfgVal $fileCfg 'GF_RCON_PW' 'password' ''
if (-not $pw) { $pw = Read-RconPw }
$cfg.password = $pw

$pwLen = 0; if ($cfg.password) { $pwLen = $cfg.password.Length }
Write-Log 'GF Join Notifier starting'
Write-Log "  server     $($cfg.host):$($cfg.port)"
Write-Log "  rcon pw    $(if ($pwLen) { "($pwLen chars)" } else { 'MISSING' })"
Write-Log "  ntfy       $($cfg.ntfyServer)/$(if ($cfg.ntfyTopic) { $cfg.ntfyTopic } else { '(NO TOPIC SET)' })"
# The banner is the only place a MISSING transport is visible - a silent one cannot be debugged
# from the log after the fact.
Write-Log "  discord    $(if (Get-GfDiscordWebhook -Config $cfg -Category 'joins') { 'on (joins channel, falls back to default)' } else { 'off (no webhook configured)' })"
$linkCount = (Get-GfPlayerLinks $script:PlayerLinkFile).Count
Write-Log "  links      $linkCount player(s) linked to a Discord id$(if ($linkCount -eq 0) { ' (add ids in tools\players.local.json)' })"
Write-Log "  poll       $($cfg.pollMs)ms   leaves=$($cfg.notifyLeaves)  firstJoin=$($cfg.notifyFirstJoin)  empty=$($cfg.notifyEmpty)"
Write-Log "  issues     $(if ($cfg.notifyIssues) { "on (red alert after $($script:IssueFailStreak) failed polls, re-alert $($script:IssueReAlertMins)min)" } else { 'off' })"
Write-Log "  heartbeat  $(if ($cfg.heartbeatMins -gt 0) { "$($cfg.heartbeatMins) min" } else { 'off' })"
Write-Log "  geo        $(if ($cfg.geoLookup) { 'on (ip-api.com)' } else { 'off' })"
Write-Log "  connects   $(if ($cfg.connectCount) { "on ($($script:ConnLogDir))" } else { 'off' })"

if (-not $cfg.ntfyTopic) { Write-Host "`nFATAL: no ntfy topic set. Put ntfyTopic in config.json or env GF_NTFY_TOPIC.`n"; exit 1 }
if (-not $cfg.password)  { Write-Host "`nFATAL: no rcon_password (not in config/env, not found in dedicated.cfg).`n"; exit 1 }

if (-not $cfg.quiet) {
  [void](Send-Ntfy $cfg "$($cfg.serverName) - notifier online" `
    'Join notifier started and watching the server.' 'low' @('satellite_antenna'))
}

$lastHeartbeat = Get-Date
while ($true) {
  Do-Tick $cfg
  if ($cfg.heartbeatMins -gt 0 -and ((Get-Date) - $lastHeartbeat).TotalMinutes -ge $cfg.heartbeatMins) {
    $lastHeartbeat = Get-Date
    $msg = "Watcher alive - $($script:lastOnline) player(s) online"
    if ($script:lastCtx) { $msg += "  -  $($script:lastCtx)" }
    Write-Log "HEARTBEAT $msg"
    [void](Send-Ntfy $cfg "$($cfg.serverName) - heartbeat" $msg 'min' @('green_heart'))
  }
  Start-Sleep -Milliseconds $cfg.pollMs
}
