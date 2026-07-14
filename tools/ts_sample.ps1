# ts_sample.ps1 — measure the server's TIMESCALE from outside the game sim.
#
# WHY THIS EXISTS (do not try to replace it with a GSC probe — it cannot be done):
# A SetTimeScale dilation compresses game time against WALL time without ever creating a game-clock
# gap. gettime(), wait() and the games_mp.log timestamps are ALL on the game clock, so every probe
# that lives inside the VM is structurally blind to it — GF_HITCH and GF_ENDGAP included. Their
# zeros were never evidence the killcam was clean; a zero is what a dilation LOOKS like from inside.
# And SetTimeScale does not mirror into a readable `timescale` dvar either (it reads a steady 1
# straight through a measured 0.27x dilation), so you cannot just poll a dvar.
#
# RCON lives outside the sim, so its stopwatch is a true wall clock. gf_roundEndProbe (_gf_debug.gsc)
# stamps gettime() into the gf_endprobe_last dvar at 20 Hz for the whole round-end window (it is
# empty outside that window, which is how you spot the window boundaries). Therefore:
#
#       d(game_ms) / d(wall_ms)  ==  the server's timescale
#
# This is how the killcam slow-mo floor (scr_gf_killcam_slowmo) was found and sized. Reference
# numbers from the VPS, sv_fps 20:
#
#       stock slow-mo (floor 0.25)  ->  ratio ~0.27, held for 8-10 REAL seconds, every round
#       floor 0.6                   ->  ratio ~0.6
#       no slow-mo (floor 1.0)      ->  flat 1.00
#
# Also worth reading straight off the raw game_ms column: every value is an exact multiple of
# 1000/sv_fps (50 at sv_fps 20). That quantum is the server's game-frame step, and the dilation does
# NOT shrink it — it spreads those steps apart in wall time, which is the whole root cause of the
# mid-killcam usercmd backlog (MAX_PACKET_USERCMDS) and the "Connection Interrupted" plug.
#
# ⚠ Goes through the RCON PANEL's paced queue (127.0.0.1:3000), NOT a new direct RCON socket —
# Plutonium answers ~1 reply per 0.7s and silently drops faster sends. That caps us at ~1.2
# samples/sec, which is plenty: the dilation lasts seconds, not frames.
#
# USAGE (on the box, or through an SSH tunnel to the panel):
#     powershell -ExecutionPolicy Bypass -File tools\ts_sample.ps1 -Seconds 250
# Output is CSV (wall_ms,game_ms) with a ratio column; each blank-line-separated run of samples is
# one round-end window.

param(
  [int]$Seconds  = 240,
  [string]$Pw    = "",
  [string]$Panel = "http://127.0.0.1:3000"
)

if (-not $Pw) {
  # Same store the panel itself uses; gitignored, box-local.
  $secrets = Join-Path $PSScriptRoot "rcon\secrets.local.json"
  if (Test-Path $secrets) {
    $j = Get-Content $secrets -Raw | ConvertFrom-Json
    $Pw = $j.profiles.VPS
  }
}
if (-not $Pw) { throw "No RCON password. Pass -Pw <password> or populate tools/rcon/secrets.local.json." }

$uri  = "$Panel/api/dvars?fresh=1&password=$Pw&names=gf_endprobe_last"
$sw   = [System.Diagnostics.Stopwatch]::StartNew()
$prevW = $null
$prevG = $null

Write-Output "wall_ms,game_ms,ratio"
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
  try   { $g = (Invoke-RestMethod -Uri $uri -TimeoutSec 10).values.gf_endprobe_last }
  catch { $g = $null }

  $w = [int]$sw.Elapsed.TotalMilliseconds

  if ($g) {
    $gi = [int]$g
    $ratio = ""
    # Only meaningful WITHIN one round-end window: the dvar is cleared between windows, and game
    # time also resets on a map change, so a negative/absurd delta means "new window" -> no ratio.
    if ($null -ne $prevG) {
      $dw = $w - $prevW
      $dg = $gi - $prevG
      if ($dw -gt 0 -and $dg -ge 0 -and $dg -lt 60000) {
        $ratio = [math]::Round($dg / $dw, 2)
      }
    }
    Write-Output "$w,$gi,$ratio"
    $prevW = $w; $prevG = $gi
  } else {
    # Outside a round-end window. Break the run so the next window starts a fresh ratio chain.
    if ($null -ne $prevG) { Write-Output "" }
    $prevW = $null; $prevG = $null
  }
}
