local _, Addon = ...

local Alerts = {}
Addon.Alerts = Alerts

local lootAnchor
local lootOriginalAdjustAnchors
local lootCustomAdjustAnchors
local groupAnchor
local groupOriginalParent
local groupOriginalIgnoreFramePositionManager
local groupCustomizationApplied = false
local groupAlertSubsystem
local groupOriginalAdjustAnchors
local groupCustomAdjustAnchors
local achievementAnchor
local achievementOriginalAdjustAnchors
local achievementCustomAdjustAnchors

local function DB()
    return Addon:GetDatabase()
end

local function RefreshAlertAnchors()
    if AlertFrame and AlertFrame.UpdateAnchors then
        AlertFrame:UpdateAnchors()
    end
end

local function PositionLootAnchor()
    if lootAnchor then
        Addon.Anchors:Position(lootAnchor, "lootAlertAnchorPosition", 0.5, 0.35)
    end
end

local function EnsureLootAnchor()
    if not lootAnchor then
        lootAnchor = Addon.Anchors:Create({
            name = "LiteToolsLootAlertAnchor",
            label = Addon.L.LOOT_ALERT_ANCHOR_SHORT,
            positionKey = "lootAlertAnchorPosition",
            hiddenKey = "lootAlertAnchorHidden",
            defaultX = 0.5,
            defaultY = 0.35,
            movedCallback = RefreshAlertAnchors,
        })
    end
    return lootAnchor
end

local function ApplyLootAnchor(reposition)
    local db = DB()
    if not db then return end
    if db.showLootAlertAnchor and not db.lootAlertAnchorPosition then
        db.lootAlertAnchorPosition = { version = 2, x = 0.5, y = 0.35 }
    end
    if db.showLootAlertAnchor then
        local anchor = EnsureLootAnchor()
        if reposition then PositionLootAnchor() end
        anchor:SetShown(not db.lootAlertAnchorHidden)
        if LootAlertSystem and LootAlertSystem.AdjustAnchors then
            if not lootOriginalAdjustAnchors then
                lootOriginalAdjustAnchors = LootAlertSystem.AdjustAnchors
                lootCustomAdjustAnchors = function(system, relativeAlert)
                    lootOriginalAdjustAnchors(system, anchor)
                    return relativeAlert
                end
            end
            LootAlertSystem.AdjustAnchors = lootCustomAdjustAnchors
        end
    else
        if lootAnchor then lootAnchor:Hide() end
        if LootAlertSystem
            and lootCustomAdjustAnchors
            and LootAlertSystem.AdjustAnchors == lootCustomAdjustAnchors
        then
            LootAlertSystem.AdjustAnchors = lootOriginalAdjustAnchors
        end
    end
    RefreshAlertAnchors()
end

local function PositionAchievementAnchor()
    if achievementAnchor then
        Addon.Anchors:Position(
            achievementAnchor,
            "achievementAlertAnchorPosition",
            0.5,
            0.45
        )
    end
end

local function EnsureAchievementAnchor()
    if not achievementAnchor then
        achievementAnchor = Addon.Anchors:Create({
            name = "LiteToolsAchievementAlertAnchor",
            label = Addon.L.ACHIEVEMENT_ALERT_ANCHOR_SHORT,
            positionKey = "achievementAlertAnchorPosition",
            hiddenKey = "achievementAlertAnchorHidden",
            defaultX = 0.5,
            defaultY = 0.45,
            movedCallback = RefreshAlertAnchors,
        })
    end
    return achievementAnchor
end

local function ApplyAchievementAnchor(reposition)
    local db = DB()
    if not db then return end
    if db.showAchievementAlertAnchor and not db.achievementAlertAnchorPosition then
        db.achievementAlertAnchorPosition = { version = 2, x = 0.5, y = 0.45 }
    end
    if db.showAchievementAlertAnchor then
        local anchor = EnsureAchievementAnchor()
        if reposition then PositionAchievementAnchor() end
        anchor:SetShown(not db.achievementAlertAnchorHidden)
        if AchievementAlertSystem and AchievementAlertSystem.AdjustAnchors then
            if not achievementOriginalAdjustAnchors then
                achievementOriginalAdjustAnchors = AchievementAlertSystem.AdjustAnchors
                achievementCustomAdjustAnchors = function(system, relativeAlert)
                    achievementOriginalAdjustAnchors(system, anchor)
                    return relativeAlert
                end
            end
            AchievementAlertSystem.AdjustAnchors = achievementCustomAdjustAnchors
        end
    else
        if achievementAnchor then achievementAnchor:Hide() end
        if AchievementAlertSystem
            and achievementCustomAdjustAnchors
            and AchievementAlertSystem.AdjustAnchors == achievementCustomAdjustAnchors
        then
            AchievementAlertSystem.AdjustAnchors = achievementOriginalAdjustAnchors
        end
    end
    RefreshAlertAnchors()
end

local function FindGroupSubsystem()
    if groupAlertSubsystem and groupAlertSubsystem.anchorFrame == GroupLootContainer then
        return groupAlertSubsystem
    end
    if not AlertFrame or not AlertFrame.alertFrameSubSystems or not GroupLootContainer then
        return nil
    end
    for _, subsystem in ipairs(AlertFrame.alertFrameSubSystems) do
        if subsystem.anchorFrame == GroupLootContainer then
            groupAlertSubsystem = subsystem
            return subsystem
        end
    end
    return nil
end

local function PositionGroupContainer()
    if GroupLootContainer and groupAnchor then
        GroupLootContainer:ClearAllPoints()
        GroupLootContainer:SetPoint("BOTTOM", groupAnchor, "TOP", 0, 0)
    end
end

local function PositionGroupAnchor()
    if groupAnchor then
        Addon.Anchors:Position(groupAnchor, "groupLootAnchorPosition", 0.5, 0.25)
        PositionGroupContainer()
    end
end

local function EnsureGroupAnchor()
    if not groupAnchor then
        groupAnchor = Addon.Anchors:Create({
            name = "LiteToolsGroupLootAnchor",
            label = Addon.L.GROUP_LOOT_ANCHOR_SHORT,
            positionKey = "groupLootAnchorPosition",
            hiddenKey = "groupLootAnchorHidden",
            defaultX = 0.5,
            defaultY = 0.25,
            movedCallback = PositionGroupContainer,
        })
    end
    return groupAnchor
end

local function ApplyGroupAnchor(reposition)
    local db = DB()
    if not db then return end
    if db.showGroupLootAnchor and not db.groupLootAnchorPosition then
        db.groupLootAnchorPosition = { version = 2, x = 0.5, y = 0.25 }
    end
    if db.showGroupLootAnchor then
        local anchor = EnsureGroupAnchor()
        if reposition then PositionGroupAnchor() end
        anchor:SetShown(not db.groupLootAnchorHidden)
        if GroupLootContainer then
            if not groupCustomizationApplied then
                groupOriginalParent = GroupLootContainer:GetParent()
                groupOriginalIgnoreFramePositionManager =
                    GroupLootContainer.ignoreFramePositionManager
                if GroupLootContainer.layoutParent
                    and GroupLootContainer.layoutParent.RemoveManagedFrame
                then
                    GroupLootContainer.layoutParent:RemoveManagedFrame(GroupLootContainer)
                end
                GroupLootContainer.ignoreFramePositionManager = true
                GroupLootContainer:SetParent(UIParent)
                groupCustomizationApplied = true
            end
            PositionGroupContainer()
        end
        local subsystem = FindGroupSubsystem()
        if subsystem and subsystem.AdjustAnchors then
            if not groupOriginalAdjustAnchors then
                groupOriginalAdjustAnchors = subsystem.AdjustAnchors
                groupCustomAdjustAnchors = function(_, relativeAlert)
                    return relativeAlert
                end
            end
            subsystem.AdjustAnchors = groupCustomAdjustAnchors
        end
    else
        if groupAnchor then groupAnchor:Hide() end
        local subsystem = FindGroupSubsystem()
        if subsystem
            and groupCustomAdjustAnchors
            and subsystem.AdjustAnchors == groupCustomAdjustAnchors
        then
            subsystem.AdjustAnchors = groupOriginalAdjustAnchors
        end
        if groupCustomizationApplied and GroupLootContainer then
            GroupLootContainer.ignoreFramePositionManager =
                groupOriginalIgnoreFramePositionManager
            GroupLootContainer:ClearAllPoints()
            GroupLootContainer:SetParent(groupOriginalParent or UIParent)
            if GroupLootContainer:IsShown()
                and GroupLootContainer.layoutParent
                and GroupLootContainer.layoutParent.AddManagedFrame
            then
                GroupLootContainer.layoutParent:AddManagedFrame(GroupLootContainer)
            end
            groupOriginalParent = nil
            groupOriginalIgnoreFramePositionManager = nil
            groupCustomizationApplied = false
        end
    end
    RefreshAlertAnchors()
end

function Alerts:GetGroupLootAnchor()
    return groupAnchor
end

function Alerts:ApplyGroupLootAnchor(reposition)
    ApplyGroupAnchor(reposition)
end

local function RegisterAnchorSettings(toggleKey, positionKey, hiddenKey, applyFunction)
    Addon:RegisterSetting(positionKey, nil, Addon.PositionSetting)
    Addon:RegisterSetting(hiddenKey, false, Addon.BooleanSetting)
    Addon:RegisterSetting(toggleKey, false, Addon.BooleanSetting, function(value)
        local db = DB()
        if value then db[hiddenKey] = false end
        applyFunction(true)
    end)
end

RegisterAnchorSettings(
    "showLootAlertAnchor",
    "lootAlertAnchorPosition",
    "lootAlertAnchorHidden",
    ApplyLootAnchor
)
RegisterAnchorSettings(
    "showGroupLootAnchor",
    "groupLootAnchorPosition",
    "groupLootAnchorHidden",
    ApplyGroupAnchor
)
RegisterAnchorSettings(
    "showAchievementAlertAnchor",
    "achievementAlertAnchorPosition",
    "achievementAlertAnchorHidden",
    ApplyAchievementAnchor
)

local function HasCustomAnchor(db)
    return db.showLootAlertAnchor
        or db.showGroupLootAnchor
        or db.showAchievementAlertAnchor
end

local function ApplyEnabledAnchors()
    local db = DB()
    if db.showLootAlertAnchor then ApplyLootAnchor(true) end
    if db.showGroupLootAnchor then ApplyGroupAnchor(true) end
    if db.showAchievementAlertAnchor then ApplyAchievementAnchor(true) end
end

Addon:RegisterEvent("PLAYER_LOGIN", ApplyEnabledAnchors)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", ApplyEnabledAnchors)
Addon:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", ApplyEnabledAnchors, HasCustomAnchor)
Addon:RegisterEvent("DISPLAY_SIZE_CHANGED", ApplyEnabledAnchors, HasCustomAnchor)
Addon:RegisterEvent("UI_SCALE_CHANGED", ApplyEnabledAnchors, HasCustomAnchor)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_UIPanels_Game" and Addon:GetSetting("showGroupLootAnchor") then
        ApplyGroupAnchor(true)
    end
end)

