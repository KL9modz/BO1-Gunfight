@echo off
cd /d "%~dp0"

REM ============================================================================
REM  LAPTOP RCON panel -- controls THIS machine's own listen server.
REM  The panel's "Local" profile = 127.0.0.1:28960 = the server on this same box.
REM  Pinned to 3005 so it never collides with the VPS SSH-tunnel panel on 3000
REM  (Desktop "Gunfight RCON.bat"). Two fixed ports = two stable URLs:
REM    laptop -> http://127.0.0.1:3005   VPS -> http://127.0.0.1:3000
REM  An explicit first arg still wins, e.g.  start.bat 3006
REM ============================================================================
set PORT=%~1
if "%PORT%"=="" set PORT=3005
title GF RCON Tool - LAPTOP listen server (port %PORT%)

where node >nul 2>&1
if errorlevel 1 (
    echo Node.js not found. Install from https://nodejs.org
    pause
    exit /b 1
)

REM Auto-close any STALE panel already holding THIS port (prevents EADDRINUSE on re-run).
REM Targets only the PID listening on %PORT% -- never touches other node apps.
for /f "tokens=5" %%A in ('netstat -ano ^| findstr /r /c:":%PORT% .*LISTENING"') do (
    echo Closing stale panel on port %PORT% - PID %%A
    taskkill /F /PID %%A >nul 2>&1
)

REM Wait until the panel is listening, then open the browser to the LAPTOP panel.
start "" /min powershell -NoProfile -Command "for($i=0;$i -lt 25;$i++){try{$t=New-Object Net.Sockets.TcpClient;$t.Connect('127.0.0.1',%PORT%);$t.Close();break}catch{Start-Sleep 1}};Start-Process ('http://127.0.0.1:%PORT%/')"

echo Starting GF RCON Tool - LAPTOP listen server - on http://127.0.0.1:%PORT% ...
echo VPS dedicated server is a separate panel: Desktop "Gunfight RCON" -^> http://127.0.0.1:3000
node server.js
pause