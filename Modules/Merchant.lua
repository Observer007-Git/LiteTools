local _, Addon = ...

local junkSaleTicker
local junkSaleQueue = {}
local junkSaleIndex = 1

local function DB()
    return Addon:GetDatabase()
end

local function TryAutoRepair()
    local db = DB()
    if not db
        or not db.autoRepair
        or not MerchantFrame
        or not MerchantFrame:IsShown()
        or not CanMerchantRepair()
    then
        return
    end

    local repairCost, canRepair = GetRepairAllCost()
    if canRepair and repairCost and repairCost > 0 then
        RepairAllItems(CanGuildBankRepair())
    end
end

local function StopJunkSale()
    if junkSaleTicker then
        junkSaleTicker:Cancel()
        junkSaleTicker = nil
    end
    wipe(junkSaleQueue)
    junkSaleIndex = 1
end

local function ProcessNextJunkItem()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        StopJunkSale()
        return
    end

    local entry = junkSaleQueue[junkSaleIndex]
    if not entry then
        StopJunkSale()
        TryAutoRepair()
        return
    end

    junkSaleIndex = junkSaleIndex + 1
    local itemInfo = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    if itemInfo
        and itemInfo.itemID == entry.itemID
        and itemInfo.quality == Enum.ItemQuality.Poor
        and not itemInfo.hasNoValue
        and not itemInfo.isLocked
    then
        C_Container.UseContainerItem(entry.bag, entry.slot)
    end
end

local function StartJunkSale()
    StopJunkSale()
    local db = DB()
    if not db or not db.autoSellJunk then
        return
    end

    local poorQuality = Enum.ItemQuality.Poor
    local equippedBagSlots = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 0
    for bag = 0, equippedBagSlots do
        local slotCount = tonumber(C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, slotCount do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo
                and itemInfo.quality == poorQuality
                and not itemInfo.hasNoValue
                and not itemInfo.isLocked
            then
                junkSaleQueue[#junkSaleQueue + 1] = {
                    bag = bag,
                    slot = slot,
                    itemID = itemInfo.itemID,
                }
            end
        end
    end

    if #junkSaleQueue > 0 then
        junkSaleTicker = C_Timer.NewTicker(0.05, ProcessNextJunkItem)
    end
end

local function ApplyJunkSetting(enabled)
    if enabled and MerchantFrame and MerchantFrame:IsShown() then
        StartJunkSale()
    else
        StopJunkSale()
    end
end

local function ApplyRepairSetting(enabled)
    if enabled and MerchantFrame and MerchantFrame:IsShown() then
        TryAutoRepair()
    end
end

local function MerchantShown()
    TryAutoRepair()
    StartJunkSale()
end

local function MerchantFeaturesEnabled()
    local db = DB()
    return db and (db.autoSellJunk or db.autoRepair)
end

Addon:RegisterSetting("autoSellJunk", false, Addon.BooleanSetting, ApplyJunkSetting)
Addon:RegisterSetting("autoRepair", false, Addon.BooleanSetting, ApplyRepairSetting)
Addon:RegisterEvent("MERCHANT_SHOW", MerchantShown, MerchantFeaturesEnabled)
Addon:RegisterEvent("MERCHANT_CLOSED", StopJunkSale, function()
    local db = DB()
    return db and db.autoSellJunk
end)
