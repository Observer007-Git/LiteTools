local ADDON_NAME, Addon = ...

local DEFAULT_STATUS_BAR_WIDTH = 571

local DEFAULTS = {
    autoTypeDelete = false,
    skipCinematics = false,
    experienceBarWidth = DEFAULT_STATUS_BAR_WIDTH,
    reputationBarWidth = DEFAULT_STATUS_BAR_WIDTH,
    fixedMicroMenu = false,
    showInstanceProgress = false,
    autoSellJunk = false,
}

Addon.defaults = DEFAULTS

local eventFrame = CreateFrame("Frame")
local db

local menuOriginalGetPosition
local menuFixedGetPosition
local barHooksInstalled = false
local cinematicHooksInstalled = false
local deleteHookInstalled = false
local clockHookInstalled = false
local barResizePending = false
local barUpdateQueued = false
local junkSaleTicker
local junkSaleQueue = {}
local junkSaleIndex = 1

local instanceCache = {
    ready = false,
    entries = {},
    lastRequestTime = nil,
}

local DELETE_CONFIRM_DIALOGS = {
    DELETE_ITEM = true,
    DELETE_GOOD_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
}

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function InitializeDatabase()
    if type(FansWowToolsDB) ~= "table" then
        FansWowToolsDB = {}
    end

    db = FansWowToolsDB
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then
            db[key] = value
        end
    end

    db.autoTypeDelete = not not db.autoTypeDelete
    db.skipCinematics = not not db.skipCinematics
    db.fixedMicroMenu = not not db.fixedMicroMenu
    db.showInstanceProgress = not not db.showInstanceProgress
    db.autoSellJunk = not not db.autoSellJunk
    db.experienceBarWidth = math.floor(Clamp(db.experienceBarWidth, 200, 1200) + 0.5)
    db.reputationBarWidth = math.floor(Clamp(db.reputationBarWidth, 200, 1200) + 0.5)
end

function Addon:GetSetting(key)
    if db then
        return db[key]
    end
    return DEFAULTS[key]
end

local function GetBarWidth(barIndex)
    local barInfo = StatusTrackingBarInfo
    local barsEnum = barInfo and barInfo.BarsEnum
    if not barsEnum then
        return DEFAULT_STATUS_BAR_WIDTH
    end

    if barIndex == barsEnum.Experience then
        return db.experienceBarWidth
    elseif barIndex == barsEnum.Reputation then
        return db.reputationBarWidth
    end

    return DEFAULT_STATUS_BAR_WIDTH
end

local function ResizeStatusBarContainer(container, barIndex)
    if not container or not container.bars then
        return
    end

    if InCombatLockdown() then
        barResizePending = true
        return
    end

    local width = GetBarWidth(barIndex)
    local innerWidth = math.max(1, width - 6)
    local bar = container.bars[barIndex]
    local containerChanged = math.abs(container:GetWidth() - width) > 0.01

    if containerChanged then
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

local function ApplyStatusBarWidths()
    local manager = StatusTrackingBarManager
    if not manager or not manager.barContainers then
        return
    end

    for _, container in ipairs(manager.barContainers) do
        local barIndex = container.pendingBarToShowIndex or container.shownBarIndex
        ResizeStatusBarContainer(container, barIndex)
    end
end

local function QueueStatusBarWidthUpdate()
    if barUpdateQueued then
        return
    end

    barUpdateQueued = true
    C_Timer.After(0, function()
        barUpdateQueued = false
        ApplyStatusBarWidths()
    end)
end

local function InstallStatusBarHooks()
    if barHooksInstalled or not StatusTrackingBarContainerMixin then
        return
    end

    hooksecurefunc(StatusTrackingBarContainerMixin, "SetShownBar", function(container, barIndex)
        ResizeStatusBarContainer(container, barIndex)
    end)

    barHooksInstalled = true
    ApplyStatusBarWidths()
end

local function ApplyMicroMenuSetting()
    local container = MicroMenuContainer
    local positionEnum = MicroMenuPositionEnum
    if not container or not positionEnum or not positionEnum.BottomRight then
        return
    end

    if not menuOriginalGetPosition then
        menuOriginalGetPosition = container.GetPosition
        menuFixedGetPosition = function()
            return positionEnum.BottomRight
        end
    end

    if db.fixedMicroMenu then
        container.GetPosition = menuFixedGetPosition
    elseif container.GetPosition == menuFixedGetPosition then
        container.GetPosition = menuOriginalGetPosition
    end
end

local function FillDeleteConfirmation()
    if not db.autoTypeDelete then
        return
    end

    local index = 1
    while true do
        local popup = _G["StaticPopup" .. index]
        if not popup then
            break
        end

        if popup and popup:IsShown() and DELETE_CONFIRM_DIALOGS[popup.which] then
            local editBox
            if popup.GetEditBox then
                editBox = popup:GetEditBox()
            end
            editBox = editBox or popup.editBox
            local popupName = popup:GetName()
            if not editBox and popupName then
                editBox = _G[popupName .. "EditBox"]
            end
            if editBox and editBox:IsShown() then
                editBox:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE")
                editBox:SetCursorPosition(editBox:GetNumLetters())
                return
            end
        end

        index = index + 1
    end
end

local function InstallDeleteHook()
    if deleteHookInstalled then
        return
    end

    hooksecurefunc("StaticPopup_Show", function(which)
        if DELETE_CONFIRM_DIALOGS[which] and db.autoTypeDelete then
            C_Timer.After(0, FillDeleteConfirmation)
        end
    end)

    deleteHookInstalled = true
end

local function InstallCinematicHooks()
    if cinematicHooksInstalled or not CinematicFrame or not MovieFrame then
        return
    end

    CinematicFrame:HookScript("OnKeyDown", function(frame, key)
        if db.skipCinematics and key == "SPACE" and frame:IsShown() then
            if frame.closeDialog then
                frame.closeDialog:Hide()
            end
            CinematicFrame_CancelCinematic()
        end
    end)

    MovieFrame:HookScript("OnKeyUp", function(frame, key)
        if db.skipCinematics and key == "SPACE" and frame:IsShown() then
            frame:FinishMovie()
        end
    end)

    cinematicHooksInstalled = true
end

local function RebuildInstanceCache()
    if not db.showInstanceProgress then
        instanceCache.ready = false
        return
    end

    local entries = instanceCache.entries
    wipe(entries)

    local count = GetNumSavedInstances() or 0
    for index = 1, count do
        local name, _, _, _, locked, _, _, _, _, difficultyName, maxEncounters, progress =
            GetSavedInstanceInfo(index)

        if locked and name then
            local instanceName = name
            if difficultyName and difficultyName ~= "" then
                instanceName = string.format("%s [%s]", name, difficultyName)
            end

            if maxEncounters and maxEncounters > 0 then
                entries[#entries + 1] = string.format(
                    "%s - %d/%d",
                    instanceName,
                    progress or 0,
                    maxEncounters
                )
            else
                entries[#entries + 1] = instanceName
            end
        end
    end

    instanceCache.ready = true
end

local function AddInstanceProgressToTooltip()
    if not db.showInstanceProgress then
        return
    end

    if not instanceCache.ready then
        RebuildInstanceCache()
    end

    GameTooltip:AddLine(" ")
    if #instanceCache.entries == 0 then
        GameTooltip:AddLine("本周尚无已锁定的副本进度", 0.55, 0.55, 0.55)
    else
        GameTooltip:AddLine("当前副本进度:", 1, 0.82, 0)
        for _, text in ipairs(instanceCache.entries) do
            GameTooltip:AddLine(text, 0.3, 0.9, 0.3)
        end
    end
    GameTooltip:Show()
end

local function InstallClockHook()
    if clockHookInstalled or type(TimeManagerClockButton_UpdateTooltip) ~= "function" then
        return
    end

    hooksecurefunc("TimeManagerClockButton_UpdateTooltip", AddInstanceProgressToTooltip)
    clockHookInstalled = true
end

local function RefreshSavedInstances(forceRequest)
    if not db.showInstanceProgress then
        return
    end

    instanceCache.ready = false
    local now = GetTime()
    if forceRequest or not instanceCache.lastRequestTime or now - instanceCache.lastRequestTime >= 2 then
        instanceCache.lastRequestTime = now
        RequestRaidInfo()
    end
end

local function StopJunkSale()
    if junkSaleTicker then
        junkSaleTicker:Cancel()
        junkSaleTicker = nil
    end
    wipe(junkSaleQueue)
    junkSaleIndex = 1
end

local function ProcessNextJunkItem()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        StopJunkSale()
        return
    end

    local entry = junkSaleQueue[junkSaleIndex]
    if not entry then
        StopJunkSale()
        return
    end

    junkSaleIndex = junkSaleIndex + 1
    local itemInfo = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    if itemInfo
        and itemInfo.itemID == entry.itemID
        and itemInfo.quality == Enum.ItemQuality.Poor
        and not itemInfo.hasNoValue
        and not itemInfo.isLocked
    then
        C_Container.UseContainerItem(entry.bag, entry.slot)
    end
end

local function StartJunkSale()
    StopJunkSale()
    if not db.autoSellJunk then
        return
    end

    local poorQuality = Enum.ItemQuality.Poor
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local slotCount = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slotCount do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo
                and itemInfo.quality == poorQuality
                and not itemInfo.hasNoValue
                and not itemInfo.isLocked
            then
                junkSaleQueue[#junkSaleQueue + 1] = {
                    bag = bag,
                    slot = slot,
                    itemID = itemInfo.itemID,
                }
            end
        end
    end

    if #junkSaleQueue > 0 then
        junkSaleTicker = C_Timer.NewTicker(0.05, ProcessNextJunkItem)
    end
end

function Addon:SetSetting(key, value)
    if not db or DEFAULTS[key] == nil then
        return
    end

    if key == "experienceBarWidth" or key == "reputationBarWidth" then
        value = math.floor(Clamp(value, 200, 1200) + 0.5)
    else
        value = not not value
    end

    if db[key] == value then
        return
    end

    db[key] = value

    if key == "experienceBarWidth" or key == "reputationBarWidth" then
        QueueStatusBarWidthUpdate()
    elseif key == "fixedMicroMenu" then
        ApplyMicroMenuSetting()
    elseif key == "autoTypeDelete" and value then
        C_Timer.After(0, FillDeleteConfirmation)
    elseif key == "showInstanceProgress" and value then
        RefreshSavedInstances(true)
    elseif key == "showInstanceProgress" then
        instanceCache.ready = false
        wipe(instanceCache.entries)
    elseif key == "autoSellJunk" then
        if value and MerchantFrame and MerchantFrame:IsShown() then
            StartJunkSale()
        else
            StopJunkSale()
        end
    end
end

local function FinishInitialization()
    InstallDeleteHook()
    InstallCinematicHooks()
    InstallStatusBarHooks()
    InstallClockHook()
    ApplyMicroMenuSetting()
    ApplyStatusBarWidths()
    if db.showInstanceProgress then
        RefreshSavedInstances()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            InitializeDatabase()

            eventFrame:RegisterEvent("PLAYER_LOGIN")
            eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
            eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
            eventFrame:RegisterEvent("BOSS_KILL")
            eventFrame:RegisterEvent("MERCHANT_SHOW")
            eventFrame:RegisterEvent("MERCHANT_CLOSED")
        elseif loadedAddon == "Blizzard_TimeManager" or loadedAddon == "Blizzard_TimeManager_Mainline" then
            InstallClockHook()
        end
    elseif event == "PLAYER_LOGIN" then
        FinishInitialization()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyMicroMenuSetting()
        QueueStatusBarWidthUpdate()
        if db.showInstanceProgress then
            RefreshSavedInstances()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if barResizePending then
            barResizePending = false
            QueueStatusBarWidthUpdate()
        end
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        QueueStatusBarWidthUpdate()
    elseif event == "UPDATE_INSTANCE_INFO" then
        if db.showInstanceProgress then
            RebuildInstanceCache()
        end
    elseif event == "BOSS_KILL" then
        if db.showInstanceProgress then
            RefreshSavedInstances()
        end
    elseif event == "MERCHANT_SHOW" then
        StartJunkSale()
    elseif event == "MERCHANT_CLOSED" then
        StopJunkSale()
    end
end)
