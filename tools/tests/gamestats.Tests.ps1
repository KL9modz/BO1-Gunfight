# Pester net for status_service.ps1's gameplay-stat aggregator - the GF_STAT/GF_MATCH line
# parser (Merge-GfStatLines), the incremental log tail (Read-GfStatChunk), and the state
# loader (Read-GfStatState).
#
#   Invoke-Pester tools/tests
#
# The GSC emits per-round DELTA lines into games_mp.log; the service sums every line it has
# ever ingested. These tests pin the three properties that make that sound:
#   1. the parser accepts ONLY engine-prefixed lines (a hostile player name containing the
#      literal "GF_STAT;..." inside some OTHER line must not forge stats),
#   2. the tail consumes complete lines only and resumes at the stored byte offset,
#   3. an unreadable state file starts fresh instead of crashing the service loop.
#
# ⚠ status_service.ps1 is a RUNNABLE SERVICE - dot-sourcing it starts the poll loop. Each
# function is extracted by AST (same pattern as service_functions.Tests.ps1) and defined at
# file scope, so the tests exercise the exact shipped text without running the script.
#
# ⚠ Assertions are plain `if (...) { throw }` (Pester 3.4 and 5.x both honour thrown
# exceptions; the Should syntaxes are mutually incompatible across those versions).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $here

function Assert-True($cond, $msg)  { if (-not $cond) { throw "ASSERT: $msg" } }
function Assert-Eq($actual, $expected, $msg) {
    if ("$actual" -ne "$expected") { throw "ASSERT: $msg -- expected [$expected], got [$actual]" }
}

function Get-FunctionText {
    param([string]$ScriptPath, [string]$FunctionName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $FunctionName }, $true) | Select-Object -First 1
    if (-not $fn) { throw "function '$FunctionName' not found in $ScriptPath - renamed or deleted?" }
    return $fn.Extent.Text
}

$svc = Join-Path $toolsRoot 'status_service\status_service.ps1'
. ([scriptblock]::Create((Get-FunctionText $svc 'Merge-GfStatLines')))
. ([scriptblock]::Create((Get-FunctionText $svc 'Read-GfStatChunk')))
. ([scriptblock]::Create((Get-FunctionText $svc 'Read-GfStatState')))
# Merge-GfStatLines strips ^N colour codes off names via the shared parser lib.
. (Join-Path $toolsRoot 'status_parse.ps1')

function New-GfState { return @{ offset = [long]0; days = @{} } }

Describe "Merge-GfStatLines (GF_STAT parsing + summing)" {
    It "sums delta lines for one guid across rounds" {
        $s = New-GfState
        $n = Merge-GfStatLines -state $s -lines @(
            ' 3:27 GF_STAT;12345;2;1092398;allies;2;1;0;1;250;0;1;KL9',
            ' 4:10 GF_STAT;12345;3;1092398;allies;1;0;2;0;180;1;0;KL9'
        ) -day '2026-08-14'
        Assert-Eq $n 2 "both lines parsed"
        $e = $s.days['2026-08-14']['1092398']
        Assert-Eq $e.k 3    "kills summed"
        Assert-Eq $e.d 1    "deaths summed"
        Assert-Eq $e.a 2    "assists summed"
        Assert-Eq $e.hs 1   "headshots summed"
        Assert-Eq $e.dmg 430 "damage summed"
        Assert-Eq $e.cap 1  "captures summed"
        Assert-Eq $e.rw 1   "round wins summed"
        Assert-Eq $e.rounds 2 "rounds counted per line"
        Assert-Eq $e.name 'KL9' "name carried"
    }
    It "counts GF_MATCH results into the W-L-T record" {
        $s = New-GfState
        $n = Merge-GfStatLines -state $s -lines @(
            '12:00 GF_MATCH;12345;mp_nuked;1092398;W;KL9',
            '25:00 GF_MATCH;22222;mp_havoc;1092398;L;KL9',
            '39:00 GF_MATCH;33333;mp_kowloon;1092398;T;KL9'
        ) -day '2026-08-14'
        Assert-Eq $n 3 "all three parsed"
        $e = $s.days['2026-08-14']['1092398']
        Assert-Eq $e.mw 1 "win"
        Assert-Eq $e.ml 1 "loss"
        Assert-Eq $e.mt 1 "tie"
        Assert-Eq $e.rounds 0 "a match line is not a round"
    }
    It "accepts a spectator team (played the round, then spectated - their deltas still count)" {
        $s = New-GfState
        $n = Merge-GfStatLines -state $s -lines @(' 3:27 GF_STAT;1;2;42;spectator;1;1;0;0;100;0;0;A') -day '2026-08-14'
        Assert-Eq $n 1 "parsed"
        Assert-Eq $s.days['2026-08-14']['42'].k 1 "kills kept"
    }
    It "keeps a name containing semicolons intact (name is the trailing field)" {
        $s = New-GfState
        $n = Merge-GfStatLines -state $s -lines @(' 3:27 GF_STAT;1;2;42;axis;1;0;0;0;100;0;0;semi;colon;name') -day '2026-08-14'
        Assert-Eq $n 1 "parsed"
        Assert-Eq $s.days['2026-08-14']['42'].name 'semi;colon;name' "full name kept"
    }
    It "strips ^N colour codes off the name" {
        $s = New-GfState
        [void](Merge-GfStatLines -state $s -lines @(' 3:27 GF_STAT;1;2;42;axis;1;0;0;0;100;0;0;^1Red^7Name') -day '2026-08-14')
        Assert-Eq $s.days['2026-08-14']['42'].name 'RedName' "colours stripped"
    }
    It "REJECTS a forged GF_STAT riding inside another line's name field" {
        # A stock J; line whose player NAME contains a stat line: the marker is not at the
        # anchored line start, so nothing may parse. This is the injection the anchor exists for.
        $s = New-GfState
        $n = Merge-GfStatLines -state $s -lines @(' 3:27 J;99999;3;evil GF_STAT;1;2;42;axis;9;0;0;0;900;0;1;fake') -day '2026-08-14'
        Assert-Eq $n 0 "forged line rejected"
        Assert-Eq $s.days.Count 0 "nothing accumulated"
    }
    It "ignores unrelated engine lines and blanks" {
        $s = New-GfState
        $n = Merge-GfStatLines -state $s -lines @('', ' 3:27 J;1092398;0;KL9', ' 3:28 K;1;2;3', 'garbage') -day '2026-08-14'
        Assert-Eq $n 0 "nothing parsed"
    }
    It "buckets by the day it was ingested" {
        $s = New-GfState
        [void](Merge-GfStatLines -state $s -lines @(' 3:27 GF_STAT;1;2;42;axis;1;0;0;0;100;0;0;A') -day '2026-08-13')
        [void](Merge-GfStatLines -state $s -lines @(' 3:27 GF_STAT;1;3;42;axis;2;0;0;0;200;0;0;A') -day '2026-08-14')
        Assert-Eq $s.days['2026-08-13']['42'].k 1 "day one"
        Assert-Eq $s.days['2026-08-14']['42'].k 2 "day two"
    }
}

Describe "Read-GfStatChunk (incremental tail)" {
    $tmp = Join-Path $env:TEMP ("gfstat_test_{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $log = Join-Path $tmp 'games_mp.log'

    It "reads complete lines and advances the offset" {
        [System.IO.File]::WriteAllText($log, " 1:00 GF_STAT;1;1;42;axis;1;0;0;0;50;0;0;A`n 1:30 GF_STAT;1;2;42;axis;0;1;0;0;20;0;0;A`n")
        $r = Read-GfStatChunk -path $log -offset 0
        Assert-Eq (@($r.lines | Where-Object { $_ }).Count) 2 "two lines"
        Assert-Eq $r.newOffset ((Get-Item $log).Length) "offset at EOF"
    }
    It "leaves a partial trailing line for the next pass" {
        [System.IO.File]::WriteAllText($log, " 1:00 GF_STAT;1;1;42;axis;1;0;0;0;50;0;0;A`n 1:30 GF_STAT;1;2;42;axis;0;1")
        $r = Read-GfStatChunk -path $log -offset 0
        Assert-Eq (@($r.lines | Where-Object { $_ }).Count) 1 "only the complete line"
        $full = [System.Text.Encoding]::UTF8.GetBytes(" 1:00 GF_STAT;1;1;42;axis;1;0;0;0;50;0;0;A`n")
        Assert-Eq $r.newOffset $full.Length "offset stops at the last newline"
    }
    It "resumes from a stored offset without re-reading" {
        [System.IO.File]::WriteAllText($log, "OLD LINE`nNEW LINE`n")
        $old = [System.Text.Encoding]::UTF8.GetBytes("OLD LINE`n").Length
        $r = Read-GfStatChunk -path $log -offset $old
        Assert-Eq (@($r.lines | Where-Object { $_ }) -join '|') 'NEW LINE' "only the new line"
    }
    It "detects rotation by size (ctime unknown: pre-upgrade state) and restarts at zero" {
        [System.IO.File]::WriteAllText($log, "FRESH`n")
        $r = Read-GfStatChunk -path $log -offset 9999
        Assert-Eq (@($r.lines | Where-Object { $_ }) -join '|') 'FRESH' "fresh file read from 0"
        Assert-Eq $r.newOffset ((Get-Item $log).Length) "offset rebuilt against the fresh file"
        Assert-Eq $r.newCtime ((Get-Item $log).CreationTimeUtc.Ticks) "identity learned for next pass"
    }
    It "detects rotation by CREATION TIME even when the fresh file outgrew the old offset" {
        # The size heuristic alone cannot see this: fresh file (6+ bytes) > old offset (5).
        [System.IO.File]::WriteAllText((Join-Path $tmp 'games_mp.log.000'), "SEEN`nMISSED`n")
        [System.IO.File]::WriteAllText($log, "FRESH`n")
        $seen = [System.Text.Encoding]::UTF8.GetBytes("SEEN`n").Length
        $stale = (Get-Item $log).CreationTimeUtc.Ticks - 1   # any ticks != the live file's
        $r = Read-GfStatChunk -path $log -offset $seen -ctime $stale
        $lines = @($r.lines | Where-Object { $_ })
        Assert-True ($lines -contains 'MISSED') "archive tail recovered"
        Assert-True ($lines -contains 'FRESH') "fresh file read too"
        Assert-Eq $r.newCtime ((Get-Item $log).CreationTimeUtc.Ticks) "identity updated"
    }
    It "never reads the LIVE file (or a non-.NNN sibling) as its own archive" {
        # Win32's -Filter 'games_mp.log.*' ALSO matches the extensionless live file, which is
        # always the newest-written -> it used to win the newest-first sort and be recovered as
        # its own archive: the real tail was lost, and its own bytes past $offset were read twice
        # (once as "archive", once from 0) into an accumulator that sums with no dedup.
        # Two independent guards now, so this pins each: .bak fails the suffix rule, the live
        # file fails the path rule. Both decoys are NEWER than the real archive on purpose.
        [System.IO.File]::WriteAllText((Join-Path $tmp 'games_mp.log.000'), "SEEN`nARCHIVED`n")
        [System.IO.File]::WriteAllText((Join-Path $tmp 'games_mp.log.bak'), "SEEN`nDECOY`n")
        [System.IO.File]::WriteAllText($log, "SEEN`nLIVETAIL`n")
        $seen  = [System.Text.Encoding]::UTF8.GetBytes("SEEN`n").Length
        $stale = (Get-Item $log).CreationTimeUtc.Ticks - 1
        $r = Read-GfStatChunk -path $log -offset $seen -ctime $stale
        $lines = @($r.lines | Where-Object { $_ })
        Assert-True ($lines -contains 'ARCHIVED') "recovered from the .NNN archive"
        Assert-True (-not ($lines -contains 'DECOY')) "a non-.NNN sibling is not an archive"
        Assert-Eq (@($lines | Where-Object { $_ -eq 'LIVETAIL' }).Count) 1 "live tail read once, not double-counted"
    }
    It "does NOT rotate on a matching creation time" {
        [System.IO.File]::WriteAllText($log, "A`nB`n")
        $ct = (Get-Item $log).CreationTimeUtc.Ticks
        $a  = [System.Text.Encoding]::UTF8.GetBytes("A`n").Length
        $r  = Read-GfStatChunk -path $log -offset $a -ctime $ct
        Assert-Eq (@($r.lines | Where-Object { $_ }) -join '|') 'B' "tail only, no false rotation"
    }
    It "returns the offset unchanged when the file is missing" {
        $r = Read-GfStatChunk -path (Join-Path $tmp 'nope.log') -offset 7
        Assert-Eq $r.newOffset 7 "offset preserved"
        Assert-Eq (@($r.lines).Count) 0 "no lines"
    }

    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Describe "Read-GfStatState (accumulator load)" {
    $tmp = Join-Path $env:TEMP ("gfstate_test_{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null

    It "round-trips a state written as JSON" {
        $p = Join-Path $tmp 'state.json'
        $obj = [ordered]@{
            offset = 123
            days   = [ordered]@{ '2026-08-14' = [ordered]@{ '42' = [ordered]@{
                k=3; d=1; a=2; hs=1; dmg=430; cap=0; rw=1; mw=1; ml=0; mt=0; rounds=2; name='KL9' } } }
        }
        [System.IO.File]::WriteAllText($p, ($obj | ConvertTo-Json -Depth 6))
        $s = Read-GfStatState $p
        Assert-Eq $s.offset 123 "offset restored"
        Assert-Eq $s.days['2026-08-14']['42'].k 3 "nested stats restored as hashtables"
        Assert-Eq $s.days['2026-08-14']['42'].name 'KL9' "name restored"
        # The merge must be able to ADD to a loaded state (hashtable, not PSCustomObject).
        [void](Merge-GfStatLines -state $s -lines @(' 9:00 GF_STAT;1;9;42;allies;1;0;0;0;10;0;0;KL9') -day '2026-08-14')
        Assert-Eq $s.days['2026-08-14']['42'].k 4 "loaded state accepts merges"
    }
    It "starts fresh on a missing file" {
        $s = Read-GfStatState (Join-Path $tmp 'absent.json')
        Assert-Eq $s.offset 0 "zero offset"
        Assert-Eq $s.days.Count 0 "no days"
    }
    It "starts fresh on an unreadable file instead of throwing" {
        $p = Join-Path $tmp 'corrupt.json'
        [System.IO.File]::WriteAllText($p, '{not json')
        $s = Read-GfStatState $p 3> $null
        Assert-Eq $s.offset 0 "fresh state"
    }

    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
