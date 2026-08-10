local _, Addon = ...

local hookInstalled = false
local settingApplied = false
local updatePending = false

local function IsEnabled()
    return Addon:GetSetting("fixedMicroMenu")
end

local function UpdateQueuePosition(useFixedPosition)
    local container = MicroMenuContainer
    local positionEnum = MicroMenuPositionEnum
    if not container or not positionEnum or not MicroMenu then
        return
    end

    local position = container:GetPosition()
    if useFixedPosition then
        if position == positionEnum.TopLeft or position == positionEnum.TopRight then
            position = positionEnum.TopRight
        else
            position = positionEnum.BottomRight
        end
    end

    if QueueStatusButton and QueueStatusButton.UpdatePosition then
        QueueStatusButton:UpdatePosition(position, MicroMenu.isHorizontal)
    end
    if QueueStatusFrame and QueueStatusFrame.UpdatePosition then
        QueueStatusFrame:UpdatePosition(position, MicroMenu.isHorizontal)
    end
end

local function InstallHook()
    if hookInstalled or not MicroMenu or not MicroMenu.Layout then
        return
    end
    hooksecurefunc(MicroMenu, "Layout", function()
        if IsEnabled() then
            UpdateQueuePosition(true)
        end
    end)
    hookInstalled = true
end

local function ApplySetting()
    if not MicroMenuContainer or not MicroMenu then
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
        settingApplied = true
    else
        settingApplied = false
    end
    if MicroMenuContainer.Layout then
        MicroMenuContainer:Layout()
    end
    UpdateQueuePosition(IsEnabled())
end

Addon:RegisterSetting("fixedMicroMenu", false, Addon.BooleanSetting, ApplySetting)
Addon:RegisterEvent("PLAYER_LOGIN", ApplySetting)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", ApplySetting)
Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if updatePending then
        ApplySetting()
    end
end)
Addon:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", ApplySetting, IsEnabled)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_MicroMenu" then
        ApplySetting()
    end
end)

