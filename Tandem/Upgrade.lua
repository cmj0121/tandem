local _, ns = ...

-- Says in chat when an item new in the bags beats what the player wears (decision 4): one line per item, at most once
-- per item per session, by stat score only (never item level), and never for an item the player cannot equip now.
-- Advises only:
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

-- Returns the score to beat in one slot's worn table: the lowest worn score (an empty slot scores 0), false when
-- there is nothing to beat (an off hand behind a two-hander), nil while a worn item is unknown, loading or unscored.
local function toBeat(worn)
    local low = math.huge
    for _, e in ipairs(worn.list) do
        if e.unknown or (e.id and (e.ilvl == nil or e.score == nil)) then
            return nil
        end
        low = math.min(low, e.score)
    end
    if worn.ilvl == nil then
        return false
    end
    return low
end

-- The score to beat for the item's place: both hands for a one-hander that fills either, else its slot.
local function wornScore(place)
    if not place.offhand then
        return toBeat(ns.View.Equipped(place.slot))
    end
    local low = false
    for _, slot in ipairs({ "mainhand", "offhand" }) do
        local s = toBeat(ns.View.Equipped(slot))
        if s == nil then
            return nil
        end
        if s and (not low or s < low) then
            low = s
        end
    end
    return low
end

-- Judges the item against what is worn, by stat score only: returns { better, done, r, place, over } where better is
-- nil while the item or a score is not known yet (the client is asked for the item), done says the answer was made
-- on complete data, and r, place and over (the worn score) are set behind a true answer.
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
    local View, Advisor = ns.View, ns.Advisor
    local place = Advisor.PlaceRecord(r, class, level, id)
    if not (place.slot and place.usable) then
        return { better = false, done = true }
    end
    local function wornNow()
        return place.offhand and View.EquippedHands() or View.Equipped(place.slot)
    end
    local worn = wornNow()
    if worn.ids[id] then
        return { better = false, done = true }
    end
    local blocked = ns.StatSearch.Blocked(id)
    if blocked == nil then
        waiting[id] = true
        return { done = false }
    elseif blocked then
        return { better = false, done = true }
    end
    if place.score == nil and Advisor.ReadStats(id) then
        place = Advisor.PlaceRecord(r, class, level, id)
    end
    local read = false
    for _, e in ipairs(worn.list) do
        if e.id and e.score == nil then
            read = Advisor.ReadStats(e.id) and true or read
        end
    end
    if read then
        worn = wornNow()
    end
    local over = wornScore(place)
    if over == false then
        return { better = false, done = true }
    end
    if place.score == nil or over == nil then
        waiting[id] = true
        for _, e in ipairs(worn.list) do
            if e.id and (e.ilvl == nil or e.score == nil) then
                waiting[e.id] = true
            end
        end
        return { done = false }
    end
    if place.score <= over then
        return { better = false, done = true }
    end
    return { better = true, done = true, r = r, place = place, over = over }
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

-- Returns true when the item's stat score beats every worn item's of its slot, false when it does not (not usable,
-- not equippable now, no slot, already worn, no better), nil while the item, its stats or a worn item's are unknown.
function Upgrade.Better(id)
    return verdict(id).better
end

-- PLAYER_EQUIPMENT_CHANGED, PLAYER_LEVEL_UP (and OnSkillLines): drops Better's answers.
function Upgrade.Invalidate()
    cache = { answers = {} }
end

local skillNames

-- Returns the player's skill line names joined, or nil when the client does not tell.
local function skillLines()
    if not (GetNumSkillLines and GetSkillLineInfo) then
        return nil
    end
    local ok, n = pcall(GetNumSkillLines)
    n = ok and Safe(n)
    if type(n) ~= "number" then
        return nil
    end
    local names = {}
    for i = 1, n do
        local got, name = pcall(GetSkillLineInfo, i)
        name = got and Safe(name)
        if type(name) ~= "string" then
            return nil
        end
        names[#names + 1] = name
    end
    return table.concat(names, "\n")
end

-- SKILL_LINES_CHANGED: drops Better's answers and returns true when a skill line was learned or lost (or the client
-- does not tell), not when only a skill's points changed.
function Upgrade.OnSkillLines()
    local names = skillLines()
    if names and names == skillNames then
        return false
    end
    skillNames = names
    Upgrade.Invalidate()
    return true
end

-- Prints a line for a new bag item when it is an upgrade; remembers it in pending while it cannot be judged yet.
local function judge(id)
    local v = verdict(id)
    if v.better == nil then
        pending[id] = true
    end
    if not v.better then
        return
    end
    alerted[id] = true
    local View, r, place = ns.View, v.r, v.place
    say(L["Tandem: upgrade for %s: %s (score %s over %s)"]:format(View.SlotLabel(place.slot), View.ItemLink(id, r[3]),
        View.ScoreText(place.score), View.ScoreText(v.over)))
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

-- GET_ITEM_INFO_RECEIVED: returns true for a waiting item (a new bag item, one Better asked for, or a worn item whose
-- stats were missing). The new bag item judge was waiting on, or for a worn or other item every one it waits on, is
-- judged again and gets its line when it is an upgrade.
function Upgrade.OnItemInfo(id)
    id = Safe(id)
    if not (id and waiting[id]) then
        return false
    end
    waiting[id] = nil
    local due = {}
    if pending[id] then
        due[id] = true
    else
        for p in pairs(pending) do
            due[p] = true
        end
    end
    for p in pairs(due) do
        pending[p] = nil
        if seen and seen[p] and not alerted[p] then
            judge(p)
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
