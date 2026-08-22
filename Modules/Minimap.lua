local ADDON_NAME, Addon = ...

local BORDER_TEXTURE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\UIMinimap-ring"
local BORDER_SOURCE_WIDTH = 410
local BORDER_SOURCE_HEIGHT = 411
local OFFICIAL_ATLAS_SOURCE_WIDTH = 438
local OFFICIAL_ATLAS_SOURCE_HEIGHT = 460
local OFFICIAL_BORDER_WIDTH = 215
local OFFICIAL_BORDER_HEIGHT = 226
local OFFICIAL_MINIMAP_SIZE = 198
local BORDER_WIDTH_SCALE = BORDER_SOURCE_WIDTH * OFFICIAL_BORDER_WIDTH
    / (OFFICIAL_ATLAS_SOURCE_WIDTH * OFFICIAL_MINIMAP_SIZE)
local BORDER_HEIGHT_SCALE = BORDER_SOURCE_HEIGHT * OFFICIAL_BORDER_HEIGHT
    / (OFFICIAL_ATLAS_SOURCE_HEIGHT * OFFICIAL_MINIMAP_SIZE)
local BORDER_OFFSET_Y_SCALE = BORDER_HEIGHT_SCALE * -3.5 / BORDER_SOURCE_HEIGHT

local borderHookInstalled = false
local borderUpdateQueued = false
local borderTexture
local defaultBorderWasShown
local borderApplied = false
local dragInstalled = false
local positionApplied = false
local positionUpdatePending = false
local dragUpdateFrame
local dragging = false
local dragStartCursorX
local dragStartCursorY
local dragStartCenterX
local dragStartCenterY

local function DB()
    return Addon:GetDatabase()
end

local function SanitizePosition(position)
    if type(position) ~= "table" then
        return nil
    end
    if position.version == 2 then
        return Addon.PositionSetting(position)
    end
    if type(position.point) ~= "string" then
        return nil
    end
    return {
        point = position.point,
        relativeTo = type(position.relativeTo) == "string" and position.relativeTo or nil,
        relativePoint = type(position.relativePoint) == "string" and position.relativePoint or nil,
        x = tonumber(position.x) or 0,
        y = tonumber(position.y) or 0,
    }
end

local function EnsureBorderTexture()
    if borderTexture then
        return borderTexture
    end
    if not Minimap or not MinimapBackdrop or not MinimapCompassTexture then
        return nil
    end

    local db = DB()
    borderTexture = MinimapBackdrop:CreateTexture("LiteToolsMinimapBorder", "OVERLAY", nil, 3)
    borderTexture:SetTexture(BORDER_TEXTURE)
    borderTexture:SetTexCoord(0, 1, 0, 1)
    borderTexture:SetDesaturated(db.minimapBorderColorCustomized)
    borderTexture:SetVertexColor(
        db.minimapBorderColorR,
        db.minimapBorderColorG,
        db.minimapBorderColorB
    )
    borderTexture:SetAlpha(db.minimapBorderColorA)
    borderTexture:Hide()
    return borderTexture
end

local function ResizeBorder()
    local texture = EnsureBorderTexture()
    if not texture or not Minimap then
        return
    end
    local width, height = Minimap:GetSize()
    if width and height and width > 0 and height > 0 then
        texture:SetSize(width * BORDER_WIDTH_SCALE, height * BORDER_HEIGHT_SCALE)
        texture:ClearAllPoints()
        texture:SetPoint(
            "CENTER",
            Minimap,
            "CENTER",
            0,
            height * BORDER_OFFSET_Y_SCALE
        )
    end
end

local function ApplyBorder()
    local db = DB()
    if not db or not MinimapCompassTexture then
        return
    end
    if db.hideMinimapBorder then
        if not borderApplied then
            defaultBorderWasShown = MinimapCompassTexture:IsShown()
            borderApplied = true
        end
        MinimapCompassTexture:Hide()
        if borderTexture then
            borderTexture:Hide()
        end
    elseif db.replaceMinimapBorder then
        local texture = EnsureBorderTexture()
        if not texture then
            return
        end
        if not borderApplied then
            defaultBorderWasShown = MinimapCompassTexture:IsShown()
            borderApplied = true
        end
        ResizeBorder()
        MinimapCompassTexture:Hide()
        texture:Show()
    else
        if borderTexture then
            borderTexture:Hide()
        end
        if borderApplied then
            MinimapCompassTexture:SetShown(defaultBorderWasShown)
            borderApplied = false
        end
    end
end

local function QueueBorderUpdate()
    if borderUpdateQueued then
        return
    end
    borderUpdateQueued = true
    C_Timer.After(0, function()
        borderUpdateQueued = false
        ApplyBorder()
    end)
end

local function InstallBorderHook()
    if borderHookInstalled or not Minimap then
        return
    end
    Minimap:HookScript("OnSizeChanged", function()
        if Addon:GetSetting("replaceMinimapBorder") then
            QueueBorderUpdate()
        end
    end)
    if MinimapCompassTexture then
        hooksecurefunc(MinimapCompassTexture, "Show", function(texture)
            if Addon:GetSetting("replaceMinimapBorder")
                or Addon:GetSetting("hideMinimapBorder")
            then
                texture:Hide()
            end
        end)
    end
    borderHookInstalled = true
end

local function SetHeaderScale(frame, scale)
    if frame and math.abs(frame:GetScale() - scale) > 0.001 then
        frame:SetScale(scale)
    end
end

local function ApplyHeaderScale()
    if not MinimapCluster then
        return
    end
    local scale = Addon:GetSetting("minimapHeaderScale") / 100
    SetHeaderScale(MinimapCluster.BorderTop, scale)
    SetHeaderScale(MinimapCluster.ZoneTextButton, scale)
    SetHeaderScale(MinimapCluster.Tracking, scale)
    SetHeaderScale(TimeManagerClockButton, scale)
    SetHeaderScale(GameTimeFrame, scale)
end

local function GetCenterInUIParent()
    if not Minimap or not UIParent then
        return nil, nil
    end
    local centerX, centerY = Minimap:GetCenter()
    local minimapScale = Minimap:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    if not centerX or not centerY or not minimapScale or not uiScale or uiScale <= 0 then
        return nil, nil
    end
    return centerX * minimapScale / uiScale, centerY * minimapScale / uiScale
end

local function ClampCenter(centerX, centerY)
    local uiWidth, uiHeight = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()
    local minimapScale = Minimap:GetEffectiveScale()
    if not uiScale or not minimapScale or uiScale <= 0 or minimapScale <= 0 then
        return centerX, centerY
    end
    local scale = minimapScale / uiScale
    local halfWidth = Minimap:GetWidth() * scale / 2
    local halfHeight = Minimap:GetHeight() * scale / 2
    return Addon:Clamp(centerX, halfWidth, math.max(halfWidth, uiWidth - halfWidth)),
        Addon:Clamp(centerY, halfHeight, math.max(halfHeight, uiHeight - halfHeight))
end

local function SetCenter(centerX, centerY)
    centerX, centerY = ClampCenter(centerX, centerY)
    local uiScale = UIParent:GetEffectiveScale()
    local minimapScale = Minimap:GetEffectiveScale()
    if not uiScale or not minimapScale or uiScale <= 0 or minimapScale <= 0 then
        return
    end
    local pointScale = uiScale / minimapScale
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX * pointScale, centerY * pointScale)
    positionApplied = true
end

local function SavePosition()
    local db = DB()
    if not db or not Minimap or not UIParent then
        return
    end
    local centerX, centerY = GetCenterInUIParent()
    local uiWidth, uiHeight = UIParent:GetSize()
    if centerX and centerY and uiWidth and uiHeight and uiWidth > 0 and uiHeight > 0 then
        db.minimapPosition = {
            version = 2,
            x = Addon:Clamp(centerX / uiWidth, 0, 1),
            y = Addon:Clamp(centerY / uiHeight, 0, 1),
        }
    end
end

local function ApplyPosition()
    local db = DB()
    local position = db and db.minimapPosition
    if not position or not Minimap or not UIParent then
        return
    end
    if position.version == 2 then
        local uiWidth, uiHeight = UIParent:GetSize()
        SetCenter(
            Addon:Clamp(position.x, 0, 1) * uiWidth,
            Addon:Clamp(position.y, 0, 1) * uiHeight
        )
    elseif position.point then
        local relativeTo = position.relativeTo and _G[position.relativeTo] or Minimap:GetParent()
        Minimap:ClearAllPoints()
        Minimap:SetPoint(
            position.point,
            relativeTo,
            position.relativePoint or "CENTER",
            position.x or 0,
            position.y or 0
        )
        positionApplied = true
        SavePosition()
    end
end

local function RestoreDefaultPosition()
    if Minimap then
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", Minimap:GetParent(), "CENTER", 0, 0)
        positionApplied = false
    end
end

local function StopDrag(savePosition)
    if not dragging then
        return
    end
    dragging = false
    if dragUpdateFrame then
        dragUpdateFrame:Hide()
    end
    if savePosition and Addon:GetSetting("moveableMinimap") then
        SavePosition()
    end
end

local function UpdateDrag()
    if not dragging or not IsMouseButtonDown("LeftButton") then
        StopDrag(true)
        return
    end
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale <= 0 then
        StopDrag(true)
        return
    end
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / uiScale
    cursorY = cursorY / uiScale
    SetCenter(
        dragStartCenterX + cursorX - dragStartCursorX,
        dragStartCenterY + cursorY - dragStartCursorY
    )
end

local function InstallDrag()
    if dragInstalled or not Minimap then
        return
    end
    Minimap:SetMovable(true)
    Minimap:RegisterForDrag("LeftButton")
    dragUpdateFrame = CreateFrame("Frame")
    dragUpdateFrame:Hide()
    dragUpdateFrame:SetScript("OnUpdate", UpdateDrag)
    Minimap:HookScript("OnDragStart", function()
        local db = DB()
        if not db or not db.moveableMinimap or db.minimapPositionLocked or InCombatLockdown() then
            return
        end
        local centerX, centerY = GetCenterInUIParent()
        local uiScale = UIParent:GetEffectiveScale()
        if not centerX or not centerY or not uiScale or uiScale <= 0 then
            return
        end
        dragStartCursorX, dragStartCursorY = GetCursorPosition()
        dragStartCursorX = dragStartCursorX / uiScale
        dragStartCursorY = dragStartCursorY / uiScale
        dragStartCenterX = centerX
        dragStartCenterY = centerY
        dragging = true
        dragUpdateFrame:Show()
    end)
    Minimap:HookScript("OnDragStop", function() StopDrag(true) end)
    dragInstalled = true
end

local function ApplyMoveSetting(forcePosition)
    local db = DB()
    if not db or not Minimap then
        return
    end
    if InCombatLockdown() then
        positionUpdatePending = true
        return
    end
    positionUpdatePending = false
    if db.moveableMinimap then
        InstallDrag()
        if forcePosition then
            StopDrag(true)
        end
        if db.minimapPosition and (forcePosition or not positionApplied) then
            ApplyPosition()
        end
    else
        StopDrag(false)
        if positionApplied then
            RestoreDefaultPosition()
        end
    end
end

Addon:RegisterDatabaseMigration(function(db)
    if db.minimapBorderColorCustomized == nil then
        db.minimapBorderColorCustomized = (tonumber(db.minimapBorderColorR) or 1) ~= 1
            or (tonumber(db.minimapBorderColorG) or 1) ~= 1
            or (tonumber(db.minimapBorderColorB) or 1) ~= 1
    end
end)

Addon:RegisterSetting("replaceMinimapBorder", false, Addon.BooleanSetting, function(value)
    if value then InstallBorderHook() end
    QueueBorderUpdate()
end)
Addon:RegisterSetting("hideMinimapBorder", false, Addon.BooleanSetting, function(value)
    if value then InstallBorderHook() end
    QueueBorderUpdate()
end)
Addon:RegisterSetting("minimapHeaderScale", 100, Addon.NumberSetting(50, 200), ApplyHeaderScale)
Addon:RegisterSetting("moveableMinimap", false, Addon.BooleanSetting, function() ApplyMoveSetting(false) end)
Addon:RegisterSetting("minimapPositionLocked", false, Addon.BooleanSetting, function(value)
    if value then
        StopDrag(false)
        SavePosition()
    end
    ApplyMoveSetting(false)
end)
Addon:RegisterSetting("minimapPosition", nil, SanitizePosition)
Addon:RegisterSetting("minimapBorderColorR", 1, function(value) return Addon:Clamp(value, 0, 1) end)
Addon:RegisterSetting("minimapBorderColorG", 1, function(value) return Addon:Clamp(value, 0, 1) end)
Addon:RegisterSetting("minimapBorderColorB", 1, function(value) return Addon:Clamp(value, 0, 1) end)
Addon:RegisterSetting("minimapBorderColorA", 1, function(value) return Addon:Clamp(value, 0, 1) end)
Addon:RegisterSetting("minimapBorderColorCustomized", false, Addon.BooleanSetting)

function Addon:GetMinimapBorderColor()
    local db = DB()
    if not db then
        return 1, 1, 1, 1, false
    end
    return db.minimapBorderColorR,
        db.minimapBorderColorG,
        db.minimapBorderColorB,
        db.minimapBorderColorA,
        db.minimapBorderColorCustomized
end

function Addon:SetMinimapBorderColor(red, green, blue, alpha, customized)
    local db = DB()
    if not db then
        return
    end
    red = Addon:Clamp(red, 0, 1)
    green = Addon:Clamp(green, 0, 1)
    blue = Addon:Clamp(blue, 0, 1)
    alpha = Addon:Clamp(tonumber(alpha) or 1, 0, 1)
    customized = customized == nil or not not customized
    if db.minimapBorderColorR == red
        and db.minimapBorderColorG == green
        and db.minimapBorderColorB == blue
        and db.minimapBorderColorA == alpha
        and db.minimapBorderColorCustomized == customized
    then
        return
    end
    db.minimapBorderColorR = red
    db.minimapBorderColorG = green
    db.minimapBorderColorB = blue
    db.minimapBorderColorA = alpha
    db.minimapBorderColorCustomized = customized
    if borderTexture then
        borderTexture:SetDesaturated(customized)
        borderTexture:SetVertexColor(red, green, blue)
        borderTexture:SetAlpha(alpha)
    end
end

local function ApplyAll(immediateBorder)
    if Addon:GetSetting("replaceMinimapBorder")
        or Addon:GetSetting("hideMinimapBorder")
    then
        InstallBorderHook()
        if immediateBorder then ApplyBorder() else QueueBorderUpdate() end
    end
    ApplyHeaderScale()
    ApplyMoveSetting(true)
end

local function HasCustomMinimap(db)
    return db.replaceMinimapBorder or db.hideMinimapBorder
        or db.minimapHeaderScale ~= 100 or db.moveableMinimap
end

Addon:RegisterEvent("PLAYER_LOGIN", function() ApplyAll(true) end, HasCustomMinimap)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function() ApplyAll(false) end, HasCustomMinimap)
Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if positionUpdatePending then ApplyMoveSetting(true) end
end)
Addon:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
    if Addon:GetSetting("replaceMinimapBorder")
        or Addon:GetSetting("hideMinimapBorder")
    then
        QueueBorderUpdate()
    end
    ApplyHeaderScale()
    ApplyMoveSetting(true)
end, HasCustomMinimap)
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    Addon:RegisterEvent(event, function()
        if Addon:GetSetting("replaceMinimapBorder")
            or Addon:GetSetting("hideMinimapBorder")
        then
            QueueBorderUpdate()
        end
        if Addon:GetSetting("moveableMinimap") then ApplyMoveSetting(true) end
    end, function(db)
        return db.replaceMinimapBorder or db.hideMinimapBorder
            or db.moveableMinimap
    end)
end
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_TimeManager" or loadedAddon == "Blizzard_TimeManager_Mainline" then
        ApplyHeaderScale()
    elseif loadedAddon == "Blizzard_Minimap" then
        ApplyAll(true)
    end
end, HasCustomMinimap)
