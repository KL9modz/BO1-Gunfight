# iw4_iwi_to_t5.ps1 -- convert an IW4 (Modern Warfare 2) .iwi v8 into a T5 (Black Ops) .iwi v13.
#
# THE SIBLING OF dds_to_iwi.ps1, and the same trick: both files hold the SAME raw DXT blocks, only
# the wrapper differs. No re-encode, no image maths, no quality loss.
#
# WHY IT EXISTS: MW2 keeps its art in loose `main\iw_NN.iwd` zips (BO1 does not), so every MW2
# texture is one `unzip` away -- no fastfile extractor, no Greyhound/Wraith. That makes the whole
# IW4 texture set available as source material, and the first use is the WEAPON CAMOS: MW2 camos
# are single tiling images, exactly the shape a BO1 weaponOptions camo cell wants (see
# docs/notes/mw2-camo-import-iwi-v8-to-v13.md and custom-camos-bocl-architecture.md).
#
#   unzip -j "...\Call of Duty Modern Warfare 2\main\iw_07.iwd" "images/weapon_camo_*" -d art\mw2
#   powershell -File tools\iw4_iwi_to_t5.ps1 -Path art\mw2 -OutDir images -Prefix gf_camo_mw2_
#
# THE TWO HEADERS (v8 is 32 bytes, v13 is 48; iwi_common.ps1 owns the v13 side):
#
#            IW4 v8 (MW2)                          T5 v13 (BO1)
#   0x00     "IWi" + 0x08                          "IWi" + 0x0D
#   0x04     u32 (unused by us)                    format byte, then flags 0xC3
#   0x08     format byte, flags                    u16 width, u16 height
#   0x0A     u16 width, u16 height, u16 depth      u16 depth, u32 0
#   0x10     4x u32 mip END-offsets                8x u32 mip END-offsets
#   payload  0x20                                  0x30
#
# ⚠⚠ MIPS ARE STORED SMALLEST-FIRST IN v8 -- mip 0 (full resolution) is the TAIL of the file, not
#    the head. This is the one fact the whole conversion turns on, and getting it wrong yields a
#    file that is structurally valid and renders as a 1x1-ish smear. The header proves it and this
#    script checks rather than trusts: offsets[0] must equal the file length (= end of mip 0) and
#    offsets[1] must equal filelength - mip0size (= its start). Verified true on all 17 MW2 camo
#    images. A file that disagrees is REFUSED, never guessed at.
#
# ⚠ MIP 0 ONLY, deliberately -- same call as dds_to_iwi.ps1: BOCL's production camos and every camo
#   we ship declare a single level (all eight v13 slots = file size) and render correctly.
# ⚠ DXT only (DXT1/DXT3/DXT5). MW2 also ships uncompressed and ARGB images; those are not a
#   byte-compatible swap and are skipped with a reason rather than mangled.
# ⚠ Output is ALWAYS v13. Art from another CoD packs, deploys and FastDLs perfectly happily, then
#   simply does not render -- the version byte is the only thing that catches it, which is why
#   make_iwd.ps1 gates on it at package time.
#
# Usage:
#   powershell -File tools\iw4_iwi_to_t5.ps1 -Path art\mw2\weapon_camo_woodland.iwi -OutDir images
#   powershell -File tools\iw4_iwi_to_t5.ps1 -Path art\mw2 -OutDir images -Prefix gf_camo_mw2_ -Force

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,          # an .iwi file OR a directory
    [string]$OutDir,                              # default: alongside each source
    [string]$Filter = '*.iwi',
    [string]$Prefix = '',                         # prepended to each output name
    [switch]$Recurse,
    [switch]$Force,                               # overwrite existing output
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# The v13 header shape + the format/block tables, shared with dds_to_iwi, make_camo_iwi,
# preview_iwi and make_iwd's format gate.
. (Join-Path $PSScriptRoot 'iwi_common.ps1')

function Convert-OneIw4Iwi {
    param([string]$Src, [string]$Dst)

    $b = [System.IO.File]::ReadAllBytes($Src)
    if ($b.Length -lt 32) { throw "too small to be an .iwi" }
    if ($b[0] -ne 0x49 -or $b[1] -ne 0x57 -or $b[2] -ne 0x69) { throw "no 'IWi' magic" }
    if ($b[3] -eq 0x0D) { throw "already T5 v13 - nothing to convert" }
    if ($b[3] -ne 0x08) { throw "IWi v$($b[3]); this converts v8 (IW4/MW2) only" }

    $fmt = [byte]$b[8]
    $w   = [int][BitConverter]::ToUInt16($b, 10)
    $h   = [int][BitConverter]::ToUInt16($b, 12)
    if ($w -lt 1 -or $h -lt 1) { throw "bad dimensions (${w}x${h})" }

    $blockBytes = $null
    try { $blockBytes = Get-IwiBlockBytes -Format $fmt } catch { }
    if ($null -eq $blockBytes) {
        throw ("format 0x{0:X2} is not DXT1/3/5 - not a byte-compatible swap" -f $fmt)
    }

    # DXT works in 4x4 blocks; dims pad up, which is what lets non-power-of-two sources through
    # (MW2's 408x152 camo menu swatches convert cleanly).
    $bw = [Math]::Max(1, [Math]::Ceiling($w / 4.0))
    $bh = [Math]::Max(1, [Math]::Ceiling($h / 4.0))
    $mip0 = [int]($bw * $bh * $blockBytes)
    if ($b.Length -lt 32 + $mip0) {
        throw "truncated: need $(32 + $mip0) B for ${w}x${h}, file is $($b.Length) B"
    }

    # ⚠ THE SMALLEST-FIRST CHECK. Do not relax this into "just take the tail" -- the whole point is
    # that the header agrees with the tail, so a file laid out some other way fails loudly here
    # instead of shipping as a silent smear.
    $start = $b.Length - $mip0
    $off0 = [BitConverter]::ToUInt32($b, 16)
    $off1 = [BitConverter]::ToUInt32($b, 20)
    if ($off0 -ne $b.Length) {
        throw "mip end-offset[0] is $off0, expected the file length $($b.Length) - unexpected v8 layout"
    }
    # A single-mip v8 file repeats the file length in every slot (no chain to describe); a chained
    # one names mip 0's start in slot 1. Both are fine, anything else is not.
    if ($off1 -ne $start -and $off1 -ne $off0) {
        throw "mip end-offset[1] is $off1, expected $start (chained) or $off0 (single mip)"
    }

    $iwi = New-IwiBuffer -Width $w -Height $h -PayloadBytes $mip0 -Format $fmt
    [Array]::Copy($b, $start, $iwi, (Get-IwiPayloadOffset), $mip0)
    [System.IO.File]::WriteAllBytes($Dst, $iwi)

    $fmtName = @{ 0x0B = 'DXT1'; 0x0C = 'DXT3'; 0x0D = 'DXT5' }[[int]$fmt]
    return [pscustomobject]@{ W = $w; H = $h; Fmt = $fmtName; Mips = ($start -ne 32); Bytes = $iwi.Length }
}

# ---- gather sources ---------------------------------------------------------------------
$srcs = @()
if (Test-Path -LiteralPath $Path -PathType Leaf) { $srcs = @(Get-Item -LiteralPath $Path) }
elseif (Test-Path -LiteralPath $Path -PathType Container) {
    $srcs = @(Get-ChildItem -LiteralPath $Path -Filter $Filter -File -Recurse:$Recurse)
} else { throw "not found: $Path" }
if (-not $srcs) { throw "no files matched '$Filter' under $Path" }

$ok = 0; $skip = 0; $fail = @()
foreach ($s in $srcs) {
    $name = $Prefix + [System.IO.Path]::GetFileNameWithoutExtension($s.Name) + '.iwi'
    $dir  = if ($OutDir) { $OutDir } else { $s.DirectoryName }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dst = Join-Path $dir $name

    if ((Test-Path -LiteralPath $dst) -and -not $Force) { $skip++; continue }
    if ($WhatIf) { Write-Host "(whatif) $($s.Name) -> $name"; $ok++; continue }

    try {
        $r = Convert-OneIw4Iwi -Src $s.FullName -Dst $dst
        Write-Host ("{0,-40} -> {1,-40} {2} {3}x{4} {5} {6:N0} B" -f `
            $s.Name, $name, $r.Fmt, $r.W, $r.H, $(if ($r.Mips) { 'chained->mip0' } else { 'single-mip' }), $r.Bytes)
        $ok++
    } catch {
        $fail += "$($s.Name): $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host ("converted {0}, skipped {1} (exists; -Force to overwrite), failed {2}" -f $ok, $skip, $fail.Count)
# Non-fatal by design, like dds_to_iwi.ps1: a batch over a whole iwd will always contain
# uncompressed/ARGB images, and one refusal should not abandon the run.
foreach ($f in $fail) { Write-Host "  ! $f" -ForegroundColor Yellow }
