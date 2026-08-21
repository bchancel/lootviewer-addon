local _, LV = ...

LV.UI = {}
LV.modules.UI = LV.UI

local ATTENDANCE_PAGE_SIZE = 6
local METER_DETAIL_PAGE_SIZE = 8
local HISTORY_PAGE_SIZE = 15

local difficultyLabels = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "Raid Finder",
    [250] = "Raid Finder",
}

local raidDifficultyThresholds = {
    { value = "lfr", label = "LFR", abbreviation = "L", rank = 1, bucket = "lfr" },
    { value = "normal", label = "Normal", abbreviation = "N", rank = 2, bucket = "normal" },
    { value = "heroic", label = "Heroic", abbreviation = "H", rank = 3, bucket = "heroic" },
    { value = "mythic", label = "Mythic", abbreviation = "M", rank = 4, bucket = "mythic" },
}

local raidDifficultyRankByAbbreviation = { L = 1, N = 2, H = 3, M = 4 }
local raidDifficultyRankByValue = { lfr = 1, normal = 2, heroic = 3, mythic = 4 }

local lootRollVisuals = {
    need = { label = "Need", atlas = "lootroll-rollicon-yourolled-need" },
    greed = { label = "Greed", atlas = "lootroll-rollicon-yourolled-greed" },
    transmog = { label = "Transmog", atlas = "lootroll-rollicon-yourolled-transmog" },
}
local lootRollGroupOrder = { "need", "greed", "transmog" }
local unknownLootRollTexture = "Interface\\Icons\\INV_Misc_Dice_01"

local SIDEBAR_WIDTH = 220

local pageDefinitions = {
    config = {
        label = "Configuration",
        hint = "Guild raid tracking, timing, and raid-team settings.",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
    },
    attendance = {
        label = "Raid History",
        hint = "Raid nights and the attendance recorded for each player.",
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        context = "raid",
    },
    meter = {
        label = "Attendance Meter",
        hint = "Scrollable attendance totals across recent raid nights.",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
        context = "raid",
    },
    history = {
        label = "Loot History",
        hint = "Recent loot, season tier tokens, trades, and excluded items.",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        context = "raid",
    },
    dungeonHistory = {
        label = "Loot History",
        hint = "Dungeon loot history and distribution.",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        context = "dungeon",
    },
    sync = {
        label = "Sync",
        hint = "Send this guild's LootViewer data to another player.",
        icon = "Interface\\Icons\\Spell_Arcane_PortalDalaran",
    },
}

local pageOrder = { "config", "attendance", "meter", "history", "dungeonHistory", "sync" }

local attendanceStatusValues = {
    { value = "here", label = "Here" },
    { value = "bench", label = "Standby" },
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

local function compareText(a, b)
    return tostring(a or ""):lower() < tostring(b or ""):lower()
end

local function containsValue(values, value)
    for _, item in ipairs(values or {}) do
        if item.value == value then
            return true
        end
    end
    return false
end

local function popupEditBox(dialog)
    return dialog and (dialog.editBox or dialog.EditBox)
end

local function addonVersion()
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(getter) == "function" then
        local ok, version = pcall(getter, LV.name, "Version")
        if ok and type(version) == "string" and version ~= "" then
            return version
        end
    end
    return LV.version
end

local function windowState()
    LV.Store:InitializeIfNeeded()
    local character = LV.Store.db.c
    character.ui = type(character.ui) == "table" and character.ui or {}
    character.ui.window = type(character.ui.window) == "table" and character.ui.window or {}
    local state = character.ui.window
    state.width = math.max(1040, math.min(1700, tonumber(state.width) or 1040))
    state.height = math.max(700, math.min(1050, tonumber(state.height) or 700))
    state.point = state.point or "CENTER"
    state.relativePoint = state.relativePoint or "CENTER"
    state.x = tonumber(state.x) or 0
    state.y = tonumber(state.y) or 0
    return state
end

function LV.UI:HistoryFilterPreference(key, fallback)
    LV.Store:InitializeIfNeeded()
    LV.Store.db.c.ui = type(LV.Store.db.c.ui) == "table" and LV.Store.db.c.ui or {}
    local ui = LV.Store.db.c.ui
    ui.lootFilters = type(ui.lootFilters) == "table" and ui.lootFilters or {}
    local value = ui.lootFilters[key]
    return value ~= nil and value or fallback
end

function LV.UI:SetHistoryFilterPreference(key, value)
    LV.Store:InitializeIfNeeded()
    LV.Store.db.c.ui = type(LV.Store.db.c.ui) == "table" and LV.Store.db.c.ui or {}
    local ui = LV.Store.db.c.ui
    ui.lootFilters = type(ui.lootFilters) == "table" and ui.lootFilters or {}
    ui.lootFilters[key] = value
end

local function saveWindowPosition(frame, state)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    state.point = point or "CENTER"
    state.relativePoint = relativePoint or state.point
    state.x = tonumber(x) or 0
    state.y = tonumber(y) or 0
end

function LV.UI:ContextValue()
    LV.Store:InitializeIfNeeded()
    LV.Store.db.c.ui = type(LV.Store.db.c.ui) == "table" and LV.Store.db.c.ui or {}
    local ui = LV.Store.db.c.ui
    local currentSeasonID = LV.Seasons:CurrentSeasonID()
    ui.context = ui.context or ("raid:" .. currentSeasonID)
    local contentType, seasonID = tostring(ui.context):match("^(%a+):(.+)$")
    local dungeonEnabled = LV.Store:AccountConfig().dungeonLogging == true
    if (contentType ~= "raid" and contentType ~= "dungeon")
        or (contentType == "dungeon" and not dungeonEnabled) then
        contentType = "raid"
    end
    if seasonID ~= "all" and seasonID ~= currentSeasonID then
        seasonID = currentSeasonID
    end
    ui.context = contentType .. ":" .. seasonID
    return ui.context
end

function LV.UI:SetContextValue(value)
    LV.Store:InitializeIfNeeded()
    LV.Store.db.c.ui = type(LV.Store.db.c.ui) == "table" and LV.Store.db.c.ui or {}
    LV.Store.db.c.ui.context = value
end

function LV.UI:ContextParts()
    local contentType, seasonID = self:ContextValue():match("^(%a+):(.+)$")
    return contentType or "raid", seasonID or LV.Seasons:CurrentSeasonID()
end

function LV.UI:IsDungeonContext()
    return self:ContextParts() == "dungeon"
end

function LV.UI:SelectedSeasonFilter()
    local _, seasonID = self:ContextParts()
    return seasonID
end

function LV.UI:SetSelectedSeasonFilter(seasonID)
    local contentType = self:ContextParts()
    seasonID = seasonID == "all" and "all" or LV.Seasons:CurrentSeasonID()
    self:SetContextValue(contentType .. ":" .. seasonID)
end

function LV.UI:ResetSeasonOnOpen()
    local contentType = self:ContextParts()
    self:SetContextValue(contentType .. ":" .. LV.Seasons:CurrentSeasonID())
    if self.contextSelector and self.contextSelector.Refresh then
        self.contextSelector:Refresh()
    end
end

function LV.UI:RebuildContextSelector()
    if not self.nav then
        return
    end
    if self.contextSelector then
        self.contextSelector:Hide()
    end
    local values = LV.Seasons:ContextValues()
    local selector = LV.Widgets:Dropdown(self.nav, values, function()
        return self:SelectedSeasonFilter()
    end, function(value)
        self:SetSelectedSeasonFilter(value)
        self.historyView = "recent"
        self.historyOffset = 0
        self:Refresh()
    end, SIDEBAR_WIDTH - 36)
    selector:SetPoint("TOPLEFT", 18, -94)
    self.contextSelector = selector
end

function LV.UI:Toggle()
    self:Ensure()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:ResetSeasonOnOpen()
        self.frame:Show()
        self:Refresh()
    end
end

function LV.UI:Ensure()
    if self.frame then
        return
    end

    local state = windowState()
    local frame = CreateFrame("Frame", "LootViewerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(state.width, state.height)
    frame:SetPoint(state.point, UIParent, state.relativePoint, state.x, state.y)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(1000)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(false)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(1040, 700, 1700, 1050)
    else
        frame:SetMinResize(1040, 700)
        frame:SetMaxResize(1700, 1050)
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(selfFrame)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        selfFrame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        saveWindowPosition(selfFrame, state)
    end)
    frame:SetScript("OnMouseDown", function(self)
        self:Raise()
    end)
    frame:SetScript("OnShow", function(self)
        self:Raise()
    end)
    frame:SetScript("OnHide", function()
        self.lootExclusionPromptAccepted = nil
        self.editingRaidID = nil
        self.pugEditRaidID = nil
        if self.adHocPanel then
            self.adHocPanel:Hide()
        end
        if self.confirmationModal then
            self.confirmationModal:Hide()
        end
        if self.textEntryModal then
            self.textEntryModal:Hide()
        end
        if self.lootDistributionModal then
            self.lootDistributionModal:Hide()
        end
        if self.lootItemActionModal then
            self.lootItemActionModal:Hide()
        end
        if self.teamConfigLayer then
            self.teamConfigLayer:Hide()
        end
    end)
    frame:Hide()
    LV.Widgets:ApplyBackdrop(frame, LV.Widgets.colors.canvas, LV.Widgets.colors.borderStrong)

    local nav = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 1, -1)
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetWidth(SIDEBAR_WIDTH)
    nav:SetFrameLevel(frame:GetFrameLevel() + 10)
    LV.Widgets:ApplyBackdrop(nav, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.border)

    local brandMark = CreateFrame("Frame", nil, nav, "BackdropTemplate")
    brandMark:SetSize(44, 38)
    brandMark:SetPoint("TOPLEFT", 18, -18)
    LV.Widgets:ApplyBackdrop(brandMark, LV.Widgets.colors.accentSoft, LV.Widgets.colors.accent)
    local brandLetters = LV.Widgets:Text(brandMark, "/LV")
    brandLetters:SetPoint("CENTER", 0, 1)
    brandLetters:SetTextColor(unpack(LV.Widgets.colors.accentBright))

    local brandText = LV.Widgets:Text(nav, "LootViewer", "large")
    brandText:SetPoint("LEFT", brandMark, "RIGHT", 10, 1)
    brandText:SetTextColor(unpack(LV.Widgets.colors.accentBright))

    local brandDivider = LV.Widgets:Line(nav, 2, LV.Widgets.colors.accent)
    brandDivider:SetPoint("TOPLEFT", 16, -72)
    brandDivider:SetPoint("TOPRIGHT", -16, -72)

    local adHocAction = LV.Widgets:Button(nav, "Ad Hoc", 86, 28, function()
        self:ToggleAdHocPanel()
    end, "primary")
    adHocAction:SetPoint("TOPLEFT", 18, -136)
    LV.Widgets:SetTooltip(adHocAction, "Configure and start an ad hoc raid.")

    local extendAction = LV.Widgets:Button(nav, "Extend Last", 92, 28, function()
        local extended = LV.Raid:ExtendMostRecentSession(tonumber(self.adHocHours) or 3)
        if extended then
            self.currentTab = "attendance"
            self.attendanceSelectedRaid = extended.id
            self.editingRaidID = nil
            self:Refresh()
        end
    end)
    extendAction:SetPoint("LEFT", adHocAction, "RIGHT", 6, 0)
    LV.Widgets:SetTooltip(extendAction, "Reactivate and extend the most recent raid.")

    local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", -1, 1)
    content:SetFrameLevel(frame:GetFrameLevel() + 10)
    content._lvTrackDirect = true
    LV.Widgets:ApplyBackdrop(content, LV.Widgets.colors.canvas, LV.Widgets.colors.border)

    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(84)
    header._lvPersistent = true

    local pageTitle = LV.Widgets:Text(header, "Configuration", "large")
    pageTitle:SetPoint("TOPLEFT", 24, -18)
    local pageHint = LV.Widgets:Text(header, pageDefinitions.config.hint)
    pageHint:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -7)
    pageHint:SetWidth(700)
    pageHint:SetWordWrap(false)
    pageHint:SetTextColor(unpack(LV.Widgets.colors.muted))
    local headerDivider = LV.Widgets:Line(header, 1, LV.Widgets.colors.borderStrong)
    headerDivider:SetPoint("BOTTOMLEFT")
    headerDivider:SetPoint("BOTTOMRIGHT")

    local close = LV.Widgets:Button(header, "x", 28, 28, function()
        frame:Hide()
    end, "ghost")
    close:SetPoint("TOPRIGHT", -14, -14)

    local footerLine = LV.Widgets:Line(nav, 1, LV.Widgets.colors.border)
    footerLine:SetPoint("BOTTOMLEFT", 16, 44)
    footerLine:SetPoint("BOTTOMRIGHT", -16, 44)
    local footer = LV.Widgets:Text(nav, "v" .. tostring(addonVersion() or ""))
    footer:SetPoint("BOTTOMLEFT", 18, 16)
    footer:SetTextColor(unpack(LV.Widgets.colors.textSecondary))

    local raidNavHeader = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidNavHeader:SetText("Raids")
    raidNavHeader:SetTextColor(unpack(LV.Widgets.colors.navigation))
    raidNavHeader:SetJustifyH("LEFT")
    local dungeonNavHeader = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dungeonNavHeader:SetText("Dungeons")
    dungeonNavHeader:SetTextColor(unpack(LV.Widgets.colors.navigation))
    dungeonNavHeader:SetJustifyH("LEFT")

    local resizeHandle = LV.Widgets:Button(frame, "//", 24, 24, nil, "ghost")
    resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 80)
    resizeHandle:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" or (InCombatLockdown and InCombatLockdown()) then
            return
        end
        frame.isResizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        if not frame.isResizing then
            return
        end
        frame:StopMovingOrSizing()
        frame.isResizing = false
        state.width = math.floor(frame:GetWidth() + 0.5)
        state.height = math.floor(frame:GetHeight() + 0.5)
        self:Refresh()
    end)

    self.frame = frame
    self.nav = nav
    self.content = content
    self.pageTitle = pageTitle
    self.pageHint = pageHint
    self.currentTab = "attendance"
    self.navButtons = {}
    self.adHocAction = adHocAction
    self.extendAction = extendAction
    self.raidNavHeader = raidNavHeader
    self.dungeonNavHeader = dungeonNavHeader

    for index, key in ipairs(pageOrder) do
        self:BuildNavButton(key, pageDefinitions[key], index)
    end
    self:RebuildContextSelector()
    self:RefreshNavigation()

    frame:SetScript("OnSizeChanged", function(_, width, height)
        state.width = math.floor((tonumber(width) or frame:GetWidth()) + 0.5)
        state.height = math.floor((tonumber(height) or frame:GetHeight()) + 0.5)
    end)
end

function LV.UI:BuildNavButton(tab, definition, index)
    local button = LV.Widgets:NavigationButton(self.nav, definition.label, definition.icon, SIDEBAR_WIDTH - 36, 36, function()
        self:SwitchTab(tab)
    end)
    self.navButtons[tab] = button
end

function LV.UI:RefreshNavigation()
    local dungeonEnabled = LV.Store:AccountConfig().dungeonLogging == true
    if self.currentTab == "dungeonHistory" and not dungeonEnabled then
        self.currentTab = "history"
        self:SetContextValue("raid:" .. self:SelectedSeasonFilter())
    end

    local visibleOrder = { "config", "attendance", "meter", "history", "sync" }
    if dungeonEnabled then
        table.insert(visibleOrder, 5, "dungeonHistory")
    end
    local visible = {}
    for _, key in ipairs(visibleOrder) do
        visible[key] = true
    end
    for key, button in pairs(self.navButtons or {}) do
        button:SetShown(visible[key] == true)
    end

    local positions = {
        config = -180,
        attendance = -242,
        meter = -284,
        history = -326,
        dungeonHistory = -390,
    }
    for key, y in pairs(positions) do
        local button = self.navButtons[key]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 18, y)
    end

    local sync = self.navButtons.sync
    sync:ClearAllPoints()
    sync:SetPoint("BOTTOMLEFT", 18, 54)

    self.raidNavHeader:ClearAllPoints()
    self.raidNavHeader:SetPoint("TOPLEFT", 22, -226)
    self.raidNavHeader:Show()
    self.dungeonNavHeader:ClearAllPoints()
    self.dungeonNavHeader:SetPoint("TOPLEFT", 22, -374)
    self.dungeonNavHeader:SetShown(dungeonEnabled)
end

function LV.UI:ShowTextEntryDialog(options)
    options = options or {}
    local layer = self.textEntryModal
    if not layer then
        layer = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
        layer:SetAllPoints(self.frame)
        layer:SetFrameStrata("FULLSCREEN_DIALOG")
        layer:SetFrameLevel(self.frame:GetFrameLevel() + 400)
        layer:SetToplevel(true)
        layer:EnableMouse(true)
        LV.Widgets:ApplyBackdrop(layer, LV.Widgets.colors.overlay, LV.Widgets.colors.transparent)

        local dialog = CreateFrame("Frame", nil, layer, "BackdropTemplate")
        dialog:SetSize(430, 184)
        dialog:SetPoint("CENTER")
        dialog:SetFrameLevel(layer:GetFrameLevel() + 1)
        dialog:EnableMouse(true)
        LV.Widgets:ApplyBackdrop(dialog, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.borderStrong)
        layer.dialog = dialog

        dialog.title = LV.Widgets:Text(dialog, "", "large")
        dialog.title:SetPoint("TOPLEFT", 20, -18)
        dialog.hint = LV.Widgets:Text(dialog, "")
        dialog.hint:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -7)
        dialog.hint:SetWidth(380)
        dialog.hint:SetTextColor(unpack(LV.Widgets.colors.muted))

        dialog.edit = LV.Widgets:EditBox(dialog, 390, 30)
        dialog.edit:SetPoint("TOPLEFT", 20, -82)

        dialog.cancel = LV.Widgets:Button(dialog, "Cancel", 88, 28, function()
            layer:Hide()
        end)
        dialog.cancel:SetPoint("BOTTOMRIGHT", -20, 18)

        dialog.accept = LV.Widgets:Button(dialog, "Add", 100, 28, function()
            local callback = layer.onAccept
            local value = dialog.edit:GetText()
            layer:Hide()
            if callback then
                callback(value)
            end
        end, "success")
        dialog.accept:SetPoint("RIGHT", dialog.cancel, "LEFT", -10, 0)

        local function acceptFromKeyboard()
            dialog.accept:Click()
        end
        dialog.edit:SetScript("OnEnterPressed", acceptFromKeyboard)
        dialog.edit:SetScript("OnEscapePressed", function()
            layer:Hide()
        end)
        layer:Hide()
        self.textEntryModal = layer
    end

    local dialog = layer.dialog
    layer.onAccept = options.onAccept
    dialog.title:SetText(options.title or "Enter Value")
    dialog.hint:SetText(options.hint or "")
    dialog.accept.text:SetText(options.acceptText or "Accept")
    dialog.edit:SetText(options.initialValue or "")
    layer:Show()
    layer:Raise()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if layer:IsShown() then
                dialog.edit:SetFocus()
                dialog.edit:HighlightText()
            end
        end)
    else
        dialog.edit:SetFocus()
        dialog.edit:HighlightText()
    end
end

function LV.UI:ShowConfirmationDialog(options)
    options = options or {}
    local layer = self.confirmationModal
    if not layer then
        layer = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
        layer:SetAllPoints(self.frame)
        layer:SetFrameStrata("FULLSCREEN_DIALOG")
        layer:SetFrameLevel(self.frame:GetFrameLevel() + 410)
        layer:SetToplevel(true)
        layer:EnableMouse(true)
        LV.Widgets:ApplyBackdrop(layer, LV.Widgets.colors.overlay, LV.Widgets.colors.transparent)

        local dialog = CreateFrame("Frame", nil, layer, "BackdropTemplate")
        dialog:SetSize(450, 184)
        dialog:SetPoint("CENTER")
        dialog:SetFrameLevel(layer:GetFrameLevel() + 1)
        dialog:EnableMouse(true)
        LV.Widgets:ApplyBackdrop(dialog, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.borderStrong)
        layer.dialog = dialog

        dialog.title = LV.Widgets:Text(dialog, "", "large")
        dialog.title:SetPoint("TOPLEFT", 20, -18)
        dialog.message = LV.Widgets:Text(dialog, "")
        dialog.message:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -12)
        dialog.message:SetWidth(410)
        dialog.message:SetWordWrap(true)
        dialog.message:SetTextColor(unpack(LV.Widgets.colors.textSecondary))

        dialog.cancel = LV.Widgets:Button(dialog, "Cancel", 88, 28, function()
            layer:Hide()
        end)
        dialog.cancel:SetPoint("BOTTOMRIGHT", -20, 18)

        dialog.accept = LV.Widgets:Button(dialog, "Confirm", 104, 28, function()
            local callback = layer.onAccept
            layer:Hide()
            if callback then
                callback()
            end
        end, "danger")
        dialog.accept:SetPoint("RIGHT", dialog.cancel, "LEFT", -10, 0)
        layer:Hide()
        self.confirmationModal = layer
    end

    local dialog = layer.dialog
    layer.onAccept = options.onAccept
    dialog.title:SetText(options.title or "Confirm")
    dialog.message:SetText(options.message or "Are you sure?")
    dialog.accept.text:SetText(options.acceptText or "Confirm")
    LV.Widgets:SetButtonStyle(dialog.accept, options.acceptStyle or "danger")
    layer:Show()
    layer:Raise()
end

function LV.UI:PromptRaidTeamSelection(teams, onSelect)
    teams = teams or {}
    if #teams == 0 then
        return
    end
    if self.raidTeamSelectionModal then
        self.raidTeamSelectionModal:Hide()
    end

    local layer = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    layer:SetAllPoints(UIParent)
    layer:SetFrameStrata("FULLSCREEN_DIALOG")
    layer:SetFrameLevel(500)
    layer:SetToplevel(true)
    layer:EnableMouse(true)
    LV.Widgets:ApplyBackdrop(layer, LV.Widgets.colors.overlay, LV.Widgets.colors.transparent)

    local modal = CreateFrame("Frame", nil, layer, "BackdropTemplate")
    modal:SetSize(430, 108 + (#teams * 36))
    modal:SetPoint("CENTER")
    modal:SetFrameLevel(layer:GetFrameLevel() + 1)
    modal:EnableMouse(true)
    LV.Widgets:ApplyBackdrop(modal, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.borderStrong)

    local title = LV.Widgets:Text(modal, "Choose Raid Team", "large")
    title:SetPoint("TOPLEFT", 20, -18)
    local message = LV.Widgets:Text(modal, "Multiple raid teams are active now. Which team is this raid?")
    message:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    message:SetTextColor(unpack(LV.Widgets.colors.textSecondary))

    local y = -66
    for _, team in ipairs(teams) do
        local teamID = team.id
        local label = LV.Util:Trim(team.name) ~= "" and team.name or teamID
        local button = LV.Widgets:Button(modal, label, 390, 28, function()
            layer:Hide()
            if onSelect then
                onSelect(teamID)
            end
        end, "primary")
        button:SetPoint("TOPLEFT", 20, y)
        y = y - 36
    end

    local cancel = LV.Widgets:Button(modal, "Cancel", 88, 26, function()
        layer:Hide()
    end, "ghost")
    cancel:SetPoint("BOTTOMRIGHT", -20, 14)
    self.raidTeamSelectionModal = layer
    layer:Show()
    layer:Raise()
end

function LV.UI:ToggleAdHocPanel()
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo then
        LV:Print("Select stored guild data or log into a guilded character before starting an ad hoc raid.")
        return
    end

    if self.adHocPanel and self.adHocPanel.guildKey == guildInfo.key then
        self.adHocPanel:SetShown(not self.adHocPanel:IsShown())
        return
    elseif self.adHocPanel then
        self.adHocPanel:Hide()
    end

    local cfg = LV.Store:GetConfig(guildInfo.key)
    local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    panel:SetSize(390, 118)
    panel:SetPoint("TOPLEFT", self.nav, "TOPRIGHT", 8, -82)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(self.frame:GetFrameLevel() + 100)
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel.guildKey = guildInfo.key
    LV.Widgets:ApplyBackdrop(panel, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.borderStrong)

    local title = LV.Widgets:Text(panel, "Start Ad Hoc Raid", "large")
    title:SetPoint("TOPLEFT", 16, -14)
    local close = LV.Widgets:Button(panel, "x", 24, 24, function()
        panel:Hide()
    end, "ghost")
    close:SetPoint("TOPRIGHT", -8, -8)

    local teamLabel = LV.Widgets:Label(panel, "Raid Team")
    teamLabel:SetPoint("TOPLEFT", 16, -58)
    local selectedTeamID = self.adHocTeamID or cfg.selectedTeam or "main"
    local team = LV.Widgets:Dropdown(panel, self:TeamValues(cfg), function()
        return selectedTeamID
    end, function(value)
        selectedTeamID = value
        self.adHocTeamID = value
    end, 120)
    team:SetPoint("TOPLEFT", 16, -78)

    local durationLabel = LV.Widgets:Label(panel, "Hours")
    durationLabel:SetPoint("TOPLEFT", 156, -58)
    local duration = LV.Widgets:EditBox(panel, 58, 28, function(value)
        self.adHocHours = tonumber(value) or 3
    end)
    duration:SetText(tostring(self.adHocHours or 3))
    duration:SetPoint("TOPLEFT", 156, -78)

    local start = LV.Widgets:Button(panel, "Start Raid", 110, 28, function()
        local hours = tonumber(duration:GetText()) or tonumber(self.adHocHours) or 3
        self.adHocHours = hours
        self.adHocTeamID = selectedTeamID
        local started = LV.Raid:StartAdHocSession(selectedTeamID, hours)
        if started then
            self.currentTab = "attendance"
            self.attendanceSelectedRaid = started.id
            self.editingRaidID = nil
            panel:Hide()
            self:Refresh()
        end
    end, "success")
    start:SetPoint("TOPRIGHT", -16, -78)

    self.adHocPanel = panel
    panel:Show()
end

function LV.UI:SwitchTab(tab)
    if tab == "config" and type(self.RenderConfig) ~= "function" then
        LV.OptionsLoader:Run(function()
            self.currentTab = "config"
            self:Refresh()
        end)
        return
    end
    local definition = pageDefinitions[tab]
    if definition and definition.context then
        self:SetContextValue(definition.context .. ":" .. self:SelectedSeasonFilter())
    end
    self.currentTab = tab
    self:Refresh()
end

function LV.UI:OpenConfiguration()
    self:Ensure()
    self:ResetSeasonOnOpen()
    self.frame:Show()
    self:SwitchTab("config")
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
        if not child._lvPersistent then
            child:Hide()
        end
    end
end

function LV.UI:SetPageHeader(title, hint, guildInfo)
    self.pageTitle:SetText(title or "LootViewer")
    local detail = hint or ""
    if guildInfo then
        detail = detail .. "  " .. guildInfo.name .. " - " .. guildInfo.realm
        if guildInfo.override then
            detail = detail .. " (session override)"
        end
    end
    self.pageHint:SetText(detail)
end

function LV.UI:Refresh()
    self:Ensure()
    if not self.frame:IsShown() then
        return
    end

    self:RefreshNavigation()
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
    elseif self.currentTab == "history" or self.currentTab == "dungeonHistory" then
        self:RenderHistory()
    elseif type(self.RenderConfig) == "function" then
        self:RenderConfig()
    else
        self:SetPageHeader("Configuration", "Loading the on-demand options panel...")
    end
end

function LV.UI:CurrentGuildOrMessage()
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo then
        self:SetPageHeader("LootViewer", "No guild data is currently selected.")
        local text = LV.Widgets:Text(self.content, "LootViewer configuration is guild-scoped. Log into a guilded character to configure tracking.")
        text:SetPoint("TOPLEFT", 24, -112)
        return nil
    end
    LV.Store:GuildRecord(guildInfo.key)
    return guildInfo
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

function LV.UI:TeamValues(cfg)
    local values = {}
    for _, team in ipairs((cfg and cfg.teams) or {}) do
        values[#values + 1] = { value = team.id, label = team.name }
    end
    if #values == 0 then
        values[1] = { value = "main", label = "Main" }
    end
    values[#values + 1] = { value = LV.Constants.PUG_TEAM_ID, label = LV.Constants.PUG_TEAM_NAME }
    return values
end

function LV.UI:MeterTeamValues(cfg)
    local values = {
        { value = "all", label = "All Teams" },
    }
    for _, team in ipairs((cfg and cfg.teams) or {}) do
        values[#values + 1] = { value = team.id, label = team.name }
    end
    values[#values + 1] = { value = LV.Constants.PUG_TEAM_ID, label = LV.Constants.PUG_TEAM_NAME }
    return values
end

function LV.UI:RaidTagValues(cfg)
    local values = self:MeterTeamValues(cfg)
    values[1].label = "All Raid Tags"
    return values
end

function LV.UI:IsValidRaidTag(values, teamID)
    for _, item in ipairs(values or {}) do
        if item.value == teamID then
            return true
        end
    end
    return false
end

function LV.UI:RaidMatchesTag(raid, teamID)
    return teamID == nil or teamID == "all"
        or (type(raid) == "table" and tostring(raid.team or "main") == tostring(teamID))
end

function LV.UI:EventMatchesRaidTag(record, row, teamID)
    if teamID == nil or teamID == "all" then
        return true
    end
    local raid = type(record) == "table" and type(record.r) == "table" and row and row.sid and record.r[row.sid]
    return self:RaidMatchesTag(raid, teamID)
end

function LV.UI:CanModifyHistoricalRaid(raidID, raid)
    return type(raid) == "table" and (
        LV.Store:IsGlobalPugTeam(raid.team)
        or tostring(self.pugEditRaidID or "") == tostring(raidID or "")
        or LV.Guild:CanModifySession()
    )
end

function LV.UI:DeleteRaid(guildKey, raidID)
    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and raidID and record.r[raidID]
    if type(raid) ~= "table" then
        return
    end
    if not self:CanModifyHistoricalRaid(raidID, raid) then
        LV:Print("Your current LootViewer authority settings do not allow raid deletion.")
        return
    end

    if record.cur == raidID then
        record.cur = nil
    end
    record.r[raidID] = nil
    self.attendanceSelectedRaid = nil
    self.editingRaidID = nil
    self.pugEditRaidID = nil
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
    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and record.r and record.r[raidID]
    if type(raid) ~= "table" then
        return false
    end
    if not self:CanModifyHistoricalRaid(raidID, raid) then
        LV:Print("Your current LootViewer authority settings do not allow attendance changes.")
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

    raid.lastBy = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    raid.lastSource = "ui_edit"
    return true
end

function LV.UI:RemoveHistoricalRaidAttendance(guildKey, raidID, nameID, status)
    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and record.r and record.r[raidID]
    nameID = tonumber(nameID)
    if type(raid) ~= "table" or not nameID then
        return false
    end
    if not self:CanModifyHistoricalRaid(raidID, raid) then
        LV:Print("Your current LootViewer authority settings do not allow attendance changes.")
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

    raid.lastBy = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    raid.lastSource = "ui_edit"
    return true
end

function LV.UI:MoveHistoricalRaidToTeam(guildKey, raidID, teamID)
    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and record.r and record.r[raidID]
    local team = record and LV.Store:GetTeamByID(record, teamID)
    if type(raid) ~= "table" or type(team) ~= "table" then
        return false
    end
    if not self:CanModifyHistoricalRaid(raidID, raid) then
        LV:Print("Your current LootViewer authority settings do not allow raid-team changes.")
        return false
    end
    if tostring(raid.team or "main") == tostring(team.id) then
        return true
    end

    local previousName = self:RaidTeamName(guildKey, raid)
    raid.team = team.id
    raid.tn = LV.Store:StringID(guildKey, team.name)
    raid.lastBy = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    raid.lastSource = "ui_team_move"
    if self.attendanceTeamID and self.attendanceTeamID ~= "all" then
        self.attendanceTeamID = team.id
    end
    LV:Print("Moved raid from " .. tostring(previousName) .. " to " .. tostring(team.name)
        .. ". Attendance, kills, loot, and trades remain linked.")
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

function LV.UI:AttendanceRows(guildKey, record, seasonFilter, teamID)
    local rows = {}
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table"
            and LV.Seasons:RaidMatchesFilter(guildKey, raid, seasonFilter)
            and self:RaidMatchesTag(raid, teamID) then
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

function LV.UI:AttendanceMeterRows(guildKey, record, range, teamID, showPugs)
    local players = {}
    local raidRows = {}
    local groupedByRaid = {}

    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table"
            and LV.Seasons:RaidMatchesRange(guildKey, raid, range, self:SelectedSeasonFilter())
            and (teamID == "all" or raid.team == teamID) then
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
    self.attendanceSeason = self:SelectedSeasonFilter()
    local tagValues = self:RaidTagValues(cfg)
    self.attendanceTeamID = self.attendanceTeamID or "all"
    if not self:IsValidRaidTag(tagValues, self.attendanceTeamID) then
        self.attendanceTeamID = "all"
    end
    local session = LV.Raid:GetActiveSession()
    local statusText = "No active raid"
    if session then
        statusText = "Tracking " .. (self:RaidTeamName(guildInfo.key, session) or "Raid")
        if session.adhoc then
            statusText = statusText .. " ad hoc"
        end
    end
    self:SetPageHeader("Raid History", statusText .. ". " .. pageDefinitions.attendance.hint, guildInfo)

    if session then
        local stop = LV.Widgets:Button(self.content, "Stop Raid", 100, 28, function()
            LV.Raid:EndSession("ui")
        end, "danger")
        stop:SetPoint("TOPRIGHT", -24, -96)
    end

    local tagLabel = LV.Widgets:Label(self.content, "Raid Tag")
    tagLabel:SetPoint("TOPLEFT", 24, -109)
    local tag = LV.Widgets:Dropdown(self.content, tagValues, function()
        return self.attendanceTeamID
    end, function(value)
        self.attendanceTeamID = value
        self.attendanceSelectedRaid = nil
        self.attendanceOffset = 0
        self.attendanceDetailOffset = 0
        self.editingRaidID = nil
        self.pugEditRaidID = nil
        self:Refresh()
    end, 170)
    tag:SetPoint("LEFT", tagLabel, "RIGHT", 12, -1)

    local summary = LV.Widgets:Section(self.content, "Raid Nights", 248)
    summary:SetPoint("TOPLEFT", 22, -146)
    summary:SetPoint("RIGHT", -22, 0)
    self:RenderAttendanceHistory(summary, guildInfo.key, record)

    local detail = LV.Widgets:Section(self.content, "Attendance Detail", 220)
    detail:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -18)
    detail:SetPoint("BOTTOMRIGHT", -22, 22)
    self:RenderAttendanceDetail(detail, guildInfo.key, record)
end

function LV.UI:RenderAttendanceHistory(parent, guildKey, record)
    local rows = self:AttendanceRows(guildKey, record, self.attendanceSeason, self.attendanceTeamID)
    self.attendanceOffset = tonumber(self.attendanceOffset) or 0
    if self.attendanceOffset >= #rows then
        self.attendanceOffset = math.max(0, #rows - ATTENDANCE_PAGE_SIZE)
    end
    local selectedVisible = false
    for _, row in ipairs(rows) do
        if tostring(row.id) == tostring(self.attendanceSelectedRaid) then
            selectedVisible = true
            break
        end
    end
    if not selectedVisible and rows[1] then
        local activeRaidID = nil
        for _, row in ipairs(rows) do
            if record.cur and tostring(row.id) == tostring(record.cur) then
                activeRaidID = row.id
                break
            end
        end
        self.attendanceSelectedRaid = activeRaidID or rows[1].id
        self.attendanceDetailOffset = 0
        for index, row in ipairs(rows) do
            if tostring(row.id) == tostring(self.attendanceSelectedRaid) then
                self.attendanceOffset = math.floor((index - 1) / ATTENDANCE_PAGE_SIZE) * ATTENDANCE_PAGE_SIZE
                break
            end
        end
    elseif #rows == 0 then
        self.attendanceSelectedRaid = nil
        self.editingRaidID = nil
        self.pugEditRaidID = nil
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
        { "Standby", 266 },
        { "Late", 322 },
        { "Out", 374 },
        { "NoShow", 426 },
        { "Kills", 498 },
        { "Type", 540 },
        { "Options", 596 },
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
            if tostring(self.editingRaidID or "") ~= tostring(row.id) then
                self.editingRaidID = nil
                self.pugEditRaidID = nil
            end
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
        local edit = LV.Widgets:IconButton(rowButton, "edit", 26, 20, function()
            if not self:CanModifyHistoricalRaid(row.id, raid) then
                LV:Print("Your current LootViewer authority settings do not allow attendance changes.")
                return
            end
            self.attendanceSelectedRaid = row.id
            self.attendanceDetailOffset = 0
            if self.editingRaidID == row.id then
                self.editingRaidID = nil
                self.pugEditRaidID = nil
            else
                self.editingRaidID = row.id
                self.pugEditRaidID = LV.Store:IsGlobalPugTeam(raid.team) and row.id or nil
            end
            self:Refresh()
        end)
        edit:SetPoint("RIGHT", -36, 0)
        LV.Widgets:SetTooltip(edit, "Edit player attendance for this raid night.")
        local delete = LV.Widgets:IconButton(rowButton, "trash", 26, 20, function()
            local raidLabel = date("%m/%d/%y %H:%M", tonumber(raid.st) or 0)
                .. " " .. self:RaidTeamName(guildKey, raid)
            self:ShowConfirmationDialog({
                title = "Delete Raid Attendance?",
                message = "Delete the attendance record for " .. raidLabel
                    .. "? Loot and trade history will be kept.",
                acceptText = "Delete",
                onAccept = function()
                    self:DeleteRaid(guildKey, row.id)
                end,
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
            self.pugEditRaidID = nil
            self:Refresh()
        end)
        done:SetPoint("TOPRIGHT", -24, -44)
    end

    local ended = tonumber(raid.en) or tonumber(raid.st) or 0
    local duration = math.max(0, math.floor((ended - (tonumber(raid.st) or ended)) / 60))
    local meta = LV.Widgets:Text(parent, tostring(duration) .. " min  " .. tostring(#(raid.kills or {})) .. " boss kill(s)")
    meta:SetTextColor(unpack(LV.Widgets.colors.muted))
    meta:SetPoint("TOPLEFT", 24, -72)

    local scrollTop = -98
    if editMode then
        local teamLabel = LV.Widgets:Label(parent, "Raid Team")
        teamLabel:SetPoint("TOPLEFT", 24, -102)
        local teamValues = self:TeamValues(record.cfg)
        local currentTeamID = raid.team or "main"
        if not self:IsValidRaidTag(teamValues, currentTeamID) then
            currentTeamID = teamValues[1] and teamValues[1].value or "main"
        end
        local team = LV.Widgets:Dropdown(parent, teamValues, function()
            return currentTeamID
        end, function(value)
            if self:MoveHistoricalRaidToTeam(guildKey, self.attendanceSelectedRaid, value) then
                currentTeamID = value
                self:Refresh()
            end
        end, 180)
        team:SetPoint("LEFT", teamLabel, "RIGHT", 12, 0)
        LV.Widgets:SetTooltip(team, "Move this raid session and all linked attendance, kills, loot, and trades to another raid team.")

        local addLabel = LV.Widgets:Label(parent, "Add Player")
        addLabel:SetPoint("TOPLEFT", 24, -138)

        local nameEdit = LV.Widgets:EditBox(parent, 160, 24, function(value)
            self.raidEditName = value
        end)
        nameEdit:SetText(self.raidEditName or "")
        nameEdit:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)

        local previous = nameEdit
        for _, option in ipairs(attendanceStatusValues) do
            local optionValue = option.value
            local optionLabel = option.label
            local width = option.value == "noshow" and 72 or option.value == "bench" and 72 or 54
            local addButton = LV.Widgets:Button(parent, optionLabel, width, 24, function()
                local value = nameEdit:GetText()
                if self:SetHistoricalRaidAttendance(guildKey, self.attendanceSelectedRaid, value, optionValue) then
                    self.raidEditName = ""
                    self:Refresh()
                end
            end)
            addButton:SetPoint("LEFT", previous, "RIGHT", 8, 0)
            LV.Widgets:SetTooltip(addButton, "Add player to " .. optionLabel .. ".")
            previous = addButton
        end
        scrollTop = -174
    end

    local hereMap = self:ExclusiveHereMap(raid)
    local sections = {
        { "Here", "here", hereMap },
        { "Standby", "bench", raid.b },
        { "Late", "late", raid.late },
        { "Out", "out", raid.out },
        { "NoShow", "noshow", raid.noshow },
    }

    local scroll, scrollContent = LV.Widgets:ScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 12, scrollTop)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    scroll:HookScript("OnVerticalScroll", function(selfScroll)
        self.attendanceDetailScroll = selfScroll:GetVerticalScroll()
    end)

    local availableWidth = math.max(560, (tonumber(parent:GetWidth()) or 700) - 54)
    local columnCount = math.max(2, math.min(6, math.floor(availableWidth / 150)))
    local cellWidth = math.floor(availableWidth / columnCount)
    local sectionY = 0

    local zones = {}
    local seenZones = {}
    local bosses = {}
    local seenBosses = {}
    local function addUnique(target, seen, value)
        value = LV.Util:Trim(value)
        if value ~= "" and not seen[value] then
            seen[value] = true
            target[#target + 1] = value
        end
    end
    local function addRaidZone(instanceID, nameID)
        local name = LV.Store:DictionaryValue(guildKey, "s", nameID)
        if LV.Seasons:IsKnownRaid(instanceID, name) then
            addUnique(zones, seenZones, name)
        end
    end
    addRaidZone(raid.iid, raid.z)
    for _, row in ipairs(record.l or {}) do
        if type(row) == "table" and tostring(row.sid or "") == tostring(raid.id or self.attendanceSelectedRaid) then
            addRaidZone(row.iid, row.inst)
        end
    end
    for _, kill in ipairs(raid.kills or {}) do
        if type(kill) == "table" then
            addUnique(bosses, seenBosses, LV.Store:DictionaryValue(guildKey, "s", kill.b))
        end
    end

    local raidInfo = LV.Widgets:Section(scrollContent, "Raid Information", 88)
    raidInfo:SetPoint("TOPLEFT", 0, sectionY)
    raidInfo:SetPoint("RIGHT", 0, 0)
    local zoneLabel = LV.Widgets:Label(raidInfo, "Zone(s)")
    zoneLabel:SetPoint("TOPLEFT", 12, -38)
    zoneLabel:SetWidth(105)
    local zoneText = LV.Widgets:Text(raidInfo, #zones > 0 and table.concat(zones, ", ") or "Not recorded")
    zoneText:SetPoint("TOPLEFT", 120, -38)
    zoneText:SetWidth(math.max(300, availableWidth - 138))
    zoneText:SetWordWrap(false)
    local bossLabel = LV.Widgets:Label(raidInfo, "Bosses Killed")
    bossLabel:SetPoint("TOPLEFT", 12, -62)
    bossLabel:SetWidth(105)
    local bossText = LV.Widgets:Text(raidInfo, #bosses > 0 and table.concat(bosses, ", ") or "None recorded")
    bossText:SetPoint("TOPLEFT", 120, -62)
    bossText:SetWidth(math.max(300, availableWidth - 138))
    bossText:SetWordWrap(false)
    sectionY = sectionY - 100

    for _, definition in ipairs(sections) do
        local label, statusKey, statusMap = definition[1], definition[2], definition[3]
        local names = self:AttendanceNames(guildKey, statusMap)
        local rowCount = math.max(1, math.ceil(#names / columnCount))
        local sectionHeight = 38 + (rowCount * 26) + 6
        local section = LV.Widgets:Section(scrollContent, label .. " (" .. tostring(#names) .. ")", sectionHeight)
        section:SetPoint("TOPLEFT", 0, sectionY)
        section:SetPoint("RIGHT", 0, 0)

        if #names == 0 then
            local empty = LV.Widgets:Text(section, "No players")
            empty:SetPoint("TOPLEFT", 8, -40)
            empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        end

        for index, entry in ipairs(names) do
            local entryID = entry.id
            local entryName = entry.name
            local entryStatus = statusKey
            local entrySectionLabel = label
            local column = (index - 1) % columnCount
            local row = math.floor((index - 1) / columnCount)
            local cell = CreateFrame("Button", nil, section, "BackdropTemplate")
            cell:SetPoint("TOPLEFT", 4 + (column * cellWidth), -36 - (row * 26))
            cell:SetSize(cellWidth - 8, 22)
            local rowColor = row % 2 == 0 and LV.Widgets.colors.surface or LV.Widgets.colors.canvasAlt
            LV.Widgets:ApplyBackdrop(cell, rowColor, LV.Widgets.colors.transparent)
            cell:SetScript("OnClick", function()
                self:ShowPlayerDetailForName(guildKey, entryID)
            end)
            local text = LV.Widgets:Text(cell, entryName)
            text:SetPoint("LEFT", 7, 0)
            text:SetWidth(cellWidth - (editMode and 40 or 16))
            text:SetWordWrap(false)
            self:SetNameClassColor(text, guildKey, entryID)
            cell:SetScript("OnEnter", function()
                cell:SetBackdropColor(unpack(LV.Widgets.colors.surfaceHover))
                text:SetTextColor(unpack(LV.Widgets.colors.text))
            end)
            cell:SetScript("OnLeave", function()
                cell:SetBackdropColor(unpack(rowColor))
                self:SetNameClassColor(text, guildKey, entryID)
            end)

            if editMode then
                local remove = LV.Widgets:IconButton(cell, "trash", 20, 18, function()
                    if self:RemoveHistoricalRaidAttendance(guildKey, self.attendanceSelectedRaid, entryID, entryStatus) then
                        self:Refresh()
                    end
                end)
                remove:SetPoint("RIGHT", -2, 0)
                LV.Widgets:SetTooltip(remove, "Remove " .. entryName .. " from " .. entrySectionLabel .. ".")
            end
        end

        sectionY = sectionY - sectionHeight - 12
    end

    scrollContent:SetHeight(math.max(1, -sectionY))
    scroll:SetVerticalScroll(math.max(0, math.min(tonumber(self.attendanceDetailScroll) or 0, scroll:GetVerticalScrollRange())))
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
        return "Standby"
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
    local rows, _, raidCount = self:AttendanceMeterRows(guildKey, record, self.meterRange or "months:3", self.meterTeamID or "all", self.meterShowPugs)
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
        { range = self.meterRange or "months:3", team = self.meterTeamID or "all" },
        { range = "all", team = "all" },
    }

    for _, search in ipairs(searches) do
        local rows, _, raidCount = self:AttendanceMeterRows(guildKey, record, search.range, search.team, true)
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

    self:DrawMeterDetailLegend(frame, "Here / Standby", detailStatusColors.here, 24, -166)
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
    local rangeValues = LV.Seasons:MeterRangeValues()
    self.meterRange = self.meterRange or "months:3"
    if not containsValue(rangeValues, self.meterRange) then
        self.meterRange = "months:3"
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
    local pugsSelected = self.meterTeamID == LV.Constants.PUG_TEAM_ID
    if pugsSelected then
        self.meterShowPugs = true
    end

    self:SetPageHeader("Attendance Meter", pageDefinitions.meter.hint, guildInfo)

    local showPugs = LV.Widgets:Check(self.content, "Show Pugs", function(value)
        self.meterShowPugs = value
        self:Refresh()
    end)
    showPugs:SetPoint("TOPLEFT", 24, -106)
    showPugs:SetChecked(self.meterShowPugs)
    if pugsSelected then
        showPugs:SetEnabled(false)
        showPugs.label:SetTextColor(unpack(LV.Widgets.colors.muted))
        LV.Widgets:SetTooltip(showPugs, "Pugs are always included when the Pugs raid tag is selected.")
    end

    local rangeLabel = LV.Widgets:Label(self.content, "Stats Range")
    rangeLabel:SetPoint("TOPLEFT", 210, -109)
    local range = LV.Widgets:Dropdown(self.content, rangeValues, function()
        return self.meterRange
    end, function(value)
        self.meterRange = value
        self.meterScroll = 0
        self:Refresh()
    end, 190)
    range:SetPoint("LEFT", rangeLabel, "RIGHT", 10, -1)

    local teamLabel = LV.Widgets:Label(self.content, "Raid Tag")
    teamLabel:SetPoint("LEFT", range, "RIGHT", 22, 1)
    local team = LV.Widgets:Dropdown(self.content, teamValues, function()
        return self.meterTeamID
    end, function(value)
        self.meterTeamID = value
        if value == LV.Constants.PUG_TEAM_ID then
            self.meterShowPugs = true
        end
        self:Refresh()
    end, 118)
    team:SetPoint("LEFT", teamLabel, "RIGHT", 10, -1)

    local panel = LV.Widgets:Section(self.content, "Attendance", 520)
    panel:SetPoint("TOPLEFT", 22, -146)
    panel:SetPoint("BOTTOMRIGHT", -22, 22)

    local rows, maxTotal, raidCount, guildRows, pugRows = self:AttendanceMeterRows(guildInfo.key, record, self.meterRange, self.meterTeamID, self.meterShowPugs)
    local displayRows = self:MeterDisplayRows(guildRows, pugRows, self.meterShowPugs)

    local countText
    if self.meterShowPugs then
        countText = tostring(#(guildRows or {})) .. " guild player(s), " .. tostring(#(pugRows or {})) .. " pug(s), " .. tostring(raidCount) .. " raid(s)"
    else
        countText = tostring(#rows) .. " player(s), " .. tostring(raidCount) .. " raid(s)"
    end
    local count = LV.Widgets:Text(panel.header, countText)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    count:SetPoint("RIGHT", -18, 0)

    self:DrawMeterLegend(panel, "Here / Standby", meterColors.here, 24, -46)
    self:DrawMeterLegend(panel, "Late", meterColors.late, 150, -46)
    self:DrawMeterLegend(panel, "Posted Out", meterColors.out, 218, -46)
    self:DrawMeterLegend(panel, "NoShow", meterColors.noshow, 334, -46)

    local availableWidth = math.max(650, (tonumber(panel:GetWidth()) or 720) - 60)
    local barWidth = math.max(320, availableWidth - 220)
    local percentX = 146 + barWidth + 20
    local headerName = LV.Widgets:Label(panel, "Player")
    headerName:SetPoint("TOPLEFT", 24, -76)
    local headerBar = LV.Widgets:Label(panel, "Attendance")
    headerBar:SetPoint("TOPLEFT", 146, -76)
    local headerRaids = LV.Widgets:Label(panel, "Attend")
    headerRaids:SetPoint("TOPLEFT", percentX, -76)

    if raidCount == 0 or #rows == 0 then
        local empty = LV.Widgets:Text(panel, "No marked raid attendance in this window.")
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, -110)
        return
    end

    local scroll, scrollContent = LV.Widgets:ScrollFrame(panel)
    scroll:SetPoint("TOPLEFT", 12, -98)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    scroll:HookScript("OnVerticalScroll", function(selfScroll)
        self.meterScroll = selfScroll:GetVerticalScroll()
    end)

    local y = -4
    for _, item in ipairs(displayRows) do
        if item.section then
            local section = LV.Widgets:Label(scrollContent, item.section .. " (" .. tostring(item.count or 0) .. ")")
            section:SetPoint("TOPLEFT", 24, y + 2)
            y = y - 24
        else
            local row = item.row
            local meterRow = row
            local rowBackground = scrollContent:CreateTexture(nil, "BACKGROUND")
            rowBackground:SetPoint("TOPLEFT", 12, y + 4)
            rowBackground:SetPoint("TOPRIGHT", -2, y + 4)
            rowBackground:SetHeight(26)
            local stripe = (math.floor((-y) / 30) % 2 == 0) and LV.Widgets.colors.surface or LV.Widgets.colors.canvasAlt
            rowBackground:SetColorTexture(unpack(stripe))

            local nameButton = CreateFrame("Button", nil, scrollContent)
            nameButton:SetPoint("TOPLEFT", 24, y + 1)
            nameButton:SetSize(108, 18)
            nameButton.text = LV.Widgets:Text(nameButton, meterRow.name)
            nameButton.text:SetPoint("LEFT", 0, 0)
            nameButton.text:SetWidth(108)
            nameButton.text:SetWordWrap(false)
            self:SetNameClassColor(nameButton.text, guildInfo.key, meterRow.id)
            nameButton:SetScript("OnEnter", function()
                nameButton.text:SetTextColor(unpack(LV.Widgets.colors.yellow))
            end)
            nameButton:SetScript("OnLeave", function()
                self:SetNameClassColor(nameButton.text, guildInfo.key, meterRow.id)
            end)
            nameButton:SetScript("OnClick", function()
                self.meterDetailOffset = 0
                self:ShowMeterPlayerDetail(guildInfo.key, meterRow, raidCount)
            end)

            self:DrawMeterBar(scrollContent, meterRow, maxTotal, 146, y, barWidth)

            local raids = LV.Widgets:Text(scrollContent, tostring(self:MeterAttendancePercent(meterRow, raidCount)) .. "%")
            raids:SetPoint("TOPLEFT", percentX, y + 1)
            raids:SetWidth(62)
            raids:SetWordWrap(false)

            y = y - 30
        end
    end
    scrollContent:SetHeight(math.max(1, -y + 8))
    scroll:SetVerticalScroll(math.max(0, math.min(tonumber(self.meterScroll) or 0, scroll:GetVerticalScrollRange())))
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

    local tierToken = LV.Tier and LV.Tier.Token and LV.Tier:Token(itemID)
    local displayName = itemName
        or (tierToken and tierToken.name)
        or tostring(itemKey or ""):match("%[(.-)%]")
        or (itemID > 0 and ("Item " .. tostring(itemID)) or tostring(itemKey or "item"))
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

function LV.UI:LootRollGroup(value)
    value = tostring(value or ""):lower()
    if value == "need" or value == "offspec" then
        return "need"
    elseif value == "greed" then
        return "greed"
    elseif value == "transmog" or value == "tmog" then
        return "transmog"
    end
    return nil
end

function LV.UI:LootRollVisual(value)
    local group = self:LootRollGroup(value)
    return group, group and lootRollVisuals[group] or nil
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

function LV.UI:CreateLootMethodDisplay(parent, guildKey, row, x, y, width, justify, iconOnly)
    local method = self:LootMethodDisplay(row)
    local winnerRoll = self:LootWinnerRoll(row) or (row and row.r)
    local _, rollVisual = self:LootRollVisual(winnerRoll)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", x, y)
    host:SetSize(width, 18)
    host:EnableMouse(true)
    local icon = host:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    if rollVisual and icon.SetAtlas then
        icon:SetAtlas(rollVisual.atlas, false)
    else
        icon:SetTexture(unknownLootRollTexture)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if iconOnly then
        icon:SetPoint("CENTER")
    else
        icon:SetPoint(justify == "RIGHT" and "RIGHT" or "LEFT")
    end
    host.icon = icon
    if not iconOnly then
        local label = LV.Widgets:Text(host, method)
        if justify == "RIGHT" then
            label:SetPoint("RIGHT", -20, 0)
            label:SetJustifyH("RIGHT")
        else
            label:SetPoint("LEFT", 20, 0)
        end
        label:SetWidth(math.max(1, width - 20))
        label:SetWordWrap(false)
    end
    host:SetScript("OnEnter", function()
        GameTooltip:SetOwner(host, "ANCHOR_RIGHT")
        if self:LootBreakdownCount(row) > 0 then
            local color = LV.Widgets.colors.yellow
            GameTooltip:SetText("LootViewer Rolls", color[1], color[2], color[3])
            self:AddLootBreakdownTooltip(guildKey, row, false)
        elseif row and row.src == "bonus" then
            GameTooltip:SetText("Bonus Roll")
        elseif method ~= "" then
            GameTooltip:SetText("Loot roll: " .. method)
        else
            GameTooltip:SetText("No roll details recorded")
        end
        GameTooltip:Show()
    end)
    host:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return host
end

function LV.UI:LootDifficultyAbbrev(guildKey, row)
    local difficulty = self:LootDifficultyDisplay(guildKey, row)
    local value = tostring(difficulty or ""):lower()
    local difficultyID = tonumber(row and row.did) or 0

    if value:find("mythic", 1, true) or difficultyID == 16 or difficultyID == 23 then
        return "M"
    elseif value:find("heroic", 1, true) or difficultyID == 15 then
        return "H"
    elseif value:find("raid finder", 1, true) or value:find("lfr", 1, true)
        or value == "world" or difficultyID == 17 or difficultyID == 250 then
        return "L"
    elseif value:find("normal", 1, true) or difficultyID == 14 then
        return "N"
    end

    return ""
end

function LV.UI:MinimumRaidDifficultyRank()
    return raidDifficultyRankByValue[self.historyMinDifficulty or "lfr"] or 1
end

function LV.UI:RaidDifficultyBuckets()
    local minimum = self:MinimumRaidDifficultyRank()
    local buckets = {}
    for _, definition in ipairs(raidDifficultyThresholds) do
        if definition.rank >= minimum then
            buckets[#buckets + 1] = definition.bucket
        end
    end
    return buckets
end

function LV.UI:EventDifficultyAbbrev(guildKey, record, row)
    local difficulty = self:LootDifficultyAbbrev(guildKey, row)
    if difficulty ~= "" then
        return difficulty
    end

    if row and row.loot then
        for _, loot in ipairs((record and record.l) or {}) do
            if type(loot) == "table" and tostring(loot.id or "") == tostring(row.loot) then
                difficulty = self:LootDifficultyAbbrev(guildKey, loot)
                if difficulty ~= "" then
                    return difficulty
                end
                break
            end
        end
    end

    local raid = type(record) == "table" and type(record.r) == "table" and row and row.sid and record.r[row.sid]
    return type(raid) == "table" and self:LootDifficultyAbbrev(guildKey, raid) or ""
end

function LV.UI:EventMeetsMinimumDifficulty(guildKey, record, row)
    local difficulty = self:EventDifficultyAbbrev(guildKey, record, row)
    local rank = raidDifficultyRankByAbbreviation[difficulty]
    if not rank then
        return self:MinimumRaidDifficultyRank() == 1
    end
    return rank >= self:MinimumRaidDifficultyRank()
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
    local difficultyID = tonumber(row and row.src == "bonus" and row.bdid) or tonumber(row and row.did) or 0
    if row and row.src == "bonus" and difficultyID > 0 then
        return difficultyLabels[difficultyID] or tostring(difficultyID)
    end
    if difficultyID == 250 or tostring(difficulty or ""):lower() == "world" then
        return "Raid Finder"
    end
    if difficulty ~= "" then
        return difficulty
    end
    return difficultyLabels[difficultyID] or (difficultyID > 0 and tostring(difficultyID) or "")
end

function LV.UI:TierHistoryGroups(guildKey, seasonFilter, typeFilter)
    local record = LV.Store:GuildRecord(guildKey)
    local groups = {}
    local total = 0
    local seasonID = LV.Seasons:ResolveFilter(seasonFilter or "current")
    typeFilter = typeFilter or "all"

    for _, definition in ipairs(LV.Tier:Types(seasonID)) do
        groups[definition.id] = {
            definition = definition,
            rows = {},
        }
    end

    for index = #((record and record.l) or {}), 1, -1 do
        local row = record.l[index]
        local token = LV.Tier:TokenForRow(guildKey, row)
        local groupType = token and LV.Tier:GroupTypeForRow(guildKey, row, token) or nil
        if token
            and token.seasonID == seasonID
            and seasonID == LV.Seasons:EventSeasonID(guildKey, record, row)
            and self:EventMatchesRaidTag(record, row, self.historyTeamID)
            and self:EventMeetsMinimumDifficulty(guildKey, record, row)
            and row.src ~= "bonus"
            and not (LV.Loot and LV.Loot.IsWarboundRow and LV.Loot:IsWarboundRow(guildKey, row))
            and (typeFilter == "all" or groupType == typeFilter) then
            local group = groups[groupType]
            if group then
                group.rows[#group.rows + 1] = {
                    loot = row,
                    token = token,
                }
                total = total + 1
            end
        end
    end

    return groups, total, seasonID
end

function LV.UI:LootSearchText(guildKey, row)
    local itemName = self:LootItemDisplay(guildKey, row)
    local player = LV.Store:DictionaryValue(guildKey, "n", row and row.p)
    local record = LV.Store:GuildRecord(guildKey)
    local finalOwner = LV.Store:DictionaryValue(guildKey, "n", self:RaidFinalLootOwner(record, row))
    local itemKey = LV.Store:DictionaryValue(guildKey, "i", row and row.item)
    local parts = {
        date("%m/%d %H:%M", row and row.ts or 0),
        player,
        LV.Util:ShortName(player),
        finalOwner,
        LV.Util:ShortName(finalOwner),
        itemName,
        itemKey,
        self:LootBossDifficultyDisplay(guildKey, row),
        self:LootInstanceDisplay(guildKey, row),
        self:LootDifficultyDisplay(guildKey, row),
        self:LootMethodDisplay(row),
    }
    return table.concat(parts, " "):lower()
end

function LV.UI:CreateHistorySearch(parent, stateKey, x, y)
    local searchText = LV.Util:Trim(self[stateKey] or "")
    local searchLabel = LV.Widgets:Label(parent, "Search")
    searchLabel:SetPoint("TOPLEFT", x or 24, y or -245)

    local function commitSearch(value)
        value = LV.Util:Trim(value or "")
        if value ~= LV.Util:Trim(self[stateKey] or "") then
            self[stateKey] = value
            self.historyOffset = 0
            self:Refresh()
        end
    end

    local search = LV.Widgets:EditBox(parent, 240, 24, commitSearch)
    search:SetText(searchText)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 12, 0)

    local clear = LV.Widgets:Button(parent, "Clear", 58, 24, function()
        self[stateKey] = ""
        self.historyOffset = 0
        search:SetText("")
        search:ClearFocus()
        self:Refresh()
    end)
    clear:SetPoint("LEFT", search, "RIGHT", 8, 0)

    return searchText
end

function LV.UI:FilteredHistoryRows(guildKey, sourceFilter)
    local record = LV.Store:GuildRecord(guildKey)
    local query = LV.Util:Trim(self.historySearch or ""):lower()
    local rows = {}
    local total = 0
    sourceFilter = sourceFilter == "bonus" and "bonus" or "regular"

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        if type(row) == "table" then
            local excluded = LV.Loot and LV.Loot.IsLootItemExcluded and LV.Loot:IsLootItemExcluded(guildKey, row)
            local warbound = LV.Loot and LV.Loot.IsWarboundRow and LV.Loot:IsWarboundRow(guildKey, row)
            local sourceMatches = (row.src == "bonus") == (sourceFilter == "bonus")
            local inSeason = LV.Seasons:EventMatchesFilter(guildKey, record, row, self:SelectedSeasonFilter())
            local inTeam = self:EventMatchesRaidTag(record, row, self.historyTeamID)
            local inDifficulty = self:EventMeetsMinimumDifficulty(guildKey, record, row)
            if inSeason and inTeam and inDifficulty and sourceMatches and not excluded and not warbound then
                total = total + 1
                if query == "" or self:LootSearchText(guildKey, row):find(query, 1, true) then
                    rows[#rows + 1] = row
                end
            end
        end
    end

    return rows, total
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

function LV.UI:CreateHistoryNameButton(parent, guildKey, nameID, x, y, width, nativeScroll, tooltipText)
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
        if tooltipText and tooltipText ~= "" then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        self:SetNameClassColor(button.text, guildKey, nameID)
        if tooltipText and tooltipText ~= "" then
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnClick", function()
        self:ShowPlayerDetailForName(guildKey, nameID)
    end)
    if not nativeScroll then
        self:AttachHistoryScroll(button)
    end
    return button
end

function LV.UI:ConfirmLootExclusion(guildKey, row)
    if not LV.Loot or not LV.Loot.ExcludeLootItem then
        return
    end
    local itemName = self:LootItemDisplay(guildKey, row)
    if self.lootExclusionPromptAccepted then
        LV.Loot:ExcludeLootItem(guildKey, row, itemName)
        return
    end
    self:ShowConfirmationDialog({
        title = "Exclude " .. itemName .. "?",
        message = "All recorded copies will be removed and future copies will be ignored. You will not be prompted again for exclusions until the LootViewer window is closed or the UI is reloaded.",
        acceptText = "Exclude Item",
        onAccept = function()
            if LV.Loot:ExcludeLootItem(guildKey, row, itemName) then
                self.lootExclusionPromptAccepted = true
            end
        end,
    })
end

function LV.UI:RaidLootRecipientValues(guildKey, row)
    local record = LV.Store:GuildRecord(guildKey)
    local raid = record and record.r and row and row.sid and record.r[row.sid]
    local currentOwner = self:RaidFinalLootOwner(record, row)
    local ids = {}
    local function addID(value)
        value = tonumber(value)
        if value and value ~= tonumber(currentOwner) and LV.Store:DictionaryValue(guildKey, "n", value) ~= "" then
            ids[value] = true
        end
    end
    local function addCollection(collection, isList)
        if isList then
            for _, value in ipairs(collection or {}) do
                addID(value)
            end
        else
            for key in pairs(collection or {}) do
                addID(key)
            end
        end
    end

    if type(raid) == "table" then
        addCollection(raid.p, false)
        addCollection(raid.b, false)
        addCollection(raid.late, false)
        addCollection(raid.out, false)
        addCollection(raid.noshow, false)
        for _, kill in ipairs(raid.kills or {}) do
            if type(kill) == "table" then
                addCollection(kill.p, true)
                addCollection(kill.bench, true)
                addCollection(kill.late, true)
                addCollection(kill.out, true)
                addCollection(kill.noshow, true)
            end
        end
        for _, loot in ipairs(record.l or {}) do
            if type(loot) == "table" and tostring(loot.sid or "") == tostring(row.sid or "") then
                addID(loot.p)
                addID(self:RaidFinalLootOwner(record, loot))
            end
        end
    end

    local entries = {}
    local shortCounts = {}
    for id in pairs(ids) do
        local fullName = LV.Store:DictionaryValue(guildKey, "n", id)
        local shortName = LV.Util:ShortName(fullName)
        entries[#entries + 1] = { value = id, fullName = fullName, shortName = shortName }
        shortCounts[shortName] = (shortCounts[shortName] or 0) + 1
    end
    table.sort(entries, function(a, b)
        return a.shortName:lower() < b.shortName:lower()
    end)
    local values = {}
    for _, entry in ipairs(entries) do
        values[#values + 1] = {
            value = entry.value,
            label = shortCounts[entry.shortName] > 1 and entry.fullName or entry.shortName,
        }
    end
    return values
end

function LV.UI:ShowLootItemActions(guildKey, row)
    if self.lootItemActionModal then
        self.lootItemActionModal:Hide()
    end
    local layer = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    layer:SetAllPoints(self.frame)
    layer:SetFrameStrata("FULLSCREEN_DIALOG")
    layer:SetFrameLevel(self.frame:GetFrameLevel() + 450)
    layer:SetToplevel(true)
    layer:EnableMouse(true)
    LV.Widgets:ApplyBackdrop(layer, LV.Widgets.colors.overlay, LV.Widgets.colors.transparent)

    local modal = CreateFrame("Frame", nil, layer, "BackdropTemplate")
    modal:SetSize(650, 250)
    modal:SetPoint("CENTER")
    modal:SetFrameLevel(layer:GetFrameLevel() + 1)
    modal:EnableMouse(true)
    LV.Widgets:ApplyBackdrop(modal, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.borderStrong)
    local title = LV.Widgets:Text(modal, "Loot Options", "large")
    title:SetPoint("TOPLEFT", 20, -18)
    local close = LV.Widgets:Button(modal, "x", 28, 28, function() layer:Hide() end, "ghost")
    close:SetPoint("TOPRIGHT", -14, -14)
    local itemName = self:LootItemDisplay(guildKey, row)
    local item = LV.Widgets:Text(modal, itemName)
    item:SetPoint("TOPLEFT", 20, -50)
    item:SetWidth(590)
    item:SetWordWrap(false)
    item:SetTextColor(unpack(LV.Widgets.colors.textSecondary))

    local cellWidth, cellHeight = 299, 58
    local function cell(x, y)
        local frame = CreateFrame("Frame", nil, modal, "BackdropTemplate")
        frame:SetPoint("TOPLEFT", x, y)
        frame:SetSize(cellWidth, cellHeight)
        LV.Widgets:ApplyBackdrop(frame, LV.Widgets.colors.surface, LV.Widgets.colors.transparent)
        return frame
    end
    local tradeCell = cell(20, -82)
    local recipientCell = cell(331, -82)
    local excludeCell = cell(20, -152)
    cell(331, -152)

    local isBonusLoot = row and row.src == "bonus"
    local recipientValues = self:RaidLootRecipientValues(guildKey, row)
    local selectedRecipient = recipientValues[1] and recipientValues[1].value or nil
    local recipientDropdownValues = recipientValues
    if #recipientDropdownValues == 0 then
        recipientDropdownValues = { { value = "none", label = "No other raid members" } }
        selectedRecipient = "none"
    end
    if isBonusLoot then
        local personal = LV.Widgets:Text(tradeCell, "Personal bonus loot")
        personal:SetPoint("CENTER")
        personal:SetTextColor(unpack(LV.Widgets.colors.muted))
        local noTrade = LV.Widgets:Text(recipientCell, "Cannot be traded")
        noTrade:SetPoint("CENTER")
        noTrade:SetTextColor(unpack(LV.Widgets.colors.muted))
    else
        local recipient = LV.Widgets:Dropdown(recipientCell, recipientDropdownValues, function()
            return selectedRecipient
        end, function(value)
            selectedRecipient = value
        end, 255, 10)
        recipient:SetPoint("CENTER")

        local trade = LV.Widgets:Button(tradeCell, "Trade Item", 255, 30, function()
            if selectedRecipient == "none" or not selectedRecipient then
                LV:Print("No other raid member is available for this trade.")
                return
            end
            if LV.Trade and LV.Trade.RecordManualTrade
                and LV.Trade:RecordManualTrade(guildKey, row, selectedRecipient) then
                layer:Hide()
            end
        end, "success")
        trade:SetPoint("CENTER")
        LV.Widgets:SetTooltip(trade, "Record this item as traded to the selected raid member.")
    end

    local exclude = LV.Widgets:Button(excludeCell, "Exclude Loot", 255, 30, function()
        layer:Hide()
        self:ConfirmLootExclusion(guildKey, row)
    end, "danger")
    exclude:SetPoint("CENTER")
    LV.Widgets:SetTooltip(exclude, "Exclude this item from history and future rebuilds.")

    self.lootItemActionModal = layer
    layer:Show()
    layer:Raise()
end

function LV.UI:CreateHistoryLootOptionsButton(parent, guildKey, row, x, y, width)
    local button = LV.Widgets:IconButton(parent, "gear", width or 28, 18, function()
        self:ShowLootItemActions(guildKey, row)
    end)
    button:SetPoint("TOPLEFT", x, y + 1)
    LV.Widgets:SetTooltip(button, row and row.src == "bonus"
        and "View or exclude this personal bonus loot."
        or "Trade or exclude this loot item.")
    self:AttachHistoryScroll(button)
    return button
end

function LV.UI:AddLootBreakdownTooltip(guildKey, row, includeHeader)
    if type(row) ~= "table" or type(row.rb) ~= "table" or #row.rb == 0 then
        return
    end

    if includeHeader ~= false then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("LootViewer Rolls", unpack(LV.Widgets.colors.yellow))
    end

    local function entryName(entry)
        return LV.Util:ShortName(LV.Store:DictionaryValue(guildKey, "n", entry.p))
    end

    local function sortEntries(entries)
        table.sort(entries, function(a, b)
            local aWinner = a.w and 1 or 0
            local bWinner = b.w and 1 or 0
            if aWinner ~= bWinner then
                return aWinner > bWinner
            end
            local aRoll = tonumber(a.raw) or -1
            local bRoll = tonumber(b.raw) or -1
            if aRoll ~= bRoll then
                return aRoll > bRoll
            end
            return entryName(a):lower() < entryName(b):lower()
        end)
    end

    local function addEntry(entry, includeMethod)
        local name = entryName(entry)
        local method = includeMethod and self:LootMethodLabel(entry.r) or ""
        local raw = tostring(entry.raw or "")
        local detail = method
        if raw ~= "" then
            detail = detail ~= "" and (detail .. " - " .. raw) or raw
        end
        if entry.w then
            detail = raw ~= "" and ("Winner - " .. raw) or "Winner"
            if includeMethod and method ~= "" then
                detail = "Winner - " .. method .. (raw ~= "" and (" " .. raw) or "")
            end
        end
        local color = self:ClassColorForName(guildKey, entry.p)
        GameTooltip:AddDoubleLine(name, detail, color[1], color[2], color[3], 0.72, 0.74, 0.80)
    end

    local winnerRoll = self:LootWinnerRoll(row) or row.r
    local winnerGroup = self:LootRollGroup(winnerRoll)
    if not winnerGroup then
        local entries = {}
        for _, entry in ipairs(row.rb) do
            if type(entry) == "table" and entry.p then
                entries[#entries + 1] = entry
            end
        end
        sortEntries(entries)
        for _, entry in ipairs(entries) do
            addEntry(entry, true)
        end
        return
    end

    local groups = { need = {}, greed = {}, transmog = {}, unknown = {} }
    for _, entry in ipairs(row.rb) do
        if type(entry) == "table" and entry.p then
            local method = tostring(entry.r or ""):lower()
            local group = self:LootRollGroup(method)
            if group then
                groups[group][#groups[group] + 1] = entry
            elseif entry.w and method ~= "pass" and method ~= "noroll" then
                -- Older roll breakdowns can identify the winner without storing
                -- their per-player method. The loot row still preserves the
                -- winning method, so it is safe to apply that method to the
                -- explicitly flagged winner only.
                groups[winnerGroup][#groups[winnerGroup] + 1] = entry
            elseif method ~= "pass" and method ~= "noroll" then
                groups.unknown[#groups.unknown + 1] = entry
            end
        end
    end

    local displayedGroup = false
    for _, group in ipairs(lootRollGroupOrder) do
        local entries = groups[group]
        if #entries > 0 then
            if displayedGroup then
                GameTooltip:AddLine(" ")
            end
            displayedGroup = true
            sortEntries(entries)
            local visual = lootRollVisuals[group]
            GameTooltip:AddLine("|A:" .. visual.atlas .. ":16:16|a " .. visual.label,
                unpack(LV.Widgets.colors.yellow))
            for _, entry in ipairs(entries) do
                addEntry(entry, false)
            end
        end
    end

    if #groups.unknown > 0 then
        if displayedGroup then
            GameTooltip:AddLine(" ")
        end
        sortEntries(groups.unknown)
        GameTooltip:AddLine("|T" .. unknownLootRollTexture .. ":16:16|t Unclassified",
            unpack(LV.Widgets.colors.yellow))
        for _, entry in ipairs(groups.unknown) do
            addEntry(entry, false)
        end
    end
end

function LV.UI:CreateHistoryItemButton(parent, guildKey, row, x, y, width, nativeScroll)
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
    if not nativeScroll then
        self:AttachHistoryScroll(button)
    end
    return button
end

function LV.UI:RenderDataSync()
    local guildInfo = self:CurrentGuildOrMessage()
    if not guildInfo then
        return
    end

    self:SetPageHeader("Data Sync", pageDefinitions.sync.hint, guildInfo)

    local panel = LV.Widgets:Section(self.content, "Two-Way Guild Merge", 216)
    panel:SetPoint("TOPLEFT", 22, -102)
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
    end, "primary")
    send:SetPoint("LEFT", target, "RIGHT", 12, 0)

    local hint = LV.Widgets:Text(panel, "Merges both players' attendance, loot, trades, and excluded-item rules from the last 2 months. Your shared guild config is used.")
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
        local text = LV.Widgets:Text(detail, "Sync with " .. tostring(outbound.target or "") .. " - " .. tostring(outbound.state or ""))
        text:SetPoint("TOPLEFT", 24, y)
        y = y - 28
        local counts = LV.Widgets:Text(detail, LV.DataSync:FormatCounts(outbound.counts))
        counts:SetTextColor(unpack(LV.Widgets.colors.muted))
        counts:SetPoint("TOPLEFT", 24, y)
        y = y - 28
        if outbound.returnImported then
            local imported = LV.Widgets:Text(detail, "Received " .. LV.DataSync:FormatCounts(outbound.returnImported))
            imported:SetTextColor(unpack(LV.Widgets.colors.muted))
            imported:SetPoint("TOPLEFT", 24, y)
            y = y - 28
        end
    end
    if inbound then
        local text = LV.Widgets:Text(detail, "Sync with " .. tostring(inbound.sender or "") .. " - " .. tostring(inbound.state or ""))
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

function LV.UI:CreateHistoryDifficultySlider(parent, width)
    width = math.max(170, tonumber(width) or 210)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(width, 18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(1, #raidDifficultyThresholds)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    local rail = slider:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("LEFT", 4, 0)
    rail:SetPoint("RIGHT", -4, 0)
    rail:SetHeight(4)
    rail:SetColorTexture(unpack(LV.Widgets.colors.border))
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", rail, "LEFT")
    fill:SetHeight(4)
    fill:SetColorTexture(unpack(LV.Widgets.colors.accent))
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(12, 18)
    thumb:SetVertexColor(unpack(LV.Widgets.colors.accentBright))

    for index, definition in ipairs(raidDifficultyThresholds) do
        local tick = slider:CreateTexture(nil, "OVERLAY")
        tick:SetSize(2, 8)
        if index == 1 then
            tick:SetPoint("CENTER", slider, "LEFT", 4, 0)
        elseif index == #raidDifficultyThresholds then
            tick:SetPoint("CENTER", slider, "RIGHT", -4, 0)
        else
            tick:SetPoint("CENTER", slider, "LEFT", 4 + ((width - 8) * (index - 1) / (#raidDifficultyThresholds - 1)), 0)
        end
        tick:SetColorTexture(unpack(LV.Widgets.colors.textSecondary))

        local label = LV.Widgets:Text(slider, definition.label)
        label:SetWidth(58)
        label:SetJustifyH(index == 1 and "LEFT" or index == #raidDifficultyThresholds and "RIGHT" or "CENTER")
        if index == 1 then
            label:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
        elseif index == #raidDifficultyThresholds then
            label:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
        else
            label:SetPoint("TOP", slider, "BOTTOMLEFT", 4 + ((width - 8) * (index - 1) / (#raidDifficultyThresholds - 1)), -2)
        end
        label:SetTextColor(unpack(LV.Widgets.colors.muted))
    end

    local updating = false
    local function update(value)
        local index = math.max(1, math.min(#raidDifficultyThresholds, math.floor((tonumber(value) or 1) + 0.5)))
        if not updating and tonumber(value) ~= index then
            updating = true
            slider:SetValue(index)
            updating = false
        end
        self.historyMinDifficulty = raidDifficultyThresholds[index].value
        self:SetHistoryFilterPreference("raidMinDifficulty", self.historyMinDifficulty)
        fill:SetWidth(math.max(1, (width - 8) * (index - 1) / (#raidDifficultyThresholds - 1)))
    end
    slider:SetScript("OnValueChanged", function(_, value) update(value) end)
    slider:SetScript("OnMouseUp", function()
        self.historyOffset = 0
        self:Refresh()
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        slider:SetValue(slider:GetValue() + (delta > 0 and 1 or -1))
        self.historyOffset = 0
        self:Refresh()
    end)
    slider:SetScript("OnEnter", function()
        GameTooltip:SetOwner(slider, "ANCHOR_RIGHT")
        GameTooltip:SetText("Minimum Difficulty")
        GameTooltip:AddLine("Shows the selected raid difficulty and every difficulty above it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slider:SetValue(raidDifficultyRankByValue[self.historyMinDifficulty or "lfr"] or 1)
    return slider
end

function LV.UI:RenderLootHistoryFilters(tagValues)
    local section = LV.Widgets:Section(self.content, "Loot Filters", 92)
    section:SetPoint("TOPLEFT", 22, -132)
    section:SetPoint("RIGHT", -22, 0)
    local width = math.max(720, (tonumber(section:GetWidth()) or 820) - 8)
    local half = math.floor((width - 2) / 2)

    local difficultyCell = CreateFrame("Frame", nil, section, "BackdropTemplate")
    difficultyCell:SetPoint("TOPLEFT", 4, -34)
    difficultyCell:SetSize(half, 52)
    LV.Widgets:ApplyBackdrop(difficultyCell, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.transparent)
    local difficultyLabel = LV.Widgets:Text(difficultyCell, "Minimum Difficulty")
    difficultyLabel:SetPoint("LEFT", 14, 3)
    local difficulty = self:CreateHistoryDifficultySlider(difficultyCell, math.max(180, half - 168))
    difficulty:SetPoint("TOPRIGHT", -14, -9)

    local tagCell = CreateFrame("Frame", nil, section, "BackdropTemplate")
    tagCell:SetPoint("TOPLEFT", half + 6, -34)
    tagCell:SetSize(half, 52)
    LV.Widgets:ApplyBackdrop(tagCell, LV.Widgets.colors.canvasAlt, LV.Widgets.colors.transparent)
    local tagLabel = LV.Widgets:Text(tagCell, "Raid Tag")
    tagLabel:SetPoint("LEFT", 14, 0)
    local raidTag = LV.Widgets:Dropdown(tagCell, tagValues, function()
        return self.historyTeamID
    end, function(value)
        self.historyTeamID = value
        self.historyOffset = 0
        self:Refresh()
    end, 170)
    raidTag:SetPoint("RIGHT", -14, 0)
    return section
end

function LV.UI:RenderHistory()
    if self:IsDungeonContext() then
        self:RenderDungeonHistory()
        return
    end
    local guildInfo = self:CurrentGuildOrMessage()
    if not guildInfo then
        return
    end

    local record = LV.Store:GuildRecord(guildInfo.key)
    local cfg = LV.Store:GetConfig(guildInfo.key)
    self.historySeason = self:SelectedSeasonFilter()
    self.historyView = self.historyView or "recent"
    self.tierSeason = self.historySeason
    self.tierType = self.tierType or "all"
    local savedMinDifficulty = self:HistoryFilterPreference("raidMinDifficulty", "lfr")
    self.historyMinDifficulty = self.historyMinDifficulty or savedMinDifficulty
    self.historyMinDifficulty = raidDifficultyRankByValue[self.historyMinDifficulty]
        and self.historyMinDifficulty or "lfr"
    self:SetHistoryFilterPreference("raidMinDifficulty", self.historyMinDifficulty)
    local tagValues = self:RaidTagValues(cfg)
    self.historyTeamID = self.historyTeamID or "all"
    if not self:IsValidRaidTag(tagValues, self.historyTeamID) then
        self.historyTeamID = "all"
    end
    self:SetPageHeader("Loot History", pageDefinitions.history.hint, guildInfo)

    local tabHost = self:Track(CreateFrame("Frame", nil, self.content))
    tabHost:SetPoint("TOPLEFT", 22, -84)
    tabHost:SetPoint("TOPRIGHT", -22, -84)
    tabHost:SetHeight(38)
    local tabs = {
        { key = "recent", label = "Recent" },
        { key = "bonus", label = "Bonus Rolls" },
        { key = "distribution", label = "Distribution" },
        { key = "trades", label = "Trades" },
        { key = "exclusions", label = "Exclusions" },
    }
    if self.historySeason ~= "all" then
        table.insert(tabs, 4, { key = "tier", label = "Tier" })
    elseif self.historyView == "tier" then
        self.historyView = "recent"
    end
    local previous = nil
    for _, definition in ipairs(tabs) do
        local viewKey = definition.key
        local button = LV.Widgets:Tab(tabHost, definition.label, 112, 38, function()
            self.historyView = viewKey
            self.historyOffset = 0
            self:Refresh()
        end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT")
        end
        LV.Widgets:SetButtonActive(button, self.historyView == viewKey)
        previous = button
    end

    local hasLootFilters = self.historyView ~= "exclusions"
    if hasLootFilters then
        self:RenderLootHistoryFilters(tagValues)
    end
    local contentTop = hasLootFilters and -238 or -132

    if self.historyView == "tier" then
        if LV.Loot and LV.Loot.ScheduleLootHistoryScan then
            LV.Loot:ScheduleLootHistoryScan()
        end
        local tierSeasonID = LV.Seasons:ResolveFilter(self.tierSeason)
        local tier = LV.Widgets:Section(self.content, LV.Seasons:Label(tierSeasonID) .. " Tier Tokens", 440)
        tier:SetPoint("TOPLEFT", 22, contentTop)
        tier:SetPoint("BOTTOMRIGHT", -22, 22)
        local typeValues = LV.Tier:TypeValues(tierSeasonID)
        if #typeValues > 0 then
            if not containsValue(typeValues, self.tierType) then
                self.tierType = "all"
            end
            local tierType = LV.Widgets:Dropdown(tier.header, typeValues, function()
                return self.tierType
            end, function(value)
                self.tierType = value
                self:Refresh()
            end, 190)
            tierType:SetPoint("RIGHT", -12, 0)
        end
        self:RenderTierHistory(tier, guildInfo.key, self.tierSeason, self.tierType)
        return
    elseif self.historyView == "distribution" then
        local distribution = LV.Widgets:Section(self.content, "Loot by Final Owner", 440)
        distribution:SetPoint("TOPLEFT", 22, contentTop)
        distribution:SetPoint("BOTTOMRIGHT", -22, 22)
        self:RenderRaidLootDistribution(distribution, guildInfo.key)
        return
    elseif self.historyView == "trades" then
        local trades = LV.Widgets:Section(self.content, "Trades", 440)
        trades:SetPoint("TOPLEFT", 22, contentTop)
        trades:SetPoint("BOTTOMRIGHT", -22, 22)
        self:RenderTradeRows(trades, guildInfo.key)
        return
    elseif self.historyView == "exclusions" then
        local excludedItems = LV.Loot and LV.Loot.ExcludedLootItems and LV.Loot:ExcludedLootItems(guildInfo.key) or {}
        local exclusions = LV.Widgets:Section(self.content, "Excluded Items", 440)
        exclusions:SetPoint("TOPLEFT", 22, -132)
        exclusions:SetPoint("BOTTOMRIGHT", -22, 22)
        self:RenderExcludedLootItems(exclusions, guildInfo.key, excludedItems)
        return
    end

    if self.historyView == "recent" and LV.Loot and LV.Loot.ScheduleLootHistoryScan then
        LV.Loot:ScheduleLootHistoryScan()
    end
    local sourceFilter = self.historyView == "bonus" and "bonus" or "regular"
    local rows, totalRows = self:FilteredHistoryRows(guildInfo.key, sourceFilter)
    self.historyRowsCount = #rows
    self.historyOffset = tonumber(self.historyOffset) or 0
    if self.historyOffset >= #rows then
        self.historyOffset = math.max(0, #rows - HISTORY_PAGE_SIZE)
    end

    local searchText = self:CreateHistorySearch(self.content, "historySearch", 24, -245)

    local history = LV.Widgets:Section(self.content, self.historyView == "bonus" and "Bonus Rolls" or "Loot", 398)
    history:SetPoint("TOPLEFT", 22, -280)
    history:SetPoint("BOTTOMRIGHT", -22, 22)
    self:AttachHistoryScroll(history)
    local pageLabel = searchText ~= ""
        and (tostring(#rows) .. " of " .. tostring(totalRows) .. " loot event(s)")
        or (tostring(totalRows) .. " loot event(s)")
    local page = LV.Widgets:Text(history.header, pageLabel)
    page:SetTextColor(unpack(LV.Widgets.colors.muted))
    page:SetPoint("RIGHT", -18, 0)
    self:RenderLootRows(history, guildInfo.key, rows, self.historyOffset)
end

function LV.UI:RenderTierHistory(parent, guildKey, seasonFilter, typeFilter)
    local groups, total, seasonID = self:TierHistoryGroups(guildKey, seasonFilter, typeFilter)
    if not LV.Tier:HasDefinitions(seasonID) then
        local empty = LV.Widgets:Text(parent, "No tier tokens defined for this season.")
        empty:SetPoint("TOPLEFT", 24, -50)
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        return
    end

    local count = LV.Widgets:Text(parent.header, tostring(total) .. " token(s)")
    count:SetPoint("RIGHT", -218, 0)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))

    if total == 0 then
        local empty = LV.Widgets:Text(parent, "No tier tokens recorded for this season and type.")
        empty:SetPoint("TOPLEFT", 24, -50)
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        return
    end

    self:CreateHistoryColumnHeader(parent, "Date", 24, 76)
    self:CreateHistoryColumnHeader(parent, "Player", 110, 94)
    self:CreateHistoryColumnHeader(parent, "Slot", 214, 68)
    self:CreateHistoryColumnHeader(parent, "Token", 292, 244)
    self:CreateHistoryColumnHeader(parent, "Difficulty", 546, 88)
    self:CreateHistoryColumnHeader(parent, "Roll", 644, 60, "CENTER")

    local scroll, scrollContent = LV.Widgets:ScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 12, -58)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)

    local y = -4
    local displayIndex = 0
    for _, definition in ipairs(LV.Tier:Types(seasonID)) do
        local group = groups[definition.id]
        if group and #group.rows > 0 then
            local groupBackground = scrollContent:CreateTexture(nil, "BACKGROUND")
            groupBackground:SetPoint("TOPLEFT", 4, y + 4)
            groupBackground:SetPoint("TOPRIGHT", -2, y + 4)
            groupBackground:SetHeight(24)
            groupBackground:SetColorTexture(unpack(LV.Widgets.colors.canvasAlt))

            local groupLabel = LV.Widgets:Label(scrollContent,
                definition.label .. " - " .. definition.family .. " (" .. tostring(#group.rows) .. ")")
            groupLabel:SetPoint("TOPLEFT", 12, y)
            groupLabel:SetTextColor(unpack(LV.Widgets.colors.yellow))
            y = y - 26

            for _, entry in ipairs(group.rows) do
                local row = entry.loot
                displayIndex = displayIndex + 1
                local background = scrollContent:CreateTexture(nil, "BACKGROUND")
                background:SetPoint("TOPLEFT", 4, y + 4)
                background:SetPoint("TOPRIGHT", -2, y + 4)
                background:SetHeight(24)
                local stripe = displayIndex % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface
                background:SetColorTexture(unpack(stripe))

                local dateText = LV.Widgets:Text(scrollContent, date("%m/%d %H:%M", row.ts or 0))
                dateText:SetPoint("TOPLEFT", 12, y)
                dateText:SetWidth(76)
                dateText:SetWordWrap(false)
                dateText:SetTextColor(unpack(LV.Widgets.colors.text))

                self:CreateHistoryNameButton(scrollContent, guildKey, row.p, 98, y, 94, true)

                local slot = LV.Widgets:Text(scrollContent, entry.token.slot)
                slot:SetPoint("TOPLEFT", 202, y)
                slot:SetWidth(68)
                slot:SetWordWrap(false)
                slot:SetTextColor(unpack(LV.Widgets.colors.text))

                self:CreateHistoryItemButton(scrollContent, guildKey, row, 280, y, 244, true)

                local difficulty = LV.Widgets:Text(scrollContent, self:LootDifficultyDisplay(guildKey, row))
                difficulty:SetPoint("TOPLEFT", 534, y)
                difficulty:SetWidth(88)
                difficulty:SetWordWrap(false)
                difficulty:SetTextColor(unpack(LV.Widgets.colors.text))

                self:CreateLootMethodDisplay(scrollContent, guildKey, row, 632, y, 60, "RIGHT", true)
                y = y - 26
            end
        end
    end
    scrollContent:SetHeight(math.max(1, -y + 4))
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
    items = items or {}
    local count = LV.Widgets:Text(parent.header, tostring(#items) .. " excluded item(s)")
    count:SetPoint("RIGHT", -18, 0)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    if #items == 0 then
        local empty = LV.Widgets:Text(parent, "No items are excluded.")
        empty:SetPoint("TOPLEFT", 24, -50)
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        return
    end

    local scroll, scrollContent = LV.Widgets:ScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 12, -38)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    local y = -4
    for index, item in ipairs(items) do
        local itemKey = item.key
        local row = CreateFrame("Frame", nil, scrollContent, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 4, y + 4)
        row:SetPoint("RIGHT", -2, 0)
        row:SetHeight(26)
        local stripe = index % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface
        LV.Widgets:ApplyBackdrop(row, stripe, LV.Widgets.colors.transparent)

        local name = LV.Widgets:Text(row, item.name or item.key or "item")
        name:SetPoint("LEFT", 8, 0)
        name:SetPoint("RIGHT", -74, 0)
        name:SetWordWrap(false)
        name:SetTextColor(unpack(item.default and LV.Widgets.colors.muted or LV.Widgets.colors.white))

        local undo = LV.Widgets:Button(row, "Undo", 54, 20, function()
            if LV.Loot and LV.Loot.UnexcludeLootItem then
                LV.Loot:UnexcludeLootItem(guildKey, itemKey)
            end
        end)
        undo:SetPoint("RIGHT", -4, 0)
        LV.Widgets:SetTooltip(undo, "Allow this item again. Rebuild loot to restore matching rows.")
        y = y - 28
    end
    scrollContent:SetHeight(math.max(1, -y + 4))
end

function LV.UI:CreateHistoryRowBackground(parent, y, index)
    local row = parent:CreateTexture(nil, "BACKGROUND")
    row:SetPoint("TOPLEFT", 10, y + 3)
    row:SetPoint("TOPRIGHT", -10, y + 3)
    row:SetHeight(20)
    local color = index % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface
    row:SetColorTexture(unpack(color))
    return row
end

function LV.UI:CreateHistoryDateDisplay(parent, guildKey, row, x, y, width)
    local timestamp = tonumber(row and row.ts) or 0
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", x, y)
    host:SetSize(width, 18)
    host:EnableMouse(true)
    local text = LV.Widgets:Text(host, date("%m/%d", timestamp))
    text:SetAllPoints()
    text:SetWordWrap(false)
    text:SetTextColor(unpack(LV.Widgets.colors.text))
    host:SetScript("OnEnter", function()
        GameTooltip:SetOwner(host, "ANCHOR_RIGHT")
        GameTooltip:SetText(date("%A, %B %d, %Y", timestamp))
        GameTooltip:AddLine("Loot recorded: " .. date("%m/%d/%y %H:%M:%S", timestamp), 0.82, 0.84, 0.90)
        local record = LV.Store:GuildRecord(guildKey)
        local raid = record and record.r and row and row.sid and record.r[row.sid]
        if type(raid) == "table" then
            local raidStart = tonumber(raid.st) or timestamp
            local raidEnd = tonumber(raid.en)
            local hours = date("%m/%d/%y %H:%M", raidStart) .. " - "
                .. (raidEnd and date("%m/%d/%y %H:%M", raidEnd) or "In progress")
            GameTooltip:AddLine("Raid hours: " .. hours, 0.35, 0.82, 0.95, true)
        end
        GameTooltip:Show()
    end)
    host:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:AttachHistoryScroll(host)
    return host
end

function LV.UI:RenderLootRows(parent, guildKey, rows, offset)
    rows = rows or {}
    local record = LV.Store:GuildRecord(guildKey)
    local y = -60
    offset = tonumber(offset) or 0
    local panelWidth = math.max(700, tonumber(parent:GetWidth()) or 700)
    local dateX, dateWidth = 14, 54
    local playerX = dateX + dateWidth + 10
    local playerWidth = math.min(180, math.max(120, 120 + math.floor((panelWidth - 700) * 0.10)))
    local lootX = playerX + playerWidth + 10
    local lootWidth = math.min(440, math.max(252, math.floor(panelWidth * 0.30)))
    local optionsWidth = 28
    local optionsX = panelWidth - 42
    local methodWidth = 40
    local methodX = optionsX - 54
    local bossX = lootX + lootWidth + 10
    local bossWidth = math.max(120, methodX - bossX - 10)

    self:CreateHistoryColumnHeader(parent, "Date", dateX, dateWidth)
    self:CreateHistoryColumnHeader(parent, "Owner", playerX, playerWidth)
    self:CreateHistoryColumnHeader(parent, "Loot", lootX, lootWidth)
    self:CreateHistoryColumnHeader(parent, "Boss", bossX, bossWidth)
    self:CreateHistoryColumnHeader(parent, "Roll", methodX, methodWidth, "CENTER")
    self:CreateHistoryColumnHeader(parent, "Options", optionsX - 14, 56, "CENTER")

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
        self:CreateHistoryDateDisplay(parent, guildKey, row, dateX, y, dateWidth)

        local ownerID = self:RaidFinalLootOwner(record, row) or row.p
        local originalName = LV.Store:DictionaryValue(guildKey, "n", row.p)
        local ownerTooltip = ownerID ~= row.p
            and ("Final owner after trade\nOriginally looted by " .. LV.Util:ShortName(originalName)) or nil
        self:CreateHistoryNameButton(parent, guildKey, ownerID, playerX, y, playerWidth, false, ownerTooltip)
        self:CreateHistoryItemButton(parent, guildKey, row, lootX, y, lootWidth)

        local bossText = LV.Widgets:Text(parent, self:LootBossDifficultyDisplay(guildKey, row))
        bossText:SetPoint("TOPLEFT", bossX, y)
        bossText:SetWidth(bossWidth)
        bossText:SetWordWrap(false)
        bossText:SetTextColor(unpack(LV.Widgets.colors.text))

        self:CreateLootMethodDisplay(parent, guildKey, row, methodX, y, methodWidth, "CENTER", true)
        self:CreateHistoryLootOptionsButton(parent, guildKey, row, optionsX, y, optionsWidth)
        y = y - 22
    end
end

function LV.UI:RenderTradeRows(parent, guildKey)
    local record = LV.Store:GuildRecord(guildKey)
    local rows = {}
    for _, row in ipairs(record.t or {}) do
        if type(row) == "table"
            and LV.Seasons:EventMatchesFilter(guildKey, record, row, self:SelectedSeasonFilter())
            and self:EventMatchesRaidTag(record, row, self.historyTeamID)
            and self:EventMeetsMinimumDifficulty(guildKey, record, row) then
            rows[#rows + 1] = row
        end
    end

    local count = LV.Widgets:Text(parent.header, tostring(#rows) .. " trade(s)")
    count:SetPoint("RIGHT", -18, 0)
    count:SetTextColor(unpack(LV.Widgets.colors.muted))
    if #rows == 0 then
        local empty = LV.Widgets:Text(parent, "No trades recorded for this season.")
        empty:SetTextColor(unpack(LV.Widgets.colors.muted))
        empty:SetPoint("TOPLEFT", 24, -50)
        return
    end

    local panelWidth = math.max(700, tonumber(parent:GetWidth()) or 700)
    local dateX, dateWidth = 24, 98
    local fromX, fromWidth = 132, 110
    local toX, toWidth = 252, 110
    local itemX = 372
    local initiatedWidth = 128
    local initiatedX = panelWidth - initiatedWidth - 16
    local itemWidth = math.max(150, initiatedX - itemX - 10)
    self:CreateHistoryColumnHeader(parent, "Date", dateX, dateWidth)
    self:CreateHistoryColumnHeader(parent, "From", fromX, fromWidth)
    self:CreateHistoryColumnHeader(parent, "To", toX, toWidth)
    self:CreateHistoryColumnHeader(parent, "Item", itemX, itemWidth)
    self:CreateHistoryColumnHeader(parent, "Initiated By", initiatedX, initiatedWidth)

    local scroll, scrollContent = LV.Widgets:ScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 12, -58)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    local y = -4
    for index = #rows, 1, -1 do
        local row = rows[index]
        local displayIndex = #rows - index + 1
        local background = scrollContent:CreateTexture(nil, "BACKGROUND")
        background:SetPoint("TOPLEFT", 4, y + 4)
        background:SetPoint("TOPRIGHT", -2, y + 4)
        background:SetHeight(26)
        local stripe = displayIndex % 2 == 0 and LV.Widgets.colors.canvasAlt or LV.Widgets.colors.surface
        background:SetColorTexture(unpack(stripe))

        local dateText = LV.Widgets:Text(scrollContent, date("%m/%d %H:%M", row.ts or 0))
        dateText:SetPoint("TOPLEFT", dateX - 12, y)
        dateText:SetWidth(dateWidth)
        dateText:SetWordWrap(false)
        dateText:SetTextColor(unpack(LV.Widgets.colors.text))
        self:CreateHistoryNameButton(scrollContent, guildKey, row.f, fromX - 12, y, fromWidth, true)
        self:CreateHistoryNameButton(scrollContent, guildKey, row.to, toX - 12, y, toWidth, true)
        self:CreateHistoryItemButton(scrollContent, guildKey, row, itemX - 12, y, itemWidth, true)
        if row.src == "manual" and row.by then
            self:CreateHistoryNameButton(scrollContent, guildKey, row.by, initiatedX - 12, y, initiatedWidth, true)
        else
            local initiated = LV.Widgets:Text(scrollContent, "Detected")
            initiated:SetPoint("TOPLEFT", initiatedX - 12, y)
            initiated:SetWidth(initiatedWidth)
            initiated:SetWordWrap(false)
            initiated:SetTextColor(unpack(LV.Widgets.colors.muted))
        end
        y = y - 28
    end
    scrollContent:SetHeight(math.max(1, -y + 4))
end

LV:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if LV.UI and LV.UI.frame and LV.UI.frame:IsShown() and LV.UI.currentTab == "history" then
        LV.UI:Refresh()
    end
end)
