# security_watch.ps1 - security event watcher for the Gunfight VPS (run ON the box)
# ------------------------------------------------------------------------------
# GF-Watchdog answers "is the server ALIVE". This answers "did something get IN, or change".
# Nothing else on the box watched authentication, persistence or config drift.
#
# Invoked FRESH on a schedule (same reason as watchdog.ps1: a long-lived task's retry budget
# exhausts silently). Each run reads what happened since its last bookmark, alerts, saves state.
#
#   powershell -ExecutionPolicy Bypass -File security_watch.ps1
#   powershell -ExecutionPolicy Bypass -File security_watch.ps1 -WhatIf   # detect + print, never push
#   powershell -ExecutionPolicy Bypass -File security_watch.ps1 -Summary  # what it would watch, no state write
#
# ── EVERY DETECTOR HERE IS SIZED AGAINST MEASURED VOLUME, NOT INTUITION ────────
# Live counts read off this box 2026-07-17 (7d unless noted). Re-measure before adding one:
#
#   671  sshd "Accepted publickey"       -> ~96/DAY. Alerting per successful login is UNUSABLE.
#          ...but all 671 were ONE key fingerprint, one user, 3 IPs. So the detector is
#          "a key we have never seen", not "a login happened". That is ~0 noise and catches
#          the only thing that matters: someone else's key working.
#    64  invalid-user preauth rejects    -> ~9/day of internet background radiation (root, ubnt,
#          admin). sshd is key-only so none can succeed. DIGEST/THRESHOLD ONLY - never per-event.
#   196  firewall "rule added" (30d)     -> far too noisy to tail. So the firewall detector is a
#          POSTURE SNAPSHOT of the rules touching 22/3389 instead: it answers "is RDP still
#          pinned to the home IP", which is the property we actually care about.
#     7  account/group management (30d)  -> low + high-signal. Per-event is fine.
#     4  RDP logons (30d)                -> low + high-signal. Per-event is fine.
#     9  service installs (30d)          -> low volume, BUT the most frequent single source is
#          Microsoft Defender re-registering its own kernel drivers (KslD, ~00:30 nightly, 3 of
#          the 10 events on record). Per-event alerting on that is pure fatigue, so section 7
#          classifies by Authenticode: Microsoft-signed = log only, everything else = push.
#
# ⚠ AUDIT POLICY GAPS (auditpol, read live off this box - a detector for these fires NEVER):
#     "Other Object Access Events"       = No Auditing -> Security 4698 is dead. ✅ CLOSED
#                                          2026-08-06 WITHOUT enabling it: section 7b reads task
#                                          create/delete from the TaskScheduler OPERATIONAL log
#                                          (106/141) instead, which was already enabled, is
#                                          precisely scoped, and avoids the COM+ events that
#                                          share that subcategory. ⚠ Do NOT run the auditpol
#                                          line that used to be here - it buys nothing now and
#                                          adds Security-log volume.
#     "MPSSVC Rule-Level Policy Change"  = No Auditing -> Security 4946-4954 dead. Covered
#                                          instead by the firewall POSTURE check below.
#     "Security System Extension"        = No Auditing -> 4697 dead. System/7045 covers it and
#                                          needs no auditpol.
#   Working today: Logon (Success+Failure), User Account Management, Security Group Management.
#
# ⚠ This DETECTS. It does not remediate - no killing sessions, no firewall edits. A false
# positive must never lock you out of your own box.
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string] $StatePath       = '',   # bookmarks + posture baseline; gitignored, box-local
    [string] $ConfigPath      = '',   # allowlists (tools\security.local.json); optional - TOFU if absent
    [string] $NotifyConfigPath= '',   # topic comes from the shared tools\notify\config.json
    [string] $AuthKeysPath    = 'C:\ProgramData\ssh\administrators_authorized_keys',
    # First run has no bookmark. Look back this far so a fresh install still sees recent history,
    # but not so far that it pages you about last month on install.
    [int]    $FirstRunLookbackHours = 2,
    # Brute force is constant and harmless against a key-only sshd. Only a genuine SPIKE is worth
    # a buzz - measured floor is ~9/day, so this is ~50x the floor.
    # ⚠ PER RUN, not per hour: the count is "since the last bookmark", and at the registered 3-min
    # cadence 20 hits/run is ~400/hr. Named PerHour at first, which was a lie - the window is the
    # gap between runs, so the same number means a different RATE on a different cadence. If you
    # re-schedule this task, re-think this number.
    [int]    $BruteForceSpikePerRun = 20,
    [int]    $ReAlertMinutes  = 60,   # a persisting condition (low disk) re-alerts at most this often
    [int]    $DiskFreeGbMin   = 10,
    [switch] $Summary,                # print what it sees, touch nothing
    [switch] $WhatIf                  # detect + print, never push, never save state
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot  = Split-Path -Parent $scriptRoot

if (-not $StatePath)        { $StatePath        = Join-Path $scriptRoot 'security_state.json' }
if (-not $ConfigPath)       { $ConfigPath       = Join-Path $toolsRoot  'security.local.json' }
if (-not $NotifyConfigPath) { $NotifyConfigPath = Join-Path $toolsRoot  'notify\config.json' }

. (Join-Path $toolsRoot 'ntfy.ps1')   # Send-GfNtfy / Get-GfNtfyConfig

function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) }

# ── state ─────────────────────────────────────────────────────────────────────
# Bookmarks are per-channel RecordIds, NOT timestamps: a timestamp cursor double-reports events
# that share the boundary second and silently drops any written out of order.
function Read-State {
    if (Test-Path $StatePath) {
        try { return (Get-Content $StatePath -Raw | ConvertFrom-Json) }
        catch { Log "state unreadable ($($_.Exception.Message)) - starting fresh" }
    }
    return $null
}
function Write-State($s) {
    if ($WhatIf -or $Summary) { return }
    try { ($s | ConvertTo-Json -Depth 6) | Set-Content -Path $StatePath -Encoding utf8 }
    catch { Log "could not save state: $($_.Exception.Message)" }
}
function State-Get($s, $name, $def) {
    if ($null -ne $s -and ($s.PSObject.Properties.Name -contains $name)) { return $s.$name }
    return $def
}

# ── alerting ──────────────────────────────────────────────────────────────────
$script:notify   = Get-GfNtfyConfig $NotifyConfigPath
$script:srvName  = $(if ($script:notify) { $script:notify.serverName } else { 'Gunfight' })
$script:alerted  = 0

function Alert($title, $message, $priority, $tags) {
    $script:alerted++
    Log "ALERT [$priority] $title :: $($message -replace "`n", ' / ')"
    if ($WhatIf -or $Summary) { Log '  (WhatIf - not sent)'; return }
    if ($null -eq $script:notify) { Log '  (no notify config - not sent)'; return }
    $r = Send-GfAlert -Config $script:notify -Title $title -Message $message -Priority $priority -Tags $tags -Category 'security'
    if ($r.ntfyError)    { Log "  ntfy send FAILED: $($r.ntfyError)" }
    if ($r.discordError) { Log "  discord send FAILED: $($r.discordError)" }
}

# ── event reading ─────────────────────────────────────────────────────────────
# Returns events NEWER than $sinceRecordId, oldest-first. A missing/empty channel yields nothing
# rather than throwing - a detector going quiet must never take the watcher down.
function Get-NewEvents($logName, $sinceRecordId, $ids) {
    $filter = @{ LogName = $logName }
    if ($ids) { $filter['Id'] = $ids }
    if ($null -eq $sinceRecordId -or $sinceRecordId -le 0) {
        $filter['StartTime'] = (Get-Date).AddHours(-$FirstRunLookbackHours)
    }
    $ev = @()
    try { $ev = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) }
    catch { return @() }   # "No events were found" throws
    if ($null -ne $sinceRecordId -and $sinceRecordId -gt 0) {
        $ev = @($ev | Where-Object { $_.RecordId -gt $sinceRecordId })
    }
    return @($ev | Sort-Object RecordId)
}
function Max-RecordId($events, $fallback) {
    if ($events -and $events.Count -gt 0) { return [int64](($events | Measure-Object RecordId -Maximum).Maximum) }
    return $fallback
}
# Newest RecordId in a channel, for seeding a bookmark without replaying history.
function Tip-RecordId($logName) {
    try { return [int64]((Get-WinEvent -LogName $logName -MaxEvents 1 -ErrorAction Stop).RecordId) }
    catch { return 0 }
}
function Xml-Data($ev, $name) {
    try { return ((([xml]$ev.ToXml()).Event.EventData.Data | Where-Object { $_.Name -eq $name }).'#text') }
    catch { return '' }
}

$state = Read-State
$new   = [ordered]@{}

# ── config / allowlists ───────────────────────────────────────────────────────
# TOFU: with no config file the FIRST run adopts whatever keys are in use today as the baseline
# and says so loudly. That is the honest trade - it assumes the box is clean right now, which is
# only sound if you trust it at install time. Pin the fingerprints in security.local.json to
# remove the assumption.
$cfgKeys  = @()
$cfgUsers = @()
if (Test-Path $ConfigPath) {
    try {
        $c = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if ($c.sshKeyFingerprints) { $cfgKeys  = @($c.sshKeyFingerprints | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) }
        if ($c.sshUsers)           { $cfgUsers = @($c.sshUsers           | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) }
    } catch { Log "security.local.json unreadable ($($_.Exception.Message)) - falling back to learned baseline" }
}
$knownKeys  = @(@($cfgKeys)  + @(State-Get $state 'knownSshKeys'  @()) | Where-Object { $_ } | Select-Object -Unique)
$knownUsers = @(@($cfgUsers) + @(State-Get $state 'knownSshUsers' @()) | Where-Object { $_ } | Select-Object -Unique)

# ══ 1. SSH: a login with an UNKNOWN KEY or by an UNKNOWN USER ═════════════════
# The crown jewel. 671 accepted logins in 7d all carried ONE fingerprint, so anything else is a
# key that is not yours: a second key added to administrators_authorized_keys, or a stolen one.
$sshBookmark = [int64](State-Get $state 'sshRecordId' 0)
$sshEvents   = Get-NewEvents 'OpenSSH/Operational' $sshBookmark $null
$accepted    = @()
foreach ($e in $sshEvents) {
    $line = ($e.Message -split "`n")[0]
    if ($line -match 'Accepted (\S+) for (\S+) from (\S+) port \d+ \S+: (\S+) SHA256:(\S+)') {
        $accepted += [pscustomobject]@{
            time = $e.TimeCreated; method = $Matches[1]; user = $Matches[2]
            ip   = $Matches[3];    keyType = $Matches[4]; fp = "SHA256:$($Matches[5])"
        }
    }
}

if ($knownKeys.Count -eq 0 -and $accepted.Count -gt 0) {
    # First run, nothing pinned: adopt, don't alert (or every historical login pages you).
    $knownKeys  = @($accepted.fp   | Select-Object -Unique)
    $knownUsers = @($accepted.user | Select-Object -Unique)
    Log "TOFU baseline adopted - ssh keys: $($knownKeys -join ', ') / users: $($knownUsers -join ', ')"
    Log '     ^ pin these in security.local.json to stop trusting whatever ran first.'
} else {
    # ⚠ COALESCE PER IDENTITY, AND THROTTLE ACROSS RUNS. This box takes ~96 successful logins a
    # DAY, so "alert per offending event" would mean 96 max-priority buzzes the moment a key
    # stops being recognised - and the likeliest cause of that is benign: you rotated your key
    # and forgot security.local.json. A real intruder is described just as well by one alert
    # naming the key and a count, so per-event gains nothing and costs everything.
    $offenders = @($accepted | Where-Object {
        ($knownKeys.Count  -gt 0 -and $knownKeys  -notcontains $_.fp) -or
        ($knownUsers.Count -gt 0 -and $knownUsers -notcontains $_.user)
    })
    $prevSeen = @{}
    $ps = State-Get $state 'unknownKeyAlertAt' $null
    if ($null -ne $ps) { foreach ($p in $ps.PSObject.Properties) { $prevSeen[$p.Name] = $p.Value } }
    $seen = @{}
    foreach ($g in @($offenders | Group-Object { "$($_.fp)|$($_.user)" })) {
        $a  = $g.Group[0]
        $k  = $g.Name
        $due = $true
        if ($prevSeen.ContainsKey($k)) {
            try { $due = ((Get-Date) - [datetime]$prevSeen[$k]).TotalMinutes -ge $ReAlertMinutes } catch { $due = $true }
        }
        $seen[$k] = $(if ($due) { (Get-Date).ToString('o') } else { $prevSeen[$k] })
        if (-not $due) { Log "unknown ssh key $($a.fp) still present - alert throttled"; continue }
        $why = @()
        if ($knownKeys.Count  -gt 0 -and $knownKeys  -notcontains $a.fp)   { $why += 'unknown key' }
        if ($knownUsers.Count -gt 0 -and $knownUsers -notcontains $a.user) { $why += 'unknown user' }
        $ips = (@($g.Group.ip | Select-Object -Unique) -join ', ')
        Alert "$($script:srvName) - SSH login: $($why -join ' + ')" `
              ("$($a.user) from $ips`n$($g.Count) login(s) since the last check, first at $($a.time.ToString('HH:mm:ss'))`n$($a.keyType) $($a.fp)`nThis key is not in the known set. Either you rotated your key and did not update security.local.json, or someone else's key works on this box.") `
              'max' @('rotating_light', 'key')
    }
    $new['unknownKeyAlertAt'] = [pscustomobject]$seen
}
$new['sshRecordId']   = Max-RecordId $sshEvents $sshBookmark
$new['knownSshKeys']  = @($knownKeys)
$new['knownSshUsers'] = @($knownUsers)

# ══ 2. SSH brute force: DIGEST, never per-event ═══════════════════════════════
# ~9/day of invalid-user probes is the internet, not an incident. Only a spike is news.
#
# ⚠ SKIPPED ON THE FIRST RUN. The first run has no bookmark so it reads $FirstRunLookbackHours
# (2h) instead of the ~3min a steady run covers, so its count cannot be judged by a threshold
# meant for a 3-min window. It fired on install for that reason (2026-07-17, "108 invalid-user
# attempts").
#
# ⚠ That install-time alert was a REAL burst, not noise - do not read this skip as "bursts don't
# happen here". 43.160.219.175 ran 95 attempts in ~2 MINUTES (root x19, then ubuntu/deploy/admin/
# pi/git/hadoop/postgres/kali - a stock scanner dictionary), against a 7d baseline of ~23. All 95
# died at preauth because sshd is key-only. The steady-state path would have caught it correctly
# (95 in one 3-min run >> 20). The ONLY thing this skip gives up is a burst that lands in the 2h
# backfill of a FRESH INSTALL - a one-time blind spot, not an ongoing one.
$invalid = @($sshEvents | Where-Object { ($_.Message -split "`n")[0] -match 'Invalid user (\S+) from (\S+)' })
if ($sshBookmark -le 0) {
    Log "brute-force digest skipped on the first run ($($invalid.Count) invalid-user hits over the ${FirstRunLookbackHours}h backfill - window not comparable)"
} elseif ($invalid.Count -ge $BruteForceSpikePerRun) {
    $ips = @($invalid | ForEach-Object { if ((($_.Message -split "`n")[0]) -match 'from (\S+) port') { $Matches[1] } }) |
           Group-Object | Sort-Object Count -Descending | Select-Object -First 3
    $top = ($ips | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
    Alert "$($script:srvName) - SSH probe spike" `
          ("$($invalid.Count) invalid-user attempts since the last check.`nTop: $top`nsshd is key-only so these cannot succeed - informational.") `
          'low' @('warning')
}

# ══ 3. administrators_authorized_keys changed ════════════════════════════════
# This file IS the SSH gate for admin accounts (Windows OpenSSH ignores ~/.ssh/authorized_keys
# for admins). A write to it is someone granting themselves durable access. No legitimate
# process touches it.
$keysHash = ''
if (Test-Path $AuthKeysPath) {
    try { $keysHash = (Get-FileHash -Path $AuthKeysPath -Algorithm SHA256).Hash } catch { $keysHash = 'UNREADABLE' }
} else { $keysHash = 'ABSENT' }
$prevHash = [string](State-Get $state 'authKeysHash' '')
if ($prevHash -and $prevHash -ne $keysHash) {
    $n = 0
    if (Test-Path $AuthKeysPath) { $n = @(Get-Content $AuthKeysPath | Where-Object { $_ -match '\S' }).Count }
    Alert "$($script:srvName) - SSH authorized_keys CHANGED" `
          ("$AuthKeysPath`nwas $prevHash`nnow $keysHash`n$n key line(s) now present. If this was not you, someone has added their own key.") `
          'max' @('rotating_light', 'key')
}
$new['authKeysHash'] = $keysHash

# ══ 4. RDP logon (4624 type 10) ══════════════════════════════════════════════
# 4 in 30d, and the firewall pins RDP to the home IP - so any hit is worth a look and none of
# them are noise.
$secBookmark = [int64](State-Get $state 'secRecordId' 0)
$secEvents   = Get-NewEvents 'Security' $secBookmark @(4624, 4625, 4720, 4722, 4724, 4726, 4728, 4732, 4756)
foreach ($e in @($secEvents | Where-Object { $_.Id -eq 4624 })) {
    if ((Xml-Data $e 'LogonType') -ne '10') { continue }   # 3/5/7/8 are services+network: pure noise
    $u = Xml-Data $e 'TargetUserName'; $ip = Xml-Data $e 'IpAddress'
    Alert "$($script:srvName) - RDP login" `
          ("$u from $ip at $($e.TimeCreated.ToString('HH:mm:ss'))`nRDP is firewalled to the home IP - if this is not you, check the firewall posture.") `
          'high' @('rotating_light', 'desktop_computer')
}

# ══ 5. account + group management ════════════════════════════════════════════
# ~7 in 30d. Creating an account or adding one to Administrators is the textbook way to keep
# access after a key is rotated.
$acctIds = @{
    4720 = 'user account CREATED'; 4722 = 'user account ENABLED'; 4724 = 'password reset attempt'
    4726 = 'user account DELETED'; 4728 = 'member added to a global group'
    4732 = 'member added to a LOCAL group (Administrators?)'; 4756 = 'member added to a universal group'
}
foreach ($e in @($secEvents | Where-Object { $acctIds.ContainsKey([int]$_.Id) })) {
    $what = $acctIds[[int]$e.Id]
    $who  = Xml-Data $e 'SubjectUserName'
    $tgt  = Xml-Data $e 'TargetUserName'
    $grp  = Xml-Data $e 'TargetSid'
    Alert "$($script:srvName) - $what" `
          ("event $($e.Id) at $($e.TimeCreated.ToString('HH:mm:ss'))`nby: $who`ntarget: $tgt $grp`nIf you did not just do this, treat the box as compromised.") `
          'max' @('rotating_light', 'bust_in_silhouette')
}

# ══ 6. failed logon spike (4625) ═════════════════════════════════════════════
# 2 in 30d - sshd rejects never reach here. So any real volume is RDP/SMB and is worth knowing.
$failed = @($secEvents | Where-Object { $_.Id -eq 4625 })
if ($failed.Count -ge 5) {
    Alert "$($script:srvName) - failed logon burst" `
          ("$($failed.Count) failed Windows logons since the last check (normal is ~2 per MONTH).") `
          'high' @('warning')
}
$new['secRecordId'] = Max-RecordId $secEvents $secBookmark

# ══ 7. service installed (System 7045) - needs no auditpol ═══════════════════
# This used to push for EVERY 7045 regardless of what installed. Measured cost of that: KslD - a
# Microsoft Defender kernel driver - is the single most frequent 7045 on this box (3 of the 10
# events on record: 06-29, 07-08, 08-06) because Defender RE-REGISTERS its demand-start drivers
# during each platform update, around 00:30 nightly. A watcher that buzzes for routine antivirus
# churn trains you to swipe it away, and the one alert that matters gets swiped with it.
#
# ⚠ Classify by CODE SIGNATURE, never by NAME. A name allowlist ("KslD is fine") is defeated by
# dropping a hostile KslD.sys at another path - Authenticode is a property of the BYTES, not the
# filename. Three tiers:
#   Microsoft-signed + Valid       -> LOG ONLY. Routine platform churn. Still durably recorded in
#                                     logs\services\GF-SecurityWatch.log via run_service.ps1.
#   validly signed by anyone else  -> 'default' push. Third-party drivers are legitimate in
#                                     general, but nothing on THIS box should be installing one.
#   binary NOT on disk             -> 'default' push. Install-then-delete IS an anti-forensic
#                                     move, BUT it is also what Defender does every update: it
#                                     registers a randomly-named temp driver (MpKsld1e30cb9,
#                                     2026-06-29) and deletes it minutes later. 3 of the 10
#                                     historical 7045s on this box are vanished binaries, so
#                                     'high' here would just rebuild the fatigue this fix removes.
#                                     Report it, don't scream it.
#   EXISTS but unsigned / invalid  -> 'high' push. THIS is the tier worth waking up for: positive
#                                     evidence of an unverifiable kernel driver sitting on disk.
#                                     Defender never produces this case; an attacker does.
#
# ⚠ Tiers were calibrated by replaying all 10 real 7045s on this box through the classifier (see
# the file header's rule: size detectors against MEASURED volume, not intuition). Result: 6 go
# silent (KslD x3, Defender Core, WdAiNisDrv, OpenSSH), 1 informs (Mozilla), 3 inform-as-vanished
# (MpKsld temp + Windows Admin Center x2). Zero would have paged. Re-run that replay before
# changing a tier.

# ImagePath arrives in several shapes: relative to %SystemRoot% ("system32\drivers\wd\KslD.sys"),
# NT-native ("\??\C:\..." or "\SystemRoot\..."), quoted, and/or with trailing switches. Normalize
# before touching disk, or every signature check silently fails open.
function Resolve-ServiceImagePath($raw) {
    $p = [string]$raw
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    $p = $p.Trim()
    if ($p.StartsWith('"')) { $p = ($p -split '"')[1] }        # quoted path wins over trailing args
    else { $p = ($p -split '\s+-|\s+/')[0].Trim() }            # strip switch-style args
    $p = $p -replace '^\\\?\?\\', ''                           # NT-native prefix
    $p = $p -replace '^\\SystemRoot\\', ($env:SystemRoot + '\')
    if ($p -notmatch '^[A-Za-z]:\\') { $p = Join-Path $env:SystemRoot $p }   # relative to %SystemRoot%
    return $p
}

# Never throws: a signature check that errors must degrade to "untrusted" (which alerts), never
# take the watcher down or silently pass.
function Get-BinaryTrust($path) {
    $r = [pscustomobject]@{ exists = $false; status = 'FileMissing'; signer = ''; isMicrosoft = $false }
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return $r }
    $r.exists = $true
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        $r.status = [string]$sig.Status
        if ($sig.SignerCertificate) {
            $r.signer = [string]$sig.SignerCertificate.Subject
            # Match the ORGANISATION, not the CN: Microsoft signs variously as CN=Microsoft Windows,
            # CN=Microsoft Corporation, CN=Microsoft Windows Publisher - all carry O=Microsoft Corporation.
            $r.isMicrosoft = ($r.status -eq 'Valid' -and $r.signer -match 'O=Microsoft Corporation')
        }
    } catch { $r.status = "SigCheckFailed: $($_.Exception.Message)" }
    return $r
}

$sysBookmark = [int64](State-Get $state 'sysRecordId' 0)
$sysEvents   = Get-NewEvents 'System' $sysBookmark @(7045)
foreach ($e in $sysEvents) {
    $svc  = Xml-Data $e 'ServiceName'
    $img  = Xml-Data $e 'ImagePath'
    $type = Xml-Data $e 'ServiceType'
    $trust = Get-BinaryTrust (Resolve-ServiceImagePath $img)
    # Full DNs are unreadable on a phone - show the CN only.
    $who = $trust.signer
    if ($who -match 'CN=([^,]+)') { $who = $Matches[1] }

    if ($trust.isMicrosoft) {
        Log "7045 $svc ($img) - Microsoft-signed [$who] - routine, no push"
        continue
    }

    $pri = 'default'; $tags = @('gear'); $verdict = "signed by: $who [$($trust.status)]"
    if (-not $trust.exists) {
        # Informational, NOT high - see the tier rationale above (Defender's own temp drivers).
        $tags = @('grey_question')
        $verdict = 'binary not on disk (transient installer, or removed after install)'
    } elseif ($trust.status -ne 'Valid') {
        $pri = 'high'; $tags = @('rotating_light')
        $verdict = "UNSIGNED / UNVERIFIABLE [$($trust.status)] - treat as compromise until explained"
    }
    Alert "$($script:srvName) - service installed" `
          ("$svc at $($e.TimeCreated.ToString('HH:mm:ss'))`n$img`n$type`n$verdict") `
          $pri $tags
}
$new['sysRecordId'] = Max-RecordId $sysEvents $sysBookmark

# ══ 7b. scheduled task REGISTERED / DELETED ══════════════════════════════════
# Scheduled tasks are THE classic persistence trick and this box runs 8 of them, so "a task
# appeared" is a detector worth having. The file header long carried a TODO to enable the
# Security-log route (auditpol "Other Object Access Events" -> 4698). ⚠ DON'T - that route was
# measured and rejected 2026-08-06 in favour of this one:
#   * The TaskScheduler OPERATIONAL log already carries the same facts (106 registered, 141
#     deleted, 140 updated) and has been enabled since 2026-08-02 by register_services.ps1, so
#     this costs no auditpol change, no extra Security-log volume, and none of the COM+ noise
#     that shares the "Other Object Access Events" subcategory.
#   * It needs no privilege change on a box whose whole point is being hard to get into.
#
# MEASURED over 2.9 days on this box before writing a line of it:
#   id 140 (task UPDATED)    120 events = ~41/DAY -> UNUSABLE. Excluded outright. Windows
#                            rewrites its own maintenance tasks constantly; same lesson as the
#                            671 "Accepted publickey" lines in the header.
#   id 106 (REGISTERED)        4 events   |  ALL EIGHT were Windows churning two built-in tasks:
#   id 141 (DELETED)           4 events   |  UpdateOrchestrator\AC Power Download and
#                                         |  Windows Defender\Windows Defender Scheduled Scan.
#
# So the filter is the built-in NAMESPACE, not a name list: anything under \Microsoft\Windows\ is
# Windows maintaining itself -> log only. Measured events OUTSIDE that namespace: ZERO. The only
# expected source is your own register_services.ps1 run, which you initiate and will recognise.
# That makes a registration outside \Microsoft\Windows\ a near-perfect signal, so it pages.
#
# ⚠ Residual, stated honestly: an attacker with admin could create their task INSIDE
# \Microsoft\Windows\ to land in the log-only tier. Closing that would mean alerting on 41
# events/day, which trains you to ignore all of them - a strictly worse defence. Admin is already
# game over for this detector either way; it exists to catch the careless case, which is most.
# ⚠ The operational log is CIRCULAR at 10MB (~3 days at current churn). If the watcher is down
# longer than that, rolled-off events are simply missed - the RecordId bookmark stays correct,
# it just never sees them. Acceptable for a 3-minute cadence.
$taskBookmark = [int64](State-Get $state 'taskRecordId' 0)
$taskEvents   = Get-NewEvents 'Microsoft-Windows-TaskScheduler/Operational' $taskBookmark @(106, 141)
foreach ($e in $taskEvents) {
    $tn = Xml-Data $e 'TaskName'
    $by = Xml-Data $e 'UserContext'
    if ([string]::IsNullOrWhiteSpace($by)) { $by = Xml-Data $e 'UserName' }
    $what = if ($e.Id -eq 106) { 'registered' } else { 'deleted' }

    # Built-in namespace = Windows maintaining itself. 100% of measured volume.
    if ($tn -like '\Microsoft\Windows\*') {
        Log "task $what (builtin, no push): $tn by $by"
        continue
    }
    if ($e.Id -eq 106) {
        Alert "$($script:srvName) - scheduled task registered" `
              ("$tn`nby: $by at $($e.TimeCreated.ToString('HH:mm:ss'))`nScheduled tasks are a persistence mechanism. If this was not your deploy (register_services.ps1), investigate now.") `
              'high' @('rotating_light', 'calendar')
    } else {
        Alert "$($script:srvName) - scheduled task deleted" `
              ("$tn`nby: $by at $($e.TimeCreated.ToString('HH:mm:ss'))") `
              'default' @('calendar')
    }
}
$new['taskRecordId'] = Max-RecordId $taskEvents $taskBookmark

# ══ 8. firewall POSTURE (not the event stream) ═══════════════════════════════
# 196 "rule added" events in 30d makes tailing useless. Snapshot the property we care about
# instead: every ENABLED inbound ALLOW rule touching 22 or 3389, and its remote-address scope.
# This is what answers "is RDP still pinned to the home IP" - and it catches a rule widened in
# place, which an "added" event never would.
function Get-FirewallPosture {
    $out = New-Object System.Collections.ArrayList
    try {
        $rules = Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -ErrorAction Stop
        foreach ($r in $rules) {
            $pf = $null
            try { $pf = $r | Get-NetFirewallPortFilter -ErrorAction Stop } catch { continue }
            $ports = @($pf.LocalPort) -join ','
            if ($ports -notmatch '(^|,)(22|3389)(,|$)' -and $ports -ne 'Any') { continue }
            if ($ports -eq 'Any') { continue }   # 'Any' rules are legion and not about 22/3389
            $addr = 'Any'
            try { $addr = (@(($r | Get-NetFirewallAddressFilter -ErrorAction Stop).RemoteAddress) -join ',') } catch { }
            [void]$out.Add("$($r.DisplayName)|$ports|$addr")
        }
    } catch { return $null }   # not a Windows with the module / no rights: skip, don't crash
    return @($out | Sort-Object)
}
$posture = Get-FirewallPosture
if ($null -ne $posture) {
    $postureStr = ($posture -join "`n")
    $prevPost   = [string](State-Get $state 'firewallPosture' '')
    if ($prevPost -and $prevPost -ne $postureStr) {
        # Show the diff both ways - a REMOVED pin is as dangerous as an added hole.
        $added   = @($posture | Where-Object { ($prevPost -split "`n") -notcontains $_ })
        $removed = @(($prevPost -split "`n") | Where-Object { $posture -notcontains $_ })
        $body = @()
        if ($added)   { $body += "ADDED:`n  " + ($added -join "`n  ") }
        if ($removed) { $body += "REMOVED:`n  " + ($removed -join "`n  ") }
        Alert "$($script:srvName) - firewall posture CHANGED (22/3389)" `
              (($body -join "`n") + "`nRDP should stay pinned to the home IP; SSH is intentionally open but key-only.") `
              'max' @('rotating_light', 'fire')
    }
    $new['firewallPosture'] = $postureStr
} else {
    Log 'firewall posture: Get-NetFirewallRule unavailable - skipped'
    $new['firewallPosture'] = [string](State-Get $state 'firewallPosture' '')
}

# ══ 9. disk space ════════════════════════════════════════════════════════════
# Mundane, but a full disk takes the game server down and logs grow forever. Re-alert throttled:
# unlike everything above, this condition PERSISTS once true.
$diskAlertAt = State-Get $state 'diskAlertAt' $null
$newDiskAt   = $diskAlertAt
try {
    $c = Get-PSDrive -Name C -PSProvider FileSystem -ErrorAction Stop
    $freeGb = [math]::Round($c.Free / 1GB, 1)
    if ($freeGb -lt $DiskFreeGbMin) {
        $due = $true
        if ($diskAlertAt) {
            try { $due = ((Get-Date) - [datetime]$diskAlertAt).TotalMinutes -ge $ReAlertMinutes } catch { $due = $true }
        }
        if ($due) {
            Alert "$($script:srvName) - low disk" "C: has ${freeGb} GB free (floor ${DiskFreeGbMin} GB)." 'high' @('warning')
            $newDiskAt = (Get-Date).ToString('o')
        }
    } else { $newDiskAt = $null }
} catch { Log "disk check failed: $($_.Exception.Message)" }
$new['diskAlertAt'] = $newDiskAt

# ══ 10. is the WATCHDOG alive? (the reciprocal dead-man check) ════════════════
# GF-Watchdog watches every service INCLUDING this one (its check 1b) - but nothing watched the
# watchdog. If its trigger breaks or its script starts failing every run, ALL self-healing and
# health alerting dies silently, and that failure takes every other net down with it. This is
# the mirror of its check on us: two periodic tasks on INDEPENDENT triggers, each the other's
# dead-man switch. 0x41301 = "currently running" is not a failure.
try {
    $wdName = 'GF-Watchdog'
    $wd  = Get-ScheduledTask -TaskName $wdName -ErrorAction SilentlyContinue
    if ($wd) {
        $wdi = Get-ScheduledTaskInfo -TaskName $wdName -ErrorAction SilentlyContinue
        $wdAgeMin = if ($wdi.LastRunTime) { [int]((Get-Date) - $wdi.LastRunTime).TotalMinutes } else { 9999 }
        $wdBad = ($wdi.LastTaskResult -ne 0 -and $wdi.LastTaskResult -ne 267009 -and $wdi.LastTaskResult -ne 267011)
        if ($wdAgeMin -gt 15 -or $wdBad) {
            $why = if ($wdBad) { "LastTaskResult=0x$('{0:X}' -f $wdi.LastTaskResult)" } else { "last ran ${wdAgeMin} min ago (cadence 3 min)" }
            # Remediate first, alert regardless: with the watchdog down there is no other healer.
            if (-not $WhatIf) { try { Start-ScheduledTask -TaskName $wdName } catch { } }
            Alert "$($script:srvName) - WATCHDOG down" `
                  ("$wdName : $why`nWhile it is down there is NO self-healing and NO health alerting - every other safety net is dark. Start was issued; verify it stays up.") `
                  'urgent' @('rotating_light')
        } else {
            Log "watchdog OK (last ran ${wdAgeMin} min ago)"
        }
    } else {
        Alert "$($script:srvName) - WATCHDOG not registered" `
              'GF-Watchdog does not exist as a scheduled task. No self-healing is running. Re-register with register_services.ps1.' `
              'urgent' @('rotating_light')
    }
} catch { Log "watchdog check failed: $($_.Exception.Message)" }

# ══ 11. Windows evaluation-license expiry (INERT on a licensed box) ═══════════
# Pre-staged for the migration target: the plan runs Windows Server EVALUATION for the trial
# month, and an expired eval starts shutting the machine down HOURLY - silently, at day 180.
# slmgr /dlv names the channel; only an EVAL channel with low remaining time alerts, so on this
# (licensed) box the check logs one line and does nothing. Threshold 14 days; re-alert daily via
# the standard throttle. Rearm guidance lives in the alert because future-you will read it there.
# ⚠ The throttle stamp follows section 9's idiom and MUST: $new is rebuilt empty every run and
# Write-State replaces the whole file, so a key written ONLY inside the alert branch is dropped on
# the next quiet run - State-Get then reads $null, $due is always true, and the "daily" re-alert
# fires every cadence (3 min) for the whole 14-day window. Seed from the old state, overwrite only
# when we actually alert, and write it back UNCONDITIONALLY below - including on the licensed and
# throw paths, where carrying $null forward is the correct no-op.
$evalAlertAt = State-Get $state 'evalAlertAt' $null
$newEvalAt   = $evalAlertAt
try {
    $slmgr = & cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /dlv 2>$null
    $txt = ($slmgr -join "`n")
    if ($txt -match '(?i)EVAL|TIMEBASED') {
        $minsLeft = $null
        if ($txt -match '(?i)Timebased activation expiration:\s*(\d+)\s*minute') { $minsLeft = [int]$Matches[1] }
        if ($null -ne $minsLeft) {
            $daysLeft = [math]::Round($minsLeft / 1440, 1)
            Log "windows EVAL detected: $daysLeft days remaining"
            if ($daysLeft -le 14) {
                $due = $true
                if ($evalAlertAt) { try { $due = ((Get-Date) - [datetime]$evalAlertAt).TotalHours -ge 24 } catch { } }
                if ($due) {
                    Alert "$($script:srvName) - Windows eval expires in $daysLeft days" `
                          ("At expiry Windows begins shutting down HOURLY - on an unattended server that is an outage loop. Options: slmgr /rearm (resets to 180d, max 6 uses, restart required) or license it (DISM /Online /Set-Edition:ServerStandard /ProductKey:...).") `
                          'high' @('warning', 'hourglass')
                    $newEvalAt = (Get-Date).ToString('o')
                }
            } else { $newEvalAt = $null }   # back above the threshold (rearmed/licensed): clear the stamp
        } else { Log 'windows EVAL channel detected but no expiration counter parsed - check slmgr /dlv by hand' }
    } else {
        Log 'windows license: not an evaluation channel (check inert)'
    }
} catch { Log "eval check failed: $($_.Exception.Message)" }
$new['evalAlertAt'] = $newEvalAt

# ── first run: seed bookmarks at the TIP so the next run starts clean ─────────
if ($null -eq $state) {
    foreach ($p in @(@{k='sshRecordId';l='OpenSSH/Operational'}, @{k='secRecordId';l='Security'}, @{k='sysRecordId';l='System'})) {
        if ([int64]$new[$p.k] -le 0) { $new[$p.k] = Tip-RecordId $p.l }
    }
    Log 'first run - bookmarks seeded at the current tip; steady state from the next run.'
}

$new['lastRun'] = (Get-Date).ToString('o')
Write-State ([pscustomobject]$new)

if ($Summary) {
    Log "SUMMARY: ssh events=$($sshEvents.Count) (accepted=$($accepted.Count), invalid=$($invalid.Count)), security=$($secEvents.Count), system=$($sysEvents.Count)"
    Log "         known keys: $($knownKeys -join ', ')"
    Log "         known users: $($knownUsers -join ', ')"
    if ($posture) { Log "         firewall 22/3389 rules:"; $posture | ForEach-Object { Log "           $_" } }
}
Log "done - $($script:alerted) alert(s)$(if ($WhatIf -or $Summary) { ' (WhatIf: nothing sent, no state written)' })"
