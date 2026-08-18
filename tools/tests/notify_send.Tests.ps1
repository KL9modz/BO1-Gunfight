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
    It "every priority the senders accept has a colour" {
        foreach ($p in @('min','low','default','high','urgent','max')) {
            Assert-True ($script:GfDiscordColor.ContainsKey($p)) "colour for priority '$p'"
        }
    }
}
