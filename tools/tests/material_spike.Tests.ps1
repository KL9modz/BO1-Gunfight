# Pester net for tools/material_spike/make_material.ps1 - the BO1 custom-material fabricator.
#
# The generator was proven 2026-08-14 by regenerating three materials from the
# Classixz/bo1-competitiveleaguemod corpus BYTE-FOR-BYTE (blank 100B hud-family, icon_x3 99B
# hud-family, bo_cl_camo_1 108B decal-family), matching material_properties' first 12 bytes
# (last 4 are per-file converter garbage in the corpus, zeros in ours), and matching
# bocl_rank30.iwi's 48-byte header exactly (after the 8-mip-slot fix - the first recon pass
# dumped only 32 header bytes and mis-called it 4 slots).
#
# These tests pin that validated shape WITHOUT the corpus (79MB, not committable): the
# arithmetic law, the header constants per family, string order, and the IWI header. When the
# corpus clone happens to exist at %TEMP%\bo1-clm, the original byte-for-byte comparison runs
# too (skipped silently otherwise - CI-safe either way).
#
# ⚠ Plain `if (...) { throw }` assertions - Pester 3.4/5.x compatible (see guards.Tests.ps1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $here
$mk = Join-Path $toolsRoot 'material_spike\make_material.ps1'

function Assert-True($cond, $msg) { if (-not $cond) { throw "ASSERT: $msg" } }
function Assert-Eq($actual, $expected, $msg) {
    if ("$actual" -ne "$expected") { throw "ASSERT: $msg -- expected [$expected], got [$actual]" }
}
function Get-U32($bytes, $off) { return [BitConverter]::ToUInt32($bytes, $off) }
function Get-U16($bytes, $off) { return [BitConverter]::ToUInt16($bytes, $off) }
function Get-CStr($bytes, $off) {
    $end = $off; while ($bytes[$end] -ne 0) { $end++ }
    return [System.Text.Encoding]::ASCII.GetString($bytes, $off, $end - $off)
}
function Invoke-Maker {
    param([string[]]$MakerArgs, [string]$OutRoot)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $mk @MakerArgs -OutRoot $OutRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "make_material.ps1 exited $LASTEXITCODE" }
}

$work = Join-Path $env:TEMP ("gf_matspike_test_" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work -Force | Out-Null

Describe "make_material.ps1 - material binary (the validated BOCL shape)" {
    Invoke-Maker @('-Name', 'gf_test_brand', '-Image', 'gf_test', '-Width', '256', '-Family', 'hud') $work
    $m = [System.IO.File]::ReadAllBytes((Join-Path $work 'materials\gf_test_brand'))

    It "obeys the arithmetic law (size = 0x4F + N+1 + I+1 + 9)" {
        Assert-Eq $m.Length (0x4F + 14 + 8 + 9) "gf_test_brand(13)/gf_test(7) size"
    }
    It "header offsets point at the right strings" {
        Assert-Eq (Get-CStr $m (Get-U32 $m 0x00)) 'gf_test_brand' "name via +0x00"
        Assert-Eq (Get-CStr $m (Get-U32 $m 0x04)) 'gf_test' "image via +0x04"
        Assert-Eq (Get-CStr $m (Get-U32 $m 0x34)) '2d' "techset via +0x34"
        Assert-Eq (Get-U32 $m 0x38) 0x40 "texture table at 0x40"
    }
    It "texture entry = colorMap/0xE2 sampler/TS_2D semantic/image" {
        Assert-Eq (Get-CStr $m (Get-U32 $m 0x40)) 'colorMap' "type name"
        Assert-Eq $m[0x44] 0xE2 "2d sampler byte"
        Assert-Eq $m[0x45] 0x00 "TS_2D semantic"
        Assert-Eq (Get-U32 $m 0x48) (Get-U32 $m 0x04) "entry image offset == header +0x04"
    }
    It "hud family constants (sortKey 43, drawSurf 0x00200000, +0x28 batch const)" {
        Assert-Eq $m[0x09] 0x2B "sortKey"
        Assert-Eq (Get-U32 $m 0x10) 0x00200000 "drawSurf hi"
        Assert-Eq (Get-U32 $m 0x28) 0x08128965 "+0x28"
        Assert-Eq (Get-U32 $m 0x2C) 0x0C "+0x2C 2d constant"
    }
    It "dims land at +0x18/+0x1A" {
        Assert-Eq (Get-U16 $m 0x18) 256 "width"
        Assert-Eq (Get-U16 $m 0x1A) 256 "height"
    }
    It "string pool order is techset, name, image, colorMap - no dedup" {
        Assert-Eq (Get-CStr $m 0x4C) '2d' "pool starts with techset at fixed 0x4C"
        Assert-Eq (Get-CStr $m 0x4F) 'gf_test_brand' "name at fixed 0x4F"
    }
    It "decal family flips exactly the three family constants" {
        Invoke-Maker @('-Name', 'gf_decal_t', '-Image', 'gf_decal_i', '-Width', '256', '-Family', 'decal', '-SkipIwi') $work
        $d = [System.IO.File]::ReadAllBytes((Join-Path $work 'materials\gf_decal_t'))
        Assert-Eq $d[0x09] 0x04 "decal sortKey"
        Assert-Eq (Get-U32 $d 0x10) 0x00100000 "decal drawSurf hi"
        Assert-Eq (Get-U32 $d 0x28) 0x08128812 "decal +0x28"
    }
    It "material_properties = 16 bytes: u32 0,1,0,0" {
        $p = [System.IO.File]::ReadAllBytes((Join-Path $work 'material_properties\gf_test_brand'))
        Assert-Eq $p.Length 16 "props length"
        Assert-Eq (Get-U32 $p 0) 0 "dword 1"
        Assert-Eq (Get-U32 $p 4) 1 "dword 2"
        Assert-Eq (Get-U32 $p 8) 0 "dword 3 (mirror of material +0x20, 0 for 2d)"
    }
}

Describe "make_material.ps1 - IWI (v13, DXT5, 8 size slots)" {
    $i = [System.IO.File]::ReadAllBytes((Join-Path $work 'images\gf_test.iwi'))
    It "header magic/version/format/flags/dims" {
        Assert-Eq ([System.Text.Encoding]::ASCII.GetString($i, 0, 3)) 'IWi' "magic"
        Assert-Eq $i[3] 0x0D "version 13 (BO1)"
        Assert-Eq $i[4] 0x0D "DXT5"
        Assert-Eq $i[5] 0xC3 "flags"
        Assert-Eq (Get-U16 $i 6) 256 "width"
        Assert-Eq (Get-U16 $i 8) 256 "height"
        Assert-Eq (Get-U16 $i 10) 1 "depth"
    }
    It "EIGHT size dwords at 0x10..0x2F, all = file length (the 4-slot recon error, pinned)" {
        for ($s = 0; $s -lt 8; $s++) {
            Assert-Eq (Get-U32 $i (0x10 + 4 * $s)) $i.Length "slot $s"
        }
    }
    It "payload = W*H bytes, sentinel-filled" {
        Assert-Eq $i.Length (48 + 256 * 256) "file size"
        Assert-True ($i[48] -eq 0xAB -and $i[$i.Length - 1] -eq 0xAB) "0xAB sentinel at both ends"
    }
    It "transparent payload is all zeros (DXT5 all-zero = alpha 0)" {
        Invoke-Maker @('-Name', 'gf_tr_t', '-Image', 'gf_tr_i', '-Width', '64', '-Payload', 'transparent') $work
        $t = [System.IO.File]::ReadAllBytes((Join-Path $work 'images\gf_tr_i.iwi'))
        $nz = 0; for ($b = 48; $b -lt $t.Length; $b++) { if ($t[$b] -ne 0) { $nz++ } }
        Assert-Eq $nz 0 "non-zero payload bytes"
    }
}

Describe "make_material.ps1 - corpus byte-compare (runs only when %TEMP%\bo1-clm exists)" {
    $clm = Join-Path $env:TEMP 'bo1-clm'
    It "regenerates blank / icon_x3 / bo_cl_camo_1 byte-for-byte" {
        if (-not (Test-Path -LiteralPath (Join-Path $clm 'materials\blank'))) { return }   # corpus absent: skip
        Invoke-Maker @('-Name', 'blank', '-Image', 'blank', '-Width', '8', '-Family', 'hud', '-SkipIwi') $work
        Invoke-Maker @('-Name', 'icon_x3', '-Image', 'x3', '-Width', '512', '-Family', 'hud', '-SkipIwi') $work
        Invoke-Maker @('-Name', 'bo_cl_camo_1', '-Image', 'camo_1', '-Width', '1024', '-Family', 'decal', '-SkipIwi') $work
        foreach ($n in @('blank', 'icon_x3', 'bo_cl_camo_1')) {
            $mine = [System.IO.File]::ReadAllBytes((Join-Path $work "materials\$n"))
            $theirs = [System.IO.File]::ReadAllBytes((Join-Path $clm "materials\$n"))
            Assert-Eq $mine.Length $theirs.Length "$n length"
            for ($b = 0; $b -lt $mine.Length; $b++) {
                if ($mine[$b] -ne $theirs[$b]) { throw "ASSERT: $n differs from corpus at 0x$('{0:X}' -f $b)" }
            }
        }
    }
}

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
