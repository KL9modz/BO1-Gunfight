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
    }
}
