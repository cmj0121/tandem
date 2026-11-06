local _, ns = ...

-- Says in chat when an item new in the bags beats what the player wears (decision 4): one line per item, at most once
-- per item per session, by View.IsUpgrade: stat score when both sides have stats, else item level. Advises only:
-- nothing is equipped, and a line due in combat waits until combat ends. The first bag snapshot after login is taken
-- silently.
local Upgrade = {}
ns.Upgrade = Upgrade

local L = ns.L
local Safe = ns.Store.Safe

local BAGS = 4

local seen
local alerted = {}
local waiting = {}
local pending = {}
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

-- Better's answers by item id, for one class:level:spec:Store.revision:Weights.revision (as Advisor's memo); worn
-- items are not in the key, so an equipment change calls Invalidate.
local cache = { answers = {} }

local function cacheKey(class, level)
    return class .. ":" .. level .. ":" .. tostring(ns.Weights.Active(class, level)) .. ":" .. ns.Store.revision
        .. ":" .. ns.Weights.revision
end

-- True when every worn item of the slot is known and loaded.
local function complete(worn)
    for _, e in ipairs(worn.list) do
        if e.unknown or (e.id and e.ilvl == nil) then
            return false
        end
    end
    return true
end

-- Judges the item against what is worn: returns { better, done, r, place, worn } where better is nil while the record
-- loads (the client is asked for it), done says the answer was made on complete data, and r, place and worn are set
-- behind a true answer.
local function assess(id)
    local r = ns.View.Record(id)
    if r == nil then
        waiting[id] = true
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
        return { done = false }
    end
    local _, class, level = ns.View.Player(true)
    if not class then
        return { better = false, done = false }
    end
    if not r then
        return { better = false, done = true }
    end
    local View = ns.View
    local place = ns.Advisor.PlaceRecord(r, class, level, id)
    if not (place.slot and place.usable) then
        return { better = false, done = true }
    end
    local worn = place.offhand and View.EquippedHands() or View.Equipped(place.slot)
    local done = complete(worn)
    if worn.ids[id] or not View.IsUpgrade({ ilvl = r[1], score = place.score, usable = true }, worn) then
        return { better = false, done = done }
    end
    return { better = true, done = done, r = r, place = place, worn = worn }
end

-- Returns the item's assessment, kept while the cache key holds when it was made on complete data.
local function verdict(id)
    local _, class, level = ns.View.Player(true)
    local key = class and cacheKey(class, level)
    if cache.key ~= key then
        cache = { key = key, answers = {} }
    end
    local v = cache.answers[id]
    if v then
        return v
    end
    v = assess(id)
    if v.done and key then
        cache.answers[id] = v
    end
    return v
end

-- Returns true when the item beats what the player wears in its slot, false when it does not (not usable, no slot,
-- already worn, no better), nil while its record is loading.
function Upgrade.Better(id)
    return verdict(id).better
end

-- PLAYER_EQUIPMENT_CHANGED: drops Better's answers.
function Upgrade.Invalidate()
    cache = { answers = {} }
end

-- Prints a line for a new bag item when it is an upgrade; remembers it in pending while its record loads.
local function judge(id)
    local v = verdict(id)
    if v.better == nil then
        pending[id] = true
    end
    if not v.better then
        return
    end
    alerted[id] = true
    local View, r, place, worn = ns.View, v.r, v.place, v.worn
    local slot, link = View.SlotLabel(place.slot), View.ItemLink(id, r[3])
    if place.score and worn.score then
        say(L["Tandem: upgrade for %s: %s (score %s over %s)"]:format(slot, link, View.ScoreText(place.score),
            View.ScoreText(worn.score)))
    else
        say(L["Tandem: upgrade for %s: %s (item level %d over %d)"]:format(slot, link, r[1], worn.ilvl))
    end
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

-- GET_ITEM_INFO_RECEIVED: returns true for a waiting item (a new bag item, or one Better asked for); a new bag item
-- judge was waiting on gets its line when it is an upgrade.
function Upgrade.OnItemInfo(id)
    id = Safe(id)
    if not (id and waiting[id]) then
        return false
    end
    waiting[id] = nil
    if pending[id] then
        pending[id] = nil
        if seen and seen[id] and not alerted[id] then
            judge(id)
        end
    end
    return true
end

-- PLAYER_REGEN_ENABLED: prints the lines held back during combat.
function Upgrade.OnCombatEnd()
    local lines = queued
    queued = {}
    for _, line in ipairs(lines) do
        print(line)
    end
end
