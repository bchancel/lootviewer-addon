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

function LV.Trade:RecordTrade(fromName, toName, itemLink, source, remoteTS, remoteBy, sourceLootID, guildKeyOverride, receivedRemote)
    local guildKey = guildKeyOverride or LV.Guild:CurrentKey()
    if not guildKey then
        return nil
    end

    fromName = LV.Loot:NormalizePlayerName(fromName)
    toName = LV.Loot:NormalizePlayerName(toName)
    local record = LV.Store:GuildRecord(guildKey)
    local timestamp = tonumber(remoteTS) or LV.Util:Now()
    local sourceLoot = lootEventByID(record, sourceLootID)
        or LV.Loot:FindTradeSource(guildKey, fromName, itemLink, timestamp)
    local session = LV.Raid:GetActiveSession()
    if not session and not sourceLoot then
        return nil
    end

    local row = {
        id = LV.Store:NewID(record, "trade", "t"),
        ts = timestamp,
        sid = sourceLoot and sourceLoot.sid or session.id,
        f = LV.Store:NameID(guildKey, fromName),
        to = LV.Store:NameID(guildKey, toName),
        item = LV.Store:ItemID(guildKey, itemLink),
        itemID = LV.Util:ItemID(itemLink) or 0,
        loot = sourceLoot and sourceLoot.id or nil,
        src = source or "observed",
        by = remoteBy and LV.Store:NameID(guildKey, remoteBy) or LV.Store:NameID(guildKey, LV.Util:PlayerFullName()),
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

    local ts = tonumber(parts[3]) or LV.Util:Now()
    local fromName = parts[4]
    local toName = parts[5]
    local itemKey = parts[6]
    if LV.Util:IsBlank(fromName) or LV.Util:IsBlank(toName) or LV.Util:IsBlank(itemKey) then
        return
    end

    local source = parts[8] == "manual" and "manual" or "observed"
    local initiatedBy = LV.Util:Trim(parts[9]) ~= "" and parts[9] or sender
    self:RecordTrade(fromName, toName, itemKey, source, ts, initiatedBy, parts[7], nil, true)
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
