@echo off
title GF RCON Tool
cd /d "%~dp0"

where node >nul 2>&1
if errorlevel 1 (
    echo Node.js not found. Install from https://nodejs.org
    pause
    exit /b 1
)

echo Starting GF RCON Tool...
node server.js
pause
