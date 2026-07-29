param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

# Statically validate the curated per-map location table in _gf_locations.gsc.
#
# Why this exists: the table is ~550 hand-pasted lines (recorder output), and its runtime
# validation is deliberately loose — gf_validateCustomLocations only requires >=1 point per
# team, and a malformed line just makes that spawn point silently vanish. The real contract
# every curated map ships is EXACTLY 5 allies + 5 axis per set + 1 OT flag point (the
# recorder emits exactly that; small mode's picker and the health HUD assume it), and the
# only symptom of a hole is "spawns feel wrong on <map>", weeks later. Same commit-time
# discipline as verify_release_strip.ps1 / verify_loadouts.ps1.
#
# Checks:
#   - every map block: exactly 5 allies + 5 axis per set, >=1 set, exactly 1 OT point
#   - the block's `// mp_<name>` header comment matches its `t["mp_<name>"] = e;` key
#     (a paste of one map's recorder block under another map's header is the easy
#     hand-edit accident, and nothing at runtime would notice)
#   - yaw in -180..180 (the recorder emits normalized yaw; anything outside is a typo)
#   - no duplicate map keys; recorder-format lines that fail to parse are ERRORS, not skips
#
# An UNLISTED map is the supported opt-out (stock spawns + native Dom-B OT) — this only
# validates maps that ARE listed.
#
# Usage:  tools\verify_locations.ps1

$GscPath = Join-Path $WorkspaceRoot "maps\mp\gametypes\_gf_locations.gsc"
if (!(Test-Path -LiteralPath $GscPath)) { Write-Host "FAILED -- missing $GscPath" -ForegroundColor Red; exit 1 }

$lines = [System.IO.File]::ReadAllText($GscPath) -split "`n"

# Bound the scan to gf_locationsTable()'s body — the helper definitions (gf_sp/gf_ot/
# gf_spawnSet at column 0) live elsewhere in the file and must not trip the malformed-line
# checks below.
$fnStart = -1; $fnEnd = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($fnStart -lt 0 -and $lines[$i] -match '^gf_locationsTable\s*\(') { $fnStart = $i; continue }
    if ($fnStart -ge 0 -and $lines[$i] -match '^\}') { $fnEnd = $i; break }
}
if ($fnStart -lt 0 -or $fnEnd -le $fnStart) {
    Write-Host "FAILED -- gf_locationsTable() not found in _gf_locations.gsc" -ForegroundColor Red
    exit 1
}

$SpRe = '\[\s*[ax]\.size\s*\]\s*=\s*gf_sp\(\s*\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)\s*;'
$OtRe = 'e\["ot"\]\s*=\s*gf_ot\(\s*\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)\s*,\s*(-?\d+)\s*\)\s*;'

$errors    = @()
$seenKeys  = @{}
$mapCount  = 0
$ptTotal   = 0

$header    = ""      # last `// mp_<name>` comment seen (the block's label)
$inBlock   = $false
$blockLine = 0
$aCount    = 0; $xCount = 0; $setCount = 0; $otCount = 0; $inSet = $false

for ($i = $fnStart + 1; $i -lt $fnEnd; $i++) {
    $line   = $lines[$i]
    $lineNo = $i + 1

    if ($line -match '^\s*//\s*(mp_[a-z0-9_]+)\s*$') { $header = $Matches[1]; continue }

    if ($line -match 'gf_locMapEntry\s*\(\s*\)') {
        if ($inBlock) { $errors += "UNCLOSED BLOCK  :{0}  new map block starts before the one at line {1} was assigned into the table" -f $lineNo, $blockLine }
        $inBlock = $true; $blockLine = $lineNo
        $aCount = 0; $xCount = 0; $setCount = 0; $otCount = 0; $inSet = $false
        continue
    }

    if ($line -match 'set\s*=\s*gf_spawnSet\s*\(\s*\)') {
        if ($inSet) { $errors += "UNCLOSED SET    :{0}  new spawn set starts before the previous one was appended to e[""sets""]" -f $lineNo }
        $inSet = $true; $aCount = 0; $xCount = 0
        continue
    }

    if ($line -match '\bgf_sp\s*\(') {
        $m = [regex]::Match($line, $SpRe)
        if (-not $m.Success) { $errors += "MALFORMED POINT :{0}  gf_sp line does not match the recorder's output shape" -f $lineNo; continue }
        if (-not $inSet)     { $errors += "STRAY POINT     :{0}  gf_sp line outside any spawn set" -f $lineNo }
        if ($line -match '^\s*a\[') { $aCount++ } elseif ($line -match '^\s*x\[') { $xCount++ }
        $ptTotal++
        $yaw = [double]$m.Groups[4].Value
        if ($yaw -lt -180 -or $yaw -gt 180) {
            $errors += "BAD YAW         :{0}  yaw {1} outside -180..180 (the recorder emits normalized yaw -- this is a typo)" -f $lineNo, $yaw
        }
        continue
    }

    if ($line -match 'e\["sets"\]\[') {
        if (-not $inSet) { $errors += "STRAY SET CLOSE :{0}  e[""sets""] append with no open spawn set" -f $lineNo }
        else {
            if ($aCount -ne 5) { $errors += "BAD SET         :{0}  spawn set closes with {1} allies point(s) -- the contract is exactly 5" -f $lineNo, $aCount }
            if ($xCount -ne 5) { $errors += "BAD SET         :{0}  spawn set closes with {1} axis point(s) -- the contract is exactly 5" -f $lineNo, $xCount }
        }
        $inSet = $false; $setCount++
        continue
    }

    if ($line -match '\bgf_ot\s*\(') {
        if (-not [regex]::Match($line, $OtRe).Success) { $errors += "MALFORMED OT    :{0}  gf_ot line does not match the recorder's output shape" -f $lineNo; continue }
        $otCount++
        continue
    }

    if ($line -match 't\["(mp_[a-z0-9_]+)"\]\s*=\s*e\s*;') {
        $key = $Matches[1]
        if (-not $inBlock)          { $errors += "STRAY ASSIGN    :{0}  t[""{1}""] = e with no open map block" -f $lineNo, $key }
        if ($inSet)                 { $errors += "UNCLOSED SET    :{0}  map ""{1}"" assigned while a spawn set is still open" -f $lineNo, $key }
        if ($setCount -lt 1)        { $errors += "NO SETS         :{0}  map ""{1}"" has no spawn sets" -f $lineNo, $key }
        if ($otCount -ne 1)         { $errors += "BAD OT COUNT    :{0}  map ""{1}"" has {2} OT point(s) -- the contract is exactly 1" -f $lineNo, $key, $otCount }
        if ($header -ne "" -and $header -ne $key) {
            $errors += "HEADER MISMATCH :{0}  block labeled ""// {1}"" is assigned to t[""{2}""] -- one map's recorder block pasted under another's header" -f $lineNo, $header, $key
        }
        if ($seenKeys.ContainsKey($key)) { $errors += "DUPLICATE MAP   :{0}  t[""{1}""] assigned twice (first at line {2}) -- the second silently wins" -f $lineNo, $key, $seenKeys[$key] }
        $seenKeys[$key] = $lineNo
        $mapCount++
        $inBlock = $false; $header = ""
        continue
    }
}
if ($inBlock) { $errors += "UNCLOSED BLOCK  :{0}  map block never assigned into the table (t[""...""] = e missing)" -f $blockLine }

if ($mapCount -eq 0) { $errors += "EMPTY TABLE     no map blocks found in gf_locationsTable()" }

# -- Report -----------------------------------------------------------------------
Write-Host "Verifying the curated location table"
Write-Host ("  {0} map(s), {1} spawn point(s)" -f $mapCount, $ptTotal)
Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "FAILED -- the curated table violates its own contract:" -ForegroundColor Red
    Write-Host ""
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
    Write-Host ""
    Write-Host ("{0} problem(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}
Write-Host "OK -- every curated map ships exactly 5+5 spawn points per set and 1 OT point," -ForegroundColor Green
Write-Host "     headers match keys, yaws normalized, no duplicate maps." -ForegroundColor Green
exit 0
