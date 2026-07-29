param(
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

# Statically prove the PUBLIC build still resolves. Run after touching ANY #strip region.
#
# Why this exists: GSC resolves symbols at COMPILE time, and a strip region that removes a
# function some KEPT code still calls is an "unknown function" that fails the WHOLE server
# -- not just that gametype. There is no compiler to run here (Plutonium compiles the GSC on
# map load), so the failure would first surface as a dead server after a deploy. This closes
# that gap by checking the three ways a strip region can go wrong:
#
#   1. DANGLING CALL   - kept code calls a function whose definition got stripped.
#   2. DANGLING INCLUDE- a kept #include points at a file the public build drops entirely.
#   3. LEAKED DVAR     - a dev-only dvar is still read/written, so a strip region has a hole.
#
# It does NOT prove the GSC parses (no brace/paren checking) -- it proves the SYMBOLS resolve,
# which is the failure mode the strip mechanism actually creates. A real map load is still the
# final word.
#
# Usage:  tools\verify_release_strip.ps1

. (Join-Path $PSScriptRoot "release_common.ps1")

$ModRoot = $WorkspaceRoot

# GSC keywords that a naive "name(" scan would otherwise read as calls. Harmless to leave in
# (they're intersected against the mod's own symbol table below and would never match), but
# excluding them keeps the debug output honest.
$Keywords = @("if", "while", "for", "switch", "return", "wait", "waittill", "notify", "endon", "thread")

# Comment-strip for SCANNING ONLY -- deliberately cruder than the packager's Strip-Comments
# (which produces the shipped text and must respect string literals). Here a "//" inside a
# string literal at worst hides a call from the scan, which can only cost a missed warning,
# never a false alarm. Do NOT reuse this to produce shippable source.
function Remove-CommentsForScan {
    param([string]$Content)
    $t = [regex]::Replace($Content, "(?s)/\*.*?\*/", "")
    $t = [regex]::Replace($t, "(?m)//.*$", "")
    return $t
}

function Get-DefinedFunctions {
    param([string]$Text)
    # A GSC function definition is an identifier at COLUMN 0 followed by "(".
    $names = @()
    foreach ($m in [regex]::Matches($Text, "(?m)^([A-Za-z_][A-Za-z0-9_]*)\s*\(")) {
        $names += $m.Groups[1].Value
    }
    return $names
}

function Get-CalledFunctions {
    param([string]$Text)
    # Bare calls "name(" plus function pointers "::name" (as in level.onSpawnPlayer = ::onSpawnPlayer).
    #
    # Both patterns must ignore FULLY-QUALIFIED stock calls (maps\mp\gametypes\_globallogic::init()),
    # which resolve against the stock script, not ours. The lookbehinds do that: a qualified call has
    # an identifier char immediately before the "::", a function pointer never does (it follows "=",
    # "(", "," or whitespace). Without that, "_globallogic::init" reads as a call to 'init' -- which
    # _bot.gsc happens to define, so it would be reported as a dangling call into stripped code.
    $names = @()
    foreach ($m in [regex]::Matches($Text, "(?<![A-Za-z0-9_:\\])([A-Za-z_][A-Za-z0-9_]*)\s*\(")) {
        $n = $m.Groups[1].Value
        if ($Keywords -contains $n) { continue }
        $names += $n
    }
    foreach ($m in [regex]::Matches($Text, "(?<![A-Za-z0-9_])::\s*([A-Za-z_][A-Za-z0-9_]*)")) {
        $names += $m.Groups[1].Value
    }
    return $names
}

Write-Host "Verifying the public (stripped) build"
Write-Host "Mod: $ModRoot"
Write-Host ""

# -- 1. Every function the mod defines ANYWHERE (incl. dev-only files) -------------
# This is the oracle for "is this identifier a mod function or an engine builtin?". An
# engine builtin (createServerFontString, getDvar, ...) is defined in no mod file, so it
# never enters this set and is never checked -- exactly what we want.
$AllModFunctions = @{}
foreach ($file in (Get-ChildItem -Recurse -File -LiteralPath (Join-Path $ModRoot "maps") -Filter *.gsc)) {
    $text = Remove-CommentsForScan ([System.IO.File]::ReadAllText($file.FullName))
    foreach ($n in (Get-DefinedFunctions $text)) { $AllModFunctions[$n] = $true }
}

# -- 2. The public build: shipped files, with the strip regions removed ------------
$Shipped = Get-ShippedGsc $ModRoot
$PublicText = @{}
$PublicDefined = @{}
foreach ($rel in $Shipped) {
    $full = Join-Path $ModRoot ($rel -replace '/', '\')
    $stripped = Strip-Markers ([System.IO.File]::ReadAllText($full))
    $scan = Remove-CommentsForScan $stripped
    $PublicText[$rel] = $scan
    foreach ($n in (Get-DefinedFunctions $scan)) { $PublicDefined[$n] = $true }
}

Write-Host ("  ships {0} GSC file(s); drops {1}" -f $Shipped.Count, ($script:DevFiles -join ", "))
Write-Host ("  {0} mod function(s) defined in the full source; {1} survive the strip" -f $AllModFunctions.Count, $PublicDefined.Count)
Write-Host ""

$errors = @()

# -- 0. UNBALANCED STRIP MARKERS ----------------------------------------------------
# Checked first because EVERY later check trusts Strip-Markers' output. The regex pairs each
# #strip-begin with the NEXT #strip-end (non-greedy, no nesting) -- so an unmatched BEGIN simply
# never matches and the whole dev region, markers and all, ships in the public build. That is the
# worst failure direction this pipeline has (a silent full leak), and nothing checked it: the
# other checks only notice if the leaked region happens to also break symbol resolution.
# A stray END is the mirror image -- the begin above it may have paired with a LATER end and
# over-stripped PUBLIC code in between. Both directions fail here, on the ORIGINAL text.
foreach ($rel in $Shipped) {
    $full = Join-Path $ModRoot ($rel -replace '/', '\')
    $rawLines = [System.IO.File]::ReadAllText($full) -split "`n"
    $openLine = 0     # 1-based line of the currently open #strip-begin, 0 = none open
    for ($i = 0; $i -lt $rawLines.Count; $i++) {
        if ($rawLines[$i] -match '#strip-begin\b') {
            if ($openLine -ne 0) {
                $errors += "UNBALANCED MARKER {0}:{1}  #strip-begin while the one at line {2} is still open (regions cannot nest)" -f $rel, ($i + 1), $openLine
            }
            $openLine = $i + 1
        }
        if ($rawLines[$i] -match '#strip-end\b') {
            if ($openLine -eq 0) {
                $errors += "UNBALANCED MARKER {0}:{1}  #strip-end with no open #strip-begin -- the begin above it may have paired past this point and over-stripped public code" -f $rel, ($i + 1)
            }
            $openLine = 0
        }
    }
    if ($openLine -ne 0) {
        $errors += "UNBALANCED MARKER {0}:{1}  #strip-begin never closed -- the region does NOT match and the whole dev block LEAKS into the public build" -f $rel, $openLine
    }
}

# -- 3. DANGLING CALLS ------------------------------------------------------------
foreach ($rel in $Shipped) {
    $lines = $PublicText[$rel] -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($n in (Get-CalledFunctions $lines[$i])) {
            if (-not $AllModFunctions.ContainsKey($n)) { continue }   # engine builtin / stock fn
            if ($PublicDefined.ContainsKey($n)) { continue }          # still defined -- fine
            $errors += "DANGLING CALL   {0}:{1}  calls '{2}' -- defined only in stripped/dev code" -f $rel, ($i + 1), $n
        }
    }
}

# -- 4. DANGLING INCLUDES ---------------------------------------------------------
foreach ($rel in $Shipped) {
    foreach ($m in [regex]::Matches($PublicText[$rel], "(?m)^\s*#include\s+([^;]+);")) {
        $inc = ($m.Groups[1].Value.Trim() -replace '\\', '/') + ".gsc"
        if ($script:DevFiles -contains $inc) {
            $errors += "DANGLING INCLUDE {0}  includes '{1}', which the public build drops" -f $rel, $inc
        }
    }
}

# -- 5. LEAKED DVARS --------------------------------------------------------------
# Matches the engine builtins AND every one of the mod's own read wrappers:
#   gf_cfgFloat / gf_cfgInt ( "<dvar>", def, lo, hi )   (_gf_rounds.gsc)
#   gf_seedDvar ( "<dvar>", def )                        (gf.gsc)
# All three seed the dvar if unset, so a surviving call registers the dvar just as a bare
# setDvar would. Scanning only get/setDvar missed that entirely and passed a real leak
# (scr_gf_load_grace, read via gf_cfgFloat from the kept gf_closeGraceEarly) as clean --
# and the alternation itself then went stale the same way, knowing gf_cfgFloat but not the
# later-added gf_cfgInt/gf_seedDvar. If a new read wrapper is ever added, add it here, and
# know that this comment has failed to make that happen once already: grep for
# 'getdvar' inside any new wrapper candidate when touching this file.
#
# Known blind spot, accepted: a call whose dvar name is COMPUTED rather than a string literal
# (e.g. gf_cfgFloat( level.gf_overtimeLimitDvar + "_large", ... )) cannot be resolved statically.
# Every such name in the mod today is a PUBLIC gameplay dvar, so there is nothing to leak.
# The gf_sv_* family is the near-exception (computed reads in dropped files, literal reads
# dev-only) -- any LITERAL gf_sv_ name in a shipped file is a hole, caught by prefix below.
foreach ($rel in $Shipped) {
    $lines = $PublicText[$rel] -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($m in [regex]::Matches($lines[$i], '(?i)\b(?:(?:get|set)Dvar(?:Int|Float)?|gf_cfg(?:Float|Int)|gf_seedDvar)\s*\(\s*"([^"]+)"')) {
            $d = $m.Groups[1].Value
            $hit = $script:StrippedDvars -contains $d
            if (-not $hit) {
                foreach ($p in $script:StrippedDvarPrefixes) {
                    if ($d.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) { $hit = $true; break }
                }
            }
            if ($hit) {
                $errors += "LEAKED DVAR     {0}:{1}  still touches '{2}' -- a strip region has a hole" -f $rel, ($i + 1), $d
            }
        }
    }
}

# -- Report -----------------------------------------------------------------------
if ($errors.Count -gt 0) {
    Write-Host "FAILED -- the public build would not resolve:" -ForegroundColor Red
    Write-Host ""
    foreach ($e in ($errors | Sort-Object -Unique)) { Write-Host "  $e" -ForegroundColor Red }
    Write-Host ""
    Write-Host ("{0} problem(s)." -f ($errors | Sort-Object -Unique).Count) -ForegroundColor Red
    exit 1
}

Write-Host "OK -- every strip marker pairs, every mod function called by the public build is" -ForegroundColor Green
Write-Host "     still defined, no kept #include points at a dropped file, and no dev-only" -ForegroundColor Green
Write-Host "     dvar leaked." -ForegroundColor Green
exit 0
