---
name: rcon-tool-vps-connect-23char-cap
description: "Connecting the GF RCON web tool to the VPS; Plutonium's 23-char rcon_password cap silently breaks RCON (no reply at all); live password reverts to a broken value on restart (source unresolved)"
metadata: 
  node_type: memory
  type: project
  originSessionId: ff936017-7de8-4abc-86bb-9aed0ff575bb
---

Connecting the local RCON web tool (`tools/rcon/server.js`) to the live VPS server (94.72.121.4).

**Architecture:** the tool is a local Node web app on the DESKTOP at `127.0.0.1:3000`; it sends UDP rcon packets to whatever Host/Port you type in the UI. "Connecting to the VPS" = point it at `94.72.121.4:28960` with the rcon_password. The loopback Host-header guard in server.js only restricts who can open the *web UI*; it does NOT restrict the rcon target, so aiming at the VPS works unchanged. RCON rides the same UDP port as the game (net_port 28960).

**ROOT CAUSE of "every rcon times out" (cost a long debug session):** Plutonium truncates `rcon_password` at 23 chars and a value >23 chars **silently never authenticates — no reply at all** (not even "Bad rconpassword"). The VPS live value was 24 chars (`aBHgu…`, redacted) → every rcon packet silently dropped, on loopback AND remote, regardless of what password the client sent. Fix: use a password <=23 chars. `dedicated.cfg` holds a valid 20-char one; setting that value live via the server console makes rcon work immediately.

**The network path was NEVER the problem** (chased it for hours — don't repeat): Windows Firewall has inbound UDP 28960 ALLOW (there's a pre-existing `Plutonium T5 28960 UDP` rule + the `BO1 Gunfight UDP 28960` one I added), outbound DefaultAction = allow, public IP `94.72.121.4` is direct on the NIC (no Contabo NAT). Firewall drop-logging (`Set-NetFirewallProfile -LogAllowed`) confirmed inbound rcon packets arrive and are `ALLOW...RECEIVE`. So if rcon is silent, suspect the PASSWORD (length/value/loaded-vs-file), not the firewall.

**Diagnostic that nails it:** in the server console window (`PlutoniumT5 MP - Gunfight - Seattle`, prompt `Plutonium rNNNN >`) type `rcon_password` — prints the *actually loaded* live value. Don't trust the cfg file; the live value drifts from it. A PowerShell loopback rcon test (UdpClient -> 127.0.0.1:28960, packet = 4x0xFF + `rcon <pw> status`) bypasses all firewalls and isolates server/password from network.

**Live server facts:** runs as Administrator; launched by `C:\gameserver\T5\start_mp_server.bat` (gamepath `C:\gameserver\T5`, `+exec dedicated.cfg`, net_port 28960, maxclients 8, `cd /D %LOCALAPPDATA%\Plutonium` with NO localappdata redirect). So the live cfg is `C:\Users\Administrator\AppData\Local\Plutonium\storage\t5\dedicated.cfg`. There's a DORMANT decoy cfg with empty rcon_password at `C:\gameserver\T5\T5ServerConfig-master\localappdata\Plutonium\storage\t5\dedicated.cfg` — ignore it (not the one the server reads). Also bumped `sv_floodProtect` 4 -> 20 for the tool's batch dvar reads.

**RESOLVED — the "reverts on restart" was a DUPLICATE/ORPHAN server instance, not a reverting value.** Two `plutonium-bootstrapper-win32.exe` were running: an ORPHAN (no restart-loop managing it) squatting UDP 28960, plus a loop-managed one bumped to 28961 (Plutonium auto-increments net_port when 28960 is taken). The orphan on 28960 had come up earlier loading a stale 24-char password (from an older dedicated.cfg state), and every rcon test/the tool hit 28960 = that stale orphan. The live `gf.gsc` is current and does NOT set rcon_password; no `.cfg` held the 24-char value — it was just baked into the long-lived orphan process. Fix that made it permanent: `taskkill /PID <orphan>` (frees 28960), then `taskkill /PID <loop-managed>` so the single restart-loop (`cmd /c C:\gameserver\T5\start_mp_server.bat`, PID was 1548) relaunches ONE fresh instance that grabs 28960 and loads the current dedicated.cfg (the valid 20-char password). Verify: exactly one bootstrapper PID, owning 28960, nothing on 28961, console `rcon_password` reads the valid value on its own (no manual set). Diagnose duplicates with: `Get-Process plutonium-bootstrapper-win32 | Select Id,StartTime` + `Get-NetUDPEndpoint | ? LocalPort -in 28960..28965 | Select LocalPort,OwningProcess` + `Get-CimInstance Win32_Process -Filter "name='cmd.exe'" | ? CommandLine -match 'start_mp_server'`.

**Still open (prevention):** how a 2nd launcher started in the first place (orphan implies a 2nd restart-loop ran at some point — likely an auto-start task/shortcut PLUS a manual run). If the server reboots and TWO loops launch, the orphan-on-28960 problem returns. Check for a duplicate auto-start (Task Scheduler / Startup folder) vs the manual `start_mp_server.bat`. Note: auto-start on reboot was "not yet set up" per [[vps-server-provisioned]] — reconcile.

Related: [[package-server-does-not-strip-markers]] (the OLD theory that gf.gsc's dev block set rcon_password live — DISPROVEN here: the deployed gf.gsc is current and sets only sv_cheats/g_password, listen-server only), [[vps-server-provisioned]], [[gunfight-us-security-audit]].
