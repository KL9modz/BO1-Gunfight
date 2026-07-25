# setup_rcon_vps.ps1 - run the RCON admin panel ON the VPS, loopback-only (run ON the box)
# ------------------------------------------------------------------------------
# Installs Node LTS if missing, writes the two gitignored credential files -
# servers.local.json (one LOOPBACK profile) and secrets.local.json (its password,
# read out of dedicated.cfg) - so RCON never leaves the box: it talks to
# 127.0.0.1:28960. Then registers GF-RconPanel as a boot-start SYSTEM task running
# `node server.js` bound to 127.0.0.1:3000, under cmd.exe so the panel's stdout and
# stderr land in <mod>\logs\panel.log instead of nowhere. The panel is NEVER exposed
# to the internet (loopback bind + server.js Host-header allowlist).
#
# Reach it from your machine via an SSH tunnel - THE RECOMMENDED laptop -> VPS path,
# because the panel then resolves its own credentials box-side and nothing sensitive
# crosses the internet (direct public rcon puts the password in a cleartext UDP packet):
#
#   ssh -L 3000:127.0.0.1:3000 gf-vps
#   then browse http://localhost:3000  and pick the "Local" profile
#   (127.0.0.1:28960 = the VPS's own dedicated server, seen from the box).
#
# `gf-vps` is an SSH alias - put HostName/User/IdentityFile in ~/.ssh/config so no
# address is typed (or kept in this repo). The box's real address lives in your
# gitignored ops notes; the panel's own server list lives in servers.local.json.
#
# (Stop any laptop-side server.js on 3000 first, or the tunnel can't bind 3000.
#  tools/rcon/start.bat pins the LAPTOP panel to 3005 for exactly this reason.)
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
$servers  = Join-Path $rconDir 'servers.local.json'
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

# --- 2. servers.local.json + secrets.local.json (ONE loopback profile) --------
# server.js joins the two files on the profile NAME: servers.local.json gives host/port,
# secrets.local.json gives that name's rcon_password. On the box only "Local" makes sense
# (loopback -> this box's own dedicated server); reaching the box by its own public IP
# would hairpin out and back for nothing, so it is deliberately not written here.
# NO-BOM UTF-8 for BOTH files: PowerShell's `Set-Content -Encoding UTF8` writes a BOM,
# which makes server.js's JSON.parse THROW. The failure is SILENT and differs per file -
# a BOM'd secrets file = zero saved passwords (Connect fails auth); a BOM'd servers file
# = the profile dropdown falls back to its built-in loopback default. Write without one.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (Test-Path $servers) {
    Write-Host "servers.local.json already present - leaving it as-is."
} else {
    $srv = @{ profiles = @( @{ name = 'Local'; host = '127.0.0.1'; port = '28960' } ) }
    [System.IO.File]::WriteAllText($servers, ($srv | ConvertTo-Json -Depth 4), $utf8NoBom)
    Write-Host "Wrote servers.local.json (profile 'Local' -> 127.0.0.1:28960)."
}

if (Test-Path $secrets) {
    Write-Host "secrets.local.json already present - leaving it as-is."
} else {
    if (-not (Test-Path $cfgPath)) { throw "dedicated.cfg not found at $cfgPath - cannot read rcon_password." }
    # Same regex shape as tools/common.ps1's Get-RconPassword: `seta` counts, quotes around
    # the NAME are optional, and the ^ anchor is what stops a commented-out line matching.
    $pw = ([regex]::Match((Get-Content $cfgPath -Raw), '(?im)^\s*set[as]?\s+"?rcon_password"?\s+"([^"]*)"')).Groups[1].Value
    if ([string]::IsNullOrEmpty($pw)) { throw "No rcon_password found in dedicated.cfg." }
    # ConvertTo-Json is fine for the shape { profiles: { name: pw } }
    $obj = @{ profiles = @{ 'Local' = $pw } }
    [System.IO.File]::WriteAllText($secrets, ($obj | ConvertTo-Json -Depth 4), $utf8NoBom)
    Write-Host ("Wrote secrets.local.json (profile 'Local', {0} chars)." -f $pw.Length)
}

# --- 3. GF-RconPanel boot-start task (SYSTEM, loopback, restart-on-exit) -------
# The task runs node UNDER cmd.exe for one reason: to get a log. As SYSTEM there is no console,
# so everything server.js says on stdout/stderr is discarded - its startup banner, its
# rcon_password auto-seed line, and the one that actually matters, its "secrets.local.json is
# present but unreadable - ignoring it" report. That report exists precisely because the symptom
# otherwise is a panel with zero passwords "and nothing in any log" (server.js says so in its own
# comment), and THIS is the box where that file is unattended and nobody is watching a console.
# The laptop never had the problem - tools\rcon\start.bat keeps a visible console window.
#
# The log lives in the mod's logs\ folder, NOT beside server.js, because deploy.ps1 -Mod mirrors
# the mod tree with robocopy /MIR: an untracked file inside the mirrored area is an "extra file"
# to be PURGED, and purging one the running panel holds open fails with ERROR 32 and pushes the
# whole deploy past robocopy exit 8 (a thrown deploy). deploy.ps1 already /XD-excludes
# <mod>\logs for exactly that reason - it is where the engine's games_mp.log lives - so a log
# written there survives every deploy untouched and sits with the other logs a human greps.
$logDir = Join-Path (Split-Path -Parent (Split-Path -Parent $rconDir)) 'logs'   # tools\rcon -> tools -> <mod>
# Not optional: cmd cannot create the directory for a `>>` target, and a redirect into a missing
# folder fails the whole action with "The system cannot find the path specified" - node would
# never start, and the task would look like a broken panel rather than a missing folder.
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$panelLog = Join-Path $logDir 'panel.log'
# Roll one generation if a previous run left a big file. Be honest about what this is and is not:
# the log is NOT structurally bounded. A healthy panel writes ~2 lines per start, but a corrupt
# credential file makes server.js report it on every API call, and nothing prunes this file at
# runtime - watchdog.ps1's Trim-EngineLogArchive is keyed BY NAME to the engine's own <base>.NNN
# rolls of games_mp.log / console_mp.log and does not cover panel.log. So the mitigation is this
# roll plus the fact that a deploy recycles the panel; if it ever grows enough to matter, add
# 'panel.log' to that watchdog pass rather than inventing a second rotation scheme here.
if ((Test-Path $panelLog) -and ((Get-Item $panelLog).Length -gt 5MB)) {
    Move-Item -LiteralPath $panelLog -Destination ($panelLog + '.1') -Force
}
# cmd /c quoting, verified rather than assumed: the string has more than two quote characters and
# begins with one, so cmd strips the OUTER pair and runs  "<node>" "<server.js>" >> "<log>" 2>&1,
# keeping the space in "C:\Program Files\nodejs\node.exe" intact. The outer pair is not optional -
# without it cmd ends the command at that space. node's exit code still propagates through cmd
# (tested: exit 7 came back as 7), so -RestartCount below keeps working, and Task Scheduler stops
# the whole process tree, so deploy.ps1's panel recycle is unaffected (it also kills by port).
$cmdLine = '/c ""{0}" "{1}" >> "{2}" 2>&1"' -f $node, $serverJs, $panelLog
$action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument $cmdLine -WorkingDirectory $rconDir
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
Write-Host "Panel stdout/stderr -> $panelLog  (read this first if the panel is up but auth fails)."
Write-Host "On the box: open http://127.0.0.1:3000 - the 'Local' profile is already populated."
Write-Host "From your machine (recommended - credentials stay on the box):"
Write-Host "  ssh -L 3000:127.0.0.1:3000 gf-vps"
Write-Host "  then open http://localhost:3000  and select the 'Local' profile (127.0.0.1:28960)."
Write-Host "  ('gf-vps' = an SSH alias in your ~/.ssh/config; the box address is not kept in this repo.)"
