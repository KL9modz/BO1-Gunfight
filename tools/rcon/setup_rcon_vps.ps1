# setup_rcon_vps.ps1 - run the RCON admin panel ON the VPS, loopback-only (run ON the box)
# ------------------------------------------------------------------------------
# Installs Node LTS if missing, writes secrets.local.json from dedicated.cfg's
# rcon_password (so RCON never leaves the box - it talks to 127.0.0.1:28960), and
# registers GF-RconPanel as a boot-start SYSTEM task running `node server.js` bound
# to 127.0.0.1:3000. The panel is NEVER exposed to the internet (loopback bind +
# server.js Host-header allowlist). Reach it from your machine via an SSH tunnel:
#
#   ssh -i ~/.ssh/gf_vps -L 3000:127.0.0.1:3000 Administrator@94.72.121.4
#   then browse http://localhost:3000  and pick the "Local (listen)" profile.
#
# (Stop any laptop-side server.js on 3000 first, or the tunnel can't bind 3000.)
#
# Run ELEVATED (Administrator) on the box.  Windows PowerShell 5.1.  ASCII-only.
#   powershell -ExecutionPolicy Bypass -File setup_rcon_vps.ps1
#   powershell -ExecutionPolicy Bypass -File setup_rcon_vps.ps1 -Uninstall
# ------------------------------------------------------------------------------

param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

$taskName = 'GF-RconPanel'
$rconDir  = $PSScriptRoot                         # this script lives in tools\rcon
$serverJs = Join-Path $rconDir 'server.js'
$secrets  = Join-Path $rconDir 'secrets.local.json'
$cfgPath  = Join-Path $rconDir '..\..\..\..\dedicated.cfg'   # -> storage\t5\dedicated.cfg

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this elevated (Administrator)." }

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed $taskName."
    } else { Write-Host "$taskName not registered." }
    return
}

if (-not (Test-Path $serverJs)) { throw "server.js not found next to this script ($serverJs)." }

# --- 1. Node LTS -------------------------------------------------------------
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node -or -not (Test-Path $node)) { $node = 'C:\Program Files\nodejs\node.exe' }
if (-not (Test-Path $node)) {
    Write-Host "Node not found - installing latest LTS from nodejs.org ..."
    $idx = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 30
    $ver = ($idx | Where-Object { $_.lts })[0].version           # index is newest-first
    $url = "https://nodejs.org/dist/$ver/node-$ver-x64.msi"
    $msi = Join-Path $env:TEMP 'node-lts-x64.msi'
    Write-Host "  downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing -TimeoutSec 180
    Write-Host "  installing (silent) ..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Node MSI install failed (exit $($p.ExitCode))." }
    $node = 'C:\Program Files\nodejs\node.exe'
    if (-not (Test-Path $node)) { throw "Node install did not produce $node." }
}
Write-Host ("Node: {0}  ({1})" -f $node, (& $node -v))

# --- 2. secrets.local.json (loopback profile, password from dedicated.cfg) ----
# server.js maps profile-name -> rcon_password. The panel's built-in loopback
# profile is named "Local (listen)" (127.0.0.1:28960), so key the secret to that.
if (Test-Path $secrets) {
    Write-Host "secrets.local.json already present - leaving it as-is."
} else {
    if (-not (Test-Path $cfgPath)) { throw "dedicated.cfg not found at $cfgPath - cannot read rcon_password." }
    $pw = ([regex]::Match((Get-Content $cfgPath -Raw), 'set\s+rcon_password\s+"([^"]*)"')).Groups[1].Value
    if ([string]::IsNullOrEmpty($pw)) { throw "No rcon_password found in dedicated.cfg." }
    # ConvertTo-Json is fine for the shape { profiles: { name: pw } }
    $obj = @{ profiles = @{ 'Local (listen)' = $pw } }
    ($obj | ConvertTo-Json -Depth 4) | Set-Content -Path $secrets -Encoding UTF8
    Write-Host "Wrote secrets.local.json (profile 'Local (listen)')."
}

# --- 3. GF-RconPanel boot-start task (SYSTEM, loopback, restart-on-exit) -------
$action = New-ScheduledTaskAction -Execute $node -Argument ('"{0}"' -f $serverJs) -WorkingDirectory $rconDir
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
Register-ScheduledTask -TaskName $taskName `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'GF RCON admin panel - loopback 127.0.0.1:3000, reach via SSH tunnel (never public).' | Out-Null
Start-ScheduledTask -TaskName $taskName

Start-Sleep -Seconds 4
$listening = [bool](Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue)
Write-Host ""
Write-Host "GF-RconPanel registered + started. Listening on 127.0.0.1:3000 = $listening"
Write-Host "From your machine:"
Write-Host "  ssh -i ~/.ssh/gf_vps -L 3000:127.0.0.1:3000 Administrator@94.72.121.4"
Write-Host "  then open http://localhost:3000  and select the 'Local (listen)' profile."
