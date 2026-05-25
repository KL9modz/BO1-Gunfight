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

# ── 5. Config assertions ──────────────────────────────────────────────────
# Parse mp_gunfight.gsc and assert required game rules are set correctly.

Write-Head "── Config assertions"

$cfgPath = Join-Path $ScriptDir "mp_gunfight.gsc"
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw

    function Assert-Source([string]$Pattern, [string]$TestName) {
        if ($cfg -match $Pattern) { Write-Pass $TestName }
        else                      { Write-Fail $TestName }
    }

    Assert-Source 'scr_sd_numlives[^;]+\"1\"'                     'one life per round  (scr_sd_numlives = "1")'
    Assert-Source 'healthRegenDisabled\s*=\s*true'                 'health regen disabled'
    Assert-Source 'playerHealth_RegularRegenDelay\s*=\s*0'         'regen delay zeroed'
    Assert-Source 'killstreaksenabled\s*=\s*0'                     'killstreaks disabled'
    Assert-Source 'compass[^;]+\"0\"'                              'minimap hidden (compass = "0")'
    Assert-Source 'gf_cfg_winLimit\s*=\s*6'                       'win limit = 6'
    Assert-Source 'roundWinLimit\s*=\s*level\.gf_cfg_winLimit'    'roundWinLimit wired to config'
    Assert-Source 'gf_cfg_roundTime\s*=\s*\d+'                    'round time configured'
    Assert-Source 'gf_cfg_roundsPerLoadout\s*=\s*\d+'             'rounds-per-loadout configured'
    Assert-Source 'gf_cfg_roundSwitch\s*=\s*\d+'                  'side-switch interval configured'
    Assert-Source 'onDeadEvent\s*=\s*::gf_onDeadEvent'            'onDeadEvent overridden'
    Assert-Source 'onTimeLimit\s*=\s*::gf_onTimeLimit'            'onTimeLimit overridden'
    Assert-Source 'onGiveLoadout\s*=\s*::gf_onGiveLoadout'        'onGiveLoadout overridden'
    Assert-Source 'replacefunc[^;]+beginClassChoice'               'class select suppressed via replacefunc'
    Assert-Source 'gf_bombSuppress'                                'bomb suppress thread started'
    Assert-Source 'gf_forfeitWatch'                                'forfeit watch thread started'
    Assert-Source 'gf_initLoadouts'                                'loadout pool initialised'
} else {
    Write-Fail "mp_gunfight.gsc not found — skipping config assertions"
}

# ── 6. Loadout pool sanity ─────────────────────────────────────────────────

Write-Head "── Loadout pool sanity"

$loPath = Join-Path $ScriptDir "_gf_loadouts.gsc"
if (Test-Path $loPath) {
    $lo = Get-Content $loPath -Raw

    # count gf_buildSlot calls — should be 22
    $slotCount = ([regex]::Matches($lo, 'gf_buildSlot\s*\(')).Count
    if ($slotCount -eq 22) { Write-Pass "pool has 22 loadout entries" }
    else                    { Write-Fail "pool has $slotCount entries — expected 22" }

    # each weapon class present
    foreach ($weapon in @('famas_mp','mp5k_mp','hk21_mp','l96a1_mp','spas_mp')) {
        if ($lo -match [regex]::Escape($weapon)) { Write-Pass "pool contains $weapon" }
        else                                      { Write-Fail "pool missing $weapon" }
    }

    # shader prefix sanity
    $badShader = [regex]::Matches($lo, '"menu_mp_weapons_[^"]*"') |
        Where-Object { $_.Value -match ' ' }
    if ($badShader.Count -eq 0) { Write-Pass "no spaces in shader names" }
    else                        { Write-Fail "$($badShader.Count) shader name(s) contain spaces" }

    # secondary shaders cover all 4 pistols
    foreach ($shader in @('menu_mp_weapons_python','menu_mp_weapons_colt',
                           'menu_mp_weapons_makarov','menu_mp_weapons_cz75')) {
        if ($lo -match [regex]::Escape($shader)) { Write-Pass "secondary shader $shader present" }
        else                                      { Write-Warn "secondary shader $shader not found" }
    }

    # lethal shaders
    foreach ($shader in @('hud_grenadeicon','hud_satchel_charge','hud_hatchet')) {
        if ($lo -match [regex]::Escape($shader)) { Write-Pass "lethal shader $shader present" }
        else                                      { Write-Warn "lethal shader $shader not found" }
    }
} else {
    Write-Fail "_gf_loadouts.gsc not found — skipping pool sanity"
}

# ── 7. SD conflict checks ────────────────────────────────────────────────
# Verify our round-end paths use the correct SD integration points and
# we never accidentally set bomb state to a non-zero value.

Write-Head "── SD conflict checks"

$roundsPath = Join-Path $ScriptDir "_gf_rounds.gsc"
$mainPath   = Join-Path $ScriptDir "mp_gunfight.gsc"

if (Test-Path $roundsPath) {
    $rd = Get-Content $roundsPath -Raw

    # gf_onDeadEvent must call sd_endgame (not raw endGame)
    if ($rd -match 'gf_onDeadEvent[\s\S]*?sd_endgame') {
        Write-Pass "gf_onDeadEvent routes through sd_endgame"
    } else {
        Write-Fail "gf_onDeadEvent does not call sd_endgame — round scoring will not work"
    }

    # gf_onTimeLimit must call sd_endgame
    if ($rd -match 'gf_onTimeLimit[\s\S]*?sd_endgame') {
        Write-Pass "gf_onTimeLimit routes through sd_endgame"
    } else {
        Write-Fail "gf_onTimeLimit does not call sd_endgame — timeout win will not score"
    }

    # forfeit path must use endGame (NOT sd_endgame — no round score needed)
    if ($rd -match 'gf_forfeitWatch[\s\S]*?endGame\b') {
        Write-Pass "gf_forfeitWatch uses endGame for forfeit (no extra score increment)"
    } else {
        Write-Fail "gf_forfeitWatch missing endGame call"
    }

    # nobody sets bombplanted/bombexploded/bombdefused to a non-zero literal
    $badBomb = [regex]::Matches($rd, 'level\.(bombplanted|bombexploded|bombdefused)\s*=\s*[1-9]')
    if ($badBomb.Count -eq 0) {
        Write-Pass "_gf_rounds.gsc never sets bomb vars to non-zero"
    } else {
        foreach ($m in $badBomb) { Write-Fail "_gf_rounds.gsc sets bomb var to non-zero: $($m.Value)" }
    }

    # gf_onDeadEvent must NOT chain into SD's native onDeadEvent via [[level.onDeadEvent]]()
    if ($rd -match '\[\[\s*level\s*\.\s*onDeadEvent\s*\]\]') {
        Write-Fail "_gf_rounds.gsc chains through [[level.onDeadEvent]] — will double-score rounds"
    } else {
        Write-Pass "no [[level.onDeadEvent]] chain-through detected"
    }
} else {
    Write-Fail "_gf_rounds.gsc not found — skipping SD conflict checks"
}

if (Test-Path $mainPath) {
    $mn = Get-Content $mainPath -Raw

    # Callbacks must all three be wired
    foreach ($cb in @('onDeadEvent','onTimeLimit','onGiveLoadout')) {
        if ($mn -match "level\.$cb\s*=\s*::") {
            Write-Pass "$cb override registered in mp_gunfight.gsc"
        } else {
            Write-Fail "$cb not overridden in mp_gunfight.gsc — SD default will run"
        }
    }

    # replacefunc must target beginClassChoice
    if ($mn -match 'replacefunc[^;]*beginClassChoice') {
        Write-Pass "beginClassChoice suppressed via replacefunc"
    } else {
        Write-Fail "beginClassChoice not suppressed — class select screen will appear"
    }

    # We must not set scr_sd_roundlimit — that would override level.roundWinLimit
    if ($mn -match 'setDvar[^;]*scr_sd_roundlimit') {
        Write-Warn "scr_sd_roundlimit dvar set — SD may override level.roundWinLimit"
    } else {
        Write-Pass "scr_sd_roundlimit not set (roundWinLimit controlled via level var)"
    }
} else {
    Write-Fail "mp_gunfight.gsc not found — skipping SD conflict checks"
}

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
