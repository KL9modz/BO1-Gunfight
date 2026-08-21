# Downscale a DXT1 tile, then block-tile it back up: MANY repeats at a SMALL texture size.
#
# WHY: a camo cell's texture is magnified wildly on low-UV-density surfaces (gunplastic furniture
# needs >8x the repeats that gunmetal does). Getting there by tiling a 128^2 tile means 2048^2
# textures. Shrinking the PATTERN first costs nothing visible -- those surfaces magnify so hard the
# source detail is invisible anyway -- and keeps every texture at 512^2.
#
# This is the ONE place we re-encode rather than copy blocks, so it is deliberately kept tiny: the
# encode target is the SHRUNK image (32^2 = 64 blocks), never the final one, which is block-tiled.
#
# Encoder: per 4x4 block, endpoints = per-channel min/max (a range fit), then each texel takes the
# nearest of the 4 interpolated palette entries. ⚠ c0 MUST be > c1 as packed u16 or DXT1 switches to
# 3-colour+black mode and the block decodes wrong; if the fit degenerates we emit a flat block.
param([Parameter(Mandatory)][string]$In,[Parameter(Mandatory)][string]$Out,
      [int]$Shrink=4,[int]$TileN=16,[double]$Contrast=1.0,[double]$Bright=1.0)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSCommandPath) 'iwi_common.ps1')

$b=[IO.File]::ReadAllBytes($In); $h=Read-IwiHeader -Bytes $b
if(-not $h.ok){throw $h.reason}
$srcBB = if($h.format -eq 0x0B){8}else{16}   # bytes per block
$srcCO = if($h.format -eq 0x0B){0}else{8}   # colour sub-block offset
if($h.format -notin 0x0B,0x0C,0x0D){throw 'DXT1/3/5 only'}
$w=$h.width; $ht=$h.height; $bw=$w/4; $bh=$ht/4; $off=Get-IwiPayloadOffset

# ---- decode to an RGB plane -----------------------------------------------------------------
$px=New-Object 'double[]' ($w*$ht*3)
for($by=0;$by -lt $bh;$by++){ for($bx=0;$bx -lt $bw;$bx++){
  $o=$off+(($by*$bw)+$bx)*$srcBB+$srcCO
  $c0=[BitConverter]::ToUInt16($b,$o); $c1=[BitConverter]::ToUInt16($b,$o+2)
  $idx=[BitConverter]::ToUInt32($b,$o+4)
  $p=@(@(0,0,0),@(0,0,0),@(0,0,0),@(0,0,0))
  foreach($k in 0,1){
    $c=if($k -eq 0){$c0}else{$c1}
    $p[$k]=@( ((((($c -shr 11) -band 0x1F)*255)/31)), ((((($c -shr 5) -band 0x3F)*255)/63)), (((($c -band 0x1F)*255)/31)) )
  }
  for($ch=0;$ch -lt 3;$ch++){
    $p[2][$ch]=((2*$p[0][$ch]+$p[1][$ch])/3); $p[3][$ch]=(($p[0][$ch]+2*$p[1][$ch])/3)
  }
  for($t=0;$t -lt 16;$t++){
    $x=$bx*4+($t%4); $y=$by*4+[Math]::Floor($t/4)
    $c=$p[[int](($idx -shr ($t*2)) -band 3)]
    $q=(($y*$w)+$x)*3; $px[$q]=$c[0]; $px[$q+1]=$c[1]; $px[$q+2]=$c[2]
  }
}}

# ---- box downscale + contrast ----------------------------------------------------------------
$nw=[int]($w/$Shrink); $nh=[int]($ht/$Shrink)
$sm=New-Object 'double[]' ($nw*$nh*3)
for($y=0;$y -lt $nh;$y++){ for($x=0;$x -lt $nw;$x++){
  $acc=@(0.0,0.0,0.0)
  for($dy=0;$dy -lt $Shrink;$dy++){ for($dx=0;$dx -lt $Shrink;$dx++){
    $q=(((($y*$Shrink)+$dy)*$w)+(($x*$Shrink)+$dx))*3
    $acc[0]+=$px[$q]; $acc[1]+=$px[$q+1]; $acc[2]+=$px[$q+2]
  }}
  $n=$Shrink*$Shrink; $q=(($y*$nw)+$x)*3
  for($ch=0;$ch -lt 3;$ch++){ $sm[$q+$ch]=[Math]::Max(0,[Math]::Min(255, ((128+((($acc[$ch]/$n)-128)*$Contrast))*$Bright) )) }
}}

# ---- encode DXT1 (range fit) -------------------------------------------------------------------
function To565($r,$g,$bl){
  $r=[int][Math]::Round($r); $g=[int][Math]::Round($g); $bl=[int][Math]::Round($bl)
  return [uint16]((([int]($r*31/255)) -shl 11) -bor (([int]($g*63/255)) -shl 5) -bor ([int]($bl*31/255)))
}
$nbw=$nw/4; $nbh=$nh/4
$blocks=New-Object byte[] ($nbw*$nbh*8)
for($by=0;$by -lt $nbh;$by++){ for($bx=0;$bx -lt $nbw;$bx++){
  $mn=@(255.0,255.0,255.0); $mx=@(0.0,0.0,0.0)
  for($t=0;$t -lt 16;$t++){
    $x=$bx*4+($t%4); $y=$by*4+[Math]::Floor($t/4); $q=(($y*$nw)+$x)*3
    for($ch=0;$ch -lt 3;$ch++){ $v=$sm[$q+$ch]; if($v -lt $mn[$ch]){$mn[$ch]=$v}; if($v -gt $mx[$ch]){$mx[$ch]=$v} }
  }
  $c0=To565 $mx[0] $mx[1] $mx[2]; $c1=To565 $mn[0] $mn[1] $mn[2]
  if($c0 -le $c1){ if($c1 -lt 65535){$c0=$c1+1}else{$c0=65535;$c1=65534} }   # keep 4-colour mode
  $pal=@()
  foreach($c in $c0,$c1){ $pal+=,@( ((((($c -shr 11) -band 0x1F)*255)/31)), ((((($c -shr 5) -band 0x3F)*255)/63)), (((($c -band 0x1F)*255)/31)) ) }
  $pal+=,@( ((2*$pal[0][0]+$pal[1][0])/3), ((2*$pal[0][1]+$pal[1][1])/3), ((2*$pal[0][2]+$pal[1][2])/3) )
  $pal+=,@( (($pal[0][0]+2*$pal[1][0])/3), (($pal[0][1]+2*$pal[1][1])/3), (($pal[0][2]+2*$pal[1][2])/3) )
  $bits=[uint32]0
  for($t=0;$t -lt 16;$t++){
    $x=$bx*4+($t%4); $y=$by*4+[Math]::Floor($t/4); $q=(($y*$nw)+$x)*3
    $best=0; $bd=[double]::MaxValue
    for($k=0;$k -lt 4;$k++){
      $d=0.0
      for($ch=0;$ch -lt 3;$ch++){ $e=$sm[$q+$ch]-$pal[$k][$ch]; $d+=($e*$e) }
      if($d -lt $bd){$bd=$d;$best=$k}
    }
    $bits=$bits -bor ([uint32]$best -shl ($t*2))
  }
  $o=(($by*$nbw)+$bx)*8
  [Array]::Copy([BitConverter]::GetBytes($c0),0,$blocks,$o,2)
  [Array]::Copy([BitConverter]::GetBytes($c1),0,$blocks,$o+2,2)
  [Array]::Copy([BitConverter]::GetBytes($bits),0,$blocks,$o+4,4)
}}

# ---- block-tile up (lossless) -------------------------------------------------------------------
$fw=$nbw*$TileN; $fh=$nbh*$TileN
$tiled=New-Object byte[] ($fw*$fh*8)
for($y=0;$y -lt $fh;$y++){ for($x=0;$x -lt $fw;$x++){
  [Array]::Copy($blocks,((($y%$nbh)*$nbw)+($x%$nbw))*8,$tiled,((($y*$fw)+$x))*8,8)
}}
$iwi=New-IwiBuffer -Width ($fw*4) -Height ($fh*4) -PayloadBytes $tiled.Length -Format 0x0B
[Array]::Copy($tiled,0,$iwi,(Get-IwiPayloadOffset),$tiled.Length)
[IO.File]::WriteAllBytes($Out,$iwi)
"{0,-30} -> {1}x{2} ({3}^2 pattern x{4}) {5:N0} B" -f (Split-Path -Leaf $In),($fw*4),($fh*4),$nw,$TileN,$iwi.Length
