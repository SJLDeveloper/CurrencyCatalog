-- Currency Catalog : Scanner
-- Captures merchant inventory + vendor location whenever a vendor is opened.

local ADDON, ns = ...

-- Extract a numeric NPC id from a unit GUID like "Creature-0-1234-...-NPCID-...".
local function npcIDFromGUID(guid)
    -- On some restricted/instanced units the GUID is a "secret" value that throws
    -- when indexed, so match it defensively (no method-call syntax, pcall-guarded).
    if type(guid) ~= "string" then return nil end
    local ok, id = pcall(string.match, guid, "%-(%d-)%-%x+$")
    if ok and id then return tonumber(id) end
    return nil
end

-- The vendor's title is the gray subname under its name (e.g. "Quartermaster").
-- There's no direct API for it, so we read the unit tooltip's second line and
-- reject it if it's actually the "Level ..." line (NPCs without a title).
local scanTip
local function getNPCTitle()
    local levelWord = LEVEL or "Level"

    -- Preferred: modern tooltip data API.
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit("npc")
        if data and data.lines then
            if TooltipUtil and TooltipUtil.SurfaceArgs then
                for _, line in ipairs(data.lines) do
                    pcall(TooltipUtil.SurfaceArgs, line)
                end
            end
            local l2 = data.lines[2] and data.lines[2].leftText
            if type(l2) == "string" and l2 ~= "" then
                local ok, hit = pcall(string.find, l2, levelWord, 1, true)
                if ok and not hit then return l2 end   -- skip if secret (pcall fails)
            end
        end
        return nil
    end

    -- Fallback: scan a hidden tooltip.
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "CurrencyCatalogScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetUnit("npc")
    local fs = _G["CurrencyCatalogScanTipTextLeft2"]
    local txt = fs and fs:GetText()
    scanTip:Hide()
    if type(txt) == "string" and txt ~= "" then
        local ok, hit = pcall(string.find, txt, levelWord, 1, true)
        if ok and not hit then return txt end
    end
    return nil
end

-- Record where the currently-targeted vendor stands.
local function recordVendor()
    local guid = UnitGUID("npc") or UnitGUID("target")
    local npcID = npcIDFromGUID(guid)

    -- Unit name can also be a "secret" value on restricted vendors; concatenating
    -- a secret throws, so sanitise it (the pcall does a harmless concat test).
    local rawName = UnitName("npc") or UnitName("target")
    local name = "Vendor"
    local okName, res = pcall(function() return (rawName or "Vendor") .. "" end)
    if okName and type(res) == "string" then name = res end

    -- Location (these APIs return normal values, not secrets).
    local mapID, zone, x, y
    if C_Map and C_Map.GetBestMapForUnit then
        mapID = C_Map.GetBestMapForUnit("player")
    end
    if mapID then
        local mi = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        zone = mi and mi.name
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local px, py = pos:GetXY()
            if px and py and px > 0 and py > 0 then x, y = px, py end
        end
    end

    -- Fallback key when the GUID is unavailable/secret. Prefer a location-based
    -- key so distinct restricted vendors don't collide on one shared key.
    if not npcID then
        if mapID and x and y then
            npcID = ("loc:%d:%d:%d"):format(mapID, math.floor(x * 1000), math.floor(y * 1000))
        else
            npcID = "name:" .. name
        end
    end

    local rec = ns.db.vendors[npcID] or {}
    rec.name = name
    rec.title = getNPCTitle() or rec.title   -- keep a previously captured title if this read fails
    if mapID then
        rec.mapID = mapID
        rec.zone = zone or rec.zone
    end
    if x and y then
        rec.x = x
        rec.y = y
    end
    rec.last = time()
    ns.db.vendors[npcID] = rec
    return npcID
end

-- Parse a currency id out of a currency link.
local function currencyIDFromLink(link)
    if not link then return nil end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyIDFromLink then
        local ok, id = pcall(C_CurrencyInfo.GetCurrencyIDFromLink, link)
        if ok and id then return id end
    end
    local id = link:match("currency:(%d+)")
    return id and tonumber(id)
end

-- Read every "extended cost" component of merchant item `index`.
-- Returns: table currencyID->amount, and gold copper amount (number).
local function readCosts(index, basePrice)
    local costs = {}
    local gold = (basePrice and basePrice > 0) and basePrice or nil

    if not (GetMerchantItemCostInfo and GetMerchantItemCostItem) then
        return costs, gold
    end
    local numCost = GetMerchantItemCostInfo(index) or 0
    for ci = 1, numCost do
        local _, costValue, costLink, currencyName = GetMerchantItemCostItem(index, ci)
        if costLink and costLink:find("currency:") then
            local cid = currencyIDFromLink(costLink)
            if cid and costValue and costValue > 0 then
                costs[cid] = (costs[cid] or 0) + costValue
                -- Make sure we know this currency's display info.
                local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(cid)
                if info then
                    local rec = ns.db.currencies[cid] or {}
                    rec.name = info.name or rec.name
                    rec.icon = info.iconFileID or rec.icon
                    ns.db.currencies[cid] = rec
                end
            end
        end
        -- (Item-based extended costs, e.g. "5x [Mark of Honor]", are ignored:
        --  the brief targets currencies, not item-for-item trades. Easy to add later.)
    end

    return costs, gold
end

-- Has at least one non-gold currency cost?
local function hasCurrencyCost(costs)
    for _ in pairs(costs) do return true end
    return false
end

-- Merchant item info. The old global GetMerchantItemInfo was removed on current
-- clients in favour of C_MerchantFrame.GetItemInfo (which returns a table).
local function merchantItemInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(index)
        if t then
            return t.name, t.texture, t.price, t.numAvailable, t.isPurchasable, t.hasExtendedCost
        end
    end
    if GetMerchantItemInfo then
        local name, texture, price, _, numAvailable, isPurchasable = GetMerchantItemInfo(index)
        return name, texture, price, numAvailable, isPurchasable
    end
    return nil
end

-- Item info. The global GetItemInfo / GetItemInfoInstant shims were removed in
-- 12.1.5 (Blizzard_Deprecated* addons dropped); prefer the C_Item namespace and
-- keep the globals as a fallback for older clients.
local function itemInfoInstant(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(fn) ~= "function" then return nil end
    local ok, itemID, itemType, itemSubType, equipLoc, icon, classID, subClassID = pcall(fn, link)
    if not ok then return nil end
    return itemID, itemType, itemSubType, equipLoc, icon, classID, subClassID
end

local function itemQuality(link)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(fn) ~= "function" then return nil end
    local ok, _, _, quality = pcall(fn, link)
    if ok then return quality end
    return nil
end

local function scanMerchant()
    local npcID = recordVendor()
    local n = GetMerchantNumItems() or 0
    local found = 0
    local offered = {}   -- itemIDs this vendor currently sells for a currency

    for i = 1, n do
        local itemLink = GetMerchantItemLink(i)
        local name, texture, price = merchantItemInfo(i)
        if itemLink and name then
            local costs, gold = readCosts(i, price)
            if hasCurrencyCost(costs) then
                local itemID, itemType, itemSubType, equipLoc, _, classID, subClassID = itemInfoInstant(itemLink)
                if itemID then
                    offered[itemID] = true
                    local quality = itemQuality(itemLink)
                    local cosmetic = false
                    if C_Item and C_Item.IsCosmeticItem then
                        local okc, res = pcall(C_Item.IsCosmeticItem, itemID)
                        if okc then cosmetic = res and true or false end
                    end
                    local rec = ns.db.items[itemID] or { costs = {}, vendors = {} }
                    rec.name = name
                    rec.icon = texture or rec.icon
                    rec.link = itemLink
                    rec.quality = quality or rec.quality
                    rec.classID = classID
                    rec.subClassID = subClassID
                    rec.equipLoc = equipLoc
                    rec.itemType = itemType
                    rec.itemSubType = itemSubType
                    rec.cosmetic = cosmetic
                    rec.gold = gold
                    rec.costs = costs
                    rec.vendors = rec.vendors or {}
                    rec.vendors[npcID] = true
                    ns.db.items[itemID] = rec
                    found = found + 1
                end
            end
        end
    end

    -- Prune: drop this vendor from any catalogued item it no longer offers, so
    -- cyclic stock and one-time purchases stay accurate. Skip when the merchant
    -- list is filtered (we might not be seeing the vendor's full inventory).
    local fullList = (not GetMerchantFilter) or (GetMerchantFilter() == (LE_LOOT_FILTER_ALL or 1))
    if fullList then
        for itemID, rec in pairs(ns.db.items) do
            if rec.vendors and rec.vendors[npcID] and not offered[itemID] then
                rec.vendors[npcID] = nil
                if next(rec.vendors) == nil then
                    ns.db.items[itemID] = nil   -- no vendors left; forget the item
                end
            end
        end
    end

    if ns.RefreshUI then ns.RefreshUI() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")
f:SetScript("OnEvent", function()
    -- Item data can be momentarily unavailable on first show; a tiny delay helps.
    C_Timer.After(0.2, function()
        if MerchantFrame and MerchantFrame:IsShown() then
            local ok, err = pcall(scanMerchant)
            if not ok then ns.Print("scan error:", err) end
        end
    end)
end)
