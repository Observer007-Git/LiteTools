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

    CreateCheckButton(panel, "FansWowToolsAutoDeleteCheck", "自动输入DELETE", "autoTypeDelete", -72)
    CreateCheckButton(panel, "FansWowToolsSkipCinematicsCheck", "跳过动画", "skipCinematics", -108)
    CreateSlider(panel, "FansWowToolsExperienceWidthSlider", "经验条缩放", "experienceBarWidth", -170)
    CreateSlider(panel, "FansWowToolsReputationWidthSlider", "声望条缩放", "reputationBarWidth", -238)
    CreateCheckButton(panel, "FansWowToolsFixedMicroMenuCheck", "菜单栏固定", "fixedMicroMenu", -292)
    CreateCheckButton(
        panel,
        "FansWowToolsInstanceProgressCheck",
        "鼠标放到日历显示副本进度",
        "showInstanceProgress",
        -328
    )
    CreateCheckButton(panel, "FansWowToolsAutoSellJunkCheck", "自动售卖垃圾", "autoSellJunk", -364)

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
