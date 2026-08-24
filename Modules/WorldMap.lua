local _, Addon = ...

local DEFAULT_WIDTH = 702
local DEFAULT_HEIGHT = 534
local MIN_SCALE = 0.5
local MAX_SCALE = 2
local SCREEN_MARGIN = 20
local DIRECTION_LINE_UPDATE_INTERVAL = 1 / 30
local DIRECTION_LINE_START_OFFSET = 10

local resizeButton
local resizeTracker
local collapseCategoriesButton
local topDragRegion
local directionLineFrame
local directionCanvas
local directionLineBackground
local directionLine
local directionLineCreateQueued = false
local dragRegions = {}
local initialized = false
local applyQueued = false
local resizing = false
local moving = false
local resizeStartScale
local resizeStartDistance
local resizeTopLeftX
local resizeTopLeftY
local directionLineUpdateElapsed = 0

local function DB()
    return Addon:GetDatabase()
end

local function SanitizeScale(value)
    return Addon:Clamp(tonumber(value) or 1, MIN_SCALE, MAX_SCALE)
end

local function IsMaximized()
    return WorldMapFrame
        and WorldMapFrame.IsMaximized
        and WorldMapFrame:IsMaximized()
end

local function SavePosition()
    local db = DB()
    if not db or not WorldMapFrame or not UIParent then
        return
    end

    local centerX, centerY = WorldMapFrame:GetCenter()
    local uiWidth, uiHeight = UIParent:GetSize()
    local mapScale = WorldMapFrame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    if not centerX or not centerY or not uiWidth or not uiHeight
        or not mapScale or not uiScale or uiWidth <= 0 or uiHeight <= 0
        or mapScale <= 0 or uiScale <= 0
    then
        return
    end

    centerX = centerX * mapScale / uiScale
    centerY = centerY * mapScale / uiScale
    db.worldMapPosition = {
        version = 2,
        x = Addon:Clamp(centerX / uiWidth, 0, 1),
        y = Addon:Clamp(centerY / uiHeight, 0, 1),
    }
end

local function SaveWindow()
    local db = DB()
    if not db or not WorldMapFrame or IsMaximized() then
        return
    end

    db.worldMapScale = SanitizeScale(WorldMapFrame:GetScale())
    SavePosition()
end

local function ApplyPosition(position)
    if not position or not WorldMapFrame or not UIParent then
        return
    end

    local uiWidth, uiHeight = UIParent:GetSize()
    local mapScale = WorldMapFrame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    if not uiWidth or not uiHeight or not mapScale or not uiScale
        or uiWidth <= 0 or uiHeight <= 0 or mapScale <= 0 or uiScale <= 0
    then
        return
    end

    local scale = mapScale / uiScale
    local halfWidth = WorldMapFrame:GetWidth() * scale / 2
    local halfHeight = WorldMapFrame:GetHeight() * scale / 2
    local centerX = Addon:Clamp(
        position.x * uiWidth,
        halfWidth,
        math.max(halfWidth, uiWidth - halfWidth)
    )
    local centerY = Addon:Clamp(
        position.y * uiHeight,
        halfHeight,
        math.max(halfHeight, uiHeight - halfHeight)
    )

    WorldMapFrame:ClearAllPoints()
    WorldMapFrame:SetPoint(
        "CENTER",
        UIParent,
        "BOTTOMLEFT",
        centerX / scale,
        centerY / scale
    )
end

local function GetScaleBounds()
    if not WorldMapFrame or not UIParent then
        return MIN_SCALE, MAX_SCALE
    end

    local currentScale = WorldMapFrame:GetScale()
    local mapScale = WorldMapFrame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local uiWidth, uiHeight = UIParent:GetSize()
    if not currentScale or not mapScale or not uiScale
        or not uiWidth or not uiHeight or currentScale <= 0
        or mapScale <= 0 or uiScale <= 0
    then
        return MIN_SCALE, MAX_SCALE
    end

    local baseScale = mapScale / currentScale
    local widthAtScaleOne = WorldMapFrame:GetWidth() * baseScale / uiScale
    local heightAtScaleOne = WorldMapFrame:GetHeight() * baseScale / uiScale
    if widthAtScaleOne <= 0 or heightAtScaleOne <= 0 then
        return MIN_SCALE, MAX_SCALE
    end

    local screenMaximum = math.min(
        (uiWidth - SCREEN_MARGIN) / widthAtScaleOne,
        (uiHeight - SCREEN_MARGIN) / heightAtScaleOne
    )
    return MIN_SCALE, math.max(MIN_SCALE, math.min(MAX_SCALE, screenMaximum))
end

local function HideDirectionLine()
    if directionLineBackground then
        directionLineBackground:Hide()
    end
    if directionLine then
        directionLine:Hide()
    end
end

local function UpdateDirectionLine()
    if not directionLine or not directionLineFrame
        or not Addon:GetSetting("enableWorldMapDirectionLine")
        or not WorldMapFrame:IsShown()
    then
        HideDirectionLine()
        return
    end

    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local position = mapID and C_Map and C_Map.GetPlayerMapPosition
        and C_Map.GetPlayerMapPosition(mapID, "player")
    local facing = type(GetPlayerFacing) == "function" and GetPlayerFacing()
    if not position or facing == nil then
        HideDirectionLine()
        return
    end

    local canvas = directionCanvas
    local positionX, positionY = position:GetXY()
    local canvasWidth, canvasHeight = canvas:GetSize()
    local canvasLeft, canvasTop = canvas:GetLeft(), canvas:GetTop()
    local canvasScale = canvas:GetEffectiveScale()
    local frameWidth, frameHeight = directionLineFrame:GetSize()
    local frameLeft = directionLineFrame:GetLeft()
    local frameTop = directionLineFrame:GetTop()
    local frameScale = directionLineFrame:GetEffectiveScale()
    if not positionX or not positionY or positionX < 0 or positionX > 1
        or positionY < 0 or positionY > 1
        or not canvasWidth or not canvasHeight
        or not canvasLeft or not canvasTop or not canvasScale
        or not frameWidth or not frameHeight or not frameLeft or not frameTop
        or not frameScale or canvasWidth <= 0 or canvasHeight <= 0
        or canvasScale <= 0 or frameWidth <= 0 or frameHeight <= 0
        or frameScale <= 0
    then
        HideDirectionLine()
        return
    end

    local startX = (
        (canvasLeft + positionX * canvasWidth) * canvasScale
        - frameLeft * frameScale
    ) / frameScale
    local startY = (
        frameTop * frameScale
        - (canvasTop - positionY * canvasHeight) * canvasScale
    ) / frameScale
    if startX < 0 or startX > frameWidth
        or startY < 0 or startY > frameHeight
    then
        HideDirectionLine()
        return
    end

    local directionX = -math.sin(facing)
    local directionY = -math.cos(facing)
    startX = startX + directionX * DIRECTION_LINE_START_OFFSET
    startY = startY + directionY * DIRECTION_LINE_START_OFFSET
    local distanceX = math.huge
    local distanceY = math.huge
    if directionX > 0 then
        distanceX = (frameWidth - startX) / directionX
    elseif directionX < 0 then
        distanceX = -startX / directionX
    end
    if directionY > 0 then
        distanceY = (frameHeight - startY) / directionY
    elseif directionY < 0 then
        distanceY = -startY / directionY
    end
    local distance = math.min(distanceX, distanceY)
    if distance == math.huge or distance < 0 then
        HideDirectionLine()
        return
    end

    directionLineBackground:SetStartPoint(
        "TOPLEFT",
        directionLineFrame,
        startX,
        -startY
    )
    directionLineBackground:SetEndPoint(
        "TOPLEFT",
        directionLineFrame,
        startX + directionX * distance,
        -(startY + directionY * distance)
    )
    directionLine:SetStartPoint(
        "TOPLEFT",
        directionLineFrame,
        startX,
        -startY
    )
    directionLine:SetEndPoint(
        "TOPLEFT",
        directionLineFrame,
        startX + directionX * distance,
        -(startY + directionY * distance)
    )
    directionLineBackground:Show()
    directionLine:Show()
end

local function OnDirectionLineUpdate(_, elapsed)
    directionLineUpdateElapsed = directionLineUpdateElapsed + elapsed
    if directionLineUpdateElapsed < DIRECTION_LINE_UPDATE_INTERVAL then
        return
    end
    directionLineUpdateElapsed = 0
    UpdateDirectionLine()
end

local function UpdateDirectionLineVisibility()
    if not directionLineFrame then
        return
    end
    local enabled = Addon:GetSetting("enableWorldMapDirectionLine")
    directionLineFrame:SetShown(enabled)
    if enabled then
        UpdateDirectionLine()
    else
        HideDirectionLine()
    end
end

local function CreateDirectionLine()
    if directionLineFrame then
        return true
    end
    if not WorldMapFrame then
        return false
    end

    local scrollContainer = WorldMapFrame.ScrollContainer
    local canvas = scrollContainer and scrollContainer.Child
    if not canvas and WorldMapFrame.GetCanvasContainer then
        canvas = WorldMapFrame:GetCanvasContainer()
    end
    if not canvas then
        return false
    end

    directionCanvas = canvas
    directionLineFrame = CreateFrame(
        "Frame",
        "LiteToolsWorldMapDirectionLineFrame",
        scrollContainer or WorldMapFrame
    )
    directionLineFrame:SetAllPoints(scrollContainer or WorldMapFrame)
    directionLineFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    directionLineFrame:SetFrameLevel(200)
    directionLineBackground = directionLineFrame:CreateLine(
        nil,
        "OVERLAY",
        nil,
        6
    )
    directionLineBackground:SetThickness(1)
    directionLineBackground:SetColorTexture(0, 0, 0, 0.75)
    directionLine = directionLineFrame:CreateLine(
        nil,
        "OVERLAY",
        nil,
        7
    )
    directionLine:SetThickness(1)
    local _, classFile = UnitClass("player")
    local color = classFile and RAID_CLASS_COLORS
        and RAID_CLASS_COLORS[classFile]
    directionLine:SetColorTexture(
        color and color.r or 1,
        color and color.g or 0.82,
        color and color.b or 0,
        0.9
    )
    directionLineFrame:SetScript("OnUpdate", OnDirectionLineUpdate)
    UpdateDirectionLineVisibility()
    return true
end

local function QueueDirectionLineCreation()
    if directionLineFrame or directionLineCreateQueued
        or not Addon:GetSetting("enableWorldMapDirectionLine")
    then
        return
    end

    directionLineCreateQueued = true
    local attemptsRemaining = 20
    local function TryCreate()
        if CreateDirectionLine() then
            directionLineCreateQueued = false
            return
        end
        attemptsRemaining = attemptsRemaining - 1
        if attemptsRemaining > 0 then
            C_Timer.After(0, TryCreate)
        else
            directionLineCreateQueued = false
        end
    end
    C_Timer.After(0, TryCreate)
end

local function UpdateControlVisibility()
    local shown = Addon:GetSetting("enableWorldMapResize") and not IsMaximized()
    if resizeButton then
        resizeButton:SetShown(shown)
    end
    for _, region in ipairs(dragRegions) do
        region:SetShown(shown)
    end
    if collapseCategoriesButton then
        local collapseShown = Addon:GetSetting(
            "showCollapseQuestCategoriesButton"
        )
        collapseCategoriesButton:SetShown(collapseShown)
        if topDragRegion then
            topDragRegion:ClearAllPoints()
            topDragRegion:SetPoint(
                "TOPLEFT",
                WorldMapFrame,
                "TOPLEFT",
                4,
                -2
            )
            local maximizeFrame = WorldMapFrame.BorderFrame
                and WorldMapFrame.BorderFrame.MaximizeMinimizeFrame
            local rightControl = collapseShown
                and collapseCategoriesButton or maximizeFrame
            if rightControl then
                topDragRegion:SetPoint(
                    "TOPRIGHT",
                    rightControl,
                    "TOPLEFT",
                    0,
                    0
                )
            else
                topDragRegion:SetPoint(
                    "TOPRIGHT",
                    WorldMapFrame,
                    "TOPRIGHT",
                    -64,
                    -2
                )
            end
        end
    end
end

local function ApplySavedWindow()
    if not initialized or not WorldMapFrame then
        return
    end

    local enabled = Addon:GetSetting("enableWorldMapResize")
    WorldMapFrame:SetMovable(enabled)
    UpdateControlVisibility()
    if not enabled then
        return
    end
    if IsMaximized() then
        WorldMapFrame:SetScale(1)
        return
    end
    if not WorldMapFrame:IsShown() or resizing or moving then
        return
    end

    local db = DB()
    if not db then
        return
    end

    local minimumScale, maximumScale = GetScaleBounds()
    WorldMapFrame:SetScale(Addon:Clamp(
        tonumber(db.worldMapScale) or 1,
        minimumScale,
        maximumScale
    ))
    if not db.worldMapPosition then
        SavePosition()
    end
    ApplyPosition(db.worldMapPosition)
end

local function QueueApply()
    if applyQueued then
        return
    end
    applyQueued = true
    C_Timer.After(0, function()
        applyQueued = false
        ApplySavedWindow()
    end)
end

local function StopResize(save)
    if not resizing then
        return
    end
    resizing = false
    if resizeTracker then
        resizeTracker:Hide()
    end
    if save then
        SaveWindow()
        ApplySavedWindow()
        SavePosition()
    end
end

local function UpdateResize()
    if not resizing or not IsMouseButtonDown("LeftButton") then
        StopResize(true)
        return
    end

    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale <= 0 then
        StopResize(true)
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / uiScale
    cursorY = cursorY / uiScale
    local distance = math.sqrt(
        (cursorX - resizeTopLeftX) ^ 2
        + (resizeTopLeftY - cursorY) ^ 2
    )
    local minimumScale, maximumScale = GetScaleBounds()
    local scale = Addon:Clamp(
        resizeStartScale * distance / resizeStartDistance,
        minimumScale,
        maximumScale
    )
    WorldMapFrame:SetScale(scale)

    local mapScale = WorldMapFrame:GetEffectiveScale()
    local pointScale = uiScale / mapScale
    WorldMapFrame:ClearAllPoints()
    WorldMapFrame:SetPoint(
        "TOPLEFT",
        UIParent,
        "BOTTOMLEFT",
        resizeTopLeftX * pointScale,
        resizeTopLeftY * pointScale
    )
end

local function StartResize()
    if resizing or moving or IsMaximized()
        or not Addon:GetSetting("enableWorldMapResize")
    then
        return
    end

    local uiScale = UIParent:GetEffectiveScale()
    local mapScale = WorldMapFrame:GetEffectiveScale()
    local left, top = WorldMapFrame:GetLeft(), WorldMapFrame:GetTop()
    if not uiScale or not mapScale or not left or not top
        or uiScale <= 0 or mapScale <= 0
    then
        return
    end

    resizeStartScale = WorldMapFrame:GetScale()
    resizeTopLeftX = left * mapScale / uiScale
    resizeTopLeftY = top * mapScale / uiScale
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / uiScale
    cursorY = cursorY / uiScale
    resizeStartDistance = math.sqrt(
        (cursorX - resizeTopLeftX) ^ 2
        + (resizeTopLeftY - cursorY) ^ 2
    )
    if resizeStartDistance <= 0 then
        return
    end

    resizing = true
    resizeTracker:Show()
end

local function StopMove(save)
    if not moving then
        return
    end
    moving = false
    WorldMapFrame:StopMovingOrSizing()
    if save then
        SaveWindow()
        ApplySavedWindow()
        SavePosition()
    end
end

local function StartMove()
    if moving or resizing or IsMaximized()
        or not Addon:GetSetting("enableWorldMapResize")
    then
        return
    end
    moving = true
    WorldMapFrame:StartMoving()
end

local function ConfigureDragRegion(region, borderFrame)
    region:SetFrameStrata(borderFrame:GetFrameStrata())
    region:SetFrameLevel(borderFrame:GetFrameLevel() + 20)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", StartMove)
    region:SetScript("OnDragStop", function() StopMove(true) end)
    dragRegions[#dragRegions + 1] = region
end

local function CreateDragRegions(borderFrame)
    local top = CreateFrame("Button", nil, borderFrame)
    top:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 4, -2)
    top:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -64, -2)
    top:SetHeight(24)
    ConfigureDragRegion(top, borderFrame)
    topDragRegion = top

    local left = CreateFrame("Button", nil, borderFrame)
    left:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 0, -26)
    left:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMLEFT", 0, 8)
    left:SetWidth(8)
    ConfigureDragRegion(left, borderFrame)

    local right = CreateFrame("Button", nil, borderFrame)
    right:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", 0, -26)
    right:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", 0, 24)
    right:SetWidth(8)
    ConfigureDragRegion(right, borderFrame)

    local bottom = CreateFrame("Button", nil, borderFrame)
    bottom:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMLEFT", 4, 0)
    bottom:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -24, 0)
    bottom:SetHeight(8)
    ConfigureDragRegion(bottom, borderFrame)
end

local function CollapseAllQuestCategories()
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries
        or not C_QuestLog.GetInfo or type(CollapseQuestHeader) ~= "function"
    then
        return
    end

    local function RefreshQuestMap()
        if type(QuestMapFrame_UpdateAll) == "function" then
            QuestMapFrame_UpdateAll()
        end
    end

    local function CollapseNext(remaining)
        if remaining <= 0 then
            RefreshQuestMap()
            return
        end

        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for questLogIndex = numEntries, 1, -1 do
            local info = C_QuestLog.GetInfo(questLogIndex)
            if info and info.isHeader and not info.isCollapsed then
                CollapseQuestHeader(info.questLogIndex or questLogIndex)
                C_Timer.After(0, function()
                    CollapseNext(remaining - 1)
                end)
                return
            end
        end

        RefreshQuestMap()
    end

    CollapseNext(C_QuestLog.GetNumQuestLogEntries())
end

local function CreateCollapseCategoriesButton(borderFrame)
    collapseCategoriesButton = CreateFrame(
        "Button",
        "LiteToolsCollapseQuestCategoriesButton",
        borderFrame
    )
    collapseCategoriesButton:SetSize(20, 20)
    local maximizeFrame = borderFrame.MaximizeMinimizeFrame
    if maximizeFrame then
        collapseCategoriesButton:SetPoint(
            "RIGHT",
            maximizeFrame,
            "LEFT",
            0,
            0
        )
    else
        collapseCategoriesButton:SetPoint("TOPRIGHT", WorldMapFrame, -66, -3)
    end
    collapseCategoriesButton:SetFrameStrata("FULLSCREEN_DIALOG")
    collapseCategoriesButton:SetFrameLevel(100)
    local icon = collapseCategoriesButton:CreateTexture(
        nil,
        "OVERLAY",
        nil,
        7
    )
    icon:SetAllPoints()
    icon:SetAtlas("QuestLog-icon-shrink", false)
    local highlight = collapseCategoriesButton:CreateTexture(
        nil,
        "HIGHLIGHT",
        nil,
        7
    )
    highlight:SetAllPoints()
    highlight:SetAtlas("QuestLog-icon-shrink", false)
    highlight:SetBlendMode("ADD")
    collapseCategoriesButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            StopMove(false)
            WorldMapFrame:StopMovingOrSizing()
        end
    end)
    collapseCategoriesButton:SetScript("OnClick", function()
        if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        CollapseAllQuestCategories()
    end)
    collapseCategoriesButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Addon.L.COLLAPSE_QUEST_CATEGORIES_TOOLTIP)
        GameTooltip:Show()
    end)
    collapseCategoriesButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function RestoreDefaultWindow()
    if not initialized or not WorldMapFrame then
        return
    end

    StopResize(false)
    StopMove(false)
    WorldMapFrame:SetMovable(false)
    UpdateControlVisibility()
    if IsMaximized() then
        WorldMapFrame:SetScale(1)
        return
    end

    WorldMapFrame:SetScale(1)
    WorldMapFrame:SetSize(
        (tonumber(WorldMapFrame.minimizedWidth) or DEFAULT_WIDTH)
            + (WorldMapFrame.QuestLog and WorldMapFrame.QuestLog:IsShown()
                and (tonumber(WorldMapFrame.questLogWidth) or 0) or 0),
        tonumber(WorldMapFrame.minimizedHeight) or DEFAULT_HEIGHT
    )
    if WorldMapFrame.OnFrameSizeChanged then
        WorldMapFrame:OnFrameSizeChanged()
    end
    if WorldMapFrame.SynchronizeDisplayState then
        WorldMapFrame:SynchronizeDisplayState()
    end
end

local function InitializeWorldMap()
    if initialized or not WorldMapFrame then
        return
    end
    initialized = true

    local borderFrame = WorldMapFrame.BorderFrame or WorldMapFrame
    resizeButton = CreateFrame(
        "Button",
        "LiteToolsWorldMapResizeButton",
        borderFrame,
        "PanelResizeButtonTemplate"
    )
    resizeButton:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -4, 4)
    resizeButton:SetSize(20, 20)
    resizeButton:SetFrameStrata(borderFrame:GetFrameStrata())
    resizeButton:SetFrameLevel(borderFrame:GetFrameLevel() + 30)
    resizeButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartResize() end
    end)
    resizeButton:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopResize(true) end
    end)

    resizeTracker = CreateFrame("Frame")
    resizeTracker:Hide()
    resizeTracker:SetScript("OnUpdate", UpdateResize)
    CreateDragRegions(borderFrame)
    CreateCollapseCategoriesButton(borderFrame)
    if not CreateDirectionLine() then
        QueueDirectionLineCreation()
    end

    WorldMapFrame:HookScript("OnShow", function()
        QueueApply()
        if not CreateDirectionLine() then
            QueueDirectionLineCreation()
        end
    end)
    WorldMapFrame:HookScript("OnHide", function()
        StopResize(false)
        StopMove(false)
        if Addon:GetSetting("enableWorldMapResize") then
            SaveWindow()
        end
    end)
    hooksecurefunc(WorldMapFrame, "Maximize", QueueApply)
    hooksecurefunc(WorldMapFrame, "Minimize", QueueApply)
    hooksecurefunc(WorldMapFrame, "SetQuestLogPanelShown", QueueApply)

    ApplySavedWindow()
end

Addon:RegisterDatabaseMigration(function(db)
    if db.worldMapScale == nil and type(db.worldMapSize) == "table" then
        local width = tonumber(db.worldMapSize.width)
        local height = tonumber(db.worldMapSize.height)
        if width and height and width > 0 and height > 0 then
            db.worldMapScale = SanitizeScale(math.min(
                width / DEFAULT_WIDTH,
                height / DEFAULT_HEIGHT
            ))
        end
    end
    db.worldMapSize = nil
end)

Addon:RegisterSetting(
    "enableWorldMapResize",
    false,
    Addon.BooleanSetting,
    function(value)
        InitializeWorldMap()
        if value then
            QueueApply()
        else
            RestoreDefaultWindow()
        end
    end
)
Addon:RegisterSetting("worldMapScale", 1, SanitizeScale)
Addon:RegisterSetting("worldMapPosition", nil, Addon.PositionSetting)
Addon:RegisterSetting(
    "showCollapseQuestCategoriesButton",
    false,
    Addon.BooleanSetting,
    function()
        InitializeWorldMap()
        UpdateControlVisibility()
    end
)
Addon:RegisterSetting(
    "enableWorldMapDirectionLine",
    false,
    Addon.BooleanSetting,
    function()
        InitializeWorldMap()
        if not CreateDirectionLine() then
            QueueDirectionLineCreation()
        end
        UpdateDirectionLineVisibility()
    end
)

local function HasWorldMapFeature(db)
    return db.enableWorldMapResize or db.showCollapseQuestCategoriesButton
        or db.enableWorldMapDirectionLine
end

Addon:RegisterEvent("PLAYER_LOGIN", function()
    InitializeWorldMap()
end, HasWorldMapFeature)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", QueueApply, function(db)
    return db.enableWorldMapResize
end)
Addon:RegisterEvent("DISPLAY_SIZE_CHANGED", QueueApply, function(db)
    return db.enableWorldMapResize
end)
Addon:RegisterEvent("UI_SCALE_CHANGED", QueueApply, function(db)
    return db.enableWorldMapResize
end)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_WorldMap" then
        InitializeWorldMap()
    end
end, HasWorldMapFeature)
