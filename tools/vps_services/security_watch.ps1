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
#     9  service installs (30d)          -> low. Per-event, low priority.
#
# ⚠ AUDIT POLICY GAPS (auditpol, read live off this box - a detector for these fires NEVER):
#     "Other Object Access Events"       = No Auditing -> 4698 scheduled-task-created is DEAD.
#                                          Scheduled tasks are THE classic persistence trick, so
#                                          this is a real blind spot. Enable with:
#         auditpol /set /subcategory:"Other Object Access Events" /success:enable
#                                          (it is chatty - measure before trusting it.)
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
    $ok = Send-GfNtfy -Config $script:notify -Title $title -Message $message -Priority $priority -Tags $tags
    if (-not $ok) { Log "  ntfy send FAILED: $($script:GfNtfyLastError)" }
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
$sysBookmark = [int64](State-Get $state 'sysRecordId' 0)
$sysEvents   = Get-NewEvents 'System' $sysBookmark @(7045)
foreach ($e in $sysEvents) {
    Alert "$($script:srvName) - service installed" `
          ("$(Xml-Data $e 'ServiceName') at $($e.TimeCreated.ToString('HH:mm:ss'))`n$(Xml-Data $e 'ImagePath')") `
          'default' @('gear')
}
$new['sysRecordId'] = Max-RecordId $sysEvents $sysBookmark

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
