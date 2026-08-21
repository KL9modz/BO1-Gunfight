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
            # ⚠ EVERY key Send-GfDiscord reads must be listed here. This object is a REBUILD, so
            # anything omitted is silently absent at the send site with no error - exactly how
            # discordWebhooks went missing from join-notify's copy and sent joins to ntfy only.
            discordFooter   = $j.discordFooter
            # Optional channel ids for the BOT transport (components). Absent is normal - the id is
            # then derived from the webhook itself, so a working box needs no new config.
            discordChannels = $j.discordChannels
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
    # Player-activity vocabulary. These arrive POSITIONALLY (join-notify passes Count-Tag's
    # return, not a -Tags literal), which is how they went unmapped while the drift guard
    # below reported full coverage: ntfy renders a shortcode natively, so the badge showed on
    # the phone and silently vanished from the Discord embed.
    bust_in_silhouette     = [char]::ConvertFromUtf32(0x1F464)
    busts_in_silhouette    = [char]::ConvertFromUtf32(0x1F465)
    wave                   = [char]::ConvertFromUtf32(0x1F44B)
    # join-notify's own lifecycle set, positional for the same reason and unmapped for the same
    # reason. red/green are its poll-failure EDGE pair, so on Discord those two were the least
    # affordable to lose: down and back-up read identically without the badge.
    red_circle             = [char]::ConvertFromUtf32(0x1F534)
    green_circle           = [char]::ConvertFromUtf32(0x1F7E2)
    green_heart            = [char]::ConvertFromUtf32(0x1F49A)
    satellite_antenna      = [char]::ConvertFromUtf32(0x1F4E1)
    zzz                    = [char]::ConvertFromUtf32(0x1F4A4)
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

# ---- Bot transport (ONLY for messages that need COMPONENTS) ------------------------------
# ⚠ A WEBHOOK CANNOT SEND COMPONENTS. Proven live 2026-08-20: a webhook POST carrying one link
# button returned 200 and echoed `components: []` - accepted and silently dropped, the same shape
# as the presence-button finding. So a card with a real button has to come from the BOT.
#
# ⚠ THIS DOES NOT MOVE THE ALERT FEED ONTO THE BOT. Only a caller that passes -Components takes
# this path. Everything else stays on the webhook, which keeps watchdog/security alerts on their
# existing identity and keeps them working on a box where the bot is not installed at all.
#
# ⚠ The token is READ FROM THE BOT'S OWN CONFIG, never copied into notify\config.json: one copy of
# a credential is one place to rotate, the same rule that keeps rcon_password in dedicated.cfg.
$script:GfBotToken = $null
function Get-GfBotToken {
    if ($null -ne $script:GfBotToken) { return $script:GfBotToken }
    $script:GfBotToken = ''
    # $PSScriptRoot here is tools\ - the bot lives beside this file.
    $p = Join-Path $PSScriptRoot 'discord_bot\config.local.json'
    try {
        if (Test-Path $p) {
            $raw = (Get-Content $p -Raw) -replace "^$([char]0xFEFF)", ''
            $script:GfBotToken = [string](($raw | ConvertFrom-Json).token)
        }
    } catch { $script:GfBotToken = '' }
    return $script:GfBotToken
}

# Which channel a category posts to. Explicit `discordChannels` wins; otherwise it is DERIVED from
# the webhook, since GET /webhooks/{id}/{token} returns channel_id - so this needs no new config on
# a box that already has webhooks working. Cached: the answer cannot change without a restart.
$script:GfBotChannels = @{}
function Get-GfDiscordChannelId {
    param($Config, [string]$Category = 'default')
    $map = $null
    if ($null -ne $Config) { $map = $Config.discordChannels }
    foreach ($key in @($Category, 'default')) {
        if ([string]::IsNullOrWhiteSpace($key) -or $null -eq $map) { continue }
        $v = $null
        if ($map -is [System.Collections.IDictionary]) { if ($map.Contains($key)) { $v = $map[$key] } }
        elseif ($map.PSObject.Properties.Name -contains $key) { $v = $map.$key }
        if (-not [string]::IsNullOrWhiteSpace($v)) { return [string]$v }
    }
    $hook = Get-GfDiscordWebhook -Config $Config -Category $Category
    if ([string]::IsNullOrWhiteSpace($hook)) { return '' }
    if ($script:GfBotChannels.ContainsKey($hook)) { return $script:GfBotChannels[$hook] }
    $id = ''
    try {
        $res = Invoke-RestMethod -Uri $hook -Method Get -TimeoutSec 15
        if ($res -and $res.channel_id) { $id = [string]$res.channel_id }
    } catch { $id = '' }
    $script:GfBotChannels[$hook] = $id
    return $id
}

# One webhook POST. Returns $true/$false and never throws - an alert transport that can take a
# service down is worse than no alert. $Category selects the channel (joins / alerts / security).
# $Color overrides the priority stripe when a caller owns its own colour language (joins are
# always dark green, whatever priority the ntfy push rides at). $Prefix is a DISCORD-ONLY first
# line of the description - it exists so a Discord mention never reaches the ntfy push, where
# <@123…> would render as literal junk on a phone.
function Send-GfDiscord {
    param($Config, [string]$Title, [string]$Message, [string]$Priority = 'default',
          [string[]]$Tags = @(), [string]$Category = 'default', [int]$Color = 0,
          [string]$Prefix = '', $Fields = @(), $Components = @())

    $script:GfDiscordLastError = ''
    # ⚠ DO NOT ADD A PARAMETER NAMED $Url TO THIS FUNCTION. PowerShell variables are
    # case-insensitive, so a $Url parameter and this $url local are ONE variable - a title-link
    # parameter added here on 2026-08-18 silently became the WEBHOOK URL and shipped it as the
    # embed's clickable title, i.e. a credential rendered as a link in the channel. Caught by
    # inspecting the payload, not the call. Same trap as the $color/$Color collision above; if a
    # title link is ever wanted, name the parameter something that cannot collide.
    $url = Get-GfDiscordWebhook -Config $Config -Category $Category
    if ([string]::IsNullOrWhiteSpace($url)) { $script:GfDiscordLastError = 'no webhook configured'; return $false }

    $badge = ''
    foreach ($t in @($Tags)) { if ($script:GfDiscordEmoji.ContainsKey($t)) { $badge += $script:GfDiscordEmoji[$t] + ' ' } }
    # ⚠ NAMED $stripe, NOT $color. PowerShell variables are CASE-INSENSITIVE, so a local $color
    # IS the $Color parameter: the assignment below silently destroyed the caller's override,
    # and the "explicit wins" line then assigned the priority colour to itself. Every join card
    # rendered in its priority stripe while the code read as though it did not. Do not rename
    # this back - a parameter is only as safe as the locals around it are distinct.
    $stripe = 0x5865F2
    if ($script:GfDiscordColor.ContainsKey($Priority)) { $stripe = $script:GfDiscordColor[$Priority] }
    # A recovery reads green whatever its priority - it is the one case where the TAG carries the
    # severity and the priority does not (recoveries are sent at 'default' so they do not buzz).
    if (@($Tags) -contains 'white_check_mark') { $stripe = 0x57F287 }
    # Explicit LAST: a caller that names a colour has said the most about its own alert.
    if ($Color -gt 0) { $stripe = $Color }

    $embed = [ordered]@{
        title       = (($badge + $Title).Trim())
        # ⚠ FIELDS vs DESCRIPTION IS A NOTIFICATION DECISION, not a styling one. Proven on a real
        # device 2026-08-19: a push shows `content` if present, otherwise it flattens the embed
        # TITLE + DESCRIPTION - so anything in the description lands on the lock screen, raw
        # markdown and all. Text moved into FIELDS renders identically in Discord and stays OUT
        # of the push. Hence: one-line summary in the title, detail in fields.
        description = $(if ($Fields -and $Fields.Count) { $null }
                        elseif ($Prefix) { ([string]$Prefix + "`n" + [string]$Message).Trim() }
                        else { [string]$Message })
        fields      = $(if ($Fields -and $Fields.Count) { @($Fields) } else { $null })
        color       = $stripe
        # ⚠ FOOTER TEXT IS RAW - Discord renders no markdown and no links in it, so a footer can
        # never be a hyperlink. It can only SAY 'gunfight.us'; the clickable half is the embed url
        # below, which turns the title into the link. discordFooter overrides serverName so the
        # footer can be branding without renaming the server everywhere else.
        footer      = @{ text = $(if ($Config.discordFooter) { [string]$Config.discordFooter } elseif ($Config.serverName) { [string]$Config.serverName } else { 'Gunfight' }) }
        timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    $payload = [ordered]@{
        embeds           = @($embed)
        allowed_mentions = @{ parse = @() }   # see the header - never relax this
    }
    # Urgent also goes in `content`: embed text is thin in a mobile push preview, and an urgent
    # alert is exactly the one a phone should be able to read without opening the app.
    if ($Priority -eq 'urgent' -or $Priority -eq 'max') { $payload['content'] = (($badge + $Title).Trim()) }

    # ⚠ COMPONENTS FORCE THE BOT TRANSPORT, because a webhook silently drops them (see above).
    # A caller asking for a button gets the bot or gets told why - it must never post a card that
    # LOOKS right and quietly has no button on it.
    if ($Components -and @($Components).Count) {
        $token = Get-GfBotToken
        $chan  = Get-GfDiscordChannelId -Config $Config -Category $Category
        if (-not [string]::IsNullOrWhiteSpace($token) -and -not [string]::IsNullOrWhiteSpace($chan)) {
            $payload['components'] = @($Components)
            try {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Compress -Depth 8))
                Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$chan/messages" -Method Post `
                    -Body $bytes -Headers @{ Authorization = "Bot $token" } `
                    -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
                return $true
            }
            catch {
                # 🛑 NEVER LOSE THE ALERT FOR THE SAKE OF A BUTTON. This used to `return $false`, and
                # on 2026-08-20 a real join (YooDyl, the FIRST player of the session) produced no
                # Discord card at all: the bot lacked Send Messages on that channel, the POST 403'd,
                # and the message was simply abandoned. A missing button is cosmetic; a missing join
                # alert is the feature not working.
                # So a failed bot post degrades to the WEBHOOK without components, exactly like the
                # no-token path above, and the reason is recorded for the caller to log.
                $script:GfDiscordLastError = 'bot post failed (' + $_.Exception.Message + ') - sent via webhook WITHOUT buttons'
                $payload.Remove('components')
            }
        }
        # ⚠ Fall through WITHOUT the components rather than sending them into the void, and say so.
        # A silent buttonless card would look like a Discord bug rather than a missing bot token.
        $payload.Remove('components')
        $script:GfDiscordLastError = 'no bot token/channel - posted via webhook WITHOUT buttons'
    }

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
# $DiscordTitle lets the two transports disagree about the headline. They are different surfaces:
# an ntfy push is a phone notification read in isolation, so it states everything; a Discord card
# sits in a scrolling channel next to its neighbours, where the same words are clutter. Empty =
# both transports use $Title, which is what every other caller wants.
function Send-GfAlert {
    param($Config, [string]$Title, [string]$Message, [string]$Priority = 'default',
          [string[]]$Tags = @(), [string]$Category = 'default', [int]$DiscordColor = 0,
          [string]$DiscordPrefix = '', [string]$DiscordTitle = '',
          [string]$DiscordMessage = '', $DiscordFields = @(), $DiscordComponents = @())

    $ntfyOk = $false; $ntfyTried = $false
    if ($null -ne $Config -and $Config.ntfyTopic) {
        $ntfyTried = $true
        $ntfyOk = Send-GfNtfy -Config $Config -Title $Title -Message $Message -Priority $Priority -Tags $Tags
    }
    $dscOk = $false; $dscTried = $false
    if (-not [string]::IsNullOrWhiteSpace((Get-GfDiscordWebhook -Config $Config -Category $Category))) {
        $dscTried = $true
        $dTitle = $(if ($DiscordTitle) { $DiscordTitle } else { $Title })
        # Same idea for the body: the phone and the channel do not want the same sentence.
        $dMsg   = $(if ($DiscordMessage) { $DiscordMessage } else { $Message })
        $dscOk = Send-GfDiscord -Config $Config -Title $dTitle -Message $dMsg -Priority $Priority -Tags $Tags -Category $Category -Color $DiscordColor -Prefix $DiscordPrefix -Fields $DiscordFields -Components $DiscordComponents
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

# ---- Live-card transport (create once, then edit in place) --------------------------------
# Send-GfDiscord above is fire-and-forget: it posts and forgets the message. A STATUS CARD is
# the opposite - one message that is rewritten forever, so the channel does not fill with a new
# "4 players online" every few minutes. Two extra calls make that possible:
#   New-GfDiscordMessage : POST ?wait=true, which makes Discord RETURN the created message
#                          (without ?wait it answers 204 with no body and the id is lost forever)
#   Set-GfDiscordMessage : PATCH .../messages/<id>, the in-place rewrite
# ⚠ A webhook CANNOT pin (that needs a bot token with MANAGE_MESSAGES) - pin it by hand once.

# Returns the new message id, or '' on failure. $Embed is a hashtable in Discord embed shape.
function New-GfDiscordMessage {
    param($Config, $Embed, [string]$Category = 'default')
    $script:GfDiscordLastError = ''
    # ⚠ DO NOT ADD A PARAMETER NAMED $Url TO THIS FUNCTION. PowerShell variables are
    # case-insensitive, so a $Url parameter and this $url local are ONE variable - a title-link
    # parameter added here on 2026-08-18 silently became the WEBHOOK URL and shipped it as the
    # embed's clickable title, i.e. a credential rendered as a link in the channel. Caught by
    # inspecting the payload, not the call. Same trap as the $color/$Color collision above; if a
    # title link is ever wanted, name the parameter something that cannot collide.
    $url = Get-GfDiscordWebhook -Config $Config -Category $Category
    if ([string]::IsNullOrWhiteSpace($url)) { $script:GfDiscordLastError = 'no webhook configured'; return '' }
    $payload = [ordered]@{ embeds = @($Embed); allowed_mentions = @{ parse = @() } }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Compress -Depth 8))
        # ?wait=true is what turns a 204-no-body into the created message object.
        $sep = $(if ($url.Contains('?')) { '&' } else { '?' })
        $res = Invoke-RestMethod -Uri ($url + $sep + 'wait=true') -Method Post -Body $bytes `
                   -ContentType 'application/json; charset=utf-8' -TimeoutSec 15
        if ($res -and $res.id) { return [string]$res.id }
        $script:GfDiscordLastError = 'no message id in response'
        return ''
    }
    catch { $script:GfDiscordLastError = $_.Exception.Message; return '' }
}

# Rewrites an existing message. Returns $true, or $false with $script:GfDiscordLastError set.
# ⚠ A 404 here is EXPECTED and RECOVERABLE, not an error to alert on: it means the message was
# deleted in Discord (or the webhook was rotated). Callers detect it via -MessageGone and create
# a fresh card rather than going permanently silent.
function Set-GfDiscordMessage {
    param($Config, [string]$MessageId, $Embed, [string]$Category = 'default', [ref]$MessageGone)
    $script:GfDiscordLastError = ''
    if ($MessageGone) { $MessageGone.Value = $false }
    # ⚠ DO NOT ADD A PARAMETER NAMED $Url TO THIS FUNCTION. PowerShell variables are
    # case-insensitive, so a $Url parameter and this $url local are ONE variable - a title-link
    # parameter added here on 2026-08-18 silently became the WEBHOOK URL and shipped it as the
    # embed's clickable title, i.e. a credential rendered as a link in the channel. Caught by
    # inspecting the payload, not the call. Same trap as the $color/$Color collision above; if a
    # title link is ever wanted, name the parameter something that cannot collide.
    $url = Get-GfDiscordWebhook -Config $Config -Category $Category
    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($MessageId)) {
        $script:GfDiscordLastError = 'no webhook or no message id'; return $false
    }
    $payload = [ordered]@{ embeds = @($Embed); allowed_mentions = @{ parse = @() } }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Compress -Depth 8))
        Invoke-RestMethod -Uri ($url + '/messages/' + $MessageId) -Method Patch -Body $bytes `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
        return $true
    }
    catch {
        $script:GfDiscordLastError = $_.Exception.Message
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if ($code -eq 404 -and $MessageGone) { $MessageGone.Value = $true }
        return $false
    }
}
