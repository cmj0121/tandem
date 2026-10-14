local _, ns = ...

-- Owns TandemDB: validates and migrates it on load and is its only writer.
local Store = { unsaved = 0, readOnly = false }
ns.Store = Store

local SCHEMA = 1
local MAX_COORDS = 5
local KINDS = { c = true, o = true, ["?"] = true }
local RUN_FIELDS = {
    "started", "from", "to", "rate", "processed", "skipped", "hits", "misses", "equippable", "deferred",
    "timeouts", "elapsed",
}

local floor = math.floor

local function isNum(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v, min)
    return isNum(v) and v == floor(v) and v >= min
end

local function count(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do
            n = n + 1
        end
    end
    return n
end

local function lootKey(item, kind, id, map)
    return item .. ":" .. kind .. ":" .. id .. ":" .. map
end

local function newDB()
    return {
        schemaVersion = SCHEMA,
        items = {},
        scan = { cursor = 1, nonEquippable = 0, blocks = {} },
        npcs = {},
        loot = {},
    }
end

-- Returns a clean copy of an item record, or nil.
local function copyItem(v)
    if type(v) == "table" and isNum(v[1]) and isNum(v[2]) and isNum(v[3]) and type(v[4]) == "string"
        and v[4] ~= "" and isNum(v[5]) and isNum(v[6]) then
        return { v[1], v[2], v[3], v[4], v[5], v[6] }
    end
end

-- Returns a clean copy of a loot entry, or nil; invalid coords are left out.
local function copyLoot(v)
    if type(v) ~= "table" or not isInt(v.item, 1) or not KINDS[v.kind] or not isInt(v.id, 0)
        or not isInt(v.map, 0) or not isInt(v.count, 1) then
        return nil
    end
    local coords = {}
    if type(v.coords) == "table" then
        for _, c in ipairs(v.coords) do
            if #coords < MAX_COORDS and type(c) == "table" and isInt(c[1], 0) and isInt(c[2], 0) then
                coords[#coords + 1] = { c[1], c[2] }
            end
        end
    end
    return { item = v.item, kind = v.kind, id = v.id, map = v.map, count = v.count, coords = coords }
end

-- Copies every entry of raw that passes its type check into a fresh current-schema table.
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

    for id, v in pairs(entries(raw.items)) do
        local item = isInt(id, 1) and copyItem(v)
        if item then
            db.items[id] = item
        else
            drop()
        end
    end

    local scan, out = entries(raw.scan), db.scan
    if isInt(scan.cursor, 1) then
        out.cursor = scan.cursor
    elseif scan.cursor ~= nil then
        drop()
    end
    if isInt(scan.nonEquippable, 0) then
        out.nonEquippable = scan.nonEquippable
    elseif scan.nonEquippable ~= nil then
        drop()
    end
    for _, key in ipairs({ "minFound", "maxFound" }) do
        if isInt(scan[key], 1) then
            out[key] = scan[key]
        elseif scan[key] ~= nil then
            drop()
        end
    end
    for block, hits in pairs(entries(scan.blocks)) do
        if isInt(block, 0) and isInt(hits, 0) then
            out.blocks[block] = hits
        else
            drop()
        end
    end
    if type(scan.lastRun) == "table" then
        out.lastRun = {}
        for _, key in ipairs(RUN_FIELDS) do
            if isNum(scan.lastRun[key]) then
                out.lastRun[key] = scan.lastRun[key]
            end
        end
    elseif scan.lastRun ~= nil then
        drop()
    end

    for npc, name in pairs(entries(raw.npcs)) do
        if isInt(npc, 1) and type(name) == "string" and name ~= "" then
            db.npcs[npc] = name
        else
            drop()
        end
    end

    -- Entries are re-keyed from their fields so a mangled key cannot hide a valid record.
    for _, v in pairs(entries(raw.loot)) do
        local entry = copyLoot(v)
        if entry then
            db.loot[lootKey(entry.item, entry.kind, entry.id, entry.map)] = entry
        else
            drop()
        end
    end
    return db
end

-- Returns a current-schema db and a report {status, version, dropped}; status is
-- "new", "reset" (not a table), "ok", "migrated" or "newer" (kept as is, writes disabled).
function Store.Load(raw)
    local report = { dropped = 0 }
    Store.unsaved = 0
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

-- Stores an equippable item's core fields; false when already cached, invalid or read-only.
function Store.AddItem(id, ilvl, reqLevel, quality, equipLoc, classID, subclassID)
    if Store.readOnly or not isInt(id, 1) or Store.db.items[id] then
        return false
    end
    local item = copyItem({ ilvl, reqLevel, quality, equipLoc, classID, subclassID })
    if not item then
        return false
    end
    Store.db.items[id] = item
    Store.unsaved = Store.unsaved + 1
    return true
end

-- Counts one drop of item from a source; x, y are 0..1 map fractions or nil.
function Store.AddLoot(item, kind, id, map, x, y)
    map = map or 0
    if Store.readOnly or not isInt(item, 1) or not KINDS[kind] or not isInt(id, 0) or not isInt(map, 0) then
        return false
    end
    local key = lootKey(item, kind, id, map)
    local entry = Store.db.loot[key]
    if not entry then
        entry = { item = item, kind = kind, id = id, map = map, count = 0, coords = {} }
        Store.db.loot[key] = entry
    end
    entry.count = entry.count + 1

    if isNum(x) and isNum(y) and x >= 0 and y >= 0 and #entry.coords < MAX_COORDS then
        local cx, cy = floor(x * 1000), floor(y * 1000)
        local seen = false
        for _, c in ipairs(entry.coords) do
            if c[1] == cx and c[2] == cy then
                seen = true
                break
            end
        end
        if not seen then
            entry.coords[#entry.coords + 1] = { cx, cy }
        end
    end
    Store.unsaved = Store.unsaved + 1
    return true
end

-- Records an npc name; false when unchanged, invalid or read-only.
function Store.SetNpcName(npcID, name)
    if Store.readOnly or not isInt(npcID, 1) or type(name) ~= "string" or name == ""
        or Store.db.npcs[npcID] == name then
        return false
    end
    Store.db.npcs[npcID] = name
    Store.unsaved = Store.unsaved + 1
    return true
end

function Store.Counts()
    local db = Store.db
    local scan = type(db.scan) == "table" and db.scan or {}
    return {
        items = count(db.items),
        nonEquippable = scan.nonEquippable,
        cursor = scan.cursor,
        minFound = scan.minFound,
        maxFound = scan.maxFound,
        loot = count(db.loot),
        npcs = count(db.npcs),
        unsaved = Store.unsaved,
        readOnly = Store.readOnly,
    }
end

-- Returns v, or nil when the client marks it secret.
function Store.Safe(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    return v
end
