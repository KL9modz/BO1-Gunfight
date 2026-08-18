# ntfy push - the single sender shared by every box service that alerts a phone
# (GF-JoinNotify, GF-SecurityWatch, ...). Dot-source it, like tools\ignore_list.ps1.
#
# Sent as ntfy's JSON publish format: the topic travels in the BODY and the server URL is the
# bare root, so title/message/tags are all fields of one UTF-8 JSON document.
#
# This is deliberately NOT the X-Title/Priority/Tags HEADER form: HTTP header values are ASCII,
# and titles here carry emoji (a flag is a 4-byte code point built from a surrogate pair) - a
# header cannot survive that. With JSON every field is unicode-safe. Do NOT move a title back
# into a header.
#
# `priority` is a NUMBER in JSON (the header form accepted the names). Callers pass the names
# and this maps them, so an unknown name degrades to normal rather than throwing.
#
# ⚠ tools\vps_services\watchdog.ps1 still carries its OWN older header-form sender (Send-Alert).
# It works and predates this file; fold it in here when convenient rather than growing a third
# copy.

$script:GfNtfyPriority = @{ min = 1; low = 2; default = 3; high = 4; max = 5 }

# Why a send failed, for the caller to log. Send-GfNtfy returns only $true/$false so a failed
# alert can never take a service down - but a silent false is undiagnosable, so the reason is
# parked here rather than thrown.
$script:GfNtfyLastError = ''

# Reads the shared notify config (tools\notify\config.json) - the transports every service
# pushes to. Returns $null when it's absent or configures NO transport at all, which every
# caller must treat as "cannot alert", never as fatal.
# ⚠ The gate is "any transport", NOT "has an ntfyTopic". It used to be the latter, which would
# have made a Discord-ONLY box return $null here and silently never alert - the config would
# look fine and nothing would ever arrive. Adding a transport must never be able to do that
# again: gate on the union.
function Get-GfNtfyConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    try {
        $j = Get-Content $Path -Raw | ConvertFrom-Json
        $server = 'https://ntfy.sh'
        if ($j.ntfyServer) { $server = ([string]$j.ntfyServer).TrimEnd('/') }
        $cfg = [pscustomobject]@{
            ntfyTopic       = [string]$j.ntfyTopic
            ntfyServer      = $server
            ntfyToken       = [string]$j.ntfyToken
            serverName      = $(if ($j.serverName) { [string]$j.serverName } else { 'Gunfight' })
            discordWebhooks = $j.discordWebhooks
        }
        $hasNtfy = -not [string]::IsNullOrWhiteSpace($cfg.ntfyTopic)
        # ⚠ ANY channel counts, not just 'default'. Checking only the default would return $null
        # for a config that set nothing but "alerts" - a live, valid setup reported as no-transport.
        $hasDiscord = $false
        if ($null -ne $cfg.discordWebhooks) {
            foreach ($p in $cfg.discordWebhooks.PSObject.Properties) {
                if (-not [string]::IsNullOrWhiteSpace($p.Value)) { $hasDiscord = $true; break }
            }
        }
        if (-not ($hasNtfy -or $hasDiscord)) { return $null }
        return $cfg
    }
    catch { return $null }
}

# $cfg needs .ntfyTopic / .ntfyServer / .ntfyToken - either Get-GfNtfyConfig's object or any
# object carrying those. $tags is an array of emoji shortcodes; ntfy renders them immediately
# BEFORE the title, so a tag reads as a badge on the alert.
function Send-GfNtfy {
    param($Config, [string]$Title, [string]$Message, [string]$Priority = 'default', [string[]]$Tags = @())

    $script:GfNtfyLastError = ''
    if ($null -eq $Config -or -not $Config.ntfyTopic) {
        $script:GfNtfyLastError = 'no topic configured'
        return $false
    }
    $prio = 3
    if ($script:GfNtfyPriority.ContainsKey($Priority)) { $prio = $script:GfNtfyPriority[$Priority] }
    # [string[]] forces a JSON array even for a single tag (ConvertTo-Json unwraps a lone element).
    $payload = [ordered]@{
        topic    = [string]$Config.ntfyTopic
        title    = $Title
        message  = $Message
        priority = $prio
        tags     = [string[]]@($Tags)
    }
    $headers = @{}
    if ($Config.ntfyToken) { $headers['Authorization'] = "Bearer $($Config.ntfyToken)" }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Compress -Depth 4))
        Invoke-RestMethod -Uri $Config.ntfyServer -Method Post -Body $bytes -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
        return $true
    }
    catch {
        $script:GfNtfyLastError = $_.Exception.Message
        return $false
    }
}

# ---- Discord ----------------------------------------------------------------------------
# Transport #2. WEBHOOKS, deliberately not a bot: a webhook is one HTTPS POST to a per-channel
# URL - no gateway connection to hold open, no bot process to supervise, no token refresh, and
# no privileged intents. It is one-way (post only), which is exactly what an alert feed is. A
# bot only becomes necessary for READING Discord (slash commands, live presence, roles).
#
# ⚠ The webhook URL IS the credential - anyone holding it can post to that channel as the
# server. It lives in the gitignored tools\notify\config.json alongside the ntfy topic, and the
# pre-commit hook blocks a discord.com/api/webhooks literal the same way it blocks passwords.
#
# ⚠⚠ allowed_mentions is pinned to parse:[] and NEVER relaxed. Alert bodies carry PLAYER NAMES,
# and a player can rename themselves "@everyone" - without this, a join alert would ping the
# whole Discord. Same class of injection as the rcon-command sanitising in gf_bridgeAdminSay.
# Blocking it at the API layer beats escaping, because it also covers @here and role IDs.

# ntfy tag shortcodes -> real unicode. Discord renders :shortcode: in MESSAGE content but not
# reliably inside an embed, so the badge is converted rather than passed through. Unknown tags
# are dropped (never rendered as literal ":foo:").
$script:GfDiscordEmoji = @{
    rotating_light         = [char]::ConvertFromUtf32(0x1F6A8)
    robot                  = [char]::ConvertFromUtf32(0x1F916)
    white_check_mark       = [char]::ConvertFromUtf32(0x2705)
    information_source     = [char]::ConvertFromUtf32(0x2139)
    arrows_counterclockwise = [char]::ConvertFromUtf32(0x1F504)
    warning                = [char]::ConvertFromUtf32(0x26A0)
}

# Embed stripe colour by priority. Recovery is special-cased by the caller's tag, because
# "server is back" arrives at default priority and should read green, not grey.
$script:GfDiscordColor = @{ min = 0x95A5A6; low = 0x95A5A6; default = 0x5865F2; high = 0xE67E22; urgent = 0xED4245; max = 0xED4245 }

$script:GfDiscordLastError = ''

# Pick the webhook for a category, falling back to 'default'. Returns '' when nothing matches -
# which is the normal state for a box that has not configured Discord at all.
function Get-GfDiscordWebhook {
    param($Config, [string]$Category = 'default')
    if ($null -eq $Config -or $null -eq $Config.discordWebhooks) { return '' }
    $map = $Config.discordWebhooks
    foreach ($key in @($Category, 'default')) {
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $v = $null
        # PSCustomObject (from ConvertFrom-Json) and Hashtable are both plausible here.
        if ($map -is [System.Collections.IDictionary]) { if ($map.Contains($key)) { $v = $map[$key] } }
        elseif ($map.PSObject.Properties.Name -contains $key) { $v = $map.$key }
        if (-not [string]::IsNullOrWhiteSpace($v)) { return [string]$v }
    }
    return ''
}

# One webhook POST. Returns $true/$false and never throws - an alert transport that can take a
# service down is worse than no alert. $Category selects the channel (joins / alerts / security).
function Send-GfDiscord {
    param($Config, [string]$Title, [string]$Message, [string]$Priority = 'default',
          [string[]]$Tags = @(), [string]$Category = 'default')

    $script:GfDiscordLastError = ''
    $url = Get-GfDiscordWebhook -Config $Config -Category $Category
    if ([string]::IsNullOrWhiteSpace($url)) { $script:GfDiscordLastError = 'no webhook configured'; return $false }

    $badge = ''
    foreach ($t in @($Tags)) { if ($script:GfDiscordEmoji.ContainsKey($t)) { $badge += $script:GfDiscordEmoji[$t] + ' ' } }
    $color = 0x5865F2
    if ($script:GfDiscordColor.ContainsKey($Priority)) { $color = $script:GfDiscordColor[$Priority] }
    # A recovery reads green whatever its priority - it is the one case where the TAG carries the
    # severity and the priority does not (recoveries are sent at 'default' so they do not buzz).
    if (@($Tags) -contains 'white_check_mark') { $color = 0x57F287 }

    $embed = [ordered]@{
        title       = (($badge + $Title).Trim())
        description = [string]$Message
        color       = $color
        footer      = @{ text = $(if ($Config.serverName) { [string]$Config.serverName } else { 'Gunfight' }) }
        timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    $payload = [ordered]@{
        embeds           = @($embed)
        allowed_mentions = @{ parse = @() }   # see the header - never relax this
    }
    # Urgent also goes in `content`: embed text is thin in a mobile push preview, and an urgent
    # alert is exactly the one a phone should be able to read without opening the app.
    if ($Priority -eq 'urgent' -or $Priority -eq 'max') { $payload['content'] = (($badge + $Title).Trim()) }

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Compress -Depth 6))
        Invoke-RestMethod -Uri $url -Method Post -Body $bytes `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
        return $true
    }
    catch {
        # 429 = webhook rate limit (5 req / 2s per webhook). Report it and MOVE ON: a retry loop
        # inside a watchdog tick would stall the very health check that is trying to alert.
        $script:GfDiscordLastError = $_.Exception.Message
        return $false
    }
}

# ---- The fan-out ------------------------------------------------------------------------
# THE entry point every service should call. Sends to every configured transport and reports
# per-transport results, so a box with only ntfy, only Discord, or both all work unchanged.
# ⚠ Independent try/catch per transport: Discord being down must never suppress the ntfy push
# that reaches a phone, and vice versa.
function Send-GfAlert {
    param($Config, [string]$Title, [string]$Message, [string]$Priority = 'default',
          [string[]]$Tags = @(), [string]$Category = 'default')

    $ntfyOk = $false; $ntfyTried = $false
    if ($null -ne $Config -and $Config.ntfyTopic) {
        $ntfyTried = $true
        $ntfyOk = Send-GfNtfy -Config $Config -Title $Title -Message $Message -Priority $Priority -Tags $Tags
    }
    $dscOk = $false; $dscTried = $false
    if (-not [string]::IsNullOrWhiteSpace((Get-GfDiscordWebhook -Config $Config -Category $Category))) {
        $dscTried = $true
        $dscOk = Send-GfDiscord -Config $Config -Title $Title -Message $Message -Priority $Priority -Tags $Tags -Category $Category
    }
    return [pscustomobject]@{
        ntfy        = $ntfyOk
        discord     = $dscOk
        anySent     = ($ntfyOk -or $dscOk)
        # "configured but every configured transport failed" - the only state worth logging loudly.
        allFailed   = (($ntfyTried -or $dscTried) -and -not ($ntfyOk -or $dscOk))
        # Errors only for transports actually ATTEMPTED - the module-scope Last* vars persist
        # across calls, so reporting them unconditionally would resurrect a stale message from
        # an earlier send and log a failure for a transport this box does not even have.
        ntfyError    = $(if ($ntfyTried) { $script:GfNtfyLastError } else { '' })
        discordError = $(if ($dscTried) { $script:GfDiscordLastError } else { '' })
    }
}
