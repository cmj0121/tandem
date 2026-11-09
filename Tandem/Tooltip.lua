local _, ns = ...

-- Adds one line to item tooltips out of combat when the item beats what the player wears (from live item data).
local Tooltip = {}
ns.Tooltip = Tooltip

local L = ns.L
local View = ns.View
local Safe = ns.Store.Safe

local GREEN = { 0.1, 1, 0.1 }

-- The item tooltip post-call: adds the upgrade line for an item on GameTooltip or ItemRefTooltip, judged from the
-- tooltip's hyperlink when it has one; anything else, or anything in combat, is left alone without a word.
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
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Item ~= nil then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip.OnItem)
end
