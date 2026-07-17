# ntfy push - the single sender shared by every box service that alerts a phone
# (GF-JoinNotify, GF-SecurityWatch, ...). Dot-source it, like tools\ignore_list.ps1.
#
# Sent as ntfy's JSON publish format: the topic travels in the BODY and the server URL is the
# bare root, so title/message/tags are all fields of one UTF-8 JSON document.
#
# This is deliberately NOT the X-Title/Priority/Tags HEADER form: HTTP header values are ASCII,
# and titles here carry emoji (a flag is a 4-byte code point built from a surrogate pair) - a
# header cannot survive that. With JSON every field is unicode-safe. Do NOT move a title back
# into a header.
#
# `priority` is a NUMBER in JSON (the header form accepted the names). Callers pass the names
# and this maps them, so an unknown name degrades to normal rather than throwing.
#
# ⚠ tools\vps_services\watchdog.ps1 still carries its OWN older header-form sender (Send-Alert).
# It works and predates this file; fold it in here when convenient rather than growing a third
# copy.

$script:GfNtfyPriority = @{ min = 1; low = 2; default = 3; high = 4; max = 5 }

# Why a send failed, for the caller to log. Send-GfNtfy returns only $true/$false so a failed
# alert can never take a service down - but a silent false is undiagnosable, so the reason is
# parked here rather than thrown.
$script:GfNtfyLastError = ''

# Reads the shared notify config (tools\notify\config.json) - the same topic every service
# pushes to. Returns $null when it's absent/topicless, which every caller must treat as
# "cannot alert", never as fatal.
function Get-GfNtfyConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    try {
        $j = Get-Content $Path -Raw | ConvertFrom-Json
        if (-not $j.ntfyTopic) { return $null }
        $server = 'https://ntfy.sh'
        if ($j.ntfyServer) { $server = ([string]$j.ntfyServer).TrimEnd('/') }
        return [pscustomobject]@{
            ntfyTopic  = [string]$j.ntfyTopic
            ntfyServer = $server
            ntfyToken  = [string]$j.ntfyToken
            serverName = $(if ($j.serverName) { [string]$j.serverName } else { 'Gunfight' })
        }
    }
    catch { return $null }
}

# $cfg needs .ntfyTopic / .ntfyServer / .ntfyToken - either Get-GfNtfyConfig's object or any
# object carrying those. $tags is an array of emoji shortcodes; ntfy renders them immediately
# BEFORE the title, so a tag reads as a badge on the alert.
function Send-GfNtfy {
    param($Config, [string]$Title, [string]$Message, [string]$Priority = 'default', [string[]]$Tags = @())

    $script:GfNtfyLastError = ''
    if ($null -eq $Config -or -not $Config.ntfyTopic) {
        $script:GfNtfyLastError = 'no topic configured'
        return $false
    }
    $prio = 3
    if ($script:GfNtfyPriority.ContainsKey($Priority)) { $prio = $script:GfNtfyPriority[$Priority] }
    # [string[]] forces a JSON array even for a single tag (ConvertTo-Json unwraps a lone element).
    $payload = [ordered]@{
        topic    = [string]$Config.ntfyTopic
        title    = $Title
        message  = $Message
        priority = $prio
        tags     = [string[]]@($Tags)
    }
    $headers = @{}
    if ($Config.ntfyToken) { $headers['Authorization'] = "Bearer $($Config.ntfyToken)" }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Compress -Depth 4))
        Invoke-RestMethod -Uri $Config.ntfyServer -Method Post -Body $bytes -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
        return $true
    }
    catch {
        $script:GfNtfyLastError = $_.Exception.Message
        return $false
    }
}
