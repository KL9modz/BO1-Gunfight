@echo off
cd /d "%~dp0"

REM Web port. An explicit first arg wins (e.g.  start.bat 3005 ). With NO arg we auto-pick the
REM first free port from 3000..3003, so double-clicking works even when an SSH tunnel to the VPS
REM panel already holds 3000 (it then lands on 3001, etc.).
set PORT=%~1
if not "%PORT%"=="" goto :haveport
for %%P in (3000 3001 3002 3003) do (
    netstat -ano | findstr /r /c:":%%P .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        set PORT=%%P
        goto :haveport
    )
)
set PORT=3000
:haveport
title GF RCON Tool (port %PORT%)

where node >nul 2>&1
if errorlevel 1 (
    echo Node.js not found. Install from https://nodejs.org
    pause
    exit /b 1
)

echo Starting GF RCON Tool on http://127.0.0.1:%PORT% ...
node server.js
pause
