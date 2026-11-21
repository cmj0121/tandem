local _, ns = ...

-- Stat weights per class and talent tree (decision 8): built-in Classic defaults, the active tree detected from the
-- talent points spent, and per-character overrides in TandemDB.weights["Name"] =
-- { spec = n|nil, overrides = { [spec] = { key = w } } }. A nil spec means auto.
-- revision goes up with every saved spec or weight change; Upgrade keys its memo on it.
local Weights = { revision = 0 }
ns.Weights = Weights

local Safe = ns.Store.Safe

-- The stored stat keys (decision 7), in display order; Store owns the list.
Weights.KEYS = ns.Store.STAT_KEYS
local IS_KEY = {}
for _, key in ipairs(Weights.KEYS) do
    IS_KEY[key] = true
end

-- Talent trees per class, in talent tab order.
Weights.SPECS = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },
    SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral Combat", "Restoration" },
}

-- The tree assumed while talents are unreadable, unspent or the player is below level 10: the usual levelling tree.
Weights.DEFAULT_SPEC = {
    WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2,
}

-- Hit and crit lines are percentages, so their weights are per 1%; sp counts damage and healing, heal healing only.
Weights.DEFAULTS = {
    WARRIOR = {
        { str = 1, agi = 0.6, sta = 0.5, ap = 0.5, hit = 10, crit = 10, dps = 3, armor = 0.01 },
        { str = 1, agi = 0.7, sta = 0.5, ap = 0.5, hit = 12, crit = 11, dps = 3, armor = 0.01 },
        { sta = 1, def = 1.5, armor = 0.05, dodge = 12, parry = 12, block = 8, blockvalue = 0.5, str = 0.5,
          agi = 0.6, hit = 6, crit = 3, dps = 1 },
    },
    PALADIN = {
        { int = 1, heal = 0.9, sp = 0.9, mp5 = 1.5, spellcrit = 9, spi = 0.3, sta = 0.3 },
        { sta = 1, def = 1.4, armor = 0.05, sp = 0.5, block = 7, blockvalue = 0.6, dodge = 10, parry = 10,
          str = 0.4, agi = 0.5, int = 0.3, hit = 5 },
        { str = 1, agi = 0.5, sta = 0.4, ap = 0.5, crit = 9, hit = 9, dps = 3, int = 0.3, sp = 0.3,
          spellcrit = 3 },
    },
    HUNTER = {
        { agi = 1, rap = 0.5, ap = 0.4, hit = 11, crit = 10, int = 0.4, sta = 0.4, dps = 2, mp5 = 0.6 },
        { agi = 1, rap = 0.5, ap = 0.4, hit = 12, crit = 11, int = 0.4, sta = 0.4, dps = 2.5, mp5 = 0.6 },
        { agi = 1.1, rap = 0.45, ap = 0.4, hit = 11, crit = 10, int = 0.4, sta = 0.5, dps = 2, mp5 = 0.5 },
    },
    ROGUE = {
        { agi = 1, str = 0.5, ap = 0.5, hit = 12, crit = 12, sta = 0.4, dps = 3 },
        { agi = 1, str = 0.5, ap = 0.5, hit = 14, crit = 11, sta = 0.4, dps = 3.5 },
        { agi = 1.1, str = 0.5, ap = 0.5, hit = 11, crit = 11, sta = 0.4, dps = 3 },
    },
    PRIEST = {
        { int = 1, heal = 0.8, sp = 0.8, spi = 0.7, mp5 = 1.5, spellcrit = 7, sta = 0.3 },
        { int = 0.9, heal = 1, sp = 1, spi = 0.9, mp5 = 1.4, spellcrit = 7, sta = 0.3 },
        { sp = 1, spellhit = 12, spellcrit = 6, int = 0.4, spi = 0.4, sta = 0.5, mp5 = 0.6 },
    },
    SHAMAN = {
        { sp = 1, spellcrit = 10, spellhit = 11, int = 0.5, mp5 = 1.2, sta = 0.3, spi = 0.1 },
        { str = 1, agi = 0.7, ap = 0.5, hit = 10, crit = 10, dps = 3, sta = 0.4, int = 0.3 },
        { heal = 1, sp = 1, int = 0.9, mp5 = 1.7, spellcrit = 7, spi = 0.3, sta = 0.3 },
    },
    MAGE = {
        { sp = 1, int = 0.6, spellcrit = 10, spellhit = 12, spi = 0.5, mp5 = 0.9, sta = 0.3 },
        { sp = 1, spellcrit = 12, spellhit = 12, int = 0.4, spi = 0.3, mp5 = 0.7, sta = 0.3 },
        { sp = 1, spellhit = 12, spellcrit = 9, int = 0.45, spi = 0.35, mp5 = 0.7, sta = 0.4 },
    },
    WARLOCK = {
        { sp = 1, spellhit = 12, spellcrit = 4, sta = 0.6, int = 0.35, spi = 0.4, mp5 = 0.6 },
        { sp = 1, sta = 0.8, spellhit = 11, spellcrit = 6, int = 0.4, spi = 0.3, mp5 = 0.6 },
        { sp = 1, spellcrit = 10, spellhit = 12, sta = 0.5, int = 0.35, spi = 0.2, mp5 = 0.5 },
    },
    DRUID = {
        { sp = 1, spellcrit = 9, spellhit = 11, int = 0.5, spi = 0.4, mp5 = 1, sta = 0.3 },
        { agi = 1, str = 1.1, ap = 0.5, sta = 0.6, armor = 0.03, hit = 10, crit = 10, def = 0.5, dodge = 8 },
        { heal = 1, sp = 1, int = 0.8, spi = 0.8, mp5 = 1.6, spellcrit = 6, sta = 0.3 },
    },
}

local function isSpec(v)
    return type(v) == "number" and v >= 1 and v <= 3 and v % 1 == 0
end

local function isWeight(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Returns the player's name as the character key, or nil when the client hides it or still shows its placeholder
-- (UNKNOWNOBJECT) early at login. The key has no realm: Forever blanks the realm APIs (GetRealmName returns "") and
-- the realm UnitName gives is a pseudonym.
function Weights.CharacterKey()
    local name = UnitName and Safe((UnitName("player")))
    local unknown = _G.UNKNOWNOBJECT
    if type(name) == "string" and name ~= "" and not (type(unknown) == "string" and name == unknown) then
        return name
    end
end

-- Returns the character's saved entry, or nil; read defensively since an older or newer db may lack or garble it.
local function entry()
    local db, key = ns.Store.db, Weights.CharacterKey()
    local all = type(db) == "table" and db.weights
    local e = key and type(all) == "table" and all[key]
    return type(e) == "table" and e or nil
end

-- Returns the character's entry, created on first write; nil when read-only or the character is unknown.
local function writableEntry()
    local db, key = ns.Store.db, Weights.CharacterKey()
    if ns.Store.readOnly or type(db) ~= "table" or not key then
        return nil
    end
    if type(db.weights) ~= "table" then
        db.weights = {}
    end
    if type(db.weights[key]) ~= "table" then
        db.weights[key] = {}
    end
    local e = db.weights[key]
    if type(e.overrides) ~= "table" then
        e.overrides = {}
    end
    return e
end

-- Returns the points spent in talent tab i: newer clients return id, name, description, icon, pointsSpent; older
-- ones name, icon, pointsSpent.
local function tabPoints(i)
    local first, _, third, _, fifth = GetTalentTabInfo(i)
    local points = Safe(type(Safe(first)) == "number" and fifth or third)
    return type(points) == "number" and points or 0
end

-- The C_Traits walk's cache (D4): tab is the last good result (a tree, or false for nothing spent), fresh whether it
-- still stands, failed whether a walk failed since the last OnTalents (no walk again until then).
local traits = { tab = nil, fresh = false, failed = false }

-- Returns whether v is a secret value, which must not be read.
local function secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Returns the visible talent nodes of the active config as a list of { x = posX, points = ranksPurchased }, or nil
-- and why when an API raises, is missing or returns something unreadable.
local function traitNodes()
    local config = ns.Store.Call(C_ClassTalents.GetActiveConfigID)
    if type(config) ~= "number" then
        return nil, "no active config"
    end
    local info = ns.Store.Call(C_Traits.GetConfigInfo, config)
    local trees = type(info) == "table" and Safe(info.treeIDs)
    if type(trees) ~= "table" then
        return nil, "no trees"
    end
    local nodes = {}
    for _, treeID in ipairs(trees) do
        local ids = ns.Store.Call(C_Traits.GetTreeNodes, Safe(treeID))
        if type(ids) ~= "table" then
            return nil, "no nodes"
        end
        for _, id in ipairs(ids) do
            local n = ns.Store.Call(C_Traits.GetNodeInfo, config, Safe(id))
            if type(n) ~= "table" then
                return nil, "no node info"
            end
            local visible, x, ranks = n.isVisible, n.posX, n.ranksPurchased
            if secret(visible) or secret(x) or secret(ranks) then
                return nil, "secret node"
            end
            if visible ~= false and type(x) == "number" and x == x then
                nodes[#nodes + 1] = { x = x, points = type(ranks) == "number" and ranks or 0 }
            end
        end
    end
    return nodes
end

-- Returns the indices after which the sorted distinct xs split into three columns: the two largest gaps between
-- neighbours (the leftmost on a tie), in order.
local function columnSplits(xs)
    local first, second
    for i = 1, #xs - 1 do
        local gap = xs[i + 1] - xs[i]
        if not first or gap > xs[first + 1] - xs[first] then
            first, second = i, first
        elseif not second or gap > xs[second + 1] - xs[second] then
            second = i
        end
    end
    return math.min(first, second), math.max(first, second)
end

-- Walks the C_Traits tree once: groups the visible nodes into three tabs by posX and returns the tab with the most
-- ranks purchased (the first on a tie), false when nothing is spent, or nil when the walk fails; and the debug line.
local function walkTraits()
    local nodes, why = traitNodes()
    if not nodes then
        return nil, "spec traits failed: " .. why
    end
    local xs, seen = {}, {}
    for _, n in ipairs(nodes) do
        if not seen[n.x] then
            seen[n.x] = true
            xs[#xs + 1] = n.x
        end
    end
    if #xs < 3 then
        return nil, ("spec traits failed: %d columns"):format(#xs)
    end
    table.sort(xs)
    local a, b = columnSplits(xs)
    local points = { 0, 0, 0 }
    for _, n in ipairs(nodes) do
        local tab = n.x <= xs[a] and 1 or n.x <= xs[b] and 2 or 3
        points[tab] = points[tab] + n.points
    end
    local best, most = false, 0
    for i = 1, 3 do
        if points[i] > most then
            best, most = i, points[i]
        end
    end
    return best, ("spec traits columns %s-%s %s-%s %s-%s points %s/%s/%s -> %s"):format(xs[1], xs[a], xs[a + 1],
        xs[b], xs[b + 1], xs[#xs], points[1], points[2], points[3], tostring(best))
end

-- Returns the cached C_Traits tab (a tree, false for nothing spent, nil when unknown), walking the tree only when
-- the cache is stale and no walk failed since the last OnTalents. A failed walk keeps the last good tab.
local function traitsSpec()
    if not traits.fresh and not traits.failed then
        local tab, line = walkTraits()
        if tab == nil then
            traits.failed = true
        else
            traits.tab, traits.fresh = tab, true
        end
        if ns.Debug ~= nil and ns.Debug.IsOn() then
            ns.Debug.Log(line)
        end
    end
    return traits.tab
end

-- Marks the C_Traits tab stale after a talent change, level up or combat end; the next DetectSpec walks again.
function Weights.OnTalents()
    traits.fresh, traits.failed = false, false
end

-- Returns the talent tree with the most points spent (the first on a tie), or nil below level 10, when the client
-- cannot say or nothing is spent. Sources in order: GetTalentTabInfo, the C_Traits tree (D1), GetSpecialization.
function Weights.DetectSpec(level)
    if type(level) ~= "number" or level < 10 or not ns.Check.Ready("Talent spec") then
        return nil
    end
    if GetTalentTabInfo then
        local tabs = GetNumTalentTabs and Safe(GetNumTalentTabs()) or 3
        local best, most = nil, 0
        for i = 1, math.min(type(tabs) == "number" and tabs or 3, 3) do
            local points = tabPoints(i)
            if points > most then
                best, most = i, points
            end
        end
        return best
    end
    if type(C_ClassTalents) == "table" and type(C_Traits) == "table" then
        local tab = traitsSpec()
        if tab ~= nil then
            return tab or nil
        end
    end
    -- A one-spec client (Forever) always answers 1 (D2).
    local count = ns.Store.Call(GetNumSpecializations)
    if type(count) == "number" and count <= 1 then
        return nil
    end
    local get = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
    local spec = ns.Store.Call(get)
    return isSpec(spec) and spec or nil
end

-- Returns the active spec for the class and whether it is auto: the saved choice, else the detected tree, else the
-- class default. nil for a class without built-in weights.
function Weights.Active(classFile, level)
    if not Weights.DEFAULTS[classFile] then
        return nil, true
    end
    local e = entry()
    if e and isSpec(e.spec) then
        return e.spec, false
    end
    return Weights.DetectSpec(level) or Weights.DEFAULT_SPEC[classFile], true
end

-- Returns the character's valid overrides for spec as a new { key = w }.
local function overrides(spec)
    local e = entry()
    local saved = e and type(e.overrides) == "table" and e.overrides[spec]
    local out = {}
    if type(saved) == "table" then
        for key, w in pairs(saved) do
            if IS_KEY[key] and isWeight(w) then
                out[key] = w
            end
        end
    end
    return out
end
Weights.Overrides = overrides

-- Returns a new { key = w } for the class and spec: the built-in weights with the character's overrides on top.
-- Empty for a class or spec without built-ins.
function Weights.Effective(classFile, spec)
    local out = {}
    local base = Weights.DEFAULTS[classFile] and Weights.DEFAULTS[classFile][spec]
    if not base then
        return out
    end
    for key, w in pairs(base) do
        out[key] = w
    end
    for key, w in pairs(overrides(spec)) do
        out[key] = w
    end
    return out
end

-- Returns the weighted sum of stats ({ key = number }) for the class and spec, or nil when stats is nil. A nil spec
-- means the active one at the player's level. weights, an Effective table, skips building it again for each item.
function Weights.Score(stats, classFile, spec, weights)
    if type(stats) ~= "table" then
        return nil
    end
    if not weights then
        if spec == nil then
            local level = UnitLevel and Safe(UnitLevel("player"))
            spec = Weights.Active(classFile, level)
        end
        weights = Weights.Effective(classFile, spec)
    end
    local score = 0
    for key, w in pairs(weights) do
        local v = stats[key]
        if type(v) == "number" then
            score = score + v * w
        end
    end
    return score
end

-- Saves the character's spec: 1-3, or "auto"/nil to follow the talents; false when invalid or read-only.
function Weights.SetSpec(spec)
    if spec == "auto" then
        spec = nil
    end
    if spec ~= nil and not isSpec(spec) then
        return false
    end
    local e = writableEntry()
    if not e then
        return false
    end
    e.spec = spec
    Weights.revision = Weights.revision + 1
    return true
end

-- Saves one override for the active spec (0 ignores the stat); false for an unknown key, a non-number, a class
-- without built-ins or read-only.
function Weights.SetOverride(key, w, classFile, level)
    local spec = Weights.Active(classFile, level)
    if not (spec and IS_KEY[key] and isWeight(w)) then
        return false
    end
    local e = writableEntry()
    if not e then
        return false
    end
    if type(e.overrides[spec]) ~= "table" then
        e.overrides[spec] = {}
    end
    e.overrides[spec][key] = w
    Weights.revision = Weights.revision + 1
    return true
end

-- Drops the active spec's overrides; false for a class without built-ins or read-only.
function Weights.Reset(classFile, level)
    local spec = Weights.Active(classFile, level)
    local e = spec and writableEntry()
    if not e then
        return false
    end
    e.overrides[spec] = nil
    Weights.revision = Weights.revision + 1
    return true
end
