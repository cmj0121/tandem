local _, ns = ...

-- Owns TandemDB: validates and migrates it on load and is its only writer.
-- revision goes up with every record change, as unsaved does, and Advisor keys its caches on it.
local Store = { unsaved = 0, revision = 0, readOnly = false, itemCount = 0 }
ns.Store = Store

local SCHEMA = 3
Store.SCHEMA = SCHEMA
local MAX_COORDS = 5
-- c creature, o object, ? unknown: drops counted per loot. q quest (id = questID), v vendor (id = merchant npcID):
-- sources recorded once with the first sighting's map and coords, and a factions bitmask.
local KINDS = { c = true, o = true, ["?"] = true, q = true, v = true }
local SET_ONCE = { q = true, v = true }
-- UnitFactionGroup("player") to the bit a q/v entry's factions carries.
local FACTIONS = { Alliance = 1, Horde = 2 }
Store.FACTIONS = FACTIONS
local ALL_FACTIONS = 3
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

-- Returns a | b for two factions masks (1..3); Lua 5.1 has no bit operators.
local function orFactions(a, b)
    local out = 0
    for _, bit in ipairs({ 1, 2 }) do
        if a % (bit * 2) >= bit or b % (bit * 2) >= bit then
            out = out + bit
        end
    end
    return out
end

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

-- A q/v source is one entry per (item, kind, id) whatever its map.
local function sourceKey(item, kind, id)
    return item .. ":" .. kind .. ":" .. id
end

-- sourceKey -> lootKey of the q/v entries in Store.db; rebuilt on load, kept up by AddSource.
local sources = {}

local function isFactions(v)
    return isInt(v, 1) and v <= ALL_FACTIONS
end

local function newDB()
    return {
        schemaVersion = SCHEMA,
        items = {},
        scan = { cursor = 1, nonEquippable = 0, blocks = {} },
        npcs = {},
        quests = {},
        loot = {},
        kills = {},
        corpses = {},
    }
end

-- Returns a clean copy of an item record, or nil. The optional 7th field is kept only as 1 (deprecated); any
-- other 7th value is stripped, as are fields after it.
local function copyItem(v)
    if type(v) == "table" and isNum(v[1]) and isNum(v[2]) and isNum(v[3]) and type(v[4]) == "string"
        and v[4] ~= "" and isNum(v[5]) and isNum(v[6]) then
        return { v[1], v[2], v[3], v[4], v[5], v[6], v[7] == 1 and 1 or nil }
    end
end

-- Returns a clean copy of a loot entry, or nil; invalid coords are left out. A q/v entry needs an id of 1 or more
-- and valid factions; its count becomes 1 and it keeps one coord. Other kinds carry no factions.
local function copyLoot(v)
    if type(v) ~= "table" or not isInt(v.item, 1) or not KINDS[v.kind] or not isInt(v.id, 0)
        or not isInt(v.map, 0) or not isInt(v.count, 1) then
        return nil
    end
    local once = SET_ONCE[v.kind]
    if once and (v.id < 1 or not isFactions(v.factions)) then
        return nil
    end
    local maxCoords = once and 1 or MAX_COORDS
    local coords = {}
    if type(v.coords) == "table" then
        for _, c in ipairs(v.coords) do
            if #coords < maxCoords and type(c) == "table" and isInt(c[1], 0) and isInt(c[2], 0) then
                coords[#coords + 1] = { c[1], c[2] }
            end
        end
    end
    return { item = v.item, kind = v.kind, id = v.id, map = v.map, count = once and 1 or v.count, coords = coords,
             factions = once and v.factions or nil }
end

-- Fills sources from db.loot.
local function indexSources(db)
    sources = {}
    for key, entry in pairs(db.loot) do
        if SET_ONCE[entry.kind] then
            sources[sourceKey(entry.item, entry.kind, entry.id)] = key
        end
    end
end

local function isAnchor(v)
    return type(v) == "string" and ANCHORS[v] == true
end

local function isSize(v)
    return isNum(v) and v >= 1 and v <= MAX_OFFSET
end

-- Returns a clean copy of a saved window { point, relativePoint, x, y [, width, height] }, or nil, then true when
-- a size was there but invalid (stripped, the position kept). A position saved without relativePoint uses point;
-- a size is both width and height or neither.
local function copyWindow(v)
    if type(v) == "table" and isAnchor(v.point) and (v.relativePoint == nil or isAnchor(v.relativePoint))
        and isNum(v.x) and isNum(v.y) and math.abs(v.x) <= MAX_OFFSET and math.abs(v.y) <= MAX_OFFSET then
        local out = { point = v.point, relativePoint = v.relativePoint or v.point, x = v.x, y = v.y }
        if isSize(v.width) and isSize(v.height) then
            out.width, out.height = v.width, v.height
        end
        return out, out.width == nil and (v.width ~= nil or v.height ~= nil)
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
        local badSize
        out.window, badSize = copyWindow(v.window)
        if not out.window or badSize then
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

    for quest, name in pairs(entries(raw.quests)) do
        if isInt(quest, 1) and type(name) == "string" and name ~= "" then
            db.quests[quest] = name
        else
            drop()
        end
    end

    -- Entries are re-keyed from their fields so a mangled key cannot hide a valid record. A q/v source seen on two
    -- maps keeps the lower map with both factions; the other counts as dropped.
    local seen = {}
    for _, v in pairs(entries(raw.loot)) do
        local entry = copyLoot(v)
        local skey = entry and SET_ONCE[entry.kind] and sourceKey(entry.item, entry.kind, entry.id)
        local other = skey and seen[skey]
        if other then
            local keep, gone = other, entry
            if entry.map < other.map then
                keep, gone = entry, other
            end
            keep.factions = orFactions(keep.factions, gone.factions)
            db.loot[lootKey(gone.item, gone.kind, gone.id, gone.map)] = nil
            db.loot[lootKey(keep.item, keep.kind, keep.id, keep.map)] = keep
            seen[skey] = keep
            drop()
        elseif entry then
            db.loot[lootKey(entry.item, entry.kind, entry.id, entry.map)] = entry
            if skey then
                seen[skey] = entry
            end
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
    Store.revision = 0
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
    sources = {}
    if not Store.readOnly then
        indexSources(db)
    end
    return db, report
end

-- Counts one record change.
local function changed()
    Store.unsaved = Store.unsaved + 1
    Store.revision = Store.revision + 1
end

-- Returns true for an item name the client marks as deprecated: it starts with "deprecated" in any case, after any
-- leading spaces.
function Store.IsDeprecatedName(name)
    return type(name) == "string" and name:lower():match("^%s*deprecated") ~= nil
end

-- Stores an equippable item's core fields, flagged when deprecated is true; false when already cached, invalid or
-- read-only.
function Store.AddItem(id, ilvl, reqLevel, quality, equipLoc, classID, subclassID, deprecated)
    if Store.readOnly or not isInt(id, 1) or Store.db.items[id] then
        return false
    end
    local item = copyItem({ ilvl, reqLevel, quality, equipLoc, classID, subclassID, deprecated == true and 1 or nil })
    if not item then
        return false
    end
    Store.db.items[id] = item
    Store.itemCount = Store.itemCount + 1
    changed()
    return true
end

-- Flags an item as deprecated: its own record, else a flagged copy of record (the shipped one) so the next import
-- ships the flag. True when changed; false when already flagged, invalid or read-only.
function Store.MarkDeprecated(id, record)
    if Store.readOnly or not isInt(id, 1) then
        return false
    end
    local item = Store.db.items[id]
    if item then
        if item[7] == 1 then
            return false
        end
        item[7] = 1
    else
        item = copyItem(record)
        if not item then
            return false
        end
        item[7] = 1
        Store.db.items[id] = item
        Store.itemCount = Store.itemCount + 1
    end
    changed()
    return true
end

-- Counts one drop of item from a source; x, y are 0..1 map fractions or nil. Quest and vendor kinds go through
-- AddSource.
function Store.AddLoot(item, kind, id, map, x, y)
    map = map or 0
    if Store.readOnly or not isInt(item, 1) or not KINDS[kind] or SET_ONCE[kind] or not isInt(id, 0)
        or not isInt(map, 0) then
        return false
    end
    local key = lootKey(item, kind, id, map)
    local entry = Store.db.loot[key]
    if not entry then
        entry = { item = item, kind = kind, id = id, map = map, count = 0, coords = {} }
        Store.db.loot[key] = entry
    end
    entry.count = entry.count + 1
    changed()

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
    return true
end

-- Store.AddSource(item, kind, id, map, x, y, faction) -> changed
-- Records item as a quest reward (kind "q", id = questID) or vendor item (kind "v", id = merchant npcID) seen on map
-- (nil = 0) at x, y (0..1 map fractions or nil), by a player of faction (a Store.FACTIONS bit, 1 or 2). The first
-- sighting makes the entry with count 1 and that map and coord; a later one, on any map, only ORs faction into its
-- factions. True when the entry was made or gained a faction; false when nothing changed, invalid or read-only.
function Store.AddSource(item, kind, id, map, x, y, faction)
    map = map or 0
    if Store.readOnly or not isInt(item, 1) or not SET_ONCE[kind] or not isInt(id, 1) or not isInt(map, 0)
        or not isFactions(faction) then
        return false
    end
    local skey = sourceKey(item, kind, id)
    local entry = sources[skey] and Store.db.loot[sources[skey]]
    if entry then
        local factions = orFactions(entry.factions, faction)
        if factions == entry.factions then
            return false
        end
        entry.factions = factions
        changed()
        return true
    end
    local key = lootKey(item, kind, id, map)
    entry = { item = item, kind = kind, id = id, map = map, count = 1, coords = {}, factions = faction }
    if isNum(x) and isNum(y) and x >= 0 and y >= 0 then
        entry.coords[1] = { floor(x * 1000), floor(y * 1000) }
    end
    Store.db.loot[key] = entry
    sources[skey] = key
    changed()
    return true
end

-- Records a quest name; false when unchanged, invalid or read-only.
function Store.SetQuestName(questID, name)
    if Store.readOnly or not isInt(questID, 1) or type(name) ~= "string" or name == ""
        or Store.db.quests[questID] == name then
        return false
    end
    Store.db.quests[questID] = name
    changed()
    return true
end

-- Records an npc name; false when unchanged, invalid or read-only.
function Store.SetNpcName(npcID, name)
    if Store.readOnly or not isInt(npcID, 1) or type(name) ~= "string" or name == ""
        or Store.db.npcs[npcID] == name then
        return false
    end
    Store.db.npcs[npcID] = name
    changed()
    return true
end

local function addCount(field, npcID)
    if Store.readOnly or not isInt(npcID, 1) then
        return false
    end
    local t = Store.db[field]
    t[npcID] = (t[npcID] or 0) + 1
    changed()
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

-- Returns the saved browse window { point, relativePoint, x, y [, width, height] }, or nil; checked again since a
-- newer db is kept raw.
local function savedWindow()
    local ui = savedUI()
    if ui then
        return (copyWindow(ui.window))
    end
end

-- Saves the browse window position, keeping a saved size; false when invalid or read-only. A position is not a
-- record: unsaved is unchanged.
function Store.SetUIPosition(point, relativePoint, x, y)
    local window = not Store.readOnly and copyWindow({ point = point, relativePoint = relativePoint, x = x, y = y })
    if not window then
        return false
    end
    local old = savedWindow()
    if old then
        window.width, window.height = old.width, old.height
    end
    setUI("window", window)
    return true
end

-- Returns the saved browse window position { point, relativePoint, x, y }, or nil.
function Store.UIPosition()
    local window = savedWindow()
    if window then
        window.width, window.height = nil, nil
    end
    return window
end

-- Saves the browse window size next to its position; false without a saved position, when invalid or read-only.
-- Not a record.
function Store.SetUISize(width, height)
    local window = not Store.readOnly and savedWindow()
    if not window or not isSize(width) or not isSize(height) then
        return false
    end
    window.width, window.height = width, height
    setUI("window", window)
    return true
end

-- Returns the saved browse window width, height, or nil.
function Store.UISize()
    local window = savedWindow()
    if window and window.width then
        return window.width, window.height
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
