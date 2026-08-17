local _, LV = ...

LV.Loot = {}
LV.modules.Loot = LV.Loot

local lootHistoryScanDelays = { 1, 4, 10, 20, 45 }
local lootHistoryAddOns = {
    "Blizzard_GroupLoot",
    "Blizzard_LootHistory",
    "Blizzard_LootUI",
}
local lootHistoryAPIKeys = {
    "C_LootHistory",
    "C_GroupLootHistory",
    "C_LootRollHistory",
}

local lootHistoryRollTypeLabels = {
    [0] = "pass",
    [1] = "need",
    [2] = "greed",
    [3] = "transmog",
    [4] = "transmog",
}

local sortedLootHistoryRollStateLabels = {
    [0] = "need",
    [1] = "offspec",
    [2] = "transmog",
    [3] = "greed",
    [4] = "noroll",
    [5] = "pass",
}

local function firstField(source, keys)
    if type(source) ~= "table" then
        return nil
    end
    for _, key in ipairs(keys) do
        if source[key] ~= nil and source[key] ~= "" then
            return source[key]
        end
    end
    return nil
end

local rollMethodKeys = {
    "rollState",
    "rollType",
    "response",
    "responseID",
    "responseType",
    "selectedResponse",
    "choice",
    "choiceID",
    "awardReason",
}

local rawRollKeys = {
    "rawRoll",
    "roll",
    "rollValue",
    "rollNumber",
    "winningRoll",
    "winningRollValue",
}

local winnerKeys = {
    "winner",
    "winnerName",
    "player",
    "playerName",
    "recipient",
    "recipientName",
    "looter",
    "looterName",
    "owner",
}

local classKeys = {
    "className",
    "classFileName",
    "class",
    "classFilename",
    "playerClass",
}

local sortedRollStateKeys = {
    "playerRollState",
    "rollState",
    "rollType",
    "response",
    "responseID",
    "responseType",
    "selectedResponse",
    "choice",
    "choiceID",
    "awardReason",
}

local function rollInfoFromSources(...)
    local method = nil
    local rawRoll = nil

    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if type(source) == "table" then
            method = method or firstField(source, rollMethodKeys)
            rawRoll = rawRoll or firstField(source, rawRollKeys)
        end
    end

    if method == rawRoll and type(method) == "number" and not LV.RollStateLabels[method] then
        method = nil
    end

    return method, rawRoll
end

local function fieldFromSources(keys, ...)
    for index = 1, select("#", ...) do
        local value = firstField(select(index, ...), keys)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function tableCount(list)
    local count = 0
    for _ in pairs(list or {}) do
        count = count + 1
    end
    return count
end

local function rollBreakdownMethodCount(list)
    local count = 0
    for _, entry in ipairs(list or {}) do
        if type(entry) == "table" then
            local roll = entry.r or entry.roll or entry.method
            if roll ~= nil then
                roll = tostring(roll)
                if roll ~= "" and not roll:match("^%d+$") then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function stripWoWText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|A:.-|a", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("[\r\n]+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local defaultLootItemExclusions = {
    { key = "id:268650", name = "Ascendant Voidshard" },
    { key = "name:fine void-tempered hide", name = "Fine Void-Tempered Hide" },
}

local function normalizeItemName(value)
    value = stripWoWText(value or "")
    value = value:match("%[(.-)%]") or value
    value = value:gsub("%s+", " ")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value:lower()
end

local function rowItemName(guildKey, row, fallbackName)
    fallbackName = stripWoWText(fallbackName or "")
    if fallbackName ~= "" then
        return fallbackName
    end

    local itemKey = nil
    if type(row) == "table" then
        itemKey = row._itemLink or row.itemLink or row.item
        if guildKey and tonumber(itemKey) then
            itemKey = LV.Store:DictionaryValue(guildKey, "i", itemKey)
        end
    end

    local fromLink = tostring(itemKey or ""):match("%[(.-)%]")
    if fromLink and fromLink ~= "" then
        return fromLink
    end

    local itemID = tonumber(row and row.itemID) or LV.Util:ItemID(itemKey)
    local lookup = itemKey and itemKey ~= "" and itemKey or itemID
    if lookup and type(GetItemInfo) == "function" then
        local result = { pcall(GetItemInfo, lookup) }
        if result[1] and result[2] then
            return result[2]
        end
    end

    return ""
end

local function findItemLink(value, depth)
    depth = tonumber(depth) or 0
    if depth > 4 then
        return nil
    end

    if type(value) == "string" then
        if value:find("|Hitem:", 1, true) or value:find("item:", 1, true) then
            return value
        end
        return nil
    end

    if type(value) ~= "table" then
        return nil
    end

    local direct = firstField(value, { "itemLink", "itemHyperlink", "hyperlink", "link", "item", "itemString" })
    local found = findItemLink(direct, depth + 1)
    if found then
        return found
    end

    for _, child in pairs(value) do
        found = findItemLink(child, depth + 1)
        if found then
            return found
        end
    end
    return nil
end

local function sameItem(itemA, itemB)
    local idA = LV.Util:ItemID(itemA)
    local idB = LV.Util:ItemID(itemB)
    if idA and idB and idA == idB then
        return true
    end
    return LV.Util:ItemKey(itemA) ~= "" and LV.Util:ItemKey(itemA) == LV.Util:ItemKey(itemB)
end

local function normalizeWinnerName(value)
    if type(value) == "string" then
        value = LV.Util:Trim(value)
        if value ~= "" and not value:find("|", 1, true) and not value:find("item:", 1, true) then
            return value
        end
    elseif type(value) == "table" then
        local name = firstField(value, { "winnerName", "playerName", "recipientName", "looterName", "unitName", "fullName", "name" })
        if type(name) == "string" and name ~= "" then
            local realm = firstField(value, { "realm", "server", "realmName" })
            if realm and not name:find("-", 1, true) then
                return name .. "-" .. realm
            end
            return name
        end
    end
    return nil
end

local function normalizeRollEntryName(value)
    if type(value) ~= "table" then
        return nil
    end

    local name = firstField(value, { "playerName", "winnerName", "recipientName", "looterName", "unitName", "fullName" })
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local realm = firstField(value, { "realm", "server", "realmName" })
    if realm and not name:find("-", 1, true) then
        return name .. "-" .. realm
    end

    return name
end

local function normalizeLootHistoryName(name)
    name = normalizeWinnerName(name)
    if not name or name == "" then
        return nil
    end
    if not name:find("-", 1, true) then
        local info = LV.Guild:CurrentInfo()
        name = name .. "-" .. ((info and info.realm) or LV.Util:RealmName())
    end
    return name
end

local function sameLootHistoryName(nameA, nameB)
    local normalizedA = normalizeLootHistoryName(nameA)
    local normalizedB = normalizeLootHistoryName(nameB)
    return normalizedA and normalizedB and normalizedA == normalizedB
end

local function isCurrentPlayerName(name)
    local playerName = LV.Util:PlayerFullName()
    return sameLootHistoryName(name, playerName)
end

local function isWinningRoll(entry)
    if type(entry) ~= "table" then
        return false
    end

    if entry.isWinner == true or entry.won == true or entry.selected == true or entry.awarded == true then
        return true
    end

    local status = tostring(entry.state or entry.status or entry.result or entry.rollState or ""):lower()
    return status == "won" or status == "winner" or status == "awarded"
end

local function findWinnerEntry(value, depth)
    depth = tonumber(depth) or 0
    if type(value) ~= "table" or depth > 4 then
        return nil
    end

    if isWinningRoll(value) and normalizeWinnerName(value) then
        return value
    end

    local direct = firstField(value, { "winner", "winnerInfo", "winningRoll", "awardee" })
    if type(direct) == "table" then
        local found = findWinnerEntry(direct, depth + 1)
        if found then
            return found
        end
        if normalizeWinnerName(direct) then
            return direct
        end
    end

    for _, key in ipairs({ "rolls", "rollList", "players", "candidates", "entries", "results", "lootList" }) do
        local list = value[key]
        if type(list) == "table" then
            for _, child in pairs(list) do
                local found = findWinnerEntry(child, depth + 1)
                if found then
                    return found
                end
            end
        end
    end

    for _, child in pairs(value) do
        if type(child) == "table" then
            local found = findWinnerEntry(child, depth + 1)
            if found then
                return found
            end
        end
    end
    return nil
end

function LV.Loot:NormalizePlayerName(name)
    name = LV.Util:Trim(name)
    if name == "" or name == YOU then
        return LV.Util:PlayerFullName()
    end
    if not name:find("-", 1, true) then
        local info = LV.Guild:CurrentInfo()
        name = name .. "-" .. ((info and info.realm) or LV.Util:RealmName())
    end
    return name
end

function LV.Loot:RollLabel(raw)
    if raw == nil then
        return ""
    end

    if type(raw) == "number" then
        return LV.RollStateLabels[raw] or ""
    end

    local text = LV.Util:Trim(tostring(raw))
    local numeric = tonumber(text)
    if numeric and text:match("^%d+$") then
        return LV.RollStateLabels[numeric] or ""
    end

    local value = text:lower()
    if value:find("off") then
        return "offspec"
    elseif value:find("trans") then
        return "transmog"
    elseif value:find("greed") then
        return "greed"
    elseif value:find("pass") then
        return "pass"
    elseif value:find("no") and value:find("roll") then
        return "noroll"
    elseif value:find("need") then
        return "need"
    end

    return value
end

function LV.Loot:LootHistoryRollLabel(raw)
    if raw == nil then
        return ""
    end

    if type(raw) == "number" then
        return lootHistoryRollTypeLabels[raw] or ""
    end

    local text = LV.Util:Trim(tostring(raw))
    local numeric = tonumber(text)
    if numeric and text:match("^%d+$") then
        return lootHistoryRollTypeLabels[numeric] or ""
    end

    return self:RollLabel(text)
end

function LV.Loot:SortedLootHistoryRollLabel(raw)
    if raw == nil then
        return ""
    end

    if type(raw) == "number" then
        return sortedLootHistoryRollStateLabels[raw] or self:RollLabel(raw)
    end

    local text = LV.Util:Trim(tostring(raw))
    local numeric = tonumber(text)
    if numeric and text:match("^%d+$") then
        return sortedLootHistoryRollStateLabels[numeric] or self:RollLabel(numeric)
    end

    return self:RollLabel(text)
end

function LV.Loot:SortedDropRollInfo(...)
    local roll = nil
    local rawRoll = nil

    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if type(source) == "table" then
            local state = firstField(source, sortedRollStateKeys)
            if roll == nil and state ~= nil then
                local label = self:SortedLootHistoryRollLabel(state)
                if label ~= "" then
                    roll = label
                end
            end
            rawRoll = rawRoll or firstField(source, rawRollKeys)
        end
    end

    return roll, rawRoll
end

function LV.Loot:CollectSortedRollBreakdown(...)
    local entries = {}
    local seen = {}

    local function addEntry(entry)
        local name = normalizeRollEntryName(entry)
        if not name then
            return
        end

        local roll, rawRoll = self:SortedDropRollInfo(entry)
        if not roll or roll == "" then
            roll, rawRoll = rollInfoFromSources(entry)
            roll = self:RollLabel(roll)
        end

        local key = name .. ":" .. tostring(roll or "") .. ":" .. tostring(rawRoll or "")
        if seen[key] then
            return
        end
        seen[key] = true

        entries[#entries + 1] = {
            player = name,
            className = fieldFromSources(classKeys, entry),
            roll = roll,
            rawRoll = rawRoll,
            won = isWinningRoll(entry),
        }
    end

    local function looksLikeRollEntry(entry)
        if type(entry) ~= "table" or not normalizeRollEntryName(entry) then
            return false
        end
        return isWinningRoll(entry)
            or firstField(entry, sortedRollStateKeys) ~= nil
            or firstField(entry, rawRollKeys) ~= nil
    end

    local function walk(value, depth)
        depth = tonumber(depth) or 0
        if type(value) ~= "table" or depth > 5 then
            return
        end

        if looksLikeRollEntry(value) then
            addEntry(value)
        end

        for _, key in ipairs({ "rolls", "rollList", "rollResults", "lootRolls", "players", "candidates", "entries", "results" }) do
            local list = value[key]
            if type(list) == "table" then
                for _, child in pairs(list) do
                    walk(child, depth + 1)
                end
            end
        end

        for _, child in pairs(value) do
            if type(child) == "table" then
                walk(child, depth + 1)
            end
        end
    end

    for index = 1, select("#", ...) do
        walk(select(index, ...), 0)
    end

    return #entries > 1 and entries or nil
end

function LV.Loot:CurrentOrLastEncounterID()
    local session = LV.Raid:GetActiveSession()
    if not session then
        return 0
    end

    for index = #(session.kills or {}), 1, -1 do
        local encounterID = tonumber(session.kills[index].e)
        if encounterID and encounterID > 0 then
            return encounterID
        end
    end

    return 0
end

function LV.Loot:CurrentOrLastEncounterName(encounterID)
    local boss = self:CurrentEncounterName(encounterID)
    if boss ~= "" then
        return boss
    end

    local session = LV.Raid:GetActiveSession()
    if not session then
        return ""
    end

    for index = #(session.kills or {}), 1, -1 do
        local kill = session.kills[index]
        if kill and kill.b then
            local guildKey = LV.Guild:CurrentKey()
            return guildKey and LV.Store:DictionaryValue(guildKey, "s", kill.b) or ""
        end
    end

    return ""
end

function LV.Loot:NormalizeRollBreakdown(guildKey, entries)
    local out = {}
    if type(entries) ~= "table" then
        return nil
    end

    local seen = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local fullName = normalizeLootHistoryName(entry.player or entry.name)
            if fullName then
                local nameID = LV.Store:NameID(guildKey, fullName)
                local className = LV.Util:Trim(entry.className or entry.class or "")
                local rollType = self:RollLabel(entry.roll or entry.method or entry.r)
                local rawRoll = entry.rawRoll or entry.raw
                local key = tostring(nameID) .. ":" .. tostring(rollType) .. ":" .. tostring(rawRoll or "")
                if nameID and not seen[key] then
                    seen[key] = true
                    if className ~= "" then
                        LV.Store:SetPlayerClass(guildKey, nameID, className)
                    end
                    out[#out + 1] = {
                        p = nameID,
                        cls = className ~= "" and LV.Store:StringID(guildKey, className) or nil,
                        r = rollType,
                        raw = rawRoll and tostring(rawRoll) or nil,
                        w = entry.won and 1 or nil,
                    }
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if (a.w and 1 or 0) ~= (b.w and 1 or 0) then
            return a.w and true or false
        end
        local ar = tonumber(a.raw) or -1
        local br = tonumber(b.raw) or -1
        if ar ~= br then
            return ar > br
        end
        return (LV.Store:DictionaryValue(guildKey, "n", a.p) or ""):lower() < (LV.Store:DictionaryValue(guildKey, "n", b.p) or ""):lower()
    end)

    return #out > 0 and out or nil
end

function LV.Loot:WinnerRollFromBreakdown(row, breakdown)
    if type(row) ~= "table" or type(breakdown) ~= "table" then
        return nil, nil, false
    end

    local function rollFrom(entry)
        if type(entry) ~= "table" then
            return nil, nil, false
        end

        local roll = self:RollLabel(entry.r or entry.roll or entry.method)
        local rawRoll = entry.raw or entry.rawRoll
        if (roll and roll ~= "") or rawRoll ~= nil then
            return roll ~= "" and roll or nil, rawRoll, true
        end
        return nil, nil, false
    end

    local fallbackRoll = nil
    local fallbackRawRoll = nil
    local fallbackFound = false

    for _, entry in ipairs(breakdown) do
        if type(entry) == "table" and entry.w then
            local roll, rawRoll, found = rollFrom(entry)
            if found then
                if roll and roll ~= "" then
                    return roll, rawRoll, true
                end
                fallbackRoll = fallbackRoll or roll
                fallbackRawRoll = fallbackRawRoll or rawRoll
                fallbackFound = true
            end
        end
    end

    if row.p then
        for _, entry in ipairs(breakdown) do
            if type(entry) == "table" and entry.p == row.p then
                local roll, rawRoll, found = rollFrom(entry)
                if found then
                    if roll and roll ~= "" then
                        return roll, rawRoll, true
                    end
                    fallbackRoll = fallbackRoll or roll
                    fallbackRawRoll = fallbackRawRoll or rawRoll
                    fallbackFound = true
                end
            end
        end
    end

    if fallbackFound then
        return fallbackRoll, fallbackRawRoll, true
    end

    return nil, nil, false
end

function LV.Loot:Classify(source, rollType, itemLink)
    local boe = false
    local warbound = false

    if source == "trash" and LV.Util:IsItemBoE(itemLink) then
        boe = true
    elseif source == "boss" and (not rollType or rollType == "" or rollType == "noroll") then
        warbound = true
    end

    return boe, warbound
end

function LV.Loot:FindDuplicate(record, fields, windowSeconds)
    local playerID = fields.p
    local itemID = fields.itemID or 0
    local itemKey = fields.item
    local encounterID = fields.e or 0
    local raidID = fields.sid
    local timestamp = fields.ts or LV.Util:Now()
    local duplicateWindow = tonumber(windowSeconds) or 8

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        if timestamp - (tonumber(row.ts) or 0) > duplicateWindow then
            break
        end

        local rowItemID = tonumber(row.itemID) or 0
        local sameItemID = rowItemID > 0 and itemID > 0 and rowItemID == itemID
        local sameItemKey = row.item ~= nil and itemKey ~= nil and row.item == itemKey
        local samePlayerItem = row.p == playerID and (sameItemID or sameItemKey)
        local sameRaid = not raidID or not row.sid or row.sid == raidID
        local rowEncounterID = tonumber(row.e) or 0
        local sameEncounter = rowEncounterID == 0 or encounterID == 0 or rowEncounterID == encounterID
        local sameSource = row.src == fields.src

        if samePlayerItem and sameRaid and (sameEncounter or sameSource) then
            return row
        end
    end

    return nil
end

function LV.Loot:HasRecentLoot(record, playerID, itemID, itemKey, timestamp, windowSeconds)
    timestamp = tonumber(timestamp) or LV.Util:Now()
    windowSeconds = tonumber(windowSeconds) or 15

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        local delta = math.abs(timestamp - (tonumber(row.ts) or 0))
        if delta > windowSeconds and timestamp > (tonumber(row.ts) or 0) then
            break
        end

        if row.p == playerID and (row.itemID or 0) == itemID and row.item == itemKey and delta <= windowSeconds then
            return true
        end
    end

    return false
end

function LV.Loot:AddLootEvent(fields)
    local session, _, guildKey = LV.Raid:GetActiveSession()
    if not session or not guildKey then
        return nil
    end

    local record = LV.Store:GuildRecord(guildKey)
    local itemLink = fields.itemLink or fields.item or ""
    local rollBreakdown = self:NormalizeRollBreakdown(guildKey, fields.rollBreakdown)
    local playerID = LV.Store:NameID(guildKey, self:NormalizePlayerName(fields.player))
    local rollType = self:RollLabel(fields.roll)
    local rawRoll = fields.rawRoll
    local rollSource = fields.rollSource
    local winnerRoll, winnerRawRoll, winnerRollFound = self:WinnerRollFromBreakdown({ p = playerID }, rollBreakdown)
    if winnerRoll and winnerRoll ~= "" then
        rollType = winnerRoll
        rollSource = "winner"
    end
    if winnerRollFound and winnerRawRoll ~= nil then
        rawRoll = winnerRawRoll or rawRoll
        rollSource = "winner"
    end
    local boe, warbound = self:Classify(fields.src, rollType, itemLink)

    local row = {
        ts = tonumber(fields.ts) or LV.Util:Now(),
        sid = session.id,
        e = tonumber(fields.encounterID) or tonumber(fields.e) or 0,
        iid = tonumber(fields.instanceID) or 0,
        inst = LV.Store:StringID(guildKey, fields.instance or ""),
        boss = LV.Store:StringID(guildKey, fields.boss or ""),
        did = tonumber(fields.difficultyID) or 0,
        diff = LV.Store:StringID(guildKey, fields.difficulty or ""),
        p = playerID,
        cls = LV.Store:StringID(guildKey, fields.className or ""),
        item = LV.Store:ItemID(guildKey, itemLink),
        itemID = tonumber(fields.itemID) or LV.Util:ItemID(itemLink) or 0,
        _itemLink = itemLink,
        q = tonumber(fields.quantity) or 1,
        r = rollType,
        raw = rawRoll and tostring(rawRoll) or nil,
        src = fields.src or "unknown",
        boe = boe and 1 or nil,
        wb = warbound and 1 or nil,
        rb = rollBreakdown,
        by = LV.Store:NameID(guildKey, LV.Util:PlayerFullName()),
    }

    if not row.p or not row.item then
        return nil
    end
    if self:IsLootExcluded(guildKey, row) then
        return nil
    end
    row._itemLink = nil
    if row.cls and fields.className and fields.className ~= "" then
        LV.Store:SetPlayerClass(guildKey, row.p, fields.className)
    end

    local duplicate = self:FindDuplicate(record, row, fields.dedupeSeconds)
    if duplicate then
        local duplicateRoll = tostring(duplicate.r or "")
        if row.r ~= "" and (rollSource == "winner" or duplicateRoll == "" or duplicateRoll:match("^%d+$")) then
            duplicate.r = row.r
        end
        if rollSource == "winner" and row.raw then
            duplicate.raw = row.raw
        else
            duplicate.raw = duplicate.raw or row.raw
        end
        duplicate.boe = duplicate.boe or row.boe
        duplicate.wb = duplicate.wb or row.wb
        if row.rb and (
            not duplicate.rb
            or tableCount(duplicate.rb) < tableCount(row.rb)
            or rollBreakdownMethodCount(duplicate.rb) < rollBreakdownMethodCount(row.rb)
        ) then
            duplicate.rb = row.rb
        end
        if (tonumber(duplicate.e) or 0) == 0 and (tonumber(row.e) or 0) > 0 then
            duplicate.e = row.e
        end
        if (tonumber(duplicate.iid) or 0) == 0 and (tonumber(row.iid) or 0) > 0 then
            duplicate.iid = row.iid
        end
        if (tonumber(duplicate.did) or 0) == 0 and (tonumber(row.did) or 0) > 0 then
            duplicate.did = row.did
        end
        if (not duplicate.inst or duplicate.inst == 0) and row.inst then
            duplicate.inst = row.inst
        end
        if (not duplicate.boss or duplicate.boss == 0) and row.boss then
            duplicate.boss = row.boss
        end
        if (not duplicate.diff or duplicate.diff == 0) and row.diff then
            duplicate.diff = row.diff
        end
        if (not duplicate.cls or duplicate.cls == 0) and row.cls then
            duplicate.cls = row.cls
        end
        if row.src == "boss" then
            duplicate.src = "boss"
        end
        return duplicate
    end

    row.id = LV.Store:NewID(record, "loot", "l")
    table.insert(record.l, row)

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return row
end

function LV.Loot:CurrentEncounterName(encounterID)
    local session = LV.Raid:GetActiveSession()
    if not session then
        return ""
    end

    for index = #session.kills, 1, -1 do
        local kill = session.kills[index]
        if tonumber(kill.e) == tonumber(encounterID) then
            local guildKey = LV.Guild:CurrentKey()
            return guildKey and LV.Store:DictionaryValue(guildKey, "s", kill.b) or ""
        end
    end

    return ""
end

function LV.Loot:RecordEncounterLoot(encounterID, itemID, itemLink, quantity, recipientName, className)
    local instance = LV.Util:CurrentInstance()
    self:AddLootEvent({
        ts = LV.Util:Now(),
        encounterID = encounterID,
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        player = recipientName,
        className = className,
        instanceID = instance.instanceID,
        instance = instance.name,
        difficultyID = instance.difficultyID,
        difficulty = instance.difficultyName,
        boss = self:CurrentEncounterName(encounterID),
        src = "boss",
    })
end

function LV.Loot:RecordChatLoot(message)
    if not LV.Raid:GetActiveSession() then
        return
    end

    local itemLink = tostring(message or ""):match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    if not itemLink then
        return
    end

    local player = tostring(message or ""):match("^(.+) receives loot:")
    if not player then
        player = tostring(message or ""):match("^(.+) receives item:")
    end
    if not player and tostring(message or ""):find("You receive") then
        player = LV.Util:PlayerFullName()
    end
    if not player then
        return
    end

    local seenAt = LV.Util:Now()
    C_Timer.After(4, function()
        local session, _, guildKey = LV.Raid:GetActiveSession()
        if not session or not guildKey then
            return
        end

        local record = LV.Store:GuildRecord(guildKey)
        local normalizedPlayer = self:NormalizePlayerName(player)
        local playerID = LV.Store:NameID(guildKey, normalizedPlayer)
        local itemID = LV.Util:ItemID(itemLink) or 0
        local itemKey = LV.Store:ItemID(guildKey, itemLink)
        if self:HasRecentLoot(record, playerID, itemID, itemKey, seenAt, 15) then
            return
        end

        local instance = LV.Util:CurrentInstance()
        self:AddLootEvent({
            ts = seenAt,
            itemLink = itemLink,
            player = normalizedPlayer,
            instanceID = instance.instanceID,
            instance = instance.name,
            difficultyID = instance.difficultyID,
            difficulty = instance.difficultyName,
            src = "trash",
        })
    end)
end

function LV.Loot:RecordRollWon(itemLink, rollQuantity, rollType, roll, upgraded)
    if not itemLink then
        return
    end

    local instance = LV.Util:CurrentInstance()
    self:AddLootEvent({
        ts = LV.Util:Now(),
        itemLink = itemLink,
        player = LV.Util:PlayerFullName(),
        instanceID = instance.instanceID,
        instance = instance.name,
        difficultyID = instance.difficultyID,
        difficulty = instance.difficultyName,
        quantity = tonumber(rollQuantity) or 1,
        roll = self:RollLabel(rollType),
        rawRoll = roll,
        src = "roll",
    })
end

function LV.Loot:RecordLootRollStart(rollID)
    rollID = tonumber(rollID)
    if not rollID then
        return
    end

    local itemLink = nil
    if type(GetLootRollItemLink) == "function" then
        local ok, link = pcall(GetLootRollItemLink, rollID)
        if ok then
            itemLink = link
        end
    end

    local itemName, texture, quantity, quality, canNeed, canGreed, canDisenchant, canTransmog
    if type(GetLootRollItemInfo) == "function" then
        local result = { pcall(GetLootRollItemInfo, rollID) }
        if result[1] then
            texture = result[2]
            itemName = result[3]
            quantity = result[4]
            quality = result[5]
            canNeed = result[7]
            canGreed = result[8]
            canDisenchant = result[9]
            canTransmog = result[14]
        end
    end

    if not itemLink then
        return
    end

    self.rollFrames = self.rollFrames or {}
    local instance = LV.Util:CurrentInstance()
    local encounterID = self:CurrentOrLastEncounterID()
    self.rollFrames[rollID] = {
        ts = LV.Util:Now(),
        itemLink = itemLink,
        itemID = LV.Util:ItemID(itemLink) or 0,
        itemName = itemName,
        texture = texture,
        quantity = quantity,
        quality = quality,
        canNeed = canNeed and 1 or nil,
        canGreed = canGreed and 1 or nil,
        canDisenchant = canDisenchant and 1 or nil,
        canTransmog = canTransmog and 1 or nil,
        encounterID = encounterID,
        boss = encounterID > 0 and self:CurrentEncounterName(encounterID) or "",
        instanceID = instance.instanceID,
        instance = instance.name,
        difficultyID = instance.difficultyID,
        difficulty = instance.difficultyName,
    }
end

function LV.Loot:LootHistoryAPI()
    for _, key in ipairs(lootHistoryAPIKeys) do
        local api = _G and _G[key]
        if type(api) == "table" then
            return api, key
        end
    end

    if not self.triedLoadLootHistoryAddOns then
        self.triedLoadLootHistoryAddOns = true
        self.lootHistoryAddOnLoadResults = {}
        for _, addonName in ipairs(lootHistoryAddOns) do
            local ok, loaded, reason = false, false, "no loader"
            if C_AddOns and C_AddOns.LoadAddOn then
                ok, loaded, reason = pcall(C_AddOns.LoadAddOn, addonName)
            elseif type(LoadAddOn) == "function" then
                ok, loaded, reason = pcall(LoadAddOn, addonName)
            end
            local status = ok and loaded and "loaded" or tostring(reason or loaded or "unavailable")
            self.lootHistoryAddOnLoadResults[#self.lootHistoryAddOnLoadResults + 1] = addonName .. "=" .. status
        end
    end

    for _, key in ipairs(lootHistoryAPIKeys) do
        local api = _G and _G[key]
        if type(api) == "table" then
            return api, key
        end
    end

    return nil, nil
end

function LV.Loot:CollectFullLootHistoryItems()
    local items = {}
    local api = self:LootHistoryAPI()
    if not api or not api.GetNumItems or not api.GetItem or not api.GetPlayerInfo then
        return items
    end

    local okCount, count = pcall(api.GetNumItems)
    if not okCount then
        return items
    end

    count = tonumber(count) or 0
    for itemIndex = 1, count do
        local okItem, rollID, itemLink, numPlayers, isDone, winnerIndex = pcall(api.GetItem, itemIndex)
        if okItem and itemLink then
            local item = {
                rollID = rollID,
                itemLink = itemLink,
                itemID = LV.Util:ItemID(itemLink) or 0,
                rollBreakdown = {},
                isDone = isDone and true or false,
            }

            numPlayers = tonumber(numPlayers) or 0
            for playerIndex = 1, numPlayers do
                local okPlayer, name, className, rollType, rawRoll, isWinner = pcall(api.GetPlayerInfo, itemIndex, playerIndex)
                if okPlayer and name then
                    local method = self:LootHistoryRollLabel(rollType)
                    local entry = {
                        player = name,
                        className = className,
                        roll = method,
                        rawRoll = rawRoll,
                        won = isWinner and true or playerIndex == tonumber(winnerIndex),
                    }
                    item.rollBreakdown[#item.rollBreakdown + 1] = entry
                    if entry.won then
                        item.player = name
                        item.className = className
                        item.roll = method
                        item.rawRoll = rawRoll
                    end
                end
            end

            local anchor = self.rollFrames and self.rollFrames[rollID]
            if anchor then
                item.encounterID = anchor.encounterID
                item.boss = anchor.boss
                item.instanceID = anchor.instanceID
                item.instance = anchor.instance
                item.difficultyID = anchor.difficultyID
                item.difficulty = anchor.difficulty
            end

            items[#items + 1] = item
        end
    end

    return items
end

local function debugValue(value)
    if type(value) == "table" then
        local parts = {}
        local count = 0
        for key, child in pairs(value) do
            count = count + 1
            if count > 6 then
                parts[#parts + 1] = "..."
                break
            end
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(child)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

function LV.Loot:DebugLootHistoryGlobals()
    local names = {}
    if not _G then
        return
    end

    for key, value in pairs(_G) do
        if type(key) == "string" then
            local lower = key:lower()
            if lower:find("loothistory", 1, true) or lower:find("grouploot", 1, true) or lower:find("lootroll", 1, true) then
                names[#names + 1] = key .. ":" .. type(value)
                if #names >= 12 then
                    break
                end
            end
        end
    end

    LV:Print("Loot history globals: " .. (#names > 0 and table.concat(names, ", ") or "none found"))
end

function LV.Loot:CollectLootHistoryFrames()
    local frames = {}
    local seen = {}

    local function isFrame(value)
        return type(value) == "table" and type(value.GetObjectType) == "function"
    end

    local function isLootHistoryRootName(key)
        key = tostring(key or "")
        return key:match("^GroupLootHistoryFrame")
    end

    local function addFrame(frame)
        if not isFrame(frame) or seen[frame] then
            return
        end

        seen[frame] = true
        frames[#frames + 1] = frame

        if type(frame.GetChildren) == "function" then
            local ok, children = pcall(function()
                return { frame:GetChildren() }
            end)
            if ok and type(children) == "table" then
                for _, child in ipairs(children) do
                    addFrame(child)
                end
            end
        end
    end

    local function walkKnownTable(value, depth)
        depth = tonumber(depth) or 0
        if type(value) ~= "table" or seen[value] or depth > 3 then
            return
        end

        if isFrame(value) then
            addFrame(value)
            return
        end

        seen[value] = true

        local checked = 0
        for _, child in pairs(value) do
            checked = checked + 1
            if checked > 120 then
                break
            end

            if isFrame(child) then
                addFrame(child)
            elseif type(child) == "table" and depth < 2 then
                walkKnownTable(child, depth + 1)
            end
        end
    end

    if _G then
        for key, value in pairs(_G) do
            if type(key) == "string" and isLootHistoryRootName(key) then
                walkKnownTable(value, 0)
            end
        end
    end

    return frames
end

function LV.Loot:TooltipLines(tooltip)
    local lines = {}
    if not tooltip or not tooltip.GetName then
        return lines
    end

    local name = tooltip:GetName()
    if not name then
        return lines
    end
    local count = type(tooltip.NumLines) == "function" and tooltip:NumLines() or 0
    for index = 1, tonumber(count) or 0 do
        local left = _G[name .. "TextLeft" .. tostring(index)]
        local right = _G[name .. "TextRight" .. tostring(index)]
        lines[#lines + 1] = {
            left = left and left.GetText and stripWoWText(left:GetText()) or "",
            right = right and right.GetText and stripWoWText(right:GetText()) or "",
        }
    end
    return lines
end

function LV.Loot:ParseLootRollTooltipLines(lines)
    local entries = {}
    local seen = {}

    local function add(rawRoll, playerText)
        rawRoll = LV.Util:Trim(rawRoll or "")
        playerText = stripWoWText(playerText or "")
        if rawRoll == "" or playerText == "" then
            return
        end

        local methodText = playerText:match("%(([^%)]+)%)") or ""
        local player = playerText:gsub("%b()", "")
        player = player:gsub("\226\156\147", "")
        player = player:gsub("\226\156\148", "")
        player = player:gsub("^%s+", "")
        player = player:gsub("%s+$", "")
        if player == "" then
            return
        end

        local method = self:RollLabel(methodText)
        local key = player:lower() .. ":" .. rawRoll .. ":" .. method
        if seen[key] then
            return
        end
        seen[key] = true

        entries[#entries + 1] = {
            player = player,
            roll = method,
            rawRoll = rawRoll,
        }
    end

    for _, line in ipairs(lines or {}) do
        local left = stripWoWText(line.left)
        local right = stripWoWText(line.right)
        if left:match("^%d+$") and right ~= "" then
            add(left, right)
        end

        for _, text in ipairs({ left, right, left .. " " .. right }) do
            local rawRoll, playerText = stripWoWText(text):match("^(%d+)%s+(.+)$")
            if rawRoll and playerText then
                add(rawRoll, playerText)
            end
        end
    end

    return #entries > 0 and entries or nil
end

function LV.Loot:CollectLootHistoryFrameItems(filter)
    filter = LV.Util:Trim(filter or ""):lower()
    local items = {}
    local seen = {}
    local scanned = 0

    if not GameTooltip then
        return items, scanned
    end

    for _, frame in ipairs(self:CollectLootHistoryFrames()) do
        if type(frame.GetScript) == "function" then
            local onEnter = frame:GetScript("OnEnter")
            if type(onEnter) == "function" then
                scanned = scanned + 1
                GameTooltip:Hide()
                local ok = pcall(onEnter, frame)
                if ok then
                    local itemName, itemLink = nil, nil
                    if type(GameTooltip.GetItem) == "function" then
                        itemName, itemLink = GameTooltip:GetItem()
                    end
                    itemLink = itemLink or findItemLink(frame)
                    local lines = self:TooltipLines(GameTooltip)
                    local rollBreakdown = self:ParseLootRollTooltipLines(lines)
                    local haystack = tostring(itemName or itemLink or ""):lower()
                    for _, line in ipairs(lines) do
                        haystack = haystack .. " " .. tostring(line.left or ""):lower() .. " " .. tostring(line.right or ""):lower()
                    end
                    if itemLink and rollBreakdown and (filter == "" or haystack:find(filter, 1, true)) then
                        local key = LV.Util:ItemKey(itemLink) .. ":" .. tostring(#rollBreakdown)
                        for _, entry in ipairs(rollBreakdown) do
                            key = key .. ":" .. tostring(entry.player) .. ":" .. tostring(entry.roll) .. ":" .. tostring(entry.rawRoll)
                        end
                        if not seen[key] then
                            seen[key] = true
                            items[#items + 1] = {
                                itemLink = itemLink,
                                itemName = itemName,
                                rollBreakdown = rollBreakdown,
                                frameName = frame.GetName and frame:GetName() or tostring(frame),
                            }
                        end
                    end
                end
                GameTooltip:Hide()
            end
        end
    end

    return items, scanned
end

function LV.Loot:RollEntryForPlayer(entries, playerName)
    for _, entry in ipairs(entries or {}) do
        if type(entry) == "table" and sameLootHistoryName(entry.player, playerName) then
            return entry
        end
    end
    return nil
end

function LV.Loot:BreakdownWithWinner(entries, winnerName)
    local out = {}
    for _, entry in ipairs(entries or {}) do
        if type(entry) == "table" then
            out[#out + 1] = {
                player = entry.player,
                className = entry.className,
                roll = entry.roll,
                rawRoll = entry.rawRoll,
                won = sameLootHistoryName(entry.player, winnerName),
            }
        end
    end
    return out
end

function LV.Loot:EnrichActiveRaidLootFromLootHistoryFrames()
    local session, record, guildKey = LV.Raid:GetActiveSession()
    if not session or not record or not guildKey then
        return 0, 0
    end

    local items = self:CollectLootHistoryFrameItems()
    local updated = 0
    for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.itemLink and type(item.rollBreakdown) == "table" then
            for _, row in ipairs(record.l or {}) do
                if type(row) == "table" and row.sid == session.id then
                    local rowItem = LV.Store:DictionaryValue(guildKey, "i", row.item)
                    if sameItem(rowItem, item.itemLink) then
                        local rowName = LV.Store:DictionaryValue(guildKey, "n", row.p)
                        local winnerEntry = self:RollEntryForPlayer(item.rollBreakdown, rowName)
                        if winnerEntry then
                            local patchItem = {
                                itemLink = item.itemLink,
                                player = rowName,
                                roll = winnerEntry.roll,
                                rawRoll = winnerEntry.rawRoll,
                                rollBreakdown = self:BreakdownWithWinner(item.rollBreakdown, rowName),
                            }
                            if self:ApplyFullHistoryItemToRow(guildKey, row, patchItem) then
                                updated = updated + 1
                            end
                        end
                    end
                end
            end
        end
    end

    return updated, #(items or {})
end

function LV.Loot:DebugLootHistoryFrames(filter)
    local items, scanned = self:CollectLootHistoryFrameItems(filter)
    LV:Print("Loot history frame scan: " .. tostring(#items) .. " item(s), " .. tostring(scanned) .. " tooltip frame(s).")
    for index, item in ipairs(items) do
        if index > 4 then
            LV:Print("  +" .. tostring(#items - 4) .. " more item(s)")
            break
        end
        LV:Print("  " .. tostring(item.itemLink or item.itemName or "item") .. " from " .. tostring(item.frameName or "frame"))
        local parts = {}
        for entryIndex, entry in ipairs(item.rollBreakdown or {}) do
            if entryIndex > 6 then
                parts[#parts + 1] = "..."
                break
            end
            local method = self:RollLabel(entry.roll)
            parts[#parts + 1] = tostring(entry.player) .. "=" .. (method ~= "" and (method .. " ") or "") .. tostring(entry.rawRoll or "")
        end
        LV:Print("    " .. table.concat(parts, ", "))
    end
end

function LV.Loot:DebugLootWindow(filter)
    filter = LV.Util:Trim(filter or ""):lower()
    local api, apiName = self:LootHistoryAPI()
    if not api or not api.GetNumItems or not api.GetItem or not api.GetPlayerInfo then
        LV:Print("Loot history API is not available after loading Blizzard loot UI.")
        if self.lootHistoryAddOnLoadResults then
            LV:Print("Loot UI load: " .. table.concat(self.lootHistoryAddOnLoadResults, ", "))
        end
        self:DebugLootHistoryGlobals()
        self:DebugLootHistoryFrames(filter)
        return
    end

    LV:Print("Loot history API: " .. tostring(apiName))

    local okCount, count = pcall(api.GetNumItems)
    count = okCount and tonumber(count) or 0
    if count <= 0 then
        LV:Print("No Blizzard /loot rows available.")
        return
    end

    local printed = 0
    for itemIndex = 1, count do
        local okItem, rollID, itemLink, numPlayers, isDone, winnerIndex = pcall(api.GetItem, itemIndex)
        if okItem and itemLink then
            local haystack = tostring(itemLink):lower()
            local rows = {}
            numPlayers = tonumber(numPlayers) or 0
            for playerIndex = 1, numPlayers do
                local result = { pcall(api.GetPlayerInfo, itemIndex, playerIndex) }
                if result[1] then
                    haystack = haystack .. " " .. tostring(result[2] or ""):lower()
                    rows[#rows + 1] = result
                end
            end

            if filter == "" or haystack:find(filter, 1, true) then
                printed = printed + 1
                LV:Print("Loot #" .. tostring(itemIndex) .. " rollID=" .. tostring(rollID) .. " winnerIndex=" .. tostring(winnerIndex) .. " done=" .. tostring(isDone) .. " item=" .. tostring(itemLink))
                for _, result in ipairs(rows) do
                    local fields = {}
                    for index = 2, #result do
                        fields[#fields + 1] = tostring(index - 1) .. "=" .. debugValue(result[index])
                    end
                    LV:Print("  " .. table.concat(fields, " | "))
                end
                if printed >= 3 then
                    break
                end
            end
        end
    end

    if printed == 0 then
        LV:Print("No /loot rows matched '" .. filter .. "'.")
    end
end

function LV.Loot:FindFullLootHistoryItem(items, itemLink, winner)
    local normalizedWinner = normalizeLootHistoryName(winner)
    local fallback = nil

    for _, item in ipairs(items or {}) do
        if not item._used and sameItem(item.itemLink, itemLink) then
            if normalizedWinner and normalizeLootHistoryName(item.player) == normalizedWinner then
                item._used = true
                return item
            end
            fallback = fallback or item
        end
    end

    if fallback and not normalizedWinner then
        fallback._used = true
        return fallback
    end

    return nil
end

function LV.Loot:LootExcludeKey(row)
    if type(row) ~= "table" then
        return nil
    end

    local playerID = tonumber(row.p) or 0
    local itemID = tonumber(row.itemID) or 0
    local itemKeyID = tonumber(row.item) or 0
    if playerID <= 0 or (itemID <= 0 and itemKeyID <= 0) then
        return nil
    end

    local itemPart = itemID > 0 and ("id:" .. tostring(itemID)) or ("key:" .. tostring(itemKeyID))
    return tostring(tonumber(row.e) or 0)
        .. "|"
        .. itemPart
        .. "|"
        .. tostring(playerID)
end

function LV.Loot:LootExclusions(record)
    if type(record) ~= "table" then
        return nil
    end
    if type(record.x) ~= "table" then
        record.x = {}
    end
    if type(record.x.loot) ~= "table" then
        record.x.loot = {}
    end
    return record.x.loot
end

function LV.Loot:LootItemExclusions(record)
    if type(record) ~= "table" then
        return nil
    end
    if type(record.x) ~= "table" then
        record.x = {}
    end
    if type(record.x.items) ~= "table" then
        record.x.items = {}
    end
    if type(record.x.itemSeed) ~= "table" then
        record.x.itemSeed = {}
    end

    for _, item in ipairs(defaultLootItemExclusions) do
        if item.key and not record.x.itemSeed[item.key] then
            record.x.items[item.key] = {
                name = item.name,
                default = 1,
            }
            record.x.itemSeed[item.key] = 1
        end
    end

    return record.x.items
end

function LV.Loot:LootItemExcludeKey(guildKey, row, fallbackName)
    if type(row) ~= "table" then
        return nil
    end

    local itemKey = row._itemLink or row.itemLink
    if not itemKey and guildKey and row.item then
        itemKey = LV.Store:DictionaryValue(guildKey, "i", row.item)
    end

    local itemID = tonumber(row.itemID) or LV.Util:ItemID(itemKey)
    if itemID and itemID > 0 then
        return "id:" .. tostring(itemID)
    end

    local itemName = normalizeItemName(fallbackName or rowItemName(guildKey, row))
    if itemName ~= "" then
        return "name:" .. itemName
    end

    return nil
end

function LV.Loot:IsLootItemExcluded(guildKey, row)
    local record = LV.Store:GuildRecord(guildKey)
    if not record then
        return false
    end

    local exclusions = self:LootItemExclusions(record)
    if type(exclusions) ~= "table" then
        return false
    end

    local key = self:LootItemExcludeKey(guildKey, row)
    if key and exclusions[key] then
        return true
    end

    local itemName = normalizeItemName(rowItemName(guildKey, row))
    if itemName ~= "" and exclusions["name:" .. itemName] then
        return true
    end

    return false
end

function LV.Loot:IsLootExcluded(guildKey, row)
    local record = LV.Store:GuildRecord(guildKey)
    local key = self:LootExcludeKey(row)
    if not record then
        return false
    end

    local exclusions = record.x and record.x.loot
    if key and type(exclusions) == "table" and exclusions[key] then
        return true
    end

    return self:IsLootItemExcluded(guildKey, row)
end

function LV.Loot:ExcludeLootRow(guildKey, lootID)
    local record = LV.Store:GuildRecord(guildKey)
    if not record or not lootID then
        return false
    end

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        if type(row) == "table" and row.id == lootID then
            local key = self:LootExcludeKey(row)
            if key then
                local exclusions = self:LootExclusions(record)
                exclusions[key] = 1
            end

            local itemLink = LV.Store:DictionaryValue(guildKey, "i", row.item)
            for _, trade in ipairs(record.t or {}) do
                if type(trade) == "table" and trade.loot == row.id then
                    trade.loot = nil
                end
            end
            table.remove(record.l, index)

            LV:Print("Excluded loot: " .. tostring(itemLink ~= "" and itemLink or "item") .. ".")
            if LV.UI and LV.UI.Refresh then
                LV.UI:Refresh()
            end
            return true
        end
    end

    return false
end

function LV.Loot:ExcludeLootItem(guildKey, row, fallbackName)
    local record = LV.Store:GuildRecord(guildKey)
    if not record or type(row) ~= "table" then
        return false
    end

    local key = self:LootItemExcludeKey(guildKey, row, fallbackName)
    if not key then
        LV:Print("Could not identify that item for exclusion.")
        return false
    end

    local itemName = rowItemName(guildKey, row, fallbackName)
    if itemName == "" then
        itemName = key
    end

    local exclusions = self:LootItemExclusions(record)
    exclusions[key] = {
        name = itemName,
        itemID = tonumber(row.itemID) or nil,
    }

    local removed = 0
    local removedLoot = {}
    for index = #record.l, 1, -1 do
        local lootRow = record.l[index]
        if type(lootRow) == "table" and self:LootItemExcludeKey(guildKey, lootRow) == key then
            if lootRow.id then
                removedLoot[lootRow.id] = true
            end
            table.remove(record.l, index)
            removed = removed + 1
        end
    end

    for _, trade in ipairs(record.t or {}) do
        if type(trade) == "table" and trade.loot and removedLoot[trade.loot] then
            trade.loot = nil
        end
    end

    LV:Print("Excluded item: " .. tostring(itemName) .. " (" .. tostring(removed) .. " row(s)).")
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return true
end

function LV.Loot:UnexcludeLootItem(guildKey, key)
    local record = LV.Store:GuildRecord(guildKey)
    if not record or not key then
        return false
    end

    local exclusions = self:LootItemExclusions(record)
    local entry = exclusions and exclusions[key]
    if not entry then
        return false
    end

    local name = type(entry) == "table" and entry.name or tostring(entry)
    exclusions[key] = nil
    LV:Print("Allowed item again: " .. tostring(name or key) .. ". Rebuild loot to restore matching rows.")
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return true
end

function LV.Loot:ExcludedLootItems(guildKey)
    local record = LV.Store:GuildRecord(guildKey)
    local exclusions = record and self:LootItemExclusions(record)
    local out = {}

    for key, entry in pairs(exclusions or {}) do
        local name = type(entry) == "table" and entry.name or tostring(entry)
        if name == "" then
            name = key
        end
        out[#out + 1] = {
            key = key,
            name = name,
            default = type(entry) == "table" and entry.default or nil,
        }
    end

    table.sort(out, function(a, b)
        return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
    end)

    return out
end

function LV.Loot:WipeActiveRaidLoot(silent)
    local session, record = LV.Raid:GetActiveSession()
    if not session or not record then
        LV:Print("No active LootViewer raid.")
        return 0
    end

    local raidID = session.id
    local removed = 0
    local removedLoot = {}

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        if type(row) == "table" and row.sid == raidID then
            if row.id then
                removedLoot[row.id] = true
            end
            table.remove(record.l, index)
            removed = removed + 1
        end
    end

    for _, trade in ipairs(record.t or {}) do
        if type(trade) == "table" and trade.loot and removedLoot[trade.loot] then
            trade.loot = nil
        end
    end

    if not silent then
        LV:Print("Wiped " .. tostring(removed) .. " loot row(s) for the active raid.")
    end
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return removed
end

function LV.Loot:WipeAllLoot()
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey then
        LV:Print("You are not currently in a guild.")
        return 0
    end

    local record = LV.Store:GuildRecord(guildKey)
    if not record then
        LV:Print("No guild record found.")
        return 0
    end

    local removed = #(record.l or {})
    record.l = {}

    for _, trade in ipairs(record.t or {}) do
        if type(trade) == "table" then
            trade.loot = nil
        end
    end

    LV:Print("Wiped " .. tostring(removed) .. " loot row(s) for the current guild.")
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return removed
end

function LV.Loot:ImportFullLootHistoryWindow()
    local session = LV.Raid:GetActiveSession()
    if not session then
        return 0
    end

    local items = self:CollectFullLootHistoryItems()
    local instance = LV.Util:CurrentInstance()
    local imported = 0

    for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.itemLink and item.player then
            local encounterID = tonumber(item.encounterID) or self:CurrentOrLastEncounterID()
            local row = self:AddLootEvent({
                ts = item.ts or LV.Util:Now(),
                encounterID = encounterID,
                itemID = item.itemID,
                itemLink = item.itemLink,
                quantity = item.quantity or 1,
                player = item.player,
                className = item.className,
                instanceID = tonumber(item.instanceID) or instance.instanceID,
                instance = item.instance or instance.name,
                difficultyID = tonumber(item.difficultyID) or instance.difficultyID,
                difficulty = item.difficulty or instance.difficultyName,
                boss = (item.boss and item.boss ~= "" and item.boss) or self:CurrentOrLastEncounterName(encounterID),
                roll = item.roll,
                rawRoll = item.rawRoll,
                rollSource = item.roll and item.roll ~= "" and "winner" or nil,
                rollBreakdown = item.rollBreakdown,
                src = "boss",
                dedupeSeconds = 10 * 60,
            })
            if row then
                imported = imported + 1
            end
        end
    end

    return imported
end

function LV.Loot:ApplyFullHistoryItemToRow(guildKey, row, item)
    if type(row) ~= "table" or type(item) ~= "table" then
        return false
    end

    local changed = false
    if item.roll and item.roll ~= "" then
        if row.r ~= item.roll then
            row.r = item.roll
            changed = true
        end
        if item.rawRoll and tostring(row.raw or "") ~= tostring(item.rawRoll) then
            row.raw = tostring(item.rawRoll)
            changed = true
        end
    end

    local breakdown = self:NormalizeRollBreakdown(guildKey, item.rollBreakdown)
    if breakdown and (
        not row.rb
        or tableCount(row.rb) < tableCount(breakdown)
        or rollBreakdownMethodCount(row.rb) < rollBreakdownMethodCount(breakdown)
    ) then
        row.rb = breakdown
        changed = true
    end

    local winnerRoll, winnerRawRoll, winnerRollFound = self:WinnerRollFromBreakdown(row, breakdown or row.rb)
    if winnerRoll and winnerRoll ~= "" then
        if row.r ~= winnerRoll then
            row.r = winnerRoll
            changed = true
        end
    end
    if winnerRollFound and winnerRawRoll ~= nil then
        if tostring(row.raw or "") ~= tostring(winnerRawRoll) then
            row.raw = tostring(winnerRawRoll)
            changed = true
        end
    end

    if item.className and item.className ~= "" and row.p then
        LV.Store:SetPlayerClass(guildKey, row.p, item.className)
        local classID = LV.Store:StringID(guildKey, item.className)
        if row.cls ~= classID then
            row.cls = classID
            changed = true
        end
    end

    return changed
end

function LV.Loot:FindActiveRaidLootRowForHistoryItem(record, guildKey, raidID, item)
    if type(record) ~= "table" or type(item) ~= "table" or not item.itemLink then
        return nil
    end

    local itemWinner = normalizeLootHistoryName(item.player)
    local fallback = nil
    for _, row in ipairs(record.l or {}) do
        if type(row) == "table" and row.sid == raidID and not row._lvHistoryMatched then
            local rowItem = LV.Store:DictionaryValue(guildKey, "i", row.item)
            if sameItem(rowItem, item.itemLink) then
                local rowWinner = normalizeLootHistoryName(LV.Store:DictionaryValue(guildKey, "n", row.p))
                if itemWinner and rowWinner == itemWinner then
                    return row
                end
                if not itemWinner then
                    fallback = fallback or row
                end
            end
        end
    end

    return fallback
end

function LV.Loot:EnrichActiveRaidLootFromFullHistoryWindow()
    local session, record, guildKey = LV.Raid:GetActiveSession()
    if not session or not record or not guildKey then
        return 0, 0
    end

    local items = self:CollectFullLootHistoryItems()
    local updated = 0
    for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.itemLink and item.player then
            local row = self:FindActiveRaidLootRowForHistoryItem(record, guildKey, session.id, item)
            if row then
                row._lvHistoryMatched = true
                if self:ApplyFullHistoryItemToRow(guildKey, row, item) then
                    updated = updated + 1
                end
            end
        end
    end

    for _, row in ipairs(record.l or {}) do
        if type(row) == "table" then
            row._lvHistoryMatched = nil
        end
    end

    return updated, #(items or {})
end

function LV.Loot:RebuildActiveRaidFromLootWindow()
    local session, record = LV.Raid:GetActiveSession()
    if not session or not record then
        LV:Print("No active LootViewer raid.")
        return 0
    end

    local removed = self:WipeActiveRaidLoot(true)
    local before = #(record.l or {})

    local scanned = false
    local seenEncounters = {}
    for _, kill in ipairs(session.kills or {}) do
        local encounterID = tonumber(kill.e)
        if encounterID and encounterID > 0 and not seenEncounters[encounterID] then
            seenEncounters[encounterID] = true
            scanned = true
            self:ScanLootHistory(encounterID)
        end
    end
    if not scanned then
        self:ScanLootHistory()
    end

    _, record = LV.Raid:GetActiveSession()
    local afterSorted = record and #(record.l or {}) or before
    local imported = math.max(0, afterSorted - before)
    local sortedImported = imported
    local enriched = 0
    local historyItems = 0
    local frameEnriched = 0
    local frameItems = 0
    if imported > 0 then
        enriched, historyItems = self:EnrichActiveRaidLootFromFullHistoryWindow()
        frameEnriched, frameItems = self:EnrichActiveRaidLootFromLootHistoryFrames()
    end
    if imported == 0 then
        imported = self:ImportFullLootHistoryWindow()
        if imported > 0 then
            frameEnriched, frameItems = self:EnrichActiveRaidLootFromLootHistoryFrames()
        end
    end

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    local source = sortedImported > 0 and " from /loot" or " from legacy loot history"
    local details = {}
    if historyItems > 0 then
        details[#details + 1] = "legacy roll details " .. tostring(enriched) .. "/" .. tostring(historyItems)
    end
    if frameItems > 0 then
        details[#details + 1] = "frame roll details " .. tostring(frameEnriched) .. "/" .. tostring(frameItems)
    end
    local detail = #details > 0 and (", " .. table.concat(details, ", ")) or ""
    LV:Print("Rebuilt active raid loot. Removed " .. tostring(removed) .. ", imported " .. tostring(imported) .. source .. detail .. ".")
    return imported
end

function LV.Loot:ExtractDropInfo(drop, fallback)
    if type(drop) ~= "table" and type(fallback) ~= "table" then
        return nil
    end

    local itemLink = findItemLink(drop) or findItemLink(fallback)
    local winnerEntry = findWinnerEntry(drop) or findWinnerEntry(fallback)
    local directWinner = fieldFromSources(winnerKeys, drop, fallback)
    local winner = normalizeWinnerName(directWinner)
        or normalizeWinnerName(winnerEntry)
    local roll, rawRoll = rollInfoFromSources(directWinner, winnerEntry)
    roll = self:RollLabel(roll)
    local className = fieldFromSources(classKeys, winnerEntry, directWinner, drop, fallback)
    if not itemLink or not winner then
        return nil
    end
    if (not roll or roll == "") and isCurrentPlayerName(winner) then
        local localRoll, localRawRoll = self:SortedDropRollInfo(drop, fallback)
        if localRoll and localRoll ~= "" then
            roll = localRoll
            rawRoll = rawRoll or localRawRoll
        end
    end

    return {
        itemLink = itemLink,
        player = winner,
        roll = roll,
        rawRoll = rawRoll,
        rollSource = roll and roll ~= "" and "winner" or nil,
        rollBreakdown = self:CollectSortedRollBreakdown(drop, fallback),
        className = className,
        itemID = fieldFromSources({ "itemID", "itemId" }, drop, fallback) or LV.Util:ItemID(itemLink),
        quantity = fieldFromSources({ "quantity", "count" }, drop, fallback) or 1,
    }
end

function LV.Loot:ScheduleLootHistoryScan(wantedEncounterID)
    if not LV.Raid:GetActiveSession() then
        return
    end

    local key = tostring(wantedEncounterID or "all")
    self.historyScanSchedule = self.historyScanSchedule or {}
    local now = LV.Util:Now()
    if now - (tonumber(self.historyScanSchedule[key]) or 0) < 5 then
        return
    end
    self.historyScanSchedule[key] = now

    if not C_Timer or not C_Timer.After then
        self:ScanLootHistory(wantedEncounterID)
        return
    end

    for _, delay in ipairs(lootHistoryScanDelays) do
        C_Timer.After(delay, function()
            if LV.Raid:GetActiveSession() then
                LV.Loot:ScanLootHistory(wantedEncounterID)
            end
        end)
    end
end

function LV.Loot:ScanLootHistory(wantedEncounterID)
    local api = self:LootHistoryAPI()
    if not api then
        return
    end

    if wantedEncounterID and not api.GetAllEncounterInfos then
        self:ScanEncounterDrops(wantedEncounterID, tonumber(wantedEncounterID))
        return
    end

    if not api.GetAllEncounterInfos then
        return
    end

    local ok, encounters = pcall(api.GetAllEncounterInfos)
    if not ok or type(encounters) ~= "table" then
        return
    end

    for _, encounter in pairs(encounters) do
        local encounterID = type(encounter) == "table" and tonumber(encounter.encounterID or encounter.encounterId or encounter.id) or tonumber(encounter)
        if not wantedEncounterID or encounterID == tonumber(wantedEncounterID) then
            self:ScanEncounterDrops(encounter, encounterID)
        end
    end
end

function LV.Loot:ScanEncounterDrops(encounter, encounterID)
    local api = self:LootHistoryAPI()
    if not api or not api.GetSortedDropsForEncounter then
        return
    end

    local ok, drops = pcall(api.GetSortedDropsForEncounter, encounter)
    if (not ok or type(drops) ~= "table") and encounterID then
        ok, drops = pcall(api.GetSortedDropsForEncounter, encounterID)
    end
    if not ok or type(drops) ~= "table" then
        return
    end

    local instance = LV.Util:CurrentInstance()
    local boss = type(encounter) == "table" and (encounter.encounterName or encounter.name) or self:CurrentEncounterName(encounterID)
    local historyItems = self:CollectFullLootHistoryItems()
    for _, drop in pairs(drops) do
        local detail = nil
        local lootListID = type(drop) == "table" and (drop.lootListID or drop.lootListId)
        if encounterID and lootListID and api.GetSortedInfoForDrop then
            local detailOk, detailResult = pcall(api.GetSortedInfoForDrop, encounterID, lootListID)
            if detailOk and type(detailResult) == "table" then
                detail = detailResult
            end
        end

        local info = self:ExtractDropInfo(detail or drop, drop)
        if info then
            local historyInfo = self:FindFullLootHistoryItem(historyItems, info.itemLink, info.player)
            if historyInfo then
                if historyInfo.roll and historyInfo.roll ~= "" then
                    info.roll = historyInfo.roll
                    info.rollSource = "winner"
                end
                if historyInfo.rawRoll then
                    info.rawRoll = historyInfo.rawRoll
                end
                info.rollBreakdown = historyInfo.rollBreakdown
                info.className = info.className or historyInfo.className
                if (not info.boss or info.boss == "") and historyInfo.boss then
                    info.boss = historyInfo.boss
                end
            end
            info.ts = LV.Util:Now()
            info.encounterID = encounterID
            info.instanceID = instance.instanceID
            info.instance = instance.name
            info.difficultyID = instance.difficultyID
            info.difficulty = instance.difficultyName
            info.boss = (boss and boss ~= "" and boss) or info.boss or ""
            info.src = "boss"
            info.dedupeSeconds = 10 * 60
            self:AddLootEvent(info)
        end
    end
end

function LV.Loot:FindTradeSource(guildKey, fromName, itemLink, tradeTS)
    local record = LV.Store:GuildRecord(guildKey)
    local fromID = LV.Store:NameID(guildKey, fromName)
    local itemID = LV.Util:ItemID(itemLink) or 0
    local itemKey = LV.Store:ItemID(guildKey, itemLink)
    tradeTS = tonumber(tradeTS) or LV.Util:Now()

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        if tradeTS - (tonumber(row.ts) or 0) > LV.Constants.TRADE_WINDOW_SECONDS then
            break
        end

        if row.p == fromID and (row.itemID or 0) == itemID and row.item == itemKey and not row.tr then
            return row
        end
    end

    return nil
end

LV:RegisterEvent("ENCOUNTER_LOOT_RECEIVED", function(_, encounterID, itemID, itemLink, quantity, recipientName, className)
    LV.Loot:RecordEncounterLoot(encounterID, itemID, itemLink, quantity, recipientName, className)
end)

LV:RegisterEvent("CHAT_MSG_LOOT", function(_, message)
    LV.Loot:RecordChatLoot(message)
end)

LV:RegisterEvent("LOOT_ITEM_ROLL_WON", function(_, ...)
    LV.Loot:RecordRollWon(...)
end)

LV:RegisterOptionalEvent("START_LOOT_ROLL", function(_, rollID)
    LV.Loot:RecordLootRollStart(rollID)
end)

LV:RegisterOptionalEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", function(_, encounterID)
    LV.Loot:ScheduleLootHistoryScan(encounterID)
end)

LV:RegisterOptionalEvent("LOOT_HISTORY_UPDATE_DROP", function(_, encounterID)
    LV.Loot:ScheduleLootHistoryScan(encounterID)
end)
