# verify_zone.ps1 - decide, from an inflated mod.ff zone, whether a spike material/image
# actually shipped - and in WHICH of the three possible shapes. Companion to
# make_material.ps1; full runbook in README.md.
#
# The 2026-07-12 trap this exists to prevent: a build that "works" can still be a silent
# no-op. `image,<name>` built clean back then while writing only a by-name reference
# (+16 bytes, no pixels). So the tests are ordered by proof strength and the interpretation
# is printed with the verdict:
#   A PIXELS  - a >=1KB 0xAB sentinel run / IWi magic inside the zone. Only this proves the
#               image itself was baked into mod.ff.
#   B SIZE    - inflated-size delta vs a baseline zone >= the .iwi payload. Corroborates A.
#   C RECORD  - material + image names present as strings, and the nul-delimited "2d"
#               techset count rose above the baseline's (deployed mod.ff today: exactly 1).
#               Necessary but NOT sufficient - attempt 1 of 2026-07-12 passed C while no-op.
#   D SANITY  - the healthy-build strings are still present; if these are gone the build
#               broke and A-C mean nothing.
#
# C-without-A is not failure: it is the BOCL model (material record in the ff, pixels
# delivered loose beside it) - proceed to the runbook's delivery tests.
#
#   powershell -File verify_zone.ps1 -Zone mod.zone -Name gf_test_brand -Image gf_test `
#       -IwiBytes 65584 [-BaselineZone base.zone]

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Zone,          # inflated zone (tools/inflate_fastfile_zlib.ps1 output)
    [Parameter(Mandatory)][string]$Name,          # spike material name
    [Parameter(Mandatory)][string]$Image,         # spike image name
    [int]$IwiBytes = 0,                           # spike .iwi total size (for the size test)
    [string]$BaselineZone = ''                    # inflated zone of a build WITHOUT the spike entries
)

$ErrorActionPreference = 'Stop'
$b = [System.IO.File]::ReadAllBytes($Zone)
$ascii = [System.Text.Encoding]::ASCII

function Find-Bytes {
    param([byte[]]$Hay, [byte[]]$Pat)
    $hits = 0
    for ($i = 0; $i -le $Hay.Length - $Pat.Length; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $Pat.Length; $j++) { if ($Hay[$i + $j] -ne $Pat[$j]) { $ok = $false; break } }
        if ($ok) { $hits++; $i += $Pat.Length - 1 }
    }
    return $hits
}
function Find-NulDelimited {
    param([byte[]]$Hay, [string]$S)
    # \0<s>\0 - a whole string-table token, not a substring of a longer name
    return (Find-Bytes $Hay ([byte[]]@(0) + $ascii.GetBytes($S) + [byte[]]@(0)))
}

$results = New-Object System.Collections.Generic.List[string]
$fail = $false

# ---- A: PIXELS --------------------------------------------------------------------------
$run = 0; $maxRun = 0
foreach ($byte in $b) { if ($byte -eq 0xAB) { $run++; if ($run -gt $maxRun) { $maxRun = $run } } else { $run = 0 } }
$iwiMagic = Find-Bytes $b ($ascii.GetBytes('IWi'))
$aPass = ($maxRun -ge 1024 -or $iwiMagic -gt 0)
$results.Add(("A PIXELS   {0}   sentinel-run max {1}B, IWi magic x{2}" -f $(if ($aPass) { 'PASS' } else { 'no  ' }), $maxRun, $iwiMagic))

# ---- B: SIZE ----------------------------------------------------------------------------
if ($BaselineZone) {
    $delta = $b.Length - ([System.IO.File]::ReadAllBytes($BaselineZone)).Length
    $bPass = ($IwiBytes -gt 0 -and $delta -ge ($IwiBytes - 48))
    $results.Add(("B SIZE     {0}   delta {1:+#;-#;0}B vs baseline (payload {2}B; 2026-07-12 no-op signature was +16)" -f $(if ($bPass) { 'PASS' } else { 'no  ' }), $delta, ($IwiBytes - 48)))
} else {
    $results.Add("B SIZE     skip  (no -BaselineZone given)")
}

# ---- C: RECORD --------------------------------------------------------------------------
$nameHits = Find-NulDelimited $b $Name
$imgHits  = Find-NulDelimited $b $Image
$twoD     = Find-NulDelimited $b '2d'
$cPass = ($nameHits -gt 0 -and $twoD -gt 1)
$results.Add(("C RECORD   {0}   name x{1}, image x{2}, nul-delimited '2d' x{3} (deployed baseline: exactly 1)" -f $(if ($cPass) { 'PASS' } else { 'FAIL' }), $nameHits, $imgHits, $twoD))
if (-not $cPass) { $fail = $true }

# ---- D: SANITY --------------------------------------------------------------------------
$sane = @('ui_mp/hud_gf.txt', 'maps/mp/gametypes/gf.txt', 'mp/gametypestable.csv', 'GF_TITLE')
$missing = @($sane | Where-Object { (Find-Bytes $b ($ascii.GetBytes($_))) -eq 0 })
if ($missing.Count -gt 0) {
    $results.Add("D SANITY   FAIL  missing: $($missing -join ', ') - the build broke; A-C are meaningless")
    $fail = $true
} else {
    $results.Add("D SANITY   PASS  all healthy-build markers present")
}

""
"zone: $Zone ($($b.Length) bytes)"
$results | ForEach-Object { "  $_" }
""
if ($fail) {
    "VERDICT: build problem - fix D (or C) before interpreting anything else."
    exit 1
} elseif ($aPass) {
    "VERDICT: PIXELS BAKED into mod.ff - the 2026-07-12 reference-only finding is overturned"
    "for this path. mod.ff alone delivers the image; no loose-file delivery needed."
} else {
    "VERDICT: REFERENCE-ONLY (the BOCL model) - the material record shipped, the pixels did"
    "not. This is NOT failure: proceed to the README's delivery tests (loose raw/images and"
    ".iwd) to get the pixels beside the ff, exactly as bo1-competitiveleaguemod ships them."
}
exit 0
