local _, Addon = ...

local DEFAULT_WIDTH = 571
local resizePending = false
local updateQueued = false
local widthHookInstalled = false
local visibilityHookInstalled = false

local function DB()
    return Addon:GetDatabase()
end

local function HasCustomWidths()
    local db = DB()
    return db and (
        db.experienceBarWidth ~= DEFAULT_WIDTH
        or db.reputationBarWidth ~= DEFAULT_WIDTH
        or db.honorBarWidth ~= DEFAULT_WIDTH
    )
end

local function HasHiddenBars()
    local db = DB()
    return db and (db.hideExperienceBar or db.hideReputationBar or db.hideHonorBar)
end

local function GetBarWidth(barIndex)
    local db = DB()
    local barsEnum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    if not db or not barsEnum then
        return DEFAULT_WIDTH
    end
    if barIndex == barsEnum.Experience then
        return db.experienceBarWidth
    elseif barIndex == barsEnum.Reputation then
        return db.reputationBarWidth
    elseif barIndex == barsEnum.Honor then
        return db.honorBarWidth
    end
    return DEFAULT_WIDTH
end

local function ResizeContainer(container, barIndex)
    if not container or not container.bars then
        return
    end
    if InCombatLockdown() then
        resizePending = true
        return
    end

    local width = GetBarWidth(barIndex)
    local innerWidth = math.max(1, width - 6)
    local bar = container.bars[barIndex]
    if math.abs(container:GetWidth() - width) > 0.01 then
        container:SetWidth(width)
        if container.BarFrameTexture then
            container.BarFrameTexture:SetWidth(width)
        end
    end
    if bar and math.abs(bar:GetWidth() - innerWidth) > 0.01 then
        bar:SetWidth(innerWidth)
        if bar.StatusBar then
            bar.StatusBar:SetWidth(innerWidth)
        end
        if container.shownBarIndex == barIndex and bar.UpdateTick then
            bar:UpdateTick()
        end
    end
end

local function ApplyWidths()
    local manager = StatusTrackingBarManager
    if not manager or not manager.barContainers then
        return
    end
    for _, container in ipairs(manager.barContainers) do
        ResizeContainer(container, container.pendingBarToShowIndex or container.shownBarIndex)
    end
end

local function QueueWidthUpdate()
    if updateQueued then
        return
    end
    updateQueued = true
    C_Timer.After(0, function()
        updateQueued = false
        ApplyWidths()
    end)
end

local function IsBarHidden(barIndex)
    local db = DB()
    local barsEnum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    if not db or not barsEnum then
        return false
    end
    return (barIndex == barsEnum.Experience and db.hideExperienceBar)
        or (barIndex == barsEnum.Reputation and db.hideReputationBar)
        or (barIndex == barsEnum.Honor and db.hideHonorBar)
end

local function ApplyContainerVisibility(container)
    if not container then
        return
    end
    local barIndex = container.pendingBarToShowIndex or container.shownBarIndex
    if IsBarHidden(barIndex) then
        container:Hide()
        return
    end
    local noneIndex = StatusTrackingBarInfo
        and StatusTrackingBarInfo.BarsEnum
        and StatusTrackingBarInfo.BarsEnum.None
    if barIndex and barIndex ~= noneIndex then
        container:Show()
    end
end

local function ApplyVisibility()
    local manager = StatusTrackingBarManager
    if not manager or not manager.barContainers then
        return
    end
    for _, container in ipairs(manager.barContainers) do
        ApplyContainerVisibility(container)
    end
end

local function InstallVisibilityHook()
    if visibilityHookInstalled or not StatusTrackingBarContainerMixin then
        return
    end
    hooksecurefunc(StatusTrackingBarContainerMixin, "SetShownBar", function(container)
        if HasHiddenBars() then
            ApplyContainerVisibility(container)
        end
    end)
    if StatusTrackingBarContainerMixin.UpdateShownState then
        hooksecurefunc(StatusTrackingBarContainerMixin, "UpdateShownState", function(container)
            if HasHiddenBars() then
                ApplyContainerVisibility(container)
            end
        end)
    end
    visibilityHookInstalled = true
end

local function InstallWidthHook()
    if widthHookInstalled or not StatusTrackingBarContainerMixin then
        return
    end
    hooksecurefunc(StatusTrackingBarContainerMixin, "SetShownBar", function(container, barIndex)
        if HasCustomWidths() then
            ResizeContainer(container, barIndex)
        end
    end)
    widthHookInstalled = true
end

local function ApplyAll(immediateWidth)
    if HasCustomWidths() then
        InstallWidthHook()
        if immediateWidth then
            ApplyWidths()
        else
            QueueWidthUpdate()
        end
    end
    if HasHiddenBars() then
        InstallVisibilityHook()
        ApplyVisibility()
    end
end

for _, key in ipairs({ "experienceBarWidth", "reputationBarWidth", "honorBarWidth" }) do
    Addon:RegisterSetting(key, DEFAULT_WIDTH, Addon.NumberSetting(200, 1200), function()
        InstallWidthHook()
        QueueWidthUpdate()
    end)
end
for _, key in ipairs({ "hideExperienceBar", "hideReputationBar", "hideHonorBar" }) do
    Addon:RegisterSetting(key, false, Addon.BooleanSetting, function(value)
        if value then
            InstallVisibilityHook()
        end
        ApplyVisibility()
    end)
end

Addon:RegisterEvent("PLAYER_LOGIN", function() ApplyAll(true) end)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function() ApplyAll(false) end)
Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if resizePending then
        resizePending = false
        QueueWidthUpdate()
    end
end)
Addon:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", QueueWidthUpdate, HasCustomWidths)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_ActionBar" then
        ApplyAll(true)
    end
end)
