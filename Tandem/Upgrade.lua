local _, ns = ...

-- Says in chat when an item new in the bags beats what the player wears (decision 4): one line per item, at most once
-- per item per session, by the View.Marks rule. Advises only: nothing is equipped, and a line due in combat waits
-- until combat ends. The first bag snapshot after login is taken silently.
local Upgrade = {}
ns.Upgrade = Upgrade

local L = ns.L
local Safe = ns.Store.Safe

local BAGS = 4

local seen
local alerted = {}
local waiting = {}
local queued = {}

local function bagFunctions()
    local c = C_Container or {}
    return c.GetContainerNumSlots or GetContainerNumSlots, c.GetContainerItemID or GetContainerItemID
end

-- Returns the set of item ids in bags 0..4.
local function snapshot()
    local numSlots, itemID = bagFunctions()
    local ids = {}
    for bag = 0, BAGS do
        local n = Safe(numSlots(bag))
        for slot = 1, type(n) == "number" and n or 0 do
            local id = Safe(itemID(bag, slot))
            if type(id) == "number" then
                ids[id] = true
            end
        end
    end
    return ids
end

local function say(line)
    if InCombatLockdown and InCombatLockdown() then
        queued[#queued + 1] = line
    else
        print(line)
    end
end

-- Prints a line for the item when it is an upgrade; asks the client for it and waits while it is not loaded.
local function judge(id)
    local r = ns.View.Record(id)
    if r == nil then
        waiting[id] = true
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
        return
    end
    local _, class, level = ns.View.Player(true)
    if not r or not class then
        return
    end
    local place = ns.Advisor.PlaceRecord(r, class, level)
    if not (place.slot and place.usable) then
        return
    end
    local worn = place.offhand and ns.View.EquippedHands() or ns.View.Equipped(place.slot)
    if worn.ids[id] or not worn.ilvl or r[1] <= worn.ilvl then
        return
    end
    alerted[id] = true
    say(L["Tandem: upgrade for %s: %s (item level %d over %d)"]:format(ns.View.SlotLabel(place.slot),
        ns.View.ItemLink(id, r[3]), r[1], worn.ilvl))
end

-- BAG_UPDATE_DELAYED: judges the item ids not in the last snapshot.
function Upgrade.OnBagUpdate()
    if not (ns.Check.Ready("Upgrade alert") and C_Item and C_Item.GetItemInfo) then
        return
    end
    local now = snapshot()
    local before = seen
    seen = now
    if not before then
        return
    end
    for id in pairs(now) do
        if not before[id] and not alerted[id] then
            judge(id)
        end
    end
end

-- GET_ITEM_INFO_RECEIVED: judges a new bag item that was still loading.
function Upgrade.OnItemInfo(id)
    id = Safe(id)
    if id and waiting[id] then
        waiting[id] = nil
        if seen and seen[id] and not alerted[id] then
            judge(id)
        end
    end
end

-- PLAYER_REGEN_ENABLED: prints the lines held back during combat.
function Upgrade.OnCombatEnd()
    local lines = queued
    queued = {}
    for _, line in ipairs(lines) do
        print(line)
    end
end
