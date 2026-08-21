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
if ($tocText -notmatch '(?m)^## Version:\s*(\d+\.\d+\.\d+(?:-\d+)?)\s*$') {
    throw "LootViewer.toc does not contain a semantic version with an optional numeric prerelease suffix."
}
$tocVersion = $Matches[1]
$runtimeText = Get-Content -LiteralPath (Join-Path $root "LootViewer.lua") -Raw
if ($runtimeText -notmatch '(?m)^LV\.version\s*=\s*"(\d+\.\d+\.\d+(?:-\d+)?)"\s*$') {
    throw "LootViewer.lua does not contain a semantic LV.version value with an optional numeric prerelease suffix."
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
    '(?m)^## Dependencies:\s*LootViewer\s*$',
    '(?m)^## LoadOnDemand:\s*1\s*$'
)) {
    if ($optionsTocText -notmatch $pattern) {
        throw "LootViewer_Options.toc is missing required on-demand addon metadata."
    }
}
if ($optionsTocText -notmatch "(?m)^## Version:\s*$([regex]::Escape($tocVersion))\s*$") {
    throw "LootViewer_Options.toc version does not match LootViewer.toc version $tocVersion."
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
$guildText = Get-Content -LiteralPath (Join-Path $root "Core\Guild.lua") -Raw
$commsText = Get-Content -LiteralPath (Join-Path $root "Core\Comms.lua") -Raw
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
if ($lootText -notmatch 'function LV\.Loot:LootHistoryKey' -or
    $lootText -notmatch 'function LV\.Loot:FindLootHistoryDuplicate' -or
    $lootText -notmatch 'duplicate\.lh\s*=\s*duplicate\.lh\s+or\s+row\.lh' -or
    $lootText -notmatch 'wantedEncounterID\s*=\s*tonumber\(wantedEncounterID\)\s+or\s+self:CurrentOrLastEncounterID\(\)' -or
    $lootText -notmatch 'info\.lootHistoryKey\s*=\s*self:LootHistoryKey') {
    throw "Loot-history rescans no longer have stable per-drop deduplication or encounter scoping."
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
if ($tierText -notmatch 'function LV\.Tier:GroupTypeForRow' -or
    $tierText -notmatch 'MAGE\s*=\s*"cloth"' -or
    $tierText -notmatch 'SHAMAN\s*=\s*"mail"' -or
    $tierText -notmatch 'WARRIOR\s*=\s*"plate"' -or
    $uiText -notmatch 'groupType\s*=\s*token\s+and\s+LV\.Tier:GroupTypeForRow') {
    throw "Curio tier tokens no longer group under the winner's armor class."
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
if ($dataSyncText -notmatch 'SYNC_PROTOCOL_VERSION\s*=\s*2' -or
    $dataSyncText -notmatch 'function LV\.DataSync:BeginReturnChunkSend' -or
    $dataSyncText -notmatch 'SendWhisper\("M"' -or
    $dataSyncText -notmatch 'kind\s*==\s*"M"' -or
    $dataSyncText -notmatch 'configState\.existingTeams' -or
    $dataSyncText -notmatch 'preserveConfig\s*=\s*true' -or
    $dataSyncText -notmatch 'Two-way sync complete' -or
    $uiText -notmatch 'Two-Way Guild Merge') {
    throw "Manual sync no longer performs a backward-compatible two-way raid merge with additive teams."
}
if ($dataSyncText -notmatch 'line\("XI"' -or
    $dataSyncText -notmatch 'function LV\.DataSync:ImportLootItemExclusion' -or
    $dataSyncText -notmatch 'kind\s*==\s*"XI"' -or
    $dataSyncText -notmatch 'counts\.exclusions' -or
    $lootText -notmatch 'IsLootItemExclusionEnabled' -or
    $lootText -notmatch 'enabled\s*=\s*0' -or
    $lootText -notmatch 'ts\s*=\s*LV\.Util:Now\(\)') {
    throw "Manual sync no longer merges excluded-item rules and undo tombstones."
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
if ($guildText -notmatch 'ParseAuthorityDirective' -or
    $guildText -notmatch 'C_Club\.GetGuildClubId' -or
    $guildText -notmatch 'C_Club\.GetClubInfo' -or
    $guildText -notmatch 'ScanAuthorityDirective' -or
    $guildText -match 'GetGuildInfoText' -or
    $guildText -notmatch 'EffectiveAuthority' -or
    $guildText -notmatch 'lootviewer%s\+authority' -or
    $optionsText -notmatch 'SET BY GUILD INFORMATION' -or
    $optionsText -notmatch 'MULTIPLE DIRECTIVES FOUND' -or
    $optionsText -notmatch "Using this character's saved setting" -or
    $optionsText -notmatch 'authorityDirective') {
    throw "Guild Information authority directives or their locked configuration state appear incomplete."
}
if ($constantsText -notmatch 'autoPugRaids\s*=\s*false' -or
    $constantsText -notmatch 'autoPugIncludeLFR\s*=\s*false' -or
    $raidText -notmatch 'MaybeAutoStartPug' -or
    $raidText -notmatch 'IsWithinRaidHours' -or
    $raidText -notmatch 'function isLFRWorldTier' -or
    $raidText -notmatch 'difficultyID\s*==\s*17\s+or\s+difficultyID\s*==\s*250' -or
    $raidText -notmatch 'account\.autoPugIncludeLFR\s*~=\s*true' -or
    $raidText -notmatch 'IsGlobalPugTeam\(teamID\)' -or
    $optionsText -notmatch 'Auto Start Pug Raids' -or
    $optionsText -notmatch 'Include LFR' -or
    $optionsText -notmatch 'account\.autoPugRaids\s+then[\s\S]*?autoPugIncludeLFR' -or
    $optionsText -notmatch 'equivalent World tier' -or
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
if ($seasonText -notmatch 'label\s*=\s*"Current Season"' -or
    $seasonText -notmatch '\{ value = "all", label = "All" \}' -or
    $uiText -notmatch 'function LV\.UI:ResetSeasonOnOpen' -or
    $uiText -notmatch 'self:ResetSeasonOnOpen\(\)' -or
    $uiText -notmatch 'dungeonHistory\s*=\s*\{' -or
    $uiText -notmatch 'raidNavHeader:SetText\("Raids"\)' -or
    $uiText -notmatch 'dungeonNavHeader:SetText\("Dungeons"\)' -or
    $uiText -notmatch 'dungeonNavHeader:SetShown\(dungeonEnabled\)' -or
    $uiText -notmatch 'sync:SetPoint\("BOTTOMLEFT", 18, 54\)') {
    throw "The Current Season/All selector, grouped sidebar, conditional dungeon menu, or fixed Sync action appears incomplete."
}
if ($dungeonText -notmatch 'CHALLENGE_MODE_COMPLETED' -or
    $dungeonText -notmatch 'BONUS_ROLL_RESULT' -or
    $dungeonText -notmatch 'specID' -or
    $historyMeterText -notmatch 'Champion \(0-5\)' -or
    $historyMeterText -notmatch 'Hero \(6-9\)' -or
    $historyMeterText -notmatch 'Myth \(M\+10 Bonus Roll\)' -or
    $optionsText -notmatch 'checkCell\(parent, x, y, width, "Dungeon Logging"' -or
    $constantsText -notmatch 'dungeonLogging\s*=\s*true') {
    throw "Dungeon logging, bonus-roll capture, or dungeon history UI appears incomplete."
}
if ($utilText -notmatch 'function LV\.Util:IsItemWarbound' -or
    $utilText -notmatch 'TooltipDataItemBinding' -or
    $utilText -notmatch 'AccountUntilEquipped' -or
    $utilText -notmatch 'BindToAccountUntilEquipped' -or
    $utilText -notmatch 'line\.bonding' -or
    $utilText -notmatch 'C_TooltipInfo\.GetHyperlink' -or
    $lootText -notmatch 'if warbound then' -or
    $dungeonText -notmatch 'LV\.Util:IsItemWarbound\(fields\.itemLink\)' -or
    $historyMeterText -notmatch 'LV\.Dungeons:IsWarboundRow\(row\)' -or
    $dataSyncText -notmatch 'LV\.Loot:IsWarboundRow\(guildKey, row\)') {
    throw "Warbound-until-equipped gear is no longer excluded from raid, dungeon, and sync counts."
}
if ($lootText -notmatch 'function LV\.Loot:RecordRaidBonusResult' -or
    $lootText -notmatch 'src\s*=\s*"bonus"' -or
    $lootText -notmatch 'BONUS_ROLL_RESULT' -or
    $uiText -notmatch '\{ key = "bonus", label = "Bonus Rolls" \}' -or
    $uiText -notmatch 'sourceFilter\s*==\s*"bonus"' -or
    $uiText -notmatch '\(row\.src\s*==\s*"bonus"\)\s*==\s*\(sourceFilter\s*==\s*"bonus"\)' -or
    $historyMeterText -notmatch 'row\.src\s*~=\s*"bonus"') {
    throw "Raid bonus rolls are no longer captured and isolated on their own Loot History tab."
}
if ($utilText -notmatch 'function LV\.Util:ExtractBonusLoot' -or
    $utilText -notmatch 'LOOT_ITEM_BONUS_ROLL_SELF' -or
    $utilText -notmatch 'LOOT_ITEM_BONUS_ROLL' -or
    $lootText -notmatch 'function LV\.Loot:NewBonusEventID' -or
    $lootText -notmatch 'br\s*=\s*fields\.bonusEventID' -or
    $lootText -notmatch 'function LV\.Loot:RecordRaidBonusChatLoot' -or
    $dataSyncText -notmatch 'row\.br\s*==\s*bonusEventID' -or
    $dungeonText -notmatch 'level\s*>=\s*10\s+and\s+"myth"' -or
    $lootText -notmatch 'sourceDifficultyID\s*==\s*15\s+or\s+sourceDifficultyID\s*==\s*16' -or
    $tradeText -notmatch 'sourceLoot\.src\s*==\s*"bonus"' -or
    $tradeText -notmatch 'lootRow\.src\s*==\s*"bonus"' -or
    $dungeonText -notmatch 'row\.src\s*~=\s*"bonus"' -or
    $uiText -notmatch 'Personal bonus loot' -or
    $uiText -notmatch 'Cannot be traded') {
    throw "Unique localized bonus-loot capture, reward labels, sync identity, or no-trade protection appears incomplete."
}
if ($raidText -notmatch 'function LV\.Raid:ActiveScheduleMatches' -or
    $raidText -notmatch 'local before\s*=\s*tonumber\(cfg\.promptBefore\)' -or
    $raidText -notmatch 'serverNow\s*<\s*scheduledEndAt\s*\+\s*\(after\s*\*\s*60\)' -or
    $raidText -notmatch 'isAutoScheduled\s+and\s+scheduledEnd[\s\S]*?LV\.Util:ServerNow\(\)\s*>=\s*scheduledEnd' -or
    $raidText -notmatch 'guildMembers\s*\*\s*2\s*>\s*total' -or
    $raidText -notmatch 'function LV\.Raid:MaybeAutoStartScheduled' -or
    $raidText -notmatch 'isGuildRaidGroup\(\)\s+and\s+#self:ActiveScheduleMatches\(cfg\)\s*>\s*0' -or
    $raidText -notmatch 'self\.autoPugSignature\s*=\s*signature' -or
    $raidText -notmatch 'function LV\.Raid:ObserveLoggerProbe' -or
    $raidText -notmatch 'AUTO_START_ELECTION_SECONDS' -or
    $commsText -notmatch 'kind\s*==\s*"P"' -or
    $uiText -notmatch 'function LV\.UI:PromptRaidTeamSelection') {
    throw "Scheduled in-instance raid auto-start, logger election, guild-majority protection, or team selection appears incomplete."
}
$raidAutoStartEventBlocks = [regex]::Matches(
    $raidText,
    '(?sm)LV:RegisterEvent\("(?:PLAYER_ENTERING_WORLD|ZONE_CHANGED_NEW_AREA|GROUP_ROSTER_UPDATE)".*?^end\)'
)
if ($raidAutoStartEventBlocks.Count -ne 3 -or
    @($raidAutoStartEventBlocks | Where-Object {
        $_.Value.IndexOf('MaybeAutoStartScheduled') -lt 0 -or
        $_.Value.IndexOf('MaybeAutoStartPug') -lt 0 -or
        $_.Value.IndexOf('MaybeAutoStartScheduled') -gt $_.Value.IndexOf('MaybeAutoStartPug')
    }).Count -gt 0) {
    throw "Scheduled raid classification must run before automatic Pug classification on raid-state events."
}
if ($seasonText -notmatch 'DungeonFilterValues' -or
    $historyMeterText -notmatch 'CreateDungeonTrackSlider' -or
    $historyMeterText -notmatch 'Bonus Rolls' -or
    $historyMeterText -notmatch 'dungeonHistoryFilter' -or
    $historyMeterText -notmatch 'FilteredDungeonLootRows' -or
    $historyMeterText -notmatch 'dungeonHistorySearch' -or
    $uiText -notmatch 'CreateHistorySearch' -or
    $uiText -notmatch 'Raid Information' -or
    $uiText -notmatch 'Bosses Killed' -or
    $uiText -notmatch 'CreateHistoryDateDisplay' -or
    $uiText -notmatch 'Raid hours:' -or
    $uiText -notmatch 'iconOnly') {
    throw "Dungeon distribution/search filters, raid detail context, or the formatted Recent loot table appears incomplete."
}
if ($tradeText -notmatch 'RecordManualTrade' -or
    $tradeText -notmatch 'sourceLootID' -or
    $tradeText -notmatch 'parts\[7\]' -or
    $tradeText -notmatch 'if\s+not\s+sourceLoot\s+or\s+sourceLoot\.src\s*==\s*"bonus"\s+then' -or
    $tradeText -match 'if\s+not\s+session\s+and\s+not\s+sourceLoot\s+then' -or
    $tradeText -notmatch 'sid\s*=\s*sourceLoot\.sid' -or
    $tradeText -notmatch 'loot\s*=\s*sourceLoot\.id' -or
    $uiText -notmatch 'ShowLootItemActions' -or
    $uiText -notmatch 'RaidLootRecipientValues' -or
    $uiText -notmatch 'Trade Item' -or
    $uiText -notmatch 'Exclude Loot' -or
    $historyMeterText -notmatch '#entries / maxTotal' -or
    $historyMeterText -notmatch 'maxTotal = math\.max') {
    throw "Trade-to-loot linkage, manual per-loot trade options, or proportional Distribution meter scaling appears incomplete."
}
if ($tradeText -notmatch 'function LV\.Trade:FindDuplicate' -or
    $tradeText -notmatch 'tradeEventByRemoteID' -or
    $tradeText -notmatch 'lootEventByRemoteID' -or
    $tradeText -notmatch 'sender:lower\(\)\s*==\s*LV\.Loot:NormalizePlayerName' -or
    $tradeText -notmatch 'row\.id,\s*\r?\n\s*\}\)' -or
    $tradeText -notmatch 'parts\[10\]' -or
    $tradeText -notmatch 'replaceWithEmpty\s*=\s*replaceWithEmpty\s+and\s+not\s+self\.active\.accepted' -or
    $tradeText -notmatch 'function LV\.Trade:DeduplicateRecord' -or
    $tradeText -notmatch 'sourceLoot\.tr\s*=\s*keep\.id') {
    throw "Live trade messages no longer have stable deduplication, final item snapshot protection, or safe duplicate cleanup."
}
if ($uiText -notmatch 'HistoryFilterPreference' -or
    $uiText -notmatch 'raidMinDifficulty' -or
    $historyMeterText -notmatch 'dungeonMinTrack' -or
    $uiText -notmatch 'SetHistoryFilterPreference' -or
    $historyMeterText -notmatch 'SetHistoryFilterPreference') {
    throw "Saved raid or dungeon loot-level filter preferences appear incomplete."
}
if ($uiText -notmatch 'CreateHistoryColumnHeader\(parent, "Roll"' -or
    $uiText -notmatch 'local methodWidth = 40' -or
    $uiText -notmatch 'lootroll-rollicon-yourolled-need' -or
    $uiText -notmatch 'lootroll-rollicon-yourolled-greed' -or
    $uiText -notmatch 'lootroll-rollicon-yourolled-transmog' -or
    $uiText -notmatch 'INV_Misc_Dice_01' -or
    $uiText -notmatch 'local lootRollGroupOrder\s*=\s*\{ "need", "greed", "transmog" \}' -or
    $uiText -notmatch 'method ~= "pass" and method ~= "noroll"' -or
    $uiText -notmatch 'aWinner\s*>\s*bWinner' -or
    $uiText -notmatch 'self:AddLootBreakdownTooltip\(guildKey, row, false\)' -or
    $uiText -notmatch 'CreateHistoryColumnHeader\(parent, "Roll", 644') {
    throw "The Roll column, winner-method icons, grouped tooltip, or legacy dice fallback appears incomplete."
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
$historicalAttendanceEdits = [regex]::Matches(
    $uiText,
    '(?s)function LV\.UI:(?:Set|Remove)HistoricalRaidAttendance\b.*?(?=\r?\nfunction LV\.UI:)'
)
if ($historicalAttendanceEdits.Count -ne 2 -or
    @($historicalAttendanceEdits | Where-Object { $_.Value -match '\braid\.en\s*=' }).Count -gt 0 -or
    $storeText -notmatch 'function LV\.Store:NormalizeHistoricalRaidTimes' -or
    $storeText -notmatch 'raid\.lastSource == "ui_edit"' -or
    $storeText -notmatch 'raid\.en = maximumEndAt') {
    throw "Historical attendance edits can alter raid duration, or the scheduled-raid repair is missing."
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
