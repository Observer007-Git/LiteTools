local _, Addon = ...

local L = Addon.L
local cache = {
    entries = {},
    ready = false,
    lastRequestTime = nil,
}
local clockHookInstalled = false

local function IsEnabled()
    local db = Addon:GetDatabase()
    return db and db.showInstanceProgress
end

local function RebuildCache()
    if not IsEnabled() then
        cache.ready = false
        return
    end

    wipe(cache.entries)
    local count = GetNumSavedInstances() or 0
    for index = 1, count do
        local name, _, _, _, locked, _, _, _, _, difficultyName, maxEncounters, progress =
            GetSavedInstanceInfo(index)
        if locked and name then
            local instanceName = name
            if difficultyName and difficultyName ~= "" then
                instanceName = string.format("%s [%s]", name, difficultyName)
            end
            if maxEncounters and maxEncounters > 0 then
                cache.entries[#cache.entries + 1] = string.format(
                    "%s - %d/%d",
                    instanceName,
                    progress or 0,
                    maxEncounters
                )
            else
                cache.entries[#cache.entries + 1] = instanceName
            end
        end
    end
    cache.ready = true
end

local function AddToTooltip()
    if not IsEnabled() then
        return
    end
    if not cache.ready then
        RebuildCache()
    end

    GameTooltip:AddLine(" ")
    if #cache.entries == 0 then
        GameTooltip:AddLine(L.INSTANCE_NONE, 0.55, 0.55, 0.55)
    else
        GameTooltip:AddLine(L.INSTANCE_HEADER, 1, 0.82, 0)
        for _, text in ipairs(cache.entries) do
            GameTooltip:AddLine(text, 0.3, 0.9, 0.3)
        end
    end
    GameTooltip:Show()
end

local function InstallClockHook()
    if clockHookInstalled or type(TimeManagerClockButton_UpdateTooltip) ~= "function" then
        return
    end
    hooksecurefunc("TimeManagerClockButton_UpdateTooltip", AddToTooltip)
    clockHookInstalled = true
end

local function RefreshSavedInstances(forceRequest)
    if not IsEnabled() then
        return
    end
    cache.ready = false
    local now = GetTime()
    if forceRequest or not cache.lastRequestTime or now - cache.lastRequestTime >= 2 then
        cache.lastRequestTime = now
        RequestRaidInfo()
    end
end

local function ApplySetting(enabled)
    if enabled then
        InstallClockHook()
        RefreshSavedInstances(true)
    else
        cache.ready = false
        wipe(cache.entries)
    end
end

Addon:RegisterSetting("showInstanceProgress", false, Addon.BooleanSetting, ApplySetting)
Addon:RegisterEvent("PLAYER_LOGIN", function()
    if IsEnabled() then
        InstallClockHook()
        RefreshSavedInstances()
    end
end)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    RefreshSavedInstances()
end, IsEnabled)
Addon:RegisterEvent("UPDATE_INSTANCE_INFO", RebuildCache, IsEnabled)
Addon:RegisterEvent("BOSS_KILL", function()
    RefreshSavedInstances()
end, IsEnabled)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if (loadedAddon == "Blizzard_TimeManager" or loadedAddon == "Blizzard_TimeManager_Mainline")
        and IsEnabled()
    then
        InstallClockHook()
    end
end)
