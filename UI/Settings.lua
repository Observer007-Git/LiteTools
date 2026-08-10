local _, Addon = ...

local L = Addon.L
local controls = {}
local panelCreated = false

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
    content:SetSize(620, 930)
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

    CreateSectionTitle(content, L.SECTION_ACTION_BARS, -784)
    CreateCheckButton(content, "LiteToolsActionBarHotkeyAliasesCheck", L.ACTION_BAR_ALIASES, "customActionBarHotkeyAliases", 20, -806)

    panel:SetScript("OnShow", RefreshControls)
    local category = Settings.RegisterCanvasLayoutCategory(panel, L.ADDON_TITLE)
    Settings.RegisterAddOnCategory(category)
    Addon.settingsCategoryID = category:GetID()
    RefreshControls()
end

Addon:RegisterEvent("PLAYER_LOGIN", CreateSettingsPanel)
