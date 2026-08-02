local _, LV = ...

LV.Comms = {}
LV.modules.Comms = LV.Comms

local SEP = "\031"

local function splitMessage(message)
    local parts = {}
    local cursor = 1
    message = message or ""

    while true do
        local found = string.find(message, SEP, cursor, true)
        if not found then
            parts[#parts + 1] = string.sub(message, cursor)
            break
        end

        parts[#parts + 1] = string.sub(message, cursor, found - 1)
        cursor = found + 1
    end

    return parts
end

function LV.Comms:Initialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(LV.Constants.PREFIX)
    end
end

function LV.Comms:SendMessage(kind, payload, channel, target)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        return false
    end

    local parts = { kind or "" }
    for _, value in ipairs(payload or {}) do
        parts[#parts + 1] = tostring(value or "")
    end

    C_ChatInfo.SendAddonMessage(LV.Constants.PREFIX, table.concat(parts, SEP), channel or "WHISPER", target)
    return true
end

function LV.Comms:Send(kind, payload)
    if not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return false
    end

    local channel = IsInRaid() and "RAID" or "PARTY"
    return self:SendMessage(kind, payload, channel)
end

function LV.Comms:SendWhisper(kind, target, payload)
    target = LV.Util:Trim(target)
    if target == "" then
        return false
    end

    return self:SendMessage(kind, payload, "WHISPER", target)
end

function LV.Comms:AnnounceTrade(fromName, itemLink, toName)
    local cfg = LV.Guild:CurrentConfig()
    if not cfg or not cfg.tradeRaid or not IsInRaid() then
        return
    end

    SendChatMessage("LV: " .. LV.Util:ShortName(fromName) .. " traded " .. tostring(itemLink or "item") .. " to " .. LV.Util:ShortName(toName), "RAID")
end

function LV.Comms:HandleMessage(prefix, message, channel, sender)
    if prefix ~= LV.Constants.PREFIX then
        return
    end

    local parts = splitMessage(message)
    local kind = parts[1]
    if kind == "S" and LV.Raid then
        LV.Raid:ObserveRemoteSession(parts, sender)
    elseif kind == "T" and LV.Trade then
        LV.Trade:ObserveRemoteTrade(parts, sender)
    elseif LV.DataSync and LV.DataSync:IsSyncKind(kind) then
        LV.DataSync:HandleMessage(parts, sender)
    end
end

LV:RegisterEvent("ADDON_LOADED", function(_, loadedAddonName)
    if loadedAddonName == LV.name then
        LV.Comms:Initialize()
    end
end)

LV:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, message, channel, sender)
    LV.Comms:HandleMessage(prefix, message, channel, sender)
end)
