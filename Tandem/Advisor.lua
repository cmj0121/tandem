local _, ns = ...

-- Read-only view over own TandemDB and the shipped ns.Shipped: which items a class can use, how they rank in their
-- slot, and where they drop. Class and level are arguments; nothing here touches the player.
local Advisor = {}
ns.Advisor = Advisor

local Safe = ns.Store.Safe
local EMPTY = {}

-- Game objects named in source lines, by locale key.
local OBJECT_NAMES = { [35591] = "Fishing" }

Advisor.SLOTS = {
    "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket",
    "mainhand", "offhand", "twohand", "ranged",
}

local IS_SLOT = {}
for _, slot in ipairs(Advisor.SLOTS) do
    IS_SLOT[slot] = true
end

local SLOT_OF = {
    INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
    INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
    INVTYPE_TRINKET = "trinket", INVTYPE_WEAPON = "mainhand", INVTYPE_WEAPONMAINHAND = "mainhand",
    INVTYPE_WEAPONOFFHAND = "offhand", INVTYPE_SHIELD = "offhand", INVTYPE_HOLDABLE = "offhand",
    INVTYPE_2HWEAPON = "twohand", INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged",
    INVTYPE_THROWN = "ranged", INVTYPE_RELIC = "ranged",
}

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

Advisor.PROFICIENCY = {
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

-- Returns field of a table-valued source, or an empty table when either is missing or not a table.
local function field(t, key)
    local v = type(t) == "table" and t[key]
    return type(v) == "table" and v or EMPTY
end

local function own(key)
    return field(ns.Store.db, key)
end

local function shipped(key)
    return field(ns.Shipped, key)
end

local function isRecord(r)
    return type(r) == "table" and type(r[1]) == "number" and type(r[2]) == "number" and type(r[3]) == "number"
        and type(r[4]) == "string" and type(r[5]) == "number" and type(r[6]) == "number"
end

local function isDeprecated(r)
    return r[7] == 1
end

local function dualWields(class, level)
    local dual = Advisor.PROFICIENCY[class] and Advisor.PROFICIENCY[class].dualWield
    return dual ~= nil and level >= dual
end

-- Returns true when an equipLoc fills slot for a class at a level: its own slot, and the off hand too for a
-- one-hand weapon once the class dual-wields.
local function fills(equipLoc, slot, class, level)
    return SLOT_OF[equipLoc] == slot
        or (slot == "offhand" and equipLoc == "INVTYPE_WEAPON" and dualWields(class, level))
end

-- Returns ok, reason ("slot" | "proficiency" | "level"), needLevel (only for "level").
function Advisor.Usable(item, class, level)
    if not SLOT_OF[item[4]] then
        return false, "slot"
    end
    local classID, sub = item[5], item[6]
    local minLevel = ALL_CLASSES[classID] and ALL_CLASSES[classID][sub]
    local prof = Advisor.PROFICIENCY[class]
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

-- Returns an item record { ilvl, reqLevel, quality, equipLoc, classID, subclassID [, 1 = deprecated] } or nil; own
-- data wins.
function Advisor.Item(id)
    local r = own("items")[id]
    if isRecord(r) then
        return r
    end
    r = shipped("items")[id]
    if isRecord(r) then
        return r
    end
end

-- Returns true when the item's record is flagged deprecated.
function Advisor.IsDeprecated(id)
    local r = Advisor.Item(id)
    return r ~= nil and isDeprecated(r)
end

-- Returns true when a row for an equipLoc in All slots also fills the off hand: a one-hand weapon once the class
-- dual-wields.
local function alsoOffhand(equipLoc, class, level)
    return equipLoc == "INVTYPE_WEAPON" and dualWields(class, level)
end

local lootIndex, indexedFrom

-- Returns the shipped loot rows grouped by item; rebuilt only when ns.Shipped.loot changes.
local function shippedByItem()
    local loot = shipped("loot")
    if indexedFrom ~= loot then
        lootIndex, indexedFrom = {}, loot
        for _, r in ipairs(loot) do
            if type(r) == "table" and type(r[1]) == "number" and type(r[2]) == "string" and type(r[3]) == "number"
                and type(r[4]) == "number" and type(r[5]) == "number" then
                local rows = lootIndex[r[1]] or {}
                lootIndex[r[1]] = rows
                rows[#rows + 1] = r
            end
        end
    end
    return lootIndex
end

local function ownSourced()
    local set = {}
    for _, v in pairs(own("loot")) do
        if type(v) == "table" and v.item then
            set[v.item] = true
        end
    end
    return set
end

-- Returns the item ids with a known source: { own = {[id] = true}, shipped = {[id] = rows} }. Build it once and
-- pass it as opts.index to several Best calls.
function Advisor.SourceIndex()
    return { own = ownSourced(), shipped = shippedByItem() }
end

local function isSourced(id, index)
    return index.own[id] == true or index.shipped[id] ~= nil
end

function Advisor.HasSource(id)
    return isSourced(id, Advisor.SourceIndex())
end

local function before(a, b)
    if a.ilvl ~= b.ilvl then
        return a.ilvl > b.ilvl
    end
    if a.quality ~= b.quality then
        return a.quality > b.quality
    end
    return a.id < b.id
end

-- Walks own and shipped items once (own records win) and returns the rows for slot (nil: every ranked slot, each
-- item once under its first slot), sorted best first. f.sourcedOnly, f.hideDeprecated and f.quality drop items
-- before a row is built, f.usableOnly after; f.index is the SourceIndex to use.
local function list(slot, class, level, f)
    local out, done = {}, {}
    local index = f.index
    local function consider(id)
        if done[id] or type(id) ~= "number" then
            return
        end
        done[id] = true
        local r = Advisor.Item(id)
        if not r or (f.hideDeprecated and isDeprecated(r)) or (f.quality and r[3] ~= f.quality) then
            return
        end
        -- The first slot an item fills is SLOT_OF[equipLoc] (a one-hander is listed under main hand).
        local rowSlot = slot or SLOT_OF[r[4]]
        if not rowSlot or (slot and not fills(r[4], slot, class, level)) then
            return
        end
        local sourced = isSourced(id, index)
        if f.sourcedOnly and not sourced then
            return
        end
        local usable, reason, needLevel = Advisor.Usable(r, class, level)
        if usable or not f.usableOnly then
            out[#out + 1] = { id = id, slot = rowSlot, ilvl = r[1], quality = r[3], reqLevel = r[2], usable = usable,
                              reason = reason, needLevel = needLevel, sourced = sourced,
                              deprecated = isDeprecated(r) or nil,
                              offhand = (not slot and alsoOffhand(r[4], class, level)) or nil }
        end
    end
    for id in pairs(own("items")) do
        consider(id)
    end
    for id in pairs(shipped("items")) do
        consider(id)
    end
    table.sort(out, before)
    return out
end

-- Deprecated items are never the best.
local function best(slot, class, level, all, index)
    return list(slot, class, level, { usableOnly = true, sourcedOnly = not all, hideDeprecated = true, index = index })
end

-- Returns every known item for slot, or for all ranked slots when slot is nil, sorted best first:
-- { id, slot, ilvl, quality, reqLevel, usable, reason, needLevel, sourced, deprecated, offhand }; offhand is true in
-- All slots for a one-hander the class can also wield in the off hand. opts.usableOnly drops rows the class or level
-- cannot use, opts.hideDeprecated flagged items, opts.quality (a number) items of any other quality. nil for an
-- unknown slot.
function Advisor.List(slot, class, level, opts)
    if slot ~= nil and not IS_SLOT[slot] then
        return nil
    end
    opts = opts or EMPTY
    return list(slot, class, level, { usableOnly = opts.usableOnly, hideDeprecated = opts.hideDeprecated,
                                      quality = opts.quality, index = Advisor.SourceIndex() })
end

-- Returns the usable items for slot sorted best first (List rows); sourceless items only with opts.all. opts.index
-- reuses an Advisor.SourceIndex() across calls. nil for an unknown slot.
function Advisor.Best(slot, class, level, opts)
    if not IS_SLOT[slot] then
        return nil
    end
    return best(slot, class, level, opts and opts.all, opts and opts.index or Advisor.SourceIndex())
end

-- Returns where an item goes for a class at a level without walking the other items: nil for an unknown item, else
-- { slot, usable, reason, needLevel, deprecated, offhand }; slot is nil when the item has no ranked slot, offhand is
-- true for a one-hander the class can also wield in the off hand.
function Advisor.Place(id, class, level)
    local r = Advisor.Item(id)
    if not r then
        return nil
    end
    local usable, reason, needLevel = Advisor.Usable(r, class, level)
    return { slot = SLOT_OF[r[4]], usable = usable, reason = reason, needLevel = needLevel,
             deprecated = isDeprecated(r) or nil, offhand = alsoOffhand(r[4], class, level) or nil }
end

-- Rank's memo: the source index and the ranked list per slot, for one class:level:Store.revision over one own db
-- and one shipped table. Any record change bumps the revision; a level-up changes the key.
local memo = {}

local function memoFor(class, level)
    local key = class .. ":" .. level .. ":" .. ns.Store.revision
    if memo.key ~= key or memo.db ~= ns.Store.db or memo.shipped ~= ns.Shipped then
        memo = { key = key, db = ns.Store.db, shipped = ns.Shipped, index = Advisor.SourceIndex(), ranked = {} }
    end
    return memo
end

local function rankedFor(m, slot, class, level)
    m.ranked[slot] = m.ranked[slot] or best(slot, class, level, false, m.index)
    return m.ranked[slot]
end

-- Returns nil for an unknown item, else { rank, total, slot, usable, reason, needLevel, sourced, deprecated,
-- offhand }; rank and total are nil when the item has no ranked slot. Repeated calls reuse one walk per slot until a
-- record changes.
function Advisor.Rank(id, class, level)
    local result = Advisor.Place(id, class, level)
    if not result then
        return nil
    end
    local m = memoFor(class, level)
    result.sourced = isSourced(id, m.index)
    if not result.slot then
        return result
    end
    local r = Advisor.Item(id)
    local me = { id = id, ilvl = r[1], quality = r[3] }
    local ranked = rankedFor(m, result.slot, class, level)
    local rank, listed = 1, false
    for _, e in ipairs(ranked) do
        if e.id == id then
            listed = true
        elseif before(e, me) then
            rank = rank + 1
        end
    end
    result.rank, result.total = rank, #ranked + (listed and 0 or 1)
    return result
end

-- Returns the localised map name, or nil when unknown.
function Advisor.MapName(map)
    if map == 0 or not (C_Map and C_Map.GetMapInfo) then
        return nil
    end
    local info = Safe(C_Map.GetMapInfo(map))
    return type(info) == "table" and Safe(info.name) or nil
end

-- Returns the npc's name from own data, else from the shipped names for the client locale.
local function npcName(npcID)
    local name = own("npcs")[npcID]
    if type(name) == "string" then
        return name
    end
    name = field(shipped("names"), GetLocale and GetLocale() or nil)[npcID]
    return type(name) == "string" and name or nil
end

local function npcCount(t, npcID)
    local n = t[npcID]
    return type(n) == "number" and n or 0
end

local BASES = { { field = "kills", label = "kill" }, { field = "corpses", label = "corpse" } }

-- Returns rate, basis ("kill" | "corpse") for an npc that dropped the item drops.own / drops.shipped times, or nil.
-- Only a dataset with drops counts; kills beat corpses, the larger denominator wins (tie: shipped), and a rate
-- above 100% (drops counted before their denominator) is no rate.
local function dropRate(npcID, drops)
    local sets = {}
    for _, name in ipairs({ "shipped", "own" }) do
        local data = name == "own" and own or shipped
        if drops[name] > 0 then
            sets[#sets + 1] = { drops = drops[name], kills = npcCount(data("kills"), npcID),
                                corpses = npcCount(data("corpses"), npcID) }
        end
    end
    for _, basis in ipairs(BASES) do
        local pick
        for _, set in ipairs(sets) do
            if set[basis.field] > 0 and (not pick or set[basis.field] > pick[basis.field]) then
                pick = set
            end
        end
        if pick then
            if pick.drops > pick[basis.field] then
                return nil
            end
            return pick.drops / pick[basis.field], basis.label
        end
    end
end

-- Returns where an item drops: { kind, id, map, count, coords, name, mapName, rate, rateBasis } sorted by count desc,
-- then kind, id, map. Own and shipped rows merge by max count (decision 13); rates follow decision 16.
function Advisor.Sources(id)
    local rows, byKey = {}, {}
    local function add(dataset, kind, srcID, map, count, coords)
        local key = kind .. ":" .. srcID .. ":" .. map
        local row = byKey[key]
        if not row then
            row = { kind = kind, id = srcID, map = map, count = 0, coords = {}, by = {} }
            byKey[key] = row
            rows[#rows + 1] = row
        end
        row.by[dataset] = count
        if count > row.count or (count == row.count and dataset == "shipped") then
            row.count, row.coords = count, coords
        end
    end
    for _, v in pairs(own("loot")) do
        if type(v) == "table" and v.item == id then
            add("own", v.kind, v.id, v.map, v.count, v.coords)
        end
    end
    for _, r in ipairs(shippedByItem()[id] or EMPTY) do
        local coords = {}
        for i = 6, #r - 1, 2 do
            coords[#coords + 1] = { r[i], r[i + 1] }
        end
        add("shipped", r[2], r[3], r[4], r[5], coords)
    end

    local drops = {}
    for _, row in ipairs(rows) do
        if row.kind == "c" then
            local d = drops[row.id] or { own = 0, shipped = 0 }
            drops[row.id] = d
            d.own = d.own + (row.by.own or 0)
            d.shipped = d.shipped + (row.by.shipped or 0)
        end
    end
    for _, row in ipairs(rows) do
        if row.kind == "c" then
            row.name = npcName(row.id)
            row.rate, row.rateBasis = dropRate(row.id, drops[row.id])
        elseif row.kind == "o" and OBJECT_NAMES[row.id] then
            row.name = ns.L[OBJECT_NAMES[row.id]]
        end
        row.mapName = Advisor.MapName(row.map)
        row.by = nil
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        if a.id ~= b.id then
            return a.id < b.id
        end
        return a.map < b.map
    end)
    return rows
end
