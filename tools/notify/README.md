# GF Join Notifier

Pushes a phone notification via **ntfy.sh** on player activity (join / leave / server
active / server empty / heartbeat). Runs 24/7 on the VPS, independent of the browser
RCON panel. It polls `status` over loopback RCON, diffs the human-player set by GUID
(bots excluded), and POSTs to your ntfy topic.

**Two implementations, same behavior & config:**

- **`join-notify.ps1`** — native Windows PowerShell 5.1, **no runtime to install**. This is
  what runs on the VPS (the box has no Node.js).
- **`join-notify.js`** — Node.js version, for a desktop / Linux host that already has Node.

Both read the same `config.json` and `GF_*` env vars. Zero external dependencies.

**Events it can push** (each with its own phone priority):

| Event | When | Priority | Config |
|---|---|---|---|
| **Server now active** | first human joins an *empty* server | high | `notifyFirstJoin` (on) |
| **Player joined** | any subsequent human join | default | always |
| **Player left** | a human leaves | low | `notifyLeaves` (off) |
| **Server empty** | last human leaves → 0 online | low | `notifyEmpty` (off) |
| **Heartbeat** | periodic "still alive — N online" | min (silent) | `heartbeatMins` (0 = off) |

The "server now active" alert comes through at **high** priority so it cuts through Do-Not-
Disturb; the heartbeat is **min** priority so it lands silently as a health check. Messages
include the current `map / gametype`.

## 1. Phone setup (once)

1. Install the **ntfy** app — [iOS](https://apps.apple.com/app/ntfy/id1625396347) /
   [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy) (or F-Droid).
2. In the app, **Subscribe to a topic**. Pick a long, hard-to-guess name — the topic name
   is the only secret on the public ntfy.sh server; anyone who knows it can read your alerts
   (and push spam to your phone). e.g. `gunfight-7h3n9x2k`, not just `gunfight`.
3. That's it — no account needed.

> For real access control, self-host ntfy or set `ntfyToken` with an auth-protected topic.

## 2. Config (`config.json`, next to the script)

Copy the template and set your topic:

```
copy config.example.json config.json
```

Edit `config.json` → `ntfyTopic` = the exact topic you subscribed to. Leave `password`
blank to auto-read `rcon_password` from `dedicated.cfg`. `config.json` is gitignored (it
holds your secret topic).

## 3. Run / test on the VPS

```
powershell -NoProfile -ExecutionPolicy Bypass -File join-notify.ps1
```

You get a "notifier online" push immediately, then the console logs the seeded baseline.
Have someone join → you get "server now active" (empty server) or "player joined".
`Ctrl+C` to stop.

## 4. Auto-start on boot — scheduled task (the deployed setup)

Registered once (as Administrator). Runs as **SYSTEM**, at startup, restarts on crash,
never times out. Paths are absolute so the SYSTEM account resolves them correctly.

```powershell
$dir = "C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight\tools\notify"
$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$dir\join-notify.ps1`""
$act = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg -WorkingDirectory $dir
$trg = New-ScheduledTaskTrigger -AtStartup
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName "GF Join Notifier" -Action $act -Trigger $trg -Settings $set `
        -RunLevel Highest -User "SYSTEM" -Force
Start-ScheduledTask -TaskName "GF Join Notifier"
```

Manage it:

```powershell
Start-ScheduledTask    -TaskName "GF Join Notifier"    # start now
Stop-ScheduledTask     -TaskName "GF Join Notifier"    # stop
Get-ScheduledTaskInfo  -TaskName "GF Join Notifier"    # LastRunTime / LastTaskResult (267009 = running)
Unregister-ScheduledTask -TaskName "GF Join Notifier" -Confirm:$false
```

> After editing `config.json`, restart the task (`Stop-ScheduledTask` then
> `Start-ScheduledTask`) so it re-reads the config.

## Config reference (`config.json`, or `GF_*` env vars)

| Key | Env | Default | Meaning |
|---|---|---|---|
| `ntfyTopic` | `GF_NTFY_TOPIC` | — (**required**) | Your subscribed topic name |
| `ntfyServer` | `GF_NTFY_SERVER` | `https://ntfy.sh` | ntfy server (change if self-hosting) |
| `ntfyToken` | `GF_NTFY_TOKEN` | — | Bearer token for auth-protected topics (optional) |
| `host` | `GF_HOST` | `127.0.0.1` | Game server host (loopback on the VPS) |
| `port` | `GF_PORT` | `28960` | Game server port |
| `password` | `GF_RCON_PW` | (from `dedicated.cfg`) | RCON password |
| `pollMs` | `GF_POLL_MS` | `12000` | Poll interval (ms) |
| `notifyLeaves` | `GF_NOTIFY_LEAVES` | `false` | Also push when a player leaves |
| `notifyFirstJoin` | `GF_NOTIFY_FIRST` | `true` | High-priority "server now active" on first join to an empty server |
| `notifyEmpty` | `GF_NOTIFY_EMPTY` | `false` | Push when the last player leaves (server → 0) |
| `heartbeatMins` | `GF_HEARTBEAT_MINS` | `0` | Minutes between silent "still alive — N online" pushes; `0` = off |
| `serverName` | `GF_SERVER_NAME` | `Gunfight` | Shown in the push title |
| `quietStart` | `GF_QUIET_START` | `false` | Skip the "notifier online" push at launch |

**Currently deployed on the VPS:** topic `gunfight`, `notifyLeaves`/`notifyFirstJoin`/
`notifyEmpty` on, `heartbeatMins` 60. Running as scheduled task "GF Join Notifier".
