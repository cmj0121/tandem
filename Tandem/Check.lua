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
    { name = "Stat search", needs = {
        { "C_TooltipInfo.GetItemByID" },
    } },
    { name = "Talent spec", needs = {
        { "GetTalentTabInfo", "C_SpecializationInfo.GetSpecialization", "GetSpecialization" },
    } },
    { name = "Trainer record", needs = {
        { "GetNumTrainerServices" }, { "GetTrainerServiceInfo" }, { "GetTrainerServiceLevelReq" },
        { "C_TooltipInfo.GetTrainerService" },
    } },
    { name = "Action bar borders", needs = {
        { "GetActionInfo" }, { "GetSpellInfo", "C_Spell.GetSpellInfo" }, { "IsSpellKnown", "IsPlayerSpell" },
        { "ActionButton1" },
    } },
    { name = "Upgrade borders", needs = {
        { "C_Container.GetContainerNumSlots", "GetContainerNumSlots" },
        { "C_Container.GetContainerItemID", "GetContainerItemID" },
        { "GetInventoryItemLink" },
        { "ContainerFrame1Item1", "ContainerFrameCombinedBags" },
    } },
    { name = "Layout", needs = {
        { "C_EditMode.GetLayouts" }, { "C_EditMode.SaveLayouts" }, { "C_EditMode.SetActiveLayout" },
        { "EditModeManagerFrame" }, { "EditModePresetLayoutManager.GetCopyOfPresetLayouts" },
        { "MainActionBar", "MainMenuBar" },
    } },
    { name = "XP bar", needs = {
        { "UnitXP" }, { "UnitXPMax" },
    } },
    { name = "Bag button", needs = {
        { "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots" }, { "ToggleAllBags" },
    } },
    { name = "Shaman area", needs = {
        { "GetTotemInfo" }, { "GetWeaponEnchantInfo" }, { "UnitPower" },
    } },
}

-- Client paths /tandem check reports for in-game diagnosis; they gate nothing.
Check.PROBES = {
    "LootButton1", "LootFrame.ScrollBox", "LootFrame_Update", "ContainerFrame1Item1.IconBorder",
    "ContainerFrame1Item1.NewItemTexture", "ContainerFrame1Item1.UpgradeIcon", "Enum.EditModeSystem.ChatFrame",
    "MainStatusTrackingBarContainer", "BagsBar", "C_UnitAuras.GetAuraDataBySpellName", "UnitBuff",
    "Enum.EditModeSystem.MicroMenu", "Enum.EditModeSystem.Minimap", "Enum.EditModeSystem.AuraFrame",
    "Enum.EditModeActionBarSetting.HideBarArt", "MainActionBar.EndCaps", "MainMenuBar.EndCaps",
    "MainMenuBarArtFrame.LeftEndCap", "MainMenuBarLeftEndCap",
}

-- Returns true when the dotted global path resolves to a value; never raises on a missing or non-table step.
-- A step that raises (an __index metamethod on a client frame) counts as missing.
function Check.Has(path)
    local ok, found = pcall(function()
        local v = _G
        for key in path:gmatch("[^.]+") do
            if type(v) ~= "table" then
                return false
            end
            v = v[key]
        end
        return v ~= nil
    end)
    return ok and found
end

-- Returns true when every need of the named feature is met; a feature gates on this before touching its API.
function Check.Ready(name)
    for _, feature in ipairs(Check.FEATURES) do
        if feature.name == name then
            for _, need in ipairs(feature.needs) do
                local met = false
                for _, path in ipairs(need) do
                    met = met or Check.Has(path)
                end
                if not met then
                    return false
                end
            end
            return true
        end
    end
    return false
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

-- Returns { {path, ok}, ... } in PROBES order.
function Check.Probes()
    local out = {}
    for i, path in ipairs(Check.PROBES) do
        out[i] = { path = path, ok = Check.Has(path) }
    end
    return out
end
