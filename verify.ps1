$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$tocPath = Join-Path $root "LootViewer.toc"
$optionsTocPath = Join-Path $root "Options\LootViewer_Options.toc"
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
    "Core/OptionsLoader.lua"
    "Core/Guild.lua"
    "Core/Comms.lua"
    "Core/DataSync.lua"
    "Events/Raid.lua"
    "Events/Loot.lua"
    "Events/Dungeons.lua"
    "Events/Trade.lua"
    "UI/Widgets.lua"
    "UI/MainFrame.lua"
    "UI/HistoryMeters.lua"
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

$coreRuntimeLuaFiles = @(
    Get-ChildItem -LiteralPath $root -File -Filter '*.lua' -Recurse |
        ForEach-Object { $_.FullName.Substring($root.Length).TrimStart([char[]]'\/').Replace('\', '/') } |
        Where-Object { $_ -notmatch '^(dist|\.build|Options)/' } |
        Sort-Object
)
$unreferencedLua = @(Compare-Object -ReferenceObject ($expectedTocEntries | Sort-Object) -DifferenceObject $coreRuntimeLuaFiles)
if ($unreferencedLua.Count -gt 0) {
    $detail = ($unreferencedLua | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '
    throw "Lua source and TOC entries do not match: $detail"
}

$optionsTocText = Get-Content -LiteralPath $optionsTocPath -Raw
foreach ($pattern in @(
    '(?m)^## Interface:\s*120100,\s*120007\s*$',
    '(?m)^## Version:\s*12\.1\.2\s*$',
    '(?m)^## Dependencies:\s*LootViewer\s*$',
    '(?m)^## LoadOnDemand:\s*1\s*$'
)) {
    if ($optionsTocText -notmatch $pattern) {
        throw "LootViewer_Options.toc is missing required on-demand addon metadata."
    }
}
$optionsTocEntries = @(
    Get-Content -LiteralPath $optionsTocPath | ForEach-Object {
        $entry = $_.Trim()
        if ($entry -and -not $entry.StartsWith('#')) { $entry.Replace('\', '/') }
    }
)
if ($optionsTocEntries.Count -ne 1 -or $optionsTocEntries[0] -ne 'Configuration.lua') {
    throw "LootViewer_Options.toc has unexpected runtime files."
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
    $pkgmetaText -notmatch '(?m)^manual-changelog:\s*CHANGELOG\.md\s*$' -or
    $pkgmetaText -notmatch '(?m)^\s*LootViewer/Options:\s*LootViewer_Options\s*$') {
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
$constantsText = Get-Content -LiteralPath (Join-Path $root "Core\Constants.lua") -Raw
$utilText = Get-Content -LiteralPath (Join-Path $root "Core\Util.lua") -Raw
$dataSyncText = Get-Content -LiteralPath (Join-Path $root "Core\DataSync.lua") -Raw
$seasonText = Get-Content -LiteralPath (Join-Path $root "Core\Seasons.lua") -Raw
$tierText = Get-Content -LiteralPath (Join-Path $root "Core\Tier.lua") -Raw
$raidText = Get-Content -LiteralPath (Join-Path $root "Events\Raid.lua") -Raw
$lootText = Get-Content -LiteralPath (Join-Path $root "Events\Loot.lua") -Raw
$tradeText = Get-Content -LiteralPath (Join-Path $root "Events\Trade.lua") -Raw
$dungeonText = Get-Content -LiteralPath (Join-Path $root "Events\Dungeons.lua") -Raw
$uiText = Get-Content -LiteralPath (Join-Path $root "UI\MainFrame.lua") -Raw
$historyMeterText = Get-Content -LiteralPath (Join-Path $root "UI\HistoryMeters.lua") -Raw
$optionsText = Get-Content -LiteralPath (Join-Path $root "Options\Configuration.lua") -Raw
if ($storeText -notmatch 'LootViewerDB' -or $storeText -notmatch 'guild') {
    throw "Core/Store.lua no longer exposes the guild-scoped SavedVariables store."
}
if ($raidText -notmatch 'ENCOUNTER_' -or $lootText -notmatch 'LOOT_' -or $tradeText -notmatch 'TRADE_') {
    throw "Raid, loot, or trade event capture appears incomplete."
}
foreach ($seasonToken in @(
    'midnight-1', 'midnight-2', '20260812',
    'Sporefall', 'The Voidspire', "March on Quel'Danas", 'The Dreamrift',
    'The Venomous Abyss', 'The Tidebound Grotto',
    'Altar of Fangs', 'Den of Nalorakk', 'Murder Row', 'The Blinding Vale',
    'Voidscar Arena', "Kings' Rest", 'Ruby Life Pools', 'Temple of Sethraliss',
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
if ($raidText -notmatch 'ScheduleScheduledEnd' -or
    $raidText -notmatch 'ExpireScheduledSession' -or
    $optionsText -notmatch 'End Grace' -or
    $optionsText -notmatch 'Prompt Timeout' -or
    $optionsText -notmatch 'createRankRange' -or
    $optionsText -notmatch 'ShowConfirmationDialog' -or
    $optionsText -match 'Scheduled Raid Tier') {
    throw "Scheduled end grace, constrained timing controls, trusted-rank range, or confirmed pruning appear incomplete."
}
if ($utilText -notmatch 'GetServerTime' -or $raidText -notmatch 'session\.sst' -or $raidText -notmatch 'lateAnchor') {
    throw "Scheduled late attendance is no longer anchored to the configured raid start."
}
if ($utilText -notmatch 'NormalizeTimezone' -or
    $utilText -notmatch 'TimezoneWeekMinute' -or
    $raidText -notmatch 'teamWeekMinute' -or
    $optionsText -notmatch 'TIME ZONE' -or
    $optionsText -notmatch 'Exclude from Sync' -or
    $optionsText -notmatch '24-Hour Clock' -or
    $optionsText -notmatch 'createScheduleRange' -or
    $optionsText -notmatch '30-MINUTE SNAP' -or
    $optionsText -notmatch 'IconButton\(row, "copy"' -or
    $dataSyncText -notmatch 'excludedTeamIDs' -or
    $dataSyncText -notmatch 'EXCLUDED_REMOTE_RAID') {
    throw "Per-team time zones or local-only sync exclusion appear incomplete."
}
if ($storeText -notmatch 'GLOBAL_PUG_TEAM' -or
    $storeText -notmatch '197 / 255' -or
    $storeText -notmatch '198 / 255' -or
    $storeText -notmatch '199 / 255' -or
    $storeText -notmatch 'IsGlobalPugTeam' -or
    $dataSyncText -notmatch '\[LV\.Constants\.PUG_TEAM_ID\]\s*=\s*true' -or
    $optionsText -notmatch 'ACCOUNT-WIDE.*LOCAL ONLY' -or
    $uiText -notmatch 'PUG_TEAM_NAME') {
    throw "The reserved account-wide Pugs raid team or its forced local-only behavior appears incomplete."
}
if ($constantsText -notmatch 'autoPugRaids\s*=\s*false' -or
    $raidText -notmatch 'MaybeAutoStartPug' -or
    $raidText -notmatch 'IsWithinRaidHours' -or
    $raidText -notmatch 'IsGlobalPugTeam\(teamID\)' -or
    $optionsText -notmatch 'Auto Start Pug Raids' -or
    $uiText -notmatch 'attendanceTeamID' -or
    $uiText -notmatch 'historyTeamID' -or
    $uiText -notmatch 'EventMatchesRaidTag' -or
    $uiText -notmatch 'pugsSelected' -or
    $historyMeterText -notmatch 'EventMatchesRaidTag') {
    throw "Automatic Pugs tracking, authority bypass, meter behavior, or raid-tag history filters appear incomplete."
}
if ($uiText -notmatch 'CreateHistoryDifficultySlider' -or
    $uiText -notmatch 'Minimum Difficulty' -or
    $uiText -notmatch 'EventMeetsMinimumDifficulty' -or
    $uiText -notmatch 'Loot Filters' -or
    $historyMeterText -notmatch 'lfr\s*=\s*\{\s*0\.46' -or
    $historyMeterText -notmatch 'difficulty\s*==\s*"L"' -or
    $historyMeterText -notmatch 'RaidDifficultyBuckets') {
    throw "The Loot History filter panel, minimum-difficulty threshold, or gray LFR distribution segment appears incomplete."
}
if ($uiText -notmatch '\[250\]\s*=\s*"Raid Finder"' -or
    $uiText -notmatch 'difficultyID\s*==\s*250' -or
    $uiText -notmatch 'value\s*==\s*"world"') {
    throw "Retail 12.1 World difficulty is no longer normalized to LFR."
}
if ($uiText -notmatch 'lootExclusionPromptAccepted' -or
    $uiText -notmatch 'You will not be prompted again for exclusions' -or
    $uiText -notmatch 'ShowConfirmationDialog' -or
    $uiText -notmatch 'confirmationModal:Hide\(\)') {
    throw "The per-window loot-exclusion confirmation or reset behavior appears incomplete."
}
if ($seasonText -notmatch 'for month = 1, 6 do' -or
    $seasonText -notmatch 'Entire Selected Season' -or
    $uiText -notmatch 'attendanceSeason' -or
    $uiText -notmatch 'meterRange' -or
    $uiText -notmatch 'historySeason' -or
    $uiText -notmatch 'RenderTierHistory' -or
    $uiText -notmatch 'No tier tokens defined for this season') {
    throw "Season filters or the 1-6 month attendance ranges appear incomplete."
}
if ($dungeonText -notmatch 'CHALLENGE_MODE_COMPLETED' -or
    $dungeonText -notmatch 'BONUS_ROLL_RESULT' -or
    $dungeonText -notmatch 'specID' -or
    $historyMeterText -notmatch 'Champion \(0-5\)' -or
    $historyMeterText -notmatch 'Hero \(6-10\)' -or
    $historyMeterText -notmatch 'Myth \(Bonus Roll\)' -or
    $optionsText -notmatch 'Enable Dungeon Logging') {
    throw "Dungeon logging, bonus-roll capture, or dungeon history UI appears incomplete."
}
if ($seasonText -notmatch 'DungeonFilterValues' -or
    $historyMeterText -notmatch 'CreateDungeonTrackSlider' -or
    $historyMeterText -notmatch 'Bonus Rolls' -or
    $historyMeterText -notmatch 'dungeonHistoryFilter' -or
    $uiText -notmatch 'Raid Information' -or
    $uiText -notmatch 'Bosses Killed' -or
    $uiText -notmatch 'CreateHistoryDateDisplay' -or
    $uiText -notmatch 'Raid hours:' -or
    $uiText -notmatch 'iconOnly') {
    throw "Dungeon distribution filters, raid detail context, or the formatted Recent loot table appears incomplete."
}
if ($tradeText -notmatch 'RecordManualTrade' -or
    $tradeText -notmatch 'sourceLootID' -or
    $tradeText -notmatch 'parts\[7\]' -or
    $uiText -notmatch 'ShowLootItemActions' -or
    $uiText -notmatch 'RaidLootRecipientValues' -or
    $uiText -notmatch 'Trade Item' -or
    $uiText -notmatch 'Exclude Loot' -or
    $historyMeterText -notmatch '#entries / maxTotal' -or
    $historyMeterText -notmatch 'maxTotal = math\.max') {
    throw "Manual per-loot trade options or proportional Distribution meter scaling appears incomplete."
}
if ($uiText -notmatch 'HistoryFilterPreference' -or
    $uiText -notmatch 'raidMinDifficulty' -or
    $historyMeterText -notmatch 'dungeonMinTrack' -or
    $uiText -notmatch 'SetHistoryFilterPreference' -or
    $historyMeterText -notmatch 'SetHistoryFilterPreference') {
    throw "Saved raid or dungeon loot-level filter preferences appear incomplete."
}
if ($uiText -notmatch 'CreateHistoryColumnHeader\(parent, "Roll"' -or
    $uiText -notmatch 'local methodWidth = 40') {
    throw "The Recent Loot History Roll column label or width appears incomplete."
}
if ($uiText -notmatch 'CreateHistoryColumnHeader\(parent, "Owner"' -or
    $uiText -notmatch 'Final owner after trade' -or
    $uiText -notmatch 'Originally looted by' -or
    $uiText -notmatch 'finalOwner') {
    throw "Recent Loot History no longer appears to resolve and explain final ownership after trades."
}
if ($uiText -notmatch 'Initiated By' -or
    $uiText -notmatch 'row\.src == "manual"' -or
    $uiText -notmatch '"Detected"' -or
    $tradeText -notmatch 'receivedRemote' -or
    $tradeText -notmatch 'row\.src or "observed"' -or
    $tradeText -notmatch 'parts\[8\] == "manual"' -or
    $tradeText -notmatch 'parts\[9\]') {
    throw "Trade initiation metadata or the Trades Initiated By column appears incomplete."
}
if ($uiText -notmatch 'CanModifyHistoricalRaid' -or
    $uiText -notmatch 'IsGlobalPugTeam\(raid\.team\)' -or
    $uiText -notmatch 'MoveHistoricalRaidToTeam' -or
    $uiText -notmatch 'ui_team_move' -or
    $uiText -notmatch 'Raid Team' -or
    $uiText -notmatch 'Attendance, kills, loot, and trades remain linked') {
    throw "Pugs historical-edit bypass or linked raid-team reassignment appears incomplete."
}
if ($uiText -notmatch 'Delete Raid Attendance\?' -or
    $uiText -notmatch 'self:ShowConfirmationDialog' -or
    $uiText -match 'StaticPopup_Show\(LV\.Constants\.DELETE_RAID_PROMPT') {
    throw "Raid deletion no longer appears to use LootViewer's foreground confirmation modal."
}

$deployPath = Join-Path $root "deploy.ps1"
if (Test-Path -LiteralPath $deployPath -PathType Leaf) {
    & $deployPath -WhatIf
}

Write-Host "LootViewer static verification passed." -ForegroundColor Green
