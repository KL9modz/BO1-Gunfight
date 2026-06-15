param(
    [Parameter(Position = 0)][string]$Message,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"

# Stage every change in the repo, commit, and push the current branch.
# Usage:
#   tools\push_all.ps1                         # auto timestamped message
#   tools\push_all.ps1 "Tune perk values"      # custom message
#   tools\push_all.ps1 "WIP" -NoPush           # commit only, don't push

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & git -C $RepoRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed (exit $LASTEXITCODE)"
    }
    return $output
}

# Confirm this is a git repo.
& git -C $RepoRoot rev-parse --is-inside-work-tree > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Not a git repository: $RepoRoot"
}

$branch = (Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")).Trim()
Write-Host "Repo:   $RepoRoot"
Write-Host "Branch: $branch"

# Stage everything (new, modified, deleted).
Invoke-Git @("add", "-A") | Out-Null

# Anything staged?
& git -C $RepoRoot diff --cached --quiet
$hasStaged = ($LASTEXITCODE -ne 0)

if ($hasStaged) {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Update " + (Get-Date -Format "yyyy-MM-dd HH:mm")
    }

    # Write the message to a temp file so quotes/newlines survive intact.
    $msgFile = Join-Path ([System.IO.Path]::GetTempPath()) ("gf_commit_" + [System.Guid]::NewGuid().ToString("N") + ".txt")
    try {
        # UTF-8 without BOM — Set-Content -Encoding utf8 (PS 5.1) prepends a BOM
        # that ends up inside the commit message.
        [System.IO.File]::WriteAllText($msgFile, $Message, (New-Object System.Text.UTF8Encoding($false)))
        Invoke-Git @("commit", "-F", $msgFile)
    }
    finally {
        if (Test-Path -LiteralPath $msgFile) { Remove-Item -Force -LiteralPath $msgFile }
    }
    Write-Host "Committed: $Message"
}
else {
    Write-Host "Nothing to commit."
}

if ($NoPush) {
    Write-Host "Skipping push (-NoPush)."
    return
}

# Push even when there was nothing new to commit, in case earlier commits are unpushed.
$pushArgs = @("push")
& git -C $RepoRoot rev-parse --abbrev-ref --symbolic-full-name "@{u}" > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    # No upstream configured yet — set it on first push.
    $pushArgs = @("push", "-u", "origin", $branch)
}

Invoke-Git $pushArgs
Write-Host "Pushed $branch."
