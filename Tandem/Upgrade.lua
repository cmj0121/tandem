local _, ns = ...

-- Says in chat when an item new in the bags beats what the player wears (decision 4, rule D2 of stage 11): one line
-- per item, at most once per item per session, by stat score with item level breaking a tie, from live item data
-- only, and never for an item the player cannot equip now.
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

-- Better's answers by item id, for one class:level:spec:Weights.revision; worn items, skills and the player's level
-- are not all in the key, so an equipment, level or skill line change calls Invalidate.
local cache = { answers = {} }

local function cacheKey(class, level)
    return class .. ":" .. level .. ":" .. tostring(ns.Weights.Active(class, level)) .. ":" .. ns.Weights.revision
end

-- Judges the item against what is worn by rule D2 (Items.Beats): returns { better, done, info, score, place, over }
-- where better is nil while the item, its tooltip or a worn item is not known yet (the client is asked for them),
-- done says the answer was made on complete data, and info, score, place and over (the worn score) are set behind a
-- true answer.
local function assess(id)
    local Items = ns.Items
    local info = Items.Info(id)
    if info == nil then
        waiting[id] = true
        return { done = false }
    end
    local _, class, level = ns.View.Player(true)
    if not class then
        return { better = false, done = false }
    end
    if not info then
        return { better = false, done = true }
    end
    local place = Items.Place(info, class, level)
    if not (place.slot and place.usable) then
        return { better = false, done = true }
    end
    local worn = place.offhand and Items.EquippedHands() or Items.Equipped(place.slot)
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
    local score = Items.Score(id, class, level)
    local better, over = Items.Beats(score, info[1], worn)
    if better == nil then
        waiting[id] = true
        for _, e in ipairs(worn.list) do
            if e.id and (e.ilvl == nil or e.score == nil) then
                waiting[e.id] = true
            end
        end
        return { done = false }
    end
    if not better then
        return { better = false, done = true }
    end
    return { better = true, done = true, info = info, score = score, place = place, over = over }
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

-- Returns true when the item beats the weakest worn item of its slot by rule D2, false when it does not (not usable,
-- a red tooltip line, not equippable, no slot, already worn, no better), nil while the item, its stats or a worn
-- item's are unknown. Behind a true answer it also returns the item's score and the worn score it beats.
function Upgrade.Better(id)
    local v = verdict(id)
    if v.better then
        return true, v.score, v.over
    end
    return v.better
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
    local View = ns.View
    say(L["Tandem: upgrade for %s: %s (score %s over %s)"]:format(View.SlotLabel(v.place.slot),
        View.ItemLink(id, v.info[3]), View.ScoreText(v.score), View.ScoreText(v.over)))
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
