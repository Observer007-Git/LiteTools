local _, Addon = ...

local DEFAULT_DURATION = 2
local DEFAULT_SCALE = 100
local FADE_DURATION = 0.5
local ALERT_HEIGHT = 96
local FALLBACK_ALERT_WIDTH = 420

local ALERT_DEFINITIONS = {
    {
        event = "PLAYER_REGEN_DISABLED",
        enabledKey = "showCombatAlert",
        durationKey = "combatAlertDuration",
        scaleKey = "combatAlertScale",
        mutedKey = "combatAlertMuted",
        soundKey = "combatAlertSound",
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
        mutedKey = "leaveCombatAlertMuted",
        soundKey = "leaveCombatAlertSound",
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

local function SanitizeSound(value)
    if type(value) ~= "string" and type(value) ~= "number" then
        return ""
    end
    return tostring(value):match("^%s*(.-)%s*$"):sub(1, 255)
end

local function PlaySoundValue(value)
    if value == nil or value == "" or type(PlaySoundFile) ~= "function" then return end

    local soundFile = value
    local soundFileID = tonumber(soundFile)
    if soundFileID and soundFileID > 0 and soundFileID == math.floor(soundFileID) then
        soundFile = soundFileID
    end
    pcall(PlaySoundFile, soundFile, "Master")
end

function Addon:PreviewCombatAlertSound(value)
    PlaySoundValue(value)
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

local function PlayConfiguredSound(definition)
    local db = DB()
    if not db or db[definition.mutedKey] then return end
    PlaySoundValue(db[definition.soundKey])
end

local function ShowAlert(definition)
    local db = DB()
    if not db or not db[definition.enabledKey] then return end

    local frame = EnsureAlertFrame(definition)
    EnsureAnchor(definition)
    UpdateBackground(definition)
    PositionAlert(definition)
    frame:Show()
    PlayConfiguredSound(definition)
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
    Addon:RegisterSetting(definition.mutedKey, false, Addon.BooleanSetting)
    Addon:RegisterSetting(definition.soundKey, "", SanitizeSound)
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

for _, definition in ipairs(ALERT_DEFINITIONS) do
    RegisterAlert(definition)
end
