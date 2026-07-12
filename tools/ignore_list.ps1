# Box-local "ignore these players" list - the single source of truth shared by
# GF-StatusService (status_service.ps1) and GF-JoinNotify (join-notify.ps1).
#
# An ignored player is EXCLUDED FROM ACTIVITY, NOT FROM PRESENCE:
#   hidden   - ntfy join/leave pushes, status.json's `recent` ring, the public activity.json feed
#   VISIBLE  - status.json's live `players` list (they still show as online on the website)
#   VISIBLE  - the .secured admin snapshot + admin_history + the players_*.log day-files
# So the owner hopping on and off doesn't spam his own phone or bury the public feed, while the
# site still shows a truthful "who is on right now" and the private ops history stays complete.
#
# Match by GUID (stable across name/IP changes - this is the key `status` itself uses); the
# optional `names` list is a case-insensitive exact-match fallback for a client that connects
# without a usable GUID. A missing/unreadable file means "ignore nobody" - never fatal.
#
# The file is gitignored (a GUID is an account identifier, and this repo is public) and
# /XF-excluded in deploy.ps1, so it lives on the box and no deploy overwrites or deletes it.
# See tools/ignore.example.json for the shape.

$script:GfIgnoreCache = $null
$script:GfIgnoreStamp = $null   # LastWriteTimeUtc ticks of the loaded file; 0 = file absent

# Cached by mtime, so both services pick up an edit within one poll without a restart and
# without re-reading the file every tick.
function Get-GfIgnoreList {
    param([string]$Path)

    $stamp = 0
    try { if (Test-Path $Path) { $stamp = (Get-Item $Path).LastWriteTimeUtc.Ticks } } catch { $stamp = 0 }
    if ($null -ne $script:GfIgnoreCache -and $script:GfIgnoreStamp -eq $stamp) { return $script:GfIgnoreCache }

    $guids = @()
    $names = @()
    if ($stamp -ne 0) {
        try {
            $j = ConvertFrom-Json (Get-Content -Path $Path -Raw -ErrorAction Stop)
            if ($j.guids) { $guids = @($j.guids | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) }
            if ($j.names) { $names = @($j.names | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ }) }
        }
        catch {
            # Bad JSON degrades to "ignore nobody" rather than taking the service down.
            Write-Host ("[ignore] bad {0}: {1}" -f $Path, $_.Exception.Message)
        }
    }

    $script:GfIgnoreStamp = $stamp
    $script:GfIgnoreCache = [pscustomobject]@{ guids = $guids; names = $names }
    return $script:GfIgnoreCache
}

function Test-GfIgnored {
    param($List, [string]$Guid, [string]$Name)

    if ($null -eq $List) { return $false }
    # guid 0 = a client still connecting; it identifies nobody, so never match on it.
    $g = ([string]$Guid).Trim()
    if ($g -and $g -ne '0' -and ($List.guids -contains $g)) { return $true }
    $n = ([string]$Name).Trim().ToLowerInvariant()
    if ($n -and ($List.names -contains $n)) { return $true }
    return $false
}
