local _, LV = ...

LV.Widgets = {}

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function hex(value, alpha)
    value = value:gsub("#", "")
    return {
        tonumber(value:sub(1, 2), 16) / 255,
        tonumber(value:sub(3, 4), 16) / 255,
        tonumber(value:sub(5, 6), 16) / 255,
        alpha or 1,
    }
end

-- Palette follows the PopAuras visual design: calm dark neutrals with a slight
-- blue-green bias and one teal accent for "on", "selected" and "focus".
local colors = {
    transparent = { 0, 0, 0, 0 },
    overlay = { 0, 0, 0, 0.62 },
    canvas = hex("0D1116", 0.99),
    canvasAlt = hex("0A0E11", 0.99),
    rowOdd = hex("0F1419"),
    rowEven = hex("13191E"),
    control = hex("131C22"),
    surface = hex("11171C"),
    surfaceRaised = hex("161E24"),
    surfaceHover = hex("1B242A"),
    surfacePressed = hex("22303A"),
    accent = hex("0CD29D"),
    accentBright = hex("54EDC2"),
    accentSoft = hex("073328"),
    accentGlow = hex("0CD29D", 0.10),
    onAccent = hex("04241B"),
    border = hex("262F36"),
    borderStrong = hex("344047"),
    borderFocus = hex("0CD29D"),
    text = hex("F2F5F7"),
    textSecondary = hex("C2C9CF"),
    textMuted = hex("858F96"),
    sectionTitle = hex("8F99A1"),
    navigation = hex("54EDC2"),
    success = hex("0CD29D"),
    successBorder = hex("0CD29D"),
    danger = hex("2A1517"),
    dangerHover = hex("3A1A1D"),
    dangerBorder = hex("E0585E"),
    switchTrackOff = hex("2E373D"),
    switchKnobOff = hex("9EA6AB"),
}

-- Compatibility aliases used by the existing renderers.
colors.bg = colors.canvas
colors.panel = colors.rowOdd
colors.header = colors.surfaceHover
colors.active = colors.accentSoft
colors.yellow = colors.navigation
colors.white = colors.text
colors.muted = colors.textMuted

LV.Widgets.colors = colors

local backdrop = {
    bgFile = WHITE_TEXTURE,
    edgeFile = WHITE_TEXTURE,
    edgeSize = 1,
}

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local buttonStyles = {
    secondary = {
        normal = { colors.surface, colors.border, colors.textSecondary },
        hover = { colors.surfaceHover, colors.borderStrong, colors.text },
        pressed = { colors.surfacePressed, colors.borderStrong, colors.text },
    },
    control = {
        normal = { colors.control, colors.border, colors.textSecondary },
        hover = { colors.control, colors.accent, colors.text },
        pressed = { colors.surfaceHover, colors.accent, colors.text },
    },
    primary = {
        normal = { colors.accent, colors.accent, colors.onAccent },
        hover = { colors.accentBright, colors.accentBright, colors.onAccent },
        pressed = { colors.accent, colors.accentBright, colors.onAccent },
    },
    success = {
        normal = { colors.accent, colors.accent, colors.onAccent },
        hover = { colors.accentBright, colors.accentBright, colors.onAccent },
        pressed = { colors.accent, colors.accentBright, colors.onAccent },
    },
    danger = {
        normal = { colors.danger, colors.dangerBorder, colors.dangerBorder },
        hover = { colors.dangerHover, colors.dangerBorder, colors.text },
        pressed = { colors.dangerHover, colors.dangerBorder, colors.text },
    },
    ghost = {
        normal = { colors.transparent, colors.transparent, colors.textSecondary },
        hover = { colors.surfaceHover, colors.transparent, colors.text },
        pressed = { colors.surfacePressed, colors.transparent, colors.text },
    },
    menu = {
        normal = { colors.transparent, colors.transparent, colors.textSecondary },
        hover = { colors.surfaceHover, colors.transparent, colors.text },
        pressed = { colors.surfacePressed, colors.transparent, colors.text },
    },
    navigation = {
        normal = { colors.transparent, colors.transparent, colors.textSecondary },
        hover = { colors.surfaceHover, colors.transparent, colors.text },
        pressed = { colors.surfacePressed, colors.transparent, colors.text },
        active = { colors.accentSoft, colors.transparent, colors.text },
    },
    tab = {
        normal = { colors.transparent, colors.transparent, colors.textMuted },
        hover = { colors.transparent, colors.transparent, colors.text },
        pressed = { colors.transparent, colors.transparent, colors.text },
        active = { colors.transparent, colors.transparent, colors.text },
    },
}

local function track(parent, region)
    if parent and parent._lvTrackDirect and LV.UI and LV.UI.Track then
        LV.UI:Track(region)
    end
    return region
end

local function hideTextureRegions(frame)
    if not frame or not frame.GetRegions then
        return
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
end

function LV.Widgets:ApplyBackdrop(frame, color, borderColor)
    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(unpack(color or colors.surface))
    frame:SetBackdropBorderColor(unpack(borderColor or colors.border))
end

function LV.Widgets:Line(parent, height, color)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE_TEXTURE)
    line:SetHeight(height or 1)
    line:SetVertexColor(unpack(color or colors.border))
    return line
end

function LV.Widgets:Label(parent, text, size)
    local font = parent:CreateFontString(nil, "OVERLAY", size == "large" and "GameFontNormalLarge" or "GameFontNormal")
    font:SetText(text or "")
    font:SetTextColor(unpack(colors.textSecondary))
    font:SetJustifyH("LEFT")
    return track(parent, font)
end

function LV.Widgets:Text(parent, text, size)
    local font = parent:CreateFontString(nil, "OVERLAY", size == "large" and "GameFontHighlightLarge" or "GameFontHighlight")
    font:SetText(text or "")
    font:SetTextColor(unpack(colors.text))
    font:SetJustifyH("LEFT")
    return track(parent, font)
end

-- Monochrome line glyphs drawn from plain textures so they can be tinted in
-- code: neutral at rest, accent when active.
local glyphBuilders = {}

local function glyphLine(glyph, width, height, x, y, rotation)
    local line = glyph:CreateTexture(nil, "OVERLAY")
    line:SetTexture(WHITE_TEXTURE)
    line:SetSize(width, height)
    line:SetPoint("CENTER", glyph, "CENTER", x or 0, y or 0)
    if rotation and line.SetRotation then
        line:SetRotation(rotation)
    end
    glyph.lines[#glyph.lines + 1] = line
    return line
end

local function glyphRing(glyph, cx, cy, radius, segments, thickness, skipFrom, skipTo)
    segments = segments or 12
    local length = (2 * math.pi * radius) / segments + 0.6
    for segment = 0, segments - 1 do
        local angle = (math.pi * 2 * segment) / segments
        local skip = skipFrom and segment >= skipFrom and segment <= skipTo
        if not skip then
            glyphLine(glyph, length, thickness or 1.5, cx + math.cos(angle) * radius,
                cy + math.sin(angle) * radius, angle + (math.pi / 2))
        end
    end
end

local function glyphBox(glyph, cx, cy, width, height, thickness)
    thickness = thickness or 1.5
    glyphLine(glyph, width, thickness, cx, cy + (height / 2) - (thickness / 2))
    glyphLine(glyph, width, thickness, cx, cy - (height / 2) + (thickness / 2))
    glyphLine(glyph, thickness, height, cx - (width / 2) + (thickness / 2), cy)
    glyphLine(glyph, thickness, height, cx + (width / 2) - (thickness / 2), cy)
end

glyphBuilders.meter = function(g)
    glyphLine(g, 9, 2, -2.5, 4)
    glyphLine(g, 13, 2, -0.5, 0)
    glyphLine(g, 6, 2, -4, -4)
end
glyphBuilders.calendar = function(g)
    glyphBox(g, 0, -1, 13, 12)
    glyphLine(g, 13, 2, 0, 2)
    glyphLine(g, 1.5, 3, -3.5, 6)
    glyphLine(g, 1.5, 3, 3.5, 6)
end
glyphBuilders.users = function(g)
    glyphRing(g, -1.5, 3, 2.6, 10)
    glyphLine(g, 9, 1.5, -1.5, -5)
    glyphLine(g, 1.5, 4, -5.5, -3.5)
    glyphLine(g, 1.5, 4, 2.5, -3.5)
    glyphLine(g, 1.5, 4, 5.5, 2.5)
    glyphLine(g, 1.5, 4, 6.5, -4)
end
glyphBuilders.gear = function(g)
    glyphRing(g, 0, 0, 4, 12)
    for tooth = 0, 7 do
        local angle = (math.pi * 2 * tooth) / 8
        glyphLine(g, 2.6, 2, math.cos(angle) * 6, math.sin(angle) * 6, angle)
    end
end
glyphBuilders.chest = function(g)
    glyphBox(g, 0, -3, 13, 7)
    glyphBox(g, 0, 3.5, 13, 5)
    glyphLine(g, 3, 3, 0, 0.5)
end
glyphBuilders.key = function(g)
    glyphRing(g, -3.5, 0, 3, 10)
    glyphLine(g, 8, 1.5, 3.5, 0)
    glyphLine(g, 1.5, 3, 4.5, -2)
    glyphLine(g, 1.5, 3, 7, -2)
end
glyphBuilders.sync = function(g)
    glyphRing(g, 0, 0, 5, 14, 1.5, 2, 3)
    glyphRing(g, 0, 0, 5, 14, 1.5, 9, 10)
    glyphLine(g, 4, 1.5, 5.5, 2, math.rad(-60))
    glyphLine(g, 4, 1.5, -5.5, -2, math.rad(-60))
end
glyphBuilders.more = function(g)
    glyphLine(g, 2.5, 2.5, -4.5, 0)
    glyphLine(g, 2.5, 2.5, 0, 0)
    glyphLine(g, 2.5, 2.5, 4.5, 0)
end
glyphBuilders.close = function(g)
    glyphLine(g, 12, 1.5, 0, 0, math.rad(45))
    glyphLine(g, 12, 1.5, 0, 0, math.rad(-45))
end
glyphBuilders.chevron = function(g)
    glyphLine(g, 5.5, 1.5, -1.8, 0, math.rad(-45))
    glyphLine(g, 5.5, 1.5, 1.8, 0, math.rad(45))
end
glyphBuilders.pencil = function(g)
    glyphLine(g, 12, 3, 0.5, 0.5, math.rad(45))
    glyphLine(g, 3, 1.5, -5, -5)
end
glyphBuilders.resize = function(g)
    glyphLine(g, 10, 1.5, 1, -1, math.rad(45))
    glyphLine(g, 5, 1.5, 3.5, -3.5, math.rad(45))
end

function LV.Widgets:HasGlyph(kind)
    return type(kind) == "string" and glyphBuilders[kind] ~= nil
end

function LV.Widgets:Glyph(parent, kind, size, color)
    local glyph = CreateFrame("Frame", nil, parent)
    glyph:SetSize(size or 16, size or 16)
    glyph.lines = {}
    local builder = glyphBuilders[kind]
    if builder then
        builder(glyph)
    end
    function glyph:SetColor(value)
        for _, line in ipairs(self.lines) do
            line:SetVertexColor(unpack(value or colors.textSecondary))
        end
    end
    glyph:SetColor(color or colors.textSecondary)
    return glyph
end

function LV.Widgets:ApplyButtonState(button, state)
    local style = buttonStyles[button._lvStyle or "secondary"] or buttonStyles.secondary
    local definition = (button._lvActive and style.active) or style[state or "normal"] or style.normal
    self:ApplyBackdrop(button, definition[1], definition[2])
    if button.text then
        button.text:SetTextColor(unpack(definition[3]))
    end
    if button._lvNavigationLine then
        button._lvNavigationLine:SetShown(button._lvActive == true)
    end
    if button._lvTabLine then
        button._lvTabLine:SetShown(button._lvActive == true)
    end
    local hovered = state == "hover" or state == "pressed"
    local tint = button._lvActive and colors.accentBright
        or (hovered and colors.text or colors.textMuted)
    if button.icon then
        button.icon:SetVertexColor(unpack(tint))
    end
    if button.glyph then
        button.glyph:SetColor(tint)
    end
    if button.chevron then
        button.chevron:SetColor(hovered and colors.accentBright or colors.textMuted)
    end
end

function LV.Widgets:Button(parent, text, width, height, onClick, style)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 120, height or 28)
    button._lvStyle = style or "secondary"
    button.text = self:Text(button, text or "")
    button.Text = button.text
    button.text:SetPoint("CENTER")
    self:ApplyButtonState(button, "normal")
    button:SetScript("OnEnter", function()
        LV.Widgets:ApplyButtonState(button, "hover")
        if button.tooltip then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(button.tooltip)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        LV.Widgets:ApplyButtonState(button, "normal")
        if button.tooltip then
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnMouseDown", function()
        LV.Widgets:ApplyButtonState(button, "pressed")
    end)
    button:SetScript("OnMouseUp", function()
        LV.Widgets:ApplyButtonState(button, button:IsMouseOver() and "hover" or "normal")
    end)
    button:SetScript("OnClick", function()
        if onClick then
            onClick(button)
        end
    end)
    return track(parent, button)
end

function LV.Widgets:SetButtonStyle(button, style)
    if button then
        button._lvStyle = style or "secondary"
        self:ApplyButtonState(button, "normal")
    end
end

function LV.Widgets:SetButtonActive(button, active)
    if button then
        button._lvActive = active and true or false
        self:ApplyButtonState(button, "normal")
    end
end

function LV.Widgets:NavigationButton(parent, text, iconTexture, width, height, onClick)
    local button = self:Button(parent, text, width, height, onClick, "navigation")
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 42, 0)
    button.text:SetPoint("RIGHT", -12, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)
    if self:HasGlyph(iconTexture) then
        button.glyph = self:Glyph(button, iconTexture, 16)
        button.glyph:SetPoint("LEFT", 16, 0)
    else
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(16, 16)
        button.icon:SetPoint("LEFT", 16, 0)
        button.icon:SetTexture(iconTexture)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetDesaturated(true)
    end
    button._lvNavigationLine = self:Line(button, 1, colors.accent)
    button._lvNavigationLine:ClearAllPoints()
    button._lvNavigationLine:SetPoint("TOPLEFT", 0, 0)
    button._lvNavigationLine:SetPoint("BOTTOMLEFT", 0, 0)
    button._lvNavigationLine:SetWidth(3)
    button._lvNavigationLine:Hide()
    self:ApplyButtonState(button, "normal")
    return button
end

function LV.Widgets:Tab(parent, text, width, height, onClick)
    local button = self:Button(parent, text, width, height, onClick, "tab")
    button._lvTabLine = self:Line(button, 2, colors.accent)
    button._lvTabLine:SetPoint("BOTTOMLEFT", 10, 0)
    button._lvTabLine:SetPoint("BOTTOMRIGHT", -10, 0)
    button._lvTabLine:Hide()
    self:ApplyButtonState(button, "normal")
    return button
end

-- The "selected row" treatment: soft accent fill plus a 3px accent bar.
function LV.Widgets:SelectionBar(frame)
    local bar = frame:CreateTexture(nil, "OVERLAY")
    bar:SetTexture(WHITE_TEXTURE)
    bar:SetVertexColor(unpack(colors.accent))
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    return bar
end

function LV.Widgets:RowColor(index)
    return (tonumber(index) or 0) % 2 == 0 and colors.rowEven or colors.rowOdd
end

-- A shared, labelled action menu. Items: { text, onClick, danger, disabled,
-- title = true, separator = true }. Closes on outside click or Escape.
function LV.Widgets:ShowMenu(anchor, items, point, relativePoint, x, y)
    local menu = self.actionMenu
    if not menu then
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("TOOLTIP")
        catcher:SetFrameLevel(1)
        catcher:RegisterForClicks("AnyUp")
        catcher:Hide()

        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("TOOLTIP")
        menu:SetFrameLevel(20)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:Hide()
        self:ApplyBackdrop(menu, colors.canvasAlt, colors.borderStrong)
        menu.catcher = catcher
        menu.rows = {}
        catcher:SetScript("OnClick", function()
            menu:Hide()
        end)
        menu:SetScript("OnHide", function()
            catcher:Hide()
        end)
        menu:SetScript("OnKeyDown", function(selfMenu, key)
            if InCombatLockdown and InCombatLockdown() then
                return
            end
            if key == "ESCAPE" then
                selfMenu:SetPropagateKeyboardInput(false)
                selfMenu:Hide()
            else
                selfMenu:SetPropagateKeyboardInput(true)
            end
        end)
        self.actionMenu = menu
    end

    for _, row in ipairs(menu.rows) do
        row:Hide()
    end
    local width = 188
    local offset = -4
    for rowIndex, item in ipairs(items or {}) do
        local row = menu.rows[rowIndex]
        if not row then
            row = self:Button(menu, "", width - 2, 26, nil, "menu")
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", 12, 0)
            row.text:SetPoint("RIGHT", -12, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.divider = self:Line(row, 1, colors.border)
            row.divider:SetPoint("LEFT", 0, 0)
            row.divider:SetPoint("RIGHT", 0, 0)
            row:HookScript("OnLeave", function(selfRow)
                if selfRow._lvDanger and selfRow:IsEnabled() then
                    selfRow.text:SetTextColor(unpack(colors.dangerBorder))
                end
            end)
            menu.rows[rowIndex] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 1, offset)
        row:SetWidth(width - 2)
        row.divider:Hide()
        row.text:Show()
        row:Enable()
        row:EnableMouse(true)
        row._lvDanger = nil
        row:SetScript("OnClick", nil)
        local height = 26
        if item.separator then
            height = 9
            row.text:Hide()
            row.divider:Show()
            row:Disable()
            row:EnableMouse(false)
            self:ApplyBackdrop(row, colors.transparent, colors.transparent)
        elseif item.title then
            height = 24
            row.text:SetText(string.upper(item.text or ""))
            row:Disable()
            row:EnableMouse(false)
            self:ApplyBackdrop(row, colors.transparent, colors.transparent)
            row.text:SetTextColor(unpack(colors.sectionTitle))
        else
            row.text:SetText(item.text or "")
            local onClick = item.onClick
            row:SetScript("OnClick", function()
                menu:Hide()
                if onClick then
                    onClick()
                end
            end)
            self:ApplyButtonState(row, "normal")
            if item.disabled then
                row:Disable()
                row.text:SetTextColor(unpack(colors.textMuted))
            elseif item.danger then
                row._lvDanger = true
                row.text:SetTextColor(unpack(colors.dangerBorder))
            end
        end
        row:SetHeight(height)
        row:Show()
        offset = offset - height
    end
    menu:SetSize(width, -offset + 4)
    menu:ClearAllPoints()
    menu:SetPoint(point or "TOPRIGHT", anchor, relativePoint or "BOTTOMRIGHT", x or 0, y or -2)
    -- Escape closes the menu, but never take keyboard input during combat.
    menu:EnableKeyboard(not (InCombatLockdown and InCombatLockdown()))
    menu.catcher:Show()
    menu:Show()
    menu:Raise()
    return menu
end

function LV.Widgets:HideMenu()
    if self.actionMenu then
        self.actionMenu:Hide()
    end
end

-- A quiet "more actions" button. It stays hidden until its row is hovered or
-- selected. Rows call button:OpenMenu() on right-click to show the same menu.
function LV.Widgets:RowMenuButton(row, getItems, alwaysShown)
    local button = self:IconButton(row, "more", 24, 22)
    local function open()
        local items = type(getItems) == "function" and getItems() or getItems
        LV.Widgets:ShowMenu(button, items)
    end
    button:SetScript("OnClick", open)
    button.OpenMenu = open
    button._lvAlwaysShown = alwaysShown == true
    local function refreshVisibility()
        local shown = button._lvAlwaysShown or row:IsMouseOver() or button:IsMouseOver()
        button:SetAlpha(shown and 1 or 0)
    end
    local function refreshSoon()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, refreshVisibility)
        else
            refreshVisibility()
        end
    end
    button:SetAlpha(button._lvAlwaysShown and 1 or 0)
    row:HookScript("OnEnter", refreshVisibility)
    row:HookScript("OnLeave", refreshSoon)
    button:HookScript("OnEnter", refreshVisibility)
    button:HookScript("OnLeave", refreshSoon)
    return button
end

function LV.Widgets:SetTooltip(frame, text)
    if frame then
        frame.tooltip = text
    end
end

local function addIconLine(icon, width, height, point, x, y, rotation)
    local line = icon:CreateTexture(nil, "OVERLAY")
    line:SetTexture(WHITE_TEXTURE)
    line:SetSize(width, height)
    line:SetPoint(point or "CENTER", icon, point or "CENTER", x or 0, y or 0)
    if rotation and line.SetRotation then
        line:SetRotation(rotation)
    end
    icon.lines[#icon.lines + 1] = line
end

local function addOutlineSquare(icon, x, y, size)
    addIconLine(icon, size, 1, "TOPLEFT", x, y)
    addIconLine(icon, size, 1, "TOPLEFT", x, y - size + 1)
    addIconLine(icon, 1, size, "TOPLEFT", x, y)
    addIconLine(icon, 1, size, "TOPLEFT", x + size - 1, y)
end

local function setActionIconColor(button, color)
    local icon = button and button._lvActionIcon
    for _, line in ipairs(icon and icon.lines or {}) do
        line:SetVertexColor(unpack(color))
    end
    if icon and icon.texture then
        icon.texture:SetVertexColor(unpack(color))
    end
end

function LV.Widgets:IconButton(parent, kind, width, height, onClick)
    local style = kind == "trash" and "ghost" or "ghost"
    local button = self:Button(parent, "", width or 24, height or 22, onClick, style)
    local icon = CreateFrame("Frame", nil, button)
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    icon.lines = {}

    if kind == "edit" then
        kind = "pencil"
    end
    if kind == "more" or kind == "close" or kind == "pencil" then
        local glyph = self:Glyph(icon, kind, 16)
        glyph:SetAllPoints()
        icon.lines = glyph.lines
    elseif kind == "copy" then
        -- Matches PopAuras' overlapping-outline duplicate icon.
        addOutlineSquare(icon, 2, -2, 8)
        addOutlineSquare(icon, 6, -6, 8)
    elseif kind == "trash" then
        -- Matches the line-art trash icon used by PopAuras.
        addIconLine(icon, 8, 1, "TOPLEFT", 4, -4)
        addIconLine(icon, 4, 1, "TOPLEFT", 6, -2)
        addIconLine(icon, 1, 8, "TOPLEFT", 5, -6)
        addIconLine(icon, 1, 8, "TOPLEFT", 11, -6)
        addIconLine(icon, 7, 1, "TOPLEFT", 5, -13)
        addIconLine(icon, 1, 5, "TOPLEFT", 7, -7)
        addIconLine(icon, 1, 5, "TOPLEFT", 9, -7)
    elseif kind == "edit" then
        -- A desaturated game icon stays recognizable as a quill at table-row size.
        icon.texture = icon:CreateTexture(nil, "OVERLAY")
        icon.texture:SetSize(18, 18)
        icon.texture:SetPoint("CENTER")
        icon.texture:SetTexture("Interface\\Icons\\INV_Feather_01")
        icon.texture:SetTexCoord(0.10, 0.90, 0.10, 0.90)
        icon.texture:SetDesaturated(true)
    elseif kind == "gear" then
        icon.texture = icon:CreateTexture(nil, "OVERLAY")
        icon.texture:SetSize(18, 18)
        icon.texture:SetPoint("CENTER")
        icon.texture:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        icon.texture:SetTexCoord(0.10, 0.90, 0.10, 0.90)
        icon.texture:SetDesaturated(true)
    elseif kind == "exclude" then
        local radius = 5.2
        for segment = 0, 11 do
            local angle = (math.pi * 2 * segment) / 12
            addIconLine(
                icon,
                3,
                1,
                "CENTER",
                math.cos(angle) * radius,
                math.sin(angle) * radius,
                angle + (math.pi / 2)
            )
        end
        addIconLine(icon, 1, 14, "CENTER", 0, 0, math.rad(-45))
    end

    button._lvActionIcon = icon
    local normalColor = colors.textSecondary
    if kind == "exclude" then
        normalColor = colors.dangerBorder
    elseif kind == "more" or kind == "close" then
        normalColor = colors.textMuted
    end
    local hoverColor = kind == "trash" and colors.dangerBorder or colors.text
    setActionIconColor(button, normalColor)
    button:HookScript("OnEnter", function()
        setActionIconColor(button, hoverColor)
    end)
    button:HookScript("OnLeave", function()
        setActionIconColor(button, normalColor)
    end)
    return button
end

function LV.Widgets:EditBox(parent, width, height, onCommit)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate,BackdropTemplate")
    edit:SetSize(width or 120, height or 28)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlight)
    edit:SetTextInsets(7, 7, 0, 0)
    hideTextureRegions(edit)
    self:ApplyBackdrop(edit, colors.control, colors.border)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onCommit then
            onCommit(self:GetText())
        end
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropColor(unpack(colors.control))
        self:SetBackdropBorderColor(unpack(colors.border))
        if onCommit then
            onCommit(self:GetText())
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropColor(unpack(colors.control))
        self:SetBackdropBorderColor(unpack(colors.borderFocus))
    end)
    edit:HookScript("OnEnter", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(unpack(colors.borderStrong))
        end
    end)
    edit:HookScript("OnLeave", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(unpack(colors.border))
        end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return track(parent, edit)
end

local function roundPiece(parent, layer, size)
    local piece = parent:CreateTexture(nil, layer)
    piece:SetTexture(WHITE_TEXTURE)
    piece:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(piece)
    piece:AddMaskTexture(mask)
    return piece
end

local function updateToggle(check)
    local checked = check:GetChecked() and true or false
    local hovered = check:IsMouseOver()
    local track = checked and (hovered and colors.accentBright or colors.accent)
        or (hovered and colors.borderStrong or colors.switchTrackOff)
    for _, piece in ipairs(check.trackPieces) do
        piece:SetVertexColor(unpack(track))
    end
    check.knob:ClearAllPoints()
    check.knob:SetPoint("CENTER", check, "LEFT", checked and 28 or 10, 0)
    check.knob:SetVertexColor(unpack(checked and { 1, 1, 1, 1 } or colors.switchKnobOff))
    check:SetAlpha(check:IsEnabled() and 1 or 0.4)
end

-- Pill switch: 38x20 rounded track with a 14px round knob.
function LV.Widgets:Check(parent, text, onChanged)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(38, 20)
    check:SetHitRectInsets(0, -6, -2, -2)
    local left = roundPiece(check, "BACKGROUND", 20)
    left:SetPoint("LEFT", 0, 0)
    local right = roundPiece(check, "BACKGROUND", 20)
    right:SetPoint("RIGHT", 0, 0)
    local middle = check:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture(WHITE_TEXTURE)
    middle:SetPoint("TOPLEFT", 10, 0)
    middle:SetPoint("BOTTOMRIGHT", -10, 0)
    check.trackPieces = { left, right, middle }
    check.knob = roundPiece(check, "ARTWORK", 14)
    check.label = self:Text(check, text or "")
    check.label:SetPoint("LEFT", check, "RIGHT", 10, 0)
    check.label:SetTextColor(unpack(colors.textSecondary))
    local originalSetChecked = check.SetChecked
    check.SetChecked = function(self, value)
        originalSetChecked(self, value)
        updateToggle(self)
    end
    check:HookScript("OnEnable", updateToggle)
    check:HookScript("OnDisable", updateToggle)
    check:SetScript("OnClick", function(self)
        updateToggle(self)
        if onChanged then
            onChanged(self:GetChecked() and true or false)
        end
    end)
    check:SetScript("OnEnter", function(self)
        updateToggle(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltip)
            GameTooltip:Show()
        end
    end)
    check:SetScript("OnLeave", function(self)
        updateToggle(self)
        if self.tooltip then
            GameTooltip:Hide()
        end
    end)
    check:SetScript("OnShow", updateToggle)
    updateToggle(check)
    return track(parent, check)
end

local function pillLayer(frame, layer, inset, height)
    local size = height - (inset * 2)
    local left = roundPiece(frame, layer, size)
    left:SetPoint("LEFT", inset, 0)
    local right = roundPiece(frame, layer, size)
    right:SetPoint("RIGHT", -inset, 0)
    local middle = frame:CreateTexture(nil, layer)
    middle:SetTexture(WHITE_TEXTURE)
    middle:SetPoint("TOPLEFT", inset + (size / 2), -inset)
    middle:SetPoint("BOTTOMRIGHT", -(inset + (size / 2)), inset)
    return { left, right, middle }
end

local function tintPieces(pieces, color)
    for _, piece in ipairs(pieces) do
        piece:SetVertexColor(unpack(color))
    end
end

-- Pill-shaped option (24px). Selected: accent outline, soft accent fill and
-- accent text. Idle: neutral outline. `idleFill` should match the surface the
-- chip sits on.
function LV.Widgets:Chip(parent, text, onClick, swatchColor, idleFill)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(24)
    chip.outline = pillLayer(chip, "BACKGROUND", 0, 24)
    chip.fill = pillLayer(chip, "BORDER", 1, 24)
    chip.idleFill = idleFill or colors.canvas
    local textLeft = 12
    if swatchColor then
        chip.swatch = chip:CreateTexture(nil, "ARTWORK")
        chip.swatch:SetTexture(WHITE_TEXTURE)
        chip.swatch:SetSize(8, 8)
        chip.swatch:SetPoint("LEFT", 11, 0)
        chip.swatch:SetVertexColor(unpack(swatchColor))
        textLeft = 25
    end
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.text:SetText(text or "")
    chip.text:SetPoint("LEFT", textLeft, 0)
    chip:SetWidth(math.ceil((chip.text:GetStringWidth() or 40) + textLeft + 12))

    function chip:Refresh()
        local hovered = self:IsMouseOver() and self:IsEnabled()
        if self._selected then
            tintPieces(self.outline, hovered and colors.accentBright or colors.accent)
            tintPieces(self.fill, colors.accentSoft)
            self.text:SetTextColor(unpack(colors.accentBright))
        else
            tintPieces(self.outline, hovered and colors.textMuted or colors.borderStrong)
            tintPieces(self.fill, self.idleFill)
            self.text:SetTextColor(unpack(hovered and colors.text or colors.textSecondary))
        end
        self:SetAlpha(self:IsEnabled() and 1 or 0.4)
    end
    function chip:SetSelected(value)
        self._selected = value and true or false
        self:Refresh()
    end
    chip:SetScript("OnEnter", function(self)
        self:Refresh()
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    chip:SetScript("OnLeave", function(self)
        self:Refresh()
        if self.tooltip then
            GameTooltip:Hide()
        end
    end)
    chip:HookScript("OnEnable", function(self) self:Refresh() end)
    chip:HookScript("OnDisable", function(self) self:Refresh() end)
    chip:SetScript("OnClick", function(self)
        if onClick then
            onClick(self)
        end
    end)
    chip:SetSelected(false)
    return track(parent, chip)
end

-- Lays chips out in a flowing row starting at the anchor; returns the last.
function LV.Widgets:ChipRow(parent, chips, point, relativeTo, relativePoint, x, y, gap)
    local previous
    for _, chip in ipairs(chips) do
        chip:ClearAllPoints()
        if previous then
            chip:SetPoint("LEFT", previous, "RIGHT", gap or 6, 0)
        else
            chip:SetPoint(point or "LEFT", relativeTo or parent, relativePoint or point or "LEFT", x or 0, y or 0)
        end
        previous = chip
    end
    return previous
end

function LV.Widgets:Section(parent, title, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(height or 42)
    self:ApplyBackdrop(frame, colors.transparent, colors.transparent)
    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT")
    frame.header:SetPoint("TOPRIGHT")
    frame.header:SetHeight(30)
    frame.title = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetText(string.upper(title or ""))
    frame.title:SetTextColor(unpack(colors.sectionTitle))
    frame.title:SetPoint("LEFT", 4, 0)
    frame.title:SetJustifyH("LEFT")
    frame.divider = self:Line(frame.header, 1, colors.border)
    frame.divider:SetPoint("BOTTOMLEFT", 4, 0)
    frame.divider:SetPoint("BOTTOMRIGHT", -4, 0)
    return track(parent, frame)
end

-- Hairline track, slim muted thumb, no step arrows.
function LV.Widgets:StyleScrollBar(bar)
    if not bar or bar._lvStyled then
        return
    end
    bar._lvStyled = true
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton", "Back", "Forward" }) do
        local stepButton = bar[key]
        if stepButton then
            stepButton:SetAlpha(0)
            stepButton:EnableMouse(false)
            if stepButton.SetSize then
                stepButton:SetSize(1, 1)
            end
        end
    end
    local name = bar.GetName and bar:GetName()
    if name then
        for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
            local stepButton = _G[name .. suffix]
            if stepButton then
                stepButton:SetAlpha(0)
                stepButton:EnableMouse(false)
            end
        end
    end
    for _, region in ipairs({ bar:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
    if not bar._lvTrack then
        bar._lvTrack = bar:CreateTexture(nil, "BACKGROUND")
        bar._lvTrack:SetTexture(WHITE_TEXTURE)
        bar._lvTrack:SetVertexColor(unpack(colors.border))
        bar._lvTrack:SetWidth(1)
        bar._lvTrack:SetPoint("TOP", 0, 0)
        bar._lvTrack:SetPoint("BOTTOM", 0, 0)
    end
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture() or bar.ThumbTexture
    if thumb then
        thumb:SetAlpha(1)
        thumb:SetTexture(WHITE_TEXTURE)
        thumb:SetWidth(4)
        thumb:SetVertexColor(unpack(colors.borderStrong))
    end
end

function LV.Widgets:ScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local step = IsShiftKeyDown and IsShiftKeyDown() and 150 or 45
        local nextValue = self:GetVerticalScroll() - ((tonumber(delta) or 0) * step)
        self:SetVerticalScroll(math.max(0, math.min(nextValue, self:GetVerticalScrollRange())))
    end)
    scroll:HookScript("OnSizeChanged", function(_, width)
        child:SetWidth(math.max(1, (tonumber(width) or 1) - 28))
    end)
    self:StyleScrollBar(scroll.ScrollBar)
    track(parent, scroll)
    return scroll, child
end

function LV.Widgets:CycleButton(parent, values, getValue, setValue, width)
    local button
    local function labelFor(value)
        for _, item in ipairs(values) do
            if item.value == value then
                return item.label
            end
        end
        return values[1] and values[1].label or ""
    end

    button = self:Button(parent, "", width or 120, 28, function()
        local current = getValue()
        local nextIndex = 1
        for index, item in ipairs(values) do
            if item.value == current then
                nextIndex = index + 1
                break
            end
        end
        if nextIndex > #values then
            nextIndex = 1
        end
        setValue(values[nextIndex].value)
        button.text:SetText(labelFor(getValue()))
    end)
    button.text:SetText(labelFor(getValue()))
    return button
end

function LV.Widgets:Dropdown(parent, values, getValue, setValue, width, maxVisible)
    local button = self:Button(parent, "", width or 120, 28, nil, "control")
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 10, 0)
    button.text:SetPoint("RIGHT", -24, 0)
    button.text:SetJustifyH("LEFT")
    button.chevron = self:Glyph(button, "chevron", 12, colors.textMuted)
    button.chevron:SetPoint("RIGHT", -8, 0)
    button.arrow = button.chevron
    button.menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    button.menu:SetWidth(width or 120)
    button.menu:SetFrameStrata("TOOLTIP")
    button.menu:SetFrameLevel(button:GetFrameLevel() + 50)
    button.menu:Hide()
    self:ApplyBackdrop(button.menu, colors.canvasAlt, colors.borderStrong)

    local function labelFor(value)
        for _, item in ipairs(values) do
            if item.value == value then
                return item.label
            end
        end
        return values[1] and values[1].label or ""
    end

    local function refresh()
        button.text:SetText(labelFor(getValue()))
    end
    button.Refresh = refresh

    maxVisible = math.max(1, math.floor(tonumber(maxVisible) or #values))
    local rowParent = button.menu
    local scrollContent
    if #values > maxVisible then
        local scroll = CreateFrame("ScrollFrame", nil, button.menu, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 2, -2)
        scroll:SetPoint("BOTTOMRIGHT", -2, 2)
        scrollContent = CreateFrame("Frame", nil, scroll)
        scrollContent:SetSize(math.max(1, (width or 120) - 24), #values * 24)
        scroll:SetScrollChild(scrollContent)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local nextValue = self:GetVerticalScroll() - ((tonumber(delta) or 0) * 48)
            self:SetVerticalScroll(math.max(0, math.min(nextValue, self:GetVerticalScrollRange())))
        end)
        rowParent = scrollContent
        button.menu.scroll = scroll
        self:StyleScrollBar(scroll.ScrollBar)
    end

    for index, item in ipairs(values) do
        local itemValue = item.value
        local row = self:Button(rowParent, item.label, width or 120, 24, function()
            setValue(itemValue)
            button.menu:Hide()
            refresh()
        end, "menu")
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row:SetPoint("RIGHT", #values > maxVisible and -20 or 0, 0)
    end

    button.menu:SetHeight(math.max(1, math.min(#values, maxVisible)) * 24 + (#values > maxVisible and 4 or 0))
    button:SetScript("OnClick", function()
        if button.menu:IsShown() then
            button.menu:Hide()
        else
            button.menu:Show()
            button.menu:Raise()
        end
    end)
    button:SetScript("OnHide", function()
        button.menu:Hide()
    end)
    refresh()
    return button
end

function LV.Widgets:MultiSelectDropdown(parent, values, getSelected, setSelected, width)
    values = values or {}
    local button = self:Button(parent, "", width or 180, 28, nil, "control")
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 10, 0)
    button.text:SetPoint("RIGHT", -24, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)
    button.chevron = self:Glyph(button, "chevron", 12, colors.textMuted)
    button.chevron:SetPoint("RIGHT", -8, 0)
    button.arrow = button.chevron

    button.menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    button.menu:SetWidth(width or 180)
    button.menu:SetHeight(math.max(1, #values) * 24)
    button.menu:SetFrameStrata("TOOLTIP")
    button.menu:SetFrameLevel(button:GetFrameLevel() + 50)
    button.menu:Hide()
    self:ApplyBackdrop(button.menu, colors.canvasAlt, colors.borderStrong)

    local rows = {}
    local function refresh()
        local selected = getSelected() or {}
        local labels = {}
        for index, item in ipairs(values) do
            local checked = selected[item.value] == true
            if checked then
                labels[#labels + 1] = item.label
            end
            if rows[index] and rows[index].text then
                rows[index].text:SetText((checked and "[x] " or "[ ] ") .. item.label)
                rows[index].text:SetTextColor(unpack(checked and colors.text or colors.textMuted))
            end
        end
        button.text:SetText(#labels > 0 and table.concat(labels, ", ") or "Select teams")
    end
    button.Refresh = refresh

    for index, item in ipairs(values) do
        local itemValue = item.value
        local row = self:Button(button.menu, item.label, width or 180, 24, function()
            local selected = getSelected() or {}
            setSelected(itemValue, selected[itemValue] ~= true)
            refresh()
        end, "ghost")
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row:SetPoint("RIGHT", 0, 0)
        rows[index] = row
    end

    button:SetScript("OnClick", function()
        if button.menu:IsShown() then
            button.menu:Hide()
        else
            refresh()
            button.menu:Show()
            button.menu:Raise()
        end
    end)
    button:SetScript("OnHide", function()
        button.menu:Hide()
    end)
    refresh()
    return button
end

function LV.Widgets:SearchDropdown(parent, values, getValue, setValue, width, maxVisible)
    values = values or {}
    maxVisible = math.max(1, math.floor(tonumber(maxVisible) or 6))
    local edit = self:EditBox(parent, width or 180, 28)
    local menu = CreateFrame("Frame", nil, edit, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width or 180)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(edit:GetFrameLevel() + 50)
    menu:Hide()
    self:ApplyBackdrop(menu, colors.canvasAlt, colors.borderStrong)

    local rows = {}
    local function hideMenu()
        menu:Hide()
    end
    local function refreshMatches()
        local query = LV.Util:Trim(edit:GetText()):lower()
        local matches = {}
        for _, item in ipairs(values) do
            local label = tostring(item.label or "")
            local value = tostring(item.value or "")
            if query == "" or label:lower():find(query, 1, true) or value:lower():find(query, 1, true) then
                matches[#matches + 1] = item
                if #matches >= maxVisible then
                    break
                end
            end
        end

        for index, row in ipairs(rows) do
            local item = matches[index]
            row._lvItem = item
            row:SetShown(item ~= nil)
            if item then
                row.text:SetText(item.label)
            end
        end
        menu:SetHeight(math.max(1, #matches) * 24)
        menu:SetShown(#matches > 0 and edit:HasFocus())
        if menu:IsShown() then
            menu:Raise()
        end
    end

    local function selectSearchItem(clicked)
        local item = clicked and clicked._lvItem
        if not item then
            return
        end
        -- Select on mouse-down because clicking a result first removes focus
        -- from the edit box. Waiting for OnClick lets the focus-loss handler
        -- hide the result button before it receives mouse-up.
        edit:SetText(item.label)
        setValue(item.value, item)
        edit:ClearFocus()
        hideMenu()
    end

    for index = 1, maxVisible do
        local row = self:Button(menu, "", width or 180, 24, nil, "ghost")
        row:HookScript("OnMouseDown", function(clicked, mouseButton)
            if mouseButton == "LeftButton" then
                selectSearchItem(clicked)
            end
        end)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row:SetPoint("RIGHT", 0, 0)
        rows[index] = row
    end

    edit:SetScript("OnTextChanged", function(self)
        setValue(self:GetText(), nil)
        refreshMatches()
    end)
    edit:HookScript("OnEditFocusGained", refreshMatches)
    edit:HookScript("OnEditFocusLost", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, hideMenu)
        else
            hideMenu()
        end
    end)
    edit:HookScript("OnHide", hideMenu)
    edit:SetText(getValue() or "")
    edit.menu = menu
    return edit
end
