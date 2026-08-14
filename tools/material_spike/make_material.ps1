# make_material.ps1 - fabricate a BO1 custom-material triplet (material + material_properties
# + .iwi image) in the exact raw-binary format the community linker packs verbatim.
#
# FORMAT PROVENANCE: reverse-engineered 2026-08-14 from Classixz/bo1-competitiveleaguemod
# ("BOCL", the retail league mod that ships 132 custom images this way) - full parse of all
# 132 material binaries, 132/132 geometry + string round-trip. This generator is VALIDATED
# BYTE-FOR-BYTE against that corpus: regenerating BOCL's `blank`, `icon_x3` and `bo_cl_camo_1`
# reproduces their files exactly (see tools/tests/material_spike.Tests.ps1).
#
# MATERIAL BINARY (2d techset, single colorMap - the HUD-icon shape):
#   [0x40 header][one 12-byte texture entry @0x40][string pool: "2d" name image "colorMap"]
#   Every offset is absolute into the file; little-endian; no padding; no string dedup even
#   when name == image (BOCL's `blank` stores "blank" twice). Only 5 things vary with string
#   length: header+0x04, texEntry+0, texEntry+8, the pool bytes, and the file size.
#   Two 2d families exist, differing only in 4 header constants (sortKey/drawSurf/+0x28):
#     hud   (sortKey 43, drawSurf-hi 0x00200000, +0x28 0x08128965) - HUD icons/ranks/shop
#     decal (sortKey  4, drawSurf-hi 0x00100000, +0x28 0x08128812) - camo carriers/fullscreen
#   Unknown-but-constant fields (+0x24=1, +0x2C=0x0C, sampler 0xE2) are copied verbatim from
#   the corpus - they are cross-correlated constants, not understood semantics.
#
# MATERIAL_PROPERTIES: 16 bytes = u32 0, u32 1, u32 <mirror of material +0x20 = 0 for 2d>,
#   u32 <per-file garbage in BOCL (uninitialized converter memory) - we write zeros>.
#
# IWI (BO1 v13): 48-byte header "IWi\x0D" + fmt 0x0D (DXT5) + flags 0xC3 + u16 w/h + u16
#   depth 1 + u32 0 + 4x u32 mip-end-offsets (= file size: single mip, no chain) + payload
#   (DXT5 = w*h bytes). Payloads: 'sentinel' fills 0xAB - detectable in an inflated zone, the
#   spike's tracer dye; 'transparent' fills 0x00 - an all-zero DXT5 block decodes to alpha 0
#   (the invisible-image trick for hiding stock art, e.g. the net_disconnect plug).
#
# ⚠ The image is NOT embedded in mod.ff by our linker (proven 2026-07-12: reference-only,
#   +16 bytes, no pixels) - and BOCL is built the SAME way (zero image rows in its mod.csv,
#   .iwi shipped loose beside the ff). The material record rides in mod.ff; the pixels ride
#   beside it. Delivery of the loose .iwi on Plutonium T5 is what the spike tests.
#   Full runbook: tools/material_spike/README.md.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,          # material name (what menus/GSC reference)
    [Parameter(Mandatory)][string]$Image,         # image asset name -> images\<Image>.iwi
    [Parameter(Mandatory)][ValidateSet(4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048)][int]$Width,
    [int]$Height = 0,                             # 0 = square (= Width)
    [ValidateSet('hud', 'decal')][string]$Family = 'hud',
    [ValidateSet('sentinel', 'transparent')][string]$Payload = 'sentinel',
    [switch]$SkipIwi,                             # material+props only (image already exists)
    # Output root: materials\, material_properties\ and images\ are created under it.
    # Default = the repo root (two parents up from tools\material_spike\).
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'
if ($Height -eq 0) { $Height = $Width }
if (-not $OutRoot) { $OutRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

# ---- family constants (from the BOCL corpus; never edit without re-validating) ----------
$fam = @{
    hud   = @{ sortKey = 0x2B; drawSurfHi = [uint32]0x00200000; f28 = [uint32]0x08128965 }
    decal = @{ sortKey = 0x04; drawSurfHi = [uint32]0x00100000; f28 = [uint32]0x08128812 }
}[$Family]

$ascii = [System.Text.Encoding]::ASCII

# ---- materials\<Name> -------------------------------------------------------------------
# String pool layout: "2d\0" fixed @0x4C, name @0x4F, image, "colorMap"; file ends at the
# last NUL. The arithmetic law held with 0 deviations over all 66 BOCL 2d materials.
$nameOff = 0x4F
$imgOff  = $nameOff + $Name.Length + 1
$cmOff   = $imgOff + $Image.Length + 1
$size    = $cmOff + 9   # "colorMap" + NUL

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint32]$nameOff)                     # +0x00 material name offset
$bw.Write([uint32]$imgOff)                      # +0x04 colorMap image name offset
$bw.Write([byte]0x00)                           # +0x08 gameFlags (0 for 2d)
$bw.Write([byte]$fam.sortKey)                   # +0x09 sortKey
$bw.Write([byte]0x01); $bw.Write([byte]0x01)    # +0x0A/+0x0B texture atlas 1x1
$bw.Write([uint32]0)                            # +0x0C drawSurf lo (0 in all 132)
$bw.Write([uint32]$fam.drawSurfHi)              # +0x10 drawSurf hi (family constant)
$bw.Write([uint32]0)                            # +0x14 surfaceTypeBits
$bw.Write([uint16]$Width)                       # +0x18 width  - MUST match the .iwi
$bw.Write([uint16]$Height)                      # +0x1A height - MUST match the .iwi
$bw.Write([uint32]0)                            # +0x1C (0 in all 132)
$bw.Write([uint32]0)                            # +0x20 (0 for 2d; mirrored in props dword 3)
$bw.Write([uint32]1)                            # +0x24 (1 in all 132; semantics unknown)
$bw.Write([uint32]$fam.f28)                     # +0x28 converter leftover, family-constant
$bw.Write([uint32]0x0C)                         # +0x2C (0x0C for every 2d material)
$bw.Write([uint16]1)                            # +0x30 textureCount
$bw.Write([uint16]0)                            # +0x32 constantCount
$bw.Write([uint32]0x4C)                         # +0x34 techset "2d" offset (fixed)
$bw.Write([uint32]0x40)                         # +0x38 textureTable offset (fixed)
$bw.Write([uint32]0x4C)                         # +0x3C constantTable offset (= end of texTable)
# texture entry @0x40: typeName("colorMap"), sampler 0xE2, semantic 0x00 (TS_2D), pad, image
$bw.Write([uint32]$cmOff)
$bw.Write([byte]0xE2); $bw.Write([byte]0x00); $bw.Write([uint16]0)
$bw.Write([uint32]$imgOff)
foreach ($s in @('2d', $Name, $Image, 'colorMap')) {
    $bw.Write($ascii.GetBytes($s)); $bw.Write([byte]0)
}
$matBytes = $ms.ToArray()
if ($matBytes.Length -ne $size) { throw "size law violated: wrote $($matBytes.Length), law says $size" }

# ---- material_properties\<Name> ---------------------------------------------------------
$props = New-Object byte[] 16
$props[4] = 1                                   # u32 0, u32 1, u32 0 (2d mirror), u32 0

# ---- images\<Image>.iwi -----------------------------------------------------------------
$iwi = $null
if (-not $SkipIwi) {
    $payloadLen = $Width * $Height              # DXT5 = 1 byte/px (dims >= 4)
    $fileLen = 48 + $payloadLen
    $iwi = New-Object byte[] $fileLen
    $hdr = [byte[]]@(0x49, 0x57, 0x69, 0x0D, 0x0D, 0xC3)   # "IWi" v13, DXT5, flags C3
    [Array]::Copy($hdr, $iwi, 6)
    [Array]::Copy([BitConverter]::GetBytes([uint16]$Width),  0, $iwi, 6, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]$Height), 0, $iwi, 8, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]1),       0, $iwi, 10, 2)
    # EIGHT u32 end-offset slots at 0x10..0x2F, all = file size (single mip, no chain).
    # ⚠ Read off the real corpus bytes - the first recon pass dumped only 32 header bytes and
    # called it four slots; regenerating with 4 diverged from bocl_rank30.iwi at offset 0x20.
    for ($m = 0; $m -lt 8; $m++) {
        [Array]::Copy([BitConverter]::GetBytes([uint32]$fileLen), 0, $iwi, 0x10 + 4 * $m, 4)
    }
    if ($Payload -eq 'sentinel') { for ($i = 48; $i -lt $fileLen; $i++) { $iwi[$i] = 0xAB } }
    # transparent = leave zeros: DXT5 alpha0=alpha1=0, indices 0 -> alpha 0 everywhere
}

# ---- write ------------------------------------------------------------------------------
foreach ($dir in @('materials', 'material_properties') + $(if ($iwi) { , 'images' } else { @() })) {
    $p = Join-Path $OutRoot $dir
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
[System.IO.File]::WriteAllBytes((Join-Path $OutRoot "materials\$Name"), $matBytes)
[System.IO.File]::WriteAllBytes((Join-Path $OutRoot "material_properties\$Name"), $props)
Write-Host ("materials\{0}            {1} bytes ({2} family)" -f $Name, $matBytes.Length, $Family)
Write-Host ("material_properties\{0}  16 bytes" -f $Name)
if ($iwi) {
    [System.IO.File]::WriteAllBytes((Join-Path $OutRoot "images\$Image.iwi"), $iwi)
    Write-Host ("images\{0}.iwi           {1} bytes (DXT5 {2}x{3}, {4} payload)" -f $Image, $iwi.Length, $Width, $Height, $Payload)
}
Write-Host ""
Write-Host "mod.csv line:   material,$Name"
Write-Host "menu/GSC use:   `"$Name`" as an ordinary shader/material name"
