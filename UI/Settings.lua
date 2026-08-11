local _, Addon = ...

local L = Addon.L
local controls = {}
local panelCreated = false
local COMBAT_ALERT_SOUND_PRESETS = {
    6325085,
    4822118,
    5744408,
    4719485,
    5917424,
    642839,
    5923734,
}

local function SetControlLabel(control, text)
    local label = control.Text or (control.GetName and _G[control:GetName() .. "Text"])
    if label then
        label:SetText(text)
    end
    return label
end

local function SetButtonText(button, text)
    if button.SetText then
        button:SetText(text)
    elseif button.Text then
        button.Text:SetText(text)
    end
end

local function CreateSectionTitle(parent, text, y)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 20, y)
    title:SetText(text)
end

local function CreateCheckButton(parent, name, label, settingKey, x, y)
    local button = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(26, 26)
    local labelRegion = SetControlLabel(button, label)
    if labelRegion then
        button:SetHitRectInsets(0, -labelRegion:GetStringWidth() - 8, 0, 0)
    end
    button:SetScript("OnClick", function(self)
        Addon:SetSetting(settingKey, self:GetChecked())
    end)
    button.Refresh = function(self)
        self:SetChecked(Addon:GetSetting(settingKey))
    end
    controls[#controls + 1] = button
    return button
end

local function CreateSlider(parent, name, label, settingKey, x, y, minimum, maximum, suffix)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x + 34, y - 20)
    slider:SetWidth(190)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local low = slider.Low or _G[name .. "Low"]
    local high = slider.High or _G[name .. "High"]
    if low then low:SetText("") end
    if high then high:SetText("") end

    local minus = CreateFrame("Button", name .. "DecreaseButton", parent, "UIPanelButtonTemplate")
    minus:SetPoint("TOPLEFT", x, y - 26)
    minus:SetSize(24, 24)
    SetButtonText(minus, "−")
    minus:SetScript("OnClick", function()
        Addon:SetSetting(settingKey, Addon:GetSetting(settingKey) - 1)
        slider:Refresh()
    end)

    local plus = CreateFrame("Button", name .. "IncreaseButton", parent, "UIPanelButtonTemplate")
    plus:SetPoint("TOPLEFT", x + 234, y - 26)
    plus:SetSize(24, 24)
    SetButtonText(plus, "+")
    plus:SetScript("OnClick", function()
        Addon:SetSetting(settingKey, Addon:GetSetting(settingKey) + 1)
        slider:Refresh()
    end)

    minus:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.DECREASE)
        GameTooltip:Show()
    end)
    minus:SetScript("OnLeave", function() GameTooltip:Hide() end)
    plus:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.INCREASE)
        GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", function() GameTooltip:Hide() end)

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SetControlLabel(self, string.format(L.SLIDER_VALUE, label, value, suffix))
        if not self.refreshing then
            Addon:SetSetting(settingKey, value)
        end
    end)
    slider.Refresh = function(self)
        self.refreshing = true
        self:SetValue(Addon:GetSetting(settingKey))
        self.refreshing = false
    end
    controls[#controls + 1] = slider
    return slider
end

local function CreateEditBox(parent, name, label, settingKey, x, y, width)
    local labelRegion = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelRegion:SetPoint("TOPLEFT", x, y)
    labelRegion:SetText(label)

    local editBox = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", x, y - 20)
    editBox:SetSize(width, 24)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(255)

    local function Save(self)
        Addon:SetSetting(settingKey, self:GetText())
        if self.settingChangedCallback then self.settingChangedCallback() end
    end

    editBox:SetScript("OnEnterPressed", function(self)
        Save(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:Refresh()
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", Save)
    editBox.Refresh = function(self)
        self:SetText(Addon:GetSetting(settingKey) or "")
    end
    controls[#controls + 1] = editBox
    return editBox
end

local function CreateAlertSoundSelector(
    parent,
    controlPrefix,
    soundSettingKey,
    x,
    y,
    soundEditBox
)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(L.COMBAT_ALERT_SOUND_PRESET)

    local dropdown = CreateFrame(
        "Frame",
        "LiteTools" .. controlPrefix .. "SoundDropdown",
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint("TOPLEFT", x - 16, y - 16)
    UIDropDownMenu_SetWidth(dropdown, 150)

    dropdown.Refresh = function(self)
        local currentValue = tostring(Addon:GetSetting(soundSettingKey) or "")
        local selectedText
        for index, soundFileID in ipairs(COMBAT_ALERT_SOUND_PRESETS) do
            if currentValue == tostring(soundFileID) then
                selectedText = string.format(
                    L.COMBAT_ALERT_SOUND_OPTION,
                    index,
                    soundFileID
                )
                break
            end
        end
        UIDropDownMenu_SetText(
            self,
            selectedText or (currentValue ~= "" and L.COMBAT_ALERT_SOUND_CUSTOM
                or L.COMBAT_ALERT_SOUND_NONE)
        )
    end

    local function CreatePresetCallback(value)
        return function()
            Addon:SetSetting(soundSettingKey, value)
            soundEditBox:Refresh()
            dropdown:Refresh()
        end
    end

    UIDropDownMenu_Initialize(dropdown, function()
        local currentValue = tostring(Addon:GetSetting(soundSettingKey) or "")
        for index, soundFileID in ipairs(COMBAT_ALERT_SOUND_PRESETS) do
            local value = tostring(soundFileID)
            local optionText = string.format(
                L.COMBAT_ALERT_SOUND_OPTION,
                index,
                soundFileID
            )
            local info = UIDropDownMenu_CreateInfo()
            info.text = optionText
            info.value = value
            info.checked = currentValue == value
            info.func = CreatePresetCallback(value)
            UIDropDownMenu_AddButton(info)
        end
    end)
    controls[#controls + 1] = dropdown

    soundEditBox.settingChangedCallback = function() dropdown:Refresh() end

    local preview = CreateFrame(
        "Button",
        "LiteTools" .. controlPrefix .. "SoundPreviewButton",
        parent,
        "UIPanelButtonTemplate"
    )
    preview:SetPoint("TOPLEFT", x + 190, y - 20)
    preview:SetSize(60, 24)
    SetButtonText(preview, L.COMBAT_ALERT_SOUND_PREVIEW)
    preview:SetScript("OnClick", function()
        Addon:PreviewCombatAlertSound(Addon:GetSetting(soundSettingKey))
    end)

    return dropdown
end

local function CreateMinimapBorderColorButton(parent, x, y)
    local button = CreateFrame(
        "Button",
        "LiteToolsMinimapBorderColorButton",
        parent,
        "ColorSwatchTemplate"
    )
    button:SetPoint("TOPLEFT", x, y)

    local label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", button, "RIGHT", 8, 0)
    label:SetText(L.MINIMAP_BORDER_COLOR)
    button:SetHitRectInsets(0, -label:GetStringWidth() - 8, 0, 0)

    button:SetScript("OnClick", function(self)
        local red, green, blue, alpha, wasCustomized = Addon:GetMinimapBorderColor()
        local currentAlpha = alpha
        local colorCustomized = wasCustomized
        local pickerReady = false

        local function ApplyColor()
            local newRed, newGreen, newBlue = ColorPickerFrame:GetColorRGB()
            if pickerReady then
                currentAlpha = ColorPickerFrame:GetColorAlpha()
                colorCustomized = true
            end
            Addon:SetMinimapBorderColor(
                newRed,
                newGreen,
                newBlue,
                currentAlpha,
                colorCustomized
            )
            self:SetColorRGB(newRed, newGreen, newBlue)
        end

        local function ApplyOpacity()
            local newAlpha = ColorPickerFrame:GetColorAlpha()
            if newAlpha == currentAlpha then
                return
            end
            currentAlpha = newAlpha
            local newRed, newGreen, newBlue = ColorPickerFrame:GetColorRGB()
            Addon:SetMinimapBorderColor(
                newRed,
                newGreen,
                newBlue,
                currentAlpha,
                colorCustomized
            )
        end

        ColorPickerFrame:SetupColorPickerAndShow({
            r = red,
            g = green,
            b = blue,
            opacity = alpha,
            hasOpacity = true,
            swatchFunc = ApplyColor,
            opacityFunc = ApplyOpacity,
            cancelFunc = function()
                local oldRed, oldGreen, oldBlue, oldAlpha = ColorPickerFrame:GetPreviousValues()
                Addon:SetMinimapBorderColor(
                    oldRed,
                    oldGreen,
                    oldBlue,
                    oldAlpha,
                    wasCustomized
                )
                self:SetColorRGB(oldRed, oldGreen, oldBlue)
            end,
        })
        pickerReady = true
    end)

    button.Refresh = function(self)
        self:SetColorRGB(Addon:GetMinimapBorderColor())
    end
    controls[#controls + 1] = button
    return button
end

local function RefreshControls()
    for _, control in ipairs(controls) do
        control:Refresh()
    end
end

local function CreateSettingsPanel()
    if panelCreated then
        return
    end
    panelCreated = true

    local panel = CreateFrame("Frame")
    panel.name = L.ADDON_TITLE

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        "LiteToolsSettingsScrollFrame",
        panel,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 0)

    local content = CreateFrame("Frame", "LiteToolsSettingsContent", scrollFrame)
    content:SetSize(620, 1420)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(1, width))
    end)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.ADDON_TITLE)

    local description = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText(L.ADDON_DESCRIPTION)

    CreateSectionTitle(content, L.SECTION_GENERAL, -70)
    CreateCheckButton(content, "LiteToolsAutoDeleteCheck", L.AUTO_DELETE, "autoTypeDelete", 20, -92)
    CreateCheckButton(content, "LiteToolsSkipCinematicsCheck", L.SKIP_CINEMATICS, "skipCinematics", 315, -92)
    CreateCheckButton(content, "LiteToolsFixedMicroMenuCheck", L.FIXED_MICRO_MENU, "fixedMicroMenu", 20, -124)
    CreateCheckButton(content, "LiteToolsInstanceProgressCheck", L.INSTANCE_PROGRESS, "showInstanceProgress", 315, -124)

    CreateSectionTitle(content, L.SECTION_STATUS_BARS, -170)
    CreateSlider(content, "LiteToolsExperienceWidthSlider", L.EXPERIENCE_BAR_WIDTH, "experienceBarWidth", 20, -196, 200, 1200, L.PIXELS)
    CreateSlider(content, "LiteToolsReputationWidthSlider", L.REPUTATION_BAR_WIDTH, "reputationBarWidth", 315, -196, 200, 1200, L.PIXELS)
    CreateCheckButton(content, "LiteToolsHideExperienceBarCheck", L.HIDE_EXPERIENCE_BAR, "hideExperienceBar", 20, -246)
    CreateCheckButton(content, "LiteToolsHideReputationBarCheck", L.HIDE_REPUTATION_BAR, "hideReputationBar", 315, -246)
    CreateSlider(content, "LiteToolsHonorWidthSlider", L.HONOR_BAR_WIDTH, "honorBarWidth", 20, -286, 200, 1200, L.PIXELS)
    CreateCheckButton(content, "LiteToolsHideHonorBarCheck", L.HIDE_HONOR_BAR, "hideHonorBar", 20, -336)

    CreateSectionTitle(content, L.SECTION_MINIMAP, -382)
    CreateCheckButton(content, "LiteToolsMinimapBorderCheck", L.REPLACE_MINIMAP_BORDER, "replaceMinimapBorder", 20, -404)
    CreateCheckButton(content, "LiteToolsMinimapMoveCheck", L.MOVE_MINIMAP, "moveableMinimap", 315, -404)
    CreateMinimapBorderColorButton(content, 20, -442)
    CreateCheckButton(content, "LiteToolsMinimapLockCheck", L.LOCK_MINIMAP, "minimapPositionLocked", 315, -436)
    CreateSlider(content, "LiteToolsMinimapHeaderScaleSlider", L.MINIMAP_HEADER_SCALE, "minimapHeaderScale", 20, -486, 50, 200, L.PERCENT)

    CreateSectionTitle(content, L.SECTION_MERCHANT_BAGS, -552)
    CreateCheckButton(content, "LiteToolsAutoSellJunkCheck", L.AUTO_SELL_JUNK, "autoSellJunk", 20, -574)
    CreateCheckButton(content, "LiteToolsAutoRepairCheck", L.AUTO_REPAIR, "autoRepair", 315, -574)
    CreateCheckButton(content, "LiteToolsHideChildBagsCheck", L.HIDE_CHILD_BAGS, "hideChildBags", 20, -606)
    CreateCheckButton(content, "LiteToolsHideAllBagButtonsCheck", L.HIDE_ALL_BAGS, "hideAllBagButtons", 315, -606)

    CreateSectionTitle(content, L.SECTION_ALERTS_LOOT, -652)
    CreateCheckButton(content, "LiteToolsLootAlertAnchorCheck", L.LOOT_ALERT_ANCHOR, "showLootAlertAnchor", 20, -674)
    CreateCheckButton(content, "LiteToolsGroupLootAnchorCheck", L.GROUP_LOOT_ANCHOR, "showGroupLootAnchor", 315, -674)
    CreateCheckButton(content, "LiteToolsAutoRollGearCheck", L.AUTO_ROLL_GEAR, "autoRollGear", 20, -706)
    CreateCheckButton(content, "LiteToolsAutoRollPanelAnchorCheck", L.AUTO_ROLL_PANEL_ANCHOR, "showAutoRollPanelAnchor", 315, -706)
    CreateCheckButton(content, "LiteToolsAchievementAlertAnchorCheck", L.ACHIEVEMENT_ALERT_ANCHOR, "showAchievementAlertAnchor", 20, -738)
    CreateCheckButton(content, "LiteToolsCombatAlertCheck", L.COMBAT_ALERT, "showCombatAlert", 20, -770)
    CreateSlider(content, "LiteToolsCombatAlertDurationSlider", L.COMBAT_ALERT_DURATION, "combatAlertDuration", 315, -750, 1, 3, L.SECONDS)
    CreateSlider(content, "LiteToolsCombatAlertScaleSlider", L.COMBAT_ALERT_SCALE, "combatAlertScale", 315, -806, 50, 200, L.PERCENT)
    CreateCheckButton(content, "LiteToolsCombatAlertMuteCheck", L.COMBAT_ALERT_MUTE, "combatAlertMuted", 315, -868)
    local combatAlertSoundEditBox = CreateEditBox(content, "LiteToolsCombatAlertSoundEditBox", L.COMBAT_ALERT_SOUND, "combatAlertSound", 315, -902, 250)
    CreateAlertSoundSelector(content, "CombatAlert", "combatAlertSound", 315, -964, combatAlertSoundEditBox)

    CreateCheckButton(content, "LiteToolsLeaveCombatAlertCheck", L.LEAVE_COMBAT_ALERT, "showLeaveCombatAlert", 20, -1030)
    CreateSlider(content, "LiteToolsLeaveCombatAlertDurationSlider", L.COMBAT_ALERT_DURATION, "leaveCombatAlertDuration", 315, -1010, 1, 3, L.SECONDS)
    CreateSlider(content, "LiteToolsLeaveCombatAlertScaleSlider", L.COMBAT_ALERT_SCALE, "leaveCombatAlertScale", 315, -1066, 50, 200, L.PERCENT)
    CreateCheckButton(content, "LiteToolsLeaveCombatAlertMuteCheck", L.COMBAT_ALERT_MUTE, "leaveCombatAlertMuted", 315, -1128)
    local leaveCombatAlertSoundEditBox = CreateEditBox(content, "LiteToolsLeaveCombatAlertSoundEditBox", L.COMBAT_ALERT_SOUND, "leaveCombatAlertSound", 315, -1162, 250)
    CreateAlertSoundSelector(content, "LeaveCombatAlert", "leaveCombatAlertSound", 315, -1224, leaveCombatAlertSoundEditBox)

    CreateSectionTitle(content, L.SECTION_ACTION_BARS, -1296)
    CreateCheckButton(content, "LiteToolsActionBarHotkeyAliasesCheck", L.ACTION_BAR_ALIASES, "customActionBarHotkeyAliases", 20, -1318)

    panel:SetScript("OnShow", RefreshControls)
    local category = Settings.RegisterCanvasLayoutCategory(panel, L.ADDON_TITLE)
    Settings.RegisterAddOnCategory(category)
    Addon.settingsCategoryID = category:GetID()
    RefreshControls()
end

Addon:RegisterEvent("PLAYER_LOGIN", CreateSettingsPanel)
