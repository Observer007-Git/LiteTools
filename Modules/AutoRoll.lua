local _, Addon = ...

local CHOICES = {
    { labelKey = "NEED", rollType = 1, suffix = "need" },
    { labelKey = "GREED", rollType = 2, suffix = "greed" },
    { labelKey = "DISENCHANT", rollType = 3, suffix = "disenchant" },
    { labelKey = "TRANSMOG", rollType = 4, suffix = "transmog" },
    { labelKey = "PASS", rollType = 0, suffix = "pass" },
}
for _, choice in ipairs(CHOICES) do
    choice.normalAtlas = "lootroll-toast-icon-" .. choice.suffix .. "-up"
    choice.pushedAtlas = "lootroll-toast-icon-" .. choice.suffix .. "-down"
    choice.highlightAtlas = "lootroll-toast-icon-" .. choice.suffix .. "-highlight"
end

local PANEL_HEIGHT = 96
local LEFT_BACKGROUND_WIDTH = 82
local RIGHT_BACKGROUND_WIDTH = 365
local PANEL_WIDTH = LEFT_BACKGROUND_WIDTH + RIGHT_BACKGROUND_WIDTH
local BUTTON_SIZE, BUTTON_SPACING = 48, 10
local BUTTON_HORIZONTAL_PADDING, BUTTON_TOP = 30, 20
local BUTTON_OFFSETS = {
    [1] = { x = -8, y = -2 },
    [2] = { x = 2, y = 1 },
    [3] = { x = 8, y = 0 },
    [4] = { x = 8, y = 0 },
    [5] = { x = 8, y = 1 },
}
local BUTTON_EXPANSIONS = { [1] = 1, [2] = 1 }
local ALL_OF_IT_PANEL_SIZE = 96
local ALL_OF_IT_BUTTON_SIZE = 88
local ALL_OF_IT_ATLAS = "charactercreate-icon-dice"

local panel
local panelAnchor
local panelHooksInstalled = false
local confirmationHookInstalled = false
local batch
local submittedRolls = {}
local previewMode = false
local UpdatePanel

local function DB() return Addon:GetDatabase() end

local function SanitizeSoundID(value)
    local soundID = tonumber(tostring(value or ""):match("^%s*(.-)%s*$"))
    if not soundID or soundID <= 0 or soundID ~= math.floor(soundID) then return "" end
    return tostring(soundID)
end

local function PlayConfiguredSound(ignoreMute)
    local db = DB()
    if not db or (db.autoRollMuted and not ignoreMute) then return false end
    local soundID = tonumber(db.autoRollSoundID)
    if not soundID or type(PlaySoundFile) ~= "function" then return false end
    local ok, played = pcall(PlaySoundFile, soundID, "Master")
    return ok and played ~= false
end

function Addon:PreviewAutoRollSound()
    return PlayConfiguredSound(true)
end

local function CollectPendingRolls()
    if not GroupLootContainer then return {} end
    local queue, seen, indexedFrames = {}, {}, {}
    for index, rollFrame in pairs(GroupLootContainer.rollFrames or {}) do
        if type(index) == "number" and rollFrame and rollFrame.rollID
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
    local _, itemName, _, _, _, canNeed, canGreed, canDisenchant,
        _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if not itemName then return nil end
    return { canNeed, canGreed, canDisenchant, canTransmog, true }
end

local function GetPreferredRollType(rollID, startingPriority)
    local allowed = GetAllowedChoices(rollID)
    if not allowed then return nil end
    for priority = startingPriority, #CHOICES do
        if allowed[priority] then return CHOICES[priority].rollType end
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
    if not currentBatch or currentBatch.waitingRollID ~= rollID
        or currentBatch.waitingRollType ~= rollType
    then
        return
    end
    currentBatch.waitingRollID = nil
    currentBatch.waitingRollType = nil
    currentBatch.currentRollID = nil
    C_Timer.After(0, function()
        if batch == currentBatch and not currentBatch.waitingRollID then ProcessBatch() end
    end)
end

local function HandleConfirmation(rollID, rollType)
    local currentBatch = batch
    if not currentBatch or currentBatch.currentRollID ~= rollID then return end
    currentBatch.waitingRollID = rollID
    currentBatch.waitingRollType = rollType
    C_Timer.After(0, function()
        if not batch or batch.waitingRollID ~= rollID
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
            currentBatch.submittedCount = currentBatch.submittedCount + 1
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
    local currentBatch = {
        queue = queue,
        index = 1,
        startingPriority = startingPriority,
        submittedCount = 0,
    }
    batch = currentBatch
    UpdatePanel()
    ProcessBatch()
    if currentBatch.submittedCount > 0 then PlayConfiguredSound(false) end
end

local function PositionPanel()
    local db = DB()
    if not panel or not GroupLootContainer or not db then return end
    panel:ClearAllPoints()
    if db.showAutoRollPanelAnchor and panelAnchor then
        panel:SetPoint("TOP", panelAnchor, "BOTTOM", 0, -5)
    else
        panel:SetPoint("TOP", GroupLootContainer, "BOTTOM", 0, -5)
    end
end

local function PositionPanelAnchor()
    if not panelAnchor then return end
    Addon.Anchors:Position(panelAnchor, "autoRollPanelAnchorPosition", 0.5, 0.18)
    PositionPanel()
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
    if db.showAutoRollPanelAnchor then
        local anchor = EnsurePanelAnchor()
        if reposition then PositionPanelAnchor() end
        anchor:SetShown(not db.autoRollPanelAnchorHidden)
    elseif panelAnchor then
        panelAnchor:Hide()
    end
    PositionPanel()
end

local function UpdateRegularButtonStates(pendingRolls)
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
        button.choiceAvailable = not not available[priority]
        button.availabilityGlow:SetShown(enabled)
        if not enabled then button.selectionGlow:Hide() end
    end
end

local function ShowRegularPreview()
    for _, button in ipairs(panel.buttons) do
        button:SetEnabled(true)
        button:SetAlpha(1)
        button.choiceAvailable = true
        button.availabilityGlow:Show()
    end
end

local function ApplyPanelMode(fullAllMode)
    panel.regularFrame:SetShown(not fullAllMode)
    panel.allOfItButton:SetShown(fullAllMode)
    if fullAllMode then
        panel:SetSize(ALL_OF_IT_PANEL_SIZE, ALL_OF_IT_PANEL_SIZE)
    else
        panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    end
end

UpdatePanel = function()
    if not panel then return end
    local db = DB()
    if not previewMode and (not db or not db.autoRollGear) then
        panel:Hide()
        return
    end
    local pendingRolls = CollectPendingRolls()
    local fullAllMode = db and db.autoRollFullAll
    ApplyPanelMode(fullAllMode)
    PositionPanel()
    if fullAllMode then
        local enabled = not batch and (#pendingRolls > 0 or previewMode)
        panel.allOfItButton:SetEnabled(enabled)
        panel.allOfItButton:SetAlpha(enabled and 1 or 0.20)
        panel.allOfItButton.availabilityGlow:SetShown(enabled)
    elseif previewMode and #pendingRolls == 0 then
        ShowRegularPreview()
    else
        UpdateRegularButtonStates(pendingRolls)
    end
    panel:SetShown(previewMode or (db and db.autoRollGear and GroupLootContainer:IsShown()
        and #pendingRolls > 0))
end

local function ConfigureButtonTooltip(button, startingPriority)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self:IsEnabled() and self.selectionGlow then self.selectionGlow:Show() end
        if startingPriority == #CHOICES then
            GameTooltip:SetText(Addon.L.PASS_ALL_LOOT)
        elseif self.choiceAvailable then
            GameTooltip:SetText(Addon.L[CHOICES[startingPriority].labelKey])
            GameTooltip:AddLine(Addon.L.AUTO_ROLL_TOOLTIP, 1, 1, 1, true)
        else
            GameTooltip:SetText(Addon.L[CHOICES[startingPriority].labelKey])
            GameTooltip:AddLine(Addon.L.AUTO_ROLL_UNAVAILABLE, 1, 0.2, 0.2, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if self.selectionGlow then self.selectionGlow:Hide() end
        GameTooltip:Hide()
    end)
end

local function EnsurePanel()
    if panel or not GroupLootContainer then return panel end
    panel = CreateFrame("Frame", "LiteToolsAutoRollPanel", UIParent)
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("TOP", GroupLootContainer, "BOTTOM", 0, -5)

    local regularFrame = CreateFrame("Frame", nil, panel)
    regularFrame:SetAllPoints()
    panel.regularFrame = regularFrame
    local regularBackground = regularFrame:CreateTexture(nil, "BACKGROUND")
    regularBackground:SetSize(PANEL_WIDTH, 140)
    regularBackground:SetPoint("CENTER", regularFrame, "CENTER", 33, 28)
    regularBackground:SetAlpha(1)
    regularBackground:SetAtlas("characterupdate_green-glow-and-filigree", false)

    panel.buttons = {}
    for index, choice in ipairs(CHOICES) do
        local button = CreateFrame("Button", "LiteToolsAutoRollButton" .. index, regularFrame)
        local expansion = BUTTON_EXPANSIONS[index] or 0
        button:SetSize(BUTTON_SIZE + expansion * 2, BUTTON_SIZE + expansion * 2)
        local offset = BUTTON_OFFSETS[index]
        local x = LEFT_BACKGROUND_WIDTH + BUTTON_HORIZONTAL_PADDING
            + (index - 1) * (BUTTON_SIZE + BUTTON_SPACING) + offset.x - expansion
        button:SetPoint("TOPLEFT", regularFrame, "TOPLEFT",
            x, -BUTTON_TOP + offset.y + expansion)
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
        selectionGlow:SetSize(128, 128)
        selectionGlow:SetPoint("CENTER")
        selectionGlow:SetAtlas("AftLevelup-WhiteStarBurst", false)
        selectionGlow:Hide()
        button.selectionGlow = selectionGlow
        local startingPriority = index
        button:SetScript("OnClick", function() StartBatch(startingPriority) end)
        ConfigureButtonTooltip(button, startingPriority)
        panel.buttons[index] = button
    end

    local allOfItButton = CreateFrame("Button", "LiteToolsAllOfItButton", panel)
    allOfItButton:SetSize(ALL_OF_IT_BUTTON_SIZE, ALL_OF_IT_BUTTON_SIZE)
    allOfItButton:SetPoint("CENTER")
    allOfItButton:SetNormalAtlas(ALL_OF_IT_ATLAS, false)
    allOfItButton:SetPushedAtlas(ALL_OF_IT_ATLAS, false)
    allOfItButton:SetHighlightAtlas(ALL_OF_IT_ATLAS, "ADD")
    local allGlow = allOfItButton:CreateTexture(nil, "OVERLAY")
    allGlow:SetAllPoints()
    allGlow:SetAtlas(ALL_OF_IT_ATLAS, false)
    allGlow:SetBlendMode("ADD")
    allGlow:SetAlpha(0.35)
    allGlow:Hide()
    allOfItButton.availabilityGlow = allGlow
    allOfItButton:SetScript("OnClick", function() StartBatch(1) end)
    allOfItButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Addon.L.ALL_OF_IT)
        GameTooltip:AddLine(Addon.L.ALL_OF_IT_TOOLTIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    allOfItButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.allOfItButton = allOfItButton
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
    print("|cffffd200LiteTools:|r "
        .. (previewMode and Addon.L.AUTO_ROLL_PREVIEW_SHOWN or Addon.L.AUTO_ROLL_PREVIEW_HIDDEN))
end

SLASH_LITETOOLSROLLPREVIEW1 = "/ltrollpreview"
SLASH_LITETOOLSROLLPREVIEW2 = "/ltrp"
SlashCmdList = SlashCmdList or {}
SlashCmdList.LITETOOLSROLLPREVIEW = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "show" then SetPreviewMode(true)
    elseif command == "hide" then SetPreviewMode(false)
    else SetPreviewMode(not previewMode) end
end

local function InstallConfirmationHook()
    if confirmationHookInstalled or type(hooksecurefunc) ~= "function"
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

local function ApplyEnabled()
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

Addon:RegisterSetting("autoRollGear", false, Addon.BooleanSetting, ApplyEnabled)
Addon:RegisterSetting("autoRollFullAll", false, Addon.BooleanSetting, UpdatePanel)
Addon:RegisterSetting("autoRollMuted", false, Addon.BooleanSetting)
Addon:RegisterSetting("autoRollSoundID", "", SanitizeSoundID)
Addon:RegisterSetting("autoRollPanelAnchorPosition", nil, Addon.PositionSetting)
Addon:RegisterSetting("autoRollPanelAnchorHidden", false, Addon.BooleanSetting)
Addon:RegisterSetting("showAutoRollPanelAnchor", false, Addon.BooleanSetting, function(value)
    local db = DB()
    if value and db then db.autoRollPanelAnchorHidden = false end
    ApplyPanelAnchor(true)
end)

Addon:RegisterSettingCallback("showGroupLootAnchor", UpdatePanel)

local function HasUI(db)
    return db and (db.autoRollGear or db.showAutoRollPanelAnchor)
end

Addon:RegisterEvent("PLAYER_LOGIN", function()
    ApplyPanelAnchor(true)
    ApplyEnabled()
end, HasUI)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ApplyPanelAnchor(true)
    ApplyEnabled()
end, HasUI)
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED" }) do
    Addon:RegisterEvent(event, function()
        ApplyPanelAnchor(true)
        if UpdatePanel then UpdatePanel() end
    end, function(db) return db and db.showAutoRollPanelAnchor end)
end
Addon:RegisterEvent("CONFIRM_LOOT_ROLL", function(_, ...) HandleConfirmation(...) end,
    function(db) return db and db.autoRollGear end)
Addon:RegisterEvent("CONFIRM_DISENCHANT_ROLL", function(_, ...) HandleConfirmation(...) end,
    function(db) return db and db.autoRollGear end)
Addon:RegisterEvent("CANCEL_LOOT_ROLL", function(_, ...)
    HandleCancelled(...)
    UpdatePanel()
end, function(db) return db and db.autoRollGear end)
Addon:RegisterEvent("CANCEL_ALL_LOOT_ROLLS", function()
    StopBatch()
    wipe(submittedRolls)
    UpdatePanel()
end, function(db) return db and db.autoRollGear end)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_UIPanels_Game" then
        ApplyPanelAnchor(true)
        ApplyEnabled()
    end
end, HasUI)
