# tools/lint.ps1 — T5 GSC static linter
# Usage: .\tools\lint.ps1
# Exit 0 = clean, Exit 1 = errors found

param(
    [string]$ScriptDir = "$PSScriptRoot\..\raw\scripts\mp"
)

$files = @(
    "mp_gunfight.gsc",
    "_gf_rounds.gsc",
    "_gf_loadouts.gsc",
    "_gf_hud.gsc"
)

$errorCount = 0
$warnCount  = 0

function Write-Pass  { param($msg) Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Write-Fail  { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red;    $script:errorCount++ }
function Write-Warn  { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow; $script:warnCount++ }
function Write-Head  { param($msg) Write-Host "`n$msg" -ForegroundColor Cyan }

# ── 1. File existence ──────────────────────────────────────────────────────

Write-Head "── File existence"
foreach ($f in $files) {
    $path = Join-Path $ScriptDir $f
    if (Test-Path $path) { Write-Pass $f }
    else                 { Write-Fail "$f not found at $path" }
}

# ── 2. Banned T5 patterns ─────────────────────────────────────────────────

$banned = @(
    @{ Re = 'getPlayers\s*\(\s*\)';          Msg = 'getPlayers() broken in T5 — use level.players' },
    @{ Re = 'spawnStruct\s*\(\s*\)';         Msg = 'spawnStruct() broken in T5 — use associative array []' },
    @{ Re = '\bisAlive\s*\(';               Msg = 'isAlive() broken in T5 — use .health > 0' },
    @{ Re = '\bforeach\s*\(';               Msg = 'foreach broken in T5 — use for(i=0; i<arr.size; i++)' },
    @{ Re = '(?<!\bpers\["team"\])\b\w+\.team\b(?!ed|Based|Score|Scores|name|Name)';
                                             Msg = 'player.team broken in T5 — use player.pers["team"]' },
    @{ Re = 'level\s+setClientField';        Msg = 'setClientField has no T5 equivalent' },
    @{ Re = 'level\.disableclassselection';  Msg = 'disableclassselection ignored — use replacefunc on beginClassChoice' },
    @{ Re = 'GiveWeapon\s*\([^)]+,\s*\d+';  Msg = 'GiveWeapon with numeric 3rd arg is T6 camo — omit in T5' },
    @{ Re = '"\s*\+\s*"\+[a-z]';            Msg = 'possible T6 attachment format (+reflex) — use _reflex_mp suffix in T5' }
)

Write-Head "── Banned T5 patterns"
foreach ($f in $files) {
    $path = Join-Path $ScriptDir $f
    if (-not (Test-Path $path)) { continue }
    $lines = Get-Content $path
    $fileClean = $true
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # skip comment lines
        if ($line -match '^\s*//') { continue }
        foreach ($b in $banned) {
            if ($line -match $b.Re) {
                Write-Fail "${f}:$($i+1) — $($b.Msg)"
                $fileClean = $false
            }
        }
    }
    if ($fileClean) { Write-Pass "$f — no banned patterns" }
}

# ── 3. Include chain validation ───────────────────────────────────────────

Write-Head "── Include chain"

function Get-Includes([string]$path) {
    $result = @()
    foreach ($line in (Get-Content $path -ErrorAction SilentlyContinue)) {
        if ($line -match '#include\s+([\w\\]+)\s*;') {
            # take last segment of path as filename
            $seg = $matches[1] -replace '.*[\\\/]', ''
            $result += $seg
        }
    }
    return $result
}

foreach ($f in $files) {
    $path = Join-Path $ScriptDir $f
    if (-not (Test-Path $path)) { continue }
    $incs = Get-Includes $path
    if ($incs.Count -eq 0) {
        Write-Pass "$f — no includes"
        continue
    }
    foreach ($inc in $incs) {
        $incPath = Join-Path $ScriptDir "$inc.gsc"
        if (Test-Path $incPath) { Write-Pass "$f includes $inc.gsc — found" }
        else                    { Write-Fail "$f includes $inc.gsc — FILE NOT FOUND" }
    }
}

# ── 4. gf_* function cross-reference ─────────────────────────────────────

Write-Head "── gf_* function cross-reference"

# build map: funcName -> declaring file
$declared = @{}
foreach ($f in $files) {
    $path = Join-Path $ScriptDir $f
    if (-not (Test-Path $path)) { continue }
    foreach ($line in (Get-Content $path)) {
        if ($line -match '^(gf_\w+)\s*\(') {
            $declared[$matches[1]] = $f
        }
    }
}

# build transitive include chain per file
function Get-IncludeChain([string]$f, [string]$dir, [int]$depth = 0) {
    if ($depth -gt 5) { return @() }
    $path  = Join-Path $dir $f
    $chain = @($f)
    foreach ($inc in (Get-Includes $path)) {
        $chain += Get-IncludeChain "$inc.gsc" $dir ($depth + 1)
    }
    return $chain | Select-Object -Unique
}

$allCallsClean = $true
foreach ($f in $files) {
    $path = Join-Path $ScriptDir $f
    if (-not (Test-Path $path)) { continue }

    $chain = Get-IncludeChain $f $ScriptDir

    $lines = Get-Content $path
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*//') { continue }
        $calls = [regex]::Matches($line, '\b(gf_\w+)\s*\(')
        foreach ($m in $calls) {
            $name = $m.Groups[1].Value
            if (-not $declared.ContainsKey($name)) {
                Write-Fail "${f}:$($i+1) — $name() called but not declared in any file"
                $allCallsClean = $false
            } elseif ($chain -notcontains $declared[$name]) {
                Write-Fail "${f}:$($i+1) — $name() declared in $($declared[$name]) but that file is not in the include chain"
                $allCallsClean = $false
            }
        }
    }
}
if ($allCallsClean) { Write-Pass "all gf_* calls resolve in include chain" }

# ── Summary ───────────────────────────────────────────────────────────────

Write-Host ""
if ($errorCount -eq 0 -and $warnCount -eq 0) {
    Write-Host "CLEAN — no issues found" -ForegroundColor Green
} elseif ($errorCount -eq 0) {
    Write-Host "WARNINGS: $warnCount  errors: 0" -ForegroundColor Yellow
} else {
    Write-Host "ERRORS: $errorCount  warnings: $warnCount" -ForegroundColor Red
}

exit ([int]($errorCount -gt 0))
