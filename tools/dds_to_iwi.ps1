# dds_to_iwi.ps1 -- convert a DXT-compressed .dds into a T5 .iwi, header swap only.
#
# WHY THIS IS EASY: both formats store the SAME raw DXT block payload; only the wrapper differs.
#   .dds  = 4-byte magic "DDS " + 124-byte DDS_HEADER (+20 more if the DX10 extension)  -> blocks
#   .iwi  = 48-byte IWi header                                                          -> blocks
# So conversion is: read dims + FourCC, write our header, copy mip 0 through. No image maths, no
# re-encoding, no quality loss, and no need to run the unsigned Converter.exe that ships inside the
# community art packs (86 copies of it in ReealithysBlackOps1 alone).
#
# WHAT THIS UNLOCKS: community retexture packs are distributed as .dds SOURCE art (e.g.
# CUSTOM ASSETS\completes-pack-full-dds -- 21,587 .dds laid out as iw_NN\images\, including the
# whole tiling camo set: camo_desert_nevada.dds, cammo_wood_tile_red.dds, ...). Converted, those
# drop straight into our camo pipeline (docs/notes/custom-camos-bocl-architecture.md).
#
# ⚠ MIP 0 ONLY, deliberately. The IWi header's eight u32 slots are mip END-OFFSETS; a stock T5
#   image carries a full descending chain, but BOCL's production camos (and every camo we ship)
#   set all eight to the file size = a single level, and those render correctly. Copying mip 0 and
#   declaring one level is the shape we have proven; re-deriving a chain is unnecessary risk for a
#   texture that tiles.
# ⚠ Output is ALWAYS IWi v13 (T5). Plutonium: "textures only work on the game they were created
#   for, the .iwi version is different between games." make_iwd.ps1 enforces v13 at package time.
# ⚠ DXT only (DXT1/3/5). A DX10-header or uncompressed .dds is REFUSED rather than mangled --
#   BC7/RGBA payloads are not a byte-compatible swap and would render as garbage.
#
# Usage:
#   powershell -File tools\dds_to_iwi.ps1 -Path art\camo.dds                      # -> art\camo.iwi
#   powershell -File tools\dds_to_iwi.ps1 -Path "...\iw_01\images" -Recurse -OutDir images
#   powershell -File tools\dds_to_iwi.ps1 -Path X -Filter "camo_*.dds" -Prefix gf_camo_ -WhatIf

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,          # a .dds file OR a directory
    [string]$OutDir,                              # default: alongside each source
    [string]$Filter = '*.dds',
    [string]$Prefix = '',                         # prepended to each output name
    [switch]$Recurse,
    [switch]$Force,                               # overwrite existing .iwi
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# The IWi v13 header shape + the FourCC/block-size tables, shared with make_camo_iwi.ps1 and
# material_spike\make_material.ps1 (Get-IwiFormatByte / Get-IwiBlockBytes / New-IwiBuffer).
. (Join-Path $PSScriptRoot 'iwi_common.ps1')

function Convert-OneDds {
    param([string]$Src, [string]$Dst)

    $b = [System.IO.File]::ReadAllBytes($Src)
    if ($b.Length -lt 128) { throw "too small to be a .dds" }
    if ($b[0] -ne 0x44 -or $b[1] -ne 0x44 -or $b[2] -ne 0x53 -or $b[3] -ne 0x20) { throw "no 'DDS ' magic" }
    if ([BitConverter]::ToUInt32($b, 4) -ne 124) { throw "bad DDS_HEADER size" }

    $h = [BitConverter]::ToUInt32($b, 12)          # dwHeight
    $w = [BitConverter]::ToUInt32($b, 16)          # dwWidth
    $cc = [Text.Encoding]::ASCII.GetString($b, 84, 4)

    if ($cc -eq 'DX10') { throw "DX10-extension .dds (likely BC7/typed) - not a byte-compatible swap" }
    $fmt = Get-IwiFormatByte -FourCC $cc
    if ($null -eq $fmt) {
        $pfFlags = [BitConverter]::ToUInt32($b, 80)
        if (($pfFlags -band 0x4) -eq 0) { throw "uncompressed .dds (no FourCC) - needs real encoding, not a header swap" }
        throw "unsupported FourCC '$cc' (only DXT1/DXT3/DXT5)"
    }

    # DXT works in 4x4 blocks; dims are padded up, which is what makes non-power-of-two
    # sources (e.g. the 1080x1080 Dark Matter art) convert cleanly.
    $bw = [Math]::Max(1, [Math]::Ceiling($w / 4.0))
    $bh = [Math]::Max(1, [Math]::Ceiling($h / 4.0))
    $mip0 = [int]($bw * $bh * (Get-IwiBlockBytes -Format $fmt))

    # ⚠ Both lookup tables now live in iwi_common.ps1 behind Get-IwiFormatByte / Get-IwiBlockBytes,
    # which also retires a trap worth remembering: PowerShell variable names are CASE-INSENSITIVE,
    # so the old local `$cc` string and a table named `$CC` would have been the SAME variable --
    # that is how an earlier version silently overwrote its own hashtable and died with
    # "[System.String] does not contain a method named 'ContainsKey'". Function calls cannot collide
    # with a local the way a bare table variable can.
    if ($b.Length -lt 128 + $mip0) { throw "truncated: need $(128 + $mip0) B for ${w}x${h} $cc, file is $($b.Length) B" }

    # Header shape lives in tools\iwi_common.ps1, shared with make_camo_iwi + material_spike (and
    # pinned by the corpus byte-compare in material_spike.Tests.ps1). This is the one caller that
    # passes a format other than DXT5 through.
    $iwi = New-IwiBuffer -Width $w -Height $h -PayloadBytes $mip0 -Format $fmt
    [Array]::Copy($b, 128, $iwi, (Get-IwiPayloadOffset), $mip0)
    [System.IO.File]::WriteAllBytes($Dst, $iwi)

    return [pscustomobject]@{ W = $w; H = $h; Fmt = $cc; Bytes = $iwi.Length }
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
        $r = Convert-OneDds -Src $s.FullName -Dst $dst
        Write-Host ("{0,-44} -> {1,-40} {2} {3}x{4} {5:N0} B" -f $s.Name, $name, $r.Fmt, $r.W, $r.H, $r.Bytes)
        $ok++
    } catch {
        $fail += "$($s.Name): $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host ("converted {0}, skipped {1} (exists; -Force to overwrite), failed {2}" -f $ok, $skip, $fail.Count)
# Non-fatal by design: a batch over a whole pack will always contain a few uncompressed or
# DX10 textures, and one of those must not abort the other 500.
foreach ($f in $fail) { Write-Warning $f }
