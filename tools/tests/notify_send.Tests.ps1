# Pester net for tools\ntfy.ps1 - the shared alert sender (ntfy + Discord fan-out).
#
# Unlike the service scripts, this file is a LIBRARY: dot-sourcing it only defines functions,
# so no AST extraction is needed (contrast service_functions.Tests.ps1).
#
# Nothing here touches the network. The transports are covered by shape/routing logic; the
# actual POSTs were verified 2026-08-18 against a local HttpListener standing in for
# discord.com (urgent, recovery, hostile-name and unknown-category cases).
#
# ⚠ Assertions are plain `if (...) { throw }` - Pester 3.4/5.x compatible (see guards.Tests.ps1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $here
. (Join-Path $toolsRoot 'ntfy.ps1')

function Assert-True($cond, $msg)  { if (-not $cond) { throw "ASSERT: $msg" } }
function Assert-Eq($actual, $expected, $msg) {
    if ("$actual" -ne "$expected") { throw "ASSERT: $msg -- expected [$expected], got [$actual]" }
}
function New-TempConfig($obj) {
    $p = Join-Path $env:TEMP ("gf_notifycfg_" + [IO.Path]::GetRandomFileName() + ".json")
    ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $p -Encoding UTF8
    return $p
}

Describe "Get-GfDiscordWebhook - channel routing" {
    $cfg = [pscustomobject]@{ discordWebhooks = [pscustomobject]@{
        default = 'https://d/default'; joins = 'https://d/joins'; alerts = '' } }

    It "an exact category wins" {
        Assert-Eq (Get-GfDiscordWebhook -Config $cfg -Category 'joins') 'https://d/joins' "joins"
    }
    It "an UNSET category falls back to default (alerts is blank here)" {
        Assert-Eq (Get-GfDiscordWebhook -Config $cfg -Category 'alerts') 'https://d/default' "blank -> default"
    }
    It "an unknown category falls back to default" {
        Assert-Eq (Get-GfDiscordWebhook -Config $cfg -Category 'nope') 'https://d/default' "unknown -> default"
    }
    It "no discord config at all yields empty, never a throw" {
        Assert-Eq (Get-GfDiscordWebhook -Config ([pscustomobject]@{}) -Category 'joins') '' "absent"
        Assert-Eq (Get-GfDiscordWebhook -Config $null -Category 'joins') '' "null config"
    }
    It "a Hashtable map works too (not just ConvertFrom-Json's PSCustomObject)" {
        $h = [pscustomobject]@{ discordWebhooks = @{ default = 'https://h/def' } }
        Assert-Eq (Get-GfDiscordWebhook -Config $h -Category 'x') 'https://h/def' "hashtable"
    }
    It "with ONLY a non-default category set, that category still resolves" {
        $only = [pscustomobject]@{ discordWebhooks = [pscustomobject]@{ security = 'https://d/sec' } }
        Assert-Eq (Get-GfDiscordWebhook -Config $only -Category 'security') 'https://d/sec' "security only"
        Assert-Eq (Get-GfDiscordWebhook -Config $only -Category 'joins') '' "no default to fall back to"
    }
}

Describe "Get-GfNtfyConfig - the transport gate" {
    It "ntfy-only config loads" {
        $p = New-TempConfig @{ ntfyTopic = 'abc' }
        $c = Get-GfNtfyConfig -Path $p; Remove-Item $p -Force
        Assert-True ($null -ne $c) "loaded"
        Assert-Eq $c.ntfyTopic 'abc' "topic"
    }
    It "DISCORD-ONLY config loads (the regression: this used to return null and alert nothing)" {
        $p = New-TempConfig @{ discordWebhooks = @{ default = 'https://d/x' } }
        $c = Get-GfNtfyConfig -Path $p; Remove-Item $p -Force
        Assert-True ($null -ne $c) "a box with only Discord MUST still get a config object"
    }
    It "discord-only via a NON-default category also counts as configured" {
        $p = New-TempConfig @{ discordWebhooks = @{ alerts = 'https://d/a' } }
        $c = Get-GfNtfyConfig -Path $p; Remove-Item $p -Force
        Assert-True ($null -ne $c) "only 'alerts' set is still a live transport"
    }
    It "NO transport configured yields null (callers treat that as cannot-alert)" {
        $p = New-TempConfig @{ serverName = 'Gunfight'; discordWebhooks = @{ default = '' } }
        $c = Get-GfNtfyConfig -Path $p; Remove-Item $p -Force
        Assert-True ($null -eq $c) "no transports = null"
    }
    It "a missing file yields null, never a throw" {
        Assert-True ($null -eq (Get-GfNtfyConfig -Path (Join-Path $env:TEMP 'gf_no_such_cfg.json'))) "missing"
    }
}

Describe "Send-GfAlert - result shape" {
    It "reports nothing sent, and no STALE error, when no transport is configured" {
        $r = Send-GfAlert -Config ([pscustomobject]@{}) -Title 't' -Message 'm'
        Assert-Eq $r.anySent $false "nothing sent"
        Assert-Eq $r.allFailed $false "not 'failed' - it was never attempted"
        Assert-Eq $r.ntfyError '' "must not resurrect a Last* error from an earlier call"
        Assert-Eq $r.discordError '' "same for discord"
    }
}

Describe "Discord badge/colour maps cover the vocabulary actually in use" {
    # DRIFT GUARD: every ntfy tag any service passes must have a Discord emoji, or that alert
    # silently loses its badge. Scans the real call sites rather than a hand-copied list.
    It "every -Tags value used in tools\ has an emoji mapping" {
        $files = Get-ChildItem $toolsRoot -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch [regex]::Escape([IO.Path]::DirectorySeparatorChar + "tests" + [IO.Path]::DirectorySeparatorChar) }
        $tags = @()
        foreach ($f in $files) {
            foreach ($m in [regex]::Matches((Get-Content $f.FullName -Raw), "(?i)-tags\s+'([^']+)'")) {
                $tags += ($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() })
            }
        }
        $tags = @($tags | Where-Object { $_ -and $_ -notmatch '^\$' } | Sort-Object -Unique)
        Assert-True ($tags.Count -ge 5) "sanity: expected to find several tags, found $($tags.Count)"
        $missing = @($tags | Where-Object { -not $script:GfDiscordEmoji.ContainsKey($_) })
        Assert-Eq ($missing -join ',') '' "tags with no Discord emoji mapping"
    }
    # The -Tags scan above only sees a LITERAL named argument, which is why it reported full
    # coverage while every join alert was losing its badge: join-notify passes tags POSITIONALLY,
    # and by variable (Count-Tag's return). Two more collectors close that:
    #   * string literals inside an @(...) argument of a send call - catches @('wave')
    #   * string literals RETURNED by a *-Tag helper - catches the join 👤/👥 pair
    # Restricted to the send commands and to tag helpers on purpose: a blanket scan for string
    # arrays would flag every unrelated @('allies','axis') in the tree as an unmapped tag.
    It 'tags passed positionally or via a *-Tag helper are covered too' {
        $sendCmds = @('send-ntfy','send-gfalert','send-gfdiscord','send-gfntfy')
        $files = Get-ChildItem $toolsRoot -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch [regex]::Escape([IO.Path]::DirectorySeparatorChar + "tests" + [IO.Path]::DirectorySeparatorChar) }
        $found = @()
        foreach ($f in $files) {
            $fAst = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            if (-not $fAst) { continue }

            foreach ($c in $fAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $name = ''
                if ($c.CommandElements.Count -gt 0) { $name = [string]$c.CommandElements[0].Extent.Text }
                if ($sendCmds -notcontains $name.ToLower()) { continue }
                foreach ($arr in $c.FindAll({ param($n) $n -is [System.Management.Automation.Language.ArrayExpressionAst] }, $true)) {
                    foreach ($s in $arr.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
                        $found += $s.Value
                    }
                }
            }

            foreach ($fn in $fAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                if ($fn.Name -notmatch '-Tags?$') { continue }
                foreach ($s in $fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
                    $found += $s.Value
                }
            }
        }
        $found = @($found | Where-Object { $_ -and $_ -match '^[a-z0-9_]+$' } | Sort-Object -Unique)
        Assert-True ($found.Count -ge 3) "sanity: expected to find the positional tags, found $($found.Count)"
        # The incident itself, pinned: these three were live and unmapped.
        foreach ($t in @('bust_in_silhouette','busts_in_silhouette','wave')) {
            Assert-True ($found -contains $t) "collector no longer sees '$t' - the positional/helper scan stopped working"
        }
        $missing = @($found | Where-Object { -not $script:GfDiscordEmoji.ContainsKey($_) })
        Assert-Eq ($missing -join ',') '' "tags with no Discord emoji mapping (positional/helper call sites)"
    }
    It "every priority the senders accept has a colour" {
        foreach ($p in @('min','low','default','high','urgent','max')) {
            Assert-True ($script:GfDiscordColor.ContainsKey($p)) "colour for priority '$p'"
        }
    }
}

Describe "New-StatusEmbed (discord_status) - the live card rendering" {
    # Pure function (data in, embed out), extracted by AST because discord_status.ps1 is a
    # RUNNABLE script - dot-sourcing it would post to Discord.
    $sp = Join-Path $toolsRoot 'notify\discord_status.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sp, [ref]$null, [ref]$null)
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-StatusEmbed' }, $true) | Select-Object -First 1
    if (-not $fn) { throw "New-StatusEmbed not found in $sp - renamed?" }
    . ([scriptblock]::Create($fn.Extent.Text))
    function Get-GfMapName($m) { return $m }   # stub: the real one lives in map_names.ps1

    $fresh = (Get-Date).ToString('o')
    $green = 0x57F287; $red = 0xED4245; $grey = 0x95A5A6

    It "online + fresh renders green with map, players and score" {
        $st = [pscustomobject]@{ updated=$fresh; online=$true; mapName='Drive-In'; humans=2; bots=4
                                 round=3; score=[pscustomobject]@{allies=2;axis=1} }
        $e = New-StatusEmbed $st $null 'Gunfight' 120
        Assert-Eq $e.color $green "green when live"
        Assert-True ($e.title -match 'Drive-In') "map in title"
        Assert-True ((@($e.fields) | Where-Object { $_.name -eq 'Players' }).value -eq '2 humans + 4 bots') "player line"
        Assert-True ((@($e.fields) | Where-Object { $_.name -eq 'Score' }).value -match 'Allies 2 - 1 Axis') "score line"
    }
    It "offline renders RED even if the snapshot is fresh" {
        $st = [pscustomobject]@{ updated=$fresh; online=$false; mapName='Drive-In'; humans=0; bots=0 }
        $e = New-StatusEmbed $st $null 'Gunfight' 120
        Assert-Eq $e.color $red "red when offline"
        Assert-True ($e.title -match 'OFFLINE') "says offline"
    }
    It "a STALE snapshot is grey and says so - never a confident frozen roster" {
        $st = [pscustomobject]@{ updated=((Get-Date).AddMinutes(-30).ToString('o')); online=$true; mapName='X'; humans=9; bots=0 }
        $e = New-StatusEmbed $st $null 'Gunfight' 120
        Assert-Eq $e.color $grey "grey when stale"
        Assert-True ($e.description -match 'stuck|snapshot') "explains the staleness"
    }
    It "an UNREADABLE timestamp counts as stale, not as fresh" {
        $st = [pscustomobject]@{ updated='not-a-date'; online=$true; mapName='X'; humans=1; bots=0 }
        $e = New-StatusEmbed $st $null 'Gunfight' 120
        Assert-Eq $e.color $grey "unparseable date must not read as live"
    }
    It "no snapshot at all degrades to 'status unknown', never a throw" {
        $e = New-StatusEmbed $null $null 'Gunfight' 120
        Assert-Eq $e.color $grey "grey"
        Assert-True ($e.title -match 'unknown') "says unknown"
    }
    It "singular/plural reads correctly for one human and one bot" {
        $st = [pscustomobject]@{ updated=$fresh; online=$true; mapName='X'; humans=1; bots=1 }
        $e = New-StatusEmbed $st $null 'Gunfight' 120
        Assert-Eq ((@($e.fields) | Where-Object { $_.name -eq 'Players' }).value) '1 human + 1 bot' "no stray plurals"
    }
    It "a hostile long name cannot exceed Discord's 1024-char field cap" {
        $long = [pscustomobject]@{ name = ('N' * 400) }
        $st = [pscustomobject]@{ updated=$fresh; online=$true; mapName='X'; humans=3; bots=0
                                 players=@($long,$long,$long) }
        $e = New-StatusEmbed $st $null 'Gunfight' 120
        $v = (@($e.fields) | Where-Object { $_.name -eq 'Online now' }).value
        Assert-True ($v.Length -le 1024) "field value must stay under the API cap, got $($v.Length)"
    }
    It "uptime and lobby state come from health.json when present" {
        $st = [pscustomobject]@{ updated=$fresh; online=$true; mapName='X'; humans=0; bots=2 }
        $he = [pscustomobject]@{ serverUptimeMins = 751; lobbyHold = $true }
        $e = New-StatusEmbed $st $he 'Gunfight' 120
        Assert-Eq ((@($e.fields) | Where-Object { $_.name -eq 'Uptime' }).value) '12h 31m' "uptime formatted"
        Assert-True ((@($e.fields) | Where-Object { $_.name -eq 'State' }).value -eq 'Pregame lobby') "lobby state"
    }
}

Describe "join-notify config build - every transport survives the rebuild" {
    # join-notify.ps1 does NOT use Get-GfNtfyConfig: it builds its own $cfg so each field can be
    # overridden by an env var. That hand-rolled literal is the failure mode this guards - it
    # shipped once WITHOUT discordWebhooks, and the result was invisible: Send-GfAlert resolves no
    # webhook, skips Discord, reports no error (an unset webhook is a legitimate config), so joins
    # pushed to ntfy and never reached the channel. Nothing failed loudly enough to notice.
    #
    # AST, not a text grep: the point is that the KEY is in the object literal assigned to $cfg,
    # which survives reformatting and comment churn.
    $jn = Join-Path $toolsRoot 'notify\join-notify.ps1'

    It "join-notify.ps1 exists where the test expects it" {
        Assert-True (Test-Path $jn) "not found: $jn"
    }

    It 'the $cfg literal carries discordWebhooks' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($jn, [ref]$null, [ref]$null)
        $assign = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$cfg' -and
            $n.Right.Extent.Text -like '*pscustomobject*'
        }, $true) | Select-Object -First 1
        Assert-True ($null -ne $assign) "no `$cfg = [pscustomobject]@{...} assignment found - renamed?"

        $keys = @($assign.Right.FindAll({
            param($n) $n -is [System.Management.Automation.Language.HashtableAst]
        }, $true) | ForEach-Object { $_.KeyValuePairs } | ForEach-Object { $_.Item1.Extent.Text })

        Assert-True ($keys -contains 'discordWebhooks') `
            "the config object drops discordWebhooks - every alert from this service degrades to ntfy-only, silently. Keys: $($keys -join ', ')"
        Assert-True ($keys -contains 'ntfyTopic') "the config object drops ntfyTopic"
        Assert-True ($keys -contains 'discordFooter') "the config object drops discordFooter - the footer silently falls back to serverName"
    }
}

Describe "Send-GfDiscord - the embed colour actually SENT (payload, not intent)" {
    # THE INCIDENT: -DiscordColor was plumbed correctly end to end and still did nothing, because
    # Send-GfDiscord used a local $color alongside its $Color parameter - and PowerShell variables
    # are CASE-INSENSITIVE, so those are one variable. The first assignment destroyed the caller's
    # value and "explicit wins" then assigned the priority colour to itself. Every join card
    # rendered in its priority stripe while every layer of code read as though it did not.
    #
    # No amount of testing the CALL would have caught that - only the PAYLOAD. So this shadows the
    # HTTP call and inspects the JSON that would have gone to Discord.
    $sent = $null
    function Invoke-RestMethod { param($Uri, $Method, $Body, $ContentType, $TimeoutSec)
        $script:sentBody = [System.Text.Encoding]::UTF8.GetString($Body); return $null }
    $cfg = [pscustomobject]@{ serverName = 'Gunfight'; ntfyTopic = ''
                              discordWebhooks = [pscustomobject]@{ default = 'https://d/def' } }
    function Get-SentEmbed {
        param($Priority = 'default', $Tags = @(), $Color = 0)
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Priority $Priority -Tags $Tags -Color $Color
        if (-not $script:sentBody) { throw 'nothing was sent - the shadowed Invoke-RestMethod never fired' }
        return ($script:sentBody | ConvertFrom-Json).embeds[0]
    }

    It 'an explicit -Color beats the priority stripe (the regression)' {
        Assert-Eq (Get-SentEmbed -Priority 'high'    -Color 0xE67E22).color 0xE67E22 'high + override'
        Assert-Eq (Get-SentEmbed -Priority 'default' -Color 0xE67E22).color 0xE67E22 'default + override'
        Assert-Eq (Get-SentEmbed -Priority 'urgent'  -Color 0x1F8B4C).color 0x1F8B4C 'urgent + override'
    }
    It 'without an override the priority stripe still decides' {
        Assert-Eq (Get-SentEmbed -Priority 'urgent').color  0xED4245 'urgent stays red'
        Assert-Eq (Get-SentEmbed -Priority 'default').color 0x5865F2 'default stays blurple'
        Assert-Eq (Get-SentEmbed -Priority 'low').color     0x95A5A6 'low stays grey'
    }
    It 'a recovery reads green on its tag, and an override still beats even that' {
        Assert-Eq (Get-SentEmbed -Priority 'default' -Tags @('white_check_mark')).color 0x57F287 'recovery green'
        Assert-Eq (Get-SentEmbed -Priority 'default' -Tags @('white_check_mark') -Color 0xE67E22).color 0xE67E22 'override wins'
    }
    It 'the badge and title are what actually ship' {
        $e = Get-SentEmbed -Tags @('bust_in_silhouette')
        Assert-True ($e.title -like "*t") 'title present'
        Assert-True ($e.title.Length -gt 1) 'badge prefixed'
    }
}

Describe "Send-GfDiscord - the webhook URL must never appear in the payload" {
    # THE NEAR MISS: a -Url parameter was added to carry a title link, and PowerShell's
    # case-insensitive variables made it the same variable as the function's $url local - which
    # holds the WEBHOOK. The embed therefore shipped url = <the webhook>, rendering a credential as
    # the card's clickable title in the channel. Nothing was sent to a real channel (no joins
    # occurred in the window), and the parameter is gone rather than renamed.
    #
    # This guard is about the CLASS, not that parameter: the webhook is in scope throughout this
    # function, so any future field that interpolates a variable can leak it the same way. Assert
    # on the bytes that would go out.
    $sent = $null
    function Invoke-RestMethod { param($Uri, $Method, $Body, $ContentType, $TimeoutSec)
        $script:sentBody = [System.Text.Encoding]::UTF8.GetString($Body); return $null }
    $secret = 'https://discord.example/api/webhooks/12345/SUPER-SECRET-TOKEN'
    $cfg = [pscustomobject]@{ serverName = 'Gunfight'; discordFooter = 'gunfight.us'
                              discordWebhooks = [pscustomobject]@{ default = $secret } }

    It 'no field of the embed carries the webhook' {
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 'someone joined Villa' -Message 'body line' `
                -Priority 'high' -Tags @('bust_in_silhouette') -Color 0xE67E22 -Prefix '<@1>'
        Assert-True ($null -ne $script:sentBody) 'nothing was sent'
        Assert-True (-not ($script:sentBody -like '*SUPER-SECRET-TOKEN*')) `
            'the webhook URL appears in the JSON body that would go to Discord'
    }
    It 'the live-card senders do not leak it either' {
        $script:sentBody = $null
        $null = New-GfDiscordMessage -Config $cfg -Embed @{ title = 't'; description = 'd' }
        if ($script:sentBody) {
            Assert-True (-not ($script:sentBody -like '*SUPER-SECRET-TOKEN*')) 'status card body carries the webhook'
        }
    }
}

Describe "Send-GfDiscord - components force the BOT transport" {
    # ⚠ A WEBHOOK CANNOT SEND COMPONENTS. Proven live 2026-08-20: a webhook POST carrying one link
    # button returns 200 and echoes components:[] - accepted and silently dropped. So a card with a
    # button has to be posted by the bot, and the failure mode to guard is a card that looks right
    # and quietly has no button on it.
    $script:sentBody = $null; $script:sentUri = $null; $script:sentHeaders = $null
    function Invoke-RestMethod { param($Uri, $Method, $Body, $ContentType, $TimeoutSec, $Headers)
        $script:sentUri = $Uri; $script:sentHeaders = $Headers
        if ($Body) { $script:sentBody = [System.Text.Encoding]::UTF8.GetString($Body) }
        return $null }

    $btn = ,@( @{ type = 1; components = @( @{ type = 2; style = 5; label = 'Play for free!'; url = 'https://gunfight.us/' } ) } )

    It 'with a channel id it posts as the BOT, and the button survives' {
        $cfg = [pscustomobject]@{ serverName = 'Gunfight'; ntfyTopic = ''
                                  discordWebhooks = [pscustomobject]@{ joins = 'https://d/joins' }
                                  discordChannels = [pscustomobject]@{ joins = '1156243690168266822' } }
        $script:sentBody = $null; $script:sentUri = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Category 'joins' -Components $btn
        Assert-True ($script:sentUri -like '*/channels/1156243690168266822/messages') "posted to $($script:sentUri)"
        Assert-True ($script:sentHeaders -and $script:sentHeaders['Authorization'] -like 'Bot *') 'bot auth header'
        $p = $script:sentBody | ConvertFrom-Json
        Assert-Eq $p.components[0].components[0].label 'Play for free!' 'button label shipped'
        Assert-Eq $p.components[0].components[0].style 5 'link style'
    }

    It 'with NO bot channel it falls back to the webhook and DROPS the components, loudly' {
        # The important half: never post a card that looks right and silently has no button. The
        # reason lands in GfDiscordLastError so join-notify can log it.
        $cfg = [pscustomobject]@{ serverName = 'Gunfight'; ntfyTopic = ''
                                  discordWebhooks = [pscustomobject]@{ joins = 'https://d/joins' } }
        $script:sentBody = $null; $script:sentUri = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Category 'joins' -Components $btn
        Assert-True ($script:sentUri -eq 'https://d/joins') "fell back to the webhook, got $($script:sentUri)"
        $p = $script:sentBody | ConvertFrom-Json
        Assert-True ($null -eq $p.components) 'components must NOT be sent to a webhook - it drops them silently'
        Assert-True ($script:GfDiscordLastError -like '*WITHOUT buttons*') "said why: '$($script:GfDiscordLastError)'"
    }

    It 'a card with no components still goes to the webhook exactly as before' {
        $cfg = [pscustomobject]@{ serverName = 'Gunfight'; ntfyTopic = ''
                                  discordWebhooks = [pscustomobject]@{ default = 'https://d/def' }
                                  discordChannels = [pscustomobject]@{ default = '999' } }
        $script:sentUri = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm'
        Assert-True ($script:sentUri -eq 'https://d/def') 'ordinary alerts keep the webhook identity'
    }
}

Describe "Send-GfDiscord - a failed BOT post must never lose the alert" {
    # 🛑 THE INCIDENT, 2026-08-20: components forced the bot transport, the bot lacked Send Messages
    # on the joins channel, the POST 403'd - and the code returned $false, so a real join (the FIRST
    # player of the session) produced no Discord card at all. A missing button is cosmetic; a missing
    # join alert is the feature not working. A failed bot post must degrade to the webhook.
    $script:calls = @()
    function Invoke-RestMethod { param($Uri, $Method, $Body, $ContentType, $TimeoutSec, $Headers)
        $script:calls += [pscustomobject]@{ uri = $Uri; body = $(if ($Body) { [System.Text.Encoding]::UTF8.GetString($Body) } else { '' }) }
        # Fail ONLY the bot route, exactly like a missing Send Messages permission.
        if ("$Uri" -like '*/channels/*') { throw 'The remote server returned an error: (403) Forbidden.' }
        return $null }

    $btn = ,@( @{ type = 1; components = @( @{ type = 2; style = 5; label = 'Play for free!'; url = 'https://gunfight.us/' } ) } )
    $cfg = [pscustomobject]@{ serverName = 'Gunfight'; ntfyTopic = ''
                              discordWebhooks = [pscustomobject]@{ joins = 'https://d/joins' }
                              discordChannels = [pscustomobject]@{ joins = '123' } }

    It 'falls back to the webhook and STILL DELIVERS when the bot post 403s' {
        $script:calls = @()
        $ok = Send-GfDiscord -Config $cfg -Title 'YooDyl joined' -Message 'm' -Category 'joins' -Components $btn
        Assert-True $ok 'the alert must still be reported as sent'
        Assert-Eq $script:calls.Count 2 'one failed bot attempt, then the webhook'
        Assert-True ($script:calls[0].uri -like '*/channels/123/messages') 'tried the bot first'
        Assert-True ($script:calls[1].uri -eq 'https://d/joins') 'then the webhook'
        $p = $script:calls[1].body | ConvertFrom-Json
        Assert-True ($null -eq $p.components) 'the webhook copy carries no components'
        Assert-True ($p.embeds[0].title -like '*YooDyl joined*') 'and it is the SAME alert, not a stub'
    }
    It 'records WHY the button is missing, so it is diagnosable' {
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Category 'joins' -Components $btn
        Assert-True ($script:GfDiscordLastError -like '*WITHOUT buttons*') "got '$($script:GfDiscordLastError)'"
    }
}

Describe "Send-GfDiscord - a ONE-field card must ship fields as a LIST" {
    # 🛑 THE INCIDENT, 2026-08-20: four join alerts lost to a bare 400. A $( ) SUBEXPRESSION unrolls
    # a one-element array back to the bare element, so a card with a single field shipped
    #     "fields":{...}     instead of     "fields":[{...}]
    # and Discord rejected the whole message. Every card had TWO fields (location + the text link)
    # until the button replaced the link field with nothing - so this lay dormant for months and
    # detonated on a config change rather than a code change.
    $script:sentBody = $null
    function Invoke-RestMethod { param($Uri,$Method,$Body,$ContentType,$TimeoutSec,$Headers)
        $script:sentBody = [System.Text.Encoding]::UTF8.GetString($Body); return $null }
    $cfg = [pscustomobject]@{ serverName='Gunfight'; ntfyTopic=''
                              discordWebhooks=[pscustomobject]@{ default='https://d/def' } }
    $field = @{ name = 'x'; value = 'v' }

    It 'ONE field serialises as an array, not an object' {
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Fields @($field)
        Assert-True ($script:sentBody -match '"fields":\[') "shipped: $([regex]::Match($script:sentBody,'"fields":.{0,40}').Value)"
    }
    It 'TWO fields still serialise as an array' {
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Fields @($field, @{ name='y'; value='v2' })
        Assert-True ($script:sentBody -match '"fields":\[') 'two fields must stay a list'
    }
    It 'and it is never DOUBLE wrapped, which is the opposite mistake' {
        # `,` inside $( ) is right; `,` on a plain assignment ships [[{...}]] and 400s just as hard.
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Fields @($field)
        Assert-True (-not ($script:sentBody -match '"fields":\[\[')) 'fields must not be nested'
    }
    It 'no fields at all still sends, with a description instead' {
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'body text' -Fields @()
        Assert-True ($script:sentBody -match '"description":"body text"') 'falls back to the description'
    }
}

Describe "Send-GfDiscord - the map thumbnail" {
    # The ONE image mechanism available to us. A bot's own presence ignores art entirely
    # (docs/notes/bot-presence-is-text-only.md), but an embed renders a thumbnail from any public
    # https URL - which is why the map picture lives on the join CARD and not on the profile.
    $script:sentBody = $null
    function Invoke-RestMethod { param($Uri,$Method,$Body,$ContentType,$TimeoutSec,$Headers)
        $script:sentBody = [System.Text.Encoding]::UTF8.GetString($Body); return $null }
    $cfg = [pscustomobject]@{ serverName='Gunfight'; ntfyTopic=''
                              discordWebhooks=[pscustomobject]@{ default='https://d/def' } }

    It 'a URL ships as an OBJECT with a url key, which is the shape Discord requires' {
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Thumbnail 'https://gunfight.us/assets/maps/mp_nuked.jpg'
        Assert-True ($script:sentBody -match '"thumbnail":\{"url":"https://gunfight\.us/assets/maps/mp_nuked\.jpg"\}') `
                    "shipped: $([regex]::Match($script:sentBody,'"thumbnail":.{0,60}').Value)"
    }
    It 'omitted is null, never an empty object (which Discord rejects)' {
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm'
        Assert-True ($script:sentBody -match '"thumbnail":null') "shipped: $([regex]::Match($script:sentBody,'"thumbnail":.{0,30}').Value)"
    }
    It 'a thumbnail does not disturb the fields array - the two coexist on one card' {
        # Guards the 2026-08-20 class of bug from the other direction: adding an embed key must not
        # perturb the serialisation of the neighbouring one.
        $script:sentBody = $null
        $null = Send-GfDiscord -Config $cfg -Title 't' -Message 'm' -Fields @(@{ name='x'; value='v' }) `
                               -Thumbnail 'https://gunfight.us/assets/maps/mp_array.jpg'
        Assert-True ($script:sentBody -match '"fields":\[') 'fields must still be a list'
        Assert-True ($script:sentBody -match '"thumbnail":\{') 'and the thumbnail must still be an object'
    }
    It 'it also rides the BOT transport, not just the webhook' {
        # The join card uses the bot whenever a button is on it, so a thumbnail that only survived
        # the webhook path would be invisible on exactly the cards that have one.
        $script:calls = @()
        function Get-GfBotToken { return 'tok' }
        function Invoke-RestMethod { param($Uri,$Method,$Body,$ContentType,$TimeoutSec,$Headers)
            $script:calls += @{ uri = $Uri; body = [System.Text.Encoding]::UTF8.GetString($Body) }; return $null }
        $c = [pscustomobject]@{ serverName='Gunfight'; ntfyTopic=''
                                discordWebhooks=[pscustomobject]@{ joins='https://d/joins' }
                                discordChannels=[pscustomobject]@{ joins='123' } }
        $btn = @( @{ type=1; components=@( @{ type=2; style=5; label='Play for free!'; url='https://gunfight.us/' } ) } )
        $null = Send-GfDiscord -Config $c -Title 't' -Message 'm' -Category 'joins' -Components $btn `
                               -Thumbnail 'https://gunfight.us/assets/maps/mp_villa.jpg'
        Assert-True ($script:calls[0].uri -like '*/channels/123/messages') 'the bot transport was used'
        Assert-True ($script:calls[0].body -match '"thumbnail":\{"url":"[^"]*mp_villa\.jpg"\}') 'and it carried the thumbnail'
    }
}

Describe "Get-GfMapThumb - only ever points at art that exists" {
    # ⚠ $toolsRoot from the top of this file, NOT $MyInvocation - inside a Describe scriptblock
    # Pester 3.4 leaves MyCommand.Path null and Join-Path then throws on a null Path.
    $toolsDir = $toolsRoot
    . (Join-Path $toolsDir 'map_names.ps1')

    It 'a known map resolves to its picture' {
        Assert-Eq (Get-GfMapThumb 'mp_nuked') 'https://gunfight.us/assets/maps/mp_nuked.jpg' 'nuketown'
    }
    It 'an UNKNOWN map yields nothing rather than a guaranteed 404' {
        Assert-Eq (Get-GfMapThumb 'mp_notarealmap') '' 'unknown id must not build a URL'
    }
    It 'empty in, empty out' {
        Assert-Eq (Get-GfMapThumb '') '' 'blank'
        Assert-Eq (Get-GfMapThumb $null) '' 'null'
    }
    It 'the path is LOWERCASED - hashtables ignore case, web servers do not' {
        Assert-Eq (Get-GfMapThumb 'MP_Nuked') 'https://gunfight.us/assets/maps/mp_nuked.jpg' 'MP_Nuked'
    }
    It 'EVERY map in the name table has a staged image, and vice versa' {
        # 🛑 The invariant the whole design rests on: the art set and the id table are the same 26
        # maps, which is what lets Get-GfMapThumb treat "in the table" as "the image exists". A map
        # added to one and not the other silently breaks that, so it is asserted rather than assumed.
        $repo = Split-Path -Parent $toolsDir
        $dir  = Join-Path $repo 'site\wwwroot\assets\maps'
        if (-not (Test-Path $dir)) { throw "ASSERT: map art missing - run tools\fetch_map_art.ps1" }
        $onDisk = @(Get-ChildItem $dir -Filter '*.jpg' | ForEach-Object { $_.BaseName })
        $inTable = @($script:GfMapNames.Keys)
        $missing = @($inTable | Where-Object { $onDisk -notcontains $_ })
        $extra   = @($onDisk  | Where-Object { $inTable -notcontains $_ })
        Assert-True ($missing.Count -eq 0) "maps with no picture: $($missing -join ', ')"
        Assert-True ($extra.Count   -eq 0) "pictures with no map: $($extra -join ', ')"
    }
}
