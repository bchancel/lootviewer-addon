local addonName, LV = ...

LV.name = addonName
LV.version = "12.1.7"
LV.frame = CreateFrame("Frame")
LV.eventHandlers = {}
LV.modules = {}

_G.LootViewer = LV

function LV:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33aaffLootViewer|r " .. tostring(message or ""))
end

function LV:RegisterEvent(eventName, handler)
    if not eventName or type(handler) ~= "function" then
        return
    end

    local handlers = self.eventHandlers[eventName]
    if not handlers then
        handlers = {}
        self.eventHandlers[eventName] = handlers
        self.frame:RegisterEvent(eventName)
    end

    table.insert(handlers, handler)
end

function LV:RegisterOptionalEvent(eventName, handler)
    if not eventName or type(handler) ~= "function" then
        return false
    end

    local handlers = self.eventHandlers[eventName]
    if not handlers then
        handlers = {}
        local ok = pcall(self.frame.RegisterEvent, self.frame, eventName)
        if not ok then
            return false
        end
        self.eventHandlers[eventName] = handlers
    end

    table.insert(handlers, handler)
    return true
end

function LV:UnregisterEvent(eventName, handler)
    local handlers = self.eventHandlers[eventName]
    if not handlers then
        return
    end

    for index = #handlers, 1, -1 do
        if handlers[index] == handler then
            table.remove(handlers, index)
        end
    end

    if #handlers == 0 then
        self.eventHandlers[eventName] = nil
        self.frame:UnregisterEvent(eventName)
    end
end

function LV:CallModule(methodName, ...)
    for _, module in pairs(self.modules) do
        local method = module and module[methodName]
        if type(method) == "function" then
            method(module, ...)
        end
    end
end

LV.frame:SetScript("OnEvent", function(_, eventName, ...)
    local handlers = LV.eventHandlers[eventName]
    if not handlers then
        return
    end

    local args = { ... }
    for _, handler in ipairs(handlers) do
        local ok, err = xpcall(function()
            handler(eventName, unpack(args))
        end, geterrorhandler())
        if not ok and err then
            LV:Print("Error in " .. eventName .. ": " .. tostring(err))
        end
    end
end)

function LV:PrintHelp()
    self:Print("Commands:")
    self:Print("/lv - toggle LootViewer")
    self:Print("/lv config - open the on-demand configuration panel")
    self:Print("/lv start - start tracking the current raid")
    self:Print("/lv stop - stop tracking the current raid")
    self:Print("/lv extend [hours] - reactivate and extend the most recent raid")
    self:Print("/lv standby - mark yourself as standby")
    self:Print("/lv guild_set <guild> - use stored guild data for this session")
    self:Print("/lv guild_set clear - return to the character's actual guild")
    self:Print("/lv wipe_loot - wipe loot history for the active raid")
    self:Print("/lv rebuild_loot - rebuild active raid loot from Blizzard /loot history")
    self:Print("/lv debug_loot_window [search] - print Blizzard /loot roll fields")
    self:Print("/lv help - show this help")
end

SLASH_LOOTVIEWER1 = "/lv"
SLASH_LOOTVIEWER2 = "/lootviewer"
SlashCmdList.LOOTVIEWER = function(input)
    input = strtrim(input or "")
    local command, rest = input:match("^(%S+)%s*(.*)$")
    command = (command or ""):lower()
    rest = strtrim(rest or "")

    if command == "help" or command == "?" then
        LV:PrintHelp()
        return
    end

    if command == "start" then
        LV.Raid:StartSession("slash")
        return
    end

    if command == "stop" then
        LV.Raid:EndSession("slash")
        return
    end

    if command == "extend" or command == "extend_raid" then
        LV.Raid:ExtendMostRecentSession(tonumber(rest) or 3)
        return
    end

    if command == "standby" or command == "bench" then
        LV.Raid:MarkPlayerBench(LV.Util:PlayerFullName(), "self")
        return
    end

    if command == "guild_set" then
        LV.Guild:SetSessionOverride(rest)
        return
    end

    if command == "wipe_loot" then
        if rest:lower() == "all" then
            LV.Loot:WipeAllLoot()
        else
            LV.Loot:WipeActiveRaidLoot()
        end
        return
    end

    if command == "rebuild_loot" or command == "rebuild_from_loot_window" then
        LV.Loot:RebuildActiveRaidFromLootWindow()
        return
    end

    if command == "debug_loot_window" then
        LV.Loot:DebugLootWindow(rest or "")
        return
    end

    if command == "config" or command == "options" then
        if LV.UI and LV.UI.OpenConfiguration then
            LV.UI:OpenConfiguration()
        else
            LV:Print("UI is not loaded yet.")
        end
        return
    end

    if LV.UI and LV.UI.Toggle then
        LV.UI:Toggle()
    else
        LV:Print("UI is not loaded yet.")
    end
end
