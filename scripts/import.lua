-- Imports TandemDB loot (drops, quest rewards, vendor items), npc and quest names, kills, looted corpses and items
-- from saved-variables files into the repo.
-- Usage: lua scripts/import.lua <data-dir> <out-file> [<locale> <contributor-id> <saved-variables-file> ...]
-- Each file overwrites <data-dir>/contributions/<id>.lua; <out-file> (the addon's Data/Loot.lua) is then rebuilt
-- from every contribution. With no saved-variables files, only <out-file> is rebuilt.
-- Saved-variables and contribution files run in an empty environment with an instruction budget.
local scriptDir = arg[0]:gsub("[^/]*$", "")

local MAX_COORDS = 5
local BUDGET = 100000000 -- instructions a data file may run; a WoW SV file needs a small fraction of this
local MAX_COUNT = 2 ^ 53 -- sums stop here so they stay exact and finite
-- Rows per function in the generated file: each function has its own constant table, and LuaJIT allows 65536
-- constants per function (WoW's Lua 5.1 allows 262143).
local CHUNK_ROWS = 2000
local LOOT_FIELDS = { "item", "kind", "id", "map", "count" }
local SET_ONCE = { q = true, v = true } -- quest and vendor kinds: one source per item, kind and id

-- LuaJIT's compiled loops skip count hooks, which would let a data file run forever.
local luajit = rawget(_G, "jit")
if luajit then
    luajit.off()
end

local function fail(msg)
    io.stderr:write("import: " .. msg .. "\n")
end

local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Loads Tandem/Store.lua for its validation; the repo's own file, so it runs unsandboxed.
local function loadStore()
    local ns = {}
    assert(loadfile(scriptDir .. "../Tandem/Store.lua"))("Tandem", ns)
    return ns.Store
end
local Store = loadStore()

-- Runs a data file in an empty environment; returns that environment and the chunk's return value,
-- or nil and an error. Binary chunks are refused; a file that runs too long is stopped.
local function sandbox(path)
    local env = {}
    local chunk, err
    if setfenv then
        local f = io.open(path, "rb")
        if f and f:read(1) == "\27" then
            f:close()
            return nil, path .. ": binary chunks are not accepted"
        end
        if f then
            f:close()
        end
        chunk, err = loadfile(path)
        if chunk then
            setfenv(chunk, env)
        end
    else
        chunk, err = loadfile(path, "t", env)
    end
    if not chunk then
        return nil, err:find(path, 1, true) and err or path .. ": " .. err
    end
    local steps = 0
    debug.sethook(function()
        steps = steps + 1
        if steps * 1000000 >= BUDGET then
            error("ran over its instruction budget", 2)
        end
    end, "", 1000000)
    local ok, result = pcall(chunk)
    debug.sethook()
    if not ok then
        return nil, path .. ": " .. tostring(result)
    end
    return env, result
end

-- Validates a contribution's blocks through Store.Load; returns the clean db and the number of dropped entries.
local function clean(c)
    local db, report = Store.Load({
        schemaVersion = Store.SCHEMA, loot = c.loot, npcs = c.npcs, quests = c.quests, items = c.items,
        kills = c.kills, corpses = c.corpses,
    })
    return db, report.dropped
end

-- Operands are capped first: Lua 5.3+ integers near 2^63 would wrap negative when added.
local function add(a, b)
    return math.min(math.min(a, MAX_COUNT) + math.min(b, MAX_COUNT), MAX_COUNT)
end

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

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- Writer: keys sorted (numbers numerically before strings lexically), one entry per line.
local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta == "number"
        end
        return a < b
    end)
    return keys
end

local function scalar(v)
    if type(v) == "number" then
        if v == math.floor(v) and math.abs(v) <= MAX_COUNT then
            return string.format("%d", v)
        end
        return string.format("%.17g", v)
    end
    return string.format("%q", v)
end

local function list(values)
    local parts = {}
    for i, v in ipairs(values) do
        parts[i] = scalar(v)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function key(k)
    return "[" .. scalar(k) .. "]"
end

local function lootEntry(e)
    local parts = {}
    for _, field in ipairs(LOOT_FIELDS) do
        parts[#parts + 1] = field .. " = " .. scalar(e[field])
    end
    local coords = {}
    for _, c in ipairs(e.coords) do
        coords[#coords + 1] = "{ " .. scalar(c[1]) .. ", " .. scalar(c[2]) .. " }"
    end
    parts[#parts + 1] = "coords = {" .. (#coords > 0 and " " .. table.concat(coords, ", ") .. " " or "") .. "}"
    if e.factions then
        parts[#parts + 1] = "factions = " .. scalar(e.factions)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function block(out, indent, name, t, format)
    out[#out + 1] = indent .. name .. " = {"
    for _, k in ipairs(sortedKeys(t)) do
        out[#out + 1] = indent .. "    " .. key(k) .. " = " .. format(t[k]) .. ","
    end
    out[#out + 1] = indent .. "},"
end

local function writeFile(path, out)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then
        return nil, err
    end
    f:write(table.concat(out, "\n"), "\n")
    f:close()
    local ok, rerr = os.rename(tmp, path)
    if not ok then
        os.remove(tmp)
        return nil, rerr
    end
    return true
end

local function writeContribution(path, locale, db)
    local out = {
        "-- Loot snapshot of one account, generated by `make import`; do not edit.",
        "return {",
        "    locale = " .. scalar(locale) .. ",",
    }
    block(out, "    ", "loot", db.loot, lootEntry)
    block(out, "    ", "npcs", db.npcs, scalar)
    block(out, "    ", "quests", db.quests, scalar)
    block(out, "    ", "items", db.items, list)
    block(out, "    ", "kills", db.kills, scalar)
    block(out, "    ", "corpses", db.corpses, scalar)
    out[#out + 1] = "}"
    return writeFile(path, out)
end

local function contributionFiles(dir)
    local files = {}
    local p = io.popen("ls " .. quote(dir) .. " 2>/dev/null")
    for name in p:lines() do
        if name:match("^[%w_-]+%.lua$") then
            files[#files + 1] = name
        end
    end
    p:close()
    table.sort(files)
    return files
end

local function sortLoot(a, b)
    if a.item ~= b.item then
        return a.item < b.item
    elseif a.kind ~= b.kind then
        return a.kind < b.kind
    elseif a.id ~= b.id then
        return a.id < b.id
    end
    return a.map < b.map
end

local function sumInto(dst, src)
    for npc, n in pairs(src) do
        dst[npc] = add(dst[npc] or 0, n)
    end
end

-- Merges src names into dst[locale], keeping the lexically smallest name per id so the order contributions are
-- read in does not matter.
local function mergeNames(dst, locale, src)
    local t = dst[locale] or {}
    dst[locale] = t
    for id, n in pairs(src) do
        if not t[id] or n < t[id] then
            t[id] = n
        end
    end
end

-- Rebuilds outFile, the addon's ns.Shipped, from every contribution; returns the number of contributors,
-- items and loot rows, or nil when it cannot be written.
local function rebuild(dataDir, outFile)
    local dir = dataDir .. "/contributions"
    local loot, names, questNames, items, kills, corpses, contributors = {}, {}, {}, {}, {}, {}, 0
    for _, name in ipairs(contributionFiles(dir)) do
        local _, c = sandbox(dir .. "/" .. name)
        if type(c) ~= "table" or type(c.locale) ~= "string" or not c.locale:match("^%a%a%a%a$") then
            fail(dir .. "/" .. name .. ": not a contribution, skipped")
        else
            local db, dropped = clean(c)
            if dropped > 0 then
                fail(("%s/%s: %d invalid entries ignored"):format(dir, name, dropped))
            end
            contributors = contributors + 1
            -- A quest or vendor source is one row per item, kind and id across contributions, as in Store: it keeps
            -- the lowest map and that map's coords, with the counts summed and the factions ORed.
            for lootKey, e in pairs(db.loot) do
                local once = SET_ONCE[e.kind]
                local k = once and e.item .. ":" .. e.kind .. ":" .. e.id or lootKey
                local agg = loot[k]
                if not agg then
                    agg = { item = e.item, kind = e.kind, id = e.id, map = e.map, count = 0, coords = {}, seen = {} }
                    loot[k] = agg
                elseif once and e.map < agg.map then
                    agg.map, agg.coords, agg.seen = e.map, {}, {}
                end
                agg.count = add(agg.count, e.count)
                if once then
                    agg.factions = orFactions(agg.factions or 0, e.factions)
                end
                if e.map == agg.map then
                    for _, xy in ipairs(e.coords) do
                        local ck = xy[1] .. "," .. xy[2]
                        if not agg.seen[ck] then
                            agg.seen[ck] = true
                            agg.coords[#agg.coords + 1] = { xy[1], xy[2] }
                        end
                    end
                end
            end
            mergeNames(names, c.locale, db.npcs)
            mergeNames(questNames, c.locale, db.quests)
            -- Files are read sorted, so on a conflict the lexically first contribution's record stays; it is flagged
            -- deprecated when any contribution flags it.
            for id, record in pairs(db.items) do
                if not items[id] then
                    items[id] = record
                elseif record[7] == 1 then
                    items[id][7] = 1
                end
            end
            sumInto(kills, db.kills)
            sumInto(corpses, db.corpses)
        end
    end

    local rows, factions = {}, {}
    for _, agg in pairs(loot) do
        if agg.factions then
            factions[agg.item .. ":" .. agg.kind .. ":" .. agg.id .. ":" .. agg.map] = agg.factions
        end
        table.sort(agg.coords, function(a, b)
            return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
        end)
        local row = { agg.item, agg.kind, agg.id, agg.map, agg.count }
        for i = 1, math.min(#agg.coords, MAX_COORDS) do
            row[#row + 1] = agg.coords[i][1]
            row[#row + 1] = agg.coords[i][2]
        end
        agg.row = row
        rows[#rows + 1] = agg
    end
    table.sort(rows, sortLoot)

    if contributors == 0 then
        fail(dir .. ": no contributions, " .. outFile .. " not written")
        return nil
    end

    local out = {
        "-- Merged from data/contributions/ by `make import`; do not edit.",
        "-- Rows are filled in functions of " .. CHUNK_ROWS .. " so no function exceeds Lua's constant limit.",
        "local _, ns = ...",
        "local S = { contributors = " .. scalar(contributors)
            .. ", items = {}, loot = {}, factions = {}, kills = {}, corpses = {}, names = {}, questNames = {} }",
        "ns.Shipped = S",
    }
    -- Appends `target[key] = value` lines for each { key, value } pair, CHUNK_ROWS per local function.
    local function emit(target, pairsList)
        for first = 1, #pairsList, CHUNK_ROWS do
            out[#out + 1] = "do"
            out[#out + 1] = "    local function fill(t)"
            for i = first, math.min(first + CHUNK_ROWS - 1, #pairsList) do
                out[#out + 1] = "        t" .. key(pairsList[i][1]) .. " = " .. pairsList[i][2]
            end
            out[#out + 1] = "    end"
            out[#out + 1] = "    fill(" .. target .. ")"
            out[#out + 1] = "end"
        end
    end
    local function keyed(t, format)
        local entries = {}
        for _, k in ipairs(sortedKeys(t)) do
            entries[#entries + 1] = { k, format(t[k]) }
        end
        return entries
    end

    emit("S.items", keyed(items, list))
    out[#out + 1] = "-- S.loot rows: { item, kind, id, map, count, x1, y1, ... up to " .. MAX_COORDS
        .. " pairs }, sorted by item, kind, id, map"
    local lootRows = {}
    for i, agg in ipairs(rows) do
        lootRows[i] = { i, list(agg.row) }
    end
    emit("S.loot", lootRows)
    out[#out + 1] = '-- S.factions["item:kind:id:map"]: factions of a quest (q) or vendor (v) row, '
        .. "1 = Alliance, 2 = Horde, 3 = both"
    emit("S.factions", keyed(factions, scalar))
    emit("S.kills", keyed(kills, scalar))
    emit("S.corpses", keyed(corpses, scalar))
    for _, locale in ipairs(sortedKeys(names)) do
        out[#out + 1] = "S.names" .. key(locale) .. " = {}"
        emit("S.names" .. key(locale), keyed(names[locale], scalar))
    end
    for _, locale in ipairs(sortedKeys(questNames)) do
        out[#out + 1] = "S.questNames" .. key(locale) .. " = {}"
        emit("S.questNames" .. key(locale), keyed(questNames[locale], scalar))
    end
    local outDir = outFile:match("^(.*)/[^/]*$")
    if outDir and outDir ~= "" then
        os.execute("mkdir -p " .. quote(outDir))
    end
    local ok, err = writeFile(outFile, out)
    if not ok then
        fail(err)
        return nil
    end
    return contributors, count(items), #rows
end

-- Imports one saved-variables file; returns true when its contribution was written.
local function import(dataDir, locale, id, path)
    if not locale:match("^%a%a%a%a$") then
        fail(path .. ": invalid locale " .. locale .. ", skipped")
        return false
    end
    if not id:match("^[%w_-]+$") then
        fail(path .. ": invalid contributor id " .. id .. ", skipped")
        return false
    end
    local env, err = sandbox(path)
    if not env then
        fail(err .. ", skipped")
        return false
    end
    if type(env.TandemDB) ~= "table" then
        fail(path .. ": no TandemDB table, skipped")
        return false
    end
    local db, report = Store.Load(env.TandemDB)
    if report.status == "newer" then
        fail(("%s: schemaVersion %s is newer than this importer, skipped"):format(path, tostring(report.version)))
        return false
    end
    if report.dropped > 0 then
        fail(("%s: %d invalid entries ignored"):format(path, report.dropped))
    end

    local dest = dataDir .. "/contributions/" .. id .. ".lua"
    local ok, werr = writeContribution(dest, locale, db)
    if not ok then
        fail(werr)
        return false
    end
    local counts = Store.Counts()
    -- Kills and corpses are sums of hostile values, so they print through scalar rather than %d.
    print(("wrote %s (%s: %d loot entries, %d npc names, %d quest names, %d items, %s kills, %s looted corpses)")
        :format(dest, locale, counts.loot, counts.npcs, count(db.quests), counts.items, scalar(counts.kills),
            scalar(counts.corpses)))
    return true
end

local dataDir, outFile = arg[1], arg[2]
if not outFile or (#arg - 2) % 3 ~= 0 then
    fail("usage: lua scripts/import.lua <data-dir> <out-file> [<locale> <contributor-id> <saved-variables-file> ...]")
    os.exit(2)
end
os.execute("mkdir -p " .. quote(dataDir .. "/contributions"))

local imported = 0
for i = 3, #arg, 3 do
    if import(dataDir, arg[i], arg[i + 1], arg[i + 2]) then
        imported = imported + 1
    end
end
if #arg > 2 and imported == 0 then
    fail("no file imported")
    os.exit(1)
end
local contributors, nItems, nRows = rebuild(dataDir, outFile)
if not contributors then
    os.exit(1)
end
print(("wrote %s (%d contributors, %d items, %d loot rows)"):format(outFile, contributors, nItems, nRows))
