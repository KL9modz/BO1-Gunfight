# Player GUID -> Discord user id. The box-local table that lets an alert say who a player IS in
# Discord, instead of only what they call themselves in game.
#
# Shape (tools\players.local.json, gitignored - see below):
#
#   { "links": { "<game guid>": { "discordId": "123456789012345678", "note": "KL9 (owner)" } } }
#
# ⚠ THE FILE IS BOX-LOCAL AND MUST STAY THAT WAY. It is keyed by player GUID, which the project
# rule puts in the same class as a player's IP: never in any tracked file, ever. It is therefore
# in .gitignore, in $LocalOnlyFiles (so deploy's /MIR cannot delete the box copy and no packager
# can ship it), and the committed template tools\players.example.json carries invented values
# only. Add real entries ON THE BOX.
#
# ⚠ A mention rendered from this table goes in an embed DESCRIPTION, where Discord renders the
# chip but sends NO notification - embeds never notify. That is deliberate: a player who just
# joined does not need their phone buzzed about it, and the alert channel keeps its one job.
# Moving a mention into the message `content` WOULD notify, and would then also need
# allowed_mentions widened from its locked-down parse:[] - do not do that casually.

# Cached by path + last-write time, so an edit takes effect without restarting a service (the
# same courtesy ignore_list.ps1 gives the mute list) while a hot loop still costs one stat call.
$script:GfPlayerLinkCache = @{}

function Get-GfPlayerLinks {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return @{} }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { return @{} }   # no table on this box is the normal state, not an error

    $stamp = $item.LastWriteTimeUtc.Ticks
    if ($script:GfPlayerLinkCache.ContainsKey($Path) -and $script:GfPlayerLinkCache[$Path].stamp -eq $stamp) {
        return $script:GfPlayerLinkCache[$Path].links
    }

    # @{} is case-insensitive for string keys, which is what we want for a hex-ish guid.
    $links = @{}
    try {
        $j = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($j -and $j.links) {
            foreach ($prop in $j.links.PSObject.Properties) {
                $guid = ([string]$prop.Name).Trim()
                if (-not $guid) { continue }
                $val = $prop.Value
                $id = ''
                if ($val -is [string]) { $id = [string]$val } elseif ($val) { $id = [string]$val.discordId }
                $id = ($id -replace '[^0-9]', '')   # see the sanitising note in Get-GfPlayerMention
                if (-not $id) { continue }          # a seeded row with no id yet is not an error
                $note = ''
                if ($val -and -not ($val -is [string])) { $note = [string]$val.note }
                $links[$guid] = [pscustomobject]@{ discordId = $id; note = $note }
            }
        }
    } catch {
        # An unreadable table must never take an alert path down: no links is the safe answer,
        # and the alert still sends with everything else intact.
        $links = @{}
    }

    $script:GfPlayerLinkCache[$Path] = @{ stamp = $stamp; links = $links }
    return $links
}

# '<@123…>' for a linked guid, '' for everyone else.
function Get-GfPlayerMention {
    param($Links, [string]$Guid)

    if ($null -eq $Links -or [string]::IsNullOrWhiteSpace($Guid)) { return '' }
    $key = $Guid.Trim()
    if (-not $Links.ContainsKey($key)) { return '' }
    # ⚠ Digits only, enforced at BOTH ends. The id is interpolated straight into text Discord
    # parses, so a malformed or hostile value ('everyone>  <@&role') would otherwise smuggle a
    # different mention into the card. Cheap here, impossible to spot later.
    $id = ([string]$Links[$key].discordId) -replace '[^0-9]', ''
    if (-not $id) { return '' }
    return "<@$id>"
}
