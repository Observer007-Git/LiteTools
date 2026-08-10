local _, Addon = ...

local CHILD_BUTTONS = {
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
    "CharacterReagentBag0Slot",
}

local hooksInstalled = false
local settingApplied = false
local updatePending = false
local originalHideExpandToggle

local function DB()
    return Addon:GetDatabase()
end

local function IsEnabled()
    local db = DB()
    return db and (db.hideChildBags or db.hideAllBagButtons)
end

local function HideChildren(hideBackpack)
    if BagBarExpandToggle then
        BagBarExpandToggle:Hide()
    end
    for _, buttonName in ipairs(CHILD_BUTTONS) do
        local button = _G[buttonName]
        if button then
            button:Hide()
        end
    end
    if MainMenuBarBackpackButton then
        MainMenuBarBackpackButton:SetShown(not hideBackpack)
    end
end

local function CollapseBar()
    if not BagsBar or not MainMenuBarBackpackButton then
        return
    end
    local width, height = MainMenuBarBackpackButton:GetSize()
    if width and height and width > 0 and height > 0 then
        BagsBar:SetSize(width, height)
    end
end

local function InstallHooks()
    if hooksInstalled or not BagsBar or not BagsBar.Layout then
        return
    end
    hooksecurefunc(BagsBar, "Layout", function()
        local db = DB()
        if db and (db.hideChildBags or db.hideAllBagButtons) then
            if InCombatLockdown() then
                updatePending = true
                return
            end
            HideChildren(db.hideAllBagButtons)
            if not db.hideAllBagButtons then
                CollapseBar()
            end
        end
    end)
    hooksInstalled = true
end

local function ApplySetting()
    local db = DB()
    if not db or not BagsBar or not MainMenuBarBackpackButton then
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
        InstallHooks()
        if not settingApplied then
            originalHideExpandToggle = BagsBar.hideExpandToggle
        end
        settingApplied = true
        BagsBar.hideExpandToggle = true
        HideChildren(db.hideAllBagButtons)
        if BagsBar.Layout then
            BagsBar:Layout()
        end
        if db.hideAllBagButtons then
            HideChildren(true)
        else
            CollapseBar()
        end
        return
    end

    BagsBar.hideExpandToggle = originalHideExpandToggle
    if MainMenuBarBagManager and MainMenuBarBagManager.OnExpandBarChanged then
        MainMenuBarBagManager:OnExpandBarChanged()
    end
    MainMenuBarBackpackButton:Show()
    if CharacterReagentBag0Slot then
        CharacterReagentBag0Slot:Show()
    end
    if BagBarExpandToggle then
        BagBarExpandToggle:SetShown(not BagsBar.hideExpandToggle)
    end
    if BagsBar.Layout then
        BagsBar:Layout()
    end
    settingApplied = false
end

Addon:RegisterSetting("hideChildBags", false, Addon.BooleanSetting, ApplySetting)
Addon:RegisterSetting("hideAllBagButtons", false, Addon.BooleanSetting, ApplySetting)
Addon:RegisterEvent("PLAYER_LOGIN", ApplySetting)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", ApplySetting)
Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if updatePending then
        ApplySetting()
    end
end)
Addon:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", ApplySetting, IsEnabled)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_MainMenuBarBagButtons" then
        ApplySetting()
    end
end)

