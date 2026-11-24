local env = setmetatable({}, { __index = _G })
env.StaticPopupDialogs = {}
local wipes = 0
env.wipe = function(t)
    wipes = wipes + 1
    for key in pairs(t) do t[key] = nil end
    return t
end
env.time, env.date = function() return 1000 end, os.date
local LV = { modules = {}, RegisterEvent = function() end, RegisterOptionalEvent = function() end,
    Print = function() end }
for _, path in ipairs({ "Core/Constants.lua", "Core/Util.lua", "Core/Store.lua", "Events/Loot.lua", "UI/MainFrame.lua" }) do
    setfenv(assert(loadfile(path)), env)("LootViewer", LV)
end
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function withinBudget(callback)
    local instructions = 0
    debug.sethook(function()
        instructions = instructions + 1000
        if instructions > 8000000 then error("History exceeded its Lua instruction budget") end
    end, "", 1000)
    local ok, err = pcall(callback)
    debug.sethook()
    assert(ok, err)
end
env.LootViewerDB = { g = { large = { d = { n = {}, i = {}, s = {} } } } }
local names = env.LootViewerDB.g.large.d.n
for index = 1, 6000 do names[index] = "Player" .. index .. "-Realm" end
LV.Store:Initialize()
local record = LV.Store:GuildRecord("large")
local startWipes = wipes
withinBudget(function()
    for index = 1, 10000 do
        eq(LV.Store:DictionaryValue("large", "n", 5000), "Player5000-Realm", "Existing name lookup")
        eq(LV.Store:NameID("large", "Player5000-Realm"), 5000, "Existing name ID")
    end
end)
eq(wipes, startWipes, "Repeated dictionary access never rebuilds unchanged reverse maps")
local playerID = LV.Store:NameID("large", "NewPlayer-Realm")
eq(playerID, 6001, "Append keeps stable dictionary IDs")
eq(LV.Store:NameID("large", "NewPlayer-Realm"), playerID, "New ID is immediately reusable")
local removed = LV.Store:DeletePlayer("large", playerID)
eq(removed, true, "Player can be deleted")
eq(LV.Store:DictionaryValue("large", "n", playerID), "", "Deleted dictionary slot stays empty")
eq(LV.Store:NameID("large", "NewPlayer-Realm"), 6002, "Deleted ID is not accidentally reused")
record.d.s = { "Replacement" }
eq(LV.Store:StringID("large", "Replacement"), 1, "Replaced dictionary rebuilds its reverse map")
record.d.s[2] = "ExternalAppend"
eq(LV.Store:StringID("large", "ExternalAppend"), 2, "Appended dictionary refreshes its reverse map")
record.d.s[1] = "Renamed"
LV.Store:EnsureReverseMaps("large", record)
eq(LV.Store:StringID("large", "Renamed"), 1, "Explicit rebuild supports same-size edits")
eq(LV.Store:StringID("large", "Replacement"), 3, "Explicit rebuild discards old reverse entries")
local other = LV.Store:NameID("other", "Player5000-Realm")
eq(other, 1, "Guild dictionaries stay isolated")
LV.Store.db.g.other = { d = { n = { "ReplacedGuild-Realm" }, i = {}, s = {} } }
eq(LV.Store:DictionaryValue("other", "n", 1), "ReplacedGuild-Realm", "Record replacement invalidates cached preparation")
eq(LV.Store:NameID("other", "ReplacedGuild-Realm"), 1, "Record replacement invalidates reverse maps")
LV.Store:Initialize()
eq(LV.Store:NameID("large", "Player5000-Realm"), 5000, "Reload rebuilds runtime caches")
record = LV.Store:GuildRecord("large")
print("PASS: large guild dictionaries stay fast through appends, deletions, replacements and reloads")

-- Run the actual history renderer with lightweight display objects.
local frames = {}
local function frame(parent)
    local result = { parent = parent, children = {}, scripts = {}, text = "" }
    if parent then parent.children[#parent.children + 1] = result end
    function result:SetScript(event, callback) self.scripts[event] = callback end
    result.HookScript = result.SetScript
    function result:SetText(text) self.text = text end
    function result:GetVerticalScrollRange() return 2000 end
    function result:GetVerticalScroll() return self.scroll or 0 end
    function result:SetVerticalScroll(value) self.scroll = value end
    function result:CreateTexture() return frame(self) end
    setmetatable(result, { __index = function() return function() end end })
    return result
end
env.CreateFrame = function(kind, _, parent)
    local result = frame(parent)
    if kind == "Button" then frames[#frames + 1] = result end
    return result
end
local color = { 1, 1, 1, 1 }
LV.Widgets = { colors = setmetatable({ muted = color, active = color, header = color, panel = color,
    yellow = color, border = color }, { __index = function() return color end }),
    ApplyBackdrop = function() end, SetTooltip = function() end }
function LV.Widgets:RowColor() return color end
function LV.Widgets:SelectionBar(parent) return frame(parent) end
function LV.Widgets:RowMenuButton(parent) return frame(parent) end
function LV.Widgets:Text(parent, text)
    local result = frame(parent)
    result.text = text
    return result
end
LV.Widgets.Label = LV.Widgets.Text
function LV.Widgets:IconButton(parent, _, _, _, callback)
    local result = frame(parent)
    result.onClick = callback
    return result
end
function LV.Widgets:ScrollFrame(parent) local scroll = frame(parent); return scroll, frame(scroll) end
LV.Seasons = { RaidMatchesFilter = function(_, _, raid) return raid.team == "main" end }
local tooltipReads, ready = 0, true
env.C_TooltipInfo = { GetHyperlink = function(itemLink)
    tooltipReads = tooltipReads + 1
    if not ready then return nil end
    if itemLink == "item:2" then return { lines = { { bonding = 9 } } } end
    return { lines = { { leftText = "Soulbound" } } }
end }
local ordinary, warbound, unloaded = LV.Store:ItemID("large", "item:1"),
    LV.Store:ItemID("large", "item:2"), LV.Store:ItemID("large", "item:3")
for index = 1, 80 do
    local raidID = "r" .. index
    record.r[raidID] = { id = raidID, team = "main", st = index, p = {}, b = {}, kills = {} }
    for lootIndex = 1, 100 do
        record.l[#record.l + 1] = { sid = raidID, item = ordinary }
    end
    record.l[#record.l + 1] = { sid = raidID, item = warbound }
end
record.r.hidden = { team = "other", st = 100, p = {} }
record.l[#record.l + 1] = { sid = "hidden", item = unloaded }
LV.UI.attendanceTeamID, LV.UI.attendanceSelectedRaid = "__guild_raids__", "r80"
local parent = frame(); parent.header = frame(parent)
withinBudget(function() LV.UI:RenderAttendanceHistory(parent, "large", record) end)
eq(tooltipReads, 2, "History checks each visible item once, including ordinary items")
eq(#frames, 80, "All filtered raids are rendered")
eq(frames[1].children[10].text, "100", "Warbound loot is excluded from the raid count")
eq(LV.UI.attendanceSelectedRaid, "r80", "Current selection survives rendering")
local refreshes = 0
function LV.UI:Refresh() refreshes = refreshes + 1 end
frames[2].scripts.OnClick()
eq(LV.UI.attendanceSelectedRaid, "r79", "Raid selection still works")
eq(refreshes, 1, "Click refreshes raid details")
-- A failed tooltip lookup is retried at the next refresh rather than cached forever.
record.l[#record.l + 1] = { sid = "r80", item = unloaded }
ready = false
local beforeRetry = tooltipReads
LV.UI:RenderAttendanceHistory(parent, "large", record)
ready = true
LV.UI:RenderAttendanceHistory(parent, "large", record)
assert(tooltipReads >= beforeRetry + 4, "Unloaded and non-warbound items must be retried next render")
print("PASS: raid history renders 80 raids and 8,000 loot rows within a bounded work budget")
