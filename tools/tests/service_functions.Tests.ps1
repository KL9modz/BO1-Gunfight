# Pester net for the pure functions embedded in the SERVICE scripts - the classifiers that were
# each verified by ad-hoc probes at birth (2026-08-06/07) and then had no regression net:
#
#   security_watch.ps1  Resolve-ServiceImagePath   the four ImagePath shapes Event 7045 emits
#   security_watch.ps1  Get-BinaryTrust            the Authenticode tiering that decides pushes
#   conn_logger.ps1     Convert-PanelStatus        the panel-fallback shape conversion
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
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'notify\join-notify.ps1') 'Get-ConnectCount')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'notify\join-notify.ps1') 'Format-Ordinal')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $toolsRoot 'notify\join-notify.ps1') 'Format-ConnectCount')))

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
