local _, Addon = ...

local PANEL_NAME = "Fan's wow tools"
local controls = {}

local function SetControlLabel(control, text)
    local label = control.Text or _G[control:GetName() .. "Text"]
    if label then
        label:SetText(text)
    end
    return label
end

local function CreateCheckButton(panel, name, label, settingKey, y)
    local button = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", 20, y)
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

local function CreateSlider(panel, name, label, settingKey, y)
    local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 24, y)
    slider:SetWidth(360)
    slider:SetMinMaxValues(200, 1200)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local low = slider.Low or _G[name .. "Low"]
    local high = slider.High or _G[name .. "High"]
    if low then
        low:SetText("200")
    end
    if high then
        high:SetText("1200")
    end

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SetControlLabel(self, string.format("%s：%d 像素", label, value))
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

local function CreateMinimapBorderColorButton(panel, y)
    local button = CreateFrame(
        "Button",
        "FansWowToolsMinimapBorderColorButton",
        panel,
        "ColorSwatchTemplate"
    )
    button:SetPoint("TOPLEFT", 24, y)

    local label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", button, "RIGHT", 8, 0)
    label:SetText("更改小地图边框颜色和透明度")
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
    local panel = CreateFrame("Frame")
    panel.name = PANEL_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PANEL_NAME)

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("所有设置即时生效，并自动永久保存。")

    CreateCheckButton(panel, "FansWowToolsAutoDeleteCheck", "删除物品自动输入 DELETE", "autoTypeDelete", -72)
    CreateCheckButton(panel, "FansWowToolsSkipCinematicsCheck", "空格跳过动画", "skipCinematics", -108)
    CreateSlider(panel, "FansWowToolsExperienceWidthSlider", "经验条缩放", "experienceBarWidth", -170)
    CreateCheckButton(
        panel,
        "FansWowToolsHideExperienceBarCheck",
        "隐藏经验条",
        "hideExperienceBar",
        -210
    )
    CreateSlider(panel, "FansWowToolsReputationWidthSlider", "声望条缩放", "reputationBarWidth", -258)
    CreateCheckButton(
        panel,
        "FansWowToolsHideReputationBarCheck",
        "隐藏声望条",
        "hideReputationBar",
        -298
    )
    CreateCheckButton(panel, "FansWowToolsFixedMicroMenuCheck", "将眼睛固定在左侧", "fixedMicroMenu", -334)
    CreateCheckButton(
        panel,
        "FansWowToolsInstanceProgressCheck",
        "鼠标放到时间上显示副本进度",
        "showInstanceProgress",
        -370
    )
    CreateCheckButton(
        panel,
        "FansWowToolsMinimapBorderCheck",
        "替换小地图边框",
        "replaceMinimapBorder",
        -406
    )
    CreateMinimapBorderColorButton(panel, -442)
    CreateCheckButton(panel, "FansWowToolsAutoSellJunkCheck", "自动售卖垃圾", "autoSellJunk", -478)
    CreateCheckButton(panel, "FansWowToolsHideChildBagsCheck", "隐藏子背包", "hideChildBags", -514)
    CreateCheckButton(
        panel,
        "FansWowToolsActionBarHotkeyAliasesCheck",
        "自定义动作条快捷键显示别名（只支持原生动作条）",
        "customActionBarHotkeyAliases",
        -550
    )

    panel:SetScript("OnShow", RefreshControls)

    local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
    Settings.RegisterAddOnCategory(category)
    Addon.settingsCategoryID = category:GetID()

    RefreshControls()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    CreateSettingsPanel()
end)
