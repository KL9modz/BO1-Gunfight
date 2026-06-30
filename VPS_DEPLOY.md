# mp_gunfight - VPS Deployment Runbook

Step-by-step guide to host the **mp_gunfight** Plutonium T5 (Black Ops 1) Gunfight
server on the Contabo Cloud VPS. Verified against the project's own tooling and the
official Plutonium docs (https://plutonium.pw/docs/server/t5/setting-up-a-server/).

## Target box (what was purchased)

| | |
|---|---|
| Plan | Contabo Cloud VPS 10 SSD - 4 vCPU / 8 GB RAM / 150 GB SSD / 200 Mbit/s |
| Public IPv4 | `94.72.121.4` |
| IPv6 | `2605:a141:2340:4923::1` |
| Location | Seattle (US West) |
| OS | Windows Server 2025 Datacenter (64-bit) |
| VNC console | `144.126.146.144:63019` (out-of-band access if RDP breaks) |
| Game UDP port | `28960` |

A BO1 server is light and largely single-thread; 4 cores / 8 GB is plenty for a
small Gunfight lobby with headroom.

## How T5 connectivity works (read first)

- **You cannot `connect <publicIP>:port` remotely on T5.** Direct IP connect only works
  on the same machine/LAN (`connect 127.0.0.1:28960` on the server itself, or a private
  LAN IP). Remote players join through the **in-game Plutonium server browser** (the
  backend hands out a Session ID). So set a recognizable `sv_hostname` to find it.
- **A VPS needs NO port forwarding** (that's only for home routers behind NAT). The VPS
  has a direct public IP; the only gate is the **Windows Firewall** rule for UDP 28960.
- A valid **server key** + open UDP port = the server heartbeats to Plutonium's master
  and shows up in the server browser.

---

## Phase 0 - Decisions

| Decision | Value used here | Notes |
|---|---|---|
| `sv_maxclients` | **8** (up to 4v4) | Gunfight flips to LARGE mode at 4v4. Use 6 for small-mode-only, 12 for busier. |
| Server key | **Generate a fresh one** | platform.plutonium.pw/serverkeys. Do not reuse the dev-machine key. |
| RCON password | **Rotate via packager** | The live `dedicated.cfg` still carries a leaked value - never deploy it. |
| Public vs friends | `party_minplayers "2"`, no `g_password` = public | Set `g_password "..."` for friends-only. |
| Player mod delivery | **FastDL** (see Phase 8) | Auto-download on join; verify in-game (see caveat). |

---

## Phase 1 - First login & harden

1. RDP to `94.72.121.4`, user `Administrator`, password from Contabo's email.
   (Fallback: VNC console `144.126.146.144:63019`.)
2. Change the Administrator password immediately (Ctrl+Alt+End -> Change a password).
3. Run Windows Update -> reboot.
4. Server Manager -> Local Server -> set **IE Enhanced Security Config = Off**
   (so the built-in browser can download files), or paste links via the RDP clipboard.

## Phase 2 - Game files + Plutonium

5. **Black Ops 1 game files** go in `C:\gameserver\T5` (the docs' standard path):
   - Easiest: zip your local trimmed server copy (you keep one at `S:\BO1_Server`),
     upload via RDP drive redirection (mstsc -> Local Resources -> More -> Drives),
     and extract to `C:\gameserver\T5`.
   - Or follow the game-files step on the official docs page from the VPS browser.
6. **Plutonium launcher:** download from plutonium.pw, place it in `C:\gameserver\T5`,
   run it once and log in with your Plutonium account so it downloads the engine
   binaries into `%LOCALAPPDATA%\Plutonium\bin\` (this creates
   `plutonium-bootstrapper-win32.exe`, which the launch bat calls).
7. **T5 config files:** download the T5ServerConfig zip
   (https://github.com/xerxes-at/T5ServerConfig/archive/refs/heads/master.zip).
   - Move everything **except** the `localappdata` folder into `C:\gameserver\T5`.
   - Move the zip's `localappdata\Plutonium\*` into `%LOCALAPPDATA%\Plutonium`.
8. **Server key:** platform.plutonium.pw/serverkeys -> name it (e.g. "Gunfight-Seattle"),
   game **Black Ops (T5)**, create, copy the key.

## Phase 3 - Build & package the mod (LOCAL machine)

9. From the repo root:
   ```powershell
   tools\package_server.ps1 1.0.0 -RotateRcon
   ```
   Rebuilds `mod.ff`, stages `mod.ff` + `mod.csv` + all `maps\*.gsc` + `dedicated.cfg`
   (with a fresh random <=20-char RCON password injected into the BUNDLED copy only),
   writes `DEPLOY.txt`, and prints the new RCON password in a green/cyan banner -
   **save that password.** Output: `tools\dist\mp_gunfight-server-1.0.0.zip`.
   (Add `-SkipBuild` if `mod.ff` is already current and only GSC/cfg changed.)

## Phase 4 - Deploy the mod on the VPS

10. Upload `mp_gunfight-server-1.0.0.zip` and extract so the `t5\` folder lands inside
    `%LOCALAPPDATA%\Plutonium\storage\`. Result:
    ```
    %LOCALAPPDATA%\Plutonium\storage\t5\mods\mp_gunfight\   (mod.ff + mod.csv + GSC)
    %LOCALAPPDATA%\Plutonium\storage\t5\dedicated.cfg
    ```
11. Edit `storage\t5\dedicated.cfg`:
    - `rcon_password` - already the rotated value (no action unless you want to change it).
    - **Add** `set sv_hostname "Gunfight | Seattle"` so it is identifiable in the browser.
    - `party_minplayers "2"` (public) - already correct.
    - `g_gametype "gf"`, `xblive_wagermatch "0"`, the 28-map `sv_maprotation` - already set.
    - (For IW4MAdmin later: `g_logSync 2` and a unique `g_log`.)

## Phase 5 - Launch script & firewall

12. Edit the start bat in `C:\gameserver\T5` (from the T5ServerConfig zip):
    ```bat
    set key=<YOUR-NEW-SERVER-KEY>
    set cfg=dedicated.cfg
    set name=Gunfight
    set port=28960
    set maxclients=8
    set mod=mods/mp_gunfight
    ```
    Launch line (your proven command - gamepath points at the game files):
    ```bat
    cd /D %LOCALAPPDATA%\Plutonium
    :server
    start /wait /abovenormal bin\plutonium-bootstrapper-win32.exe t5mp "C:\gameserver\T5" -dedicated ^
      +set key %key% +set fs_game "mods/mp_gunfight" +exec "dedicated.cfg" ^
      +set net_port %port% +set sv_maxclients %maxclients% +map_rotate
    goto server
    ```
    The mod loads via `fs_game "mods/mp_gunfight"` (NOT a `loadMod` line in the cfg).
    The `:server ... goto server` loop auto-restarts on crash.
13. **Open the firewall port** (PowerShell as admin on the VPS):
    ```powershell
    New-NetFirewallRule -DisplayName "Plutonium T5 28960 UDP" -Direction Inbound `
      -Protocol UDP -LocalPort 28960 -Action Allow
    ```
    No port forwarding needed (direct public IP). If you enable Contabo's optional Cloud
    firewall, allow UDP 28960 there too.

## Phase 6 - Keep it running across reboots

14. The bootstrapper needs an interactive session, so:
    - Enable auto-logon. **Do NOT use the Winlogon `DefaultPassword` registry method** (stores the
      password in cleartext) and **do NOT auto-logon the admin account** - see Phase 10 #2/#3:
      auto-logon the low-priv `gfsvc` user via Sysinternals **Autologon.exe** (encrypted LSA secret).
    - Put a shortcut to the start bat in `shell:startup`.
    - The bat's restart loop handles crashes; Startup handles reboots.
    - **When you leave: DISCONNECT RDP, do not LOG OFF** (log off kills the session and
      the server). Closing the mstsc window disconnects without logging off.

## Phase 7 - Verify

15. On the VPS, double-click the start bat; wait for the console to load a map and report
    the server started.
16. From your home Plutonium client, open the **server browser** and find
    "Gunfight | Seattle" (your `sv_hostname`). Join from there. (Remember: remote
    `connect 94.72.121.4:28960` will NOT work on T5.)
17. On the VPS itself you can smoke-test locally with `connect 127.0.0.1:28960`.
18. Test RCON from your RCON client/panel with the rotated password (e.g. `status`,
    `map_rotate`). With no `rconWhitelistAdd` lines active, any IP may send RCON but the
    password is still required; tighten later by adding your own IP.

## Phase 8 - Player mod distribution via FastDL (clients auto-download mod.ff on join)

> **CORRECTION (2026-06-29):** an earlier version of this doc claimed "FastDL does NOT work
> for T5 mods." **That was wrong** - it was a misconfiguration, not an engine limit. Plutonium
> T5 *does* download the server's mod to clients on join, and FastDL (`sv_wwwBaseURL`) is the
> mechanism. Confirmation: Plutonium staff (Resxt, forum topic 44044, Feb 2026): *"FastDL is how
> you make the downloading happen"*; the client's own log shows `Requesting mod list -> Received
> mod dl info response! -> found N files required for mod download`; official docs at
> `plutonium.pw/docs/server/t5/fastdl`. The old "manual install" path still works as a fallback.

**Why the first attempt failed (all three were true at once):**
1. `sv_wwwBaseURL` was **empty at runtime** - every server log dump showed `sv_wwwBaseURL ""`.
   With no URL the client has nowhere to fetch from -> "Invalid download response." This dvar
   **latches at startup**: it must be in `dedicated.cfg` *before launch*, not set over RCON.
2. **IIS 404s the `.ff` extension** unless a MIME type is mapped (IIS refuses unknown extensions).
3. A **version mismatch** (r5316 client vs r5328 server) fails the handshake independently.

The server advertises exactly **1 file** for our mod: `mod.ff` (confirmed in `console_mp.log`:
`found 1 files required for mod download`). So FastDL only needs to serve that one file.

### One-time VPS setup

19. **Map the `.ff` MIME type in IIS** (so it serves `mod.ff` instead of 404ing). Elevated PowerShell:
    ```powershell
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:staticContent `
        /+"[fileExtension='.ff',mimeType='application/octet-stream']"
    # (add .iwd and .iwi the same way only if you later ship custom maps/assets)
    ```
    This adds one `<mimeMap>` to the live (VPS-owned, hardened) `web.config`; the existing
    HTTPS-redirect/HSTS/GET-HEAD-only rules are unaffected. **Alternative (staff-recommended,
    zero MIME fuss):** run **HFS** (github.com/rejetto/hfs) on a separate port rooted at a folder
    containing `mods\`, and point `sv_wwwBaseURL` at `http://gunfight.us:<port>/`.
20. **Set the base URL in `dedicated.cfg`** (the VPS-local one in `storage\t5\`, the sole owner of
    `rcon_password` - never published), then restart the server:
    ```cfg
    set sv_wwwBaseURL "https://gunfight.us/"
    ```
    Trailing slash. The URL must point at the dir that *contains* `mods\`, NOT at `mods\` itself.
    **Use `https://`, not `http://`:** the hardened IIS 301-redirects http->https (verified), and
    the FastDL client may not follow the redirect - https serves `mod.ff` directly (valid cert, 200).
    After restart, confirm the startup console dump shows a **non-empty** `sv_wwwBaseURL` (the
    old failure was it staying `""`). If https downloads fail, fall back to **HFS on a separate
    plain-HTTP port** (`http://gunfight.us:<port>/`) - it dodges both the redirect and the MIME map.

### Every deploy (automatic)

21. `.\tools\deploy.ps1 -Mod` now publishes `mod.ff` to `C:\inetpub\wwwroot\mods\mp_gunfight\mod.ff`
    as part of the mod deploy (the FastDL copy is just `mod.ff` - never the mod tree, so nothing
    private is exposed). `-Web`'s `/MIR` excludes `mods\`+`usermaps\` so it never deletes it.
    Pass `-NoFastDL` to skip. **Verify** from an external network that
    `http://gunfight.us/mods/mp_gunfight/mod.ff` **downloads the binary** (not a 404/HTML page)
    before announcing the server.

### What players still must do

22. **Match the Plutonium build** - FastDL ships the *mod*, not the *engine*. A stale client
    (e.g. r5316 vs r5328) still fails the handshake; players just run the launcher so it updates.
    With a matching build + FastDL, joining from the server browser auto-downloads `mod.ff` -
    **no manual Mods-menu install required.**
23. **Fallback (manual install)** if you ever run FastDL off: give players the public package
    (`tools\package_release.ps1` zip / the `release` branch), extract into their own
    `...\storage\t5\mods\mp_gunfight\` (their `mod.ff` must byte-match the server's), then load it
    via main menu -> **Mods** -> `mp_gunfight` -> wait for "Mod loaded from mods/mp_gunfight" ->
    join. With FastDL working this step is unnecessary.

> Remote `connect <ip>:port` does not work on T5 - players find the server in the in-game
> browser by its `sv_hostname`. Loopback `connect 127.0.0.1:28960` works only on the VPS itself.

## Phase 9 - Operations

- **Optional slim-down:** delete everything in the game's `main\` except `iw_00.iwd` and
  `server.cfg` -> ~3 GB instead of ~11 GB and faster map loads. Do this only AFTER the
  server runs cleanly.
- **Update the mod:** the recommended path is now **git-pull deploys** (Phase 11) - no
  zip upload. The legacy manual path still works: rebuild -> `package_server.ps1 <newver>`
  -> upload -> extract over the old folder -> restart the bat.
- **Rotate RCON later:** re-run `package_server.ps1 -RotateRcon`, redeploy the cfg.
- **Backups:** take a Contabo snapshot once it works so you can roll back.

## Phase 10 - Security hardening (REQUIRED before/while public)

Run on the VPS in an **elevated PowerShell**. Ordered by impact. `<YOUR_IP>` = your home/admin
public IPv4 (find it at https://ifconfig.me). Do **#1 before #2** or a spammer hitting the
world-open 3389 can lock out your own admin account.

**1. Lock RDP to your IP + harden auth (highest impact - 3389 is world-open by default).**
```powershell
# Scope RDP to your IP only (replicate this in the Contabo Cloud Firewall too):
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Set-NetFirewallRule -RemoteAddress <YOUR_IP>
# Enforce Network Level Authentication:
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 1
# Account lockout (AFTER the firewall scope above is in place):
net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30
# Separate named admin; disable the well-known default 'Administrator':
New-LocalUser gfadmin -Password (Read-Host -AsSecureString); Add-LocalGroupMember Administrators gfadmin
# (log in as gfadmin, confirm it works, THEN:)  Disable-LocalUser Administrator
```
Best of all: pull 3389 off the public internet and reach it over **Tailscale/WireGuard**; if you
keep public RDP, add MFA (e.g. Duo for Windows Logon). Changing the RDP port is obscurity only.

**2. Run the game server as a low-privilege user (caps blast radius of any engine/mod RCE).**
```powershell
New-LocalUser gfsvc -Password (Read-Host -AsSecureString) -PasswordNeverExpires   # stays in 'Users' only
```
Auto-logon **gfsvc** (not an admin) and put the start-bat shortcut in its `shell:startup`.

**3. Fix auto-logon: never store the password in plaintext registry.** Replace the Winlogon
`DefaultPassword` method (Phase 6) with Sysinternals **Autologon.exe** (encrypted LSA secret):
```powershell
# Download Autologon from https://learn.microsoft.com/sysinternals/downloads/autologon , then:
.\Autologon.exe gfsvc <COMPUTERNAME> <password>
```
Also auto-**lock** the session after logon so the auto-logged-in desktop isn't sitting open on the
VNC console: add a logon scheduled task running `rundll32.exe user32.dll,LockWorkStation`.

**4. Firewall = default-deny inbound; only UDP 28960 (game) + scoped RDP.**
```powershell
Set-NetFirewallProfile -Profile Domain,Private,Public -DefaultInboundAction Block -DefaultOutboundAction Allow
New-NetFirewallRule -DisplayName 'Plutonium T5 28960 UDP' -Direction Inbound -Protocol UDP -LocalPort 28960 -Action Allow
# Remove the FastDL/IIS experiment (does nothing for T5 mods) and confirm nothing else listens externally:
Uninstall-WindowsFeature Web-Server -Remove
Get-NetTCPConnection -State Listen | Where-Object LocalAddress -notin '127.0.0.1','::1'
```
The RCON web panel binds `127.0.0.1:3000` - never port-forward it; reach it via RDP on the box.

**5. RCON access control (engine-level).** In `dedicated.cfg`, enable the whitelist (see the
`RCON ACCESS CONTROL` block): uncomment `rconWhitelistAdd "127.0.0.1"` if you run the panel on the
VPS (blocks all internet rcon), or set your public IP if you rcon remotely. Keep
`rcon_localhost_bypass "0"`. The rcon_password is the gate to the GSC cheat bridge, so treat it as
a primary secret and rotate via `package_server.ps1 -RotateRcon`.

**6. Patching / Defender / SMBv1.**
```powershell
Set-MpPreference -DisableRealtimeMonitoring $false -ScanScheduleDay Everyday -ScanScheduleTime 03:00
Update-MpSignature
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
# Re-enable IE Enhanced Security Config after setup downloads are done (reverses Phase 1 step 4).
```
Keep Windows Update on automatic, and keep the Plutonium launcher/bootstrapper current.

**7. Out-of-band & provider plane.** Rotate the Contabo **VNC** password to the longest the panel
allows; enable **2FA on the Contabo customer panel** (it can rebuild/reset the box). Don't leave an
auto-logged-in *admin* desktop reachable on the console (covered by #2/#3).

**8. Monitoring & recovery.**
```powershell
# Failed RDP logons (should be ~zero once RDP is IP-scoped):
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -MaxEvents 50 |
  Select TimeCreated,@{n='User';e={$_.Properties[5].Value}},@{n='SrcIP';e={$_.Properties[19].Value}}
```
Take a Contabo **snapshot** after hardening and before each deploy. Keep the server key + rcon
password in a password manager so identity survives a rebuild.

## Phase 11 - Ongoing deploys via git pull (recommended)

After the box is set up (Phases 1-10), routine mod **and** website updates go through git
instead of zip-upload-and-extract. The laptop pushes to GitHub; the VPS pulls and a small
`.\tools\deploy.ps1` copies into the two live locations. Git is **outbound HTTPS** from the
VPS, so this opens **no new inbound ports** - the default-deny firewall (Phase 10 #4) is
unchanged. The website source now lives in the repo at `site\wwwroot\`, so it is version-
controlled and editable like any other file (Claude edits it directly).

> **Windows PowerShell note:** run repo scripts with a leading `.\` (e.g. `.\tools\deploy.ps1`,
> `.\tools\vps_setup.ps1`). Without it, PowerShell treats `tools\...` as a module-qualified
> command and fails with "the module 'tools' could not be loaded."

### One-time setup on the VPS
1. Install **Git for Windows**. (No winget on this Server image - download the latest installer
   from the git-for-windows GitHub releases, or git-scm.com/download/win.)
2. **No credentials needed** - `KL9modz/BO1-Gunfight` is a public repo, so `git clone`/`pull`
   work unauthenticated, and the box has no push credentials = read-only (pull-only) for free.
   (Only if the repo is ever made private: add a read-only fine-grained PAT or deploy key in
   Windows Credential Manager.)
3. Clone once to a neutral path, **as the account that runs the game server** (so a plain
   `.\tools\deploy.ps1 -Mod` resolves `$env:LOCALAPPDATA` to that account's Plutonium storage).
   The hardening ideal is a low-priv `gfsvc` user; **on this box the server runs as
   `Administrator`**, so run deploys from an elevated Administrator session (`-Mod` then needs no
   `-ModDest`). `.\tools\vps_setup.ps1` prints the right command for whichever account you use.
   ```powershell
   git clone -b main https://github.com/KL9modz/BO1-Gunfight.git C:\gfdeploy\BO1-Gunfight
   ```
   **Use `-b main`.** The GitHub *default* branch is `release` (the minimal public snapshot with
   NO `tools/` or `site/`), so a plain `git clone` lands there and the deploy scripts are missing.
   The deploy clone must be on `main`; on an existing clone, switch with `git checkout main`.
   `deploy.ps1 -Mod` then fetches `mod.ff` from the `release` branch on demand (it is a gitignored
   binary on `main`).
4. Confirm the deploy account has write access to `C:\inetpub\wwwroot` and the Plutonium mods
   path (Administrator already does; a low-priv `gfsvc` may need ACL grants).

### Deploy a WEBSITE change (no restart)
```powershell
# Laptop:
tools\push_all.ps1 "web: <what changed>"
# VPS (RDP), in C:\gfdeploy\BO1-Gunfight:
.\tools\deploy.ps1 -Web          # add -DryRun first to preview
```
Mirrors `site\wwwroot\` -> `C:\inetpub\wwwroot`. Secret-scans first and **refuses to publish**
if it finds an RCON password / secret. The VPS-owned hardened `web.config` (Phase 10) is
preserved (excluded from the mirror unless you deliberately track one), and the Let's Encrypt
`.well-known` challenge dir is never purged. IIS serves the new files immediately - just hard-refresh.

### Deploy a MOD change (restarts the server)
```powershell
# Laptop:
tools\build_ff.ps1                            # only if mod.ff-affecting files changed
                                              #   (menus / strings / gametypesTable / fx);
                                              #   pure-GSC edits load as loose rawfiles - skip it
tools\package_release.ps1 <ver> -PublishBranch  # force-push mod.ff + GSC to the release branch
tools\push_all.ps1 "deploy: <what changed>"     # push main
# VPS (RDP), in C:\gfdeploy\BO1-Gunfight:
.\tools\deploy.ps1 -Mod          # pulls main + release mod.ff, mirrors to the mod folder, restarts
```
`deploy.ps1 -Mod` never touches `dedicated.cfg` (it lives in `storage\t5\`, not the mod folder,
and is the sole owner of `rcon_password`). Players still install the matching public package
themselves - T5 has no client mod download (Phase 8) - so re-cut it with
`package_release.ps1 <ver> -Publish` when `mod.ff` changes.

### Rollback
- Bad web deploy: `git reset --hard <good-sha>` then `.\tools\deploy.ps1 -Web`.
- Bad mod deploy: re-run `package_release.ps1` from the previous good commit and
  `.\tools\deploy.ps1 -Mod`, or restore the Contabo snapshot.

> The RCON admin panel (`tools\rcon\`) is part of the mod tree, stays bound to `127.0.0.1:3000`,
> and is **never** part of the website deploy. The public site is `site\wwwroot\` only.

## Secrets checklist (never commit / publish)

- New Plutonium **server key** (in the start bat).
- Rotated **rcon_password** (in `dedicated.cfg`; printed by the packager). The GSC no longer sets
  any rcon_password (removed 2026-06-29); `dedicated.cfg` is the sole owner. `package_server.ps1`
  now hard-fails if a staged `.gsc` hardcodes one.
- The live `dedicated.cfg` and the start bat stay OFF the public release branch/zip.
- Treat the **Contabo panel + VNC** passwords as primary secrets (panel can rebuild the box).
