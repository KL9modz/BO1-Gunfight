# gunfight.us / VPS Security Hardening Runbook

Verified hardening steps for **gunfight.us** and the Contabo VPS (`94.72.121.4`) that
serves it. Produced from a live audit on 2026-06-29 (direct probing of the box + an
adversarially-reviewed analysis). Every apply-to-production command below was checked for
**lockout / breakage** risk before inclusion.

> **Architecture reality:** `gunfight.us` is a *static* IIS page, but it is served by **IIS on
> the same VPS as the BO1 game server**. The page itself is low-risk; the real exposure is the
> box's remote-management surface. So this runbook is mostly about the VPS, not the HTML.

> **OS confirmed: Windows Server 2019 Datacenter (build 17763)** — *not* 2025 as an earlier note
> said. Consequences baked into this runbook: TLS 1.3 is **unsupported** on 2019 (skip it; keep
> 1.2 top), and `AllowAdministratorLockout` **does not exist** on 2019 (P1.3's optional part is N/A).

## ✅ As-applied status (worked through interactively 2026-06-29)
| Item | Status | Notes |
|---|---|---|
| RCON tool hardening (`tools/rcon/server.js`) | ✅ done | committed `af1707b`: CORS wildcard dropped, loopback Host/Origin guard, body cap, savecfg path pinned + sanitized. Panel password un-hardcoded. |
| **P0.2 RDP → scoped to admin IP** (`76.167.246.191`) | ✅ done | rule `RDP-AdminOnly-In`; broad built-in allows disabled. Used a **15-min scheduled auto-rollback task** as the safety net (re-enables broad RDP if the scoped rule is wrong) — see pattern below. |
| **P1.1 WinRM 5986 → closed** | ✅ done | service stopped+disabled, `WinRM-HTTPS-Block-In` rule, built-in WinRM allows disabled. Verified externally OPEN→closed. Leftover `0.0.0.0:5986` http.sys sslcert is inert (optional `netsh http delete sslcert ipport=0.0.0.0:5986`). |
| P1.2 NLA | ✅ done | `UserAuthentication=1`. `SecurityLayer` was already `2` (TLS-only) and working — left as-is. |
| P1.3 Account lockout | ✅ done | threshold 10 / 15 / 15. Built-in Administrator exempt on 2019 (auto-logon safe). |
| **P1.4 IIS web.config** | ✅ done + externally verified | Installed **URL Rewrite 2.1**. Deployed a **merged** `C:\inetpub\wwwroot\web.config` that KEEPS the FastDL MIME maps, turns **directoryBrowse off** (was on), and adds HTTP→HTTPS redirect + HSTS(300, HTTPS-only) + CSP + X-Frame/X-CTO/Referrer/Permissions + `removeServerHeader` + GET/HEAD-only verbs. `.bak` saved alongside. |
| P1.6 Cert auto-renewal | ✅ confirmed | win-acme task `Ready`, `C:\win-acme\wacs.exe --renew`; cert in **WebHosting** store bound to :443; issued today so the pipeline demonstrably works. |
| P2.1 CAA | ✅ done | `0 issue "letsencrypt.org"` (issuewild/iodef skipped). |
| P2.3 DNSSEC | ✅ done | GoDaddy-managed; DS (2, algo 13) at `.us`, 4 DNSKEYs, queries validate (`AD:true`). **If NS ever change, disable DNSSEC first.** |
| P2.2 SPF + DMARC | ✅ done | `v=spf1 -all`; DMARC `p=reject; sp=reject; adkim=s; aspf=s`. No MX. |
| **P1.5 disable TLS 1.0/1.1** | ✅ done | snapshot-protected reboot 2026-06-29; verified externally — TLS 1.0/1.1 rejected, 1.2 accepted, site 200. (Server 2019 → 1.3 left off.) |
| Registrar lock + 2FA | ⬜ confirm in portal | `.us` RDAP wouldn't answer remotely — verify GoDaddy Domain lock = ON + 2FA on account & Gmail. |

> **Auto-rollback firewall pattern (used for P0.2, reuse for any remote firewall change):** before
> disabling broad allows, register a SYSTEM scheduled task that re-enables them in ~15 min, so a bad
> rule self-heals even without VNC. Confirm the scoped rule works via a fresh connection, THEN
> `Unregister-ScheduledTask` to cancel the rollback. (Windows Firewall gotcha: an explicit **Block**
> beats a narrower **Allow**, so scope with an Allow + disable the broad allows — never add a
> "block all others" rule, it matches your own IP too.)

## Out-of-band safety net (read first)
Every firewall/TLS/RDP change below can, if mistyped, drop your RDP session. Your recovery path
is the **Contabo VNC console `144.126.146.144:63019`** — it bypasses Windows Firewall and Schannel
entirely. **Confirm you can log into the VNC console BEFORE running any P0/P1 step.** Keep a second
RDP session open as a live canary while changing remote-access settings.

---

## What the audit measured (baseline, 2026-06-29)
| Area | Finding |
|---|---|
| Open ports on `94.72.121.4` | 80, 443, **3389 (RDP)**, **5986 (WinRM-HTTPS)** all internet-open. 3000 (RCON tool) correctly closed. |
| Web server | IIS 10. HTTP **not** redirected to HTTPS; **no HSTS**; **zero** security headers; `Server` header leaks IIS. |
| TLS | Cert good (Let's Encrypt, `gunfight.us`+`www`, exp **2026-09-27**). **TLS 1.0 + 1.1 accepted**; **TLS 1.3 not offered**. Renewal automation **unconfirmed**. |
| DNS (GoDaddy) | No CAA, no DNSSEC, no SPF/DMARC/null-MX. `www` is a 2nd A record. |
| Secret leak | RCON password `aBHguGlfMQA9NcqEO1YJ5WKm` was hardcoded in the committed RCON panel + is in git history (commit `43f79da`). |

---

## P0 — Do today

### P0.1 Rotate the leaked RCON password
The old value is in git history and cannot be un-leaked. Rotate it and redeploy:
```powershell
# On the dev box, from the repo root — generates a fresh random pw into the BUNDLED cfg only:
tools\package_server.ps1 <ver> -RotateRcon   # prints the new password; save it
```
Deploy the new bundle's `dedicated.cfg` to the VPS, restart the server, and update your RCON
client/panel with the printed value. (History scrubbing is optional — rotation makes the old
value inert. The repo panel's input no longer hardcodes it.)

### P0.2 Scope RDP (and WinRM) to your IP — the #1 risk
RDP open to the whole internet on an `Administrator` + AutoAdminLogon box is the top ransomware
vector. **Key correction the audit caught:** in Windows Firewall an explicit **Block beats a
narrower Allow**, so do NOT add a "block all others" rule — it would match your own IP. The
default inbound action is already Deny; a scoped Allow + disabling the broad built-in allows is
sufficient and safe.

```powershell
# ===== ELEVATED PowerShell ON THE VPS. VNC console ready, 2nd RDP session open. =====

# STEP 1 — on YOUR LOCAL machine, find your public IP:
#   (Invoke-RestMethod 'https://api.ipify.org')   ->  e.g. 203.0.113.45
$MyIP = '<YOUR.PUBLIC.IP.HERE>'   # single IP = /32

# STEP 2 — create/update ONE scoped allow rule for RDP (idempotent):
if (Get-NetFirewallRule -DisplayName 'RDP-AdminOnly-In' -ErrorAction SilentlyContinue) {
  Set-NetFirewallRule -DisplayName 'RDP-AdminOnly-In' -RemoteAddress $MyIP -Action Allow -Enabled True
} else {
  New-NetFirewallRule -DisplayName 'RDP-AdminOnly-In' -Direction Inbound `
    -Protocol TCP -LocalPort 3389 -RemoteAddress $MyIP -Action Allow -Profile Any
}

# STEP 3 — HARD GATE: open a SECOND brand-new RDP session to 94.72.121.4. It MUST connect.
#          Keep both sessions open. DO NOT proceed until this works.

# STEP 4 — disable every OTHER inbound rule that opens 3389 broadly (no Block rule, by design):
Get-NetFirewallPortFilter -Protocol TCP | Where-Object { $_.LocalPort -eq 3389 } |
  Get-NetFirewallRule |
  Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' -and $_.DisplayName -ne 'RDP-AdminOnly-In' } |
  Disable-NetFirewallRule

# STEP 5 — confirm ONLY RDP-AdminOnly-In now allows 3389:
Get-NetFirewallPortFilter -Protocol TCP | Where-Object { $_.LocalPort -eq 3389 } |
  Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' } |
  Format-Table DisplayName, Enabled, Action
```
**Lockout recovery:** if a session can't reconnect, use the VNC console and re-run STEP 2 with the
correct IP, or `Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'` to reopen RDP. A dynamic
home IP will eventually stop matching — re-scope from VNC, or move to the VPN/Tunnel option (P3).

---

## P1 — This week

### P1.1 Close WinRM-over-HTTPS (5986)
The box is RDP-administered; WinRM is pure attack surface. Do this **after** P0.2 is confirmed.
```powershell
Disable-PSRemoting -Force
Stop-Service WinRM -Force
Set-Service  WinRM -StartupType Disabled
Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
New-NetFirewallRule -DisplayName 'WinRM-HTTPS-Block-In' -Direction Inbound `
  -Protocol TCP -LocalPort 5986 -RemoteAddress Any -Action Block -Profile Any -Enabled True
Get-NetFirewallRule -DisplayName 'Windows Remote Management*' | Disable-NetFirewallRule
# Verify from your CLIENT machine (not the VPS):
#   Test-NetConnection 94.72.121.4 -Port 5986   # expect False
#   Test-NetConnection 94.72.121.4 -Port 3389   # expect True  (RDP still up)
```
(If you ever want WinRM, instead scope the built-in `Windows Remote Management (HTTPS-In)` rule's
`-RemoteAddress` to `$MyIP` — do NOT stack a broad Block, it beats the Allow.)

### P1.2 Enforce NLA on RDP (no reboot; affects only new connections)
```powershell
$rdp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Get-ItemProperty $rdp -Name UserAuthentication, SecurityLayer    # check current
Set-ItemProperty  $rdp -Name UserAuthentication -Type DWord -Value 1   # require NLA
```
**Do NOT set `SecurityLayer=2`** (TLS-only) — it requires a valid RDP cert with no fallback and is
a latent lockout if win-acme ever rebinds the RDP cert. Leave SecurityLayer at the default (1 =
Negotiate). Open a fresh RDP session to confirm before disconnecting; revert from VNC with
`Set-ItemProperty $rdp -Name UserAuthentication -Value 0` if needed.

### P1.3 Account lockout policy (safe baseline)
```powershell
net accounts /lockoutthreshold:10 /lockoutduration:15 /lockoutwindow:15
net accounts   # verify
```
This throttles normal accounts and **does not** touch the built-in Administrator (RID 500), so it
can't break AutoAdminLogon. The *real* fix for Administrator guessing is P0.2 (scope the port) —
do not enable `AllowAdministratorLockout` while 3389/5986 are internet-open, or an attacker can
trip the lockout and deny YOU the auto-logon account. Best practice: create a **separate named
admin** for interactive RDP and reserve built-in Administrator solely for the local auto-logon.

### P1.4 IIS response hardening — `web.config`
Adds HTTP→HTTPS redirect, HSTS, security headers, removes the `Server` header, blocks unneeded
verbs. **Pre-flight first** — the redirect/HSTS need the URL Rewrite module; shipping the
`<rewrite>` block without it 500s *every* request.
```cmd
:: Is URL Rewrite installed? (a Version line = yes)
reg query "HKLM\SOFTWARE\Microsoft\IIS Extensions\URL Rewrite" /v Version
```
- **If installed:** use the full `web.config` below.
- **If not:** install it (https://www.iis.net/downloads/microsoft/url-rewrite), OR delete the
  `<rewrite>` block and do the redirect as a separate **:80-only** site (see note at the bottom of
  the file). Never put `<httpRedirect>` in a combined :80/:443 site — it infinite-loops HTTPS.

HSTS starts at `max-age=300` deliberately; raise to `31536000; includeSubDomains` only after a few
days of stable HTTPS + confirmed cert renewal.
```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>

    <!-- Requires URL Rewrite module. Delete this whole block if it isn't installed. -->
    <rewrite>
      <rules>
        <rule name="HTTP to HTTPS redirect" stopProcessing="true">
          <match url="(.*)" />
          <conditions><add input="{HTTPS}" pattern="^OFF$" /></conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" appendQueryString="true" />
        </rule>
      </rules>
      <outboundRules>
        <rule name="Add HSTS header" enabled="true">
          <match serverVariable="RESPONSE_Strict_Transport_Security" pattern=".*" />
          <conditions><add input="{HTTPS}" pattern="^ON$" /></conditions>
          <action type="Rewrite" value="max-age=300" />
        </rule>
      </outboundRules>
    </rewrite>

    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Content-Type-Options" value="nosniff" />
        <add name="X-Frame-Options" value="DENY" />
        <add name="Referrer-Policy" value="no-referrer" />
        <add name="Permissions-Policy" value="geolocation=(), microphone=(), camera=(), payment=(), usb=(), interest-cohort=()" />
        <add name="Content-Security-Policy" value="default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-src https://discord.com; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; upgrade-insecure-requests" />
      </customHeaders>
    </httpProtocol>

    <security>
      <requestFiltering removeServerHeader="true">
        <verbs allowUnlisted="false">
          <add verb="GET"  allowed="true" />
          <add verb="HEAD" allowed="true" />
          <add verb="POST" allowed="false" />
          <add verb="OPTIONS" allowed="false" />
          <add verb="TRACE" allowed="false" />
          <add verb="PUT" allowed="false" /><add verb="DELETE" allowed="false" /><add verb="PATCH" allowed="false" />
        </verbs>
      </requestFiltering>
    </security>

  </system.webServer>
</configuration>
```
> **CSP caveat:** validate against the real landing-page HTML before locking in. The page links to
> GitHub/Discord (navigation `<a>` is fine under this CSP). If it uses inline `<style>`,
> `style-src 'unsafe-inline'` covers it; if it loads an external font/CSS/JS, add that origin.
>
> **`frame-src https://discord.com` — required for the Discord widget on `status.html`.** The Live
> Status page embeds Discord's official server-widget iframe (`discord.com/widget?id=...`). Under a
> bare `default-src 'none'` the frame silently renders **blank** (no error banner) because `frame-src`
> falls back to `default-src`; the widget itself is self-contained (its scripts run in Discord's own
> origin inside the frame). The pre-existing `X-Frame-Options: DENY` + `frame-ancestors 'none'` only
> stop **our** page from being framed by others; they don't affect us embedding Discord.
>
> `status.html` also drives its live server readout with an inline `<script>` + a same-origin
> `fetch('live/status.json')`, so shipping it needs `script-src 'self' 'unsafe-inline'` and
> `connect-src 'self'` **in addition** to the `frame-src` above. `index.html` and `setup.html` stay
> pure-static and need none of these. (The page is 404 on live until deployed.)

**Apply & test (from a separate machine):**
```
curl -I http://gunfight.us/    # expect 301 -> https
curl -I https://gunfight.us/   # expect 200 + headers, no Server header
curl -s -o NUL -w "%{http_code}" -X OPTIONS https://gunfight.us/   # expect 404
```
If you see `500.x`, the module/lock pre-flight was wrong — delete `web.config` (or just the
`<rewrite>` block) via RDP/VNC and you're instantly back to the working page.

### P1.5 Disable TLS 1.0/1.1, enable 1.2/1.3 (Schannel, **OS-wide, needs reboot**)
This affects RDP + WinRM TLS too. **Confirm VNC login works first.** Use **IIS Crypto (Nartac)
"Best Practices" template** as the safer GUI route, or the `.reg` below, then reboot.
```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server]
"Enabled"=dword:00000000
"DisabledByDefault"=dword:00000001
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server]
"Enabled"=dword:00000000
"DisabledByDefault"=dword:00000001
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server]
"Enabled"=dword:00000001
"DisabledByDefault"=dword:00000000
; TLS 1.3 — only honored on Server 2022/2025 (inert no-op on 2019; confirm OS with `winver`):
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server]
"Enabled"=dword:00000001
"DisabledByDefault"=dword:00000000
; .NET (so win-acme renewal keeps using strong TLS) — both bitnesses:
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\.NETFramework\v4.0.30319]
"SystemDefaultTlsVersions"=dword:00000001
"SchUseStrongCrypto"=dword:00000001
[HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319]
"SystemDefaultTlsVersions"=dword:00000001
"SchUseStrongCrypto"=dword:00000001
```
**After reboot:** reconnect RDP, confirm the game server bat relaunched (auto-start on reboot is
NOT configured — see VPS_DEPLOY.md), force a win-acme renewal dry-run (P1.6) to prove renewal still
works over the restricted stack, and re-probe 443 from off-box (e.g. SSL Labs / `openssl s_client`).

### P1.6 Confirm cert auto-renewal (HTTPS hard-breaks ~2026-09-27 otherwise)
```powershell
Import-Module WebAdministration -ErrorAction SilentlyContinue
# What cert is the LIVE 443 binding actually serving + its expiry (ground truth):
Get-WebBinding -Protocol https | ForEach-Object {
  $h=$_.certificateHash
  if($h){ $c=Get-ChildItem Cert:\LocalMachine\My | ?{ $_.Thumbprint -eq $h }
    [pscustomobject]@{ Binding=$_.bindingInformation; Subject=$c.Subject; NotAfter=$c.NotAfter } } } | Format-List
# Is there a renewal scheduled task?
Get-ScheduledTask | ?{ $_.TaskName -match 'acme|certify' -or $_.TaskPath -match 'acme' } |
  Format-List TaskName,TaskPath,State
```
- Task exists + `LastTaskResult 0` + binding `NotAfter` tracks the cert → automated; document the
  tool + task name in VPS_DEPLOY.md.
- No task / unsure it rebinds IIS → re-run `wacs.exe` interactively: validation **http-01 via the
  IIS plugin** (port 80 is open; do NOT use tls-alpn-01, it fights IIS for 443), store = Windows
  cert store, installation = **"Create or update IIS bindings"** (this is what auto-rebinds future
  renewals), and accept the scheduled-task creation at the end (needs elevation).

---

## P2 — DNS & registrar (GoDaddy portal; no VPS access needed)

> Enter the **Value** field WITHOUT surrounding quotes; **Name** is the host label only.

### P2.1 CAA — pin issuance to Let's Encrypt
**First** force a successful `wacs.exe --renew --force` so you KNOW renewal works before
restricting CAs. Then add:
```
Type=CAA  Name=@  Flags=0  Tag=issue      Value=letsencrypt.org
Type=CAA  Name=@  Flags=0  Tag=issuewild  Value=;
Type=CAA  Name=@  Flags=0  Tag=iodef      Value=mailto:klazerson@gmail.com
```
Verify: `nslookup -type=CAA gunfight.us`. Then re-run `wacs.exe --renew --force` to prove CAA
didn't break your own renewal.

### P2.2 SPF / DMARC / null-MX — stop domain spoofing (you send no mail)
```
TXT  Name=@        Value=v=spf1 -all
TXT  Name=_dmarc   Value=v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s; rua=mailto:klazerson@gmail.com; pct=100
MX   Name=@  Priority=0  Points to: .      (omit if the panel rejects a bare "."; SPF/DMARC still cover you)
```
Only add the null-MX if no other MX exists (RFC 7505). If you ever add a real sender, relax `-all`.

### P2.3 DNSSEC + registrar lock + account 2FA
- **DNSSEC:** GoDaddy → Domain → DNSSEC → Add DNSSEC (auto-publishes DS to `.us`). Verify with
  dnsviz.net/d/gunfight.us. **Caveat:** if you ever change nameservers, remove DNSSEC/DS first or
  the zone goes dark.
- **Registrar lock:** confirm `client transfer prohibited` is set:
  `(Invoke-RestMethod "https://rdap.org/domain/gunfight.us").status` — or GoDaddy → Domain Settings
  → Domain lock = ON.
- **2FA** (authenticator app + backup codes) on the **GoDaddy account AND `klazerson@gmail.com`** —
  the registrar/email account is a single point of total domain takeover.

---

## P3 — Optional / defense-in-depth
- **Contabo Cloud Firewall** — replicate the 80/443/28960-open + 3389/5986-scoped policy at the
  hypervisor (blocks packets before they reach Windows). Apply via the Contabo panel, not PowerShell.
- **RDP behind a VPN/Tailscale/Cloudflare Tunnel** — removes the public 3389 allow entirely and
  fixes dynamic-IP churn. The clean long-term answer to P0.2.
- **Cloudflare in front of the web origin** — free edge TLS/WAF/HSTS/DDoS and hides the *web* IP
  (note the *game* IP is public by necessity). Trade-off: NS migration off GoDaddy; disable GoDaddy
  DNSSEC before the NS cutover.
- **`www` → CNAME** (cosmetic; defer until a Cloudflare migration), **weak-cipher pruning**
  (bundle into the P1.5 reboot via IIS Crypto), **external uptime + cert-expiry monitoring**,
  **regular Windows Update cadence**, and a **scheduled Contabo snapshot cadence**.

---

## RCON web tool (already hardened in-repo, 2026-06-29)
`tools/rcon/server.js` now: drops the `Access-Control-Allow-Origin: *` wildcard, rejects any
non-loopback `Host`/`Origin` (anti-DNS-rebinding), caps request-body size, pins `/api/savecfg` to
the real `dedicated.cfg` (ignores caller-supplied `body.path`), and sanitizes dvar names/values.
The panel input no longer hardcodes the RCON password. It still binds `127.0.0.1:3000` only.
**Operational rule:** never expose port 3000, and avoid browsing the web from the VPS interactive
session (the only way to reach `127.0.0.1:3000` is from the box itself).
