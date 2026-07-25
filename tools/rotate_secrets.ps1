param(
    [switch]$Apply,
    [switch]$WhatIf,
    [string]$Password           = "",
    [int]$Length                = 20,
    [int]$MaintenanceMinutes    = 15,
    [int]$PanelPort             = 3000,
    [string]$CfgPath            = "",
    [string]$SecretsPath        = "",
    [switch]$SkipServices,
    [string]$Rollback           = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'common.ps1')   # Resolve-T5Root / Resolve-ModRoot / Get-RconPassword

# ---------------------------------------------------------------------------
# Rotate the LIVE rcon_password on the box, in the right order, updating every
# store that holds a copy. Run ON the VPS, as the account that runs the server.
#
#   .\tools\rotate_secrets.ps1                 # DRY RUN (the default): plan + holder
#                                              #   inventory + manual checklist. Changes NOTHING.
#   .\tools\rotate_secrets.ps1 -Apply          # actually rotate
#   .\tools\rotate_secrets.ps1 -Apply -Password <value>     # bring your own (<=23 chars, alnum)
#   .\tools\rotate_secrets.ps1 -Rollback <dedicated.cfg.rotbak-...>   # undo
#
# SAFE BY DEFAULT. -Apply is the ONLY switch that writes anything; without it the
# script reads, reports and exits 0. -WhatIf is accepted as an explicit spelling of
# that default (it is a plain switch here, NOT the ShouldProcess common parameter --
# this script has no [CmdletBinding()], deliberately, so the two can never be
# confused for one another).
#   Why -Apply and not -Confirm: -Confirm IS a PowerShell common parameter name.
#   Declaring it as an ordinary switch works today but silently changes meaning the
#   moment anyone adds [CmdletBinding()] to this file, and "the safety switch quietly
#   became a prompt" is not a failure mode worth leaving armed.
#
# WHY THIS EXISTS. The risk in rotating this password is not typing it; it is MISSING
# one of the holders, and every miss fails SILENTLY -- a wrong rcon password draws no
# reply at all, which is the same observable as a dead port or a firewall block. The
# ordering below is also load-bearing: the maintenance window goes up FIRST, because a
# stale password in GF-StatusService stops admin.json, and the watchdog reads that as a
# dead server past AdminHardStaleSecs (300) and escalates to killing the bootstrapper
# and bouncing the GF-GameServer task -- mid-rotation.
#
# WHAT IT WILL NOT DO
#   * It never touches the Plutonium SERVER KEY. That lives in
#     C:\gameserver\T5\start_mp_server.bat as `set key=`, its rotation needs an
#     authenticated human at platform.plutonium.pw, and the key's LABEL is the in-game
#     browser name -- a new key with a different label renames the server for every
#     player. It only DETECTS the line and prints the manual steps.
#   * It never rewrites the laptop's copies. Those are in the closing checklist.
#   * It never opens its own RCON socket: every command goes through the panel's single
#     paced queue on 127.0.0.1, per the panel-first rule (a second poller saturates
#     Plutonium's ~1-reply-per-0.7s budget).
#
# NOT FOR THIS JOB: tools\package_server.ps1 -RotateRcon. That builds a bundle from the
# LAPTOP's dedicated.cfg and rotates only that copy; deploying it would OVERWRITE the
# VPS-local dedicated.cfg -- the one file deploy.ps1 deliberately never touches, and the
# sole owner of sv_wwwBaseURL, sv_hostname, g_log, the map rotation, the g_fix_* set and
# the bot tuning. -RotateRcon provisions a NEW box. This script rotates a RUNNING one.
#
# EXIT CODES
#   0  dry run completed, or rotated and verified
#   1  refused at pre-flight (nothing was touched)
#   2  rotation failed and was rolled back
#   3  rotated, but a post-check failed (maintenance window left ARMED on purpose)
# ---------------------------------------------------------------------------

# The <=23 rule is the whole reason this script exists as a script. Plutonium truncates
# rcon_password at 23 chars on login, so a longer value is silently chopped and NEVER
# authenticates -- and it fails identically to a dead network path, which is how a past
# 24-char password burned a debugging session. 20 alnum chars is ~119 bits and keeps a
# margin. Alnum only: no quotes, spaces or cfg/shell metacharacters that could break the
# cfg line or the RCON packet. Same shape as package_server.ps1::New-RconPassword.
$script:RconMaxLen = 23

$script:ExitCode = 0
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Head { param([string]$m) Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host ("  OK    " + $m) -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host ("        " + $m) }
function Write-Warn2{ param([string]$m) Write-Host ("  WARN  " + $m) -ForegroundColor Yellow }
function Write-Bad  { param([string]$m) Write-Host ("  FAIL  " + $m) -ForegroundColor Red }

function New-RconPassword {
    param([int]$Len = 20)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
    $bytes = New-Object 'System.Byte[]' $Len
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (-join ($bytes | ForEach-Object { $chars[ $_ % $chars.Length ] }))
}

function Test-PasswordShape {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value))          { return "empty" }
    if ($Value.Length -gt $script:RconMaxLen)     { return ("too long ({0} chars, Plutonium truncates at {1} and it would NEVER authenticate)" -f $Value.Length, $script:RconMaxLen) }
    if ($Value -notmatch '^[A-Za-z0-9]+$')        { return "not alphanumeric (quotes/spaces/metacharacters break the cfg line or the RCON packet)" }
    return ""
}

# Quote-anchored on BOTH sides. A regex that stops at whitespace swallows the trailing
# // comment and rotates the password to a 264-char string -- the classic silent drop.
$script:RconCfgRe = '(?m)^(\s*set\s+rcon_password\s+)"[^"]*"'

function Get-CfgRconPassword {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return "" }
    $m = [regex]::Match([System.IO.File]::ReadAllText($Path), '(?im)^\s*set[as]?\s+"?rcon_password"?\s+"([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Invoke-PanelStatus {
    param([string]$Pw, [int]$TimeoutSec = 20)
    # Returns $true only on a positive, authenticated reply. Any failure -- wrong
    # password, dead panel, dead server -- returns $false, because on this transport
    # they are genuinely indistinguishable. That is why the caller checks BOTH the new
    # password (must succeed) and the old one (must fail).
    $u = "http://127.0.0.1:{0}/api/status?host=127.0.0.1&port=28960&password={1}" -f $PanelPort, [uri]::EscapeDataString($Pw)
    try {
        $r = Invoke-RestMethod -Uri $u -TimeoutSec $TimeoutSec
        if ($null -eq $r) { return $false }
        return [bool]$r.ok
    } catch {
        return $false
    }
}

function Invoke-PanelRcon {
    param([string]$Pw, [string]$Command, [int]$TimeoutSec = 15)
    # NOTE the panel takes an EXPLICIT password here on purpose. If the panel is later
    # migrated to profile-based credential resolution, an explicitly PRESENT password
    # key must keep winning over any profile -- that back-compat rule is what keeps the
    # box services (and this script) working. Do not "finish the migration" by deleting it.
    $body = @{ host = '127.0.0.1'; port = 28960; password = $Pw; command = $Command; priority = $true } | ConvertTo-Json -Compress
    $u = "http://127.0.0.1:{0}/api/rcon" -f $PanelPort
    return (Invoke-RestMethod -Uri $u -Method Post -ContentType 'application/json' -Body $body -TimeoutSec $TimeoutSec)
}

function Set-MaintenanceWindow {
    param([int]$Minutes, [string]$Reason = 'rcon rotation')
    $dir = Join-Path (Resolve-ModRoot) 'tools\vps_services'
    if (!(Test-Path -LiteralPath $dir)) { return "" }      # watchdog not deployed on this box
    $marker = Join-Path $dir 'watchdog_maintenance.json'
    $obj = @{ until = (Get-Date).AddMinutes($Minutes).ToString('o'); reason = $Reason }
    ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $marker -Encoding UTF8
    return $marker
}

function Clear-MaintenanceWindow {
    param([string]$Marker)
    if ([string]::IsNullOrEmpty($Marker)) { return }
    if (Test-Path -LiteralPath $Marker) { Remove-Item -LiteralPath $Marker -Force -ErrorAction SilentlyContinue }
}

function Set-CfgRconPassword {
    param([string]$Path, [string]$NewPw)
    $txt = [System.IO.File]::ReadAllText($Path)
    if (-not [regex]::IsMatch($txt, $script:RconCfgRe)) {
        # Do NOT append one. On a live box a missing line means we are looking at the
        # wrong file, and appending would create a second source of truth.
        throw ("no quoted 'set rcon_password' line in " + $Path + " -- refusing to append one (wrong file?)")
    }
    $txt = [regex]::Replace($txt, $script:RconCfgRe, ('$1"' + $NewPw + '"'))
    [System.IO.File]::WriteAllText($Path, $txt, $script:Utf8NoBom)
    $back = Get-CfgRconPassword $Path
    if ($back -ne $NewPw) { throw "cfg write did not round-trip in $Path" }
}

function Set-SecretsStore {
    param([string]$Path, [string]$NewPw)
    # UTF-8 with NO BOM: server.js does a plain JSON.parse and a BOM makes it throw, at
    # which point loadSecrets()'s catch returns {} and the panel silently loses EVERY
    # saved password. Never Set-Content -Encoding UTF8 here, never Out-File.
    if (!(Test-Path -LiteralPath $Path)) { return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    $obj = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ($null -eq $obj.profiles) { throw "unexpected shape in $Path (no .profiles)" }
    foreach ($name in @($obj.profiles.PSObject.Properties.Name)) {
        $obj.profiles.$name = $NewPw
    }
    [System.IO.File]::WriteAllText($Path, ($obj | ConvertTo-Json -Depth 6), $script:Utf8NoBom)
    return $true
}

function Restart-BoxService {
    param([string]$Name)
    if (-not (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue)) { return "absent" }
    try {
        Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
        Start-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        return "recycled"
    } catch {
        return ("failed: " + $_.Exception.Message)
    }
}

function Show-ServerKeyChecklist {
    # The Plutonium SERVER KEY is a separate secret with a separate blast radius, and
    # its rotation CANNOT be scripted: platform.plutonium.pw has no API and no CLI, the
    # key value is displayed exactly once at creation, and the whole thing sits behind an
    # authenticated web login. So this only DETECTS the live copy and prints the steps.
    Write-Head "PLUTONIUM SERVER KEY - manual, and only if you are rotating it too"
    if (Test-Path -LiteralPath $LaunchBat) {
        $keyLine = @(Select-String -LiteralPath $LaunchBat -Pattern '^\s*set\s+key=' -ErrorAction SilentlyContinue)
        if ($keyLine.Count -gt 0) {
            Write-Info ("live copy: {0} line {1}  (value not printed)" -f $LaunchBat, $keyLine[0].LineNumber)
        } else {
            Write-Info ("no 'set key=' line found in " + $LaunchBat)
        }
    } else {
        Write-Info ("launch bat not found here: " + $LaunchBat)
    }
    Write-Info  "  1. platform.plutonium.pw/serverkeys -> create a key for Black Ops (T5)."
    Write-Info  "     !! Give it the EXACT SAME LABEL as the current key. The in-game server"
    Write-Info  "        browser shows the key's LABEL, not sv_hostname -- a different label"
    Write-Info  "        renames the server for every player."
    Write-Info  "  2. Copy the value (shown ONCE, never retrievable) into the password manager."
    Write-Info  "  3. Edit 'set key=' in the launch bat, then do a FULL bat restart:"
    Write-Info  "     Stop-ScheduledTask GF-GameServer; Start-ScheduledTask GF-GameServer"
    Write-Info  "     !! Killing the bootstrapper is NOT enough -- 'set key=' runs ABOVE the"
    Write-Info  "        :server label, so the relaunch reuses the OLD %key% already in the"
    Write-Info  "        cmd.exe environment. Same latch as sv_maxclients."
    Write-Info  "  4. VERIFY EXTERNALLY: the server must appear in the in-game browser under"
    Write-Info  "     the expected label. 'the process is running' is NOT verification."
    Write-Info  "  5. Only then revoke the old key at platform.plutonium.pw."
}

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($CfgPath))     { $CfgPath     = Join-Path (Resolve-T5Root)  'dedicated.cfg' }
if ([string]::IsNullOrEmpty($SecretsPath)) { $SecretsPath = Join-Path (Resolve-ModRoot) 'tools\rcon\secrets.local.json' }
$LaunchBat = 'C:\gameserver\T5\start_mp_server.bat'

Write-Host "mp_gunfight - rcon_password rotation" -ForegroundColor Cyan
Write-Host ("Mode:    " + $(if ($Apply) { "APPLY (will write)" } else { "DRY RUN (default - nothing is written)" }))
Write-Host ("Cfg:     " + $CfgPath)
Write-Host ("Secrets: " + $SecretsPath)

if ($Apply -and $WhatIf) {
    Write-Bad "-Apply and -WhatIf are mutually exclusive. Pick one."
    exit 1
}

# ---------------------------------------------------------------------------
# ROLLBACK
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrEmpty($Rollback)) {
    Write-Head "ROLLBACK"
    if (!(Test-Path -LiteralPath $Rollback)) { Write-Bad "backup not found: $Rollback"; exit 1 }
    $rbPw = Get-CfgRconPassword $Rollback
    if ([string]::IsNullOrEmpty($rbPw)) { Write-Bad "no rcon_password in the backup -- refusing to restore it"; exit 1 }
    Write-Info ("backup holds a {0}-char password" -f $rbPw.Length)
    if (-not $Apply) {
        Write-Warn2 "DRY RUN: would copy the backup over $CfgPath and restart the bootstrapper."
        Write-Info  "Re-run with -Apply to actually roll back."
        exit 0
    }
    Set-MaintenanceWindow -Minutes $MaintenanceMinutes -Reason 'rcon rollback' | Out-Null
    Copy-Item -LiteralPath $Rollback -Destination $CfgPath -Force
    Write-Ok "cfg restored from backup"
    Write-Info "restarting the bootstrapper so the bat re-execs dedicated.cfg ..."
    Get-Process -Name 'plutonium-bootstrapper-win32' -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Warn2 "Now revert tools\rcon\secrets.local.json and recycle GF-StatusService / GF-JoinNotify by hand."
    exit 0
}

# ---------------------------------------------------------------------------
# PRE-FLIGHT. Every check here is a REFUSAL, before anything is written.
# ---------------------------------------------------------------------------
Write-Head "PRE-FLIGHT"
$fatal = 0

if (Test-Path -LiteralPath $CfgPath) { Write-Ok "dedicated.cfg found" }
else { Write-Bad "dedicated.cfg not found: $CfgPath"; $fatal++ }

if (Test-Path -LiteralPath $SecretsPath) { Write-Ok "panel secret store found" }
else { Write-Warn2 "panel secret store absent ($SecretsPath) -- the panel will need its password typed in by hand" }

# $env:GF_RCON_PW OVERRIDES the cfg for every PowerShell consumer (common.ps1's
# precedence is explicit -> env -> cfg). A leftover value would leave the game server on
# the new password while status_service / join-notify / watchdog all still use the old
# one. This is the nastiest silent failure in the whole list, so it is fatal.
foreach ($scope in @('Process', 'User', 'Machine')) {
    $v = [Environment]::GetEnvironmentVariable('GF_RCON_PW', $scope)
    if (-not [string]::IsNullOrEmpty($v)) {
        Write-Bad ("GF_RCON_PW is set in the {0} scope -- it would OVERRIDE the rotated cfg. Clear it first." -f $scope)
        $fatal++
    }
}
if ($fatal -eq 0) { Write-Ok "GF_RCON_PW unset in all scopes" }

# tools/notify/config.json's password, if non-empty, WINS over the cfg for the notifier.
$notifyCfg = Join-Path (Resolve-ModRoot) 'tools\notify\config.json'
if (Test-Path -LiteralPath $notifyCfg) {
    try {
        $nj = (Get-Content -LiteralPath $notifyCfg -Raw) | ConvertFrom-Json
        if (-not [string]::IsNullOrEmpty($nj.password)) {
            Write-Bad "tools\notify\config.json carries a non-empty password -- it pins the OLD value. Blank it (it then auto-reads the cfg)."
            $fatal++
        } else { Write-Ok "tools\notify\config.json password is blank (auto-reads the cfg)" }
    } catch { Write-Warn2 "could not parse tools\notify\config.json -- check it by hand" }
}

# A hand-registered task could carry -RconPassword in its arguments.
$tasksWithPw = @()
foreach ($t in @(Get-ScheduledTask -TaskName 'GF-*' -ErrorAction SilentlyContinue)) {
    foreach ($a in @($t.Actions)) {
        if ($a.Arguments -and ($a.Arguments -match '-RconPassword')) { $tasksWithPw += $t.TaskName }
    }
}
if ($tasksWithPw.Count -gt 0) {
    Write-Bad ("these scheduled tasks pass -RconPassword and would keep the old value: " + ($tasksWithPw -join ', '))
    $fatal++
} else { Write-Ok "no GF-* task passes -RconPassword" }

$panelUp = [bool](Get-NetTCPConnection -LocalPort $PanelPort -State Listen -ErrorAction SilentlyContinue)
if ($panelUp) { Write-Ok ("RCON panel listening on 127.0.0.1:{0}" -f $PanelPort) }
else { Write-Bad ("RCON panel is NOT listening on {0} -- it is the only sanctioned transport (panel-first rule)." -f $PanelPort); $fatal++ }

$gameUp = [bool](Get-NetUDPEndpoint -LocalPort 28960 -ErrorAction SilentlyContinue)
if ($gameUp) { Write-Ok "game server up (UDP 28960 bound)" }
else { Write-Bad "game server is DOWN (UDP 28960 not bound) -- nothing to rotate against."; $fatal++ }

$oldPw = Get-CfgRconPassword $CfgPath
if ([string]::IsNullOrEmpty($oldPw)) {
    Write-Bad "no rcon_password value in the cfg -- refusing to guess."
    $fatal++
} else {
    Write-Ok ("current cfg password is {0} chars" -f $oldPw.Length)
}

# Decide the new value now, so its shape is refused BEFORE anything is touched.
$newPw = $Password
if ([string]::IsNullOrEmpty($newPw)) { $newPw = New-RconPassword -Len $Length }
$shapeErr = Test-PasswordShape $newPw
if (-not [string]::IsNullOrEmpty($shapeErr)) {
    Write-Bad ("the new password is " + $shapeErr)
    $fatal++
} else {
    Write-Ok ("new password shape OK ({0} chars, alnum, within the {1}-char Plutonium cap)" -f $newPw.Length, $script:RconMaxLen)
}
if ($newPw -eq $oldPw) { Write-Bad "the new password is identical to the current one."; $fatal++ }

if ($fatal -gt 0) {
    Write-Host ""
    Write-Bad ("{0} pre-flight check(s) failed. NOTHING was changed." -f $fatal)
    exit 1
}

# ---------------------------------------------------------------------------
# HOLDER INVENTORY. Printed in both modes -- it is half the value of the script.
# ---------------------------------------------------------------------------
Write-Head "HOLDERS THIS SCRIPT UPDATES"
Write-Info ("1. dedicated.cfg (sole owner, re-exec'd on every bootstrapper relaunch)  " + $CfgPath)
Write-Info  "2. the LIVE dvar (set over the panel's rcon queue, no restart, no player drop)"
Write-Info ("3. panel secret store, every profile                                     " + $SecretsPath)
Write-Info  "4. GF-StatusService + GF-JoinNotify (both cache the password at process start)"

Write-Head "HOLDERS YOU MUST UPDATE BY HAND"
Write-Info  "5. the password manager (the system of record)"
Write-Info  "6. the LAPTOP's tools\rcon\secrets.local.json, then reload its panel tab"
Write-Info  "7. every open panel tab / PWA (box and tunnel) -- hard reload, they poll with the old value"
$bakList = @(Get-ChildItem -LiteralPath (Split-Path -Parent $CfgPath) -Filter 'dedicated.cfg*' -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne 'dedicated.cfg' })
if ($bakList.Count -gt 0) {
    Write-Info ("8. these cfg BACKUPS still hold the old password (inert, but a hand-restore reverts it):")
    foreach ($b in $bakList) { Write-Info ("     " + $b.Name + "   " + $b.LastWriteTime) }
}
Write-Info  "9. stale bundles: tools\dist\*server*.zip and tools\dist\server-stage\t5\dedicated.cfg"

# ---------------------------------------------------------------------------
# DRY RUN STOPS HERE
# ---------------------------------------------------------------------------
if (-not $Apply) {
    Write-Head "DRY RUN - nothing was written"
    Write-Info  "Re-run with -Apply to rotate. Order that will be used:"
    Write-Info ("  1. arm the watchdog maintenance window ({0} min, self-expiring)" -f $MaintenanceMinutes)
    Write-Info  "  2. back up dedicated.cfg to dedicated.cfg.rotbak-<stamp>"
    Write-Info  "  3. rewrite the cfg line, then read it back and assert it round-tripped"
    Write-Info  "  4. flip the LIVE dvar through the panel using the OLD password"
    Write-Info  "  5. verify BOTH ways: new password must answer, old password must NOT"
    Write-Info  "  6. rewrite the panel secret store (UTF-8, no BOM)"
    Write-Info  "  7. recycle GF-StatusService + GF-JoinNotify"
    Write-Info  "  8. post-check admin.json freshness, then clear the maintenance window"
    Show-ServerKeyChecklist
    exit 0
}

# ---------------------------------------------------------------------------
# APPLY
# ---------------------------------------------------------------------------
$marker = ""
$backup = ""
try {
    Write-Head "1/8  watchdog maintenance window"
    $marker = Set-MaintenanceWindow -Minutes $MaintenanceMinutes
    if ([string]::IsNullOrEmpty($marker)) { Write-Warn2 "watchdog not deployed here -- no window needed" }
    else { Write-Ok ("armed for {0} min (self-expiring): {1}" -f $MaintenanceMinutes, $marker) }

    Write-Head "2/8  back up dedicated.cfg"
    $backup = "{0}.rotbak-{1}" -f $CfgPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $CfgPath -Destination $backup -Force
    Write-Ok ("saved " + $backup)

    Write-Head "3/8  rewrite the cfg (inert until restart -- pure persistence)"
    Set-CfgRconPassword -Path $CfgPath -NewPw $newPw
    Write-Ok "cfg rewritten and read back clean"

    Write-Head "4/8  flip the LIVE dvar (using the OLD password)"
    # From here the old password is dead and every consumer still holding it goes
    # silent. That is expected, not a fault.
    Invoke-PanelRcon -Pw $oldPw -Command ("set rcon_password " + $newPw) | Out-Null
    Write-Ok "live dvar set through the panel queue"
    Start-Sleep -Seconds 2

    Write-Head "5/8  verify (two-sided -- silence alone proves nothing)"
    $newOk = Invoke-PanelStatus -Pw $newPw
    $oldOk = Invoke-PanelStatus -Pw $oldPw
    Write-Info ("new password answers : {0}   (must be True)"  -f $newOk)
    Write-Info ("old password answers : {0}   (must be False)" -f $oldOk)
    if (-not $newOk) { throw "the NEW password does not authenticate" }
    if ($oldOk)      { throw "the OLD password still authenticates -- the live flip did not take" }
    Write-Ok "rotation verified live"
} catch {
    Write-Head "ROTATION FAILED - rolling back"
    Write-Bad $_.Exception.Message
    if (-not [string]::IsNullOrEmpty($backup)) {
        Copy-Item -LiteralPath $backup -Destination $CfgPath -Force
        Write-Ok ("cfg restored from " + $backup)
    }
    Write-Info "restarting the bootstrapper so the bat re-execs the restored cfg ..."
    Get-Process -Name 'plutonium-bootstrapper-win32' -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Warn2 "maintenance window LEFT ARMED while it settles -- it self-expires."
    Write-Host ""
    Write-Info "Ground truth, one variable at a time (wrong password, blocked port and dead"
    Write-Info "server all look identical here):"
    Write-Info "  Get-NetUDPEndpoint -LocalPort 28960          # is the server even up"
    Write-Info "  Get-Content <mod>\console_mp.log -Tail 40    # is it live"
    Write-Info "  Get-Process plutonium                        # a wedged -update-only"
    exit 2
}

Write-Head "6/8  panel secret store"
try {
    if (Set-SecretsStore -Path $SecretsPath -NewPw $newPw) { Write-Ok "every profile in secrets.local.json updated (UTF-8, no BOM)" }
    else { Write-Warn2 "no secrets.local.json here -- type the new password into the panel instead" }
} catch {
    Write-Bad ("secret store update failed: " + $_.Exception.Message)
    Write-Warn2 "type the new password into the panel by hand (it POSTs /api/secrets)."
    $script:ExitCode = 3
}

Write-Head "7/8  recycle the services that cached the old value"
if ($SkipServices) { Write-Warn2 "-SkipServices: skipped (they will keep failing until recycled)" }
else {
    foreach ($svc in @('GF-StatusService', 'GF-JoinNotify')) {
        $r = Restart-BoxService $svc
        if ($r -eq 'recycled')   { Write-Ok ($svc + " recycled") }
        elseif ($r -eq 'absent') { Write-Info ($svc + " not installed here") }
        else { Write-Warn2 ($svc + " " + $r); $script:ExitCode = 3 }
    }
}

Write-Head "8/8  post-check"
Start-Sleep -Seconds 25
$adminJson = 'C:\inetpub\wwwroot\admin\live\admin.json'
if (Test-Path -LiteralPath $adminJson) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $adminJson).LastWriteTime).TotalSeconds
    if ($age -lt 60) { Write-Ok ("admin.json is fresh ({0:N0}s) -- GF-StatusService is alive on the new password" -f $age) }
    else { Write-Bad ("admin.json is {0:N0}s stale -- GF-StatusService is NOT reading. Check it before leaving." -f $age); $script:ExitCode = 3 }
} else { Write-Info "admin.json not present here -- skipping the freshness check" }

if ($script:ExitCode -eq 0) {
    Clear-MaintenanceWindow $marker
    Write-Ok "maintenance window cleared"
} else {
    Write-Warn2 "post-check did not pass cleanly -- maintenance window LEFT ARMED (it self-expires)."
}

# ---------------------------------------------------------------------------
# The one thing that cannot be automated, and the value, printed once.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " NEW rcon_password (live now, and in dedicated.cfg):" -ForegroundColor Green
Write-Host ""
Write-Host ("     " + $newPw) -ForegroundColor Cyan
Write-Host ""
Write-Host " Save it to the password manager NOW. It is not printed again," -ForegroundColor Green
Write-Host " and it is only in this scrollback." -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green

Write-Head "STILL TO DO BY HAND"
Write-Info "  [ ] password manager updated"
Write-Info "  [ ] laptop tools\rcon\secrets.local.json updated, laptop panel reloaded"
Write-Info "  [ ] every open panel tab / PWA hard-reloaded (box and SSH tunnel)"
if ($bakList.Count -gt 0) { Write-Info "  [ ] old dedicated.cfg.* backups reviewed (they still hold the previous password)" }
Write-Info "  [ ] stale tools\dist\*server*.zip / server-stage cfg deleted"
Show-ServerKeyChecklist

exit $script:ExitCode
