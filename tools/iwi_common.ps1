# iwi_common.ps1 -- the T5 IWi v13 header, in ONE place.
#
# Dot-source it:
#   . (Join-Path $PSScriptRoot 'iwi_common.ps1')        # from a tools\ script
#   . (Join-Path $PSScriptRoot '..\iwi_common.ps1')     # from a tools\<subdir>\ script
#
# WHY THIS EXISTS: the same 48-byte header was hand-written by three tools (make_camo_iwi,
# dds_to_iwi, material_spike\make_material) and re-parsed by two more (preview_iwi, make_iwd's
# format gate). The ONE documented failure mode of this format is header-shape drift, and it had
# already started: the first recon pass dumped only 32 header bytes, called the size table "4x u32
# mip-end-offsets", and regenerating with four slots diverged from the BOCL corpus at offset 0x20.
# The code was fixed to eight in all three copies; make_material's own header comment still said
# four. A comment that disagrees with its code is how the next person re-learns this the hard way.
#
# THE SHAPE (verified byte-for-byte against the bo1-competitiveleaguemod corpus; the assertions
# live in tools\tests\material_spike.Tests.ps1, which is what keeps this file honest):
#   0x00  "IWi"                      magic
#   0x03  0x0D                       version 13 = T5. ⚠ Art from another CoD packs, deploys and
#                                    FastDLs perfectly happily, then simply does not render.
#   0x04  format byte                0x0B DXT1 / 0x0C DXT3 / 0x0D DXT5
#   0x05  0xC3                       flags
#   0x06  u16 width
#   0x08  u16 height
#   0x0A  u16 depth (1)
#   0x0C  u32 0
#   0x10  8x u32 mip END-OFFSETS     all = file length for the single-mip files we ship
#   0x30  payload (mip 0)
#
# ⚠ SINGLE MIP IS DELIBERATE, not a shortcut. A stock T5 .iwi carries a full mip chain with
# ascending end-offsets; setting all eight slots to the file size declares one level, and those
# render correctly in game. Do not "fix" it into a chain without regenerating the corpus compare.

Set-Variable -Name IwiHeaderBytes -Value 48 -Option Constant -Scope Script -ErrorAction SilentlyContinue

# FourCC -> IWi format byte, and bytes per 4x4 block for each.
$script:IwiFormatFromFourCC = @{ 'DXT1' = 0x0B; 'DXT3' = 0x0C; 'DXT5' = 0x0D }
$script:IwiBlockBytes       = @{ 0x0B = 8;      0x0C = 16;     0x0D = 16 }

function New-IwiBuffer {
    <#
    .SYNOPSIS
      Allocate a complete .iwi byte[] with the v13 header filled in, payload zeroed.
    .DESCRIPTION
      Returns 48 + PayloadBytes zero-initialised bytes with the header written, so the caller
      only has to fill from offset 48 (Get-IwiPayloadOffset). Zeroed is a meaningful default:
      an all-zero DXT5 payload is alpha 0 everywhere, i.e. fully transparent.
    #>
    param(
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [Parameter(Mandatory = $true)][int]$PayloadBytes,
        [byte]$Format = 0x0D          # DXT5
    )

    if ($Width -gt 65535 -or $Height -gt 65535) { throw "dimensions exceed the IWi u16 fields (${Width}x${Height})" }
    if ($Width -lt 1 -or $Height -lt 1)         { throw "bad dimensions (${Width}x${Height})" }
    if ($PayloadBytes -lt 1)                    { throw "empty payload" }

    $fileLen = $script:IwiHeaderBytes + $PayloadBytes
    $iwi = New-Object byte[] $fileLen
    [Array]::Copy([byte[]]@(0x49, 0x57, 0x69, 0x0D, $Format, 0xC3), $iwi, 6)
    [Array]::Copy([BitConverter]::GetBytes([uint16]$Width),  0, $iwi, 6, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]$Height), 0, $iwi, 8, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]1),       0, $iwi, 10, 2)
    # EIGHT slots, not four -- see the header comment. All = file length: one mip, no chain.
    for ($m = 0; $m -lt 8; $m++) {
        [Array]::Copy([BitConverter]::GetBytes([uint32]$fileLen), 0, $iwi, 0x10 + 4 * $m, 4)
    }
    return $iwi
}

function Get-IwiPayloadOffset { return $script:IwiHeaderBytes }

function Get-IwiFormatByte {
    # 'DXT5' -> 0x0D. Returns $null for anything not compressed the way BO1 wants.
    param([Parameter(Mandatory = $true)][string]$FourCC)
    $key = $FourCC.Trim().ToUpperInvariant()
    if ($script:IwiFormatFromFourCC.ContainsKey($key)) { return [byte]$script:IwiFormatFromFourCC[$key] }
    return $null
}

function Get-IwiBlockBytes {
    # Bytes per 4x4 block for an IWi format byte (DXT1 = 8, DXT3/DXT5 = 16).
    param([Parameter(Mandatory = $true)][byte]$Format)
    if ($script:IwiBlockBytes.ContainsKey([int]$Format)) { return [int]$script:IwiBlockBytes[[int]$Format] }
    throw ("no block size for IWi format 0x{0:X2}" -f $Format)
}

function Read-IwiHeader {
    <#
    .SYNOPSIS
      Parse an .iwi header from a path or a byte[].
    .DESCRIPTION
      Returns a hashtable: ok, reason, version, format, width, height, isT5. Never throws on a
      bad/short/missing file -- callers are validators and want to REPORT, not blow up. Reads only
      the header, so it is cheap enough to run over a whole images\ directory.
    #>
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = 'Bytes')][byte[]]$Bytes
    )

    $h = @{ ok = $false; reason = ''; version = 0; format = 0; width = 0; height = 0; isT5 = $false }

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $buf = New-Object byte[] $script:IwiHeaderBytes
        $read = 0
        try {
            $fs = [System.IO.File]::OpenRead($Path)
            try { $read = $fs.Read($buf, 0, $script:IwiHeaderBytes) } finally { $fs.Close() }
        } catch {
            $h.reason = "unreadable: $($_.Exception.Message)"
            return $h
        }
        if ($read -lt 12) { $h.reason = 'truncated (not even a header)'; return $h }
        $Bytes = $buf
    }

    if ($Bytes.Length -lt 12) { $h.reason = 'truncated (not even a header)'; return $h }
    if ($Bytes[0] -ne 0x49 -or $Bytes[1] -ne 0x57 -or $Bytes[2] -ne 0x69) {
        $h.reason = 'not an IWi file'
        return $h
    }

    $h.version = [int]$Bytes[3]
    $h.format  = [int]$Bytes[4]
    $h.width   = [int][BitConverter]::ToUInt16($Bytes, 6)
    $h.height  = [int][BitConverter]::ToUInt16($Bytes, 8)
    $h.isT5    = ($h.version -eq 0x0D)
    if (-not $h.isT5) {
        $h.reason = "IWi v$($h.version), not T5's v13 (art from another game - it will not render)"
        return $h
    }
    $h.ok = $true
    return $h
}
