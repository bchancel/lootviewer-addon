local _, LV = ...

LV.Widgets = {}

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local colors = {
    transparent = { 0.000, 0.000, 0.000, 0.00 },
    overlay = { 0.000, 0.000, 0.000, 0.58 },
    canvas = { 0.035, 0.064, 0.084, 0.99 },
    canvasAlt = { 0.047, 0.086, 0.112, 0.99 },
    control = { 0.018, 0.038, 0.054, 1.00 },
    surface = { 0.064, 0.116, 0.150, 0.98 },
    surfaceRaised = { 0.082, 0.150, 0.190, 0.99 },
    surfaceHover = { 0.070, 0.190, 0.245, 1.00 },
    surfacePressed = { 0.035, 0.230, 0.340, 1.00 },
    accentSoft = { 0.025, 0.210, 0.315, 0.96 },
    accent = { 0.035, 0.610, 0.875, 1.00 },
    accentBright = { 0.210, 0.790, 1.000, 1.00 },
    border = { 0.140, 0.240, 0.300, 1.00 },
    borderStrong = { 0.120, 0.360, 0.460, 1.00 },
    borderFocus = { 0.075, 0.610, 0.830, 1.00 },
    text = { 0.925, 0.955, 0.975, 1.00 },
    textSecondary = { 0.725, 0.790, 0.835, 1.00 },
    textMuted = { 0.500, 0.590, 0.660, 1.00 },
    navigation = { 0.340, 0.860, 0.560, 1.00 },
    success = { 0.025, 0.360, 0.310, 1.00 },
    successBorder = { 0.070, 0.760, 0.640, 1.00 },
    danger = { 0.310, 0.055, 0.070, 0.92 },
    dangerBorder = { 0.760, 0.180, 0.200, 1.00 },
}

-- Compatibility aliases used by the existing renderers.
colors.bg = colors.canvas
colors.panel = colors.canvasAlt
colors.header = colors.surfaceRaised
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

local buttonStyles = {
    secondary = {
        normal = { colors.surfaceRaised, colors.border, colors.textSecondary },
        hover = { colors.surfaceHover, colors.borderFocus, colors.text },
        pressed = { colors.surfacePressed, colors.borderFocus, colors.text },
    },
    primary = {
        normal = { colors.accentSoft, colors.accent, colors.text },
        hover = { colors.surfacePressed, colors.accentBright, colors.text },
        pressed = { colors.surfaceHover, colors.accentBright, colors.text },
    },
    success = {
        normal = { colors.success, colors.successBorder, colors.text },
        hover = { colors.success, colors.text, colors.text },
        pressed = { colors.surfaceHover, colors.successBorder, colors.text },
    },
    danger = {
        normal = { colors.danger, colors.dangerBorder, colors.text },
        hover = { colors.danger, colors.text, colors.text },
        pressed = { colors.surfaceHover, colors.dangerBorder, colors.text },
    },
    ghost = {
        normal = { colors.transparent, colors.transparent, colors.textMuted },
        hover = { colors.surfaceHover, colors.borderStrong, colors.text },
        pressed = { colors.surfacePressed, colors.borderFocus, colors.text },
    },
    navigation = {
        normal = { colors.transparent, colors.transparent, colors.textMuted },
        hover = { colors.surface, colors.transparent, colors.text },
        pressed = { colors.surfaceHover, colors.transparent, colors.text },
        active = { colors.surface, colors.border, colors.text },
    },
    tab = {
        normal = { colors.transparent, colors.transparent, colors.textMuted },
        hover = { colors.surface, colors.transparent, colors.text },
        pressed = { colors.surfaceHover, colors.transparent, colors.text },
        active = { colors.transparent, colors.transparent, colors.accentBright },
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
    if button.icon then
        local tint = button._lvActive and colors.navigation
            or ((state == "hover" or state == "pressed") and colors.text or colors.textSecondary)
        button.icon:SetVertexColor(unpack(tint))
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
    button.text:SetPoint("LEFT", 46, 0)
    button.text:SetJustifyH("LEFT")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("LEFT", 18, 0)
    button.icon:SetTexture(iconTexture)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon:SetDesaturated(true)
    button._lvNavigationLine = self:Line(button, 1, colors.navigation)
    button._lvNavigationLine:ClearAllPoints()
    button._lvNavigationLine:SetPoint("TOPLEFT", 4, -5)
    button._lvNavigationLine:SetPoint("BOTTOMLEFT", 4, 5)
    button._lvNavigationLine:SetWidth(3)
    button._lvNavigationLine:Hide()
    self:ApplyButtonState(button, "normal")
    return button
end

function LV.Widgets:Tab(parent, text, width, height, onClick)
    local button = self:Button(parent, text, width, height, onClick, "tab")
    button._lvTabLine = self:Line(button, 2, colors.accentBright)
    button._lvTabLine:SetPoint("BOTTOMLEFT")
    button._lvTabLine:SetPoint("BOTTOMRIGHT")
    button._lvTabLine:Hide()
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

    if kind == "copy" then
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
    if kind == "trash" or kind == "exclude" then
        normalColor = colors.dangerBorder
    elseif kind == "edit" or kind == "gear" then
        normalColor = colors.accentBright
    end
    setActionIconColor(button, normalColor)
    button:HookScript("OnEnter", function()
        setActionIconColor(button, colors.text)
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
        self:SetBackdropColor(unpack(colors.surface))
        self:SetBackdropBorderColor(unpack(colors.borderFocus))
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return track(parent, edit)
end

local function updateToggle(check)
    local checked = check:GetChecked() and true or false
    LV.Widgets:ApplyBackdrop(
        check,
        checked and colors.accentSoft or colors.surfaceRaised,
        checked and colors.accent or colors.border
    )
    check.knob:ClearAllPoints()
    check.knob:SetPoint("CENTER", check, "CENTER", checked and 10 or -10, 0)
    check.knob:SetVertexColor(unpack(checked and colors.accentBright or colors.textSecondary))
end

function LV.Widgets:Check(parent, text, onChanged)
    local check = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    check:SetSize(42, 22)
    check.knob = check:CreateTexture(nil, "OVERLAY")
    check.knob:SetTexture(WHITE_TEXTURE)
    check.knob:SetSize(14, 14)
    check.label = self:Text(check, text or "")
    check.label:SetPoint("LEFT", check, "RIGHT", 8, 0)
    check.label:SetTextColor(unpack(colors.textSecondary))
    local originalSetChecked = check.SetChecked
    check.SetChecked = function(self, value)
        originalSetChecked(self, value)
        updateToggle(self)
    end
    check:SetScript("OnClick", function(self)
        updateToggle(self)
        if onChanged then
            onChanged(self:GetChecked() and true or false)
        end
    end)
    check:SetScript("OnEnter", function(self)
        local checked = self:GetChecked() and true or false
        LV.Widgets:ApplyBackdrop(
            self,
            checked and colors.accentSoft or colors.surfaceHover,
            checked and colors.accentBright or colors.borderFocus
        )
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
    frame.title:SetTextColor(unpack(colors.navigation))
    frame.title:SetPoint("LEFT", 4, 0)
    frame.title:SetJustifyH("LEFT")
    frame.divider = self:Line(frame.header, 1, colors.border)
    frame.divider:SetPoint("BOTTOMLEFT", 4, 0)
    frame.divider:SetPoint("BOTTOMRIGHT", -4, 0)
    return track(parent, frame)
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
    local bar = scroll.ScrollBar
    if bar then
        if bar.Background then
            bar.Background:SetTexture(WHITE_TEXTURE)
            bar.Background:SetVertexColor(unpack(colors.canvas))
        end
        local thumb = bar.GetThumbTexture and bar:GetThumbTexture() or bar.ThumbTexture
        if thumb then
            thumb:SetTexture(WHITE_TEXTURE)
            thumb:SetWidth(6)
            thumb:SetVertexColor(unpack(colors.accent))
        end
    end
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
    local button = self:Button(parent, "", width or 120, 28)
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 10, 0)
    button.text:SetPoint("RIGHT", -24, 0)
    button.text:SetJustifyH("LEFT")
    button.arrow = self:Label(button, "v")
    button.arrow:SetPoint("RIGHT", -8, 1)
    button.arrow:SetTextColor(unpack(colors.accentBright))
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
    end

    for index, item in ipairs(values) do
        local itemValue = item.value
        local row = self:Button(rowParent, item.label, width or 120, 24, function()
            setValue(itemValue)
            button.menu:Hide()
            refresh()
        end, "ghost")
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
    local button = self:Button(parent, "", width or 180, 28)
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 10, 0)
    button.text:SetPoint("RIGHT", -24, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetWordWrap(false)
    button.arrow = self:Label(button, "v")
    button.arrow:SetPoint("RIGHT", -8, 1)
    button.arrow:SetTextColor(unpack(colors.accentBright))

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
