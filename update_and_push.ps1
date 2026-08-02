param(
    [string]$NewVersion,
    [switch]$Release,
    [switch]$NoTag
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$mainBranch = "main"

function Assert-LastExitCode {
    param([string]$Message)

    if ($LASTEXITCODE -ne 0) {
        throw $Message
    }
}

if ($Release -and $NoTag) {
    throw "Use either -Release or -NoTag, not both."
}

$originalBranch = (& git branch --show-current | Out-String).Trim()
Assert-LastExitCode "git branch --show-current failed."
if (-not $originalBranch) {
    throw "Unable to determine the current branch. Switch to a branch before running this script."
}

$tocPath = Join-Path $PSScriptRoot "LootViewer.toc"
$toc = Get-Content -LiteralPath $tocPath -Raw
if ($toc -notmatch '(?m)^## Version:\s*(\d+)\.(\d+)\.(\d+)(?:[^\r\n]*)$') {
    throw "Could not find a semantic ## Version value in LootViewer.toc."
}

$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$patch = [int]$Matches[3]
$currentVersion = "$major.$minor.$patch"

if ($NewVersion) {
    if ($NewVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version must use major.minor.patch format (for example, 1.2.0)."
    }
    $version = $NewVersion
}
else {
    $patch++
    $version = "$major.$minor.$patch"
}

$tag = "v$version"
$shouldTag = -not $NoTag -and ($Release -or $originalBranch -eq $mainBranch)

Write-Host "Current branch: $originalBranch"
Write-Host "Updating version: $currentVersion -> $version"
Write-Host ("Release tagging: " + ($(if ($shouldTag) { "enabled" } else { "disabled" })))

$toc = $toc -replace '(?m)^## Version:\s*[^\r\n]+$', "## Version: $version"
Set-Content -LiteralPath $tocPath -Value $toc -NoNewline

& (Join-Path $PSScriptRoot "verify.ps1")

& git add -A
Assert-LastExitCode "git add -A failed."

& git diff --cached --quiet
$hasStagedChanges = $LASTEXITCODE -ne 0
if ($hasStagedChanges) {
    & git commit -m "Update version $tag"
    Assert-LastExitCode "git commit failed."
}
else {
    Write-Host "No staged changes detected. Reusing the current HEAD commit."
}

& git push origin $originalBranch
Assert-LastExitCode "git push origin $originalBranch failed."

if (-not $shouldTag) {
    Write-Host "Done. Pushed '$originalBranch' without creating a release tag."
    return
}

$switchedBranches = $false
try {
    if ($originalBranch -ne $mainBranch) {
        & git checkout $mainBranch
        Assert-LastExitCode "git checkout $mainBranch failed."
        $switchedBranches = $true

        & git pull --ff-only origin $mainBranch
        Assert-LastExitCode "git pull --ff-only origin $mainBranch failed."

        & git merge --ff-only $originalBranch
        if ($LASTEXITCODE -ne 0) {
            throw "git merge --ff-only $originalBranch failed. Rebase or merge first, then rerun with -Release."
        }
    }

    & git push origin $mainBranch
    Assert-LastExitCode "git push origin $mainBranch failed."

    & git tag -a $tag -m "Release $tag"
    Assert-LastExitCode "git tag failed."

    & git push origin $tag
    Assert-LastExitCode "git push origin $tag failed."
}
finally {
    if ($switchedBranches -and $originalBranch -ne $mainBranch) {
        & git checkout $originalBranch | Out-Null
    }
}

Write-Host "Published release tag $tag." -ForegroundColor Green
