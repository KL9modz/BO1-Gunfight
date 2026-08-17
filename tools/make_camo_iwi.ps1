# make_camo_iwi.ps1 -- generate a custom weapon-camo .iwi for mp_gunfight.
#
# WHY THIS EXISTS / WHAT A CAMO ACTUALLY IS ON T5 (settled 2026-08-16, see
# docs/notes/custom-camos-bocl-architecture.md):
#   A BO1 camo is ONE TILING IMAGE, not a material and not a per-gun repaint. The engine reads
#   mp/weaponOptions.csv, takes the cell at (camo index, weapon-parent column), and plugs that
#   IMAGE in as the gun material's `colorDetailMap` -- a tiling detail layer over the gun's own
#   colorMap. Proof the cells are images, not materials: stock row 0's cells `cammo_gunmetal` and
#   `cammo_wood_tile_red` exist verbatim as raw/images/*.iwi and as NO material source.
#   That is why one camo covers every weapon, and why this costs an image instead of BOCL's
#   50 weapon-file forks + 61 xmodels.
#
# So the whole recipe is: this script's .iwi  +  one weaponOptions row naming it  +  ship the
# .iwi in mp_gunfight.iwd. No material, no material_properties, no mod.csv `image,` row.
#
# FORMAT: IWi v13, DXT5, flags 0xC3, single mip (all EIGHT u32 end-offset slots = file size).
# Header shape is copied from tools/material_spike/make_material.ps1, which was corpus-validated
# byte-for-byte against BOCL -- and BOCL's own production camo_1.iwi has this identical header
# (`IWi 0d 0d c3`, 1024x1024, 8 slots all = file size), so this is a known-good shape for a CAMO
# specifically, not just for HUD art.
#
# ⚠ DXT5 is 1 byte/texel, so payload = Width*Height and dims must be multiples of 4.
# ⚠ The pattern wraps (all noise sampling is modular) because a detail map TILES across the gun --
#   a non-wrapping pattern shows a visible seam.
#
# Usage:
#   powershell -File tools\make_camo_iwi.ps1 -Preset crimson
#   powershell -File tools\make_camo_iwi.ps1 -Preset solid -Solid "0,180,190" -Name gf_camo_teal
#   powershell -File tools\make_camo_iwi.ps1 -ListPresets

[CmdletBinding()]
param(
    [string]$Preset = 'crimson',
    [string]$Name,                                   # image name; default gf_camo_<preset>
    [ValidateScript({ $_ % 4 -eq 0 })][int]$Width  = 512,
    [ValidateScript({ $_ % 4 -eq 0 })][int]$Height = 512,
    [string]$Solid,                                  # "R,G,B" -- only for -Preset solid
    [int]$Seed = 1337,
    # Blobs ACROSS the texture. This is the blob-size control: 12 = chunky military-ish patches,
    # 40 = fine speckle. ⚠ It is also the noise-grid size, deliberately: the first version kept a
    # fixed 64-cell grid and a `BlobScale` multiplier that TILED it, which SUBSAMPLED 64 cells into
    # ~21 blocks and aliased the whole thing into static -- the generated camos looked like flat
    # noise, not camo. Sampling one cell per >=1 block is what keeps blobs readable.
    [ValidateRange(4, 128)][int]$Blobs = 14,
    [string]$OutRoot,
    [switch]$ListPresets
)

$ErrorActionPreference = 'Stop'

# ⚠ Resolve here, not in the param default: $PSScriptRoot is empty in a param() default under
# `powershell -File`, which made every invocation die on Split-Path.
if (-not $OutRoot) {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $OutRoot = Split-Path -Parent $scriptDir
}

# ---- palettes ---------------------------------------------------------------------------
# 3 tones each, ordered dark -> light. Kept deliberately low-contrast-ish: this is a DETAIL
# layer multiplied over the gun's own texture, so a screaming palette reads as noise in game.
$PRESETS = @{
    'crimson' = @{ desc = 'dark red / oxblood / black'; cols = @(@(18,10,12), @(96,16,22), @(158,34,38)) }
    'teal'    = @{ desc = 'gunfight teal / navy / near-black'; cols = @(@(10,20,26), @(16,74,86), @(28,140,150)) }
    'urban'   = @{ desc = 'grey urban splinter'; cols = @(@(26,26,28), @(88,90,94), @(158,160,164)) }
    'violet'  = @{ desc = 'deep violet / plum'; cols = @(@(20,12,30), @(70,32,104), @(126,72,168)) }
    'sand'    = @{ desc = 'desert sand / khaki'; cols = @(@(60,50,34), @(134,116,80), @(190,174,132)) }
    'toxic'   = @{ desc = 'acid green / black'; cols = @(@(12,20,10), @(52,102,26), @(126,190,48)) }
    # ⚠ 'white' exists because a MISSING camo image renders the gun flat white, the owner liked
    # that look, and shipping it as a deliberate asset is the only safe way to keep it: relying on
    # a failed image load means the look silently changes the moment delivery starts working, and
    # a missing texture is not guaranteed to be white on every client/driver. Near-white rather
    # than pure #FFF -- a camo is a colorDetailMap MULTIPLIED over the gun, so pure white is a
    # no-op that reads as "no camo", while 235-250 keeps the bright look and still shows form.
    'white'   = @{ desc = 'flat near-white (the deliberate version of the missing-texture look)'; cols = @(@(228,232,236), @(240,243,246), @(250,252,255)) }
    'arctic'  = @{ desc = 'white/pale-grey arctic splinter'; cols = @(@(176,184,192), @(214,220,226), @(246,249,252)) }
    # Second wave, 2026-08-16 (owner asked for blue/yellow/orange by name, plus creative extras).
    # Same 3-tone dark->light rule as above. Generate these with DIFFERENT -Blobs values (see the
    # per-preset notes) so the wave reads as different patterns, not one pattern recoloured.
    'blue'    = @{ desc = 'cobalt / navy / near-black (requested)'; cols = @(@(10,16,40), @(24,60,130), @(64,124,205)) }
    'yellow'  = @{ desc = 'wasp yellow / dark bronze (requested)'; cols = @(@(42,34,8), @(140,110,20), @(224,184,40)) }
    'orange'  = @{ desc = 'burnt orange / ember (requested; distinct from SSC "Ember" which is red/black)'; cols = @(@(48,20,6), @(152,72,16), @(232,132,36)) }
    'midnight'= @{ desc = 'near-black blues -- stealth look, reads almost solid at range (use -Blobs 10)'; cols = @(@(8,10,18), @(20,26,44), @(46,56,88)) }
    'copper'  = @{ desc = 'copper / rust / bronze (use -Blobs 18)'; cols = @(@(32,16,10), @(112,60,30), @(184,112,62)) }
    'forest'  = @{ desc = 'deep bottle greens -- the quiet one next to toxic (use -Blobs 12)'; cols = @(@(10,20,12), @(30,60,34), @(72,112,62)) }
    'storm'   = @{ desc = 'blue-grey overcast (use -Blobs 22, finer grain)'; cols = @(@(24,28,34), @(70,80,92), @(132,142,156)) }
    'bubblegum'= @{ desc = 'pink / magenta -- the one loud entry of this wave (use -Blobs 16)'; cols = @(@(62,20,42), @(172,70,122), @(242,142,192)) }
    'solid'   = @{ desc = 'single flat colour (use -Solid "R,G,B")'; cols = $null }
}

if ($ListPresets) {
    Write-Host "Presets:"
    foreach ($k in ($PRESETS.Keys | Sort-Object)) { "  {0,-9} {1}" -f $k, $PRESETS[$k].desc }
    exit 0
}

if (-not $PRESETS.ContainsKey($Preset)) {
    throw "unknown preset '$Preset'. Known: $(($PRESETS.Keys | Sort-Object) -join ', ')"
}
if (-not $Name) { $Name = "gf_camo_$Preset" }

# ---- resolve palette --------------------------------------------------------------------
if ($Preset -eq 'solid') {
    if (-not $Solid) { throw "-Preset solid requires -Solid `"R,G,B`"" }
    $p = $Solid.Split(',') | ForEach-Object { [int]$_.Trim() }
    if ($p.Count -ne 3) { throw "-Solid must be `"R,G,B`"" }
    $palette = @(, $p) * 3
} else {
    $palette = $PRESETS[$Preset].cols
}

function To565([int[]]$c) {
    $r = [int](($c[0] * 31) / 255); $g = [int](($c[1] * 63) / 255); $b = [int](($c[2] * 31) / 255)
    return [uint16](($r -shl 11) -bor ($g -shl 5) -bor $b)
}
$pal565 = @($palette | ForEach-Object { To565 $_ })

# ---- wrapping value noise ---------------------------------------------------------------
# Random lattice + 2 box-blur passes (both wrap), then bilinear sampling. Cheap, and the blur is
# what turns white noise into organic blobs instead of static.
$NG = $Blobs
$rng = New-Object System.Random($Seed)
$noise = New-Object 'double[]' ($NG * $NG)
for ($i = 0; $i -lt $noise.Length; $i++) { $noise[$i] = $rng.NextDouble() }

for ($pass = 0; $pass -lt 2; $pass++) {
    $next = New-Object 'double[]' ($NG * $NG)
    for ($y = 0; $y -lt $NG; $y++) {
        for ($x = 0; $x -lt $NG; $x++) {
            $s = 0.0
            for ($dy = -1; $dy -le 1; $dy++) {
                for ($dx = -1; $dx -le 1; $dx++) {
                    $sx = (($x + $dx) % $NG + $NG) % $NG
                    $sy = (($y + $dy) % $NG + $NG) % $NG
                    $s += $noise[$sy * $NG + $sx]
                }
            }
            $next[$y * $NG + $x] = $s / 9.0
        }
    }
    $noise = $next
}

# renormalise to 0..1 (blurring collapses the range toward 0.5)
$min = [double]::MaxValue; $max = [double]::MinValue
foreach ($v in $noise) { if ($v -lt $min) { $min = $v }; if ($v -gt $max) { $max = $v } }
$span = $max - $min; if ($span -le 0) { $span = 1 }
for ($i = 0; $i -lt $noise.Length; $i++) { $noise[$i] = ($noise[$i] - $min) / $span }

function SampleNoise([double]$u, [double]$v) {
    # u,v in 0..1, wrapping bilinear
    $fx = $u * $NG; $fy = $v * $NG
    $x0 = [int][Math]::Floor($fx); $y0 = [int][Math]::Floor($fy)
    $tx = $fx - $x0; $ty = $fy - $y0
    $x1 = ($x0 + 1) % $NG; $y1 = ($y0 + 1) % $NG
    $x0 = (($x0 % $NG) + $NG) % $NG; $y0 = (($y0 % $NG) + $NG) % $NG
    $a = $noise[$y0 * $NG + $x0]; $b = $noise[$y0 * $NG + $x1]
    $c = $noise[$y1 * $NG + $x0]; $d = $noise[$y1 * $NG + $x1]
    return ($a * (1 - $tx) + $b * $tx) * (1 - $ty) + ($c * (1 - $tx) + $d * $tx) * $ty
}

# ---- build DXT5 payload -----------------------------------------------------------------
# DXT5 block = 16B: [0]a0 [1]a1 [2..7]alpha idx (3b x16) [8..9]c0 565 [10..11]c1 565 [12..15]colour idx (2b x16)
# Opaque everywhere: a0=a1=255 and all alpha indices 0 -> alpha = a0.
$bw = $Width / 4; $bh = $Height / 4
$payloadLen = $Width * $Height
$fileLen = 48 + $payloadLen
$iwi = New-Object byte[] $fileLen

$hdr = [byte[]]@(0x49, 0x57, 0x69, 0x0D, 0x0D, 0xC3)      # "IWi" v13, DXT5, flags C3
[Array]::Copy($hdr, $iwi, 6)
[Array]::Copy([BitConverter]::GetBytes([uint16]$Width),  0, $iwi, 6, 2)
[Array]::Copy([BitConverter]::GetBytes([uint16]$Height), 0, $iwi, 8, 2)
[Array]::Copy([BitConverter]::GetBytes([uint16]1),       0, $iwi, 10, 2)
for ($m = 0; $m -lt 8; $m++) {
    [Array]::Copy([BitConverter]::GetBytes([uint32]$fileLen), 0, $iwi, 0x10 + 4 * $m, 4)
}

$jit = New-Object System.Random(($Seed + 7))
$off = 48
for ($by = 0; $by -lt $bh; $by++) {
    for ($bx = 0; $bx -lt $bw; $bx++) {
        # Straight 0..1 sweep -- one pass over the noise field per texture. The field itself wraps
        # (blur + bilinear both use modular indices), so the result tiles seamlessly without any
        # multiplier, and no aliasing is possible.
        $n = SampleNoise ($bx / [double]$bw) ($by / [double]$bh)

        # quantise into palette bands; keep the neighbouring band as c1 so edge blocks can
        # dither between two tones instead of hard-stepping.
        if ($n -lt 0.38)      { $i0 = 0; $i1 = 1; $edge = ($n -gt 0.30) }
        elseif ($n -lt 0.68)  { $i0 = 1; $i1 = 2; $edge = ($n -gt 0.60) }
        else                  { $i0 = 2; $i1 = 1; $edge = $false }

        $c0 = $pal565[$i0]; $c1 = $pal565[$i1]

        $iwi[$off]     = 0xFF          # alpha0 = opaque
        $iwi[$off + 1] = 0xFF          # alpha1
        # [2..7] stay 0 -> every texel picks alpha0
        [Array]::Copy([BitConverter]::GetBytes($c0), 0, $iwi, $off + 8, 2)
        [Array]::Copy([BitConverter]::GetBytes($c1), 0, $iwi, $off + 10, 2)

        if ($edge) {
            # 2-bit indices, 16 texels: scatter c1 (index 1) into ~half the block to soften the
            # band boundary. Deterministic per block via the jitter RNG.
            $bits = [uint32]0
            for ($t = 0; $t -lt 16; $t++) {
                if ($jit.NextDouble() -lt 0.45) { $bits = $bits -bor ([uint32]1 -shl ($t * 2)) }
            }
            [Array]::Copy([BitConverter]::GetBytes($bits), 0, $iwi, $off + 12, 4)
        }
        # else indices stay 0 -> flat c0 block
        $off += 16
    }
}

# ---- write ------------------------------------------------------------------------------
$imgDir = Join-Path $OutRoot 'images'
if (-not (Test-Path -LiteralPath $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }
$dest = Join-Path $imgDir "$Name.iwi"
[System.IO.File]::WriteAllBytes($dest, $iwi)

Write-Host ("images\{0}.iwi  {1} bytes (DXT5 {2}x{3}, preset '{4}')" -f $Name, $iwi.Length, $Width, $Height, $Preset)
Write-Host ""
Write-Host "weaponOptions.csv row (append to the camo block, col 2 only -- like stock 'gold'):"
Write-Host ("  <index>,camo,{0},,,,,,,,,,,,,,,,,,,,," -f $Name)
Write-Host "Ship the .iwi in mp_gunfight.iwd as images/$Name.iwi (Deflate). No mod.csv row needed."
