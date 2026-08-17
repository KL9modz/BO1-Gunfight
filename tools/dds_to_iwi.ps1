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

$FourCCMap = @{ 'DXT1' = 0x0B; 'DXT3' = 0x0C; 'DXT5' = 0x0D }   # -> IWi format byte
$BLOCKB = @{ 0x0B = 8;      0x0C = 16;     0x0D = 16 }        # bytes per 4x4 block

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
    if (-not $FourCCMap.ContainsKey($cc)) {
        $pfFlags = [BitConverter]::ToUInt32($b, 80)
        if (($pfFlags -band 0x4) -eq 0) { throw "uncompressed .dds (no FourCC) - needs real encoding, not a header swap" }
        throw "unsupported FourCC '$cc' (only DXT1/DXT3/DXT5)"
    }
    $fmt = $FourCCMap[$cc]

    # DXT works in 4x4 blocks; dims are padded up, which is what makes non-power-of-two
    # sources (e.g. the 1080x1080 Dark Matter art) convert cleanly.
    $bw = [Math]::Max(1, [Math]::Ceiling($w / 4.0))
    $bh = [Math]::Max(1, [Math]::Ceiling($h / 4.0))
    $mip0 = [int]($bw * $bh * $BLOCKB[$fmt])

    # ⚠ The FourCC lookup is $FourCCMap, NOT $FOURCC. PowerShell variable names are
    # CASE-INSENSITIVE, so a local `$fourCC` and a table `$FOURCC` are the SAME variable -- reading
    # the string into it silently destroyed the hashtable, and every conversion died with
    # "[System.String] does not contain a method named 'ContainsKey'".
    if ($b.Length -lt 128 + $mip0) { throw "truncated: need $(128 + $mip0) B for ${w}x${h} $cc, file is $($b.Length) B" }
    if ($w -gt 65535 -or $h -gt 65535) { throw "dimensions exceed the IWi u16 fields" }

    $fileLen = 48 + $mip0
    $iwi = New-Object byte[] $fileLen
    [Array]::Copy([byte[]]@(0x49, 0x57, 0x69, 0x0D, $fmt, 0xC3), $iwi, 6)   # "IWi" v13, fmt, flags
    [Array]::Copy([BitConverter]::GetBytes([uint16]$w), 0, $iwi, 6, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]$h), 0, $iwi, 8, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]1),  0, $iwi, 10, 2)
    for ($m = 0; $m -lt 8; $m++) {
        [Array]::Copy([BitConverter]::GetBytes([uint32]$fileLen), 0, $iwi, 0x10 + 4 * $m, 4)
    }
    [Array]::Copy($b, 128, $iwi, 48, $mip0)
    [System.IO.File]::WriteAllBytes($Dst, $iwi)

    return [pscustomobject]@{ W = $w; H = $h; Fmt = $cc; Bytes = $fileLen }
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
