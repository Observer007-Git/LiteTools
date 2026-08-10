local _, Addon = ...

local HOTKEY_ALIASES = {
    MOUSEWHEELUP = "MU",
    MOUSEWHEELDOWN = "MD",
    PAGEUP = "PU",
    PAGEDOWN = "PD",
}
local MODIFIER_ALIASES = { SHIFT = "S", CTRL = "C", ALT = "A" }

local hookInstalled = false
local settingApplied = false
local updatePending = false

local function IsEnabled()
    return Addon:GetSetting("customActionBarHotkeyAliases")
end

local function GetAliasPart(keyPart)
    if HOTKEY_ALIASES[keyPart] then
        return HOTKEY_ALIASES[keyPart]
    end
    local numpadNumber = keyPart:match("^NUMPAD(%d)$")
    if numpadNumber then
        return "N" .. numpadNumber
    end
    local mouseButton = keyPart:match("^BUTTON(%d+)$")
    if mouseButton then
        return "M" .. mouseButton
    end
    local localizedText = GetBindingText(keyPart, 1)
    return localizedText and localizedText ~= "" and localizedText or keyPart
end

local function GetAlias(key)
    local parts = {}
    local remainingKey = key
    while true do
        local modifier, nextKey = remainingKey:match("^([^-]+)%-(.+)$")
        local modifierAlias = modifier and MODIFIER_ALIASES[modifier]
        if not modifierAlias then
            break
        end
        parts[#parts + 1] = modifierAlias
        remainingKey = nextKey
    end
    parts[#parts + 1] = GetAliasPart(remainingKey)
    return table.concat(parts, "+")
end

local function ApplyAlias(button)
    if not IsEnabled() or not button or not button.HotKey or not button.bindingAction then
        return
    end
    local key = GetBindingKey(button.bindingAction)
    local buttonName = button:GetName()
    if not key and buttonName then
        key = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
    end
    if not key or IsBindingForGamePad(key) then
        return
    end
    local alias = GetAlias(key)
    if alias ~= "" then
        button.HotKey:SetText(alias)
    end
end

local function HookButton(button)
    if not button or not button.UpdateHotkeys or button.liteToolsHotkeyHooked then
        return
    end
    hooksecurefunc(button, "UpdateHotkeys", ApplyAlias)
    button.liteToolsHotkeyHooked = true
end

local function InstallHook()
    if hookInstalled or not ActionBarButtonEventsFrame then
        return
    end
    if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateHotkeys then
        hooksecurefunc(ActionBarActionButtonMixin, "UpdateHotkeys", ApplyAlias)
    end
    ActionBarButtonEventsFrame:ForEachFrame(HookButton)
    hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, button)
        if IsEnabled() then
            HookButton(button)
        end
    end)
    hookInstalled = true
end

local function RefreshButton(button)
    if button and button.UpdateHotkeys then
        button:UpdateHotkeys(button.buttonType)
    end
end

local function ApplySetting()
    if not ActionBarButtonEventsFrame or not ActionBarButtonEventsFrame.ForEachFrame then
        return
    end
    if not IsEnabled() and not settingApplied then
        return
    end
    if InCombatLockdown() then
        updatePending = true
        return
    end

    updatePending = false
    if IsEnabled() then
        InstallHook()
        if not hookInstalled then
            return
        end
    end
    ActionBarButtonEventsFrame:ForEachFrame(RefreshButton)
    settingApplied = IsEnabled()
end

Addon:RegisterSetting("customActionBarHotkeyAliases", false, Addon.BooleanSetting, ApplySetting)
Addon:RegisterEvent("PLAYER_LOGIN", ApplySetting)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", ApplySetting)
Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if updatePending then
        ApplySetting()
    end
end)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_ActionBar" then
        ApplySetting()
    end
end)

