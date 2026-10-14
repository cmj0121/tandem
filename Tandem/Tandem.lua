local addonName, ns = ...

ns.name = addonName

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function onLoaded(self, event, loadedName)
    if loadedName ~= addonName then
        return
    end

    self:UnregisterEvent(event)
    local L = ns.L
    local db, report = ns.Store.Load(TandemDB)
    TandemDB = db
    print(L["%s loaded"]:format(addonName))

    if report.status == "newer" then
        print(L["%s: saved data uses newer schema %d; recording is off until the addon is updated"]:format(
            addonName, report.version))
    elseif report.status == "reset" then
        print(L["%s: saved data was unreadable and has been reset"]:format(addonName))
    end
    if report.dropped > 0 then
        print(L["%s: dropped %d invalid saved entries"]:format(addonName, report.dropped))
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        onLoaded(self, event, ...)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.Scanner.OnItemInfo(...)
    end
end)
