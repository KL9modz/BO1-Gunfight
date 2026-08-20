# fix_join_card_labels.ps1 - blank the leftover field HEADINGS on already-posted join cards.
# ------------------------------------------------------------------------------------------
# One-off cleanup. Join cards used to label their fields "Location", "Discord" and "Play"; the
# values are all self-describing, and "Play" sat directly above copy reading "Play for free",
# printing the word twice. Live cards stopped doing that on 2026-08-20 - this fixes the ones
# already in the channel.
#
# ⚠ SCOPE IS DELIBERATELY TINY: it blanks field NAMES and changes NOTHING else. Not the values,
# not the colour, not the timestamp, not the layout. It cannot add the [Play for free!] button,
# because these are WEBHOOK messages and a webhook cannot send components (proven 2026-08-20) -
# so an edited old card keeps its text call to action and only loses the redundant heading.
#
# ⚠ TWO DIFFERENT CREDENTIALS, and they are not interchangeable:
#     READING  the channel needs the BOT token (+ View Channel and Read Message History).
#     EDITING  a webhook's message needs the WEBHOOK token - a bot cannot edit another
#              author's message, and these were posted by the webhook.
#
# ⚠ Edits do NOT re-notify, so this is silent for everyone in the channel. It is still a public
# channel: run it with -DryRun first (the default) and read the before/after.
#
#   .\fix_join_card_labels.ps1                 # dry run, shows what would change
#   .\fix_join_card_labels.ps1 -Limit 30       # look further back
#   .\fix_join_card_labels.ps1 -Apply          # actually edit
# ------------------------------------------------------------------------------------------

[CmdletBinding()]
param(
    # How many recent messages to SCAN (not how many to edit). 100 is Discord's per-request max.
    [int]    $Limit    = 50,
    [string] $Category = 'joins',
    # Dry run is the default on purpose: this writes to a channel players read.
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ntfy.ps1')

$BLANK = [string][char]0x200B          # a field name cannot be empty; this renders as no heading
$STALE = @('Location', 'Discord', 'Play')

$cfg = Get-GfNtfyConfig -Path (Join-Path $PSScriptRoot 'config.json')
if (-not $cfg) { throw 'no notify config - nothing to do' }

$hook = Get-GfDiscordWebhook -Config $cfg -Category $Category
if (-not $hook) { throw "no '$Category' webhook configured" }
$chan = Get-GfDiscordChannelId -Config $cfg -Category $Category
if (-not $chan) { throw "could not resolve the channel id for '$Category'" }
$tok = Get-GfBotToken
if (-not $tok) { throw 'no bot token - reading the channel needs one (tools\discord_bot\config.local.json)' }

Write-Host "channel $chan, scanning the last $Limit message(s)$(if (-not $Apply) { '  [DRY RUN]' })"

try {
    $msgs = Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$chan/messages?limit=$Limit" `
                              -Headers @{ Authorization = "Bot $tok" } -TimeoutSec 25
}
catch {
    # THE expected failure until someone grants it: the bot is in the guild but not on the channel.
    throw "cannot read the channel ($($_.Exception.Message)). Grant the bot View Channel + Read Message History on it."
}

$changed = 0; $skipped = 0
foreach ($m in $msgs) {
    # Only OUR webhook's join cards. A bot-posted card (anything from today onward) already has
    # blank headings, and someone else's message is never touched.
    if (-not $m.webhook_id) { continue }
    if (-not $m.embeds -or $m.embeds.Count -eq 0) { continue }
    $e = $m.embeds[0]
    # "Joined:" -> "Joined match:" (owner's wording, 2026-08-20). ⚠ Anchored on "Joined:" WITH the
    # colon so it cannot fire twice: an already-fixed card reads "Joined match:", which does not
    # contain "Joined:" followed by a space, so re-running this is a no-op rather than producing
    # "Joined match match:".
    $newTitle = $e.title
    if ($newTitle -and $newTitle -match 'Joined:') { $newTitle = $newTitle -replace 'Joined:', 'Joined match:' }

    $labelsStale = (@($e.fields | Where-Object { $STALE -contains $_.name }).Count -gt 0)
    $titleStale  = ($newTitle -ne $e.title)
    if (-not $e.fields -or $e.fields.Count -eq 0) {
        # A pre-fields card can still have a stale TITLE, so it is not automatically skippable.
        if (-not $titleStale) { continue }
    }
    if (-not $labelsStale -and -not $titleStale) { $skipped++; continue }

    # Rebuild the embed by COPYING it and replacing only the field names. Anything not named here
    # is carried across untouched - an edit that drops a key would silently delete that part of
    # the card, and there is no undo on a channel.
    $embed = [ordered]@{}
    if ($newTitle) { $embed['title'] = $newTitle }
    foreach ($k in 'description', 'color', 'url', 'timestamp') {
        if ($null -ne $e.$k -and $e.$k -ne '') { $embed[$k] = $e.$k }
    }
    if ($e.fields -and $e.fields.Count) {
        $fields = @()
        foreach ($f in $e.fields) {
            $name = $(if ($STALE -contains $f.name) { $BLANK } else { $f.name })
            $fields += @{ name = $name; value = $f.value; inline = [bool]$f.inline }
        }
        # ⚠ Comma operator: a ONE-field card would otherwise unroll to a bare hashtable and ship
        # `fields: {...}` where Discord requires a list. Same trap as Get-JoinButton.
        $embed['fields'] = ,$fields
    }
    if ($e.footer)    { $embed['footer']    = @{ text = [string]$e.footer.text } }
    if ($e.thumbnail) { $embed['thumbnail'] = @{ url  = [string]$e.thumbnail.url } }
    if ($e.author)    { $embed['author']    = @{ name = [string]$e.author.name } }

    $what = @()
    if ($titleStale)  { $what += "title -> '$newTitle'" }
    if ($labelsStale) { $what += 'labels -> blank (' + (($e.fields | ForEach-Object { $_.name } | Where-Object { $STALE -contains $_ }) -join ', ') + ')' }
    Write-Host ("  {0}  {1}" -f $m.id, ($what -join '; '))

    if ($Apply) {
        $payload = [ordered]@{ embeds = @($embed); allowed_mentions = @{ parse = @() } }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Compress -Depth 8))
        try {
            # ⚠ The WEBHOOK route, not the bot's - a webhook's message can only be edited by it.
            Invoke-RestMethod -Uri "$hook/messages/$($m.id)" -Method Patch -Body $bytes `
                -ContentType 'application/json; charset=utf-8' -TimeoutSec 20 | Out-Null
            $changed++
            # Discord allows 5 edits / 2s per webhook. Pacing beats catching a 429 in a loop.
            Start-Sleep -Milliseconds 450
        }
        catch { Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    else { $changed++ }
}

Write-Host ""
Write-Host ("{0} card(s) {1}; {2} already clean" -f $changed, $(if ($Apply) { 'edited' } else { 'would be edited' }), $skipped)
if (-not $Apply) { Write-Host "Dry run - nothing was changed. Re-run with -Apply to write." -ForegroundColor Cyan }
