local addonName, ns = ...

ns.name = addonName

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("LOOT_CLOSED")

local function onLoaded(self, event, loadedName)
    if loadedName ~= addonName then
        return
    end

    self:UnregisterEvent(event)
    local L = ns.L
    local db, report = ns.Store.Load(TandemDB)
    TandemDB = db
    ns.Kills.Register(self)
    print(L["%s loaded"]:format(addonName))

    if report.status == "newer" then
        print(L["%s: saved data uses newer schema %d; recording is off until the addon is updated"]:format(
            addonName, report.version))
    elseif report.status == "migrated" and type(report.version) == "number" and report.version >= 0
        and report.version < math.huge and report.version == math.floor(report.version) then
        print(L["%s: saved data upgraded from schema %d to %d"]:format(addonName, report.version, ns.Store.SCHEMA))
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
    elseif event == "LOOT_READY" then
        ns.Loot.OnLootReady()
    elseif event == "LOOT_CLOSED" then
        ns.Loot.OnLootClosed()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ns.Kills.OnCombatLog()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_LOGOUT" then
        ns.Kills.Flush(event == "PLAYER_LOGOUT")
    end
end)
