local _, LV = ...

LV.UI = {}
LV.modules.UI = LV.UI

local authorityModes = {
    { value = "assist", label = "Lead / Assist" },
    { value = "lead", label = "Raid Lead" },
    { value = "rank", label = "Guild Rank" },
    { value = "trusted", label = "Trusted Rank" },
    { value = "all", label = "Anyone" },
}

local dayValues = {
    { value = 1, label = "Sunday" },
    { value = 2, label = "Monday" },
    { value = 3, label = "Tuesday" },
    { value = 4, label = "Wednesday" },
    { value = 5, label = "Thursday" },
    { value = 6, label = "Friday" },
    { value = 7, label = "Saturday" },
}

local amPmValues = {
    { value = "AM", label = "AM" },
    { value = "PM", label = "PM" },
}

local ATTENDANCE_PAGE_SIZE = 6
local ATTENDANCE_METER_PAGE_SIZE = 12
local METER_DETAIL_PAGE_SIZE = 8
local HISTORY_PAGE_SIZE = 15

local attendanceStatusValues = {
    { value = "here", label = "Here" },
    { value = "bench", label = "Bench" },
    { value = "late", label = "Late" },
    { value = "out", label = "Out" },
    { value = "noshow", label = "NoShow" },
}

local rosterTagValues = {
    { value = "guild", label = "Guild" },
    { value = "alt", label = "Alt" },
    { value = "pug", label = "Pug" },
}

local classValues = {
    { value = "", label = "Class" },
    { value = "DEATHKNIGHT", label = "Death Knight" },
    { value = "DEMONHUNTER", label = "Demon Hunter" },
    { value = "DRUID", label = "Druid" },
    { value = "EVOKER", label = "Evoker" },
    { value = "HUNTER", label = "Hunter" },
    { value = "MAGE", label = "Mage" },
    { value = "MONK", label = "Monk" },
    { value = "PALADIN", label = "Paladin" },
    { value = "PRIEST", label = "Priest" },
    { value = "ROGUE", label = "Rogue" },
    { value = "SHAMAN", label = "Shaman" },
    { value = "WARLOCK", label = "Warlock" },
    { value = "WARRIOR", label = "Warrior" },
}

local meterMonthValues = {}
for month = 1, 12 do
    meterMonthValues[#meterMonthValues + 1] = { value = month, label = tostring(month) }
end

local meterColors = {
    here = { 0.16, 0.68, 0.28, 0.95 },
    late = { 0.95, 0.76, 0.18, 0.95 },
    out = { 0.95, 0.45, 0.16, 0.95 },
    noshow = { 0.72, 0.12, 0.16, 0.95 },
    empty = { 0.03, 0.04, 0.07, 0.9 },
}

local detailStatusColors = {
    here = meterColors.here,
    bench = meterColors.here,
    late = meterColors.late,
    out = { 0, 0, 0, 0.95 },
    noshow = meterColors.noshow,
    empty = meterColors.empty,
}

local function selectedTeam(cfg)
    return LV.Store:GetSelectedTeam(cfg)
end

local function pickerAlpha()
    if ColorPickerFrame and ColorPickerFrame.GetColorAlpha then
        local alpha = ColorPickerFrame:GetColorAlpha()
        if type(alpha) == "number" then
            return alpha
        end
    end
    if OpacitySliderFrame and OpacitySliderFrame.GetValue then
        local opacity = OpacitySliderFrame:GetValue()
        if type(opacity) == "number" then
            return 1 - opacity
        end
    end
    return 1
end

local function prepareColorPicker()
    if not ColorPickerFrame then
        return
    end
    if ColorPickerFrame.SetFrameStrata then
        ColorPickerFrame:SetFrameStrata("TOOLTIP")
    end
    if ColorPickerFrame.SetFrameLevel then
        ColorPickerFrame:SetFrameLevel(200)
    end
end

local function toClock12(hour)
    hour = tonumber(hour) or 0
    local period = hour >= 12 and "PM" or "AM"
    local clock = hour % 12
    if clock == 0 then
        clock = 12
    end
    return clock, period
end

local function fromClock12(hour, period)
    hour = tonumber(hour) or 12
    if hour < 1 then
        hour = 1
    elseif hour > 12 then
        hour = 12
    end

    if period == "PM" and hour < 12 then
        return hour + 12
    elseif period == "AM" and hour == 12 then
        return 0
    end

    return hour
end

local function compareText(a, b)
    return tostring(a or ""):lower() < tostring(b or ""):lower()
end

local function popupEditBox(dialog)
    return dialog and (dialog.editBox or dialog.EditBox)
end

function LV.UI:Toggle()
    self:Ensure()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Refresh()
    end
end

function LV.UI:Ensure()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "LootViewerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(1040, 700)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(1000)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnMouseDown", function(self)
        self:Raise()
    end)
    frame:SetScript("OnShow", function(self)
        self:Raise()
    end)
    frame:Hide()
    LV.Widgets:ApplyBackdrop(frame, LV.Widgets.colors.bg, LV.Widgets.colors.border)

    local title = LV.Widgets:Text(frame, "LootViewer", "large")
    title:SetPoint("TOPLEFT", 18, -14)

    local subtitle = LV.Widgets:Text(frame, "Guild raid tracking")
    subtitle:SetTextColor(unpack(LV.Widgets.colors.muted))
    subtitle:SetPoint("LEFT", title, "RIGHT", 18, -2)

    local close = LV.Widgets:Button(frame, "X", 32, 28, function()
        frame:Hide()
    end)
    close:SetPoint("TOPRIGHT", -12, -12)

    local nav = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 16, -64)
    nav:SetPoint("BOTTOMLEFT", 16, 16)
    nav:SetWidth(210)
    nav:SetFrameLevel(frame:GetFrameLevel() + 10)
    LV.Widgets:ApplyBackdrop(nav, LV.Widgets.colors.panel, LV.Widgets.colors.border)

    local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 14, 0)
    content:SetPoint("BOTTOMRIGHT", -16, 16)
    content:SetFrameLevel(frame:GetFrameLevel() + 10)
    content._lvTrackDirect = true
    LV.Widgets:ApplyBackdrop(content, LV.Widgets.colors.panel, LV.Widgets.colors.border)

    self.frame = frame
    self.nav = nav
    self.content = content
    self.currentTab = "config"
    self.navButtons = {}

    self:BuildNavButton("config", "Guild Configuration", 1)
    self:BuildNavButton("attendance", "Attendance", 2)
    self:BuildNavButton("meter", "Attendance Meter", 3)
    self:BuildNavButton("history", "History", 4)
    self:BuildNavButton("sync", "Data Sync")
end

function LV.UI:BuildNavButton(tab, label, index)
    local button = LV.Widgets:Button(self.nav, label, 178, 34, function()
        self:SwitchTab(tab)
    end)
    if index then
        button:SetPoint("TOP", 0, -26 - ((index - 1) * 48))
    else
        button:SetPoint("BOTTOM", 0, 28)
    end
    self.navButtons[tab] = button
end

function LV.UI:SwitchTab(tab)
    self.currentTab = tab
    self:Refresh()
end

function LV.UI:Track(region)
    self.renderRegions = self.renderRegions or {}
    self.renderRegions[#self.renderRegions + 1] = region
    return region
end

function LV.UI:ClearContent()
    if self.renderRegions then
        for _, region in ipairs(self.renderRegions) do
            if region and region.Hide then
                region:Hide()
            end
        end
        wipe(self.renderRegions)
    end

    for _, child in ipairs({ self.content:GetChildren() }) do
        child:Hide()
    end
end

function LV.UI:Refresh()
    self:Ensure()
    if not self.frame:IsShown() then
        return
    end

    for tab, button in pairs(self.navButtons) do
        LV.Widgets:SetButtonActive(button, tab == self.currentTab)
    end

    self:ClearContent()
    if self.currentTab == "attendance" then
        self:RenderAttendance()
    elseif self.currentTab == "meter" then
        self:RenderAttendanceMeter()
    elseif self.currentTab == "sync" then
        self:RenderDataSync()
    elseif self.currentTab == "history" then
        self:RenderHistory()
    else
        self:RenderConfig()
    end
end

function LV.UI:CurrentGuildOrMessage()
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo then
        local text = LV.Widgets:Text(self.content, "LootViewer configuration is guild-scoped. Log into a guilded character to configure tracking.")
        text:SetPoint("TOPLEFT", 22, -24)
        return nil
    end
    LV.Store:GuildRecord(guildInfo.key)
    return guildInfo
end

function LV.UI:NumberCommit(setter, fallback)
    return function(value)
        local parsed = tonumber(value)
        setter(parsed or fallback)
    end
end

function LV.UI:RenderConfig()
    local guildInfo = self:CurrentGuildOrMessage()
    if not guildInfo then
        return
    end

    local cfg = LV.Store:GetConfig(guildInfo.key)
    local title = LV.Widgets:Text(self.content, "Guild Configuration", "large")
    title:SetPoint("TOPLEFT", 22, -20)

    local guild = LV.Widgets:Text(self.content, guildInfo.name .. " - " .. guildInfo.realm)
    guild:SetTextColor(unpack(LV.Widgets.colors.muted))
    guild:SetPoint("LEFT", title, "RIGHT", 18, -2)

    local tracking = LV.Widgets:Section(self.content, "Tracking", 108)
    tracking:SetPoint("TOPLEFT", 22, -62)
    tracking:SetPoint("RIGHT", -22, 0)

    local enabled = LV.Widgets:Check(tracking, "Prompt for scheduled guild raids", function(value)
        cfg.prompt = value
    end)
    enabled:SetPoint("TOPLEFT", 22, -44)
    enabled:SetChecked(cfg.prompt)

    local trade = LV.Widgets:Check(tracking, "Announce observed trades in raid", function(value)
        cfg.tradeRaid = value
    end)
    trade:SetPoint("LEFT", enabled, "RIGHT", 250, 0)
    trade:SetChecked(cfg.tradeRaid)

    local authorityLabel = LV.Widgets:Label(tracking, "Authority")
    authorityLabel:SetPoint("TOPLEFT", 24, -78)
    local authority = LV.Widgets:Dropdown(tracking, authorityModes, function()
        return cfg.authority or "assist"
    end, function(value)
        cfg.authority = value
    end, 150)
    authority:SetPoint("LEFT", authorityLabel, "RIGHT", 18, 0)

    local rankLabel = LV.Widgets:Label(tracking, "Rank Range")
    rankLabel:SetPoint("LEFT", authority, "RIGHT", 30, 0)
    local rankMin = LV.Widgets:EditBox(tracking, 42, 26, self:NumberCommit(function(value)
        cfg.rankMin = value
    end, cfg.rankMin or 0))
    rankMin:SetText(tostring(cfg.rankMin or 0))
    rankMin:SetPoint("LEFT", rankLabel, "RIGHT", 14, 0)
    local rankMax = LV.Widgets:EditBox(tracking, 42, 26, self:NumberCommit(function(value)
        cfg.rankMax = value
    end, cfg.rankMax or 3))
    rankMax:SetText(tostring(cfg.rankMax or 3))
    rankMax:SetPoint("LEFT", rankMin, "RIGHT", 8, 0)

    local timing = LV.Widgets:Section(self.content, "Timing", 104)
    timing:SetPoint("TOPLEFT", tracking, "BOTTOMLEFT", 0, -12)
    timing:SetPoint("RIGHT", -22, 0)

    self:AddLabeledEdit(timing, "Late Grace Min", tostring(cfg.lateGrace or 10), 24, -50, 56, function(value)
        cfg.lateGrace = tonumber(value) or 10
    end)
    self:AddLabeledEdit(timing, "Prompt Timeout Sec", tostring(cfg.promptTimeout or 30), 188, -50, 56, function(value)
        cfg.promptTimeout = tonumber(value) or 30
    end)
    self:AddLabeledEdit(timing, "Whisper Keyword", cfg.whisper or "bench", 382, -50, 110, function(value)
        cfg.whisper = LV.Util:Trim(value)
    end)
    local pruneEdit = self:AddLabeledEdit(timing, "Prune Days", tostring(cfg.pruneDays or 0), 548, -50, 54, function(value)
        cfg.pruneDays = tonumber(value) or 0
    end)
    local prune = LV.Widgets:Button(timing, "Prune", 56, 26, function()
        local days = tonumber(cfg.pruneDays) or 0
        if days > 0 then
            local removed = LV.Store:Prune(guildInfo.key, days * 86400)
            LV:Print("Pruned " .. removed .. " old record(s).")
            self:Refresh()
        end
    end)
    prune:SetPoint("LEFT", pruneEdit, "RIGHT", 8, 0)

    local schedule = LV.Widgets:Section(self.content, "Raid Teams / Times", 244)
    schedule:SetPoint("TOPLEFT", timing, "BOTTOMLEFT", 0, -12)
    schedule:SetPoint("BOTTOMRIGHT", -22, 22)

    self:RenderScheduleRows(schedule, cfg)
end

function LV.UI:AddLabeledEdit(parent, label, value, x, y, width, onCommit)
    local lbl = LV.Widgets:Label(parent, label)
    lbl:SetPoint("TOPLEFT", x, y)
    local edit = LV.Widgets:EditBox(parent, width or 80, 26, onCommit)
    edit:SetText(value or "")
    edit:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
    parent[label:gsub("%s+", ""):lower() .. "Edit"] = edit
    return edit
end

function LV.UI:SetTeamColor(team, color)
    if type(team) ~= "table" then
        return
    end
    team.color = LV.Store:NormalizeTeamColor(color)
end

function LV.UI:UpdateTeamColorSwatch(swatch, color)
    if not swatch or not swatch.fill then
        return
    end
    color = LV.Store:NormalizeTeamColor(color)
    swatch.fill:SetColorTexture(color.r, color.g, color.b, color.a)
end

function LV.UI:OpenTeamColorPicker(team, swatch)
    if not ColorPickerFrame then
        LV:Print("The WoW color picker is not available.")
        return
    end

    local starting = LV.Store:NormalizeTeamColor(team and team.color)
    local function applyColor(color)
        self:SetTeamColor(team, color)
        self:UpdateTeamColorSwatch(swatch, team and team.color)
    end
    local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        applyColor({ r = r, g = g, b = b, a = pickerAlpha() })
    end
    local function cancel(previous)
        if type(previous) == "table" then
            applyColor({
                r = previous.r or starting.r,
                g = previous.g or starting.g,
                b = previous.b or starting.b,
                a = previous.opacity or previous.a or starting.a,
            })
        else
            applyColor(starting)
        end
    end

    prepareColorPicker()
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = starting.r,
            g = starting.g,
            b = starting.b,
            opacity = starting.a,
            hasOpacity = true,
            swatchFunc = apply,
            opacityFunc = apply,
            cancelFunc = cancel,
        })
        return
    end

    ColorPickerFrame.func = apply
    ColorPickerFrame.opacityFunc = apply
    ColorPickerFrame.cancelFunc = cancel
    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity = starting.a
    ColorPickerFrame:SetColorRGB(starting.r, starting.g, starting.b)
    ColorPickerFrame:Show()
end

function LV.UI:TeamColorSwatch(parent, team)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(28, 24)
    LV.Widgets:ApplyBackdrop(button, LV.Widgets.colors.header, LV.Widgets.colors.border)

    button.fill = button:CreateTexture(nil, "ARTWORK")
    button.fill:SetPoint("TOPLEFT", 5, -5)
    button.fill:SetPoint("BOTTOMRIGHT", -5, 5)
    self:UpdateTeamColorSwatch(button, team and team.color)

    button:SetScript("OnClick", function()
        self:OpenTeamColorPicker(team, button)
    end)
    button:SetScript("OnEnter", function()
        button:SetBackdropColor(unpack(LV.Widgets.colors.active))
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Raid team color")
        GameTooltip:AddLine("Click to change this team's highlight color.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        button:SetBackdropColor(unpack(LV.Widgets.colors.header))
        GameTooltip:Hide()
    end)
    return button
end

function LV.UI:RaidTeamColor(guildKey, raid)
    local record = guildKey and LV.Store:GuildRecord(guildKey)
    local teamID = raid and raid.team
    local team = record and LV.Store:GetTeamByID(record, teamID or "main")
    return LV.Store:NormalizeTeamColor(team and team.color)
end

function LV.UI:DrawTeamAccent(parent, guildKey, raid)
    local color = self:RaidTeamColor(guildKey, raid)
    local accent = parent:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(color.r, color.g, color.b, color.a)
    accent:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
    accent:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 2, 2)
    accent:SetWidth(4)
    return accent
end

function LV.UI:RenderScheduleRows(parent, cfg)
    local team = selectedTeam(cfg)
    local teamLabel = LV.Widgets:Label(parent, "Raid Team")
    teamLabel:SetPoint("TOPLEFT", 24, -42)

    local teamValues = {}
    for _, item in ipairs(cfg.teams or {}) do
        teamValues[#teamValues + 1] = { value = item.id, label = item.name }
    end
    local teamPick = LV.Widgets:CycleButton(parent, teamValues, function()
        return cfg.selectedTeam
    end, function(value)
        cfg.selectedTeam = value
        self:Refresh()
    end, 120)
    teamPick:SetPoint("LEFT", teamLabel, "RIGHT", 18, 0)

    local nameEdit = LV.Widgets:EditBox(parent, 150, 26, function(value)
        team.name = LV.Util:Trim(value)
        if team.name == "" then
            team.name = team.id
        end
        self:Refresh()
    end)
    nameEdit:SetText(team.name or "")
    nameEdit:SetPoint("LEFT", teamPick, "RIGHT", 14, 0)

    local colorSwatch = self:TeamColorSwatch(parent, team)
    colorSwatch:SetPoint("LEFT", nameEdit, "RIGHT", 10, 0)

    local serverTime = LV.Widgets:Text(parent, "Raid times use server time.")
    serverTime:SetTextColor(unpack(LV.Widgets.colors.muted))
    serverTime:SetPoint("LEFT", colorSwatch, "RIGHT", 14, 0)

    local addTeam = LV.Widgets:Button(parent, "Add Team", 88, 26, function()
        local guildInfo = LV.Guild:CurrentInfo()
        if guildInfo then
            StaticPopup_Show(LV.Constants.TEAM_PROMPT, nil, nil, { guildKey = guildInfo.key })
        end
    end)
    addTeam:SetPoint("TOPLEFT", 24, -72)

    local deleteTeam = LV.Widgets:Button(parent, "Delete Team", 96, 26, function()
        if #(cfg.teams or {}) <= 1 then
            LV:Print("Keep at least one raid team.")
            return
        end
        for index, item in ipairs(cfg.teams) do
            if item.id == team.id then
                table.remove(cfg.teams, index)
                break
            end
        end
        cfg.selectedTeam = cfg.teams[1].id
        self:Refresh()
    end)
    deleteTeam:SetPoint("LEFT", addTeam, "RIGHT", 8, 0)

    local addRaidTime = LV.Widgets:Button(parent, "Add Raid Time", 120, 26, function()
        team.schedules[#team.schedules + 1] = { w = date("*t").wday, h = 20, m = 0, d = 180 }
        self:Refresh()
    end)
    addRaidTime:SetPoint("LEFT", deleteTeam, "RIGHT", 8, 0)

    local y = -132
    local headers = { "Day", "Hour", "AM/PM", "Minute", "Duration Min" }
    local x = { 24, 184, 254, 330, 424 }
    for index, header in ipairs(headers) do
        local label = LV.Widgets:Label(parent, header)
        label:SetPoint("TOPLEFT", x[index], -104)
    end

    for index, slot in ipairs(team.schedules or {}) do
        local clockHour, period = toClock12(slot.h)
        local day = LV.Widgets:Dropdown(parent, dayValues, function()
            return tonumber(slot.w) or 1
        end, function(value)
            slot.w = value
        end, 140)
        day:SetPoint("TOPLEFT", 24, y)

        local hour = LV.Widgets:EditBox(parent, 50, 26, function(value)
            local _, currentPeriod = toClock12(slot.h)
            slot.h = fromClock12(value, currentPeriod)
        end)
        hour:SetText(tostring(clockHour))
        hour:SetPoint("TOPLEFT", 184, y)

        local ampm = LV.Widgets:Dropdown(parent, amPmValues, function()
            return select(2, toClock12(slot.h))
        end, function(value)
            slot.h = fromClock12(toClock12(slot.h), value)
        end, 64)
        ampm:SetPoint("TOPLEFT", 254, y)

        local minute = LV.Widgets:EditBox(parent, 58, 26, function(value)
            local parsed = tonumber(value) or 0
            if parsed < 0 then
                parsed = 0
            elseif parsed > 59 then
                parsed = 59
            end
            slot.m = parsed
        end)
        minute:SetText(tostring(slot.m or 0))
        minute:SetPoint("TOPLEFT", 330, y)

        local duration = LV.Widgets:EditBox(parent, 86, 26, function(value)
            slot.d = tonumber(value) or 180
        end)
        duration:SetText(tostring(slot.d or 180))
        duration:SetPoint("TOPLEFT", 424, y)

        local remove = LV.Widgets:Button(parent, "Delete", 64, 26, function()
            table.remove(team.schedules, index)
            self:Refresh()
        end)
        remove:SetPoint("TOPLEFT", 546, y)

        y = y - 32
    end
end

function LV.UI:TeamValues(cfg)
    local values = {}
    for _, team in ipairs((cfg and cfg.teams) or {}) do
        values[#values + 1] = { value = team.id, label = team.name }
    end
    if #values == 0 then
        values[1] = { value = "main", label = "Main" }
    end
    return values
end

function LV.UI:MeterTeamValues(cfg)
    local values = {
        { value = "all", label = "All Teams" },
    }
    for _, team in ipairs((cfg and cfg.teams) or {}) do
        values[#values + 1] = { value = team.id, label = team.name }
    end
    return values
end

function LV.UI:DeleteRaid(guildKey, raidID)
    if not LV.Guild:CanModifySession() then
        LV:Print("Your current LootViewer authority settings do not allow raid deletion.")
        return
    end

    local record = LV.Store:GuildRecord(guildKey)
    if not record or not raidID or type(record.r[raidID]) ~= "table" then
        return
    end

    if record.cur == raidID then
        record.cur = nil
    end
    record.r[raidID] = nil
    self.attendanceSelectedRaid = nil
    LV:Print("Deleted raid attendance record " .. tostring(raidID) .. ". Loot and trade history were kept.")
    self:Refresh()
end

function LV.UI:MapCount(map)
    local count = 0
    for _, _ in pairs(map or {}) do
        count = count + 1
    end
    return count
end

function LV.UI:NormalizeClassToken(className)
    className = LV.Util:Trim(className):upper()
    className = className:gsub("%s+", "")
    className = className:gsub("[^A-Z]", "")
    return className
end

function LV.UI:LiveClassForName(guildKey, nameID)
    local wanted = LV.Store:DictionaryValue(guildKey, "n", nameID)
    if wanted == "" then
        return ""
    end

    local wantedLower = wanted:lower()
    local wantedShort = LV.Util:ShortName(wanted):lower()
    local foundClass = ""

    local function inspect(unit)
        if foundClass ~= "" or not UnitExists(unit) then
            return
        end

        local fullName = LV.Util:UnitFullName(unit)
        if fullName == "" then
            return
        end

        if fullName:lower() == wantedLower or LV.Util:ShortName(fullName):lower() == wantedShort then
            local _, classFileName = UnitClass(unit)
            foundClass = LV.Util:Trim(classFileName)
        end
    end

    inspect("player")
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            inspect("raid" .. index)
        end
    elseif IsInGroup() then
        for index = 1, GetNumSubgroupMembers() do
            inspect("party" .. index)
        end
    end

    if foundClass ~= "" then
        LV.Store:SetPlayerClass(guildKey, nameID, foundClass)
    end
    return foundClass
end

function LV.UI:PlayerClassToken(guildKey, nameID)
    local record = LV.Store:GuildRecord(guildKey)
    nameID = tonumber(nameID)
    if not record or not nameID then
        return ""
    end

    local className = LV.Store:PlayerClass(guildKey, nameID)
    if className == "" then
        className = self:LiveClassForName(guildKey, nameID)
    end
    if className == "" then
        for index = #record.l, 1, -1 do
            local row = record.l[index]
            if type(row) == "table" and row.p == nameID and row.cls then
                className = LV.Store:DictionaryValue(guildKey, "s", row.cls)
                if className ~= "" then
                    LV.Store:SetPlayerClass(guildKey, nameID, className)
                    break
                end
            end
        end
    end

    return self:NormalizeClassToken(className)
end

function LV.UI:ClassColorForName(guildKey, nameID)
    local token = self:PlayerClassToken(guildKey, nameID)
    local palette = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = palette and palette[token]
    if color then
        return { color.r or 1, color.g or 1, color.b or 1, 1 }
    end
    return LV.Widgets.colors.white
end

function LV.UI:SetNameClassColor(font, guildKey, nameID)
    if font then
        font:SetTextColor(unpack(self:ClassColorForName(guildKey, nameID)))
    end
end

function LV.UI:NormalizePlayerForGuild(name)
    name = LV.Util:Trim(name)
    if name ~= "" and not name:find("-", 1, true) then
        local info = LV.Guild:CurrentInfo()
        name = name .. "-" .. ((info and info.realm) or LV.Util:RealmName())
    end
    return name
end

function LV.UI:RaidAttendanceStatus(raid, nameID)
    if not raid or not nameID then
        return "empty"
    end
    if raid.out and raid.out[nameID] then
        return "out"
    end
    if raid.noshow and raid.noshow[nameID] then
        return "noshow"
    end
    if raid.b and raid.b[nameID] then
        return "bench"
    end
    if raid.late and raid.late[nameID] then
        return "late"
    end
    if raid.p and raid.p[nameID] then
        return "here"
    end
    return "empty"
end

function LV.UI:SetHistoricalRaidAttendance(guildKey, raidID, fullName, status)
    if not LV.Guild:CanModifySession() then
        LV:Print("Your current LootViewer authority settings do not allow attendance changes.")
        return false
    end

    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and record.r and record.r[raidID]
    if type(raid) ~= "table" then
        return false
    end

    fullName = self:NormalizePlayerForGuild(fullName)
    if fullName == "" then
        LV:Print("Enter a player name.")
        return false
    end

    local nameID = LV.Store:NameID(guildKey, fullName)
    if not nameID then
        return false
    end

    raid.p = raid.p or {}
    raid.b = raid.b or {}
    raid.late = raid.late or {}
    raid.out = raid.out or {}
    raid.noshow = raid.noshow or {}

    raid.p[nameID] = nil
    raid.b[nameID] = nil
    raid.late[nameID] = nil
    raid.out[nameID] = nil
    raid.noshow[nameID] = nil

    local now = LV.Util:Now()
    if status == "bench" then
        raid.p[nameID] = now
        raid.b[nameID] = now
    elseif status == "late" then
        raid.p[nameID] = now
        raid.late[nameID] = now
    elseif status == "out" then
        raid.out[nameID] = now
    elseif status == "noshow" then
        raid.noshow[nameID] = now
    else
        raid.p[nameID] = now
    end

    raid.en = math.max(tonumber(raid.en) or 0, now)
    raid.lastBy = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    raid.lastSource = "ui_edit"
    return true
end

function LV.UI:RemoveHistoricalRaidAttendance(guildKey, raidID, nameID, status)
    if not LV.Guild:CanModifySession() then
        LV:Print("Your current LootViewer authority settings do not allow attendance changes.")
        return false
    end

    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and record.r and record.r[raidID]
    nameID = tonumber(nameID)
    if type(raid) ~= "table" or not nameID then
        return false
    end

    raid.p = raid.p or {}
    raid.b = raid.b or {}
    raid.late = raid.late or {}
    raid.out = raid.out or {}
    raid.noshow = raid.noshow or {}

    if status == "bench" then
        raid.b[nameID] = nil
    elseif status == "late" then
        raid.late[nameID] = nil
    elseif status == "out" then
        raid.out[nameID] = nil
    elseif status == "noshow" then
        raid.noshow[nameID] = nil
    else
        raid.p[nameID] = nil
        raid.b[nameID] = nil
        raid.late[nameID] = nil
    end

    raid.en = math.max(tonumber(raid.en) or 0, LV.Util:Now())
    raid.lastBy = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    raid.lastSource = "ui_edit"
    return true
end

function LV.UI:RaidTeamName(guildKey, raid)
    if not raid then
        return ""
    end
    if raid.tn then
        return LV.Store:DictionaryValue(guildKey, "s", raid.tn)
    end
    return raid.team or "main"
end

function LV.UI:AttendanceRows(record)
    local rows = {}
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" then
            rows[#rows + 1] = { id = raidID, raid = raid }
        end
    end
    table.sort(rows, function(a, b)
        local ast = tonumber(a.raid.st) or 0
        local bst = tonumber(b.raid.st) or 0
        if ast ~= bst then
            return ast > bst
        end
        return compareText(a.id, b.id)
    end)
    return rows
end

function LV.UI:AttendanceNames(guildKey, map)
    local names = {}
    for id, _ in pairs(map or {}) do
        local name = LV.Store:DictionaryValue(guildKey, "n", id)
        if name ~= "" then
            names[#names + 1] = {
                id = tonumber(id) or id,
                fullName = name,
                name = LV.Util:ShortName(name),
            }
        end
    end
    table.sort(names, function(a, b)
        return compareText(a.name, b.name)
    end)

    return names
end

function LV.UI:ExclusiveHereMap(raid)
    local map = {}
    if type(raid) ~= "table" then
        return map
    end

    for id, value in pairs(raid.p or {}) do
        if not ((raid.b or {})[id] or (raid.late or {})[id] or (raid.out or {})[id] or (raid.noshow or {})[id]) then
            map[id] = value
        end
    end
    return map
end

function LV.UI:AttendanceRollupID(guildKey, nameID)
    nameID = tonumber(nameID)
    if not nameID then
        return nil, "pug"
    end

    local tag, mainID = LV.Guild:InferRosterTag(guildKey, nameID)
    if tag == "alt" and mainID then
        return tonumber(mainID) or mainID, tag
    end
    return nameID, tag
end

function LV.UI:AttendanceStatusPriority(status, actorID, rollupID)
    local priority = {
        here = 60,
        bench = 50,
        late = 40,
        out = 30,
        noshow = 20,
        empty = 0,
    }
    local value = priority[status or "empty"] or 0
    if tonumber(actorID) == tonumber(rollupID) then
        value = value + 1
    end
    return value
end

function LV.UI:AddRollupCandidate(guildKey, record, rows, grouped, id, status, includePugs)
    local fullName = LV.Store:DictionaryValue(guildKey, "n", id)
    if fullName == "" then
        return
    end

    local rollupID = self:AttendanceRollupID(guildKey, id)
    if not rollupID then
        return
    end

    local rollupTag = LV.Guild:InferRosterTag(guildKey, rollupID)
    if rollupTag == "pug" and not includePugs then
        return
    end

    local rollupName = LV.Store:DictionaryValue(guildKey, "n", rollupID)
    if rollupName == "" then
        rollupName = fullName
        rollupID = tonumber(id) or id
    end

    local row = rows[rollupID]
    if not row then
        row = {
            id = tonumber(rollupID) or rollupID,
            name = LV.Util:ShortName(rollupName),
            fullName = rollupName,
            here = 0,
            late = 0,
            out = 0,
            noshow = 0,
            total = 0,
            attended = 0,
            nights = {},
            rosterTag = rollupTag or "guild",
        }
        rows[rollupID] = row
    end

    local candidate = {
        status = status,
        actorID = tonumber(id) or id,
        actorName = LV.Util:ShortName(fullName),
    }
    local existing = grouped[rollupID]
    if not existing or self:AttendanceStatusPriority(candidate.status, candidate.actorID, rollupID) > self:AttendanceStatusPriority(existing.status, existing.actorID, rollupID) then
        grouped[rollupID] = candidate
    end
end

function LV.UI:AltRowsForMain(guildKey, mainID)
    local record = LV.Store:GuildRecord(guildKey)
    local rows = {}
    mainID = tonumber(mainID)
    if not record or not mainID then
        return rows
    end

    for id, _ in ipairs((record.d and record.d.n) or {}) do
        local tag, altMainID = LV.Guild:InferRosterTag(guildKey, id)
        if tag == "alt" and tonumber(altMainID) == mainID then
            local fullName = LV.Store:DictionaryValue(guildKey, "n", id)
            if fullName ~= "" then
                rows[#rows + 1] = {
                    id = tonumber(id) or id,
                    fullName = fullName,
                    name = LV.Util:ShortName(fullName),
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        return compareText(a.name, b.name)
    end)
    return rows
end

function LV.UI:AttendanceMeterRows(guildKey, record, months, teamID, showPugs)
    local cutoff = LV.Util:Now() - ((tonumber(months) or 3) * 30 * 86400)
    local players = {}
    local raidRows = {}
    local groupedByRaid = {}

    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and (tonumber(raid.st) or 0) >= cutoff and (teamID == "all" or raid.team == teamID) then
            raidRows[#raidRows + 1] = { id = raidID, raid = raid }
        end
    end
    table.sort(raidRows, function(a, b)
        local ast = tonumber(a.raid.st) or 0
        local bst = tonumber(b.raid.st) or 0
        if ast ~= bst then
            return ast > bst
        end
        return compareText(a.id, b.id)
    end)

    for _, raidRow in ipairs(raidRows) do
        local raid = raidRow.raid
        local statusByID = {}

        for id, _ in pairs(raid.p or {}) do
            statusByID[id] = "here"
        end
        for id, _ in pairs(raid.b or {}) do
            statusByID[id] = "bench"
        end
        for id, _ in pairs(raid.late or {}) do
            statusByID[id] = "late"
        end
        for id, _ in pairs(raid.out or {}) do
            statusByID[id] = "out"
        end
        for id, _ in pairs(raid.noshow or {}) do
            statusByID[id] = "noshow"
        end

        local grouped = {}
        groupedByRaid[raidRow.id] = grouped
        for id, status in pairs(statusByID) do
            self:AddRollupCandidate(guildKey, record, players, grouped, id, status, showPugs and true or false)
        end

        for rollupID, choice in pairs(grouped) do
            local row = players[rollupID]
            if row and choice then
                if choice.status == "bench" then
                    row.here = (row.here or 0) + 1
                else
                    row[choice.status] = (row[choice.status] or 0) + 1
                end
                if choice.status == "here" or choice.status == "bench" or choice.status == "late" then
                    row.attended = row.attended + 1
                end
                if choice.status ~= "empty" then
                    row.total = row.total + 1
                end
            end
        end
    end

    for _, row in pairs(players) do
        for _, raidRow in ipairs(raidRows) do
            local choice = groupedByRaid[raidRow.id] and groupedByRaid[raidRow.id][row.id]
            row.nights[#row.nights + 1] = {
                raidID = raidRow.id,
                raid = raidRow.raid,
                status = choice and choice.status or "empty",
                actorID = choice and choice.actorID or nil,
                actorName = choice and choice.actorName or nil,
            }
        end
    end

    local rows = {}
    for _, row in pairs(players) do
        rows[#rows + 1] = row
    end

    table.sort(rows, function(a, b)
        if a.attended ~= b.attended then
            return a.attended > b.attended
        end
        if a.total ~= b.total then
            return a.total > b.total
        end
        return compareText(a.name, b.name)
    end)

    local guildRows = {}
    local pugRows = {}
    for _, row in ipairs(rows) do
        if row.rosterTag == "pug" then
            pugRows[#pugRows + 1] = row
        else
            guildRows[#guildRows + 1] = row
        end
    end

    return rows, #raidRows, #raidRows, guildRows, pugRows
end

function LV.UI:RenderAttendance()
    local guildInfo = self:CurrentGuildOrMessage()
    if not guildInfo then
        return
    end

    local record = LV.Store:GuildRecord(guildInfo.key)
    local cfg = LV.Store:GetConfig(guildInfo.key)
    local session = LV.Raid:GetActiveSession()
    local recentSession = nil
    if not session then
        recentSession = LV.Raid:FindMostRecentSession(record)
    end
    local title = LV.Widgets:Text(self.content, "Attendance", "large")
    title:SetPoint("TOPLEFT", 22, -20)

    local statusText = "No active raid"
    if session then
        statusText = "Tracking " .. (self:RaidTeamName(guildInfo.key, session) or "Raid")
        if session.adhoc then
            statusText = statusText .. " ad hoc"
        end
    end
    local status = LV.Widgets:Text(self.content, statusText)
    status:SetTextColor(unpack(session and LV.Widgets.colors.white or LV.Widgets.colors.muted))
    status:SetPoint("LEFT", title, "RIGHT", 18, -2)

    local adHoc = LV.Widgets:Button(self.content, "AdHoc Raid", 104, 28, function()
        self.showAdHocEditor = not self.showAdHocEditor
        self:Refresh()
    end)
    adHoc:SetPoint("TOPRIGHT", (session or recentSession) and -142 or -22, -18)

    if session then
        local stop = LV.Widgets:Button(self.content, "Stop Raid", 100, 28, function()
            LV.Raid:EndSession("ui")
        end)
        stop:SetPoint("TOPRIGHT", -22, -18)
    elseif recentSession then
        local extend = LV.Widgets:Button(self.content, "Extend Last", 100, 28, function()
            local extended = LV.Raid:ExtendMostRecentSession(tonumber(self.adHocHours) or 3)
            if extended then
                self.attendanceSelectedRaid = extended.id
                self.attendanceDetailOffset = 0
            end
        end)
        extend:SetPoint("TOPRIGHT", -22, -18)
    end

    local y = -62
    if self.showAdHocEditor then
        local editor = LV.Widgets:Section(self.content, "AdHoc Raid", 88)
        editor:SetPoint("TOPLEFT", 22, y)
        editor:SetPoint("RIGHT", -22, 0)

        local teamLabel = LV.Widgets:Label(editor, "Raid Tag")
        teamLabel:SetPoint("TOPLEFT", 24, -48)
        local selectedTeamID = self.adHocTeamID or cfg.selectedTeam or "main"
        local team = LV.Widgets:Dropdown(editor, self:TeamValues(cfg), function()
            return selectedTeamID
        end, function(value)
            self.adHocTeamID = value
            selectedTeamID = value
        end, 126)
        team:SetPoint("LEFT", teamLabel, "RIGHT", 16, 0)

        local durationLabel = LV.Widgets:Label(editor, "Duration Hours")
        durationLabel:SetPoint("LEFT", team, "RIGHT", 28, 0)
        local duration = LV.Widgets:EditBox(editor, 52, 26, function(value)
            self.adHocHours = tonumber(value) or 3
        end)
        duration:SetText(tostring(self.adHocHours or 3))
        duration:SetPoint("LEFT", durationLabel, "RIGHT", 12, 0)

        local start = LV.Widgets:Button(editor, "Start", 74, 26, function()
            local hours = tonumber(duration:GetText()) or tonumber(self.adHocHours) or 3
            self.adHocHours = hours
            self.adHocTeamID = selectedTeamID
            local started = LV.Raid:StartAdHocSession(selectedTeamID, hours)
            if started then
                self.showAdHocEditor = false
                self.attendanceSelectedRaid = started.id
                self.attendanceDetailOffset = 0
                self:Refresh()
            end
        end)
        start:SetPoint("LEFT", duration, "RIGHT", 18, 0)
        y = y - 106
    end

    local summary = LV.Widgets:Section(self.content, "Raid Nights", 248)
    summary:SetPoint("TOPLEFT", 22, y)
    summary:SetPoint("RIGHT", -22, 0)
    self:RenderAttendanceHistory(summary, guildInfo.key, record)

    local detail = LV.Widgets:Section(self.content, "Attendance Detail", 220)
    detail:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -18)
    detail:SetPoint("BOTTOMRIGHT", -22, 22)
    self:RenderAttendanceDetail(detail, guildInfo.key, record)
end

function LV.UI:RenderAttendanceHistory(parent, guildKey, record)
    local rows = self:AttendanceRows(record)
    self.attendanceOffset = tonumber(self.attendanceOffset) or 0
    if self.attendanceOffset >= #rows then
        self.attendanceOffset = math.max(0, #rows - ATTENDANCE_PAGE_SIZE)
    end
    if (not self.attendanceSelectedRaid or type(record.r[self.attendanceSelectedRaid]) ~= "table") and rows[1] then
        local activeRaidID = record.cur and record.r[record.cur] and record.cur
        self.attendanceSelectedRaid = activeRaidID or rows[1].id
        self.attendanceDetailOffset = 0
        for index, row in ipairs(rows) do
            if tostring(row.id) == tostring(self.attendanceSelectedRaid) then
                self.attendanceOffset = math.floor((index - 1) / ATTENDANCE_PAGE_SIZE) * ATTENDANCE_PAGE_SIZE
                break
            end
        end
    end

    local count = LV.Widgets:Text(parent.header, tostring(#rows) .. " raid(s)")
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    count:SetPoint("RIGHT", -18, 0)

    local newer = LV.Widgets:Button(parent.header, "<", 26, 22, function()
        self.attendanceOffset = math.max(0, (self.attendanceOffset or 0) - ATTENDANCE_PAGE_SIZE)
        self:Refresh()
    end)
    newer:SetPoint("RIGHT", count, "LEFT", -10, 0)

    local older = LV.Widgets:Button(parent.header, ">", 26, 22, function()
        self.attendanceOffset = math.min(math.max(0, #rows - ATTENDANCE_PAGE_SIZE), (self.attendanceOffset or 0) + ATTENDANCE_PAGE_SIZE)
        self:Refresh()
    end)
    older:SetPoint("RIGHT", newer, "LEFT", -6, 0)

    if self.attendanceOffset <= 0 then
        newer:Hide()
    end
    if self.attendanceOffset >= math.max(0, #rows - ATTENDANCE_PAGE_SIZE) then
        older:Hide()
    end

    local headers = {
        { "Date", 24 },
        { "Tag", 124 },
        { "Here", 218 },
        { "Bench", 266 },
        { "Late", 322 },
        { "Out", 374 },
        { "NoShow", 426 },
        { "Kills", 498 },
        { "Type", 540 },
        { "Edit", 592 },
        { "Del", 646 },
    }
    for _, header in ipairs(headers) do
        local label = LV.Widgets:Label(parent, header[1])
        label:SetPoint("TOPLEFT", header[2], -48)
    end

    if #rows == 0 then
        local empty = LV.Widgets:Text(parent, "No tracked raid attendance yet.")
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, -84)
        return
    end

    local y = -78
    for index = self.attendanceOffset + 1, math.min(#rows, self.attendanceOffset + ATTENDANCE_PAGE_SIZE) do
        local row = rows[index]
        local raid = row.raid
        local selected = tostring(self.attendanceSelectedRaid) == tostring(row.id)
        local active = record.cur and tostring(record.cur) == tostring(row.id)
        local rowColor = selected and LV.Widgets.colors.active or (active and LV.Widgets.colors.header or LV.Widgets.colors.panel)
        local borderColor = active and LV.Widgets.colors.yellow or LV.Widgets.colors.border

        local rowButton = CreateFrame("Button", nil, parent, "BackdropTemplate")
        rowButton:SetPoint("TOPLEFT", 16, y + 5)
        rowButton:SetPoint("TOPRIGHT", -18, y + 5)
        rowButton:SetHeight(24)
        LV.Widgets:ApplyBackdrop(rowButton, rowColor, borderColor)
        self:DrawTeamAccent(rowButton, guildKey, raid)
        rowButton:SetScript("OnClick", function()
            self.attendanceSelectedRaid = row.id
            self.attendanceDetailOffset = 0
            self:Refresh()
        end)
        rowButton:SetScript("OnEnter", function()
            rowButton:SetBackdropColor(unpack(LV.Widgets.colors.active))
            rowButton:SetBackdropBorderColor(unpack(borderColor))
        end)
        rowButton:SetScript("OnLeave", function()
            rowButton:SetBackdropColor(unpack(rowColor))
            rowButton:SetBackdropBorderColor(unpack(borderColor))
        end)

        local dateText = LV.Widgets:Text(rowButton, date("%m/%d %H:%M", tonumber(raid.st) or 0))
        dateText:SetPoint("LEFT", 14, 0)
        local team = LV.Widgets:Text(rowButton, self:RaidTeamName(guildKey, raid))
        team:SetPoint("LEFT", 108, 0)
        local teamColor = self:RaidTeamColor(guildKey, raid)
        team:SetTextColor(teamColor.r, teamColor.g, teamColor.b, 1)
        local here = LV.Widgets:Text(rowButton, tostring(self:MapCount(self:ExclusiveHereMap(raid))))
        here:SetPoint("LEFT", 202, 0)
        local bench = LV.Widgets:Text(rowButton, tostring(self:MapCount(raid.b)))
        bench:SetPoint("LEFT", 250, 0)
        local late = LV.Widgets:Text(rowButton, tostring(self:MapCount(raid.late)))
        late:SetPoint("LEFT", 306, 0)
        local out = LV.Widgets:Text(rowButton, tostring(self:MapCount(raid.out)))
        out:SetPoint("LEFT", 358, 0)
        local noshow = LV.Widgets:Text(rowButton, tostring(self:MapCount(raid.noshow)))
        noshow:SetPoint("LEFT", 410, 0)
        local kills = LV.Widgets:Text(rowButton, tostring(#(raid.kills or {})))
        kills:SetPoint("LEFT", 482, 0)
        local raidType = LV.Widgets:Text(rowButton, raid.adhoc and "adhoc" or (raid.reason or "raid"))
        raidType:SetPoint("LEFT", 524, 0)
        raidType:SetWidth(58)
        raidType:SetWordWrap(false)
        if active then
            raidType:SetTextColor(unpack(LV.Widgets.colors.yellow))
        end
        local edit = LV.Widgets:Button(rowButton, "Edit", 40, 20, function()
            if not LV.Guild:CanModifySession() then
                LV:Print("Your current LootViewer authority settings do not allow attendance changes.")
                return
            end
            self.attendanceSelectedRaid = row.id
            self.attendanceDetailOffset = 0
            self.editingRaidID = self.editingRaidID == row.id and nil or row.id
            self:Refresh()
        end)
        edit:SetPoint("RIGHT", -36, 0)
        LV.Widgets:SetTooltip(edit, "Edit player attendance for this raid night.")
        local delete = LV.Widgets:Button(rowButton, "X", 26, 20, function()
            StaticPopup_Show(LV.Constants.DELETE_RAID_PROMPT, date("%m/%d %H:%M", tonumber(raid.st) or 0), nil, {
                guildKey = guildKey,
                raidID = row.id,
            })
        end)
        delete:SetPoint("RIGHT", -4, 0)
        LV.Widgets:SetTooltip(delete, "Delete this raid attendance record.")
        y = y - 28
    end
end

function LV.UI:RenderAttendanceDetail(parent, guildKey, record)
    local raid = self.attendanceSelectedRaid and record.r[self.attendanceSelectedRaid]
    if type(raid) ~= "table" then
        local empty = LV.Widgets:Text(parent, "Select a raid night above.")
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, -48)
        return
    end

    local title = LV.Widgets:Text(parent, date("%m/%d/%y %H:%M", tonumber(raid.st) or 0) .. "  " .. self:RaidTeamName(guildKey, raid))
    title:SetPoint("TOPLEFT", 24, -48)

    local editMode = self.editingRaidID == self.attendanceSelectedRaid
    if editMode then
        local done = LV.Widgets:Button(parent, "Done", 56, 22, function()
            self.editingRaidID = nil
            self:Refresh()
        end)
        done:SetPoint("TOPRIGHT", -24, -44)
    end

    local ended = tonumber(raid.en) or tonumber(raid.st) or 0
    local duration = math.max(0, math.floor((ended - (tonumber(raid.st) or ended)) / 60))
    local meta = LV.Widgets:Text(parent, tostring(duration) .. " min  " .. tostring(#(raid.kills or {})) .. " boss kill(s)")
    meta:SetTextColor(unpack(LV.Widgets.colors.muted))
    meta:SetPoint("TOPLEFT", 24, -72)

    local headingY = -104
    local nameY = -130
    if editMode then
        local addLabel = LV.Widgets:Label(parent, "Add Player")
        addLabel:SetPoint("TOPLEFT", 24, -102)

        local nameEdit = LV.Widgets:EditBox(parent, 180, 24, function(value)
            self.raidEditName = value
        end)
        nameEdit:SetText(self.raidEditName or "")
        nameEdit:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)

        local previous = nameEdit
        for _, option in ipairs(attendanceStatusValues) do
            local width = option.value == "noshow" and 72 or option.value == "bench" and 62 or 54
            local addButton = LV.Widgets:Button(parent, option.label, width, 24, function()
                local value = nameEdit:GetText()
                if self:SetHistoricalRaidAttendance(guildKey, self.attendanceSelectedRaid, value, option.value) then
                    self.raidEditName = ""
                    self:Refresh()
                end
            end)
            addButton:SetPoint("LEFT", previous, "RIGHT", 8, 0)
            LV.Widgets:SetTooltip(addButton, "Add player to " .. option.label .. ".")
            previous = addButton
        end

        headingY = -140
        nameY = -166
    end

    local hereMap = self:ExclusiveHereMap(raid)
    local columns = {
        { "Here", "here", hereMap, 24 },
        { "Bench", "bench", raid.b, 154 },
        { "Late", "late", raid.late, 284 },
        { "Out", "out", raid.out, 414 },
        { "NoShow", "noshow", raid.noshow, 544 },
    }

    local columnData = {}
    local maxRows = 0
    for _, column in ipairs(columns) do
        local names = self:AttendanceNames(guildKey, column[3])
        maxRows = math.max(maxRows, #names)
        columnData[#columnData + 1] = {
            label = column[1],
            status = column[2],
            x = column[4],
            names = names,
        }
    end

    local visibleRows = editMode and 4 or 6
    local maxOffset = math.max(0, maxRows - visibleRows)
    self.attendanceDetailOffset = math.max(0, math.min(tonumber(self.attendanceDetailOffset) or 0, maxOffset))

    local function scrollDetail(delta)
        if maxOffset <= 0 then
            return
        end
        local nextOffset = (self.attendanceDetailOffset or 0) + (delta > 0 and -1 or 1)
        nextOffset = math.max(0, math.min(nextOffset, maxOffset))
        if nextOffset ~= self.attendanceDetailOffset then
            self.attendanceDetailOffset = nextOffset
            self:Refresh()
        end
    end

    parent:EnableMouse(true)
    parent:EnableMouseWheel(maxOffset > 0)
    parent:SetScript("OnMouseWheel", function(_, delta)
        scrollDetail(delta)
    end)

    if maxOffset > 0 then
        local range = LV.Widgets:Text(parent, tostring(self.attendanceDetailOffset + 1) .. "-" .. tostring(math.min(maxRows, self.attendanceDetailOffset + visibleRows)) .. "/" .. tostring(maxRows))
        range:SetTextColor(unpack(LV.Widgets.colors.muted))
        range:SetPoint("TOPRIGHT", -92, headingY + 2)

        local up = LV.Widgets:Button(parent, "^", 24, 20, function()
            scrollDetail(1)
        end)
        up:SetPoint("LEFT", range, "RIGHT", 8, 0)
        if self.attendanceDetailOffset <= 0 then
            up:Hide()
        end

        local down = LV.Widgets:Button(parent, "v", 24, 20, function()
            scrollDetail(-1)
        end)
        down:SetPoint("LEFT", up, "RIGHT", 4, 0)
        if self.attendanceDetailOffset >= maxOffset then
            down:Hide()
        end
    end

    for _, column in ipairs(columnData) do
        local heading = LV.Widgets:Label(parent, column.label .. " (" .. tostring(#column.names) .. ")")
        heading:SetPoint("TOPLEFT", column.x, headingY)
        heading:SetWidth(118)
        for index = self.attendanceDetailOffset + 1, math.min(#column.names, self.attendanceDetailOffset + visibleRows) do
            local entry = column.names[index]
            local y = nameY - ((index - self.attendanceDetailOffset - 1) * 20)
            local width = editMode and 88 or 118
            local nameButton = CreateFrame("Button", nil, parent)
            nameButton:SetPoint("TOPLEFT", column.x, y + 2)
            nameButton:SetSize(width, 18)
            nameButton:EnableMouseWheel(maxOffset > 0)
            nameButton:SetScript("OnMouseWheel", function(_, delta)
                scrollDetail(delta)
            end)
            nameButton:SetScript("OnClick", function()
                self:ShowPlayerDetailForName(guildKey, entry.id)
            end)

            local text = LV.Widgets:Text(nameButton, entry.name)
            text:SetPoint("LEFT", 0, 0)
            text:SetWidth(width)
            text:SetWordWrap(false)
            self:SetNameClassColor(text, guildKey, entry.id)
            nameButton:SetScript("OnEnter", function()
                text:SetTextColor(unpack(LV.Widgets.colors.yellow))
            end)
            nameButton:SetScript("OnLeave", function()
                self:SetNameClassColor(text, guildKey, entry.id)
            end)

            if editMode then
                local remove = LV.Widgets:Button(parent, "X", 18, 18, function()
                    if self:RemoveHistoricalRaidAttendance(guildKey, self.attendanceSelectedRaid, entry.id, column.status) then
                        self:Refresh()
                    end
                end)
                remove:SetPoint("TOPLEFT", column.x + 94, y + 2)
                LV.Widgets:SetTooltip(remove, "Remove " .. entry.name .. " from " .. column.label .. ".")
            end
        end
    end
end

function LV.UI:DrawMeterSegment(bar, color, x, width)
    width = math.floor(tonumber(width) or 0)
    if width <= 0 then
        return
    end

    local texture = bar:CreateTexture(nil, "ARTWORK")
    texture:SetColorTexture(unpack(color))
    texture:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -1)
    texture:SetSize(width, 14)
end

function LV.UI:DrawMeterBar(parent, row, maxTotal, x, y, width)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", x, y)
    bar:SetSize(width, 16)
    LV.Widgets:ApplyBackdrop(bar, meterColors.empty, LV.Widgets.colors.border)

    if maxTotal <= 0 or row.total <= 0 then
        return
    end

    local totalWidth = math.floor((width * row.total / maxTotal) + 0.5)
    if totalWidth < 2 then
        totalWidth = 2
    elseif totalWidth > width then
        totalWidth = width
    end

    local used = 0
    local remaining = row.total
    local segments = {
        { key = "here", count = row.here or 0 },
        { key = "late", count = row.late or 0 },
        { key = "out", count = row.out or 0 },
        { key = "noshow", count = row.noshow or 0 },
    }

    for _, segment in ipairs(segments) do
        if segment.count > 0 and used < totalWidth then
            local segmentWidth
            if remaining == segment.count then
                segmentWidth = totalWidth - used
            else
                segmentWidth = math.floor((totalWidth * segment.count / row.total) + 0.5)
            end
            segmentWidth = math.max(1, math.min(segmentWidth, totalWidth - used))
            self:DrawMeterSegment(bar, meterColors[segment.key], used, segmentWidth)
            used = used + segmentWidth
            remaining = remaining - segment.count
        end
    end
end

function LV.UI:DrawMeterLegend(parent, label, color, x, y)
    local swatch = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    swatch:SetPoint("TOPLEFT", x, y)
    swatch:SetSize(12, 12)
    LV.Widgets:ApplyBackdrop(swatch, color, color)

    local text = LV.Widgets:Text(parent, label)
    text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    text:SetTextColor(unpack(LV.Widgets.colors.muted))
end

function LV.UI:MeterDisplayRows(guildRows, pugRows, showPugs)
    local displayRows = {}
    guildRows = guildRows or {}
    pugRows = pugRows or {}

    if not showPugs then
        for _, row in ipairs(guildRows) do
            displayRows[#displayRows + 1] = { row = row }
        end
        return displayRows
    end

    if #pugRows > 0 then
        if #guildRows > 0 then
            displayRows[#displayRows + 1] = { section = "Guild Players", count = #guildRows }
            for _, row in ipairs(guildRows) do
                displayRows[#displayRows + 1] = { row = row }
            end
        end

        displayRows[#displayRows + 1] = { section = "Pugs", count = #pugRows }
        for _, row in ipairs(pugRows) do
            displayRows[#displayRows + 1] = { row = row }
        end
        return displayRows
    end

    for _, row in ipairs(guildRows) do
        displayRows[#displayRows + 1] = { row = row }
    end
    return displayRows
end

function LV.UI:MeterAttendancePercent(row, raidCount)
    raidCount = tonumber(raidCount) or 0
    if raidCount <= 0 then
        return 0
    end
    return math.floor((((row and row.attended) or 0) * 100 / raidCount) + 0.5)
end

function LV.UI:StatusLabel(status)
    if status == "here" then
        return "Here"
    elseif status == "bench" then
        return "Bench"
    elseif status == "late" then
        return "Late"
    elseif status == "out" then
        return "Out"
    elseif status == "noshow" then
        return "NoShow"
    end
    return "Not marked"
end

function LV.UI:EnsureMeterDetailFrame()
    if self.meterDetailFrame then
        return self.meterDetailFrame
    end

    local frame = CreateFrame("Frame", "LootViewerMeterDetailFrame", UIParent, "BackdropTemplate")
    frame:SetSize(700, 540)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(1200)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    frame._lvChildren = {}
    LV.Widgets:ApplyBackdrop(frame, LV.Widgets.colors.bg, LV.Widgets.colors.border)

    self.meterDetailFrame = frame
    return frame
end

function LV.UI:TrackMeterDetail(region)
    local frame = self:EnsureMeterDetailFrame()
    frame._lvChildren = frame._lvChildren or {}
    frame._lvChildren[#frame._lvChildren + 1] = region
    return region
end

function LV.UI:ClearMeterDetail()
    local frame = self:EnsureMeterDetailFrame()
    for _, region in ipairs(frame._lvChildren or {}) do
        if region and region.Hide then
            region:Hide()
        end
    end
    wipe(frame._lvChildren)
end

function LV.UI:DrawMeterDetailLegend(frame, label, color, x, y)
    local swatch = self:TrackMeterDetail(CreateFrame("Frame", nil, frame, "BackdropTemplate"))
    swatch:SetPoint("TOPLEFT", x, y)
    swatch:SetSize(12, 12)
    LV.Widgets:ApplyBackdrop(swatch, color, color)

    local text = self:TrackMeterDetail(LV.Widgets:Text(frame, label))
    text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    text:SetTextColor(unpack(LV.Widgets.colors.muted))
end

function LV.UI:RefreshMeterDetail(guildKey, playerID)
    local record = LV.Store:GuildRecord(guildKey)
    local rows, _, raidCount = self:AttendanceMeterRows(guildKey, record, self.meterMonths or 3, self.meterTeamID or "all", self.meterShowPugs)
    for _, row in ipairs(rows) do
        if tonumber(row.id) == tonumber(playerID) then
            self:ShowMeterPlayerDetail(guildKey, row, raidCount)
            return
        end
    end

    if self.meterDetailFrame then
        self.meterDetailFrame:Hide()
    end
end

function LV.UI:ShowPlayerDetailForName(guildKey, nameID)
    local playerID = self:AttendanceRollupID(guildKey, nameID)
    if not playerID then
        return
    end

    local record = LV.Store:GuildRecord(guildKey)
    local searches = {
        { months = self.meterMonths or 3, team = self.meterTeamID or "all" },
        { months = 12, team = "all" },
    }

    for _, search in ipairs(searches) do
        local rows, _, raidCount = self:AttendanceMeterRows(guildKey, record, search.months, search.team, true)
        for _, row in ipairs(rows) do
            if tonumber(row.id) == tonumber(playerID) then
                self.meterDetailOffset = 0
                self:ShowMeterPlayerDetail(guildKey, row, raidCount)
                return
            end
        end
    end
end

function LV.UI:RenderMeterDetailAlts(frame, guildKey, row)
    local label = self:TrackMeterDetail(LV.Widgets:Label(frame, "Alts"))
    label:SetPoint("TOPLEFT", 24, -118)

    local alts = self:AltRowsForMain(guildKey, row.id)
    if #alts == 0 then
        local empty = self:TrackMeterDetail(LV.Widgets:Text(frame, "None"))
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("LEFT", label, "RIGHT", 14, 0)
        return
    end

    local startX = 78
    local startY = -118
    for index, alt in ipairs(alts) do
        local x = startX + (((index - 1) % 4) * 142)
        local y = startY - (math.floor((index - 1) / 4) * 24)
        local name = self:TrackMeterDetail(LV.Widgets:Text(frame, alt.name))
        name:SetPoint("TOPLEFT", x, y)
        name:SetWidth(94)
        name:SetWordWrap(false)
        self:SetNameClassColor(name, guildKey, alt.id)

        local remove = self:TrackMeterDetail(LV.Widgets:Button(frame, "X", 18, 18, function()
            LV.Guild:SetRosterOverride(guildKey, alt.fullName, "guild", "")
            self:Refresh()
            self:RefreshMeterDetail(guildKey, row.id)
        end))
        remove:SetPoint("TOPLEFT", x + 96, y + 2)
        LV.Widgets:SetTooltip(remove, "Untag " .. alt.name .. " as an alt.")
    end
end

function LV.UI:RenderMeterDetailGrid(frame, guildKey, row, raidCount)
    local nights = row.nights or {}
    self.meterDetailOffset = tonumber(self.meterDetailOffset) or 0
    if self.meterDetailOffset >= #nights then
        self.meterDetailOffset = math.max(0, #nights - METER_DETAIL_PAGE_SIZE)
    end

    local newer = self:TrackMeterDetail(LV.Widgets:Button(frame, "<", 26, 22, function()
        self.meterDetailOffset = math.max(0, (self.meterDetailOffset or 0) - METER_DETAIL_PAGE_SIZE)
        self:ShowMeterPlayerDetail(guildKey, row, raidCount)
    end))
    newer:SetPoint("TOPRIGHT", -70, -202)

    local older = self:TrackMeterDetail(LV.Widgets:Button(frame, ">", 26, 22, function()
        self.meterDetailOffset = math.min(math.max(0, #nights - METER_DETAIL_PAGE_SIZE), (self.meterDetailOffset or 0) + METER_DETAIL_PAGE_SIZE)
        self:ShowMeterPlayerDetail(guildKey, row, raidCount)
    end))
    older:SetPoint("LEFT", newer, "RIGHT", 6, 0)

    if self.meterDetailOffset <= 0 then
        newer:Hide()
    end
    if self.meterDetailOffset >= math.max(0, #nights - METER_DETAIL_PAGE_SIZE) then
        older:Hide()
    end

    local startX = 28
    local startY = -232
    for index = self.meterDetailOffset + 1, math.min(#nights, self.meterDetailOffset + METER_DETAIL_PAGE_SIZE) do
        local night = nights[index]
        local rowIndex = index - self.meterDetailOffset - 1
        local y = startY - (rowIndex * 30)
        local status = night.status or "empty"
        local color = detailStatusColors[status] or detailStatusColors.empty
        local teamColor = self:RaidTeamColor(guildKey, night.raid)

        local rowButton = self:TrackMeterDetail(CreateFrame("Button", nil, frame, "BackdropTemplate"))
        rowButton:SetPoint("TOPLEFT", startX - 4, y + 4)
        rowButton:SetSize(620, 26)
        LV.Widgets:ApplyBackdrop(rowButton, LV.Widgets.colors.panel, LV.Widgets.colors.border)
        self:DrawTeamAccent(rowButton, guildKey, night.raid)
        rowButton:SetScript("OnClick", function()
            self.attendanceSelectedRaid = night.raidID
            self.currentTab = "attendance"
            self.editingRaidID = nil
            frame:Hide()
            self:Refresh()
        end)
        rowButton:SetScript("OnEnter", function()
            rowButton:SetBackdropColor(unpack(LV.Widgets.colors.header))
            GameTooltip:SetOwner(rowButton, "ANCHOR_RIGHT")
            GameTooltip:SetText(date("%m/%d/%y %H:%M", tonumber(night.raid.st) or 0) .. " - " .. self:RaidTeamName(guildKey, night.raid))
            GameTooltip:AddLine(self:StatusLabel(status), 1, 1, 1)
            GameTooltip:Show()
        end)
        rowButton:SetScript("OnLeave", function()
            rowButton:SetBackdropColor(unpack(LV.Widgets.colors.panel))
            GameTooltip:Hide()
        end)

        local square = self:TrackMeterDetail(CreateFrame("Frame", nil, rowButton, "BackdropTemplate"))
        square:SetPoint("LEFT", 16, 0)
        square:SetSize(16, 16)
        LV.Widgets:ApplyBackdrop(square, color, LV.Widgets.colors.border)

        local actorText = ""
        if night.actorName and night.actorName ~= "" and night.actorName ~= row.name then
            actorText = " (as " .. night.actorName .. ")"
        end
        local text = self:TrackMeterDetail(LV.Widgets:Text(rowButton,
            date("%m/%d/%Y %H:%M", tonumber(night.raid.st) or 0)
            .. actorText
        ))
        text:SetPoint("LEFT", square, "RIGHT", 10, 0)
        text:SetWidth(570)
        text:SetWordWrap(false)
        text:SetTextColor(teamColor.r, teamColor.g, teamColor.b, 1)
    end
end

function LV.UI:ShowMeterPlayerDetail(guildKey, row, raidCount)
    local frame = self:EnsureMeterDetailFrame()
    self:ClearMeterDetail()
    local currentTag, currentMainID = LV.Guild:InferRosterTag(guildKey, row.id)
    local currentMainName = currentMainID and LV.Store:DictionaryValue(guildKey, "n", currentMainID) or ""
    if self.meterDetailPlayerID ~= row.id then
        self.meterDetailPlayerID = row.id
        self.meterDetailTag = currentTag or "guild"
        self.meterDetailMain = currentMainName ~= "" and LV.Util:ShortName(currentMainName) or ""
        self.meterDetailClass = self:PlayerClassToken(guildKey, row.id)
    end

    local title = self:TrackMeterDetail(LV.Widgets:Text(frame, row.name, "large"))
    title:SetPoint("TOPLEFT", 22, -18)
    self:SetNameClassColor(title, guildKey, row.id)

    local close = self:TrackMeterDetail(LV.Widgets:Button(frame, "X", 30, 26, function()
        frame:Hide()
    end))
    close:SetPoint("TOPRIGHT", -12, -12)

    local percent = self:MeterAttendancePercent(row, raidCount)
    local summary = self:TrackMeterDetail(LV.Widgets:Text(frame, tostring(percent) .. "% attendance  " .. tostring(row.attended or 0) .. "/" .. tostring(raidCount) .. " attended"))
    summary:SetTextColor(unpack(LV.Widgets.colors.muted))
    summary:SetPoint("TOPLEFT", 22, -48)

    local tagLabel = self:TrackMeterDetail(LV.Widgets:Label(frame, "Tag"))
    tagLabel:SetPoint("TOPLEFT", 24, -82)
    local tag = self:TrackMeterDetail(LV.Widgets:Dropdown(frame, rosterTagValues, function()
        return self.meterDetailTag or "guild"
    end, function(value)
        self.meterDetailTag = value
    end, 76))
    tag:SetPoint("LEFT", tagLabel, "RIGHT", 12, 0)

    local mainLabel = self:TrackMeterDetail(LV.Widgets:Label(frame, "Main"))
    mainLabel:SetPoint("LEFT", tag, "RIGHT", 20, 0)
    local mainEdit = self:TrackMeterDetail(LV.Widgets:EditBox(frame, 120, 24, function(value)
        self.meterDetailMain = value
    end))
    mainEdit:SetText(self.meterDetailMain or "")
    mainEdit:SetPoint("LEFT", mainLabel, "RIGHT", 10, 0)

    local class = self:TrackMeterDetail(LV.Widgets:Dropdown(frame, classValues, function()
        return self.meterDetailClass or ""
    end, function(value)
        self.meterDetailClass = value
    end, 118))
    class:SetPoint("LEFT", mainEdit, "RIGHT", 14, 0)

    local save = self:TrackMeterDetail(LV.Widgets:Button(frame, "Save", 58, 24, function()
        self.meterDetailMain = mainEdit:GetText()
        if self.meterDetailClass and self.meterDetailClass ~= "" then
            LV.Store:SetPlayerClass(guildKey, row.id, self.meterDetailClass)
        end
        LV.Guild:SetRosterOverride(guildKey, row.fullName or LV.Store:DictionaryValue(guildKey, "n", row.id), self.meterDetailTag or "guild", self.meterDetailMain or "")
        self:Refresh()
        self:RefreshMeterDetail(guildKey, row.id)
    end))
    save:SetPoint("LEFT", class, "RIGHT", 12, 0)

    self:RenderMeterDetailAlts(frame, guildKey, row)

    self:DrawMeterDetailLegend(frame, "Here / Bench", detailStatusColors.here, 24, -166)
    self:DrawMeterDetailLegend(frame, "Late", detailStatusColors.late, 150, -166)
    self:DrawMeterDetailLegend(frame, "Out", detailStatusColors.out, 218, -166)
    self:DrawMeterDetailLegend(frame, "NoShow", detailStatusColors.noshow, 280, -166)
    self:DrawMeterDetailLegend(frame, "Not marked", detailStatusColors.empty, 380, -166)

    local nightsTitle = self:TrackMeterDetail(LV.Widgets:Label(frame, "Raid Nights - Newest First"))
    nightsTitle:SetPoint("TOPLEFT", 24, -204)

    self:RenderMeterDetailGrid(frame, guildKey, row, raidCount)
    frame:Show()
    frame:Raise()
end

function LV.UI:RenderAttendanceMeter()
    local guildInfo = self:CurrentGuildOrMessage()
    if not guildInfo then
        return
    end

    local record = LV.Store:GuildRecord(guildInfo.key)
    local cfg = LV.Store:GetConfig(guildInfo.key)
    self.meterMonths = tonumber(self.meterMonths) or 3
    if self.meterMonths < 1 or self.meterMonths > 12 then
        self.meterMonths = 3
    end
    self.meterTeamID = self.meterTeamID or "all"

    local teamValues = self:MeterTeamValues(cfg)
    local validTeam = false
    for _, item in ipairs(teamValues) do
        if item.value == self.meterTeamID then
            validTeam = true
            break
        end
    end
    if not validTeam then
        self.meterTeamID = "all"
    end
    self.meterShowPugs = self.meterShowPugs and true or false

    local title = LV.Widgets:Text(self.content, "Attendance Meter", "large")
    title:SetPoint("TOPLEFT", 22, -20)

    local showPugs = LV.Widgets:Check(self.content, "Show Pugs", function(value)
        self.meterShowPugs = value
        self.meterOffset = 0
        self:Refresh()
    end)
    showPugs:SetPoint("LEFT", title, "RIGHT", 18, -2)
    showPugs:SetChecked(self.meterShowPugs)

    local monthsLabel = LV.Widgets:Label(self.content, "Last Months")
    monthsLabel:SetPoint("TOPRIGHT", -280, -22)
    local months = LV.Widgets:Dropdown(self.content, meterMonthValues, function()
        return self.meterMonths
    end, function(value)
        self.meterMonths = tonumber(value) or 3
        self.meterOffset = 0
        self:Refresh()
    end, 58)
    months:SetPoint("LEFT", monthsLabel, "RIGHT", 10, -1)

    local teamLabel = LV.Widgets:Label(self.content, "Raid Tag")
    teamLabel:SetPoint("LEFT", months, "RIGHT", 22, 1)
    local team = LV.Widgets:Dropdown(self.content, teamValues, function()
        return self.meterTeamID
    end, function(value)
        self.meterTeamID = value
        self.meterOffset = 0
        self:Refresh()
    end, 118)
    team:SetPoint("LEFT", teamLabel, "RIGHT", 10, -1)

    local panel = LV.Widgets:Section(self.content, "Attendance Meter", 520)
    panel:SetPoint("TOPLEFT", 22, -62)
    panel:SetPoint("BOTTOMRIGHT", -22, 22)

    local rows, maxTotal, raidCount, guildRows, pugRows = self:AttendanceMeterRows(guildInfo.key, record, self.meterMonths, self.meterTeamID, self.meterShowPugs)
    local displayRows = self:MeterDisplayRows(guildRows, pugRows, self.meterShowPugs)
    self.meterOffset = tonumber(self.meterOffset) or 0
    if self.meterOffset >= #displayRows then
        self.meterOffset = math.max(0, #displayRows - ATTENDANCE_METER_PAGE_SIZE)
    end

    local countText
    if self.meterShowPugs then
        countText = tostring(#(guildRows or {})) .. " guild player(s), " .. tostring(#(pugRows or {})) .. " pug(s), " .. tostring(raidCount) .. " raid(s)"
    else
        countText = tostring(#rows) .. " player(s), " .. tostring(raidCount) .. " raid(s)"
    end
    local count = LV.Widgets:Text(panel.header, countText)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    count:SetPoint("RIGHT", -18, 0)

    local newer = LV.Widgets:Button(panel.header, "<", 26, 22, function()
        self.meterOffset = math.max(0, (self.meterOffset or 0) - ATTENDANCE_METER_PAGE_SIZE)
        self:Refresh()
    end)
    newer:SetPoint("RIGHT", count, "LEFT", -10, 0)

    local older = LV.Widgets:Button(panel.header, ">", 26, 22, function()
        self.meterOffset = math.min(math.max(0, #displayRows - ATTENDANCE_METER_PAGE_SIZE), (self.meterOffset or 0) + ATTENDANCE_METER_PAGE_SIZE)
        self:Refresh()
    end)
    older:SetPoint("RIGHT", newer, "LEFT", -6, 0)

    if self.meterOffset <= 0 then
        newer:Hide()
    end
    if self.meterOffset >= math.max(0, #displayRows - ATTENDANCE_METER_PAGE_SIZE) then
        older:Hide()
    end

    self:DrawMeterLegend(panel, "Here / Bench", meterColors.here, 24, -46)
    self:DrawMeterLegend(panel, "Late", meterColors.late, 150, -46)
    self:DrawMeterLegend(panel, "Posted Out", meterColors.out, 218, -46)
    self:DrawMeterLegend(panel, "NoShow", meterColors.noshow, 334, -46)

    local headerName = LV.Widgets:Label(panel, "Player")
    headerName:SetPoint("TOPLEFT", 24, -76)
    local headerBar = LV.Widgets:Label(panel, "Attendance")
    headerBar:SetPoint("TOPLEFT", 146, -76)
    local headerRaids = LV.Widgets:Label(panel, "Attend")
    headerRaids:SetPoint("TOPLEFT", 590, -76)

    if raidCount == 0 or #rows == 0 then
        local empty = LV.Widgets:Text(panel, "No marked raid attendance in this window.")
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, -110)
        return
    end

    local y = -106
    local barWidth = 420
    for index = self.meterOffset + 1, math.min(#displayRows, self.meterOffset + ATTENDANCE_METER_PAGE_SIZE) do
        local item = displayRows[index]
        if item.section then
            local section = LV.Widgets:Label(panel, item.section .. " (" .. tostring(item.count or 0) .. ")")
            section:SetPoint("TOPLEFT", 24, y + 2)
            y = y - 24
        else
            local row = item.row
            local nameButton = CreateFrame("Button", nil, panel)
            nameButton:SetPoint("TOPLEFT", 24, y + 1)
            nameButton:SetSize(108, 18)
            nameButton.text = LV.Widgets:Text(nameButton, row.name)
            nameButton.text:SetPoint("LEFT", 0, 0)
            nameButton.text:SetWidth(108)
            nameButton.text:SetWordWrap(false)
            self:SetNameClassColor(nameButton.text, guildInfo.key, row.id)
            nameButton:SetScript("OnEnter", function()
                nameButton.text:SetTextColor(unpack(LV.Widgets.colors.yellow))
            end)
            nameButton:SetScript("OnLeave", function()
                self:SetNameClassColor(nameButton.text, guildInfo.key, row.id)
            end)
            nameButton:SetScript("OnClick", function()
                self.meterDetailOffset = 0
                self:ShowMeterPlayerDetail(guildInfo.key, row, raidCount)
            end)

            self:DrawMeterBar(panel, row, maxTotal, 146, y, barWidth)

            local raids = LV.Widgets:Text(panel, tostring(self:MeterAttendancePercent(row, raidCount)) .. "%")
            raids:SetPoint("TOPLEFT", 590, y + 1)
            raids:SetWidth(62)
            raids:SetWordWrap(false)

            y = y - 30
        end
    end
end

function LV.UI:DrawProgressBar(parent, current, total, x, y, width)
    current = tonumber(current) or 0
    total = tonumber(total) or 1
    if total <= 0 then
        total = 1
    end

    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", x, y)
    bar:SetSize(width or 420, 18)
    LV.Widgets:ApplyBackdrop(bar, meterColors.empty, LV.Widgets.colors.border)

    local fillWidth = math.floor(((width or 420) * math.min(current, total) / total) + 0.5)
    if fillWidth > 0 then
        local fill = bar:CreateTexture(nil, "ARTWORK")
        fill:SetColorTexture(unpack(LV.Widgets.colors.active))
        fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
        fill:SetSize(math.max(1, fillWidth - 2), 16)
    end

    local label = LV.Widgets:Text(bar, tostring(current) .. "/" .. tostring(total))
    label:SetPoint("CENTER")
    label:SetTextColor(unpack(LV.Widgets.colors.white))
end

function LV.UI:LootItemDisplay(guildKey, row)
    local itemKey = LV.Store:DictionaryValue(guildKey, "i", row and row.item)
    local itemID = tonumber(row and row.itemID) or LV.Util:ItemID(itemKey) or 0
    local itemName, itemLink, itemQuality, itemIcon

    if type(GetItemInfo) == "function" then
        local lookup = itemKey ~= "" and itemKey or itemID
        local result = { pcall(GetItemInfo, lookup) }
        if result[1] then
            itemName = result[2]
            itemLink = result[3]
            itemQuality = result[4]
            itemIcon = result[10]
        end
    end

    if not itemName and C_Item and C_Item.GetItemInfo then
        local lookup = itemKey ~= "" and itemKey or itemID
        local result = { pcall(C_Item.GetItemInfo, lookup) }
        if result[1] then
            itemName = result[2]
            itemLink = result[3]
            itemQuality = result[4]
            itemIcon = result[10]
        end
    end

    if not itemIcon and type(GetItemIcon) == "function" then
        local lookup = itemLink or itemKey ~= "" and itemKey or itemID
        local result = { pcall(GetItemIcon, lookup) }
        if result[1] then
            itemIcon = result[2]
        end
    end
    if not itemIcon and C_Item and C_Item.GetItemIconByID and itemID > 0 then
        local result = { pcall(C_Item.GetItemIconByID, itemID) }
        if result[1] then
            itemIcon = result[2]
        end
    end

    if not itemName and C_Item and C_Item.RequestLoadItemDataByID and itemID > 0 then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end

    local displayName = itemName or tostring(itemKey or ""):match("%[(.-)%]") or (itemID > 0 and ("Item " .. tostring(itemID)) or tostring(itemKey or "item"))
    local tooltipLink = itemLink or (itemKey ~= "" and itemKey or (itemID > 0 and ("item:" .. tostring(itemID)) or nil))
    local color = ITEM_QUALITY_COLORS and itemQuality and ITEM_QUALITY_COLORS[itemQuality]
    return displayName, tooltipLink, color, itemIcon
end

function LV.UI:LootMethodLabel(value)
    local labels = {
        need = "Need",
        offspec = "OSpec",
        transmog = "Tmog",
        greed = "Greed",
        pass = "Pass",
        noroll = "NoRoll",
    }

    value = tostring(value or "")
    if value == "" then
        return ""
    end
    if value:match("^%d+$") then
        return ""
    end

    return labels[value] or value
end

function LV.UI:LootBreakdownCount(row)
    local count = 0
    for _, entry in ipairs((row and row.rb) or {}) do
        if type(entry) == "table" and entry.p then
            count = count + 1
        end
    end
    return count
end

function LV.UI:LootWinnerRollInfo(row)
    if type(row) ~= "table" or type(row.rb) ~= "table" then
        return nil, nil
    end

    local function infoFrom(entry)
        if type(entry) ~= "table" then
            return nil, nil, false
        end

        local roll = tostring(entry.r or "")
        if roll:match("^%d+$") then
            roll = ""
        end
        local raw = tostring(entry.raw or "")
        if roll ~= "" or raw ~= "" then
            return roll ~= "" and roll or nil, raw ~= "" and raw or nil, true
        end
        return nil, nil, false
    end

    for _, entry in ipairs(row.rb) do
        if type(entry) == "table" and entry.w then
            local roll, raw, found = infoFrom(entry)
            if found then
                return roll, raw
            end
        end
    end

    for _, entry in ipairs(row.rb) do
        if type(entry) == "table" and row.p and entry.p == row.p then
            local roll, raw, found = infoFrom(entry)
            if found then
                return roll, raw
            end
        end
    end

    return nil, nil
end

function LV.UI:LootWinnerRoll(row)
    local roll = self:LootWinnerRollInfo(row)
    return roll
end

function LV.UI:LootMethodDisplay(row)
    local winnerRoll = self:LootWinnerRollInfo(row)
    local label = self:LootMethodLabel(winnerRoll or (row and row.r))
    if label == "" and row and row.tr then
        label = "Traded"
    end

    return label
end

function LV.UI:LootDifficultyAbbrev(guildKey, row)
    local difficulty = self:LootDifficultyDisplay(guildKey, row)
    local value = tostring(difficulty or ""):lower()
    local difficultyID = tonumber(row and row.did) or 0

    if value:find("mythic", 1, true) or difficultyID == 16 or difficultyID == 23 then
        return "M"
    elseif value:find("heroic", 1, true) or difficultyID == 15 then
        return "H"
    elseif value:find("raid finder", 1, true) or value:find("lfr", 1, true) or difficultyID == 17 then
        return "L"
    elseif value:find("normal", 1, true) or difficultyID == 14 then
        return "N"
    end

    return ""
end

function LV.UI:LootBossDisplay(guildKey, row)
    if type(row) ~= "table" then
        return ""
    end

    local boss = LV.Store:DictionaryValue(guildKey, "s", row.boss)
    if boss ~= "" then
        return boss
    end

    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and record.r and row.sid and record.r[row.sid]
    if type(raid) == "table" then
        for _, kill in ipairs(raid.kills or {}) do
            if tonumber(kill.e) == tonumber(row.e) then
                boss = LV.Store:DictionaryValue(guildKey, "s", kill.b)
                if boss ~= "" then
                    return boss
                end
            end
        end
    end

    return ""
end

function LV.UI:LootBossDifficultyDisplay(guildKey, row)
    local boss = self:LootBossDisplay(guildKey, row)
    local difficulty = self:LootDifficultyAbbrev(guildKey, row)
    if boss ~= "" and difficulty ~= "" then
        return "(" .. difficulty .. ") " .. boss
    elseif boss ~= "" then
        return boss
    elseif difficulty ~= "" then
        return "(" .. difficulty .. ")"
    end
    return ""
end

function LV.UI:LootInstanceDisplay(guildKey, row)
    local instance = LV.Store:DictionaryValue(guildKey, "s", row and row.inst)
    if instance ~= "" then
        return instance
    end
    return ""
end

function LV.UI:LootDifficultyDisplay(guildKey, row)
    local difficulty = LV.Store:DictionaryValue(guildKey, "s", row and row.diff)
    if difficulty ~= "" then
        return difficulty
    end
    local difficultyID = tonumber(row and row.did) or 0
    return difficultyID > 0 and tostring(difficultyID) or ""
end

function LV.UI:LootSearchText(guildKey, row)
    local itemName = self:LootItemDisplay(guildKey, row)
    local player = LV.Store:DictionaryValue(guildKey, "n", row and row.p)
    local itemKey = LV.Store:DictionaryValue(guildKey, "i", row and row.item)
    local parts = {
        date("%m/%d %H:%M", row and row.ts or 0),
        player,
        LV.Util:ShortName(player),
        itemName,
        itemKey,
        self:LootBossDifficultyDisplay(guildKey, row),
        self:LootInstanceDisplay(guildKey, row),
        self:LootDifficultyDisplay(guildKey, row),
        self:LootMethodDisplay(row),
    }
    return table.concat(parts, " "):lower()
end

function LV.UI:FilteredHistoryRows(guildKey)
    local record = LV.Store:GuildRecord(guildKey)
    local query = LV.Util:Trim(self.historySearch or ""):lower()
    local rows = {}

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        if type(row) == "table" then
            local excluded = LV.Loot and LV.Loot.IsLootItemExcluded and LV.Loot:IsLootItemExcluded(guildKey, row)
            if not excluded and (query == "" or self:LootSearchText(guildKey, row):find(query, 1, true)) then
                rows[#rows + 1] = row
            end
        end
    end

    return rows
end

function LV.UI:ScrollHistoryRows(delta)
    if self.currentTab ~= "history" then
        return
    end

    local total = tonumber(self.historyRowsCount) or 0
    if total <= HISTORY_PAGE_SIZE then
        return
    end

    local step = IsShiftKeyDown and IsShiftKeyDown() and HISTORY_PAGE_SIZE or 3
    local maxOffset = math.max(0, total - HISTORY_PAGE_SIZE)
    local current = tonumber(self.historyOffset) or 0
    local nextOffset = current
    if tonumber(delta) and delta < 0 then
        nextOffset = math.min(maxOffset, current + step)
    else
        nextOffset = math.max(0, current - step)
    end

    if nextOffset ~= current then
        self.historyOffset = nextOffset
        self:Refresh()
    end
end

function LV.UI:AttachHistoryScroll(frame)
    if not frame or not frame.EnableMouseWheel then
        return frame
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        LV.UI:ScrollHistoryRows(delta)
    end)
    return frame
end

function LV.UI:CreateHistoryNameButton(parent, guildKey, nameID, x, y, width)
    local fullName = LV.Store:DictionaryValue(guildKey, "n", nameID)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", x, y + 1)
    button:SetSize(width, 18)
    button.text = LV.Widgets:Text(button, LV.Util:ShortName(fullName))
    button.text:SetPoint("LEFT", 0, 0)
    button.text:SetWidth(width)
    button.text:SetWordWrap(false)
    self:SetNameClassColor(button.text, guildKey, nameID)
    button:SetScript("OnEnter", function()
        button.text:SetTextColor(unpack(LV.Widgets.colors.yellow))
    end)
    button:SetScript("OnLeave", function()
        self:SetNameClassColor(button.text, guildKey, nameID)
    end)
    button:SetScript("OnClick", function()
        self:ShowPlayerDetailForName(guildKey, nameID)
    end)
    self:AttachHistoryScroll(button)
    return button
end

function LV.UI:CreateHistoryExcludeButton(parent, guildKey, row, y)
    local button = LV.Widgets:Button(parent, "X", 22, 18, function()
        if LV.Loot and LV.Loot.ExcludeLootItem then
            local itemName = self:LootItemDisplay(guildKey, row)
            LV.Loot:ExcludeLootItem(guildKey, row, itemName)
        end
    end)
    button:SetPoint("TOPRIGHT", -14, y + 1)
    button.text:SetTextColor(unpack(LV.Widgets.colors.muted))
    LV.Widgets:SetTooltip(button, "Exclude this item from history and future rebuilds.")
    self:AttachHistoryScroll(button)
    return button
end

function LV.UI:AddLootBreakdownTooltip(guildKey, row)
    if type(row) ~= "table" or type(row.rb) ~= "table" or #row.rb == 0 then
        return
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("LootViewer Rolls", unpack(LV.Widgets.colors.yellow))

    local shown = 0
    for _, entry in ipairs(row.rb) do
        if type(entry) == "table" and entry.p then
            shown = shown + 1
            if shown > 12 then
                GameTooltip:AddLine("+" .. tostring(#row.rb - 12) .. " more", unpack(LV.Widgets.colors.muted))
                break
            end

            local name = LV.Util:ShortName(LV.Store:DictionaryValue(guildKey, "n", entry.p))
            local method = self:LootMethodLabel(entry.r)
            local raw = tostring(entry.raw or "")
            local detail = method
            if raw ~= "" then
                detail = detail ~= "" and (detail .. " " .. raw) or raw
            end
            if entry.w then
                detail = detail ~= "" and ("Winner - " .. detail) or "Winner"
            end

            local color = self:ClassColorForName(guildKey, entry.p)
            GameTooltip:AddDoubleLine(name, detail, color[1], color[2], color[3], 0.72, 0.74, 0.80)
        end
    end
end

function LV.UI:CreateHistoryItemButton(parent, guildKey, row, x, y, width)
    local itemName, itemLink, qualityColor, itemIcon = self:LootItemDisplay(guildKey, row)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", x, y + 1)
    button:SetSize(width, 18)

    if itemIcon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("LEFT", 0, 0)
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
        if itemLink or self:LootBreakdownCount(row) > 0 then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if itemLink then
                GameTooltip:SetHyperlink(itemLink)
            else
                GameTooltip:SetText(itemName)
            end
            self:AddLootBreakdownTooltip(guildKey, row)
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
    self:AttachHistoryScroll(button)
    return button
end

function LV.UI:RenderDataSync()
    local guildInfo = self:CurrentGuildOrMessage()
    if not guildInfo then
        return
    end

    local title = LV.Widgets:Text(self.content, "Data Sync", "large")
    title:SetPoint("TOPLEFT", 22, -20)

    local guild = LV.Widgets:Text(self.content, guildInfo.name .. " - " .. guildInfo.realm)
    guild:SetTextColor(unpack(LV.Widgets.colors.muted))
    guild:SetPoint("LEFT", title, "RIGHT", 18, -2)

    local panel = LV.Widgets:Section(self.content, "Send Current Guild Data", 216)
    panel:SetPoint("TOPLEFT", 22, -62)
    panel:SetPoint("RIGHT", -22, 0)

    local targetLabel = LV.Widgets:Label(panel, "Player")
    targetLabel:SetPoint("TOPLEFT", 24, -52)

    local target = LV.Widgets:EditBox(panel, 208, 26, function(value)
        self.syncTarget = value
    end)
    target:SetText(self.syncTarget or "")
    target:SetPoint("LEFT", targetLabel, "RIGHT", 16, 0)

    local send = LV.Widgets:Button(panel, "Invite Sync", 96, 26, function()
        self.syncTarget = target:GetText()
        LV.DataSync:StartSync(self.syncTarget)
    end)
    send:SetPoint("LEFT", target, "RIGHT", 12, 0)

    local hint = LV.Widgets:Text(panel, "Sends guild config plus attendance, loot, and trades from the last 2 months after they accept.")
    hint:SetTextColor(unpack(LV.Widgets.colors.muted))
    hint:SetPoint("TOPLEFT", 24, -88)

    local current, total, status = LV.DataSync:Progress()
    local statusText = LV.Widgets:Text(panel, status)
    statusText:SetPoint("TOPLEFT", 24, -124)
    statusText:SetWidth(620)
    statusText:SetWordWrap(false)

    self:DrawProgressBar(panel, current, total, 24, -154, 620)

    local inbound = LV.DataSync.inbound
    local outbound = LV.DataSync.outbound
    local detail = LV.Widgets:Section(self.content, "Sync Activity", 164)
    detail:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -18)
    detail:SetPoint("RIGHT", -22, 0)

    local y = -48
    if outbound then
        local text = LV.Widgets:Text(detail, "Sending to " .. tostring(outbound.target or "") .. " - " .. tostring(outbound.state or ""))
        text:SetPoint("TOPLEFT", 24, y)
        y = y - 28
        local counts = LV.Widgets:Text(detail, LV.DataSync:FormatCounts(outbound.counts))
        counts:SetTextColor(unpack(LV.Widgets.colors.muted))
        counts:SetPoint("TOPLEFT", 24, y)
        y = y - 28
    end
    if inbound then
        local text = LV.Widgets:Text(detail, "Receiving from " .. tostring(inbound.sender or "") .. " - " .. tostring(inbound.state or ""))
        text:SetPoint("TOPLEFT", 24, y)
        y = y - 28
        if inbound.imported then
            local imported = LV.Widgets:Text(detail, "Imported " .. LV.DataSync:FormatCounts(inbound.imported))
            imported:SetTextColor(unpack(LV.Widgets.colors.muted))
            imported:SetPoint("TOPLEFT", 24, y)
            y = y - 28
        end
    end
    if not inbound and not outbound then
        local empty = LV.Widgets:Text(detail, "No active sync.")
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, y)
    end
end

StaticPopupDialogs[LV.Constants.MAIN_PROMPT] = {
    text = "Set main for %s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self, data)
        data = data or self.data
        local editBox = popupEditBox(self)
        if editBox then
            editBox:SetText(data and LV.Util:ShortName(data.main or "") or "")
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self, data)
        data = data or self.data
        if data and data.guildKey and data.name then
            local editBox = popupEditBox(self)
            LV.Guild:SetRosterOverride(data.guildKey, data.name, "alt", editBox and editBox:GetText() or "")
            LV.UI:Refresh()
        end
    end,
}

StaticPopupDialogs[LV.Constants.TEAM_PROMPT] = {
    text = "New raid team name",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local editBox = popupEditBox(self)
        if editBox then
            editBox:SetText("")
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self, data)
        data = data or self.data
        if data and data.guildKey then
            local editBox = popupEditBox(self)
            LV.Store:AddRaidTeam(data.guildKey, editBox and editBox:GetText() or "")
            LV.UI:Refresh()
        end
    end,
}

StaticPopupDialogs[LV.Constants.DELETE_RAID_PROMPT] = {
    text = "Delete raid attendance for %s?\nLoot and trade history will be kept.",
    button1 = "Delete",
    button2 = CANCEL,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, data)
        if data and data.guildKey and data.raidID then
            LV.UI:DeleteRaid(data.guildKey, data.raidID)
        end
    end,
}

function LV.UI:RenderHistory()
    local guildInfo = self:CurrentGuildOrMessage()
    if not guildInfo then
        return
    end

    local record = LV.Store:GuildRecord(guildInfo.key)
    if LV.Loot and LV.Loot.ScheduleLootHistoryScan then
        LV.Loot:ScheduleLootHistoryScan()
    end
    local rows = self:FilteredHistoryRows(guildInfo.key)
    self.historyRowsCount = #rows
    self.historyOffset = tonumber(self.historyOffset) or 0
    if self.historyOffset >= #rows then
        self.historyOffset = math.max(0, #rows - HISTORY_PAGE_SIZE)
    end
    local excludedItems = LV.Loot and LV.Loot.ExcludedLootItems and LV.Loot:ExcludedLootItems(guildInfo.key) or {}

    local title = LV.Widgets:Text(self.content, "History", "large")
    title:SetPoint("TOPLEFT", 22, -20)

    local searchText = LV.Util:Trim(self.historySearch or "")
    local pageLabel = (searchText ~= "" or #rows ~= #record.l)
        and (tostring(#rows) .. " of " .. tostring(#record.l) .. " loot event(s)")
        or (tostring(#record.l) .. " loot event(s)")
    local page = LV.Widgets:Text(self.content, pageLabel)
    page:SetTextColor(unpack(LV.Widgets.colors.muted))
    page:SetPoint("LEFT", title, "RIGHT", 18, -2)

    local searchLabel = LV.Widgets:Label(self.content, "Search")
    searchLabel:SetPoint("TOPLEFT", 22, -54)
    local function commitSearch(box)
        local value = LV.Util:Trim(box and box:GetText() or "")
        if value ~= LV.Util:Trim(self.historySearch or "") then
            self.historySearch = value
            self.historyOffset = 0
            self:Refresh()
        end
    end
    local search = LV.Widgets:EditBox(self.content, 240, 24)
    search:SetText(searchText)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 12, 0)
    search:SetScript("OnEnterPressed", function(box)
        commitSearch(box)
        box:ClearFocus()
    end)
    search:SetScript("OnEditFocusLost", function(box)
        commitSearch(box)
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local clear = LV.Widgets:Button(self.content, "Clear", 58, 24, function()
        self.historySearch = ""
        self.historyOffset = 0
        self:Refresh()
    end)
    clear:SetPoint("LEFT", search, "RIGHT", 8, 0)

    local historyY = -86
    if #excludedItems > 0 then
        local excluded = LV.Widgets:Section(self.content, "Excluded Items", 58)
        excluded:SetPoint("TOPLEFT", 22, historyY)
        excluded:SetPoint("RIGHT", -22, 0)
        self:RenderExcludedLootItems(excluded, guildInfo.key, excludedItems)
        historyY = historyY - 76
    end

    local history = LV.Widgets:Section(self.content, "Recent Loot", 398)
    history:SetPoint("TOPLEFT", 22, historyY)
    history:SetPoint("RIGHT", -22, 0)
    self:AttachHistoryScroll(history)
    self:RenderLootRows(history, guildInfo.key, rows, self.historyOffset)

    local trades = LV.Widgets:Section(self.content, "Recent Trades", 104)
    trades:SetPoint("TOPLEFT", history, "BOTTOMLEFT", 0, -18)
    trades:SetPoint("RIGHT", -22, 0)
    self:RenderTradeRows(trades, guildInfo.key)
end

function LV.UI:CreateHistoryColumnHeader(parent, text, x, width, justify)
    local label = LV.Widgets:Label(parent, text)
    label:SetPoint("TOPLEFT", x, -36)
    label:SetWidth(width)
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

function LV.UI:RenderExcludedLootItems(parent, guildKey, items)
    local x = 18
    local y = -34
    local maxShown = 4

    for index, item in ipairs(items or {}) do
        if index > maxShown then
            local more = LV.Widgets:Text(parent, "+" .. tostring(#items - maxShown) .. " more")
            more:SetTextColor(unpack(LV.Widgets.colors.muted))
            more:SetPoint("TOPLEFT", x, y)
            return
        end

        local name = LV.Widgets:Text(parent, item.name or item.key or "item")
        name:SetPoint("TOPLEFT", x, y + 1)
        name:SetWidth(174)
        name:SetWordWrap(false)
        name:SetTextColor(unpack(item.default and LV.Widgets.colors.muted or LV.Widgets.colors.white))

        local undo = LV.Widgets:Button(parent, "Undo", 48, 18, function()
            if LV.Loot and LV.Loot.UnexcludeLootItem then
                LV.Loot:UnexcludeLootItem(guildKey, item.key)
            end
        end)
        undo:SetPoint("LEFT", name, "RIGHT", 8, 0)
        LV.Widgets:SetTooltip(undo, "Allow this item again. Rebuild loot to restore matching rows.")

        x = x + 248
    end
end

function LV.UI:CreateHistoryRowBackground(parent, y, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetPoint("TOPLEFT", 10, y + 3)
    row:SetPoint("RIGHT", -10, 0)
    row:SetHeight(20)
    local color = index % 2 == 0 and { 0.06, 0.09, 0.14, 0.72 } or { 0.05, 0.07, 0.11, 0.45 }
    LV.Widgets:ApplyBackdrop(row, color, { 0, 0, 0, 0 })
    self:AttachHistoryScroll(row)
    return row
end

function LV.UI:RenderLootRows(parent, guildKey, rows, offset)
    rows = rows or {}
    local y = -60
    offset = tonumber(offset) or 0

    self:CreateHistoryColumnHeader(parent, "Date", 14, 72)
    self:CreateHistoryColumnHeader(parent, "Player", 92, 102)
    self:CreateHistoryColumnHeader(parent, "Loot", 202, 252)
    self:CreateHistoryColumnHeader(parent, "Boss", 462, 100)
    self:CreateHistoryColumnHeader(parent, "Method", 570, 104, "RIGHT")

    if #rows == 0 then
        local message = LV.Util:Trim(self.historySearch or "") ~= "" and "No loot matches your search." or "No loot recorded yet."
        local empty = LV.Widgets:Text(parent, message)
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, y)
        return
    end

    for count = 1, math.min(#rows - offset, HISTORY_PAGE_SIZE) do
        local row = rows[offset + count]
        self:CreateHistoryRowBackground(parent, y, count)
        local dateText = LV.Widgets:Text(parent, date("%m/%d %H:%M", row.ts or 0))
        dateText:SetPoint("TOPLEFT", 14, y)
        dateText:SetWidth(74)
        dateText:SetWordWrap(false)

        self:CreateHistoryNameButton(parent, guildKey, row.p, 92, y, 102)
        self:CreateHistoryItemButton(parent, guildKey, row, 202, y, 252)

        local bossText = LV.Widgets:Text(parent, self:LootBossDifficultyDisplay(guildKey, row))
        bossText:SetPoint("TOPLEFT", 462, y)
        bossText:SetWidth(100)
        bossText:SetWordWrap(false)
        bossText:SetTextColor(unpack(LV.Widgets.colors.muted))

        local methodText = LV.Widgets:Text(parent, self:LootMethodDisplay(row))
        methodText:SetPoint("TOPLEFT", 570, y)
        methodText:SetWidth(104)
        methodText:SetJustifyH("RIGHT")
        methodText:SetWordWrap(false)
        methodText:SetTextColor(unpack(LV.Widgets.colors.muted))
        self:CreateHistoryExcludeButton(parent, guildKey, row, y)
        y = y - 22
    end
end

function LV.UI:RenderTradeRows(parent, guildKey)
    local record = LV.Store:GuildRecord(guildKey)
    local y = -48
    if #record.t == 0 then
        local empty = LV.Widgets:Text(parent, "No trades recorded yet.")
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, y)
        return
    end

    for count = 1, math.min(#record.t, 2) do
        local row = record.t[#record.t - count + 1]
        local dateText = LV.Widgets:Text(parent, date("%m/%d %H:%M", row.ts or 0))
        dateText:SetPoint("TOPLEFT", 24, y)
        dateText:SetWidth(76)
        dateText:SetWordWrap(false)
        self:CreateHistoryNameButton(parent, guildKey, row.f, 102, y, 112)
        local arrow = LV.Widgets:Text(parent, "->")
        arrow:SetPoint("TOPLEFT", 218, y)
        arrow:SetTextColor(unpack(LV.Widgets.colors.muted))
        self:CreateHistoryNameButton(parent, guildKey, row.to, 242, y, 112)
        self:CreateHistoryItemButton(parent, guildKey, row, 362, y, 260)
        y = y - 30
    end
end

LV:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if LV.UI and LV.UI.frame and LV.UI.frame:IsShown() and LV.UI.currentTab == "history" then
        LV.UI:Refresh()
    end
end)
