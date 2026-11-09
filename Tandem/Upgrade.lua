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

-- Bag items are keyed per StatSearch.Key of their slot (the item's link, or its id without one), so two suffix
-- variants of one item id are judged apart. waiting maps an item id to the keys waiting on it, since
-- GET_ITEM_INFO_RECEIVED gives an id.
local seen
local alerted = {}
local waiting = {}
local pending = {}
local queued = {}

local function bagFunctions()
    local c = C_Container or {}
    return c.GetContainerNumSlots or GetContainerNumSlots, c.GetContainerItemID or GetContainerItemID
end

-- Returns the items in bags 0..4: { [key] = { id, bag, slot } } by StatSearch.Key of the slot.
local function snapshot()
    local numSlots, itemID = bagFunctions()
    local items = {}
    for bag = 0, BAGS do
        local n = Safe(numSlots(bag))
        for slot = 1, type(n) == "number" and n or 0 do
            local id = Safe(itemID(bag, slot))
            if type(id) == "number" then
                local src = { id = id, bag = bag, slot = slot }
                items[ns.StatSearch.Key(src)] = src
            end
        end
    end
    return items
end

local function say(line)
    if InCombatLockdown and InCombatLockdown() then
        queued[#queued + 1] = line
    else
        print(line)
    end
end

-- Better's answers by StatSearch.Key of the judged source, for one class:level:spec:Weights.revision; worn items,
-- skills and the player's level are not all in the key, so an equipment, level or skill line change calls Invalidate.
local cache = { answers = {} }

local function cacheKey(class, level)
    return class .. ":" .. level .. ":" .. tostring(ns.Weights.Active(class, level)) .. ":" .. ns.Weights.revision
end

-- Marks key as waiting on the item id's GET_ITEM_INFO_RECEIVED.
local function wait(id, key)
    waiting[id] = waiting[id] or {}
    waiting[id][key] = true
end

-- Judges the item (scored and checked from src, a StatSearch source for it, under key) against what is worn by rule
-- D2 (Items.Beats): returns { better, done, info, score, place, over } where better is nil while the item, its
-- tooltip or a worn item is not known yet (the client is asked for them), done says the answer was made on complete
-- data, and info, score, place and over (the worn score) are set behind a true answer.
local function assess(id, src, key)
    local Items = ns.Items
    local info = Items.Info(id)
    if info == nil then
        wait(id, key)
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
    local blocked = ns.StatSearch.Blocked(src)
    if blocked == nil then
        wait(id, key)
        return { done = false }
    elseif blocked then
        return { better = false, done = true }
    end
    local score = Items.Score(src, class, level)
    local better, over = Items.Beats(score, info[1], worn)
    if better == nil then
        if score == nil then
            wait(id, key)
        end
        for _, e in ipairs(worn.list) do
            if e.id and (e.ilvl == nil or e.score == nil) then
                wait(e.id, key)
            end
        end
        return { done = false }
    end
    if not better then
        return { better = false, done = true }
    end
    return { better = true, done = true, info = info, score = score, place = place, over = over }
end

-- Returns the item's assessment from src (the id when nil), kept per StatSearch.Key of the source while the cache key
-- holds when it was made on complete data.
local function verdict(id, src)
    local _, class, level = ns.View.Player(true)
    local key = class and cacheKey(class, level)
    if cache.key ~= key then
        cache = { key = key, answers = {} }
    end
    src = src or id
    local answer = ns.StatSearch.Key(src)
    local v = cache.answers[answer]
    if v then
        return v
    end
    v = assess(id, src, answer)
    if v.done and key then
        cache.answers[answer] = v
    end
    return v
end

-- Upgrade.Better(id [, src]) -> true, score, over | false | nil
-- True when the item beats the weakest worn item of its slot by rule D2, false when it does not (not usable, a red
-- tooltip line, not equippable, no slot, already worn, no better), nil while the item, its stats or a worn item's are
-- unknown. src, a StatSearch source for the item (its bag slot or link), is scored and checked instead of the bare id
-- when given. Behind a true answer it also returns the item's score and the worn score it beats.
function Upgrade.Better(id, src)
    local v = verdict(id, src)
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

-- Prints a line for the new bag item seen under key when it is an upgrade, judged from its bag slot and named by its
-- own link when the key is one; remembers the key in pending while it cannot be judged yet.
local function judge(key)
    local item = seen[key]
    local v = verdict(item.id, item)
    if v.better == nil then
        pending[key] = true
    end
    if not v.better then
        return
    end
    alerted[key] = true
    local View = ns.View
    say(L["Tandem: upgrade for %s: %s (score %s over %s)"]:format(View.SlotLabel(v.place.slot),
        type(key) == "string" and key or View.ItemLink(item.id, v.info[3]), View.ScoreText(v.score),
        View.ScoreText(v.over)))
end

-- BAG_UPDATE_DELAYED: judges the bag items whose key is not in the last snapshot.
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
    for key in pairs(now) do
        if not before[key] and not alerted[key] then
            judge(key)
        end
    end
end

-- GET_ITEM_INFO_RECEIVED: returns true for a waiting item (a new bag item, one Better asked for, or a worn item whose
-- stats were missing). Every pending bag item still in the bags that waited on it, or that waits on no item id (behind
-- a worn item the client does not reveal), is judged again, once, and gets its line when it is an upgrade.
function Upgrade.OnItemInfo(id)
    id = Safe(id)
    local keys = id and waiting[id]
    if not keys then
        return false
    end
    waiting[id] = nil
    local tied = {}
    for _, others in pairs(waiting) do
        for key in pairs(others) do
            tied[key] = true
        end
    end
    local due = {}
    for key in pairs(pending) do
        if keys[key] or not tied[key] then
            due[key] = true
        end
    end
    for key in pairs(due) do
        pending[key] = nil
        if seen and seen[key] and not alerted[key] then
            judge(key)
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
