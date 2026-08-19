local _, LV = ...

local distributionColors = {
    lfr = { 0.46, 0.48, 0.52, 0.95 },
    normal = { 0.20, 0.72, 0.34, 0.95 },
    heroic = { 0.14, 0.48, 0.95, 0.95 },
    mythic = { 0.65, 0.28, 0.92, 0.95 },
    champion = { 0.20, 0.72, 0.34, 0.95 },
    hero = { 0.14, 0.48, 0.95, 0.95 },
    myth = { 0.65, 0.28, 0.92, 0.95 },
}

local distributionLabels = {
    lfr = "LFR",
    normal = "Normal",
    heroic = "Heroic",
    mythic = "Mythic",
    champion = "Champion (0-5)",
    hero = "Hero (6-9)",
    myth = "Myth (M+10 Bonus Roll)",
}

local dungeonBuckets = { "champion", "hero", "myth" }
local dungeonTrackThresholds = {
    { value = "champion", label = "Champion" },
    { value = "hero", label = "Heroic" },
    { value = "myth", label = "Bonus Rolls" },
}
local dungeonTrackRank = { champion = 1, hero = 2, myth = 3 }

local function itemDisplay(itemKey, itemID)
    itemKey = tostring(itemKey or "")
    itemID = tonumber(itemID) or LV.Util:ItemID(itemKey) or 0
    local itemName, itemLink, itemQuality, itemIcon
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(getter) == "function" then
        local result = { pcall(getter, itemKey ~= "" and itemKey or itemID) }
        if result[1] then
            itemName, itemLink, itemQuality, itemIcon = result[2], result[3], result[4], result[10]
        end
    end
    if not itemIcon and C_Item and C_Item.GetItemIconByID and itemID > 0 then
        local result = { pcall(C_Item.GetItemIconByID, itemID) }
        itemIcon = result[1] and result[2] or nil
    end
    if not itemName and C_Item and C_Item.RequestLoadItemDataByID and itemID > 0 then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    local displayName = itemName
        or itemKey:match("%[(.-)%]")
        or (itemID > 0 and ("Item " .. tostring(itemID)) or "Unknown item")
    local tooltipLink = itemLink or (itemKey ~= "" and itemKey or (itemID > 0 and ("item:" .. itemID) or nil))
    local color = ITEM_QUALITY_COLORS and itemQuality and ITEM_QUALITY_COLORS[itemQuality]
    return displayName, tooltipLink, color, itemIcon
end

local function dungeonItemDisplay(row)
    return itemDisplay(LV.Store:DungeonDictionaryValue("i", row and row.item), row and row.itemID)
end

local function dungeonRuns(record)
    local lookup = {}
    for _, run in ipairs((record and record.r) or {}) do
        if type(run) == "table" and run.id then
            lookup[run.id] = run
        end
    end
    return lookup
end

local function seasonMatches(row, seasonID)
    return seasonID == "all" or (row and row.sea == seasonID)
end

local function specName(specID)
    if type(GetSpecializationInfoByID) == "function" and tonumber(specID) then
        local result = { pcall(GetSpecializationInfoByID, tonumber(specID)) }
        if result[1] and result[3] then
            return tostring(result[3])
        end
    end
    return tonumber(specID) and ("Spec " .. tostring(specID)) or "Unknown spec"
end

function LV.UI:RaidFinalLootOwner(record, row)
    local owner = row and row.p
    local lastTrade = tonumber(row and row.ts) or 0
    local trades = {}
    for _, trade in ipairs((record and record.t) or {}) do
        if type(trade) == "table" then trades[#trades + 1] = trade end
    end
    table.sort(trades, function(a, b) return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0) end)
    for _, trade in ipairs(trades) do
        local timestamp = tonumber(trade and trade.ts) or 0
        local direct = row and trade and trade.loot == row.id
        local chained = trade and trade.f == owner and trade.item == row.item
            and timestamp >= lastTrade and timestamp <= ((tonumber(row.ts) or timestamp) + 7200)
        if direct or chained then
            owner = trade.to or owner
            lastTrade = timestamp
        end
    end
    return owner
end

function LV.UI:RaidLootDistributionRows(guildKey)
    local record = LV.Store:GuildRecord(guildKey)
    local groups = {}
    local total = 0
    for _, row in ipairs(record.l or {}) do
        local difficulty = self:LootDifficultyAbbrev(guildKey, row)
        local bucket = difficulty == "L" and "lfr" or difficulty == "N" and "normal"
            or difficulty == "H" and "heroic" or difficulty == "M" and "mythic" or nil
        local excluded = LV.Loot and LV.Loot.IsLootItemExcluded and LV.Loot:IsLootItemExcluded(guildKey, row)
        local warbound = LV.Loot and LV.Loot.IsWarboundRow and LV.Loot:IsWarboundRow(guildKey, row)
        if bucket and row.src ~= "bonus" and not excluded and not warbound
            and LV.Seasons:EventMatchesFilter(guildKey, record, row, self:SelectedSeasonFilter())
            and self:EventMatchesRaidTag(record, row, self.historyTeamID)
            and self:EventMeetsMinimumDifficulty(guildKey, record, row) then
            local owner = self:RaidFinalLootOwner(record, row)
            local mainID = self:AttendanceRollupID(guildKey, owner)
            if mainID then
                local group = groups[mainID]
                if not group then
                    local fullName = LV.Store:DictionaryValue(guildKey, "n", mainID)
                    group = { id = mainID, name = LV.Util:ShortName(fullName), total = 0, buckets = {} }
                    groups[mainID] = group
                end
                group.buckets[bucket] = group.buckets[bucket] or {}
                group.buckets[bucket][#group.buckets[bucket] + 1] = row
                group.total = group.total + 1
                total = total + 1
            end
        end
    end
    local rows = {}
    for _, group in pairs(groups) do
        rows[#rows + 1] = group
    end
    table.sort(rows, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.name:lower() < b.name:lower()
    end)
    return rows, total
end

function LV.UI:DungeonLootRows()
    local record = LV.Store:DungeonRecord()
    local seasonID = self:SelectedSeasonFilter()
    local rows = {}
    for _, row in ipairs(record.l or {}) do
        if type(row) == "table" and seasonMatches(row, seasonID)
            and not (LV.Dungeons and LV.Dungeons.IsWarboundRow and LV.Dungeons:IsWarboundRow(row)) then
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0)
    end)
    return rows, record, dungeonRuns(record)
end

function LV.UI:DungeonLootSearchText(row, runs)
    local run = (runs or {})[row and row.run] or {}
    local itemName = dungeonItemDisplay(row)
    local itemKey = LV.Store:DungeonDictionaryValue("i", row and row.item)
    local looter = LV.Store:DungeonDictionaryValue("n", row and row.p)
    local owner = LV.Store:DungeonDictionaryValue("n", row and (row.o or row.p))
    local dungeon = LV.Store:DungeonDictionaryValue("s", run.z)
    local boss = LV.Store:DungeonDictionaryValue("s", row and row.boss)
    local level = tonumber(run.lvl) or 0
    local key = (run.m0 or level == 0) and "M0 Mythic 0" or ("+" .. level .. " M+ Mythic Plus")
    local source = row and row.src == "bonus"
        and ("Bonus " .. specName(row.spec))
        or (boss ~= "" and boss or "End chest")
    local parts = {
        date("%m/%d %H:%M", tonumber(row and row.ts) or 0),
        looter,
        LV.Util:ShortName(looter),
        owner,
        LV.Util:ShortName(owner),
        itemName,
        itemKey,
        tostring(row and row.itemID or ""),
        dungeon,
        key,
        source,
        row and row.track or "",
    }
    return table.concat(parts, " "):lower()
end

function LV.UI:FilteredDungeonLootRows()
    local allRows, record, runs = self:DungeonLootRows()
    local query = LV.Util:Trim(self.dungeonHistorySearch or ""):lower()
    if query == "" then
        return allRows, record, runs, #allRows
    end

    local rows = {}
    for _, row in ipairs(allRows) do
        if self:DungeonLootSearchText(row, runs):find(query, 1, true) then
            rows[#rows + 1] = row
        end
    end
    return rows, record, runs, #allRows
end

function LV.UI:DungeonLootDistributionRows()
    local lootRows, record, runs = self:DungeonLootRows()
    local groups = {}
    local total = 0
    local minimumRank = dungeonTrackRank[self.dungeonMinTrack or "champion"] or 1
    local dungeonFilter = self.dungeonHistoryFilter or "all"
    for _, row in ipairs(lootRows) do
        local bucket = dungeonTrackRank[row.track] and row.track or "champion"
        local run = runs[row.run] or {}
        local dungeonName = LV.Store:DungeonDictionaryValue("s", run.z)
        if (dungeonTrackRank[bucket] or 1) >= minimumRank
            and (dungeonFilter == "all" or dungeonName == dungeonFilter) then
            local owner = row.o or row.p
            local group = groups[owner]
            if not group then
                local fullName = LV.Store:DungeonDictionaryValue("n", owner)
                group = { id = owner, name = LV.Util:ShortName(fullName), total = 0, buckets = {} }
                groups[owner] = group
            end
            group.buckets[bucket] = group.buckets[bucket] or {}
            group.buckets[bucket][#group.buckets[bucket] + 1] = row
            group.total = group.total + 1
            total = total + 1
        end
    end
    local rows = {}
    for _, group in pairs(groups) do
        rows[#rows + 1] = group
    end
    table.sort(rows, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.name:lower() < b.name:lower()
    end)
    return rows, total, record
end

function LV.UI:DungeonDistributionBuckets()
    local minimumRank = dungeonTrackRank[self.dungeonMinTrack or "champion"] or 1
    local buckets = {}
    for _, bucket in ipairs(dungeonBuckets) do
        if (dungeonTrackRank[bucket] or 1) >= minimumRank then
            buckets[#buckets + 1] = bucket
        end
    end
    return buckets
end

function LV.UI:CreateDungeonItemButton(parent, row, x, y, width)
    local itemName, itemLink, qualityColor, itemIcon = dungeonItemDisplay(row)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", x, y + 1)
    button:SetSize(width, 18)
    if itemIcon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("LEFT")
        button.icon:SetSize(16, 16)
        button.icon:SetTexture(itemIcon)
    end
    button.text = LV.Widgets:Text(button, itemName)
    button.text:SetPoint("LEFT", itemIcon and 20 or 0, 0)
    button.text:SetWidth(itemIcon and math.max(20, width - 20) or width)
    button.text:SetWordWrap(false)
    if qualityColor then
        button.text:SetTextColor(qualityColor.r, qualityColor.g, qualityColor.b, 1)
    end
    button:SetScript("OnEnter", function()
        if itemLink then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(itemLink)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function()
        if itemLink and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(itemLink)
        end
    end)
    return button
end

function LV.UI:ShowLootDistributionDetail(title, entries, guildKey, isDungeon)
    if self.lootDistributionModal then
        self.lootDistributionModal:Hide()
    end
    local layer = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    layer:SetAllPoints(self.frame)
    layer:SetFrameStrata("FULLSCREEN_DIALOG")
    layer:SetFrameLevel(self.frame:GetFrameLevel() + 450)
    layer:EnableMouse(true)
    LV.Widgets:ApplyBackdrop(layer, LV.Widgets.colors.overlay, LV.Widgets.colors.transparent)
    local modal = CreateFrame("Frame", nil, layer, "BackdropTemplate")
    modal:SetSize(720, 450)
    modal:SetPoint("CENTER")
    modal:SetFrameLevel(layer:GetFrameLevel() + 1)
    LV.Widgets:ApplyBackdrop(modal, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.borderStrong)
    local heading = LV.Widgets:Text(modal, title, "large")
    heading:SetPoint("TOPLEFT", 22, -18)
    local close = LV.Widgets:Button(modal, "x", 28, 28, function() layer:Hide() end, "ghost")
    close:SetPoint("TOPRIGHT", -14, -14)
    local count = LV.Widgets:Text(modal, tostring(#(entries or {})) .. " item(s)")
    count:SetPoint("TOPLEFT", 24, -51)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    local scroll, content = LV.Widgets:ScrollFrame(modal)
    scroll:SetPoint("TOPLEFT", 14, -78)
    scroll:SetPoint("BOTTOMRIGHT", -14, 14)
    local runs = isDungeon and dungeonRuns(LV.Store:DungeonRecord()) or nil
    local y = -4
    for index, row in ipairs(entries or {}) do
        local background = content:CreateTexture(nil, "BACKGROUND")
        background:SetPoint("TOPLEFT", 4, y + 4)
        background:SetPoint("TOPRIGHT", -2, y + 4)
        background:SetHeight(28)
        background:SetColorTexture(unpack(index % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface))
        local dateText = LV.Widgets:Text(content, date("%m/%d/%y", tonumber(row.ts) or 0))
        dateText:SetPoint("TOPLEFT", 12, y)
        dateText:SetWidth(72)
        if isDungeon then
            self:CreateDungeonItemButton(content, row, 92, y, 290)
            local run = runs[row.run] or {}
            local dungeon = LV.Store:DungeonDictionaryValue("s", run.z)
            local source = row.src == "bonus" and ("Bonus - " .. specName(row.spec))
                or (LV.Store:DungeonDictionaryValue("s", row.boss) ~= "" and LV.Store:DungeonDictionaryValue("s", row.boss) or ("+" .. tostring(run.lvl or 0)))
            local context = LV.Widgets:Text(content, dungeon .. "  " .. source)
            context:SetPoint("TOPLEFT", 394, y)
            context:SetWidth(280)
            context:SetWordWrap(false)
            context:SetTextColor(unpack(LV.Widgets.colors.muted))
        else
            self:CreateHistoryItemButton(content, guildKey, row, 92, y, 290, true)
            local context = LV.Widgets:Text(content, self:LootBossDifficultyDisplay(guildKey, row))
            context:SetPoint("TOPLEFT", 394, y)
            context:SetWidth(280)
            context:SetWordWrap(false)
            context:SetTextColor(unpack(LV.Widgets.colors.muted))
        end
        y = y - 30
    end
    content:SetHeight(math.max(1, -y + 4))
    self.lootDistributionModal = layer
    layer:Show()
    layer:Raise()
end

function LV.UI:RenderDistributionMeter(parent, rows, total, buckets, guildKey, isDungeon)
    local count = LV.Widgets:Text(parent.header, tostring(total) .. " item(s)")
    count:SetPoint("RIGHT", -18, 0)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    local legendX = 24
    for _, bucket in ipairs(buckets) do
        local swatch = parent:CreateTexture(nil, "ARTWORK")
        swatch:SetColorTexture(unpack(distributionColors[bucket]))
        swatch:SetSize(10, 10)
        swatch:SetPoint("TOPLEFT", legendX, -44)
        local label = LV.Widgets:Text(parent, distributionLabels[bucket])
        label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
        label:SetTextColor(unpack(LV.Widgets.colors.textSecondary))
        legendX = legendX + (isDungeon and 170 or 105)
    end
    if #rows == 0 then
        local empty = LV.Widgets:Text(parent, "No qualifying loot has been recorded for this selection.")
        empty:SetPoint("TOPLEFT", 24, -84)
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        return
    end
    local scroll, content = LV.Widgets:ScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 12, -70)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    local width = math.max(420, (tonumber(parent:GetWidth()) or 760) - 190)
    local maxTotal = 1
    for _, group in ipairs(rows) do
        maxTotal = math.max(maxTotal, tonumber(group.total) or 0)
    end
    local y = -4
    for index, group in ipairs(rows) do
        local name = LV.Widgets:Text(content, group.name ~= "" and group.name or "Unknown")
        name:SetPoint("TOPLEFT", 12, y - 1)
        name:SetWidth(120)
        name:SetWordWrap(false)
        if not isDungeon then
            self:SetNameClassColor(name, guildKey, group.id)
        end
        local bar = CreateFrame("Frame", nil, content, "BackdropTemplate")
        bar:SetPoint("TOPLEFT", 138, y)
        bar:SetSize(width, 22)
        LV.Widgets:ApplyBackdrop(bar, LV.Widgets.colors.control, LV.Widgets.colors.border)
        local x = 1
        for _, bucket in ipairs(buckets) do
            local entries = group.buckets[bucket] or {}
            local segmentWidth = math.floor((width - 2) * #entries / maxTotal)
            if #entries > 0 then
                segmentWidth = math.max(1, segmentWidth)
                local segment = CreateFrame("Button", nil, bar)
                segment:SetPoint("TOPLEFT", x, -1)
                segment:SetSize(math.max(1, segmentWidth), 20)
                local fill = segment:CreateTexture(nil, "ARTWORK")
                fill:SetAllPoints()
                fill:SetColorTexture(unpack(distributionColors[bucket]))
                local value = LV.Widgets:Text(segment, tostring(#entries))
                value:SetPoint("CENTER")
                segment:SetScript("OnClick", function()
                    self:ShowLootDistributionDetail(group.name .. " - " .. distributionLabels[bucket], entries, guildKey, isDungeon)
                end)
                segment:SetScript("OnEnter", function()
                    fill:SetVertexColor(1.18, 1.18, 1.18, 1)
                    GameTooltip:SetOwner(segment, "ANCHOR_RIGHT")
                    GameTooltip:SetText(distributionLabels[bucket])
                    GameTooltip:AddLine("Click to see " .. tostring(#entries) .. " item(s).", 1, 1, 1)
                    GameTooltip:Show()
                end)
                segment:SetScript("OnLeave", function()
                    fill:SetVertexColor(1, 1, 1, 1)
                    GameTooltip:Hide()
                end)
                x = x + segmentWidth
            end
        end
        local totalText = LV.Widgets:Text(content, tostring(group.total))
        totalText:SetPoint("LEFT", bar, "RIGHT", 10, 0)
        y = y - 32
    end
    content:SetHeight(math.max(1, -y + 4))
end

function LV.UI:RenderRaidLootDistribution(parent, guildKey)
    local rows, total = self:RaidLootDistributionRows(guildKey)
    self:RenderDistributionMeter(parent, rows, total, self:RaidDifficultyBuckets(), guildKey, false)
end

function LV.UI:RenderDungeonRecent(parent)
    local rows, record, runs, total = self:FilteredDungeonLootRows()
    local searchText = LV.Util:Trim(self.dungeonHistorySearch or "")
    local countText = searchText ~= ""
        and (tostring(#rows) .. " of " .. tostring(total) .. " item(s)")
        or (tostring(total) .. " item(s)")
    local count = LV.Widgets:Text(parent.header, countText)
    count:SetPoint("RIGHT", -18, 0)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    self:CreateHistoryColumnHeader(parent, "Date", 24, 78)
    self:CreateHistoryColumnHeader(parent, "Player", 106, 96)
    self:CreateHistoryColumnHeader(parent, "Loot", 210, 212)
    self:CreateHistoryColumnHeader(parent, "Dungeon", 432, 120)
    self:CreateHistoryColumnHeader(parent, "M+", 562, 34)
    self:CreateHistoryColumnHeader(parent, "Source / Loot Spec", 606, 130)
    if #rows == 0 then
        local message = searchText ~= ""
            and "No dungeon gear matches your search."
            or "No dungeon gear recorded for this season yet."
        local empty = LV.Widgets:Text(parent, message)
        empty:SetPoint("TOPLEFT", 24, -70)
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        return
    end
    local scroll, content = LV.Widgets:ScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 12, -58)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    local y = -4
    for index, row in ipairs(rows) do
        local background = content:CreateTexture(nil, "BACKGROUND")
        background:SetPoint("TOPLEFT", 4, y + 4)
        background:SetPoint("TOPRIGHT", -2, y + 4)
        background:SetHeight(26)
        background:SetColorTexture(unpack(index % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface))
        local run = runs[row.run] or {}
        local ownerName = LV.Store:DungeonDictionaryValue("n", row.o or row.p)
        local dateText = LV.Widgets:Text(content, date("%m/%d %H:%M", tonumber(row.ts) or 0))
        dateText:SetPoint("TOPLEFT", 12, y)
        dateText:SetWidth(78)
        local player = LV.Widgets:Text(content, LV.Util:ShortName(ownerName))
        player:SetPoint("TOPLEFT", 94, y)
        player:SetWidth(96)
        player:SetWordWrap(false)
        self:CreateDungeonItemButton(content, row, 198, y, 212)
        local dungeon = LV.Widgets:Text(content, LV.Store:DungeonDictionaryValue("s", run.z))
        dungeon:SetPoint("TOPLEFT", 420, y)
        dungeon:SetWidth(120)
        dungeon:SetWordWrap(false)
        local key = LV.Widgets:Text(content, (run.m0 or tonumber(run.lvl) == 0) and "M0" or ("+" .. tostring(run.lvl or 0)))
        key:SetPoint("TOPLEFT", 550, y)
        key:SetWidth(34)
        local boss = LV.Store:DungeonDictionaryValue("s", row.boss)
        local sourceText = row.src == "bonus" and ("Bonus - " .. specName(row.spec)) or (boss ~= "" and boss or "End chest")
        local source = LV.Widgets:Text(content, sourceText)
        source:SetPoint("TOPLEFT", 594, y)
        source:SetWidth(140)
        source:SetWordWrap(false)
        source:SetTextColor(unpack(row.src == "bonus" and distributionColors.myth or LV.Widgets.colors.textSecondary))
        y = y - 28
    end
    content:SetHeight(math.max(1, -y + 4))
end

function LV.UI:CreateDungeonTrackSlider(parent, width)
    width = math.max(210, tonumber(width) or 250)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(width, 18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(1, #dungeonTrackThresholds)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    local rail = slider:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("LEFT", 4, 0)
    rail:SetPoint("RIGHT", -4, 0)
    rail:SetHeight(4)
    rail:SetColorTexture(unpack(LV.Widgets.colors.border))
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", rail, "LEFT")
    fill:SetHeight(4)
    fill:SetColorTexture(unpack(LV.Widgets.colors.accent))
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(12, 18)
    thumb:SetVertexColor(unpack(LV.Widgets.colors.accentBright))

    for index, definition in ipairs(dungeonTrackThresholds) do
        local tick = slider:CreateTexture(nil, "OVERLAY")
        tick:SetSize(2, 8)
        if index == 1 then
            tick:SetPoint("CENTER", slider, "LEFT", 4, 0)
        elseif index == #dungeonTrackThresholds then
            tick:SetPoint("CENTER", slider, "RIGHT", -4, 0)
        else
            tick:SetPoint("CENTER", slider, "LEFT", 4 + ((width - 8) * (index - 1) / (#dungeonTrackThresholds - 1)), 0)
        end
        tick:SetColorTexture(unpack(LV.Widgets.colors.textSecondary))

        local label = LV.Widgets:Text(slider, definition.label)
        label:SetWidth(index == 3 and 92 or 68)
        label:SetJustifyH(index == 1 and "LEFT" or index == #dungeonTrackThresholds and "RIGHT" or "CENTER")
        if index == 1 then
            label:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
        elseif index == #dungeonTrackThresholds then
            label:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
        else
            label:SetPoint("TOP", slider, "BOTTOMLEFT", 4 + ((width - 8) * (index - 1) / (#dungeonTrackThresholds - 1)), -2)
        end
        label:SetTextColor(unpack(LV.Widgets.colors.muted))
    end

    local updating = false
    local function update(value)
        local index = math.max(1, math.min(#dungeonTrackThresholds, math.floor((tonumber(value) or 1) + 0.5)))
        if not updating and tonumber(value) ~= index then
            updating = true
            slider:SetValue(index)
            updating = false
        end
        self.dungeonMinTrack = dungeonTrackThresholds[index].value
        self:SetHistoryFilterPreference("dungeonMinTrack", self.dungeonMinTrack)
        fill:SetWidth(math.max(1, (width - 8) * (index - 1) / (#dungeonTrackThresholds - 1)))
    end
    slider:SetScript("OnValueChanged", function(_, value) update(value) end)
    slider:SetScript("OnMouseUp", function() self:Refresh() end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        slider:SetValue(slider:GetValue() + (delta > 0 and 1 or -1))
        self:Refresh()
    end)
    slider:SetScript("OnEnter", function()
        GameTooltip:SetOwner(slider, "ANCHOR_RIGHT")
        GameTooltip:SetText("Minimum Difficulty")
        GameTooltip:AddLine("Shows the selected dungeon loot track and every track above it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slider:SetValue(dungeonTrackRank[self.dungeonMinTrack or "champion"] or 1)
    return slider
end

function LV.UI:RenderDungeonDistributionFilters(dungeonValues)
    local section = LV.Widgets:Section(self.content, "Loot Filters", 92)
    section:SetPoint("TOPLEFT", 22, -132)
    section:SetPoint("RIGHT", -22, 0)
    local width = math.max(720, (tonumber(section:GetWidth()) or 820) - 8)
    local half = math.floor((width - 2) / 2)

    local difficultyCell = CreateFrame("Frame", nil, section, "BackdropTemplate")
    difficultyCell:SetPoint("TOPLEFT", 4, -34)
    difficultyCell:SetSize(half, 52)
    LV.Widgets:ApplyBackdrop(difficultyCell, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.transparent)
    local difficultyLabel = LV.Widgets:Text(difficultyCell, "Minimum Difficulty")
    difficultyLabel:SetPoint("LEFT", 14, 3)
    local difficulty = self:CreateDungeonTrackSlider(difficultyCell, math.max(220, half - 168))
    difficulty:SetPoint("TOPRIGHT", -14, -9)

    local dungeonCell = CreateFrame("Frame", nil, section, "BackdropTemplate")
    dungeonCell:SetPoint("TOPLEFT", half + 6, -34)
    dungeonCell:SetSize(half, 52)
    LV.Widgets:ApplyBackdrop(dungeonCell, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.transparent)
    local dungeonLabel = LV.Widgets:Text(dungeonCell, "Dungeon")
    dungeonLabel:SetPoint("LEFT", 14, 0)
    local dungeon = LV.Widgets:Dropdown(dungeonCell, dungeonValues, function()
        return self.dungeonHistoryFilter
    end, function(value)
        self.dungeonHistoryFilter = value
        self:Refresh()
    end, 210)
    dungeon:SetPoint("RIGHT", -14, 0)
    return section
end

function LV.UI:RenderDungeonHistory()
    self.historyView = self.historyView == "distribution" and "distribution" or "recent"
    local savedMinTrack = self:HistoryFilterPreference("dungeonMinTrack", "champion")
    self.dungeonMinTrack = self.dungeonMinTrack or savedMinTrack
    self.dungeonMinTrack = dungeonTrackRank[self.dungeonMinTrack] and self.dungeonMinTrack or "champion"
    self:SetHistoryFilterPreference("dungeonMinTrack", self.dungeonMinTrack)
    local dungeonValues = LV.Seasons:DungeonFilterValues(self:SelectedSeasonFilter())
    self.dungeonHistoryFilter = self.dungeonHistoryFilter or "all"
    local validDungeonFilter = false
    for _, option in ipairs(dungeonValues) do
        if option.value == self.dungeonHistoryFilter then
            validDungeonFilter = true
            break
        end
    end
    if not validDungeonFilter then
        self.dungeonHistoryFilter = "all"
    end
    self:SetPageHeader("Dungeon Loot History", "End-of-run Mythic+ gear and per-boss Mythic 0 gear. Data stays on this account.")
    local tabHost = self:Track(CreateFrame("Frame", nil, self.content))
    tabHost:SetPoint("TOPLEFT", 22, -84)
    tabHost:SetPoint("TOPRIGHT", -22, -84)
    tabHost:SetHeight(38)
    local previous
    for _, definition in ipairs({ { key = "recent", label = "Recent" }, { key = "distribution", label = "Distribution" } }) do
        local key = definition.key
        local tab = LV.Widgets:Tab(tabHost, definition.label, 122, 38, function()
            self.historyView = key
            self:Refresh()
        end)
        tab:SetPoint(previous and "LEFT" or "LEFT", previous or tabHost, previous and "RIGHT" or "LEFT", previous and 4 or 0, 0)
        LV.Widgets:SetButtonActive(tab, self.historyView == key)
        previous = tab
    end
    local contentTop = -174
    if self.historyView == "distribution" then
        self:RenderDungeonDistributionFilters(dungeonValues)
        contentTop = -238
    else
        self:CreateHistorySearch(self.content, "dungeonHistorySearch", 24, -139)
    end
    local panel = LV.Widgets:Section(self.content, self.historyView == "distribution" and "Gear by Final Owner" or "Dungeon Gear", 440)
    panel:SetPoint("TOPLEFT", 22, contentTop)
    panel:SetPoint("BOTTOMRIGHT", -22, 22)
    if self.historyView == "distribution" then
        local rows, total = self:DungeonLootDistributionRows()
        self:RenderDistributionMeter(panel, rows, total, self:DungeonDistributionBuckets(), nil, true)
    else
        self:RenderDungeonRecent(panel)
    end
end
