local _, Addon = ...

local DEFAULT_DURATION = 2
local DEFAULT_SCALE = 100
local FADE_DURATION = 0.5
local ALERT_HEIGHT = 96
local FALLBACK_ALERT_WIDTH = 420
local COMBAT_TIMER_HEIGHT = 64
local COMBAT_TIMER_FALLBACK_WIDTH = 360
local COMBAT_TIMER_UPDATE_INTERVAL = 0.25
local COMBAT_TIMER_FONT_SCALE = 1.2

local ALERT_DEFINITIONS = {
    {
        event = "PLAYER_REGEN_DISABLED",
        enabledKey = "showCombatAlert",
        durationKey = "combatAlertDuration",
        scaleKey = "combatAlertScale",
        positionKey = "combatAlertPosition",
        hiddenKey = "combatAlertAnchorHidden",
        frameName = "LiteToolsCombatAlertFrame",
        anchorName = "LiteToolsCombatAlertAnchor",
        anchorLabelKey = "COMBAT_ALERT_ANCHOR_SHORT",
        textKey = "ENTER_COMBAT_TEXT",
        allianceAtlas = "AllianceScenario-TitleBG",
        hordeAtlas = "HordeScenario-TitleBG",
        textColor = { 1, 0.82, 0, 1 },
        defaultX = 0.5,
        defaultY = 0.62,
    },
    {
        event = "PLAYER_REGEN_ENABLED",
        enabledKey = "showLeaveCombatAlert",
        durationKey = "leaveCombatAlertDuration",
        scaleKey = "leaveCombatAlertScale",
        positionKey = "leaveCombatAlertPosition",
        hiddenKey = "leaveCombatAlertAnchorHidden",
        frameName = "LiteToolsLeaveCombatAlertFrame",
        anchorName = "LiteToolsLeaveCombatAlertAnchor",
        anchorLabelKey = "LEAVE_COMBAT_ALERT_ANCHOR_SHORT",
        textKey = "LEAVE_COMBAT_TEXT",
        allianceAtlas = "scoreboard-header-alliance",
        hordeAtlas = "scoreboard-header-horde",
        desaturateBackground = true,
        backgroundColor = { 0.2, 1, 0.2, 1 },
        textColor = { 0.2, 1, 0.2, 1 },
        defaultX = 0.5,
        defaultY = 0.55,
    },
}

local function DB()
    return Addon:GetDatabase()
end

local function CancelFadeTimer(definition)
    if definition.fadeTimer then
        definition.fadeTimer:Cancel()
        definition.fadeTimer = nil
    end
end

local function HideAlert(definition)
    CancelFadeTimer(definition)
    local frame = definition.frame
    if frame then
        frame.fadeOut:Stop()
        frame:SetAlpha(1)
        frame:Hide()
    end
end

local function ScheduleFade(definition, duration)
    CancelFadeTimer(definition)
    local frame = definition.frame
    frame.fadeOut:Stop()
    frame:SetAlpha(1)
    definition.fadeTimer = C_Timer.NewTimer(
        math.max(0, duration - FADE_DURATION),
        function()
            definition.fadeTimer = nil
            if frame:IsShown() then frame.fadeOut:Play() end
        end
    )
end

local function GetBackgroundAtlas(definition)
    return UnitFactionGroup("player") == "Horde"
        and definition.hordeAtlas
        or definition.allianceAtlas
end

local function UpdateBackground(definition)
    local frame = definition.frame
    if not frame then return end

    local atlas = GetBackgroundAtlas(definition)
    local width = FALLBACK_ALERT_WIDTH
    if C_Texture and C_Texture.GetAtlasInfo then
        local atlasInfo = C_Texture.GetAtlasInfo(atlas)
        if atlasInfo and atlasInfo.width and atlasInfo.height and atlasInfo.height > 0 then
            width = Addon:Clamp(ALERT_HEIGHT * atlasInfo.width / atlasInfo.height, 320, 600)
        end
    end

    frame:SetSize(width, ALERT_HEIGHT)
    frame.background:SetAtlas(atlas, false)
end

local function EnsureAlertFrame(definition)
    if definition.frame then return definition.frame end

    local frame = CreateFrame("Frame", definition.frameName, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetDesaturated(not not definition.desaturateBackground)
    local backgroundColor = definition.backgroundColor or { 1, 1, 1, 1 }
    background:SetVertexColor(
        backgroundColor[1],
        backgroundColor[2],
        backgroundColor[3],
        backgroundColor[4]
    )
    frame.background = background

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    local textColor = definition.textColor
    text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
    text:SetText(Addon.L[definition.textKey])
    frame.text = text

    local fadeOut = frame:CreateAnimationGroup()
    local fadeAnimation = fadeOut:CreateAnimation("Alpha")
    fadeAnimation:SetFromAlpha(1)
    fadeAnimation:SetToAlpha(0)
    fadeAnimation:SetDuration(FADE_DURATION)
    fadeAnimation:SetSmoothing("OUT")
    fadeOut:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)
    frame.fadeOut = fadeOut

    definition.frame = frame
    UpdateBackground(definition)
    frame:SetScale((Addon:GetSetting(definition.scaleKey) or DEFAULT_SCALE) / 100)
    frame:Hide()
    return frame
end

local function PositionAlert(definition)
    local frame = definition.frame
    local anchor = definition.anchor
    if not frame or not anchor then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
end

local function PositionAnchor(definition)
    local anchor = definition.anchor
    if not anchor then return end
    Addon.Anchors:Position(
        anchor,
        definition.positionKey,
        definition.defaultX,
        definition.defaultY
    )
    PositionAlert(definition)
end

local function EnsureAnchor(definition)
    if definition.anchor then return definition.anchor end

    definition.anchor = Addon.Anchors:Create({
        name = definition.anchorName,
        label = Addon.L[definition.anchorLabelKey],
        positionKey = definition.positionKey,
        hiddenKey = definition.hiddenKey,
        defaultX = definition.defaultX,
        defaultY = definition.defaultY,
        movedCallback = function() PositionAlert(definition) end,
    })
    EnsureAlertFrame(definition)
    PositionAlert(definition)
    return definition.anchor
end

local function ShowAlert(definition)
    local db = DB()
    if not db or not db[definition.enabledKey] then return end

    local frame = EnsureAlertFrame(definition)
    EnsureAnchor(definition)
    UpdateBackground(definition)
    PositionAlert(definition)
    frame:Show()
    ScheduleFade(definition, db[definition.durationKey])
end

local function ApplySetting(definition, reposition)
    local db = DB()
    if not db then return end

    if db[definition.enabledKey] then
        local anchor = EnsureAnchor(definition)
        if reposition then PositionAnchor(definition) end
        anchor:SetShown(not db[definition.hiddenKey])
    else
        HideAlert(definition)
        if definition.anchor then definition.anchor:Hide() end
    end
end

local function RegisterAlert(definition)
    Addon:RegisterSetting(
        definition.enabledKey,
        false,
        Addon.BooleanSetting,
        function(value)
            local db = DB()
            if value and db then db[definition.hiddenKey] = false end
            ApplySetting(definition, true)
        end
    )
    Addon:RegisterSetting(
        definition.durationKey,
        DEFAULT_DURATION,
        Addon.NumberSetting(1, 3),
        function(value)
            if definition.frame and definition.frame:IsShown() then
                ScheduleFade(definition, value)
            end
        end
    )
    Addon:RegisterSetting(
        definition.scaleKey,
        DEFAULT_SCALE,
        Addon.NumberSetting(50, 200),
        function(value)
            if definition.frame then definition.frame:SetScale(value / 100) end
        end
    )
    Addon:RegisterSetting(definition.positionKey, nil, Addon.PositionSetting)
    Addon:RegisterSetting(definition.hiddenKey, false, Addon.BooleanSetting)

    local function IsEnabled(db)
        return db[definition.enabledKey]
    end

    Addon:RegisterEvent(definition.event, function() ShowAlert(definition) end, IsEnabled)
    Addon:RegisterEvent("PLAYER_LOGIN", function()
        ApplySetting(definition, true)
    end, IsEnabled)
    Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        HideAlert(definition)
        ApplySetting(definition, true)
    end, IsEnabled)
    for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
        Addon:RegisterEvent(event, function()
            ApplySetting(definition, true)
        end, IsEnabled)
    end
end

Addon:RegisterDatabaseMigration(function(db)
    db.combatAlertMuted = nil
    db.combatAlertSound = nil
    db.leaveCombatAlertMuted = nil
    db.leaveCombatAlertSound = nil
end)

for _, definition in ipairs(ALERT_DEFINITIONS) do
    RegisterAlert(definition)
end

local combatTimerFrame
local combatTimerTicker
local instanceStartTime
local lastInstanceDuration = 0
local instanceActive = false
local instanceStateUpdateGeneration = 0
local combatStartTime
local lastCombatDuration = 0
local combatActive = false

local function FormatInstanceTime(elapsed)
    elapsed = math.max(0, math.floor(elapsed or 0))
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor(elapsed / 60) % 60
    local seconds = elapsed % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function FormatCombatTime(elapsed)
    local hundredths = math.max(0, math.floor((elapsed or 0) * 100))
    local minutes = math.floor(hundredths / 6000)
    local seconds = math.floor(hundredths / 100) % 60
    local fraction = hundredths % 100
    return string.format("%02d:%02d.%02d", minutes, seconds, fraction)
end

local function UpdateCombatTimerText()
    if not combatTimerFrame then return end

    local now = GetTime()
    local instanceElapsed = instanceActive and instanceStartTime
        and (now - instanceStartTime)
        or lastInstanceDuration
    local combatElapsed = combatActive and combatStartTime
        and (now - combatStartTime)
        or lastCombatDuration
    local instanceText = FormatInstanceTime(instanceElapsed)
    local combatText = FormatCombatTime(combatElapsed)
    if combatTimerFrame.lastInstanceText ~= instanceText then
        combatTimerFrame.lastInstanceText = instanceText
        combatTimerFrame.instanceText:SetText(instanceText)
    end
    if combatTimerFrame.lastCombatText ~= combatText then
        combatTimerFrame.lastCombatText = combatText
        combatTimerFrame.combatText:SetText(combatText)
    end
end

local function GetCombatTimerAtlas()
    return UnitFactionGroup("player") == "Horde"
        and "HordeScenario-TitleBG"
        or "AllianceScenario-TitleBG"
end

local function UpdateCombatTimerBackground()
    if not combatTimerFrame then return end

    local atlas = GetCombatTimerAtlas()
    local width = COMBAT_TIMER_FALLBACK_WIDTH
    if C_Texture and C_Texture.GetAtlasInfo then
        local atlasInfo = C_Texture.GetAtlasInfo(atlas)
        if atlasInfo and atlasInfo.width and atlasInfo.height and atlasInfo.height > 0 then
            width = Addon:Clamp(
                COMBAT_TIMER_HEIGHT * atlasInfo.width / atlasInfo.height,
                300,
                520
            )
        end
    end
    combatTimerFrame:SetSize(width, COMBAT_TIMER_HEIGHT)
    combatTimerFrame.background:SetAtlas(atlas, false)
end

local function PositionCombatTimer()
    if not combatTimerFrame then return end
    Addon.Anchors:Position(
        combatTimerFrame,
        "combatTimerPosition",
        0.5,
        0.68
    )
end

local function GetInstanceToken()
    local inInstance, instanceType = IsInInstance()
    local inDelve = C_PartyInfo
        and C_PartyInfo.IsDelveInProgress
        and C_PartyInfo.IsDelveInProgress()
    if not inInstance and not inDelve then return nil end

    if inInstance then
        local instanceID = select(8, GetInstanceInfo())
        return tostring(instanceType or "instance")
            .. ":"
            .. tostring(instanceID or "")
    end
    return "delve"
end

local function ResetInstanceTimer()
    local instanceToken = GetInstanceToken()
    lastInstanceDuration = 0
    if instanceToken then
        instanceStartTime = GetTime()
        instanceActive = true
    else
        instanceStartTime = nil
        instanceActive = false
    end
    UpdateCombatTimerText()
end

local function ResetCombatTimer()
    lastCombatDuration = 0
    if InCombatLockdown() then
        combatStartTime = GetTime()
        combatActive = true
    else
        combatStartTime = nil
        combatActive = false
    end
    UpdateCombatTimerText()
end

local function ScaleCombatTimerFont(fontString)
    local fontFile, fontHeight, fontFlags = fontString:GetFont()
    if fontFile and fontHeight then
        fontString:SetFont(
            fontFile,
            fontHeight * COMBAT_TIMER_FONT_SCALE,
            fontFlags or ""
        )
    end
end

local function EnsureCombatTimerFrame()
    if combatTimerFrame then return combatTimerFrame end

    local frame = CreateFrame("Frame", "LiteToolsCombatTimerFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    if frame.SetDontSavePosition then
        frame:SetDontSavePosition(true)
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    frame.background = background

    local divider = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    divider:SetPoint("CENTER")
    divider:SetJustifyH("CENTER")
    divider:SetJustifyV("MIDDLE")
    divider:SetTextColor(1, 0.82, 0, 1)
    divider:SetText("|")
    ScaleCombatTimerFont(divider)
    frame.divider = divider

    local instanceText = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    instanceText:SetPoint("RIGHT", divider, "LEFT", -8, 0)
    instanceText:SetSize(112, COMBAT_TIMER_HEIGHT)
    instanceText:SetJustifyH("RIGHT")
    instanceText:SetJustifyV("MIDDLE")
    instanceText:SetTextColor(1, 0.82, 0, 1)
    ScaleCombatTimerFont(instanceText)
    frame.instanceText = instanceText

    local combatText = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    combatText:SetPoint("LEFT", divider, "RIGHT", 8, 0)
    combatText:SetSize(112, COMBAT_TIMER_HEIGHT)
    combatText:SetJustifyH("LEFT")
    combatText:SetJustifyV("MIDDLE")
    combatText:SetTextColor(1, 0.82, 0, 1)
    ScaleCombatTimerFont(combatText)
    frame.combatText = combatText

    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Addon.Anchors:SavePosition(self, "combatTimerPosition")
        PositionCombatTimer()
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        ResetInstanceTimer()
        ResetCombatTimer()
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Addon.L.COMBAT_TIMER_TOOLTIP)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnHide", function(self) self:StopMovingOrSizing() end)

    combatTimerFrame = frame
    UpdateCombatTimerBackground()
    frame:SetScale((Addon:GetSetting("combatTimerScale") or DEFAULT_SCALE) / 100)
    PositionCombatTimer()
    UpdateCombatTimerText()
    frame:Hide()
    return frame
end

local function StartCombatTimerUpdates()
    if combatTimerTicker then return end
    combatTimerTicker = C_Timer.NewTicker(
        COMBAT_TIMER_UPDATE_INTERVAL,
        UpdateCombatTimerText
    )
end

local function StopCombatTimerUpdates()
    if combatTimerTicker then
        combatTimerTicker:Cancel()
        combatTimerTicker = nil
    end
end

local function UpdateCombatTimerRefreshMode()
    if not combatTimerFrame then return end

    if combatActive then
        StopCombatTimerUpdates()
        combatTimerFrame:SetScript("OnUpdate", UpdateCombatTimerText)
    else
        combatTimerFrame:SetScript("OnUpdate", nil)
        StartCombatTimerUpdates()
    end
end

local function UpdateInstanceTimerState()
    local instanceToken = GetInstanceToken()
    if instanceToken and not instanceActive then
        instanceStartTime = GetTime()
        lastInstanceDuration = 0
        instanceActive = true
    elseif not instanceToken and instanceActive then
        if instanceActive and instanceStartTime then
            lastInstanceDuration = math.max(0, GetTime() - instanceStartTime)
        end
        instanceStartTime = nil
        instanceActive = false
    end
    UpdateCombatTimerText()
end

local function QueueInstanceTimerStateUpdate()
    instanceStateUpdateGeneration = instanceStateUpdateGeneration + 1
    local generation = instanceStateUpdateGeneration
    C_Timer.After(0.75, function()
        if generation == instanceStateUpdateGeneration
            and Addon:GetSetting("showCombatTimer") then
            UpdateInstanceTimerState()
        end
    end)
end

local function ApplyCombatTimer(reposition)
    local db = DB()
    if not db then return end

    if db.showCombatTimer then
        local frame = EnsureCombatTimerFrame()
        UpdateCombatTimerBackground()
        if reposition then PositionCombatTimer() end
        frame:SetScale(db.combatTimerScale / 100)
        UpdateCombatTimerText()
        frame:Show()
        UpdateCombatTimerRefreshMode()
    else
        if instanceActive and instanceStartTime then
            lastInstanceDuration = math.max(0, GetTime() - instanceStartTime)
        end
        instanceStartTime = nil
        instanceActive = false
        StopCombatTimerUpdates()
        if combatTimerFrame then
            combatTimerFrame:SetScript("OnUpdate", nil)
            combatTimerFrame:Hide()
        end
    end
end

local function IsCombatTimerEnabled(db)
    return db.showCombatTimer
end

Addon:RegisterSetting("showCombatTimer", false, Addon.BooleanSetting, function()
    ApplyCombatTimer(true)
    if Addon:GetSetting("showCombatTimer") then
        QueueInstanceTimerStateUpdate()
    end
end)
Addon:RegisterSetting(
    "combatTimerScale",
    DEFAULT_SCALE,
    Addon.NumberSetting(50, 200),
    function(value)
        if combatTimerFrame then combatTimerFrame:SetScale(value / 100) end
    end
)
Addon:RegisterSetting("combatTimerPosition", nil, Addon.PositionSetting)

Addon:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    combatStartTime = GetTime()
    lastCombatDuration = 0
    combatActive = true
    UpdateCombatTimerText()
    UpdateCombatTimerRefreshMode()
end, IsCombatTimerEnabled)
Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if combatActive and combatStartTime then
        lastCombatDuration = math.max(0, GetTime() - combatStartTime)
    end
    combatStartTime = nil
    combatActive = false
    UpdateCombatTimerText()
    UpdateCombatTimerRefreshMode()
end, IsCombatTimerEnabled)
Addon:RegisterEvent("PLAYER_LOGIN", function()
    ApplyCombatTimer(true)
    QueueInstanceTimerStateUpdate()
end, IsCombatTimerEnabled)
for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "LOADING_SCREEN_DISABLED",
    "SCENARIO_UPDATE",
}) do
    Addon:RegisterEvent(event, function()
        ApplyCombatTimer(true)
        QueueInstanceTimerStateUpdate()
    end, IsCombatTimerEnabled)
end
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    Addon:RegisterEvent(event, function()
        ApplyCombatTimer(true)
    end, IsCombatTimerEnabled)
end
