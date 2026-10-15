local _, ns = ...

-- Adds Tandem lines to item tooltips out of combat: where the item ranks in its slot, whether the player can use
-- it, and where it drops most.
local Tooltip = {}
ns.Tooltip = Tooltip

local L = ns.L
local Store = ns.Store
local View = ns.View
local Advisor = ns.Advisor
local Safe = Store.Safe

local BLUE = { 0.4, 0.8, 1 }
local RED = { 1, 0.25, 0.25 }
local LIGHT = { 0.8, 0.8, 0.8 }
local GREY = { 0.5, 0.5, 0.5 }

-- Per-item results for one class:level:Store.revision over one own db and one shipped table, as Advisor's rank memo.
local memo = {}

local function entries(class, level)
    local key = class .. ":" .. level .. ":" .. Store.revision
    if memo.key ~= key or memo.db ~= Store.db or memo.shipped ~= ns.Shipped then
        memo = { key = key, db = Store.db, shipped = ns.Shipped, items = {} }
    end
    return memo.items
end

-- Returns the line naming the item's most frequent source, or false when it has none.
local function sourceLine(id)
    local rows = Advisor.Sources(id)
    local top = rows[1]
    if not top then
        return false
    end
    local text = L["Tandem: drops from %s, %s"]:format(View.SourceName(top), View.MapLabel(top))
    if top.rateBasis == "kill" then
        text = text .. L[" (%.1f%% per kill)"]:format(top.rate * 100)
    elseif top.rateBasis == "corpse" then
        text = text .. L[" (up to %.1f%%)"]:format(top.rate * 100)
    end
    if #rows > 1 then
        text = text .. L[" (+%d more)"]:format(#rows - 1)
    end
    return text
end

local function addLine(tooltip, text, colour)
    tooltip:AddLine(text, colour[1], colour[2], colour[3], false)
end

-- The item tooltip post-call: adds the lines for a known item on GameTooltip or ItemRefTooltip; anything else, or
-- anything in combat, is left alone without a word.
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
    local _, class, level = View.Player(true)
    local record = class and Advisor.Item(id)
    if not record then
        return
    end
    if not Advisor.IsDeprecated(id) then
        View.NoteName(id, View.CachedName(id))
    end
    if Advisor.IsDeprecated(id) then
        addLine(tooltip, L["Tandem: deprecated item"], GREY)
        return
    end

    local items = entries(class, level)
    local e = items[id]
    if not e then
        e = { rank = Advisor.Rank(id, class, level), source = sourceLine(id) }
        items[id] = e
    end
    local r = e.rank
    if r.slot then
        local row = { id = id, ilvl = record[1], sourced = r.sourced, usable = r.usable }
        local worn = r.offhand and View.EquippedHands() or View.Equipped(r.slot)
        addLine(tooltip, L["Tandem: rank %d of %d for %s"]:format(r.rank, r.total, View.SlotLabel(r.slot))
            .. View.Marks(row, worn), BLUE)
    end
    if r.reason == "level" then
        addLine(tooltip, L["Tandem: you cannot use it: level %d required"]:format(r.needLevel), RED)
    elseif r.reason == "proficiency" then
        addLine(tooltip, L["Tandem: your class cannot use it"], RED)
    end
    if e.source then
        addLine(tooltip, e.source, LIGHT)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Item ~= nil then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip.OnItem)
end
