# Pester net for the pure functions embedded in the SERVICE scripts - the classifiers that were
# each verified by ad-hoc probes at birth (2026-08-06/07) and then had no regression net:
#
#   security_watch.ps1  Resolve-ServiceImagePath   the four ImagePath shapes Event 7045 emits
#   security_watch.ps1  Get-BinaryTrust            the Authenticode tiering that decides pushes
#   conn_logger.ps1     Convert-PanelStatus        the panel-fallback shape conversion
#   watchdog.ps1        Get-FileAgeSeconds         the atomically-replaced-json stat race (BOTH halves)
#   join-notify.ps1     Get-ConnectCount           the day-file connect tally behind "7th connect"
#                       Format-Ordinal / Format-ConnectCount
#
#   Invoke-Pester tools/tests
#
# ⚠ These scripts are RUNNABLE SERVICES, not libraries - dot-sourcing them starts a watcher /
# infinite loop. Each function is extracted by AST instead (FunctionDefinitionAst by name) and
# defined into this scope, so the tests exercise the EXACT shipped text without running a line
# of the surrounding script. If extraction fails, the named test fails loudly - a renamed or
# deleted function cannot pass silently.
#
# NOT here: run_service.ps1's remaining-args parser - it is inline loop code, not a function, so
# there is nothing to extract by name. If it ever needs pinning, lift it into a function first.
#
# ⚠ Assertions are plain `if (...) { throw }` (Pester 3.4 and 5.x both honour thrown exceptions;
# the Should syntaxes are mutually incompatible across those versions - see guards.Tests.ps1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $here

function Assert-True($cond, $msg)  { if (-not $cond) { throw "ASSERT: $msg" } }
function Assert-False($cond, $msg) { if ($cond)      { throw "ASSERT: $msg" } }
function Assert-Eq($actual, $expected, $msg) {
    if ("$actual" -ne "$expected") { throw "ASSERT: $msg -- expected [$expected], got [$actual]" }
}

# Returns the function's exact shipped TEXT; the caller dot-sources it AT FILE SCOPE. (First cut
# dot-sourced inside this helper - the definition landed in the helper's scope and evaporated
# when it returned, so every test failed CommandNotFound. Scope of a dot-source = scope of the
# CALL SITE, not of the target.)
function Get-FunctionText {
    param([string]$ScriptPath, [string]$FunctionName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $FunctionName }, $true) | Select-Object -First 1
    if (-not $fn) { throw "function '$FunctionName' not found in $ScriptPath - renamed or deleted?" }
    return $fn.Extent.Text
}

. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'vps_services\security_watch.ps1') 'Resolve-ServiceImagePath')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'vps_services\security_watch.ps1') 'Get-BinaryTrust')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'conn_logger\conn_logger.ps1') 'Convert-PanelStatus')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'vps_services\watchdog.ps1') 'Get-FileAgeSeconds')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'notify\join-notify.ps1') 'Get-ConnectCount')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'notify\join-notify.ps1') 'Format-Ordinal')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'notify\join-notify.ps1') 'Format-ConnectCount')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'notify\join-notify.ps1') 'Get-JoinTitle')))

Describe "Resolve-ServiceImagePath (security_watch)" {
    It "resolves a %SystemRoot%-relative path (the KslD shape)" {
        Assert-Eq (Resolve-ServiceImagePath 'system32\drivers\wd\KslD.sys') (Join-Path $env:SystemRoot 'system32\drivers\wd\KslD.sys') "relative resolves under SystemRoot"
    }
    It "strips the NT-native \??\ prefix" {
        Assert-Eq (Resolve-ServiceImagePath '\??\C:\Windows\System32\drivers\x.sys') 'C:\Windows\System32\drivers\x.sys' "NT prefix stripped"
    }
    It "expands \SystemRoot\" {
        Assert-Eq (Resolve-ServiceImagePath '\SystemRoot\System32\drivers\x.sys') (Join-Path $env:SystemRoot 'System32\drivers\x.sys') "SystemRoot token expanded"
    }
    It "takes the quoted path and drops trailing arguments" {
        Assert-Eq (Resolve-ServiceImagePath '"C:\Program Files\App\svc.exe" -k net') 'C:\Program Files\App\svc.exe' "quoted path wins over args"
    }
    It "drops switch-style args from an unquoted path" {
        Assert-Eq (Resolve-ServiceImagePath 'C:\Windows\system32\svchost.exe -k netsvcs') 'C:\Windows\system32\svchost.exe' "unquoted args dropped"
    }
    It "empty input yields empty, never a throw" {
        Assert-Eq (Resolve-ServiceImagePath '') '' "empty in, empty out"
    }
}

Describe "Get-BinaryTrust (security_watch) - the tiering that decides what pages" {
    It "a Microsoft-signed system binary is Valid + isMicrosoft (the log-only tier)" {
        $t = Get-BinaryTrust (Join-Path $env:SystemRoot 'System32\notepad.exe')
        Assert-True $t.exists "notepad exists"
        Assert-Eq $t.status 'Valid' "signature valid"
        Assert-True $t.isMicrosoft "O=Microsoft Corporation matched"
    }
    It "an unsigned file EXISTS but is not Valid (the HIGH tier)" {
        $tmp = Join-Path $env:TEMP 'gf_trust_test_unsigned.sys'
        'not a driver' | Set-Content $tmp -Encoding Ascii
        $t = Get-BinaryTrust $tmp
        Remove-Item $tmp -Force
        Assert-True $t.exists "file existed"
        Assert-False ($t.status -eq 'Valid') "unsigned is not Valid"
        Assert-False $t.isMicrosoft "unsigned is never isMicrosoft"
    }
    It "a missing file is exists=false, FileMissing (the informational tier)" {
        $t = Get-BinaryTrust (Join-Path $env:TEMP 'gf_no_such_binary_ever.sys')
        Assert-False $t.exists "missing"
        Assert-Eq $t.status 'FileMissing' "status names it"
    }
    It "empty path degrades to missing, never throws" {
        $t = Get-BinaryTrust ''
        Assert-False $t.exists "empty path = missing"
    }
}

Describe "Get-FileAgeSeconds (watchdog) - both halves of the atomic-replace stat race" {
    # status_service replaces admin.json with Move-Item -Force (delete THEN move), so a reader can
    # land mid-replace and see either no file (paged a false alarm 2026-08-14 02:29:04) or a file
    # whose LastWriteTime is the ZERO FILETIME, 1601-01-01 (paged another 2026-08-17 08:38:03, via
    # an Int32 overflow on a 13,431,458,283-second age). Both must degrade to "unknown", never to a
    # number - a huge age would make check 3b KILL THE BOOTSTRAPPER on a healthy server.
    $work = Join-Path $env:TEMP ("gf_agetest_" + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $f = Join-Path $work 'admin.json'
    'x' | Set-Content $f

    It "a normal file gives a sane age in seconds" {
        (Get-Item $f).LastWriteTime = (Get-Date).AddSeconds(-42)
        $age = Get-FileAgeSeconds $f
        Assert-True ($age -ge 40 -and $age -le 45) "expected ~42, got $age"
    }
    It "a MISSING file is null, never a throw (the 2026-08-14 half)" {
        Assert-True ($null -eq (Get-FileAgeSeconds (Join-Path $work 'gone.json'))) "missing = null"
    }
    It "the ZERO FILETIME (1601) is null, not an Int32 overflow (the 2026-08-17 half)" {
        (Get-Item $f).LastWriteTime = [datetime]'1601-01-01 00:00:00'
        # sanity: this really is the overflowing shape, or the test proves nothing
        $raw = (New-TimeSpan -Start (Get-Item $f).LastWriteTime -End (Get-Date)).TotalSeconds
        Assert-True ($raw -gt 2147483647) "fixture must exceed Int32 max; got $raw"
        Assert-True ($null -eq (Get-FileAgeSeconds $f)) "1601 timestamp = failed stat = null"
    }
    It "a small clock skew still reads as FRESH (must not be nulled)" {
        (Get-Item $f).LastWriteTime = (Get-Date).AddSeconds(2)
        $age = Get-FileAgeSeconds $f
        Assert-True ($null -ne $age -and $age -le 0) "small future = small negative, got [$age]"
    }
    It "an absurd future timestamp is null" {
        (Get-Item $f).LastWriteTime = (Get-Date).AddDays(10)
        Assert-True ($null -eq (Get-FileAgeSeconds $f)) "10d future = failed stat = null"
    }

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Convert-PanelStatus (conn_logger) - the panel-fallback shape" {
    $fake = [pscustomobject]@{ ok = $true; players = @(
        [pscustomobject]@{ num=1; name='AdrianRGamer'; guid='7654321'; addr='203.0.113.7:-12558'; ping=68;    bot=$false }
        [pscustomobject]@{ num=2; name='SomeBot';      guid='0';       addr='unknown';            ping=0;     bot=$true  }
        [pscustomobject]@{ num=3; name='MidConnect';   guid='0';       addr='CNCT';               ping=$null; bot=$null  }
    ) }
    It "keeps only POSITIVELY-human rows (bot -eq false; null unclassifiable excluded)" {
        $snap = Convert-PanelStatus $fake
        Assert-Eq (@($snap.players).Count) 1 "exactly the one human"
        Assert-Eq (@($snap.players)[0].name) 'AdrianRGamer' "the human survived"
    }
    It "maps addr (with its signed-16-bit port) into ip, guid stays a string" {
        $p = @((Convert-PanelStatus $fake).players)[0]
        Assert-Eq $p.ip '203.0.113.7:-12558' "addr carried as ip, negative port intact"
        Assert-Eq $p.guid '7654321' "guid string"
    }
    It "produces an online snapshot with a fresh timestamp field" {
        $snap = Convert-PanelStatus $fake
        Assert-True $snap.online "online"
        Assert-True ([bool]$snap.updated) "updated stamped"
    }
    It "panel ok=false yields null (caller falls through to 'no data')" {
        Assert-True ($null -eq (Convert-PanelStatus ([pscustomobject]@{ ok = $false }))) "not-ok is null"
        Assert-True ($null -eq (Convert-PanelStatus $null)) "null is null"
    }
}

Describe "Get-ConnectCount (join-notify) - the day-file connect tally" {
    # The function reads $script:ConnLogDir / $script:ConnCountFreshSec, which live in the
    # service script's scope. Extracted here, they resolve against THIS file's scope, so the
    # tests point them at a throwaway log dir built to conn_logger's Write-Event line format.
    $script:ConnCountFreshSec = 120
    $tmp = Join-Path $env:TEMP ("gf_conncount_test_{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $script:ConnLogDir = $tmp

    $oldDay = (Get-Date).AddDays(-2)
    $old = $oldDay.ToString('yyyy-MM-dd HH:mm:ss')
    @(
        "$oldDay  ----- conn_logger started (source=admin.json interval=5s) -----",
        "$old  ONLINE   ip=203.0.113.5:28960  name=`"Old Timer`"  guid=111  ping=42",
        "$old  CONNECT  ip=203.0.113.5:28960  name=`"Old Timer`"  guid=111  ping=42",
        "$old  LEFT     ip=203.0.113.5:28960  name=`"Old Timer`"  guid=111  ping=-  session=5m00s",
        "$old  CONNECT  ip=203.0.113.9:-12558  name=`"Other Guy`"  guid=1112  ping=90",
        "$old  CONNECT  ip=203.0.113.5:28960  name=`"Old Timer`"  guid=111  ping=99"
    ) | Set-Content (Join-Path $tmp ('players_{0}.log' -f $oldDay.ToString('yyyy-MM-dd'))) -Encoding UTF8

    It "counts logged CONNECTs plus the join being announced" {
        Assert-Eq (Get-ConnectCount 111) 3 "2 on disk + this join"
    }
    It "ignores ONLINE (cold-start) and LEFT lines" {
        # 111 has one ONLINE and one LEFT line too; counting either would make it 4 or 5.
        Assert-Eq (Get-ConnectCount 111) 3 "only CONNECT lines count"
    }
    It "matches the WHOLE guid, never a prefix" {
        Assert-Eq (Get-ConnectCount 1112) 2 "guid=111 lines are not guid=1112 lines"
    }
    It "a never-seen guid is their first connect" {
        Assert-Eq (Get-ConnectCount 999999) 1 "no history = 1"
        Assert-Eq (Format-ConnectCount (Get-ConnectCount 999999)) 'first connect' "spelled out"
    }
    It "does NOT double-count when conn_logger already logged this join" {
        $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content (Join-Path $tmp ('players_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))) -Encoding UTF8 `
            -Value "$now  CONNECT  ip=203.0.113.5:28960  name=`"Old Timer`"  guid=111  ping=50"
        Assert-Eq (Get-ConnectCount 111) 3 "fresh line IS this join - still 3, not 4"
    }
    It "a guid forged INSIDE a name cannot inflate that guid's count" {
        # name="..." is the one free-text field, so a player renamed to  x"  guid=7777  ping=1
        # writes a line whose FRONT reads as a complete record for 7777 while their own record
        # sits at the end. Only the end anchor separates them. conn_logger's Write-Event now
        # strips quotes so this line stops being written at all; this pins the READER's half,
        # which is what covers the day-files already on disk. Dated OLD so the "add the current
        # join" step applies - that is what makes a miscount visible as 2 instead of 1.
        Add-Content (Join-Path $tmp ('players_{0}.log' -f $oldDay.ToString('yyyy-MM-dd'))) -Encoding UTF8 `
            -Value "$old  CONNECT  ip=203.0.113.7:28960  name=`"x`"  guid=7777  ping=1`"  guid=222  ping=9"
        Assert-Eq (Get-ConnectCount 7777) 1 "forged front is not a record for 7777 - no history, just this join"
        Assert-Eq (Get-ConnectCount 222) 2 "the REAL end-of-line record still counts: 1 logged + this join"
    }
    It "returns null (bit omitted) for an unusable guid or a missing log dir" {
        Assert-True ($null -eq (Get-ConnectCount '0')) "guid 0 identifies nobody"
        Assert-True ($null -eq (Get-ConnectCount '')) "empty guid"
        $script:ConnLogDir = Join-Path $tmp 'no_such_dir'
        Assert-True ($null -eq (Get-ConnectCount 111)) "no day-files = no claim, NOT 'first connect'"
        $script:ConnLogDir = $tmp
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Format-Ordinal / Format-ConnectCount (join-notify)" {
    It "suffixes 1/2/3 and the 11-13 teens correctly" {
        Assert-Eq ((1,2,3,4,11,12,13,21,111,112 | ForEach-Object { Format-Ordinal $_ }) -join ' ') `
                  '1st 2nd 3rd 4th 11th 12th 13th 21st 111th 112th' "ordinals"
    }
    It "renders the alert bit, empty for null/0 so it drops out of the body" {
        Assert-Eq (Format-ConnectCount 1) 'first connect' "1 spells out"
        Assert-Eq (Format-ConnectCount 7) '7th connect' "N takes an ordinal"
        Assert-Eq (Format-ConnectCount $null) '' "null = no bit"
        Assert-Eq (Format-ConnectCount 0) '' "0 = no bit"
    }
}

Describe "watchdog check 1d (Claude RC) - the fail-safe structure, not the happy path" {
    # This check can Stop/Start GF-ClaudeRC, which ends every live remote-control session on the
    # box - including the one an operator may be watching it from. So the structural property
    # worth pinning is not "does it detect a dead server" but "can it ever act on ABSENT EVIDENCE".
    # Both guards below encode a decision that is invisible in the happy path and expensive to
    # rediscover.
    $wd = Join-Path $toolsRoot 'vps_services\watchdog.ps1'
    $wdAst = [System.Management.Automation.Language.Parser]::ParseFile($wd, [ref]$null, [ref]$null)

    It "the 'server gone' branch is gated behind the query-failed branch" {
        $ifs = @($wdAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.IfStatementAst]
        }, $true) | Where-Object { $_.Extent.Text -match 'RC SERVER GONE' })
        Assert-True ($ifs.Count -gt 0) "no if-statement mentions 'RC SERVER GONE' - check 1d renamed or removed?"

        # The tightest enclosing if IS the whole elseif chain, so its FIRST clause must be the
        # query-failed escape. If a later edit reorders these, the down branch becomes reachable
        # on a failed/blind query and remediation kills live sessions for no reason.
        $chain = $ifs | Sort-Object { $_.Extent.Text.Length } | Select-Object -First 1
        $firstCond = $chain.Clauses[0].Item1.Extent.Text
        Assert-True ($firstCond -match 'queryOk') `
            "the first clause of the RC branch chain is [$firstCond] - it must be the query-failed escape, or a blind run can Stop/Start the RC task"

        $conds = @($chain.Clauses | ForEach-Object { $_.Item1.Extent.Text })
        Assert-True (($conds -join ' ') -match 'anyClaude') `
            "no clause tests `$anyClaude - claude.exe running with unreadable command lines would be judged 'gone'"
    }

    It 'GF-ClaudeRC is not also in the plain $Tasks list' {
        $paramBlock = $wdAst.ParamBlock
        Assert-True ($null -ne $paramBlock) "watchdog.ps1 lost its param block"
        $tasksParam = @($paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Tasks' }) | Select-Object -First 1
        Assert-True ($null -ne $tasksParam) "no `$Tasks parameter found"
        # Check 1 (task State) and check 1d (process truth) would both fire on one outage. Two
        # pushes for one event is how an alert channel gets muted.
        Assert-False ($tasksParam.DefaultValue.Extent.Text -match 'ClaudeRC') `
            "GF-ClaudeRC is in the `$Tasks default - it would double-alert alongside check 1d"
    }
}

Describe "Get-JoinTitle (join-notify) - the owner's join card format" {
    # Format rules, and each one is a decision rather than a default:
    #   * an empty-server join does NOT say "empty server" and does NOT carry a count - the alert
    #     arriving IS that news, and "(1)" was noise
    #   * once others are playing, the head count trails the MAP, reading as context instead of a
    #     label stuck to the player's name
    #   * the map is the public display name, resolved upstream by Get-GfMapName
    It 'a join into an empty server carries neither count nor empty-server text' {
        Assert-Eq (Get-JoinTitle 'fentfella' 'Havana' 1) 'fentfella joined  Havana' 'first join'
    }
    It 'a join with others already on puts the total AFTER the map name' {
        Assert-Eq (Get-JoinTitle 'KL9' 'Havana' 3) 'KL9 joined  Havana  (3)' 'later join'
    }
    It 'an unknown map degrades to name + count, never a dangling separator' {
        Assert-Eq (Get-JoinTitle 'KL9' '' 3) 'KL9 joined  (3)' 'no map, others on'
        Assert-Eq (Get-JoinTitle 'KL9' '' 1) 'KL9 joined'      'no map, alone'
    }
    It 'a count of 0 or a non-numeric count never renders a count' {
        Assert-Eq (Get-JoinTitle 'KL9' 'Zoo' 0) 'KL9 joined  Zoo' 'zero'
    }
}

Describe "Get-GfPlayerLinks / Get-GfPlayerMention - the Discord link table" {
    . (Join-Path $toolsRoot 'player_links.ps1')

    function New-LinkFile($obj) {
        $p = Join-Path $env:TEMP ("gf_links_" + [IO.Path]::GetRandomFileName() + ".json")
        ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $p -Encoding UTF8
        return $p
    }

    It 'resolves a linked guid to a mention' {
        $f = New-LinkFile @{ links = @{ '1234567' = @{ discordId = '987654321098765432'; note = 'someone' } } }
        $links = Get-GfPlayerLinks $f
        Assert-Eq (Get-GfPlayerMention $links '1234567') '<@987654321098765432>' 'linked guid'
        Remove-Item $f -Force
    }
    It 'an unlinked guid, an empty id and a missing table all yield no mention' {
        $f = New-LinkFile @{ links = @{ '1234567' = @{ discordId = ''; note = 'seeded, not filled in' } } }
        $links = Get-GfPlayerLinks $f
        # A seeded row is the NORMAL state of a pre-populated table - it must not become a mention
        # of nobody, and must not throw.
        Assert-Eq (Get-GfPlayerMention $links '1234567') '' 'empty discordId'
        Assert-Eq (Get-GfPlayerMention $links '7654321') '' 'guid not in table'
        Assert-Eq (Get-GfPlayerMention (Get-GfPlayerLinks (Join-Path $env:TEMP 'gf_no_such_links.json')) '1234567') '' 'missing file'
        Remove-Item $f -Force
    }
    It 'sanitises the id to digits, so a bad value cannot smuggle in another mention' {
        # The table is hand-edited; a stray paste like "everyone> <@&12345" would otherwise be
        # interpolated straight into text Discord parses.
        $f = New-LinkFile @{ links = @{ '1234567' = @{ discordId = 'everyone>  <@&11111>'; note = 'hostile' } } }
        $m = Get-GfPlayerMention (Get-GfPlayerLinks $f) '1234567'
        Assert-Eq $m '<@11111>' 'reduced to digits'
        Assert-False ($m -match 'everyone') 'no everyone token survives'
        Remove-Item $f -Force
    }
    It 'an unreadable table yields no links instead of throwing' {
        $f = Join-Path $env:TEMP ("gf_links_bad_" + [IO.Path]::GetRandomFileName() + ".json")
        '{ this is not json' | Set-Content -LiteralPath $f -Encoding UTF8
        Assert-Eq (Get-GfPlayerLinks $f).Count 0 'bad json is empty, not fatal'
        Remove-Item $f -Force
    }
    It 'picks up an EDIT without a restart (the mtime cache must not go stale)' {
        $f = New-LinkFile @{ links = @{ '1234567' = @{ discordId = '111111111111111111'; note = 'before' } } }
        Assert-Eq (Get-GfPlayerMention (Get-GfPlayerLinks $f) '1234567') '<@111111111111111111>' 'first read'
        (@{ links = @{ '1234567' = @{ discordId = '222222222222222222'; note = 'after' } } } | ConvertTo-Json -Depth 5) |
            Set-Content -LiteralPath $f -Encoding UTF8
        (Get-Item $f).LastWriteTimeUtc = (Get-Item $f).LastWriteTimeUtc.AddSeconds(5)   # beat same-tick granularity
        Assert-Eq (Get-GfPlayerMention (Get-GfPlayerLinks $f) '1234567') '<@222222222222222222>' 'edit picked up'
        Remove-Item $f -Force
    }
}
