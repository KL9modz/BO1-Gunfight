# carry.ps1 - bundle every BOX-LOCAL artifact for a migration to a new server
# ------------------------------------------------------------------------------
# `git clone` + deploy.ps1 rebuilds the mod and the website. This script collects everything they
# do NOT rebuild - the state that exists only on this box. It is the executable form of
# docs/MIGRATION.md Phase 1, and its authority is .gitignore: every entry there is by definition
# something a fresh clone will not have.
#
#   .\tools\carry.ps1 -Check      # MIGRATION.md Phase 0: what exists, what is missing. Copies NOTHING.
#   .\tools\carry.ps1             # build the bundle
#   .\tools\carry.ps1 -Zip        # ...and zip it
#
# !! THE OUTPUT CONTAINS LIVE SECRETS AND PLAYER PII !!
#   dedicated.cfg          rcon_password + g_password
#   start_mp_server.bat    the Plutonium server key
#   secrets.local.json     the panel's rcon password store
#   notify/config.json     the ntfy topic (functions as a password)
#   .geocache.json         player IP -> location (PII, opt-in only)
#   players_*.log          player IPs + GUIDs (PII)
# Transfer over scp/SFTP only. Never a web root, never email, never git. Delete it from BOTH boxes
# once the migration is verified. The default output dir is deliberately outside the repo AND
# outside C:\inetpub - do not move it into either.
#
# DELIBERATELY NOT COLLECTED (copying these is WRONG, not merely unnecessary):
#   security_state.json    the security watcher's learned baseline. Copying carries the OLD box's
#                          trust baseline and produces false alarms forever. Deleting it is
#                          correct - the new box re-runs trust-on-first-use. (MIGRATION.md 1.6)
#   watchdog_state.json    transient alert state, regenerates
#   watchdog_maintenance.json  self-expiring marker
#   .connstate.json        conn_logger's bookmark, regenerates
#   .dvarcache.json        learned dead-dvar cache, regenerates on the next connect sweep
#   console_mp.log         ~92% engine dvar-dump flood, worthless off-box
#   mod.ff                 comes from origin/release via deploy.ps1, never carried by hand
#
# Windows PowerShell 5.1 compatible. ASCII-only source (the project convention - non-ASCII here
# gets mangled by re-encoding, which is how the first draft of this file corrupted itself).
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string] $OutRoot = (Join-Path $env:USERPROFILE 'gf-carry'),
    [switch] $Check,                # report only, copy nothing
    [switch] $Zip,
    [switch] $IncludeGeoCache,      # PII; regenerates on its own. Opt in only for the warm cache.
    # The hitch baseline is ~6MB extracted from a 221MB log, and it is a DERIVED DIAGNOSTIC, not
    # state. Worth every byte for a migration (it is the acceptance test for the new box) and pure
    # noise for the daily backup push, where it would be 93% of every commit forever.
    [switch] $SkipHitchBaseline,
    # NOT common.ps1's Resolve-T5Root/Resolve-ModRoot. Those derive the tree from the SCRIPT'S OWN
    # location - correct for a script running inside the deployed mods folder, WRONG here: carry.ps1
    # is normally run from the repo clone (C:\gfdeploy\BO1-Gunfight), where they resolve to "C:\" and
    # the repo root and every collection silently misses. Same trap class as
    # docs/notes/vps-deploy-repo-path-and-ssh-invocation.md - the repo is the SOURCE, the storage
    # tree is the TARGET, and they are not the same place. Anchor on the live tree, overridable.
    [string] $T5Root   = (Join-Path $env:LOCALAPPDATA 'Plutonium\storage\t5'),
    [string] $ModRoot  = '',
    [string] $GameRoot = 'C:\gameserver\T5',
    [string] $WebRoot  = 'C:\inetpub\wwwroot',
    [string] $SshRoot  = 'C:\ProgramData\ssh'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($ModRoot)) { $ModRoot = Join-Path $T5Root 'mods\mp_gunfight' }

$t5      = $T5Root
$modRoot = $ModRoot
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest    = Join-Path $OutRoot "carry-$stamp"

# Fail loudly rather than "collecting" an empty bundle from a wrong root - a migration script that
# reports success while copying nothing is the worst possible failure mode here.
if (-not (Test-Path $t5))      { throw "storage t5 root not found: $t5  (pass -T5Root)" }
if (-not (Test-Path $modRoot)) { throw "mod root not found: $modRoot  (pass -ModRoot)" }

# category: SECRET | PII | DATA | CONFIG | REF
# req $true = a failed migration if absent. req $false = optional or regenerable.
$items = @(
  @{ n='dedicated.cfg'; src=(Join-Path $t5 'dedicated.cfg'); sub='server'; cat='SECRET'; req=$true
     note='THE single largest carry risk - every tuned deviation lives here and none are in git. Diff against server/dedicated.cfg.example before trusting it. ROTATE rcon_password (max 23 chars) rather than reusing. sv_wwwBaseURL LATCHES at startup: it must be in the cfg before first launch or FastDL fails with "Invalid download response".' }
  @{ n='start_mp_server.bat'; src=(Join-Path $GameRoot 'start_mp_server.bat'); sub='server'; cat='SECRET'; req=$true
     note='Carries the Plutonium server key AND the sv_maxclients latch (launch-time only). The key LABEL is set at platform.plutonium.pw, NOT in this file, and the label IS the in-game browser name - reuse the exact label or the server renames itself for every player.' }
  @{ n='secrets.local.json'; src=(Join-Path $modRoot 'tools\rcon\secrets.local.json'); sub='panel'; cat='SECRET'; req=$false
     note='Panel password store. setup_rcon_vps.ps1 REGENERATES this from the new dedicated.cfg - carried only as reference. Joined to servers.local.json BY PROFILE NAME: rename a profile in one file and the panel sees the server but cannot authenticate.' }
  @{ n='servers.local.json'; src=(Join-Path $modRoot 'tools\rcon\servers.local.json'); sub='panel'; cat='CONFIG'; req=$false
     note='Panel profile list (names + real hosts/ports). setup_rcon_vps.ps1 recreates it.' }
  @{ n='prefs.local.json'; src=(Join-Path $modRoot 'tools\rcon\prefs.local.json'); sub='panel'; cat='CONFIG'; req=$false
     note='FAVORITES pinboard. Regenerable only by re-pinning every row by hand - carry it. deploy.ps1 /XF-excludes it so /MIR cannot delete it.' }
  @{ n='.geocache.json'; src=(Join-Path $modRoot 'tools\rcon\.geocache.json'); sub='panel'; cat='PII'; req=$false; optIn=$true
     note='Player IP -> location cache. PII. Regenerates on its own, but re-warming costs ip-api calls against the free 45/min tier. Included only with -IncludeGeoCache.' }
  @{ n='config.json'; src=(Join-Path $modRoot 'tools\notify\config.json'); sub='notify'; cat='SECRET'; req=$true
     note='ntfy topic = a password. WITHOUT this file register_services.ps1 SILENTLY SKIPS GF-JoinNotify and GF-SecurityWatch - no alerts, no error message.' }
  @{ n='ignore.local.json'; src=(Join-Path $modRoot 'tools\ignore.local.json'); sub='tools'; cat='PII'; req=$false
     note='Muted player GUIDs (activity surfaces only). Re-read on change, no restart needed.' }
  @{ n='ops.local.json'; src=(Join-Path $modRoot 'tools\ops.local.json'); sub='tools'; cat='SECRET'; req=$false
     note='Ops crib sheet: home egress IP + provider VNC console. Create it on the new box from tools/ops.local.json.example with the NEW provider console details. Nothing at runtime reads it - it is a human crib sheet.' }
  @{ n='security.local.json'; src=(Join-Path $modRoot 'tools\security.local.json'); sub='tools'; cat='CONFIG'; req=$false
     note='Trusted ssh key fingerprints/users for the security watcher. Review before reusing - it pins what counts as "known".' }
  @{ n='web.config'; src=(Join-Path $WebRoot 'web.config'); sub='iis'; cat='CONFIG'; req=$true
     note='Box-owned, deliberately excluded from deploy.ps1 -Web /MIR. Carries the HTTPS redirect, HSTS and GET/HEAD-only rules. CHECK the CSP allows script-src/connect-src or status.html cannot load its scripts.' }
  @{ n='bots.txt'; src=(Join-Path $t5 'bots.txt'); sub='server'; cat='CONFIG'; req=$false
     note='Bot display names + the orange ^<bot^7 clantag, one "name,clantag" per line. Native Plutonium, box-local, ABOVE the mod folder so no deploy ever ships it - which is exactly why it must be carried. Read at PROCESS START: a change needs a bootstrapper restart, not a map_restart. Without it the new box shows Plutonium internal random bot names.' }
  @{ n='gamestats.local.json'; src=(Join-Path $t5 'logs\gamestats.local.json'); sub='data'; cat='DATA'; req=$false
     note='Every accumulated GF_STAT/GF_MATCH bucket - the Combat leaderboard IS this file, and nothing else holds it (games_mp.log rotates and is not carried). It also stores the tail byte-offset + log identity, so restoring it prevents the aggregator re-reading and double-counting a log it already ingested. Losing it silently resets all combat history to zero.' }
  @{ n='players.local.json'; src=(Join-Path $modRoot 'tools\players.local.json'); sub='tools'; cat='PII'; req=$false
     note='Player GUID -> Discord user id links, used by GF-JoinNotify to name a known player in the join card. Keyed by GUID, hence PII and hence gitignored. Rebuildable only by asking every player for their Discord id again.' }
  @{ n='discord_status.local.json'; src=(Join-Path $modRoot 'tools\notify\discord_status.local.json'); sub='notify'; cat='CONFIG'; req=$false
     note='The message id of the live status card GF-DiscordStatus rewrites in place. Carry it ONLY if the new box posts to the SAME channel: without it the service posts a fresh card and the old one is orphaned (a webhook cannot delete a message it did not create in that run). Harmless to omit - you just re-pin the new card.' }
  @{ n='administrators_authorized_keys'; src=(Join-Path $SshRoot 'administrators_authorized_keys'); sub='ssh'; cat='CONFIG'; req=$true
     note='For ADMIN accounts Windows OpenSSH ignores ~/.ssh/authorized_keys and reads ONLY this file. Restore its ACLs on the new box (Administrators + SYSTEM only) or sshd refuses it.' }
  @{ n='sshd_config'; src=(Join-Path $SshRoot 'sshd_config'); sub='ssh'; cat='REF'; req=$false
     note='REFERENCE ONLY - re-apply the directives on the new box, do not drop this in. Needs BOTH PasswordAuthentication no AND KbdInteractiveAuthentication no, and BOTH must sit in the GLOBAL section: the file ends with "Match Group administrators", so anything appended lands inside that block and does nothing globally.' }
)

function Report($state, $cat, $name, $extra) { "  {0,-9} {1,-7} {2,-32} {3}" -f $state, $cat, $name, $extra }

Write-Host ""
Write-Host "carry.ps1 - box-local artifact bundle" -ForegroundColor Cyan
Write-Host "  storage t5 : $t5"
Write-Host "  mod root   : $modRoot"
Write-Host "  game root  : $GameRoot"
if (-not $Check) { Write-Host "  output     : $dest" -ForegroundColor Yellow }
Write-Host ""

$missingRequired = @()
$collected = 0
$manifest  = New-Object System.Collections.ArrayList
[void]$manifest.Add("GF migration carry bundle - built $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $env:COMPUTERNAME")
[void]$manifest.Add("Source tree: $t5")
[void]$manifest.Add("")
[void]$manifest.Add("*** CONTAINS LIVE SECRETS AND PLAYER PII - scp only, delete both copies when verified ***")
[void]$manifest.Add("")

foreach ($it in $items) {
    $exists = Test-Path $it.src
    $skip   = ($it.optIn -and -not $IncludeGeoCache)
    if (-not $exists) {
        Report 'MISSING' $it.cat $it.n $(if ($it.req) { '<-- REQUIRED' } else { '(optional)' })
        if ($it.req) { $missingRequired += $it.n }
        [void]$manifest.Add("[MISSING]  $($it.sub)/$($it.n)")
        [void]$manifest.Add("           $($it.note)")
        [void]$manifest.Add("")
        continue
    }
    if ($skip) {
        Report 'skipped' $it.cat $it.n '(-IncludeGeoCache to add)'
        [void]$manifest.Add("[SKIPPED]  $($it.sub)/$($it.n) - opt-in only")
        [void]$manifest.Add("")
        continue
    }
    if ($Check) { Report 'ok' $it.cat $it.n ''; continue }
    $sd = Join-Path $dest $it.sub
    if (-not (Test-Path $sd)) { New-Item -ItemType Directory -Force -Path $sd | Out-Null }
    Copy-Item $it.src (Join-Path $sd $it.n) -Force
    $collected++
    Report 'COPIED' $it.cat $it.n ''
    [void]$manifest.Add("[$($it.cat)]  $($it.sub)/$($it.n)")
    [void]$manifest.Add("           $($it.note)")
    [void]$manifest.Add("")
}

# --- day-files: the one dataset nothing reproduces --------------------------------
$dayFiles = @(Get-ChildItem (Join-Path $t5 'logs\players_*.log') -ErrorAction SilentlyContinue)
if ($dayFiles.Count -eq 0) {
    Report 'MISSING' 'DATA' 'players_*.log' '<-- REQUIRED'
    $missingRequired += 'players_*.log'
} else {
    Report $(if ($Check) { 'ok' } else { 'COPIED' }) 'DATA' 'players_*.log' ("$($dayFiles.Count) files, {0:N2} MB" -f (($dayFiles | Measure-Object Length -Sum).Sum/1MB))
    if (-not $Check) {
        $dd = Join-Path $dest 'data\logs'
        New-Item -ItemType Directory -Force -Path $dd | Out-Null
        $dayFiles | ForEach-Object { Copy-Item $_.FullName $dd -Force }
        $collected += $dayFiles.Count
    }
    [void]$manifest.Add("[DATA]  data/logs/players_*.log  ($($dayFiles.Count) files)")
    [void]$manifest.Add("           IRREPLACEABLE. Both the admin connection history and the PUBLIC 7-day")
    [void]$manifest.Add("           activity feed derive from these. Restore to <storage>\t5\logs\ on the new")
    [void]$manifest.Add("           box BEFORE starting GF-StatusService. Contains player IPs + GUIDs (PII).")
    [void]$manifest.Add("")
}

# --- GF_HITCH baseline: extract, never copy the whole log -------------------------
$gml = Join-Path $modRoot 'logs\games_mp.log'
if ($SkipHitchBaseline) {
    Report 'skipped' 'DATA' 'GF_HITCH baseline' '(-SkipHitchBaseline)'
} elseif (Test-Path $gml) {
    $sz = (Get-Item $gml).Length/1MB
    Report $(if ($Check) { 'ok' } else { 'EXTRACT' }) 'DATA' 'GF_HITCH baseline' ("from games_mp.log, {0:N0} MB" -f $sz)
    if (-not $Check) {
        $dd = Join-Path $dest 'data'
        if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Force -Path $dd | Out-Null }
        $out = Join-Path $dd 'GF_HITCH-baseline.txt'
        $buf = New-Object System.Collections.ArrayList
        Get-Content $gml -ReadCount 5000 | ForEach-Object { foreach ($l in $_) { if ($l -match 'GF_HITCH') { [void]$buf.Add($l) } } }
        $buf | Set-Content $out -Encoding UTF8
        Report '' '' '' ("  -> {0:N0} GF_HITCH lines extracted" -f $buf.Count)
        [void]$manifest.Add("[DATA]  data/GF_HITCH-baseline.txt  ($($buf.Count) lines)")
        [void]$manifest.Add("           The OLD box's performance baseline - the acceptance test for whether the")
        [void]$manifest.Add("           move actually worked. Contabo reference (33 days): 45,490 hitches, 99.5%")
        [void]$manifest.Add("           prematch, 207 mid-gameplay (6.3/day), 78 with humans present (2.4/day),")
        [void]$manifest.Add("           prematch median 650ms at 4 bodies / 900ms at 12 / 2650ms at 0.")
        [void]$manifest.Add("           Compare the NEW box against these, matching gf_fill_n 2 / bot_difficulty fu /")
        [void]$manifest.Add("           sv_fps 20 / scr_gf_timelimit 0.7 and the same map rotation, or it is not a")
        [void]$manifest.Add("           fair test.")
        [void]$manifest.Add("")
    }
}

# --- the two scheduled tasks register_services.ps1 does NOT recreate ---------------
foreach ($tn in 'GF-GameServer', 'GF-ClaudeRC') {
    $t = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
    if (-not $t) { Report 'MISSING' 'REF' "task:$tn" '(not registered here)'; continue }
    Report $(if ($Check) { 'ok' } else { 'EXPORT' }) 'REF' "task:$tn" 'XML'
    if (-not $Check) {
        $td = Join-Path $dest 'tasks'
        if (-not (Test-Path $td)) { New-Item -ItemType Directory -Force -Path $td | Out-Null }
        (Export-ScheduledTask -TaskName $tn) | Set-Content (Join-Path $td "$tn.xml") -Encoding UTF8
    }
}
[void]$manifest.Add("[REF]  tasks/GF-GameServer.xml, tasks/GF-ClaudeRC.xml")
[void]$manifest.Add("           register_services.ps1 recreates the OTHER five tasks but NOT these two.")
[void]$manifest.Add("           Reference only - the paths inside are box-specific. GF-ClaudeRC: STOP it on")
[void]$manifest.Add("           the OLD box before starting it on the new one, or you get")
[void]$manifest.Add("           'ambiguous: multiple remote-control servers match name'.")
[void]$manifest.Add("")

# --- firewall posture: reference for rebuilding the rules --------------------------
if (-not $Check) {
    try {
        $fw = @(Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -ErrorAction Stop | ForEach-Object {
            $pf = $null; try { $pf = $_ | Get-NetFirewallPortFilter -ErrorAction Stop } catch { }
            $af = $null; try { $af = $_ | Get-NetFirewallAddressFilter -ErrorAction Stop } catch { }
            if ($pf) {
                $ports = @($pf.LocalPort) -join ','
                if ($ports -match '(^|,)(22|3389|28960|80|443)(,|$)') {
                    "{0,-45} port={1,-10} remote={2}" -f $_.DisplayName, $ports, (@($af.RemoteAddress) -join ',')
                }
            }
        })
        $rd = Join-Path $dest 'reference'
        if (-not (Test-Path $rd)) { New-Item -ItemType Directory -Force -Path $rd | Out-Null }
        $fw | Set-Content (Join-Path $rd 'firewall-inbound.txt') -Encoding UTF8
        Report 'EXPORT' 'REF' 'firewall rules' "$($fw.Count) matching inbound rules"
    } catch { Write-Warning "firewall export failed: $($_.Exception.Message)" }
    [void]$manifest.Add("[REF]  reference/firewall-inbound.txt")
    [void]$manifest.Add("           Recreate on the new box: RDP pinned to the home IP, SSH, UDP 28960, 80/443,")
    [void]$manifest.Add("           then Set-NetFirewallProfile -DefaultInboundAction Block.")
    [void]$manifest.Add("           Scope RDP BEFORE exposing the box, or a spammer on world-open 3389 can lock")
    [void]$manifest.Add("           out your own account.")
    [void]$manifest.Add("")
}

# --- Defender exclusions: perf tuning that is INVISIBLE until it is missing ---------
# A fresh box scans the game tree on every map load, so the omission shows up as I/O latency
# and MsMpEng RAM spikes (measured peak 1183MB on the old box) - i.e. as frame hitches, which
# read as "the new host is worse" rather than as a missing setting. Exported as reference, not
# restored automatically: the paths are box-specific and re-adding them is one command.
if (-not $Check) {
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        $lines = @('# Re-add on the new box (Add-, never Set- - Set REPLACES the whole list):', '')
        foreach ($x in @($mp.ExclusionPath))    { $lines += "Add-MpPreference -ExclusionPath '$x'" }
        foreach ($x in @($mp.ExclusionProcess)) { $lines += "Add-MpPreference -ExclusionProcess '$x'" }
        foreach ($x in @($mp.ExclusionExtension)) { $lines += "Add-MpPreference -ExclusionExtension '$x'" }
        if (@($mp.ExclusionPath).Count -eq 0 -and @($mp.ExclusionProcess).Count -eq 0) { $lines += '# (none were set)' }
        $rd = Join-Path $dest 'reference'
        if (-not (Test-Path $rd)) { New-Item -ItemType Directory -Force -Path $rd | Out-Null }
        $lines | Set-Content (Join-Path $rd 'defender-exclusions.txt') -Encoding UTF8
        Report 'EXPORT' 'REF' 'defender exclusions' "$(@($mp.ExclusionPath).Count) path(s), $(@($mp.ExclusionProcess).Count) process(es)"
    } catch { Write-Warning "defender exclusion export failed: $($_.Exception.Message)" }
    [void]$manifest.Add("[REF]  reference/defender-exclusions.txt")
    [void]$manifest.Add("           Paste the Add-MpPreference lines on the new box. Excluding the game tree")
    [void]$manifest.Add("           cuts map-load I/O and the Defender RAM spike - it matters MORE on a 4GB")
    [void]$manifest.Add("           plan, where a scan spike is the difference between fitting and paging.")
    [void]$manifest.Add("")
}

# --- the not-a-file checklist ------------------------------------------------------
[void]$manifest.Add("=== DELIBERATELY NOT INCLUDED (copying these is wrong, not just unnecessary) ===")
[void]$manifest.Add("  security_state.json   carries the OLD box's trust baseline -> false alarms forever.")
[void]$manifest.Add("                        Let the new box re-run trust-on-first-use.")
[void]$manifest.Add("  watchdog_state.json, watchdog_maintenance.json, .connstate.json, .dvarcache.json")
[void]$manifest.Add("                        transient or learned; all regenerate.")
[void]$manifest.Add("  console_mp.log        ~92% engine dvar-dump flood, worthless off-box.")
[void]$manifest.Add("  mod.ff                comes from origin/release via deploy.ps1 - never carry by hand.")
[void]$manifest.Add("")
[void]$manifest.Add("=== NOT FILES - carry these by hand ===")
[void]$manifest.Add("  1. PUSH ALL COMMITS FIRST. deploy.ps1 pulls origin/main and takes mod.ff from")
[void]$manifest.Add("     origin/release. Unpushed work simply will not exist on the new box.")
[void]$manifest.Add("  2. Plutonium server key LABEL (platform.plutonium.pw). The label IS the browser name.")
[void]$manifest.Add("  3. Auto-logon: Sysinternals Autologon (encrypted LSA secret), NEVER the cleartext")
[void]$manifest.Add("     Winlogon DefaultPassword registry method. Without it the game server does not survive")
[void]$manifest.Add("     a reboot - the bootstrapper needs an interactive session. Plus the startup shortcut.")
[void]$manifest.Add("  4. IIS: add the .ff MIME type (application/octet-stream) or FastDL 404s silently.")
[void]$manifest.Add("  5. setup_admin_auth.ps1 recreates the .secured interlock + Basic auth users.")
[void]$manifest.Add("  6. git config core.hooksPath tools/hooks  (per-clone; does not travel with the repo).")
[void]$manifest.Add("  7. TLS: issue AFTER DNS moves (HTTP-01 cannot validate before).")
[void]$manifest.Add("  8. Drop the DNS TTL to 300s BEFORE cutover day - it is the only step with lead time.")
[void]$manifest.Add("  9. Expect the plutonium.exe -update-only wedge on first launch: if it sits flat on CPU")
[void]$manifest.Add("     with no bootstrapper, kill it and the bat's goto-server loop relaunches.")
[void]$manifest.Add(" 10. Windows Server evaluation expires at 180 days and then shuts down HOURLY. Set a")
[void]$manifest.Add("     calendar reminder at ~170 days, or license it before then.")

Write-Host ""
if ($Check) {
    Write-Host "CHECK ONLY - nothing copied." -ForegroundColor Cyan
} else {
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
    $mf = Join-Path $dest 'MANIFEST.txt'
    $manifest | Set-Content $mf -Encoding UTF8
    Write-Host "Collected $collected file(s) -> $dest" -ForegroundColor Green
    Write-Host "Manifest: $mf"
    if ($Zip) {
        $zipPath = Join-Path $OutRoot "gf-carry-$stamp.zip"
        Compress-Archive -Path (Join-Path $dest '*') -DestinationPath $zipPath -Force
        Write-Host "Zipped: $zipPath" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "*** THIS BUNDLE HOLDS LIVE SECRETS AND PLAYER PII ***" -ForegroundColor Red
    Write-Host "    scp/SFTP only. Never a web root, never email, never git." -ForegroundColor Red
    Write-Host "    Delete from BOTH boxes once the migration is verified." -ForegroundColor Red
}

if ($missingRequired.Count) {
    Write-Host ""
    Write-Host "MISSING REQUIRED: $($missingRequired -join ', ')" -ForegroundColor Red
    Write-Host "Resolve before cutover - MIGRATION.md Phase 0 exists to catch exactly this."
    exit 1
}
Write-Host ""
