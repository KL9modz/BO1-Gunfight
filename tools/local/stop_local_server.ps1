param(
    [switch]$IncludeClient,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# LOCAL TEST BOX - stop every local dedicated server, and NOTHING else.
#
# WHY THIS EXISTS. Plutonium refuses to start a game CLIENT while a process
# named plutonium-bootstrapper-win32.exe is running, and a dedicated server is
# that same executable. The symptom is awful to diagnose from the outside: the
# launcher dies instantly, writes a 0-byte console.log, and says nothing useful
# (or reports a misleading auth error). A stray server - a zombie from an
# earlier session, a console window you forgot, a bat someone double-clicked -
# locks you out of your own game with no explanation.
#
# So when the game will not launch, run this FIRST. It is the cheapest possible
# check and it fixes the common case outright.
#
# WHAT IT WILL NOT DO: kill your game. Servers and clients are the same
# executable name, so they are told apart by their COMMAND LINE - a server
# carries -dedicated, a client carries -token. Anything not positively
# identified as a dedicated server is left alone unless you pass -IncludeClient.
#
#   Usage:  .\tools\local\stop_local_server.ps1
#           .\tools\local\stop_local_server.ps1 -WhatIf          show, kill nothing
#           .\tools\local\stop_local_server.ps1 -IncludeClient   also close the game
# ---------------------------------------------------------------------------

$names = @('plutonium-bootstrapper-win32.exe', 'gfserver.exe', 't5mp.exe')
$filter = ($names | ForEach-Object { "Name='$_'" }) -join ' OR '

$procs = @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue)
if (-not $procs.Count) {
    Write-Host "  Nothing running. Your game is free to launch." -ForegroundColor Green
    exit 0
}

$killed = 0
foreach ($p in $procs) {
    $cmd  = if ($p.CommandLine) { $p.CommandLine } else { '' }
    $kind = if ($cmd -match '-dedicated') { 'server' }
            elseif ($cmd -match '-token') { 'CLIENT (your game)' }
            else { 'unknown' }

    # Leave anything that is not clearly a server. An "unknown" is most often a
    # client whose command line could not be read, and killing your own game to
    # tidy up would be a worse outcome than leaving a stray process behind.
    if ($kind -ne 'server' -and -not $IncludeClient) {
        Write-Host ("  [skip] PID {0,-6} {1,-34} {2}" -f $p.ProcessId, $p.Name, $kind) -ForegroundColor DarkGray
        continue
    }

    if ($WhatIf) {
        Write-Host ("  [would kill] PID {0,-6} {1,-34} {2}" -f $p.ProcessId, $p.Name, $kind) -ForegroundColor Yellow
        continue
    }

    # Kill a cmd.exe parent first. start_local_server.bat ends in `pause`, and a
    # shell still hosting it can bring the server back or hold the window open.
    try {
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue
        if ($parent -and $parent.Name -eq 'cmd.exe') {
            Stop-Process -Id $parent.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch { }

    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        Write-Host ("  [kill] PID {0,-6} {1,-34} {2}" -f $p.ProcessId, $p.Name, $kind) -ForegroundColor Yellow
        $killed++
    } catch {
        Write-Host ("  [FAIL] PID {0} - {1}" -f $p.ProcessId, $_.Exception.Message) -ForegroundColor Red
    }
}

if ($WhatIf) { exit 0 }

Start-Sleep -Seconds 2
$left = @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue |
          Where-Object { $_.CommandLine -match '-dedicated' })
Write-Host ""
if ($left.Count) {
    Write-Host "  $($left.Count) server(s) still up - run again." -ForegroundColor Red
    exit 1
}
Write-Host "  No dedicated servers running. Your game is free to launch." -ForegroundColor Green
exit 0
