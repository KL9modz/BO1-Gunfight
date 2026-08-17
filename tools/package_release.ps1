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
# What ships: mod.ff + the gameplay GSC under maps/ + a generated README.md.
# What is dropped: the $DevFiles in release_common.ps1 (bots, RCON bridge, debug), and any
# dev wiring wrapped in markers:
#     // #strip-begin ... // #strip-end
# (markers are inert // comments on main, so the dev build is unaffected).
#
# The result is a STRIPPED-DOWN Gunfight: the gameplay is identical to what the VPS runs
# (rounds, shared rotating loadouts, overtime + capture zone, auto large/small team-size
# mode, curated spawns, damage scoring, menu HUD), but none of the dev/ops machinery ships
# -- no pregame warmup, no lobby/load-gate hold, no bots, no RCON bridge, no debug tooling,
# and none of their dvars. A public server owner still gets the core admin knobs
# (scorelimit / timelimit / overtimelimit / roundswitch / roundsperloadout / teamspawnmode /
# capture_time / flinch / team_maxsize).
#
# Two PUBLISH GUARDS (release_common.ps1) run over the STAGED output before anything is
# zipped or force-pushed, because the zip and the 'release' branch are the most public
# things this repo produces: no public IP literal / pasted `status` roster row, and no
# gitignored per-box store. The IP rule is the intentional twin of tools/hooks/pre-commit
# section 4 -- same excluded ranges, same `ip-ok` marker, same ip-allow.txt.
#
# tools\verify_release_strip.ps1 statically proves the staged GSC still resolves -- run it
# after touching ANY strip region. A region that removes a function some KEPT code still
# calls is an "unknown function" compile error that kills the whole server, and it will not
# show up until a client actually connects.
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

# $DevFiles (what's dropped outright) and Strip-Markers (what's cut from the files that
# DO ship) live in release_common.ps1 so tools\verify_release_strip.ps1 checks the exact
# same build this script produces.
. (Join-Path $PSScriptRoot "release_common.ps1")
. (Join-Path $PSScriptRoot "common.ps1")   # Invoke-BuildFf (shared with package_server.ps1)

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

    # ⚠ THE .iwd IS NOT OPTIONAL -- mod.ff alone ships VISIBLY BROKEN guns.
    # The linker never embeds image pixels, so mod.ff carries the camo table (weaponOptions rows
    # 17-46) and 30 carrier materials that reference images BY NAME. Without the .iwd beside it
    # those names resolve to nothing and the engine renders the missing texture as FLAT WHITE --
    # and gf_camoPool() is deliberately NOT strip-marked, so the public build rolls custom camos
    # like the VPS does (~45% of rolls). Shipping mod.ff without this file is the one packaging
    # mistake that reaches every public server at once.
    # Always rebuilt (never -SkipBuild'd): it is a ~1 MB zip of tracked sources, and a stale copy
    # would silently omit a camo added since.
    & (Join-Path $PSScriptRoot "make_iwd.ps1") -ModRoot $ModRoot -Verify
    if ($LASTEXITCODE -ne 0) { throw "make_iwd.ps1 failed -- refusing to ship a release whose camos would render white" }
    # make_iwd falls back to '<name>.new' when a RUNNING game holds the .iwd open, so take that
    # copy when it exists -- it is the fresh one.
    $iwdSrc = Join-Path $ModRoot "mp_gunfight.iwd.new"
    if (-not (Test-Path -LiteralPath $iwdSrc)) { $iwdSrc = Join-Path $ModRoot "mp_gunfight.iwd" }
    if (-not (Test-Path -LiteralPath $iwdSrc)) { throw "mp_gunfight.iwd was not produced -- refusing to ship a release whose camos would render white" }
    Copy-Item -Force -LiteralPath $iwdSrc -Destination (Join-Path $StageMod "mp_gunfight.iwd")

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

    # Ship the Getting Started guide at the release ROOT (linked from the README).
    # It's authored under docs/ on main; here we relocate it to root and fix its
    # relative links: the parent README link -> sibling, and doc-relative image
    # paths -> absolute main-branch raw URLs. The image binaries are NOT shipped
    # (keeps the release minimal); they still render on the 'release' branch via
    # raw.githubusercontent, and the guide's text stands alone in the offline zip.
    $mainRaw = "https://raw.githubusercontent.com/KL9modz/BO1-Gunfight/main"
    $gs = [System.IO.File]::ReadAllText((Join-Path $ModRoot "docs\GETTING_STARTED.md"))
    $gs = $gs -replace '\]\(\.\./README\.md\)', '](README.md)'
    $gs = $gs -replace '\]\(images/getting-started/', "](${mainRaw}/docs/images/getting-started/"
    [System.IO.File]::WriteAllText((Join-Path $StageMod "GETTING_STARTED.md"), $gs, $Utf8NoBom)
    $docCount = 1

    # The 'release' branch is the GitHub DEFAULT branch, so its README is the repo's
    # public landing page. Derive it from main's README.md verbatim so the two never
    # drift - stamp the version badge, point the Getting Started link at the root copy
    # shipped above, and rewrite any OTHER relative docs/ links to absolute main-branch
    # URLs (the rest of docs/ - REFERENCE.md / DEV.md - is not shipped on 'release').
    $mainBlob = "https://github.com/KL9modz/BO1-Gunfight/blob/main"
    $readme = [System.IO.File]::ReadAllText((Join-Path $ModRoot "README.md"))
    $readme = $readme -replace '\]\(docs/GETTING_STARTED\.md\)', '](GETTING_STARTED.md)'
    $readme = $readme -replace '\]\(docs/', "](${mainBlob}/docs/"
    $readme = $readme -replace 'version-[^-)]+-ff7a1a', "version-$Version-ff7a1a"
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
Invoke-BuildFf -GameRoot $GameRoot -ModName $ModName -SkipBuild:$SkipBuild -ModFf $ModFf

# -- Stage + zip --------------------------------------------------------------
Write-Host ""
Build-Staging $StageMod

# -- Publish guards (see PUBLISH GUARDS in release_common.ps1) -----------------
# Scan the STAGE, not the source tree: staging is what actually ships, and it is post
# comment-strip, so a gamertag left in a GSC comment on main is already gone by here.
# Placed BEFORE the zip and before -PublishBranch so a hit blocks every public path.
#
# >>> The IP/PII rule is the intentional TWIN of tools/hooks/pre-commit section 4.
# >>> Change both or neither. A developer who satisfied the hook must never be blocked
# >>> here, which is why both read the same tools/hooks/ip-allow.txt and honour the same
# >>> `ip-ok` line marker.
Write-Host ""
Write-Host "Publish guard: scanning the stage for public IPs / player PII / box-local stores ..."
$leaks     = @(Find-LeakHits -Root $StageMod -AllowFile (Get-IpAllowFile $ModRoot))
$localOnly = @(Find-LocalOnlyFiles -Root $StageMod)
if ($leaks.Count -gt 0) {
    Write-Host "REFUSING TO PACKAGE - public IP / player PII in the staged public build:" -ForegroundColor Red
    $leaks | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "  -> if intentional: put 'ip-ok' in a comment on that line, or add the address" -ForegroundColor Red
    Write-Host "     to tools\hooks\ip-allow.txt (the SAME allowlist the pre-commit hook reads)." -ForegroundColor Red
}
if ($localOnly.Count -gt 0) {
    Write-Host "REFUSING TO PACKAGE - gitignored per-box store(s) reached the stage:" -ForegroundColor Red
    $localOnly | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}
if (($leaks.Count + $localOnly.Count) -gt 0) {
    throw "Release aborted: the zip and the 'release' branch are world-readable."
}
Write-Host "  clean (no public IP, no player PII, no box-local store)."

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
