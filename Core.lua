-- Currency Catalog : Core
-- Addon namespace, saved-vars bootstrap, shared helpers, slash command.

local ADDON, ns = ...

ns.name = ADDON
ns.version = "1.2.3"

-- Default shape of the persisted database.
local DB_DEFAULTS = {
    version = 1,
    -- currencyID -> { name, icon }
    currencies = {},
    -- npcID -> { name, mapID, x, y, zone, last }
    vendors = {},
    -- itemID -> {
    --     name, icon, link, quality,
    --     costs   = { [currencyID] = amount, ... },  -- non-gold currencies
    --     gold    = copperAmount or nil,
    --     vendors = { [npcID] = true, ... },
    -- }
    items = {},
    settings = {
        autoOpenWithCharFrame = false,
    },
}

-- Shallow+nested default fill (does not overwrite existing user data).
local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Lightweight print helper.
function ns.Print(...)
    local prefix = "|cff66ccffCurrencyCatalog|r:"
    print(prefix, ...)
end

-- Resolve a real currencyID from a Currency-tab list index. GetCurrencyListInfo
-- does NOT reliably expose currencyTypesID, so we fall back to the row's link.
function ns.CurrencyIDFromListIndex(index, info)
    local C = C_CurrencyInfo
    if not C then return nil end
    if info and info.currencyTypesID then return info.currencyTypesID end
    if C.GetCurrencyListLink then
        local link = C.GetCurrencyListLink(index)
        if link then
            if C.GetCurrencyIDFromLink then
                local ok, id = pcall(C.GetCurrencyIDFromLink, link)
                if ok and id then return id end
            end
            local id = link:match("currency:(%d+)")
            if id then return tonumber(id) end
        end
    end
    return nil
end

-- Returns the live currency list (currencyID -> {name, icon, quantity}) the
-- player currently holds. Used so the catalog can show currencies even before
-- any matching vendor has been scanned.
function ns.GetHeldCurrencies()
    local out = {}
    local C = C_CurrencyInfo
    if not C or not C.GetCurrencyListSize then return out end
    local size = C.GetCurrencyListSize() or 0
    for i = 1, size do
        local info = C.GetCurrencyListInfo(i)
        if info and not info.isHeader then
            local id = ns.CurrencyIDFromListIndex(i, info)
            if id then
                out[id] = {
                    name = info.name,
                    icon = info.iconFileID,
                    quantity = info.quantity or 0,
                }
            end
        end
    end
    return out
end

-- Current quantity of a specific currency the player holds.
function ns.GetCurrencyQuantity(currencyID)
    local C = C_CurrencyInfo
    if not C or not C.GetCurrencyInfo then return 0 end
    local info = C.GetCurrencyInfo(currencyID)
    return (info and info.quantity) or 0
end

-- Merge the held-currency metadata into the DB so names/icons persist.
function ns.RememberHeldCurrencies()
    local held = ns.GetHeldCurrencies()
    for id, c in pairs(held) do
        local rec = ns.db.currencies[id] or {}
        rec.name = c.name or rec.name
        rec.icon = c.icon or rec.icon
        ns.db.currencies[id] = rec
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        CurrencyCatalogDB = CurrencyCatalogDB or {}
        ns.db = applyDefaults(CurrencyCatalogDB, DB_DEFAULTS)
    elseif event == "PLAYER_LOGIN" then
        ns.RememberHeldCurrencies()
        if ns.OnLogin then ns.OnLogin() end

        -- Greeting / summary.
        local nItems, nVendors = 0, 0
        for _ in pairs(ns.db.items) do nItems = nItems + 1 end
        for _ in pairs(ns.db.vendors) do nVendors = nVendors + 1 end
        ns.Print(("%d vendors, %d items known."):format(nVendors, nItems))
        print("|cff66ccffCurrency Catalog|r: Thank you for using CCat!")
    end
end)

-- Slash command: /cc  or  /currencycatalog
SLASH_CURRENCYCATALOG1 = "/cc"
SLASH_CURRENCYCATALOG2 = "/currencycatalog"
SlashCmdList.CURRENCYCATALOG = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "wipe" then
        wipe(ns.db.items)
        wipe(ns.db.vendors)
        ns.Print("Catalog data wiped.")
        if ns.RefreshUI then ns.RefreshUI() end
    elseif msg == "stats" then
        local nItems, nVendors = 0, 0
        for _ in pairs(ns.db.items) do nItems = nItems + 1 end
        for _ in pairs(ns.db.vendors) do nVendors = nVendors + 1 end
        ns.Print(("%d items from %d vendors catalogued."):format(nItems, nVendors))
    elseif msg == "debug" then
        -- Dump item classification (useful for future categorisation work).
        local n, shown = 0, 0
        for itemID, rec in pairs(ns.db.items) do
            n = n + 1
            if shown < 40 then
                shown = shown + 1
                ns.Print(("%s | class=%s sub=%s equip=%s subtype=%s cosmetic=%s"):format(
                    rec.link or rec.name or tostring(itemID),
                    tostring(rec.classID), tostring(rec.subClassID),
                    tostring(rec.equipLoc), tostring(rec.itemSubType), tostring(rec.cosmetic)))
            end
        end
        ns.Print(("dumped %d of %d items."):format(shown, n))
    else
        if ns.ToggleUI then ns.ToggleUI() end
    end
end
