local _, ns = ...

-- Which client APIs each feature needs, for /tandem check (decision 1). Every Forever API is unverified until checked
-- in game, so a feature whose API is missing stays dark instead of raising.
local Check = {}
ns.Check = Check

-- Per feature, its needs in order; a need is a list of alternative global paths, met when any one is present.
Check.FEATURES = {
    { name = "Item tooltip", needs = {
        { "TooltipDataProcessor.AddTooltipPostCall" }, { "Enum.TooltipDataType.Item" },
    } },
    { name = "Quest sources", needs = {
        { "GetQuestID" }, { "GetQuestItemLink" }, { "GetNumQuestChoices" }, { "GetNumQuestRewards" },
    } },
    { name = "Vendor sources", needs = {
        { "UnitGUID" }, { "GetMerchantNumItems" }, { "GetMerchantItemLink" },
    } },
    { name = "Map pins", needs = {
        { "WorldMapFrame.GetCanvas" }, { "WorldMapFrame.GetMapID" }, { "WorldMapFrame.OnMapChanged" },
        { "OpenWorldMap" }, { "hooksecurefunc" },
    } },
    { name = "Map waypoint", needs = {
        { "C_Map.CanSetUserWaypointOnMap" }, { "C_Map.SetUserWaypoint" }, { "UiMapPoint.CreateFromCoordinates" },
        { "C_SuperTrack.SetSuperTrackedUserWaypoint" },
    } },
    { name = "Quest reward pick", needs = {
        { "GetNumQuestChoices" }, { "GetQuestItemLink" },
        { "QuestInfoRewardsFrame.RewardButtons", "QuestInfoRewardsFrameQuestInfoItem1", "QuestRewardItem1" },
    } },
    { name = "Upgrade alert", needs = {
        { "C_Container.GetContainerNumSlots", "GetContainerNumSlots" },
        { "C_Container.GetContainerItemID", "GetContainerItemID" },
        { "GetInventoryItemLink" },
    } },
    { name = "Item stats", needs = {
        { "C_Item.GetItemStats", "GetItemStats" },
    } },
}

-- Returns true when the dotted global path resolves to a value; never raises on a missing or non-table step.
function Check.Has(path)
    local v = _G
    for key in path:gmatch("[^.]+") do
        if type(v) ~= "table" then
            return false
        end
        v = v[key]
    end
    return v ~= nil
end

-- Returns { {name, ok, apis = { {path, ok}, ... }}, ... } in FEATURES order; ok when every need is met.
function Check.Status()
    local out = {}
    for _, feature in ipairs(Check.FEATURES) do
        local ok, apis = true, {}
        for _, need in ipairs(feature.needs) do
            local met = false
            for _, path in ipairs(need) do
                local has = Check.Has(path)
                met = met or has
                apis[#apis + 1] = { path = path, ok = has }
            end
            ok = ok and met
        end
        out[#out + 1] = { name = feature.name, ok = ok, apis = apis }
    end
    return out
end
