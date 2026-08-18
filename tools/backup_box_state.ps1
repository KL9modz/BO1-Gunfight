# Back up everything on this box that a `git clone` + build CANNOT reproduce, as one encrypted
# archive. This is the executable form of docs\MIGRATION.md Phase 1 (the carry list) - keep the two
# in step, and prefer fixing this script over re-reading that doc under pressure.
#
#   .\backup_box_state.ps1                      # make a backup (uses the stored passphrase)
#   .\backup_box_state.ps1 -Verify <file>       # decrypt + list, WITHOUT restoring
#   .\backup_box_state.ps1 -Restore <file> -To C:\restore
#   .\backup_box_state.ps1 -WhatIf              # show what would be collected, write nothing
#
# WHY ENCRYPTED, AND WHAT THAT DOES AND DOES NOT BUY. The archive holds live credentials (rcon and
# g_password out of dedicated.cfg, the panel's stored passwords, the Discord webhook URLs) and
# player PII (GUIDs and IPs in the day-files). Encryption protects it AFTER IT LEAVES THE BOX -
# on a laptop, in a private repo, in cloud storage. It does NOT protect against a compromise of
# this box, because anything that can read the passphrase file can already read the plaintext
# sources; that is a deliberate, bounded trade, not an oversight.
#
# ⚠ NEVER commit an archive, and never commit the passphrase. Keep the passphrase in a password
# manager as well as in tools\backup.local.json (gitignored) - an archive whose passphrase died
# with the box it was protecting is not a backup.
#
# ⚠ ROTATE, DON'T RESTORE, the credential class (MIGRATION Phase 2). The manifest inside every
# archive marks each item CARRY or ROTATE so the distinction survives into the restore, when it
# actually matters and nobody is reading docs.
[CmdletBinding()]
param(
    [string] $OutDir      = '',
    [string] $Passphrase  = '',
    [string] $CopyTo      = '',      # second destination (a pulled share, a synced folder)
    [string] $GitDir      = '',      # local clone of the PRIVATE backup repo (see Publish-Backup)
    [int]    $KeepDays    = 30,
    [string] $Verify      = '',
    [string] $Restore     = '',
    [string] $To          = '',
    [switch] $IncludeClaudeCreds,    # OFF by default - see the note at the collection list
    [switch] $Encrypt,               # local archives only; the repo path is plaintext by decision
    [switch] $WhatIf
)
$ErrorActionPreference = 'Stop'

# ⚠ PowerShell 5.1 does not load this by default. The BACKUP path gets it implicitly via
# Compress-Archive, so the omission was invisible there and only -Verify / -Restore failed - i.e.
# it broke the half you reach for when a backup actually matters. Load it explicitly, up front.
Add-Type -AssemblyName System.IO.Compression.FileSystem

. (Join-Path $PSScriptRoot 'common.ps1')      # Resolve-T5Root

$t5      = Resolve-T5Root
$modRoot = Join-Path $t5 'mods\mp_gunfight'
$tools   = Join-Path $modRoot 'tools'
if (-not $OutDir) { $OutDir = Join-Path $t5 'backups' }

# ── the collection list ────────────────────────────────────────────────────────────────────────
# Class is documentation that TRAVELS WITH THE DATA: it lands in the manifest inside the archive,
# so whoever restores sees "rotate this" at the moment of restoring rather than in a doc they read
# last month.
#   CARRY    - irreplaceable or expensive to rebuild; restore it as-is
#   ROTATE   - restore only to get running, then replace (it has been sitting in an archive)
#   CONFIG   - box/OS config; review against the NEW box rather than pasting blindly
function Item($path, $class, $why) {
    return [pscustomobject]@{ Path = $path; Class = $class; Why = $why }
}
$items = @(
    # --- irreplaceable history and state -------------------------------------------------------
    Item (Join-Path $t5 'logs\players_*.log')                    'CARRY'  'connect history day-files - the source every activity/admin view derives from'
    Item (Join-Path $t5 'logs\gamestats.local.json')             'CARRY'  'aggregated GF_STAT/GF_MATCH buckets (the log tail offset lives here too)'
    Item (Join-Path $tools 'players.local.json')                 'CARRY'  'player GUID -> Discord id links'
    Item (Join-Path $tools 'ignore.local.json')                  'CARRY'  'muted GUIDs'
    Item (Join-Path $tools 'rcon\prefs.local.json')              'CARRY'  'panel FAVORITES pinboard'
    Item (Join-Path $tools 'rcon\.geocache.json')                'CARRY'  'ip-api results - rebuildable but rate-limited at 45/min, so worth carrying'
    Item (Join-Path $tools 'vps_services\security_state.json')   'CARRY'  'SecurityWatch event bookmarks + learned baseline'
    Item (Join-Path $tools 'notify\discord_status.local.json')   'CARRY'  'the live status cards message id (lose it and a duplicate card appears)'
    Item (Join-Path $tools 'security.local.json')                'CARRY'  'SecurityWatch trust store (ssh key fingerprints)'
    Item (Join-Path $t5 'bots.txt')                              'CARRY'  'bot display names + clantags (read at process start)'

    # --- credentials: restore to get running, then replace --------------------------------------
    Item (Join-Path $t5 'dedicated.cfg')                         'ROTATE' 'rcon_password + g_password live here, alongside all engine tuning'
    Item (Join-Path $tools 'rcon\secrets.local.json')            'ROTATE' 'panel per-profile rcon passwords'
    Item (Join-Path $tools 'notify\config.json')                 'ROTATE' 'ntfy topic + Discord webhook URLs (a webhook URL IS the credential)'
    Item 'C:\gameserver\T5\start_mp_server.bat'                  'ROTATE' 'Plutonium server key + the sv_maxclients latch. Re-issue the key at platform.plutonium.pw and REUSE THE EXACT LABEL - the label is the in-game browser name'

    # --- box / OS config: review against the new box --------------------------------------------
    Item 'C:\inetpub\wwwroot\web.config'                         'CONFIG' 'IIS: MIME types, headers, CSP'
    Item 'C:\inetpub\wwwroot\admin\live\.secured'                'CONFIG' 'the admin-auth interlock marker; setup_admin_auth.ps1 writes it, and without it no admin snapshot is published'
    Item 'C:\ProgramData\ssh\sshd_config'                        'CONFIG' 'key-only auth needs BOTH PasswordAuthentication no and KbdInteractiveAuthentication no, in the GLOBAL section'
    Item 'C:\ProgramData\ssh\administrators_authorized_keys'     'CONFIG' 'admin ssh keys (Windows ignores ~/.ssh for admins)'

    # --- build outputs are NOT collected: GitHub already has them -------------------------------
    # mod.ff and mp_gunfight.iwd both live on origin/release (that is where deploy.ps1 -Mod checks
    # mod.ff out of), and the .iwd rebuilds from the 30 tracked images\*.iwi. Carrying them here
    # was 672 KB of a 768 KB archive - 87% of every daily push - to duplicate something already
    # versioned off-box. Restore them with:
    #     git checkout origin/release -- mod.ff mp_gunfight.iwd
    # ⚠ If they are ever dropped from origin/release, put them BACK in this list: mod.ff cannot be
    # rebuilt on this box or in a cloud session (it needs Windows, the BO1 linker and S:\zone_source
    # on the dev desktop), so losing both copies at once is unrecoverable without that machine.
)
# ⚠ ~\.claude\.credentials.json is DELIBERATELY OPT-IN (-IncludeClaudeCreds). It is a full-scope
# OAuth token for the Claude account, which is equivalent to the SSH key on this box. Re-running
# `claude auth login` on the new host costs a minute; carrying the token in an archive multiplies
# the places it can leak from. Opt in only for an offline migration you are performing right now.
if ($IncludeClaudeCreds) {
    $items += Item (Join-Path $env:USERPROFILE '.claude\.credentials.json') 'ROTATE' 'Claude OAuth (Remote Control). Prefer re-authenticating on the new box'
}

# ⚠ NOT collected, on purpose: logs\games_mp.log* (hundreds of MB, and the live handle is held
# open) and console_mp.log (92% per-round dvar dump). They are diagnostics, not state - carrying
# them would turn an 11MB backup into a 350MB one and make the daily task a disk problem.

function Get-BackupPassphrase {
    if ($Passphrase) { return $Passphrase }
    if ($env:GF_BACKUP_PASSPHRASE) { return $env:GF_BACKUP_PASSPHRASE }
    $store = Join-Path $PSScriptRoot 'backup.local.json'
    if (Test-Path $store) {
        try {
            $j = Get-Content $store -Raw | ConvertFrom-Json
            if ($j.passphrase) { return [string]$j.passphrase }
        } catch { }
    }
    throw "no passphrase: pass -Passphrase, set GF_BACKUP_PASSPHRASE, or create tools\backup.local.json with { ""passphrase"": ""..."" }"
}

# ── crypto ─────────────────────────────────────────────────────────────────────────────────────
# AES-256-CBC with a per-archive random salt+IV, key stretched with PBKDF2, and an HMAC-SHA256 over
# the ciphertext (encrypt-then-MAC). The MAC is not decoration: without it a truncated or corrupted
# archive fails as a garbage unzip much later, instead of as a clear "this file is damaged" now.
$script:GfMagic = [byte[]][char[]]'GFBK1'

function Protect-File($inFile, $outFile, $pass) {
    $salt = New-Object byte[] 16; $iv = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($salt); $rng.GetBytes($iv)
    $kdf  = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 200000)
    $key  = $kdf.GetBytes(32); $mkey = $kdf.GetBytes(32)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256; $aes.Key = $key; $aes.IV = $iv
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

    $plain  = [System.IO.File]::ReadAllBytes($inFile)
    $cipher = $aes.CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)
    $hmac   = New-Object System.Security.Cryptography.HMACSHA256(,$mkey)
    $tag    = $hmac.ComputeHash($cipher)

    $fs = [System.IO.File]::Create($outFile)
    try {
        $fs.Write($script:GfMagic, 0, $script:GfMagic.Length)
        $fs.Write($salt, 0, 16); $fs.Write($iv, 0, 16); $fs.Write($tag, 0, 32)
        $fs.Write($cipher, 0, $cipher.Length)
    } finally { $fs.Dispose(); $aes.Dispose() }
}

function Unprotect-File($inFile, $outFile, $pass) {
    $all = [System.IO.File]::ReadAllBytes($inFile)
    $hdr = 5 + 16 + 16 + 32
    if ($all.Length -le $hdr) { throw "not a GF backup archive (too short): $inFile" }
    for ($i = 0; $i -lt 5; $i++) {
        if ($all[$i] -ne $script:GfMagic[$i]) { throw "not a GF backup archive (bad magic): $inFile" }
    }
    $salt = $all[5..20]; $iv = $all[21..36]; $tag = $all[37..68]
    $cipher = New-Object byte[] ($all.Length - $hdr)
    [Array]::Copy($all, $hdr, $cipher, 0, $cipher.Length)

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, [byte[]]$salt, 200000)
    $key = $kdf.GetBytes(32); $mkey = $kdf.GetBytes(32)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256(,$mkey)
    $calc = $hmac.ComputeHash($cipher)
    # Constant-time-ish compare, and a WRONG PASSPHRASE lands here rather than as a padding error.
    $ok = ($calc.Length -eq 32)
    if ($ok) { for ($i = 0; $i -lt 32; $i++) { if ($calc[$i] -ne $tag[$i]) { $ok = $false } } }
    if (-not $ok) { throw "wrong passphrase, or the archive is corrupt (HMAC mismatch)" }

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256; $aes.Key = $key; $aes.IV = [byte[]]$iv
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    try {
        $plain = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length)
        [System.IO.File]::WriteAllBytes($outFile, $plain)
    } finally { $aes.Dispose() }
}


# ── publish to the private backup repo ─────────────────────────────────────────────────────────
# PLAINTEXT BY DECISION (owner's call, 2026-08-18). What that buys and what it costs:
#
#   buys  - git does real work. Day-files are append-only, so a day already committed is stored
#           ONCE and costs nothing again; only genuinely changed bytes cost anything. An encrypted
#           archive is a fresh incompressible blob every run (~116 KB/day forever, changed or not),
#           so plaintext is roughly 5-10x cheaper AND diffable, browsable and restorable one file
#           at a time from the GitHub UI.
#   costs - the repo now holds live credentials (rcon_password + g_password out of dedicated.cfg,
#           the panel's stored passwords, the Discord webhook URLs) and PLAYER PII (IPs and GUIDs
#           in the day-files and the geo cache), in a form anyone with read access can use.
#
# ⚠ THEREFORE, THE ONLY THING PROTECTING ALL OF IT IS THAT THE REPO STAYS PRIVATE. Git history is
# permanent: if the repo is ever made public, forked, or its access leaks, deleting a file does not
# undo it - the remedy is rotating every credential in it, and the player data cannot be recalled
# at all. Treat "is this repo still private" as a standing check, not a setup step.
#
# ⚠ The marker guard below matters MORE now, not less. Encrypted, a mispush leaked ciphertext;
# plaintext, it leaks the lot. It refuses any tree without .gf-backup-repo, and refuses outright if
# origin looks like the public mod repo.
function Publish-BackupTree($stagingDir, $gitDir) {
    if (-not (Test-Path $gitDir)) { throw "backup repo clone not found: $gitDir" }
    if (-not (Test-Path (Join-Path $gitDir '.gf-backup-repo'))) {
        throw "refusing to publish: $gitDir has no .gf-backup-repo marker. That marker is what distinguishes the private backup clone from every other git tree on this box."
    }
    $remote = (& git -C $gitDir remote get-url origin 2>$null)
    if (-not $remote) { throw "no origin remote in $gitDir" }
    if ($remote -match 'BO1-Gunfight(\.git)?$') {
        throw "refusing to publish: origin of $gitDir is the PUBLIC mod repo ($remote)"
    }

    # MIRROR, not merge: a file that stops being collected must disappear from the repo tip too, or
    # the tree slowly becomes a museum of paths that no longer exist. History still holds it, which
    # is the point of using git at all.
    $stateDir = Join-Path $gitDir 'state'
    $null = robocopy $stagingDir $stateDir /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed mirroring into $stateDir (exit $LASTEXITCODE)" }

    if (-not (Test-Path (Join-Path $gitDir 'README.md'))) {
        @(
            '# BO1-Gunfight box state'
            ''
            'Everything the mod repo cannot rebuild: connect history, Discord links, panel prefs,'
            'caches, box config, scheduled task definitions, and the live credentials the server'
            'runs on. Written daily by `tools/backup_box_state.ps1` on the game server.'
            ''
            '**This repo must stay private.** It contains live credentials and player IPs/GUIDs in'
            'plaintext. If it is ever exposed, rotate everything in `state/` that `MANIFEST.txt`'
            'marks ROTATE; the player data cannot be recalled.'
            ''
            'Restore guidance is in `state/MANIFEST.txt`, which classes every file CARRY, ROTATE or'
            'CONFIG. Pair it with `docs/MIGRATION.md` in the mod repo.'
            ''
            '`mod.ff` and `mp_gunfight.iwd` are deliberately absent: they live on the mod repo'
            "'s `release` branch (`git checkout origin/release -- mod.ff mp_gunfight.iwd`)."
        ) -join "`r`n" | Set-Content -Path (Join-Path $gitDir 'README.md') -Encoding UTF8
    }

    & git -C $gitDir add -A | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    & git -C $gitDir -c user.name='GF-Backup' -c user.email='gf-backup@localhost' commit -q -m "box state $stamp" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host 'no changes since the last backup - nothing committed'; return }
    & git -C $gitDir push -q origin HEAD 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "git push failed (deploy key missing or revoked?) - the commit is local and the next run will push it"
    }
    $n = (& git -C $gitDir rev-list --count HEAD).Trim()
    Write-Host "published to $remote (commit $n)"
}

# ── verify / restore ───────────────────────────────────────────────────────────────────────────
if ($Verify -or $Restore) {
    $src = $(if ($Verify) { $Verify } else { $Restore })
    if (-not (Test-Path $src)) { throw "archive not found: $src" }
    $pass = Get-BackupPassphrase
    $tmpZip = Join-Path $env:TEMP ("gf_backup_" + [IO.Path]::GetRandomFileName() + ".zip")
    Unprotect-File $src $tmpZip $pass
    try {
        if ($Verify) {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($tmpZip)
            try {
                Write-Host "archive OK (HMAC verified): $src"
                Write-Host "$($zip.Entries.Count) entries, $([math]::Round((Get-Item $src).Length/1KB,1)) KB encrypted"
                $man = $zip.Entries | Where-Object { $_.FullName -eq 'MANIFEST.txt' }
                if ($man) {
                    $sr = New-Object System.IO.StreamReader($man.Open())
                    Write-Host ''; Write-Host $sr.ReadToEnd(); $sr.Dispose()
                }
            } finally { $zip.Dispose() }
        } else {
            if (-not $To) { throw 'give -To <dir> to restore into' }
            # NEVER restore in place. Files land in a staging dir and a human puts them where they
            # belong: half of them want reviewing against the new box, and several want rotating.
            if (-not (Test-Path $To)) { New-Item -ItemType Directory -Path $To -Force | Out-Null }
            Expand-Archive -LiteralPath $tmpZip -DestinationPath $To -Force
            Write-Host "restored into $To"
            Write-Host 'Read MANIFEST.txt there: items marked ROTATE must be replaced, not reused.'
        }
    } finally { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue }
    return
}

# ── backup ─────────────────────────────────────────────────────────────────────────────────────
$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$staging = Join-Path $env:TEMP "gf_backup_stage_$stamp"
$null = New-Item -ItemType Directory -Path $staging -Force

$manifest = New-Object System.Collections.ArrayList
$null = $manifest.Add("Gunfight box-state backup")
$null = $manifest.Add("taken    : $stamp")
$null = $manifest.Add("host     : $env:COMPUTERNAME")
$null = $manifest.Add("pairs with docs/MIGRATION.md Phase 1 (carry list) and Phase 2 (rotate, don't copy)")
$null = $manifest.Add('')
$null = $manifest.Add('CARRY  = restore as-is    ROTATE = replace after restoring    CONFIG = review against the new box')
$null = $manifest.Add('')

$copied = 0; $missing = 0; $bytes = 0
foreach ($it in $items) {
    $matches2 = @(Get-Item -Path $it.Path -ErrorAction SilentlyContinue)
    if ($matches2.Count -eq 0) {
        $missing++
        $null = $manifest.Add(("  [MISSING] {0,-7} {1}" -f $it.Class, $it.Path))
        continue
    }
    foreach ($m in $matches2) {
        # Mirror the source layout under a drive-letter-free relative path, so a restore is
        # readable and two files with the same leaf name cannot collide.
        $rel = ($m.FullName -replace '^[A-Za-z]:\\', '') -replace '[:*?"<>|]', '_'
        $dst = Join-Path $staging $rel
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force
        if (-not $WhatIf) { Copy-Item -LiteralPath $m.FullName -Destination $dst -Force }
        $copied++; $bytes += $m.Length
        $null = $manifest.Add(("  {0,-7} {1,10:N0}  {2}" -f $it.Class, $m.Length, $rel))
        if ($it.Class -ne 'CARRY') { $null = $manifest.Add(("            why: {0}" -f $it.Why)) }
    }
}

# Scheduled tasks as XML - the definitions themselves are state (they pin LOCALAPPDATA, the working
# directory and the repetition that self-heals GF-ClaudeRC).
$taskDir = Join-Path $staging '_scheduled_tasks'
$null = New-Item -ItemType Directory -Path $taskDir -Force
$tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'GF-*' })
foreach ($t in $tasks) {
    if ($WhatIf) { continue }
    try {
        (Export-ScheduledTask -TaskName $t.TaskName) | Set-Content -Path (Join-Path $taskDir "$($t.TaskName).xml") -Encoding UTF8
    } catch { $null = $manifest.Add("  [WARN] could not export task $($t.TaskName): $($_.Exception.Message)") }
}
$null = $manifest.Add('')
$null = $manifest.Add(("  CONFIG  {0} scheduled task definition(s) under _scheduled_tasks\" -f $tasks.Count))
$null = $manifest.Add('')
$null = $manifest.Add('NOT INCLUDED (diagnostics, not state): logs\games_mp.log*, console_mp.log')
$null = $manifest.Add('NOT INCLUDED unless -IncludeClaudeCreds: ~\.claude\.credentials.json (re-auth instead)')

if ($WhatIf) {
    Write-Host "WhatIf: would collect $copied file(s), $([math]::Round($bytes/1MB,2)) MB ($missing missing)"
    $manifest | ForEach-Object { Write-Host $_ }
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    return
}

$manifest -join "`r`n" | Set-Content -Path (Join-Path $staging 'MANIFEST.txt') -Encoding UTF8

# ── publish ────────────────────────────────────────────────────────────────────────────────────
# The repo path is the primary one, and it is PLAINTEXT by decision: git then stores each
# append-only day-file once instead of re-storing an opaque blob every run, and the tree stays
# diffable and restorable file-by-file. See Publish-BackupTree for what that costs.
if ($GitDir) {
    try {
        Publish-BackupTree $staging $GitDir
        Write-Host ("collected {0} file(s), {1:N0} KB ({2} missing)" -f $copied, ($bytes / 1KB), $missing)
    } catch {
        # A failed publish must not also destroy the local copy - leave staging for inspection.
        Write-Host "PUBLISH FAILED: $($_.Exception.Message)"
        Write-Host "collected files left at: $staging"
        return
    }
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    return
}

# ── or a local archive (no repo configured) ────────────────────────────────────────────────────
# Plain .zip unless -Encrypt. Encryption is opt-in rather than removed: the code is written and
# tested, and an archive leaving this box for anywhere OTHER than the private repo (a laptop, a USB
# stick, a cloud drive) still wants it.
if (-not (Test-Path $OutDir)) { $null = New-Item -ItemType Directory -Path $OutDir -Force }
$zip = Join-Path $env:TEMP "gf_backup_$stamp.zip"
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -Force

if ($Encrypt) {
    $pass = Get-BackupPassphrase
    $out = Join-Path $OutDir "gf_box_state_$stamp.gfbk"
    Protect-File $zip $out $pass
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    # Verify by DECRYPTING what we just wrote. An unverified backup is a belief, not a backup, and
    # the failures this catches (wrong passphrase source, truncated write) are otherwise silent.
    $check = Join-Path $env:TEMP "gf_backup_check_$stamp.zip"
    Unprotect-File $out $check $pass
    $entries = 0
    try {
        $z = [System.IO.Compression.ZipFile]::OpenRead($check); $entries = $z.Entries.Count; $z.Dispose()
    } finally { Remove-Item $check -Force -ErrorAction SilentlyContinue }
    Write-Host ("backup: {0}  ({1:N0} KB encrypted, {2} files, {3} missing, verified {4} entries)" -f `
        $out, ((Get-Item $out).Length / 1KB), $copied, $missing, $entries)
} else {
    $out = Join-Path $OutDir "gf_box_state_$stamp.zip"
    Move-Item -LiteralPath $zip -Destination $out -Force
    $entries = 0
    $z = [System.IO.Compression.ZipFile]::OpenRead($out)
    try { $entries = $z.Entries.Count } finally { $z.Dispose() }
    Write-Host ("backup: {0}  ({1:N0} KB, {2} files, {3} missing, verified {4} entries)" -f `
        $out, ((Get-Item $out).Length / 1KB), $copied, $missing, $entries)
}
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

if ($CopyTo) {
    if (-not (Test-Path $CopyTo)) { $null = New-Item -ItemType Directory -Path $CopyTo -Force }
    Copy-Item -LiteralPath $out -Destination $CopyTo -Force
    Write-Host "copied to $CopyTo"
}

# Retention. Only ever prunes files this script names, in the directory it owns.
if ($KeepDays -gt 0) {
    $cut = (Get-Date).AddDays(-$KeepDays)
    $old = @(Get-ChildItem $OutDir -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -like 'gf_box_state_*.gfbk' -or $_.Name -like 'gf_box_state_*.zip' } |
             Where-Object { $_.LastWriteTime -lt $cut })
    foreach ($o in $old) { Remove-Item $o.FullName -Force -ErrorAction SilentlyContinue }
    if ($old.Count) { Write-Host "pruned $($old.Count) archive(s) older than $KeepDays days" }
}
