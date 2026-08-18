# make_iwd.ps1 -- package images\*.iwi into mp_gunfight.iwd for client delivery.
#
# WHY: the linker NEVER embeds image pixels -- it writes an image reference by name and drops the
# data (docs/notes/modff-cannot-embed-new-images.md, re-proven with a sentinel payload). So any
# custom image (weapon camos, HUD art, a transparent `net`) must travel BESIDE mod.ff. The route
# with production proof behind it is a mod-folder .iwd.
#
# SHAPE COPIED FROM A SHIPPED MOD, NOT GUESSED -- storage\t5\mods\bo1-snife-1.0 holds snife's
# sources next to the artifacts it actually ships, and `mp_UU_snife_final` (the installed copy)
# is *only* mod.ff + mp_UU_snife.iwd. Facts taken from it (2026-08-16):
#   * the .iwd is a plain zip of 210 entries, EVERY one `images/<name>.iwi`, and nothing else
#   * entry paths use FORWARD slashes
#   * compression is Defl:N -- ordinary Deflate, NOT stored. ⚠ tools/material_spike/README.md
#     originally guessed "store/no-compression to be safe"; that was wrong, and at snife's 68 MB
#     it plainly matters. Ours compresses ~99% (flat DXT5 camo blocks).
#   * the mod.csv registers NO `image,` rows -- registration is not how pixels travel
#
# ⚠ FastDL must mirror this file byte-identical next to mod.ff or clients get "Invalid file",
#   and it must never be bz2'd. deploy.ps1 -Mod has to publish it alongside mod.ff.
# ⚠ The .iwd is a BUILD ARTIFACT (.gitignore'd). images\*.iwi are the tracked source.

[CmdletBinding()]
param(
    [string]$ModRoot,
    [string]$IwdName = 'mp_gunfight.iwd',
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

# The IWi v13 header shape (Read-IwiHeader), shared with the camo writers + preview tool.
. (Join-Path $PSScriptRoot 'iwi_common.ps1')

if (-not $ModRoot) {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ModRoot = Split-Path -Parent $scriptDir
}

$imgDir = Join-Path $ModRoot 'images'
if (-not (Test-Path -LiteralPath $imgDir)) { throw "no images\ directory at $imgDir -- nothing to package" }

$files = @(Get-ChildItem -LiteralPath $imgDir -Filter *.iwi -File | Sort-Object Name)
if ($files.Count -eq 0) { throw "images\ holds no .iwi files" }

# ⚠ FORMAT GATE -- every image must be a T5 IWi v13.
# Plutonium's own docs: "Camos and other textures only work on the game they were created for, the
# .iwi version is different between games." Since we now import art from community packs (which are
# published per-game and freely re-hosted), an IW5/T6 .iwi can easily end up in images\. It would
# pack, deploy and FastDL perfectly happily, then simply fail to render -- the exact silent, hard-
# to-attribute failure the carrier-material bug already cost a debug cycle on. Fail at build time.
# Header: "IWi" + version byte; every stock T5 image and every working camo we ship reads 0x0D.
# Read-IwiHeader (tools\iwi_common.ps1) owns the header shape for every tool that writes or reads
# one; it reports instead of throwing, which is exactly what a batch validator wants.
$badFmt = @()
foreach ($f in $files) {
    $h = Read-IwiHeader -Path $f.FullName
    if (-not $h.ok) { $badFmt += "$($f.Name): $($h.reason)" }
}
if ($badFmt.Count) { throw "Refusing to package - wrong-format image(s):`n  " + ($badFmt -join "`n  ") }

# ⚠ BOTH assemblies: ZipFile/ZipFileExtensions live in .FileSystem, but ZipArchiveMode and
# CompressionLevel live in System.IO.Compression -- loading only the first fails with
# "Unable to find type [System.IO.Compression.ZipArchiveMode]".
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$dest = Join-Path $ModRoot $IwdName

# ⚠ A RUNNING GAME HOLDS THE .iwd OPEN -- Plutonium mounts it at load and keeps the handle, so a
# rebuild while the client/server is up dies with "being used by another process". Rather than
# fail (and lose the packaging work), write it beside the live file and let the caller swap. The
# lock is also the cheapest positive evidence that the mount is happening at all.
$locked = $false
if (Test-Path -LiteralPath $dest) {
    try { $fs = [System.IO.File]::Open($dest, 'Open', 'ReadWrite', 'None'); $fs.Close() }
    catch { $locked = $true }
}
if ($locked) {
    $dest = "$dest.new"
    $holder = @(Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'plutonium|BlackOps' } | Select-Object -Expand Name -Unique)
    Write-Warning ("{0} is LOCKED (mounted by: {1}). Writing {2} instead -- close the game, then replace the .iwd with it." -f `
        $IwdName, $(if ($holder) { $holder -join ', ' } else { 'unknown process' }), (Split-Path -Leaf $dest))
}
if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }

$zip = [System.IO.Compression.ZipFile]::Open($dest, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        # ⚠ forward slash, matching snife's entries. .NET writes the name verbatim, and a
        # backslash here would produce an entry the game cannot resolve.
        $entry = "images/$($f.Name)"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $f.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}

$raw = ($files | Measure-Object -Property Length -Sum).Sum
$out = (Get-Item -LiteralPath $dest).Length
Write-Host ("{0}: {1} image(s), {2:N0} B raw -> {3:N0} B packed ({4:N1}% saved)" -f `
    $IwdName, $files.Count, $raw, $out, ((1 - $out / [double]$raw) * 100))
foreach ($f in $files) { Write-Host ("  images/{0}  {1:N0} B" -f $f.Name, $f.Length) }

if ($Verify) {
    $zr = [System.IO.Compression.ZipFile]::OpenRead($dest)
    try {
        $bad = @($zr.Entries | Where-Object { $_.FullName -notmatch '^images/[^/\\]+\.iwi$' })
        if ($bad) { throw "malformed entries: $($bad.FullName -join ', ')" }
        Write-Host ("verify: OK -- {0} entries, all images/*.iwi, forward-slashed" -f $zr.Entries.Count)
    } finally { $zr.Dispose() }
}
