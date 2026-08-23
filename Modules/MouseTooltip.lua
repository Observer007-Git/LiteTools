local _, Addon = ...
local L = Addon.L

local CURSOR_GAP = 12
local INSPECT_RETRY_SECONDS = 3
local TOOLTIP_HIDE_DELAY = 0.06
local INSPECT_PVP_ITEM_LEVEL_CACHE_SECONDS = 30
local EQUIPPED_ITEM_LEVEL_SLOT_COUNT = 16
local INSPECT_EQUIPMENT_SLOTS = {
    1, 2, 3, 5, 6, 7, 8, 9,
    10, 11, 12, 13, 14, 15, 16, 17,
}
local ANCHOR_POINTS = {
    TOP = { "BOTTOM", "TOP", 0, CURSOR_GAP },
    BOTTOM = { "TOP", "BOTTOM", 0, -CURSOR_GAP },
    LEFT = { "RIGHT", "LEFT", -CURSOR_GAP, 0 },
    RIGHT = { "LEFT", "RIGHT", CURSOR_GAP, 0 },
    TOPLEFT = { "BOTTOMRIGHT", "TOPLEFT", -CURSOR_GAP, CURSOR_GAP },
    BOTTOMLEFT = { "TOPRIGHT", "BOTTOMLEFT", -CURSOR_GAP, -CURSOR_GAP },
    TOPRIGHT = { "BOTTOMLEFT", "TOPRIGHT", CURSOR_GAP, CURSOR_GAP },
    BOTTOMRIGHT = { "TOPLEFT", "BOTTOMRIGHT", CURSOR_GAP, -CURSOR_GAP },
}

local function SanitizeAnchor(value)
    return ANCHOR_POINTS[value] and value or "BOTTOMRIGHT"
end

local cursorAnchor = CreateFrame(
    "Frame",
    "LiteToolsMouseTooltipCursorAnchor",
    UIParent
)
cursorAnchor:SetSize(1, 1)
cursorAnchor:Hide()

local trackedOwner
local ownerWasUnderMouse = false
local unitWasUnderMouse = false
local mouseLostElapsed = 0
local pendingInspectGUID
local lastInspectRequest = 0
local healthValueText
local factionIconTexture
local trackedHealthUnit
local lastCursorX
local lastCursorY
local lastCursorScale
local mountSpellCache = {}
local cachedPvpItemLevelGUID
local cachedPvpItemLevelRegular
local cachedPvpItemLevel
local cachedPvpItemLevelTime = 0
local pvpItemLevelPattern

local function ResetTooltipTracking()
    trackedOwner = GameTooltip and GameTooltip:GetOwner() or nil
    ownerWasUnderMouse = false
    unitWasUnderMouse = false
    mouseLostElapsed = 0
end

local function ShouldHideTooltip(elapsed)
    local owner = GameTooltip:GetOwner()
    if owner ~= trackedOwner then
        trackedOwner = owner
        ownerWasUnderMouse = false
        unitWasUnderMouse = false
        mouseLostElapsed = 0
    end

    local worldOwned = not owner
        or owner == UIParent
        or owner == WorldFrame
    if worldOwned then
        if UnitExists("mouseover") then
            unitWasUnderMouse = true
            mouseLostElapsed = 0
        elseif unitWasUnderMouse then
            mouseLostElapsed = mouseLostElapsed + elapsed
            return mouseLostElapsed >= TOOLTIP_HIDE_DELAY
        end
        return false
    end

    if owner.IsMouseOver then
        local isMouseOver = owner:IsMouseOver()
        if isMouseOver then
            ownerWasUnderMouse = true
            mouseLostElapsed = 0
        elseif ownerWasUnderMouse then
            mouseLostElapsed = mouseLostElapsed + elapsed
            return mouseLostElapsed >= TOOLTIP_HIDE_DELAY
        end
    end
    return false
end

local function AnchorGameTooltip()
    if not Addon:GetSetting("enableMouseTooltipFollow") then return end
    if not GameTooltip or not GameTooltip:IsShown() then return end
    if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end

    local anchor = ANCHOR_POINTS[Addon:GetSetting("mouseTooltipAnchor")]
        or ANCHOR_POINTS.BOTTOMRIGHT
    local point, relativeTo, relativePoint = GameTooltip:GetPoint(1)
    if GameTooltip:GetNumPoints() == 1
        and point == anchor[1]
        and relativeTo == cursorAnchor
        and relativePoint == anchor[2]
    then
        return
    end

    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint(
        anchor[1],
        cursorAnchor,
        anchor[2],
        anchor[3],
        anchor[4]
    )
    GameTooltip:SetClampedToScreen(true)
end

local function UpdateCursorAnchor()
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale <= 0 then return end

    local cursorX, cursorY = GetCursorPosition()
    if cursorX == lastCursorX
        and cursorY == lastCursorY
        and uiScale == lastCursorScale
    then
        return
    end

    lastCursorX = cursorX
    lastCursorY = cursorY
    lastCursorScale = uiScale
    cursorAnchor:ClearAllPoints()
    cursorAnchor:SetPoint(
        "CENTER",
        UIParent,
        "BOTTOMLEFT",
        cursorX / uiScale,
        cursorY / uiScale
    )
end

if hooksecurefunc and GameTooltip_SetDefaultAnchor then
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
        if tooltip ~= GameTooltip
            or not Addon:GetSetting("enableMouseTooltipFollow")
        then
            return
        end
        cursorAnchor:Show()
        UpdateCursorAnchor()
        AnchorGameTooltip()
    end)
end

cursorAnchor:SetScript("OnUpdate", function(_, elapsed)
    if not GameTooltip or not GameTooltip:IsShown() then return end
    UpdateCursorAnchor()
    if ShouldHideTooltip(elapsed) then
        GameTooltip:Hide()
        return
    end
    AnchorGameTooltip()
end)

GameTooltip:HookScript("OnShow", function()
    if not Addon:GetSetting("enableMouseTooltipFollow") then return end
    ResetTooltipTracking()
    cursorAnchor:Show()
    UpdateCursorAnchor()
    AnchorGameTooltip()
end)
GameTooltip:HookScript("OnHide", function()
    cursorAnchor:Hide()
    ResetTooltipTracking()
    if healthValueText then
        healthValueText:Hide()
    end
    if factionIconTexture then
        factionIconTexture:Hide()
    end
    trackedHealthUnit = nil
    GameTooltip.liteToolsMountLineAdded = nil
    GameTooltip.liteToolsTargetOfTargetLineAdded = nil
end)
GameTooltip:HookScript("OnTooltipCleared", function()
    if factionIconTexture then
        factionIconTexture:Hide()
    end
    trackedHealthUnit = nil
    GameTooltip.liteToolsMountLineAdded = nil
    GameTooltip.liteToolsTargetOfTargetLineAdded = nil
end)

local ROLE_ATLASES = {
    TANK = "icons_64x64_tank",
    HEALER = "icons_16x16_heal",
    DAMAGER = "icons_64x64_damage",
}
local ROLE_LABELS = {
    TANK = L.MOUSE_TOOLTIP_ROLE_TANK,
    HEALER = L.MOUSE_TOOLTIP_ROLE_HEALER,
    DAMAGER = L.MOUSE_TOOLTIP_ROLE_DAMAGE,
}
local FACTION_ATLASES = {
    Alliance = "charcreatetest-logo-alliance",
    Horde = "charcreatetest-logo-horde",
}

local function IsAccessible(value)
    if value == nil then return false end
    if canaccessvalue then
        local ok, accessible = pcall(canaccessvalue, value)
        return ok and accessible
    end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        return ok and not secret
    end
    return true
end

local function IsAccessibleTable(value)
    if not IsAccessible(value) then return false end
    if canaccesstable then
        local ok, accessible = pcall(canaccesstable, value)
        return ok and accessible
    end
    return type(value) == "table"
end

local function IsAccessibleNumber(value)
    return IsAccessible(value) and type(value) == "number"
end

local function GetPvpItemLevelPattern()
    if pvpItemLevelPattern ~= nil then
        return pvpItemLevelPattern or nil
    end

    pvpItemLevelPattern = false
    local formatText = PVP_ITEM_LEVEL_TOOLTIP
    if not IsAccessible(formatText) or type(formatText) ~= "string" then
        return nil
    end

    local marker = "\001"
    local markedText, replacements = formatText:gsub(
        "%%%d*%$?[ds]",
        marker,
        1
    )
    if replacements ~= 1 then return nil end

    markedText = markedText:gsub(
        "([%(%)%.%%%+%-%*%?%[%]%^%$])",
        "%%%1"
    )
    pvpItemLevelPattern = "^"
        .. markedText:gsub(marker, "([0-9]+)")
        .. "$"
    return pvpItemLevelPattern
end

local function SafeUnitTest(test, unit, ...)
    if not test or not IsAccessible(unit) then return false end
    local ok, result = pcall(test, unit, ...)
    return ok and IsAccessible(result) and result == true
end

local function GetTooltipUnit(tooltip)
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not IsAccessible(unit) or type(unit) ~= "string" then
        return nil
    end
    if not SafeUnitTest(UnitExists, unit) then return nil end
    return unit
end

local function GetUnitGUIDSafely(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and IsAccessible(guid) and type(guid) == "string" then
        return guid
    end
    return nil
end

local function ResolveTooltipHealthUnit(tooltip, tooltipData)
    local unit = GetTooltipUnit(tooltip)
    if unit then return unit end

    local healthGUID = tooltipData and tooltipData.healthGUID
    if not UnitTokenFromGUID or not IsAccessible(healthGUID) then return nil end
    local ok, resolvedUnit = pcall(UnitTokenFromGUID, healthGUID)
    if not ok
        or not IsAccessible(resolvedUnit)
        or type(resolvedUnit) ~= "string"
        or not SafeUnitTest(UnitExists, resolvedUnit)
    then
        return nil
    end
    return resolvedUnit
end

local function TooltipHasLabel(tooltip, label)
    local tooltipName = tooltip:GetName()
    if not tooltipName then return false end

    for index = 1, tooltip:NumLines() do
        local line = _G[tooltipName .. "TextLeft" .. index]
        local text = line and line:GetText()
        if IsAccessible(text)
            and type(text) == "string"
            and text:find(label, 1, true)
        then
            return true
        end
    end
    return false
end

local function GetInventoryItemLinkSafely(unit, slot)
    if not GetInventoryItemLink then return nil, false end
    local ok, itemLink = pcall(GetInventoryItemLink, unit, slot)
    if not ok then return nil, false end
    if itemLink == nil then return nil, true end
    if not IsAccessible(itemLink) or type(itemLink) ~= "string" then
        return nil, false
    end
    return itemLink, true
end

local function GetInventoryPvpItemLevel(unit, slot)
    local getInventoryItem = C_TooltipInfo
        and C_TooltipInfo.GetInventoryItem
    local pattern = GetPvpItemLevelPattern()
    if not getInventoryItem or not pattern then return nil, false end

    local ok, tooltipData = pcall(getInventoryItem, unit, slot)
    if not ok or not IsAccessibleTable(tooltipData) then
        return nil, false
    end
    local lines = tooltipData.lines
    if not IsAccessibleTable(lines) then return nil, false end

    for index = 1, #lines do
        local line = lines[index]
        if not IsAccessibleTable(line) then return nil, false end
        local text = line.leftText
        if text ~= nil then
            if not IsAccessible(text) or type(text) ~= "string" then
                return nil, false
            end
            local itemLevelText = text:match(pattern)
            if itemLevelText then
                local itemLevel = tonumber(itemLevelText)
                if itemLevel and itemLevel > 0 then
                    return itemLevel, true
                end
            end
        end
    end
    return nil, true
end

local function GetItemLevelAndWeight(itemLink, slot, hasOffHand)
    local getDetailedItemLevel = C_Item
        and C_Item.GetDetailedItemLevelInfo
    if not getDetailedItemLevel then return nil end

    local levelOK, itemLevel = pcall(getDetailedItemLevel, itemLink)
    if not levelOK or not IsAccessibleNumber(itemLevel) or itemLevel <= 0 then
        return nil
    end

    local weight = 1
    if slot == 16 and not hasOffHand and C_Item.GetItemInfoInstant then
        local infoOK, _, _, _, equipLocation = pcall(
            C_Item.GetItemInfoInstant,
            itemLink
        )
        if not infoOK
            or not IsAccessible(equipLocation)
            or type(equipLocation) ~= "string"
        then
            return nil
        end
        if equipLocation == "INVTYPE_2HWEAPON"
            or equipLocation == "INVTYPE_RANGED"
            or equipLocation == "INVTYPE_RANGEDRIGHT"
        then
            weight = 2
        end
    end
    return itemLevel, weight
end

local function CalculateInspectPvpItemLevel(unit, regularItemLevel)
    local guid = GetUnitGUIDSafely(unit)
    local now = GetTime()
    if guid
        and guid == cachedPvpItemLevelGUID
        and regularItemLevel == cachedPvpItemLevelRegular
        and now - cachedPvpItemLevelTime
            < INSPECT_PVP_ITEM_LEVEL_CACHE_SECONDS
    then
        return cachedPvpItemLevel
    end

    local itemLinks = {}
    for _, slot in ipairs(INSPECT_EQUIPMENT_SLOTS) do
        local itemLink, linkReadable = GetInventoryItemLinkSafely(unit, slot)
        if not linkReadable then return nil end
        itemLinks[slot] = itemLink
    end

    local itemLevelDelta = 0
    local hasOffHand = itemLinks[17] ~= nil
    for _, slot in ipairs(INSPECT_EQUIPMENT_SLOTS) do
        local itemLink = itemLinks[slot]
        if itemLink then
            local pvpItemLevel, tooltipReadable =
                GetInventoryPvpItemLevel(unit, slot)
            if not tooltipReadable then return nil end
            if pvpItemLevel then
                local itemLevel, weight = GetItemLevelAndWeight(
                    itemLink,
                    slot,
                    hasOffHand
                )
                if not itemLevel then return nil end
                itemLevelDelta = itemLevelDelta
                    + (pvpItemLevel - itemLevel) * weight
            end
        end
    end

    local pvpItemLevel = regularItemLevel
        + itemLevelDelta / EQUIPPED_ITEM_LEVEL_SLOT_COUNT
    if guid then
        cachedPvpItemLevelGUID = guid
        cachedPvpItemLevelRegular = regularItemLevel
        cachedPvpItemLevel = pvpItemLevel
        cachedPvpItemLevelTime = now
    end
    return pvpItemLevel
end

local function GetUnitItemLevels(unit, includePvpItemLevel)
    if SafeUnitTest(UnitIsUnit, unit, "player") then
        local ok, _, equippedItemLevel, pvpItemLevel =
            pcall(GetAverageItemLevel)
        if ok and IsAccessibleNumber(equippedItemLevel)
            and equippedItemLevel > 0
        then
            if includePvpItemLevel
                and IsAccessibleNumber(pvpItemLevel)
                and pvpItemLevel > 0
            then
                return equippedItemLevel, pvpItemLevel
            end
            return equippedItemLevel, nil
        end
        return nil
    end
    local getInspectItemLevel = C_PaperDollInfo
        and C_PaperDollInfo.GetInspectItemLevel
    if not getInspectItemLevel then return nil end

    local ok, itemLevel = pcall(getInspectItemLevel, unit)
    if ok and IsAccessibleNumber(itemLevel) and itemLevel > 0 then
        if includePvpItemLevel then
            return itemLevel, CalculateInspectPvpItemLevel(unit, itemLevel)
        end
        return itemLevel, nil
    end
    return nil
end

local function AddItemLevelLine(tooltip, itemLevel, pvpItemLevel)
    if TooltipHasLabel(tooltip, L.MOUSE_TOOLTIP_ITEM_LEVEL_LABEL) then return end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[4]
    local text = string.format(
        L.MOUSE_TOOLTIP_ITEM_LEVEL_FORMAT,
        math.floor(itemLevel + 0.5)
    )
    if pvpItemLevel then
        local pvpIcon = CreateAtlasMarkup(
            "questlog-questtypeicon-pvp",
            14,
            14
        )
        text = text
            .. "  |cffffd100(|r"
            .. pvpIcon
            .. string.format(
                L.MOUSE_TOOLTIP_PVP_ITEM_LEVEL_FORMAT,
                math.floor(pvpItemLevel + 0.5)
            )
            .. "|cffffd100)|r"
    end
    tooltip:AddLine(
        text,
        color and color.r or 0.64,
        color and color.g or 0.21,
        color and color.b or 0.93
    )
end

local function GetUnitSpecialization(unit)
    if SafeUnitTest(UnitIsUnit, unit, "player") then
        local ok, index = pcall(GetSpecialization)
        if not ok or not IsAccessibleNumber(index) or index <= 0 then
            return nil
        end
        local infoOK, specID, name, _, icon, role = pcall(
            GetSpecializationInfo,
            index
        )
        if not infoOK
            or not IsAccessibleNumber(specID)
            or not IsAccessible(name)
            or type(name) ~= "string"
        then
            return nil
        end
        return specID,
            name,
            IsAccessible(icon) and icon or nil,
            IsAccessible(role) and role or nil
    end
    local getInspectSpecialization = C_SpecializationInfo
        and C_SpecializationInfo.GetInspectSpecialization
    if not getInspectSpecialization then return nil end
    local ok, specID = pcall(getInspectSpecialization, unit)
    if not ok or not IsAccessibleNumber(specID) or specID <= 0 then
        return nil
    end

    local infoOK, _, name, _, icon, role = pcall(
        GetSpecializationInfoByID,
        specID
    )
    if not infoOK
        or not IsAccessible(name)
        or type(name) ~= "string"
    then
        return nil
    end
    return specID,
        name,
        IsAccessible(icon) and icon or nil,
        IsAccessible(role) and role or nil
end

local function AddSpecializationIcons(tooltip, unit, specName, specIcon, role)
    local roleMarkup = ""
    if ROLE_ATLASES[role] and CreateAtlasMarkup then
        roleMarkup = CreateAtlasMarkup(ROLE_ATLASES[role], 16, 16)
    end
    local roleLabel = ROLE_LABELS[role] or ""

    local specMarkup = ""
    if IsAccessibleNumber(specIcon) then
        specMarkup = string.format("|T%d:16:16|t", specIcon)
    end
    local className
    local classFilename
    local classOK, localizedClassName, resolvedClassFilename = pcall(
        UnitClass,
        unit
    )
    if classOK
        and IsAccessible(localizedClassName)
        and type(localizedClassName) == "string"
    then
        className = localizedClassName
    end
    if classOK
        and IsAccessible(resolvedClassFilename)
        and type(resolvedClassFilename) == "string"
    then
        classFilename = resolvedClassFilename
    end

    local classMarkup = ""
    if classFilename and GetClassAtlas and CreateAtlasMarkup then
        local atlasOK, classAtlas = pcall(GetClassAtlas, classFilename)
        if atlasOK
            and IsAccessible(classAtlas)
            and type(classAtlas) == "string"
        then
            local markupOK, markup = pcall(
                CreateAtlasMarkup,
                classAtlas,
                14,
                14
            )
            if markupOK and IsAccessible(markup) and type(markup) == "string" then
                classMarkup = markup
            end
        end
    end
    if roleMarkup == "" and specMarkup == "" and classMarkup == "" then return end

    local tooltipName = tooltip:GetName()
    if not tooltipName then return end
    local classLine
    local classLineText
    for index = 2, tooltip:NumLines() do
        local line = _G[tooltipName .. "TextLeft" .. index]
        local text = line and line:GetText()
        if IsAccessible(text) and type(text) == "string" then
            local hasRoleIcon = roleMarkup == ""
                or text:find(roleMarkup, 1, true)
            local hasSpecIcon = specMarkup == ""
                or text:find(specMarkup, 1, true)
            local hasClassIcon = classMarkup == ""
                or text:find(classMarkup, 1, true)
            if hasRoleIcon and hasSpecIcon and hasClassIcon then return end

            local specStart = text:find(specName, 1, true)
            if specStart then
                local updatedText = text
                if specMarkup ~= "" and not hasSpecIcon then
                    updatedText = text:sub(1, specStart - 1)
                        .. specMarkup
                        .. " "
                        .. text:sub(specStart)
                end
                local classStart
                if className then
                    classStart = updatedText:find(className, 1, true)
                end
                if classStart and classMarkup ~= "" and not hasClassIcon then
                    updatedText = updatedText:sub(1, classStart - 1)
                        .. classMarkup
                        .. " "
                        .. updatedText:sub(classStart)
                end
                if roleMarkup ~= "" and not hasRoleIcon then
                    updatedText = roleMarkup
                        .. roleLabel
                        .. " "
                        .. updatedText
                end
                line:SetText(updatedText)
                return
            end
            if not classLine
                and className
                and text:find(className, 1, true)
            then
                classLine = line
                classLineText = text
            end
        end
    end
    if classLine then
        local updatedText = classLineText
        local classStart = updatedText:find(className, 1, true)
        if classStart
            and classMarkup ~= ""
            and not updatedText:find(classMarkup, 1, true)
        then
            updatedText = updatedText:sub(1, classStart - 1)
                .. classMarkup
                .. " "
                .. updatedText:sub(classStart)
        end
        local prefix = ""
        if roleMarkup ~= "" and not updatedText:find(roleMarkup, 1, true) then
            prefix = prefix .. roleMarkup .. roleLabel .. " "
        end
        if specMarkup ~= "" and not updatedText:find(specMarkup, 1, true) then
            prefix = prefix .. specMarkup .. " "
        end
        if prefix ~= "" then
            updatedText = prefix .. updatedText
        end
        classLine:SetText(updatedText)
    end
end

local function QueryMountInfo(mountID)
    local name, _, icon, _, _, _, _, _, _, _, isCollected =
        C_MountJournal.GetMountInfoByID(mountID)
    return name, icon, isCollected
end

local function GetMountSource(mountID)
    if not C_MountJournal
        or not C_MountJournal.GetMountInfoExtraByID
        or not IsAccessibleNumber(mountID)
    then
        return nil
    end

    local ok, _, _, source = pcall(
        C_MountJournal.GetMountInfoExtraByID,
        mountID
    )
    if not ok
        or not IsAccessible(source)
        or type(source) ~= "string"
        or source == ""
    then
        return nil
    end
    return source
end

local function GetUnitMountInfo(unit)
    if not AuraUtil
        or not AuraUtil.ForEachAura
        or not C_MountJournal
        or not C_MountJournal.GetMountFromSpell
        or not C_MountJournal.GetMountInfoByID
    then
        return nil
    end

    local mountName, mountIcon, mountCollected, resolvedMountID
    local function CheckAura(aura)
        if not IsAccessibleTable(aura) then return false end
        local spellID = aura.spellId
        if not IsAccessibleNumber(spellID) then return false end

        local mountID = mountSpellCache[spellID]
        if mountID == nil then
            local mountOK, resolvedMountID = pcall(
                C_MountJournal.GetMountFromSpell,
                spellID
            )
            if mountOK
                and IsAccessibleNumber(resolvedMountID)
                and resolvedMountID > 0
            then
                mountID = resolvedMountID
            else
                mountID = false
            end
            mountSpellCache[spellID] = mountID
        end
        if not mountID then return false end

        local infoOK, name, icon, isCollected = pcall(QueryMountInfo, mountID)
        if not infoOK
            or not IsAccessible(name)
            or type(name) ~= "string"
            or not IsAccessibleNumber(icon)
            or not IsAccessible(isCollected)
            or type(isCollected) ~= "boolean"
        then
            return true
        end
        mountName = name
        mountIcon = icon
        mountCollected = isCollected
        resolvedMountID = mountID
        return true
    end

    local ok = pcall(
        AuraUtil.ForEachAura,
        unit,
        "HELPFUL",
        nil,
        CheckAura,
        true
    )
    if not ok or not mountName then return nil end
    return mountName, mountIcon, mountCollected, resolvedMountID
end

local function AddMountLine(tooltip, unit)
    if not Addon:GetSetting("showMouseTooltipMount")
        or tooltip.liteToolsMountLineAdded
    then
        return
    end

    local mountName, mountIcon, isCollected, mountID = GetUnitMountInfo(unit)
    if not mountName then return end

    local statusMarkup
    if isCollected then
        statusMarkup = CreateAtlasMarkup(
            "common-icon-checkmark-yellow",
            14,
            14,
            0,
            0,
            0,
            255,
            0
        )
    else
        statusMarkup = CreateAtlasMarkup("common-icon-redx", 14, 14)
        if RED_FONT_COLOR and RED_FONT_COLOR.WrapTextInColorCode then
            mountName = RED_FONT_COLOR:WrapTextInColorCode(mountName)
        else
            mountName = "|cffff2020" .. mountName .. "|r"
        end
    end
    local mountMarkup = CreateSimpleTextureMarkup(mountIcon, 14, 14)
    tooltip:AddLine(statusMarkup .. mountMarkup .. " " .. mountName, 1, 1, 1)
    if not isCollected and Addon:GetSetting("showMouseTooltipMountSource") then
        local source = GetMountSource(mountID)
        if source then
            source = source
                :gsub("|c%x%x%x%x%x%x%x%x", "")
                :gsub("|cn[%w_]+:", "")
                :gsub("|r", "")
            tooltip:AddLine(
                string.format(L.MOUSE_TOOLTIP_MOUNT_SOURCE_FORMAT, source),
                0.8,
                0.8,
                0.8,
                true
            )
        end
    end
    tooltip.liteToolsMountLineAdded = true
end

local function WrapWithColor(text, color)
    if color and color.WrapTextInColorCode then
        return color:WrapTextInColorCode(text)
    end
    return text
end

local function GetUnitRole(unit)
    if UnitGroupRolesAssigned then
        local roleOK, role = pcall(UnitGroupRolesAssigned, unit)
        if roleOK and IsAccessible(role) and ROLE_ATLASES[role] then
            return role
        end
    end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local _, _, _, specializationRole = GetUnitSpecialization(unit)
    return ROLE_ATLASES[specializationRole] and specializationRole or nil
end

local function AddTargetOfTargetLine(tooltip, unit)
    if not Addon:GetSetting("showMouseTooltipTargetOfTarget")
        or tooltip.liteToolsTargetOfTargetLineAdded
        or type(unit) ~= "string"
    then
        return
    end

    local targetUnit = unit .. "target"
    if not SafeUnitTest(UnitExists, targetUnit) then return end

    local roleMarkup = ""
    local nameText
    if SafeUnitTest(UnitIsUnit, targetUnit, "player") then
        nameText = "|cffff2020"
            .. L.MOUSE_TOOLTIP_TARGET_OF_TARGET_SELF
            .. "|r"
    else
        local nameOK, unitName = pcall(UnitName, targetUnit)
        if not nameOK
            or not IsAccessible(unitName)
            or type(unitName) ~= "string"
            or unitName == ""
        then
            return
        end
        nameText = unitName
    end

    if SafeUnitTest(UnitIsPlayer, targetUnit) then
        local role = GetUnitRole(targetUnit)
        if role and CreateAtlasMarkup then
            roleMarkup = CreateAtlasMarkup(ROLE_ATLASES[role], 16, 16)
        end
        if not SafeUnitTest(UnitIsUnit, targetUnit, "player") then
            local classOK, _, classFilename = pcall(UnitClass, targetUnit)
            if classOK
                and IsAccessible(classFilename)
                and type(classFilename) == "string"
            then
                local color = RAID_CLASS_COLORS
                    and RAID_CLASS_COLORS[classFilename]
                nameText = WrapWithColor(nameText, color)
            end
        end
    end

    tooltip:AddLine(string.format(
        L.MOUSE_TOOLTIP_TARGET_OF_TARGET_FORMAT,
        roleMarkup .. nameText
    ))
    tooltip.liteToolsTargetOfTargetLineAdded = true
end

local function ApplyClassColor(tooltip, unit)
    if not Addon:GetSetting("showMouseTooltipClassColor") then return end
    local ok, className, classFilename = pcall(UnitClass, unit)
    if not ok
        or not IsAccessible(className)
        or not IsAccessible(classFilename)
        or type(className) ~= "string"
        or type(classFilename) ~= "string"
    then
        return
    end

    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if not color then return end
    local tooltipName = tooltip:GetName() or "GameTooltip"
    local nameLine = _G[tooltipName .. "TextLeft1"]
    if nameLine then
        nameLine:SetTextColor(color.r, color.g, color.b)
    end

    local guildName
    if GetGuildInfo then
        local guildOK, targetGuildName = pcall(GetGuildInfo, unit)
        if guildOK
            and IsAccessible(targetGuildName)
            and type(targetGuildName) == "string"
            and targetGuildName ~= ""
        then
            guildName = targetGuildName
        end
    end

    for index = 2, tooltip:NumLines() do
        local line = _G[tooltipName .. "TextLeft" .. index]
        local text = line and line:GetText()
        if IsAccessible(text) and type(text) == "string" then
            if guildName and text:find(guildName, 1, true) then
                local nameStart, nameEnd = text:find(guildName, 1, true)
                local before = text:sub(1, nameStart - 1)
                local after = text:sub(nameEnd + 1)
                if before:sub(-1) ~= "<" then
                    before = before .. "<"
                end
                if after:sub(1, 1) ~= ">" then
                    after = ">" .. after
                end
                line:SetText(before .. guildName .. after)
                line:SetTextColor(0, 1, 0)
            elseif text:find(className, 1, true) then
                line:SetTextColor(color.r, color.g, color.b)
            end
        end
    end
end

local function UpdateFactionIcon(tooltip, unit)
    if factionIconTexture then
        factionIconTexture:Hide()
    end
    if not Addon:GetSetting("showMouseTooltipFactionIcon") or not unit then
        return
    end

    local ok, faction = pcall(UnitFactionGroup, unit)
    if not ok
        or not IsAccessible(faction)
        or type(faction) ~= "string"
        or not FACTION_ATLASES[faction]
    then
        return
    end

    if not factionIconTexture then
        factionIconTexture = tooltip:CreateTexture(nil, "BORDER", nil, 7)
        factionIconTexture:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", 0, 0)
        factionIconTexture:SetSize(56, 56)
        factionIconTexture:SetAlpha(0.85)
    end
    factionIconTexture:SetAtlas(FACTION_ATLASES[faction], false)
    factionIconTexture:Show()
end

local function GetHighestSeasonKeystoneLevel(summary)
    if not IsAccessibleTable(summary.runs) then return nil end
    local highestLevel
    for _, run in ipairs(summary.runs) do
        if IsAccessibleTable(run) then
            local level = run.bestRunLevel
            local finishedSuccess = run.finishedSuccess
            if IsAccessibleNumber(level)
                and IsAccessible(finishedSuccess)
                and finishedSuccess == true
                and level > 0
            then
                highestLevel = highestLevel and math.max(highestLevel, level)
                    or level
            end
        end
    end
    return highestLevel and math.floor(highestLevel) or nil
end

local function AddMythicRatingLine(tooltip, unit)
    if not Addon:GetSetting("showMouseTooltipMythicRating") then return end
    if TooltipHasLabel(tooltip, L.MOUSE_TOOLTIP_MYTHIC_RATING_LABEL) then return end
    local getRating = C_PlayerInfo
        and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
    if not getRating then return end

    local ok, summary = pcall(getRating, unit)
    if not ok or not IsAccessibleTable(summary) then return end
    local score = summary.currentSeasonScore
    if not IsAccessibleNumber(score) or score <= 0 then return end
    local highestLevel = GetHighestSeasonKeystoneLevel(summary)
    local keystoneText = highestLevel
        and string.format(L.MOUSE_TOOLTIP_KEYSTONE_LEVEL_FORMAT, highestLevel)
        or ""
    tooltip:AddLine(
        string.format(
            L.MOUSE_TOOLTIP_MYTHIC_RATING_FORMAT,
            math.floor(score + 0.5),
            keystoneText
        ),
        0.2,
        0.8,
        1
    )
end

local function GetHealthValueText(tooltip)
    local statusBar = tooltip.StatusBar or _G.GameTooltipStatusBar
    if not statusBar or not statusBar.CreateFontString then return nil end
    if not healthValueText then
        healthValueText = statusBar:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )
        healthValueText:SetDrawLayer("OVERLAY", 7)
        healthValueText:SetPoint("CENTER")
        healthValueText:SetShadowOffset(1, -1)
        local fontFile, fontSize, fontFlags = healthValueText:GetFont()
        if fontFile and fontSize then
            healthValueText:SetFont(
                fontFile,
                math.max(8, fontSize - 2),
                fontFlags
            )
        end
    end
    return healthValueText
end

local function UpdateHealthText(tooltip, unit)
    if not Addon:GetSetting("showMouseTooltipHealth") then
        if healthValueText then healthValueText:Hide() end
        return
    end
    local valueText = GetHealthValueText(tooltip)
    if not valueText then return end
    valueText:Hide()
    if not unit then return end

    local currentOK, currentHealth = pcall(UnitHealth, unit)
    local maximumOK, maximumHealth = pcall(UnitHealthMax, unit)
    if not currentOK or not maximumOK then return end

    if IsAccessibleNumber(currentHealth)
        and IsAccessibleNumber(maximumHealth)
    then
        if maximumHealth <= 0 then return end
        valueText:SetText(string.format(
            L.MOUSE_TOOLTIP_HEALTH_FORMAT,
            currentHealth / 1000,
            maximumHealth / 1000
        ))
        valueText:Show()
        return
    end

    if not AbbreviateNumbers then return end
    local currentTextOK, currentText = pcall(AbbreviateNumbers, currentHealth)
    local maximumTextOK, maximumText = pcall(AbbreviateNumbers, maximumHealth)
    if not currentTextOK or not maximumTextOK then return end

    valueText:Show()
    local setTextOK = pcall(
        valueText.SetFormattedText,
        valueText,
        "%s/%s",
        currentText,
        maximumText
    )
    if not setTextOK then
        valueText:Hide()
    end
end

local function RequestInspect(unit)
    if not CanInspect or not NotifyInspect then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local inspectOK, canInspect = pcall(CanInspect, unit, false)
    if not inspectOK or not IsAccessible(canInspect) or not canInspect then return end

    local guid = GetUnitGUIDSafely(unit)
    if not guid then return end
    local now = GetTime()
    if pendingInspectGUID == guid
        and now - lastInspectRequest < INSPECT_RETRY_SECONDS
    then
        return
    end

    local ok = pcall(NotifyInspect, unit)
    if ok then
        pendingInspectGUID = guid
        lastInspectRequest = now
    end
end

local function AddTargetDetails(tooltip, tooltipData)
    if tooltip ~= GameTooltip then return end
    local unit = ResolveTooltipHealthUnit(tooltip, tooltipData)
    trackedHealthUnit = unit
    UpdateFactionIcon(tooltip, unit)
    AddTargetOfTargetLine(tooltip, unit)
    if not unit or not SafeUnitTest(UnitIsPlayer, unit) then
        UpdateHealthText(tooltip, unit)
        return
    end

    ApplyClassColor(tooltip, unit)
    local needsInspect = false
    if Addon:GetSetting("showMouseTooltipSpecialization") then
        local specID, specName, specIcon, role = GetUnitSpecialization(unit)
        if specID then
            AddSpecializationIcons(tooltip, unit, specName, specIcon, role)
        else
            needsInspect = true
        end
    end
    if Addon:GetSetting("showMouseTooltipItemLevel") then
        local showPvpItemLevel = Addon:GetSetting(
            "showMouseTooltipPvpItemLevel"
        )
        local itemLevel, pvpItemLevel = GetUnitItemLevels(
            unit,
            showPvpItemLevel
        )
        if itemLevel then
            AddItemLevelLine(tooltip, itemLevel, pvpItemLevel)
        else
            needsInspect = true
        end
    end
    AddMythicRatingLine(tooltip, unit)
    AddMountLine(tooltip, unit)
    UpdateHealthText(tooltip, unit)
    if needsInspect then
        RequestInspect(unit)
    end
end


local function AddObjectHealth(tooltip, tooltipData)
    if tooltip ~= GameTooltip then return end
    local unit = ResolveTooltipHealthUnit(tooltip, tooltipData)
    trackedHealthUnit = unit
    UpdateHealthText(tooltip, unit)
end

if TooltipDataProcessor
    and TooltipDataProcessor.AddTooltipPostCall
    and Enum
    and Enum.TooltipDataType
    and Enum.TooltipDataType.Unit
then
    TooltipDataProcessor.AddTooltipPostCall(
        Enum.TooltipDataType.Unit,
        AddTargetDetails
    )
    if Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Object,
            AddObjectHealth
        )
    end
end

local function ApplyDetailSetting()
    pendingInspectGUID = nil
    if GameTooltip and GameTooltip:IsShown() then
        GameTooltip:Hide()
    end
end

local function ApplyEnabled()
    if Addon:GetSetting("enableMouseTooltipFollow") then
        ResetTooltipTracking()
        if GameTooltip and GameTooltip:IsShown() then
            cursorAnchor:Show()
            UpdateCursorAnchor()
            AnchorGameTooltip()
        else
            cursorAnchor:Hide()
        end
    else
        cursorAnchor:Hide()
        lastCursorX = nil
        lastCursorY = nil
        lastCursorScale = nil
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
    end
end

Addon:RegisterSetting(
    "enableMouseTooltipFollow",
    false,
    Addon.BooleanSetting,
    ApplyEnabled
)
Addon:RegisterSetting(
    "mouseTooltipAnchor",
    "BOTTOMRIGHT",
    SanitizeAnchor,
    AnchorGameTooltip
)
Addon:RegisterSetting(
    "showMouseTooltipItemLevel",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipPvpItemLevel",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipClassColor",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipSpecialization",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipHealth",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipMythicRating",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipFactionIcon",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipMount",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipMountSource",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterSetting(
    "showMouseTooltipTargetOfTarget",
    false,
    Addon.BooleanSetting,
    ApplyDetailSetting
)
Addon:RegisterEvent("INSPECT_READY", function(_, guid)
    if not IsAccessible(guid) or guid ~= pendingInspectGUID then return end
    pendingInspectGUID = nil
    if not GameTooltip or not GameTooltip:IsShown() then return end

    local unit = GetTooltipUnit(GameTooltip)
    if not unit or GetUnitGUIDSafely(unit) ~= guid then return end
    AddTargetDetails(GameTooltip)
    GameTooltip:Show()
end)
Addon:RegisterEvent("UNIT_HEALTH", function(_, unit)
    if not Addon:GetSetting("showMouseTooltipHealth") then return end
    if not GameTooltip or not GameTooltip:IsShown() then return end
    local tooltipUnit = trackedHealthUnit or GetTooltipUnit(GameTooltip)
    if tooltipUnit and SafeUnitTest(UnitIsUnit, tooltipUnit, unit) then
        UpdateHealthText(GameTooltip, tooltipUnit)
    end
end)
Addon:RegisterEvent("UNIT_MAXHEALTH", function(_, unit)
    if not Addon:GetSetting("showMouseTooltipHealth") then return end
    if not GameTooltip or not GameTooltip:IsShown() then return end
    local tooltipUnit = trackedHealthUnit or GetTooltipUnit(GameTooltip)
    if tooltipUnit and SafeUnitTest(UnitIsUnit, tooltipUnit, unit) then
        UpdateHealthText(GameTooltip, tooltipUnit)
    end
end)
Addon:RegisterEvent("PLAYER_LOGIN", ApplyEnabled)
