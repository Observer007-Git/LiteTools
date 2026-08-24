local _, Addon = ...

local EXPANDED_COLUMNS = 12
local EXPANDED_ROWS = 10
local BUTTON_SIZE = 36
local GRID_PADDING = 5
local GRID_SPACING = 5
local EXPANDED_SELECTOR_WIDTH = EXPANDED_COLUMNS * BUTTON_SIZE
    + (EXPANDED_COLUMNS - 1) * GRID_SPACING
    + GRID_PADDING * 2
    + 17
local EXPANDED_SELECTOR_HEIGHT = EXPANDED_ROWS * BUTTON_SIZE
    + (EXPANDED_ROWS - 1) * GRID_SPACING
    + GRID_PADDING * 2
local ORIGINAL_COLUMNS = 6
local ORIGINAL_GRID_SPACING = 13

local originalLayout
local hooksInstalled = false
local originalMacroUpdate
local originalGetMacroDataIndex
local currentMacroOrder
local currentOrderScope
local dialogMode
local pendingNativeIndex
local editedDisplayIndex
local macroCountBeforeDialog

local function CapturePoints(region)
    local points = {}
    for index = 1, region:GetNumPoints() do
        points[index] = { region:GetPoint(index) }
    end
    return points
end

local function RestorePoints(region, points, offsetY)
    region:ClearAllPoints()
    for _, point in ipairs(points) do
        region:SetPoint(
            point[1],
            point[2],
            point[3],
            point[4],
            point[5] + (offsetY or 0)
        )
    end
end

local function CaptureOriginalLayout()
    if originalLayout or not MacroFrame or not MacroFrame.MacroSelector then
        return originalLayout ~= nil
    end

    local regions = {
        MacroHorizontalBarLeft,
        MacroFrameSelectedMacroBackground,
        MacroFrameTextBackground,
    }
    for _, region in ipairs(regions) do
        if not region then return false end
    end

    local frameWidth, frameHeight = MacroFrame:GetSize()
    local selectorWidth, selectorHeight = MacroFrame.MacroSelector:GetSize()
    originalLayout = {
        frameWidth = frameWidth,
        frameHeight = frameHeight,
        selectorWidth = selectorWidth,
        selectorHeight = selectorHeight,
        panelWidth = UIPanelWindows
            and UIPanelWindows.MacroFrame
            and UIPanelWindows.MacroFrame.width,
        regions = {},
        stretchRegions = {},
    }
    for _, region in ipairs(regions) do
        originalLayout.regions[#originalLayout.regions + 1] = {
            region = region,
            points = CapturePoints(region),
        }
    end

    local stretchRegions = {
        MacroHorizontalBarLeft,
        MacroFrameSelectedMacroName,
        MacroEditButton,
        MacroFrameScrollFrame,
        MacroFrameText,
        MacroFrameTextButton,
        MacroFrameTextBackground,
    }
    for _, region in ipairs(stretchRegions) do
        if not region then return false end
        originalLayout.stretchRegions[#originalLayout.stretchRegions + 1] = {
            region = region,
            width = region:GetWidth(),
        }
    end
    return true
end

local function RefreshSelector(selector, columns, spacing)
    selector:SetCustomStride(columns)
    selector:SetCustomPadding(
        GRID_PADDING,
        GRID_PADDING,
        GRID_PADDING,
        GRID_PADDING,
        spacing,
        spacing
    )

    local scrollBox = selector.ScrollBox
    local view = scrollBox and scrollBox.GetView and scrollBox:GetView()
    if view then
        if view.SetStride then
            view:SetStride(columns)
        end
        if view.SetPadding then
            view:SetPadding(
                GRID_PADDING,
                GRID_PADDING,
                GRID_PADDING,
                GRID_PADDING,
                spacing,
                spacing
            )
        end
        if scrollBox.FullUpdate and ScrollBoxConstants then
            scrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
        end
    end
end

local function ApplyMacroFrameLayout()
    if not CaptureOriginalLayout() then return end

    local enabled = Addon:GetSetting("extendMacroUI")
    local selector = MacroFrame.MacroSelector
    local selectorHeight = enabled and EXPANDED_SELECTOR_HEIGHT
        or originalLayout.selectorHeight
    local detailOffset = selectorHeight - originalLayout.selectorHeight
    local frameWidth = enabled and EXPANDED_SELECTOR_WIDTH + 24
        or originalLayout.frameWidth
    local widthOffset = frameWidth - originalLayout.frameWidth

    MacroFrame:SetSize(
        frameWidth,
        enabled and originalLayout.frameHeight + detailOffset
            or originalLayout.frameHeight
    )
    selector:SetSize(
        enabled and EXPANDED_SELECTOR_WIDTH or originalLayout.selectorWidth,
        selectorHeight
    )

    if UIPanelWindows and UIPanelWindows.MacroFrame then
        UIPanelWindows.MacroFrame.width = enabled
            and EXPANDED_SELECTOR_WIDTH + 24
            or originalLayout.panelWidth
    end

    for _, saved in ipairs(originalLayout.regions) do
        RestorePoints(
            saved.region,
            saved.points,
            enabled and -detailOffset or 0
        )
    end
    for _, saved in ipairs(originalLayout.stretchRegions) do
        saved.region:SetWidth(saved.width + widthOffset)
    end

    RefreshSelector(
        selector,
        enabled and EXPANDED_COLUMNS or ORIGINAL_COLUMNS,
        enabled and GRID_SPACING or ORIGINAL_GRID_SPACING
    )
    if MacroFrame:IsShown()
        and MacroFrame.macroBase ~= nil
        and MacroFrame.Update
    then
        MacroFrame:Update()
    end
end

local function SanitizeMacroOrder(value)
    local result = {}
    if type(value) ~= "table" then return result end

    for scope, order in pairs(value) do
        if type(scope) == "string" and type(order) == "table" then
            local cleanOrder = {}
            for _, key in ipairs(order) do
                if type(key) == "string" then
                    cleanOrder[#cleanOrder + 1] = key
                end
            end
            result[scope] = cleanOrder
        end
    end
    return result
end

local function GetMacroKey(actualIndex)
    local name, texture = GetMacroInfo(actualIndex)
    if not name then return nil end

    return name .. "\031" .. tostring(texture or "")
end

local function GetMacroScopeAndRange()
    local tabID = PanelTemplates_GetSelectedTab(MacroFrame)
    local numAccountMacros, numCharacterMacros = GetNumMacros()
    local macroBase = MacroFrame and MacroFrame.macroBase
    if type(macroBase) ~= "number" then
        macroBase = tabID == 1 and 0 or nil
    end
    if tabID == 2 then
        local playerName, realmName = UnitFullName("player")
        local scope = table.concat({
            "character",
            realmName or GetRealmName() or "",
            playerName or UnitName("player") or "",
        }, ":")
        return scope, macroBase, numCharacterMacros
    end
    return "account", macroBase, numAccountMacros
end

local function RebuildMacroOrder()
    currentMacroOrder = nil
    currentOrderScope = nil
    if not Addon:GetSetting("extendMacroUI") or MacroFrame.macroBase == nil then
        return
    end

    local scope, macroBase, macroCount = GetMacroScopeAndRange()
    if type(macroBase) ~= "number" or type(macroCount) ~= "number" then
        return
    end
    local storage = Addon:GetSetting("macroOrder")
    if type(storage) ~= "table" then return end

    local savedOrder = storage[scope] or {}
    local buckets = {}
    for selectionIndex = 1, macroCount do
        local actualIndex = macroBase + selectionIndex
        local key = GetMacroKey(actualIndex)
        if key then
            buckets[key] = buckets[key] or {}
            buckets[key][#buckets[key] + 1] = actualIndex
        end
    end

    local order = {}
    local normalizedKeys = {}
    local used = {}
    local bucketPositions = {}
    for _, key in ipairs(savedOrder) do
        local bucket = buckets[key]
        local bucketPosition = (bucketPositions[key] or 0) + 1
        local actualIndex = bucket and bucket[bucketPosition]
        if actualIndex then
            bucketPositions[key] = bucketPosition
            order[#order + 1] = actualIndex
            normalizedKeys[#normalizedKeys + 1] = key
            used[actualIndex] = true
        end
    end

    for selectionIndex = 1, macroCount do
        local actualIndex = macroBase + selectionIndex
        if not used[actualIndex] then
            local key = GetMacroKey(actualIndex)
            if key then
                order[#order + 1] = actualIndex
                normalizedKeys[#normalizedKeys + 1] = key
            end
        end
    end

    local changed = #savedOrder ~= #normalizedKeys
    if not changed then
        for index, key in ipairs(normalizedKeys) do
            if savedOrder[index] ~= key then
                changed = true
                break
            end
        end
    end
    if changed then
        storage[scope] = normalizedKeys
    elseif not storage[scope] then
        storage[scope] = normalizedKeys
    end

    currentMacroOrder = order
    currentOrderScope = scope
end

local function FindDisplayIndex(actualIndex)
    for displayIndex, orderedActualIndex in ipairs(currentMacroOrder or {}) do
        if orderedActualIndex == actualIndex then
            return displayIndex
        end
    end
end

local function PreserveEditedMacroPosition(actualIndex, targetDisplayIndex)
    local displayIndex = FindDisplayIndex(actualIndex)
    if not displayIndex or displayIndex == targetDisplayIndex then return end

    local storage = Addon:GetSetting("macroOrder")
    local savedOrder = storage and storage[currentOrderScope]
    if not savedOrder or not savedOrder[displayIndex] then return end

    local key = table.remove(savedOrder, displayIndex)
    table.insert(
        savedOrder,
        math.min(targetDisplayIndex, #savedOrder + 1),
        key
    )
    RebuildMacroOrder()
end

local function ClearDialogTracking()
    dialogMode = nil
    pendingNativeIndex = nil
    editedDisplayIndex = nil
    macroCountBeforeDialog = nil
end

local function SelectDisplayMacro(displayIndex, refresh)
    if not displayIndex or not MacroFrame or not MacroFrame:IsShown() then
        return
    end

    if refresh ~= false then
        MacroFrame:Update()
        local selector = MacroFrame.MacroSelector
        local scrollBox = selector and selector.ScrollBox
        if scrollBox and scrollBox.FullUpdate and ScrollBoxConstants then
            scrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately)
        end
    end
    MacroFrame:SelectMacro(displayIndex, true)
end

local function InstallMacroCreationHooks()
    if hooksInstalled or not MacroPopupFrame then return end
    hooksInstalled = true

    originalMacroUpdate = MacroFrame.Update
    MacroFrame.Update = function(self, ...)
        RebuildMacroOrder()
        return originalMacroUpdate(self, ...)
    end

    originalGetMacroDataIndex = MacroFrame.GetMacroDataIndex
    MacroFrame.GetMacroDataIndex = function(self, selectionIndex)
        if Addon:GetSetting("extendMacroUI") and currentMacroOrder then
            return currentMacroOrder[selectionIndex]
                or originalGetMacroDataIndex(self, selectionIndex)
        end
        return originalGetMacroDataIndex(self, selectionIndex)
    end

    MacroPopupFrame:HookScript("OnShow", function(self)
        ClearDialogTracking()
        if not Addon:GetSetting("extendMacroUI") then return end

        dialogMode = self.mode
        if dialogMode == IconSelectorPopupFrameModes.New then
            macroCountBeforeDialog = select(
                PanelTemplates_GetSelectedTab(MacroFrame),
                GetNumMacros()
            )
        elseif dialogMode == IconSelectorPopupFrameModes.Edit then
            editedDisplayIndex = MacroFrame:GetSelectedIndex()
        end
    end)

    hooksecurefunc(MacroFrame, "SelectMacro", function(_, selectionIndex)
        if dialogMode and selectionIndex then
            pendingNativeIndex = selectionIndex
        end
    end)

    hooksecurefunc(MacroPopupFrame, "CancelButton_OnClick", ClearDialogTracking)
    hooksecurefunc(MacroPopupFrame, "OkayButton_OnClick", function(self)
        local completedMode = dialogMode
        local nativeIndex = pendingNativeIndex
        local originalDisplayIndex = editedDisplayIndex
        local previousMacroCount = macroCountBeforeDialog
        ClearDialogTracking()
        if not completedMode then return end

        C_Timer.After(0, function()
            if not MacroFrame or not MacroFrame:IsShown() then return end

            if completedMode == IconSelectorPopupFrameModes.New then
                RebuildMacroOrder()
                local displayIndex = currentMacroOrder
                    and #currentMacroOrder
                if not displayIndex
                    or (previousMacroCount
                        and displayIndex <= previousMacroCount)
                then
                    return
                end
                SelectDisplayMacro(displayIndex)

                C_Timer.After(0, function()
                    SelectDisplayMacro(displayIndex, false)
                end)
                return
            end

            if not nativeIndex then return end
            local _, macroBase = GetMacroScopeAndRange()
            if type(macroBase) ~= "number" then return end
            local actualIndex = macroBase + nativeIndex
            MacroFrame:Update()
            if originalDisplayIndex then
                PreserveEditedMacroPosition(actualIndex, originalDisplayIndex)
                MacroFrame:Update()
            end

            local displayIndex = FindDisplayIndex(actualIndex)
            if displayIndex then
                MacroFrame:SelectMacro(displayIndex, true)
            end
        end)
    end)
end

Addon:RegisterSetting(
    "extendMacroUI",
    false,
    Addon.BooleanSetting,
    ApplyMacroFrameLayout
)
Addon:RegisterSetting("macroOrder", {}, SanitizeMacroOrder)

Addon:RegisterEvent("ADDON_LOADED", function(_, addonName)
    if addonName == "Blizzard_MacroUI" then
        InstallMacroCreationHooks()
        ApplyMacroFrameLayout()
    end
end)

Addon:RegisterEvent("PLAYER_LOGIN", function()
    InstallMacroCreationHooks()
    ApplyMacroFrameLayout()
end)
