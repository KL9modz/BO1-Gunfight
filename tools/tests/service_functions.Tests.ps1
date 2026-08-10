# Pester net for the pure functions embedded in the SERVICE scripts - the classifiers that were
# each verified by ad-hoc probes at birth (2026-08-06/07) and then had no regression net:
#
#   security_watch.ps1  Resolve-ServiceImagePath   the four ImagePath shapes Event 7045 emits
#   security_watch.ps1  Get-BinaryTrust            the Authenticode tiering that decides pushes
#   conn_logger.ps1     Convert-PanelStatus        the panel-fallback shape conversion
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
