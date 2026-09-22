-- Currency Catalog : Navigation
-- Sends a vendor location to TomTom, or to the built-in waypoint if TomTom
-- is not installed.

local ADDON, ns = ...

-- vendorRec = { name, mapID, x, y, zone }
function ns.NavigateToVendor(vendorRec)
    if not vendorRec then return end
    if not (vendorRec.mapID and vendorRec.x and vendorRec.y) then
        ns.Print(("No saved location for %s yet \226\128\148 visit the vendor once to capture it.")
            :format(vendorRec.name or "that vendor"))
        return
    end

    local title = vendorRec.name or "Vendor"

    -- Preferred: TomTom add-on.
    if TomTom and TomTom.AddWaypoint then
        local ok = pcall(TomTom.AddWaypoint, TomTom, vendorRec.mapID, vendorRec.x, vendorRec.y, {
            title = title,
            from = "Currency Catalog",
            persistent = false,
            minimap = true,
            world = true,
        })
        if ok then
            ns.Print(("TomTom waypoint set: %s (%.1f, %.1f)")
                :format(title, vendorRec.x * 100, vendorRec.y * 100))
            return
        end
    end

    -- Fallback: Blizzard's built-in user waypoint + supertracking.
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        local point = UiMapPoint.CreateFromCoordinates(vendorRec.mapID, vendorRec.x, vendorRec.y)
        C_Map.SetUserWaypoint(point)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        ns.Print(("Map pin set: %s (%.1f, %.1f). Install TomTom for turn-by-turn arrows.")
            :format(title, vendorRec.x * 100, vendorRec.y * 100))
        return
    end

    ns.Print("Could not set a waypoint on this client.")
end
