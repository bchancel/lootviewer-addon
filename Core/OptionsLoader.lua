local _, LV = ...

LV.OptionsLoader = {
    pendingCallbacks = {},
    combatNoticeShown = false,
}
LV.modules.OptionsLoader = LV.OptionsLoader

function LV.OptionsLoader:IsLoaded()
    if LV.UI and type(LV.UI.RenderConfig) == "function" then
        return true
    end
    return C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("LootViewer_Options") == true
end

function LV.OptionsLoader:EnsureLoaded()
    if self:IsLoaded() and LV.UI and type(LV.UI.RenderConfig) == "function" then
        return true
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "combat"
    end
    if not (C_AddOns and C_AddOns.LoadAddOn) then
        return false, "C_AddOns.LoadAddOn is unavailable"
    end

    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, "LootViewer_Options")
    if not ok then
        return false, tostring(loaded or "options load failed")
    end
    if loaded ~= true and not self:IsLoaded() then
        return false, tostring(reason or "LootViewer_Options is disabled or missing")
    end
    if not (LV.UI and type(LV.UI.RenderConfig) == "function") then
        return false, "LootViewer_Options loaded without registering Configuration"
    end
    return true
end

function LV.OptionsLoader:EnsureCombatFrame()
    if self.combatFrame then
        return self.combatFrame
    end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function()
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        LV.OptionsLoader.combatNoticeShown = false
        local callbacks = LV.OptionsLoader.pendingCallbacks
        LV.OptionsLoader.pendingCallbacks = {}
        for _, callback in ipairs(callbacks) do
            LV.OptionsLoader:Run(callback)
        end
    end)
    self.combatFrame = frame
    return frame
end

function LV.OptionsLoader:Run(callback)
    if type(callback) ~= "function" then
        return false, "options callback is invalid"
    end
    if InCombatLockdown and InCombatLockdown() then
        self:EnsureCombatFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        self.pendingCallbacks[#self.pendingCallbacks + 1] = callback
        if not self.combatNoticeShown then
            self.combatNoticeShown = true
            LV:Print("Configuration will open after combat ends.")
        end
        return false, "queued"
    end

    local loaded, reason = self:EnsureLoaded()
    if not loaded then
        LV:Print("Configuration could not load: " .. tostring(reason or "unknown error") .. ".")
        return false, reason
    end
    local ok, callbackError = pcall(callback)
    if not ok then
        LV:Print("Configuration could not open: " .. tostring(callbackError or "unknown error") .. ".")
        return false, callbackError
    end
    return true
end
