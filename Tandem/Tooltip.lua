local _, ns = ...

-- Adds lines to item tooltips out of combat: one when the item beats what the player wears (from live item data), and
-- the most makeable learned cooking recipes that use it as a reagent with the bag counts.
local Tooltip = {}
ns.Tooltip = Tooltip

local L = ns.L
local View = ns.View
local Safe, call = ns.Store.Safe, ns.Store.Call

local GREEN = { 0.1, 1, 0.1 }
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.6, 0.6, 0.6 }
local MAX_RECIPES = 5
local COOKING = 2550

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

-- The names Cooking goes by: the client's name for the Cooking spell, plus the English and zhTW names.
local function cookingNames()
    local names = { Cooking = true, ["烹飪"] = true }
    local info = call(type(C_Spell) == "table" and C_Spell.GetSpellInfo, COOKING)
    local name = type(info) == "table" and Safe(info.name) or nil
    if type(name) ~= "string" then
        name = call(_G.GetSpellInfo, COOKING)
    end
    if type(name) == "string" and name ~= "" then
        names[name] = true
    end
    return names
end

-- A recipe's reagent parts as have/need text, with how makeable it is: enough of all, the share of the needed
-- reagents the bags hold, and how many reagent kinds fall short.
local function rate(r)
    local parts, held, needed, short = {}, 0, 0, 0
    for _, reagent in ipairs(r.reagents) do
        local have = bagCount(reagent.item)
        if have < reagent.count then
            short = short + 1
        end
        held = held + math.min(have, reagent.count)
        needed = needed + reagent.count
        parts[#parts + 1] = L["%s %d/%d"]:format(itemName(reagent.item), have, reagent.count)
    end
    return { name = r.name, parts = parts, enough = short == 0, cover = needed > 0 and held / needed or 0,
        short = short }
end

local function moreMakeable(a, b)
    if a.enough ~= b.enough then
        return a.enough
    end
    if a.cover ~= b.cover then
        return a.cover > b.cover
    end
    if a.short ~= b.short then
        return a.short < b.short
    end
    return a.name < b.name
end

-- The recipe lines: a header, then one line per cooking recipe (the MAX_RECIPES most makeable) listing its reagents
-- as have/need, green when the bags hold enough of every reagent.
local function addRecipes(tooltip, id)
    local cooking = cookingNames()
    local rated = {}
    for _, r in ipairs(ns.Crafts.RecipesUsing(id)) do
        if r.profession ~= nil and cooking[r.profession] then
            rated[#rated + 1] = rate(r)
        end
    end
    if #rated == 0 then
        return
    end
    table.sort(rated, moreMakeable)
    tooltip:AddLine(L["Tandem: cooking recipes that use this"], GOLD[1], GOLD[2], GOLD[3], false)
    for i = 1, math.min(#rated, MAX_RECIPES) do
        local r = rated[i]
        local colour = r.enough and GREEN or GREY
        tooltip:AddLine(L["%s: %s"]:format(r.name, table.concat(r.parts, L[", "])), colour[1], colour[2], colour[3],
            false)
    end
    if #rated > MAX_RECIPES then
        tooltip:AddLine(L["... and %d more"]:format(#rated - MAX_RECIPES), GREY[1], GREY[2], GREY[3], false)
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
