local ADDON_NAME, Addon = ...

local CHOICES = {
    { labelKey = "NEED", rollType = 1, suffix = "need" },
    { labelKey = "GREED", rollType = 2, suffix = "greed" },
    { labelKey = "DISENCHANT", rollType = 3, suffix = "disenchant" },
    { labelKey = "TRANSMOG", rollType = 4, suffix = "transmog" },
    { labelKey = "PASS", rollType = 0, suffix = "pass" },
}

local BACKGROUND_TEXTURE =
    "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\loot-background"
local PREVIEW_TEXTURE =
    "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\wantall"
local PANEL_HEIGHT = 96
local LEFT_BACKGROUND_WIDTH = 82
local PREVIEW_WIDTH = 67
local PREVIEW_HEIGHT = 66
local PREVIEW_CENTER_X = 50
local PREVIEW_CENTER_Y = 45

-- Manual button layout: increase horizontal padding to move right;
-- increase top padding to move down; spacing controls the gaps between buttons.
local BUTTON_SIZE = 48
local BUTTON_SPACING = 10
local BUTTON_HORIZONTAL_PADDING = 30
local BUTTON_TOP = 20
local BUTTON_OFFSETS = {
    [1] = { x = -8, y = -2 }, -- Need
    [2] = { x = 2, y = 1 }, -- Greed
    [3] = { x = 8, y = 0 }, -- Disenchant
    [4] = { x = 8, y = 0 }, -- Transmog
    [5] = { x = 8, y = 1 }, -- Pass
}
local BUTTON_EXPANSIONS = {
    [1] = 1, -- Need: expand 1px on every side
    [2] = 1, -- Greed: expand 1px on every side
}
local BUTTONS_WIDTH = #CHOICES * BUTTON_SIZE + (#CHOICES - 1) * BUTTON_SPACING
local RIGHT_BACKGROUND_WIDTH = 365
local PANEL_WIDTH = LEFT_BACKGROUND_WIDTH + RIGHT_BACKGROUND_WIDTH
local BACKGROUND_TEXTURE_WIDTH = 512
local BACKGROUND_TEXTURE_HEIGHT = 128
local BACKGROUND_VISIBLE_LEFT = 5 / BACKGROUND_TEXTURE_WIDTH
local BACKGROUND_SPLIT = 82 / BACKGROUND_TEXTURE_WIDTH
local BACKGROUND_VISIBLE_RIGHT = 362 / BACKGROUND_TEXTURE_WIDTH
local BACKGROUND_VISIBLE_TOP = 25 / BACKGROUND_TEXTURE_HEIGHT
local BACKGROUND_VISIBLE_BOTTOM = 115 / BACKGROUND_TEXTURE_HEIGHT
for _, choice in ipairs(CHOICES) do
    choice.normalAtlas = "lootroll-toast-icon-" .. choice.suffix .. "-up"
    choice.pushedAtlas = "lootroll-toast-icon-" .. choice.suffix .. "-down"
    choice.highlightAtlas = "lootroll-toast-icon-" .. choice.suffix .. "-highlight"
end

local panel
local panelAnchor
local panelHooksInstalled = false
local confirmationHookInstalled = false
local batch
local submittedRolls = {}
local previewMode = false
local UpdatePanel

local function DB()
    return Addon:GetDatabase()
end

local function CollectPendingRolls()
    local queue = {}
    local seen = {}
    local indexedFrames = {}
    for index, rollFrame in pairs(GroupLootContainer.rollFrames or {}) do
        if type(index) == "number"
            and rollFrame
            and rollFrame.rollID
            and not submittedRolls[rollFrame.rollID]
        then
            indexedFrames[#indexedFrames + 1] = { index = index, rollID = rollFrame.rollID }
        end
    end
    table.sort(indexedFrames, function(left, right) return left.index < right.index end)
    for _, entry in ipairs(indexedFrames) do
        if not seen[entry.rollID] then
            seen[entry.rollID] = true
            queue[#queue + 1] = entry.rollID
        end
    end
    for _, waitingRoll in ipairs(GroupLootContainer.waitingRolls or {}) do
        local rollID = waitingRoll and waitingRoll.rollID
        if rollID and not seen[rollID] and not submittedRolls[rollID] then
            seen[rollID] = true
            queue[#queue + 1] = rollID
        end
    end
    return queue
end

local function GetAllowedChoices(rollID)
    local _, itemName, _, _, _, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog =
        GetLootRollItemInfo(rollID)
    if not itemName then return nil end
    return { canNeed, canGreed, canDisenchant, canTransmog, true }
end

local function GetPreferredRollType(rollID, startingPriority)
    local allowed = GetAllowedChoices(rollID)
    if not allowed then return nil end
    for priority = startingPriority, #CHOICES do
        if allowed[priority] then
            return CHOICES[priority].rollType
        end
    end
    return 0
end

local function StopBatch()
    batch = nil
    if UpdatePanel then UpdatePanel() end
end

local ProcessBatch

local function CompleteConfirmation(rollID, rollType)
    local currentBatch = batch
    if not currentBatch
        or currentBatch.waitingRollID ~= rollID
        or currentBatch.waitingRollType ~= rollType
    then
        return
    end
    currentBatch.waitingRollID = nil
    currentBatch.waitingRollType = nil
    currentBatch.currentRollID = nil
    C_Timer.After(0, function()
        if batch == currentBatch and not currentBatch.waitingRollID then
            ProcessBatch()
        end
    end)
end

local function HandleConfirmation(rollID, rollType)
    local currentBatch = batch
    if not currentBatch or currentBatch.currentRollID ~= rollID then return end
    currentBatch.waitingRollID = rollID
    currentBatch.waitingRollType = rollType
    C_Timer.After(0, function()
        if not batch
            or batch.waitingRollID ~= rollID
            or batch.waitingRollType ~= rollType
            or type(ConfirmLootRoll) ~= "function"
        then
            return
        end
        local confirmed = pcall(ConfirmLootRoll, rollID, rollType)
        if confirmed then
            if type(StaticPopup_Hide) == "function" then
                StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollID)
            end
            CompleteConfirmation(rollID, rollType)
        end
    end)
end

local function HandleCancelled(rollID)
    submittedRolls[rollID] = nil
    local currentBatch = batch
    if not currentBatch or currentBatch.waitingRollID ~= rollID then return end
    currentBatch.waitingRollID = nil
    currentBatch.waitingRollType = nil
    currentBatch.currentRollID = nil
    C_Timer.After(0, function()
        if batch == currentBatch and not currentBatch.waitingRollID then ProcessBatch() end
    end)
end

ProcessBatch = function()
    local currentBatch = batch
    if not currentBatch or currentBatch.waitingRollID then return end
    while batch == currentBatch do
        local rollID = currentBatch.queue[currentBatch.index]
        if not rollID then
            StopBatch()
            return
        end
        currentBatch.index = currentBatch.index + 1
        local rollType = GetPreferredRollType(rollID, currentBatch.startingPriority)
        if rollType ~= nil then
            currentBatch.currentRollID = rollID
            submittedRolls[rollID] = true
            RollOnLoot(rollID, rollType)
            if batch ~= currentBatch or currentBatch.waitingRollID then return end
            currentBatch.currentRollID = nil
        end
    end
end

local function StartBatch(startingPriority)
    local db = DB()
    if not db or not db.autoRollGear or batch or not GroupLootContainer then return end
    local queue = CollectPendingRolls()
    if #queue == 0 then return end
    batch = { queue = queue, index = 1, startingPriority = startingPriority }
    UpdatePanel()
    ProcessBatch()
end

local function PositionPanel()
    local db = DB()
    if not panel or not GroupLootContainer or not db then return end
    if db.showAutoRollPanelAnchor and panelAnchor then
        panel:ClearAllPoints()
        panel:SetPoint("TOP", panelAnchor, "BOTTOM", 0, -5)
        return
    end
    local relativeFrame = GroupLootContainer
    local groupAnchor = Addon.Alerts and Addon.Alerts:GetGroupLootAnchor()
    if db.showGroupLootAnchor and groupAnchor then relativeFrame = groupAnchor end
    panel:ClearAllPoints()
    panel:SetPoint("TOP", relativeFrame, "BOTTOM", 0, -5)
end

local function PositionPanelAnchor()
    if panelAnchor then
        Addon.Anchors:Position(panelAnchor, "autoRollPanelAnchorPosition", 0.5, 0.18)
        PositionPanel()
    end
end

local function EnsurePanelAnchor()
    if not panelAnchor then
        panelAnchor = Addon.Anchors:Create({
            name = "LiteToolsAutoRollPanelAnchor",
            label = Addon.L.AUTO_ROLL_PANEL_ANCHOR_SHORT,
            positionKey = "autoRollPanelAnchorPosition",
            hiddenKey = "autoRollPanelAnchorHidden",
            defaultX = 0.5,
            defaultY = 0.18,
            movedCallback = PositionPanel,
        })
    end
    return panelAnchor
end

local function ApplyPanelAnchor(reposition)
    local db = DB()
    if not db then return end
    if db.showAutoRollPanelAnchor and not db.autoRollPanelAnchorPosition then
        db.autoRollPanelAnchorPosition = { version = 2, x = 0.5, y = 0.18 }
    end
    if db.showAutoRollPanelAnchor then
        local anchor = EnsurePanelAnchor()
        if reposition then PositionPanelAnchor() end
        anchor:SetShown(not db.autoRollPanelAnchorHidden)
    elseif panelAnchor then
        panelAnchor:Hide()
    end
    PositionPanel()
end

local function UpdateButtonStates(pendingRolls)
    if not panel or not panel.buttons then return end
    local available = {}
    for _, rollID in ipairs(pendingRolls) do
        local allowed = GetAllowedChoices(rollID)
        if allowed then
            for priority = 1, #CHOICES do
                available[priority] = available[priority] or not not allowed[priority]
            end
        end
    end
    for priority, button in ipairs(panel.buttons) do
        local enabled = not batch and not not available[priority]
        button:SetEnabled(enabled)
        button:SetAlpha(enabled and 1 or 0.20)
        button.autoRollChoiceAvailable = not not available[priority]
        if enabled then
            button.availabilityGlow:Show()
        else
            button.availabilityGlow:Hide()
            button.selectionGlow:Hide()
        end
    end
end

local function ShowAllButtonsForPreview()
    if not panel or not panel.buttons then return end
    for _, button in ipairs(panel.buttons) do
        button:SetEnabled(true)
        button:SetAlpha(1)
        button.autoRollChoiceAvailable = true
        button.availabilityGlow:Show()
    end
end

UpdatePanel = function()
    if not panel then return end
    local pendingRolls = CollectPendingRolls()
    PositionPanel()
    if previewMode and #pendingRolls == 0 then
        ShowAllButtonsForPreview()
    else
        UpdateButtonStates(pendingRolls)
    end
    local db = DB()
    panel:SetShown(not not (
        previewMode
        or (db and db.autoRollGear and GroupLootContainer
            and GroupLootContainer:IsShown() and #pendingRolls > 0)
    ))
end

local function EnsurePanel()
    if panel or not GroupLootContainer then return panel end
    panel = CreateFrame("Frame", "LiteToolsAutoRollPanel", UIParent)
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("TOP", GroupLootContainer, "BOTTOM", 0, -5)

    local leftBackground = panel:CreateTexture(nil, "BORDER")
    leftBackground:SetSize(LEFT_BACKGROUND_WIDTH, PANEL_HEIGHT)
    leftBackground:SetPoint("TOPLEFT")
    leftBackground:SetTexture(BACKGROUND_TEXTURE)
    leftBackground:SetTexCoord(
        BACKGROUND_VISIBLE_LEFT,
        BACKGROUND_SPLIT,
        BACKGROUND_VISIBLE_TOP,
        BACKGROUND_VISIBLE_BOTTOM
    )
    panel.leftBackground = leftBackground

    local rightBackground = panel:CreateTexture(nil, "BORDER")
    rightBackground:SetSize(RIGHT_BACKGROUND_WIDTH, PANEL_HEIGHT)
    rightBackground:SetPoint("TOPLEFT", leftBackground, "TOPRIGHT")
    rightBackground:SetTexture(BACKGROUND_TEXTURE)
    rightBackground:SetTexCoord(
        BACKGROUND_SPLIT,
        BACKGROUND_VISIBLE_RIGHT,
        BACKGROUND_VISIBLE_TOP,
        BACKGROUND_VISIBLE_BOTTOM
    )
    panel.rightBackground = rightBackground

    local panelIcon = panel:CreateTexture(nil, "BACKGROUND", nil, -1)
    panelIcon:SetSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
    panelIcon:SetPoint(
        "CENTER",
        leftBackground,
        "TOPLEFT",
        PREVIEW_CENTER_X,
        -PREVIEW_CENTER_Y
    )
    panelIcon:SetTexture(PREVIEW_TEXTURE)
    panelIcon:SetTexCoord(0, 1, 0, 1)
    panel.icon = panelIcon

    panel.buttons = {}
    for index, choice in ipairs(CHOICES) do
        local button = CreateFrame("Button", "LiteToolsAutoRollButton" .. index, panel)
        local expansion = BUTTON_EXPANSIONS[index] or 0
        button:SetSize(BUTTON_SIZE + expansion * 2, BUTTON_SIZE + expansion * 2)
        local offset = BUTTON_OFFSETS[index]
        local buttonX = LEFT_BACKGROUND_WIDTH
            + BUTTON_HORIZONTAL_PADDING
            + (index - 1) * (BUTTON_SIZE + BUTTON_SPACING)
            + offset.x
            - expansion
        button:SetPoint(
            "TOPLEFT",
            panel,
            "TOPLEFT",
            buttonX,
            -BUTTON_TOP + offset.y + expansion
        )
        button:SetNormalAtlas(choice.normalAtlas, false)
        button:SetPushedAtlas(choice.pushedAtlas, false)
        button:SetHighlightAtlas(choice.highlightAtlas, "ADD")
        local availabilityGlow = button:CreateTexture(nil, "OVERLAY")
        availabilityGlow:SetAllPoints()
        availabilityGlow:SetAtlas(choice.highlightAtlas, false)
        availabilityGlow:SetBlendMode("ADD")
        availabilityGlow:SetAlpha(0.35)
        availabilityGlow:Hide()
        button.availabilityGlow = availabilityGlow
        local selectionGlow = button:CreateTexture(nil, "BACKGROUND")
        selectionGlow:SetSize(63, 63)
        selectionGlow:SetPoint("CENTER")
        selectionGlow:SetAtlas("ChallengeMode-KeystoneSlotFrameGlow", false)
        selectionGlow:Hide()
        button.selectionGlow = selectionGlow

        local startingPriority = index
        button:SetScript("OnClick", function() StartBatch(startingPriority) end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self:IsEnabled() then
                self.selectionGlow:Show()
            end
            if startingPriority == #CHOICES then
                GameTooltip:SetText(Addon.L.PASS_ALL_LOOT)
            elseif self.autoRollChoiceAvailable then
                GameTooltip:SetText(Addon.L[choice.labelKey])
                GameTooltip:AddLine(Addon.L.AUTO_ROLL_TOOLTIP, 1, 1, 1, true)
            else
                GameTooltip:SetText(Addon.L[choice.labelKey])
                GameTooltip:AddLine(Addon.L.AUTO_ROLL_UNAVAILABLE, 1, 0.2, 0.2, true)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            self.selectionGlow:Hide()
            GameTooltip:Hide()
        end)
        panel.buttons[index] = button
    end
    panel:Hide()
    return panel
end

local function SetPreviewMode(enabled)
    previewMode = not not enabled
    if previewMode and not EnsurePanel() then
        previewMode = false
        print("|cffffd200LiteTools:|r " .. Addon.L.AUTO_ROLL_PREVIEW_UNAVAILABLE)
        return
    end
    UpdatePanel()
    print(
        "|cffffd200LiteTools:|r "
            .. (previewMode and Addon.L.AUTO_ROLL_PREVIEW_SHOWN
                or Addon.L.AUTO_ROLL_PREVIEW_HIDDEN)
    )
end

SLASH_LITETOOLSROLLPREVIEW1 = "/ltrollpreview"
SLASH_LITETOOLSROLLPREVIEW2 = "/ltrp"
SlashCmdList = SlashCmdList or {}
SlashCmdList.LITETOOLSROLLPREVIEW = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "show" then
        SetPreviewMode(true)
    elseif command == "hide" then
        SetPreviewMode(false)
    else
        SetPreviewMode(not previewMode)
    end
end

local function InstallConfirmationHook()
    if confirmationHookInstalled
        or type(hooksecurefunc) ~= "function"
        or type(ConfirmLootRoll) ~= "function"
    then
        return
    end
    hooksecurefunc("ConfirmLootRoll", CompleteConfirmation)
    confirmationHookInstalled = true
end

local function InstallPanelHooks()
    if panelHooksInstalled or not GroupLootContainer then return end
    GroupLootContainer:HookScript("OnShow", UpdatePanel)
    GroupLootContainer:HookScript("OnHide", function()
        if panel then panel:Hide() end
        StopBatch()
        wipe(submittedRolls)
    end)
    if type(GroupLootContainer_AddFrame) == "function" then
        hooksecurefunc("GroupLootContainer_AddFrame", UpdatePanel)
    end
    if type(GroupLootContainer_RemoveFrame) == "function" then
        hooksecurefunc("GroupLootContainer_RemoveFrame", UpdatePanel)
    end
    panelHooksInstalled = true
end

local function ApplyAutoRoll()
    local db = DB()
    if not db then return end
    if db.autoRollGear and GroupLootContainer then
        EnsurePanel()
        InstallConfirmationHook()
        InstallPanelHooks()
        UpdatePanel()
    else
        StopBatch()
        wipe(submittedRolls)
        if panel and not previewMode then panel:Hide() end
    end
end

Addon:RegisterSetting("autoRollGear", false, Addon.BooleanSetting, ApplyAutoRoll)
Addon:RegisterSetting("autoRollPanelAnchorPosition", nil, Addon.PositionSetting)
Addon:RegisterSetting("autoRollPanelAnchorHidden", false, Addon.BooleanSetting)
Addon:RegisterSetting("showAutoRollPanelAnchor", false, Addon.BooleanSetting, function(value)
    local db = DB()
    if value then db.autoRollPanelAnchorHidden = false end
    ApplyPanelAnchor(true)
end)
Addon:RegisterSettingCallback("showGroupLootAnchor", UpdatePanel)

Addon:RegisterEvent("PLAYER_LOGIN", function()
    if Addon:GetSetting("showAutoRollPanelAnchor") then ApplyPanelAnchor(true) end
    ApplyAutoRoll()
end)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if Addon:GetSetting("showAutoRollPanelAnchor") then ApplyPanelAnchor(true) end
    ApplyAutoRoll()
end)
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    Addon:RegisterEvent(event, function()
        if Addon:GetSetting("showAutoRollPanelAnchor") then ApplyPanelAnchor(true) end
        UpdatePanel()
    end, function(db) return db.showAutoRollPanelAnchor end)
end
Addon:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
    if Addon:GetSetting("showAutoRollPanelAnchor") then ApplyPanelAnchor(true) end
end, function(db) return db.showAutoRollPanelAnchor end)
Addon:RegisterEvent("CONFIRM_LOOT_ROLL", function(_, ...) HandleConfirmation(...) end,
    function(db) return db.autoRollGear end)
Addon:RegisterEvent("CONFIRM_DISENCHANT_ROLL", function(_, ...) HandleConfirmation(...) end,
    function(db) return db.autoRollGear end)
Addon:RegisterEvent("CANCEL_LOOT_ROLL", function(_, ...)
    HandleCancelled(...)
    UpdatePanel()
end, function(db) return db.autoRollGear end)
Addon:RegisterEvent("CANCEL_ALL_LOOT_ROLLS", function()
    StopBatch()
    wipe(submittedRolls)
    UpdatePanel()
end, function(db) return db.autoRollGear end)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_UIPanels_Game" then
        if Addon:GetSetting("showAutoRollPanelAnchor") then ApplyPanelAnchor(true) end
        ApplyAutoRoll()
    end
end)
