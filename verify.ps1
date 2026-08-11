$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$tocPath = Join-Path $root "LootViewer.toc"
if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
    throw "Missing LootViewer.toc."
}

$tocText = Get-Content -LiteralPath $tocPath -Raw
if ($tocText -notmatch '(?m)^## Interface:\s*120100,\s*120007\s*$') {
    throw "LootViewer.toc is not targeting Retail interfaces 120100 and 120007."
}
if ($tocText -notmatch '(?m)^## Title:\s*LootViewer\s*$') {
    throw "LootViewer.toc has an unexpected title."
}
if ($tocText -notmatch '(?m)^## Version:\s*(\d+\.\d+\.\d+)\s*$') {
    throw "LootViewer.toc does not contain a semantic version."
}
$tocVersion = $Matches[1]
$runtimeText = Get-Content -LiteralPath (Join-Path $root "LootViewer.lua") -Raw
if ($runtimeText -notmatch '(?m)^LV\.version\s*=\s*"(\d+\.\d+\.\d+)"\s*$') {
    throw "LootViewer.lua does not contain a semantic LV.version value."
}
if ($Matches[1] -ne $tocVersion) {
    throw "LootViewer.toc version $tocVersion does not match LootViewer.lua version $($Matches[1])."
}
if ($tocText -notmatch '(?m)^## SavedVariables:\s*LootViewerDB\s*$') {
    throw "LootViewer.toc does not declare LootViewerDB."
}
if ($tocText -match '(?m)^## X-Curse-Project-ID:\s*(\S+)\s*$') {
    if ($Matches[1] -notmatch '^\d+$') {
        throw "X-Curse-Project-ID must be numeric."
    }
}
else {
    Write-Warning "X-Curse-Project-ID is not configured; CurseForge upload will remain disabled until the project is created."
}

$expectedTocEntries = @(
    "LootViewer.lua"
    "Core/Constants.lua"
    "Core/Util.lua"
    "Core/Seasons.lua"
    "Core/Tier.lua"
    "Core/Store.lua"
    "Core/Guild.lua"
    "Core/Comms.lua"
    "Core/DataSync.lua"
    "Events/Raid.lua"
    "Events/Loot.lua"
    "Events/Trade.lua"
    "UI/Widgets.lua"
    "UI/MainFrame.lua"
    "UI/GuildOverlay.lua"
)
$tocEntries = @(
    Get-Content -LiteralPath $tocPath | ForEach-Object {
        $entry = $_.Trim()
        if ($entry -and -not $entry.StartsWith('#')) {
            $entry.Replace('\', '/')
        }
    }
)

$tocDifferences = @(Compare-Object -ReferenceObject $expectedTocEntries -DifferenceObject $tocEntries -SyncWindow 0)
if ($tocDifferences.Count -gt 0) {
    $detail = ($tocDifferences | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '
    throw "LootViewer.toc runtime order changed unexpectedly: $detail"
}

$missing = @()
foreach ($entry in $tocEntries) {
    $relativePath = $entry -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        $missing += $entry
    }
}
if ($missing.Count -gt 0) {
    throw "TOC references missing files: $($missing -join ', ')"
}

$runtimeLuaFiles = @(
    Get-ChildItem -LiteralPath $root -File -Filter '*.lua' -Recurse |
        ForEach-Object { $_.FullName.Substring($root.Length).TrimStart([char[]]'\/').Replace('\', '/') } |
        Where-Object { $_ -notmatch '^(dist|\.build)/' } |
        Sort-Object
)
$unreferencedLua = @(Compare-Object -ReferenceObject ($expectedTocEntries | Sort-Object) -DifferenceObject $runtimeLuaFiles)
if ($unreferencedLua.Count -gt 0) {
    $detail = ($unreferencedLua | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '
    throw "Lua source and TOC entries do not match: $detail"
}

foreach ($runtimeFile in (Get-ChildItem -LiteralPath $root -File -Filter '*.lua' -Recurse)) {
    $firstLine = Get-Content -LiteralPath $runtimeFile.FullName -TotalCount 1
    if ($firstLine -match '^(Exit code:|Wall time:|Output:|Script (completed|failed))') {
        throw "Tool transcript text was prepended to Lua source at $($runtimeFile.FullName):1"
    }
}

$requiredFiles = @(
    ".pkgmeta"
    ".github/workflows/release.yml"
    "AGENTS.md"
    "CHANGELOG.md"
    "README.md"
    "build.ps1"
    "verify.ps1"
    "update_and_push.ps1"
)
foreach ($entry in $requiredFiles) {
    $relativePath = $entry -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "Standalone repository is missing $entry."
    }
}

$forbiddenWebEntries = @(
    "app.py", "server.py", "Dockerfile", "docker-compose.yml",
    "templates", "static", "syncer", "data", "models"
)
foreach ($entry in $forbiddenWebEntries) {
    if (Test-Path -LiteralPath (Join-Path $root $entry)) {
        throw "Web application entry '$entry' must not be present in the standalone addon repository."
    }
}

$pkgmetaText = Get-Content -LiteralPath (Join-Path $root ".pkgmeta") -Raw
if ($pkgmetaText -notmatch '(?m)^package-as:\s*LootViewer\s*$' -or
    $pkgmetaText -notmatch '(?m)^manual-changelog:\s*CHANGELOG\.md\s*$') {
    throw ".pkgmeta is missing the LootViewer package name or changelog configuration."
}
foreach ($ignoredEntry in @('AGENTS.md', 'Docs', 'README.md', 'build.ps1', 'deploy.ps1', 'update_and_push.ps1', 'verify.ps1')) {
    if ($pkgmetaText -notmatch "(?m)^\s*-\s+$([regex]::Escape($ignoredEntry))\s*$") {
        throw ".pkgmeta does not exclude $ignoredEntry from release packages."
    }
}

$releaseWorkflowText = Get-Content -LiteralPath (Join-Path $root ".github\workflows\release.yml") -Raw
if ($releaseWorkflowText -notmatch 'BigWigsMods/packager@v2' -or
    $releaseWorkflowText -notmatch 'args:\s*-g retail' -or
    $releaseWorkflowText -notmatch 'CF_API_KEY' -or
    $releaseWorkflowText -notmatch 'tags:[\s\S]*?"v\*"') {
    throw "GitHub release workflow is not configured for tagged Retail CurseForge releases."
}

$storeText = Get-Content -LiteralPath (Join-Path $root "Core\Store.lua") -Raw
$utilText = Get-Content -LiteralPath (Join-Path $root "Core\Util.lua") -Raw
$seasonText = Get-Content -LiteralPath (Join-Path $root "Core\Seasons.lua") -Raw
$tierText = Get-Content -LiteralPath (Join-Path $root "Core\Tier.lua") -Raw
$raidText = Get-Content -LiteralPath (Join-Path $root "Events\Raid.lua") -Raw
$lootText = Get-Content -LiteralPath (Join-Path $root "Events\Loot.lua") -Raw
$tradeText = Get-Content -LiteralPath (Join-Path $root "Events\Trade.lua") -Raw
$uiText = Get-Content -LiteralPath (Join-Path $root "UI\MainFrame.lua") -Raw
if ($storeText -notmatch 'LootViewerDB' -or $storeText -notmatch 'guild') {
    throw "Core/Store.lua no longer exposes the guild-scoped SavedVariables store."
}
if ($raidText -notmatch 'ENCOUNTER_' -or $lootText -notmatch 'LOOT_' -or $tradeText -notmatch 'TRADE_') {
    throw "Raid, loot, or trade event capture appears incomplete."
}
foreach ($seasonToken in @(
    'midnight-1', 'midnight-2', '20260817',
    'Sporefall', 'The Voidspire', "March on Quel'Danas", 'The Dreamrift',
    'The Venomous Abyss', 'The Tidebound Grotto',
    '1592', '2912', '2913', '2939', '2987', '3004'
)) {
    if ($seasonText -notmatch [regex]::Escape($seasonToken)) {
        throw "Core/Seasons.lua is missing expected tier data: $seasonToken"
    }
}
foreach ($tierItemID in 270909..270929) {
    if ($tierText -notmatch "itemID\s*=\s*$tierItemID") {
        throw "Core/Tier.lua is missing Midnight Season 2 tier item ID: $tierItemID"
    }
}
if ($tierText -notmatch 'seasonCatalogs' -or $tierText -notmatch 'HasDefinitions') {
    throw "Core/Tier.lua no longer stores tier token definitions by season."
}
foreach ($tierToken in @(
    'Slumbering Coil Curio', 'Venomwoven', 'Venomcured', 'Venomcast', 'Venomforged',
    'Head', 'Chest', 'Hands', 'Legs', 'Shoulders'
)) {
    if ($tierText -notmatch [regex]::Escape($tierToken)) {
        throw "Core/Tier.lua is missing expected tier token data: $tierToken"
    }
}
if ($raidText -notmatch 'InGuildParty' -or $raidText -notmatch 'TrackingSeasonID') {
    throw "Scheduled raid prompts are no longer restricted to the active guild tier."
}
if ($utilText -notmatch 'GetServerTime' -or $raidText -notmatch 'session\.sst' -or $raidText -notmatch 'lateAnchor') {
    throw "Scheduled late attendance is no longer anchored to the server-time raid start."
}
if ($seasonText -notmatch 'for month = 1, 6 do' -or
    $seasonText -notmatch 'RaidSeasonID\(guildKey, raid\) == self:CurrentSeasonID\(\)' -or
    $uiText -notmatch 'attendanceSeason' -or
    $uiText -notmatch 'meterRange' -or
    $uiText -notmatch 'historySeason' -or
    $uiText -notmatch 'RenderTierHistory' -or
    $uiText -notmatch 'No tier tokens defined for this season') {
    throw "Season filters or the 1-6 month attendance ranges appear incomplete."
}

$deployPath = Join-Path $root "deploy.ps1"
if (Test-Path -LiteralPath $deployPath -PathType Leaf) {
    & $deployPath -WhatIf
}

Write-Host "LootViewer static verification passed." -ForegroundColor Green
