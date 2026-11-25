local _, ns = ...

-- Adds lines to item tooltips out of combat: one when the item beats what the player wears (from live item data), and
-- the learned recipes that use it as a reagent with the bag counts.
local Tooltip = {}
ns.Tooltip = Tooltip

local L = ns.L
local View = ns.View
local Safe, call = ns.Store.Safe, ns.Store.Call

local GREEN = { 0.1, 1, 0.1 }
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.6, 0.6, 0.6 }
local MAX_RECIPES = 8

local function itemName(id)
    local name = call(type(C_Item) == "table" and C_Item.GetItemNameByID, id)
    if type(name) ~= "string" or name == "" then
        name = call(type(C_Item) == "table" and C_Item.GetItemInfo or _G.GetItemInfo, id)
    end
    if type(name) ~= "string" or name == "" then
        return L["item %d"]:format(id)
    end
    return name
end

local function bagCount(id)
    local n = call(type(C_Item) == "table" and C_Item.GetItemCount, id)
    if type(n) ~= "number" then
        n = call(GetItemCount, id)
    end
    return type(n) == "number" and n or 0
end

-- The recipe lines: a header, then one line per recipe (at most MAX_RECIPES) listing its reagents as have/need, green
-- when the bags hold enough of every reagent.
local function addRecipes(tooltip, id)
    local recipes = ns.Crafts.RecipesUsing(id)
    if #recipes == 0 then
        return
    end
    local lines = {}
    for i = 1, math.min(#recipes, MAX_RECIPES) do
        local r = recipes[i]
        local parts, enough = {}, true
        for _, reagent in ipairs(r.reagents) do
            local have = bagCount(reagent.item)
            if have < reagent.count then
                enough = false
            end
            parts[#parts + 1] = L["%s %d/%d"]:format(itemName(reagent.item), have, reagent.count)
        end
        lines[#lines + 1] = { L["%s: %s"]:format(r.name, table.concat(parts, L[", "])), enough and GREEN or GREY }
    end
    tooltip:AddLine(L["Tandem: recipes that use this"], GOLD[1], GOLD[2], GOLD[3], false)
    for _, line in ipairs(lines) do
        tooltip:AddLine(line[1], line[2][1], line[2][2], line[2][3], false)
    end
    if #recipes > MAX_RECIPES then
        tooltip:AddLine(L["... and %d more"]:format(#recipes - MAX_RECIPES), GREY[1], GREY[2], GREY[3], false)
    end
end

-- The item tooltip post-call: adds the upgrade line and the recipe lines for an item on GameTooltip or ItemRefTooltip,
-- the upgrade judged from the tooltip's hyperlink when it has one; anything else, or anything in combat, is left alone
-- without a word.
function Tooltip.OnItem(tooltip, data)
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if tooltip == nil or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or tooltip:IsForbidden() then
        return
    end
    data = Safe(data)
    local id = type(data) == "table" and Safe(data.id) or nil
    if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then
        return
    end
    local link = Safe(data.hyperlink)
    local src = type(link) == "string" and { link = link, id = id } or nil
    local okBetter, better, score, over = pcall(ns.Upgrade.Better, id, src)
    if okBetter and better == true then
        tooltip:AddLine(L["Tandem: upgrade over what you wear (score %s over %s)"]:format(View.ScoreText(score),
            View.ScoreText(over)), GREEN[1], GREEN[2], GREEN[3], false)
    end
    pcall(addRecipes, tooltip, id)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Item ~= nil then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip.OnItem)
end
