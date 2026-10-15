local _, ns = ...

-- Owns TandemDB: validates and migrates it on load and is its only writer.
local Store = { unsaved = 0, readOnly = false, itemCount = 0 }
ns.Store = Store

local SCHEMA = 2
Store.SCHEMA = SCHEMA
local MAX_COORDS = 5
local KINDS = { c = true, o = true, ["?"] = true }
local RUN_FIELDS = {
    "started", "from", "to", "rate", "processed", "skipped", "hits", "misses", "equippable", "deferred",
    "timeouts", "elapsed",
}

local MAX_OFFSET = 10000
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true,
    BOTTOM = true, BOTTOMRIGHT = true,
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
        kills = {},
        corpses = {},
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

local function isAnchor(v)
    return type(v) == "string" and ANCHORS[v] == true
end

-- Returns a clean copy of a saved window position { point, relativePoint, x, y }, or nil. A position saved
-- without relativePoint uses point.
local function copyWindow(v)
    if type(v) == "table" and isAnchor(v.point) and (v.relativePoint == nil or isAnchor(v.relativePoint))
        and isNum(v.x) and isNum(v.y) and math.abs(v.x) <= MAX_OFFSET and math.abs(v.y) <= MAX_OFFSET then
        return { point = v.point, relativePoint = v.relativePoint or v.point, x = v.x, y = v.y }
    end
end

local function isAngle(v)
    return isNum(v) and v >= 0 and v < 360
end

-- Returns a clean copy of the saved ui table { window = position, minimap = angle, minimapHidden = true }, or nil
-- when nothing in it is valid; drop is called once for each invalid key. minimapHidden is kept only as true: absent
-- means the button is shown.
local function copyUI(v, drop)
    if type(v) ~= "table" then
        drop()
        return nil
    end
    local out = {}
    if v.window ~= nil then
        out.window = copyWindow(v.window)
        if not out.window then
            drop()
        end
    end
    if isAngle(v.minimap) then
        out.minimap = v.minimap
    elseif v.minimap ~= nil then
        drop()
    end
    if v.minimapHidden == true then
        out.minimapHidden = true
    elseif v.minimapHidden ~= nil then
        drop()
    end
    return next(out) and out or nil
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

    for _, field in ipairs({ "kills", "corpses" }) do
        for npc, n in pairs(entries(raw[field])) do
            if isInt(npc, 1) and isInt(n, 1) then
                db[field][npc] = n
            else
                drop()
            end
        end
    end

    if raw.ui ~= nil then
        db.ui = copyUI(raw.ui, drop)
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
    Store.itemCount = count(db.items)
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
    Store.itemCount = Store.itemCount + 1
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

local function addCount(field, npcID)
    if Store.readOnly or not isInt(npcID, 1) then
        return false
    end
    local t = Store.db[field]
    t[npcID] = (t[npcID] or 0) + 1
    Store.unsaved = Store.unsaved + 1
    return true
end

-- Counts one kill of an npc by the player; false when invalid or read-only.
function Store.AddKill(npcID)
    return addCount("kills", npcID)
end

-- Counts one looted corpse of an npc; false when invalid or read-only.
function Store.AddCorpse(npcID)
    return addCount("corpses", npcID)
end

local function sum(t)
    local n = 0
    if type(t) == "table" then
        for _, v in pairs(t) do
            if isNum(v) then
                n = n + v
            end
        end
    end
    return n
end

function Store.Counts()
    local db = Store.db
    local scan = type(db.scan) == "table" and db.scan or {}
    return {
        items = Store.itemCount,
        nonEquippable = scan.nonEquippable,
        cursor = scan.cursor,
        minFound = scan.minFound,
        maxFound = scan.maxFound,
        loot = count(db.loot),
        npcs = count(db.npcs),
        kills = sum(db.kills),
        corpses = sum(db.corpses),
        killNpcs = count(db.kills),
        unsaved = Store.unsaved,
        readOnly = Store.readOnly,
    }
end

-- Returns the number of known items without walking them: counted on load, kept up by AddItem.
function Store.ItemCount()
    return Store.itemCount
end

-- Returns the next item ID to scan, or nil when the saved one is not a whole number (a newer db is kept raw).
function Store.ScanCursor()
    local scan = Store.db and Store.db.scan
    local cursor = type(scan) == "table" and scan.cursor
    if isInt(cursor, 1) then
        return cursor
    end
end

-- Returns the saved ui table, or nil when there is none or it is not a table (a newer db is kept raw).
local function savedUI()
    local ui = Store.db and Store.db.ui
    if type(ui) == "table" then
        return ui
    end
end

-- Sets one key of TandemDB.ui, leaving the others alone.
local function setUI(key, value)
    Store.db.ui = Store.db.ui or {}
    Store.db.ui[key] = value
end

-- Saves the browse window position; false when invalid or read-only. A position is not a record: unsaved is
-- unchanged.
function Store.SetUIPosition(point, relativePoint, x, y)
    local window = not Store.readOnly and copyWindow({ point = point, relativePoint = relativePoint, x = x, y = y })
    if not window then
        return false
    end
    setUI("window", window)
    return true
end

-- Returns the saved browse window position { point, relativePoint, x, y }, or nil; checked again since a newer
-- db is kept raw.
function Store.UIPosition()
    local ui = savedUI()
    if ui then
        return copyWindow(ui.window)
    end
end

-- Saves the minimap button's angle in degrees (0 <= angle < 360); false when invalid or read-only. Not a record.
function Store.SetMinimapAngle(angle)
    if Store.readOnly or not isAngle(angle) then
        return false
    end
    setUI("minimap", angle)
    return true
end

-- Saves whether the minimap button is hidden (true) or shown (false: the key is removed); false when not a
-- boolean or read-only. Not a record.
function Store.SetMinimapHidden(hidden)
    if Store.readOnly or type(hidden) ~= "boolean" then
        return false
    end
    setUI("minimapHidden", hidden or nil)
    return true
end

-- Returns true when the minimap button was hidden; checked again since a newer db is kept raw.
function Store.MinimapHidden()
    local ui = savedUI()
    return ui ~= nil and ui.minimapHidden == true
end

-- Returns the saved minimap button angle, or nil; checked again since a newer db is kept raw.
function Store.MinimapAngle()
    local ui = savedUI()
    if ui and isAngle(ui.minimap) then
        return ui.minimap
    end
end

local GUID_KINDS = { Creature = "c", Vehicle = "c", GameObject = "o" }

-- Returns kind ("c" creature/vehicle, "o" game object), id for a GUID ("Type-0-server-instance-zone-id-spawn"),
-- or nil for any other GUID.
function Store.ParseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local fields = {}
    for field in guid:gmatch("[^-]+") do
        fields[#fields + 1] = field
    end
    local kind, id = GUID_KINDS[fields[1]], tonumber(fields[6])
    if kind and id then
        return kind, id
    end
end

-- Returns v, or nil when the client marks it secret.
function Store.Safe(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    return v
end
