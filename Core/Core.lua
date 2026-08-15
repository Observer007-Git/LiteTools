local ADDON_NAME, Addon = ...

Addon.name = ADDON_NAME
Addon.L = Addon.L or {}
Addon.defaults = Addon.defaults or {}

local eventFrame = CreateFrame("Frame", "LiteToolsEventFrame")
local database
local initialized = false
local settings = {}
local settingCallbacks = {}
local eventHandlers = {}
local databaseMigrations = {}
local registeredEvents = {}

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function SanitizeBoolean(value)
    return not not value
end

local function SanitizeNormalizedPosition(value)
    if type(value) ~= "table" then
        return nil
    end

    local positionX = tonumber(value.x)
    local positionY = tonumber(value.y)
    if not positionX or not positionY then
        return nil
    end

    return {
        version = 2,
        x = Clamp(positionX, 0, 1),
        y = Clamp(positionY, 0, 1),
    }
end

function Addon:Clamp(value, minimum, maximum)
    return Clamp(value, minimum, maximum)
end

function Addon.BooleanSetting(value)
    return SanitizeBoolean(value)
end

function Addon.NumberSetting(minimum, maximum, step)
    step = tonumber(step) or 1
    return function(value)
        value = Clamp(value, minimum, maximum)
        value = minimum + math.floor((value - minimum) / step + 0.5) * step
        return math.floor(value * 1000000 + 0.5) / 1000000
    end
end

function Addon.PositionSetting(value)
    return SanitizeNormalizedPosition(value)
end

function Addon:RegisterSetting(key, defaultValue, sanitizer, callback)
    assert(type(key) == "string" and settings[key] == nil, "Duplicate LiteTools setting: " .. tostring(key))
    settings[key] = {
        defaultValue = defaultValue,
        sanitizer = sanitizer,
    }
    self.defaults[key] = defaultValue
    if callback then
        self:RegisterSettingCallback(key, callback)
    end
end

function Addon:RegisterSettingCallback(key, callback)
    assert(settings[key] ~= nil, "Unknown LiteTools setting: " .. tostring(key))
    assert(type(callback) == "function",
        "Invalid LiteTools setting callback: " .. tostring(key))
    settingCallbacks[key] = settingCallbacks[key] or {}
    settingCallbacks[key][#settingCallbacks[key] + 1] = callback
end

function Addon:RegisterDatabaseMigration(callback)
    assert(type(callback) == "function", "Invalid LiteTools database migration")
    databaseMigrations[#databaseMigrations + 1] = callback
end

function Addon:GetSetting(key)
    if database then
        return database[key]
    end
    local definition = settings[key]
    return definition and definition.defaultValue
end

function Addon:GetDatabase()
    return database
end

local function ShouldHandleEvent(handler)
    return not handler.predicate or handler.predicate(database)
end

function Addon:RegisterEvent(event, callback, predicate)
    assert(type(event) == "string" and type(callback) == "function",
        "Invalid LiteTools event registration: " .. tostring(event))
    assert(predicate == nil or type(predicate) == "function",
        "Invalid LiteTools event predicate: " .. tostring(event))
    eventHandlers[event] = eventHandlers[event] or {}
    eventHandlers[event][#eventHandlers[event] + 1] = {
        callback = callback,
        predicate = predicate,
    }
    -- Retail may reject event registration from a settings click call stack.
    -- Register routes while addon files load, then gate dispatch with predicates.
    if not registeredEvents[event] then
        assert(not initialized,
            "LiteTools events must be registered during addon loading: " .. event)
        eventFrame:RegisterEvent(event)
        registeredEvents[event] = true
    end
end

function Addon:SetSetting(key, value)
    local definition = settings[key]
    if not database or not definition then
        return
    end

    if definition.sanitizer then
        value = definition.sanitizer(value)
    end
    if database[key] == value then
        return
    end

    database[key] = value
    for _, callback in ipairs(settingCallbacks[key] or {}) do
        callback(value, key)
    end
end

local function InitializeDatabase()
    if type(LiteToolsDB) ~= "table" then
        if type(FansWowToolsDB) == "table" then
            LiteToolsDB = FansWowToolsDB
        else
            LiteToolsDB = {}
        end
    end
    FansWowToolsDB = nil
    database = LiteToolsDB

    for _, migration in ipairs(databaseMigrations) do
        migration(database)
    end

    for key, definition in pairs(settings) do
        local value = database[key]
        if value == nil then
            value = definition.defaultValue
        end
        if definition.sanitizer then
            value = definition.sanitizer(value)
        end
        database[key] = value
    end
end

local function DispatchEvent(event, ...)
    for _, handler in ipairs(eventHandlers[event] or {}) do
        if ShouldHandleEvent(handler) then
            handler.callback(event, ...)
        end
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
registeredEvents.ADDON_LOADED = true
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME and not initialized then
        InitializeDatabase()
        initialized = true
    end

    if initialized then
        DispatchEvent(event, ...)
    end
end)

Addon.eventFrame = eventFrame
