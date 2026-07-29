# status_parse.ps1 - the ONE PowerShell-side parser for the Plutonium T5 `status` reply.
# ------------------------------------------------------------------------------
# TWIN of tools\status_parse.js - change one, change both. The shared fixture
# tools\tests\fixtures\status_reply.txt is parsed by BOTH test suites
# (tools\rcon\test\server.test.js + tools\tests\status_parse.Tests.ps1), so a one-sided
# edit fails the other side's mirror case.
#
# Consumers dot-source this file: status_service.ps1 and notify\join-notify.ps1 - and both
# reach it ONLY on their panel-down FALLBACK path. The happy path consumes the RCON panel's
# already-parsed JSON (/api/tick, /api/status), so the .js twin does the parsing box-wide
# and this copy exists so a dead panel does not blind the status snapshot or the phone alerts.
#
# The doctrine (full rationale in the .js twin's header):
#   * Columns are END-ANCHORED - names can contain spaces ("MCG Gordon"): address is the
#     3rd-from-last token, name is everything between guid and lastmsg. Never p[4]/p[6].
#   * The address port may be NEGATIVE (signed 16-bit print): `-?` on the port is
#     load-bearing or ~half of real players lose IP/notify/history.
#   * bot is THREE-STATE and a POSITIVE claim: $false = provably human (routable ip:port or
#     loopback), $true = guid 0 at a known bot marker, $null = COULD NOT TELL (a
#     still-connecting client, a split reply). $null is never actionable - a caller may act
#     only on an exact $true/$false, never a truthiness test.
#
# Output shape mirrors the panel's /api/status JSON exactly, so a consumer can swap this
# in for the panel object without projection:
#   map, gametype, listenServer, players[] of
#   { num; score; ping($null when "CNCT"/"ZMBI"); guid; name; bot; local; addr; ip }
#   (ip = 'local' for the listen host, bare address for a human, $null otherwise)
#
# Windows PowerShell 5.1 compatible. ASCII-only source.
# ------------------------------------------------------------------------------

function Remove-GfColors {
    param([string]$s)
    return ($s -replace '\^[0-9a-zA-Z]', '').Trim()
}

function ConvertFrom-GfStatus {
    param([string]$text)
    $players = New-Object System.Collections.ArrayList
    $result  = [pscustomobject]@{ map = ''; gametype = ''; listenServer = $false; players = $players }
    $lines   = [string]$text -split "`n"

    $sepIdx = -1
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i].Trim()
        if ($line -match '^map:\s*(.+)')      { $result.map      = Remove-GfColors $Matches[1]; continue }
        if ($line -match '^gametype:\s*(.+)') { $result.gametype = Remove-GfColors $Matches[1]; continue }
        if ($sepIdx -lt 0 -and $line -match '^---') { $sepIdx = $i }
    }

    if ($sepIdx -ge 0) {
        for ($i = $sepIdx + 1; $i -lt $lines.Length; $i++) {
            $line = $lines[$i].Trim()
            if ($line -eq '') { continue }
            $p = $line -split '\s+'
            if ($p.Length -lt 8 -or $p[0] -notmatch '^\d+$') { continue }
            $addr    = $p[$p.Length - 3]
            $nameEnd = $p.Length - 5
            $name = ''
            if ($nameEnd -ge 4) { $name = Remove-GfColors ($p[4..$nameEnd] -join ' ') }
            if ($name -eq '') { continue }
            $isLocal = ($addr -eq 'loopback' -or $addr -eq 'local')
            $isHuman = $isLocal -or ($addr -match '^\d{1,3}(\.\d{1,3}){3}:-?\d+$')
            $isBot   = (-not $isHuman) -and ($p[3] -eq '0') -and ($addr -match '^(unknown|bot|0\.0\.0\.0(:\d+)?)$')
            $bot = $null
            if ($isHuman) { $bot = $false } elseif ($isBot) { $bot = $true }
            if ($isLocal) { $result.listenServer = $true }
            $ip = $null
            if ($isHuman) { if ($isLocal) { $ip = 'local' } else { $ip = ($addr -split ':')[0] } }
            $score = $null
            if ($p[1] -match '^-?\d+$') { $score = [int]$p[1] }
            $ping = $null
            if ($p[2] -match '^\d+$')   { $ping  = [int]$p[2] }
            [void]$players.Add([pscustomobject]@{
                num   = [int]$p[0]
                score = $score
                ping  = $ping
                guid  = $p[3]
                name  = $name
                bot   = $bot
                local = $isLocal
                addr  = $addr
                ip    = $ip
            })
        }
    }
    return $result
}
