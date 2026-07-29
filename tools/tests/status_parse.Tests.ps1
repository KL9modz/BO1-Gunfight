# Pester regression net for tools/status_parse.ps1 - the PowerShell TWIN of
# tools/status_parse.js (which tools/rcon/test/server.test.js covers with these same cases).
#
#   Invoke-Pester tools/tests
#
# Both suites parse the SAME fixture (fixtures/status_reply.txt), so the two implementations
# are pinned to one input: a one-sided parser edit fails the other side's mirror case. Case
# names below match the node:test names 1:1 - if one suite changes, change the other.
#
# The color-coded row is appended at runtime as a string literal rather than living in the
# fixture: a bare `^N` roster row in a text file is exactly the shape the pre-commit
# status-roster guard exists to block (see tools/hooks/pre-commit section 5).
#
# ⚠ Assertions are plain `if (...) { throw }` - NOT `Should Be` / `Should -Be` - on purpose:
# the inbox Windows Pester is 3.4 (space syntax) and Pester 5 removed that syntax entirely,
# so either dialect fails on the other box. An `It` block failing on a thrown exception is
# the one contract every Pester version honours.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $here) "status_parse.ps1")

function Assert-True($cond, $msg)  { if (-not $cond) { throw "ASSERT: $msg" } }
function Assert-False($cond, $msg) { if ($cond)      { throw "ASSERT: $msg" } }
function Assert-Eq($actual, $expected, $msg) {
    if ("$actual" -ne "$expected") { throw "ASSERT: $msg -- expected [$expected], got [$actual]" }
}

$script:FIXTURE  = Get-Content (Join-Path $here "fixtures\status_reply.txt") -Raw
$script:ColorRow = "  2   857    0       0 ^1LiMi7ED       1092400 unknown                   42  5000"
$script:STATUS   = $script:FIXTURE.TrimEnd() + "`n" + $script:ColorRow

function Find-Player($result, $name) {
    foreach ($p in @($result.players)) { if ($p.name -eq $name) { return $p } }
    return $null
}

Describe "ConvertFrom-GfStatus (twin of parseStatusText)" {
    It "map/gametype header" {
        $r = ConvertFrom-GfStatus $script:STATUS
        Assert-Eq $r.map 'mp_nuked' "map read"
        Assert-Eq $r.gametype 'gf' "gametype read"
    }
    It "spaced bot name reads as ONE bot, not a shifted human (MCG Gordon incident)" {
        $p = Find-Player (ConvertFrom-GfStatus $script:STATUS) 'MCG Gordon'
        Assert-True ($null -ne $p) "spaced name parsed whole"
        Assert-True ($p.bot -eq $true) "guid 0 + addr unknown = positive bot claim"
        Assert-True ($null -eq $p.ip) "bot has no ip"
    }
    It "signed 16-bit NEGATIVE port still yields the IP (half-of-all-players incident)" {
        $p = Find-Player (ConvertFrom-GfStatus $script:STATUS) 'Player One'
        Assert-True ($null -ne $p) "spaced human name parsed whole"
        Assert-True ($p.bot -eq $false) "human claim"
        Assert-Eq $p.ip '203.0.113.7' "sign dropped, IP kept"
    }
    It "positive-port human classified with IP" {
        $p = Find-Player (ConvertFrom-GfStatus $script:STATUS) 'Dude'
        Assert-True ($p.bot -eq $false) "human claim"
        Assert-Eq $p.ip '198.51.100.3' "IP kept"
    }
    It "loopback row marks the listen server and local player" {
        $r = ConvertFrom-GfStatus $script:STATUS
        Assert-True ($r.listenServer -eq $true) "listenServer flagged"
        $p = Find-Player $r 'KL9'
        Assert-True ($p.local -eq $true) "local flagged"
        Assert-Eq $p.ip 'local' "ip is the local marker"
        Assert-True ($p.bot -eq $false) "host is a human"
    }
    It "unreadable row is bot=NULL, NEVER a claim (kick-a-real-player incident)" {
        $r = ConvertFrom-GfStatus $script:STATUS
        $p = Find-Player $r 'Joining'
        Assert-True ($null -eq $p.bot) "guid 0 at addr CNCT is unclassifiable"
        # The polarity rule: all three states must be present and distinct.
        Assert-True ((Find-Player $r 'MCG Gordon').bot -eq $true)  "claimed bot stays true"
        Assert-True ((Find-Player $r 'Dude').bot       -eq $false) "claimed human stays false"
    }
    It "nonzero-guid row at a bot address is NOT claimed as a bot" {
        $s = $script:STATUS + "`n" + "  7     0    0 1234567 Ghost                 0 unknown                  44  5000"
        $p = Find-Player (ConvertFrom-GfStatus $s) 'Ghost'
        Assert-True ($null -eq $p.bot) "nonzero guid at bot addr = unclassifiable"
    }
    It "color codes stripped from names" {
        $p = Find-Player (ConvertFrom-GfStatus $script:STATUS) 'LiMi7ED'
        Assert-True ($null -ne $p) "^1 prefix stripped"
    }
    It "malformed/short rows are skipped, not misread" {
        $s = $script:STATUS + "`nnot a row`n  9  12`n"
        Assert-Eq (@((ConvertFrom-GfStatus $s).players).Count) 6 "exactly the 6 real rows"
    }
    It "non-numeric ping (CNCT) is null, not a cast error" {
        $s = $script:STATUS + "`n" + "  8     0 CNCT       0 MidConnect            0 CNCT                     78  5000"
        $p = Find-Player (ConvertFrom-GfStatus $s) 'MidConnect'
        Assert-True ($null -eq $p.ping) "ping null when the column is not a number"
        Assert-Eq (Find-Player (ConvertFrom-GfStatus $s) 'Joining').ping 999 "numeric ping still an int"
    }
    It "headerless reply yields empty map (falsy), and map/gametype strip colors" {
        $r = ConvertFrom-GfStatus "gametype: gf^7`nno separator here"
        Assert-Eq $r.map '' "map absent reads as empty string"
        Assert-Eq $r.gametype 'gf' "^7 stripped"
        Assert-Eq (@($r.players).Count) 0 "no players parsed"
    }
}

Describe "Remove-GfColors" {
    It "Treyarch ^N codes removed, text trimmed (twin of stripColors)" {
        Assert-Eq (Remove-GfColors "  ^1Red^7Name  ") "RedName" "codes stripped + trimmed"
    }
}
