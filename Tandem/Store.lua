local _, ns = ...

-- Owns TandemDB: validates and migrates it on load and is its only writer. It keeps each character's stat weights
-- and layout mode, the class trainer spells seen and the UI layout state; every other key an older schema saved is
-- dropped on load.
local Store = { readOnly = false }
ns.Store = Store

local SCHEMA = 7
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
local KEPT = { schemaVersion = true, weights = true, trainers = true, layout = true, modes = true }
local MAX_LAYOUT_NAME = 64

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
-- mode the Tandem Edit Mode layout was last built with ("heal"; nil for dps).
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
}

-- A character's saved layout mode: only "heal" is kept; absent means dps.
local function isMode(v)
    return v == "heal"
end

local function copyLayoutField(field, v)
    if field == "previous" then
        return { name = v.name, type = v.type }
    elseif field == "minimap" then
        return { angle = v.angle, hidden = v.hidden }
    end
    return v
end

-- Copies every entry of raw that passes its type check into a fresh current-schema table; every key a current db
-- does not hold counts as one drop.
local function migrate(raw, report)
    local db = newDB()
    local function drop()
        report.dropped = report.dropped + 1
    end
    local function entries(t)
        if type(t) == "table" then
            return t
        end
        if t ~= nil then
            drop()
        end
        return {}
    end

    for name, v in pairs(entries(raw.weights)) do
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

    for name, v in pairs(entries(raw.modes)) do
        if type(name) == "string" and name ~= "" and isMode(v) then
            db.modes = db.modes or {}
            db.modes[name] = v
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
-- minimap = { angle, hidden }|nil, built = "heal"|nil }; empty (off) when the db is newer (kept raw).
function Store.Layout()
    return not Store.readOnly and Store.db.layout or {}
end

-- Sets one layout field (on, previous, tot, coords, minimap or built) to value, or clears it with nil; false when
-- invalid or read-only.
function Store.SetLayout(field, value)
    local valid = LAYOUT_FIELDS[field]
    if Store.readOnly or not valid or (value ~= nil and not valid(value)) then
        return false
    end
    Store.db.layout[field] = value ~= nil and copyLayoutField(field, value) or nil
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
