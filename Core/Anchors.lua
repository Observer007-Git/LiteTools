local _, Addon = ...

local Anchors = {}
Addon.Anchors = Anchors

function Anchors:SavePosition(anchor, settingKey)
    local database = Addon:GetDatabase()
    if not database or not anchor or not UIParent then
        return
    end

    local centerX, centerY = anchor:GetCenter()
    local uiWidth, uiHeight = UIParent:GetSize()
    local anchorScale = anchor:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    if not centerX or not centerY or not uiWidth or not uiHeight
        or not anchorScale or not uiScale or uiWidth <= 0 or uiHeight <= 0
        or anchorScale <= 0 or uiScale <= 0 then
        return
    end

    centerX = centerX * anchorScale / uiScale
    centerY = centerY * anchorScale / uiScale

    database[settingKey] = {
        version = 2,
        x = Addon:Clamp(centerX / uiWidth, 0, 1),
        y = Addon:Clamp(centerY / uiHeight, 0, 1),
    }
end

function Anchors:Position(anchor, settingKey, defaultX, defaultY)
    local database = Addon:GetDatabase()
    if not database or not anchor or not UIParent then
        return
    end

    local position = database[settingKey]
    local uiWidth, uiHeight = UIParent:GetSize()
    local anchorScale = anchor:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    if not uiWidth or not uiHeight or not anchorScale or not uiScale
        or uiWidth <= 0 or uiHeight <= 0 or anchorScale <= 0 or uiScale <= 0 then
        return
    end

    local pointScale = uiScale / anchorScale

    anchor:ClearAllPoints()
    anchor:SetPoint(
        "CENTER",
        UIParent,
        "BOTTOMLEFT",
        (position and position.x or defaultX) * uiWidth * pointScale,
        (position and position.y or defaultY) * uiHeight * pointScale
    )
end

function Anchors:Create(options)
    local anchor = CreateFrame("Frame", options.name, UIParent)
    anchor:SetSize(240, 28)
    anchor:SetFrameStrata("DIALOG")
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    if anchor.SetDontSavePosition then
        anchor:SetDontSavePosition(true)
    end
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    local background = anchor:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.06, 0.06, 0.85)

    local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(string.format(Addon.L.ANCHOR_RIGHT_CLICK, options.label))

    anchor:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Anchors:SavePosition(self, options.positionKey)
        options.movedCallback()
    end)
    anchor:SetScript("OnMouseUp", function(self, button)
        local database = Addon:GetDatabase()
        if button == "RightButton" and database then
            database[options.hiddenKey] = true
            self:Hide()
        end
    end)

    self:Position(anchor, options.positionKey, options.defaultX, options.defaultY)
    anchor:Hide()
    return anchor
end
