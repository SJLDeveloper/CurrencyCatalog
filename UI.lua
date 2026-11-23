-- Currency Catalog : UI
-- A catalog window docked to the right of the character sheet. It opens for ONE
-- currency at a time (the one whose icon was clicked on the Currency tab):
--   header : selected currency icon + name + your balance + a sort dropdown
--   list   : full-width, searchable list of items buyable with that currency,
--            sortable Alphabetical / By Vendor (Zone > Vendor, collapsible)
--   detail : clicking an item opens a panel listing its vendor(s); clicking a
--            vendor fires a TomTom / map waypoint.

local ADDON, ns = ...

local ROW_H        = 26
local ITEM_ROWS    = 14
local FRAME_W      = 430        -- wide enough for long names e.g. "Displaced Corrupted Mementos"
local LIST_TOP     = 132        -- distance from frame top to the list
local FOOTER       = 36
local FRAME_H      = LIST_TOP + ITEM_ROWS * ROW_H + FOOTER

local frame, detail
local itemButtons, vendorButtons = {}, {}
local displayRows = {}

ns.selectedCurrency = nil
ns.selectedItem     = nil
ns.sortMode         = ns.sortMode or "alpha"   -- "alpha" | "vendor"
ns.collapsed        = ns.collapsed or { zone = {}, vendor = {}, category = {} }
ns.collapsed.zone     = ns.collapsed.zone or {}
ns.collapsed.vendor   = ns.collapsed.vendor or {}
ns.collapsed.category = ns.collapsed.category or {}

local SORTS = {
    { key = "alpha",    label = "Alphabetical" },
    { key = "vendor",   label = "By Vendor" },
}

-- ---------- data assembly ----------

local function byName(a, b) return (a.name or "") < (b.name or "") end

-- "Gelanthis  <Jewelcrafting Supplies>" with the title in gray.
local function vendorLabel(g)
    local label = g.name or "Vendor"
    local t = g.title
    if t and t ~= "" then
        t = t:gsub("^%s*<", ""):gsub(">%s*$", "")
        label = label .. "  |cff9d9d9d<" .. t .. ">|r"
    end
    return label
end

-- Name of the zone the player is currently standing in (or nil).
local function currentZoneName()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local mi = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return mi and mi.name
end

-- Effective collapsed state for a group, when the user hasn't toggled it:
--   zone     -> collapsed, except the player's current zone (starts open)
--   vendor   -> collapsed
local function isCollapsed(mode, key)
    local t = ns.collapsed[mode]
    local v = t and t[key]
    if v ~= nil then return v end
    if mode == "zone" then return key ~= currentZoneName() end
    if mode == "vendor" then return true end
    return false
end

-- Default currency when opened without a choice: largest held balance.
local function defaultCurrency()
    local best, bestQ
    for id, c in pairs(ns.GetHeldCurrencies()) do
        if not bestQ or (c.quantity or 0) > bestQ then best, bestQ = id, c.quantity or 0 end
    end
    if best then return best end
    for id in pairs(ns.db.currencies) do return id end
    return nil
end

-- Items (already filtered by selected currency + search) as a flat array.
local function buildRawItems()
    local out = {}
    local cid = ns.selectedCurrency
    if not cid then return out end
    local search = (frame and frame.search:GetText() or ""):lower()
    for itemID, rec in pairs(ns.db.items) do
        if rec.costs and rec.costs[cid] then
            if search == "" or (rec.name and rec.name:lower():find(search, 1, true)) then
                out[#out + 1] = {
                    id = itemID,
                    name = rec.name or ("Item " .. itemID),
                    icon = rec.icon,
                    quality = rec.quality,
                    amount = rec.costs[cid],
                    rec = rec,
                }
            end
        end
    end
    return out
end

-- Turn the raw items into display rows (with group headers) per sort mode.
local function buildDisplayRows()
    local items = buildRawItems()
    local mode = ns.sortMode or "alpha"
    local rows = {}

    if mode == "vendor" then
        -- Group items by vendor.
        local vendors, vkeys = {}, {}
        for _, it in ipairs(items) do
            local placed = false
            for npcID in pairs(it.rec.vendors or {}) do
                placed = true
                local g = vendors[npcID]
                if not g then
                    local v = ns.db.vendors[npcID]
                    g = { name = (v and v.name) or "Unknown vendor", title = v and v.title, zone = (v and v.zone) or "Unknown zone", items = {} }
                    vendors[npcID] = g
                    vkeys[#vkeys + 1] = npcID
                end
                g.items[#g.items + 1] = it
            end
            if not placed then
                local g = vendors["__none"]
                if not g then g = { name = "Unknown vendor", zone = "Unknown zone", items = {} } vendors["__none"] = g vkeys[#vkeys + 1] = "__none" end
                g.items[#g.items + 1] = it
            end
        end

        -- Group vendors by zone.
        local zones, zkeys = {}, {}
        for _, npcID in ipairs(vkeys) do
            local zkey = vendors[npcID].zone or "Unknown zone"
            local z = zones[zkey]
            if not z then z = { vkeys = {} } zones[zkey] = z zkeys[#zkeys + 1] = zkey end
            z.vkeys[#z.vkeys + 1] = npcID
        end
        table.sort(zkeys, function(a, b) return a < b end)

        -- Emit Zone -> Vendor -> items.
        for _, zkey in ipairs(zkeys) do
            local z = zones[zkey]
            rows[#rows + 1] = { header = true, cns = "zone", key = zkey, label = zkey, count = #z.vkeys, indent = 0 }
            if not isCollapsed("zone", zkey) then
                table.sort(z.vkeys, function(a, b) return (vendors[a].name or "") < (vendors[b].name or "") end)
                for _, npcID in ipairs(z.vkeys) do
                    local g = vendors[npcID]
                    table.sort(g.items, byName)
                    rows[#rows + 1] = { header = true, cns = "vendor", key = npcID, label = vendorLabel(g), count = #g.items, indent = 16 }
                    if not isCollapsed("vendor", npcID) then
                        for _, it in ipairs(g.items) do
                            it.indent = 32
                            rows[#rows + 1] = it
                        end
                    end
                end
            end
        end

    else -- alpha
        table.sort(items, byName)
        for _, it in ipairs(items) do rows[#rows + 1] = it end
    end

    return rows
end

-- ---------- detail panel ----------

local function hideDetail()
    if detail then detail:Hide() end
    ns.selectedItem = nil
end

local function refreshDetail()
    if not (detail and detail:IsShown()) then return end
    local itemID = ns.selectedItem
    local rec = itemID and ns.db.items[itemID]
    if not rec then detail:Hide() return end

    detail.icon:SetTexture(rec.icon or 134400)
    local r, g, b = 1, 1, 1
    if rec.quality and C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(rec.quality)
    end
    detail.title:SetTextColor(r, g, b)
    detail.title:SetText(rec.name or "")

    local lines = {}
    for cid, amount in pairs(rec.costs or {}) do
        local c = ns.db.currencies[cid]
        local tex = c and c.icon and ("|T" .. c.icon .. ":14:14:0:0|t") or ""
        lines[#lines + 1] = ("%s %d  %s"):format(tex, amount, c and c.name or ("Currency " .. cid))
    end
    if rec.gold and rec.gold > 0 then
        -- GetCoinTextureString global shim removed in 12.1.5; use C_CurrencyInfo.
        local coinFn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
        if coinFn then
            lines[#lines + 1] = coinFn(rec.gold)
        else
            lines[#lines + 1] = ("%dg"):format(math.floor(rec.gold / 10000))
        end
    end
    detail.cost:SetText("Cost: " .. table.concat(lines, "   "))

    for _, btn in ipairs(vendorButtons) do btn:Hide() end
    local i = 0
    for npcID in pairs(rec.vendors or {}) do
        local v = ns.db.vendors[npcID]
        if v then
            i = i + 1
            local btn = vendorButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
                btn:SetSize(220, 34)
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.text:SetPoint("LEFT", 8, 0)
                btn.text:SetJustifyH("LEFT")
                btn.text:SetWidth(204)
                btn:SetFontString(btn.text)
                vendorButtons[i] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", detail.vendorHeader, "BOTTOMLEFT", 0, -6 - (i - 1) * 38)
            local vn = v.name or "Vendor"
            if v.title and v.title ~= "" then
                vn = vn .. " <" .. v.title:gsub("^%s*<", ""):gsub(">%s*$", "") .. ">"
            end
            local loc
            if v.x and v.y then
                loc = ("%s\n%s (%.1f, %.1f)"):format(vn, v.zone or "?", v.x * 100, v.y * 100)
            else
                loc = ("%s\n(location not captured \226\128\148 visit once)"):format(vn)
            end
            btn.text:SetText(loc)
            btn.vendorRec = v
            btn:SetScript("OnClick", function(self) ns.NavigateToVendor(self.vendorRec) end)
            btn:Show()
        end
    end
    detail.noVendor:SetShown(i == 0)
end

local function buildDetail()
    detail = CreateFrame("Frame", "CurrencyCatalogDetail", frame, "BackdropTemplate")
    detail:SetSize(250, FRAME_H)
    detail:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    detail:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    detail:SetBackdropColor(0.06, 0.06, 0.08, 1)        -- fully opaque
    detail:SetBackdropBorderColor(1, 1, 1, 1)
    detail:SetFrameStrata("HIGH")
    detail:Hide()

    detail.icon = detail:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(32, 32)
    detail.icon:SetPoint("TOPLEFT", 14, -14)

    detail.title = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detail.title:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 8, -2)
    detail.title:SetPoint("RIGHT", -10, 0)
    detail.title:SetJustifyH("LEFT")
    detail.title:SetWordWrap(true)

    detail.cost = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.cost:SetPoint("TOPLEFT", detail.icon, "BOTTOMLEFT", 0, -10)
    detail.cost:SetPoint("RIGHT", -10, 0)
    detail.cost:SetJustifyH("LEFT")
    detail.cost:SetWordWrap(true)

    detail.vendorHeader = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detail.vendorHeader:SetPoint("TOPLEFT", detail.cost, "BOTTOMLEFT", 0, -12)
    detail.vendorHeader:SetText("Sold by \226\128\148 click to set a waypoint:")

    detail.noVendor = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail.noVendor:SetPoint("TOPLEFT", detail.vendorHeader, "BOTTOMLEFT", 0, -8)
    detail.noVendor:SetText("No vendor recorded.")
    detail.noVendor:Hide()

    local close = CreateFrame("Button", nil, detail, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", hideDetail)
end

local function openDetail(itemID)
    ns.selectedItem = itemID
    if not detail then buildDetail() end
    detail:Show()
    refreshDetail()
end

-- ---------- list rendering ----------

local function updateItemScroll()
    local offset = FauxScrollFrame_GetOffset(frame.itemScroll)
    for i = 1, ITEM_ROWS do
        local idx = i + offset
        local btn = itemButtons[i]
        local data = displayRows[idx]
        if data then
            local indent = data.indent or 0
            if data.header then
                btn.kind = "header"
                btn.key = data.key
                btn.cns = data.cns
                btn.id = nil
                btn.icon:Hide()
                local sign = isCollapsed(data.cns, data.key) and "+" or "-"
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", 6 + indent, 0)
                btn.label:SetPoint("RIGHT", btn.cost, "LEFT", -4, 0)
                btn.label:SetText(("|cffffd200[%s] %s|r"):format(sign, data.label))
                btn.cost:SetText(("|cffffd200%d|r"):format(data.count or 0))
                btn:Show()
            else
                btn.kind = "item"
                btn.key = nil
                btn.cns = nil
                btn.id = data.id
                btn.icon:ClearAllPoints()
                btn.icon:SetPoint("LEFT", 2 + indent, 0)
                btn.icon:SetTexture(data.icon or 134400)
                btn.icon:Show()
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
                btn.label:SetPoint("RIGHT", btn.cost, "LEFT", -4, 0)
                local r, g, b = 1, 1, 1
                if data.quality and C_Item and C_Item.GetItemQualityColor then
                    r, g, b = C_Item.GetItemQualityColor(data.quality)
                end
                btn.label:SetText(data.name)
                btn.label:SetTextColor(r, g, b)
                btn.cost:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(data.amount) or tostring(data.amount))
                btn:Show()
            end
        else
            btn:Hide()
        end
    end
    FauxScrollFrame_Update(frame.itemScroll, #displayRows, ITEM_ROWS, ROW_H)
end

-- ---------- public refresh ----------

function ns.RefreshUI()
    if not (frame and frame:IsShown()) then return end
    displayRows = buildDisplayRows()
    updateItemScroll()

    local cid = ns.selectedCurrency
    local c = cid and ns.db.currencies[cid]
    frame.curIcon:SetTexture((c and c.icon) or 134400)
    frame.curName:SetText((c and c.name) or "Currency")
    if cid then
        frame.balance:SetText(("You have: %d"):format(ns.GetCurrencyQuantity(cid)))
    else
        frame.balance:SetText("")
    end
    frame.empty:SetShown(#displayRows == 0)
    refreshDetail()
end

-- ---------- sort dropdown ----------

local function buildSortDropdown()
    -- Modern dropdown (Dragonflight+). Guarded so a template change can't break load.
    local ok, dd = pcall(CreateFrame, "DropdownButton", "CurrencyCatalogSortDrop", frame, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(120)
        dd:SetupMenu(function(_, root)
            for _, s in ipairs(SORTS) do
                root:CreateRadio(s.label,
                    function() return ns.sortMode == s.key end,
                    function()
                        ns.sortMode = s.key
                        ns.RefreshUI()
                    end)
            end
        end)
        return dd
    end
    return nil
end

-- ---------- frame construction ----------

local function buildFrame()
    frame = CreateFrame("Frame", "CurrencyCatalogFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.08, 1)        -- fully opaque
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingSizing)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Currency Catalog")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() ns.HideUI() end)

    -- Selected-currency header (full width; the currency name can be long).
    frame.curIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.curIcon:SetSize(28, 28)
    frame.curIcon:SetPoint("TOPLEFT", 16, -40)

    frame.curName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.curName:SetPoint("LEFT", frame.curIcon, "RIGHT", 8, 0)
    frame.curName:SetPoint("RIGHT", -16, 0)
    frame.curName:SetJustifyH("LEFT")
    frame.curName:SetWordWrap(false)

    frame.balance = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.balance:SetPoint("TOPLEFT", frame.curIcon, "BOTTOMLEFT", 0, -8)

    -- Search box (shortened to leave room for the sort dropdown beside it).
    local search = CreateFrame("EditBox", "CurrencyCatalogSearch", frame, "InputBoxTemplate")
    search:SetSize(FRAME_W - 170, 20)
    search:SetPoint("TOPLEFT", frame.balance, "BOTTOMLEFT", 8, -12)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() ns.RefreshUI() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.search = search

    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", -4, 2)
    searchLabel:SetText("Search items")

    -- Sort dropdown, on the search row to the right of the search box.
    frame.sortDrop = buildSortDropdown()
    if frame.sortDrop then
        frame.sortDrop:SetWidth(130)
        frame.sortDrop:SetPoint("LEFT", search, "RIGHT", 10, 0)
    end

    -- Item scroll (full width, fixed offset from the top so rows always fit).
    local itemScroll = CreateFrame("ScrollFrame", "CurrencyCatalogItemScroll", frame, "FauxScrollFrameTemplate")
    itemScroll:SetPoint("TOPLEFT", 14, -LIST_TOP)
    itemScroll:SetSize(FRAME_W - 48, ITEM_ROWS * ROW_H)
    itemScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, updateItemScroll)
    end)
    frame.itemScroll = itemScroll

    for i = 1, ITEM_ROWS do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(FRAME_W - 52, ROW_H)
        if i == 1 then
            btn:SetPoint("TOPLEFT", itemScroll, "TOPLEFT", 0, 0)
        else
            btn:SetPoint("TOPLEFT", itemButtons[i - 1], "BOTTOMLEFT", 0, 0)
        end
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(18, 18)
        btn.icon:SetPoint("LEFT", 2, 0)
        btn.cost = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.cost:SetPoint("RIGHT", -4, 0)
        btn.cost:SetJustifyH("RIGHT")
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
        btn.label:SetPoint("RIGHT", btn.cost, "LEFT", -4, 0)
        btn.label:SetJustifyH("LEFT")
        btn.label:SetWordWrap(false)
        btn:SetScript("OnClick", function(self)
            if self.kind == "header" then
                local t = ns.collapsed[self.cns]
                if t and self.key ~= nil then t[self.key] = not isCollapsed(self.cns, self.key) end
                ns.RefreshUI()
            elseif self.id then
                openDetail(self.id)
            end
        end)
        btn:SetScript("OnEnter", function(self)
            if self.kind == "item" and self.id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.id)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        itemButtons[i] = btn
    end

    -- Empty-state message.
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOP", itemScroll, "TOP", 0, -40)
    frame.empty:SetWidth(FRAME_W - 60)
    frame.empty:SetText("Nothing catalogued for this currency yet.\nVisit a vendor that sells for it to fill this in.")
    frame.empty:Hide()

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 12)
    hint:SetPoint("BOTTOMRIGHT", -16, 12)
    hint:SetJustifyH("CENTER")
    hint:SetText("Click an item for its vendor. Click a group header to collapse it.")
end

-- ---------- show / hide / toggle / docking ----------

local function dockToCharacterFrame()
    if not frame then return end
    if CharacterFrame and CharacterFrame:IsShown() then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 6, 0)
    end
end

function ns.ShowUI()
    if not frame then buildFrame() end
    if not ns.selectedCurrency then ns.selectedCurrency = defaultCurrency() end
    dockToCharacterFrame()
    frame:Show()
    if frame.search then frame.search:SetText("") end
    ns.RefreshUI()
end

function ns.HideUI()
    if frame then frame:Hide() end
    hideDetail()
end

function ns.ToggleUI()
    if not frame then buildFrame() end
    if frame:IsShown() then ns.HideUI() else ns.ShowUI() end
end

-- Open the catalog for a specific currency (called by the Currency-tab icons).
function ns.OpenForCurrency(currencyID)
    if currencyID then ns.selectedCurrency = currencyID end
    hideDetail()
    ns.ShowUI()
end
-- Backwards-compatible alias.
ns.SelectCurrency = ns.OpenForCurrency

-- Hide the catalog when the character sheet closes (it is docked to it).
function ns.OnLogin()
    if CharacterFrame then
        CharacterFrame:HookScript("OnHide", function()
            ns.HideUI()
        end)
    end
end
