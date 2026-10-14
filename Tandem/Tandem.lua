local addonName, ns = ...

ns.name = addonName

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedName)
    if loadedName ~= addonName then
        return
    end

    self:UnregisterEvent(event)
    print(ns.L["%s loaded"]:format(addonName))
end)
