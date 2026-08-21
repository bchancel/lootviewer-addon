local _, LV = ...

LV.Trade = {}
LV.modules.Trade = LV.Trade

LV.Trade.active = nil

local function tradeTargetName()
    for _, unit in ipairs({ "target", "npc", "NPC" }) do
        if UnitExists(unit) and (not UnitIsPlayer or UnitIsPlayer(unit)) then
            local name = LV.Util:UnitFullName(unit)
            if name ~= "" then
                return name
            end
        end
    end

    return ""
end

local function lootEventByID(record, lootID)
    if not lootID then
        return nil
    end
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and tostring(row.id or "") == tostring(lootID) then
            return row
        end
    end
    return nil
end

local function lootEventByRemoteID(record, sender, remoteID)
    if LV.Util:IsBlank(sender) or LV.Util:IsBlank(remoteID) then
        return nil
    end
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and type(row.sy) == "table"
            and tostring(row.sy[sender] or "") == tostring(remoteID) then
            return row
        end
    end
    return nil
end

local function tradeEventByRemoteID(record, sender, remoteID)
    if LV.Util:IsBlank(sender) or LV.Util:IsBlank(remoteID) then
        return nil
    end
    for _, row in ipairs((record and record.t) or {}) do
        if type(row) == "table" and type(row.sy) == "table"
            and tostring(row.sy[sender] or "") == tostring(remoteID) then
            return row
        end
    end
    return nil
end

local function mergeRemoteIDs(keep, duplicate)
    if type(keep) ~= "table" or type(duplicate) ~= "table" or type(duplicate.sy) ~= "table" then
        return
    end
    keep.sy = keep.sy or {}
    for sender, remoteID in pairs(duplicate.sy) do
        if keep.sy[sender] == nil then
            keep.sy[sender] = remoteID
        end
    end
end

local function finalLootOwner(record, lootRow)
    local owner = lootRow and lootRow.p
    local trades = {}
    for _, trade in ipairs((record and record.t) or {}) do
        if type(trade) == "table" then
            trades[#trades + 1] = trade
        end
    end
    table.sort(trades, function(a, b)
        return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0)
    end)
    local lastTrade = tonumber(lootRow and lootRow.ts) or 0
    for _, trade in ipairs(trades) do
        local timestamp = tonumber(trade.ts) or 0
        local direct = lootRow and tostring(trade.loot or "") == tostring(lootRow.id or "")
        local chained = trade.f == owner and lootRow and trade.item == lootRow.item
            and timestamp >= lastTrade
            and timestamp <= ((tonumber(lootRow.ts) or timestamp) + LV.Constants.TRADE_WINDOW_SECONDS)
        if direct or chained then
            owner = trade.to or owner
            lastTrade = timestamp
        end
    end
    return owner
end

function LV.Trade:Begin()
    self.active = {
        target = tradeTargetName(),
        playerItems = {},
        targetItems = {},
        accepted = false,
    }
    self:Capture(true)
end

function LV.Trade:Capture(replaceWithEmpty)
    if not self.active then
        return
    end

    replaceWithEmpty = replaceWithEmpty and not self.active.accepted

    local playerItems = {}
    local targetItems = {}

    for slot = 1, 7 do
        local link = GetTradePlayerItemLink and GetTradePlayerItemLink(slot)
        if link then
            playerItems[#playerItems + 1] = link
        end

        local targetLink = GetTradeTargetItemLink and GetTradeTargetItemLink(slot)
        if targetLink then
            targetItems[#targetItems + 1] = targetLink
        end
    end

    if replaceWithEmpty or #playerItems > 0 then
        self.active.playerItems = playerItems
    end
    if replaceWithEmpty or #targetItems > 0 then
        self.active.targetItems = targetItems
    end
end

function LV.Trade:Accepted(playerAccepted, targetAccepted)
    if not self.active then
        return
    end

    if tonumber(playerAccepted) == 1 and tonumber(targetAccepted) == 1 then
        self.active.accepted = true
    end
    self:Capture(false)
end

function LV.Trade:RecordActiveTrade()
    if not self.active then
        return
    end

    local trade = self.active
    if trade.recorded then
        return
    end

    if not trade.accepted then
        return
    end

    local target = LV.Loot:NormalizePlayerName(trade.target)
    local player = LV.Util:PlayerFullName()
    if LV.Util:IsBlank(trade.target) or target == player then
        LV:Print("Trade completed, but LootViewer could not identify the trade target.")
        return
    end

    for _, itemLink in ipairs(trade.playerItems) do
        if LV.Dungeons and LV.Dungeons.RecordTrade then
            LV.Dungeons:RecordTrade(player, target, itemLink, "observed")
        end
        self:RecordTrade(player, target, itemLink, "observed")
    end
    for _, itemLink in ipairs(trade.targetItems) do
        if LV.Dungeons and LV.Dungeons.RecordTrade then
            LV.Dungeons:RecordTrade(target, player, itemLink, "observed")
        end
        self:RecordTrade(target, player, itemLink, "observed")
    end
    trade.recorded = true
end

function LV.Trade:Complete()
    if not self.active then
        return
    end

    self.active.accepted = true
    self:Capture(false)
    self:RecordActiveTrade()
end

function LV.Trade:Close()
    if not self.active then
        return
    end

    self:RecordActiveTrade()
    self.active = nil
end

function LV.Trade:FindDuplicate(record, timestamp, fromID, toID, itemKeyID, itemID, sourceLoot, remoteSender, remoteTradeID)
    local duplicate = tradeEventByRemoteID(record, remoteSender, remoteTradeID)
    if duplicate or not sourceLoot then
        return duplicate
    end

    timestamp = tonumber(timestamp) or 0
    for _, row in ipairs((record and record.t) or {}) do
        local sameItemID = (tonumber(itemID) or 0) > 0
            and (tonumber(row and row.itemID) or 0) == (tonumber(itemID) or 0)
        if type(row) == "table"
            and tostring(row.loot or "") == tostring(sourceLoot.id or "")
            and row.f == fromID
            and row.to == toID
            and (row.item == itemKeyID or sameItemID)
            and math.abs((tonumber(row.ts) or 0) - timestamp) <= 8 then
            return row
        end
    end
    return nil
end

function LV.Trade:RecordTrade(fromName, toName, itemLink, source, remoteTS, remoteBy, sourceLootID, guildKeyOverride, receivedRemote, remoteSender, remoteTradeID)
    local guildKey = guildKeyOverride or LV.Guild:CurrentKey()
    if not guildKey then
        return nil
    end

    fromName = LV.Loot:NormalizePlayerName(fromName)
    toName = LV.Loot:NormalizePlayerName(toName)
    remoteSender = LV.Util:IsBlank(remoteSender) and nil or LV.Loot:NormalizePlayerName(remoteSender)
    local record = LV.Store:GuildRecord(guildKey)
    local timestamp = tonumber(remoteTS) or LV.Util:Now()
    local sourceLoot = (remoteSender and lootEventByRemoteID(record, remoteSender, sourceLootID))
        or (not remoteSender and lootEventByID(record, sourceLootID))
        or LV.Loot:FindTradeSource(guildKey, fromName, itemLink, timestamp)
    if not sourceLoot or sourceLoot.src == "bonus" then
        return nil
    end

    local fromID = LV.Store:NameID(guildKey, fromName)
    local toID = LV.Store:NameID(guildKey, toName)
    local itemKeyID = LV.Store:ItemID(guildKey, itemLink)
    local itemID = LV.Util:ItemID(itemLink) or 0
    local duplicate = self:FindDuplicate(
        record,
        timestamp,
        fromID,
        toID,
        itemKeyID,
        itemID,
        sourceLoot,
        remoteSender,
        remoteTradeID
    )
    if duplicate then
        if remoteSender and remoteTradeID then
            duplicate.sy = duplicate.sy or {}
            duplicate.sy[remoteSender] = remoteTradeID
        end
        if sourceLoot then
            sourceLoot.tr = duplicate.id
        end
        return duplicate
    end

    local row = {
        id = LV.Store:NewID(record, "trade", "t"),
        ts = timestamp,
        sid = sourceLoot.sid,
        f = fromID,
        to = toID,
        item = itemKeyID,
        itemID = itemID,
        loot = sourceLoot.id,
        src = source or "observed",
        by = remoteBy and LV.Store:NameID(guildKey, remoteBy) or LV.Store:NameID(guildKey, LV.Util:PlayerFullName()),
        sy = remoteSender and remoteTradeID and { [remoteSender] = remoteTradeID } or nil,
    }

    table.insert(record.t, row)

    if sourceLoot then
        sourceLoot.tr = row.id
    end

    if not receivedRemote and source ~= "remote" then
        LV:Print("Recorded trade: " .. LV.Util:ShortName(fromName) .. " -> " .. LV.Util:ShortName(toName) .. " " .. tostring(itemLink or "item") .. ".")
        if LV.Guild:CurrentKey() == guildKey then
            LV.Comms:AnnounceTrade(fromName, itemLink, toName)
            if not LV.Store:IsRaidExcludedFromSync(guildKey, row.sid) then
                local initiatedBy = LV.Store:DictionaryValue(guildKey, "n", row.by)
                LV.Comms:Send("T", {
                    guildKey,
                    timestamp,
                    fromName,
                    toName,
                    LV.Util:ItemKey(itemLink),
                    row.loot or "",
                    row.src or "observed",
                    initiatedBy,
                    row.id,
                })
            end
        end
    end

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return row
end

function LV.Trade:RecordManualTrade(guildKey, lootRow, recipientID)
    local record = guildKey and LV.Store:GuildRecord(guildKey) or nil
    if type(record) ~= "table" or type(lootRow) ~= "table" then
        return nil
    end
    if lootRow.src == "bonus" then
        LV:Print("Bonus-roll loot cannot be traded.")
        return nil
    end
    local sourceLoot = lootEventByID(record, lootRow.id)
    if sourceLoot ~= lootRow then
        LV:Print("LootViewer could not find that loot event.")
        return nil
    end

    recipientID = tonumber(recipientID)
    local ownerID = finalLootOwner(record, lootRow)
    local fromName = LV.Store:DictionaryValue(guildKey, "n", ownerID)
    local toName = LV.Store:DictionaryValue(guildKey, "n", recipientID)
    if fromName == "" or toName == "" then
        LV:Print("Choose a raid member to receive the item.")
        return nil
    end
    if ownerID == recipientID then
        LV:Print(LV.Util:ShortName(toName) .. " already owns that item.")
        return nil
    end

    local itemKey = LV.Store:DictionaryValue(guildKey, "i", lootRow.item)
    return self:RecordTrade(fromName, toName, itemKey, "manual", nil, nil, lootRow.id, guildKey)
end

function LV.Trade:ObserveRemoteTrade(parts, sender)
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey or parts[2] ~= guildKey then
        return
    end

    sender = LV.Loot:NormalizePlayerName(sender)
    if sender:lower() == LV.Loot:NormalizePlayerName(LV.Util:PlayerFullName()):lower() then
        return
    end

    local ts = tonumber(parts[3]) or LV.Util:Now()
    local fromName = parts[4]
    local toName = parts[5]
    local itemKey = parts[6]
    if LV.Util:IsBlank(fromName) or LV.Util:IsBlank(toName) or LV.Util:IsBlank(itemKey) then
        return
    end

    local source = parts[8] == "manual" and "manual" or "observed"
    local initiatedBy = LV.Util:Trim(parts[9]) ~= "" and parts[9] or sender
    self:RecordTrade(fromName, toName, itemKey, source, ts, initiatedBy, parts[7], nil, true, sender, parts[10])
end

function LV.Trade:DeduplicateRecord(record)
    if type(record) ~= "table" or type(record.t) ~= "table" then
        return 0
    end

    local seen = {}
    local removed = 0
    local index = 1
    while index <= #record.t do
        local row = record.t[index]
        local lootID = type(row) == "table" and tostring(row.loot or "") or ""
        local key
        if lootID ~= "" then
            key = table.concat({
                tostring(tonumber(row.ts) or 0),
                tostring(row.sid or ""),
                tostring(row.f or ""),
                tostring(row.to or ""),
                tostring(row.item or ""),
                tostring(tonumber(row.itemID) or 0),
                lootID,
            }, "\031")
        end

        local keep = key and seen[key] or nil
        if keep then
            mergeRemoteIDs(keep, row)
            local sourceLoot = lootEventByID(record, row.loot)
            if sourceLoot and (not sourceLoot.tr or tostring(sourceLoot.tr) == tostring(row.id or "")) then
                sourceLoot.tr = keep.id
            end
            table.remove(record.t, index)
            removed = removed + 1
        else
            if key then
                seen[key] = row
            end
            index = index + 1
        end
    end
    return removed
end

function LV.Trade:DeduplicateCurrentGuild()
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey then
        return 0
    end
    local removed = self:DeduplicateRecord(LV.Store:GuildRecord(guildKey))
    if removed > 0 then
        LV:Print("Removed " .. tostring(removed) .. " duplicate trade record" .. (removed == 1 and "." or "s."))
        if LV.UI and LV.UI.Refresh then
            LV.UI:Refresh()
        end
    end
    return removed
end

LV:RegisterEvent("TRADE_SHOW", function()
    LV.Trade:Begin()
end)

LV:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED", function()
    LV.Trade:Capture(true)
end)

LV:RegisterEvent("TRADE_TARGET_ITEM_CHANGED", function()
    LV.Trade:Capture(true)
end)

LV:RegisterEvent("TRADE_ACCEPT_UPDATE", function(_, playerAccepted, targetAccepted)
    LV.Trade:Accepted(playerAccepted, targetAccepted)
end)

LV:RegisterEvent("TRADE_CLOSED", function()
    LV.Trade:Close()
end)

LV:RegisterOptionalEvent("TRADE_UPDATE", function()
    LV.Trade:Capture(true)
end)

LV:RegisterOptionalEvent("UI_INFO_MESSAGE", function(_, messageType)
    if LE_GAME_ERR_TRADE_COMPLETE and messageType == LE_GAME_ERR_TRADE_COMPLETE then
        LV.Trade:Complete()
    end
end)

LV:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(2, function()
        LV.Trade:DeduplicateCurrentGuild()
    end)
end)
