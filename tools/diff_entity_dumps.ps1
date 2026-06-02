<#
.SYNOPSIS
    Compares wager vs non-wager entity dumps to identify wager barrier entities.

.DESCRIPTION
    Reads ENT| lines written by _gf_debug.gsc (press F in-game with gf_debug_ents=1).
    Finds all dump sections in the log, lets you pick which two to compare, and reports
    what entities appear ONLY in the wagermatch=1 dump - those are the wager barriers.

    Both dumps can live in the same log file (run them back-to-back in one session).

.PARAMETER Log
    Path to the console log file. Defaults to Plutonium's console_mp.log.

.PARAMETER Map
    Only compare dumps for this map name (e.g. "mp_nuked"). Default: compare all.

.PARAMETER DumpA
    Index (1-based) of the baseline dump to use when multiple are found. Default: 1.

.PARAMETER DumpB
    Index (1-based) of the wager dump to use when multiple are found. Default: 2.

.PARAMETER ShowSame
    Also print entities present in both dumps (verbose).

.EXAMPLE
    # Auto-find log, compare first two dumps found:
    .\diff_entity_dumps.ps1

    # Filter to Nuketown, compare dumps 1 and 2:
    .\diff_entity_dumps.ps1 -Map mp_nuked

    # Use a specific log file:
    .\diff_entity_dumps.ps1 -Log "C:\path\to\console_mp.log"
#>
param(
    [string]$Log     = "$env:LOCALAPPDATA\Plutonium\storage\t5\mods\mp_gunfight\games_mp.log",
    [string]$Map     = "",
    [int]   $DumpA   = 1,
    [int]   $DumpB   = 2,
    [switch]$ShowSame
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# ── Load log ────────────────────────────────────────────────────────────────

if (-not (Test-Path -LiteralPath $Log)) {
    Write-Error "Log file not found: $Log`nRun the game with gf_debug_ents=1, spawn in, then type [set gf_do_dump 1] in console."
    exit 1
}

$lines = Get-Content -LiteralPath $Log -Encoding UTF8

# ── Parse all dump sections ──────────────────────────────────────────────────

$dumps      = @()   # array of hashtables: { Header, Map, Wager, Entities[] }
$inDump     = $false
$currentDump = $null

foreach ($line in $lines) {
    # games_mp.log prefixes every logString() line with "M:SS " — strip it
    $line = $line -replace '^\s*\d+:\d+\s+', ''
    $line = $line.Trim()

    if ($line -match '^=== ENTITY DUMP: (\S+)\s+wagermatch=(\d+)\s+count=(\d+) ===') {
        $currentDump = @{
            Map      = $Matches[1]
            Wager    = [int]$Matches[2]
            Count    = [int]$Matches[3]
            Entities = [System.Collections.Generic.List[string]]::new()
        }
        $inDump = $true
        continue
    }

    if ($line -eq '=== END DUMP ===' -and $inDump) {
        $dumps += $currentDump
        $inDump = $false
        $currentDump = $null
        continue
    }

    if ($inDump -and $line -match '^ENT\|') {
        # Strip the index (field 1) - it shifts when entities differ between runs.
        # Keep: classname | targetname | model | origin
        $parts = $line -split '\|', 6
        if ($parts.Count -ge 6) {
            $key = "$($parts[2])|$($parts[3])|$($parts[4])|$($parts[5])"
            $currentDump.Entities.Add($key)
        }
    }
}

if ($dumps.Count -eq 0) {
    Write-Error "No entity dumps found in log.`nPress F in-game (gf_debug_ents=1) to generate dumps, then re-run this script."
    exit 1
}

# ── Filter by map if requested ───────────────────────────────────────────────

$filtered = $dumps
if ($Map -ne "") {
    $filtered = @($dumps | Where-Object { $_.Map -eq $Map })
    if ($filtered.Count -eq 0) {
        Write-Error "No dumps found for map '$Map'. Available maps: $(($dumps | Select-Object -ExpandProperty Map -Unique) -join ', ')"
        exit 1
    }
}

# ── List available dumps ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "Found $($filtered.Count) dump(s):" -ForegroundColor Cyan
for ($i = 0; $i -lt $filtered.Count; $i++) {
    $d = $filtered[$i]
    $tag = if ($d.Wager -eq 0) { "no-dvar  " } else { "DVAR=1   " }
    Write-Host ("  [{0}] {1} {2,-20}  {3} entities" -f ($i+1), $tag, $d.Map, $d.Count)
}
Write-Host ""

if ($filtered.Count -lt 2) {
    Write-Host "Need at least 2 dumps to compare." -ForegroundColor Yellow
    Write-Host "Run the game twice (once without dvar, once with set xblive_wagermatch 1) and press F each time."
    exit 0
}

# ── Select dumps to diff ─────────────────────────────────────────────────────

$idxA = $DumpA - 1
$idxB = $DumpB - 1

if ($idxA -lt 0 -or $idxA -ge $filtered.Count) { $idxA = 0 }
if ($idxB -lt 0 -or $idxB -ge $filtered.Count) { $idxB = [Math]::Min(1, $filtered.Count - 1) }

$dumpA = $filtered[$idxA]
$dumpB = $filtered[$idxB]

$labelA = "Dump $($idxA+1) [map=$($dumpA.Map) wagermatch=$($dumpA.Wager)]"
$labelB = "Dump $($idxB+1) [map=$($dumpB.Map) wagermatch=$($dumpB.Wager)]"

Write-Host "Comparing:" -ForegroundColor Cyan
Write-Host "  A (baseline): $labelA"
Write-Host "  B (wager)   : $labelB"
Write-Host ""

# ── Diff ─────────────────────────────────────────────────────────────────────

$setA = [System.Collections.Generic.HashSet[string]]::new($dumpA.Entities)
$setB = [System.Collections.Generic.HashSet[string]]::new($dumpB.Entities)

$onlyInB  = @($dumpB.Entities | Where-Object { -not $setA.Contains($_) })  # wager barriers
$onlyInA  = @($dumpA.Entities | Where-Object { -not $setB.Contains($_) })  # deleted by wager
$inBoth   = @($dumpA.Entities | Where-Object {      $setB.Contains($_) })

# ── Report ───────────────────────────────────────────────────────────────────

$header = "{0,-22} {1,-22} {2,-40} {3}"

Write-Host ("=" * 100)
if ($onlyInB.Count -eq 0) {
    Write-Host "NO NEW ENTITIES in wager dump - barriers are compiled BSP, not GSC-accessible." -ForegroundColor Red
    Write-Host "There is no scripted path to activating them without xblive_wagermatch=1."
} else {
    Write-Host "WAGER-ONLY ENTITIES (only in dump B - these are the barriers):" -ForegroundColor Green
    Write-Host ($header -f "classname", "targetname", "model", "origin")
    Write-Host ("-" * 100)
    foreach ($e in ($onlyInB | Sort-Object)) {
        $p = $e -split '\|', 4
        Write-Host ($header -f $p[0], $p[1], $p[2], $p[3])
    }
}
Write-Host ""

if ($onlyInA.Count -gt 0) {
    Write-Host "DELETED BY WAGER (in A but not B - removed when wagermatch=1):" -ForegroundColor Yellow
    Write-Host ($header -f "classname", "targetname", "model", "origin")
    Write-Host ("-" * 100)
    foreach ($e in ($onlyInA | Sort-Object)) {
        $p = $e -split '\|', 4
        Write-Host ($header -f $p[0], $p[1], $p[2], $p[3])
    }
    Write-Host ""
}

if ($ShowSame) {
    Write-Host "COMMON ENTITIES ($($inBoth.Count)):" -ForegroundColor Gray
    foreach ($e in ($inBoth | Sort-Object)) {
        $p = $e -split '\|', 4
        Write-Host ($header -f $p[0], $p[1], $p[2], $p[3])
    }
    Write-Host ""
}

Write-Host ("=" * 100)
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "  A entity count : $($dumpA.Count)"
Write-Host "  B entity count : $($dumpB.Count)"
Write-Host "  Common         : $($inBoth.Count)"
$barrierColor = if ($onlyInB.Count -gt 0) { "Green" } else { "Red" }
Write-Host "  Only in B (wager barriers)   : $($onlyInB.Count)" -ForegroundColor $barrierColor
Write-Host "  Only in A (deleted by wager) : $($onlyInA.Count)"
Write-Host ""

if ($onlyInB.Count -gt 0) {
    Write-Host "NEXT STEP:" -ForegroundColor Cyan
    Write-Host "  Barrier entities found - can be replicated in gf_applyWagerMapAssets()."
    Write-Host "  classname = script_brushmodel -> spawncollision with the model name"
    Write-Host "  classname = trigger_hurt      -> spawn a trigger_hurt at that origin"
    Write-Host "  classname = script_model      -> move into position + makesolid"
} else {
    Write-Host "NEXT STEP:" -ForegroundColor Cyan
    Write-Host "  No entity diff - barriers are compiled into BSP, unreachable from GSC."
    Write-Host "  Options:"
    Write-Host "    1. Spawn-restriction-only approach (already implemented)"
    Write-Host "    2. Use Radiant to place clip brushes in a custom map"
}
