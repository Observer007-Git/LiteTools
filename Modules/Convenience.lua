local _, Addon = ...

local DELETE_CONFIRM_DIALOGS = {
    DELETE_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
    DELETE_GOOD_ITEM = true,
}

local deleteHookInstalled = false
local cinematicHooksInstalled = false
local cinematicFrameHookInstalled = false
local movieFrameHookInstalled = false

local function DB()
    return Addon:GetDatabase()
end

local function FillDeleteConfirmation()
    local db = DB()
    if not db or not db.autoTypeDelete then
        return
    end

    local index = 1
    while true do
        local popup = _G["StaticPopup" .. index]
        if not popup then
            break
        end

        if popup:IsShown() and DELETE_CONFIRM_DIALOGS[popup.which] then
            local editBox
            if popup.GetEditBox then
                editBox = popup:GetEditBox()
            end
            editBox = editBox or popup.editBox
            local popupName = popup:GetName()
            if not editBox and popupName then
                editBox = _G[popupName .. "EditBox"]
            end
            if editBox and editBox:IsShown() then
                editBox:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE")
                editBox:SetCursorPosition(editBox:GetNumLetters())
                return
            end
        end

        index = index + 1
    end
end

local function InstallDeleteHook()
    if deleteHookInstalled then
        return
    end

    hooksecurefunc("StaticPopup_Show", function(which)
        local db = DB()
        if DELETE_CONFIRM_DIALOGS[which] and db and db.autoTypeDelete then
            C_Timer.After(0, FillDeleteConfirmation)
        end
    end)
    deleteHookInstalled = true
end

local function InstallCinematicHooks()
    if not cinematicFrameHookInstalled and CinematicFrame then
        CinematicFrame:HookScript("OnKeyDown", function(frame, key)
            local db = DB()
            if db and db.skipCinematics and key == "SPACE" and frame:IsShown() then
                if frame.closeDialog then
                    frame.closeDialog:Hide()
                end
                CinematicFrame_CancelCinematic()
            end
        end)
        cinematicFrameHookInstalled = true
    end

    if not movieFrameHookInstalled and MovieFrame then
        MovieFrame:HookScript("OnKeyUp", function(frame, key)
            local db = DB()
            if db and db.skipCinematics and key == "SPACE" and frame:IsShown() then
                frame:FinishMovie()
            end
        end)
        movieFrameHookInstalled = true
    end

    cinematicHooksInstalled = cinematicFrameHookInstalled and movieFrameHookInstalled
end

local function ApplyDeleteSetting(enabled)
    if enabled then
        InstallDeleteHook()
        C_Timer.After(0, FillDeleteConfirmation)
    end
end

local function ApplyCinematicSetting(enabled)
    if enabled then
        InstallCinematicHooks()
    end
end

local function Initialize()
    ApplyDeleteSetting(Addon:GetSetting("autoTypeDelete"))
    ApplyCinematicSetting(Addon:GetSetting("skipCinematics"))
end

local function HasEnabledFeature(db)
    return db.autoTypeDelete or db.skipCinematics
end

Addon:RegisterSetting("autoTypeDelete", false, Addon.BooleanSetting, ApplyDeleteSetting)
Addon:RegisterSetting("skipCinematics", false, Addon.BooleanSetting, ApplyCinematicSetting)
Addon:RegisterEvent("PLAYER_LOGIN", Initialize, HasEnabledFeature)
Addon:RegisterEvent("ADDON_LOADED", function()
    if Addon:GetSetting("skipCinematics") then
        InstallCinematicHooks()
    end
end, function(db) return db.skipCinematics and not cinematicHooksInstalled end)
