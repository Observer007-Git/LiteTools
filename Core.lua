local ADDON_NAME, Addon = ...

local DEFAULT_STATUS_BAR_WIDTH = 571
local CUSTOM_MINIMAP_BORDER_TEXTURE =
    "Interface\\AddOns\\" .. ADDON_NAME .. "\\UIMinimap2x-steel-ring"
local MINIMAP_BORDER_WIDTH_SCALE = 215 / 198
local MINIMAP_BORDER_HEIGHT_SCALE = 226 / 198

local DEFAULTS = {
    autoTypeDelete = false,
    skipCinematics = false,
    experienceBarWidth = DEFAULT_STATUS_BAR_WIDTH,
    reputationBarWidth = DEFAULT_STATUS_BAR_WIDTH,
    hideExperienceBar = false,
    hideReputationBar = false,
    fixedMicroMenu = false,
    showInstanceProgress = false,
    replaceMinimapBorder = false,
    moveableMinimap = false,
    minimapPositionLocked = false,
    autoSellJunk = false,
    hideChildBags = false,
    customActionBarHotkeyAliases = false,
}

Addon.defaults = DEFAULTS

local eventFrame = CreateFrame("Frame")
local db

local menuOriginalGetPosition
local menuFixedGetPosition
local microMenuSettingApplied = false
local microMenuUpdatePending = false
local statusBarOriginalCanShow
local statusBarFilteredCanShow
local barHooksInstalled = false
local barVisibilityHookInstalled = false
local cinematicHooksInstalled = false
local deleteHookInstalled = false
local clockHookInstalled = false
local minimapBorderHookInstalled = false
local barResizePending = false
local barUpdateQueued = false
local minimapBorderUpdateQueued = false
local minimapBorderTexture
local minimapDefaultBorderWasShown
local minimapBorderApplied = false
local minimapDragInstalled = false
local minimapPositionApplied = false
local minimapPositionUpdatePending = false
local bagBarHooksInstalled = false
local bagBarOriginalHideExpandToggle
local bagBarSettingApplied = false
local bagBarUpdatePending = false
local actionBarHotkeyHookInstalled = false
local actionBarHotkeySettingApplied = false
local actionBarHotkeyUpdatePending = false
local junkSaleTicker
local junkSaleQueue = {}
local junkSaleIndex = 1

local CHILD_BAG_BUTTON_NAMES = {
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
    "CharacterReagentBag0Slot",
}

local HOTKEY_ALIASES = {
    MOUSEWHEELUP = "MU",
    MOUSEWHEELDOWN = "MD",
    PAGEUP = "PU",
    PAGEDOWN = "PD",
}

local HOTKEY_MODIFIER_ALIASES = {
    SHIFT = "S",
    CTRL = "C",
    ALT = "A",
}

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
    db.hideExperienceBar = not not db.hideExperienceBar
    db.hideReputationBar = not not db.hideReputationBar
    db.fixedMicroMenu = not not db.fixedMicroMenu
    db.showInstanceProgress = not not db.showInstanceProgress
    db.replaceMinimapBorder = not not db.replaceMinimapBorder
    db.moveableMinimap = not not db.moveableMinimap
    db.minimapPositionLocked = not not db.minimapPositionLocked
    if db.minimapPosition ~= nil and type(db.minimapPosition) ~= "table" then
        db.minimapPosition = nil
    end
    db.minimapBorderColorR = Clamp(tonumber(db.minimapBorderColorR) or 1, 0, 1)
    db.minimapBorderColorG = Clamp(tonumber(db.minimapBorderColorG) or 1, 0, 1)
    db.minimapBorderColorB = Clamp(tonumber(db.minimapBorderColorB) or 1, 0, 1)
    db.minimapBorderColorA = Clamp(tonumber(db.minimapBorderColorA) or 1, 0, 1)
    if db.minimapBorderColorCustomized == nil then
        db.minimapBorderColorCustomized = db.minimapBorderColorR ~= 1
            or db.minimapBorderColorG ~= 1
            or db.minimapBorderColorB ~= 1
    else
        db.minimapBorderColorCustomized = not not db.minimapBorderColorCustomized
    end
    db.autoSellJunk = not not db.autoSellJunk
    db.hideChildBags = not not db.hideChildBags
    db.customActionBarHotkeyAliases = not not db.customActionBarHotkeyAliases
    db.experienceBarWidth = math.floor(Clamp(db.experienceBarWidth, 200, 1200) + 0.5)
    db.reputationBarWidth = math.floor(Clamp(db.reputationBarWidth, 200, 1200) + 0.5)
end

function Addon:GetSetting(key)
    if db then
        return db[key]
    end
    return DEFAULTS[key]
end

local function HasCustomStatusBarWidths()
    return db
        and (
            db.experienceBarWidth ~= DEFAULT_STATUS_BAR_WIDTH
            or db.reputationBarWidth ~= DEFAULT_STATUS_BAR_WIDTH
        )
end

local function HasHiddenStatusBars()
    return db and (db.hideExperienceBar or db.hideReputationBar)
end

local function SetEventEnabled(event, enabled)
    if enabled then
        eventFrame:RegisterEvent(event)
    else
        eventFrame:UnregisterEvent(event)
    end
end

local function UpdateFeatureEventRegistrations()
    if not db then
        return
    end

    SetEventEnabled("UPDATE_INSTANCE_INFO", db.showInstanceProgress)
    SetEventEnabled("BOSS_KILL", db.showInstanceProgress)
    SetEventEnabled("MERCHANT_SHOW", db.autoSellJunk)
    SetEventEnabled("MERCHANT_CLOSED", db.autoSellJunk)
    SetEventEnabled("DISPLAY_SIZE_CHANGED", db.replaceMinimapBorder)
    SetEventEnabled("UI_SCALE_CHANGED", db.replaceMinimapBorder)
    SetEventEnabled(
        "EDIT_MODE_LAYOUTS_UPDATED",
        db.fixedMicroMenu
            or db.hideChildBags
            or db.replaceMinimapBorder
            or HasCustomStatusBarWidths()
    )
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

local function IsStatusBarHidden(barIndex)
    local barsEnum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    if not barsEnum then
        return false
    end

    return (barIndex == barsEnum.Experience and db.hideExperienceBar)
        or (barIndex == barsEnum.Reputation and db.hideReputationBar)
end

local function ApplyStatusBarVisibility()
    local manager = StatusTrackingBarManager
    if manager and manager.UpdateBarsShown then
        manager:UpdateBarsShown()
    end
end

local function InstallStatusBarVisibilityHook()
    local manager = StatusTrackingBarManager
    if barVisibilityHookInstalled or not manager or not manager.CanShowBar then
        return
    end

    statusBarOriginalCanShow = manager.CanShowBar
    statusBarFilteredCanShow = function(self, barIndex)
        if IsStatusBarHidden(barIndex) then
            return false
        end
        return statusBarOriginalCanShow(self, barIndex)
    end
    manager.CanShowBar = statusBarFilteredCanShow

    barVisibilityHookInstalled = true
end

local function UninstallStatusBarVisibilityHook()
    local manager = StatusTrackingBarManager
    if barVisibilityHookInstalled
        and manager
        and manager.CanShowBar == statusBarFilteredCanShow
    then
        manager.CanShowBar = statusBarOriginalCanShow
        statusBarOriginalCanShow = nil
        statusBarFilteredCanShow = nil
        barVisibilityHookInstalled = false
    end
end

local function InstallStatusBarHooks()
    if barHooksInstalled or not StatusTrackingBarContainerMixin then
        return
    end

    hooksecurefunc(StatusTrackingBarContainerMixin, "SetShownBar", function(container, barIndex)
        if HasCustomStatusBarWidths() then
            ResizeStatusBarContainer(container, barIndex)
        end
    end)

    barHooksInstalled = true
end

local function ApplyMicroMenuSetting()
    local container = MicroMenuContainer
    local positionEnum = MicroMenuPositionEnum
    if not db or not container or not positionEnum or not positionEnum.BottomRight then
        return
    end

    if not db.fixedMicroMenu and not microMenuSettingApplied then
        return
    end

    if InCombatLockdown() then
        microMenuUpdatePending = true
        return
    end

    microMenuUpdatePending = false
    if not menuOriginalGetPosition then
        menuOriginalGetPosition = container.GetPosition
        menuFixedGetPosition = function(self)
            local originalPosition = menuOriginalGetPosition(self)
            if originalPosition == positionEnum.TopLeft
                or originalPosition == positionEnum.TopRight
            then
                return positionEnum.TopRight
            end
            return positionEnum.BottomRight
        end
    end

    if db.fixedMicroMenu then
        container.GetPosition = menuFixedGetPosition
        microMenuSettingApplied = true
    elseif container.GetPosition == menuFixedGetPosition then
        container.GetPosition = menuOriginalGetPosition
        microMenuSettingApplied = false
    else
        microMenuSettingApplied = false
    end

    if container.Layout then
        container:Layout()
    elseif MicroMenu and MicroMenu.Layout then
        MicroMenu:Layout()
    end
end

local function HideChildBagControls()
    if BagBarExpandToggle then
        BagBarExpandToggle:Hide()
    end

    for _, buttonName in ipairs(CHILD_BAG_BUTTON_NAMES) do
        local button = _G[buttonName]
        if button then
            button:Hide()
        end
    end

    if MainMenuBarBackpackButton then
        MainMenuBarBackpackButton:Show()
    end
end

local function CollapseBagBar()
    if not BagsBar or not MainMenuBarBackpackButton then
        return
    end

    local width, height = MainMenuBarBackpackButton:GetSize()
    if width and height and width > 0 and height > 0 then
        BagsBar:SetSize(width, height)
    end
end

local function InstallBagBarHooks()
    if bagBarHooksInstalled or not BagsBar or not BagsBar.Layout then
        return
    end

    hooksecurefunc(BagsBar, "Layout", function()
        if db and db.hideChildBags then
            if InCombatLockdown() then
                bagBarUpdatePending = true
                return
            end
            HideChildBagControls()
            CollapseBagBar()
        end
    end)

    bagBarHooksInstalled = true
end

local function ApplyChildBagSetting()
    if not db or not BagsBar or not MainMenuBarBackpackButton then
        return
    end

    if not db.hideChildBags and not bagBarSettingApplied then
        return
    end

    if InCombatLockdown() then
        bagBarUpdatePending = true
        return
    end

    bagBarUpdatePending = false

    if db.hideChildBags then
        InstallBagBarHooks()
        if not bagBarSettingApplied then
            bagBarOriginalHideExpandToggle = BagsBar.hideExpandToggle
        end
        bagBarSettingApplied = true
        BagsBar.hideExpandToggle = true
        HideChildBagControls()
        if BagsBar.Layout then
            BagsBar:Layout()
        end
        CollapseBagBar()
        return
    end

    BagsBar.hideExpandToggle = bagBarOriginalHideExpandToggle
    if MainMenuBarBagManager and MainMenuBarBagManager.OnExpandBarChanged then
        MainMenuBarBagManager:OnExpandBarChanged()
    end

    if BagBarExpandToggle then
        BagBarExpandToggle:SetShown(not BagsBar.hideExpandToggle)
    end
    if BagsBar.Layout then
        BagsBar:Layout()
    end
    bagBarSettingApplied = false
end

local function GetHotkeyAliasPart(keyPart)
    local alias = HOTKEY_ALIASES[keyPart]
    if alias then
        return alias
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
    if localizedText and localizedText ~= "" then
        return localizedText
    end
    return keyPart
end

local function GetHotkeyAlias(key)
    local parts = {}
    local remainingKey = key

    while true do
        local modifier, nextKey = remainingKey:match("^([^-]+)%-(.+)$")
        local modifierAlias = modifier and HOTKEY_MODIFIER_ALIASES[modifier]
        if not modifierAlias then
            break
        end

        parts[#parts + 1] = modifierAlias
        remainingKey = nextKey
    end

    parts[#parts + 1] = GetHotkeyAliasPart(remainingKey)
    return table.concat(parts, "+")
end

local function ApplyHotkeyAliasToButton(button)
    if not db
        or not db.customActionBarHotkeyAliases
        or not button
        or not button.HotKey
        or not button.bindingAction
    then
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

    local alias = GetHotkeyAlias(key)
    if alias ~= "" then
        button.HotKey:SetText(alias)
    end
end

local function HookActionBarButtonHotkeys(button)
    if not button
        or not button.UpdateHotkeys
        or button.fansWowHotkeyHooked
    then
        return
    end

    hooksecurefunc(button, "UpdateHotkeys", ApplyHotkeyAliasToButton)
    button.fansWowHotkeyHooked = true
end

local function InstallActionBarHotkeyHook()
    if actionBarHotkeyHookInstalled then
        return
    end

    if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateHotkeys then
        hooksecurefunc(ActionBarActionButtonMixin, "UpdateHotkeys", ApplyHotkeyAliasToButton)
    end

    -- Mainline action buttons inherit UpdateHotkeys through mixin copies created
    -- at frame creation (ActionBarButtonMixin / ActionBarActionButtonDerivedMixin),
    -- so hooking the shared mixin above alone never fires for them. Hook each real
    -- button instead, and hook RegisterFrame so buttons created later are covered.
    ActionBarButtonEventsFrame:ForEachFrame(HookActionBarButtonHotkeys)
    hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, button)
        if db and db.customActionBarHotkeyAliases then
            HookActionBarButtonHotkeys(button)
        end
    end)

    actionBarHotkeyHookInstalled = true
end

local function RefreshActionBarHotkey(button)
    if button and button.UpdateHotkeys then
        button:UpdateHotkeys(button.buttonType)
    end
end

local function ApplyActionBarHotkeySetting()
    if not db or not ActionBarButtonEventsFrame or not ActionBarButtonEventsFrame.ForEachFrame then
        return
    end

    local shouldApply = db.customActionBarHotkeyAliases
    if not shouldApply and not actionBarHotkeySettingApplied then
        return
    end

    if InCombatLockdown() then
        actionBarHotkeyUpdatePending = true
        return
    end

    actionBarHotkeyUpdatePending = false
    if shouldApply then
        InstallActionBarHotkeyHook()
        if not actionBarHotkeyHookInstalled then
            return
        end
    end
    ActionBarButtonEventsFrame:ForEachFrame(RefreshActionBarHotkey)
    actionBarHotkeySettingApplied = shouldApply
end

local function EnsureMinimapBorderTexture()
    if minimapBorderTexture then
        return minimapBorderTexture
    end

    if not Minimap or not MinimapBackdrop or not MinimapCompassTexture then
        return nil
    end

    minimapBorderTexture = MinimapBackdrop:CreateTexture(
        "FansWowToolsMinimapBorder",
        "OVERLAY",
        nil,
        3
    )
    minimapBorderTexture:SetTexture(CUSTOM_MINIMAP_BORDER_TEXTURE)
    minimapBorderTexture:SetTexCoord(1 / 512, 439 / 512, 58 / 1024, 518 / 1024)
    local red = db.minimapBorderColorR
    local green = db.minimapBorderColorG
    local blue = db.minimapBorderColorB
    minimapBorderTexture:SetDesaturated(db.minimapBorderColorCustomized)
    minimapBorderTexture:SetVertexColor(red, green, blue)
    minimapBorderTexture:SetAlpha(db.minimapBorderColorA)
    minimapBorderTexture:SetPoint("CENTER", Minimap, "CENTER")
    minimapBorderTexture:Hide()
    return minimapBorderTexture
end

local function ResizeMinimapBorder()
    local texture = EnsureMinimapBorderTexture()
    if not texture or not Minimap then
        return
    end

    local width, height = Minimap:GetSize()
    if not width or not height or width <= 0 or height <= 0 then
        return
    end

    texture:SetSize(
        width * MINIMAP_BORDER_WIDTH_SCALE,
        height * MINIMAP_BORDER_HEIGHT_SCALE
    )
end

local function ApplyMinimapBorderSetting()
    if not MinimapCompassTexture then
        return
    end

    if db.replaceMinimapBorder then
        local texture = EnsureMinimapBorderTexture()
        if not texture then
            return
        end
        if not minimapBorderApplied then
            minimapDefaultBorderWasShown = MinimapCompassTexture:IsShown()
            minimapBorderApplied = true
        end
        ResizeMinimapBorder()
        MinimapCompassTexture:Hide()
        texture:Show()
    else
        if minimapBorderTexture then
            minimapBorderTexture:Hide()
        end
        if minimapBorderApplied then
            MinimapCompassTexture:SetShown(minimapDefaultBorderWasShown)
            minimapBorderApplied = false
        end
    end
end

local function QueueMinimapBorderUpdate()
    if minimapBorderUpdateQueued then
        return
    end

    minimapBorderUpdateQueued = true
    C_Timer.After(0, function()
        minimapBorderUpdateQueued = false
        ApplyMinimapBorderSetting()
    end)
end

local function InstallMinimapBorderHook()
    if minimapBorderHookInstalled or not Minimap then
        return
    end

    Minimap:HookScript("OnSizeChanged", function()
        if db.replaceMinimapBorder then
            QueueMinimapBorderUpdate()
        end
    end)

    if MinimapCompassTexture then
        hooksecurefunc(MinimapCompassTexture, "Show", function(texture)
            if db and db.replaceMinimapBorder then
                texture:Hide()
            end
        end)
    end

    minimapBorderHookInstalled = true
end

local function SaveMinimapPosition()
    if not db or not Minimap then
        return
    end

    local point, relativeTo, relativePoint, xOfs, yOfs = Minimap:GetPoint(1)
    if not point then
        return
    end

    db.minimapPosition = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName() or nil,
        relativePoint = relativePoint,
        x = xOfs or 0,
        y = yOfs or 0,
    }
end

local function ApplyMinimapPosition()
    local position = db and db.minimapPosition
    if not position or not position.point or not Minimap then
        return
    end

    local relativeTo = position.relativeTo and _G[position.relativeTo] or Minimap:GetParent()
    Minimap:ClearAllPoints()
    Minimap:SetPoint(
        position.point,
        relativeTo,
        position.relativePoint or "CENTER",
        position.x or 0,
        position.y or 0
    )
    minimapPositionApplied = true
end

local function RestoreDefaultMinimapPosition()
    if not Minimap then
        return
    end

    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER")
    minimapPositionApplied = false
end

local function InstallMinimapDrag()
    if minimapDragInstalled or not Minimap then
        return
    end

    Minimap:SetMovable(true)
    Minimap:SetClampedToScreen(true)
    Minimap:RegisterForDrag("LeftButton")

    Minimap:HookScript("OnDragStart", function(self)
        if db and db.moveableMinimap and not db.minimapPositionLocked then
            self:StartMoving()
        end
    end)

    Minimap:HookScript("OnDragStop", function(self)
        if self:IsMoving() then
            self:StopMovingOrSizing()
            if db and db.moveableMinimap then
                SaveMinimapPosition()
            end
        end
    end)

    minimapDragInstalled = true
end

local function ApplyMinimapMoveSetting()
    if not db or not Minimap then
        return
    end

    if InCombatLockdown() then
        minimapPositionUpdatePending = true
        return
    end

    minimapPositionUpdatePending = false
    if db.moveableMinimap then
        InstallMinimapDrag()
        if db.minimapPosition and not minimapPositionApplied then
            ApplyMinimapPosition()
        end
    elseif minimapPositionApplied then
        RestoreDefaultMinimapPosition()
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
    local equippedBagSlots = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 0
    for bag = 0, equippedBagSlots do
        local slotCount = tonumber(C_Container.GetContainerNumSlots(bag)) or 0
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
    UpdateFeatureEventRegistrations()

    if key == "experienceBarWidth" or key == "reputationBarWidth" then
        InstallStatusBarHooks()
        QueueStatusBarWidthUpdate()
    elseif key == "hideExperienceBar" or key == "hideReputationBar" then
        if value then
            InstallStatusBarVisibilityHook()
        elseif not HasHiddenStatusBars() then
            UninstallStatusBarVisibilityHook()
        end
        ApplyStatusBarVisibility()
    elseif key == "fixedMicroMenu" then
        ApplyMicroMenuSetting()
    elseif key == "replaceMinimapBorder" then
        if value then
            InstallMinimapBorderHook()
        end
        QueueMinimapBorderUpdate()
    elseif key == "moveableMinimap" then
        ApplyMinimapMoveSetting()
    elseif key == "minimapPositionLocked" then
        if value then
            SaveMinimapPosition()
        end
        ApplyMinimapMoveSetting()
    elseif key == "hideChildBags" then
        ApplyChildBagSetting()
    elseif key == "customActionBarHotkeyAliases" then
        ApplyActionBarHotkeySetting()
    elseif key == "autoTypeDelete" and value then
        InstallDeleteHook()
        C_Timer.After(0, FillDeleteConfirmation)
    elseif key == "skipCinematics" and value then
        InstallCinematicHooks()
    elseif key == "showInstanceProgress" and value then
        InstallClockHook()
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

function Addon:GetMinimapBorderColor()
    if not db then
        return 1, 1, 1, 1, false
    end
    return db.minimapBorderColorR,
        db.minimapBorderColorG,
        db.minimapBorderColorB,
        db.minimapBorderColorA,
        db.minimapBorderColorCustomized
end

function Addon:SetMinimapBorderColor(red, green, blue, alpha, customized)
    if not db then
        return
    end

    red = Clamp(red, 0, 1)
    green = Clamp(green, 0, 1)
    blue = Clamp(blue, 0, 1)
    alpha = Clamp(tonumber(alpha) or 1, 0, 1)
    if customized == nil then
        customized = true
    else
        customized = not not customized
    end
    if db.minimapBorderColorR == red
        and db.minimapBorderColorG == green
        and db.minimapBorderColorB == blue
        and db.minimapBorderColorA == alpha
        and db.minimapBorderColorCustomized == customized
    then
        return
    end

    db.minimapBorderColorR = red
    db.minimapBorderColorG = green
    db.minimapBorderColorB = blue
    db.minimapBorderColorA = alpha
    db.minimapBorderColorCustomized = customized
    if minimapBorderTexture then
        minimapBorderTexture:SetDesaturated(customized)
        minimapBorderTexture:SetVertexColor(red, green, blue)
        minimapBorderTexture:SetAlpha(alpha)
    end
end

local function FinishInitialization()
    if db.autoTypeDelete then
        InstallDeleteHook()
    end
    if db.skipCinematics then
        InstallCinematicHooks()
    end
    if HasCustomStatusBarWidths() then
        InstallStatusBarHooks()
        ApplyStatusBarWidths()
    end
    if HasHiddenStatusBars() then
        InstallStatusBarVisibilityHook()
        ApplyStatusBarVisibility()
    end
    if db.showInstanceProgress then
        InstallClockHook()
    end
    if db.replaceMinimapBorder then
        InstallMinimapBorderHook()
        ApplyMinimapBorderSetting()
    end

    ApplyMinimapMoveSetting()
    ApplyMicroMenuSetting()
    ApplyChildBagSetting()
    ApplyActionBarHotkeySetting()
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
            UpdateFeatureEventRegistrations()
        elseif loadedAddon == "Blizzard_TimeManager" or loadedAddon == "Blizzard_TimeManager_Mainline" then
            if db and db.showInstanceProgress then
                InstallClockHook()
            end
        elseif loadedAddon == "Blizzard_MainMenuBarBagButtons" then
            ApplyChildBagSetting()
        elseif loadedAddon == "Blizzard_ActionBar" then
            if HasCustomStatusBarWidths() then
                InstallStatusBarHooks()
                ApplyStatusBarWidths()
            end
            if HasHiddenStatusBars() then
                InstallStatusBarVisibilityHook()
                ApplyStatusBarVisibility()
            end
            ApplyActionBarHotkeySetting()
        elseif loadedAddon == "Blizzard_MicroMenu" then
            ApplyMicroMenuSetting()
        elseif loadedAddon == "Blizzard_Minimap" then
            if db and db.replaceMinimapBorder then
                InstallMinimapBorderHook()
                ApplyMinimapBorderSetting()
            end
            ApplyMinimapMoveSetting()
        end
    elseif event == "PLAYER_LOGIN" then
        FinishInitialization()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyMicroMenuSetting()
        if HasCustomStatusBarWidths() then
            InstallStatusBarHooks()
            QueueStatusBarWidthUpdate()
        end
        if HasHiddenStatusBars() then
            InstallStatusBarVisibilityHook()
            ApplyStatusBarVisibility()
        end
        if db.replaceMinimapBorder then
            InstallMinimapBorderHook()
            QueueMinimapBorderUpdate()
        end
        ApplyMinimapMoveSetting()
        ApplyChildBagSetting()
        ApplyActionBarHotkeySetting()
        if db.showInstanceProgress then
            RefreshSavedInstances()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if microMenuUpdatePending then
            ApplyMicroMenuSetting()
        end
        if barResizePending then
            barResizePending = false
            QueueStatusBarWidthUpdate()
        end
        if bagBarUpdatePending then
            ApplyChildBagSetting()
        end
        if actionBarHotkeyUpdatePending then
            ApplyActionBarHotkeySetting()
        end
        if minimapPositionUpdatePending then
            ApplyMinimapMoveSetting()
        end
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ApplyMicroMenuSetting()
        if HasCustomStatusBarWidths() then
            QueueStatusBarWidthUpdate()
        end
        if db.replaceMinimapBorder then
            QueueMinimapBorderUpdate()
        end
        ApplyMinimapMoveSetting()
        ApplyChildBagSetting()
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        if db.replaceMinimapBorder then
            QueueMinimapBorderUpdate()
        end
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
