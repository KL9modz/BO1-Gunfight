# setup_admin_auth.ps1 - lock down the /admin status view with IIS Basic Auth (run ON the VPS)
# ------------------------------------------------------------------------------
# Secures wwwroot\admin (the IP-bearing admin page + admin.json) behind HTTP Basic
# Authentication over the site's existing HTTPS, then drops the ".secured" marker
# that lets status_service.ps1 begin writing the admin snapshot. Until this runs,
# NO IP data is ever written to the web root.
#
#   powershell -ExecutionPolicy Bypass -File setup_admin_auth.ps1              # install
#   powershell -ExecutionPolicy Bypass -File setup_admin_auth.ps1 -Password "..."   # set a known pw
#   powershell -ExecutionPolicy Bypass -File setup_admin_auth.ps1 -Uninstall   # revert (keeps user)
#   powershell -ExecutionPolicy Bypass -File setup_admin_auth.ps1 -Uninstall -RemoveUser
#
# Run ELEVATED (Administrator). Basic auth sends credentials base64-encoded, so it
# MUST be HTTPS-only - the site already forces HTTPS + HSTS, so that holds here.
#
# NOTE: this is the one helper that could not be tested from the dev machine (SSH to
# the box is firewalled to the home IP). Review it before running. The README lists
# the equivalent manual IIS steps as a fallback.
# ------------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string] $SiteName  = 'Default Web Site',
    [string] $AdminUser = 'gfweb',
    [string] $Password  = '',
    [string] $WebRoot   = 'C:\inetpub\wwwroot',
    [switch] $Uninstall,
    [switch] $RemoveUser
)

$ErrorActionPreference = 'Stop'
$adminPath   = "$SiteName/admin"                       # IIS location path
$adminDir    = Join-Path $WebRoot 'admin'
$liveDir     = Join-Path $adminDir 'live'
$markerFile  = Join-Path $liveDir '.secured'

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this elevated (Administrator)."
    }
}
Assert-Admin
Import-Module WebAdministration -ErrorAction Stop

# --- Uninstall ----------------------------------------------------------------
if ($Uninstall) {
    Write-Host "Reverting admin auth on '$adminPath'..."
    try {
        Set-WebConfigurationProperty -PSPath 'IIS:\' -Location $adminPath `
            -Filter '/system.webServer/security/authentication/basicAuthentication' -Name enabled -Value $false
        Set-WebConfigurationProperty -PSPath 'IIS:\' -Location $adminPath `
            -Filter '/system.webServer/security/authentication/anonymousAuthentication' -Name enabled -Value $true
    } catch { Write-Warning "auth revert: $($_.Exception.Message)" }
    try { Clear-WebConfiguration -PSPath 'IIS:\' -Location $adminPath -Filter '/system.webServer/security/authorization' } catch { }

    if (Test-Path $markerFile) { Remove-Item $markerFile -Force; Write-Host "Removed .secured (admin snapshot will stop being written)." }
    $adminJson = Join-Path $liveDir 'admin.json'
    if (Test-Path $adminJson) { Remove-Item $adminJson -Force; Write-Host "Removed stale admin.json." }

    if ($RemoveUser -and (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue)) {
        Remove-LocalUser -Name $AdminUser; Write-Host "Removed local user '$AdminUser'."
    }
    Write-Host "Done. /admin is no longer auth-gated (and no admin snapshot is produced)."
    return
}

# --- Password -----------------------------------------------------------------
function New-StrongPassword {
    $upper='ABCDEFGHJKLMNPQRSTUVWXYZ'; $lower='abcdefghijkmnpqrstuvwxyz'
    $dig='23456789'; $sym='!@#$%^*-_=+'
    $all="$upper$lower$dig$sym"
    $pw = ($upper[(Get-Random -Max $upper.Length)]) + ($lower[(Get-Random -Max $lower.Length)]) +
          ($dig[(Get-Random -Max $dig.Length)]) + ($sym[(Get-Random -Max $sym.Length)])
    for ($i=0; $i -lt 16; $i++) { $pw += $all[(Get-Random -Max $all.Length)] }
    return $pw
}
$generated = $false
if ([string]::IsNullOrEmpty($Password)) { $Password = New-StrongPassword; $generated = $true }

# --- IIS features -------------------------------------------------------------
foreach ($feat in @('Web-Basic-Auth','Web-Url-Auth')) {
    $f = Get-WindowsFeature -Name $feat -ErrorAction SilentlyContinue
    if ($f -and -not $f.Installed) {
        Write-Host "Installing IIS feature $feat ..."
        Install-WindowsFeature -Name $feat | Out-Null
    }
}

# --- Local user ---------------------------------------------------------------
$sec = ConvertTo-SecureString $Password -AsPlainText -Force
if (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $AdminUser -Password $sec
    Write-Host "Updated password for existing local user '$AdminUser'."
} else {
    New-LocalUser -Name $AdminUser -Password $sec -FullName 'Gunfight Web Admin' `
        -Description 'IIS Basic auth for /admin status page' -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    # Members of Users get "Access this computer from the network", which IIS Basic
    # auth (network logon) needs to validate the credential.
    try { Add-LocalGroupMember -Group 'Users' -Member $AdminUser -ErrorAction Stop } catch { }
    Write-Host "Created local user '$AdminUser'."
}

# --- Ensure folders exist -----------------------------------------------------
if (-not (Test-Path $adminDir)) { New-Item -ItemType Directory -Force -Path $adminDir | Out-Null }
if (-not (Test-Path $liveDir))  { New-Item -ItemType Directory -Force -Path $liveDir  | Out-Null }

# --- IIS auth config (written to applicationHost.config at <location admin>, so it
#     survives web deploys and is not part of the wwwroot mirror) -----------------
Set-WebConfigurationProperty -PSPath 'IIS:\' -Location $adminPath `
    -Filter '/system.webServer/security/authentication/anonymousAuthentication' -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath 'IIS:\' -Location $adminPath `
    -Filter '/system.webServer/security/authentication/basicAuthentication' -Name enabled -Value $true
Write-Host "Enabled Basic auth + disabled Anonymous on /admin."

# Restrict to just the admin user (URL Authorization). Best-effort: needs Web-Url-Auth.
try {
    Clear-WebConfiguration -PSPath 'IIS:\' -Location $adminPath -Filter '/system.webServer/security/authorization' -ErrorAction SilentlyContinue
    Add-WebConfiguration -PSPath 'IIS:\' -Location $adminPath -Filter '/system.webServer/security/authorization' `
        -Value @{ accessType='Allow'; users=$AdminUser } -ErrorAction Stop
    Write-Host "Restricted /admin to user '$AdminUser'."
} catch {
    Write-Warning "Could not set URL authorization ($($_.Exception.Message)). Basic auth still requires a valid Windows credential; any local account would be accepted."
}

# --- Drop the interlock marker (unlocks the admin snapshot) --------------------
Set-Content -Path $markerFile -Value ("secured {0}" -f (Get-Date -Format 'o')) -Encoding ASCII
Write-Host "Wrote $markerFile - status_service will now write admin.json here."

Write-Host ''
Write-Host '======================================================================'
Write-Host ' Admin view secured:  https://gunfight.us/admin/admin.html'
Write-Host ("   user:     {0}" -f $AdminUser)
if ($generated) {
    Write-Host ("   password: {0}" -f $Password)
    Write-Host '   ^ shown ONCE - save it now (it is not stored anywhere).'
} else {
    Write-Host '   password: (the one you passed via -Password)'
}
Write-Host '======================================================================'
Write-Host 'If GF-StatusService is already registered, it picks up the marker within'
Write-Host 'one poll (~5s). Otherwise run register_services.ps1.'
