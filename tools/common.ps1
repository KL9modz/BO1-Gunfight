# Shared PowerShell helpers for the mp_gunfight tooling. Dot-source it, like
# tools\release_common.ps1 / tools\ignore_list.ps1:
#   . (Join-Path $PSScriptRoot 'common.ps1')       # from a tools\ script
#   . (Join-Path $PSScriptRoot '..\common.ps1')    # from a tools\<subdir>\ script
#
# One source of truth for what used to be copy-pasted across the packagers and the box
# services: the storage-tree path walk (T5 root / mod root), reading rcon_password out of
# dedicated.cfg, the fastfile-build wrapper, and the GameRoot/ModName/port defaults.

# This file's own directory (…\storage\t5\mods\mp_gunfight\tools), captured at dot-source
# time so the path helpers below don't depend on WHICH script called them — the same trick
# release_common.ps1 uses with its $script:-scoped state.
$script:GfToolsRoot = $PSScriptRoot

# Repo/deploy defaults that were duplicated as literals across build_ff.ps1,
# package_server.ps1, package_release.ps1, deploy.ps1, and the box services.
$script:GfDefaultGameRoot = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740"
$script:GfDefaultModName  = "mp_gunfight"
$script:GfDefaultPort     = 28960

function Get-GfDefaultGameRoot { return $script:GfDefaultGameRoot }
function Get-GfDefaultModName  { return $script:GfDefaultModName }
function Get-GfDefaultPort     { return $script:GfDefaultPort }

# The T5 storage root (…\storage\t5). common.ps1 lives in <T5>\mods\mp_gunfight\tools, so
# T5 is three parents up. Split-Path (not Resolve-Path) so it never requires the path to
# exist — identical result to the ops scripts' prior four-parents-up walk from tools\<subdir>\
# (this file sits one level ABOVE those subdirs, hence 3 vs 4).
function Resolve-T5Root {
    $r = $script:GfToolsRoot
    for ($i = 0; $i -lt 3; $i++) { $r = Split-Path -Parent $r }
    return $r
}

# The mod folder (…\mods\mp_gunfight) — one parent up from tools\.
function Resolve-ModRoot {
    return (Split-Path -Parent $script:GfToolsRoot)
}

# Read rcon_password from a dedicated.cfg, with the precedence the callers used: an explicit
# value wins, then $env:GF_RCON_PW, then the cfg file. Uses the most permissive of the prior
# regexes (set/seta, optional quotes around the dvar name) so it is a strict superset of every
# prior reader — for an ordinary set-password cfg line the result is identical. Returns ''
# when nothing is found; a caller that must throw on empty still does so itself.
function Get-RconPassword {
    param(
        [string]$Explicit,
        [string]$CfgPath
    )
    if (-not [string]::IsNullOrEmpty($Explicit))       { return $Explicit }
    if (-not [string]::IsNullOrEmpty($env:GF_RCON_PW)) { return $env:GF_RCON_PW }
    if ($CfgPath -and (Test-Path $CfgPath)) {
        $m = [regex]::Match((Get-Content $CfgPath -Raw), '(?im)^\s*set[as]?\s+"?rcon_password"?\s+"([^"]*)"')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return ''
}

# Build mod.ff via the shared build_ff.ps1 (the linker invocation itself lives only there).
# This ~8-line wrapper was byte-identical in both packagers. -ModFf, when given, is the
# expected output path checked after the build.
function Invoke-BuildFf {
    param(
        [Parameter(Mandatory)][string]$GameRoot,
        [Parameter(Mandatory)][string]$ModName,
        [switch]$SkipBuild,
        [string]$ModFf
    )
    if (-not $SkipBuild) {
        $buildScript = Join-Path $script:GfToolsRoot 'build_ff.ps1'
        if (!(Test-Path -LiteralPath $buildScript)) { throw "build_ff.ps1 not found: $buildScript" }
        Write-Host ""
        Write-Host "Building mod.ff ..."
        & $buildScript -GameRoot $GameRoot -ModName $ModName
        if ($LASTEXITCODE -ne 0) { throw "build_ff.ps1 failed (exit $LASTEXITCODE)" }
    }
    if ($ModFf -and !(Test-Path -LiteralPath $ModFf)) { throw "mod.ff not found (build it first): $ModFf" }
}
