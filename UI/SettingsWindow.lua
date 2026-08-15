local _, Addon = ...

local L = Addon.L
local UI = Addon.SettingsUI
local settingsWindow
local pages = {}
local navigationButtons = {}
local panelCreated = false
local WINDOW_WIDTH = 980
local WINDOW_HEIGHT = 680
local WINDOW_MARGIN = 40

local function SetHousingAtlas(texture, atlas, fallbackColor)
    local atlasInfo = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(atlas)
    if atlasInfo then
        texture:SetAtlas(atlas, false)
        return
    end

    local color = fallbackColor or { 0.08, 0.06, 0.04, 0.96 }
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function CreateHousingTexture(parent, layer, atlas, fallbackColor, subLevel)
    local texture = parent:CreateTexture(nil, layer, nil, subLevel)
    SetHousingAtlas(texture, atlas, fallbackColor)
    return texture
end

local function CreateSettingsPage(parent, key, titleText, contentHeight)
    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "LiteToolsSettings" .. key .. "ScrollFrame",
        parent,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", 4, -62)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 14)
    scrollFrame:Hide()

    local content = CreateFrame(
        "Frame",
        "LiteToolsSettings" .. key .. "Content",
        scrollFrame
    )
    content:SetSize(660, contentHeight)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(_, width, height)
        content:SetWidth(math.max(1, width))
        content:SetHeight(math.max(contentHeight, height))
    end)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge2")
    title:SetPoint("TOPLEFT", 28, -25)
    title:SetText(titleText)
    title:Hide()

    local divider = CreateHousingTexture(
        parent,
        "ARTWORK",
        "house-list-open-divider",
        { 0.55, 0.38, 0.16, 0.75 }
    )
    divider:SetPoint("TOPLEFT", 20, -54)
    divider:SetPoint("TOPRIGHT", -24, -54)
    divider:SetHeight(4)
    divider:Hide()

    pages[key] = {
        scrollFrame = scrollFrame,
        title = title,
        divider = divider,
    }
    return content
end

local function SelectSettingsPage(key)
    for pageKey, page in pairs(pages) do
        local selected = pageKey == key
        page.scrollFrame:SetShown(selected)
        page.title:SetShown(selected)
        page.divider:SetShown(selected)
    end

    for pageKey, button in pairs(navigationButtons) do
        local selected = pageKey == key
        button.Selected:SetShown(selected)
        button.Label:SetTextColor(
            selected and 1 or 0.82,
            selected and 0.82 or 0.76,
            selected and 0.18 or 0.62
        )
    end
end

local function CreateNavigationButton(parent, key, labelText, index)
    local button = CreateFrame("Button", nil, parent)
    local top = -76 - ((index - 1) * 47)
    button:SetPoint("TOPLEFT", 6, top)
    button:SetPoint("TOPRIGHT", -7, top)
    button:SetHeight(42)

    local background = CreateHousingTexture(
        button,
        "BACKGROUND",
        "housefinder_neighborhood-list-item-default",
        { 0.12, 0.09, 0.05, 0.9 }
    )
    background:SetAllPoints()

    local selected = CreateHousingTexture(
        button,
        "ARTWORK",
        "housefinder_neighborhood-list-item-highlight",
        { 0.42, 0.28, 0.08, 0.78 }
    )
    selected:SetAllPoints()
    selected:Hide()
    button.Selected = selected

    local highlight = CreateHousingTexture(
        button,
        "HIGHLIGHT",
        "housefinder_neighborhood-list-item-highlight",
        { 0.72, 0.52, 0.16, 0.35 }
    )
    highlight:SetAllPoints()
    highlight:SetAlpha(0.55)

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 18, 0)
    label:SetPoint("RIGHT", -12, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)
    button.Label = label

    button:SetScript("OnClick", function()
        SelectSettingsPage(key)
        if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    navigationButtons[key] = button
end

local function CreateAutoRollSettings(content, left, right)
    UI.CreateSectionTitle(content, L.SETTINGS_ALERT_ANCHORS, -20)
    UI.CreateCheckButton(content, "LiteToolsLootAlertAnchorCheck",
        L.LOOT_ALERT_ANCHOR, "showLootAlertAnchor", left, -42)
    UI.CreateCheckButton(content, "LiteToolsGroupLootAnchorCheck",
        L.GROUP_LOOT_ANCHOR, "showGroupLootAnchor", right, -42)
    UI.CreateCheckButton(content, "LiteToolsAchievementAlertAnchorCheck",
        L.ACHIEVEMENT_ALERT_ANCHOR, "showAchievementAlertAnchor", left, -76)
    UI.CreateCheckButton(content, "LiteToolsAutoRollPanelAnchorCheck",
        L.AUTO_ROLL_PANEL_ANCHOR, "showAutoRollPanelAnchor", right, -76)
    UI.CreateCheckButton(content, "LiteToolsAutoRollGearCheck",
        L.AUTO_ROLL_GEAR, "autoRollGear", left, -126)
    UI.CreateCheckButton(content, "LiteToolsAutoRollFullAllCheck",
        L.AUTO_ROLL_FULL_ALL, "autoRollFullAll", right, -126)
    UI.CreateCheckButton(content, "LiteToolsAutoRollMuteCheck",
        L.AUTO_ROLL_MUTE, "autoRollMuted", left, -160)

    local soundEditBox = UI.CreateEditBox(content,
        "LiteToolsAutoRollSoundIDEditBox", L.AUTO_ROLL_SOUND_ID,
        "autoRollSoundID", left, -205, 160, 12)
    local preview = CreateFrame("Button", "LiteToolsAutoRollSoundPreviewButton",
        content, "UIPanelButtonTemplate")
    preview:SetPoint("LEFT", soundEditBox, "RIGHT", 12, 0)
    preview:SetSize(70, 24)
    UI.SetButtonText(preview, L.AUTO_ROLL_SOUND_PREVIEW)
    preview:SetScript("OnClick", function()
        soundEditBox:ClearFocus()
        if not Addon:PreviewAutoRollSound() then
            print("|cffffd200LiteTools:|r " .. L.AUTO_ROLL_SOUND_INVALID)
        end
    end)
end

local function CreateCombatAlertSettings(content, left, right)
    UI.CreateSectionTitle(content, L.COMBAT_ALERT, -278)
    UI.CreateCheckButton(content, "LiteToolsCombatAlertCheck",
        L.COMBAT_ALERT, "showCombatAlert", left, -300)
    UI.CreateSlider(content, "LiteToolsCombatAlertDurationSlider",
        L.COMBAT_ALERT_DURATION, "combatAlertDuration", left, -340,
        1, 3, L.SECONDS)
    UI.CreateSlider(content, "LiteToolsCombatAlertScaleSlider",
        L.COMBAT_ALERT_SCALE, "combatAlertScale", right, -340,
        50, 200, L.PERCENT)

    UI.CreateSectionTitle(content, L.LEAVE_COMBAT_ALERT, -420)
    UI.CreateCheckButton(content, "LiteToolsLeaveCombatAlertCheck",
        L.LEAVE_COMBAT_ALERT, "showLeaveCombatAlert", left, -442)
    UI.CreateSlider(content, "LiteToolsLeaveCombatAlertDurationSlider",
        L.COMBAT_ALERT_DURATION, "leaveCombatAlertDuration", left, -482,
        1, 3, L.SECONDS)
    UI.CreateSlider(content, "LiteToolsLeaveCombatAlertScaleSlider",
        L.COMBAT_ALERT_SCALE, "leaveCombatAlertScale", right, -482,
        50, 200, L.PERCENT)

    UI.CreateSectionTitle(content, L.COMBAT_TIMER, -554)
    UI.CreateCheckButton(content, "LiteToolsCombatTimerCheck",
        L.COMBAT_TIMER, "showCombatTimer", left, -576)
    UI.CreateSlider(content, "LiteToolsCombatTimerScaleSlider",
        L.COMBAT_TIMER_SCALE, "combatTimerScale", right, -554,
        50, 200, L.PERCENT)
end

local function PopulateSettingsPages(pageContent)
    local left = 24
    local right = 344
    local content = pageContent.General

    UI.CreateCheckButton(content, "LiteToolsAutoDeleteCheck", L.AUTO_DELETE,
        "autoTypeDelete", left, -24)
    UI.CreateCheckButton(content, "LiteToolsSkipCinematicsCheck", L.SKIP_CINEMATICS,
        "skipCinematics", right, -24)
    UI.CreateCheckButton(content, "LiteToolsFixedMicroMenuCheck", L.FIXED_MICRO_MENU,
        "fixedMicroMenu", left, -66)
    UI.CreateCheckButton(content, "LiteToolsInstanceProgressCheck", L.INSTANCE_PROGRESS,
        "showInstanceProgress", right, -66)

    content = pageContent.StatusBars
    UI.CreateSlider(content, "LiteToolsExperienceWidthSlider", L.EXPERIENCE_BAR_WIDTH,
        "experienceBarWidth", left, -24, 200, 1200, L.PIXELS)
    UI.CreateSlider(content, "LiteToolsReputationWidthSlider", L.REPUTATION_BAR_WIDTH,
        "reputationBarWidth", right, -24, 200, 1200, L.PIXELS)
    UI.CreateCheckButton(content, "LiteToolsHideExperienceBarCheck",
        L.HIDE_EXPERIENCE_BAR, "hideExperienceBar", left, -80)
    UI.CreateCheckButton(content, "LiteToolsHideReputationBarCheck",
        L.HIDE_REPUTATION_BAR, "hideReputationBar", right, -80)
    UI.CreateSlider(content, "LiteToolsHonorWidthSlider", L.HONOR_BAR_WIDTH,
        "honorBarWidth", left, -136, 200, 1200, L.PIXELS)
    UI.CreateCheckButton(content, "LiteToolsHideHonorBarCheck", L.HIDE_HONOR_BAR,
        "hideHonorBar", left, -192)

    content = pageContent.Minimap
    UI.CreateCheckButton(content, "LiteToolsMinimapBorderCheck",
        L.REPLACE_MINIMAP_BORDER, "replaceMinimapBorder", left, -24)
    UI.CreateCheckButton(content, "LiteToolsMinimapMoveCheck", L.MOVE_MINIMAP,
        "moveableMinimap", right, -24)
    UI.CreateMinimapBorderColorButton(content, left, -68)
    UI.CreateCheckButton(content, "LiteToolsMinimapLockCheck", L.LOCK_MINIMAP,
        "minimapPositionLocked", right, -62)
    UI.CreateSlider(content, "LiteToolsMinimapHeaderScaleSlider",
        L.MINIMAP_HEADER_SCALE, "minimapHeaderScale", left, -128,
        50, 200, L.PERCENT)

    content = pageContent.MerchantBags
    UI.CreateCheckButton(content, "LiteToolsAutoSellJunkCheck", L.AUTO_SELL_JUNK,
        "autoSellJunk", left, -24)
    UI.CreateCheckButton(content, "LiteToolsAutoRepairCheck", L.AUTO_REPAIR,
        "autoRepair", right, -24)
    UI.CreateCheckButton(content, "LiteToolsHideChildBagsCheck", L.HIDE_CHILD_BAGS,
        "hideChildBags", left, -66)
    UI.CreateCheckButton(content, "LiteToolsHideAllBagButtonsCheck", L.HIDE_ALL_BAGS,
        "hideAllBagButtons", right, -66)

    CreateAutoRollSettings(pageContent.AlertsLoot, left, right)
    CreateCombatAlertSettings(pageContent.AlertsLoot, left, right)

    UI.CreateCheckButton(pageContent.ActionBars,
        "LiteToolsActionBarHotkeyAliasesCheck", L.ACTION_BAR_ALIASES,
        "customActionBarHotkeyAliases", left, -24)

end

local function CreateStandaloneSettingsWindow()
    if settingsWindow then
        return settingsWindow
    end

    local frame = CreateFrame("Frame", "LiteToolsSettingsWindow", UIParent)
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetDontSavePosition(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()
    settingsWindow = frame

    local function ApplyWindowScale()
        local parentWidth = UIParent:GetWidth()
        local parentHeight = UIParent:GetHeight()
        if not parentWidth or parentWidth <= 0
            or not parentHeight or parentHeight <= 0 then
            return
        end

        local availableWidth = math.max(1, parentWidth - WINDOW_MARGIN)
        local availableHeight = math.max(1, parentHeight - WINDOW_MARGIN)
        local scale = math.min(
            1,
            availableWidth / WINDOW_WIDTH,
            availableHeight / WINDOW_HEIGHT
        )
        if math.abs(frame:GetScale() - scale) > 0.001 then
            frame:SetScale(scale)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER")
        end
    end

    frame.ApplyWindowScale = ApplyWindowScale
    ApplyWindowScale()

    local background = CreateHousingTexture(frame, "BACKGROUND",
        "housing-dashboard-bg-elwynn", { 0.07, 0.055, 0.035, 0.98 })
    background:SetAllPoints()
    local borderFrame = CreateFrame("Frame", nil, frame)
    borderFrame:SetAllPoints()
    borderFrame:SetFrameLevel(frame:GetFrameLevel() + 100)
    local border = CreateHousingTexture(borderFrame, "OVERLAY",
        "housing-simple-wood-frame", { 0.38, 0.24, 0.09, 1 })
    border:SetAllPoints()

    local navigation = CreateFrame("Frame", nil, frame)
    navigation:SetPoint("TOPLEFT", 4, -4)
    navigation:SetPoint("BOTTOMLEFT", 4, 4)
    navigation:SetWidth(256)
    local navigationBackground = CreateHousingTexture(navigation, "BACKGROUND",
        "housefinder_neighborhood-list-bg", { 0.055, 0.045, 0.03, 0.96 })
    navigationBackground:SetAllPoints()
    local navigationHeader = CreateHousingTexture(navigation, "ARTWORK",
        "housefinder_header-bg-gradient", { 0.20, 0.13, 0.055, 0.92 })
    navigationHeader:SetPoint("TOPLEFT", 1, -1)
    navigationHeader:SetPoint("TOPRIGHT", -1, -1)
    navigationHeader:SetHeight(68)

    local addonTitle = navigation:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge2")
    addonTitle:SetPoint("TOPLEFT", 18, -20)
    addonTitle:SetText(L.ADDON_TITLE)
    local navigationTitle = navigation:CreateFontString(nil, "OVERLAY",
        "GameFontHighlightSmall")
    navigationTitle:SetPoint("TOPLEFT", addonTitle, "BOTTOMLEFT", 1, -6)
    navigationTitle:SetText(L.SETTINGS_MODULES)

    local contentPanel = CreateFrame("Frame", nil, frame)
    -- The atlases contribute about four transparent pixels at the seam. A
    -- six-pixel frame gap makes the visible border-to-border gap 10 pixels.
    contentPanel:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 6, 0)
    contentPanel:SetPoint("BOTTOMRIGHT", -8, 4)
    local contentBackground = CreateHousingTexture(contentPanel, "BACKGROUND",
        "housing-basic-container", { 0.075, 0.06, 0.04, 0.97 })
    contentBackground:SetAllPoints()
    local header = CreateHousingTexture(contentPanel, "BORDER",
        "housing-basic-container-woodheader", { 0.25, 0.16, 0.07, 0.98 })
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(61)
    local foliage = CreateHousingTexture(contentPanel, "ARTWORK",
        "housing-decorative-foliage-left", { 0.24, 0.22, 0.08, 0.35 })
    foliage:SetPoint("BOTTOMLEFT", 3, 2)
    local foliageInfo = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo("housing-decorative-foliage-left")
    if foliageInfo and foliageInfo.width and foliageInfo.width > 0
        and foliageInfo.height and foliageInfo.height > 0 then
        local foliageScale = math.min(150 / foliageInfo.width, 96 / foliageInfo.height)
        foliage:SetSize(
            foliageInfo.width * foliageScale,
            foliageInfo.height * foliageScale
        )
    else
        foliage:SetSize(150, 96)
    end
    local closeButton = CreateFrame("Button", nil, frame)
    closeButton:SetPoint("TOPRIGHT", -19, -20)
    closeButton:SetSize(28, 28)
    local closeNormal = closeButton:CreateTexture(nil, "ARTWORK")
    SetHousingAtlas(closeNormal, "RedButton-Exit", { 0.55, 0.08, 0.04, 1 })
    closeNormal:SetAllPoints()
    closeButton:SetNormalTexture(closeNormal)
    local closePushed = closeButton:CreateTexture(nil, "ARTWORK")
    SetHousingAtlas(closePushed, "RedButton-exit-pressed", { 0.35, 0.035, 0.02, 1 })
    closePushed:SetAllPoints()
    closeButton:SetPushedTexture(closePushed)
    local closeHighlight = closeButton:CreateTexture(nil, "HIGHLIGHT")
    SetHousingAtlas(closeHighlight, "RedButton-Highlight", { 1, 0.35, 0.15, 0.35 })
    closeHighlight:SetAllPoints()
    closeHighlight:SetBlendMode("ADD")
    closeButton:SetHighlightTexture(closeHighlight)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local moduleDefinitions = {
        { key = "General", text = L.SECTION_GENERAL, height = 420 },
        { key = "StatusBars", text = L.SECTION_STATUS_BARS, height = 450 },
        { key = "Minimap", text = L.SECTION_MINIMAP, height = 420 },
        { key = "MerchantBags", text = L.SECTION_MERCHANT_BAGS, height = 360 },
        { key = "AlertsLoot", text = L.SECTION_ALERTS_LOOT, height = 680 },
        { key = "ActionBars", text = L.SECTION_ACTION_BARS, height = 320 },
    }
    local pageContent = {}
    for index, definition in ipairs(moduleDefinitions) do
        CreateNavigationButton(navigation, definition.key, definition.text, index)
        pageContent[definition.key] = CreateSettingsPage(contentPanel,
            definition.key, definition.text, definition.height)
    end
    PopulateSettingsPages(pageContent)

    frame:SetScript("OnShow", function()
        ApplyWindowScale()
        frame:Raise()
        UI.RefreshControls()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        end
    end)
    frame:SetScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        end
    end)
    table.insert(UISpecialFrames, frame:GetName())
    SelectSettingsPage("General")
    return frame
end

function Addon:OpenSettings()
    CreateStandaloneSettingsWindow():Show()
end

function Addon:ToggleSettings()
    local frame = CreateStandaloneSettingsWindow()
    frame:SetShown(not frame:IsShown())
end

local function CreateSettingsPanel()
    if panelCreated then
        return
    end
    panelCreated = true

    local panel = CreateFrame("Frame")
    panel.name = L.ADDON_TITLE
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.ADDON_TITLE)
    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText(L.ADDON_DESCRIPTION)

    local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -24)
    openButton:SetSize(240, 28)
    UI.SetButtonText(openButton, L.OPEN_SETTINGS_WINDOW)
    openButton:SetScript("OnClick", function() Addon:OpenSettings() end)

    local commandHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    commandHint:SetPoint("TOPLEFT", openButton, "BOTTOMLEFT", 0, -12)
    commandHint:SetText(L.SETTINGS_COMMAND_HINT)

    local category = Settings.RegisterCanvasLayoutCategory(panel, L.ADDON_TITLE)
    Settings.RegisterAddOnCategory(category)
    Addon.settingsCategoryID = category:GetID()
end

local function RefreshWindowScale()
    if settingsWindow and settingsWindow.ApplyWindowScale then
        settingsWindow:ApplyWindowScale()
    end
end

Addon:RegisterEvent("DISPLAY_SIZE_CHANGED", RefreshWindowScale)
Addon:RegisterEvent("UI_SCALE_CHANGED", RefreshWindowScale)
Addon:RegisterEvent("PLAYER_LOGIN", CreateSettingsPanel)

SLASH_LITETOOLSSETTINGS1 = "/lt"
SLASH_LITETOOLSSETTINGS2 = "/litetools"
SlashCmdList = SlashCmdList or {}
SlashCmdList.LITETOOLSSETTINGS = function()
    if not panelCreated then
        CreateSettingsPanel()
    end
    Addon:ToggleSettings()
end
