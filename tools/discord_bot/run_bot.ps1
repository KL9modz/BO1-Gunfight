# PowerShell wrapper so the Node bot can ride the same supervision as every other box service.
#
# run_service.ps1 (the flight recorder) runs a PowerShell script in-process and captures every
# stream into storage\t5\logs\services\<Task>.log. The bot is Node, so it needs this thin shim:
# without it the task would have to invoke node.exe directly and its output - including the
# terminating error that killed it - would go to a window nobody sees. That is exactly the failure
# GF-ConnLogger had on 2026-08-02, and the reason the recorder exists.
#
# ⚠ Blocks forever on purpose. `node bot.js` is a long-running gateway client; this script returning
# means the bot exited, which is a real event the recorder should log and the task should restart.
$ErrorActionPreference = 'Stop'

$botDir = $PSScriptRoot
$bot    = Join-Path $botDir 'bot.js'
if (-not (Test-Path $bot)) { throw "bot.js not found at $bot" }

$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) { throw 'node is not on PATH for this task account - the bot cannot start' }

Write-Host "starting Discord bot: $bot  (node $((& node --version)))"
# Call operator, and NO 2>&1 on the native command: in PS 5.1 redirecting a native exe's stderr
# wraps each line in an ErrorRecord and trips $ErrorActionPreference='Stop' on perfectly ordinary
# output. The recorder is already capturing both streams.
& $node.Source $bot
$code = $LASTEXITCODE
Write-Host "Discord bot exited with code $code"
# Surface a non-zero exit to Task Scheduler so its restart policy fires.
if ($code -ne 0) { throw "bot.js exited $code" }
