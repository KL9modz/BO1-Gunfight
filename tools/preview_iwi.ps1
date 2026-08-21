# preview_iwi.ps1 -- decode a BO1 .iwi to PNG so a texture can be LOOKED AT without the game.
#
# Built for the custom-camo work (docs/notes/custom-camos-bocl-architecture.md): a camo is just a
# tiling image, so "is this actually a camo, and what does it look like" is answerable offline.
# Also the sanity check on tools/make_camo_iwi.ps1's output before burning a mod.ff rebuild.
#
# Decodes at BLOCK resolution (1 px per 4x4 DXT block, = a true box-filter downscale to W/4 x H/4)
# by averaging each block's 16 texels. That is deliberate: it is ~16x less work than a full decode,
# it is plenty to judge a tiling pattern, and it sidesteps per-pixel PowerShell loops on a 1024px
# source. Pass -Full for 1:1 if you ever need it.
#
# IWi v13 header: "IWi" + ver(1) + format(1) + flags(1) + u16 w + u16 h + u16 depth + 8 u32 slots.
#   format 0x0B = DXT1 (8-byte blocks, no alpha), 0x0C = DXT3, 0x0D = DXT5 (16-byte, colour at +8)

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$OutFile,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing | Out-Null

# The IWi v13 header shape, shared with the three writers.
. (Join-Path $PSScriptRoot 'iwi_common.ps1')

$b = [System.IO.File]::ReadAllBytes($Path)

# Header parsing (and the block-size table) live in tools\iwi_common.ps1, shared with the three
# writers. Read-IwiHeader reports rather than throwing, so turn its verdict into this tool's throw.
$hdr = Read-IwiHeader -Bytes $b
if (-not $hdr.ok -and $hdr.reason -eq 'not an IWi file') { throw "not an IWi: $Path" }
if (-not $hdr.ok) { throw ("{0}: {1}" -f $Path, $hdr.reason) }

$ver = $hdr.version; $fmt = [byte]$hdr.format
$w = $hdr.width; $h = $hdr.height
switch ($fmt) {
    0x0B { $colorOff = 0; $fmtName = 'DXT1' }
    0x0C { $colorOff = 8; $fmtName = 'DXT3' }
    0x0D { $colorOff = 8; $fmtName = 'DXT5' }
    default { throw ("unsupported IWi format 0x{0:X2} in {1} (only DXT1/3/5)" -f $fmt, $Path) }
}
$blockBytes = Get-IwiBlockBytes -Format $fmt

$bw = [int][Math]::Ceiling($w / 4.0); $bh = [int][Math]::Ceiling($h / 4.0)
$need = (Get-IwiPayloadOffset) + $bw * $bh * $blockBytes
if ($b.Length -lt $need) { throw ("truncated: need $need B for ${w}x${h} $fmtName, file is $($b.Length) B") }

# ⚠ Every element is fully parenthesised. In PowerShell the COMMA binds TIGHTER than arithmetic,
# so `a/31, b/63` parses as `a / (31, b) / 63` -- dividing by an ARRAY, which fails at runtime with
# "[System.Object[]] does not contain a method named 'op_Division'". Same trap in the $p2/$p3
# interpolations below. Do not "tidy" these parens away.
function From565([uint16]$c) {
    $r = (($c -shr 11) -band 0x1F); $g = (($c -shr 5) -band 0x3F); $bl = ($c -band 0x1F)
    return @( (($r * 255 + 15) / 31), (($g * 255 + 31) / 63), (($bl * 255 + 15) / 31) )
}

if ($Full) { $outW = $w; $outH = $h } else { $outW = $bw; $outH = $bh }
$bmp = New-Object System.Drawing.Bitmap($outW, $outH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$rect = New-Object System.Drawing.Rectangle(0, 0, $outW, $outH)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
$stride = $data.Stride
$buf = New-Object byte[] ($stride * $outH)

for ($by = 0; $by -lt $bh; $by++) {
    for ($bx = 0; $bx -lt $bw; $bx++) {
        $o = (Get-IwiPayloadOffset) + (($by * $bw) + $bx) * $blockBytes + $colorOff
        $c0 = [BitConverter]::ToUInt16($b, $o); $c1 = [BitConverter]::ToUInt16($b, $o + 2)
        $idx = [BitConverter]::ToUInt32($b, $o + 4)
        $p0 = From565 $c0; $p1 = From565 $c1

        # DXT5/DXT3 always use the 4-colour interpolation; DXT1 drops to 3-colour+black when c0<=c1.
        $threeMode = ($fmt -eq 0x0B -and $c0 -le $c1)
        if ($threeMode) {
            $p2 = @( (($p0[0] + $p1[0]) / 2), (($p0[1] + $p1[1]) / 2), (($p0[2] + $p1[2]) / 2) )
            $p3 = @(0, 0, 0)
        } else {
            $p2 = @( ((2 * $p0[0] + $p1[0]) / 3), ((2 * $p0[1] + $p1[1]) / 3), ((2 * $p0[2] + $p1[2]) / 3) )
            $p3 = @( (($p0[0] + 2 * $p1[0]) / 3), (($p0[1] + 2 * $p1[1]) / 3), (($p0[2] + 2 * $p1[2]) / 3) )
        }
        $pal = @($p0, $p1, $p2, $p3)

        if ($Full) {
            # ⚠ [Math]::Floor, NOT [int]. PowerShell's [int] cast is BANKER'S ROUNDING, so
            # [int]($t / 4) over t = 0..15 gives 0,0,0,1,1,1,2,2,2,2,2,3,3,3,4,4 instead of four
            # clean rows of four -- every 4th texel row landed in the NEXT block down, painting a
            # regular dot lattice across the whole image. It reads as fine mesh woven into the art,
            # which is how it survived: -Full is the rarely-used path (block mode averages all 16
            # texels and is immune), and it took decoding a camo with a genuinely smooth pattern
            # (the MW2 import) for the lattice to be obviously wrong rather than plausible detail.
            for ($t = 0; $t -lt 16; $t++) {
                $px = $bx * 4 + ($t % 4); $py = $by * 4 + [Math]::Floor($t / 4)
                if ($px -ge $w -or $py -ge $h) { continue }
                $c = $pal[[int](($idx -shr ($t * 2)) -band 3)]
                $q = $py * $stride + $px * 3
                $buf[$q] = [byte]$c[2]; $buf[$q + 1] = [byte]$c[1]; $buf[$q + 2] = [byte]$c[0]
            }
        } else {
            $sr = 0.0; $sg = 0.0; $sb = 0.0
            for ($t = 0; $t -lt 16; $t++) {
                $c = $pal[[int](($idx -shr ($t * 2)) -band 3)]
                $sr += $c[0]; $sg += $c[1]; $sb += $c[2]
            }
            $q = $by * $stride + $bx * 3
            $buf[$q] = [byte][int]($sb / 16); $buf[$q + 1] = [byte][int]($sg / 16); $buf[$q + 2] = [byte][int]($sr / 16)
        }
    }
}

[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $buf.Length)
$bmp.UnlockBits($data)

if (-not $OutFile) { $OutFile = [System.IO.Path]::ChangeExtension($Path, '.png') }
$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ("{0}  ->  {1}   ({2} {3}x{4} v{5}, preview {6}x{7})" -f `
    (Split-Path -Leaf $Path), (Split-Path -Leaf $OutFile), $fmtName, $w, $h, $ver, $outW, $outH)
