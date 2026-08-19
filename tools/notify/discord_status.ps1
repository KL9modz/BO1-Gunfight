# discord_status.ps1 - ONE self-updating Discord message showing live server status.
# ------------------------------------------------------------------------------
# Posts a status card once, then EDITS that same message forever, so the channel gets a live
# card instead of a new "4 players online" post every few minutes. Run on a timer
# (GF-DiscordStatus, see vps_services\register_services.ps1).
#
# ZERO RCON: it reads only files the box already writes - status.json (status_service, every
# 5s) and health.json (same, for uptime + lobby state). Same pattern as conn_logger reading
# admin.json: the RCON panel stays the single rcon pacer ([[rcon-panel-queue-saturation]]).
#
# COSMETIC BY DESIGN. Every failure path logs and exits 0, and GF-DiscordStatus is deliberately
# NOT in the watchdog $PeriodicTasks list - a stale status card is not an incident and must
# never page anyone.
#
# A webhook CANNOT pin (that needs a bot token with MANAGE_MESSAGES). Pin the card by hand once
# in Discord; the message id is remembered, so it keeps editing that same pinned message.
#
# Default category is 'default' = the PRIVATE channel. The card lists human player NAMES, which
# is fine there. Pointing it at a public channel is a privacy decision - see the _discordPrivacy
# note in config.example.json.
#
#   powershell -ExecutionPolicy Bypass -File discord_status.ps1
#   powershell -ExecutionPolicy Bypass -File discord_status.ps1 -WhatIf   # render, send nothing
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string] $ConfigPath = '',
    [string] $StatusJson = 'C:\inetpub\wwwroot\live\status.json',
    [string] $HealthJson = 'C:\inetpub\wwwroot\admin\live\health.json',
    [string] $StatePath  = '',
    [string] $Category   = 'default',
    # Beyond this, status.json is treated as STALE and the card says so rather than showing a
    # confident but frozen snapshot. status_service writes every 5s, so 120s is several missed
    # polls, not a blip.
    [int]    $StaleSecs  = 120,
    [switch] $WhatIf
)

$ErrorActionPreference = 'Continue'   # cosmetic service: nothing here may become fatal

. (Join-Path $PSScriptRoot '..\ntfy.ps1')
. (Join-Path $PSScriptRoot '..\map_names.ps1')
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
if (-not $StatePath)  { $StatePath  = Join-Path $PSScriptRoot 'discord_status.local.json' }

function Log($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }

# One tolerant read - never Test-Path-then-read. status_service REPLACES these files while we
# are looking at them ([[watchdog-toctou-on-atomically-replaced-json]]).
function Read-Json($path) {
    try { return ((Get-Content -LiteralPath $path -Raw -ErrorAction Stop) | ConvertFrom-Json) }
    catch { return $null }
}

# Pure: data in, embed hashtable out. No network, so the rendering is unit-testable.
function New-StatusEmbed($st, $he, $serverName, $staleSecs) {
    $now   = Get-Date
    $stamp = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $green = 0x57F287; $red = 0xED4245; $grey = 0x95A5A6
    $dotOn = [char]::ConvertFromUtf32(0x1F7E2)   # green circle
    $dotNo = [char]::ConvertFromUtf32(0x1F534)   # red circle
    $dotNa = [char]::ConvertFromUtf32(0x26AA)    # white circle

    if ($null -eq $st) {
        return @{ title = "$dotNa $serverName - status unknown"
                  description = 'No status snapshot on disk yet.'
                  color = $grey; timestamp = $stamp }
    }

    $age = $null
    if ($st.updated) {
        try { $age = [int]((New-TimeSpan -Start ([datetime]$st.updated) -End $now).TotalSeconds) } catch { }
    }
    # An unreadable timestamp counts as stale: better a card that admits it does not know than
    # one that confidently shows a frozen roster.
    $stale  = ($null -eq $age -or $age -gt $staleSecs)
    $online = [bool]$st.online
    $mapName = 'unknown'
    if ($st.mapName)  { $mapName = [string]$st.mapName }
    elseif ($st.map)  { $mapName = Get-GfMapName ([string]$st.map) }

    if (-not $online)  { $title = "$dotNo $serverName - OFFLINE";      $color = $red }
    elseif ($stale)    { $title = "$dotNa $serverName - status stale"; $color = $grey }
    else               { $title = "$dotOn $serverName - $mapName";     $color = $green }

    $humans = [int]$st.humans
    $bots   = [int]$st.bots
    $who = "$humans human"
    if ($humans -ne 1) { $who += 's' }
    if ($bots -gt 0) {
        $who += " + $bots bot"
        if ($bots -ne 1) { $who += 's' }
    }

    $fields = @()
    $fields += @{ name = 'Players'; value = $who; inline = $true }
    if ($st.round) { $fields += @{ name = 'Round'; value = [string]$st.round; inline = $true } }
    if ($st.score) {
        $fields += @{ name  = 'Score'
                      value = ('Allies {0} - {1} Axis' -f [int]$st.score.allies, [int]$st.score.axis)
                      inline = $true }
    }
    # Human names only, and only when there are any. status.json lists humans, not bots.
    $names = @()
    foreach ($p in @($st.players)) { if ($p -and $p.name) { $names += [string]$p.name } }
    if ($names.Count -gt 0) {
        $joined = ($names -join ', ')
        # Discord caps an embed field value at 1024 chars; 14 players cannot reach it, but a
        # hostile 200-char name could, and a rejected payload would silently stop the card.
        if ($joined.Length -gt 1000) { $joined = $joined.Substring(0, 997) + '...' }
        $fields += @{ name = 'Online now'; value = $joined; inline = $false }
    }
    if ($he -and $he.serverUptimeMins) {
        $m = [int]$he.serverUptimeMins
        $fields += @{ name = 'Uptime'; value = ('{0}h {1}m' -f [math]::Floor($m / 60), ($m % 60)); inline = $true }
    }
    if ($he -and $he.lobbyHold) { $fields += @{ name = 'State'; value = 'Pregame lobby'; inline = $true } }

    $desc = ''
    if ($stale -and $online -and $null -ne $age) { $desc = "Last snapshot ${age}s ago - status_service may be stuck." }

    return @{ title = $title; description = $desc; color = $color; fields = $fields
              footer = @{ text = 'gunfight.us - updates automatically' }; timestamp = $stamp }
}

# ---- run --------------------------------------------------------------------------------
$cfg = Get-GfNtfyConfig -Path $ConfigPath
if ($null -eq $cfg) { Log 'no notify config - nothing to do'; exit 0 }
if ([string]::IsNullOrWhiteSpace((Get-GfDiscordWebhook -Config $cfg -Category $Category))) {
    Log "no Discord webhook for category '$Category' - nothing to do"; exit 0
}

$embed = New-StatusEmbed (Read-Json $StatusJson) (Read-Json $HealthJson) $cfg.serverName $StaleSecs

if ($WhatIf) {
    Log 'WhatIf - the card that WOULD be sent:'
    ($embed | ConvertTo-Json -Depth 8)
    exit 0
}

$state = Read-Json $StatePath
$msgId = ''
if ($state -and $state.messageId) { $msgId = [string]$state.messageId }

$gone = $false
$done = $false
if ($msgId) {
    $done = Set-GfDiscordMessage -Config $cfg -MessageId $msgId -Embed $embed -Category $Category -MessageGone ([ref]$gone)
    if ($done)     { Log "card updated (message $msgId)" }
    elseif ($gone) { Log "card $msgId is gone from Discord (deleted, or webhook rotated) - creating a new one" }
    else           { Log "card update FAILED: $script:GfDiscordLastError" }
}
# Create only when there is no id at all, or the old message PROVABLY no longer exists (404).
# Never on a generic failure - a transient 500 must not spam a fresh card on every run.
if (-not $done -and (-not $msgId -or $gone)) {
    $newId = New-GfDiscordMessage -Config $cfg -Embed $embed -Category $Category
    if ($newId) {
        try {
            (@{ messageId = $newId; category = $Category; created = (Get-Date).ToString('o') } |
                ConvertTo-Json) | Set-Content -LiteralPath $StatePath -Encoding UTF8
            Log "created card $newId - PIN IT ONCE in Discord (a webhook cannot pin)"
        }
        catch {
            Log "created card $newId but FAILED to save state ($($_.Exception.Message)) - it will be recreated next run"
        }
    }
    else { Log "card create FAILED: $script:GfDiscordLastError" }
}
exit 0
