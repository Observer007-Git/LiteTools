local ADDON_NAME, Addon = ...

local SETTING_KEY = "customPlatynatorTextures"
local MEDIA_TYPE = "platynator/sizedtexture"
local TEXTURE_WIDTH = 128
local TEXTURE_HEIGHT = 69
local TEXTURES = {
    LiteRight = "Media\\LiteRight.png",
    LiteLeft = "Media\\LiteLeft.png",
}

local registeredTextures = {}

local function GetSharedMedia()
    if not _G.LibStub then
        return nil
    end

    local success, sharedMedia = pcall(function()
        return _G.LibStub("LibSharedMedia-3.0", true)
    end)
    if success and type(sharedMedia) == "table"
        and type(sharedMedia.Register) == "function"
    then
        return sharedMedia
    end
end

local function RegisterTextures()
    if not Addon:GetSetting(SETTING_KEY) then
        return
    end

    local sharedMedia = GetSharedMedia()
    if not sharedMedia then
        return
    end

    for name, relativePath in pairs(TEXTURES) do
        if not registeredTextures[name] then
            local media = {
                file = "Interface\\AddOns\\" .. ADDON_NAME .. "\\" .. relativePath,
                width = TEXTURE_WIDTH,
                height = TEXTURE_HEIGHT,
            }
            sharedMedia:Register(MEDIA_TYPE, name, media)
            registeredTextures[name] = true
        end
    end
end

Addon:RegisterSetting(
    SETTING_KEY,
    false,
    Addon.BooleanSetting,
    function(enabled)
        if enabled then
            RegisterTextures()
        end
    end
)

Addon:RegisterEvent("PLAYER_LOGIN", RegisterTextures)
Addon:RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Platynator" then
        RegisterTextures()
    end
end)
