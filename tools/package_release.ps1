param(
    [Parameter(Position = 0)][string]$Version = ("0.0.0-dev." + (Get-Date -Format "yyyyMMdd")),
    [string]$GameRoot = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops 42740",
    [string]$ModName = "mp_gunfight",
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$SkipBuild,
    [switch]$KeepComments,
    [switch]$Publish,
    [switch]$PublishBranch,
    [string]$ReleaseBranch = "release"
)

$ErrorActionPreference = "Stop"

# ONE minimal public profile, staged from the full 'main' source. The 'release'
# branch and the Release zip carry the SAME content (branch = browsable + clonable,
# zip = download). 'main' keeps everything; this script never modifies it.
#
# What ships: mod.ff + the gameplay GSC under maps/ + README.md + docs/ (SETUP.md).
# What is dropped: the dev files below, and any dev wiring wrapped in markers:
#     // #strip-begin ... // #strip-end
# (markers are inert // comments on main, so the dev build is unaffected).
#
# The shipped GSC is also COMMENT-STRIPPED (// line + /* */ block comments) so the
# public source carries no dev notes/TODOs. Strings that contain comment markers are
# preserved. 'main' keeps every comment; only these staged copies are stripped. Pass
# -KeepComments to skip stripping (e.g. when debugging a release build).
#
# Usage:
#   tools\package_release.ps1                        # build the zip
#   tools\package_release.ps1 1.0.0                  # versioned zip
#   tools\package_release.ps1 1.0.0 -PublishBranch   # zip + push 'release' branch
#   tools\package_release.ps1 1.0.0 -Publish         # zip + GitHub Release
#   tools\package_release.ps1 -SkipBuild             # reuse the existing mod.ff
#   tools\package_release.ps1 -KeepComments          # keep GSC comments in the public copy

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Dev-only GSC excluded from the public mod (forward-slash, repo-relative).
$DevFiles = @(
    "maps/mp/gametypes/_bot.gsc",
    "maps/mp/bots/_bot_loadout.gsc",
    "maps/mp/bots/_bot_script.gsc",
    "maps/mp/bots/_bot_utility.gsc",
    "maps/mp/gametypes/_gf_bridge.gsc",
    "maps/mp/gametypes/_gf_debug.gsc"
)

function Strip-Markers {
    param([string]$Content)
    # Remove every "// #strip-begin ... // #strip-end" region (dev wiring) inclusive.
    return [regex]::Replace($Content, "(?ms)^[^\r\n]*#strip-begin\b.*?#strip-end[^\r\n]*\r?\n?", "")
}

function Strip-Comments {
    param([string]$Content)
    # Remove // line comments and /* */ block comments from GSC source, leaving any
    # comment markers that appear INSIDE "string literals" untouched. A character
    # scan (not regex) is required to tell a real comment from one inside a string
    # (e.g. a "http://" or a "//" inside a printed message). Newlines inside block
    # comments are preserved so line numbers barely shift; the resulting comment-only
    # lines and trailing blanks are then tidied: trailing whitespace trimmed, runs of
    # blank lines collapsed to one, leading/trailing blank lines removed. Code and
    # string literals are emitted verbatim.
    #
    # MUST run AFTER Strip-Markers: the #strip-begin/#strip-end marker lines are //
    # comments but the wiring BETWEEN them is real code -- strip the markers first or
    # comment removal would delete the markers and leak the dev body.
    #
    # Blank-line policy: a line that was ONLY a comment is removed outright (no gap
    # left behind); a blank line the author actually wrote is kept. Runs of blank
    # lines collapse to one. The scan preserves newlines 1:1, so each stripped line
    # maps to its original line and the two cases are distinguishable.

    $eol = "`n"
    if ($Content.Contains("`r`n")) { $eol = "`r`n" }
    $text = $Content -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"

    $sb = New-Object System.Text.StringBuilder
    $len = $text.Length
    $i = 0
    $state = 0   # 0 = code, 1 = string, 2 = line comment, 3 = block comment
    while ($i -lt $len) {
        $c = $text.Substring($i, 1)
        $d = ''
        if ($i + 1 -lt $len) { $d = $text.Substring($i + 1, 1) }

        if ($state -eq 0) {
            if ($c -eq '"') { [void]$sb.Append($c); $state = 1; $i++ }
            elseif ($c -eq '/' -and $d -eq '/') { $state = 2; $i += 2 }
            elseif ($c -eq '/' -and $d -eq '*') { $state = 3; $i += 2 }
            else { [void]$sb.Append($c); $i++ }
        }
        elseif ($state -eq 1) {
            # inside "..."; backslash escapes the next char (e.g. \" does not close)
            if ($c -eq '\') {
                [void]$sb.Append($c)
                if ($d -ne '') { [void]$sb.Append($d) }
                $i += 2
            }
            elseif ($c -eq '"') { [void]$sb.Append($c); $state = 0; $i++ }
            else { [void]$sb.Append($c); $i++ }
        }
        elseif ($state -eq 2) {
            # line comment: drop until newline (newline itself is kept)
            if ($c -eq "`n") { [void]$sb.Append($c); $state = 0; $i++ }
            else { $i++ }
        }
        else {
            # block comment: drop until */, but keep newlines so lines stay aligned
            if ($c -eq '*' -and $d -eq '/') { $state = 0; $i += 2 }
            elseif ($c -eq "`n") { [void]$sb.Append($c); $i++ }
            else { $i++ }
        }
    }

    $origLines  = $text -split "`n", -1
    $stripLines = $sb.ToString() -split "`n", -1
    $out = New-Object System.Collections.Generic.List[string]
    $blank = 0
    for ($k = 0; $k -lt $stripLines.Count; $k++) {
        $t = $stripLines[$k].TrimEnd()
        if ($t.Length -eq 0) {
            # Now-blank line: keep it only if the original line was also blank (an
            # author blank). If the original had content it was a comment-only line
            # -> drop it so no gap is left. Blank runs collapse to a single blank.
            $origBlank = $true
            if ($k -lt $origLines.Count) { $origBlank = ($origLines[$k].Trim().Length -eq 0) }
            if ($origBlank) {
                $blank++
                if ($blank -le 1) { [void]$out.Add('') }
            }
        }
        else {
            $blank = 0
            [void]$out.Add($t)
        }
    }
    while ($out.Count -gt 0 -and $out[0] -eq '') { $out.RemoveAt(0) }
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }

    return ([string]::Join($eol, $out)) + $eol
}

function Build-Staging {
    param([string]$StageMod)

    if (Test-Path -LiteralPath $StageMod) { Remove-Item -Recurse -Force -LiteralPath $StageMod }
    New-Item -ItemType Directory -Force -Path $StageMod | Out-Null

    Copy-Item -Force -LiteralPath $ModFf -Destination (Join-Path $StageMod "mod.ff")

    $gscFiles = Get-ChildItem -Recurse -File -LiteralPath (Join-Path $ModRoot "maps") -Filter *.gsc
    $n = 0
    foreach ($file in $gscFiles) {
        $rel = $file.FullName.Substring($ModRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if ($DevFiles -contains $rel) { continue }
        $content = Strip-Markers ([System.IO.File]::ReadAllText($file.FullName))
        if (-not $KeepComments) { $content = Strip-Comments $content }
        $dest = Join-Path $StageMod ($rel -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        [System.IO.File]::WriteAllText($dest, $content, $Utf8NoBom)
        $n++
    }

    # No mod.csv: it's a build-time zone-source manifest (linker/mod tools), not
    # read by Plutonium at runtime. Runtime needs only mod.ff + the GSC.

    # -- Player-facing docs: SETUP -------------------------------------------
    # REFERENCE.md / DEV.md stay main-only; rewrite their inbound links (and the
    # ops docs) in the staged copies to main-branch GitHub URLs so nothing 404s.
    # SETUP<->../README.md links stay local (the doc + the generated README
    # ship, so they resolve inside the release).
    $mainBlob = "https://github.com/KL9modz/BO1-Gunfight/blob/main"
    $stageDocs = Join-Path $StageMod "docs"
    New-Item -ItemType Directory -Force -Path $stageDocs | Out-Null
    $docCount = 0
    foreach ($d in @("SETUP.md")) {
        $src = Join-Path $ModRoot "docs\$d"
        if (!(Test-Path -LiteralPath $src)) { Write-Warning "release doc missing: docs\$d"; continue }
        $c = [System.IO.File]::ReadAllText($src)
        $c = $c -replace '\]\(REFERENCE\.md', "](${mainBlob}/docs/REFERENCE.md"
        $c = $c -replace '\]\(DEV\.md', "](${mainBlob}/docs/DEV.md"
        $c = $c -replace '\]\(\.\./VPS_DEPLOY\.md', "](${mainBlob}/VPS_DEPLOY.md"
        $c = $c -replace '\]\(\.\./VPS_HARDENING\.md', "](${mainBlob}/VPS_HARDENING.md"
        [System.IO.File]::WriteAllText((Join-Path $stageDocs $d), $c, $Utf8NoBom)
        $docCount++
    }

    # The 'release' branch is the GitHub DEFAULT branch, so this README is the
    # repo's public landing page - keep it player-facing and on-brand.
    $readme = @'
<div align="center">

# Black Ops Gunfight

**Round-based, one-life Gunfight for Call of Duty: Black Ops 1 - on Plutonium T5.**

One life per round. A shared random loadout every round. No killstreaks, no health regen, no second chances - just the gunfight.

![Version](https://img.shields.io/badge/version-__VERSION__-ff7a1a)
[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?logo=discord&logoColor=white)](https://discord.gg/blackops)
[![Website](https://img.shields.io/badge/web-gunfight.us-2ea44f)](https://gunfight.us)

</div>

---

## About

**Black Ops Gunfight** is a custom multiplayer game mode for **Call of Duty: Black Ops 1**, running on the **Plutonium T5** client. Two teams, **one life each per round**, and the **same randomized loadout** for everyone - rounds are won by gunskill, not classes or streaks. First team to **6 rounds** wins.

Made by **KL9**. Come play on **[Discord](https://discord.gg/blackops)**.

## Install & play

Plutonium has **no automatic mod download** - every player (and the server) installs the mod locally and must run the **same version**, or you get no HUD, text, or effects.

1. Download `mp_gunfight` from [Releases](https://github.com/KL9modz/BO1-Gunfight/releases).
2. Extract so the folder is `%localappdata%\Plutonium\storage\t5\mods\mp_gunfight` (keep the name).
3. Launch Black Ops 1 multiplayer -> **Mods** -> load **mp_gunfight** -> **Server Browser** -> join **Gunfight**.

> T5 has no direct IP connect - find the server in the in-game browser by name. Your version must match the server's.

Full walkthrough (graphics, FOV, the aim-while-sprinting fix, troubleshooting): **[docs/SETUP.md](docs/SETUP.md)**.

## More

- **Setup guide:** [docs/SETUP.md](docs/SETUP.md)
- **Technical reference:** [REFERENCE.md (on main)](https://github.com/KL9modz/BO1-Gunfight/blob/main/docs/REFERENCE.md)
- **Developer guide:** [DEV.md (on main)](https://github.com/KL9modz/BO1-Gunfight/blob/main/docs/DEV.md)
- **Full source & development:** the [`main`](https://github.com/KL9modz/BO1-Gunfight/tree/main) branch
- **Discord:** https://discord.gg/blackops   |   **Website:** https://gunfight.us

---

<sub>Version __VERSION__. Black Ops Gunfight is a fan-made, non-commercial game mode, not affiliated with or endorsed by Activision or Treyarch. Requires a legitimate copy of Call of Duty: Black Ops and the Plutonium client.</sub>
'@ -replace '__VERSION__', $Version
    [System.IO.File]::WriteAllText((Join-Path $StageMod "README.md"), $readme, $Utf8NoBom)

    $commentNote = if ($KeepComments) { "comments kept" } else { "comments stripped" }
    Write-Host ("  staged {0} gameplay GSC file(s) + {1} doc(s); excluded {2} dev file(s); {3}" -f $n, $docCount, $DevFiles.Count, $commentNote)
}

# -- Resolve paths ------------------------------------------------------------
$ModRoot = $WorkspaceRoot
$ModFf = Join-Path $ModRoot "mod.ff"
$DistDir = Join-Path $WorkspaceRoot "tools\dist"
$StageMod = Join-Path $DistDir "stage\$ModName"
$ZipPath = Join-Path $DistDir "$ModName-$Version.zip"

Write-Host "Packaging $ModName release"
Write-Host "Version: $Version"
Write-Host "Mod:     $ModRoot"

# -- Build mod.ff -------------------------------------------------------------
if (-not $SkipBuild) {
    $buildScript = Join-Path $PSScriptRoot "build_ff.ps1"
    if (!(Test-Path -LiteralPath $buildScript)) { throw "build_ff.ps1 not found: $buildScript" }
    Write-Host ""
    Write-Host "Building mod.ff ..."
    & $buildScript -GameRoot $GameRoot -ModName $ModName
    if ($LASTEXITCODE -ne 0) { throw "build_ff.ps1 failed (exit $LASTEXITCODE)" }
}
if (!(Test-Path -LiteralPath $ModFf)) { throw "mod.ff not found (build it first): $ModFf" }

# -- Stage + zip --------------------------------------------------------------
Write-Host ""
Build-Staging $StageMod
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -Force -LiteralPath $ZipPath }
Compress-Archive -Path $StageMod -DestinationPath $ZipPath -Force
$zip = Get-Item -LiteralPath $ZipPath
Write-Host ("Zip:    {0} ({1} KB)" -f $zip.FullName, [math]::Round($zip.Length / 1KB, 1))

# -- Optional: publish 'release' branch (same content as the zip) -------------
# Force-pushed as a single orphan commit (mod.ff included) so history never
# accumulates binaries. Temp index + git plumbing -> working tree untouched.
if ($PublishBranch) {
    Write-Host ""
    Write-Host "Publishing snapshot to orphan branch '$ReleaseBranch' ..."
    # Native git can write warnings to stderr (e.g. "LF will be replaced by CRLF"),
    # which under ErrorActionPreference=Stop are promoted to a TERMINATING error and
    # abort the publish before the push. Real failures are still caught by the
    # explicit $LASTEXITCODE checks + throw below, so relax to Continue here.
    $ErrorActionPreference = 'Continue'
    $tmpIndex = Join-Path ([System.IO.Path]::GetTempPath()) ("gf_relidx_" + [System.Guid]::NewGuid().ToString("N"))
    $prevIndex = $env:GIT_INDEX_FILE
    try {
        $env:GIT_INDEX_FILE = $tmpIndex
        & git -C $WorkspaceRoot read-tree --empty
        if ($LASTEXITCODE -ne 0) { throw "git read-tree failed" }
        & git -C $WorkspaceRoot --work-tree=$StageMod add --force --all
        if ($LASTEXITCODE -ne 0) { throw "git add (snapshot) failed" }
        $tree = (& git -C $WorkspaceRoot write-tree).Trim()
        if (-not $tree) { throw "git write-tree produced no tree" }
        $commit = (& git -C $WorkspaceRoot commit-tree $tree -m "Release $Version (clean snapshot)").Trim()
        if (-not $commit) { throw "git commit-tree produced no commit" }
        $refspec = $commit + ":refs/heads/" + $ReleaseBranch
        & git -C $WorkspaceRoot push -f origin $refspec
        if ($LASTEXITCODE -ne 0) { throw "git push to '$ReleaseBranch' failed" }
        Write-Host "Published branch '$ReleaseBranch' -> $commit"
    }
    finally {
        if ($null -ne $prevIndex) { $env:GIT_INDEX_FILE = $prevIndex }
        else { Remove-Item env:GIT_INDEX_FILE -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $tmpIndex) { Remove-Item -Force -LiteralPath $tmpIndex }
    }
}

# -- Optional GitHub Release --------------------------------------------------
if ($Publish) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "gh CLI not found; cannot publish. Install GitHub CLI or omit -Publish."
    }
    Write-Host ""
    Write-Host "Publishing GitHub Release '$Version' ..."
    # gh writes progress to stderr; relax to Continue so it isn't promoted to a
    # terminating error (the $LASTEXITCODE check below still catches real failures).
    $ErrorActionPreference = 'Continue'
    & gh release create $Version $ZipPath --target $ReleaseBranch --title "$ModName $Version" --notes "Gunfight $Version. Install: extract into ...\storage\t5\mods\ then 'loadMod mp_gunfight'. See README.md."
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed (exit $LASTEXITCODE)" }
    Write-Host "Published."
}
else {
    Write-Host ""
    Write-Host "Not published. GitHub Release: re-run with -Publish (or run gh release create $Version manually)."
}
