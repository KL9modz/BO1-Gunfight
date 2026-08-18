@echo off
REM Gunfight Loadout Editor - launches the local editor and opens it in your browser.
cd /d "%~dp0"
start "" http://127.0.0.1:3100
node server.js
