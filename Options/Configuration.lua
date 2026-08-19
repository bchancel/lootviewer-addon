local LV = _G.LootViewer
if not LV or not LV.UI then
    return
end

local UI = LV.UI

local authorityModes = {
    { value = "assist", label = "Lead / Assist" },
    { value = "lead", label = "Raid Lead" },
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

local timezoneValues = LV.Util:TimezoneValues()

local graceMinuteValues = {
    { value = 0, label = "0 min" },
    { value = 5, label = "5 min" },
    { value = 10, label = "10 min" },
    { value = 15, label = "15 min" },
    { value = 20, label = "20 min" },
}

local promptTimeoutValues = {
    { value = 5, label = "5 sec" },
    { value = 10, label = "10 sec" },
    { value = 20, label = "20 sec" },
    { value = 30, label = "30 sec" },
    { value = 45, label = "45 sec" },
    { value = 60, label = "60 sec" },
}

local function toClock12(hour)
    hour = tonumber(hour) or 0
    local period = hour >= 12 and "PM" or "AM"
    local clock = hour % 12
    return clock == 0 and 12 or clock, period
end

local function pickerAlpha()
    if ColorPickerFrame and ColorPickerFrame.GetColorAlpha then
        return tonumber(ColorPickerFrame:GetColorAlpha()) or 1
    end
    if OpacitySliderFrame and OpacitySliderFrame.GetValue then
        return 1 - (tonumber(OpacitySliderFrame:GetValue()) or 0)
    end
    return 1
end

local MINUTES_PER_DAY = 24 * 60
local SCHEDULE_SNAP = 30

local function snapScheduleMinute(value, maximum)
    value = math.floor(((tonumber(value) or 0) + (SCHEDULE_SNAP / 2)) / SCHEDULE_SNAP) * SCHEDULE_SNAP
    return math.max(0, math.min(maximum or MINUTES_PER_DAY, value))
end

local function scheduleStartMinute(slot)
    return snapScheduleMinute(((tonumber(slot.h) or 20) * 60) + (tonumber(slot.m) or 0), MINUTES_PER_DAY - SCHEDULE_SNAP)
end

local function scheduleDuration(slot)
    return math.max(SCHEDULE_SNAP, snapScheduleMinute(slot.d or 180, MINUTES_PER_DAY))
end

local function scheduleEndMinute(slot)
    local startMinute = scheduleStartMinute(slot)
    local absoluteEnd = startMinute + scheduleDuration(slot)
    if absoluteEnd <= MINUTES_PER_DAY then
        return absoluteEnd
    end
    return absoluteEnd % MINUTES_PER_DAY
end

local function formatScheduleTime(value, clock24)
    value = (tonumber(value) or 0) % MINUTES_PER_DAY
    local hour = math.floor(value / 60)
    local minute = value % 60
    if clock24 then
        return string.format("%02d:%02d", hour, minute)
    end
    local clockHour, period = toClock12(hour)
    return string.format("%d:%02d %s", clockHour, minute, period)
end

local function setScheduleStart(slot, value)
    local endMinute = scheduleEndMinute(slot)
    local startMinute = snapScheduleMinute(value, MINUTES_PER_DAY - SCHEDULE_SNAP)
    local duration = endMinute - startMinute
    if duration < SCHEDULE_SNAP then
        duration = duration + MINUTES_PER_DAY
    end
    slot.h = math.floor(startMinute / 60)
    slot.m = startMinute % 60
    slot.d = math.max(SCHEDULE_SNAP, math.min(MINUTES_PER_DAY, duration))
end

local function setScheduleEnd(slot, value)
    local startMinute = scheduleStartMinute(slot)
    local endMinute = snapScheduleMinute(value, MINUTES_PER_DAY)
    local duration = endMinute - startMinute
    if duration <= 0 then
        duration = duration + MINUTES_PER_DAY
    end
    if duration >= MINUTES_PER_DAY then
        duration = SCHEDULE_SNAP
    end
    slot.d = math.max(SCHEDULE_SNAP, math.min(MINUTES_PER_DAY, duration))
end

local function createScheduleRange(parent, slot, clock24, width)
    width = tonumber(width) or 490
    local range = CreateFrame("Frame", nil, parent)
    range:SetSize(width, 58)

    local startText = LV.Widgets:Label(range, "")
    startText:SetPoint("TOPLEFT", 0, 0)
    startText:SetTextColor(unpack(LV.Widgets.colors.accentBright))
    local endText = LV.Widgets:Label(range, "")
    endText:SetPoint("TOPRIGHT", 0, 0)
    endText:SetJustifyH("RIGHT")
    endText:SetTextColor(unpack(LV.Widgets.colors.navigation))

    local track = CreateFrame("Button", nil, range)
    track:SetPoint("TOPLEFT", 0, -20)
    track:SetSize(width, 20)
    track:EnableMouse(true)
    track.line = track:CreateTexture(nil, "ARTWORK")
    track.line:SetTexture("Interface\\Buttons\\WHITE8x8")
    track.line:SetPoint("LEFT", 0, 0)
    track.line:SetPoint("RIGHT", 0, 0)
    track.line:SetHeight(5)
    track.line:SetVertexColor(unpack(LV.Widgets.colors.borderStrong))
    track.fillA = track:CreateTexture(nil, "ARTWORK", nil, 1)
    track.fillA:SetTexture("Interface\\Buttons\\WHITE8x8")
    track.fillA:SetHeight(5)
    track.fillA:SetVertexColor(unpack(LV.Widgets.colors.accent))
    track.fillB = track:CreateTexture(nil, "ARTWORK", nil, 1)
    track.fillB:SetTexture("Interface\\Buttons\\WHITE8x8")
    track.fillB:SetHeight(5)
    track.fillB:SetVertexColor(unpack(LV.Widgets.colors.accent))

    for step = 0, 4 do
        local fraction = step / 4
        local tick = track:CreateTexture(nil, "OVERLAY")
        tick:SetTexture("Interface\\Buttons\\WHITE8x8")
        tick:SetSize(1, (step == 0 or step == 4) and 8 or 6)
        tick:SetPoint("CENTER", track, "LEFT", width * fraction, 0)
        tick:SetVertexColor(unpack(LV.Widgets.colors.textMuted))
        local label = range:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOP", track, "BOTTOMLEFT", width * fraction, -1)
        label:SetText(formatScheduleTime(step * 360, clock24))
        label:SetTextColor(unpack(LV.Widgets.colors.textMuted))
    end

    local function handle(color)
        local button = CreateFrame("Button", nil, range, "BackdropTemplate")
        button:SetSize(12, 22)
        LV.Widgets:ApplyBackdrop(button, color, LV.Widgets.colors.text)
        button:SetFrameLevel(track:GetFrameLevel() + 3)
        return button
    end
    local startHandle = handle(LV.Widgets.colors.accentBright)
    local endHandle = handle(LV.Widgets.colors.navigation)
    local dragging = nil

    local function update()
        local startMinute = scheduleStartMinute(slot)
        local endMinute = scheduleEndMinute(slot)
        local startX = width * (startMinute / MINUTES_PER_DAY)
        local endX = width * (endMinute / MINUTES_PER_DAY)
        startHandle:ClearAllPoints()
        startHandle:SetPoint("CENTER", track, "LEFT", startX, 0)
        endHandle:ClearAllPoints()
        endHandle:SetPoint("CENTER", track, "LEFT", endX, 0)
        startText:SetText("START  " .. formatScheduleTime(startMinute, clock24))
        endText:SetText("END  " .. formatScheduleTime(endMinute, clock24))

        track.fillA:ClearAllPoints()
        track.fillB:ClearAllPoints()
        if endX >= startX then
            track.fillA:SetPoint("LEFT", track, "LEFT", startX, 0)
            track.fillA:SetPoint("RIGHT", track, "LEFT", endX, 0)
            track.fillA:Show()
            track.fillB:Hide()
        else
            track.fillA:SetPoint("LEFT", track, "LEFT", startX, 0)
            track.fillA:SetPoint("RIGHT", track, "RIGHT", 0, 0)
            track.fillB:SetPoint("LEFT", track, "LEFT", 0, 0)
            track.fillB:SetPoint("RIGHT", track, "LEFT", endX, 0)
            track.fillA:Show()
            track.fillB:Show()
        end
    end

    local function cursorMinute(maximum)
        local cursorX = GetCursorPosition()
        local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        cursorX = cursorX / scale
        local left = track:GetLeft() or 0
        return snapScheduleMinute(((cursorX - left) / width) * MINUTES_PER_DAY, maximum)
    end

    local function stopDrag()
        dragging = nil
        range:SetScript("OnUpdate", nil)
    end

    local function updateDrag()
        if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
            stopDrag()
            return
        end
        if dragging == "start" then
            setScheduleStart(slot, cursorMinute(MINUTES_PER_DAY - SCHEDULE_SNAP))
        elseif dragging == "end" then
            setScheduleEnd(slot, cursorMinute(MINUTES_PER_DAY))
        end
        update()
    end

    local function beginDrag(kind)
        dragging = kind
        updateDrag()
        range:SetScript("OnUpdate", updateDrag)
    end

    startHandle:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then beginDrag("start") end end)
    startHandle:SetScript("OnMouseUp", stopDrag)
    endHandle:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then beginDrag("end") end end)
    endHandle:SetScript("OnMouseUp", stopDrag)
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local clicked = cursorMinute(MINUTES_PER_DAY)
        local startDistance = math.abs(clicked - scheduleStartMinute(slot))
        local endDistance = math.abs(clicked - scheduleEndMinute(slot))
        beginDrag(startDistance <= endDistance and "start" or "end")
    end)
    track:SetScript("OnMouseUp", stopDrag)
    track:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Raid time range")
        GameTooltip:AddLine("Drag Start or End. Times snap to 30-minute increments.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    track:SetScript("OnLeave", function() GameTooltip:Hide() end)
    range:SetScript("OnHide", stopDrag)
    update()
    return range
end

local function guildRankMaximum()
    if LV.Guild and LV.Guild.RankMaximum then
        return LV.Guild:RankMaximum()
    end
    return 9
end

local function createRankRange(parent, cfg, width, locked)
    width = tonumber(width) or 168
    local maximum = guildRankMaximum()
    cfg.rankMin = math.max(0, math.min(maximum, tonumber(cfg.rankMin) or 0))
    cfg.rankMax = math.max(cfg.rankMin, math.min(maximum, tonumber(cfg.rankMax) or 3))

    local range = CreateFrame("Frame", nil, parent)
    range:SetSize(width, 38)
    local lowText = LV.Widgets:Label(range, "")
    lowText:SetPoint("TOPLEFT", 0, 0)
    lowText:SetTextColor(unpack(LV.Widgets.colors.accentBright))
    local highText = LV.Widgets:Label(range, "")
    highText:SetPoint("TOPRIGHT", 0, 0)
    highText:SetJustifyH("RIGHT")
    highText:SetTextColor(unpack(LV.Widgets.colors.navigation))

    local track = CreateFrame("Button", nil, range)
    track:SetPoint("TOPLEFT", 0, -16)
    track:SetSize(width, 18)
    track:EnableMouse(true)
    track.line = track:CreateTexture(nil, "ARTWORK")
    track.line:SetTexture("Interface\\Buttons\\WHITE8x8")
    track.line:SetPoint("LEFT", 0, 0)
    track.line:SetPoint("RIGHT", 0, 0)
    track.line:SetHeight(4)
    track.line:SetVertexColor(unpack(LV.Widgets.colors.borderStrong))
    track.fill = track:CreateTexture(nil, "ARTWORK", nil, 1)
    track.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    track.fill:SetHeight(4)
    track.fill:SetVertexColor(unpack(LV.Widgets.colors.accent))

    for rank = 0, maximum do
        local tick = track:CreateTexture(nil, "OVERLAY")
        tick:SetTexture("Interface\\Buttons\\WHITE8x8")
        tick:SetSize(1, (rank == 0 or rank == maximum) and 7 or 5)
        tick:SetPoint("CENTER", track, "LEFT", width * (rank / maximum), 0)
        tick:SetVertexColor(unpack(LV.Widgets.colors.textMuted))
    end

    local function handle(color)
        local button = CreateFrame("Button", nil, range, "BackdropTemplate")
        button:SetSize(10, 20)
        LV.Widgets:ApplyBackdrop(button, color, LV.Widgets.colors.text)
        button:SetFrameLevel(track:GetFrameLevel() + 3)
        return button
    end
    local lowHandle = handle(LV.Widgets.colors.accentBright)
    local highHandle = handle(LV.Widgets.colors.navigation)
    local dragging = nil

    local function update()
        local lowX = width * (cfg.rankMin / maximum)
        local highX = width * (cfg.rankMax / maximum)
        lowHandle:ClearAllPoints()
        lowHandle:SetPoint("CENTER", track, "LEFT", lowX, 0)
        highHandle:ClearAllPoints()
        highHandle:SetPoint("CENTER", track, "LEFT", highX, 0)
        track.fill:ClearAllPoints()
        track.fill:SetPoint("LEFT", track, "LEFT", lowX, 0)
        track.fill:SetPoint("RIGHT", track, "LEFT", highX, 0)
        lowText:SetText("RANK " .. tostring(cfg.rankMin))
        highText:SetText("RANK " .. tostring(cfg.rankMax))
    end

    local function cursorRank()
        local cursorX = GetCursorPosition()
        local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        cursorX = cursorX / scale
        local fraction = math.max(0, math.min(1, (cursorX - (track:GetLeft() or 0)) / width))
        return math.floor((fraction * maximum) + 0.5)
    end

    local function stopDrag()
        dragging = nil
        range:SetScript("OnUpdate", nil)
    end
    local function updateDrag()
        if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
            stopDrag()
            return
        end
        local value = cursorRank()
        if dragging == "low" then
            cfg.rankMin = math.min(value, cfg.rankMax)
        elseif dragging == "high" then
            cfg.rankMax = math.max(value, cfg.rankMin)
        end
        update()
    end
    local function beginDrag(kind)
        dragging = kind
        updateDrag()
        range:SetScript("OnUpdate", updateDrag)
    end

    if locked then
        lowHandle:Disable()
        highHandle:Disable()
        track:Disable()
        range:SetAlpha(0.55)
        range:EnableMouse(true)
        range:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Set by Guild Information")
            GameTooltip:AddLine("The trusted rank range is controlled by the LootViewer Authority directive.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        range:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        lowHandle:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then beginDrag("low") end end)
        lowHandle:SetScript("OnMouseUp", stopDrag)
        highHandle:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then beginDrag("high") end end)
        highHandle:SetScript("OnMouseUp", stopDrag)
        track:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local clicked = cursorRank()
            beginDrag(math.abs(clicked - cfg.rankMin) <= math.abs(clicked - cfg.rankMax) and "low" or "high")
        end)
        track:SetScript("OnMouseUp", stopDrag)
        track:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Trusted guild ranks")
            GameTooltip:AddLine("Rank 0 is the highest guild rank. Drag either handle to select the trusted range.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        track:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    range:SetScript("OnHide", stopDrag)
    update()
    return range
end

local function optionCell(parent, x, y, width)
    local cell = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    cell:SetPoint("TOPLEFT", x, y)
    cell:SetSize(width, 48)
    LV.Widgets:ApplyBackdrop(cell, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.transparent)
    return cell
end

local function cellLabel(cell, text)
    local label = LV.Widgets:Text(cell, text)
    label:SetPoint("LEFT", 14, 0)
    label:SetWidth(math.max(100, cell:GetWidth() - 190))
    label:SetWordWrap(false)
    return label
end

local function checkCell(parent, x, y, width, label, checked, onChanged, tooltip)
    local cell = optionCell(parent, x, y, width)
    cellLabel(cell, label)
    local check = LV.Widgets:Check(cell, "", onChanged)
    check:SetPoint("RIGHT", -16, 0)
    check:SetChecked(checked and true or false)
    if tooltip then
        LV.Widgets:SetTooltip(check, tooltip)
    end
    return cell
end

local function dropdownCell(parent, x, y, width, label, values, getValue, setValue, controlWidth)
    local cell = optionCell(parent, x, y, width)
    local labelText = cellLabel(cell, label)
    local dropdown = LV.Widgets:Dropdown(cell, values, getValue, setValue, controlWidth or 170)
    dropdown:SetPoint("RIGHT", -14, 0)
    return cell, dropdown, labelText
end

local function editCell(parent, x, y, width, label, value, onCommit, controlWidth)
    local cell = optionCell(parent, x, y, width)
    cellLabel(cell, label)
    local edit = LV.Widgets:EditBox(cell, controlWidth or 90, 28, onCommit)
    edit:SetText(tostring(value or ""))
    edit:SetPoint("RIGHT", -14, 0)
    return cell
end

local function sectionGrid(parent, title, y, rows)
    local width = math.max(720, (tonumber(parent:GetWidth()) or 820) - 44)
    local half = math.floor((width - 2) / 2)
    local section = LV.Widgets:Section(parent, title, 34 + (#rows * 50))
    section:SetPoint("TOPLEFT", 22, y)
    section:SetPoint("RIGHT", -22, 0)
    for index, row in ipairs(rows) do
        local rowY = -34 - ((index - 1) * 50)
        row[1](section, 4, rowY, half)
        if row[2] then
            row[2](section, half + 6, rowY, half)
        end
    end
    return section
end

local function colorSwatch(parent, team, onChanged)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(34, 28)
    LV.Widgets:ApplyBackdrop(button, LV.Widgets.colors.control, LV.Widgets.colors.border)
    button.fill = button:CreateTexture(nil, "ARTWORK")
    button.fill:SetPoint("TOPLEFT", 5, -5)
    button.fill:SetPoint("BOTTOMRIGHT", -5, 5)
    local function update()
        team.color = LV.Store:NormalizeTeamColor(team.color)
        button.fill:SetColorTexture(team.color.r, team.color.g, team.color.b, team.color.a)
    end
    update()
    button:SetScript("OnClick", function()
        if not ColorPickerFrame then
            return
        end
        local starting = LV.Store:NormalizeTeamColor(team.color)
        local function apply()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            team.color = LV.Store:NormalizeTeamColor({ r = r, g = g, b = b, a = pickerAlpha() })
            update()
            if onChanged then onChanged() end
        end
        local function cancel(previous)
            previous = type(previous) == "table" and previous or starting
            team.color = LV.Store:NormalizeTeamColor({
                r = previous.r, g = previous.g, b = previous.b,
                a = previous.opacity or previous.a,
            })
            update()
            if onChanged then onChanged() end
        end
        if ColorPickerFrame.SetFrameStrata then ColorPickerFrame:SetFrameStrata("TOOLTIP") end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = starting.r, g = starting.g, b = starting.b,
                opacity = starting.a, hasOpacity = true,
                swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
            })
        else
            ColorPickerFrame.func = apply
            ColorPickerFrame.opacityFunc = apply
            ColorPickerFrame.cancelFunc = cancel
            ColorPickerFrame.hasOpacity = true
            ColorPickerFrame.opacity = starting.a
            ColorPickerFrame:SetColorRGB(starting.r, starting.g, starting.b)
            ColorPickerFrame:Show()
        end
    end)
    return button
end

local function pruneModeValues(seasonID)
    local currentSeasonID = LV.Seasons:CurrentSeasonID()
    if LV.Seasons:IsSeasonID(seasonID) and seasonID ~= currentSeasonID then
        return {
            { value = "tier", label = "This Tier" },
        }
    end

    local values = {
        { value = "all", label = "All" },
        { value = "days:1", label = "1 Day" },
        { value = "days:7", label = "1 Week" },
        { value = "days:30", label = "1 Month" },
    }
    if LV.Seasons:IsSeasonID(seasonID) then
        values[#values + 1] = { value = "tier", label = "This Tier" }
    end
    return values
end

local function valueAvailable(values, wanted)
    for _, item in ipairs(values or {}) do
        if item.value == wanted then
            return true
        end
    end
    return false
end

function UI:RenderGeneralOptions(guildInfo)
    local cfg = guildInfo and LV.Store:GetConfig(guildInfo.key) or nil
    local account = LV.Store:AccountConfig()
    local dungeon = sectionGrid(self.content, "Dungeon Logging", -132, {
        {
            function(parent, x, y, width)
                checkCell(parent, x, y, width, "Dungeon Logging", account.dungeonLogging, function(value)
                    account.dungeonLogging = value and true or false
                    if not account.dungeonLogging and self:IsDungeonContext() then
                        self:SetContextValue("raid:" .. LV.Seasons:CurrentSeasonID())
                        self.currentTab = "config"
                    end
                    self:RebuildContextSelector()
                    self:Refresh()
                end, "Account-wide. Tracks gear from this season's Mythic+ end chest and Mythic 0 bosses.")
            end,
        },
    })

    if not cfg then
        local note = LV.Widgets:Text(self.content, "Guild raid settings become available on a guilded character.")
        note:SetPoint("TOPLEFT", dungeon, "BOTTOMLEFT", 4, -24)
        note:SetTextColor(unpack(LV.Widgets.colors.muted))
        return
    end

    local authorityDirective, authorityStatus = LV.Guild:ScanAuthorityDirective()
    local effectiveAuthority = authorityDirective or {
        mode = cfg.authority or "assist",
        rankMin = tonumber(cfg.rankMin) or 0,
        rankMax = tonumber(cfg.rankMax) or 3,
    }

    local tracking = sectionGrid(self.content, "Raid Tracking", -232, {
        {
            function(parent, x, y, width)
                checkCell(parent, x, y, width, "Prompt for Scheduled Raids", cfg.prompt, function(value) cfg.prompt = value end)
            end,
            function(parent, x, y, width)
                checkCell(parent, x, y, width, "Announce Observed Trades", cfg.tradeRaid, function(value) cfg.tradeRaid = value end)
            end,
        },
        {
            function(parent, x, y, width)
                local cell, dropdown, label = dropdownCell(parent, x, y, width, "Authority", authorityModes,
                    function() return effectiveAuthority.mode or "assist" end,
                    function(value)
                        cfg.authority = value
                        self:Refresh()
                    end, 166)
                local statusText
                local statusColor
                if authorityDirective then
                    statusText = "SET BY GUILD INFORMATION"
                    statusColor = LV.Widgets.colors.navigation
                    dropdown:Disable()
                    dropdown:SetAlpha(0.55)
                    dropdown.arrow:SetTextColor(unpack(LV.Widgets.colors.textMuted))
                elseif authorityStatus == "multiple" then
                    statusText = "MULTIPLE DIRECTIVES FOUND"
                    statusColor = LV.Widgets.colors.dangerBorder
                elseif authorityStatus == "invalid" then
                    statusText = "INVALID GUILD INFORMATION DIRECTIVE"
                    statusColor = LV.Widgets.colors.dangerBorder
                else
                    local info = LV.Widgets:Button(cell, "i", 20, 20, nil, "ghost")
                    info:SetPoint("LEFT", 86, 0)
                    info.text:SetTextColor(unpack(LV.Widgets.colors.accentBright))
                    info:HookScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Guild Information Authority")
                        GameTooltip:AddLine("Using this character's saved setting. Guild officers can lock authority by adding exactly one standalone line to Guild Information:", 0.8, 0.8, 0.8, true)
                        GameTooltip:AddLine("LootViewer Authority: Lead / Assist", 0.34, 0.86, 0.56, true)
                        GameTooltip:AddLine("LootViewer Authority: Raid Lead", 0.34, 0.86, 0.56, true)
                        GameTooltip:AddLine("LootViewer Authority: Anyone", 0.34, 0.86, 0.56, true)
                        GameTooltip:AddLine("LootViewer Authority: Trusted 0-3", 0.34, 0.86, 0.56, true)
                        GameTooltip:Show()
                    end)
                    info:HookScript("OnLeave", function() GameTooltip:Hide() end)
                end
                if statusText then
                    label:ClearAllPoints()
                    label:SetPoint("TOPLEFT", 14, -7)
                    local status = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    status:SetPoint("BOTTOMLEFT", 14, 7)
                    status:SetText(statusText)
                    status:SetTextColor(unpack(statusColor))
                    cell:EnableMouse(true)
                    cell:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        if authorityDirective then
                            GameTooltip:SetText("Set by Guild Information")
                            GameTooltip:AddLine(authorityDirective.line, 0.8, 0.8, 0.8, true)
                            GameTooltip:AddLine("Remove the directive to restore this character's saved setting.", 0.6, 0.7, 0.8, true)
                        else
                            GameTooltip:SetText("Guild Information directive ignored")
                            GameTooltip:AddLine("Use exactly one standalone line such as: LootViewer Authority: Trusted 0-3", 0.8, 0.8, 0.8, true)
                        end
                        GameTooltip:Show()
                    end)
                    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
            end,
            function(parent, x, y, width)
                if effectiveAuthority.mode ~= "trusted" then
                    return
                end
                local cell = optionCell(parent, x, y, width)
                cellLabel(cell, "Guild Rank Range")
                local rankConfig = authorityDirective and {
                    rankMin = effectiveAuthority.rankMin,
                    rankMax = effectiveAuthority.rankMax,
                } or cfg
                local range = createRankRange(cell, rankConfig, 168, authorityDirective ~= nil)
                range:SetPoint("RIGHT", -14, 0)
            end,
        },
        {
            function(parent, x, y, width)
                editCell(parent, x, y, width, "Whisper Keyword", cfg.whisper or "standby", function(value) cfg.whisper = LV.Util:Trim(value) end, 130)
            end,
            function(parent, x, y, width)
                checkCell(parent, x, y, width, "Auto Start Pug Raids", account.autoPugRaids, function(value)
                    account.autoPugRaids = value and true or false
                    if account.autoPugRaids and LV.Raid and LV.Raid.MaybeAutoStartPug then
                        LV.Raid:MaybeAutoStartPug()
                    end
                end, "Account-wide. Automatically starts a local Pugs raid after entering current-tier raid content outside every configured raid team's scheduled hours. Raid Finder is ignored.")
            end,
        },
    })

    sectionGrid(self.content, "Timing & Data", -432, {
        {
            function(parent, x, y, width)
                dropdownCell(parent, x, y, width, "Late Grace", graceMinuteValues,
                    function() return tonumber(cfg.lateGrace) or 10 end,
                    function(value) cfg.lateGrace = tonumber(value) or 10 end, 126)
            end,
            function(parent, x, y, width)
                dropdownCell(parent, x, y, width, "Prompt Timeout", promptTimeoutValues,
                    function() return tonumber(cfg.promptTimeout) or 30 end,
                    function(value) cfg.promptTimeout = tonumber(value) or 30 end, 126)
            end,
        },
        {
            function(parent, x, y, width)
                local seasonID = self:SelectedSeasonFilter()
                local values = pruneModeValues(seasonID)
                if not valueAvailable(values, cfg.pruneMode) then
                    cfg.pruneMode = values[1].value
                end
                local cell = optionCell(parent, x, y, width)
                cellLabel(cell, "Prune Records")
                local prune = LV.Widgets:Button(cell, "Prune", 62, 26, function()
                    local mode = cfg.pruneMode or values[1].value
                    local description
                    if mode == "all" then
                        description = "all raid, loot, and trade history"
                    elseif mode == "tier" then
                        local tierID = LV.Seasons:IsSeasonID(seasonID) and seasonID or LV.Seasons:CurrentSeasonID()
                        description = "all raid, loot, and trade history for " .. LV.Seasons:Label(tierID)
                    else
                        local days = tonumber(tostring(mode):match("^days:(%d+)$")) or 30
                        description = "raid, loot, and trade history older than " .. tostring(days) .. (days == 1 and " day" or " days")
                    end
                    self:ShowConfirmationDialog({
                        title = "Prune LootViewer Records",
                        message = "Permanently delete " .. description .. " for " .. tostring(guildInfo.name) .. "? This cannot be undone.",
                        acceptText = "Prune",
                        onAccept = function()
                            local removed
                            if mode == "all" then
                                removed = LV.Store:PruneAllHistory(guildInfo.key)
                            elseif mode == "tier" then
                                local tierID = LV.Seasons:IsSeasonID(seasonID) and seasonID or LV.Seasons:CurrentSeasonID()
                                removed = LV.Store:PruneSeason(guildInfo.key, tierID)
                            else
                                local days = tonumber(tostring(mode):match("^days:(%d+)$")) or 30
                                removed = LV.Store:Prune(guildInfo.key, days * 86400)
                            end
                            LV:Print("Pruned " .. tostring(removed or 0) .. " record(s).")
                            self:Refresh()
                        end,
                    })
                end, "danger")
                prune:SetPoint("RIGHT", -14, 0)
                local mode = LV.Widgets:Dropdown(cell, values,
                    function() return cfg.pruneMode end,
                    function(value) cfg.pruneMode = value end, 116)
                mode:SetPoint("RIGHT", prune, "LEFT", -8, 0)
            end,
            function(parent, x, y, width)
                dropdownCell(parent, x, y, width, "End Grace", graceMinuteValues,
                    function() return tonumber(cfg.endGrace) or 0 end,
                    function(value)
                        cfg.endGrace = tonumber(value) or 0
                        if LV.Raid and LV.Raid.GetActiveSession then
                            LV.Raid:GetActiveSession()
                        end
                    end, 126)
            end,
        },
    })
end

local function scheduleSummary(team)
    local parts = {}
    for _, slot in ipairs(team.schedules or {}) do
        local day = dayValues[tonumber(slot.w) or 1]
        parts[#parts + 1] = (day and day.label:sub(1, 3) or "Day")
            .. " " .. formatScheduleTime(scheduleStartMinute(slot), team.clock24)
            .. "–" .. formatScheduleTime(scheduleEndMinute(slot), team.clock24)
    end
    local times = #parts > 0 and table.concat(parts, "  /  ") or "No scheduled raid times"
    return times .. "  ·  " .. LV.Util:TimezoneLabel(team.tz)
end

function UI:AnimateTeamModal(modal)
    modal:SetAlpha(0)
    local group = modal:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.16)
    fade:SetSmoothing("OUT")
    local move = group:CreateAnimation("Translation")
    move:SetOffset(0, 12)
    move:SetDuration(0.16)
    move:SetSmoothing("OUT")
    group:SetScript("OnFinished", function()
        modal:ClearAllPoints()
        modal:SetPoint("CENTER")
        modal:SetAlpha(1)
    end)
    group:Play()
end

function UI:OpenRaidTeamModal(cfg, team)
    if self.teamConfigLayer then self.teamConfigLayer:Hide() end
    local layer = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    layer:SetAllPoints(self.frame)
    layer:SetFrameStrata("FULLSCREEN_DIALOG")
    layer:SetFrameLevel(self.frame:GetFrameLevel() + 430)
    layer:EnableMouse(true)
    LV.Widgets:ApplyBackdrop(layer, LV.Widgets.colors.overlay, LV.Widgets.colors.transparent)
    local modal = CreateFrame("Frame", nil, layer, "BackdropTemplate")
    modal:SetSize(820, 580)
    modal:SetPoint("CENTER", 0, -12)
    modal:SetFrameLevel(layer:GetFrameLevel() + 1)
    LV.Widgets:ApplyBackdrop(modal, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.borderStrong)
    local title = LV.Widgets:Text(modal, "Configure Raid Team", "large")
    title:SetPoint("TOPLEFT", 22, -18)
    local close = LV.Widgets:Button(modal, "x", 28, 28, function() layer:Hide() end, "ghost")
    close:SetPoint("TOPRIGHT", -14, -14)
    local nameLabel = LV.Widgets:Label(modal, "TEAM NAME")
    nameLabel:SetPoint("TOPLEFT", 24, -66)
    local name = LV.Widgets:EditBox(modal, 250, 30, function(value)
        team.name = LV.Util:Trim(value)
        if team.name == "" then team.name = team.id end
    end)
    name:SetText(team.name or team.id)
    name:SetPoint("TOPLEFT", 24, -84)
    local swatchLabel = LV.Widgets:Label(modal, "COLOR")
    swatchLabel:SetPoint("TOPLEFT", 300, -66)
    local swatch = colorSwatch(modal, team)
    swatch:SetPoint("TOPLEFT", 300, -84)
    local timezoneLabel = LV.Widgets:Label(modal, "TIME ZONE")
    timezoneLabel:SetPoint("TOPLEFT", 356, -66)
    local timezone = LV.Widgets:Dropdown(modal, timezoneValues,
        function() return LV.Util:NormalizeTimezone(team.tz) end,
        function(value)
            team.tz = LV.Util:NormalizeTimezone(value)
        end, 200)
    timezone:SetPoint("TOPLEFT", 356, -84)
    LV.Widgets:SetTooltip(timezone, "Named time zones stay consistent when synced across realms and automatically follow U.S. daylight-saving time.")

    local optionWidth = 382
    checkCell(modal, 24, -132, optionWidth, "Exclude from Sync", team.excludeSync, function(value)
        team.excludeSync = value and true or false
    end, "Raids and loot stay local and do not sync.")
    checkCell(modal, 414, -132, optionWidth, "24-Hour Clock", team.clock24, function(value)
        team.clock24 = value and true or false
        self:OpenRaidTeamModal(cfg, team)
    end, "Displays raid schedule times using a 24-hour clock. This does not change when the raid starts.")

    local raidTimesLabel = LV.Widgets:Label(modal, "RAID TIMES")
    raidTimesLabel:SetPoint("TOPLEFT", 24, -204)
    local add = LV.Widgets:Button(modal, "Add Raid Time", 116, 28, function()
        local current = LV.Util:TimezoneCalendar(team.tz, LV.Util:ServerNow())
        team.schedules[#team.schedules + 1] = { w = tonumber(current.wday) or 1, h = 20, m = 0, d = 180 }
        self:OpenRaidTeamModal(cfg, team)
    end, "success")
    add:SetPoint("TOPRIGHT", -24, -194)

    local headers = { { "DAY", 24 }, { "START / END  ·  30-MINUTE SNAP", 188 } }
    for _, header in ipairs(headers) do
        local label = LV.Widgets:Label(modal, header[1])
        label:SetPoint("TOPLEFT", header[2], -238)
    end
    local scroll, content = LV.Widgets:ScrollFrame(modal)
    scroll:SetPoint("TOPLEFT", 14, -258)
    scroll:SetPoint("BOTTOMRIGHT", -14, 64)
    local y = -4
    for index, slot in ipairs(team.schedules or {}) do
        local scheduleIndex, scheduleSlot = index, slot
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 4, y)
        row:SetPoint("RIGHT", -4, 0)
        row:SetHeight(72)
        LV.Widgets:ApplyBackdrop(row, index % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface, LV.Widgets.colors.border)
        local day = LV.Widgets:Dropdown(row, dayValues, function() return tonumber(scheduleSlot.w) or 1 end, function(value) scheduleSlot.w = value end, 136)
        day:SetPoint("TOPLEFT", 10, -22)
        local range = createScheduleRange(row, scheduleSlot, team.clock24 == true, 510)
        range:SetPoint("TOPLEFT", 164, -7)
        local duplicate = LV.Widgets:IconButton(row, "copy", 26, 26, function()
            table.insert(team.schedules, scheduleIndex + 1, {
                w = tonumber(scheduleSlot.w) or 1,
                h = tonumber(scheduleSlot.h) or 20,
                m = tonumber(scheduleSlot.m) or 0,
                d = tonumber(scheduleSlot.d) or 180,
            })
            self:OpenRaidTeamModal(cfg, team)
        end)
        duplicate:SetPoint("TOPLEFT", 696, -23)
        LV.Widgets:SetTooltip(duplicate, "Duplicate this raid time")
        local remove = LV.Widgets:IconButton(row, "trash", 26, 26, function()
            table.remove(team.schedules, scheduleIndex)
            self:OpenRaidTeamModal(cfg, team)
        end)
        remove:SetPoint("TOPLEFT", 728, -23)
        LV.Widgets:SetTooltip(remove, "Delete this raid time")
        y = y - 78
    end
    content:SetHeight(math.max(1, -y + 4))
    local delete = LV.Widgets:Button(modal, "Delete Team", 104, 28, function()
        if #(cfg.teams or {}) <= 1 then
            LV:Print("Keep at least one raid team.")
            return
        end
        for index, candidate in ipairs(cfg.teams) do
            if candidate == team then table.remove(cfg.teams, index) break end
        end
        cfg.selectedTeam = cfg.teams[1].id
        layer:Hide()
        self:Refresh()
    end, "danger")
    delete:SetPoint("BOTTOMLEFT", 24, 20)
    local done = LV.Widgets:Button(modal, "Done", 96, 28, function()
        layer:Hide()
        self:Refresh()
    end, "primary")
    done:SetPoint("BOTTOMRIGHT", -24, 20)
    self.teamConfigLayer = layer
    self:AnimateTeamModal(modal)
end

function UI:RenderRaidTeamOptions(guildInfo)
    local cfg = guildInfo and LV.Store:GetConfig(guildInfo.key) or nil
    local section = LV.Widgets:Section(self.content, "Raid Teams", 440)
    section:SetPoint("TOPLEFT", 22, -132)
    section:SetPoint("BOTTOMRIGHT", -22, 22)
    if guildInfo then
        local add = LV.Widgets:Button(section.header, "Add Team", 88, 24, function()
            self:ShowTextEntryDialog({
                title = "Add Raid Team", hint = "Create a raid team for " .. guildInfo.name .. ".", acceptText = "Add Team",
                onAccept = function(value) LV.Store:AddRaidTeam(guildInfo.key, value) self:Refresh() end,
            })
        end, "success")
        add:SetPoint("RIGHT", -14, 0)
    end
    local scroll, content = LV.Widgets:ScrollFrame(section)
    scroll:SetPoint("TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    local width = math.max(650, (tonumber(section:GetWidth()) or 760) - 46)
    local y = -4

    local function renderTeamRow(team, index, globalPugs)
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 4, y)
        row:SetSize(width, 54)
        LV.Widgets:ApplyBackdrop(row, index % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface, LV.Widgets.colors.border)
        local swatch = row:CreateTexture(nil, "ARTWORK")
        local color = LV.Store:NormalizeTeamColor(team.color)
        swatch:SetColorTexture(color.r, color.g, color.b, color.a)
        swatch:SetPoint("TOPLEFT", 10, -10)
        swatch:SetPoint("BOTTOMLEFT", 10, 10)
        swatch:SetWidth(4)
        local name = LV.Widgets:Text(row, team.name or team.id)
        name:SetPoint("TOPLEFT", 24, -9)
        local summaryText = globalPugs and "Account-wide  •  No schedule  •  Never synced" or scheduleSummary(team)
        local summary = LV.Widgets:Text(row, summaryText)
        summary:SetPoint("TOPLEFT", 24, -31)
        summary:SetWidth(width - 220)
        summary:SetWordWrap(false)
        summary:SetTextColor(unpack(LV.Widgets.colors.muted))
        if globalPugs then
            local accountWide = LV.Widgets:Label(row, "ACCOUNT-WIDE  •  LOCAL ONLY")
            accountWide:SetPoint("RIGHT", -14, 0)
            accountWide:SetTextColor(unpack(LV.Widgets.colors.navigation))
        elseif team.excludeSync == true then
            local localOnly = LV.Widgets:Label(row, "LOCAL ONLY")
            localOnly:SetPoint("RIGHT", -64, 0)
            localOnly:SetTextColor(unpack(LV.Widgets.colors.navigation))
        end
        if not globalPugs then
            local gear = LV.Widgets:Button(row, "", 34, 34, function() self:OpenRaidTeamModal(cfg, team) end, "ghost")
            gear:SetPoint("RIGHT", -10, 0)
            gear.icon = gear:CreateTexture(nil, "ARTWORK")
            gear.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
            gear.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            gear.icon:SetDesaturated(true)
            gear.icon:SetSize(20, 20)
            gear.icon:SetPoint("CENTER")
            LV.Widgets:SetTooltip(gear, "Configure " .. tostring(team.name or team.id))
        end
        y = y - 62
    end

    renderTeamRow(LV.Store:GlobalPugTeam(), 1, true)
    for index, team in ipairs((cfg and cfg.teams) or {}) do
        renderTeamRow(team, index + 1, false)
    end
    if not guildInfo then
        local note = LV.Widgets:Text(content, "Guild raid teams are available while logged into a guilded character.")
        note:SetPoint("TOPLEFT", 10, y - 2)
        note:SetTextColor(unpack(LV.Widgets.colors.muted))
        y = y - 32
    end
    content:SetHeight(math.max(1, -y + 4))
end

function UI:RenderConfig()
    local guildInfo = LV.Guild:CurrentInfo()
    if guildInfo then LV.Store:GuildRecord(guildInfo.key) end
    self.configView = self.configView == "teams" and "teams" or "general"
    self:SetPageHeader("Configuration", "Account-wide dungeon logging and guild raid settings.", guildInfo)
    local tabs = self:Track(CreateFrame("Frame", nil, self.content))
    tabs:SetPoint("TOPLEFT", 22, -84)
    tabs:SetPoint("TOPRIGHT", -22, -84)
    tabs:SetHeight(38)
    local general = LV.Widgets:Tab(tabs, "General", 112, 38, function() self.configView = "general" self:Refresh() end)
    general:SetPoint("LEFT")
    LV.Widgets:SetButtonActive(general, self.configView == "general")
    local teams = LV.Widgets:Tab(tabs, "Raid Teams", 112, 38, function() self.configView = "teams" self:Refresh() end)
    teams:SetPoint("LEFT", general, "RIGHT", 4, 0)
    LV.Widgets:SetButtonActive(teams, self.configView == "teams")
    if self.configView == "teams" then
        self:RenderRaidTeamOptions(guildInfo)
    else
        self:RenderGeneralOptions(guildInfo)
    end
end
