# Shared PowerShell helpers for the mp_gunfight tooling. Dot-source it, like
# tools\release_common.ps1 / tools\ignore_list.ps1:
#   . (Join-Path $PSScriptRoot 'common.ps1')       # from a tools\ script
#   . (Join-Path $PSScriptRoot '..\common.ps1')    # from a tools\<subdir>\ script
#
# One source of truth for what used to be copy-pasted across the packagers, deploy,
# rotate_secrets and the box services: the storage-tree path walk (T5 root / mod root),
# reading rcon_password out of dedicated.cfg, the fastfile-build wrapper, and the ops
# primitives (password generator, maintenance marker, panel-rcon POST, task recycle).

# This file's own directory (…\storage\t5\mods\mp_gunfight\tools), captured at dot-source
# time so the path helpers below don't depend on WHICH script called them — the same trick
# release_common.ps1 uses with its $script:-scoped state.
$script:GfToolsRoot = $PSScriptRoot

# (The Get-GfDefault* getters and their $script:GfDefault* variables are deleted: nothing ever
# called them — the literals they claimed to deduplicate still sit in each script's param
# defaults, and a param default CANNOT read a dot-sourced function anyway (params bind before
# the dot-source runs). The per-script defaults are the working design.)

# The T5 storage root (…\storage\t5). common.ps1 lives in <T5>\mods\mp_gunfight\tools, so
# T5 is three parents up. Split-Path (not Resolve-Path) so it never requires the path to
# exist — identical result to the ops scripts' prior four-parents-up walk from tools\<subdir>\
# (this file sits one level ABOVE those subdirs, hence 3 vs 4).
function Resolve-T5Root {
    $r = $script:GfToolsRoot
    for ($i = 0; $i -lt 3; $i++) { $r = Split-Path -Parent $r }
    return $r
}

# The mod folder (…\mods\mp_gunfight) — one parent up from tools\.
function Resolve-ModRoot {
    return (Split-Path -Parent $script:GfToolsRoot)
}

# Read rcon_password from a dedicated.cfg, with the precedence the callers used: an explicit
# value wins, then $env:GF_RCON_PW, then the cfg file. Uses the most permissive of the prior
# regexes (set/seta, optional quotes around the dvar name) so it is a strict superset of every
# prior reader — for an ordinary set-password cfg line the result is identical. Returns ''
# when nothing is found; a caller that must throw on empty still does so itself.
# File-ONLY read of rcon_password from a cfg — no explicit/env precedence. This is the read
# rotate_secrets.ps1 verifies its writes with (round-trip check), where an env override would
# make a failed cfg write look successful; Get-RconPassword below layers the precedence on top.
function Get-GfCfgRconPassword {
    param([string]$Path)
    if (-not ($Path -and (Test-Path -LiteralPath $Path))) { return '' }
    $m = [regex]::Match([System.IO.File]::ReadAllText($Path), '(?im)^\s*set[as]?\s+"?rcon_password"?\s+"([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-RconPassword {
    param(
        [string]$Explicit,
        [string]$CfgPath
    )
    if (-not [string]::IsNullOrEmpty($Explicit))       { return $Explicit }
    if (-not [string]::IsNullOrEmpty($env:GF_RCON_PW)) { return $env:GF_RCON_PW }
    return (Get-GfCfgRconPassword -Path $CfgPath)
}

# ── Ops primitives shared by deploy.ps1 / rotate_secrets.ps1 / the box services ──────────
# Each of these existed as two (or three) hand-copied twins; the copies had already begun to
# drift in harmless ways (param names, string vs int port). One definition each, callers keep
# their own policy wrappers (DryRun gates, logging, password resolution).

# Cryptographically-random alphanumeric password. Alnum only on purpose: no quotes, spaces,
# or shell/cfg metacharacters that could break the cfg line or the RCON protocol. Callers cap
# length at 20 — Plutonium truncates the rcon password at 23 chars on login, so any longer
# value is silently chopped and never matches ([[rcon-tool-vps-connect-23char-cap]]).
function New-RconPassword {
    param([int]$Length = 20)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
    $bytes = New-Object 'System.Byte[]' $Length
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (-join ($bytes | ForEach-Object { $chars[ $_ % $chars.Length ] }))
}

# Drop the self-expiring watchdog maintenance marker into $Dir (a tools\vps_services folder).
# Returns the marker path, or "" when the dir is absent (watchdog not deployed on this box).
# Callers own WHICH tree: deploy writes into the DEPLOYED mod folder ($ModDest — where the
# SYSTEM watchdog reads it, never the clone), rotate into its own Resolve-ModRoot (it runs
# from the deployed folder on the box). Self-expiring by design: an aborted caller can never
# leave the watchdog disabled.
function Write-GfMaintenanceMarker {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [int]$Minutes = 5,
        [string]$Reason = 'maintenance'
    )
    if (!(Test-Path -LiteralPath $Dir)) { return "" }
    $marker = Join-Path $Dir 'watchdog_maintenance.json'
    (@{ until = (Get-Date).AddMinutes($Minutes).ToString('o'); reason = $Reason } | ConvertTo-Json -Compress) |
        Set-Content -LiteralPath $marker -Encoding UTF8
    return $marker
}

# One rcon command THROUGH the panel API (the single box-side rcon pacer — never a second
# direct UDP sender; [[rcon-panel-queue-saturation]]). Takes an EXPLICIT password on purpose:
# rotate_secrets must probe with a password that is deliberately not the resolved one (it
# checks the NEW value works AND the OLD one fails), and the panel's presence-beats-profile
# rule is what keeps an explicit password= working. Throws on transport failure — callers
# that want a bool wrap it (watchdog's Send-PanelRcon).
function Invoke-GfPanelRcon {
    param(
        [string]$Pw,
        [Parameter(Mandatory)][string]$Command,
        [int]$PanelPort = 3000,
        [int]$TimeoutSec = 15,
        # Target game server as seen FROM the panel. Defaults cover the box; parameters exist so
        # a caller that already carries -RconHost/-RconPort (conn_logger) loses nothing by
        # consolidating onto this helper instead of hand-rolling the POST.
        [string]$RconHost = '127.0.0.1',
        [int]$RconPort = 28960
    )
    $body = @{ host = $RconHost; port = $RconPort; password = $Pw; command = $Command; priority = $true } | ConvertTo-Json -Compress
    return (Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/api/rcon" -f $PanelPort) -Method Post -ContentType 'application/json' -Body $body -TimeoutSec $TimeoutSec)
}

# Stop+start one scheduled task (the load-once box services re-read their script only on a
# recycle). Returns "absent" / "recycled" / "failed: <why>" — callers print/log per policy.
# Never throws: a guard that dies on a locked task would just get switched off.
function Restart-GfScheduledTask {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$SettleMs = 400
    )
    if (-not (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue)) { return "absent" }
    try {
        Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds $SettleMs
        Start-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        return "recycled"
    } catch {
        return ("failed: " + $_.Exception.Message)
    }
}

# Build mod.ff via the shared build_ff.ps1 (the linker invocation itself lives only there).
# This ~8-line wrapper was byte-identical in both packagers. -ModFf, when given, is the
# expected output path checked after the build.
function Invoke-BuildFf {
    param(
        [Parameter(Mandatory)][string]$GameRoot,
        [Parameter(Mandatory)][string]$ModName,
        [switch]$SkipBuild,
        [string]$ModFf
    )
    if (-not $SkipBuild) {
        $buildScript = Join-Path $script:GfToolsRoot 'build_ff.ps1'
        if (!(Test-Path -LiteralPath $buildScript)) { throw "build_ff.ps1 not found: $buildScript" }
        Write-Host ""
        Write-Host "Building mod.ff ..."
        & $buildScript -GameRoot $GameRoot -ModName $ModName
        if ($LASTEXITCODE -ne 0) { throw "build_ff.ps1 failed (exit $LASTEXITCODE)" }
    }
    if ($ModFf -and !(Test-Path -LiteralPath $ModFf)) { throw "mod.ff not found (build it first): $ModFf" }
}
