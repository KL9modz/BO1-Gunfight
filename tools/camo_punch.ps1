# Sharpen/punch a DXT1 camo tile WITHOUT re-encoding, by working in block space.
#   -Tile2x     : 2x2 the 32x32 block grid into 64x64 -> a 256^2 image whose pattern repeats twice
#                 as often. Pure block copy: ZERO quality loss, and a seamless tile stays seamless.
#   -Contrast k : push each block's two 565 endpoints apart around their midpoint (k>1 = punchier).
#   -Bright b   : scale both endpoints (b>1 = lifts highlights, the cheap "gloss" read).
# ⚠ DXT1 has a MODE BIT: c0 > c1 (as packed u16) = 4-colour, c0 <= c1 = 3-colour+black. A transform
#   that flips that order changes how the block DECODES, so any block that would flip is left
#   untouched and counted.
param([Parameter(Mandatory)][string]$In,[Parameter(Mandatory)][string]$Out,
      [double]$Contrast=1.0,[double]$Bright=1.0,[int]$TileN=1)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) 'iwi_common.ps1')
$b=[IO.File]::ReadAllBytes($In)
$h=Read-IwiHeader -Bytes $b; if(-not $h.ok){throw $h.reason}
if($h.format -ne 0x0B){throw "DXT1 only (got 0x$('{0:X2}' -f $h.format))"}
$w=$h.width;$hh=$h.height;$bw=$w/4;$bh=$hh/4;$off=Get-IwiPayloadOffset
function From565([uint16]$c){ ,@( (((($c -shr 11) -band 0x1F) * 255) / 31), (((($c -shr 5) -band 0x3F) * 255) / 63), ((($c -band 0x1F) * 255) / 31) ) }
function To565($r,$g,$bl){
  $r=[Math]::Max(0,[Math]::Min(255,[Math]::Round($r)));$g=[Math]::Max(0,[Math]::Min(255,[Math]::Round($g)));$bl=[Math]::Max(0,[Math]::Min(255,[Math]::Round($bl)))
  return [uint16]((([int]($r*31/255)) -shl 11) -bor (([int]($g*63/255)) -shl 5) -bor ([int]($bl*31/255)))
}
# --- pass 1: endpoint transform, in place on a copy of the block payload -------------------
$blocks=New-Object byte[] ($bw*$bh*8); [Array]::Copy($b,$off,$blocks,0,$blocks.Length)
$skipped=0
if($Contrast -ne 1.0 -or $Bright -ne 1.0){
  for($i=0;$i -lt $bw*$bh;$i++){
    $o=$i*8
    $c0=[BitConverter]::ToUInt16($blocks,$o); $c1=[BitConverter]::ToUInt16($blocks,$o+2)
    $p0=From565 $c0; $p1=From565 $c1
    $n0=@(0,0,0);$n1=@(0,0,0)
    for($ch=0;$ch -lt 3;$ch++){
      $mid=($p0[$ch]+$p1[$ch])/2
      $n0[$ch]=($mid+($p0[$ch]-$mid)*$Contrast)*$Bright
      $n1[$ch]=($mid+($p1[$ch]-$mid)*$Contrast)*$Bright
    }
    $q0=To565 $n0[0] $n0[1] $n0[2]; $q1=To565 $n1[0] $n1[1] $n1[2]
    if(($c0 -gt $c1) -ne ($q0 -gt $q1)){ $skipped++; continue }   # would flip the mode bit
    [Array]::Copy([BitConverter]::GetBytes($q0),0,$blocks,$o,2)
    [Array]::Copy([BitConverter]::GetBytes($q1),0,$blocks,$o+2,2)
  }
}
# --- pass 2: optional 2x2 block-grid tile ---------------------------------------------------
if($TileN -gt 1){
  $nw=$bw*$TileN;$nh=$bh*$TileN
  $tiled=New-Object byte[] ($nw*$nh*8)
  for($y=0;$y -lt $nh;$y++){ for($x=0;$x -lt $nw;$x++){
    $src=(($y % $bh)*$bw + ($x % $bw))*8
    [Array]::Copy($blocks,$src,$tiled,($y*$nw+$x)*8,8)
  }}
  $blocks=$tiled;$w=$w*$TileN;$hh=$hh*$TileN
}
$iwi=New-IwiBuffer -Width $w -Height $hh -PayloadBytes $blocks.Length -Format 0x0B
[Array]::Copy($blocks,0,$iwi,(Get-IwiPayloadOffset),$blocks.Length)
[IO.File]::WriteAllBytes($Out,$iwi)
"{0,-30} -> {1}x{2}  {3:N0} B  (contrast {4}, bright {5}{6}, {7} blocks left alone)" -f (Split-Path -Leaf $In),$w,$hh,$iwi.Length,$Contrast,$Bright,$(if($TileN -gt 1){", tiled $TileN" + 'x'}else{''}),$skipped
