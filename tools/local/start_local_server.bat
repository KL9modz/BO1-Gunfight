@echo off
REM  No delayed expansion: it would eat the "!" in the messages below, and
REM  nothing here needs !var! syntax.
setlocal
cd /d "%~dp0"

REM ===========================================================================
REM  LOCAL TEST BOX - dedicated server launcher
REM ===========================================================================
REM  Starts a LOCAL dedicated Gunfight server that mirrors how the VPS launches,
REM  so a change can be exercised on a real dedicated server before it is
REM  deployed to the live box.
REM
REM  YOU CAN PLAY ON THIS PC WHILE IT RUNS - but only because of two specific
REM  measures, both handled here. Do not remove either:
REM    * PORT. The client's own server wants 28960, so this defaults to 28965.
REM      That collision is the thing that actually bites - nothing else.
REM    * PROCESS NAME. Plutonium refuses to start a game CLIENT while a process
REM      named plutonium-bootstrapper-win32.exe is running, and a dedicated
REM      server IS that exe. So the server runs from a RENAMED copy,
REM      bintest\gfserver.exe. The guard is one-directional: a client already
REM      running tolerates a server started later, which is exactly why testing
REM      in that order makes the problem look nonexistent.
REM    * STORAGE. setup_test_box.ps1 builds an isolated tree and this bat pins
REM      LOCALAPPDATA to it, so the test server keeps its own cfg, logs and
REM      players profile and never writes the ones your game uses.
REM
REM  WHY THIS FILE EXISTS. The laptop's server used to be started straight from
REM  the Plutonium launcher with no cfg exec at all, which made dedicated.cfg -
REM  and the RCON panel's save button, which writes it - pure decoration
REM  locally: only seta-archived dvars survived a restart. This bat passes
REM  +exec, so the cfg is authoritative here exactly as it is on the VPS.
REM
REM  IT EXECS TWO CFGS, IN ORDER:
REM    1. dedicated.cfg    the shared base, kept a faithful mirror of the VPS
REM    2. local_test.cfg   the local-only override layer (isolation knobs)
REM  Last write wins, so anything in local_test.cfg beats the base.
REM
REM  NO RESTART LOOP, ON PURPOSE. The VPS bat loops because a live server must
REM  come back up unattended. A dev box wants the opposite: a GSC compile error
REM  takes the server down (SV_Shutdown), and a loop would relaunch it and
REM  scroll the error away. Here it stops with the failure still on screen.
REM
REM  Usage:  start_local_server.bat [port] [map] [-realstats]
REM     e.g. start_local_server.bat                 (28965, map_rotate)
REM          start_local_server.bat 28966           (a second test box)
REM          start_local_server.bat 28965 mp_villa  (straight onto one map)
REM          start_local_server.bat -realstats      (see below - opt-in, per run)
REM
REM  -realstats  RUNS THE SERVER AT modStats 0, i.e. the way the VPS runs.
REM     local_test.cfg pins modStats 1 on this box on purpose, so a dev session
REM     of bot farming at 5x XP cannot land in your real Black Ops profile. This
REM     flag appends +set modStats 0 AFTER both cfg execs, so it wins for ONE
REM     run and reverts the moment you restart without it.
REM     It exists for exactly one job: proving the T5 engine actually honours
REM     modStats, which is the last open question on that feature (Plutonium's
REM     changelog documents the dvar under the T4 release, so registration is
REM     not proof the T5 path reads it). See docs/notes/
REM     plutonium-stats-are-namespaced-per-mod.md for the test and what to look
REM     for.
REM     WARNING: the STORAGE ISOLATION ABOVE DOES NOT COVER YOU HERE. It gives
REM     the SERVER its own players\ tree, but a connected client's rank is
REM     written against that client's own account, and the client you join with
REM     is your normal game running from the real Plutonium tree. So a -realstats
REM     run really does move your real rank - that is the point of the test.
REM     Back up players\mpstats and players\globalstats first.
REM ===========================================================================

REM --- paths ------------------------------------------------------------------
set "REPO=%~dp0..\.."
set "REALPLUTO=%LOCALAPPDATA%\Plutonium"
set "TESTROOT=C:\gftest"
set "GAMEPATH=S:\SteamLibrary\steamapps\common\Call of Duty Black Ops"
set "MODNAME=mods/mp_gunfight"

REM --- local, gitignored overrides (server key, paths, port) ------------------
REM  local.env.bat is where the Plutonium SERVER KEY lives. It is gitignored so
REM  the key is never committed - the key has leaked once already, by being
REM  pasted somewhere it did not belong, and it is the one secret this repo's
REM  git history never held.
if exist "%~dp0local.env.bat" call "%~dp0local.env.bat"

REM  MODNAME can have been redirected by local.env.bat (GFMOD, for the skin
REM  playtest branch), so every path below derives its folder name from it. A
REM  hardcoded mp_gunfight here would validate and report the WRONG mod: the
REM  junction check would pass on a folder the server is not loading, and the
REM  compile-error hint would point at a log that never gets written.
REM  GFMOD picks a different mod folder for this run: setup_test_box.ps1 junctions
REM  every sibling WORKTREE of this repo, so a branch checked out in one (the skin
REM  playtest branch) is launchable without re-pointing anything. Read AFTER
REM  local.env.bat so either that file or a plain environment variable can set it.
REM  It is handled HERE, in the TRACKED launcher: it used to live only in the
REM  gitignored local.env.bat, so a fresh clone got the junctions and no way to
REM  select one.
if not "%GFMOD%"=="" set "MODNAME=mods/%GFMOD%"

REM  Then trim trailing spaces, because the obvious one-liner is a trap: in
REM  `set GFMOD=mp_gunfight_exp && start_local_server.bat` the space BEFORE the &&
REM  lands INSIDE the value, so fs_game becomes "mods/mp_gunfight_exp " and every
REM  path built from it misses by one character. That surfaces as [FAIL] mod
REM  junction missing, which sends you off to re-link something that was never
REM  wrong. Quoting (set "GFMOD=x") avoids it; the launcher should not have to
REM  depend on the caller getting that right.
:trimmod
if "%MODNAME:~-1%"==" " ( set "MODNAME=%MODNAME:~0,-1%" & goto :trimmod )
set "MODDIR=%MODNAME:mods/=%"

REM  Arg scan rather than plain %1/%2, so -realstats can sit in any position.
REM  "if not defined" is used instead of comparing %P1%: inside a goto loop the
REM  line is re-parsed each pass, but "defined" needs no expansion at all, which
REM  keeps this working without delayed expansion (see the note at the top).
set "P1="
set "P2="
REM  Cleared deliberately, so -realstats is FLAG-ONLY and cannot be left switched
REM  on in local.env.bat. That is what makes "restart without the flag and you
REM  are back on per-mod stats" true rather than aspirational.
set "REALSTATS="
:parseargs
if "%~1"=="" goto :parsed
REM  The bodies MUST be parenthesised: in "if cond a & b", the & separates two
REM  commands and b runs UNCONDITIONALLY, so an unbracketed goto here would fire
REM  on every argument and the parse would never assign P1/P2.
if /I "%~1"=="-realstats" ( set "REALSTATS=1" & shift & goto :parseargs )
if not defined P1 ( set "P1=%~1" & shift & goto :parseargs )
if not defined P2 ( set "P2=%~1" & shift & goto :parseargs )
shift
goto :parseargs
:parsed

set "PORT=%P1%"
if "%PORT%"=="" if not "%TESTPORT%"=="" set "PORT=%TESTPORT%"
if "%PORT%"=="" set "PORT=28965"
set "STARTMAP=%P2%"
if "%MAXCLIENTS%"=="" set "MAXCLIENTS=14"

REM  Stats profile. Default is whatever the cfgs say (local_test.cfg pins 1).
REM  -realstats appends the override AFTER both execs, so last write wins.
set "STATSARG="
set "STATSMODE=per-mod (modStats 1, from local_test.cfg - your real profile is untouched)"
if "%REALSTATS%"=="1" (
    set "STATSARG=+set modStats 0"
    set "STATSMODE=REAL BO1 PROFILE (modStats 0) - this run moves your actual rank"
)

set "TESTPLUTO=%TESTROOT%\Plutonium"
set "TESTT5=%TESTPLUTO%\storage\t5"

REM --- preflight --------------------------------------------------------------
if not exist "%GAMEPATH%\BlackOpsMP.exe" (
    echo [FAIL] Black Ops not found at:
    echo        %GAMEPATH%
    echo        Set GAMEPATH in local.env.bat to your install.
    goto :fail
)
if not exist "%REALPLUTO%\bin\plutonium-bootstrapper-win32.exe" (
    echo [FAIL] Plutonium bootstrapper not found. Run the Plutonium launcher once.
    goto :fail
)
if not exist "%TESTT5%\dedicated.cfg" (
    echo [FAIL] No isolated test box at %TESTROOT%
    echo.
    echo        Create it once with:
    echo            powershell -ExecutionPolicy Bypass -File "%~dp0setup_test_box.ps1"
    echo.
    echo        That builds an isolated Plutonium storage tree so this server
    echo        never writes the cfg, logs or player profile your game uses.
    goto :fail
)
if not exist "%TESTT5%\mods\%MODDIR%\maps\mp\gametypes\gf.gsc" (
    echo [FAIL] The test box's mod junction is missing or broken.
    echo        Re-link it:  setup_test_box.ps1 -Force
    goto :fail
)
if not exist "%TESTPLUTO%\games\t5mp.exe" (
    echo [FAIL] The test box's games junction is missing or broken.
    echo        Re-link it:  setup_test_box.ps1 -Force
    goto :fail
)
REM  The RENAMED bootstrapper is what lets you play while this server runs, so
REM  it is a hard requirement - NOT something to fall back from. Plutonium
REM  refuses to start a game client while a process named
REM  plutonium-bootstrapper-win32.exe exists, and a dedicated server is that
REM  same exe. Falling back to the stock name would start a server that works
REM  perfectly and silently locks you out of your own game, with the launcher
REM  dying instantly and no error worth reading. Fail loudly instead.
if not exist "%TESTPLUTO%\bintest\gfserver.exe" (
    echo [FAIL] Missing %TESTPLUTO%\bintest\gfserver.exe
    echo.
    echo        This is the renamed bootstrapper that lets you launch the GAME
    echo        while this server is running. Without it the server would block
    echo        your own client.
    echo.
    echo        Create it:  setup_test_box.ps1 -Force
    goto :fail
)

REM --- install the override cfg if it went missing ----------------------------
if not exist "%TESTT5%\local_test.cfg" (
    echo [ .. ] Installing local_test.cfg into the test box
    copy /y "%~dp0local_test.cfg.example" "%TESTT5%\local_test.cfg" >nul
    if errorlevel 1 (
        echo [FAIL] Could not write the override cfg.
        goto :fail
    )
)

REM --- key: required, and a dedicated server will HANG without one -------------
REM  A dedicated server authenticates to Demonware with the server KEY (a game
REM  client uses its account -token instead). With no key, DW_AUTHORIZING times
REM  out, the engine cannot fetch online_tu14_mp_english.wad, and map_rotate
REM  early-outs forever with "waiting for WAD!" - the process stays up but never
REM  loads a map. Verified live, including with an INVALID key, so the key has
REM  to be real and not merely present.
set "KEYARG="
if not "%KEY%"=="" (
    set "KEYARG=+set key %KEY%"
) else (
    echo.
    echo  ****************************************************************
    echo   WARNING: no server key set - THIS SERVER WILL NOT LOAD A MAP.
    echo.
    echo   It will start, bind its port, then sit forever printing
    echo     "Early out of maprotate, waiting for WAD!"
    echo   because Demonware authorization never completes without a key.
    echo.
    echo   Fix: copy local.env.bat.example to local.env.bat and set KEY.
    echo   Get a key at https://platform.plutonium.pw/serverkeys
    echo   Use a SEPARATE key from the live server - the key's LABEL is the
    echo   name players see, so reusing it renames or shadows the real one.
    echo  ****************************************************************
    echo.
    choice /C YN /N /M "Start anyway? [Y/N] "
    if errorlevel 2 goto :fail
)

REM --- start map ---------------------------------------------------------------
set "MAPARG=+map_rotate"
if not "%STARTMAP%"=="" set "MAPARG=+map %STARTMAP%"

REM --- -realstats: confirm, because this one reaches outside the sandbox -------
if "%REALSTATS%"=="1" (
    echo.
    echo  ****************************************************************
    echo   -realstats: running at modStats 0, the way the live VPS runs.
    echo.
    echo   The storage isolation does NOT protect you here. It gives the
    echo   SERVER its own players tree, but your rank is written against
    echo   YOUR account, and you will join with your normal game client.
    echo   So this run really does move your real Black Ops rank, at the
    echo   mod's 5x XP. That is the point - it is how the test is read.
    echo.
    echo   Back these up first if you have not:
    echo     %%LOCALAPPDATA%%\Plutonium\storage\t5\players\mpstats
    echo     %%LOCALAPPDATA%%\Plutonium\storage\t5\players\globalstats
    echo.
    echo   Restarting WITHOUT the flag returns this box to per-mod stats.
    echo  ****************************************************************
    echo.
    choice /C YN /N /M "Run against your REAL profile? [Y/N] "
    if errorlevel 2 goto :fail
)

title GF LOCAL TEST server - port %PORT%
echo.
echo  ---------------------------------------------------------------
echo   GF LOCAL TEST SERVER
echo   storage: %TESTPLUTO%   (isolated - your game is untouched)
echo   mod    : %MODDIR%   (this repo, via junction)
echo   cfg    : dedicated.cfg  then  local_test.cfg
echo   stats  : %STATSMODE%
echo   port   : %PORT%   maxclients: %MAXCLIENTS%
echo   join   : connect 127.0.0.1:%PORT%
echo   panel  : tools\rcon\rcon_start.bat
echo  ---------------------------------------------------------------
echo   Close this window to stop the server. It does NOT auto-restart,
echo   so a GSC compile error stays on screen instead of scrolling by.
echo  ---------------------------------------------------------------
echo.

REM  cd into the Plutonium tree FIRST. The bootstrapper resolves the game
REM  executable RELATIVE TO THE WORKING DIRECTORY, not to its own path and not
REM  to LOCALAPPDATA - launching from anywhere else dies with
REM  'executable "...\games\t5mp.exe" not found'. That is why the VPS bat does
REM  the same cd before its launch line. Going to the TEST tree means both
REM  games and bin resolve through its junctions.
cd /d "%TESTPLUTO%"

REM  Pin the storage tree for THIS process only. setlocal keeps it out of your
REM  environment, so nothing else on the machine sees the redirect. Same
REM  mechanism the VPS scheduled task uses to pin its profile.
set "LOCALAPPDATA=%TESTROOT%"

bintest\gfserver.exe t5mp "%GAMEPATH%" -dedicated %KEYARG% ^
    +set fs_game "%MODNAME%" ^
    +exec "dedicated.cfg" ^
    +exec "local_test.cfg" ^
    %STATSARG% ^
    +set net_port %PORT% ^
    +set sv_maxclients %MAXCLIENTS% ^
    %MAPARG%

echo.
echo  ---------------------------------------------------------------
echo   Server exited. If that was not you closing it, read the tail of
echo   %TESTT5%\mods\%MODDIR%\console_mp.log
echo   for a GSC compile error (unknown function / SV_Shutdown).
echo  ---------------------------------------------------------------
pause
exit /b 0

:fail
echo.
pause
exit /b 1
