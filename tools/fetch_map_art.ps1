# fetch_map_art.ps1 - pull the 26 BO1 map images and stage them for the website.
# ---------------------------------------------------------------------------------------------
# WHERE THEY COME FROM: Plutonium's own Discord application, "Plutonium T5: Multiplayer"
# (app id 924614901975117834). Their CLIENT publishes rich presence while you play - the card
# reading "Playing / Plutonium T5: Multiplayer / Gunfight on Stadium" - and the map picture on it
# is a Rich Presence ART ASSET on that application. Those assets are readable by anyone:
#
#     GET https://discord.com/api/v10/oauth2/applications/<app>/assets
#     https://cdn.discordapp.com/app-assets/<app>/<asset id>.png?size=<n>
#
# ⚠ They are keyed by ENGINE MAP ID (mp_nuked, mp_stadium, ...) - a 1:1 match with lib/maps.js and
# with the `map` field status.json already carries. There is no name-matching step and no second
# table to drift.
#
# ⚠ REHOSTED, NOT HOTLINKED. Their asset ids can change without notice, and a card that silently
# loses its image is worse than one that never had it. We fetch once, shrink, and serve from
# gunfight.us. That also keeps the join card independent of a third party's CDN.
#
# ⚠ A SEPARATE FINDING, so nobody re-litigates it: this art CANNOT go on the bot's own profile.
# A bot's presence ignores `assets` entirely (docs/notes/bot-presence-is-text-only.md). It works in
# an EMBED, which takes any public https URL - a completely different mechanism.
#
# 256px JPEG because an embed thumbnail renders at roughly 80 CSS px; 256 covers a retina screen
# with room to spare. The 512px PNG source is ~380 kB each (9.6 MB the set); this is ~13 kB (0.3 MB).
#
#   .\fetch_map_art.ps1              # refresh site\wwwroot\assets\maps
#   .\fetch_map_art.ps1 -Size 512    # bigger, e.g. if the website ever shows them large
# ---------------------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [int]    $Size    = 256,
    [int]    $Quality = 88,
    [string] $OutDir  = (Join-Path $PSScriptRoot '..\site\wwwroot\assets\maps')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$APP = '924614901975117834'   # Plutonium T5: Multiplayer

# ⚠ Fetched live rather than hardcoded: if Plutonium re-uploads an asset its ID changes, and a
# stale table would silently download the wrong picture (or 404). The NAMES are stable; the ids
# are not, so the names are what we key on.
Write-Host "listing assets on Plutonium's application..."
$assets = Invoke-RestMethod -Uri "https://discord.com/api/v10/oauth2/applications/$APP/assets" `
                            -Headers @{ 'User-Agent' = 'DiscordBot (https://gunfight.us, 1.0)' } -TimeoutSec 25
$maps = @($assets | Where-Object { $_.name -like 'mp_*' })
Write-Host "  $($maps.Count) map assets found"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$qp  = New-Object System.Drawing.Imaging.EncoderParameters(1)
$qp.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, $Quality)

$ok = 0; $bytes = 0
foreach ($a in $maps) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri "https://cdn.discordapp.com/app-assets/$APP/$($a.id).png?size=512" `
                          -OutFile $tmp -TimeoutSec 30 -UseBasicParsing
        $src = [System.Drawing.Image]::FromFile($tmp)
        $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($src, 0, 0, $Size, $Size)
        $out = Join-Path $OutDir ($a.name + '.jpg')
        $bmp.Save($out, $enc, $qp)
        $g.Dispose(); $bmp.Dispose(); $src.Dispose()
        $bytes += (Get-Item $out).Length
        $ok++
    }
    catch { Write-Host "  FAILED $($a.name): $($_.Exception.Message)" -ForegroundColor Yellow }
    finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

Write-Host ("staged {0}/{1} images, {2} kB total (avg {3} kB) -> {4}" -f `
    $ok, $maps.Count, [math]::Round($bytes/1kb), [math]::Round($bytes/[math]::Max($ok,1)/1kb), $OutDir)
Write-Host "⚠ They reach the web only via: tools\deploy.ps1 -Web" -ForegroundColor Cyan
