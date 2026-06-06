param(
    [Parameter(Mandatory=$true)][string]$InflatedFile,
    [string]$OutJson = "",
    [string]$Classname = "",
    [string]$Contains = ""
)

$ErrorActionPreference = "Stop"

function Convert-Entity {
    param([hashtable]$Table)
    $ordered = [ordered]@{}
    foreach ($key in ($Table.Keys | Sort-Object)) {
        $ordered[$key] = $Table[$key]
    }
    [pscustomobject]$ordered
}

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $InflatedFile))
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$lines = $text -split "`n"

$entities = [System.Collections.Generic.List[object]]::new()
$current = $null

foreach ($raw in $lines) {
    $line = $raw.Trim("`r", " ", "`t", "`0")
    if ($line -eq "{") {
        $current = @{}
        continue
    }
    if ($line -eq "}") {
        if ($null -ne $current -and $current.ContainsKey("classname")) {
            [void]$entities.Add((Convert-Entity $current))
        }
        $current = $null
        continue
    }
    if ($null -eq $current) {
        continue
    }
    if ($line -match '^"([^"]+)"\s+"([^"]*)"$') {
        $current[$Matches[1]] = $Matches[2]
    }
}

$filtered = @($entities)
if ($Classname -ne "") {
    $filtered = @($filtered | Where-Object { $_.classname -eq $Classname })
}
if ($Contains -ne "") {
    $filtered = @($filtered | Where-Object { ($_ | ConvertTo-Json -Compress -Depth 4) -match [regex]::Escape($Contains) })
}

if ($OutJson -ne "") {
    $filtered | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutJson -Encoding UTF8
}

$classCounts = $entities | Group-Object classname | Sort-Object Count -Descending
Write-Host "Parsed entities: $($entities.Count)"
Write-Host "Filtered entities: $($filtered.Count)"
Write-Host "Top classnames:"
foreach ($group in ($classCounts | Select-Object -First 20)) {
    Write-Host ("  {0,-24} {1}" -f $group.Name, $group.Count)
}

if ($filtered.Count -gt 0) {
    Write-Host ""
    Write-Host "Filtered preview:"
    $filtered | Select-Object -First 20 | Format-Table -AutoSize
}
