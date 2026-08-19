param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [switch]$NoTests,
    [switch]$Quick
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# LOCAL TEST BOX - pre-deploy gate.
#
# Everything about this mod that can be proven WITHOUT a running game, run as one
# command, so a deploy to the live VPS is never the first time a mistake is seen.
# It is the static half of the story: the other half is loading the mod on the
# local dedicated server (tools\local\start_local_server.bat) and walking the
# smoke checklist in docs\DEV.md. Neither replaces the other - the verifiers
# prove symbols and data, only a real map load proves the GSC parses.
#
# What it checks, and why each one earns its place:
#   1. VERIFIERS   the three existing static checks. Each covers a failure mode
#                  that is SILENT until it reaches the VPS: a strip region that
#                  removes a function kept code still calls takes the WHOLE
#                  server down on the next map load, and a bad loadout or
#                  location entry just quietly never appears.
#   2. TESTS       the Pester suites + the site's node suites, which pin the
#                  publish guards, the status parser and the stats aggregator.
#   3. ARTIFACTS   mod.ff and mp_gunfight.iwd are BUILD OUTPUTS, gitignored, and
#                  nothing rebuilds them for you. A compiled asset edited without
#                  a rebuild is the classic "I changed it and nothing happened".
#   4. GIT         deploy.ps1 on the box pulls main and takes mod.ff from
#                  origin/release, so anything not pushed simply will not deploy.
#
#   Usage:  .\tools\local\preflight.ps1
#           .\tools\local\preflight.ps1 -Quick     verifiers + artifacts only
#           .\tools\local\preflight.ps1 -NoTests   skip the test suites
#
# Exit code 0 = safe to deploy, 1 = at least one FAIL. WARNs never fail the run:
# they are things that are legitimate in some workflows (an unpushed WIP commit)
# but wrong if you are about to deploy right now.
# ---------------------------------------------------------------------------

if ($Quick) { $NoTests = $true }

$script:Fails = @()
$script:Warns = @()

function Write-Head($t) {
    Write-Host ""
    Write-Host "== $t " -NoNewline -ForegroundColor Cyan
    Write-Host ("=" * [Math]::Max(0, 62 - $t.Length)) -ForegroundColor DarkCyan
}
function Ok($m)   { Write-Host "  [ ok ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow; $script:Warns += $m }
function Fail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:Fails += $m }
function Info($m) { Write-Host "  [ .. ] $m" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  GF PRE-DEPLOY PREFLIGHT" -ForegroundColor White
Write-Host "  repo: $RepoRoot" -ForegroundColor DarkGray

# --- 1. static verifiers ----------------------------------------------------
Write-Head "Static verifiers"
$verifiers = @(
    @{ Name = "release strip"; Script = "verify_release_strip.ps1" },
    @{ Name = "loadout pool";  Script = "verify_loadouts.ps1"      },
    @{ Name = "map locations"; Script = "verify_locations.ps1"     }
)
foreach ($v in $verifiers) {
    $path = Join-Path $RepoRoot "tools\$($v.Script)"
    if (-not (Test-Path -LiteralPath $path)) { Fail "$($v.Name): missing $($v.Script)"; continue }
    Info "$($v.Name) ..."
    # Child process on purpose: these scripts end in `exit`, which would terminate
    # THIS script if they were dot-sourced or called in-process.
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $path 2>&1
    if ($LASTEXITCODE -eq 0) {
        Ok $v.Name
    } else {
        Fail "$($v.Name) (exit $LASTEXITCODE)"
        $out | Select-Object -Last 15 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkRed }
    }
}

# --- 2. test suites ---------------------------------------------------------
if (-not $NoTests) {
    Write-Head "Test suites"

    $testDir = Join-Path $RepoRoot "tools\tests"
    if (Test-Path -LiteralPath $testDir) {
        if (Get-Module -ListAvailable -Name Pester) {
            Info "Pester (tools\tests) ..."
            # In-process is safe here (Invoke-Pester returns, it does not `exit`).
            # The suites use plain if/throw assertions so they run on the inbox
            # Pester 3.4 AND on Pester 5 - see tools\tests\guards.Tests.ps1.
            Import-Module Pester -ErrorAction Stop
            $prev = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $r = Invoke-Pester -Path $testDir -PassThru -Quiet
            } finally { $ErrorActionPreference = $prev }
            if ($r.FailedCount -gt 0) {
                Fail "Pester: $($r.FailedCount) of $($r.TotalCount) test(s) failing"
                $r.TestResult | Where-Object { -not $_.Passed } | Select-Object -First 12 | ForEach-Object {
                    Write-Host "         $($_.Describe) > $($_.Name)" -ForegroundColor DarkRed
                    if ($_.FailureMessage) { Write-Host "           $($_.FailureMessage)" -ForegroundColor DarkRed }
                }
            } else {
                Ok "Pester suites ($($r.TotalCount) tests)"
            }
        } else {
            Warn "Pester not installed - PS test suites skipped (Install-Module Pester)"
        }
    }

    $siteTests = Join-Path $RepoRoot "site\test"
    if (Test-Path -LiteralPath $siteTests) {
        if (Get-Command node -ErrorAction SilentlyContinue) {
            Info "node --test (site\test) ..."
            Push-Location $RepoRoot
            try {
                $out = & node --test "site/test/**/*.test.js" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Ok "site suites"
                } else {
                    Fail "site suites (exit $LASTEXITCODE)"
                    $out | Select-Object -Last 25 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkRed }
                }
            } finally { Pop-Location }
        } else {
            Warn "node not found - site test suites skipped"
        }
    }
}

# --- 3. build artifacts -----------------------------------------------------
Write-Head "Build artifacts"

# Sources the LINKER compiles in. A change to any of these needs build_ff.ps1.
# Pure GSC changes do NOT - GSC loads as loose rawfiles.
$ffSources = @(
    "mod.csv",
    "mp\gametypesTable.csv",
    "mp\weaponOptions.csv",
    "localizedstrings\gf.str",
    "localizedstrings\cgame.str",
    "ui_mp\hud_gf.txt",
    "ui_mp\hud_gf_health.menu",
    "ui_mp\main.menu",
    "ui_mp\scriptmenus\class.menu"
) | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path -LiteralPath $_ }

$efx = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "raw\fx\misc") -Filter *.efx -ErrorAction SilentlyContinue
if ($efx) { $ffSources += $efx.FullName }

$modFf = Join-Path $RepoRoot "mod.ff"
if (-not (Test-Path -LiteralPath $modFf)) {
    Warn "mod.ff absent - build it (tools\build_ff.ps1) before testing menus or strings locally"
} else {
    $ffItem = Get-Item -LiteralPath $modFf
    $newer = @(Get-Item -LiteralPath $ffSources -ErrorAction SilentlyContinue |
               Where-Object { $_.LastWriteTime -gt $ffItem.LastWriteTime })
    if ($newer.Count) {
        Fail "mod.ff is STALE - rebuild with tools\build_ff.ps1. Newer than it:"
        $newer | ForEach-Object {
            Write-Host ("         {0}  ({1:yyyy-MM-dd HH:mm})" -f $_.Name, $_.LastWriteTime) -ForegroundColor DarkRed
        }
    } else {
        Ok ("mod.ff current ({0:yyyy-MM-dd HH:mm}, {1:N0} bytes)" -f $ffItem.LastWriteTime, $ffItem.Length)
    }
}

# The .iwd carries the IMAGES. mod.ff only ever holds a reference to them, so a
# new or edited .iwi that never made it into the .iwd renders as a flat white camo.
$iwd  = Join-Path $RepoRoot "mp_gunfight.iwd"
$iwis = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "images") -Filter *.iwi -ErrorAction SilentlyContinue)
if ($iwis.Count) {
    if (-not (Test-Path -LiteralPath $iwd)) {
        Warn "mp_gunfight.iwd absent but images\*.iwi exist - run tools\make_iwd.ps1"
    } else {
        $iwdTime = (Get-Item -LiteralPath $iwd).LastWriteTime
        $newerImgs = @($iwis | Where-Object { $_.LastWriteTime -gt $iwdTime })
        if ($newerImgs.Count) {
            Fail "mp_gunfight.iwd is STALE ($($newerImgs.Count) newer .iwi) - run tools\make_iwd.ps1"
            $newerImgs | Select-Object -First 8 | ForEach-Object { Write-Host "         $($_.Name)" -ForegroundColor DarkRed }
        } else {
            Ok ("mp_gunfight.iwd current ({0} images)" -f $iwis.Count)
        }
    }
}

# A leftover .new means the last build could NOT overwrite the live .iwd because a
# running game held the handle open - so that build silently did not land.
$iwdNew = Join-Path $RepoRoot "mp_gunfight.iwd.new"
if (Test-Path -LiteralPath $iwdNew) {
    Fail "mp_gunfight.iwd.new exists - the last .iwd build did NOT land (the game held the file open). Close the game and swap it in."
}

# IMAGE FORMAT. An uncompressed 32-bit .iwi (format 0x01) is 4x the bytes of the same
# texture as DXT, and past a certain size the CLIENT REFUSES TO LOAD THE MOD AT ALL:
# it relaunches, gets as far as the menu zones, then hard-hangs with
#   Com_ERROR: Needed to allocate at least 16.0 MB to load images
# and a truncated log. Bisected live 2026-08-18 on the weapon-skin import: 185 images /
# 255 MB loaded fine, and putting back ONE 2048x2048 uncompressed file (16 MB) hung it
# again. So it is a PER-IMAGE ceiling, not aggregate pressure -- trimming the total does
# not help, and the symptom points nowhere near the cause.
#
# > This check does NOT belong in make_iwd.ps1, and that is the whole point: the failure
#   needs no .iwd. The mod FOLDER sits above every stock iw_*.iwd in the client's search
#   path, so a loose images\*.iwi is live on the next level load with nothing packaged
#   ([[mod-folder-is-first-in-client-fs-search-path]]). Packaging is too late to catch it.
#
# Thresholds are anchored to what was MEASURED, not chosen: 1024x1024 uncompressed is
# proven to load (a dozen are live in the playtest branch right now), 2048x2048 is proven
# fatal. Anything uncompressed ABOVE the proven-good size is unproven and the one size
# tested above it killed the client, so it fails; smaller ones only warn, because they
# demonstrably work and are merely wasteful.
# > Compared by PIXELS, not bytes. 1024x1024 uncompressed is 4,194,352 B - a hair OVER
#   4 MB - so a "$mb -gt 4" test fails the very files we proved good. Dimensions are also
#   what was actually measured, so the check says what the evidence says.
# Nothing we author trips either: make_camo_iwi.ps1 emits DXT, and every image main ships
# today is DXT1/DXT5 at 0.5 MB or under.
$iwiCommon = Join-Path $RepoRoot "tools\iwi_common.ps1"
if ($iwis.Count -and (Test-Path -LiteralPath $iwiCommon)) {
    . $iwiCommon
    $UNCOMPRESSED_32 = 0x01
    $PROVEN_GOOD_PX  = 1024 * 1024
    $bad = @(); $waste = @()
    foreach ($f in $iwis) {
        $h = Read-IwiHeader -Path $f.FullName
        if (-not $h.ok -or [int]$h.format -ne $UNCOMPRESSED_32) { continue }
        $px  = [int]$h.width * [int]$h.height
        $row = "{0} ({1:N0} MB, {2}x{3}, uncompressed 32-bit)" -f $f.Name, ($f.Length / 1MB), $h.width, $h.height
        if ($px -gt $PROVEN_GOOD_PX) { $bad += $row } else { $waste += $row }
    }
    if ($bad.Count) {
        Fail "$($bad.Count) uncompressed .iwi larger than 1024x1024 - these HANG THE CLIENT at mod load. Recompress to DXT5 (4x smaller) or drop them:"
        $bad | Select-Object -First 8 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkRed }
    }
    if ($waste.Count) {
        Warn "$($waste.Count) uncompressed .iwi at 1024x1024 or smaller - they load, but cost 4x the VRAM of DXT. Recompress before promoting to main."
    }
    if (-not $bad.Count -and -not $waste.Count) { Ok "image formats ($($iwis.Count) .iwi, all DXT)" }
}
# --- 4. deploy readiness ----------------------------------------------------
Write-Head "Deploy readiness (git)"
Push-Location $RepoRoot
try {
    $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Warn "not a git repo - skipping deploy checks"
    } else {
        if ($branch -ne "main") { Warn "on branch '$branch' - deploy.ps1 pulls 'main'" }
        else { Ok "on main" }

        $dirty = @(& git status --porcelain 2>$null | Where-Object { $_ })
        if ($dirty.Count) {
            Warn "$($dirty.Count) uncommitted change(s) - these will NOT reach the VPS (deploy pulls from origin)"
            $dirty | Select-Object -First 10 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkYellow }
        } else { Ok "working tree clean" }

        & git rev-parse --verify --quiet "origin/$branch" > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ahead = (& git rev-list --count "origin/$branch..HEAD" 2>$null)
            if ([int]$ahead -gt 0) {
                Warn "$ahead commit(s) not pushed - push with tools\push_all.ps1 before deploying"
            } else { Ok "pushed (origin/$branch up to date)" }
        } else {
            Warn "no origin/$branch ref - fetch first to check push state"
        }

        # mod.ff is gitignored on main and reaches the box via origin/release, so a
        # local build is only deployable once it has been published to that branch.
        if (Test-Path -LiteralPath $modFf) {
            $relSize = (& git cat-file -s "origin/release:mod.ff" 2>$null)
            if ($LASTEXITCODE -eq 0 -and $relSize) {
                $localSize = (Get-Item -LiteralPath $modFf).Length
                if ([int64]$relSize -ne [int64]$localSize) {
                    Warn ("origin/release mod.ff differs from local ({0:N0} vs {1:N0} bytes) - publish it to release, or the VPS keeps the old menus and strings" -f [int64]$relSize, $localSize)
                } else {
                    Ok "origin/release mod.ff matches local size"
                }
            } else {
                Info "no origin/release:mod.ff to compare (fetch origin to enable this check)"
            }
        }
    }
} finally { Pop-Location }

# --- summary ----------------------------------------------------------------
Write-Host ""
Write-Host ("-" * 66) -ForegroundColor DarkCyan
if ($script:Fails.Count) {
    Write-Host "  PREFLIGHT FAILED - $($script:Fails.Count) blocking issue(s), $($script:Warns.Count) warning(s)" -ForegroundColor Red
    $script:Fails | ForEach-Object { Write-Host "    FAIL  $_" -ForegroundColor Red }
    Write-Host ""
    exit 1
}
if ($script:Warns.Count) {
    Write-Host "  PREFLIGHT PASSED with $($script:Warns.Count) warning(s)" -ForegroundColor Yellow
    $script:Warns | ForEach-Object { Write-Host "    WARN  $_" -ForegroundColor Yellow }
} else {
    Write-Host "  PREFLIGHT PASSED - clean" -ForegroundColor Green
}
Write-Host ""
Write-Host "  Static checks only. Now load it on the local server:" -ForegroundColor DarkGray
Write-Host "    tools\local\start_local_server.bat" -ForegroundColor DarkGray
Write-Host "  and walk the smoke checklist in docs\DEV.md before deploying." -ForegroundColor DarkGray
Write-Host ""
exit 0
