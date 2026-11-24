local _, ns = ...

-- Owns TandemDB: validates and migrates it on load and is its only writer. It keeps each character's stat weights,
-- layout mode, class macro pick, weapon enchant proc counts, the enemy players who killed them and the craft flyout's
-- learned spell items, recipes, made times and pick, the class trainer spells seen and the UI layout state; every
-- other key an older schema saved is dropped on load.
local Store = { readOnly = false }
ns.Store = Store

local SCHEMA = 8
Store.SCHEMA = SCHEMA
-- Locale-independent stat keys a weights override may carry: sp is spell damage and healing, heal healing only, dps a
-- weapon's damage per second.
local STAT_KEYS = {
    "str", "agi", "sta", "int", "spi", "armor", "dps", "ap", "rap", "sp", "heal", "hit", "crit", "spellhit",
    "spellcrit", "mp5", "def", "dodge", "parry", "block", "blockvalue",
}
Store.STAT_KEYS = STAT_KEYS
local IS_STAT = {}
for _, key in ipairs(STAT_KEYS) do
    IS_STAT[key] = true
end
local MAX_SPEC = 3

-- The top-level keys a current db holds; migrate drops and counts any other.
local KEPT = { schemaVersion = true, weights = true, trainers = true, layout = true, modes = true,
    picks = true, procs = true, killers = true, crafts = true }
-- The weapon enchant families whose procs are counted.
local PROC_FAMILIES = { windfury = true, flametongue = true, frostbrand = true }
local MAX_LAYOUT_NAME = 64
Store.MAX_KILLERS = 50

local floor = math.floor

local function isNum(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v, min)
    return isNum(v) and v == floor(v) and v >= min
end

local function newDB()
    return {
        schemaVersion = SCHEMA,
        weights = {},
        trainers = {},
        layout = {},
    }
end

-- Returns a clean copy of a { statKey = number } table, dropping (and calling drop for) each invalid entry; nil
-- when v is not a table.
local function copyStats(v, drop)
    if type(v) ~= "table" then
        return nil
    end
    local out = {}
    for key, n in pairs(v) do
        if IS_STAT[key] and isNum(n) then
            out[key] = n
        else
            drop()
        end
    end
    return out
end

-- A class key is an uppercase class token such as "MAGE".
local function isClass(v)
    return type(v) == "string" and v:match("^[A-Z]+$") ~= nil
end

-- Returns a clean copy of a trainer entry { level = n, rank = r|nil }, or nil.
local function copyTrainerSpell(v)
    if type(v) == "table" and isInt(v.level, 1) and (v.rank == nil or isInt(v.rank, 1)) then
        return { level = v.level, rank = v.rank }
    end
end

local function isSpec(v)
    return isInt(v, 1) and v <= MAX_SPEC
end

-- Returns a clean copy of a character's weights { spec = n|nil, overrides = { [spec] = { statKey = w } } }, or nil
-- when v is not a table; drop is called once for each invalid field or entry inside it.
local function copyWeights(v, drop)
    if type(v) ~= "table" then
        return nil
    end
    local out = { overrides = {} }
    if isSpec(v.spec) then
        out.spec = v.spec
    elseif v.spec ~= nil then
        drop()
    end
    if type(v.overrides) == "table" then
        for spec, w in pairs(v.overrides) do
            local clean = isSpec(spec) and copyStats(w, drop)
            if clean then
                out.overrides[spec] = clean
            else
                drop()
            end
        end
    elseif v.overrides ~= nil then
        drop()
    end
    return out
end

local function isAngle(v)
    return isNum(v) and v >= 0 and v < 360
end

-- The check for each layout field: on is a boolean, previous { name, type } the layout active before Tandem's, tot
-- the showTargetOfTarget CVar value before Tandem set it, coords the minimapShowPlayerCoords value before Tandem
-- cleared it, minimap { angle = degrees|nil, hidden = bool|nil } the minimap button's place and visibility, built the
-- mode the Tandem Edit Mode layout was last built with ("heal"; nil for dps), books the library book hints switch
-- (false off; absent on).
local LAYOUT_FIELDS = {
    on = function(v)
        return type(v) == "boolean"
    end,
    previous = function(v)
        return type(v) == "table" and type(v.name) == "string" and v.name ~= "" and #v.name <= MAX_LAYOUT_NAME
            and isInt(v.type, 0)
    end,
    tot = function(v)
        return type(v) == "string"
    end,
    coords = function(v)
        return type(v) == "string"
    end,
    minimap = function(v)
        return type(v) == "table" and (v.angle == nil or isAngle(v.angle))
            and (v.hidden == nil or type(v.hidden) == "boolean")
    end,
    built = function(v)
        return v == "heal"
    end,
    books = function(v)
        return type(v) == "boolean"
    end,
}

-- The layout fields whose false is saved; for the others, false clears the field like nil.
local KEEPS_FALSE = { books = true }

-- A character's saved layout mode: only "heal" is kept; absent means dps.
local function isMode(v)
    return v == "heal"
end

-- A character's saved class macro pick is an entry id such as "poison".
local function isPick(v)
    return type(v) == "string" and v ~= ""
end

-- A weapon enchant family's saved counts: { hits = n, procs = n }, whole numbers from 0.
local function copyProcCount(v)
    if type(v) == "table" and isInt(v.hits, 0) and isInt(v.procs, 0) then
        return { hits = v.hits, procs = v.procs }
    end
end

local function isOptional(v, check, arg)
    return v == nil or check(v, arg)
end

local function isText(v)
    return type(v) == "string" and v ~= ""
end

-- Returns a clean copy of a killer entry { name, realm, class|nil, level|nil, count, last, zone|nil } saved under
-- fullName, or nil.
local function copyKiller(fullName, v)
    if type(v) == "table" and isText(v.name) and isText(v.realm) and fullName == v.name .. "-" .. v.realm
        and isOptional(v.class, isClass) and isOptional(v.level, isInt, 1) and isInt(v.count, 1)
        and isInt(v.last, 0) and isOptional(v.zone, isText) then
        return { name = v.name, realm = v.realm, class = v.class, level = v.level, count = v.count, last = v.last,
            zone = v.zone }
    end
end

-- A craft entry id: "spell:<spellID>" or "recipe:<recipeID>".
local function isCraftId(v)
    return type(v) == "string" and (v:match("^spell:%d+$") or v:match("^recipe:%d+$")) ~= nil
end

local function isIcon(v)
    return isInt(v, 1) or isText(v)
end

-- Returns a clean copy of a cached recipe { name, icon|nil, item|nil, profession|nil }, or nil.
local function copyRecipe(v)
    if type(v) == "table" and isText(v.name) and isOptional(v.icon, isIcon) and isOptional(v.item, isInt, 1)
        and isOptional(v.profession, isText) then
        return { name = v.name, icon = v.icon, item = v.item, profession = v.profession }
    end
end

-- Returns a clean copy of a character's crafts { pairs = { [spellID] = itemID }, recipes = { [recipeID] = recipe },
-- made = { [entryId] = time }, pick = entryId|nil }, or nil when v is not a table; drop is called once for each
-- invalid field or entry inside it.
local function copyCrafts(v, drop)
    if type(v) ~= "table" then
        return nil
    end
    local out = { pairs = {}, recipes = {}, made = {} }
    local function each(t, keep)
        if type(t) == "table" then
            for k, x in pairs(t) do
                if not keep(k, x) then
                    drop()
                end
            end
        elseif t ~= nil then
            drop()
        end
    end
    each(v.pairs, function(spell, item)
        if isInt(spell, 1) and isInt(item, 1) then
            out.pairs[spell] = item
            return true
        end
    end)
    each(v.recipes, function(id, r)
        local clean = isInt(id, 1) and copyRecipe(r)
        out.recipes[id] = clean or nil
        return clean
    end)
    each(v.made, function(id, when)
        if isCraftId(id) and isInt(when, 0) then
            out.made[id] = when
            return true
        end
    end)
    if isCraftId(v.pick) then
        out.pick = v.pick
    elseif v.pick ~= nil then
        drop()
    end
    return out
end

local function copyLayoutField(field, v)
    if field == "previous" then
        return { name = v.name, type = v.type }
    elseif field == "minimap" then
        return { angle = v.angle, hidden = v.hidden }
    end
    return v
end

-- Returns a per-character table rekeyed from "<name>-<realm>" (schema 7 and older) to "<name>", the part before the
-- first "-"; a key with no "-" is kept. When several old keys map to one name, the first in sorted order wins and
-- each other counts as a drop.
local function rekey(t, drop)
    local names = {}
    local out = {}
    for key, v in pairs(t) do
        if type(key) == "string" then
            names[#names + 1] = key
        else
            out[key] = v
        end
    end
    table.sort(names)
    for _, key in ipairs(names) do
        local name = key:match("^[^-]*")
        if out[name] == nil then
            out[name] = t[key]
        else
            drop()
        end
    end
    return out
end

-- Copies every entry of raw that passes its type check into a fresh current-schema table; every key a current db
-- does not hold counts as one drop. A db older than schema 8, unversioned or with a damaged version has its
-- per-character tables rekeyed to the bare name.
local function migrate(raw, report)
    local db = newDB()
    local function drop()
        report.dropped = report.dropped + 1
    end
    local old = not isNum(raw.schemaVersion) or raw.schemaVersion < 8
    local function entries(t, perCharacter)
        if type(t) ~= "table" then
            if t ~= nil then
                drop()
            end
            return {}
        end
        return perCharacter and old and rekey(t, drop) or t
    end

    for name, v in pairs(entries(raw.weights, true)) do
        local weights = type(name) == "string" and name ~= "" and copyWeights(v, drop)
        if weights then
            db.weights[name] = weights
        else
            drop()
        end
    end

    for classFile, spells in pairs(entries(raw.trainers)) do
        if isClass(classFile) and type(spells) == "table" then
            local clean = {}
            for spellID, v in pairs(spells) do
                local entry = isInt(spellID, 1) and copyTrainerSpell(v)
                if entry then
                    clean[spellID] = entry
                else
                    drop()
                end
            end
            db.trainers[classFile] = clean
        else
            drop()
        end
    end

    for name, v in pairs(entries(raw.modes, true)) do
        if type(name) == "string" and name ~= "" and isMode(v) then
            db.modes = db.modes or {}
            db.modes[name] = v
        else
            drop()
        end
    end

    for name, v in pairs(entries(raw.picks, true)) do
        if type(name) == "string" and name ~= "" and isPick(v) then
            db.picks = db.picks or {}
            db.picks[name] = v
        else
            drop()
        end
    end

    for name, families in pairs(entries(raw.procs, true)) do
        if type(name) == "string" and name ~= "" and type(families) == "table" then
            local clean = {}
            for family, v in pairs(families) do
                local count = PROC_FAMILIES[family] and copyProcCount(v)
                if count then
                    clean[family] = count
                else
                    drop()
                end
            end
            db.procs = db.procs or {}
            db.procs[name] = clean
        else
            drop()
        end
    end

    for name, killers in pairs(entries(raw.killers, true)) do
        if isText(name) and type(killers) == "table" then
            local clean = {}
            for fullName, v in pairs(killers) do
                local entry = copyKiller(fullName, v)
                if entry then
                    clean[fullName] = entry
                else
                    drop()
                end
            end
            db.killers = db.killers or {}
            db.killers[name] = clean
        else
            drop()
        end
    end

    for name, v in pairs(entries(raw.crafts, true)) do
        local crafts = isText(name) and copyCrafts(v, drop)
        if crafts then
            db.crafts = db.crafts or {}
            db.crafts[name] = crafts
        else
            drop()
        end
    end

    for field, v in pairs(entries(raw.layout)) do
        if LAYOUT_FIELDS[field] and LAYOUT_FIELDS[field](v) then
            db.layout[field] = copyLayoutField(field, v)
        else
            drop()
        end
    end

    for key in pairs(raw) do
        if not KEPT[key] then
            drop()
        end
    end
    return db
end

-- Returns a current-schema db and a report {status, version, dropped}; status is
-- "new", "reset" (not a table), "ok", "migrated" or "newer" (kept as is, writes disabled).
function Store.Load(raw)
    local report = { dropped = 0 }
    Store.readOnly = false

    local db
    if raw == nil then
        report.status = "new"
        db = newDB()
    elseif type(raw) ~= "table" then
        report.status = "reset"
        db = newDB()
    elseif isNum(raw.schemaVersion) and raw.schemaVersion > SCHEMA then
        report.status = "newer"
        report.version = raw.schemaVersion
        Store.readOnly = true
        db = raw
    else
        report.status = raw.schemaVersion == SCHEMA and "ok" or "migrated"
        report.version = raw.schemaVersion
        db = migrate(raw, report)
    end
    Store.db = db
    return db, report
end

-- Store.SetTrainerSpell(classFile, spellID, level, rank) -> changed
-- Records that a classFile trainer teaches spellID (rank r or nil) from level. A spell already recorded keeps the
-- lower level and its rank when rank is nil. False when invalid, read-only or unchanged.
function Store.SetTrainerSpell(classFile, spellID, level, rank)
    if Store.readOnly or not isClass(classFile) or not isInt(spellID, 1) then
        return false
    end
    local entry = copyTrainerSpell({ level = level, rank = rank })
    if not entry then
        return false
    end
    local spells = Store.db.trainers[classFile]
    local old = spells and spells[spellID]
    if old then
        entry.level = math.min(old.level, entry.level)
        entry.rank = entry.rank or old.rank
        if entry.level == old.level and entry.rank == old.rank then
            return false
        end
    end
    if not spells then
        spells = {}
        Store.db.trainers[classFile] = spells
    end
    spells[spellID] = entry
    return true
end

-- Returns a class's recorded trainer spells { [spellID] = { level = n, rank = r|nil } }, or nil when none or the db
-- is newer (kept raw).
function Store.TrainerSpells(classFile)
    if not Store.readOnly then
        return Store.db.trainers[classFile]
    end
end

-- Returns the layout state { on = bool|nil, previous = { name, type }|nil, tot = string|nil, coords = string|nil,
-- minimap = { angle, hidden }|nil, built = "heal"|nil, books = bool|nil }; empty (off) when the db is newer (kept
-- raw).
function Store.Layout()
    return not Store.readOnly and Store.db.layout or {}
end

-- Sets one layout field (on, previous, tot, coords, minimap, built or books) to value, or clears it with nil (or
-- false, except for books); false when invalid or read-only.
function Store.SetLayout(field, value)
    local valid = LAYOUT_FIELDS[field]
    if Store.readOnly or not valid or (value ~= nil and not valid(value)) then
        return false
    end
    if value == nil or (value == false and not KEEPS_FALSE[field]) then
        Store.db.layout[field] = nil
    else
        Store.db.layout[field] = copyLayoutField(field, value)
    end
    return true
end

-- Returns the layout mode saved for the character key ("heal"), or nil (dps, or the db is newer).
function Store.Mode(key)
    local modes = not Store.readOnly and Store.db.modes
    return type(modes) == "table" and modes[key] or nil
end

-- Saves the character key's layout mode ("heal", or nil for dps); false when invalid or read-only.
function Store.SetMode(key, mode)
    if Store.readOnly or type(key) ~= "string" or key == "" or (mode ~= nil and not isMode(mode)) then
        return false
    end
    Store.db.modes = Store.db.modes or {}
    Store.db.modes[key] = mode
    return true
end

-- Returns the class macro entry id picked by the character key, or nil (none, or the db is newer).
function Store.Pick(key)
    local picks = not Store.readOnly and Store.db.picks
    return type(picks) == "table" and picks[key] or nil
end

-- Saves the character key's class macro pick (an entry id, or nil to clear it); false when invalid or read-only.
function Store.SetPick(key, id)
    if Store.readOnly or type(key) ~= "string" or key == "" or (id ~= nil and not isPick(id)) then
        return false
    end
    Store.db.picks = Store.db.picks or {}
    Store.db.picks[key] = id
    return true
end

-- Returns the character key's counts for a weapon enchant family { hits, procs } (a copy), or nil (none, an unknown
-- family, or the db is newer).
function Store.Procs(key, family)
    local procs = not Store.readOnly and Store.db.procs
    local mine = type(procs) == "table" and procs[key]
    local count = type(mine) == "table" and PROC_FAMILIES[family] and mine[family]
    return count and copyProcCount(count) or nil
end

-- Saves the character key's counts for a weapon enchant family ({ hits, procs }, or nil to clear them); false when
-- invalid or read-only.
function Store.SetProcs(key, family, count)
    if Store.readOnly or type(key) ~= "string" or key == "" or not PROC_FAMILIES[family]
        or (count ~= nil and not copyProcCount(count)) then
        return false
    end
    Store.db.procs = Store.db.procs or {}
    Store.db.procs[key] = Store.db.procs[key] or {}
    Store.db.procs[key][family] = count and copyProcCount(count) or nil
    return true
end

-- Returns the character key's killers as copies, each with its fullName, most recently seen first; empty when none or
-- the db is newer.
function Store.Killers(key)
    local killers = not Store.readOnly and Store.db.killers
    local mine = type(killers) == "table" and killers[key]
    local list = {}
    if type(mine) == "table" then
        for fullName, v in pairs(mine) do
            local entry = copyKiller(fullName, v)
            entry.fullName = fullName
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        if a.last ~= b.last then
            return a.last > b.last
        end
        return a.fullName < b.fullName
    end)
    return list
end

-- Records a kill of the character key by an enemy player { name, realm|nil, class|nil, level|nil, zone|nil, when }:
-- a new one counts 1, a known one counts up; last becomes when and class, level and zone are updated when given. A
-- new one past MAX_KILLERS drops the least recently seen. A nil or empty realm is the player's own. False when
-- invalid or read-only.
function Store.AddKiller(key, k)
    if Store.readOnly or not isText(key) or type(k) ~= "table" or not isText(k.name) or not isInt(k.when, 0)
        or not isOptional(k.class, isClass) or not isOptional(k.level, isInt, 1) or not isOptional(k.zone, isText)
        or (k.realm ~= nil and type(k.realm) ~= "string") then
        return false
    end
    local realm = k.realm
    if realm == nil or realm == "" then
        realm = Store.Call(GetNormalizedRealmName) or Store.Call(GetRealmName)
        if not isText(realm) then
            return false
        end
    end
    local fullName = k.name .. "-" .. realm
    Store.db.killers = Store.db.killers or {}
    local mine = Store.db.killers[key] or {}
    Store.db.killers[key] = mine
    local entry = mine[fullName]
    if entry then
        entry.count = entry.count + 1
    else
        local n, oldest = 0, nil
        for name, v in pairs(mine) do
            n = n + 1
            local o = mine[oldest]
            if not o or v.last < o.last or (v.last == o.last and name < oldest) then
                oldest = name
            end
        end
        if n >= Store.MAX_KILLERS then
            mine[oldest] = nil
        end
        entry = { name = k.name, realm = realm, count = 1 }
        mine[fullName] = entry
    end
    entry.last = k.when
    entry.class = k.class or entry.class
    entry.level = k.level or entry.level
    entry.zone = k.zone or entry.zone
    return true
end

-- Removes one of the character key's killers by fullName; false when not recorded or read-only.
function Store.ForgetKiller(key, fullName)
    local killers = not Store.readOnly and Store.db.killers
    local mine = type(killers) == "table" and killers[key]
    if type(mine) ~= "table" or type(fullName) ~= "string" or not mine[fullName] then
        return false
    end
    mine[fullName] = nil
    return true
end

-- Empties the character key's killers; false when invalid or read-only.
function Store.ClearKillers(key)
    if Store.readOnly or not isText(key) then
        return false
    end
    if type(Store.db.killers) == "table" then
        Store.db.killers[key] = nil
    end
    return true
end

-- Returns a copy of the character key's crafts { pairs, recipes, made, pick|nil }; empty when none or the db is newer.
function Store.Crafts(key)
    local crafts = not Store.readOnly and Store.db.crafts
    local mine = type(crafts) == "table" and crafts[key]
    return copyCrafts(mine, function() end) or { pairs = {}, recipes = {}, made = {} }
end

-- Returns the character key's crafts table, created when missing; nil when the key is invalid or the db read-only.
local function crafts(key)
    if Store.readOnly or not isText(key) then
        return nil
    end
    Store.db.crafts = Store.db.crafts or {}
    local mine = Store.db.crafts[key] or { pairs = {}, recipes = {}, made = {} }
    Store.db.crafts[key] = mine
    return mine
end

-- Saves that the character key's spellID makes itemID (nil clears it); false when invalid or read-only.
function Store.SetCraftPair(key, spellID, itemID)
    local mine = isInt(spellID, 1) and isOptional(itemID, isInt, 1) and crafts(key)
    if not mine then
        return false
    end
    mine.pairs[spellID] = itemID
    return true
end

-- Saves the character key's cached recipe { name, icon|nil, item|nil, profession|nil } (nil clears it); false when
-- invalid or read-only.
function Store.SetCraftRecipe(key, recipeID, recipe)
    local clean = recipe ~= nil and copyRecipe(recipe) or nil
    local mine = isInt(recipeID, 1) and (recipe == nil or clean) and crafts(key)
    if not mine then
        return false
    end
    mine.recipes[recipeID] = clean or nil
    return true
end

-- Saves when (a time()) the character key last made the craft entry id (nil clears it); false when invalid or
-- read-only.
function Store.SetCraftMade(key, id, when)
    local mine = isCraftId(id) and isOptional(when, isInt, 0) and crafts(key)
    if not mine then
        return false
    end
    mine.made[id] = when
    return true
end

-- Saves the character key's craft pick (an entry id, or nil to clear it); false when invalid or read-only.
function Store.SetCraftPick(key, id)
    local mine = (id == nil or isCraftId(id)) and crafts(key)
    if not mine then
        return false
    end
    mine.pick = id
    return true
end

-- Returns v, or nil when the client marks it secret.
function Store.Safe(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    return v
end

local function safeAll(...)
    if select("#", ...) == 0 then
        return
    end
    return Store.Safe((...)), safeAll(select(2, ...))
end

local function safeCall(ok, ...)
    if ok then
        return safeAll(...)
    end
end

-- Calls fn under pcall and returns all its results, each passed through Safe; nothing when fn is not a function or
-- raises.
function Store.Call(fn, ...)
    if type(fn) ~= "function" then
        return
    end
    return safeCall(pcall(fn, ...))
end

-- Returns the named CVar's value through C_CVar where the client has it, else the global GetCVar.
function Store.GetCVar(name)
    return (Store.Call(type(C_CVar) == "table" and C_CVar.GetCVar or GetCVar, name))
end

-- Sets the named CVar, as GetCVar reads it; a failure is ignored.
function Store.SetCVar(name, value)
    pcall(type(C_CVar) == "table" and C_CVar.SetCVar or SetCVar, name, value)
end

-- Registers event on frame; returns false, registering nothing, when the client rejects the name.
function Store.RegisterEvent(frame, event)
    return (pcall(frame.RegisterEvent, frame, event))
end

-- Registers event on frame for unit only where the client has RegisterUnitEvent, else for every unit; returns false,
-- registering nothing, when the client rejects the name.
function Store.RegisterUnitEvent(frame, event, unit)
    if type(frame.RegisterUnitEvent) == "function" and pcall(frame.RegisterUnitEvent, frame, event, unit) then
        return true
    end
    return Store.RegisterEvent(frame, event)
end
