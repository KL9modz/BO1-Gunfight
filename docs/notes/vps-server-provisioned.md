---
name: vps-server-provisioned
description: "The Contabo VPS bought to host the Gunfight server - IP, specs, OS, and where the deploy runbook lives"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0471c990-f524-4f63-855b-f3030ff8594d
---

VPS purchased 2026-06-28 to host the mp_gunfight Plutonium T5 server (resolves the
CLAUDE.md TODO "Setup a modded T5 Plutonium server on a VPS").

- Provider/plan: Contabo Cloud VPS 10 SSD - 4 vCPU / 8 GB RAM / 150 GB SSD / 200 Mbit/s, ~$18.20/mo (base + US West + Windows license)
- Public IPv4: 94.72.121.4 (IPv6 2605:a141:2340:4923::1)
- Location: Seattle (US West). OS: **Windows Server 2019 Datacenter 64-bit** (the order page said 2025, but the provisioned image is 2019 per Server Manager — fine, 2019 is Plutonium's documented minimum).
- VNC out-of-band console: 144.126.146.144:63019 (8-char VNC pass; Windows login is `Administrator` / its own pass). RDP needed Remote Desktop enabled + the box fully provisioned (initial 0x204 was just it still booting).
- Game UDP port: 28960. Game files live at C:\gameserver\T5 (BO1 install). Mod + dedicated.cfg in %LOCALAPPDATA%\Plutonium\storage\t5\. Launch bat: C:\gameserver\T5\start_mp_server.bat (bootstrapper `t5mp "C:\gameserver\T5" -dedicated +set key ... +set fs_game mods/mp_gunfight +exec dedicated.cfg ...`, with a restart loop).

**STATUS 2026-06-29: server is LIVE and successfully joined.** Full runbook in repo **VPS_DEPLOY.md** (root, `main`).

Key T5 gotchas: you CANNOT `connect <publicIP>:port` remotely on T5 - remote players join
via the in-game Plutonium server browser (set `sv_hostname`); a VPS needs NO port-forward
(direct public IP), only a Windows Firewall UDP 28960 rule. (The "FastDL was a DEAD END"
claim previously here was WRONG - it was a misconfig; FastDL works, see
[[t5-clients-must-install-mod-no-autodownload]].)

**GAME-SERVER START MODEL — ⚠ SUPERSEDED: `GF-GameServer` is now a registered, Running scheduled
task that owns the restart loop** (watchdog escalation 3e Stop/Start-restarts it, and `deploy.ps1`'s
Restart-Server relies on it), so the game server DOES come back on its own — the "DISABLED / never
launches on boot / manual desktop-launcher only" model below is history, kept for context.

**(HISTORICAL) GAME-SERVER START MODEL — CHANGED 2026-07-04 to MANUAL-LOGIN + VISIBLE CONSOLE** (user
disliked having no live Plutonium console window). The old SYSTEM/AtStartup task ran the server
in **Session 0**, so its console existed on a desktop no interactive user can ever see. A
visible window only exists inside an interactive logon session, and any "run whether logged on
or not"/SYSTEM task is *always* windowless (hard Windows rule). User chose the manual-login model
(no auto-logon → no stored credential on the public VPS) over unattended-reboot survival, and
then (same day) asked for a **one-click DESKTOP launcher** rather than auto-on-login. Current setup:
- Task **GF-GameServer** is **DISABLED** (`schtasks /change /tn GF-GameServer /disable`;
  `Settings.Enabled=False`) — reversible, kept for reference. Never launches on boot now.
- **Desktop shortcut `Gunfight Launch.lnk`** (`C:\Users\Administrator\Desktop\`, bootstrapper-exe
  icon) → **`C:\gameserver\T5\gf_launch.bat`**, which: (1) `taskkill /f /im
  plutonium-bootstrapper-win32.exe` + `taskkill /f /im node.exe` (only the RCON panel uses node
  on this box) to clear stale instances — the structural guard against the recurring
  duplicate-instance-on-UDP-28960 footgun; (2) `schtasks /end` then `/run` **GF-RconPanel** to
  bounce the RCON panel cleanly; (3) `call start_mp_server.bat` so THAT cmd window becomes the
  visible live Plutonium console. Run it interactively (double-click) — do NOT `/run` it from
  Claude's SSH session or the console spawns in the wrong/headless session.
- **GF-RconPanel stays auto-boot enabled** (windowless Session-0 node on 127.0.0.1:3000) so the
  background services (StatusService/JoinNotify/ConnLogger, which are panel-first) have it after
  a reboot; the launcher just restarts it. The other GF-* services are unchanged (SYSTEM/boot).
- **Reboot behavior:** box boots to lock screen; RCON panel + services come up windowless, but the
  GAME SERVER stays DOWN until you log into the desktop as Administrator and double-click "Gunfight
  Launch." (Superseded interim 2026-07-04: a Startup-folder shortcut `GF-GameServer-Console.lnk` +
  wrapper `start_mp_server_console.bat` auto-launched the server at login — BOTH REMOVED when the
  manual desktop-launcher replaced them.)
- TO REVERT to unattended boot: `schtasks /change /tn GF-GameServer /enable` (+ optionally delete
  the Desktop shortcut). To keep the visible window AND survive reboots unattended, add auto-logon
  (Sysinternals Autologon → encrypted LSA secret) — the option the user declined 2026-07-04.

(Superseded note, old SYSTEM/AtStartup model 2026-07-03: action was
`cmd.exe /c "set LOCALAPPDATA=C:\Users\Administrator\AppData\Local&&C:\gameserver\T5\start_mp_server.bat"`
so the bat's `cd /D %LOCALAPPDATA%\Plutonium` landed on the real install instead of SYSTEM's
systemprofile. Plutonium T5 runs fine as SYSTEM — verified stable. A schtasks `/ru Administrator`
WITHOUT `/rp` created it `logonType=Interactive` = won't run headless on boot; SYSTEM sidestepped
the password problem.) On a warm restart the first launch may crash once if the just-killed
instance still holds UDP 28960 (port not released) - the bat loop relaunches it and it
stabilizes; a cold boot has no such collision. LESSON: after a reboot
2026-07-03, SSH port 22 was DOWN (sshd/FW rule not
persistent) though the box + IIS were up - fixed by `Set-Service sshd -StartupType Automatic`
+ a **PersistentStore** FW rule "OpenSSH home" (TCP 22 from 76.167.246.191). So there may now
be TWO SSH FW rules (old `sshd-scoped` + `OpenSSH home`).

**SSH ACCESS (set up 2026-07-03): Claude can drive the VPS directly.**
`ssh -i ~/.ssh/gf_vps Administrator@94.72.121.4` (BatchMode-safe, PowerShell 5.1 is the default
shell). Key-only auth (`PasswordAuthentication no`, prepended as sshd_config line 1 so it wins
first-match ahead of the Match Group administrators block); key lives on the dev machine at
`~/.ssh/gf_vps` (ed25519, comment `claude-gf-deploy`), authorized via
`C:\ProgramData\ssh\administrators_authorized_keys` (strict ACL). ⚠ **UPDATE: SSH (22) is now open to
ANY IP** — rule **`SSH-Any-In (travel)`** carries the travel/ops path (additive, so it reverts by
disabling that one rule); the old home-IP-scoped SSH rules are left in place. Safe only because sshd is
key-only. **RDP stays home-IP-pinned** (`RDP-AdminOnly-In` → 76.167.246.191). Install was the official
Win32-OpenSSH v9.5 MSI — `Add-WindowsCapability` FoD is broken on this box (0x800f0950).
Used the same day to run `deploy.ps1 -Mod` remotely and verify live files/process.

**Server account (confirmed 2026-07-02 via bootstrapper process owner): the game server runs
as `Administrator`. NO `gfsvc` account exists** - the low-priv gfsvc in VPS_DEPLOY.md is
aspirational hardening that was never implemented. Live mod folder =
`C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\mods\mp_gunfight`. Deploys use the
git-pull applier `tools/deploy.ps1 -Mod/-Web` inside `C:\gfdeploy\BO1-Gunfight` and MUST run
from an Administrator session (default `-ModDest` resolves via `$env:LOCALAPPDATA`) - a
wrong-account deploy silently mirrors into that account's own profile while the server keeps
loading old files (this exact failure once shipped stale GSC: the enableText XP-popup fix
appeared "not to work" until deployed to the right profile). Also 2026-07-02: the Plutonium
server key was exposed in a pasted process command line (`+set key SVrs...`) - suggested
rotating it at platform.plutonium.pw/serverkeys (key label = server-browser name, see
[[plutonium-serverkey-sets-browser-name]]).
