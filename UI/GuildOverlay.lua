local _, LV = ...

LV.GuildOverlay = {}
LV.modules.GuildOverlay = LV.GuildOverlay

local hookedFrames = {}
local detailFrameNames = {
    "CommunitiesGuildMemberDetailFrame",
    "GuildMemberDetailFrame",
}

local detailFrameFields = {
    "GuildMemberDetailFrame",
    "MemberDetailFrame",
}

local detailNameFields = {
    "Name",
    "NameText",
    "MemberName",
    "CharacterName",
}

local function isVisible(frame)
    return frame and type(frame.IsShown) == "function" and frame:IsShown()
end

local function safeCall(frame, methodName)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, value = pcall(method, frame)
    if ok then
        return value
    end

    return nil
end

local function safeList(frame, methodName)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then
        return {}
    end

    local values = { pcall(method, frame) }
    if not values[1] then
        return {}
    end

    table.remove(values, 1)
    return values
end

local function frameName(frame)
    return safeCall(frame, "GetName")
end

local function frameParent(frame)
    return safeCall(frame, "GetParent")
end

local function frameLevel(frame)
    return safeCall(frame, "GetFrameLevel") or 1
end

local function frameWidth(frame)
    return safeCall(frame, "GetWidth") or 320
end

local function frameText(frame)
    local method = frame and frame.GetText
    if type(method) ~= "function" then
        return ""
    end

    local ok, value = pcall(method, frame)
    if ok then
        return LV.Util:Trim(value)
    end

    return ""
end

local function isDescendant(frame, ancestor)
    while frame do
        if frame == ancestor then
            return true
        end
        frame = frameParent(frame)
    end
    return false
end

local function guildShellVisible()
    return isVisible(CommunitiesFrame) or isVisible(GuildFrame)
end

local function frameContainsText(frame, text, depth)
    if not frame or LV.Util:IsBlank(text) or (depth or 0) > 4 then
        return false
    end

    for _, region in ipairs(safeList(frame, "GetRegions")) do
        if type(region.GetText) == "function" then
            local ok, value = pcall(region.GetText, region)
            if ok and value and tostring(value):find(text, 1, true) then
                return true
            end
        end
    end

    for _, child in ipairs(safeList(frame, "GetChildren")) do
        if frameContainsText(child, text, (depth or 0) + 1) then
            return true
        end
    end

    return false
end

function LV.GuildOverlay:NormalizeName(name)
    name = LV.Util:Trim(name)
    if name == "" then
        return ""
    end

    if not name:find("-", 1, true) then
        local info = LV.Guild:CurrentInfo()
        name = name .. "-" .. ((info and info.realm) or LV.Util:RealmName())
    end

    return name
end

function LV.GuildOverlay:SelectedGuildName()
    if type(GetGuildRosterSelection) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return ""
    end

    local ok, index = pcall(GetGuildRosterSelection)
    if not ok or not index or index <= 0 then
        return ""
    end

    local infoOk, name = pcall(GetGuildRosterInfo, index)
    if not infoOk then
        return ""
    end

    return self:NormalizeName(name)
end

function LV.GuildOverlay:DetailMemberName(detail)
    for _, field in ipairs(detailNameFields) do
        local text = frameText(detail and detail[field])
        if text ~= "" then
            return self:NormalizeName(text)
        end
    end

    return ""
end

function LV.GuildOverlay:FrameLooksLikeDetail(frame)
    local name = frameName(frame)
    local lowered = name and name:lower() or ""
    return isVisible(frame)
        and lowered:find("member", 1, true)
        and lowered:find("detail", 1, true)
end

function LV.GuildOverlay:FindDetailChild(parent, depth)
    if not parent or (depth or 0) > 8 then
        return nil
    end

    for _, child in ipairs(safeList(parent, "GetChildren")) do
        if self:FrameLooksLikeDetail(child) then
            return child
        end

        local found = self:FindDetailChild(child, (depth or 0) + 1)
        if found then
            return found
        end
    end

    return nil
end

function LV.GuildOverlay:DetailFrame()
    if isVisible(self.detailFrame) then
        return self.detailFrame
    end

    for _, root in ipairs({ CommunitiesFrame, GuildFrame }) do
        for _, field in ipairs(detailFrameFields) do
            local frame = root and root[field]
            if isVisible(frame) then
                self.detailFrame = frame
                self:HookFrame(frame)
                return frame
            end
        end
    end

    for _, name in ipairs(detailFrameNames) do
        local frame = _G[name]
        if isVisible(frame) then
            self.detailFrame = frame
            self:HookFrame(frame)
            return frame
        end
    end

    for _, root in ipairs({ CommunitiesFrame, GuildFrame }) do
        if isVisible(root) then
            local frame = self:FindDetailChild(root, 0)
            if frame and (isDescendant(frame, CommunitiesFrame) or isDescendant(frame, GuildFrame)) then
                self.detailFrame = frame
                self:HookFrame(frame)
                return frame
            end
        end
    end

    return nil
end

function LV.GuildOverlay:Ensure()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "LootViewerGuildDetailOverlay", UIParent, "BackdropTemplate")
    frame:SetHeight(74)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    LV.Widgets:ApplyBackdrop(frame, LV.Widgets.colors.panel, LV.Widgets.colors.border)

    frame.label = LV.Widgets:Text(frame, "LootViewer")
    frame.label:SetPoint("TOPLEFT", 10, -8)
    frame.label:SetPoint("TOPRIGHT", -10, -8)
    frame.label:SetHeight(18)
    frame.label:SetJustifyH("LEFT")

    local here = LV.Widgets:Button(frame, "Here", 50, 24, function()
        LV.GuildOverlay:Mark("here")
    end)
    here:SetPoint("BOTTOMLEFT", 10, 10)
    frame.here = here

    local bench = LV.Widgets:Button(frame, "Bench", 58, 24, function()
        LV.GuildOverlay:Mark("bench")
    end)
    bench:SetPoint("LEFT", here, "RIGHT", 6, 0)
    frame.bench = bench

    local late = LV.Widgets:Button(frame, "Late", 50, 24, function()
        LV.GuildOverlay:Mark("late")
    end)
    late:SetPoint("LEFT", bench, "RIGHT", 6, 0)
    frame.late = late

    local out = LV.Widgets:Button(frame, "Out", 46, 24, function()
        LV.GuildOverlay:Mark("out")
    end)
    out:SetPoint("LEFT", late, "RIGHT", 6, 0)
    frame.out = out

    local noshow = LV.Widgets:Button(frame, "NoShow", 70, 24, function()
        LV.GuildOverlay:Mark("noshow")
    end)
    noshow:SetPoint("LEFT", out, "RIGHT", 6, 0)
    frame.noshow = noshow

    frame.buttons = { here, bench, late, out, noshow }

    self.frame = frame
end

function LV.GuildOverlay:AttendanceStatus(session, guildKey, fullName)
    if not session or not guildKey then
        return "no active raid"
    end

    local nameID = LV.Store:NameID(guildKey, fullName)
    if not nameID then
        return "not marked"
    end

    if session.out and session.out[nameID] then
        return "out"
    end
    if session.noshow and session.noshow[nameID] then
        return "noshow"
    end
    if session.b and session.b[nameID] then
        return "benched"
    end
    if session.late and session.late[nameID] then
        return "late"
    end
    if session.p and session.p[nameID] then
        return "here"
    end
    return "not marked"
end

function LV.GuildOverlay:Mark(status)
    if LV.Util:IsBlank(self.currentName) then
        LV:Print("Select a guild member first.")
        return
    end

    LV.Guild:RememberMember(self.currentName, { ov = 1 })
    LV.Raid:SetAttendance(self.currentName, status, "ui")
    self:UpdateVisibility()
end

function LV.GuildOverlay:Hide()
    self.currentName = nil
    self.currentGuildKey = nil
    if self.frame then
        self.frame:Hide()
    end
end

function LV.GuildOverlay:UpdateVisibility()
    if not guildShellVisible() then
        self:Hide()
        self:StopTicker()
        return
    end

    local session, _, guildKey = LV.Raid:GetActiveSession()
    guildKey = guildKey or LV.Guild:CurrentKey()

    local detail = self:DetailFrame()
    local fullName = self:SelectedGuildName()
    if fullName == "" then
        fullName = self:DetailMemberName(detail)
    end
    local shortName = LV.Util:ShortName(fullName)
    if not isVisible(detail) or fullName == "" or not frameContainsText(detail, shortName) then
        self:Hide()
        return
    end

    self.currentName = fullName
    self.currentGuildKey = guildKey
    self:Ensure()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 12, -4)
    self.frame:SetPoint("TOPRIGHT", detail, "BOTTOMRIGHT", -12, -4)
    self.frame:SetFrameLevel(frameLevel(detail) + 20)
    self.frame.label:SetText("LootViewer: " .. shortName .. " - " .. self:AttendanceStatus(session, guildKey, fullName))
    self.frame.label:SetWidth(math.max(180, frameWidth(detail) - 24))
    if session and guildKey then
        self.frame:SetHeight(74)
        for _, button in ipairs(self.frame.buttons or {}) do
            button:Show()
        end
    else
        self.frame:SetHeight(34)
        for _, button in ipairs(self.frame.buttons or {}) do
            button:Hide()
        end
    end
    self.frame:Show()
end

function LV.GuildOverlay:HookFrame(frame)
    if not frame or hookedFrames[frame] then
        return
    end
    if type(frame.HookScript) ~= "function" then
        return
    end

    hookedFrames[frame] = true
    frame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            LV.GuildOverlay:StartTicker()
            LV.GuildOverlay:UpdateVisibility()
        end)
    end)
    frame:HookScript("OnHide", function()
        C_Timer.After(0, function()
            LV.GuildOverlay:UpdateVisibility()
        end)
    end)
end

function LV.GuildOverlay:StartTicker()
    if self.ticker or not C_Timer or not C_Timer.NewTicker then
        return
    end

    self.ticker = C_Timer.NewTicker(0.4, function()
        if guildShellVisible() then
            LV.GuildOverlay:UpdateVisibility()
        else
            LV.GuildOverlay:StopTicker()
        end
    end)
end

function LV.GuildOverlay:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function LV.GuildOverlay:HookGuildFrames()
    self:HookFrame(CommunitiesFrame)
    self:HookFrame(GuildFrame)
    self:DetailFrame()
    if guildShellVisible() then
        self:StartTicker()
    end
    self:UpdateVisibility()
end

LV:RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(1, function()
        LV.GuildOverlay:HookGuildFrames()
    end)
end)

LV:RegisterEvent("ADDON_LOADED", function(_, loadedAddonName)
    if loadedAddonName == "Blizzard_Communities" or loadedAddonName == "Blizzard_GuildUI" then
        C_Timer.After(0, function()
            LV.GuildOverlay:HookGuildFrames()
        end)
    end
end)

LV:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    LV.GuildOverlay:UpdateVisibility()
end)

LV:RegisterEvent("GUILD_ROSTER_UPDATE", function()
    LV.GuildOverlay:UpdateVisibility()
end)
