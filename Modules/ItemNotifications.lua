local _, Addon = ...

local DEFAULT_OPACITY = 90
local DEFAULT_SCALE = 100
local DEFAULT_DURATION = 5
local ROW_GAP = 4
local FADE_DURATION = 0.35
local MAX_ROWS = 20
local ROW_HEIGHT = 44
local CONTENT_LEFT = 14
local CONTENT_RIGHT = 14
local ICON_GAP = 8
local COLUMN_GAP = 4
local ICON_TEXT_GAP = 2
local MAX_ITEM_NAME_CHARS = 10
local ITEM_LINK_PATTERNS = {
    "|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r",
    "|Hitem:[^|]+|h%[[^%]]+%]|h|r",
}
local CURRENCY_LINK_PATTERN = "|c%x+|Hcurrency:[^|]+|h%[[^%]]+%]|h|r"

local anchor
local container
local rows = {}
local Relayout
local MeasureColumnWidths
local UpdateRowLayout

local function DB()
    return Addon:GetDatabase()
end

local function SanitizeDirection(value)
    return value == "down" and "down" or "up"
end

local function AtlasIcon(atlas, size)
    if CreateAtlasMarkup then
        return CreateAtlasMarkup(atlas, size, size)
    end
    return ""
end

local function CoinIcon(atlas, size)
    local textSize = size or 12
    local coinSize = math.max(4, math.floor(textSize * 0.375 + 0.5))
    return AtlasIcon(atlas, coinSize)
end

local function TruncateItemName(text)
    text = tostring(text or "?")
    local starts = {}
    for index = 1, #text do
        local byte = text:byte(index)
        if byte < 128 or byte >= 192 then
            starts[#starts + 1] = index
        end
    end
    if #starts <= MAX_ITEM_NAME_CHARS then return text end

    local keepChars = MAX_ITEM_NAME_CHARS - 3
    local cutoff = starts[keepChars + 1]
    return text:sub(1, cutoff - 1) .. "···"
end

local function FormatCompactCount(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    local divisor
    local suffix
    if value >= 10000 then
        divisor = 10000
        suffix = "万"
    elseif value >= 1000 then
        divisor = 1000
        suffix = "千"
    else
        return tostring(value)
    end

    local scaled = value / divisor
    local formatted
    if scaled >= 100 then
        formatted = string.format("%.0f", scaled)
    elseif scaled >= 10 then
        formatted = string.format("%.1f", scaled)
    else
        formatted = string.format("%.2f", scaled)
    end
    formatted = formatted:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return formatted .. suffix
end

local function QueryAuctionatorPrice(itemLink)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local getPrice = api and api.GetAuctionPriceByItemLink
    if not getPrice or type(itemLink) ~= "string" then return nil end

    local ok, price = pcall(getPrice, "LiteTools", itemLink)
    if ok and type(price) == "number" and price > 0 then
        return price
    end

    local itemID = C_Item and C_Item.GetItemInfoInstant
        and C_Item.GetItemInfoInstant(itemLink)
    local getPriceByID = api.GetAuctionPriceByItemID
    if type(itemID) == "number" and getPriceByID then
        ok, price = pcall(getPriceByID, "LiteTools", itemID)
        if ok and type(price) == "number" and price > 0 then
            return price
        end
    end
    return nil
end

local function GetAuctionatorPrice(itemLink, callback)
    local price = QueryAuctionatorPrice(itemLink)
    if price or not Item or not Item.CreateFromItemLink then
        callback(price)
        return
    end

    local item = Item:CreateFromItemLink(itemLink)
    if not item or item:IsItemEmpty() then
        callback(nil)
        return
    end
    item:ContinueOnItemLoad(function()
        callback(QueryAuctionatorPrice(itemLink))
    end)
end

local function FormatLargestMoney(copper, iconSize)
    if not copper or copper <= 0 then
        return "0" .. CoinIcon("coin-copper", iconSize)
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local bronze = copper % 100
    if gold > 0 then
        return string.format("%d%s", gold, CoinIcon("coin-gold", iconSize))
    elseif silver > 0 then
        return string.format("%d%s", silver, CoinIcon("coin-silver", iconSize))
    end
    return string.format("%d%s", bronze, CoinIcon("coin-copper", iconSize))
end

local function FormatMoneyAmount(copper, iconSize)
    copper = math.max(0, tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local bronze = copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = string.format(
            "%d%s",
            gold,
            CoinIcon("coin-gold", iconSize)
        )
    end
    if silver > 0 then
        parts[#parts + 1] = string.format(
            "%d%s",
            silver,
            CoinIcon("coin-silver", iconSize)
        )
    end
    if bronze > 0 or #parts == 0 then
        parts[#parts + 1] = string.format(
            "%d%s",
            bronze,
            CoinIcon("coin-copper", iconSize)
        )
    end
    return table.concat(parts, " ")
end

local function GetLargestMoneyAmount(copper)
    if not copper or copper <= 0 then return 0 end

    local gold = math.floor(copper / 10000)
    if gold > 0 then return gold end
    local silver = math.floor(copper / 100) % 100
    if silver > 0 then return silver end
    return copper % 100
end

local function RemoveRow(row)
    if row.timer then
        row.timer:Cancel()
        row.timer = nil
    end
    row:Hide()
    for index, current in ipairs(rows) do
        if current == row then
            table.remove(rows, index)
            break
        end
    end
    Relayout()
end

local function GetDirection()
    return Addon:GetSetting("itemNotificationDirection") == "down" and "down" or "up"
end

Relayout = function()
    if not anchor or not container then return end

    local direction = GetDirection()
    local columns = MeasureColumnWidths and MeasureColumnWidths()
    local previous = anchor
    for index, row in ipairs(rows) do
        if UpdateRowLayout then
            UpdateRowLayout(row, columns)
        end
        row:ClearAllPoints()
        if direction == "up" then
            row:SetPoint("BOTTOMLEFT", previous, "TOPLEFT", 0, index == 1 and 0 or ROW_GAP)
        else
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, index == 1 and 0 or -ROW_GAP)
        end
        previous = row
    end
end

local function ApplyFontSize(fontString, size)
    local font, _, flags = fontString:GetFont()
    if font then
        fontString:SetFont(font, size, flags or "")
    end
end

local function CreateRingedAtlasIcon(parent, atlas)
    local ring = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    ring:SetAtlas("bluemenu-Ring", false)

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas(atlas, false)

    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)

    return ring, icon, mask
end

UpdateRowLayout = function(row, columns)
    local nameSize = Addon:GetSetting("itemNotificationNameFontSize") or 14
    local iconSize = nameSize + 4
    local ringSize = iconSize + 8
    local contentLeft = CONTENT_LEFT + ringSize + ICON_GAP
    columns = columns or {
        nameCount = 0,
        bag = ringSize + ICON_TEXT_GAP,
        vendor = 0,
        auction = 0,
        rowWidth = CONTENT_LEFT + ringSize + ICON_GAP + CONTENT_RIGHT,
    }
    row:SetWidth(columns.rowWidth)
    if row.textIcon:IsShown() then
        row.textIcon:SetSize(iconSize, iconSize)
        row.iconRing:SetSize(ringSize, ringSize)
        row.iconRing:ClearAllPoints()
        row.iconRing:SetPoint("LEFT", row, "LEFT", CONTENT_LEFT, 0)
        row.textIcon:ClearAllPoints()
        row.textIcon:SetPoint("CENTER", row.iconRing)
    end

    row.name:ClearAllPoints()
    row.count:ClearAllPoints()
    row.bagCount:ClearAllPoints()
    row.vendorPrice:ClearAllPoints()
    row.auctionPrice:ClearAllPoints()
    row.bagIconRing:ClearAllPoints()
    row.bagIcon:ClearAllPoints()
    row.vendorIconRing:ClearAllPoints()
    row.vendorIcon:ClearAllPoints()
    row.auctionIconRing:ClearAllPoints()
    row.auctionIcon:ClearAllPoints()

    local bagLeft = contentLeft + columns.nameCount + COLUMN_GAP
    row.bagIconRing:SetSize(ringSize, ringSize)
    row.bagIconRing:SetPoint("LEFT", row, "LEFT", bagLeft, 0)
    row.bagIcon:SetSize(iconSize, iconSize)
    row.bagIcon:SetPoint("CENTER", row.bagIconRing)
    row.bagIconRing:Show()
    row.bagIcon:Show()
    row.bagCount:SetPoint("LEFT", row.bagIconRing, "RIGHT", ICON_TEXT_GAP, 0)
    row.bagCount:SetWidth(math.max(1, columns.bag - ringSize - ICON_TEXT_GAP))

    local vendorLeft = bagLeft + columns.bag
    if columns.vendor > 0 then
        vendorLeft = vendorLeft + COLUMN_GAP
    end
    local auctionLeft = vendorLeft + columns.vendor
    if columns.auction > 0 then
        auctionLeft = auctionLeft + COLUMN_GAP
    end

    if row.moneyAmount then
        row.name:Show()
        row.count:Show()
        row.bagCount:Show()
        row.vendorPrice:Hide()
        row.auctionPrice:Hide()
        row.vendorIconRing:Hide()
        row.vendorIcon:Hide()
        row.auctionIconRing:Hide()
        row.auctionIcon:Hide()
        row.name:SetPoint("LEFT", row, "LEFT", contentLeft, 0)
        row.count:SetPoint("LEFT", row.name, "RIGHT", COLUMN_GAP, 0)
        return
    end

    row.name:Show()
    row.count:Show()
    row.bagCount:Show()
    row.name:SetPoint("LEFT", row, "LEFT", contentLeft, 0)
    row.count:SetPoint("LEFT", row.name, "RIGHT", 0, 0)

    row.vendorIconRing:SetSize(ringSize, ringSize)
    row.vendorIconRing:SetPoint("LEFT", row, "LEFT", vendorLeft, 0)
    row.vendorIcon:SetSize(iconSize, iconSize)
    row.vendorIcon:SetPoint("CENTER", row.vendorIconRing)
    row.vendorPrice:SetPoint(
        "LEFT",
        row.vendorIconRing,
        "RIGHT",
        ICON_TEXT_GAP,
        0
    )
    row.vendorPrice:SetWidth(math.max(
        1,
        columns.vendor - ringSize - ICON_TEXT_GAP
    ))

    row.auctionIconRing:SetSize(ringSize, ringSize)
    row.auctionIconRing:SetPoint("LEFT", row, "LEFT", auctionLeft, 0)
    row.auctionIcon:SetSize(iconSize, iconSize)
    row.auctionIcon:SetPoint("CENTER", row.auctionIconRing)
    row.auctionPrice:SetPoint(
        "LEFT",
        row.auctionIconRing,
        "RIGHT",
        ICON_TEXT_GAP,
        0
    )
    row.auctionPrice:SetWidth(math.max(
        1,
        columns.auction - ringSize - ICON_TEXT_GAP
    ))
end

local function StartRowFade(row)
    if row.fading then return end
    row.fading = true
    row.fadeAnimation:SetFromAlpha(row:GetAlpha())
    row.fade:Play()
end

local function ShowRowTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.tooltipLink then
        local ok = pcall(function() GameTooltip:SetHyperlink(row.tooltipLink) end)
        if not ok then
            GameTooltip:SetText(row.nameText)
        end
    else
        GameTooltip:SetText(row.nameText)
    end
    GameTooltip:Show()
end

local function CreateRow()
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(1, ROW_HEIGHT)
    row:SetAlpha(Addon:GetSetting("itemNotificationOpacity") / 100)

    local accent = row:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT", 6, -7)
    accent:SetPoint("BOTTOMLEFT", 6, 7)
    accent:SetWidth(3)
    row.accent = accent

    local iconRing = row:CreateTexture(nil, "ARTWORK", nil, 1)
    iconRing:SetAtlas("bluemenu-Ring", false)
    iconRing:Hide()
    row.iconRing = iconRing

    local textIcon = row:CreateTexture(nil, "ARTWORK")
    textIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    textIcon:Hide()
    row.textIcon = textIcon

    local iconMask = row:CreateMaskTexture()
    iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    iconMask:SetAllPoints(textIcon)
    textIcon:AddMaskTexture(iconMask)
    row.iconMask = iconMask

    local bagIconRing, bagIcon, bagIconMask = CreateRingedAtlasIcon(row, "bag-main")
    bagIconRing:Hide()
    bagIcon:Hide()
    row.bagIconRing = bagIconRing
    row.bagIcon = bagIcon
    row.bagIconMask = bagIconMask

    local vendorIconRing, vendorIcon, vendorIconMask = CreateRingedAtlasIcon(
        row,
        "SpellIcon-256x256-SellJunk"
    )
    vendorIconRing:Hide()
    vendorIcon:Hide()
    row.vendorIconRing = vendorIconRing
    row.vendorIcon = vendorIcon
    row.vendorIconMask = vendorIconMask

    local auctionIconRing, auctionIcon, auctionIconMask = CreateRingedAtlasIcon(
        row,
        "Auctioneer"
    )
    auctionIconRing:Hide()
    auctionIcon:Hide()
    row.auctionIconRing = auctionIconRing
    row.auctionIcon = auctionIcon
    row.auctionIconMask = auctionIconMask

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    name:SetTextColor(1, 1, 1, 1)
    name:SetWordWrap(false)
    name:SetMaxLines(1)
    ApplyFontSize(name, Addon:GetSetting("itemNotificationNameFontSize") or 14)
    row.name = name

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetJustifyH("LEFT")
    count:SetJustifyV("MIDDLE")
    count:SetTextColor(1, 1, 1, 1)
    count:SetWordWrap(false)
    count:SetMaxLines(1)
    ApplyFontSize(count, Addon:GetSetting("itemNotificationCountFontSize") or 14)
    row.count = count

    local bagCount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bagCount:SetJustifyH("LEFT")
    bagCount:SetJustifyV("MIDDLE")
    bagCount:SetTextColor(1, 1, 1, 1)
    bagCount:SetWordWrap(false)
    bagCount:SetMaxLines(1)
    ApplyFontSize(
        bagCount,
        Addon:GetSetting("itemNotificationCountFontSize") or 14
    )
    row.bagCount = bagCount

    local vendorPrice = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    vendorPrice:SetJustifyH("LEFT")
    vendorPrice:SetJustifyV("MIDDLE")
    vendorPrice:SetTextColor(1, 1, 1, 1)
    vendorPrice:SetWordWrap(false)
    vendorPrice:SetMaxLines(1)
    ApplyFontSize(
        vendorPrice,
        Addon:GetSetting("itemNotificationCountFontSize") or 14
    )
    vendorPrice:Hide()
    row.vendorPrice = vendorPrice

    local auctionPrice = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    auctionPrice:SetJustifyH("LEFT")
    auctionPrice:SetJustifyV("MIDDLE")
    auctionPrice:SetTextColor(1, 1, 1, 1)
    auctionPrice:SetWordWrap(false)
    auctionPrice:SetMaxLines(1)
    ApplyFontSize(
        auctionPrice,
        Addon:GetSetting("itemNotificationCountFontSize") or 14
    )
    auctionPrice:Hide()
    row.auctionPrice = auctionPrice

    local fade = row:CreateAnimationGroup()
    local fadeAnimation = fade:CreateAnimation("Alpha")
    fadeAnimation:SetToAlpha(0)
    fadeAnimation:SetDuration(FADE_DURATION)
    fadeAnimation:SetSmoothing("OUT")
    row.fade = fade
    row.fadeAnimation = fadeAnimation
    fade:SetScript("OnFinished", function() RemoveRow(row) end)

    row:SetScript("OnEnter", function(self)
        self.hovered = true
        if self.timer then
            self.timer:Cancel()
            self.timer = nil
        end
        if self.fading then
            self.fading = false
            self.fade:Stop()
            self:SetAlpha(Addon:GetSetting("itemNotificationOpacity") / 100)
        end
        self.remaining = math.max(0, self.deadline - GetTime())
        ShowRowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = false
        GameTooltip:Hide()
        self.deadline = GetTime() + (self.remaining or 0)
        local wait = math.max(0, (self.remaining or 0) - FADE_DURATION)
        self.timer = C_Timer.NewTimer(wait, function()
            self.timer = nil
            StartRowFade(self)
        end)
    end)

    return row
end

local function RefreshRowText(row)
    local countSize = Addon:GetSetting("itemNotificationCountFontSize") or 14
    if row.moneyAmount then
        row.name:SetText(row.displayName)
        row.count:SetText(FormatMoneyAmount(row.moneyAmount, countSize))
        row.bagCount:SetText(FormatMoneyAmount(
            row.ownedCount or row.moneyAmount,
            countSize
        ))
        row.bagIconRing:Show()
        row.bagIcon:Show()
        row.vendorPrice:SetText("")
        row.auctionPrice:SetText("")
        return
    end

    row.name:SetText(TruncateItemName(row.displayName))
    row.count:SetText("×" .. FormatCompactCount(row.gainedCount or 1))
    row.bagCount:SetText(FormatCompactCount(
        row.ownedCount or row.gainedCount or 1
    ))
    row.bagIconRing:Show()
    row.bagIcon:Show()

    local showVendorPrice = row.sellPrice ~= nil
    local showAuctionPrice = row.auctionCachedPrice ~= nil
    row.vendorPrice:SetText(
        showVendorPrice
            and FormatLargestMoney(row.sellPrice, countSize)
            or ""
    )
    row.vendorPrice:SetShown(showVendorPrice)
    row.vendorIconRing:SetShown(showVendorPrice)
    row.vendorIcon:SetShown(showVendorPrice)
    row.auctionPrice:SetText(
        showAuctionPrice
            and FormatLargestMoney(row.auctionCachedPrice, countSize)
            or ""
    )
    row.auctionPrice:SetShown(showAuctionPrice)
    row.auctionIconRing:SetShown(showAuctionPrice)
    row.auctionIcon:SetShown(showAuctionPrice)
end

local function GetTextWidth(fontString)
    if fontString.GetUnboundedStringWidth then
        return fontString:GetUnboundedStringWidth()
    end
    return fontString:GetStringWidth()
end

MeasureColumnWidths = function()
    local nameSize = Addon:GetSetting("itemNotificationNameFontSize") or 14
    local ringSize = nameSize + 12
    local columns = {
        nameCount = 0,
        bag = 0,
        vendor = 0,
        auction = 0,
    }

    for _, row in ipairs(rows) do
        local nameCountGap = row.moneyAmount and COLUMN_GAP or 0
        columns.nameCount = math.max(
            columns.nameCount,
            GetTextWidth(row.name) + nameCountGap + GetTextWidth(row.count)
        )
        columns.bag = math.max(
            columns.bag,
            ringSize + ICON_TEXT_GAP + GetTextWidth(row.bagCount)
        )
        if row.sellPrice ~= nil then
            columns.vendor = math.max(
                columns.vendor,
                ringSize + ICON_TEXT_GAP + GetTextWidth(row.vendorPrice)
            )
        end
        if row.auctionCachedPrice ~= nil then
            columns.auction = math.max(
                columns.auction,
                ringSize + ICON_TEXT_GAP + GetTextWidth(row.auctionPrice)
            )
        end
    end

    local contentLeft = CONTENT_LEFT + ringSize + ICON_GAP
    local rowWidth = contentLeft
        + columns.nameCount
        + COLUMN_GAP
        + columns.bag
    if columns.vendor > 0 then
        rowWidth = rowWidth + COLUMN_GAP + columns.vendor
    end
    if columns.auction > 0 then
        rowWidth = rowWidth + COLUMN_GAP + columns.auction
    end
    columns.rowWidth = rowWidth + CONTENT_RIGHT
    return columns
end

local function SetRowData(
    row,
    icon,
    nameText,
    quality,
    gainedCount,
    sellPrice,
    bgColor,
    ownedCount,
    moneyAmount,
    auctionCachedPrice
)
    row.moneyAmount = moneyAmount
    row.displayName = nameText or "?"
    row.gainedCount = gainedCount or 1
    row.ownedCount = ownedCount
    row.sellPrice = sellPrice
    row.auctionCachedPrice = auctionCachedPrice
    if moneyAmount then
        row.textIcon:SetAtlas("coin-gold", false)
    else
        row.textIcon:SetTexture(icon)
    end
    row.textIcon:SetShown(moneyAmount ~= nil or icon ~= nil)
    row.iconRing:SetShown(row.textIcon:IsShown())

    local red, green, blue = 1, 1, 1
    if quality and GetItemQualityColor then
        red, green, blue = GetItemQualityColor(quality)
    end
    local accentRed, accentGreen, accentBlue = red, green, blue
    if bgColor then
        accentRed = bgColor[1] or accentRed
        accentGreen = bgColor[2] or accentGreen
        accentBlue = bgColor[3] or accentBlue
    end
    row.accent:SetColorTexture(accentRed, accentGreen, accentBlue, 0.9)
    row.name:SetTextColor(red, green, blue, 1)
    row.count:SetTextColor(red, green, blue, 1)
    row.bagCount:SetTextColor(red, green, blue, 1)
    row.vendorPrice:SetTextColor(red, green, blue, 1)
    row.auctionPrice:SetTextColor(red, green, blue, 1)
    RefreshRowText(row)
end

local function AddNotification(
    icon,
    nameText,
    quality,
    gainedCount,
    sellPrice,
    bgColor,
    tooltipLink,
    ownedCount,
    moneyAmount,
    auctionCachedPrice
)
    local db = DB()
    if not db or not db.showItemNotifications or not container then
        return
    end

    if #rows >= MAX_ROWS then
        RemoveRow(rows[#rows])
    end

    local row = CreateRow()
    SetRowData(
        row,
        icon,
        nameText,
        quality,
        gainedCount,
        sellPrice,
        bgColor,
        ownedCount,
        moneyAmount,
        auctionCachedPrice
    )
    row.nameText = nameText or "?"
    row.tooltipLink = tooltipLink
    table.insert(rows, 1, row)
    Relayout()

    local total = db.itemNotificationDuration or DEFAULT_DURATION
    row.deadline = GetTime() + total
    row.remaining = total
    local duration = math.max(0, total - FADE_DURATION)
    row.timer = C_Timer.NewTimer(duration, function()
        row.timer = nil
        StartRowFade(row)
    end)
end

local function GetOwnedItemCount(itemLink, fallback)
    if C_Item and C_Item.GetItemCount then
        local ok, count = pcall(
            C_Item.GetItemCount,
            itemLink,
            true,
            false,
            true,
            true
        )
        if ok and type(count) == "number" then
            return count
        end
    elseif GetItemCount then
        local ok, count = pcall(GetItemCount, itemLink, true, false, true)
        if ok and type(count) == "number" then
            return count
        end
    end
    return fallback or 0
end

local function HandleItemMessage(message)
    for _, pattern in ipairs(ITEM_LINK_PATTERNS) do
        for link in message:gmatch(pattern) do
            local linkStart = message:find(link, 1, true)
            if linkStart then
                local linkEnd = linkStart + #link - 1
                local gained = 1

                local tail = message:sub(linkEnd + 1, linkEnd + 12)
                local suffixCount = tonumber(tail:match("^%s*[xX×]?%s*(%d+)"))
                if suffixCount then
                    gained = suffixCount
                else
                    local head = message:sub(math.max(1, linkStart - 12), linkStart - 1)
                    local prefixCount = tonumber(head:match("(%d+)%s*[xX×]%s*$"))
                    if prefixCount then
                        gained = prefixCount
                    end
                end

                local name = link:match("%[([^%]]+)%]")
                local quality
                local icon
                local sellPrice
                if C_Item and C_Item.GetItemInfo then
                    local result = { pcall(C_Item.GetItemInfo, link) }
                    if result[1] and result[2] then
                        name = result[2]
                        quality = result[4]
                        icon = result[11]
                        sellPrice = result[12]
                    end
                end
                if (not name or not icon) and GetItemInfo then
                    local result = { pcall(GetItemInfo, link) }
                    if result[1] and result[2] then
                        name = result[2]
                        quality = result[4]
                        if not icon then icon = result[11] end
                        if sellPrice == nil then sellPrice = result[12] end
                    end
                end

                local itemLink = link
                local itemName = name
                local itemQuality = quality
                local itemIcon = icon
                local itemSellPrice = sellPrice
                local itemGained = gained
                C_Timer.After(0, function()
                    GetAuctionatorPrice(itemLink, function(auctionPrice)
                        AddNotification(
                            itemIcon,
                            itemName,
                            itemQuality,
                            itemGained,
                            itemSellPrice,
                            nil,
                            itemLink,
                            GetOwnedItemCount(itemLink, itemGained),
                            nil,
                            auctionPrice
                        )
                    end)
                end)
            end
        end
    end
end

local function HandleMoneyMessage(message)
    local function EscapePattern(text)
        return text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    end

    local function ExtractAmount(...)
        for index = 1, select("#", ...) do
            local formatString = select(index, ...)
            if type(formatString) == "string" then
                local prefix, suffix = formatString:match("^(.-)%%d(.-)$")
                if prefix then
                    local value = message:match(
                        EscapePattern(prefix)
                            .. "([%d%.,]+)"
                            .. EscapePattern(suffix)
                    )
                    if value then
                        return tonumber((value:gsub("[^%d]", ""))) or 0
                    end
                end
            end
        end
        return 0
    end

    local gold = ExtractAmount(GOLD_AMOUNT, GOLD_AMOUNT_TEXTURE, GOLD_AMOUNT_SYMBOL)
    local silver = ExtractAmount(
        SILVER_AMOUNT,
        SILVER_AMOUNT_TEXTURE,
        SILVER_AMOUNT_SYMBOL
    )
    local bronze = ExtractAmount(
        COPPER_AMOUNT,
        COPPER_AMOUNT_TEXTURE,
        COPPER_AMOUNT_SYMBOL
    )
    local gained = gold * 10000 + silver * 100 + bronze
    if gained <= 0 then return end

    C_Timer.After(0.1, function()
        AddNotification(
            nil,
            Addon.L.GOLD_NAME,
            nil,
            GetLargestMoneyAmount(gained),
            nil,
            { 1, 0.82, 0 },
            nil,
            GetMoney(),
            gained
        )
    end)
end

local function HandleCurrencyMessage(message)
    for link in message:gmatch(CURRENCY_LINK_PATTERN) do
        local currencyID = tonumber(link:match("Hcurrency:(%d+)"))
        local name = link:match("%[([^%]]+)%]")
        local linkStart = message:find(link, 1, true)
        local linkEnd = linkStart + #link - 1
        local tail = message:sub(linkEnd + 1, linkEnd + 12)
        local gained = tonumber(tail:match("^%s*[+xX×]?%s*(%d+)")) or 1

        local info = C_CurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo(currencyID)
        local icon = info and info.iconFileID
        if icon == 0 then icon = nil end
        if info and info.name then
            name = info.name
        end
        AddNotification(
            icon,
            name,
            nil,
            gained,
            nil,
            nil,
            nil,
            info and info.quantity or gained
        )
    end
end

local function EnsureContainer()
    if container then return container end

    container = CreateFrame("Frame", "LiteToolsItemNotificationContainer", UIParent)
    container:SetFrameStrata("HIGH")
    container:SetScale(Addon:GetSetting("itemNotificationScale") / 100)
    container:Hide()
    return container
end

local function EnsureAnchor()
    if anchor then return anchor end

    EnsureContainer()
    anchor = Addon.Anchors:Create({
        name = "LiteToolsItemNotificationAnchor",
        label = Addon.L.ITEM_NOTIFICATION_ANCHOR_SHORT,
        positionKey = "itemNotificationPosition",
        hiddenKey = "itemNotificationAnchorHidden",
        defaultX = 0.5,
        defaultY = 0.4,
        movedCallback = Relayout,
    })
    return anchor
end

local function ApplyEnabled(reposition)
    local db = DB()
    if not db then return end

    if db.showItemNotifications then
        local anchorFrame = EnsureAnchor()
        if reposition then
            Addon.Anchors:Position(anchorFrame, "itemNotificationPosition", 0.5, 0.4)
        end
        anchorFrame:SetShown(not db.itemNotificationAnchorHidden)
        EnsureContainer()
        container:SetScale(db.itemNotificationScale / 100)
        container:Show()
        Relayout()
    else
        if anchor then anchor:Hide() end
        if container then container:Hide() end
        for index = #rows, 1, -1 do
            RemoveRow(rows[index])
        end
    end
end

local function IsEnabled(db)
    return db.showItemNotifications
end

Addon:RegisterSetting("showItemNotifications", false, Addon.BooleanSetting, function(value)
    local db = DB()
    if value and db then db.itemNotificationAnchorHidden = false end
    ApplyEnabled(true)
end)
Addon:RegisterSetting(
    "itemNotificationOpacity",
    DEFAULT_OPACITY,
    Addon.NumberSetting(30, 100),
    function(value)
        local alpha = value / 100
        for _, row in ipairs(rows) do
            row:SetAlpha(alpha)
        end
    end
)
Addon:RegisterSetting(
    "itemNotificationScale",
    DEFAULT_SCALE,
    Addon.NumberSetting(50, 200),
    function(value)
        if container then container:SetScale(value / 100) end
    end
)
Addon:RegisterSetting(
    "itemNotificationDuration",
    DEFAULT_DURATION,
    Addon.NumberSetting(2, 15)
)
Addon:RegisterSetting(
    "itemNotificationNameFontSize",
    14,
    Addon.NumberSetting(8, 28),
    function(value)
        for _, row in ipairs(rows) do
            ApplyFontSize(row.name, value)
        end
        Relayout()
    end
)
Addon:RegisterSetting(
    "itemNotificationCountFontSize",
    14,
    Addon.NumberSetting(8, 28),
    function(value)
        for _, row in ipairs(rows) do
            ApplyFontSize(row.count, value)
            ApplyFontSize(row.bagCount, value)
            ApplyFontSize(row.vendorPrice, value)
            ApplyFontSize(row.auctionPrice, value)
            RefreshRowText(row)
        end
        Relayout()
    end
)
Addon:RegisterSetting("itemNotificationDirection", "up", SanitizeDirection, Relayout)
Addon:RegisterSetting("itemNotificationPosition", nil, Addon.PositionSetting)
Addon:RegisterSetting("itemNotificationAnchorHidden", false, Addon.BooleanSetting)

Addon:RegisterEvent("CHAT_MSG_LOOT", function(_, message)
    HandleItemMessage(message)
end, IsEnabled)
Addon:RegisterEvent("CHAT_MSG_MONEY", function(_, message)
    HandleMoneyMessage(message)
end, IsEnabled)
Addon:RegisterEvent("CHAT_MSG_CURRENCY", function(_, message)
    HandleCurrencyMessage(message)
end, IsEnabled)
Addon:RegisterEvent("PLAYER_LOGIN", function() ApplyEnabled(true) end, IsEnabled)
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function() ApplyEnabled(true) end, IsEnabled)
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    Addon:RegisterEvent(event, function() ApplyEnabled(true) end, IsEnabled)
end

local function ShowTestNotifications()
    local db = DB()
    if not db or not db.showItemNotifications then
        print("|cffffd200LiteTools:|r " .. Addon.L.ITEM_TEST_COMMAND_DISABLED)
        return
    end

    EnsureAnchor()
    EnsureContainer()

    local samples = {
        { icon = nil, name = Addon.L.GOLD_NAME, quality = nil,
            gained = GetLargestMoneyAmount(12345678),
            sellPrice = nil,
            bgColor = { 1, 0.82, 0 },
            ownedCount = 24691356,
            moneyAmount = 12345678 },
        { icon = "Interface\\Icons\\INV_Shoulder_01",
            name = string.format(Addon.L.ITEM_TEST_EQUIPMENT, 5), quality = 5,
            gained = 1, sellPrice = 500000, auctionPrice = 870000 },
        { icon = "Interface\\Icons\\INV_Boots_01",
            name = string.format(Addon.L.ITEM_TEST_EQUIPMENT, 4), quality = 4,
            gained = 1, sellPrice = 12500 },
        { icon = "Interface\\Icons\\INV_Sword_13",
            name = string.format(Addon.L.ITEM_TEST_EQUIPMENT, 3), quality = 3,
            gained = 2, sellPrice = 3456, auctionPrice = 250000 },
        { icon = "Interface\\Icons\\INV_Staff_30",
            name = string.format(Addon.L.ITEM_TEST_EQUIPMENT, 2), quality = 2,
            gained = 3, sellPrice = 789 },
        { icon = "Interface\\Icons\\INV_Misc_Herb_Dreamfoil",
            name = string.format(Addon.L.ITEM_TEST_MATERIAL, 1), quality = 1,
            gained = 1, sellPrice = 0, auctionPrice = 8976 },
        { icon = "Interface\\Icons\\INV_Ore_Mithril_01",
            name = string.format(Addon.L.ITEM_TEST_MATERIAL, 2), quality = 2,
            gained = 5, sellPrice = 55 },
        { icon = "Interface\\Icons\\INV_Enchant_EssenceArcaneLarge",
            name = string.format(Addon.L.ITEM_TEST_MATERIAL, 3), quality = 3,
            gained = 4, sellPrice = 120 },
    }

    for index = #samples, 1, -1 do
        local sample = samples[index]
        AddNotification(
            sample.icon,
            sample.name,
            sample.quality,
            sample.gained,
            sample.sellPrice,
            sample.bgColor,
            nil,
            sample.ownedCount or (sample.gained + 10),
            sample.moneyAmount,
            sample.auctionPrice
        )
    end

    print("|cffffd200LiteTools:|r " .. Addon.L.ITEM_TEST_COMMAND_SHOWN)
end

SLASH_LITETOOLSITEMTEST1 = "/ltitemtest"
SLASH_LITETOOLSITEMTEST2 = "/ltloottest"
SlashCmdList.LITETOOLSITEMTEST = ShowTestNotifications

local function ShouldFastLoot(autoLoot)
    if autoLoot ~= nil then
        return autoLoot
    end

    local autoLootDefault = GetCVarBool
        and GetCVarBool("autoLootDefault")
    local autoLootToggle = IsModifiedClick
        and IsModifiedClick("AUTOLOOTTOGGLE")
    return (not not autoLootDefault) ~= (not not autoLootToggle)
end

local function FastLoot(_, autoLoot)
    if not ShouldFastLoot(autoLoot) then return end

    for slot = GetNumLootItems(), 1, -1 do
        LootSlot(slot)
    end
end

Addon:RegisterSetting("fastLoot", false, Addon.BooleanSetting)
Addon:RegisterEvent("LOOT_READY", FastLoot, function(db)
    return db.fastLoot
end)
Addon:RegisterEvent("LOOT_OPENED", FastLoot, function(db)
    return db.fastLoot
end)
