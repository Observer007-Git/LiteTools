local _, Addon = ...

local L = Addon.L
local controls = {}

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
        self:Refresh()
    end)
    button.Refresh = function(self)
        self:SetChecked(Addon:GetSetting(settingKey))
    end
    controls[#controls + 1] = button
    return button
end

local function CreateSlider(
    parent,
    name,
    label,
    settingKey,
    x,
    y,
    minimum,
    maximum,
    suffix,
    step,
    decimals
)
    step = step or 1
    decimals = decimals or 0
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x + 34, y - 20)
    slider:SetWidth(190)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
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
        Addon:SetSetting(settingKey, Addon:GetSetting(settingKey) - step)
        slider:Refresh()
    end)

    local plus = CreateFrame("Button", name .. "IncreaseButton", parent, "UIPanelButtonTemplate")
    plus:SetPoint("TOPLEFT", x + 234, y - 26)
    plus:SetSize(24, 24)
    SetButtonText(plus, "+")
    plus:SetScript("OnClick", function()
        Addon:SetSetting(settingKey, Addon:GetSetting(settingKey) + step)
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

    local function UpdateLabel(self, value)
        value = minimum + math.floor((value - minimum) / step + 0.5) * step
        local format = decimals > 0 and L.SLIDER_VALUE_DECIMAL or L.SLIDER_VALUE
        SetControlLabel(self, string.format(format, label, value, suffix))
        return value
    end

    slider:SetScript("OnValueChanged", function(self, value)
        value = UpdateLabel(self, value)
        if not self.refreshing then
            Addon:SetSetting(settingKey, value)
        end
    end)
    slider.Refresh = function(self)
        local value = Addon:GetSetting(settingKey)
        self.refreshing = true
        self:SetValue(value)
        self.refreshing = false
        UpdateLabel(self, value)
    end
    controls[#controls + 1] = slider
    return slider
end

local function CreateEditBox(parent, name, label, settingKey, x, y, width, maxLetters)
    local labelRegion = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelRegion:SetPoint("TOPLEFT", x, y)
    labelRegion:SetText(label)

    local editBox = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", x, y - 20)
    editBox:SetSize(width, 24)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(maxLetters or 255)

    local function Save(self)
        Addon:SetSetting(settingKey, self:GetText())
        self:Refresh()
        if self.settingChangedCallback then self.settingChangedCallback() end
    end

    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:Refresh()
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", Save)
    editBox.Refresh = function(self)
        self:SetText(tostring(Addon:GetSetting(settingKey) or ""))
    end
    controls[#controls + 1] = editBox
    return editBox
end

local function CreateDropdown(parent, name, label, settingKey, options, x, y, width)
    local labelRegion = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelRegion:SetPoint("TOPLEFT", x, y)
    labelRegion:SetText(label)

    local dropdown = CreateFrame("DropdownButton", name, parent,
        "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", x, y - 22)
    dropdown:SetSize(width or 250, 28)
    dropdown:SetupMenu(function(_, rootDescription)
        for _, option in ipairs(options) do
            rootDescription:CreateRadio(option.text,
                function(value)
                    return Addon:GetSetting(settingKey) == value
                end,
                function(value)
                    Addon:SetSetting(settingKey, value)
                end,
                option.value)
        end
    end)
    dropdown.Refresh = function(self)
        if self.GenerateMenu then
            self:GenerateMenu()
        end
    end
    controls[#controls + 1] = dropdown
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

Addon.SettingsUI = {
    SetButtonText = SetButtonText,
    CreateSectionTitle = CreateSectionTitle,
    CreateCheckButton = CreateCheckButton,
    CreateSlider = CreateSlider,
    CreateEditBox = CreateEditBox,
    CreateDropdown = CreateDropdown,
    CreateMinimapBorderColorButton = CreateMinimapBorderColorButton,
    RefreshControls = RefreshControls,
}
