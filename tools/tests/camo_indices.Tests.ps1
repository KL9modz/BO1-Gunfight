# Pester net for the CAMO INDEX SET, which is declared in five places that can silently drift.
#
#   Invoke-Pester tools/tests
#
# THE PROBLEM THIS PINS. Adding a camo is documented as three files (a weaponOptions.csv row, a
# carrier material in mod.csv, the .iwi in images\). But an index also has to be offered by the
# TOOLING before anyone can pick it, and those copies fail SILENTLY and differently:
#   mp/weaponOptions.csv                 the game's own table -- THE AUTHORITY. A cell here is what
#                                        the engine resolves; everything else is a menu of choices.
#   maps/mp/gametypes/_gf_loadouts.gsc   gf_camoPool() -- the rotation. An index missing here just
#                                        never rolls; an index here with no CSV row renders WHITE.
#   tools/rcon/public/app.js             the panel's Force Camo dropdown.
#   tools/loadout_editor/index.html      the editor's CAMO picker.
#   tools/loadout_editor/server.js       the editor's save-time bound. Too low and the editor
#                                        REFUSES a camo the game renders perfectly well.
#
# So the rule this file enforces is one-directional and cheap to reason about: the CSV defines what
# EXISTS; every other surface may offer a subset, and may never offer an index that is not there.
# Labels are deliberately NOT pinned - the panel says "Crimson", the editor says "GF Crimson", and
# both are fine. Only the INDEX SET is shared truth.
#
# ⚠ Assertions are plain `if (...) { throw }` -- Pester 3.4 and 5.x disagree about Should syntax
# (see guards.Tests.ps1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)

function Assert-True($cond, $msg) { if (-not $cond) { throw "ASSERT: $msg" } }

function Get-CsvCamoIndices {
    param([string]$Path)
    $out = @{}
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        # <index>,camo,<imageName>,... -- the camo block of the stock table.
        $m = [regex]::Match($line, '^\s*(\d+)\s*,\s*camo\s*,\s*([^,]*)')
        if ($m.Success) { $out[[int]$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }
    }
    return $out
}

$csvPath = Join-Path $repoRoot 'mp\weaponOptions.csv'
$csv = Get-CsvCamoIndices $csvPath

Describe "mp/weaponOptions.csv - the camo authority" {
    It "parses a contiguous camo block including the custom rows" {
        Assert-True ($csv.Count -ge 30) "expected the stock 0-16 plus our customs, got $($csv.Count) rows"
        Assert-True ($csv.ContainsKey(0) -and $csv.ContainsKey(15)) "stock 0..15 must be present"
        Assert-True ($csv[15] -eq 'gold') "index 15 is gold (the stock ceiling everything else is measured against)"
    }
    It "every custom row (>16) names a gf_camo_* image that actually ships in images\" {
        # The white-camo failure mode: a cell resolves an IMAGE NAME, and nothing hunts the disk
        # for it. A row naming art we do not ship renders flat white in game with no build error.
        $missing = @()
        foreach ($i in ($csv.Keys | Where-Object { $_ -gt 16 })) {
            $img = $csv[$i]
            if ($img -notlike 'gf_camo_*') { $missing += "index ${i}: '$img' is not one of ours"; continue }
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "images\$img.iwi"))) {
                $missing += "index ${i}: images\$img.iwi not found"
            }
        }
        Assert-True ($missing.Count -eq 0) ("custom camo rows with no art: " + ($missing -join '; '))
    }
}

Describe "gf_camoPool() (_gf_loadouts.gsc) - the rotation" {
    $gsc = Get-Content -Raw (Join-Path $repoRoot 'maps\mp\gametypes\_gf_loadouts.gsc')
    $body = [regex]::Match($gsc, '(?ms)^gf_camoPool\(\)\s*\{.*?\n\}').Value
    It "is found in the shipped source" {
        Assert-True ($body.Length -gt 0) "gf_camoPool() not found - renamed?"
    }
    It "every ENABLED index has a weaponOptions row (a pool index with no row renders WHITE)" {
        # Commented-out lines are the documented way to drop a camo from the rotation, so only
        # live `p[p.size] = N;` statements count.
        $bad = @()
        foreach ($line in ($body -split "`n")) {
            if ($line -match '^\s*//') { continue }
            $m = [regex]::Match($line, 'p\[p\.size\]\s*=\s*(\d+)\s*;')
            if (-not $m.Success) { continue }
            $i = [int]$m.Groups[1].Value
            if (-not $csv.ContainsKey($i)) { $bad += $i }
        }
        Assert-True ($bad.Count -eq 0) ("pool indices with no weaponOptions row: " + ($bad -join ', '))
    }
}

Describe "RCON panel Force Camo dropdown (app.js)" {
    $js = Get-Content -Raw (Join-Path $repoRoot 'tools\rcon\public\app.js')
    $block = [regex]::Match($js, "(?ms)n:'gf_force_camo'.*?tip:").Value
    It "is found in the panel source" {
        Assert-True ($block.Length -gt 0) "gf_force_camo row not found - renamed?"
    }
    It "offers no index the game cannot resolve" {
        $bad = @()
        foreach ($m in [regex]::Matches($block, "\['(-?\d+)'\s*,")) {
            $i = [int]$m.Groups[1].Value
            if ($i -lt 0) { continue }              # -1 = "off", not a camo
            if (-not $csv.ContainsKey($i)) { $bad += $i }
        }
        Assert-True ($bad.Count -eq 0) ("panel offers indices with no weaponOptions row: " + ($bad -join ', '))
    }
}

Describe "Loadout editor (index.html CAMO list + server.js bound)" {
    $html = Get-Content -Raw (Join-Path $repoRoot 'tools\loadout_editor\index.html')
    $srv  = Get-Content -Raw (Join-Path $repoRoot 'tools\loadout_editor\server.js')
    $camoLine = [regex]::Match($html, '(?m)^const CAMO\s*=.*$').Value

    It "the picker is found and offers no index the game cannot resolve" {
        Assert-True ($camoLine.Length -gt 0) "CAMO list not found in index.html - renamed?"
        $bad = @()
        foreach ($m in [regex]::Matches($camoLine, '\[(-?\d+)\s*,')) {
            $i = [int]$m.Groups[1].Value
            if ($i -lt 0) { continue }              # -1 = "random per match"
            if (-not $csv.ContainsKey($i)) { $bad += $i }
        }
        Assert-True ($bad.Count -eq 0) ("editor offers indices with no weaponOptions row: " + ($bad -join ', '))
    }

    It "the save-time bound reaches the HIGHEST shipped camo (a low bound silently refuses a real one)" {
        # This is the copy that fails most confusingly: the game renders the camo fine and the
        # editor just will not save it.
        $m = [regex]::Match($srv, 'c\s*<\s*-1\s*\|\|\s*c\s*>\s*(\d+)')
        Assert-True ($m.Success) "the camo range check in server.js was not found - reshaped?"
        $bound = [int]$m.Groups[1].Value
        $maxCsv = ($csv.Keys | Measure-Object -Maximum).Maximum
        Assert-True ($bound -eq $maxCsv) "server.js bound is $bound but the highest weaponOptions camo is $maxCsv"
    }
}
