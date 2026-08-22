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
local MIN_WINDOW_SCALE = 0.65
local MAX_WINDOW_SCALE = 1.35
local NAVIGATION_TOP_INSET = 30
local NAVIGATION_LIST_TOP_INSET = 48
local NAVIGATION_LIST_PADDING = 6
local NAVIGATION_VISIBLE_ROWS = 7
local NAVIGATION_BUTTON_HEIGHT = 60
local PANEL_BACKGROUND_TOP_OVERLAP = 14
local PANEL_SEAM_OVERLAP = 4

-- Replace the texture or atlas values here to customize the gold-ring icons
-- shown beside each category in the left navigation panel.
local CATEGORY_ICON_CONFIG = {
    General = { texture = "Interface\\Icons\\INV_Misc_Gear_01" },
    StatusBars = { texture = "Interface\\Icons\\INV_Misc_Bandage_01" },
    Minimap = { texture = "Interface\\Icons\\INV_Misc_Map_01" },
    WorldMap = { texture = "Interface\\Icons\\INV_Misc_Map02" },
    MerchantBags = { texture = "Interface\\Icons\\INV_Misc_Bag_10" },
    AlertsLoot = { texture = "Interface\\Icons\\INV_Misc_Bell_01" },
    ActionBars = { texture = "Interface\\Icons\\INV_Misc_Key_03" },
}
Addon.SettingsCategoryIconConfig = CATEGORY_ICON_CONFIG

Addon:RegisterSetting(
    "settingsWindowScale",
    1,
    Addon.NumberSetting(MIN_WINDOW_SCALE, MAX_WINDOW_SCALE, 0.01)
)

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

local function SetCategoryIcon(texture, config)
    config = config or {}
    if config.atlas and C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(config.atlas)
    then
        texture:SetAtlas(config.atlas, false)
    else
        texture:SetTexture(config.texture or 134400)
        local texCoord = config.texCoord or { 0.08, 0.92, 0.08, 0.92 }
        texture:SetTexCoord(
            texCoord[1],
            texCoord[2],
            texCoord[3],
            texCoord[4]
        )
    end
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

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.74, 0.52, 0.18, 0.72)
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
        button:SetSelected(selected)
    end
end

local function CreateNavigationButton(parent, key, labelText, top)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", 16, top)
    button:SetPoint("TOPRIGHT", -12, top)
    button:SetHeight(NAVIGATION_BUTTON_HEIGHT)

    local background = button:CreateTexture(nil, "BACKGROUND")
    SetHousingAtlas(
        background,
        "UI-Journeys-Delve-Card",
        { 0.11, 0.09, 0.07, 0.95 }
    )
    background:SetAllPoints()
    button.Background = background

    local pushed = button:CreateTexture(nil, "BORDER")
    SetHousingAtlas(
        pushed,
        "UI-Journeys-Delve-Companion-button-pressed",
        { 0.18, 0.13, 0.08, 0.98 }
    )
    pushed:SetAllPoints()
    button:SetPushedTexture(pushed)

    local selected = button:CreateTexture(nil, "ARTWORK", nil, 1)
    local selectedAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo("UI-Journeys-Delve-Card-Glow")
    if selectedAtlasInfo then
        selected:SetTexture(
            selectedAtlasInfo.file or selectedAtlasInfo.filename
        )
        selected:SetTexCoord(
            selectedAtlasInfo.rightTexCoord,
            selectedAtlasInfo.leftTexCoord,
            selectedAtlasInfo.topTexCoord,
            selectedAtlasInfo.bottomTexCoord
        )
    else
        selected:SetColorTexture(0.72, 0.52, 0.18, 0.5)
    end
    selected:SetAllPoints()
    selected:SetBlendMode("ADD")
    selected:SetAlpha(0.7)
    selected:Hide()
    button.Selected = selected

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    local highlightAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo("UI-Journeys-Delve-Card-Glow")
    if highlightAtlasInfo then
        highlight:SetTexture(
            highlightAtlasInfo.file or highlightAtlasInfo.filename
        )
        highlight:SetTexCoord(
            highlightAtlasInfo.rightTexCoord,
            highlightAtlasInfo.leftTexCoord,
            highlightAtlasInfo.topTexCoord,
            highlightAtlasInfo.bottomTexCoord
        )
    else
        highlight:SetColorTexture(0.72, 0.52, 0.18, 0.5)
    end
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.7)
    button:SetHighlightTexture(highlight)

    local ring = button:CreateTexture(nil, "ARTWORK", nil, 2)
    ring:SetAtlas("bluemenu-Ring", false)
    ring:SetPoint("LEFT", -15, -1)
    ring:SetSize(95, 96)
    button.Ring = ring

    local icon = button:CreateTexture(nil, "ARTWORK", nil, 1)
    icon:SetPoint("CENTER", ring)
    icon:SetSize(66, 66)
    SetCategoryIcon(icon, CATEGORY_ICON_CONFIG[key])
    button.Icon = icon

    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mask:SetPoint("TOPLEFT", icon, 2, -2)
    mask:SetPoint("BOTTOMRIGHT", icon, -2, 2)
    icon:AddMaskTexture(mask)
    button.IconMask = mask

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", ring, "RIGHT", -2, 0)
    label:SetPoint("RIGHT", -12, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)
    button.Label = label

    button.SetSelected = function(self, selected)
        self.Selected:SetShown(selected)
        self.Label:SetFontObject(selected and "GameFontNormalLarge"
            or "GameFontHighlight")
        self.Label:SetTextColor(
            selected and 1 or 0.9,
            selected and 0.82 or 0.78,
            selected and 0.18 or 0.66
        )
    end

    button:SetScript("OnClick", function()
        SelectSettingsPage(key)
        if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    navigationButtons[key] = button
end

local function CreateAutoRollSettings(content, left)
    UI.CreateSectionTitle(content, L.SETTINGS_ALERT_ANCHORS, -20)
    UI.CreateCheckButton(content, "LiteToolsLootAlertAnchorCheck",
        L.LOOT_ALERT_ANCHOR, "showLootAlertAnchor", left, -42)
    UI.CreateCheckButton(content, "LiteToolsGroupLootAnchorCheck",
        L.GROUP_LOOT_ANCHOR, "showGroupLootAnchor", left, -76)
    UI.CreateCheckButton(content, "LiteToolsAchievementAlertAnchorCheck",
        L.ACHIEVEMENT_ALERT_ANCHOR, "showAchievementAlertAnchor", left, -110)
    UI.CreateCheckButton(content, "LiteToolsAutoRollPanelAnchorCheck",
        L.AUTO_ROLL_PANEL_ANCHOR, "showAutoRollPanelAnchor", left, -144)

    UI.CreateSectionTitle(content, L.SETTINGS_AUTO_ROLL, -194)
    UI.CreateCheckButton(content, "LiteToolsAutoRollGearCheck",
        L.AUTO_ROLL_GEAR, "autoRollGear", left, -216)
    UI.CreateCheckButton(content, "LiteToolsAutoRollFullAllCheck",
        L.AUTO_ROLL_FULL_ALL, "autoRollFullAll", left, -250)
    UI.CreateCheckButton(content, "LiteToolsAutoRollMuteCheck",
        L.AUTO_ROLL_MUTE, "autoRollMuted", left, -284)

    local soundEditBox = UI.CreateEditBox(content,
        "LiteToolsAutoRollSoundIDEditBox", L.AUTO_ROLL_SOUND_ID,
        "autoRollSoundID", left, -326, 160, 12)
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

local function CreateCombatAlertSettings(content, left)
    UI.CreateSectionTitle(content, L.COMBAT_ALERT, -394)
    UI.CreateCheckButton(content, "LiteToolsCombatAlertCheck",
        L.COMBAT_ALERT, "showCombatAlert", left, -416)
    UI.CreateSlider(content, "LiteToolsCombatAlertDurationSlider",
        L.COMBAT_ALERT_DURATION, "combatAlertDuration", left, -458,
        1, 3, L.SECONDS)
    UI.CreateSlider(content, "LiteToolsCombatAlertScaleSlider",
        L.COMBAT_ALERT_SCALE, "combatAlertScale", left, -520,
        50, 200, L.PERCENT)

    UI.CreateSectionTitle(content, L.LEAVE_COMBAT_ALERT, -590)
    UI.CreateCheckButton(content, "LiteToolsLeaveCombatAlertCheck",
        L.LEAVE_COMBAT_ALERT, "showLeaveCombatAlert", left, -612)
    UI.CreateSlider(content, "LiteToolsLeaveCombatAlertDurationSlider",
        L.COMBAT_ALERT_DURATION, "leaveCombatAlertDuration", left, -654,
        1, 3, L.SECONDS)
    UI.CreateSlider(content, "LiteToolsLeaveCombatAlertScaleSlider",
        L.COMBAT_ALERT_SCALE, "leaveCombatAlertScale", left, -716,
        50, 200, L.PERCENT)

    UI.CreateSectionTitle(content, L.COMBAT_TIMER, -786)
    UI.CreateCheckButton(content, "LiteToolsCombatTimerCheck",
        L.COMBAT_TIMER, "showCombatTimer", left, -808)
    UI.CreateSlider(content, "LiteToolsCombatTimerScaleSlider",
        L.COMBAT_TIMER_SCALE, "combatTimerScale", left, -850,
        50, 200, L.PERCENT)
end

local function CreateItemNotificationSettings(content, left)
    UI.CreateSectionTitle(content, L.ITEM_NOTIFICATIONS, -920)
    UI.CreateCheckButton(content, "LiteToolsItemNotificationsCheck",
        L.ITEM_NOTIFICATIONS, "showItemNotifications", left, -942)
    UI.CreateCheckButton(content, "LiteToolsFastLootCheck",
        L.FAST_LOOT, "fastLoot", left, -976)
    UI.CreateSlider(content, "LiteToolsItemNotificationOpacitySlider",
        L.ITEM_NOTIFICATION_OPACITY, "itemNotificationOpacity", left, -1018,
        30, 100, L.PERCENT)
    UI.CreateSlider(content, "LiteToolsItemNotificationScaleSlider",
        L.ITEM_NOTIFICATION_SCALE, "itemNotificationScale", left, -1080,
        50, 200, L.PERCENT)
    UI.CreateSlider(content, "LiteToolsItemNotificationDurationSlider",
        L.ITEM_NOTIFICATION_DURATION, "itemNotificationDuration", left, -1142,
        2, 15, L.SECONDS)
    UI.CreateSlider(content, "LiteToolsItemNotificationNameSizeSlider",
        L.ITEM_NOTIFICATION_NAME_SIZE, "itemNotificationNameFontSize",
        left, -1204, 8, 28, L.PIXELS)
    UI.CreateSlider(content, "LiteToolsItemNotificationCountSizeSlider",
        L.ITEM_NOTIFICATION_COUNT_SIZE, "itemNotificationCountFontSize",
        left, -1266, 8, 28, L.PIXELS)
    UI.CreateDropdown(content, "LiteToolsItemNotificationDirectionDropdown",
        L.ITEM_NOTIFICATION_DIRECTION, "itemNotificationDirection", {
            { text = L.ITEM_NOTIFICATION_DIRECTION_UP, value = "up" },
            { text = L.ITEM_NOTIFICATION_DIRECTION_DOWN, value = "down" },
        }, left, -1328, 160)
end

local function PopulateSettingsPages(pageContent)
    local left = 24
    local right = 344
    local content = pageContent.General

    UI.CreateCheckButton(content, "LiteToolsAutoDeleteCheck", L.AUTO_DELETE,
        "autoTypeDelete", left, -24)
    UI.CreateCheckButton(content, "LiteToolsSkipCinematicsCheck", L.SKIP_CINEMATICS,
        "skipCinematics", left, -66)
    UI.CreateCheckButton(content, "LiteToolsFixedMicroMenuCheck", L.FIXED_MICRO_MENU,
        "fixedMicroMenu", left, -108)
    UI.CreateCheckButton(content, "LiteToolsInstanceProgressCheck", L.INSTANCE_PROGRESS,
        "showInstanceProgress", left, -150)

    content = pageContent.StatusBars
    UI.CreateCheckButton(content, "LiteToolsHideExperienceBarCheck",
        L.HIDE_EXPERIENCE_BAR, "hideExperienceBar", left, -40)
    UI.CreateSlider(content, "LiteToolsExperienceWidthSlider", L.EXPERIENCE_BAR_WIDTH,
        "experienceBarWidth", right, -24, 200, 1200, L.PIXELS)
    UI.CreateCheckButton(content, "LiteToolsHideReputationBarCheck",
        L.HIDE_REPUTATION_BAR, "hideReputationBar", left, -108)
    UI.CreateSlider(content, "LiteToolsReputationWidthSlider", L.REPUTATION_BAR_WIDTH,
        "reputationBarWidth", right, -92, 200, 1200, L.PIXELS)
    UI.CreateCheckButton(content, "LiteToolsHideHonorBarCheck", L.HIDE_HONOR_BAR,
        "hideHonorBar", left, -176)
    UI.CreateSlider(content, "LiteToolsHonorWidthSlider", L.HONOR_BAR_WIDTH,
        "honorBarWidth", right, -160, 200, 1200, L.PIXELS)

    content = pageContent.Minimap
    UI.CreateCheckButton(content, "LiteToolsMinimapBorderCheck",
        L.REPLACE_MINIMAP_BORDER, "replaceMinimapBorder", left, -24)
    UI.CreateMinimapBorderColorButton(content, right, -24)
    UI.CreateCheckButton(content, "LiteToolsMinimapMoveCheck", L.MOVE_MINIMAP,
        "moveableMinimap", left, -66)
    UI.CreateCheckButton(content, "LiteToolsMinimapLockCheck", L.LOCK_MINIMAP,
        "minimapPositionLocked", right, -66)
    UI.CreateCheckButton(content, "LiteToolsMinimapHideBorderCheck",
        L.HIDE_MINIMAP_BORDER, "hideMinimapBorder", left, -108)
    UI.CreateSlider(content, "LiteToolsMinimapHeaderScaleSlider",
        L.MINIMAP_HEADER_SCALE, "minimapHeaderScale", left, -150,
        50, 200, L.PERCENT)

    content = pageContent.WorldMap
    UI.CreateCheckButton(content, "LiteToolsWorldMapResizeCheck",
        L.WORLD_MAP_RESIZE, "enableWorldMapResize", left, -24)
    UI.CreateCheckButton(content, "LiteToolsCollapseQuestCategoriesCheck",
        L.COLLAPSE_QUEST_CATEGORIES, "showCollapseQuestCategoriesButton",
        left, -66)
    UI.CreateCheckButton(content, "LiteToolsWorldMapDirectionLineCheck",
        L.WORLD_MAP_DIRECTION_LINE, "enableWorldMapDirectionLine", left, -108)

    content = pageContent.MerchantBags
    UI.CreateCheckButton(content, "LiteToolsAutoSellJunkCheck", L.AUTO_SELL_JUNK,
        "autoSellJunk", left, -24)
    UI.CreateCheckButton(content, "LiteToolsAutoRepairCheck", L.AUTO_REPAIR,
        "autoRepair", left, -66)
    UI.CreateCheckButton(content, "LiteToolsHideChildBagsCheck", L.HIDE_CHILD_BAGS,
        "hideChildBags", left, -108)
    UI.CreateCheckButton(content, "LiteToolsHideAllBagButtonsCheck", L.HIDE_ALL_BAGS,
        "hideAllBagButtons", left, -150)

    CreateAutoRollSettings(pageContent.AlertsLoot, left)
    CreateCombatAlertSettings(pageContent.AlertsLoot, left)
    CreateItemNotificationSettings(pageContent.AlertsLoot, left)

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
            Addon:GetSetting("settingsWindowScale") or 1,
            availableWidth / WINDOW_WIDTH,
            availableHeight / WINDOW_HEIGHT
        )
        scale = Addon:Clamp(scale, MIN_WINDOW_SCALE, MAX_WINDOW_SCALE)
        if math.abs(frame:GetScale() - scale) > 0.001 then
            frame:SetScale(scale)
        end
    end

    frame.ApplyWindowScale = ApplyWindowScale
    ApplyWindowScale()

    local borderFrame = CreateFrame(
        "Frame",
        nil,
        frame,
        "NineSlicePanelTemplate"
    )
    borderFrame:SetAllPoints()
    borderFrame:SetFrameLevel(frame:GetFrameLevel() + 100)
    if NineSliceUtil and NineSliceLayouts
        and NineSliceLayouts.PortraitFrameTemplateMinimizable
    then
        NineSliceUtil.ApplyLayout(
            borderFrame,
            NineSliceLayouts.PortraitFrameTemplateMinimizable
        )
    end
    local portraitIconFrame = CreateFrame("Frame", nil, frame)
    portraitIconFrame:SetPoint("TOPLEFT", -4, 9)
    portraitIconFrame:SetSize(62, 62)
    portraitIconFrame:SetFrameLevel(borderFrame:GetFrameLevel() - 1)
    local portraitBackground = portraitIconFrame:CreateTexture(nil, "BACKGROUND")
    portraitBackground:SetPoint("CENTER")
    portraitBackground:SetSize(54, 54)
    portraitBackground:SetColorTexture(0.02, 0.015, 0.01, 1)
    local portraitIcon = portraitIconFrame:CreateTexture(nil, "ARTWORK")
    SetHousingAtlas(
        portraitIcon,
        "GM-icon-settings-pressed",
        { 0.82, 0.62, 0.18, 1 }
    )
    portraitIcon:SetPoint("CENTER", -2, -3)
    portraitIcon:SetSize(116, 116)
    local portraitMask = portraitIconFrame:CreateMaskTexture()
    portraitMask:SetTexture(
        "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    )
    portraitMask:SetAllPoints()
    portraitIcon:AddMaskTexture(portraitMask)
    local portraitBackgroundMask = portraitIconFrame:CreateMaskTexture()
    portraitBackgroundMask:SetTexture(
        "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    )
    portraitBackgroundMask:SetAllPoints(portraitBackground)
    portraitBackground:AddMaskTexture(portraitBackgroundMask)

    local navigation = CreateFrame("Frame", nil, frame)
    navigation:SetPoint("TOPLEFT", 0, -NAVIGATION_TOP_INSET)
    navigation:SetPoint("BOTTOMLEFT")
    navigation:SetWidth(276)
    local navigationBackground = CreateHousingTexture(navigation, "BACKGROUND",
        "store-card-transmog", { 0.045, 0.04, 0.035, 0.98 })
    navigationBackground:SetPoint(
        "TOPLEFT",
        -2,
        PANEL_BACKGROUND_TOP_OVERLAP
    )
    navigationBackground:SetPoint("BOTTOMRIGHT", PANEL_SEAM_OVERLAP, -3)
    local navigationShade = navigation:CreateTexture(nil, "BACKGROUND", nil, 1)
    navigationShade:SetColorTexture(0.015, 0.02, 0.035, 0.42)
    navigationShade:SetPoint(
        "TOPLEFT",
        0,
        PANEL_BACKGROUND_TOP_OVERLAP
    )
    navigationShade:SetPoint("BOTTOMRIGHT")

    local brandTitle = navigation:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalHuge2"
    )
    brandTitle:SetPoint("TOP", navigation, "TOP", 0, -18)
    brandTitle:SetText("LiteTools")
    brandTitle:SetTextColor(1, 0.82, 0.18)

    local navigationScroll = CreateFrame(
        "ScrollFrame",
        "LiteToolsSettingsNavigationScrollFrame",
        navigation,
        "UIPanelScrollFrameTemplate"
    )
    navigationScroll:SetPoint(
        "TOPLEFT",
        0,
        -NAVIGATION_LIST_TOP_INSET
    )

    local navigationContent = CreateFrame("Frame", nil, navigationScroll)
    navigationContent:SetPoint("TOPLEFT")
    navigationScroll:SetScrollChild(navigationContent)

    local contentPanel = CreateFrame("Frame", nil, frame)
    contentPanel:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 1, 0)
    contentPanel:SetPoint("BOTTOMRIGHT")
    local contentBackground = CreateHousingTexture(contentPanel, "BACKGROUND",
        "store-card-splash1-nobanner", { 0.065, 0.055, 0.045, 0.98 })
    contentBackground:SetPoint(
        "TOPLEFT",
        -PANEL_SEAM_OVERLAP,
        PANEL_BACKGROUND_TOP_OVERLAP
    )
    contentBackground:SetPoint("BOTTOMRIGHT", 2, -2)
    local contentShade = contentPanel:CreateTexture(nil, "BACKGROUND", nil, 1)
    contentShade:SetColorTexture(0.015, 0.012, 0.01, 0.52)
    contentShade:SetPoint(
        "TOPLEFT",
        0,
        PANEL_BACKGROUND_TOP_OVERLAP
    )
    contentShade:SetPoint("BOTTOMRIGHT")
    local closeButton = CreateFrame("Button", nil, frame)
    closeButton:SetPoint("TOPRIGHT", 1, 6)
    closeButton:SetSize(28, 28)
    closeButton:SetFrameLevel(borderFrame:GetFrameLevel() + 1)
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

    local resizeButton = CreateFrame(
        "Button",
        nil,
        frame,
        "PanelResizeButtonTemplate"
    )
    resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeButton:SetSize(20, 20)
    resizeButton:SetFrameLevel(borderFrame:GetFrameLevel() + 1)
    resizeButton:SetHitRectInsets(-8, -8, -8, -8)
    resizeButton:RegisterForDrag("LeftButton")
    frame.ResizeButton = resizeButton

    local resizeTracker = CreateFrame("Frame")
    resizeTracker:Hide()
    local resizingWindow = false
    local resizeTopLeftX
    local resizeTopLeftY

    local function AnchorToResizeOrigin(scale)
        frame:ClearAllPoints()
        frame:SetPoint(
            "TOPLEFT",
            UIParent,
            "BOTTOMLEFT",
            resizeTopLeftX / scale,
            resizeTopLeftY / scale
        )
    end

    local function StopWindowResize(saveScale)
        if not resizingWindow then
            return
        end
        resizingWindow = false
        resizeTracker:Hide()
        if saveScale then
            Addon:SetSetting("settingsWindowScale", frame:GetScale())
        end
    end

    local function UpdateWindowResize()
        if not resizingWindow then
            return
        end

        local uiScale = UIParent:GetEffectiveScale()
        local uiWidth, uiHeight = UIParent:GetSize()
        if not uiScale or uiScale <= 0 or not uiWidth or not uiHeight then
            StopWindowResize(true)
            return
        end

        local cursorX, cursorY = GetCursorPosition()
        cursorX = cursorX / uiScale
        cursorY = cursorY / uiScale
        local widthFromOrigin = math.max(0, cursorX - resizeTopLeftX)
        local heightFromOrigin = math.max(0, resizeTopLeftY - cursorY)
        local scale = (
            widthFromOrigin * WINDOW_WIDTH
            + heightFromOrigin * WINDOW_HEIGHT
        ) / (
            WINDOW_WIDTH * WINDOW_WIDTH
            + WINDOW_HEIGHT * WINDOW_HEIGHT
        )
        local screenMaximum = math.min(
            MAX_WINDOW_SCALE,
            (uiWidth - resizeTopLeftX - 8) / WINDOW_WIDTH,
            (resizeTopLeftY - 8) / WINDOW_HEIGHT
        )
        screenMaximum = math.max(MIN_WINDOW_SCALE, screenMaximum)
        scale = Addon:Clamp(scale, MIN_WINDOW_SCALE, screenMaximum)
        frame:SetScale(scale)
        AnchorToResizeOrigin(scale)
    end

    resizeTracker:SetScript("OnUpdate", UpdateWindowResize)
    local function StartWindowResize()
        if resizingWindow then
            return
        end
        local uiScale = UIParent:GetEffectiveScale()
        local frameScale = frame:GetEffectiveScale()
        local left, top = frame:GetLeft(), frame:GetTop()
        if not uiScale or uiScale <= 0 or not frameScale
            or not left or not top
        then
            return
        end
        resizeTopLeftX = left * frameScale / uiScale
        resizeTopLeftY = top * frameScale / uiScale
        resizingWindow = true
        AnchorToResizeOrigin(frame:GetScale())
        resizeTracker:Show()
    end

    resizeButton:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            StartWindowResize()
        end
    end)
    resizeButton:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            StopWindowResize(true)
        end
    end)
    resizeButton:SetScript("OnDragStart", StartWindowResize)
    resizeButton:SetScript("OnDragStop", function()
        StopWindowResize(true)
    end)

    local moduleDefinitions = {
        { key = "General", text = L.SECTION_GENERAL, height = 420 },
        { key = "StatusBars", text = L.SECTION_STATUS_BARS, height = 450 },
        { key = "Minimap", text = L.SECTION_MINIMAP, height = 420 },
        { key = "WorldMap", text = L.SECTION_WORLD_MAP, height = 320 },
        { key = "MerchantBags", text = L.SECTION_MERCHANT_BAGS, height = 360 },
        { key = "AlertsLoot", text = L.SECTION_ALERTS_LOOT, height = 1496 },
        { key = "ActionBars", text = L.SECTION_ACTION_BARS, height = 320 },
    }

    local moduleCount = #moduleDefinitions
    local hasNavigationOverflow = moduleCount > NAVIGATION_VISIBLE_ROWS
    local scrollBar = navigationScroll.ScrollBar
        or _G[navigationScroll:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetShown(hasNavigationOverflow)
    end
    navigationScroll:SetPoint(
        "BOTTOMRIGHT",
        hasNavigationOverflow and -24 or 0,
        0
    )

    local navigationViewportHeight = WINDOW_HEIGHT
        - NAVIGATION_TOP_INSET
        - NAVIGATION_LIST_TOP_INSET
    local rowPitch = (
        navigationViewportHeight - NAVIGATION_LIST_PADDING * 2
    ) / NAVIGATION_VISIBLE_ROWS
    local navigationContentHeight = NAVIGATION_LIST_PADDING * 2
        + rowPitch * math.max(moduleCount, NAVIGATION_VISIBLE_ROWS)
    local navigationContentWidth = 276
        - (hasNavigationOverflow and 24 or 0)
    navigationContent:SetSize(
        navigationContentWidth,
        navigationContentHeight
    )

    local pageContent = {}
    for index, definition in ipairs(moduleDefinitions) do
        local top = -NAVIGATION_LIST_PADDING
            - (index - 1) * rowPitch
            - (rowPitch - NAVIGATION_BUTTON_HEIGHT) / 2
        CreateNavigationButton(
            navigationContent,
            definition.key,
            definition.text,
            top
        )
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
        StopWindowResize(true)
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
