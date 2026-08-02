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
        self:RecordTrade(player, target, itemLink, "observed")
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

function LV.Trade:RecordTrade(fromName, toName, itemLink, source, remoteTS, remoteBy)
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey then
        return nil
    end

    fromName = LV.Loot:NormalizePlayerName(fromName)
    toName = LV.Loot:NormalizePlayerName(toName)
    local record = LV.Store:GuildRecord(guildKey)
    local timestamp = tonumber(remoteTS) or LV.Util:Now()
    local sourceLoot = LV.Loot:FindTradeSource(guildKey, fromName, itemLink, timestamp)
    local session = LV.Raid:GetActiveSession()
    if not session and not sourceLoot then
        return nil
    end

    local row = {
        id = LV.Store:NewID(record, "trade", "t"),
        ts = timestamp,
        sid = session and session.id or sourceLoot.sid,
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

    if source ~= "remote" then
        LV:Print("Recorded trade: " .. LV.Util:ShortName(fromName) .. " -> " .. LV.Util:ShortName(toName) .. " " .. tostring(itemLink or "item") .. ".")
        LV.Comms:AnnounceTrade(fromName, itemLink, toName)
        LV.Comms:Send("T", { guildKey, timestamp, fromName, toName, LV.Util:ItemKey(itemLink), row.loot or "" })
    end

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return row
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

    self:RecordTrade(fromName, toName, itemKey, "remote", ts, sender)
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
