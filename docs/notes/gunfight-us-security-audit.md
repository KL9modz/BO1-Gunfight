---
name: gunfight-us-security-audit
description: "gunfight.us is a static IIS page served FROM the game VPS (94.72.121.4, Win Server 2019); 2026-06-29 audit found RDP+WinRM internet-open, TLS1.0/1.1 enabled, no HTTPS redirect/headers, leaked RCON pw in git history. MOST hardening APPLIED 2026-06-29 (RDP scoped, WinRM closed, IIS headers+redirect+dir-listing off, cert-renew confirmed, DNSSEC/CAA/SPF/DMARC, TLS1.0/1.1 disabled). 2026-07-03 INTERIOR RE-CHECK (via SSH): web headers/redirect/no-Server-leak/cert GOOD; WinRM+SMB+RPC+RCON-tool closed; TLS1.0/1.1 registry-CONFIRMED disabled (Enabled=0). Gaps found AND FIXED same day: (1) SSH port 22 was open to Any — broad 'OpenSSH SSH Server (sshd)' rule DISABLED, 22 now scoped to home IP only; (2) HSTS raised 300s -> max-age=31536000; includeSubDomains (live-verified); (3) Windows Admin Center v2 UNINSTALLED (unused, was Disabled w/ lingering 6601/6602 procs). OpenSSH 9.5 left as-is (scoped+key-only; PQ warning cosmetic). Runbook = VPS_HARDENING.md"
metadata: 
  node_type: memory
  type: project
  originSessionId: 307605e7-a0ef-4d8b-98a6-9b59457f23bf
---

Live security audit of **gunfight.us** on 2026-06-29. The site is a harmless *static* IIS 10
landing page, but it is served by **IIS on the same Contabo VPS as the BO1 game server**
(`94.72.121.4`), so "securing the website" is really VPS remote-access hardening.

Measured exposure (TCP on 94.72.121.4): 80, 443, **3389 RDP**, **5986 WinRM-HTTPS** all
internet-open; 3000 (RCON tool) correctly closed. No HTTP→HTTPS redirect, no HSTS, zero security
headers, `Server` header leaks IIS. **TLS 1.0 + 1.1 accepted**, TLS 1.3 not offered. Cert is fine
(Let's Encrypt, exp 2026-09-27) but renewal automation unconfirmed. GoDaddy DNS has no CAA/DNSSEC/
SPF. The box uses built-in `Administrator` + AutoAdminLogon (see VPS_DEPLOY.md), so internet-open
RDP is the critical risk.

**Leaked secret:** the RCON password (`aBHgu…`, redacted — it is in public git history) was hardcoded in the committed RCON
panel and is in git history (commit `43f79da`). MUST be rotated via `package_server.ps1 -RotateRcon`
— history can't be un-leaked. This is the concrete instance of the CLAUDE.md "rotate RCON" TODO.

**APPLIED 2026-06-29** (walked through live on the VPS): OS confirmed Win Server 2019 (build 17763,
NOT 2025 → TLS 1.3 unsupported, `AllowAdministratorLockout` N/A). Done: RDP scoped to admin IP
`76.167.246.191` (broad allows disabled, via a 15-min auto-rollback scheduled task as safety net);
WinRM 5986 closed (verified externally); NLA on; lockout 10/15/15; **IIS web.config** deployed
(URL Rewrite 2.1 installed; merged file keeps FastDL MIME maps, directoryBrowse OFF, adds
HTTPS-redirect + HSTS + CSP + headers + removeServerHeader + GET/HEAD-only — all externally
verified); cert auto-renewal confirmed (win-acme, WebHosting store); DNS CAA(letsencrypt.org) +
DNSSEC(GoDaddy-managed, DS at .us) + SPF(`-all`) + DMARC(`p=reject` strict); **P1.5 TLS 1.0/1.1 DISABLED** (snapshot-protected reboot 2026-06-29,
verified externally: 1.0/1.1 rejected, 1.2 accepted, site 200; Server 2019 so 1.3 left off).
REMAINING: confirm GoDaddy domain-lock + 2FA; RCON pw rotation (P0.1) DEFERRED by user — still leaked.
Game server needs a MANUAL bat relaunch after any reboot (auto-start-on-reboot not configured).

**2026-07-03 INTERIOR re-check (SSH `ssh -i ~/.ssh/gf_vps Administrator@94.72.121.4`):** box
REBOOTED 5:36 AM (Windows Update batch: KB5012170/5094123/5094143/5087061/4577586). Auto-recovery
GOOD: game server (`plutonium-bootstrapper-win32`) auto-started 5:37 + UDP 28960 listening; IIS
(W3SVC) up. `cloudbase-init` + `WindowsAdminCenter` services now **Disabled**. STILL GOOD: RDP
scoped to 76.167.246.191; WinRM(5985/5986)+SMB(445)+RPC(135)+RCON(3000) closed; HTTP→HTTPS 301 +
full header set; no `Server` leak; LE cert valid to 2026-09-27. **TLS 1.0/1.1 registry-CONFIRMED
DISABLED** (`SCHANNEL\Protocols\TLS 1.x\Server` Enabled=0, DisabledByDefault=1; 1.2 Enabled=1) —
so the 06-29 P1.5 hardening is intact; no TLS regression. No failed logons (4625) since boot.

**REAL GAPS found:** (1) **SSH port 22 open to `Any`** — the default `OpenSSH SSH Server (sshd)`
inbound-allow rule (RemoteAddress=Any) is ENABLED alongside two home-IP-scoped rules; in Windows
Firewall any matching Allow wins, so 22 is internet-wide despite the scoping intent (RDP has NO
broad allow — only `RDP-AdminOnly-In`). Was only *hidden* earlier because sshd was stopped
post-reboot. Fix = mirror RDP P0.2: `Disable-NetFirewallRule -DisplayName "OpenSSH SSH Server
(sshd)"` (keeps the scoped rules → my session survives). (2) **HSTS `max-age=300`** (5 min,
cosmetic) → raise to >=15768000 + includeSubDomains in site web.config. Minor: sshd was DOWN after
the reboot (now Running/Automatic); WAC v2 (Inno Setup, `unins000.exe`) still installed though
service Disabled.

**FIXES APPLIED 2026-07-03 (this session, all live-verified):** (1) `Disable-NetFirewallRule
-DisplayName "OpenSSH SSH Server (sshd)"` — port 22 was scoped to the two home-IP rules
(session survived). ⚠ **SUPERSEDED: SSH (22) is now intentionally OPEN to ANY IP** (rule
`SSH-Any-In (travel)`) — safe only because sshd is **key-only**, which takes BOTH
`PasswordAuthentication no` **and** `KbdInteractiveAuthentication no` (kbd-interactive is ON by
default on Windows OpenSSH and offers its own password path). **RDP remains home-IP-scoped**
(`RDP-AdminOnly-In`). (2) web.config HSTS `max-age=300` → `max-age=31536000; includeSubDomains`
(backup `C:\inetpub\wwwroot\web.config.bak-hsts`; external curl confirms new header). (3) WAC v2
uninstalled via `"C:\Program Files\WindowsAdminCenter\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES
/NORESTART` — folder + registry gone, 6601/6602 no longer listening (`Uninstall-Package` did NOT
work; it's an Inno Setup install, not MSI — must use unins000.exe). OpenSSH left on 9.5 capability.
Note: sshd was DOWN after
the 5:36 boot (now Running/Automatic — confirm it truly survives the NEXT reboot); WAC worker procs
still listening on 6601/6602 but firewalled + service Disabled (clear on next reboot); OpenSSH is
old enough to warn "no post-quantum KEX" (low-pri update).

**openssl TLS-version test is UNRELIABLE from this client — DO NOT TRUST IT; use the interior
registry via SSH instead.** Proven 2026-07-03 by a CONTROL test: the "reliable" method (custom cnf
`MinProtocol=None` + legacy `-tls1` flag, scratchpad `ossl_notls.cnf`) reported that **google.com
AND cloudflare.com "negotiated TLSv1"** — impossible (both killed TLS 1.0 years ago), so the method
FABRICATES a TLSv1 result even when it passes the `-tls1_2`→TLSv1.2 sanity gate. It nearly produced
a false "TLS 1.0/1.1 regression" finding here. Lesson: for TLS-version questions on a box you can
reach, read `HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\<ver>\Server`
(Enabled/DisabledByDefault) — authoritative — and always run a known-good control host before
trusting any external openssl version probe.

**Why:** the prior assumption was that the "website" was the thing to secure; the real attack
surface is the shared VPS's management ports.
**How to apply:** full prioritized + lockout-checked runbook is in repo `VPS_HARDENING.md` (P0 rotate
RCON + scope RDP; P1 WinRM/NLA/lockout/web.config/TLS/cert-renewal; P2 DNS). Windows Firewall gotcha:
an explicit Block beats a narrower Allow — scope RDP with an Allow + disable broad allows, never a
"block all others" rule. Always confirm the Contabo VNC console (144.126.146.144:63019) works before
firewall/TLS changes. The local RCON tool (`tools/rcon/server.js`) was hardened in this session
(CORS wildcard dropped, Host/Origin guard, body-size cap, savecfg path pinned + sanitized). Relates
to [[t5-clients-must-install-mod-no-autodownload]] and [[vps-server-provisioned]].
