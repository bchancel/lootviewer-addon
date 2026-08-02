local _, LV = ...

LV.Widgets = {}

local colors = {
    bg = { 0.06, 0.08, 0.12, 0.99 },
    panel = { 0.08, 0.11, 0.17, 0.98 },
    header = { 0.11, 0.16, 0.25, 0.98 },
    border = { 0.22, 0.32, 0.45, 1 },
    active = { 0.05, 0.42, 0.82, 1 },
    yellow = { 1.0, 0.84, 0.0, 1 },
    white = { 0.95, 0.95, 0.95, 1 },
    muted = { 0.58, 0.62, 0.68, 1 },
    danger = { 0.45, 0.08, 0.1, 1 },
}

LV.Widgets.colors = colors

local function track(parent, region)
    if parent and parent._lvTrackDirect and LV.UI and LV.UI.Track then
        LV.UI:Track(region)
    end
    return region
end

local backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

function LV.Widgets:ApplyBackdrop(frame, color, borderColor)
    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(unpack(color or colors.panel))
    frame:SetBackdropBorderColor(unpack(borderColor or colors.border))
end

function LV.Widgets:Label(parent, text, size)
    local font = parent:CreateFontString(nil, "OVERLAY", size == "large" and "GameFontNormalLarge" or "GameFontNormal")
    font:SetText(text or "")
    font:SetTextColor(unpack(colors.yellow))
    font:SetJustifyH("LEFT")
    return track(parent, font)
end

function LV.Widgets:Text(parent, text, size)
    local font = parent:CreateFontString(nil, "OVERLAY", size == "large" and "GameFontHighlightLarge" or "GameFontHighlight")
    font:SetText(text or "")
    font:SetTextColor(unpack(colors.white))
    font:SetJustifyH("LEFT")
    return track(parent, font)
end

function LV.Widgets:Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 120, height or 28)
    self:ApplyBackdrop(button, colors.header, colors.border)
    button.text = self:Text(button, text or "")
    button.text:SetPoint("CENTER")
    button:SetScript("OnEnter", function()
        button:SetBackdropColor(unpack(colors.active))
        if button.tooltip then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(button.tooltip)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        button:SetBackdropColor(unpack(button._active and colors.active or colors.header))
        if button.tooltip then
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnClick", function()
        if onClick then
            onClick(button)
        end
    end)
    return track(parent, button)
end

function LV.Widgets:SetButtonActive(button, active)
    button._active = active and true or false
    button:SetBackdropColor(unpack(active and colors.active or colors.header))
end

function LV.Widgets:SetTooltip(frame, text)
    if frame then
        frame.tooltip = text
    end
end

function LV.Widgets:EditBox(parent, width, height, onCommit)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width or 120, height or 28)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlight)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onCommit then
            onCommit(self:GetText())
        end
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if onCommit then
            onCommit(self:GetText())
        end
    end)
    return track(parent, edit)
end

function LV.Widgets:Check(parent, text, onChanged)
    local check = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
    check.Text:SetText(text or "")
    check.Text:SetTextColor(unpack(colors.yellow))
    check:SetScript("OnClick", function(self)
        if onChanged then
            onChanged(self:GetChecked() and true or false)
        end
    end)
    return track(parent, check)
end

function LV.Widgets:Section(parent, title, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetHeight(height or 42)
    self:ApplyBackdrop(frame, colors.panel, colors.border)
    frame.header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.header:SetPoint("TOPLEFT")
    frame.header:SetPoint("TOPRIGHT")
    frame.header:SetHeight(30)
    self:ApplyBackdrop(frame.header, colors.header, colors.border)
    frame.title = self:Label(frame.header, title or "")
    frame.title:SetPoint("LEFT", 12, 0)
    return track(parent, frame)
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

function LV.Widgets:Dropdown(parent, values, getValue, setValue, width)
    local button = self:Button(parent, "", width or 120, 28)
    button.menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    button.menu:SetWidth(width or 120)
    button.menu:SetFrameStrata("TOOLTIP")
    button.menu:SetFrameLevel(button:GetFrameLevel() + 50)
    button.menu:Hide()
    self:ApplyBackdrop(button.menu, colors.panel, colors.border)

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

    for index, item in ipairs(values) do
        local row = self:Button(button.menu, item.label, width or 120, 24, function()
            setValue(item.value)
            button.menu:Hide()
            refresh()
        end)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
        row:SetPoint("RIGHT", 0, 0)
    end

    button.menu:SetHeight(math.max(1, #values) * 24)
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
