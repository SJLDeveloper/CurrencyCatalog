-- Currency Catalog : Currency-row buttons
-- Adds a small clickable catalog icon next to each currency on the character
-- sheet's Currency tab. Clicking it opens the catalog filtered to that
-- currency, docked beside the character sheet.
--
-- The Currency tab UI (Blizzard_TokenUI) changes between patches, so every hook
-- here is wrapped defensively. If per-row icons ever fail to attach, a
-- guaranteed "Open Catalog" button is added at the bottom of the tab, and the
-- /cc slash command always works.

local ADDON, ns = ...

local ICON = "Interface\\Icons\\inv_misc_coin_02"

-- Best-effort resolution of a currencyID from a token-row frame.
local function resolveCurrencyID(rowFrame)
    if not rowFrame then return nil end
    if rowFrame.currencyTypesID then return rowFrame.currencyTypesID end

    local data = rowFrame.GetElementData and rowFrame:GetElementData()
    if type(data) == "table" then
        if data.currencyTypesID then return data.currencyTypesID end
        if data.currencyInfo and data.currencyInfo.currencyTypesID then
            return data.currencyInfo.currencyTypesID
        end
        if data.index then
            local id = ns.CurrencyIDFromListIndex(data.index)
            if id then return id end
        end
    end

    local idx = rowFrame.index or rowFrame.currencyIndex
    if idx then
        local id = ns.CurrencyIDFromListIndex(idx)
        if id then return id end
    end
    return nil
end

local function ensureRowButton(rowFrame)
    if rowFrame.ccCatalogBtn then return rowFrame.ccCatalogBtn end
    local b = CreateFrame("Button", nil, rowFrame)
    b:SetSize(18, 18)
    b:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
    b:SetFrameLevel(rowFrame:GetFrameLevel() + 5)
    b:SetNormalTexture(ICON)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open Currency Catalog")
        GameTooltip:AddLine("Show everything you can buy with this currency.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        -- Open the catalog showing only this currency.
        ns.OpenForCurrency(self.currencyID)
    end)
    rowFrame.ccCatalogBtn = b
    return b
end

-- Walk the visible currency rows and attach/refresh an icon on each.
local function decorateTokenFrame()
    local tf = _G.TokenFrame
    if not tf then return end

    -- Modern ScrollBox path.
    local sb = tf.ScrollBox
    if sb and sb.GetFrames then
        for _, row in ipairs(sb:GetFrames()) do
            local cid = resolveCurrencyID(row)
            if cid then
                local b = ensureRowButton(row)
                b.currencyID = cid
                b:Show()
            elseif row.ccCatalogBtn then
                row.ccCatalogBtn:Hide()
            end
        end
        return
    end

    -- Legacy TokenFramePanel.buttons path.
    local panel = _G.TokenFramePanel
    if panel and panel.buttons then
        for _, row in ipairs(panel.buttons) do
            if row:IsShown() then
                local cid = resolveCurrencyID(row)
                if cid then
                    local b = ensureRowButton(row)
                    b.currencyID = cid
                    b:Show()
                elseif row.ccCatalogBtn then
                    row.ccCatalogBtn:Hide()
                end
            end
        end
    end
end

-- A guaranteed entry point in the header of the Currency tab, beside the
-- account/character filter dropdown.
local function ensureFooterButton()
    local tf = _G.TokenFrame
    if not tf or tf.ccFooterBtn then return end
    local b = CreateFrame("Button", nil, tf, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetText("Catalog")
    b:SetScript("OnClick", function() ns.ToggleUI() end)

    -- Prefer sitting just above the currency list (the header band where the
    -- "<realm> Only" dropdown lives). Fall back to the frame's top-left.
    if tf.ScrollBox then
        b:SetPoint("BOTTOMLEFT", tf.ScrollBox, "TOPLEFT", 0, 6)
    else
        b:SetPoint("TOPLEFT", tf, "TOPLEFT", 14, -30)
    end
    tf.ccFooterBtn = b
end

local function hookTokenFrame()
    local tf = _G.TokenFrame
    if not tf then return end

    -- Top "Catalog" button is disabled for now (kept in ensureFooterButton so
    -- it can be re-enabled later by uncommenting the line below).
    -- pcall(ensureFooterButton)

    -- Re-decorate whenever the list updates or the tab is shown.
    local sb = tf.ScrollBox
    if sb and sb.RegisterCallback and sb.Event and sb.Event.OnUpdate then
        pcall(function()
            sb:RegisterCallback(sb.Event.OnUpdate, function() pcall(decorateTokenFrame) end, ns)
        end)
    end
    if sb and sb.Update then
        hooksecurefunc(sb, "Update", function() pcall(decorateTokenFrame) end)
    end
    if tf.Update then
        hooksecurefunc(tf, "Update", function() pcall(decorateTokenFrame) end)
    end
    tf:HookScript("OnShow", function() C_Timer.After(0, function() pcall(decorateTokenFrame) end) end)

    pcall(decorateTokenFrame)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_TokenUI" then
        C_Timer.After(0, function() pcall(hookTokenFrame) end)
    elseif event == "PLAYER_LOGIN" then
        -- TokenUI may load on demand; try now and also after it loads.
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_TokenUI") then
            C_Timer.After(0, function() pcall(hookTokenFrame) end)
        end
    end
end)
