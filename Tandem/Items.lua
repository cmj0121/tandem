local _, ns = ...

-- Live item facts (stage 11, decision D1): what the client says about an item now, and how it compares with what the
-- player wears (rule D2). Nothing here reads or writes TandemDB; tooltip stats are kept for the session only.
local Items = {}
ns.Items = Items

local Safe = ns.Store.Safe

local NON_EQUIP = "INVTYPE_NON_EQUIP_IGNORE"

Items.SLOT_OF = {
    INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
    INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
    INVTYPE_TRINKET = "trinket", INVTYPE_WEAPON = "mainhand", INVTYPE_WEAPONMAINHAND = "mainhand",
    INVTYPE_WEAPONOFFHAND = "offhand", INVTYPE_SHIELD = "offhand", INVTYPE_HOLDABLE = "offhand",
    INVTYPE_2HWEAPON = "twohand", INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged",
    INVTYPE_THROWN = "ranged", INVTYPE_RELIC = "ranged",
}
local SLOT_OF = Items.SLOT_OF

local ARMOR, WEAPON = 4, 2

-- Builds a { [subclass] = minLevel } table from a list of subclasses or { subclass, minLevel } pairs.
local function subs(list)
    local t = {}
    for _, v in ipairs(list) do
        if type(v) == "table" then
            t[v[1]] = v[2]
        else
            t[v] = 1
        end
    end
    return t
end

Items.PROFICIENCY = {
    WARRIOR = { armor = subs({ 2, 3, { 4, 40 }, 6 }),
                weapon = subs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }), dualWield = 20 },
    PALADIN = { armor = subs({ 2, 3, { 4, 40 }, 6, 7 }), weapon = subs({ 0, 1, 4, 5, 6, 7, 8 }) },
    HUNTER = { armor = subs({ 2, { 3, 40 } }), weapon = subs({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }),
               dualWield = 20 },
    ROGUE = { armor = subs({ 2 }), weapon = subs({ 2, 3, 4, 7, 13, 15, 16, 18 }), dualWield = 10 },
    PRIEST = { armor = subs({}), weapon = subs({ 4, 10, 15, 19 }) },
    SHAMAN = { armor = subs({ 2, { 3, 40 }, 6, 9 }), weapon = subs({ 0, 4, 10, 13, 15 }) },
    MAGE = { armor = subs({}), weapon = subs({ 7, 10, 15, 19 }) },
    WARLOCK = { armor = subs({}), weapon = subs({ 7, 10, 15, 19 }) },
    DRUID = { armor = subs({ 2, 8 }), weapon = subs({ 4, 5, 10, 13, 15 }) },
}

local ALL_CLASSES = { [ARMOR] = subs({ 0, 1 }), [WEAPON] = subs({ 14 }) }

-- Inventory slots worn for each slot token.
local INVENTORY = {
    head = { 1 }, neck = { 2 }, shoulder = { 3 }, back = { 15 }, chest = { 5 }, wrist = { 9 }, hands = { 10 },
    waist = { 6 }, legs = { 7 }, feet = { 8 }, finger = { 11, 12 }, trinket = { 13, 14 }, mainhand = { 16 },
    offhand = { 17 }, twohand = { 16 }, ranged = { 18 },
}

local function isEquipLoc(equipLoc)
    return type(equipLoc) == "string" and equipLoc ~= "" and equipLoc ~= NON_EQUIP
end

-- Items.Info(id) -> { ilvl, reqLevel, quality, equipLoc, classID, subclassID } | false | nil
-- The item as the client knows it now: false when it is not equippable (or the item API is missing), nil while the
-- client has not loaded it (it is then asked for).
function Items.Info(id)
    if not (C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfo) then
        return false
    end
    local instantID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    equipLoc = Safe(equipLoc)
    if not Safe(instantID) or not isEquipLoc(equipLoc) then
        return false
    end
    local name, _, quality, ilvl, reqLevel = C_Item.GetItemInfo(id)
    name, quality, ilvl, reqLevel = Safe(name), Safe(quality), Safe(ilvl), Safe(reqLevel)
    if type(name) ~= "string" or type(ilvl) ~= "number" then
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
        return nil
    end
    return { ilvl, type(reqLevel) == "number" and reqLevel or 1, type(quality) == "number" and quality or 1,
             equipLoc, Safe(classID), Safe(subclassID) }
end

local stats = {}

-- Items.Stats(src) -> { statKey = number } | nil
-- The tooltip stats of a StatSearch source (an item id, or a worn, bag or linked item), kept for the session per
-- StatSearch.Key once read; nil while they cannot be read (asked again next time).
function Items.Stats(src)
    local key = ns.StatSearch.Key(src)
    local s = stats[key]
    if s == nil and ns.StatPatterns and ns.StatSearch.Ready() then
        s = ns.StatSearch.ReadStats(src)
        stats[key] = s
    end
    return s
end

-- Drops the session's stats (tests only).
function Items.Reset()
    stats = {}
end

-- Returns the source's weighted score for the class at the level (its active spec), or nil while it has no stats.
function Items.Score(src, class, level)
    return ns.Weights.Score(Items.Stats(src), class, (ns.Weights.Active(class, level)))
end

local function dualWields(class, level)
    local dual = Items.PROFICIENCY[class] and Items.PROFICIENCY[class].dualWield
    return dual ~= nil and level >= dual
end

-- Returns ok, reason ("slot" | "proficiency" | "level"), needLevel (only for "level").
function Items.Usable(item, class, level)
    if not SLOT_OF[item[4]] then
        return false, "slot"
    end
    local classID, sub = item[5], item[6]
    local minLevel = ALL_CLASSES[classID] and ALL_CLASSES[classID][sub]
    local prof = Items.PROFICIENCY[class]
    if not minLevel and prof then
        minLevel = (classID == ARMOR and prof.armor[sub]) or (classID == WEAPON and prof.weapon[sub]) or nil
    end
    if minLevel and item[4] == "INVTYPE_WEAPONOFFHAND" then
        minLevel = prof and prof.dualWield and math.max(minLevel, prof.dualWield)
    end
    if not minLevel then
        return false, "proficiency"
    end
    local need = math.max(item[2], minLevel)
    if level < need then
        return false, "level", need
    end
    return true
end

-- Returns where an Info table goes for a class at a level: { slot, usable, reason, needLevel, offhand, score }; slot
-- is nil when the item has no ranked slot, offhand is true for a one-hander the class can also wield in the off hand,
-- and score is set only when the item's id is given.
function Items.Place(info, class, level, id)
    local usable, reason, needLevel = Items.Usable(info, class, level)
    return { slot = SLOT_OF[info[4]], usable = usable, reason = reason, needLevel = needLevel,
             offhand = (info[4] == "INVTYPE_WEAPON" and dualWields(class, level)) or nil,
             score = id and Items.Score(id, class, level) or nil }
end

-- Returns the item id worn in an inventory slot, false when it is empty, or nil when the client does not tell.
-- A secret link is never compared: it is checked before anything else touches it.
local function wornID(inv)
    if not GetInventoryItemLink then
        return nil
    end
    local raw = GetInventoryItemLink("player", inv)
    if issecretvalue and issecretvalue(raw) then
        return nil
    end
    if raw == nil then
        return false
    end
    return type(raw) == "string" and tonumber(raw:match("item:(%d+)")) or nil
end

local function equipLocOf(id)
    if C_Item and C_Item.GetItemInfoInstant then
        return Safe((select(4, C_Item.GetItemInfoInstant(id))))
    end
end

-- Returns what the player wears in a slot token: { ids = {[id] = true}, list = { {id, ilvl, score} | {ilvl = 0,
-- score = 0} | {unknown} }, ilvl, score } where ilvl is the lower of a pair (0 when a slot is empty) or nil when
-- unknown, and score the lower stat score of the pair (each from its worn slot's own tooltip), nil unless every worn
-- item has one. An off hand behind a two-hander, or behind a main hand the client does not reveal, has nothing to
-- beat: its ilvl and score are nil.
function Items.Equipped(slot)
    local out = { ids = {}, list = {}, ilvl = math.huge, score = math.huge }
    local _, classFile, level = ns.View.Player(true)
    for _, inv in ipairs(INVENTORY[slot]) do
        local id = wornID(inv)
        local e = {}
        if id then
            local info = Items.Info(id)
            e.id, e.ilvl = id, info and info[1] or nil
            e.score = classFile and Items.Score({ inv = inv, id = id }, classFile, level) or nil
            out.ids[id] = true
        elseif id == false then
            e.ilvl, e.score = 0, 0
        else
            e.unknown = true
        end
        out.list[#out.list + 1] = e
        out.ilvl = out.ilvl and e.ilvl and math.min(out.ilvl, e.ilvl) or nil
        out.score = out.score and e.score and math.min(out.score, e.score) or nil
    end
    if slot == "offhand" then
        local main = wornID(16)
        if main == nil or (main and equipLocOf(main) == "INVTYPE_2HWEAPON") then
            out.ilvl, out.score = nil, nil
        end
    end
    return out
end

-- Returns what the player wears in both hands, for a one-hander that fills either: ids of both, list of the main
-- hand and of the off hand unless it has nothing to beat, ilvl the lower of the hands whose item level is known (nil
-- when neither is), and score the lower of their scores, nil when a hand with a known item level has no score.
function Items.EquippedHands()
    local main, off = Items.Equipped("mainhand"), Items.Equipped("offhand")
    local out = { ids = {}, list = {} }
    local score, scored = math.huge, false
    for _, worn in ipairs({ main, off }) do
        for id in pairs(worn.ids) do
            out.ids[id] = true
        end
        local beatable = worn.ilvl ~= nil
        for _, e in ipairs(worn.list) do
            beatable = beatable or e.unknown or e.ilvl == nil or e.score == nil
        end
        if beatable then
            for _, e in ipairs(worn.list) do
                out.list[#out.list + 1] = e
            end
        end
        if worn.ilvl and (not out.ilvl or worn.ilvl < out.ilvl) then
            out.ilvl = worn.ilvl
        end
        if worn.score and score then
            score, scored = math.min(score, worn.score), true
        elseif worn.ilvl then
            score = nil
        end
    end
    out.score = scored and score or nil
    return out
end

-- Items.Beats(score, ilvl, worn) -> true | false | nil, over
-- Rule D2 against an Equipped or EquippedHands table: the weakest worn entry is the one with the lowest score, ties
-- by the lowest item level (an empty slot scores 0 at item level 0). A higher score beats it, an equal score only at
-- a higher item level. nil while a worn entry or the item lacks a score or item level; false when there is nothing
-- to beat (an off hand behind a two-hander). Behind true it also returns the weakest entry's score.
function Items.Beats(score, ilvl, worn)
    local weak
    for _, e in ipairs(worn.list) do
        if e.unknown or e.ilvl == nil or e.score == nil then
            return nil
        end
        if not weak or e.score < weak.score or (e.score == weak.score and e.ilvl < weak.ilvl) then
            weak = e
        end
    end
    if worn.ilvl == nil or not weak then
        return false
    end
    if score == nil or ilvl == nil then
        return nil
    end
    if score > weak.score or (score == weak.score and ilvl > weak.ilvl) then
        return true, weak.score
    end
    return false
end
