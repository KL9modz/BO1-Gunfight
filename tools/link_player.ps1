# Link a player to a Discord user id, so their join card names them in Discord.
#
#   .\link_player.ps1 -Name 6foot1 -DiscordId 414945691606056973
#   .\link_player.ps1 -Name Tender -Show          # just show what would match
#   .\link_player.ps1 -List                       # everything currently linked
#
# Writes tools\players.local.json, which GF-JoinNotify re-reads on change - no restart. The table
# is keyed by GUID and gitignored for that reason; this script exists so linking someone never
# means hand-editing a file full of player GUIDs.
#
# ⚠ REFUSES AN AMBIGUOUS NAME rather than guessing. Names are not unique and are not stable: the
# same person can hold several GUIDs and the same name can belong to two people. Writing the wrong
# row would put someone else's Discord identity on a stranger's join card, which is worse than any
# amount of inconvenience here - so 0 or 2+ matches is an error with the candidates printed.
[CmdletBinding()]
param(
    [string] $Name = '',
    [string] $DiscordId = '',
    [switch] $Show,      # resolve the name, change nothing
    [switch] $List,      # print current links
    [switch] $Unlink,
    [string] $TablePath = '',
    [string] $LogDir    = ''
)
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'player_links.ps1')
. (Join-Path $PSScriptRoot 'common.ps1')      # Resolve-T5Root

if (-not $TablePath) { $TablePath = Join-Path $PSScriptRoot 'players.local.json' }
if (-not $LogDir) {
    try { $LogDir = Join-Path (Resolve-T5Root) 'logs' } catch { $LogDir = '' }
}

function Read-Table {
    if (-not (Test-Path $TablePath)) {
        return [pscustomobject]@{
            _comment = 'Box-local player GUID to Discord user id table, read by GF-JoinNotify. NEVER commit this file: it holds player GUIDs.'
            links    = [pscustomobject]@{}
        }
    }
    return (Get-Content -LiteralPath $TablePath -Raw | ConvertFrom-Json)
}
function Write-Table($j) {
    # ConvertTo-Json, never hand-built text - a hand-escaped quote once shipped an unparseable
    # config template in this repo.
    ($j | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $TablePath -Encoding UTF8
}
function Get-NameFromNote($note) { return (([string]$note) -replace '\s*\(\d+ connects\)$', '') }

$table = Read-Table

if ($List) {
    $links = Get-GfPlayerLinks $TablePath
    if ($links.Count -eq 0) { Write-Host 'No players linked yet.'; return }
    Write-Host "$($links.Count) player(s) linked:"
    foreach ($p in $table.links.PSObject.Properties) {
        if (-not $p.Value.discordId) { continue }
        '  {0,-22} <@{1}>' -f (Get-NameFromNote $p.Value.note), $p.Value.discordId | Write-Host
    }
    return
}

if (-not $Name) { throw 'give -Name (a substring of the player name), or -List' }

# 1) look in the table first - it carries the seeded regulars
$rows = @($table.links.PSObject.Properties | Where-Object { $_.Value.note -like "*$Name*" })

# 2) not there? search the connect history, so anyone who has ever joined can be linked
if ($rows.Count -eq 0 -and $LogDir -and (Test-Path $LogDir)) {
    $found = @{}; $count = @{}
    foreach ($f in (Get-ChildItem $LogDir -Filter 'players_*.log' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        foreach ($line in (Get-Content $f.FullName)) {
            $m = [regex]::Match($line, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s+CONNECT\s+.*name="(.*)"\s+guid=(\S+)')
            if (-not $m.Success) { continue }
            $pname = $m.Groups[1].Value
            if ($pname -notlike "*$Name*") { continue }
            $g = $m.Groups[2].Value
            $found[$g] = $pname
            $count[$g] = 1 + $(if ($count.ContainsKey($g)) { $count[$g] } else { 0 })
        }
    }
    if ($found.Count -eq 1) {
        $g = @($found.Keys)[0]
        # Add the row now so the write path below is the same one the table rows take.
        $table.links | Add-Member -NotePropertyName $g `
            -NotePropertyValue ([pscustomobject]@{ discordId = ''; note = ('{0} ({1} connects)' -f $found[$g], $count[$g]) }) -Force
        $rows = @($table.links.PSObject.Properties | Where-Object { $_.Name -eq $g })
        Write-Host "found '$($found[$g])' in the connect history (not previously in the table)"
    } elseif ($found.Count -gt 1) {
        Write-Host "'$Name' matches $($found.Count) players in the connect history:"
        foreach ($g in $found.Keys) { '  {0}  ({1} connects)' -f $found[$g], $count[$g] | Write-Host }
        throw 'ambiguous - use a longer name'
    }
}

if ($rows.Count -eq 0)    { throw "no player matches '$Name'" }
if ($rows.Count -gt 1) {
    Write-Host "'$Name' matches $($rows.Count) rows:"
    foreach ($r in $rows) { '  {0}' -f $r.Value.note | Write-Host }
    throw 'ambiguous - use a longer name'
}

$row = $rows[0]
if ($Show) {
    '{0}  ->  {1}' -f (Get-NameFromNote $row.Value.note), $(if ($row.Value.discordId) { "<@$($row.Value.discordId)>" } else { '(not linked)' }) | Write-Host
    return
}
if ($Unlink) {
    $row.Value.discordId = ''
    Write-Table $table
    Write-Host "unlinked $(Get-NameFromNote $row.Value.note)"
    return
}

# ⚠ Shape-check the id. A Discord user id is a 17-20 digit snowflake; a username, a display name
# or a pasted mention are the three things people reach for instead, and all three would sit in
# the table looking plausible while resolving to nothing.
if ($DiscordId -notmatch '^\d{17,20}$') {
    throw "'$DiscordId' is not a Discord user id (17-20 digits). Enable Developer Mode, then right-click the user and Copy User ID."
}

$row.Value.discordId = $DiscordId
Write-Table $table

# Read it back through the LOADER the service uses, so success means "the service will see this",
# not merely "the file was written".
$links = Get-GfPlayerLinks $TablePath
$mention = Get-GfPlayerMention $links $row.Name
if (-not $mention) { throw "wrote the row but the loader does not resolve it - check $TablePath" }
Write-Host ('linked {0}  ->  {1}   ({2} player(s) linked)' -f (Get-NameFromNote $row.Value.note), $mention, $links.Count)
