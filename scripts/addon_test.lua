-- Loads the addon's .toc files in order under a stubbed WoW API and checks its locale handling.
local addonDir = arg[0]:gsub("[^/]*$", "") .. "../Tandem/"

local function tocFiles()
    local files = {}
    for raw in io.lines(addonDir .. "Tandem.toc") do
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    return files
end

local SHIPPED_FILE = "Data/Loot.lua"

local function exists(path)
    local f = io.open(path)
    if f then
        f:close()
    end
    return f ~= nil
end

-- Loads the addon as a client with the given locale would; returns its namespace,
-- the printed lines, a function that fires ADDON_LOADED, the global environment, a function that fires any event
-- and the event frame. opts.env sets globals before any file runs; opts.blockCLEU makes registering the combat log
-- raise, as a client that forbids it would. opts.shipped, a table, stands in for the generated Data/Loot.lua;
-- otherwise that file is skipped so tests never depend on committed data. opts.toc replaces the toc's file list;
-- its missing files are skipped, as WoW does. A missing file the real toc lists fails the load. opts.widgets, a
-- function(kind, name, parent, template), makes every other CreateFrame call than the event frame's.
local function loadAddon(locale, opts)
    opts = opts or {}
    local printed = {}
    local handler
    local frame = { registered = {}, unregistered = {} }
    function frame.RegisterEvent(self, ev)
        if opts.blockCLEU and ev == "COMBAT_LOG_EVENT_UNFILTERED" then
            error("forbidden")
        end
        self.registered[ev] = true
    end
    function frame.UnregisterEvent(self, ev)
        self.registered[ev] = nil
        self.unregistered[ev] = true
    end
    function frame.SetScript(_, _, fn)
        handler = fn
    end
    local env = setmetatable({
        CreateFrame = function(kind, name, parent, template)
            if opts.widgets and (kind ~= "Frame" or name or parent or template) then
                return opts.widgets(kind, name, parent, template)
            end
            return frame
        end,
        GetLocale = function()
            return locale
        end,
        print = function(msg)
            printed[#printed + 1] = msg
        end,
        SlashCmdList = {},
    }, { __index = _G })
    env._G = env
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end

    local ns = {}
    for _, file in ipairs(opts.toc or tocFiles()) do
        if file == SHIPPED_FILE then
            if type(opts.shipped) == "table" then
                ns.Shipped = opts.shipped
            end
        elseif not opts.toc or exists(addonDir .. file) then
            local chunk = assert(loadfile(addonDir .. file, "t", env))
            if setfenv then
                setfenv(chunk, env)
            end
            chunk("Tandem", ns)
        end
    end

    local function fire(event, ...)
        handler(frame, event, ...)
    end
    local function fireLoaded()
        fire("ADDON_LOADED", "Tandem")
    end
    return ns, printed, fireLoaded, env, fire, frame
end

local failures = 0
local function check(name, got, want)
    if got == want then
        print("ok   " .. name)
    else
        failures = failures + 1
        print(("FAIL %s: got %q, want %q"):format(name, tostring(got), tostring(want)))
    end
end

for _, case in ipairs({
    { locale = "enUS", line = "Tandem loaded" },
    { locale = "zhTW", line = "Tandem 已載入" },
    { locale = "deDE", line = "Tandem loaded" },
}) do
    local _, printed, fireLoaded = loadAddon(case.locale)
    fireLoaded()
    check(case.locale .. " load line", printed[1], case.line)
end

local ns = loadAddon("zhTW")
check("zhTW falls back to English for a missing key", ns.L["Not translated yet"], "Not translated yet")

-- Shipped data: the toc lists the generated file, tests never read it.
do
    local listed = false
    for _, file in ipairs(tocFiles()) do
        listed = listed or file == SHIPPED_FILE
    end
    check("toc lists the shipped data", listed, true)
    check("shipped data is skipped by default", loadAddon("enUS").Shipped, nil)
    local shipped = { contributors = 1 }
    check("opts.shipped stands in for the shipped data", loadAddon("enUS", { shipped = shipped }).Shipped, shipped)
    check("opts.shipped = false skips the shipped data", loadAddon("enUS", { shipped = false }).Shipped, nil)
    local toc = tocFiles()
    table.insert(toc, 1, "Data/Missing.lua")
    local _, printed, fireLoaded = loadAddon("enUS", { toc = toc })
    fireLoaded()
    check("a missing toc file does not break the load", printed[1], "Tandem loaded")
end

-- Store: TandemDB validation and migration.

-- Loads the addon with TandemDB set to db, fires ADDON_LOADED; returns ns, printed lines, env, fire, frame.
local function loadWithDB(db, locale, opts)
    local addon, printed, fireLoaded, env, fire, frame = loadAddon(locale or "enUS", opts)
    env.TandemDB = db
    fireLoaded()
    return addon, printed, env, fire, frame
end

local function isCurrent(db)
    return type(db) == "table" and db.schemaVersion == 3 and type(db.items) == "table"
        and type(db.scan) == "table" and db.scan.cursor == 1 and db.scan.nonEquippable == 0
        and type(db.scan.blocks) == "table" and type(db.npcs) == "table" and type(db.quests) == "table"
        and type(db.loot) == "table"
        and type(db.kills) == "table" and type(db.corpses) == "table"
end

do
    local addon, printed, env = loadWithDB(nil)
    check("nil db becomes a fresh v3 table", isCurrent(env.TandemDB), true)
    check("nil db prints only the load line", #printed, 1)
    check("Store.db is TandemDB", addon.Store.db, env.TandemDB)
end

do
    local _, printed, env = loadWithDB("garbage")
    check("garbage db becomes a fresh v3 table", isCurrent(env.TandemDB), true)
    check("garbage db prints a reset line", printed[2], "Tandem: saved data was unreadable and has been reset")
end

do
    local _, printed = loadWithDB("garbage", "zhTW")
    check("zhTW reset line", printed[2], "Tandem：存檔資料無法讀取，已重設")
end

do
    local _, printed, env = loadWithDB({
        items = { [25] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1, "extra" }, [26] = "bad", [-1] = { 1, 1, 1, "X", 1, 1 } },
        scan = { cursor = 500, nonEquippable = "many", minFound = 25, blocks = { [0] = 3, [1] = -2 },
                 lastRun = { hits = 3, rate = "fast" } },
        npcs = { [100] = "Hogger", [101] = 7 },
        loot = {
            wrongkey = { item = 25, kind = "c", id = 100, map = 1429, count = 2, coords = { { 1, 2 }, "x" } },
            ["9:c:1:1"] = { item = 9, kind = "z", id = 1, map = 1, count = 1 },
        },
        kills = { [448] = 3, [0] = 1, [449] = 1.5 },
        corpses = "bad",
        unknownTop = true,
    })
    local db = env.TandemDB
    check("old db is migrated to v3", db.schemaVersion, 3)
    check("old db keeps a valid item", db.items[25] and db.items[25][4], "INVTYPE_HEAD")
    check("old db strips extra item fields", db.items[25] and #db.items[25], 6)
    check("old db drops an invalid item", db.items[26], nil)
    check("old db keeps the cursor", db.scan.cursor, 500)
    check("old db resets a bad nonEquippable", db.scan.nonEquippable, 0)
    check("old db keeps minFound", db.scan.minFound, 25)
    check("old db keeps a valid block", db.scan.blocks[0], 3)
    check("old db drops a bad block", db.scan.blocks[1], nil)
    check("old db keeps numeric lastRun fields", db.scan.lastRun.hits, 3)
    check("old db drops non-numeric lastRun fields", db.scan.lastRun.rate, nil)
    check("old db keeps a valid npc", db.npcs[100], "Hogger")
    check("old db drops a bad npc", db.npcs[101], nil)
    local entry = db.loot["25:c:100:1429"]
    check("old db re-keys a valid loot entry", entry and entry.count, 2)
    check("old db keeps only valid coords", entry and #entry.coords, 1)
    check("old db drops a bad loot entry", db.loot["9:c:1:1"], nil)
    check("old db drops unknown top-level keys", db.unknownTop, nil)
    check("old db keeps a valid kill count", db.kills[448], 3)
    check("old db drops a bad kill npc", db.kills[0], nil)
    check("old db drops a fractional kill count", db.kills[449], nil)
    check("old db replaces non-table corpses", type(db.corpses) == "table" and next(db.corpses) == nil, true)
    -- items 26 and -1, nonEquippable, block 1, npc 101, loot 9:c:1:1, kills 0 and 449, corpses
    check("old db without a version prints no upgrade line", printed[2], "Tandem: dropped 9 invalid saved entries")
end

do
    local _, printed, env = loadWithDB({ schemaVersion = 1, items = { [7] = { 1, 1, 1, "INVTYPE_FEET", 4, 2 } } })
    check("v1 db keeps its items", env.TandemDB.items[7][4], "INVTYPE_FEET")
    check("v1 db fills missing sections", isCurrent(env.TandemDB), true)
    check("v1 db prints the upgrade line", printed[2], "Tandem: saved data upgraded from schema 1 to 3")
    check("v1 db prints nothing else", #printed, 2)
end

for _, bad in ipairs({ 1.5, 0 / 0, -1, -math.huge }) do
    local _, printed, env = loadWithDB({ schemaVersion = bad })
    check("damaged version " .. tostring(bad) .. " is migrated", env.TandemDB.schemaVersion, 3)
    check("damaged version " .. tostring(bad) .. " prints no upgrade line", #printed, 1)
end

do
    local _, printed = loadWithDB({ schemaVersion = 1 }, "zhTW")
    check("zhTW upgrade line", printed[2], "Tandem：存檔資料已從結構版本 1 升級到 3")
end

do
    local _, printed, env = loadWithDB({ schemaVersion = 3, kills = { [448] = 2 }, corpses = { [448] = 5 } })
    check("v3 db keeps kills", env.TandemDB.kills[448], 2)
    check("v3 db keeps corpses", env.TandemDB.corpses[448], 5)
    check("valid v3 db prints only the load line", #printed, 1)
end

-- Schema 3: a v2 db migrates losslessly (decision 8).
do
    local v2 = {
        schemaVersion = 2,
        items = { [25] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1 }, [26] = { 12, 6, 3, "INVTYPE_FEET", 4, 2, 1 } },
        scan = { cursor = 500, nonEquippable = 7, minFound = 25, maxFound = 26, blocks = { [0] = 3 },
                 lastRun = { hits = 3, rate = 0.25 } },
        npcs = { [100] = "Hogger" },
        loot = {
            ["25:c:100:1429"] = { item = 25, kind = "c", id = 100, map = 1429, count = 4,
                                  coords = { { 1, 2 }, { 3, 4 }, { 5, 6 } } },
            ["26:o:35591:0"] = { item = 26, kind = "o", id = 35591, map = 0, count = 1, coords = {} },
        },
        kills = { [100] = 9 },
        corpses = { [100] = 5 },
        ui = { window = { point = "TOP", relativePoint = "TOP", x = 1, y = 2, width = 600, height = 400 },
               minimap = 45, minimapHidden = true },
    }
    -- Returns a deep copy of t.
    local function deep(t)
        if type(t) ~= "table" then
            return t
        end
        local out = {}
        for k, v in pairs(t) do
            out[k] = deep(v)
        end
        return out
    end
    -- Returns true when a and b hold the same values.
    local function same(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            return a == b
        end
        for k, v in pairs(a) do
            if not same(v, b[k]) then
                return false
            end
        end
        for k in pairs(b) do
            if a[k] == nil then
                return false
            end
        end
        return true
    end
    local want = deep(v2)
    local _, printed, env = loadWithDB(v2)
    local db = env.TandemDB
    check("v2 db migrates to v3", db.schemaVersion, 3)
    check("v2 db gains an empty quests table", type(db.quests) == "table" and next(db.quests) == nil, true)
    db.schemaVersion, db.quests, want.schemaVersion = nil, nil, nil
    check("v2 db keeps every other field", same(db, want), true)
    check("v2 db prints only the upgrade line", printed[2] .. " #" .. #printed,
        "Tandem: saved data upgraded from schema 2 to 3 #2")
end

-- Store: quest and vendor sources (stage 5, unit 1).
do
    local addon, printed, env = loadWithDB({
        schemaVersion = 3,
        quests = { [176] = "Wanted: Hogger", [0] = "zero", [177] = "", [178] = 5 },
        loot = {
            a = { item = 1, kind = "q", id = 176, map = 1429, count = 3, coords = { { 1, 2 }, { 3, 4 } },
                  factions = 3 },
            b = { item = 2, kind = "v", id = 54, map = 1429, count = 1, factions = 0 },
            c = { item = 3, kind = "v", id = 54, map = 1429, count = 1 },
            d = { item = 4, kind = "q", id = 0, map = 1429, count = 1, factions = 1 },
            e = { item = 5, kind = "v", id = 54, map = 1429, count = 1, factions = 4 },
            f = { item = 6, kind = "v", id = 54, map = 1429, count = 1, factions = 1.5 },
            g = { item = 7, kind = "c", id = 100, map = 1429, count = 2, factions = 1 },
            h = { item = 8, kind = "v", id = 66, map = 1436, count = 1, factions = 2 },
            i = { item = 8, kind = "v", id = 66, map = 1429, count = 1, factions = 1 },
        },
    })
    local db, Store = env.TandemDB, addon.Store
    local q = db.loot["1:q:176:1429"]
    check("sources: a saved quest entry is kept", q and q.factions, 3)
    check("sources: a saved q/v count becomes 1", q and q.count, 1)
    check("sources: a saved q/v entry keeps one coord", q and #q.coords .. " " .. q.coords[1][1], "1 1")
    check("sources: zero factions is dropped", db.loot["2:v:54:1429"], nil)
    check("sources: missing factions is dropped", db.loot["3:v:54:1429"], nil)
    check("sources: quest id 0 is dropped", db.loot["4:q:0:1429"], nil)
    check("sources: factions above 3 is dropped", db.loot["5:v:54:1429"], nil)
    check("sources: fractional factions is dropped", db.loot["6:v:54:1429"], nil)
    check("sources: a drop entry carries no factions", db.loot["7:c:100:1429"].factions, nil)
    local kept = db.loot["8:v:66:1429"]
    check("sources: a vendor item on two maps keeps the lower map", kept and kept.factions, 3)
    check("sources: the higher map row is gone", db.loot["8:v:66:1436"], nil)
    check("sources: a saved quest name is kept", db.quests[176], "Wanted: Hogger")
    check("sources: bad quest names are dropped", db.quests[0] or db.quests[177] or db.quests[178], nil)
    -- loot b, c, d, e, f and the duplicate i/h; quests 0, 177, 178
    check("sources: invalid entries are counted", printed[2], "Tandem: dropped 9 invalid saved entries")

    check("AddSource records a quest reward", Store.AddSource(10, "q", 176, 1429, 0.4123, 0.6, 1), true)
    local entry = db.loot["10:q:176:1429"]
    check("AddSource stores count 1", entry.count, 1)
    check("AddSource stores the first coord", entry.coords[1][1] .. "," .. entry.coords[1][2], "412,600")
    check("AddSource stores the faction", entry.factions, 1)
    check("AddSource skips a repeat", Store.AddSource(10, "q", 176, 1429, 0.5, 0.5, 1), false)
    check("AddSource repeat keeps count and coords", entry.count .. " " .. #entry.coords, "1 1")
    check("AddSource skips a repeat on another map", Store.AddSource(10, "q", 176, 1436, 0.5, 0.5, 1), false)
    check("AddSource makes no row for another map", db.loot["10:q:176:1436"], nil)
    check("AddSource ORs another faction", Store.AddSource(10, "q", 176, 1436, nil, nil, Store.FACTIONS.Horde), true)
    check("AddSource factions become both", entry.factions, 3)
    check("AddSource skips a faction already there", Store.AddSource(10, "q", 176, 1429, nil, nil, 2), false)
    check("AddSource records a vendor item without a map", Store.AddSource(11, "v", 54, nil, nil, nil, 2), true)
    check("AddSource vendor without position", #db.loot["11:v:54:0"].coords, 0)
    check("AddSource the same item from another vendor is its own row", Store.AddSource(11, "v", 55, 0, nil, nil, 2),
        true)
    check("AddSource finds a migrated entry", Store.AddSource(8, "v", 66, 1436, nil, nil, 1), false)
    local before = Store.unsaved
    for name, args in pairs({
        ["a drop kind"] = { 12, "c", 1, 1, nil, nil, 1 }, ["id 0"] = { 12, "q", 0, 1, nil, nil, 1 },
        ["no faction"] = { 12, "q", 1, 1 },
        ["faction 4"] = { 12, "q", 1, 1, nil, nil, 4 }, ["faction string"] = { 12, "q", 1, 1, nil, nil, "Horde" },
        ["item 0"] = { 0, "q", 1, 1, nil, nil, 1 }, ["map -1"] = { 12, "q", 1, -1, nil, nil, 1 },
    }) do
        check("AddSource rejects " .. name,
            Store.AddSource(args[1], args[2], args[3], args[4], args[5], args[6], args[7]), false)
    end
    check("AddSource rejections are not records", Store.unsaved, before)
    check("AddLoot rejects a quest kind", Store.AddLoot(13, "q", 1, 1), false)
    check("AddLoot rejects a vendor kind", Store.AddLoot(13, "v", 1, 1), false)

    check("SetQuestName stores a name", Store.SetQuestName(200, "The Fargodeep Mine"), true)
    check("SetQuestName writes TandemDB", db.quests[200], "The Fargodeep Mine")
    check("SetQuestName skips an unchanged name", Store.SetQuestName(200, "The Fargodeep Mine"), false)
    check("SetQuestName rejects an empty name", Store.SetQuestName(201, ""), false)
    check("SetQuestName rejects quest 0", Store.SetQuestName(0, "x"), false)
end

do
    local newer = { schemaVersion = 4, items = "new format" }
    local addon, printed, env = loadWithDB(newer)
    check("newer db is left untouched", env.TandemDB, newer)
    check("newer db keeps its fields", env.TandemDB.items, "new format")
    check("newer db prints a warning", printed[2],
        "Tandem: saved data uses newer schema 4; recording is off until the addon is updated")
    check("newer db blocks AddItem", addon.Store.AddItem(1, 1, 1, 1, "INVTYPE_HEAD", 4, 1), false)
    check("newer db blocks AddLoot", addon.Store.AddLoot(1, "c", 1, 1), false)
    check("newer db blocks SetNpcName", addon.Store.SetNpcName(1, "x"), false)
    check("newer db blocks AddSource", addon.Store.AddSource(1, "q", 1, 1, nil, nil, 1), false)
    check("newer db blocks SetQuestName", addon.Store.SetQuestName(1, "x"), false)
    check("newer db blocks AddKill", addon.Store.AddKill(1), false)
    check("newer db blocks AddCorpse", addon.Store.AddCorpse(1), false)
    check("newer db Counts kills does not fail", addon.Store.Counts().kills, 0)
    check("newer db Counts does not fail", addon.Store.Counts().items, 0)
    check("newer db is read-only", addon.Store.Counts().readOnly, true)
end

do
    local addon, _, env = loadWithDB(nil)
    local Store = addon.Store
    check("AddItem stores a new item", Store.AddItem(42, 20, 15, 3, "INVTYPE_CHEST", 4, 2), true)
    check("AddItem writes TandemDB", env.TandemDB.items[42][1], 20)
    check("AddItem skips a cached item", Store.AddItem(42, 21, 15, 3, "INVTYPE_CHEST", 4, 2), false)
    check("AddItem rejects a nil field", Store.AddItem(43, nil, 15, 3, "INVTYPE_CHEST", 4, 2), false)
    check("AddItem rejects an empty slot", Store.AddItem(44, 20, 15, 3, "", 4, 2), false)

    check("AddLoot records a drop", Store.AddLoot(42, "c", 100, 1429, 0.4123, 0.6), true)
    Store.AddLoot(42, "c", 100, 1429, 0.4129, 0.6009)
    Store.AddLoot(42, "c", 100, 1429, 0.5, 0.5)
    local entry = env.TandemDB.loot["42:c:100:1429"]
    check("AddLoot counts repeat drops", entry.count, 3)
    check("AddLoot rounds coords to 0.1%", entry.coords[1][1], 412)
    check("AddLoot keeps distinct coords only", #entry.coords, 2)
    for i = 1, 10 do
        Store.AddLoot(42, "c", 100, 1429, i / 20, i / 20)
    end
    check("AddLoot caps coords at 5", #entry.coords, 5)
    check("AddLoot without map or position uses map 0", Store.AddLoot(42, "?", 0), true)
    check("AddLoot unknown map has no coords", #env.TandemDB.loot["42:?:0:0"].coords, 0)
    check("AddLoot rejects an unknown kind", Store.AddLoot(42, "p", 1, 1), false)

    check("SetNpcName stores a name", Store.SetNpcName(100, "Hogger"), true)
    check("SetNpcName skips an unchanged name", Store.SetNpcName(100, "Hogger"), false)

    check("AddKill counts a kill", Store.AddKill(448), true)
    Store.AddKill(448)
    Store.AddKill(299)
    check("AddKill writes TandemDB", env.TandemDB.kills[448], 2)
    check("AddCorpse counts a corpse", Store.AddCorpse(448), true)
    check("AddCorpse writes TandemDB", env.TandemDB.corpses[448], 1)
    for _, bad in ipairs({ 0, -1, 1.5, "448", 0 / 0, math.huge }) do
        check("AddKill rejects " .. tostring(bad), Store.AddKill(bad), false)
        check("AddCorpse rejects " .. tostring(bad), Store.AddCorpse(bad), false)
    end

    local counts = Store.Counts()
    check("Counts items", counts.items, 1)
    check("Counts loot entries", counts.loot, 2)
    check("Counts npcs", counts.npcs, 1)
    check("Counts cursor", counts.cursor, 1)
    check("Counts nonEquippable", counts.nonEquippable, 0)
    check("Counts kills", counts.kills, 3)
    check("Counts corpses", counts.corpses, 1)
    check("Counts kill npcs", counts.killNpcs, 2)
    check("Counts unsaved records", counts.unsaved, 1 + 13 + 1 + 1 + 3 + 1)
    check("Counts not read-only", counts.readOnly, false)
end

do
    local addon, _, env = loadWithDB(nil)
    check("Safe passes values without issecretvalue", addon.Store.Safe(5), 5)
    env.issecretvalue = function(v)
        return v == "secret"
    end
    check("Safe hides a secret value", addon.Store.Safe("secret"), nil)
    check("Safe passes a plain value", addon.Store.Safe("plain"), "plain")
end

-- Commands: /tandem parsing and output.

-- Returns the lines printed after the first from.
local function linesSince(printed, from)
    local out = {}
    for i = from + 1, #printed do
        out[#out + 1] = printed[i]
    end
    return out
end

-- Returns a fake C_Timer.NewTicker that appends each ticker { interval, fn, cancelled } to list.
local function fakeTicker(list)
    return function(interval, fn)
        local t = { interval = interval, fn = fn }
        function t.Cancel(self)
            self.cancelled = true
        end
        list[#list + 1] = t
        return t
    end
end

-- Runs msg through /tandem; returns the lines it printed.
local function run(addon, printed, msg)
    local from = #printed
    addon.Commands.Run(msg)
    return linesSince(printed, from)
end

-- Replaces ns.Scanner with a stub that records its calls.
local function stubScanner(addon)
    local calls = {}
    addon.Scanner = {
        Start = function(opts)
            calls[#calls + 1] = ("start %g %d"):format(opts.rate, opts.cap)
        end,
        SetCursor = function(id)
            calls[#calls + 1] = "cursor " .. id
        end,
        Stop = function()
            calls[#calls + 1] = "stop"
        end,
    }
    return calls
end

do
    local addon, printed, env = loadWithDB(nil)
    local ParseRate = addon.Commands.ParseRate
    check("ParseRate 10/s", ParseRate("10/s"), 10)
    check("ParseRate 15/m", ParseRate("15/m"), 0.25)
    check("ParseRate 1/m lower bound", ParseRate("1/m"), 1 / 60)
    check("ParseRate 50/s upper bound", ParseRate("50/s"), 50)
    check("ParseRate 3000/m upper bound", ParseRate("3000/m"), 50)
    check("ParseRate 0/s", ParseRate("0/s"), nil)
    check("ParseRate 51/s", ParseRate("51/s"), nil)
    check("ParseRate 3001/m", ParseRate("3001/m"), nil)
    check("ParseRate garbage", ParseRate("fast"), nil)
    check("ParseRate no unit", ParseRate("10"), nil)
    check("ParseRate fraction", ParseRate("1.5/s"), nil)
    check("ParseRate nil", ParseRate(nil), nil)
    local ScanOptions = addon.Commands.ScanOptions
    local opts = ScanOptions(" 20/M ", "\t7 ")
    check("ScanOptions trims and lowercases", opts.rate .. " " .. opts.cap, (20 / 60) .. " 7")
    opts = ScanOptions("  ", nil)
    check("ScanOptions blank takes the defaults", opts.rate .. " " .. opts.cap,
        addon.Commands.DEFAULT_RATE .. " " .. addon.Commands.DEFAULT_CAP)
    check("ScanOptions defaults", addon.Commands.DEFAULT_RATE .. " " .. addon.Commands.DEFAULT_CAP, "10 100")
    check("ScanOptions inner spaces are invalid", ScanOptions("10 /s", ""), nil)

    check("SLASH_TANDEM1 is /tandem", env.SLASH_TANDEM1, "/tandem")
    check("SlashCmdList.TANDEM is Run", env.SlashCmdList.TANDEM, addon.Commands.Run)

    local help = run(addon, printed, "")
    check("empty input prints usage", help[1], "Tandem commands:")
    check("usage lists scan", help[3], "  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)")
    check("help prints usage", run(addon, printed, "help")[1], "Tandem commands:")
    check("unknown subcommand prints usage", run(addon, printed, "dance")[1], "Tandem commands:")
    check("usage lists gear", help[6], "  /tandem gear [<slot>] [all] - best known gear you can use")
    check("usage lists rank", help[7], "  /tandem rank <item link|id> - rank an item in its slot")
    check("usage lists export", help[8], "  /tandem export - show what make import would collect")
    check("usage lists browse", help[9], "  /tandem browse [<slot>] - browse known gear in a window")
    check("usage lists minimap", help[10], "  /tandem minimap [on|off] - show or hide the minimap button")
    check("usage lists check", help[11], "  /tandem check - list the client APIs each feature needs")
    check("usage lists map", help[12], "  /tandem map <item link|id> - pin where an item comes from on the world map")
    check("usage lists map clear", help[13], "  /tandem map clear - remove the map pins")
    check("usage line count", #help, 13)

    addon.Scanner = nil
    check("scan without a scanner", run(addon, printed, "scan")[1], "Tandem: scanner not available")
    check("scan from without a scanner", run(addon, printed, "scan from 5")[1], "Tandem: scanner not available")
    check("bad scan without a scanner prints usage", run(addon, printed, "scan 0/s")[1], "Tandem commands:")

    local calls = stubScanner(addon)
    for _, case in ipairs({
        { "scan", "start 10 100" },
        { "SCAN", "start 10 100" },
        { "scan 5/s", "start 5 100" },
        { "scan 500", "start 10 500" },
        { "scan 60/m 20", "start 1 20" },
        { "scan 20 60/m", "start 1 20" },
        { "  scan   2/s   7  ", "start 2 7" },
        { "scan 100000", "start 10 100000" },
        { "scan from 2500", "cursor 2500" },
        { "scan stop", "stop" },
    }) do
        local from = #calls
        local out = run(addon, printed, case[1])
        check(("%q dispatches %s"):format(case[1], case[2]), calls[from + 1], case[2])
        check(("%q prints nothing itself"):format(case[1]), #out, 0)
    end
    for _, msg in ipairs({
        "scan 0/s", "scan 51/s", "scan fast", "scan 0", "scan 100001", "scan 1.5", "scan 5/s 6/s", "scan 10 20",
        "scan from", "scan from x", "scan from 0", "scan from 5 6", "scan stop now",
    }) do
        local from = #calls
        local out = run(addon, printed, msg)
        check(("%q prints usage"):format(msg), out[1], "Tandem commands:")
        check(("%q does not dispatch"):format(msg), #calls, from)
    end
end

do
    local addon, printed = loadWithDB(nil)
    local out = run(addon, printed, "count")
    check("count empty: items", out[1], "Tandem: 0 known items, 0 non-equippable")
    check("count empty: scan", out[2], "Scan cursor: 1, found IDs: none")
    check("count empty: loot", out[3], "Loot entries: 0, npc names: 0")
    check("count empty: kills", out[4], "Kills: 0, looted corpses: 0")
    check("count empty: rate basis", out[5], "Drop rates use looted corpses: kill counting is unavailable")
    check("count empty: unsaved", out[6], "Unsaved records: 0 (saved on /reload or logout)")
    check("count empty: last run", out[7], "Last run: never")
    check("count empty line count", #out, 7)
end

do
    local addon, printed = loadWithDB({
        schemaVersion = 1,
        items = { [25] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1 }, [30] = { 12, 6, 2, "INVTYPE_FEET", 4, 1 } },
        scan = { cursor = 1201, nonEquippable = 40, minFound = 25, maxFound = 1180, blocks = {},
                 lastRun = { from = 1, to = 1200, rate = 10, processed = 1200, skipped = 3, hits = 42, misses = 1158,
                             equippable = 2, deferred = 5, timeouts = 1, elapsed = 125.27 } },
        npcs = { [100] = "Hogger" },
        loot = { ["25:c:100:1429"] = { item = 25, kind = "c", id = 100, map = 1429, count = 2, coords = {} } },
    })
    addon.Store.SetNpcName(101, "Defias")
    local out = run(addon, printed, "count")
    check("count: items", out[1], "Tandem: 2 known items, 40 non-equippable")
    check("count: scan", out[2], "Scan cursor: 1201, found IDs: 25-1180")
    check("count: loot", out[3], "Loot entries: 1, npc names: 2")
    check("count: unsaved", out[6], "Unsaved records: 1 (saved on /reload or logout)")
    check("count: last run", out[7], "Last run: IDs 1-1200 at 10/s in 125.3s, 1200 processed, 3 skipped")
    check("count: last run results",
        out[8], "  42 hits (2 equippable), 1158 misses, 5 deferred, 1 timeouts")
end

do
    local addon, printed = loadWithDB({ schemaVersion = 1, scan = { lastRun = { rate = 0.25, hits = 3 } } })
    local out = run(addon, printed, "count")
    check("count: partial last run", out[7], "Last run: IDs ?-? at 15/m in ?s, ? processed, ? skipped")
end

do
    local addon, printed = loadWithDB({ schemaVersion = 4, items = "new format" })
    local out = run(addon, printed, "count")
    check("count on a newer db does not fail", out[1], "Tandem: 0 known items, ? non-equippable")
    check("count on a newer db says read-only", out[#out],
        "Recording is off: saved data uses a newer schema")
end

do
    local addon, printed = loadWithDB(nil, "zhTW")
    addon.Scanner = nil
    check("zhTW count line", run(addon, printed, "count")[7], "上次掃描：從未執行")
    check("zhTW scanner missing line", run(addon, printed, "scan")[1], "Tandem：掃描器無法使用")
end

-- Scanner: throttled item scan with stubbed timers and item API.

-- Loads the addon with a stubbed C_Item over items ({[id] = {equipLoc, loaded = bool}}) and a manual ticker.
local function loadScanner(items, db, locale)
    local addon, printed, env, fire = loadWithDB(db or { schemaVersion = 1, scan = { cursor = 1 } }, locale)
    local ctx = { addon = addon, printed = printed, env = env, fire = fire, Scanner = addon.Scanner, clock = 100,
                  combat = false, tickers = {}, requested = {} }
    env.GetTime = function()
        return ctx.clock
    end
    env.time = function()
        return 1700000000
    end
    env.InCombatLockdown = function()
        return ctx.combat
    end
    env.C_Timer = { NewTicker = fakeTicker(ctx.tickers) }
    env.C_Item = {
        DoesItemExistByID = function(id)
            return items[id] ~= nil
        end,
        GetItemInfoInstant = function(id)
            local it = items[id]
            if it then
                return id, "Armor", "Cloth", it[1], 134400, 4, 1
            end
        end,
        GetItemInfo = function(id)
            local it = items[id]
            if it and it.loaded ~= false then
                return "Item " .. id, "link", 2, 20, 15, "Armor", "Cloth", 1, it[1], 134400, 5, 4, 1
            end
        end,
        RequestLoadItemDataByID = function(id)
            ctx.requested[#ctx.requested + 1] = id
        end,
    }
    -- Fires the live ticker n times, advancing the clock by its interval each time.
    function ctx.tick(n)
        for _ = 1, n or 1 do
            local t = ctx.tickers[#ctx.tickers]
            if not t or t.cancelled then
                return
            end
            ctx.clock = ctx.clock + t.interval
            t.fn(t)
        end
    end
    function ctx.scan()
        return env.TandemDB.scan
    end
    function ctx.run()
        return env.TandemDB.scan.lastRun
    end
    function ctx.since(from)
        return linesSince(printed, from)
    end
    return ctx
end

local equip = { "INVTYPE_HEAD" }

do
    -- 1: equippable, 2: missing, 3: non-equippable, 4: cached already, 1001: equippable in block 1
    local ctx = loadScanner({ [1] = equip, [3] = { "" }, [4] = equip, [5] = { "INVTYPE_NON_EQUIP_IGNORE" } },
        { schemaVersion = 1, items = { [4] = { 1, 1, 1, "INVTYPE_FEET", 4, 1 } }, scan = { cursor = 1 } })
    local S = ctx.Scanner
    local mark = #ctx.printed
    S.Start({ rate = 10, cap = 5 })
    check("scan start line", ctx.since(mark)[1], "Tandem: scanning 5 IDs from ID 1")
    check("scan is running", S.IsRunning(), true)
    check("ticker interval is 1/rate", ctx.tickers[1].interval, 0.1)
    check("lastRun.started uses time()", ctx.run().started, 1700000000)
    check("lastRun.from is the cursor", ctx.run().from, 1)
    check("lastRun.rate", ctx.run().rate, 10)

    mark = #ctx.printed
    S.Start({ rate = 10, cap = 5 })
    check("second start says already running", ctx.since(mark)[1], "Tandem: scan already running")
    check("second start makes no new ticker", #ctx.tickers, 1)

    ctx.tick(1)
    check("equippable item is stored", ctx.env.TandemDB.items[1] and ctx.env.TandemDB.items[1][4], "INVTYPE_HEAD")
    check("stored item fields", ctx.env.TandemDB.items[1][1], 20)
    check("cursor persists as it advances", ctx.scan().cursor, 2)
    ctx.tick(1)
    check("missing item is a miss", ctx.run().misses, 1)
    ctx.tick(1)
    check("empty equipLoc counts non-equippable", ctx.scan().nonEquippable, 1)
    check("non-equippable is not stored", ctx.env.TandemDB.items[3], nil)
    ctx.tick(1)
    check("cached item is skipped", ctx.run().skipped, 1)
    mark = #ctx.printed
    ctx.tick(1)
    check("NON_EQUIP_IGNORE counts non-equippable", ctx.scan().nonEquippable, 2)
    check("scan stops at cap", S.IsRunning(), false)
    check("ticker is cancelled at cap", ctx.tickers[1].cancelled, true)
    local out = ctx.since(mark)
    check("cap stop summary", out[1], "Tandem: scan stopped, IDs 1-5 in 0.5s, 5 processed, 1 skipped")
    check("cap stop results", out[2], "  3 hits (1 equippable), 1 misses, 0 deferred, 0 timeouts")
    local last = ctx.run()
    check("lastRun.to", last.to, 5)
    check("lastRun.processed", last.processed, 5)
    check("lastRun.equippable", last.equippable, 1)
    check("lastRun.elapsed via GetTime", math.abs(last.elapsed - 0.5) < 1e-9, true)
    check("minFound", ctx.scan().minFound, 1)
    check("maxFound", ctx.scan().maxFound, 5)
    check("hits per block", ctx.scan().blocks[0], 3)
    check("Store.unsaved counts stored items", ctx.addon.Store.unsaved, 1)

    mark = #ctx.printed
    S.Stop()
    check("stop when idle", ctx.since(mark)[1], "Tandem: no scan running")
end

do
    local ctx = loadScanner({ [1000] = equip, [2500] = { "" } },
        { schemaVersion = 1, scan = { cursor = 1000, minFound = 1500, maxFound = 1600, blocks = { [1] = 4 } } })
    ctx.Scanner.Start({ rate = 50, cap = 1 })
    ctx.tick(1)
    check("minFound lowers", ctx.scan().minFound, 1000)
    check("maxFound kept", ctx.scan().maxFound, 1600)
    check("block hit adds to saved count", ctx.scan().blocks[1], 5)
    ctx.Scanner.SetCursor(2500)
    ctx.Scanner.Start({ rate = 50, cap = 1 })
    ctx.tick(1)
    check("maxFound raises", ctx.scan().maxFound, 2500)
    check("new block", ctx.scan().blocks[2], 1)
end

do
    -- rate below 1/s, combat pause and resume
    local ctx = loadScanner({})
    local S = ctx.Scanner
    S.Start({ rate = 0.25, cap = 3 })
    check("15/m ticks every 4 s", ctx.tickers[1].interval, 4)
    ctx.combat = true
    local mark = #ctx.printed
    ctx.tick(3)
    local out = ctx.since(mark)
    check("combat prints paused once", #out, 1)
    check("combat paused line", out[1], "Tandem: scan paused in combat")
    check("combat processes nothing", ctx.run().processed, 0)
    check("combat keeps running", S.IsRunning(), true)
    ctx.combat = false
    ctx.tick(1)
    check("scan resumes after combat", ctx.run().processed, 1)
    ctx.combat = true
    mark = #ctx.printed
    ctx.tick(1)
    check("a new combat prints paused again", ctx.since(mark)[1], "Tandem: scan paused in combat")
    ctx.combat = false
    ctx.tick(2)
    check("misses after combat", ctx.run().misses, 3)
    check("stops at cap after combat", S.IsRunning(), false)
end

do
    -- deferred: backlog limit, timeout, resolution by success and failure
    local items = {}
    for id = 1, 12 do
        items[id] = { "INVTYPE_CHEST", loaded = false }
    end
    local ctx = loadScanner(items)
    local S = ctx.Scanner
    S.Start({ rate = 10, cap = 12 })
    ctx.tick(10)
    check("ten items deferred", ctx.run().deferred, 10)
    check("deferred items are requested", #ctx.requested, 10)
    check("deferred item requested by id", ctx.requested[1], 1)
    ctx.tick(3)
    check("backlog of 10 skips the tick", ctx.run().processed, 10)
    check("backlog does not move the cursor", ctx.scan().cursor, 11)

    items[1].loaded = true
    S.OnItemInfo(1, true)
    check("resolved item is stored", ctx.env.TandemDB.items[1] and ctx.env.TandemDB.items[1][4], "INVTYPE_CHEST")
    check("resolved item is a hit", ctx.run().hits, 1)
    check("resolved item is equippable", ctx.run().equippable, 1)
    S.OnItemInfo(2, false)
    check("failed item is a miss", ctx.run().misses, 1)
    check("failed item is not stored", ctx.env.TandemDB.items[2], nil)
    S.OnItemInfo(2, true)
    check("a resolved id is not counted twice", ctx.run().misses, 1)
    S.OnItemInfo(999, true)
    check("unknown ids are ignored", ctx.run().hits + ctx.run().misses, 2)

    ctx.tick(1)
    check("freed slots let the scan go on", ctx.run().processed, 11)
    -- ids 3-10 were deferred over 5 s ago, id 11 4.9 s ago
    ctx.clock = ctx.clock + 4.8
    ctx.tick(1)
    check("pending older than 5 s times out", ctx.run().timeouts, 8)
    check("timeouts free the backlog", ctx.run().processed, 12)
    check("waits for the last pending", S.IsRunning(), true)
    ctx.clock = ctx.clock + 6
    ctx.tick(1)
    check("all deferred time out", ctx.run().timeouts, 10)
    check("stops at cap once nothing is pending", S.IsRunning(), false)
end

do
    -- the last deferred reply stops the scan without waiting for a tick
    local items = { [1] = { "INVTYPE_HEAD", loaded = false } }
    local ctx = loadScanner(items)
    ctx.Scanner.Start({ rate = 10, cap = 1 })
    ctx.tick(1)
    check("cap reached with pending keeps running", ctx.Scanner.IsRunning(), true)
    items[1].loaded = true
    ctx.fire("GET_ITEM_INFO_RECEIVED", 1, true)
    check("GET_ITEM_INFO_RECEIVED reaches the scanner", ctx.run().hits, 1)
    check("last reply stops the scan", ctx.Scanner.IsRunning(), false)
    check("last reply is stored", ctx.env.TandemDB.items[1] ~= nil, true)
end

do
    -- resume: a reload keeps the cursor
    local ctx = loadScanner({})
    ctx.Scanner.Start({ rate = 10, cap = 4 })
    ctx.tick(2)
    local saved = ctx.env.TandemDB
    local again = loadScanner({}, saved)
    check("reload keeps the cursor", again.scan().cursor, 3)
    again.Scanner.Start({ rate = 10, cap = 1 })
    check("resumed run starts at the cursor", again.run().from, 3)
    again.tick(1)
    check("resumed run scans the next id", again.run().to, 3)
end

do
    local ctx = loadScanner({})
    local mark = #ctx.printed
    ctx.Scanner.SetCursor(5000)
    check("SetCursor line", ctx.since(mark)[1], "Tandem: next scan starts at ID 5000")
    check("SetCursor writes the cursor", ctx.scan().cursor, 5000)
    check("SetCursor does not start", ctx.Scanner.IsRunning(), false)
    ctx.Scanner.Start({ rate = 1, cap = 5 })
    mark = #ctx.printed
    ctx.Scanner.SetCursor(7)
    check("SetCursor while running is refused", ctx.since(mark)[1], "Tandem: stop the scan before moving the cursor")
    check("SetCursor while running keeps the cursor", ctx.scan().cursor, 5000)
    mark = #ctx.printed
    ctx.Scanner.Stop()
    check("manual stop summary", ctx.since(mark)[1], "Tandem: scan stopped, IDs 5000-? in 0.0s, 0 processed, 0 skipped")
    check("manual stop cancels the ticker", ctx.tickers[1].cancelled, true)
    ctx.tick(1)
    check("no tick after stop", ctx.run().processed, 0)
end

do
    local ctx = loadScanner({}, { schemaVersion = 4, scan = { cursor = 9 } })
    local mark = #ctx.printed
    ctx.Scanner.Start({ rate = 10, cap = 5 })
    check("read-only start is refused", ctx.since(mark)[1], "Recording is off: saved data uses a newer schema")
    check("read-only start makes no ticker", #ctx.tickers, 0)
    check("read-only start writes nothing", ctx.env.TandemDB.scan.lastRun, nil)
    ctx.Scanner.SetCursor(50)
    check("read-only SetCursor writes nothing", ctx.env.TandemDB.scan.cursor, 9)
end

for _, missing in ipairs({ "GetItemInfo", "GetItemInfoInstant", "C_Item" }) do
    local ctx = loadScanner({})
    if missing == "C_Item" then
        ctx.env.C_Item = nil
    else
        ctx.env.C_Item[missing] = nil
    end
    local mark = #ctx.printed
    ctx.Scanner.Start({ rate = 10, cap = 5 })
    check("missing " .. missing .. " refuses to start", ctx.since(mark)[1], "Tandem: item API not available")
    check("missing " .. missing .. " is not running", ctx.Scanner.IsRunning(), false)
end

do
    local ctx = loadScanner({})
    ctx.env.C_Timer = nil
    local mark = #ctx.printed
    ctx.Scanner.Start({ rate = 10, cap = 5 })
    check("missing C_Timer refuses to start", ctx.since(mark)[1], "Tandem: timer API not available")
end

do
    -- optional functions may be missing: no existence check, no load request, no combat check
    local items = { [1] = { "" }, [2] = { "INVTYPE_HEAD", loaded = false } }
    local ctx = loadScanner(items)
    ctx.env.C_Item.DoesItemExistByID = nil
    ctx.env.C_Item.RequestLoadItemDataByID = nil
    ctx.env.InCombatLockdown = nil
    ctx.Scanner.Start({ rate = 10, cap = 3 })
    ctx.tick(3)
    check("without DoesItemExistByID a hit still counts", ctx.run().hits, 1)
    check("without DoesItemExistByID an unknown id is a miss", ctx.run().misses, 1)
    check("without RequestLoadItemDataByID the item is deferred", ctx.run().deferred, 1)
end

do
    local ctx = loadScanner({ [1] = equip })
    ctx.env.issecretvalue = function(v)
        return v == 20
    end
    ctx.Scanner.Start({ rate = 10, cap = 1 })
    ctx.tick(1)
    check("a secret field is not stored", ctx.env.TandemDB.items[1], nil)
    check("a secret field still counts the hit", ctx.run().hits, 1)
end

do
    -- /tandem scan reaches the real scanner
    local ctx = loadScanner({ [2] = { "" } })
    run(ctx.addon, ctx.printed, "scan 15/m 3")
    check("/tandem scan 15/m 3 starts", ctx.Scanner.IsRunning(), true)
    check("/tandem scan 15/m 3 interval", ctx.tickers[1].interval, 4)
    ctx.tick(3)
    check("/tandem scan 15/m 3 stops at cap", ctx.Scanner.IsRunning(), false)
    check("/tandem scan 15/m 3 rate saved", ctx.run().rate, 0.25)
    local out = run(ctx.addon, ctx.printed, "count")
    check("count after scan", out[7], "Last run: IDs 1-3 at 15/m in 12.0s, 3 processed, 0 skipped")
    run(ctx.addon, ctx.printed, "scan from 40")
    check("/tandem scan from moves the cursor", ctx.scan().cursor, 40)
    run(ctx.addon, ctx.printed, "scan 1/s")
    check("/tandem scan stop prints the summary", run(ctx.addon, ctx.printed, "scan stop")[1],
        "Tandem: scan stopped, IDs 40-? in 0.0s, 0 processed, 0 skipped")
end

do
    local ctx = loadScanner({})
    ctx.fire("GET_ITEM_INFO_RECEIVED", 77, true)
    check("GET_ITEM_INFO_RECEIVED while idle is ignored", ctx.Scanner.IsRunning(), false)
    ctx.fire("ADDON_LOADED", "OtherAddon")
    check("another addon's ADDON_LOADED is ignored", ctx.env.TandemDB.scan.cursor, 1)
end

do
    local ctx = loadScanner({}, nil, "zhTW")
    local mark = #ctx.printed
    ctx.Scanner.Start({ rate = 10, cap = 1 })
    ctx.Scanner.Start({ rate = 10, cap = 1 })
    local out = ctx.since(mark)
    check("zhTW start line", out[1], "Tandem：掃描 1 個 ID，從 ID 1 開始")
    check("zhTW already running", out[2], "Tandem：掃描已在執行中")
    ctx.combat = true
    ctx.tick(1)
    check("zhTW paused line", ctx.printed[#ctx.printed], "Tandem：戰鬥中，掃描暫停")
end

-- Loot: loot-source recording with a stubbed loot, map and unit API.

local HOGGER = "Creature-0-1-0-12-448-0000ABCD"
local WOLF = "Creature-0-1-0-12-299-0000BEEF"
local CHEST = "GameObject-0-1-0-12-2843-00001234"

-- Returns the GUID of another spawn of Hogger.
local function hogger(spawn)
    return ("Creature-0-1-0-12-448-%08X"):format(spawn)
end

-- Returns t[i], t[i + 1], ... (unpack moved between Lua versions).
local function spread(t, i)
    i = i or 1
    if i <= #t then
        return t[i], spread(t, i + 1)
    end
end

-- Loads the addon with a loot window of slots ({link, sources = {guid, qty, ...}}); the player stands at
-- map 1429, 0.4123/0.6789, targeting nobody unless ctx.units is set.
local function loadLoot(db)
    local addon, printed, env, fire = loadWithDB(db or { schemaVersion = 1 })
    local ctx = { addon = addon, printed = printed, env = env, fire = fire, slots = {}, combat = false, units = {} }
    env.InCombatLockdown = function()
        return ctx.combat
    end
    env.GetNumLootItems = function()
        return #ctx.slots
    end
    env.GetLootSlotLink = function(slot)
        return ctx.slots[slot][1]
    end
    env.GetLootSourceInfo = function(slot)
        return spread(ctx.slots[slot].sources or {})
    end
    env.C_Map = {
        GetBestMapForUnit = function(unit)
            return unit == "player" and 1429 or nil
        end,
        GetPlayerMapPosition = function(map, unit)
            if map == 1429 and unit == "player" then
                return {
                    GetXY = function()
                        return 0.4123, 0.6789
                    end,
                }
            end
        end,
    }
    env.UnitGUID = function(unit)
        return ctx.units[unit] and ctx.units[unit][1]
    end
    env.UnitName = function(unit)
        return ctx.units[unit] and ctx.units[unit][2]
    end
    function ctx.loot()
        fire("LOOT_READY")
        fire("LOOT_CLOSED")
    end
    function ctx.entry(key)
        return env.TandemDB.loot[key]
    end
    return ctx
end

local function link(id)
    return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r"
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1 } } }
    ctx.units.target = { HOGGER, "Hogger" }
    ctx.loot()
    local e = ctx.entry("25:c:448:1429")
    check("loot: creature source recorded", e and e.count, 1)
    check("loot: npc id from GUID", e and e.id, 448)
    check("loot: coords rounded", e and e.coords[1][1] .. "," .. e.coords[1][2], "412,678")
    check("loot: name via target", ctx.env.TandemDB.npcs[448], "Hogger")
    check("loot: one entry", ctx.addon.Store.Counts().loot, 1)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { WOLF, 1 } } }
    ctx.units.target = { HOGGER, "Hogger" }
    ctx.units.mouseover = { WOLF, "Wolf" }
    ctx.loot()
    check("loot: name via mouseover", ctx.env.TandemDB.npcs[299], "Wolf")
    check("loot: non-matching target name not stored", ctx.env.TandemDB.npcs[448], nil)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { WOLF, 1 } } }
    ctx.loot()
    check("loot: no name without a GUID match", ctx.addon.Store.Counts().npcs, 0)
end

do
    local ctx = loadLoot()
    ctx.slots = {
        { link(30), sources = { HOGGER, 2, WOLF, 1, "Player-1-00000001", 1 } },
        { link(31), sources = { CHEST, 1, "Vehicle-0-1-0-12-500-0000AAAA", 1 } },
        { nil },
        { "|cff9d9d9d|Hcurrency:1220|h[Resources]|h|r", sources = { HOGGER, 1 } },
    }
    ctx.loot()
    check("loot: multi-source slot gives one entry per source (hogger)", ctx.entry("30:c:448:1429").count, 1)
    check("loot: multi-source slot gives one entry per source (wolf)", ctx.entry("30:c:299:1429").count, 1)
    check("loot: gameobject source", ctx.entry("31:o:2843:1429").count, 1)
    check("loot: vehicle source is a creature", ctx.entry("31:c:500:1429").count, 1)
    check("loot: player source and money/currency slots skipped", ctx.addon.Store.Counts().loot, 4)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1 } }, { link(26) } }
    ctx.env.GetLootSourceInfo = nil
    ctx.loot()
    check("loot: missing GetLootSourceInfo records ?", ctx.entry("25:?:0:1429").count, 1)
    ctx.env.GetLootSourceInfo = function() end
    ctx.loot()
    check("loot: empty GetLootSourceInfo records ?", ctx.entry("26:?:0:1429").count, 2)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1 } } }
    ctx.env.C_Map = nil
    ctx.loot()
    local e = ctx.entry("25:c:448:0")
    check("loot: missing C_Map uses map 0", e and e.count, 1)
    check("loot: missing C_Map has no coords", e and #e.coords, 0)
    ctx.env.C_Map = { GetBestMapForUnit = function() return 1429 end }
    ctx.slots = { { link(25), sources = { hogger(1), 1 } } }
    ctx.loot()
    check("loot: missing GetPlayerMapPosition keeps the map", #ctx.entry("25:c:448:1429").coords, 0)
    ctx.env.C_Map.GetPlayerMapPosition = function() end
    ctx.slots = { { link(25), sources = { hogger(2), 1 } } }
    ctx.loot()
    check("loot: nil position object keeps the map", ctx.entry("25:c:448:1429").count, 2)
    check("loot: nil position object has no coords", #ctx.entry("25:c:448:1429").coords, 0)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1, WOLF, 1 } } }
    ctx.units.target = { HOGGER, "Hogger" }
    ctx.env.issecretvalue = function(v)
        return v == HOGGER
    end
    ctx.loot()
    check("loot: secret GUID skipped", ctx.entry("25:c:448:1429"), nil)
    check("loot: other source of the slot kept", ctx.entry("25:c:299:1429").count, 1)
    check("loot: secret GUID records no name", ctx.env.TandemDB.npcs[448], nil)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1 } } }
    ctx.combat = true
    ctx.loot()
    check("loot: skipped in combat", ctx.addon.Store.Counts().loot, 0)
    ctx.combat = false
    ctx.fire("LOOT_READY")
    check("loot: a later LOOT_READY in the same window records after combat", ctx.addon.Store.Counts().loot, 1)
end

do
    local ctx = loadLoot({ schemaVersion = 4, loot = {} })
    ctx.slots = { { link(25), sources = { HOGGER, 1 } } }
    ctx.loot()
    check("loot: read-only db is not written", next(ctx.env.TandemDB.loot), nil)
    check("loot: read-only keeps unsaved at 0", ctx.addon.Store.unsaved, 0)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1 } } }
    ctx.fire("LOOT_READY")
    ctx.fire("LOOT_READY")
    check("loot: double LOOT_READY records once", ctx.entry("25:c:448:1429").count, 1)
    ctx.fire("LOOT_CLOSED")
    ctx.slots = { { link(25), sources = { hogger(1), 1 } } }
    ctx.fire("LOOT_READY")
    check("loot: a new window records again", ctx.entry("25:c:448:1429").count, 2)
    ctx.fire("LOOT_CLOSED")

    ctx.slots = { { link(40), sources = { CHEST, 1 } } }
    ctx.units.target = { HOGGER, "Hogger" }
    ctx.loot()
    local out = run(ctx.addon, ctx.printed, "count")
    check("count reflects loot entries", out[3], "Loot entries: 2, npc names: 0")
    -- two loot drops and two corpses, one loot drop from the chest
    check("count reflects looted corpses", out[4], "Kills: 0, looted corpses: 2")
    check("count reflects unsaved loot", out[6], "Unsaved records: 5 (saved on /reload or logout)")
end

-- Loot: looted corpses and session dedupe of loot sources (decision 10).

do
    local ctx = loadLoot()
    ctx.slots = {
        { link(25), sources = { HOGGER, 1, WOLF, 1 } },
        { link(26), sources = { HOGGER, 1 } },
        { nil, sources = { WOLF, 1 } },
    }
    ctx.loot()
    local corpses = ctx.env.TandemDB.corpses
    check("corpse: one per distinct creature across slots", corpses[448], 1)
    check("corpse: a creature on a money slot counts", corpses[299], 1)

    ctx.loot()
    check("dedupe: a re-opened corpse adds no corpse", corpses[448], 1)
    check("dedupe: a re-opened corpse adds no loot", ctx.entry("25:c:448:1429").count, 1)
    check("dedupe: a re-opened corpse adds no loot (second slot)", ctx.entry("26:c:448:1429").count, 1)

    ctx.slots = { { link(25), sources = { HOGGER, 1, hogger(9), 1 } } }
    ctx.loot()
    check("dedupe: a new creature in a mixed window counts its corpse", corpses[448], 2)
    check("dedupe: a new creature in a mixed window counts its loot only", ctx.entry("25:c:448:1429").count, 2)
end

do
    local ctx = loadLoot()
    ctx.slots = { { nil, sources = { WOLF, 1 } } }
    ctx.loot()
    check("corpse: a gold-only corpse counts", ctx.env.TandemDB.corpses[299], 1)
    check("corpse: a gold-only corpse records no loot", ctx.addon.Store.Counts().loot, 0)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(31), sources = { CHEST, 1, "Vehicle-0-1-0-12-500-0000AAAA", 1 } } }
    ctx.loot()
    check("corpse: a vehicle is a creature", ctx.env.TandemDB.corpses[500], 1)
    check("corpse: a game object adds no corpse", ctx.env.TandemDB.corpses[2843], nil)
    ctx.loot()
    check("dedupe: a re-opened node adds no loot", ctx.entry("31:o:2843:1429").count, 1)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1, WOLF, 1 } } }
    ctx.env.issecretvalue = function(v)
        return v == HOGGER
    end
    ctx.loot()
    check("corpse: a secret GUID adds no corpse", ctx.env.TandemDB.corpses[448], nil)
    check("corpse: the other source still counts", ctx.env.TandemDB.corpses[299], 1)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25) } }
    ctx.loot()
    ctx.loot()
    check("no GUIDs: loot counted per window", ctx.entry("25:?:0:1429").count, 2)
    check("no GUIDs: no corpse", next(ctx.env.TandemDB.corpses), nil)
    ctx.env.GetLootSourceInfo = nil
    ctx.loot()
    check("no GetLootSourceInfo: loot counted per window", ctx.entry("25:?:0:1429").count, 3)
end

do
    local ctx = loadLoot()
    ctx.combat = true
    ctx.slots = { { link(25), sources = { HOGGER, 1 } } }
    ctx.loot()
    ctx.combat = false
    ctx.loot()
    check("dedupe: a window skipped in combat does not mark its source", ctx.env.TandemDB.corpses[448], 1)
end

do
    local ctx = loadLoot()
    check("SEEN_MAX is 200", ctx.addon.Loot.SEEN_MAX, 200)
    for spawn = 1, ctx.addon.Loot.SEEN_MAX do
        ctx.slots = { { nil, sources = { hogger(spawn), 1 } } }
        ctx.loot()
    end
    ctx.slots = { { nil, sources = { hogger(1), 1 } } }
    ctx.loot()
    check("dedupe: the last 200 sources are remembered", ctx.env.TandemDB.corpses[448], 200)
    ctx.slots = { { nil, sources = { hogger(201), 1 } } }
    ctx.loot()
    ctx.slots = { { nil, sources = { hogger(1), 1 } } }
    ctx.loot()
    check("dedupe: the 201st source evicts the oldest", ctx.env.TandemDB.corpses[448], 202)
    ctx.slots = { { nil, sources = { hogger(3), 1 } } }
    ctx.loot()
    check("dedupe: newer sources stay remembered", ctx.env.TandemDB.corpses[448], 202)
end

do
    local ctx = loadLoot()
    ctx.slots = { { link(25), sources = { HOGGER, 1 } } }
    ctx.loot()
    local again = loadLoot(ctx.env.TandemDB)
    again.slots = { { link(25), sources = { HOGGER, 1 } } }
    again.loot()
    check("dedupe: a reload forgets seen sources", again.env.TandemDB.corpses[448], 2)
end

-- Sources: quest rewards and merchant items with stubbed quest, merchant and item APIs.

local MERCHANT = "Creature-0-1-0-12-1250-0000CAFE"

-- Loads the addon with a quest frame (ctx.quest = {id, title, choices = {links}, rewards = {links}}), a merchant
-- (ctx.merchant = {guid, name, items = {links}}) and items ({[id] = {equipLoc, loaded = bool}}); the player is
-- Alliance at map 1429, 0.4123/0.6789.
local function loadSources(items)
    local addon, printed, env, fire, frame = loadWithDB({ schemaVersion = 3 })
    local ctx = { addon = addon, printed = printed, env = env, fire = fire, frame = frame, combat = false,
                  faction = "Alliance", quest = { id = 0, choices = {}, rewards = {} },
                  merchant = { items = {} }, requested = {} }
    env.InCombatLockdown = function()
        return ctx.combat
    end
    env.UnitFactionGroup = function(unit)
        if unit == "player" then
            return ctx.faction
        end
    end
    env.C_Map = {
        GetBestMapForUnit = function()
            return 1429
        end,
        GetPlayerMapPosition = function()
            return {
                GetXY = function()
                    return 0.4123, 0.6789
                end,
            }
        end,
    }
    env.GetQuestID = function()
        return ctx.quest.id
    end
    env.GetTitleText = function()
        return ctx.quest.title
    end
    env.GetNumQuestChoices = function()
        return #ctx.quest.choices
    end
    env.GetNumQuestRewards = function()
        return #ctx.quest.rewards
    end
    env.GetQuestItemLink = function(list, i)
        return (list == "choice" and ctx.quest.choices or list == "reward" and ctx.quest.rewards or {})[i]
    end
    env.UnitGUID = function(unit)
        return unit == "npc" and ctx.merchant.guid or nil
    end
    env.UnitName = function(unit)
        return unit == "npc" and ctx.merchant.name or nil
    end
    env.GetMerchantNumItems = function()
        return ctx.merchant.n or #ctx.merchant.items
    end
    env.GetMerchantItemLink = function(i)
        return ctx.merchant.items[i]
    end
    env.C_Item = {
        GetItemInfoInstant = function(id)
            local it = items[id]
            if it then
                return id, "Armor", "Cloth", it[1], 134400, 4, 1
            end
        end,
        GetItemInfo = function(id)
            local it = items[id]
            if it and it.loaded ~= false then
                return "Item " .. id, "link", 2, 20, 15, "Armor", "Cloth", 1, it[1], 134400, 5, 4, 1
            end
        end,
        RequestLoadItemDataByID = function(id)
            ctx.requested[#ctx.requested + 1] = id
        end,
    }
    function ctx.entry(key)
        return env.TandemDB.loot[key]
    end
    function ctx.loots()
        return addon.Store.Counts().loot
    end
    return ctx
end

do
    local ctx = loadSources({})
    for _, ev in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
        check("sources: registers " .. ev, ctx.frame.registered[ev], true)
    end
end

for _, event in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE" }) do
    local ctx = loadSources({ [40] = equip, [41] = { "INVTYPE_CHEST" }, [42] = { "" }, [43] = equip })
    ctx.quest = { id = 176, title = "Wanted: Hogger", choices = { link(40), link(41), link(42) },
                  rewards = { link(43), "|cffffffff|Hcurrency:1220|h[Resources]|h|r" } }
    ctx.fire(event)
    local e = ctx.entry("40:q:176:1429")
    check("sources: " .. event .. " records a choice item", e and e.count, 1)
    check("sources: " .. event .. " quest entry carries the faction", e and e.factions, 1)
    check("sources: " .. event .. " quest entry has coords", e and e.coords[1][1] .. "," .. e.coords[1][2],
        "412,678")
    check("sources: " .. event .. " records each choice", ctx.entry("41:q:176:1429") ~= nil, true)
    check("sources: " .. event .. " records a reward item", ctx.entry("43:q:176:1429") ~= nil, true)
    check("sources: " .. event .. " skips non-equippable and non-item links", ctx.loots(), 3)
    check("sources: " .. event .. " stores the quest name", ctx.env.TandemDB.quests[176], "Wanted: Hogger")
    check("sources: " .. event .. " caches the item record",
        ctx.env.TandemDB.items[40] and ctx.env.TandemDB.items[40][4], "INVTYPE_HEAD")
    check("sources: " .. event .. " does not cache a non-equippable item", ctx.env.TandemDB.items[42], nil)
end

do
    local ctx = loadSources({ [40] = equip })
    ctx.quest = { id = 176, title = "Wanted: Hogger", choices = { link(40) }, rewards = {} }
    ctx.fire("QUEST_DETAIL")
    ctx.fire("QUEST_COMPLETE")
    check("sources: offer and turn-in record the reward once", ctx.entry("40:q:176:1429").count, 1)
    ctx.faction = "Horde"
    ctx.fire("QUEST_COMPLETE")
    check("sources: another faction ORs into the entry", ctx.entry("40:q:176:1429").factions, 3)
end

do
    local ctx = loadSources({ [42] = { "" } })
    ctx.quest = { id = 177, title = "Gold Dust Exchange", choices = {}, rewards = { link(42) } }
    ctx.fire("QUEST_COMPLETE")
    check("sources: a quest without gear records nothing", ctx.loots(), 0)
    check("sources: a quest without gear keeps no name", ctx.env.TandemDB.quests[177], nil)
end

do
    local ctx = loadSources({ [50] = equip, [51] = { "INVTYPE_WEAPON" }, [52] = { "INVTYPE_NON_EQUIP_IGNORE" } })
    ctx.merchant = { guid = MERCHANT, name = "Andrew Krighton", items = { link(50), nil, link(52) }, n = 3 }
    ctx.fire("MERCHANT_SHOW")
    local e = ctx.entry("50:v:1250:1429")
    check("sources: merchant item recorded under the npc", e and e.count, 1)
    check("sources: merchant entry carries the faction", e and e.factions, 1)
    check("sources: merchant name stored", ctx.env.TandemDB.npcs[1250], "Andrew Krighton")
    check("sources: merchant skips missing links and non-equippable items", ctx.loots(), 1)
    ctx.merchant.items[2] = link(51)
    ctx.fire("MERCHANT_UPDATE")
    check("sources: MERCHANT_UPDATE records a late link", ctx.entry("51:v:1250:1429") ~= nil, true)
    check("sources: MERCHANT_UPDATE does not count again", ctx.entry("50:v:1250:1429").count, 1)
end

do
    local ctx = loadSources({ [50] = equip })
    ctx.merchant = { guid = "Player-1-00000001", name = "Someone", items = { link(50) } }
    ctx.fire("MERCHANT_SHOW")
    check("sources: a non-creature merchant records nothing", ctx.loots(), 0)
    ctx.merchant.guid = nil
    ctx.fire("MERCHANT_SHOW")
    check("sources: a merchant without GUID records nothing", ctx.loots(), 0)
end

do
    local items = { [60] = { "INVTYPE_HAND", loaded = false }, [61] = { "INVTYPE_FEET", loaded = false } }
    local ctx = loadSources(items)
    ctx.merchant = { guid = MERCHANT, name = "Andrew Krighton", items = { link(60), link(61) } }
    ctx.fire("MERCHANT_SHOW")
    ctx.fire("MERCHANT_UPDATE")
    check("sources: an uncached item is still a source", ctx.entry("60:v:1250:1429") ~= nil, true)
    check("sources: an uncached item has no record yet", ctx.env.TandemDB.items[60], nil)
    check("sources: an uncached item is requested once", #ctx.requested, 2)
    check("sources: the request names the item", ctx.requested[1], 60)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 99, true)
    check("sources: another addon's item info is ignored", ctx.env.TandemDB.items[99], nil)
    items[60].loaded, items[61].loaded = true, true
    ctx.fire("GET_ITEM_INFO_RECEIVED", 60, true)
    local rec = ctx.env.TandemDB.items[60]
    check("sources: item info arrival stores the record", rec and rec[4], "INVTYPE_HAND")
    check("sources: stored record keeps its level", rec and rec[1], 20)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 61, false)
    check("sources: a failed item info stores nothing", ctx.env.TandemDB.items[61], nil)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 61, true)
    check("sources: a resolved item is no longer pending", ctx.env.TandemDB.items[61], nil)
end

do
    local ctx = loadSources({ [40] = equip, [50] = equip })
    ctx.quest = { id = 176, title = "Wanted: Hogger", choices = { link(40) }, rewards = {} }
    ctx.merchant = { guid = MERCHANT, name = "Andrew Krighton", items = { link(50) } }
    ctx.combat = true
    ctx.fire("QUEST_COMPLETE")
    ctx.fire("MERCHANT_SHOW")
    check("sources: nothing recorded in combat", ctx.loots(), 0)
    check("sources: no names recorded in combat", ctx.addon.Store.Counts().npcs, 0)
    ctx.combat = false
    ctx.faction = "Neutral"
    ctx.fire("QUEST_COMPLETE")
    ctx.fire("MERCHANT_SHOW")
    check("sources: nothing recorded for a neutral player", ctx.loots(), 0)
    ctx.faction = "Alliance"
    ctx.addon.Store.readOnly = true
    ctx.fire("QUEST_COMPLETE")
    ctx.fire("MERCHANT_SHOW")
    check("sources: nothing recorded while read-only", ctx.loots(), 0)
end

-- Returns a sources ctx with a quest offering item 40 and a merchant selling item 50.
local function questAndMerchant()
    local ctx = loadSources({ [40] = equip, [50] = equip })
    ctx.quest = { id = 176, title = "Wanted: Hogger", choices = { link(40) }, rewards = {} }
    ctx.merchant = { guid = MERCHANT, name = "Andrew Krighton", items = { link(50) } }
    return ctx
end

for _, case in ipairs({
    { "GetQuestID", "QUEST_DETAIL" }, { "GetQuestItemLink", "QUEST_DETAIL" },
    { "UnitGUID", "MERCHANT_SHOW" }, { "GetMerchantNumItems", "MERCHANT_SHOW" },
    { "GetMerchantItemLink", "MERCHANT_SHOW" },
    { "UnitFactionGroup", "QUEST_DETAIL", "MERCHANT_SHOW" }, { "C_Item", "QUEST_DETAIL", "MERCHANT_SHOW" },
}) do
    local ctx = questAndMerchant()
    ctx.env[case[1]] = nil
    for i = 2, #case do
        ctx.fire(case[i])
    end
    check("sources: missing " .. case[1] .. " records nothing", ctx.loots(), 0)
end

do
    local ctx = questAndMerchant()
    ctx.env.GetNumQuestChoices, ctx.env.GetTitleText, ctx.env.UnitName, ctx.env.C_Map = nil, nil, nil, nil
    ctx.fire("QUEST_DETAIL")
    ctx.fire("MERCHANT_SHOW")
    check("sources: missing optional APIs still record the merchant", ctx.loots(), 1)
    check("sources: missing map records map 0", ctx.entry("50:v:1250:0") ~= nil, true)
    check("sources: missing UnitName keeps no npc name", ctx.env.TandemDB.npcs[1250], nil)
end

do
    local ctx = loadSources({ [40] = equip })
    ctx.quest = { id = 176, title = "Wanted: Hogger", choices = { link(40) }, rewards = {} }
    ctx.env.issecretvalue = function(v)
        return v == 176
    end
    ctx.fire("QUEST_DETAIL")
    check("sources: a secret quest ID records nothing", ctx.loots(), 0)
end

-- Kills: player's PARTY_KILLs from the combat log.

local PLAYER = "Player-1-00000001"

-- Loads the addon with a combat log that returns ctx.cleu; opts.noCLEU removes the API, opts.blockCLEU forbids
-- registering it, opts.player = false hides the player GUID until ctx.playerKnown is set.
local function loadKills(opts)
    opts = opts or {}
    local ctx = { combat = false, cleu = {} }
    local env = {
        InCombatLockdown = function()
            return ctx.combat
        end,
        UnitGUID = function(unit)
            if unit == "player" and (opts.player ~= false or ctx.playerKnown) then
                return PLAYER
            end
        end,
    }
    if not opts.noCLEU then
        env.CombatLogGetCurrentEventInfo = function()
            return spread(ctx.cleu)
        end
    end
    local addon, printed, e, fire, frame = loadWithDB(opts.db or { schemaVersion = 3 }, "enUS",
        { env = env, blockCLEU = opts.blockCLEU })
    ctx.addon, ctx.printed, ctx.env, ctx.fire, ctx.frame = addon, printed, e, fire, frame
    -- Fires one combat log event: timestamp, sub, hideCaster, src, srcName, srcFlags, srcRaidFlags, dst.
    function ctx.log(sub, src, dst)
        ctx.cleu = { 1, sub, false, src, "Me", 0, 0, dst }
        fire("COMBAT_LOG_EVENT_UNFILTERED")
    end
    function ctx.kills()
        return e.TandemDB.kills
    end
    return ctx
end

do
    local ctx = loadKills()
    check("kills: status on", ctx.addon.Kills.Status(), "on")
    check("kills: CLEU registered", ctx.frame.registered.COMBAT_LOG_EVENT_UNFILTERED, true)
    check("kills: PLAYER_REGEN_ENABLED registered", ctx.frame.registered.PLAYER_REGEN_ENABLED, true)
    check("kills: PLAYER_LOGOUT registered", ctx.frame.registered.PLAYER_LOGOUT, true)

    ctx.combat = true
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.log("PARTY_KILL", PLAYER, "Vehicle-0-1-0-12-500-0000AAAA")
    ctx.log("PARTY_KILL", "Player-1-00000002", WOLF)
    ctx.log("PARTY_KILL", "Pet-0-1-0-12-1-00000001", WOLF)
    ctx.log("SWING_DAMAGE", PLAYER, WOLF)
    ctx.log("PARTY_KILL", PLAYER, "Player-1-00000003")
    ctx.log("PARTY_KILL", PLAYER, CHEST)
    check("kills: nothing stored in combat", next(ctx.kills()), nil)
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: a combat-time Flush stores nothing", next(ctx.kills()), nil)
    ctx.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: player's creature kill stored after combat", ctx.kills()[448], 1)
    check("kills: player's vehicle kill stored", ctx.kills()[500], 1)
    check("kills: other players', pets' kills and other events skipped", ctx.kills()[299], nil)
    check("kills: only creature kills", ctx.addon.Store.Counts().kills, 2)
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: flush empties the buffer", ctx.addon.Store.Counts().kills, 2)

    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.fire("PLAYER_LOGOUT")
    check("kills: logout flushes", ctx.kills()[448], 2)
end

do
    local ctx = loadKills()
    ctx.combat = true
    for _ = 1, 501 do
        ctx.log("PARTY_KILL", PLAYER, HOGGER)
    end
    ctx.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: buffer caps at 500", ctx.kills()[448], 500)
end

do
    local ctx = loadKills({ noCLEU = true })
    check("kills: no combat log API is unavailable", ctx.addon.Kills.Status(), "unavailable")
    check("kills: no combat log API registers no CLEU", ctx.frame.registered.COMBAT_LOG_EVENT_UNFILTERED, nil)
end

do
    local ctx = loadKills({ player = false })
    check("kills: a missing player GUID still registers", ctx.addon.Kills.Status(), "on")
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: nothing counted while the player GUID is unknown", next(ctx.kills()), nil)
    ctx.playerKnown = true
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: the player GUID is read lazily once known", ctx.kills()[448], 1)
end

do
    local ctx = loadKills()
    ctx.combat = true
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.fire("PLAYER_LOGOUT")
    check("kills: logout in combat still stores the buffer", ctx.kills()[448], 1)
end

do
    local ctx = loadKills({ blockCLEU = true })
    check("kills: a forbidden registration is blocked", ctx.addon.Kills.Status(), "blocked")
    check("kills: blocked still loads the addon", ctx.printed[1], "Tandem loaded")
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: blocked counts nothing", next(ctx.kills()), nil)
end

do
    local ctx = loadKills()
    ctx.combat = true
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.env.issecretvalue = function(v)
        return v == WOLF
    end
    ctx.log("PARTY_KILL", PLAYER, WOLF)
    check("kills: a secret payload turns kills off", ctx.addon.Kills.Status(), "secret")
    check("kills: a secret payload unregisters CLEU", ctx.frame.unregistered.COMBAT_LOG_EVENT_UNFILTERED, true)
    ctx.env.issecretvalue = nil
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: a secret payload clears the buffer", next(ctx.kills()), nil)
end

do
    local ctx = loadKills({ db = { schemaVersion = 4 } })
    ctx.log("PARTY_KILL", PLAYER, HOGGER)
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("kills: read-only db is not written", ctx.env.TandemDB.kills, nil)
    check("kills: read-only keeps unsaved at 0", ctx.addon.Store.unsaved, 0)
end

-- Advisor: usability, ranking and sources over own + shipped data.

-- { ilvl, reqLevel, quality, equipLoc, classID, subclassID }
local GEAR = {
    [1] = { 45, 40, 3, "INVTYPE_CHEST", 4, 4 },        -- plate chest
    [2] = { 30, 25, 2, "INVTYPE_ROBE", 4, 3 },         -- mail robe
    [3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2 },        -- leather chest
    [4] = { 30, 25, 3, "INVTYPE_ROBE", 4, 1 },         -- cloth robe
    [5] = { 20, 15, 2, "INVTYPE_SHIELD", 4, 6 },
    [6] = { 20, 15, 2, "INVTYPE_RELIC", 4, 7 },        -- libram
    [7] = { 25, 20, 2, "INVTYPE_WEAPON", 2, 7 },       -- one-hand sword
    [8] = { 22, 18, 2, "INVTYPE_RANGEDRIGHT", 2, 19 }, -- wand
    [9] = { 1, 1, 1, "INVTYPE_BODY", 4, 0 },           -- shirt
    [10] = { 5, 1, 1, "INVTYPE_2HWEAPON", 2, 20 },     -- fishing pole
    [11] = { 99, 1, 5, "INVTYPE_CHEST", 4, 1 },        -- GM robe, no source
    [12] = { 20, 10, 2, "INVTYPE_CHEST", 4, 3 },       -- mail chest
    [13] = { 50, 38, 3, "INVTYPE_LEGS", 4, 4 },        -- plate legs, low reqLevel
    [14] = { 24, 15, 2, "INVTYPE_WEAPONOFFHAND", 2, 7 }, -- off-hand sword
    [15] = { 30, 20, 2, "INVTYPE_2HWEAPON", 2, 1 },    -- two-hand axe, no source
}

-- Splits GEAR between own and shipped data; own loot sources items 1 and 3, shipped loot the rest but 9-11.
local function gearData()
    local ownItems, shippedItems = {}, {}
    for id, r in pairs(GEAR) do
        if id % 2 == 1 then
            ownItems[id] = r
        else
            shippedItems[id] = r
        end
    end
    local db = { schemaVersion = 3, items = ownItems, loot = {
        ["1:c:448:1429"] = { item = 1, kind = "c", id = 448, map = 1429, count = 1 },
        ["3:o:77:1429"] = { item = 3, kind = "o", id = 77, map = 1429, count = 1 },
    } }
    local shipped = { items = shippedItems, loot = {} }
    for _, id in ipairs({ 2, 4, 5, 6, 7, 8, 12, 13, 14 }) do
        shipped.loot[#shipped.loot + 1] = { id, "c", 500, 1429, 1 }
    end
    return db, shipped
end

local function loadAdvisor(db, shipped, env)
    return loadWithDB(db, "enUS", { shipped = shipped, env = env }).Advisor
end

local function ids(list)
    if not list then
        return "nil"
    end
    local out = {}
    for _, e in ipairs(list) do
        out[#out + 1] = tostring(e.id)
    end
    return table.concat(out, ",")
end

-- Slots per equipLoc: one cloth-typed item per equipLoc, found through List (every slot it fills) and Place.
do
    local LOCS = { "INVTYPE_ROBE", "INVTYPE_CLOAK", "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_SHIELD",
                   "INVTYPE_HOLDABLE", "INVTYPE_2HWEAPON", "INVTYPE_RELIC", "INVTYPE_THROWN", "INVTYPE_BODY",
                   "INVTYPE_TABARD", "INVTYPE_WHATEVER" }
    local items, idOf = {}, {}
    for i, loc in ipairs(LOCS) do
        items[100 + i], idOf[loc] = { 10, 1, 1, loc, 4, 1 }, 100 + i
    end
    local A = loadAdvisor({ schemaVersion = 3, items = items })
    local function slots(equipLoc, class, level)
        local id, out = idOf[equipLoc], {}
        for _, slot in ipairs(A.SLOTS) do
            for _, row in ipairs(A.List(slot, class, level)) do
                if row.id == id then
                    out[#out + 1] = slot
                end
            end
        end
        local place = A.Place(id, class, level)
        check("advisor: Place of " .. equipLoc .. " is its first listed slot", place.slot, out[1])
        return table.concat(out, ",")
    end
    check("advisor: SLOTS order", table.concat(A.SLOTS, " "),
        "head neck shoulder back chest wrist hands waist legs feet finger trinket mainhand offhand twohand ranged")
    check("advisor: ROBE goes in chest", slots("INVTYPE_ROBE", "MAGE", 1), "chest")
    check("advisor: CLOAK goes in back", slots("INVTYPE_CLOAK", "MAGE", 1), "back")
    check("advisor: rogue dual-wields one-hand weapons at 10", slots("INVTYPE_WEAPON", "ROGUE", 10), "mainhand,offhand")
    check("advisor: rogue below 10 does not dual-wield", slots("INVTYPE_WEAPON", "ROGUE", 9), "mainhand")
    check("advisor: warrior dual-wields at 20", slots("INVTYPE_WEAPON", "WARRIOR", 20), "mainhand,offhand")
    check("advisor: warrior below 20 does not dual-wield", slots("INVTYPE_WEAPON", "WARRIOR", 19), "mainhand")
    check("advisor: mage never dual-wields", slots("INVTYPE_WEAPON", "MAGE", 60), "mainhand")
    check("advisor: main-hand weapon", slots("INVTYPE_WEAPONMAINHAND", "ROGUE", 60), "mainhand")
    check("advisor: shield is off hand", slots("INVTYPE_SHIELD", "WARRIOR", 60), "offhand")
    check("advisor: holdable is off hand", slots("INVTYPE_HOLDABLE", "MAGE", 60), "offhand")
    check("advisor: two-hander", slots("INVTYPE_2HWEAPON", "WARRIOR", 60), "twohand")
    check("advisor: relic is ranged", slots("INVTYPE_RELIC", "PALADIN", 60), "ranged")
    check("advisor: thrown is ranged", slots("INVTYPE_THROWN", "ROGUE", 60), "ranged")
    check("advisor: shirt is not advised", slots("INVTYPE_BODY", "MAGE", 60), "")
    check("advisor: tabard is not advised", slots("INVTYPE_TABARD", "MAGE", 60), "")
    check("advisor: unknown equipLoc is not advised", slots("INVTYPE_WHATEVER", "MAGE", 60), "")
    check("advisor: all slots lists a dual-wield weapon once", ids(A.List(nil, "ROGUE", 60)):find(
        tostring(idOf.INVTYPE_WEAPON), 1, true) ~= nil, true)
end

do
    local A = loadAdvisor(gearData())

    local function usable(id, class, level)
        local ok, reason, need = A.Usable(GEAR[id], class, level)
        return tostring(ok) .. " " .. tostring(reason) .. " " .. tostring(need)
    end
    check("advisor: warrior wears plate at 40", usable(1, "WARRIOR", 40), "true nil nil")
    check("advisor: warrior needs 40 for plate", usable(1, "WARRIOR", 39), "false level 40")
    check("advisor: plate needLevel is the proficiency level", usable(13, "WARRIOR", 30), "false level 40")
    check("advisor: paladin wears plate at 40", usable(1, "PALADIN", 40), "true nil nil")
    check("advisor: hunter needs 40 for mail", usable(12, "HUNTER", 39), "false level 40")
    check("advisor: hunter wears mail at 40", usable(12, "HUNTER", 40), "true nil nil")
    check("advisor: shaman needs 40 for mail", usable(12, "SHAMAN", 39), "false level 40")
    check("advisor: shaman wears mail at 40", usable(12, "SHAMAN", 40), "true nil nil")
    check("advisor: warrior wears mail before 40", usable(12, "WARRIOR", 10), "true nil nil")
    check("advisor: mage cannot wear plate", usable(1, "MAGE", 60), "false proficiency nil")
    check("advisor: rogue cannot wear mail", usable(12, "ROGUE", 60), "false proficiency nil")
    check("advisor: reqLevel blocks a usable type", usable(3, "ROGUE", 24), "false level 25")
    check("advisor: paladin uses a shield", usable(5, "PALADIN", 20), "true nil nil")
    check("advisor: mage cannot use a shield", usable(5, "MAGE", 60), "false proficiency nil")
    check("advisor: mage cannot use an off-hand weapon", usable(14, "MAGE", 60), "false proficiency nil")
    check("advisor: off-hand weapon needs dual wield", usable(14, "WARRIOR", 19), "false level 20")
    check("advisor: warrior uses an off-hand weapon at 20", usable(14, "WARRIOR", 20), "true nil nil")
    check("advisor: shaman cannot use a two-hand axe", usable(15, "SHAMAN", 60), "false proficiency nil")
    check("advisor: shaman cannot use a two-hand mace",
        select(2, A.Usable({ 30, 20, 2, "INVTYPE_2HWEAPON", 2, 5 }, "SHAMAN", 60)), "proficiency")
    check("advisor: warrior uses a two-hand axe", usable(15, "WARRIOR", 60), "true nil nil")
    check("advisor: paladin uses a libram", usable(6, "PALADIN", 20), "true nil nil")
    check("advisor: druid cannot use a libram", usable(6, "DRUID", 60), "false proficiency nil")
    check("advisor: priest uses a wand", usable(8, "PRIEST", 20), "true nil nil")
    check("advisor: warrior cannot use a wand", usable(8, "WARRIOR", 60), "false proficiency nil")
    check("advisor: fishing pole is never advised", usable(10, "WARRIOR", 60), "false proficiency nil")
    check("advisor: shirt has no slot", usable(9, "WARRIOR", 60), "false slot nil")
    check("advisor: unknown class wears cloth", usable(4, "MONK", 60), "true nil nil")
    check("advisor: unknown class cannot wear leather", usable(3, "MONK", 60), "false proficiency nil")

    check("advisor: Item reads own data", A.Item(1) and A.Item(1)[4], "INVTYPE_CHEST")
    check("advisor: Item reads shipped data", A.Item(2) and A.Item(2)[4], "INVTYPE_ROBE")
    check("advisor: Item of an unknown id", A.Item(999), nil)
    check("advisor: HasSource from own loot", A.HasSource(1), true)
    check("advisor: HasSource from shipped loot", A.HasSource(2), true)
    check("advisor: HasSource of a sourceless item", A.HasSource(11), false)

    check("advisor: Best chest sorts ilvl, quality, id", ids(A.Best("chest", "WARRIOR", 40)), "1,3,4,2,12")
    check("advisor: Best chest below plate level", ids(A.Best("chest", "WARRIOR", 39)), "3,4,2,12")
    check("advisor: Best chest for a mage", ids(A.Best("chest", "MAGE", 60)), "4")
    check("advisor: Best chest for a low hunter", ids(A.Best("chest", "HUNTER", 25)), "3,4")
    check("advisor: Best hides sourceless items", ids(A.Best("chest", "MAGE", 60, {})), "4")
    local all = A.Best("chest", "MAGE", 60, { all = true })
    check("advisor: Best with all adds sourceless items", ids(all), "11,4")
    check("advisor: Best marks sourceless items", all[1].sourced, false)
    check("advisor: Best marks sourced items", all[2].sourced, true)
    check("advisor: Best entry fields", all[2].ilvl .. " " .. all[2].quality .. " " .. all[2].reqLevel, "30 3 25")
    check("advisor: Best offhand for a dual-wielding rogue", ids(A.Best("offhand", "ROGUE", 20)), "7,14")
    check("advisor: Best offhand for a rogue below 10", ids(A.Best("offhand", "ROGUE", 9)), "")
    check("advisor: Best offhand for a warrior below 20", ids(A.Best("offhand", "WARRIOR", 19)), "5")
    check("advisor: Best offhand for a warrior at 20", ids(A.Best("offhand", "WARRIOR", 20)), "7,14,5")
    check("advisor: Best mainhand for a rogue", ids(A.Best("mainhand", "ROGUE", 20)), "7")
    check("advisor: Best ranged for a paladin", ids(A.Best("ranged", "PALADIN", 60)), "6")
    check("advisor: Best ranged for a priest", ids(A.Best("ranged", "PRIEST", 60)), "8")
    check("advisor: Best twohand skips the fishing pole", ids(A.Best("twohand", "WARRIOR", 60, { all = true })),
        "15")
    check("advisor: Best twohand for a shaman", ids(A.Best("twohand", "SHAMAN", 60, { all = true })), "")
    check("advisor: Best unknown slot", A.Best("shirt", "WARRIOR", 60), nil)

    local r = A.Rank(2, "WARRIOR", 40)
    check("advisor: Rank of a listed item", r.rank .. "/" .. r.total .. " " .. r.slot, "4/5 chest")
    check("advisor: Rank of a listed item is usable", r.usable, true)
    r = A.Rank(11, "WARRIOR", 40)
    check("advisor: Rank of a sourceless item", r.rank .. "/" .. r.total, "1/6")
    check("advisor: Rank marks a sourceless item", r.sourced, false)
    r = A.Rank(1, "MAGE", 60)
    check("advisor: Rank of an unusable item", r.rank .. "/" .. r.total, "1/2")
    check("advisor: Rank says why it is unusable", tostring(r.usable) .. " " .. r.reason, "false proficiency")
    r = A.Rank(1, "WARRIOR", 30)
    check("advisor: Rank gives the level needed", r.reason .. " " .. r.needLevel, "level 40")
    r = A.Rank(7, "ROGUE", 20)
    check("advisor: Rank ignores dual wield", r.slot .. " " .. r.rank .. "/" .. r.total, "mainhand 1/1")
    r = A.Rank(14, "WARRIOR", 19)
    check("advisor: Rank of an off-hand weapon before dual wield",
        r.slot .. " " .. r.reason .. " " .. r.needLevel .. " " .. r.rank .. "/" .. r.total, "offhand level 20 1/2")
    r = A.Rank(9, "WARRIOR", 60)
    check("advisor: Rank of an unranked slot", tostring(r.slot) .. " " .. tostring(r.rank), "nil nil")
    check("advisor: Rank of an unknown item", A.Rank(999, "WARRIOR", 60), nil)

    local p = A.Place(1, "WARRIOR", 30)
    check("advisor: Place of an item", p.slot .. " " .. tostring(p.usable) .. " " .. p.reason .. " " .. p.needLevel,
        "chest false level 40")
    check("advisor: Place has no rank", tostring(p.rank) .. " " .. tostring(p.total), "nil nil")
    p = A.Place(7, "ROGUE", 20)
    check("advisor: Place of a one-hander is the main hand", p.slot .. " " .. tostring(p.usable), "mainhand true")
    p = A.Place(9, "WARRIOR", 60)
    check("advisor: Place of an unranked slot", tostring(p.slot) .. " " .. p.reason, "nil slot")
    check("advisor: Place of an unknown item", A.Place(999, "WARRIOR", 60), nil)
end

-- Advisor.List: every known item per slot (unit 4).
do
    local A = loadAdvisor(gearData())
    local function slotsOf(list)
        local out = {}
        for _, e in ipairs(list) do
            out[#out + 1] = e.slot
        end
        return table.concat(out, ",")
    end
    check("list: chest sorts ilvl, quality, id", ids(A.List("chest", "WARRIOR", 40)), "11,1,3,4,2,12")
    check("list: chest keeps unusable items", ids(A.List("chest", "MAGE", 60)), "11,1,3,4,2,12")
    check("list: chest usableOnly", ids(A.List("chest", "MAGE", 60, { usableOnly = true })), "11,4")
    check("list: usableOnly false keeps unusable items", ids(A.List("chest", "MAGE", 60, { usableOnly = false })),
        "11,1,3,4,2,12")
    local rows = A.List("chest", "WARRIOR", 30)
    local r = rows[2]
    check("list: unusable row fields", ("%d %s %s %s %d %d %d %d %s"):format(r.id, r.slot, tostring(r.usable),
        r.reason, r.needLevel, r.ilvl, r.quality, r.reqLevel, tostring(r.sourced)),
        "1 chest false level 40 45 3 40 true")
    check("list: usable row has no reason", tostring(rows[3].usable) .. " " .. tostring(rows[3].reason) .. " "
        .. tostring(rows[3].needLevel), "true nil nil")
    check("list: proficiency reason", A.List("chest", "MAGE", 60)[2].reason, "proficiency")
    check("list: sourceless item", rows[1].id .. " " .. tostring(rows[1].sourced), "11 false")
    check("list: usableOnly drops a level-locked item", ids(A.List("chest", "WARRIOR", 30, { usableOnly = true })),
        "11,3,4,2,12")
    check("list: offhand includes dual-wield one-handers", ids(A.List("offhand", "WARRIOR", 40)), "7,14,5")
    check("list: offhand before dual wield", ids(A.List("offhand", "ROGUE", 9)), "14,5")
    check("list: twohand lists the fishing pole", ids(A.List("twohand", "WARRIOR", 60)), "15,10")
    check("list: twohand usableOnly skips the fishing pole",
        ids(A.List("twohand", "WARRIOR", 60, { usableOnly = true })), "15")
    check("list: unknown slot", A.List("shirt", "WARRIOR", 60), nil)

    local all = A.List(nil, "WARRIOR", 40)
    check("list: all slots", ids(all), "11,13,1,3,4,2,15,7,14,8,5,6,12,10")
    check("list: all slots row slots", slotsOf(all),
        "chest,legs,chest,chest,chest,chest,twohand,mainhand,offhand,ranged,offhand,ranged,chest,twohand")
    check("list: all slots usableOnly", ids(A.List(nil, "WARRIOR", 40, { usableOnly = true })),
        "11,13,1,3,4,2,15,7,14,5,12")
    check("list: all slots usableOnly for a priest", ids(A.List(nil, "PRIEST", 60, { usableOnly = true })),
        "11,4,8")
    check("list: Best is List filtered", ids(A.Best("chest", "WARRIOR", 30)), "3,4,2,12")
end

do
    local db, shipped = gearData()
    shipped.items[1] = { 10, 1, 1, "INVTYPE_CHEST", 4, 1 }
    db.items[2] = { 31, 25, 2, "INVTYPE_ROBE", 4, 3 }
    local A = loadAdvisor(db, shipped)
    check("advisor: own item wins over shipped", A.Item(1)[1], 45)
    check("advisor: own item wins even when shipped only", A.Item(2)[1], 31)
    check("advisor: Best uses the winning record", ids(A.Best("chest", "WARRIOR", 40)), "1,2,3,4,12")
end

for name, shipped in pairs({
    missing = false,
    garbage = "junk",
    ["garbage fields"] = { items = "x", loot = 5, kills = true, corpses = {}, names = 7 },
    ["garbage records"] = { items = { [50] = "bad", [51] = { 1 }, x = { 1, 1, 1, "INVTYPE_CHEST", 4, 1 } },
                            loot = { "bad", { "x" }, { 50 }, { 50, "c" } } },
    empty = {},
}) do
    local db = gearData()
    local A = loadAdvisor(db, shipped)
    check("advisor: " .. name .. " shipped List uses own data", ids(A.List(nil, "WARRIOR", 40)), "11,13,1,3,15,7,5")
    check("advisor: " .. name .. " shipped List sourced", tostring(A.List("chest", "WARRIOR", 40)[2].sourced), "true")
    check("advisor: " .. name .. " shipped data uses own data", ids(A.Best("chest", "WARRIOR", 40)), "1,3")
    check("advisor: " .. name .. " shipped item is unknown", A.Item(2), nil)
    check("advisor: " .. name .. " shipped Sources", #A.Sources(1), 1)
    check("advisor: " .. name .. " shipped Rank", A.Rank(1, "WARRIOR", 40).rank, 1)
    check("advisor: " .. name .. " shipped malformed rows are no source", A.HasSource(50), false)
end

do
    local A = loadAdvisor({ schemaVersion = 4, items = "new format", loot = 4 }, select(2, gearData()))
    check("advisor: newer own db is ignored", ids(A.Best("chest", "WARRIOR", 40)), "4,2,12")
    check("advisor: newer own db Sources", #A.Sources(2), 1)
end

do
    local A = loadAdvisor(nil, nil)
    check("advisor: no data at all", ids(A.Best("chest", "WARRIOR", 40)), "")
    check("advisor: no data Sources", #A.Sources(1), 0)
    check("advisor: no data List", ids(A.List(nil, "WARRIOR", 40)), "")
end

-- Sources: own + shipped merged by max (decision 13), rate per npc (decision 16).
do
    local db = {
        schemaVersion = 3,
        npcs = { [448] = "Hogger" },
        loot = {
            ["4:c:448:1429"] = { item = 4, kind = "c", id = 448, map = 1429, count = 3, coords = { { 1, 1 } } },
            ["4:c:448:12"] = { item = 4, kind = "c", id = 448, map = 12, count = 2 },
            ["4:c:449:1429"] = { item = 4, kind = "c", id = 449, map = 1429, count = 2, coords = { { 7, 7 } } },
            ["5:c:448:1429"] = { item = 5, kind = "c", id = 448, map = 1429, count = 3 },
            ["6:c:448:1429"] = { item = 6, kind = "c", id = 448, map = 1429, count = 9 },
        },
        kills = { [448] = 4 },
        corpses = { [449] = 3 },
    }
    local shipped = {
        loot = {
            { 4, "c", 448, 1429, 5, 100, 900, 200, 800 },
            { 4, "c", 449, 1429, 1, 300, 300 },
            { 4, "o", 77, 0, 4 },
        },
        kills = { [448] = 10 },
        corpses = { [449] = 2 },
        names = { enUS = { [448] = "Shipped Hogger", [449] = "Wolf", [77] = "Chest" }, zhTW = { [449] = "狼" } },
    }
    local env = { C_Map = { GetMapInfo = function(map)
        return map == 1429 and { name = "Elwynn Forest" } or nil
    end } }
    local A = loadAdvisor(db, shipped, env)
    local rows = A.Sources(4)
    local function row(i)
        local s = rows[i]
        return ("%s %d %d %d %s %s %s %s"):format(s.kind, s.id, s.map, s.count, tostring(s.name), tostring(s.mapName),
            tostring(s.rate), tostring(s.rateBasis))
    end
    check("sources: four merged rows", #rows, 4)
    check("sources: max count, shipped kills basis", row(1), "c 448 1429 5 Hogger Elwynn Forest 0.5 kill")
    check("sources: object row has no rate or name", row(2), "o 77 0 4 nil nil nil nil")
    check("sources: own-only map shares the npc rate", row(3), "c 448 12 2 Hogger nil 0.5 kill")
    check("sources: own corpse basis wins with the larger count", row(4),
        "c 449 1429 2 Wolf Elwynn Forest " .. tostring(2 / 3) .. " corpse")
    check("sources: coords from the larger count", rows[1].coords[2][1], 200)
    check("sources: own coords when own count is larger", rows[4].coords[1][1], 7)
    check("sources: no coords is an empty list", #rows[3].coords, 0)
    check("sources: unknown item", #A.Sources(999), 0)
    check("sources: a dataset without drops gives no rate", A.Sources(5)[1].rate, 0.75)
    check("sources: a rate over 100% is no rate", tostring(A.Sources(6)[1].rate), "nil")
    check("advisor: MapName of map 0", A.MapName(0), nil)
    check("advisor: MapName of an unknown map", A.MapName(5), nil)
end

-- Fishing label (unit 2): object 35591 is named, other objects are not.
for locale, label in pairs({ enUS = "Fishing", zhTW = "釣魚" }) do
    local shipped = { loot = { { 4, "o", 35591, 1429, 3 }, { 4, "o", 77, 1429, 1 } } }
    local A = loadWithDB(nil, locale, { shipped = shipped }).Advisor
    local rows = A.Sources(4)
    check(locale .. " sources: fishing object is named", rows[1].id .. " " .. tostring(rows[1].name), "35591 " .. label)
    check(locale .. " sources: fishing has no rate", tostring(rows[1].rate), "nil")
    check(locale .. " sources: other objects stay unnamed", rows[2].id .. " " .. tostring(rows[2].name), "77 nil")
end

do
    local db = {
        schemaVersion = 3,
        loot = {
            ["4:c:448:1429"] = { item = 4, kind = "c", id = 448, map = 1429, count = 1 },
            ["4:c:449:1429"] = { item = 4, kind = "c", id = 449, map = 1429, count = 1 },
            ["4:c:451:1429"] = { item = 4, kind = "c", id = 451, map = 1429, count = 1 },
        },
        kills = { [448] = 2, [452] = 7 },
        corpses = { [449] = 4, [451] = 2 },
    }
    local shipped = {
        loot = { { 4, "c", 448, 1429, 3 }, { 4, "c", 449, 1429, 2 }, { 4, "c", 450, 1429, 1 },
                 { 4, "c", 451, 1429, 1 }, { 4, "c", 452, 1429, 1 } },
        kills = { [451] = 5 },
        corpses = { [448] = 50, [449] = 4, [452] = 2 },
        names = { zhTW = { [449] = "狼" } },
    }
    local A = loadWithDB(db, "zhTW", { shipped = shipped }).Advisor
    local rows = A.Sources(4)
    check("sources: own kills beat larger shipped corpses", rows[1].rateBasis .. " " .. rows[1].rate, "kill 0.5")
    check("sources: corpse tie goes to shipped", rows[2].rateBasis .. " " .. rows[2].rate, "corpse 0.5")
    check("sources: shipped name in the client locale", rows[2].name, "狼")
    check("sources: no denominator, no rate", tostring(rows[3].rate) .. " " .. tostring(rows[3].rateBasis),
        "nil nil")
    check("sources: unnamed npc", rows[3].name, nil)
    check("sources: shipped kills beat own corpses", rows[4].id .. " " .. rows[4].rateBasis .. " " .. rows[4].rate,
        "451 kill 0.2")
    check("sources: own kills without own drops are ignored",
        rows[5].id .. " " .. rows[5].rateBasis .. " " .. rows[5].rate, "452 corpse 0.5")
end

-- Commands: gear, rank, export (units 5 and 6).

-- A secret value as the client hands it out: comparing, concatenating or indexing it raises. Lua never calls __eq
-- against nil, so `secret == nil` cannot be trapped here; code must ask issecretvalue first.
local SECRET_MT = {}
for _, event in ipairs({ "__eq", "__lt", "__le", "__concat", "__index", "__len", "__call" }) do
    SECRET_MT[event] = function()
        error("secret value used")
    end
end
local function secret()
    return setmetatable({}, SECRET_MT)
end

-- Builds the link Commands makes for an uncached item.
local function built(id, hex, name)
    return ("|cff%s|Hitem:%d::::::::::::::|h[%s]|h|r"):format(hex, id, name or ("item #" .. id))
end

-- Loads gearData() (or db, shipped) with a stubbed player: ctx.class/className/level for UnitClass/UnitLevel,
-- ctx.equipped[invSlot] = link, ctx.cache[id] = { name, link, quality, ilvl } for C_Item.GetItemInfo, ctx.combat,
-- ctx.secret values hidden by issecretvalue, ctx.instant[id] / ctx.icons[id] for C_Item.GetItemInfoInstant,
-- ctx.faction for UnitFactionGroup (default "Alliance").
-- C_Item.IsItemDataCachedByID is true for ids in ctx.cache; ctx.infoCalls[id] counts GetItemInfo calls.
-- opts.env adds globals, opts.widgets goes to loadAddon. Returns ctx with addon, printed, env, fire, frame, run(msg).
local function loadGear(locale, db, shipped, opts)
    if not db then
        db, shipped = gearData()
    end
    local ctx = { class = "WARRIOR", className = "Warrior", level = 40, faction = "Alliance", equipped = {}, cache = {},
                  combat = false, requested = {}, instant = {}, icons = {}, infoCalls = {} }
    local env = {
        UnitClass = function(unit)
            assert(unit == "player")
            return ctx.className, ctx.class
        end,
        UnitLevel = function()
            return ctx.level
        end,
        UnitFactionGroup = function(unit)
            assert(unit == "player")
            return ctx.faction
        end,
        InCombatLockdown = function()
            return ctx.combat
        end,
        GetInventoryItemLink = function(unit, slot)
            assert(unit == "player")
            return ctx.equipped[slot]
        end,
        C_Item = {
            IsItemDataCachedByID = function(id)
                return ctx.cache[id] ~= nil
            end,
            GetItemInfo = function(id)
                ctx.infoCalls[id] = (ctx.infoCalls[id] or 0) + 1
                local c = ctx.cache[id]
                if c then
                    return c[1], c[2], c[3], c[4]
                end
            end,
            RequestLoadItemDataByID = function(id)
                ctx.requested[id] = true
            end,
            GetItemInfoInstant = function(id)
                return id, nil, nil, ctx.instant[id], ctx.icons[id]
            end,
        },
        C_Map = { GetMapInfo = function(map)
            return map == 1429 and { name = "Elwynn Forest" } or nil
        end },
        issecretvalue = function(v)
            return getmetatable(v) == SECRET_MT
        end,
        ReloadUI = function()
            ctx.reloaded = true
        end,
    }
    for k, v in pairs(opts and opts.env or {}) do
        env[k] = v
    end
    local loadOpts = { shipped = shipped, env = env, blockCLEU = opts and opts.blockCLEU,
                       widgets = opts and opts.widgets }
    ctx.addon, ctx.printed, ctx.env, ctx.fire, ctx.frame = loadWithDB(db, locale or "enUS", loadOpts)
    function ctx.run(msg)
        return run(ctx.addon, ctx.printed, msg)
    end
    function ctx.since(from)
        return linesSince(ctx.printed, from)
    end
    return ctx
end

local BLUE, GREEN = "0070dd", "1eff00"

do
    local ctx = loadGear()
    for _, msg in ipairs({ "gear head foo", "gear head all extra", "gear all all all", "export now" }) do
        check(("%q prints usage"):format(msg), ctx.run(msg)[1], "Tandem commands:")
    end
    for _, msg in ipairs({ "gear shirt", "gear foo all", "gear all all" }) do
        check(("%q names an unknown slot"):format(msg), ctx.run(msg)[1]:match("^Tandem: unknown slot (%S+);"),
            (msg:match("^gear (%S+)")))
    end
    check("unknown slot lists the slots", ctx.run("gear shirt")[1], "Tandem: unknown slot shirt; use one of: "
        .. "head neck shoulder back chest wrist hands waist legs feet finger trinket mainhand offhand twohand ranged")
    for _, msg in ipairs({ "rank", "rank abc", "rank 1 2", "rank 0x10" }) do
        check(("%q prints rank usage"):format(msg), ctx.run(msg)[1], "Tandem: usage /tandem rank <item link|id>")
    end

    local out = ctx.run("gear")
    check("gear overview header", out[1], "Best known gear for level 40 Warrior:")
    check("gear overview empty slot", out[2], "Head: none known")
    check("gear overview chest is a link and an upgrade over nothing", out[6],
        "Chest: " .. built(1, BLUE) .. ", ilvl 45 (upgrade)")
    check("gear overview off hand", out[15], "Off hand: " .. built(7, GREEN) .. ", ilvl 25 (upgrade)")
    check("gear overview skips a sourceless two-hander", out[16], "Two-hand: none known")
    check("gear overview footer", out[18], "Ranked by item level, then quality; stats are not considered")
    check("gear overview line count", #out, 18)
    check("gear asks the client for uncached items", ctx.requested[1], true)
    check("gear overview all shows sourceless items, marked", ctx.run("gear all")[16],
        "Two-hand: " .. built(15, GREEN) .. ", ilvl 30 (upgrade) (no known source)")
    check("GEAR overview is case-insensitive", ctx.run("GEAR")[1], "Best known gear for level 40 Warrior:")
end

do
    local ctx = loadGear()
    ctx.equipped[5] = "|cff0070dd|Hitem:3::::::::::::::|h[Leather Vest]|h|r"
    ctx.cache[1] = { "Plate Chest", "|cffa335ee|Hitem:1::::|h[Plate Chest]|h|r", 4, 45 }
    local plate = "|cffa335ee|Hitem:1::::|h[Plate Chest]|h|r"
    local out = ctx.run("gear chest")
    check("gear chest header", out[1], "Best Chest for level 40 Warrior:")
    check("gear chest equipped line", out[2], "Equipped: " .. built(3, BLUE) .. ", ilvl 30")
    check("gear chest uses the cached client link", out[3], "1. " .. plate .. ", ilvl 45, level 40 (upgrade)")
    check("gear chest does not request a cached item", ctx.requested[1], nil)
    check("gear chest marks the equipped item", out[4], "2. " .. built(3, BLUE) .. ", ilvl 30, level 25 (equipped)")
    check("gear chest same ilvl is no upgrade", out[5], "3. " .. built(4, BLUE) .. ", ilvl 30, level 25")
    check("gear chest lower ilvl is no upgrade", out[7], "5. " .. built(12, GREEN) .. ", ilvl 20, level 10")
    check("gear chest footer", out[8], "Ranked by item level, then quality; stats are not considered")
    check("gear chest line count", #out, 8)

    ctx.equipped[5] = "|cff0070dd|Hitem:777::::|h[Unknown]|h|r"
    ctx.cache[777] = { "Unknown", ctx.equipped[5], 2, 40 }
    out = ctx.run("gear chest")
    check("gear chest ilvl of an uncached equipped item from the client", out[2],
        "Equipped: " .. ctx.equipped[5] .. ", ilvl 40")
    check("gear chest upgrade over the client ilvl", out[3], "1. " .. plate .. ", ilvl 45, level 40 (upgrade)")
    check("gear chest no upgrade below the client ilvl", out[4], "2. " .. built(3, BLUE) .. ", ilvl 30, level 25")

    ctx.cache[777] = nil
    out = ctx.run("gear chest")
    check("gear chest unknown equipped ilvl", out[2], "Equipped: " .. built(777, "ffffff") .. ", ilvl ?")
    check("gear chest unknown equipped ilvl gives no marks", out[3], "1. " .. plate .. ", ilvl 45, level 40")

    ctx.equipped[5] = secret()
    out = ctx.run("gear chest")
    check("gear chest secret equipped link gives no equipped line and no marks", out[2],
        "1. " .. plate .. ", ilvl 45, level 40")

    ctx.level, ctx.class, ctx.className = 60, "MAGE", "Mage"
    ctx.equipped[5] = nil
    out = ctx.run("gear chest")
    check("gear chest hides sourceless items", out[3], "1. " .. built(4, BLUE) .. ", ilvl 30, level 25 (upgrade)")
    check("gear chest hides sourceless items count", #out, 4)
    out = ctx.run("gear chest all")
    check("gear chest all shows sourceless items, marked", out[3],
        "1. " .. built(11, "ff8000") .. ", ilvl 99, level 1 (upgrade) (no known source)")
    check("gear chest all keeps sourced items", out[4], "2. " .. built(4, BLUE) .. ", ilvl 30, level 25 (upgrade)")
    out = ctx.run("gear twohand")
    check("gear with nothing usable", out[3], "No known Two-hand you can use")
end

do
    local db, shipped = gearData()
    db.items[21] = { 15, 10, 2, "INVTYPE_FINGER", 4, 0 }
    db.loot["21:c:448:1429"] = { item = 21, kind = "c", id = 448, map = 1429, count = 1 }
    local ctx = loadGear("enUS", db, shipped)
    ctx.equipped[11] = "|Hitem:778:|h"
    ctx.cache[778] = { "Ring", "|Hitem:778:|h", 2, 20 }
    local out = ctx.run("gear finger")
    check("gear finger lists both rings", out[2] .. " / " .. out[3],
        "Equipped: |Hitem:778:|h, ilvl 20 / Equipped: nothing")
    check("gear finger compares with the empty ring slot", out[4],
        "1. " .. built(21, GREEN) .. ", ilvl 15, level 10 (upgrade)")
    ctx.equipped[12] = "|Hitem:778:|h"
    check("gear finger compares with the lower ring", ctx.run("gear finger")[4],
        "1. " .. built(21, GREEN) .. ", ilvl 15, level 10")
end

do
    local db, shipped = gearData()
    db.npcs = { [448] = "Hogger" }
    db.kills = { [448] = 4 }
    db.corpses = { [449] = 2 }
    db.loot["1:c:449:0"] = { item = 1, kind = "c", id = 449, map = 0, count = 1 }
    db.loot["1:?:0:0"] = { item = 1, kind = "?", id = 0, map = 0, count = 1 }
    for npc = 600, 606 do
        shipped.loot[#shipped.loot + 1] = { 4, "c", npc, 1429, 1 }
    end
    local ctx = loadGear("enUS", db, shipped)
    local out = ctx.run("rank 1")
    check("rank by id", out[1], built(1, BLUE) .. " (upgrade): rank 1 of 5 for Chest")
    check("rank unknown source", out[2], "  unknown source, unknown map - drops: 1")
    check("rank source per kill", out[3], "  Hogger, Elwynn Forest - drops: 1, 25.0% per kill")
    check("rank source per looted corpse", out[4],
        "  npc #449, unknown map - drops: 1, 50.0% per looted corpse (upper bound)")
    check("rank footer", out[5], "Ranked by item level, then quality; stats are not considered")
    check("rank line count", #out, 5)

    out = ctx.run("rank |cff0070dd|Hitem:2::::::::::::::|h[Mail Robe]|h|r")
    check("rank by link", out[1], built(2, GREEN) .. " (upgrade): rank 4 of 5 for Chest")
    check("rank shipped source without a name", out[2], "  npc #500, Elwynn Forest - drops: 1")
    check("rank by a link inside text", ctx.run("rank this |Hitem:2:0|h one")[1], out[1])

    out = ctx.run("rank 3")
    check("rank object source", out[2], "  object #77, Elwynn Forest - drops: 1")
    out = ctx.run("rank 4")
    check("rank lists a few sources", out[7], "  and 3 more sources")
    check("rank source rows", #out, 8)

    ctx.equipped[5] = "|Hitem:1:|h"
    check("rank marks the equipped item", ctx.run("rank 1")[1],
        built(1, BLUE) .. " (equipped): rank 1 of 5 for Chest")

    out = ctx.run("rank 11")
    check("rank sourceless item", out[1], built(11, "ff8000") .. " (upgrade): rank 1 of 6 for Chest")
    check("rank sourceless item says so", out[2], "  no known source")
    out = ctx.run("rank 9")
    check("rank unranked slot", out[1], built(9, "ffffff") .. " does not go in a ranked slot")
    check("rank unranked slot has no footer", #out, 2)
    check("rank unknown item", ctx.run("rank 999")[1], "Tandem: item 999 is not known; scan or loot it first")

    ctx.equipped[5] = nil
    ctx.level = 30
    out = ctx.run("rank 1")
    check("rank too low gives no upgrade mark", out[1], built(1, BLUE) .. ": rank 1 of 5 for Chest")
    check("rank too low", out[2], "  you cannot use it: level 40 required")
    ctx.class, ctx.className, ctx.level = "MAGE", "Mage", 60
    check("rank wrong class", ctx.run("rank 1")[2], "  your class cannot use it")
end

do
    local ctx = loadGear()
    ctx.combat = true
    for _, msg in ipairs({ "gear", "gear chest", "gear shirt", "gear a b c", "rank 1", "rank", "export",
                           "export now", "GEAR" }) do
        local out = ctx.run(msg)
        check(("%q refuses in combat"):format(msg), out[1], "Tandem: not available in combat")
        check(("%q prints only the refusal"):format(msg), #out, 1)
    end
    check("count still works in combat", ctx.run("count")[1], "Tandem: 8 known items, 0 non-equippable")
end

for name, setup in pairs({
    ["missing UnitClass"] = function(ctx)
        ctx.env.UnitClass = nil
    end,
    ["missing UnitLevel"] = function(ctx)
        ctx.env.UnitLevel = nil
    end,
    ["nil class"] = function(ctx)
        ctx.class = nil
    end,
    ["nil level"] = function(ctx)
        ctx.level = nil
    end,
    ["secret class"] = function(ctx)
        ctx.class = secret()
    end,
    ["secret level"] = function(ctx)
        ctx.level = secret()
    end,
}) do
    local ctx = loadGear()
    setup(ctx)
    for _, msg in ipairs({ "gear", "gear chest", "rank 1" }) do
        local out = ctx.run(msg)
        check(("%s: %q explains"):format(name, msg), out[1],
            "Tandem: your class or level is not known yet; try again in a moment")
        check(("%s: %q prints one line"):format(name, msg), #out, 1)
    end
end

do
    local ctx = loadGear()
    ctx.className = secret()
    check("secret class name falls back to the class file", ctx.run("gear")[1],
        "Best known gear for level 40 WARRIOR:")
end

do
    local db, shipped = gearData()
    db.npcs = { [448] = "Hogger", [449] = "Wolf" }
    db.kills = { [448] = 3, [450] = 1 }
    db.corpses = { [448] = 2 }
    local ctx = loadGear("enUS", db, shipped)
    ctx.addon.Store.AddLoot(5, "c", 448, 1429)
    local out = ctx.run("export")
    check("export counts", out[1], "Tandem export: 3 loot entries, 2 npc names, 8 items, 4 kills, 2 looted corpses")
    check("export unsaved", out[2], "Unsaved records: 1 (saved on /reload or logout)")
    check("export next steps", out[3], "To contribute: type /reload, then run make import")
    check("export line count", #out, 3)
    check("export never reloads", ctx.reloaded, nil)

    out = ctx.run("count")
    check("count kills and corpses", out[4], "Kills: 4, looted corpses: 2")
    check("count rate basis without the combat log", out[5],
        "Drop rates use looted corpses: kill counting is unavailable")
end

do
    local ctx = loadGear("enUS", { schemaVersion = 4, items = "new format" }, nil)
    local out = ctx.run("export")
    check("export on a newer db", out[1],
        "Tandem export: 0 loot entries, 0 npc names, 0 items, 0 kills, 0 looted corpses")
    check("export on a newer db says read-only", out[3], "Recording is off: saved data uses a newer schema")
    check("export on a newer db next steps", out[4], "To contribute: type /reload, then run make import")
end

do
    local cleu = function() end
    local on = loadGear("enUS", nil, nil, { env = { CombatLogGetCurrentEventInfo = cleu } })
    check("count rate basis with the combat log", on.run("count")[5],
        "Drop rates use kills where counted, else looted corpses")
    local blocked = loadGear("enUS", nil, nil, { env = { CombatLogGetCurrentEventInfo = cleu }, blockCLEU = true })
    check("count rate basis with a blocked combat log", blocked.run("count")[5],
        "Drop rates use looted corpses: kill counting is blocked")
end

do
    local db, shipped = gearData()
    db.npcs = { [448] = "霍格" }
    db.kills = { [448] = 4 }
    db.corpses = { [449] = 2 }
    db.loot["1:c:449:0"] = { item = 1, kind = "c", id = 449, map = 0, count = 1 }
    local ctx = loadGear("zhTW", db, shipped)
    ctx.className = "戰士"
    local out = ctx.run("gear chest")
    check("zhTW gear chest header", out[1], "最佳胸部（40 級戰士）：")
    check("zhTW gear chest equipped", out[2], "已裝備：無")
    check("zhTW gear chest row", out[3], "1. " .. built(1, BLUE, "物品 #1") .. "，物品等級 45，需求等級 40（升級）")
    check("zhTW gear footer", out[#out], "依物品等級、再依品質排名；未考慮屬性")
    out = ctx.run("gear")
    check("zhTW gear overview header", out[1], "40 級戰士的最佳已知裝備：")
    check("zhTW gear overview none", out[2], "頭部：無已知物品")
    check("zhTW gear overview all", ctx.run("gear all")[16],
        "雙手：" .. built(15, GREEN, "物品 #15") .. "，物品等級 30（升級）（來源未知）")
    out = ctx.run("rank 1")
    check("zhTW rank", out[1], built(1, BLUE, "物品 #1") .. "（升級）：排名第 1／5（胸部）")
    check("zhTW rank per kill", out[2], "  霍格，Elwynn Forest：掉落 1 次，每次擊殺 25.0%")
    check("zhTW rank per corpse", out[3], "  NPC #449，未知地圖：掉落 1 次，每具拾取屍體 50.0%（上限）")
    check("zhTW rank sourceless", ctx.run("rank 11")[2], "  來源未知")
    check("zhTW rank unranked slot", ctx.run("rank 9")[1], built(9, "ffffff", "物品 #9") .. " 不屬於可排名的部位")
    ctx.level = 30
    check("zhTW rank too low", ctx.run("rank 1")[2], "  你無法使用：需要等級 40")
    check("zhTW unknown item", ctx.run("rank 999")[1], "Tandem：未知的物品 999；請先掃描或拾取")
    check("zhTW rank usage", ctx.run("rank")[1], "Tandem：用法 /tandem rank <物品連結|id>")
    check("zhTW unknown slot", ctx.run("gear shirt")[1]:find("Tandem：未知的部位 shirt；", 1, true), 1)
    out = ctx.run("export")
    check("zhTW export", out[1], "Tandem 匯出：掉落紀錄 3 筆，NPC 名稱 1 個，物品 8 件，擊殺 4 次，拾取屍體 2 具")
    check("zhTW export next steps", out[3], "要貢獻資料：輸入 /reload，然後執行 make import")
    out = ctx.run("count")
    check("zhTW count kills", out[4], "擊殺：4 次，拾取屍體：2 具")
    check("zhTW count rate basis", out[5], "掉落率使用拾取屍體數：擊殺計數無法使用")
    check("zhTW usage lists gear", ctx.run("help")[6], "  /tandem gear [<部位>] [all] - 你能使用的最佳已知裝備")
    ctx.combat = true
    check("zhTW combat refusal", ctx.run("export")[1], "Tandem：戰鬥中無法使用")
    ctx.combat, ctx.level, ctx.class = false, 40, nil
    check("zhTW unknown class", ctx.run("gear")[1], "Tandem：尚未取得你的職業或等級，請稍後再試")
end

do
    local ctx = loadGear()
    ctx.equipped[16] = "|Hitem:15:|h"
    local out = ctx.run("gear offhand")
    check("gear offhand behind a cached two-hander has no upgrade mark", out[3],
        "1. " .. built(7, GREEN) .. ", ilvl 25, level 20")
    ctx.equipped[16] = "|Hitem:780:|h"
    ctx.instant[780] = "INVTYPE_2HWEAPON"
    check("gear offhand behind a client two-hander has no upgrade mark", ctx.run("gear offhand")[3],
        "1. " .. built(7, GREEN) .. ", ilvl 25, level 20")
    ctx.equipped[16] = "|Hitem:7:|h"
    check("gear offhand behind a one-hander is an upgrade over nothing", ctx.run("gear offhand")[3],
        "1. " .. built(7, GREEN) .. ", ilvl 25, level 20 (upgrade)")
    ctx.equipped[16] = secret()
    check("gear offhand behind a secret main hand has no upgrade mark", ctx.run("gear offhand")[3],
        "1. " .. built(7, GREEN) .. ", ilvl 25, level 20")

    ctx.equipped[16] = "|Hitem:7:|h"
    ctx.equipped[17] = "|Hitem:779:|h"
    ctx.cache[779] = { "Big Shield", "|Hitem:779:|h", 4, 60 }
    out = ctx.run("gear twohand all")
    check("gear twohand compares with the main hand only", out[3],
        "1. " .. built(15, GREEN) .. ", ilvl 30, level 20 (upgrade) (no known source)")
    check("gear twohand lists only the main hand", out[2], "Equipped: " .. built(7, GREEN) .. ", ilvl 25")
end

do
    local db, shipped = gearData()
    db.npcs = { [448] = "Hog|cffff0000ger|r" }
    local env = { C_Map = { GetMapInfo = function()
        return { name = "Elw|Hitem:1|hynn" }
    end } }
    local ctx = loadGear("enUS", db, shipped, { env = env })
    check("rank escapes the npc and map names", ctx.run("rank 1")[2],
        "  Hog||cffff0000ger||r, Elw||Hitem:1||hynn - drops: 1")
end

for locale, want in pairs({
    enUS = { "  Fishing, Elwynn Forest - drops: 3", "  npc #500, Elwynn Forest - drops: 1" },
    zhTW = { "  釣魚，Elwynn Forest：掉落 3 次", "  NPC #500，Elwynn Forest：掉落 1 次" },
}) do
    local db, shipped = gearData()
    shipped.loot[#shipped.loot + 1] = { 2, "o", 35591, 1429, 3 }
    local out = loadGear(locale, db, shipped).run("rank 2")
    check(locale .. " rank fishing source", out[2], want[1])
    check(locale .. " rank keeps the npc source", out[3], want[2])
end

-- Store: browse window position (decision 8).

do
    local ui = { window = { point = "TOPLEFT", x = 120.5, y = -40 } }
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = ui })
    local w = env.TandemDB.ui.window
    check("ui: a valid position is kept", w.point .. " " .. w.x .. " " .. w.y, "TOPLEFT 120.5 -40")
    check("ui: a valid position prints only the load line", #printed, 1)
    check("ui: UIPosition returns it", addon.Store.UIPosition().x, 120.5)
    check("ui: a position saved without relativePoint uses point", addon.Store.UIPosition().relativePoint,
        "TOPLEFT")
    check("ui: SetUIPosition saves", addon.Store.SetUIPosition("BOTTOMRIGHT", "TOPLEFT", -3, 4), true)
    w = env.TandemDB.ui.window
    check("ui: SetUIPosition writes TandemDB.ui.window", w.point .. " " .. w.relativePoint .. " " .. w.x .. " " .. w.y,
        "BOTTOMRIGHT TOPLEFT -3 4")
    check("ui: SetUIPosition writes only the window", env.TandemDB.ui.minimap, nil)
    check("ui: SetUIPosition is not a record", addon.Store.unsaved, 0)
    check("ui: SetUIPosition without relativePoint uses point", addon.Store.SetUIPosition("TOP", nil, 1, 2)
        and env.TandemDB.ui.window.relativePoint, "TOP")
    addon.Store.SetUIPosition("BOTTOMRIGHT", "TOPLEFT", -3, 4)
    for name, args in pairs({
        ["unknown point"] = { "MIDDLE", "TOP", 1, 1 }, ["nil point"] = { nil, "TOP", 1, 1 },
        ["unknown relativePoint"] = { "TOP", "MIDDLE", 1, 1 }, ["number relativePoint"] = { "TOP", 5, 1, 1 },
        ["NaN x"] = { "TOP", "TOP", 0 / 0, 1 }, ["huge y"] = { "TOP", "TOP", 1, math.huge },
        ["far x"] = { "TOP", "TOP", 10001, 1 }, ["string y"] = { "TOP", "TOP", 1, "2" },
    }) do
        check("ui: SetUIPosition rejects " .. name,
            addon.Store.SetUIPosition(args[1], args[2], args[3], args[4]), false)
    end
    check("ui: a rejected position keeps the old one", env.TandemDB.ui.window.point, "BOTTOMRIGHT")
end

do
    local _, _, env = loadWithDB({ schemaVersion = 3 })
    check("ui: a fresh db has no position", env.TandemDB.ui, nil)
    check("ui: a db without ui is current", isCurrent(env.TandemDB), true)
end

for name, ui in pairs({
    ["not a table"] = "left", ["a window that is not a table"] = { window = "left" },
    ["unknown point"] = { window = { point = "MIDDLE", x = 0, y = 0 } },
    ["far x"] = { window = { point = "TOP", x = -10001, y = 0 } },
    ["NaN y"] = { window = { point = "TOP", x = 0, y = 0 / 0 } }, ["missing y"] = { window = { point = "TOP", x = 0 } },
    ["unknown relativePoint"] = { window = { point = "TOP", relativePoint = "UP", x = 0, y = 0 } },
}) do
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = ui })
    check("ui: drops a position with " .. name, env.TandemDB.ui, nil)
    check("ui: counts a position with " .. name .. " as dropped", printed[2], "Tandem: dropped 1 invalid saved entries")
    check("ui: UIPosition after dropping " .. name, addon.Store.UIPosition(), nil)
end

do
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = { point = "TOP", x = 1, y = 2, extra = true } })
    check("ui: keys outside window and minimap are not kept", env.TandemDB.ui, nil)
    check("ui: keys outside window and minimap are not counted", #printed, 1)
    check("ui: no position from top-level keys", addon.Store.UIPosition(), nil)
end

do
    local addon = loadWithDB({ schemaVersion = 4, ui = { window = { point = "TOP", x = 5, y = 6 } } })
    check("ui: a newer db still gives a valid position", addon.Store.UIPosition().y, 6)
    check("ui: a newer db is not written", addon.Store.SetUIPosition("TOP", "TOP", 1, 1), false)
    check("ui: a newer db keeps its position", addon.Store.db.ui.window.x, 5)
    addon = loadWithDB({ schemaVersion = 4, ui = { window = { point = "TOP", x = "5", y = 6 } } })
    check("ui: a newer db with a bad position gives none", addon.Store.UIPosition(), nil)
    addon = loadWithDB({ schemaVersion = 4, ui = "junk" })
    check("ui: a newer db with a junk ui gives no position", addon.Store.UIPosition(), nil)
    check("ui: a newer db with a junk ui gives no angle", addon.Store.MinimapAngle(), nil)
end

-- Browse window (unit 5) under fake widgets.

-- A fake region or frame. Methods (capitalised keys) that are not stubbed are no-ops; lower-case fields stay nil,
-- so the addon's own fields on a widget behave as on a real frame.
local function noop() end
local WIDGET = {}
WIDGET.__index = function(_, key)
    if WIDGET[key] then
        return WIDGET[key]
    end
    if type(key) == "string" and key:match("^%u") then
        return noop
    end
end
-- Show and Hide run OnShow / OnHide when the state changes, as a real frame does.
function WIDGET.Show(w)
    local was = w.shown
    w.shown = true
    if not was and w.scripts.OnShow then
        w.scripts.OnShow(w)
    end
end
function WIDGET.Hide(w)
    local was = w.shown
    w.shown = false
    if was and w.scripts.OnHide then
        w.scripts.OnHide(w)
    end
end
function WIDGET.SetFocus(w) w.focused = true end
function WIDGET.ClearFocus(w) w.focused = false end
function WIDGET.IsShown(w) return w.shown end
function WIDGET.SetShown(w, shown)
    if shown then
        w:Show()
    else
        w:Hide()
    end
end
function WIDGET.SetScript(w, name, fn) w.scripts[name] = fn end
function WIDGET.GetScript(w, name) return w.scripts[name] end
function WIDGET.SetText(w, text) w.text = text end
function WIDGET.GetText(w) return w.text end
function WIDGET.SetTexture(w, texture) w.texture = texture end
function WIDGET.SetChecked(w, checked) w.checked = checked end
function WIDGET.GetChecked(w) return w.checked end
function WIDGET.SetAlpha(w, alpha) w.alpha = alpha end
function WIDGET.SetTitle(w, title) w.title = title end
function WIDGET.ClearAllPoints(w) w.points = {} end
function WIDGET.SetPoint(w, ...) w.points[#w.points + 1] = { ... } end
function WIDGET.GetPoint(w)
    local p = w.points[1] or {}
    return p[1], p[2], p[3], p[4], p[5]
end
function WIDGET.SetupMenu(w, generator) w.generator = generator end
function WIDGET.SetDontSavePosition(w, v) w.dontSave = v end
function WIDGET.SetUserPlaced(w, v) w.userPlaced = v end
function WIDGET.StopMovingOrSizing(w) w.userPlaced, w.sizing = true, nil end
function WIDGET.SetSize(w, width, height) w.width, w.height = width, height end
function WIDGET.GetSize(w) return w.width, w.height end
function WIDGET.SetResizable(w, v) w.resizable = v end
function WIDGET.SetResizeBounds(w, ...) w.bounds = { ... } end
function WIDGET.SetMinResize(w, ...) w.minResize = { ... } end
function WIDGET.SetMaxResize(w, ...) w.maxResize = { ... } end
function WIDGET.StartSizing(w, corner) w.sizing = corner end
function WIDGET.SetNormalTexture(w, t) w.normal = t end
function WIDGET.SetPushedTexture(w, t) w.pushed = t end
function WIDGET.SetHighlightTexture(w, t) w.highlight = t end
function WIDGET.SetEnabled(w, enabled) w.enabled = enabled end
function WIDGET.IsEnabled(w) return w.enabled end

local function newWidget(ui, kind, name, parent, template)
    local w = setmetatable({ ui = ui, kind = kind, name = name, parent = parent, template = template, shown = true,
                             scripts = {}, points = {}, buttons = {} }, WIDGET)
    ui.widgets[#ui.widgets + 1] = w
    return w
end

function WIDGET.CreateFontString(w) return newWidget(w.ui, "FontString", nil, w) end
function WIDGET.CreateTexture(w) return newWidget(w.ui, "Texture", nil, w) end
function WIDGET.SetDataProvider(w, provider)
    w.provider = provider
    for i, row in ipairs(provider.rows) do
        local b = w.buttons[i] or newWidget(w.ui, "Button", nil, w)
        w.buttons[i] = b
        w.view.initializer(b, row)
    end
end
function WIDGET.ForEachFrame(w, fn)
    for i, row in ipairs(w.provider.rows) do
        fn(w.buttons[i], row)
    end
end

-- Runs a dropdown's menu generator; returns its radios { text, isSelected, setSelected, data }.
local function radios(dropdown)
    local out = {}
    dropdown.generator(dropdown, { CreateRadio = function(_, text, isSelected, setSelected, data)
        out[#out + 1] = { text = text, isSelected = isSelected, setSelected = setSelected, data = data }
    end })
    return out
end

-- Loads gearData() (or db, shipped) with fake widgets. opts.failBars lists templates that fail to build;
-- opts.noInitList removes ScrollUtil.InitScrollBoxList, opts.noDontSave hides SetDontSavePosition, opts.noResize
-- hides SetResizable, opts.noResizeBounds hides SetResizeBounds, opts.env adds or replaces globals. Returns the
-- loadGear ctx; ctx.ui records widgets, timers (C_Timer.After), tickers (C_Timer.NewTicker), the tooltip item, owner
-- and lines and the scroll bar; ctx.win() returns the window once built.
-- ctx.cursor = { kind, id } is what GetCursorInfo returns; ClearCursor empties it and sets ctx.cleared.
local function loadBrowse(locale, db, shipped, opts)
    opts = opts or {}
    local ui = { widgets = {}, timers = {}, tickers = {}, tooltipLines = {} }
    local failBars = {}
    for _, t in ipairs(opts.failBars or {}) do
        failBars[t] = true
    end
    local function widgets(kind, name, parent, template)
        if failBars[template] then
            error("no template " .. template)
        end
        local w = newWidget(ui, kind, name, parent, template)
        if opts.noDontSave then
            w.SetDontSavePosition = false
        end
        if opts.noResize then
            w.SetResizable = false
        end
        if opts.noResizeBounds then
            w.SetResizeBounds = false
        end
        return w
    end
    local tooltip = newWidget({ widgets = {} }, "GameTooltip")
    function tooltip.SetOwner(_, owner, anchor)
        ui.tooltipOwner, ui.tooltipAnchor = owner, anchor
    end
    function tooltip.SetItemByID(_, id)
        ui.tooltip = id
    end
    function tooltip.AddLine(_, text)
        ui.tooltipLines[#ui.tooltipLines + 1] = text
    end
    local cursor = {}
    local env = {
        UIParent = { name = "UIParent" },
        UISpecialFrames = {},
        GameTooltip = tooltip,
        ButtonFrameTemplate_HideButtonBar = function(f)
            f.buttonBarHidden = true
        end,
        CreateDataProvider = function(rows)
            return { rows = rows }
        end,
        CreateScrollBoxListLinearView = function()
            return { SetElementExtent = noop, SetElementInitializer = function(self, kind, init)
                self.kind, self.initializer = kind, init
            end }
        end,
        ScrollUtil = {
            InitScrollBoxListWithScrollBar = function(box, bar, view)
                box.view, ui.bar = view, bar
            end,
        },
        C_Timer = {
            After = function(delay, fn)
                ui.timers[#ui.timers + 1] = { delay = delay, fn = fn }
            end,
            NewTicker = fakeTicker(ui.tickers),
        },
        GetTime = function()
            return 100
        end,
        time = function()
            return 1700000000
        end,
        GetCursorInfo = function()
            if cursor.ctx.cursor then
                return cursor.ctx.cursor[1], cursor.ctx.cursor[2]
            end
        end,
        ClearCursor = function()
            cursor.ctx.cursor, cursor.ctx.cleared = nil, true
        end,
    }
    if not opts.noInitList then
        env.ScrollUtil.InitScrollBoxList = function(box, view)
            box.view, ui.initList = view, true
        end
    end
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    local ctx = loadGear(locale, db, shipped, { env = env, widgets = widgets })
    cursor.ctx = ctx
    ctx.ui = ui
    function ctx.win()
        for _, w in ipairs(ui.widgets) do
            if w.name == "TandemBrowseFrame" then
                return w
            end
        end
    end
    -- Runs the queued timers.
    function ctx.tick()
        local timers = ui.timers
        ui.timers = {}
        for _, t in ipairs(timers) do
            t.fn()
        end
    end
    return ctx
end

local GREY = "|cff808080"

local function rowIDs(win)
    local out = {}
    for _, row in ipairs(win.box.provider.rows) do
        out[#out + 1] = tostring(row.id)
    end
    return table.concat(out, ",")
end

local function paneText(win)
    local out = { win.pane.header:GetText() }
    for _, fs in ipairs(win.pane.lines) do
        out[#out + 1] = fs:GetText()
    end
    return out
end

do
    local ctx = loadBrowse()
    check("browse: nothing is built before use", ctx.win(), nil)
    check("browse: no output on open", #ctx.run("browse"), 0)
    local win = ctx.win()
    check("browse: opens the window", win and win:IsShown(), true)
    check("browse: window template", win.template, "ButtonFrameTemplate")
    check("browse: window parent", win.parent, ctx.env.UIParent)
    check("browse: window title", win.title, "Tandem gear")
    check("browse: button bar hidden", win.buttonBarHidden, true)
    check("browse: position not saved by the client", win.dontSave, true)
    check("browse: escape closes it", ctx.env.UISpecialFrames[1], "TandemBrowseFrame")
    check("browse: centred without a saved position", win.points[1][1], "CENTER")
    check("browse: list view uses buttons", win.box.view.kind, "Button")
    check("browse: minimal scroll bar", ctx.ui.bar.template, "MinimalScrollBar")
    check("browse: all slots by default", rowIDs(win), "11,13,1,3,4,2,15,7,14,5,12")
    check("browse: count", win.count:GetText(), "11 items")
    check("browse: usable only by default", win.usable:GetChecked(), true)
    check("browse: no selection", paneText(win)[1], "Select an item to see where it drops")
    check("browse: no source lines without a selection", paneText(win)[2], "")
    ctx.run("browse")
    check("browse: toggles closed", win:IsShown(), false)
    ctx.run("browse")
    check("browse: toggles open again", win:IsShown(), true)
    check("browse: built once", ctx.win(), win)
    check("browse: escape registered once", #ctx.env.UISpecialFrames, 1)

    local menu = radios(win.dropdown)
    check("browse: dropdown template", win.dropdown.template, "WowStyle1DropdownTemplate")
    check("browse: dropdown has all slots and each slot", #menu, 17)
    check("browse: first radio is all slots", menu[1].text .. " " .. tostring(menu[1].data), "All slots nil")
    check("browse: second radio is head", menu[2].text .. " " .. menu[2].data, "Head head")
    check("browse: all slots is selected", menu[1].isSelected(menu[1].data), true)
    menu[6].setSelected(menu[6].data)
    check("browse: picking chest filters the rows", rowIDs(win), "11,1,3,4,2,12")
    check("browse: chest is selected", menu[6].isSelected(menu[6].data) and not menu[1].isSelected(menu[1].data),
        true)
    check("browse: count follows the filter", win.count:GetText(), "6 items")

    ctx.run("browse twohand")
    check("browse <slot> filters", rowIDs(win), "15")
    check("browse <slot> keeps it open", win:IsShown(), true)
    ctx.run("browse twohand")
    check("browse <slot> does not toggle", win:IsShown(), true)

    ctx.level = 30
    ctx.run("browse chest")
    check("browse: usable only drops items above the level", rowIDs(win), "11,3,4,2,12")
    win.usable:SetChecked(false)
    win.usable:GetScript("OnClick")(win.usable)
    check("browse: unchecking lists unusable items", rowIDs(win), "11,1,3,4,2,12")
    check("browse: unchecked count", win.count:GetText(), "6 items")
end

do
    local ctx = loadBrowse()
    ctx.equipped[5] = "|Hitem:3:|h"
    ctx.icons[11] = 135000
    ctx.level = 30
    ctx.run("browse chest")
    local win = ctx.win()
    win.usable:SetChecked(false)
    win.usable:GetScript("OnClick")(win.usable)
    local b = win.box.buttons
    check("browse row: icon from the client", b[1].icon.texture, 135000)
    check("browse row: icon fallback", b[2].icon.texture, "Interface\\Icons\\INV_Misc_QuestionMark")
    check("browse row: name before the item loads", b[1].name:GetText(),
        "|cffff8000item #11|r" .. GREY .. " (upgrade) (no known source)|r")
    check("browse row: asks the client to load the item", ctx.requested[11], true)
    check("browse row: ilvl", b[1].ilvl:GetText(), "99")
    check("browse row: level", b[1].level:GetText(), "1")
    check("browse row: usable is opaque", b[1].alpha, 1)
    check("browse row: unusable item has no upgrade mark", b[2].name:GetText(), "|cff0070dditem #1|r")
    check("browse row: unusable item is faded", b[2].alpha, 0.5)
    check("browse row: needed level in red", b[2].level:GetText(), "|cffff202040|r")
    check("browse row: equipped mark", b[3].name:GetText(), "|cff0070dditem #3|r" .. GREY .. " (equipped)|r")
    check("browse row: no marks", b[4].name:GetText(), "|cff0070dditem #4|r")

    b[1].scripts.OnEnter(b[1])
    check("browse row: tooltip item", ctx.ui.tooltip, 11)
    check("browse row: tooltip owner", ctx.ui.tooltipOwner == b[1] and ctx.ui.tooltipAnchor, "ANCHOR_RIGHT")
    check("browse row: tooltip shown", ctx.env.GameTooltip:IsShown(), true)
    b[1].scripts.OnLeave(b[1])
    check("browse row: tooltip hidden on leave", ctx.env.GameTooltip:IsShown(), false)

    ctx.cache[11] = { "GM Robe", "|cffff8000|Hitem:11::::|h[GM Robe]|h|r", 5, 99 }
    ctx.cache[3] = { "Leather Vest", "|cff0070dd|Hitem:3::::|h[Leather Vest]|h|r", 3, 30 }
    ctx.fire("GET_ITEM_INFO_RECEIVED", 11, true)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 3, true)
    check("browse refresh: one timer for a burst", #ctx.ui.timers, 1)
    check("browse refresh: short delay", ctx.ui.timers[1].delay, 0.2)
    check("browse refresh: nothing redrawn before the timer", b[1].name:GetText():find("GM Robe", 1, true), nil)
    local provider = win.box.provider
    ctx.tick()
    check("browse refresh: name after the item loads", b[1].name:GetText(),
        "|cffff8000GM Robe|r" .. GREY .. " (upgrade) (no known source)|r")
    check("browse refresh: second item too", b[3].name:GetText(), "|cff0070ddLeather Vest|r" .. GREY .. " (equipped)|r")
    check("browse refresh: rows are not listed again", win.box.provider, provider)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 999, true)
    check("browse refresh: an item not in the rows is ignored", #ctx.ui.timers, 0)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 4, false)
    check("browse refresh: a failed load schedules nothing", #ctx.ui.timers, 0)
    local asked = 0
    ctx.env.C_Item.RequestLoadItemDataByID = function()
        asked = asked + 1
    end
    win.box:ForEachFrame(function(button, row)
        button.scripts.OnClick(button)
        return row
    end)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 3, true)
    ctx.tick()
    ctx.run("browse")
    ctx.run("browse chest")
    check("browse refresh: redraws do not ask for an item again", asked, 0)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 4, true)
    check("browse refresh: a later load schedules again", #ctx.ui.timers, 1)
    ctx.tick()
    ctx.run("browse")
    ctx.fire("GET_ITEM_INFO_RECEIVED", 4, true)
    check("browse refresh: nothing while hidden", #ctx.ui.timers, 0)
end

do
    local ctx = loadBrowse()
    ctx.fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
    check("browse gear change: harmless before the window is built", ctx.win(), nil)
    ctx.equipped[5] = "|Hitem:3:|h"
    ctx.run("browse chest")
    local win = ctx.win()
    local b = win.box.buttons
    check("browse gear change: listens for it", ctx.frame.registered.PLAYER_EQUIPMENT_CHANGED, true)
    check("browse gear change: worn item marked", b[3].name:GetText(), "|cff0070dditem #3|r" .. GREY .. " (equipped)|r")
    ctx.equipped[5] = "|Hitem:4:|h"
    ctx.fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
    check("browse gear change: old item no longer marked", b[3].name:GetText(), "|cff0070dditem #3|r")
    check("browse gear change: new item marked", b[4].name:GetText(), "|cff0070dditem #4|r" .. GREY .. " (equipped)|r")
    ctx.run("browse")
    ctx.equipped[5] = nil
    ctx.fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
    check("browse gear change: nothing redrawn while hidden", b[4].name:GetText(),
        "|cff0070dditem #4|r" .. GREY .. " (equipped)|r")
    ctx.run("browse chest")
    check("browse gear change: showing again reads the gear", b[4].name:GetText(),
        "|cff0070dditem #4|r" .. GREY .. " (upgrade)|r")
end

do
    local db, shipped = gearData()
    db.npcs = { [448] = "Hogger" }
    for npc = 600, 606 do
        shipped.loot[#shipped.loot + 1] = { 4, "c", npc, 1429, 1 }
    end
    local ctx = loadBrowse("enUS", db, shipped)
    ctx.run("browse chest")
    local win = ctx.win()
    local b = win.box.buttons
    b[2].scripts.OnClick(b[2])
    local pane = paneText(win)
    check("browse click: header is the item link", pane[1], built(1, BLUE))
    check("browse click: source line", pane[2], "  Hogger, Elwynn Forest - drops: 1")
    check("browse click: blank lines after the sources", pane[3], "")
    check("browse click: selected row highlighted", b[2].selected:IsShown(), true)
    check("browse click: other rows not highlighted", b[1].selected:IsShown(), false)
    b[4].scripts.OnClick(b[4])
    pane = paneText(win)
    check("browse click: many sources", pane[2], "  npc #500, Elwynn Forest - drops: 1")
    check("browse click: and more sources", pane[7], "  and 3 more sources")
    check("browse click: highlight moves", b[2].selected:IsShown() == false and b[4].selected:IsShown(), true)
    b[1].scripts.OnClick(b[1])
    check("browse click: sourceless item", paneText(win)[2], "  no known source")
    ctx.cache[11] = { "GM Robe", "|cffff8000|Hitem:11::::|h[GM Robe]|h|r", 5, 99 }
    ctx.fire("GET_ITEM_INFO_RECEIVED", 11, true)
    ctx.tick()
    check("browse click: header link refreshes after the item loads", paneText(win)[1], ctx.cache[11][2])

    local looked = 0
    local sources = ctx.addon.Advisor.Sources
    ctx.addon.Advisor.Sources = function(id)
        looked = looked + 1
        return sources(id)
    end
    ctx.fire("GET_ITEM_INFO_RECEIVED", 3, true)
    ctx.tick()
    check("browse redraw: another row loading keeps the sources pane", looked, 0)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 3, true)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 11, true)
    ctx.tick()
    check("browse redraw: the selected item loading in a burst redraws the pane once", looked, 1)
    ctx.addon.Advisor.Sources = sources
end

do
    local ctx = loadBrowse()
    ctx.combat = true
    local out = ctx.run("browse")
    check("browse in combat: refused", out[1], "Tandem: not available in combat")
    check("browse in combat: one line", #out, 1)
    check("browse in combat: nothing built", ctx.win(), nil)
    check("browse <slot> in combat: refused", ctx.run("browse chest")[1], "Tandem: not available in combat")
    check("browse <bad slot> in combat: refused first", ctx.run("browse foo")[1], "Tandem: not available in combat")
    local extra = ctx.run("browse a b")
    check("browse with extra args in combat: refused first", extra[1] .. "|" .. #extra,
        "Tandem: not available in combat|1")
    ctx.combat = false
    ctx.run("browse")
    check("browse: listens for combat", ctx.frame.registered.PLAYER_REGEN_DISABLED, true)
    ctx.fire("PLAYER_REGEN_DISABLED")
    check("browse: hidden when combat starts", ctx.win():IsShown(), false)
    ctx.fire("PLAYER_REGEN_DISABLED")
    check("browse: hiding twice is harmless", ctx.win():IsShown(), false)
end

do
    local ctx = loadBrowse()
    ctx.fire("PLAYER_REGEN_DISABLED")
    ctx.fire("GET_ITEM_INFO_RECEIVED", 1, true)
    check("browse: events before the window is built are harmless", ctx.win(), nil)
    ctx.class = nil
    local out = ctx.run("browse")
    check("browse with an unknown class explains", out[1],
        "Tandem: your class or level is not known yet; try again in a moment")
    check("browse with an unknown class builds nothing", ctx.win(), nil)
    check("browse unknown slot", ctx.run("browse shirt")[1]:match("^Tandem: unknown slot shirt;"),
        "Tandem: unknown slot shirt;")
    check("browse two arguments print usage", ctx.run("browse chest all")[1], "Tandem commands:")
end

do
    local db, shipped = gearData()
    local ctx = loadBrowse("enUS", db, shipped)
    ctx.run("browse")
    local win = ctx.win()
    win.points = { { "TOPLEFT", ctx.env.UIParent, "BOTTOMLEFT", 200, 650 } }
    win.scripts.OnDragStop(win)
    local ui = ctx.env.TandemDB.ui.window
    check("browse drag: saves the position", ui.point .. " " .. ui.relativePoint .. " " .. ui.x .. " " .. ui.y,
        "TOPLEFT BOTTOMLEFT 200 650")
    check("browse drag: user-placed left alone with SetDontSavePosition", win.userPlaced, true)
    check("browse drag: is not an unsaved record", ctx.addon.Store.unsaved, 0)
    check("browse drag: drag starts on the left button", type(win.scripts.OnDragStart), "function")

    db.ui = { window = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 200, y = 650 } }
    local again = loadBrowse("enUS", db, shipped)
    again.run("browse")
    local p = again.win().points[1]
    check("browse: restores the saved position", p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5],
        "TOPLEFT BOTTOMLEFT 200 650")
    check("browse: restores relative to UIParent", p[2], again.env.UIParent)

    db.ui = { window = { point = "TOPLEFT", x = 200, y = -150 } }
    local old = loadBrowse("enUS", db, shipped)
    old.run("browse")
    p = old.win().points[1]
    check("browse: an old position without relativePoint uses point",
        p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], "TOPLEFT TOPLEFT 200 -150")

    local noSave = loadBrowse("enUS", nil, nil, { noDontSave = true })
    noSave.run("browse")
    local nw = noSave.win()
    nw.scripts.OnDragStop(nw)
    check("browse drag: not user-placed without SetDontSavePosition", nw.userPlaced, false)

    db.ui = { window = { point = "NOWHERE", x = 200, y = -150 } }
    local bad = loadBrowse("enUS", db, shipped)
    bad.run("browse")
    check("browse: a bad saved position is centred", bad.win().points[1][1], "CENTER")
end

do
    local ctx = loadBrowse("enUS", nil, nil, { failBars = { "MinimalScrollBar" } })
    ctx.run("browse")
    check("browse: falls back to the trim scroll bar", ctx.ui.bar.template, "WowTrimScrollBar")
    check("browse: the fallback bar still lists rows", #ctx.win().box.buttons, 11)

    ctx = loadBrowse("enUS", nil, nil, { failBars = { "MinimalScrollBar", "WowTrimScrollBar" } })
    ctx.run("browse")
    check("browse: no scroll bar when neither builds", ctx.ui.bar, nil)
    check("browse: list without a bar", ctx.ui.initList, true)
    check("browse: rows without a bar", #ctx.win().box.buttons, 11)

    ctx = loadBrowse("enUS", nil, nil, { failBars = { "MinimalScrollBar", "WowTrimScrollBar" }, noInitList = true })
    local inited
    local real = WIDGET.Init
    WIDGET.Init = function(box, view)
        box.view, inited = view, true
    end
    ctx.run("browse")
    WIDGET.Init = real
    check("browse: list initialised on the box without ScrollUtil.InitScrollBoxList", inited, true)
    check("browse: rows on the plain box", #ctx.win().box.buttons, 11)
end

do
    local ctx = loadBrowse("zhTW")
    check("zhTW usage lists browse", ctx.run("help")[9], "  /tandem browse [<部位>] - 在視窗中瀏覽已知裝備")
    ctx.run("browse")
    local win = ctx.win()
    check("zhTW browse title", win.title, "Tandem 裝備")
    check("zhTW browse all slots", radios(win.dropdown)[1].text, "所有部位")
    check("zhTW browse slot label", radios(win.dropdown)[2].text, "頭部")
    check("zhTW browse count", win.count:GetText(), "11 件物品")
    check("zhTW browse no selection", paneText(win)[1], "選擇一件物品以查看掉落來源")
    local usableText
    for _, w in ipairs(ctx.ui.widgets) do
        if w.kind == "FontString" and w.text == "僅限可用" then
            usableText = w.text
        end
    end
    check("zhTW browse usable only", usableText, "僅限可用")
    ctx.combat = true
    ctx.run("browse")
    check("zhTW browse in combat", ctx.run("browse")[1], "Tandem：戰鬥中無法使用")
end

-- Store: minimap button angle in TandemDB.ui (unit 7).

do
    local addon, printed, env = loadWithDB({ schemaVersion = 3,
                                             ui = { window = { point = "TOP", x = 1, y = 2 }, minimap = 90.5 } })
    check("minimap: a valid angle is kept", env.TandemDB.ui.minimap, 90.5)
    check("minimap: kept with the position", addon.Store.UIPosition().point, "TOP")
    check("minimap: a valid angle prints only the load line", #printed, 1)
    check("minimap: MinimapAngle returns it", addon.Store.MinimapAngle(), 90.5)
    check("minimap: SetUIPosition keeps the angle", addon.Store.SetUIPosition("LEFT", "LEFT", 3, 4)
        and env.TandemDB.ui.minimap, 90.5)
    check("minimap: SetMinimapAngle saves", addon.Store.SetMinimapAngle(0), true)
    check("minimap: SetMinimapAngle keeps the position", env.TandemDB.ui.window.point .. " " .. env.TandemDB.ui.minimap,
        "LEFT 0")
    check("minimap: SetMinimapAngle is not a record", addon.Store.unsaved, 0)
    for name, angle in pairs({ ["360"] = 360, ["negative"] = -1, ["string"] = "90", ["NaN"] = 0 / 0,
                               ["nil"] = nil, ["huge"] = math.huge }) do
        check("minimap: SetMinimapAngle rejects " .. name, addon.Store.SetMinimapAngle(angle), false)
    end
    check("minimap: a rejected angle keeps the old one", env.TandemDB.ui.minimap, 0)
end

do
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = { minimap = 200 } })
    check("minimap: an angle without a position is kept", env.TandemDB.ui.minimap, 200)
    check("minimap: no position from an angle alone", addon.Store.UIPosition(), nil)
    check("minimap: an angle alone prints only the load line", #printed, 1)
    local fresh = loadWithDB({ schemaVersion = 3 })
    check("minimap: a fresh db has no angle", fresh.Store.MinimapAngle(), nil)
    check("minimap: SetMinimapAngle on a fresh db", fresh.Store.SetMinimapAngle(45) and fresh.Store.db.ui.minimap, 45)
    check("minimap: no position from SetMinimapAngle", fresh.Store.UIPosition(), nil)
end

for name, case in pairs({
    ["360"] = { ui = { minimap = 360 }, dropped = 1 },
    ["a string"] = { ui = { minimap = "90" }, dropped = 1 },
    ["NaN"] = { ui = { minimap = 0 / 0 }, dropped = 1 },
    ["a bad position too"] = { ui = { window = { point = "UP", x = 0, y = 0 }, minimap = -5 }, dropped = 2 },
}) do
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = case.ui })
    check("minimap: drops an angle of " .. name, env.TandemDB.ui, nil)
    check("minimap: counts an angle of " .. name, printed[2],
        ("Tandem: dropped %d invalid saved entries"):format(case.dropped))
    check("minimap: MinimapAngle after dropping " .. name, addon.Store.MinimapAngle(), nil)
end

do
    local addon, printed, env = loadWithDB({ schemaVersion = 3,
                                             ui = { window = { point = "TOP", x = 1, y = 2 }, minimap = 400 } })
    local ui = env.TandemDB.ui
    check("minimap: a bad angle keeps a good position", ui.window.point .. " " .. tostring(ui.minimap), "TOP nil")
    check("minimap: a bad angle alone is one drop", printed[2], "Tandem: dropped 1 invalid saved entries")
    check("minimap: UIPosition with a dropped angle", addon.Store.UIPosition().x, 1)
end

do
    local addon = loadWithDB({ schemaVersion = 4, ui = { minimap = 10 } })
    check("minimap: a newer db still gives its angle", addon.Store.MinimapAngle(), 10)
    check("minimap: a newer db is not written", addon.Store.SetMinimapAngle(20), false)
    addon = loadWithDB({ schemaVersion = 4, ui = { minimap = "10" } })
    check("minimap: a newer db with a bad angle gives none", addon.Store.MinimapAngle(), nil)
end

-- Launcher (unit 7): addon compartment entry and minimap fallback.

do
    local want = {
        ["AddonCompartmentFunc"] = "Tandem_OnCompartmentClick",
        ["AddonCompartmentFuncOnEnter"] = "Tandem_OnCompartmentEnter",
        ["AddonCompartmentFuncOnLeave"] = "Tandem_OnCompartmentLeave",
    }
    local got = {}
    for raw in io.lines(addonDir .. "Tandem.toc") do
        local key, value = raw:match("^## (%S+): (%S+)$")
        if key and want[key] then
            got[key] = value
        end
    end
    local ctx = loadBrowse()
    for key, fn in pairs(want) do
        check("toc " .. key, got[key], fn)
        check("launcher: global " .. fn, type(ctx.env[fn]), "function")
    end

    ctx.env.Tandem_OnCompartmentClick("Tandem", "LeftButton")
    check("compartment click opens the window", ctx.win() and ctx.win():IsShown(), true)
    check("compartment click prints nothing", #ctx.printed, 1)
    ctx.env.Tandem_OnCompartmentClick("Tandem", "LeftButton")
    check("compartment click closes the window", ctx.win():IsShown(), false)

    local menuButton = { name = "menu" }
    ctx.env.Tandem_OnCompartmentEnter("Tandem", menuButton)
    check("compartment tooltip owner", ctx.ui.tooltipOwner, menuButton)
    check("compartment tooltip title", ctx.env.GameTooltip:GetText(), "Tandem")
    check("compartment tooltip hint", ctx.ui.tooltipLines[1], "Click to browse known gear")
    check("compartment tooltip has no drag hint", ctx.ui.tooltipLines[2], nil)
    check("compartment tooltip shown", ctx.env.GameTooltip:IsShown(), true)
    ctx.env.Tandem_OnCompartmentLeave("Tandem", menuButton)
    check("compartment tooltip hidden", ctx.env.GameTooltip:IsShown(), false)
    ctx.env.Tandem_OnCompartmentEnter("Tandem", nil)
    check("compartment tooltip without a frame is skipped", #ctx.ui.tooltipLines, 1)

    ctx.combat = true
    local before = #ctx.printed
    ctx.env.Tandem_OnCompartmentClick("Tandem", "LeftButton")
    check("compartment click in combat refused", ctx.printed[before + 1], "Tandem: not available in combat")
    check("compartment click in combat one line", #ctx.printed, before + 1)
    check("compartment click in combat stays closed", ctx.win():IsShown(), false)
end

do
    local ctx = loadBrowse()
    ctx.env.Tandem_OnCompartmentClick("Tandem", "LeftButton")
    ctx.combat = true
    ctx.fire("PLAYER_REGEN_DISABLED")
    ctx.combat = false
    check("launcher: combat hid the window", ctx.win():IsShown(), false)
end

do
    local ctx = loadBrowse()
    ctx.combat = true
    ctx.env.Tandem_OnCompartmentClick("Tandem", "LeftButton")
    check("compartment click in combat builds nothing", ctx.win(), nil)
end

-- Returns the fake minimap and the button Tandem put on it, after PLAYER_LOGIN.
local function minimapButton(ctx)
    for _, w in ipairs(ctx.ui.widgets) do
        if w.name == "TandemMinimapButton" then
            return w
        end
    end
end

local function fakeMinimap()
    local m = newWidget({ widgets = {} }, "Minimap", "Minimap")
    m.GetWidth = function()
        return 140
    end
    m.GetCenter = function()
        return 500, 400
    end
    m.GetEffectiveScale = function()
        return 2
    end
    return m
end

do
    local ctx = loadBrowse("enUS", nil, nil, { env = { AddonCompartmentFrame = {}, Minimap = fakeMinimap() } })
    check("launcher: listens for login", ctx.frame.registered.PLAYER_LOGIN, true)
    ctx.fire("PLAYER_LOGIN")
    check("launcher: a minimap button with the compartment too", minimapButton(ctx) ~= nil, true)
end

do
    local ctx = loadBrowse("enUS", nil, nil, { env = { Minimap = false } })
    ctx.fire("PLAYER_LOGIN")
    check("launcher: no minimap and no compartment builds nothing", minimapButton(ctx), nil)
end

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

do
    local Launcher = loadBrowse().addon.Launcher
    check("angle: east is 0", near(Launcher.Angle(10, 0, 0, 0), 0), true)
    check("angle: north is 90", near(Launcher.Angle(0, 10, 0, 0), 90), true)
    check("angle: west is 180", near(Launcher.Angle(-10, 0, 0, 0), 180), true)
    check("angle: south is 270", near(Launcher.Angle(0, -10, 0, 0), 270), true)
    check("angle: around a centre", near(Launcher.Angle(6, 6, 5, 5), 45), true)
    check("angle: a tiny negative angle wraps to 0", Launcher.Angle(1, -1e-300, 0, 0), 0)
    check("angle: just below 360 stays below", Launcher.Angle(1, -1e-3, 0, 0) < 360, true)
end

do
    local db, shipped = gearData()
    local minimap = fakeMinimap()
    local cursorAt = { 1000, 1000 }
    local ctx = loadBrowse("enUS", db, shipped, { env = { Minimap = minimap, GetCursorPosition = function()
        return cursorAt[1], cursorAt[2]
    end } })
    ctx.fire("PLAYER_LOGIN")
    local b = minimapButton(ctx)
    check("minimap button: built without the compartment", b ~= nil, true)
    check("minimap button: on the minimap", b.parent, minimap)
    check("minimap button: icon", b.icon.texture, "Interface\\AddOns\\Tandem\\Media\\icon")
    local p = b.points[1]
    check("minimap button: default angle 225", p[1] .. " " .. tostring(p[2] == minimap) .. " " .. p[3],
        "CENTER true CENTER")
    check("minimap button: default position", near(p[4], -80 * math.sqrt(0.5)) and near(p[5], -80 * math.sqrt(0.5)),
        true)
    ctx.fire("PLAYER_LOGIN")
    check("minimap button: built once", #(function()
        local n = {}
        for _, w in ipairs(ctx.ui.widgets) do
            if w.name == "TandemMinimapButton" then
                n[#n + 1] = w
            end
        end
        return n
    end)(), 1)

    b.scripts.OnClick(b, "LeftButton")
    check("minimap button: click opens the window", ctx.win():IsShown(), true)
    b.scripts.OnClick(b, "LeftButton")
    check("minimap button: click closes the window", ctx.win():IsShown(), false)
    b.scripts.OnEnter(b)
    check("minimap button: tooltip owner", ctx.ui.tooltipOwner, b)
    check("minimap button: tooltip drag hint", ctx.ui.tooltipLines[2], "Drag to move this button")
    b.scripts.OnLeave(b)
    check("minimap button: tooltip hidden", ctx.env.GameTooltip:IsShown(), false)

    b.scripts.OnDragStart(b)
    check("minimap button: follows the cursor while dragged", type(b.scripts.OnUpdate), "function")
    cursorAt = { 1200, 800 }
    b.scripts.OnUpdate(b)
    check("minimap button: drag moves it (scaled cursor east)", near(b.points[1][4], 80) and near(b.points[1][5], 0),
        true)
    cursorAt = { 1200, 1000 }
    b.scripts.OnUpdate(b)
    b.scripts.OnDragStop(b)
    check("minimap button: stops following", b.scripts.OnUpdate, nil)
    check("minimap button: angle saved", near(ctx.env.TandemDB.ui.minimap, 45), true)
    check("minimap button: angle is not a record", ctx.addon.Store.unsaved, 0)

    ctx.combat = true
    local before = #ctx.printed
    b.scripts.OnClick(b, "LeftButton")
    check("minimap button: refused in combat", ctx.printed[before + 1], "Tandem: not available in combat")
    check("minimap button: stays closed in combat", ctx.win():IsShown(), false)

    db.ui = { minimap = 90 }
    local again = loadBrowse("enUS", db, shipped, { env = { Minimap = fakeMinimap() } })
    again.fire("PLAYER_LOGIN")
    local q = minimapButton(again).points[1]
    check("minimap button: restores the saved angle", near(q[4], 0) and near(q[5], 80), true)
end

do
    local ctx = loadBrowse("zhTW", nil, nil, { env = { Minimap = fakeMinimap() } })
    ctx.fire("PLAYER_LOGIN")
    local b = minimapButton(ctx)
    b.scripts.OnEnter(b)
    check("zhTW minimap tooltip hint", ctx.ui.tooltipLines[1], "點擊以瀏覽已知裝備")
    check("zhTW minimap tooltip drag hint", ctx.ui.tooltipLines[2], "拖曳以移動此按鈕")
end

-- Minimap button visibility: shown by default, /tandem minimap [on|off] and the browse window's checkbox.

do
    local ctx = loadBrowse("enUS", nil, nil, { env = { AddonCompartmentFrame = {}, Minimap = fakeMinimap() } })
    ctx.fire("PLAYER_LOGIN")
    local b = minimapButton(ctx)
    check("minimap: built with the compartment too", b ~= nil, true)
    check("minimap: shown by default", b:IsShown(), true)
    check("minimap: no flag saved by default", ctx.env.TandemDB.ui, nil)

    local out = ctx.run("minimap")
    check("minimap: no argument toggles off", out[1] .. "|" .. #out, "Tandem: minimap button hidden|1")
    check("minimap: toggled off hides the button", b:IsShown(), false)
    check("minimap: hidden flag saved", ctx.env.TandemDB.ui.minimapHidden, true)
    check("minimap: hiding is not a record", ctx.addon.Store.unsaved, 0)
    out = ctx.run("minimap")
    check("minimap: no argument toggles on", out[1], "Tandem: minimap button shown")
    check("minimap: toggled on shows the button", b:IsShown(), true)
    check("minimap: shown removes the flag", ctx.env.TandemDB.ui.minimapHidden, nil)
    check("minimap off", ctx.run("MINIMAP OFF")[1], "Tandem: minimap button hidden")
    check("minimap off again stays hidden", ctx.run("minimap off")[1] .. " " .. tostring(b:IsShown()),
        "Tandem: minimap button hidden false")
    check("minimap on", ctx.run("minimap on")[1] .. " " .. tostring(b:IsShown()), "Tandem: minimap button shown true")
    for _, msg in ipairs({ "minimap yes", "minimap on off", "minimap toggle" }) do
        local bad = ctx.run(msg)
        check(("%q prints usage"):format(msg), bad[1], "Tandem commands:")
        check(("%q leaves the button"):format(msg), b:IsShown(), true)
    end
    ctx.combat = true
    out = ctx.run("minimap off")
    check("minimap: allowed in combat", out[1] .. "|" .. #out, "Tandem: minimap button hidden|1")
    check("minimap: hidden in combat", b:IsShown(), false)
    ctx.combat = false
    ctx.run("minimap on")

    -- The browse window's checkbox follows the setting both ways.
    ctx.run("browse")
    local win = ctx.win()
    check("minimap checkbox: template", win.minimap.template, "UICheckButtonTemplate")
    check("minimap checkbox: ticked while shown", win.minimap:GetChecked(), true)
    local labelled
    for _, w in ipairs(ctx.ui.widgets) do
        if w.kind == "FontString" and w.text == "Show minimap button" then
            labelled = true
        end
    end
    check("minimap checkbox: label", labelled, true)
    ctx.run("minimap off")
    check("minimap checkbox: unticked by the command", win.minimap:GetChecked(), false)
    win.minimap:SetChecked(true)
    win.minimap:GetScript("OnClick")(win.minimap)
    check("minimap checkbox: ticking shows the button", b:IsShown(), true)
    check("minimap checkbox: ticking saves", ctx.env.TandemDB.ui.minimapHidden, nil)
    win.minimap:SetChecked(false)
    win.minimap:GetScript("OnClick")(win.minimap)
    check("minimap checkbox: unticking hides the button", b:IsShown(), false)
    check("minimap checkbox: unticking saves", ctx.env.TandemDB.ui.minimapHidden, true)
    check("minimap checkbox: prints nothing", #ctx.run("browse"), 0)
end

do
    local db, shipped = gearData()
    db.ui = { minimapHidden = true, minimap = 90 }
    local ctx = loadBrowse("enUS", db, shipped, { env = { Minimap = fakeMinimap() } })
    check("minimap: a saved hidden flag is kept", ctx.env.TandemDB.ui.minimapHidden, true)
    ctx.fire("PLAYER_LOGIN")
    local b = minimapButton(ctx)
    check("minimap: built while hidden", b ~= nil, true)
    check("minimap: hidden after login", b:IsShown(), false)
    ctx.run("browse")
    check("minimap checkbox: unticked while hidden", ctx.win().minimap:GetChecked(), false)
    check("minimap: on after a hidden login", ctx.run("minimap")[1] .. " " .. tostring(b:IsShown()),
        "Tandem: minimap button shown true")
    check("minimap checkbox: ticked by the command", ctx.win().minimap:GetChecked(), true)
end

do
    local ctx = loadBrowse("enUS", nil, nil, { env = { Minimap = false } })
    ctx.fire("PLAYER_LOGIN")
    check("minimap: without a minimap the command still answers", ctx.run("minimap off")[1],
        "Tandem: minimap button hidden")
    check("minimap: without a minimap the flag is saved", ctx.env.TandemDB.ui.minimapHidden, true)
end

do
    local db, shipped = gearData()
    db.schemaVersion = 4
    db.ui = { minimap = 10 }
    local ctx = loadBrowse("enUS", db, shipped, { env = { Minimap = fakeMinimap() } })
    ctx.fire("PLAYER_LOGIN")
    local b = minimapButton(ctx)
    check("minimap: a newer db hides for the session", ctx.run("minimap off")[1] .. " " .. tostring(b:IsShown()),
        "Tandem: minimap button hidden false")
    check("minimap: a newer db is not written", ctx.env.TandemDB.ui.minimapHidden, nil)
    check("minimap: a newer db toggles back on", ctx.run("minimap")[1], "Tandem: minimap button shown")
end

do
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = { minimapHidden = true } })
    check("minimapHidden: kept alone", env.TandemDB.ui.minimapHidden, true)
    check("minimapHidden: prints only the load line", #printed, 1)
    check("minimapHidden: MinimapHidden", addon.Store.MinimapHidden(), true)
    check("minimapHidden: SetMinimapHidden(false)", addon.Store.SetMinimapHidden(false), true)
    check("minimapHidden: false removes the key", env.TandemDB.ui.minimapHidden, nil)
    check("minimapHidden: MinimapHidden after false", addon.Store.MinimapHidden(), false)
    addon.Store.SetMinimapAngle(30)
    addon.Store.SetUIPosition("TOP", "TOP", 1, 2)
    check("minimapHidden: SetMinimapHidden(true)", addon.Store.SetMinimapHidden(true), true)
    local ui = env.TandemDB.ui
    check("minimapHidden: writes only its key",
        ui.minimap .. " " .. ui.window.point .. " " .. tostring(ui.minimapHidden), "30 TOP true")
    for name, v in pairs({ ["nil"] = nil, ["a string"] = "yes", ["a number"] = 1 }) do
        check("minimapHidden: SetMinimapHidden rejects " .. name, addon.Store.SetMinimapHidden(v), false)
    end
    check("minimapHidden: a rejected value keeps the old one", env.TandemDB.ui.minimapHidden, true)
    check("minimapHidden: not a record", addon.Store.unsaved, 0)
    local fresh = loadWithDB({ schemaVersion = 3 })
    check("minimapHidden: a fresh db shows the button", fresh.Store.MinimapHidden(), false)
end

for name, case in pairs({
    ["false"] = { ui = { minimapHidden = false }, dropped = 1 },
    ["a string"] = { ui = { minimapHidden = "true" }, dropped = 1 },
    ["a number"] = { ui = { minimapHidden = 1 }, dropped = 1 },
    ["a bad angle too"] = { ui = { minimapHidden = {}, minimap = 400 }, dropped = 2 },
}) do
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = case.ui })
    check("minimapHidden: drops " .. name, env.TandemDB.ui, nil)
    check("minimapHidden: counts " .. name, printed[2],
        ("Tandem: dropped %d invalid saved entries"):format(case.dropped))
    check("minimapHidden: shown after dropping " .. name, addon.Store.MinimapHidden(), false)
end

do
    local _, printed, env = loadWithDB({ schemaVersion = 3, ui = { minimap = 45, minimapHidden = "no" } })
    check("minimapHidden: a bad flag keeps a good angle", env.TandemDB.ui.minimap .. " "
        .. tostring(env.TandemDB.ui.minimapHidden), "45 nil")
    check("minimapHidden: a bad flag alone is one drop", printed[2], "Tandem: dropped 1 invalid saved entries")
    local newer = loadWithDB({ schemaVersion = 4, ui = { minimapHidden = true } })
    check("minimapHidden: a newer db still gives its flag", newer.Store.MinimapHidden(), true)
    check("minimapHidden: a newer db is not written", newer.Store.SetMinimapHidden(false), false)
    newer = loadWithDB({ schemaVersion = 4, ui = { minimapHidden = "yes" } })
    check("minimapHidden: a newer db with a bad flag shows the button", newer.Store.MinimapHidden(), false)
end

do
    local ctx = loadBrowse("zhTW", nil, nil, { env = { Minimap = fakeMinimap() } })
    ctx.fire("PLAYER_LOGIN")
    check("zhTW usage lists minimap", ctx.run("help")[10], "  /tandem minimap [on|off] - 顯示或隱藏小地圖按鈕")
    check("zhTW minimap hidden", ctx.run("minimap off")[1], "Tandem：已隱藏小地圖按鈕")
    check("zhTW minimap shown", ctx.run("minimap on")[1], "Tandem：已顯示小地圖按鈕")
    ctx.run("browse")
    local labelled
    for _, w in ipairs(ctx.ui.widgets) do
        if w.kind == "FontString" and w.text == "顯示小地圖按鈕" then
            labelled = true
        end
    end
    check("zhTW minimap checkbox label", labelled, true)
end

-- Scan bar in the browse window (unit 8).

-- Returns the live tickers with the given interval.
local function tickers(ctx, interval)
    local out = {}
    for _, t in ipairs(ctx.ui.tickers) do
        if t.interval == interval and not t.cancelled then
            out[#out + 1] = t
        end
    end
    return out
end

-- Types rate and cap into the scan bar and presses its button; returns the lines printed.
local function pressScan(ctx, rate, cap)
    local win = ctx.win()
    if rate then
        win.rate:SetText(rate)
    end
    if cap then
        win.cap:SetText(cap)
    end
    local before = #ctx.printed
    win.scan.scripts.OnClick(win.scan)
    return ctx.since(before)
end

do
    local ctx = loadBrowse()
    ctx.run("browse")
    local win = ctx.win()
    check("scan bar: rate box template", win.rate.template, "InputBoxTemplate")
    check("scan bar: rate default", win.rate:GetText(), "10/s")
    check("scan bar: cap default", win.cap:GetText(), "100")
    check("scan bar: button template", win.scan.template, "UIPanelButtonTemplate")
    check("scan bar: idle button", win.scan:GetText(), "Start")
    check("scan bar: idle status", win.status:GetText(), "8 known items, next scan from ID 1")
    check("scan bar: no progress ticker while idle", #tickers(ctx, 1), 0)

    win.rate:SetFocus()
    win.rate.scripts.OnEnterPressed(win.rate)
    check("scan bar: Enter drops the focus", win.rate.focused, false)
    win.cap:SetFocus()
    win.cap.scripts.OnEscapePressed(win.cap)
    check("scan bar: Escape drops the focus", win.cap.focused, false)

    ctx.run("browse")
    ctx.run("browse")
    check("scan bar: no progress ticker on an idle show", #tickers(ctx, 1), 0)

    win.rate:SetFocus()
    local out = pressScan(ctx, " 5/s ", "3")
    check("scan bar: start prints the scan line", out[1], "Tandem: scanning 3 IDs from ID 1")
    check("scan bar: start runs the scanner", ctx.addon.Scanner.IsRunning(), true)
    check("scan bar: start drops the focus", win.rate.focused, false)
    check("scan bar: progress ticker while a scan runs", #tickers(ctx, 1), 1)
    ctx.run("browse")
    check("scan bar: progress ticker cancelled on hide", #tickers(ctx, 1), 0)
    ctx.run("browse")
    check("scan bar: progress ticker again on show", #tickers(ctx, 1), 1)
    ctx.run("browse chest")
    check("scan bar: one progress ticker while shown", #tickers(ctx, 1), 1)
    local scanTicker = tickers(ctx, 0.2)[1]
    check("scan bar: rate from the box", scanTicker ~= nil, true)
    check("scan bar: running button", win.scan:GetText(), "Stop")
    check("scan bar: running status", win.status:GetText(), "Scanning: 0 of 3 IDs, 0 found, next ID 1")
    scanTicker.fn(scanTicker)
    scanTicker.fn(scanTicker)
    tickers(ctx, 1)[1].fn()
    check("scan bar: progress on tick", win.status:GetText(), "Scanning: 2 of 3 IDs, 1 found, next ID 3")
    local provider = win.box.provider
    out = pressScan(ctx)
    check("scan bar: stop prints the stop line", out[1]:match("^Tandem: scan stopped"), "Tandem: scan stopped")
    check("scan bar: stop stops the scanner", ctx.addon.Scanner.IsRunning(), false)
    check("scan bar: stop cancels the scan ticker", scanTicker.cancelled, true)
    check("scan bar: stop cancels the progress ticker", #tickers(ctx, 1), 0)
    check("scan bar: idle again", win.scan:GetText() .. "|" .. win.status:GetText(),
        "Start|8 known items, next scan from ID 3")
    check("scan bar: stop refreshes the list", win.box.provider ~= provider, true)

    pressScan(ctx, "", "")
    check("scan bar: empty boxes use the defaults", tickers(ctx, 0.1)[1] ~= nil, true)
    check("scan bar: default cap", ctx.win().status:GetText(), "Scanning: 0 of 100 IDs, 0 found, next ID 3")
    pressScan(ctx)

    pressScan(ctx, "20/m", "1")
    local slow = tickers(ctx, 3)[1]
    check("scan bar: per-minute rate", slow ~= nil, true)
    provider = win.box.provider
    slow.fn(slow)
    check("scan bar: finished scan stops", ctx.addon.Scanner.IsRunning(), false)
    check("scan bar: finished scan refreshes the list", win.box.provider ~= provider, true)
    check("scan bar: finished scan shows idle", win.scan:GetText(), "Start")
end

do
    local ctx = loadBrowse()
    ctx.run("browse")
    for name, input in pairs({
        ["too fast"] = { "51/s", "10" }, ["no unit"] = { "10", "10" }, ["bad unit"] = { "10/h", "10" },
        ["zero cap"] = { "10/s", "0" }, ["huge cap"] = { "10/s", "100001" }, ["text cap"] = { "10/s", "5x" },
        ["negative cap"] = { "10/s", "-5" }, ["slower than 1/m"] = { "0/m", "10" },
    }) do
        local out = pressScan(ctx, input[1], input[2])
        check("scan bar: " .. name .. " prints the scan usage", out[1] .. "|" .. #out,
            "  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)|1")
        check("scan bar: " .. name .. " does not start", ctx.addon.Scanner.IsRunning(), false)
    end
    check("scan bar: the cap limit is accepted", pressScan(ctx, "50/s", "100000")[1],
        "Tandem: scanning 100000 IDs from ID 1")
    pressScan(ctx)
    check("scan bar: an upper-case unit is accepted like the command", pressScan(ctx, "10/S", "5")[1],
        "Tandem: scanning 5 IDs from ID 1")
    pressScan(ctx)

    ctx.combat = true
    local out = pressScan(ctx, "10/s", "5")
    check("scan bar: refused in combat", out[1] .. "|" .. #out, "Tandem: not available in combat|1")
    check("scan bar: nothing started in combat", ctx.addon.Scanner.IsRunning(), false)
end

do
    local ctx = loadBrowse()
    ctx.run("scan 10/s 5")
    ctx.run("browse")
    local win = ctx.win()
    check("scan bar: a scan started by command shows Stop", win.scan:GetText(), "Stop")
    check("scan bar: a scan started by command shows progress", win.status:GetText(),
        "Scanning: 0 of 5 IDs, 0 found, next ID 1")
    check("scan bar: a scan started by command ticks the progress", #tickers(ctx, 1), 1)
    ctx.run("browse")
    local provider = win.box.provider
    ctx.run("scan stop")
    check("scan bar: a stop while hidden does not refresh", win.box.provider, provider)
    ctx.run("browse")
    ctx.run("scan 10/s 5")
    check("scan bar: a command start while shown shows Stop", win.scan:GetText(), "Stop")
    check("scan bar: a command start while shown ticks the progress", #tickers(ctx, 1), 1)
end

do
    local ctx = loadBrowse("enUS", nil, nil, { failBars = { "InputBoxTemplate", "UIPanelButtonTemplate" } })
    ctx.run("browse")
    local win = ctx.win()
    check("scan bar: plain edit box without the template", win.rate.kind .. " " .. tostring(win.rate.template),
        "EditBox nil")
    check("scan bar: plain button without the template", win.scan.kind .. " " .. tostring(win.scan.template),
        "Button nil")
    check("scan bar: plain boxes still start a scan", pressScan(ctx, "10/s", "2")[1],
        "Tandem: scanning 2 IDs from ID 1")
end

do
    local ctx = loadBrowse("enUS", nil, nil, { env = { C_Timer = { After = noop } } })
    ctx.run("browse")
    check("scan bar: no ticker API still shows the status", ctx.win().status:GetText(),
        "8 known items, next scan from ID 1")
    ctx.run("browse")
    check("scan bar: no ticker API hides cleanly", ctx.win():IsShown(), false)
end

do
    local ctx = loadBrowse("zhTW")
    ctx.run("browse")
    local win = ctx.win()
    check("zhTW scan bar idle", win.scan:GetText() .. "|" .. win.status:GetText(), "開始|已知物品 8 件，下次從 ID 1 開始掃描")
    pressScan(ctx, "10/s", "4")
    check("zhTW scan bar running", win.scan:GetText() .. "|" .. win.status:GetText(),
        "停止|掃描中：0／4 個 ID，找到 0 個，下一個 ID 1")
    local labels = {}
    for _, w in ipairs(ctx.ui.widgets) do
        if w.kind == "FontString" and (w.text == "速度" or w.text == "上限") then
            labels[#labels + 1] = w.text
        end
    end
    check("zhTW scan bar labels", table.concat(labels, ","), "速度,上限")
    local out = pressScan(ctx)
    pressScan(ctx, "bad", "")
    check("zhTW scan bar usage", ctx.printed[#ctx.printed]:match("^  /tandem scan") ~= nil, true)
    check("zhTW scan bar stop", out[1]:match("^Tandem：掃描已停止") ~= nil, true)
end

do
    local addon = loadWithDB({ schemaVersion = 3, items = { [5] = GEAR[5], [7] = GEAR[7] } })
    check("ItemCount: counted on load", addon.Store.ItemCount(), 2)
    addon.Store.AddItem(9, 1, 1, 1, "INVTYPE_BODY", 4, 0)
    check("ItemCount: AddItem counts", addon.Store.ItemCount(), 3)
    addon.Store.AddItem(9, 1, 1, 1, "INVTYPE_BODY", 4, 0)
    addon.Store.AddItem(10, "bad", 1, 1, "INVTYPE_BODY", 4, 0)
    check("ItemCount: a repeated or invalid item is not counted", addon.Store.ItemCount(), 3)
    check("ItemCount: matches Counts", addon.Store.Counts().items, 3)
    check("ScanCursor: a fresh scan starts at 1", addon.Store.ScanCursor(), 1)
    addon = loadWithDB({ schemaVersion = 4, items = "junk", scan = { cursor = 2.5 } })
    check("ItemCount: a newer db with junk items", addon.Store.ItemCount(), 0)
    check("ScanCursor: a fractional cursor gives none", addon.Store.ScanCursor(), nil)
end

for name, scan in pairs({ ["no scan table"] = false, ["no cursor"] = {}, ["a fractional cursor"] = { cursor = 1.5 },
                          ["a string cursor"] = { cursor = "7" } }) do
    local db, shipped = gearData()
    db.schemaVersion = 4
    db.scan = scan or nil
    local ctx = loadBrowse("enUS", db, shipped)
    ctx.run("browse")
    local win = ctx.win()
    check("scan bar: a newer db with " .. name .. " opens", win and win:IsShown(), true)
    check("scan bar: a newer db with " .. name .. " shows ? for the next ID", win.status:GetText(),
        "8 known items, next scan from ID ?")
    check("scan bar: a newer db with " .. name .. " has no progress ticker", #tickers(ctx, 1), 0)
    check("scan bar: a newer db with " .. name .. " refuses a scan", pressScan(ctx, "10/s", "5")[1],
        "Recording is off: saved data uses a newer schema")
end

-- Drop an item on the browse window (unit 9).

do
    local ctx = loadBrowse()
    ctx.run("browse")
    local win = ctx.win()
    local scrolled
    win.ScrollToElementData = nil
    win.box.ScrollToElementData = function(_, row)
        scrolled = row.id
    end

    ctx.cursor = { "item", 15 }
    win.scripts.OnReceiveDrag(win)
    check("drop: switches to the item's slot", rowIDs(win), "15")
    check("drop: the dropdown follows", radios(win.dropdown)[16].isSelected(radios(win.dropdown)[16].data)
        and radios(win.dropdown)[16].data, "twohand")
    check("drop: selects the item", win.box.buttons[1].selected:IsShown(), true)
    check("drop: header is its link", paneText(win)[1], built(15, GREEN))
    check("drop: shows its sources", paneText(win)[2], "  no known source")
    check("drop: scrolls to it", scrolled, 15)
    check("drop: clears the cursor", ctx.cursor == nil and ctx.cleared, true)

    ctx.level = 30
    ctx.cursor = { "item", 1 }
    win.box.scripts.OnMouseUp(win.box)
    check("drop on the list: chest", rowIDs(win), "11,1,3,4,2,12")
    check("drop: an unusable item turns off usable only", win.usable:GetChecked(), false)
    check("drop: unusable item selected", win.box.buttons[2].selected:IsShown(), true)
    check("drop: its source", paneText(win)[2], "  npc #448, Elwynn Forest - drops: 1")

    win.usable:SetChecked(true)
    ctx.cursor = { "item", 9 }
    win.scripts.OnMouseUp(win)
    check("drop: an item without a ranked slot lists all slots", radios(win.dropdown)[1].isSelected(nil), true)
    check("drop: an item without a ranked slot keeps usable only", win.usable:GetChecked(), true)
    check("drop: its header", paneText(win)[1], built(9, "ffffff"))

    ctx.cleared = false
    ctx.cursor = { "item", 999 }
    win.scripts.OnReceiveDrag(win)
    check("drop: unknown item says so", paneText(win)[1], "Tandem: item 999 is not known; scan or loot it first")
    check("drop: unknown item has no source lines", paneText(win)[2], "")
    check("drop: unknown item clears the cursor", ctx.cursor == nil and ctx.cleared, true)
    check("drop: unknown item selects no row", (function()
        for _, b in ipairs(win.box.buttons) do
            if b.selected:IsShown() then
                return true
            end
        end
        return false
    end)(), false)
    local b = win.box.buttons[1]
    b.scripts.OnClick(b)
    check("drop: a click after an unknown item selects again",
        paneText(win)[1]:find("|Hitem:" .. b.row.id .. ":", 1, true) ~= nil, true)
end

do
    local ctx = loadBrowse()
    ctx.run("browse chest")
    local win = ctx.win()
    local rows = rowIDs(win)
    for name, cursor in pairs({
        spell = { "spell", 133 }, money = { "money", 50 }, empty = false, ["string id"] = { "item", "15" },
        ["secret id"] = { "item", secret() }, ["secret kind"] = { secret(), 15 },
    }) do
        ctx.cursor, ctx.cleared = cursor or nil, false
        win.scripts.OnReceiveDrag(win)
        check("drop " .. name .. ": nothing changes", rowIDs(win), rows)
        check("drop " .. name .. ": cursor kept", ctx.cleared, false)
        check("drop " .. name .. ": nothing printed", #ctx.printed, 1)
    end

    ctx.cursor = { "item", 15 }
    local b = win.box.buttons[2]
    b.scripts.OnClick(b)
    check("drop on a row: looks up the held item instead", rowIDs(win), "15")
    check("drop on a row: cursor cleared", ctx.cursor, nil)
    ctx.run("browse chest")
    ctx.cursor = { "item", 15 }
    b = win.box.buttons[1]
    b.scripts.OnReceiveDrag(b)
    check("drop on a row: OnReceiveDrag", rowIDs(win), "15")

    ctx.run("browse chest")
    ctx.combat = true
    ctx.cursor, ctx.cleared = { "item", 15 }, false
    local before = #ctx.printed
    win.scripts.OnReceiveDrag(win)
    check("drop in combat: refused", ctx.printed[before + 1], "Tandem: not available in combat")
    check("drop in combat: list unchanged", rowIDs(win), rows)
    check("drop in combat: cursor kept", ctx.cleared, false)
end

do
    local ctx = loadBrowse("enUS", nil, nil, { env = { GetCursorInfo = false, ClearCursor = false } })
    ctx.run("browse chest")
    local win = ctx.win()
    win.scripts.OnReceiveDrag(win)
    check("drop without the cursor API is harmless", rowIDs(win), "11,1,3,4,2,12")
    local b = win.box.buttons[1]
    b.scripts.OnClick(b)
    check("click without the cursor API still selects", b.selected:IsShown(), true)

    ctx = loadBrowse("enUS", nil, nil, { env = { ClearCursor = false } })
    ctx.run("browse")
    ctx.cursor = { "item", 15 }
    ctx.win().scripts.OnReceiveDrag(ctx.win())
    check("drop without ClearCursor still looks up", rowIDs(ctx.win()), "15")
end

do
    local ctx = loadBrowse("zhTW")
    ctx.run("browse")
    ctx.cursor = { "item", 999 }
    ctx.win().scripts.OnReceiveDrag(ctx.win())
    check("zhTW drop unknown item", paneText(ctx.win())[1], "Tandem：未知的物品 999；請先掃描或拾取")
end

-- Deprecated flag: the optional 7th item field (stage 4, unit 4).

do
    local items = {
        [1] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1, 1 }, [2] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1, "1" },
        [3] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1, true }, [4] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1, 2 },
        [5] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1, 1, "extra" },
    }
    local addon, printed, env = loadWithDB({ schemaVersion = 3, items = items })
    local db = env.TandemDB
    check("deprecated: a 7th field of 1 is kept", db.items[1][7], 1)
    check("deprecated: a string 7th field is stripped", #db.items[2], 6)
    check("deprecated: a boolean 7th field is stripped", #db.items[3], 6)
    check("deprecated: another number is stripped", #db.items[4], 6)
    check("deprecated: fields after the flag are stripped", #db.items[5] .. " " .. db.items[5][7], "7 1")
    check("deprecated: a stripped flag is not a drop", #printed, 1)
    check("deprecated: the schema stays 3", db.schemaVersion, 3)
    check("deprecated: Advisor reads a flagged record", addon.Advisor.Item(1) ~= nil, true)
    check("deprecated: IsDeprecated of a flagged record", addon.Advisor.IsDeprecated(1), true)
    check("deprecated: IsDeprecated of a stripped record", addon.Advisor.IsDeprecated(2), false)
    check("deprecated: IsDeprecated of an unknown item", addon.Advisor.IsDeprecated(99), false)
end

do
    local Store = loadWithDB(nil).Store
    for name, case in pairs({
        plain = { "Deprecated Sword", true }, lower = { "deprecated sword", true }, upper = { "DEPRECATED", true },
        ["leading spaces"] = { "  Deprecated Sword", true }, ["later word"] = { "Sword (Deprecated)", false },
        empty = { "", false }, ["nil"] = { nil, false }, number = { 5, false }, ["plain name"] = { "Sword", false },
    }) do
        check("deprecated: IsDeprecatedName " .. name, Store.IsDeprecatedName(case[1]), case[2])
    end
end

do
    local addon, _, env = loadWithDB({ schemaVersion = 3 })
    local Store = addon.Store
    check("revision: a fresh load starts at 0", Store.revision, 0)
    Store.AddItem(1, 10, 5, 2, "INVTYPE_HEAD", 4, 1, true)
    check("revision: AddItem bumps it", Store.revision, 1)
    check("deprecated: AddItem flags with true", env.TandemDB.items[1][7], 1)
    Store.AddItem(2, 10, 5, 2, "INVTYPE_HEAD", 4, 1, false)
    Store.AddItem(3, 10, 5, 2, "INVTYPE_HEAD", 4, 1, "yes")
    Store.AddItem(4, 10, 5, 2, "INVTYPE_HEAD", 4, 1)
    check("deprecated: AddItem without true has no flag",
        #env.TandemDB.items[2] .. #env.TandemDB.items[3] .. #env.TandemDB.items[4], "666")
    local rev = Store.revision
    Store.AddItem(1, 10, 5, 2, "INVTYPE_HEAD", 4, 1)
    Store.AddLoot(0, "c", 1, 1)
    Store.SetNpcName(1, "")
    Store.AddKill(-1)
    check("revision: a refused change leaves it", Store.revision, rev)
    Store.AddLoot(1, "c", 448, 1429)
    Store.SetNpcName(448, "Hogger")
    Store.AddKill(448)
    Store.AddCorpse(448)
    check("revision: loot, names, kills and corpses bump it", Store.revision, rev + 4)
    Store.SetUIPosition("TOP", "TOP", 1, 2)
    Store.SetMinimapAngle(10)
    check("revision: ui settings are not records", Store.revision, rev + 4)
    Store.Load({ schemaVersion = 3 })
    check("revision: Load resets it", Store.revision, 0)
end

do
    local db, shipped = gearData()
    local addon, _, env = loadWithDB(db, "enUS", { shipped = shipped })
    local Store = addon.Store
    local count, unsaved, rev = Store.ItemCount(), Store.unsaved, Store.revision
    check("MarkDeprecated: an own record", Store.MarkDeprecated(1, addon.Advisor.Item(1)), true)
    check("MarkDeprecated: flags the own record", env.TandemDB.items[1][7], 1)
    check("MarkDeprecated: an own record adds no item", Store.ItemCount(), count)
    check("MarkDeprecated: is a record change", Store.unsaved .. " " .. Store.revision,
        (unsaved + 1) .. " " .. (rev + 1))
    check("MarkDeprecated: already flagged", Store.MarkDeprecated(1, addon.Advisor.Item(1)), false)
    check("MarkDeprecated: already flagged changes nothing", Store.revision, rev + 1)
    check("MarkDeprecated: a shipped record", Store.MarkDeprecated(2, addon.Advisor.Item(2)), true)
    local copy = env.TandemDB.items[2]
    check("MarkDeprecated: copies the shipped record into own items", copy and table.concat(copy, ","),
        "30,25,2,INVTYPE_ROBE,4,3,1")
    check("MarkDeprecated: the shipped table is left alone", #shipped.items[2], 6)
    check("MarkDeprecated: a copied record counts as known", Store.ItemCount(), count + 1)
    check("MarkDeprecated: Advisor sees the copy", addon.Advisor.IsDeprecated(2), true)
    check("MarkDeprecated: an unknown item without a record", Store.MarkDeprecated(999), false)
    check("MarkDeprecated: an invalid record", Store.MarkDeprecated(999, { 1, 2 }), false)
    check("MarkDeprecated: an invalid id", Store.MarkDeprecated(0, addon.Advisor.Item(4)), false)
    check("MarkDeprecated: nothing stored for refusals", env.TandemDB.items[999], nil)

    local newer = loadWithDB({ schemaVersion = 4, items = { [1] = { 1, 1, 1, "INVTYPE_HEAD", 4, 1 } } }).Store
    check("MarkDeprecated: a newer db is not written", newer.MarkDeprecated(1, { 1, 1, 1, "INVTYPE_HEAD", 4, 1 }),
        false)
    check("MarkDeprecated: a newer db keeps its record", newer.db.items[1][7], nil)
end

do
    local ctx = loadScanner({ [1] = equip, [2] = equip, [3] = equip, [4] = equip })
    local info = ctx.env.C_Item.GetItemInfo
    local names = { [2] = "Deprecated Helm", [3] = "  deprecated cap" }
    ctx.env.C_Item.GetItemInfo = function(id)
        if names[id] then
            return names[id], select(2, info(id))
        end
        return info(id)
    end
    ctx.Scanner.Start({ rate = 10, cap = 4 })
    ctx.tick(4)
    local items = ctx.env.TandemDB.items
    check("scan: a plain name is not flagged", #items[1], 6)
    check("scan: a deprecated name is flagged at cache time", items[2][7], 1)
    check("scan: a lower-case deprecated name with spaces is flagged", items[3][7], 1)
    check("scan: other fields are kept on a flagged item", items[2][4], "INVTYPE_HEAD")
end

-- Advisor: deprecated items, quality filter, off-hand flag and Rank's memo.

do
    local db, shipped = gearData()
    db.items[3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2, 1 }
    local A = loadAdvisor(db, shipped)
    check("advisor: List keeps a deprecated item by default", ids(A.List("chest", "WARRIOR", 40)), "11,1,3,4,2,12")
    check("advisor: List marks a deprecated row", A.List("chest", "WARRIOR", 40)[3].deprecated, true)
    check("advisor: List leaves other rows unmarked", A.List("chest", "WARRIOR", 40)[2].deprecated, nil)
    check("advisor: List hideDeprecated", ids(A.List("chest", "WARRIOR", 40, { hideDeprecated = true })),
        "11,1,4,2,12")
    check("advisor: List hideDeprecated in all slots",
        ids(A.List(nil, "WARRIOR", 40, { hideDeprecated = true, usableOnly = true })), "11,13,1,4,2,15,7,14,5,12")
    check("advisor: Best skips a deprecated item", ids(A.Best("chest", "WARRIOR", 40)), "1,4,2,12")
    check("advisor: Best all skips a deprecated item", ids(A.Best("chest", "WARRIOR", 40, { all = true })),
        "11,1,4,2,12")
    local r = A.Rank(3, "WARRIOR", 40)
    check("advisor: Rank of a deprecated item", r.rank .. "/" .. r.total .. " " .. tostring(r.deprecated), "2/5 true")
    r = A.Rank(4, "WARRIOR", 40)
    check("advisor: Rank skips deprecated items", r.rank .. "/" .. r.total .. " " .. tostring(r.deprecated),
        "2/4 nil")
    check("advisor: Place of a deprecated item", A.Place(3, "WARRIOR", 40).deprecated, true)

    check("advisor: List quality", ids(A.List("chest", "WARRIOR", 40, { quality = 3 })), "1,3,4")
    check("advisor: List quality 0 keeps only poor items", ids(A.List("chest", "WARRIOR", 40, { quality = 0 })), "")
    check("advisor: List quality 2 excludes better items", ids(A.List("chest", "WARRIOR", 40, { quality = 2 })), "2,12")
    check("advisor: List quality legendary", ids(A.List(nil, "WARRIOR", 40, { quality = 5 })), "11")
    check("advisor: List quality with the other filters", ids(A.List("chest", "WARRIOR", 30,
        { quality = 3, usableOnly = true, hideDeprecated = true })), "4")
end

do
    local A = loadAdvisor(gearData())
    local function offhandOf(list, id)
        for _, row in ipairs(list) do
            if row.id == id then
                return tostring(row.offhand)
            end
        end
    end
    check("advisor: an all-slots one-hander of a dual-wielder fills the off hand",
        offhandOf(A.List(nil, "WARRIOR", 40), 7), "true")
    check("advisor: an off-hand weapon is not flagged", offhandOf(A.List(nil, "WARRIOR", 40), 14), "nil")
    check("advisor: no off-hand flag before dual wield", offhandOf(A.List(nil, "WARRIOR", 19), 7), "nil")
    check("advisor: no off-hand flag for a non-dual-wielder", offhandOf(A.List(nil, "PALADIN", 40), 7), "nil")
    check("advisor: no off-hand flag in the main hand view", offhandOf(A.List("mainhand", "WARRIOR", 40), 7), "nil")
    check("advisor: no off-hand flag in the off hand view", offhandOf(A.List("offhand", "WARRIOR", 40), 7), "nil")
    check("advisor: Place of a dual-wield one-hander", A.Place(7, "WARRIOR", 40).offhand, true)
    check("advisor: Place of a one-hander before dual wield", A.Place(7, "WARRIOR", 19).offhand, nil)
    check("advisor: Rank carries the off-hand flag", A.Rank(7, "ROGUE", 20).offhand, true)
end

do
    local db, shipped = gearData()
    local addon = loadWithDB(db, "enUS", { shipped = shipped })
    local A, Store = addon.Advisor, addon.Store
    local item, calls = A.Item, 0
    A.Item = function(id)
        calls = calls + 1
        return item(id)
    end
    local function rank(id, level)
        calls = 0
        local r = A.Rank(id, "WARRIOR", level or 40)
        return r.rank .. "/" .. r.total
    end
    check("rank memo: first rank", rank(2), "4/5")
    check("rank memo: the first rank walks the items", calls > 2, true)
    check("rank memo: a second rank in the slot", rank(4), "3/5")
    check("rank memo: a second rank reuses the walk", calls, 2)
    Store.AddItem(30, 50, 30, 2, "INVTYPE_CHEST", 4, 1)
    check("rank memo: AddItem walks again", rank(2) .. " " .. tostring(calls > 2), "4/5 true")
    Store.AddLoot(30, "c", 448, 1429)
    check("rank memo: AddLoot walks again and sees the new source", rank(2) .. " " .. tostring(calls > 2), "5/6 true")
    check("rank memo: hit after AddLoot", rank(2) .. " " .. calls, "5/6 2")
    check("rank memo: a level change walks again", rank(2, 39) .. " " .. tostring(calls > 2), "4/5 true")
    check("rank memo: back to the old level walks again", rank(2) .. " " .. tostring(calls > 2), "5/6 true")
    Store.MarkDeprecated(30, A.Item(30))
    check("rank memo: MarkDeprecated walks again", rank(2) .. " " .. tostring(calls > 2), "4/5 true")
    rank(2)
    check("rank memo: other classes have their own walk", (function()
        calls = 0
        A.Rank(2, "PALADIN", 40)
        return calls > 2
    end)(), true)
    Store.Load({ schemaVersion = 3 })
    check("rank memo: a new db walks again", A.Rank(2, "WARRIOR", 40).total, 3)
end

-- Commands: deprecated items in /tandem rank and /tandem gear.

for locale, want in pairs({
    enUS = { built(3, BLUE) .. " (upgrade): rank 2 of 5 for Chest", "  this item is deprecated" },
    zhTW = { built(3, BLUE, "物品 #3") .. "（升級）：排名第 2／5（胸部）", "  此物品已棄用" },
}) do
    local db, shipped = gearData()
    db.items[3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2, 1 }
    local ctx = loadGear(locale, db, shipped)
    local out = ctx.run("rank 3")
    check(locale .. " rank deprecated item", out[1], want[1])
    check(locale .. " rank says the item is deprecated", out[2], want[2])
end

do
    local db, shipped = gearData()
    db.items[3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2, 1 }
    db.items[9] = { 1, 1, 1, "INVTYPE_BODY", 4, 0, 1 }
    local ctx = loadGear("enUS", db, shipped)
    local out = ctx.run("gear chest")
    check("gear chest skips a deprecated item", out[3] .. " / " .. out[4],
        "1. " .. built(1, BLUE) .. ", ilvl 45, level 40 (upgrade) / 2. " .. built(4, BLUE)
            .. ", ilvl 30, level 25 (upgrade)")
    check("gear chest without the deprecated item", #out, 7)
    check("rank of an unranked deprecated item says so", ctx.run("rank 9")[2], "  this item is deprecated")
    check("rank of a plain item says nothing more", ctx.run("rank 1")[2]:find("deprecated", 1, true), nil)
end

-- Store: browse window size in TandemDB.ui.window (unit 6).

do
    local ui = { window = { point = "TOP", x = 1, y = 2, width = 700, height = 600.5 } }
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = ui })
    local Store = addon.Store
    check("ui size: a valid size is kept", env.TandemDB.ui.window.width .. "x" .. env.TandemDB.ui.window.height,
        "700x600.5")
    check("ui size: a valid size is not a drop", #printed, 1)
    check("ui size: UISize returns it", table.concat({ Store.UISize() }, "x"), "700x600.5")
    check("ui size: UIPosition has no size", Store.UIPosition().width, nil)
    check("ui size: SetUISize saves", Store.SetUISize(800, 650), true)
    check("ui size: SetUISize writes the window", env.TandemDB.ui.window.width .. " " .. env.TandemDB.ui.window.point,
        "800 TOP")
    check("ui size: SetUISize is not a record", Store.unsaved .. " " .. Store.revision, "0 0")
    Store.SetUIPosition("LEFT", "LEFT", 5, 6)
    check("ui size: SetUIPosition keeps the size", table.concat({ Store.UISize() }, "x") .. " "
        .. env.TandemDB.ui.window.point, "800x650 LEFT")
    for name, size in pairs({
        zero = { 0, 600 }, ["too big"] = { 800, 10001 }, ["nil height"] = { 800 }, ["string width"] = { "800", 600 },
        NaN = { 0 / 0, 600 }, huge = { math.huge, 600 },
    }) do
        check("ui size: SetUISize rejects " .. name, Store.SetUISize(size[1], size[2]), false)
    end
    check("ui size: a rejected size keeps the old one", table.concat({ Store.UISize() }, "x"), "800x650")
end

do
    local Store = loadWithDB({ schemaVersion = 3 }).Store
    check("ui size: SetUISize without a position", Store.SetUISize(800, 600), false)
    check("ui size: nothing saved without a position", Store.UISize(), nil)
    Store.SetUIPosition("TOP", "TOP", 0, 0)
    check("ui size: no size until one is saved", Store.UISize(), nil)
    local newer = loadWithDB({ schemaVersion = 4, ui = { window = { point = "TOP", x = 0, y = 0, width = 900,
                                                                    height = 700 } } }).Store
    check("ui size: a newer db still gives a valid size", table.concat({ newer.UISize() }, "x"), "900x700")
    check("ui size: a newer db is not written", newer.SetUISize(800, 600), false)
end

for name, window in pairs({
    ["width only"] = { point = "TOP", x = 1, y = 2, width = 700 },
    ["height only"] = { point = "TOP", x = 1, y = 2, height = 700 },
    ["zero width"] = { point = "TOP", x = 1, y = 2, width = 0, height = 700 },
    ["string height"] = { point = "TOP", x = 1, y = 2, width = 700, height = "700" },
    ["far width"] = { point = "TOP", x = 1, y = 2, width = 10001, height = 700 },
}) do
    local addon, printed, env = loadWithDB({ schemaVersion = 3, ui = { window = window } })
    local w = env.TandemDB.ui and env.TandemDB.ui.window
    check("ui size: " .. name .. " keeps the position", w and w.point .. " " .. w.x .. " " .. w.y, "TOP 1 2")
    check("ui size: " .. name .. " is stripped", tostring(w and w.width) .. " " .. tostring(w and w.height), "nil nil")
    check("ui size: " .. name .. " counts one drop", printed[2], "Tandem: dropped 1 invalid saved entries")
    check("ui size: " .. name .. " gives no size", addon.Store.UISize(), nil)
end

-- Browse: off-hand marks in All slots (unit 3).

local function buttonFor(win, id)
    for _, b in ipairs(win.box.buttons) do
        if b.row and b.row.id == id and b.row.slot == "mainhand" then
            return b
        end
    end
end

do
    local ctx = loadBrowse()
    ctx.cache[781] = { "Axe", "|Hitem:781:|h", 2, 30 }
    ctx.equipped[16] = "|Hitem:781:|h"
    ctx.equipped[17] = "|Hitem:14:|h"
    ctx.run("browse")
    local win = ctx.win()
    local sword = "|cff1eff00item #7|r"
    check("hands: beats the weaker hand", buttonFor(win, 7).name:GetText(), sword .. GREY .. " (upgrade)|r")
    ctx.run("browse mainhand")
    check("hands: the main hand view compares with the main hand only", buttonFor(win, 7).name:GetText(), sword)
    ctx.run("browse")
    ctx.run("browse")

    ctx.equipped[17] = "|Hitem:7:|h"
    ctx.fire("PLAYER_EQUIPMENT_CHANGED", 17, false)
    check("hands: equipped in the off hand", buttonFor(win, 7).name:GetText(), sword .. GREY .. " (equipped)|r")

    ctx.equipped[16], ctx.equipped[17] = "|Hitem:15:|h", nil
    ctx.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    check("hands: the off hand behind a two-hander is ignored", buttonFor(win, 7).name:GetText(), sword)

    ctx.equipped[16] = "|Hitem:781:|h"
    ctx.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    check("hands: an empty off hand is beaten", buttonFor(win, 7).name:GetText(), sword .. GREY .. " (upgrade)|r")

    ctx.equipped[16] = secret()
    ctx.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    check("hands: no hand ilvl known gives no upgrade", buttonFor(win, 7).name:GetText(), sword)

    ctx.equipped[16] = "|Hitem:781:|h"
    ctx.class, ctx.className = "PALADIN", "Paladin"
    ctx.run("browse")
    ctx.run("browse")
    check("hands: a non-dual-wielder compares with the main hand only", buttonFor(win, 7).name:GetText(), sword)

    local hands = ctx.addon.View.EquippedHands()
    local worn = {}
    for id in pairs(hands.ids) do
        worn[#worn + 1] = id
    end
    check("hands: EquippedHands merges both hands", #worn .. " " .. #hands.list .. " " .. hands.ilvl, "1 2 0")
end

-- Browse: Hide deprecated (unit 4).

do
    local db, shipped = gearData()
    db.items[3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2, 1 }
    local ctx = loadBrowse("enUS", db, shipped)
    ctx.equipped[5] = "|Hitem:1:|h"
    ctx.cache[4] = { "Deprecated Robe", "|cff0070dd|Hitem:4::::|h[Deprecated Robe]|h|r", 3, 30 }
    local count = ctx.addon.Store.ItemCount()
    ctx.run("browse chest")
    local win = ctx.win()
    check("browse deprecated: hidden by default", win.deprecated:GetChecked(), true)
    check("browse deprecated: a flagged item and a cached deprecated name are hidden", rowIDs(win), "11,1,2,12")
    check("browse deprecated: the count follows", win.count:GetText(), "4 items")
    check("browse deprecated: the peek flags the shipped item", ctx.env.TandemDB.items[4][7], 1)
    check("browse deprecated: the flagged copy is a known item", ctx.addon.Store.ItemCount(), count + 1)
    check("browse deprecated: the peek asks the client for nothing", ctx.requested[4], nil)

    win.deprecated:SetChecked(false)
    win.deprecated:GetScript("OnClick")(win.deprecated)
    check("browse deprecated: unticking lists them", rowIDs(win), "11,1,3,4,2,12")
    local b = win.box.buttons
    check("browse deprecated: a flagged row is marked", b[3].name:GetText(),
        "|cff0070dditem #3|r" .. GREY .. " (deprecated)|r")
    check("browse deprecated: a named flagged row is marked", b[4].name:GetText(),
        "|cff0070ddDeprecated Robe|r" .. GREY .. " (deprecated)|r")

    win.deprecated:SetChecked(true)
    win.deprecated:GetScript("OnClick")(win.deprecated)
    ctx.cache[2] = { "Deprecated Mail", "|cff1eff00|Hitem:2::::|h[Deprecated Mail]|h|r", 2, 30 }
    ctx.fire("GET_ITEM_INFO_RECEIVED", 2, true)
    ctx.tick()
    check("browse deprecated: a name loaded while shown flags the item", ctx.env.TandemDB.items[2][7], 1)
    check("browse deprecated: the row stays until the next listing", rowIDs(win), "11,1,2,12")
    check("browse deprecated: the row is marked", win.box.buttons[3].name:GetText(),
        "|cff1eff00Deprecated Mail|r" .. GREY .. " (deprecated)|r")
    ctx.run("browse chest")
    check("browse deprecated: the next listing hides it", rowIDs(win), "11,1,12")

    ctx.cursor = { "item", 3 }
    win.scripts.OnReceiveDrag(win)
    check("browse deprecated: dropping a deprecated item unticks the box", win.deprecated:GetChecked(), false)
    check("browse deprecated: the dropped item is listed", rowIDs(win), "11,1,3,4,2,12")
    win.deprecated:SetChecked(true)
    ctx.cache[13] = { "Deprecated Legs", "|cff0070dd|Hitem:13::::|h[Deprecated Legs]|h|r", 3, 50 }
    ctx.cursor = { "item", 13 }
    win.scripts.OnReceiveDrag(win)
    check("browse deprecated: dropping an item with a cached deprecated name unticks the box",
        win.deprecated:GetChecked(), false)
    check("browse deprecated: and flags it", ctx.env.TandemDB.items[13][7], 1)
    win.deprecated:SetChecked(true)
    ctx.cursor = { "item", 1 }
    win.scripts.OnReceiveDrag(win)
    check("browse deprecated: dropping a plain item keeps the box", win.deprecated:GetChecked(), true)
end

do
    local db, shipped = gearData()
    db.items[3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2, 1 }
    local ctx = loadBrowse("enUS", db, shipped)
    ctx.addon.Store.readOnly = true
    ctx.cache[4] = { "Deprecated Robe", "|cff0070dd|Hitem:4::::|h[Deprecated Robe]|h|r", 3, 30 }
    ctx.run("browse chest")
    check("browse deprecated: a read-only db cannot flag, so the item stays", rowIDs(ctx.win()), "11,1,4,2,12")
end

-- Browse: quality filter (unit 5).

do
    local ctx = loadBrowse()
    ctx.run("browse chest")
    local win = ctx.win()
    local menu = radios(win.quality)
    check("browse quality: dropdown template", win.quality.template, "WowStyle1DropdownTemplate")
    check("browse quality: all qualities and six qualities", #menu, 7)
    check("browse quality: first radio", menu[1].text .. " " .. tostring(menu[1].data), "All qualities nil")
    check("browse quality: all qualities by default", menu[1].isSelected(menu[1].data), true)
    check("browse quality: poor in its colour", menu[2].text .. " " .. menu[2].data, "|cff9d9d9dPoor|r 0")
    check("browse quality: rare in its colour", menu[5].text .. " " .. menu[5].data, "|cff0070ddRare|r 3")
    check("browse quality: legendary last", menu[7].text .. " " .. menu[7].data, "|cffff8000Legendary|r 5")
    menu[5].setSelected(menu[5].data)
    check("browse quality: only rare", rowIDs(win), "1,3,4")
    check("browse quality: rare is selected", menu[5].isSelected(3) and not menu[1].isSelected(nil), true)
    check("browse quality: the count follows", win.count:GetText(), "3 items")
    ctx.run("browse twohand")
    check("browse quality: kept across slots", rowIDs(win), "")
    ctx.run("browse chest")

    ctx.cursor = { "item", 1 }
    win.scripts.OnReceiveDrag(win)
    check("browse quality: dropping an item of that quality keeps it", menu[5].isSelected(3), true)
    ctx.cursor = { "item", 11 }
    win.scripts.OnReceiveDrag(win)
    check("browse quality: dropping a better item resets it too", menu[1].isSelected(nil), true)
    menu[5].setSelected(menu[5].data)
    ctx.cursor = { "item", 12 }
    win.scripts.OnReceiveDrag(win)
    check("browse quality: dropping an item of another quality resets it", menu[1].isSelected(nil), true)
    check("browse quality: the dropped item is listed", rowIDs(win), "11,1,3,4,2,12")
    menu[7].setSelected(menu[7].data)
    ctx.cursor = { "item", 9 }
    win.scripts.OnReceiveDrag(win)
    check("browse quality: an item without a ranked slot keeps it", menu[7].isSelected(5), true)
    menu[1].setSelected(menu[1].data)
    check("browse quality: all again", rowIDs(win), "11,13,1,3,4,2,15,7,14,5,12")
end

-- Browse: wider, resizable window (unit 6).

local function point(w, i)
    local p = w.points[i or 1]
    local rel = p[2]
    rel = type(rel) == "table" and (rel.name or rel.kind) or tostring(rel)
    return ("%s %s %s %s %s"):format(p[1], rel, tostring(p[3]), tostring(p[4]), tostring(p[5]))
end

do
    local ctx = loadBrowse()
    ctx.run("browse")
    local win = ctx.win()
    check("browse size: wider default", win.width .. "x" .. win.height, "640x620")
    check("browse size: resizable", win.resizable, true)
    check("browse size: bounds", table.concat(win.bounds, ","), "520,480,1200,1000")
    local grip = win.grip
    check("browse size: a grip", grip and grip.kind .. " " .. grip.width .. "x" .. grip.height, "Button 16x16")
    check("browse size: the grip sits at the bottom-right corner", point(grip),
        "BOTTOMRIGHT TandemBrowseFrame BOTTOMRIGHT -4 4")
    check("browse size: grip textures", grip.normal .. " " .. grip.pushed .. " " .. grip.highlight,
        "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down "
            .. "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip.scripts.OnMouseDown(grip)
    check("browse size: the grip sizes from the corner", win.sizing, "BOTTOMRIGHT")
    win.width, win.height = 800, 700
    win.points = { { "TOPLEFT", ctx.env.UIParent, "BOTTOMLEFT", 100, 750 } }
    grip.scripts.OnMouseUp(grip)
    check("browse size: sizing stops", win.sizing, nil)
    local saved = ctx.env.TandemDB.ui.window
    check("browse size: the size is saved with the position", ("%s %s %d %d %dx%d"):format(saved.point,
        saved.relativePoint, saved.x, saved.y, saved.width, saved.height), "TOPLEFT BOTTOMLEFT 100 750 800x700")
    check("browse size: saving is not a record", ctx.addon.Store.unsaved, 0)
    win.points = { { "TOP", ctx.env.UIParent, "TOP", 0, -20 } }
    win.scripts.OnDragStop(win)
    saved = ctx.env.TandemDB.ui.window
    check("browse size: moving keeps the size", saved.point .. " " .. saved.width .. "x" .. saved.height, "TOP 800x700")

    check("browse layout: slot dropdown", point(win.dropdown), "TOPLEFT TandemBrowseFrame TOPLEFT 12 -30")
    check("browse layout: quality dropdown beside it", point(win.quality) .. " " .. tostring(win.quality.points[1][2]
        == win.dropdown), "LEFT DropdownButton RIGHT 12 0 true")
    check("browse layout: count at the top right", point(win.count), "TOPRIGHT TandemBrowseFrame TOPRIGHT -14 -36")
    check("browse layout: usable only starts the second row", point(win.usable),
        "TOPLEFT TandemBrowseFrame TOPLEFT 12 -58")
    check("browse layout: hide deprecated follows the usable label",
        win.deprecated.points[1][2].text .. " " .. win.deprecated.points[1][1], "Usable only LEFT")
    check("browse layout: the minimap box follows the deprecated label",
        win.minimap.points[1][2].text .. " " .. win.minimap.points[1][1], "Hide deprecated LEFT")
    check("browse layout: the list stretches with the window", point(win.box) .. " / " .. point(win.box, 2),
        "TOPLEFT TandemBrowseFrame TOPLEFT 12 -138 / BOTTOMRIGHT TandemBrowseFrame BOTTOMRIGHT -26 118")

    local again = loadBrowse("enUS", { schemaVersion = 3, ui = ctx.env.TandemDB.ui }, select(2, gearData()))
    again.run("browse")
    check("browse size: restores the saved size", again.win().width .. "x" .. again.win().height, "800x700")
end

for name, case in pairs({
    ["too large"] = { 2000, 1500, nil, "1200x1000" },
    ["too small"] = { 100, 50, nil, "520x480" },
    ["larger than the screen"] = { 1100, 900, { 1000, 700 }, "1000x700" },
    ["a screen below the minimum"] = { 600, 500, { 400, 300 }, "520x480" },
}) do
    local db, shipped = gearData()
    db.ui = { window = { point = "TOP", x = 0, y = 0, width = case[1], height = case[2] } }
    local env
    if case[3] then
        env = { UIParent = { name = "UIParent", GetSize = function()
            return case[3][1], case[3][2]
        end } }
    end
    local ctx = loadBrowse("enUS", db, shipped, { env = env })
    ctx.run("browse")
    check("browse size: a saved size " .. name .. " is clamped", ctx.win().width .. "x" .. ctx.win().height, case[4])
end

do
    local ctx = loadBrowse("enUS", nil, nil, { noResizeBounds = true })
    ctx.run("browse")
    local win = ctx.win()
    check("browse size: min and max without SetResizeBounds",
        table.concat(win.minResize, ",") .. " " .. table.concat(win.maxResize, ","), "520,480 1200,1000")

    local db, shipped = gearData()
    db.ui = { window = { point = "TOP", x = 0, y = 0, width = 900, height = 700 } }
    ctx = loadBrowse("enUS", db, shipped, { noResize = true })
    ctx.run("browse")
    win = ctx.win()
    check("browse size: no resize API, no grip", win.grip, nil)
    check("browse size: no resize API, fixed default size", win.width .. "x" .. win.height, "640x620")
    win.width, win.height = 300, 300
    win.scripts.OnDragStop(win)
    check("browse size: no resize API, moving leaves the saved size", ctx.env.TandemDB.ui.window.width, 900)
end

do
    local db, shipped = gearData()
    db.items[3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2, 1 }
    local ctx = loadBrowse("zhTW", db, shipped)
    ctx.equipped[5] = "|Hitem:1:|h"
    ctx.run("browse chest")
    local win = ctx.win()
    local menu = radios(win.quality)
    check("zhTW browse all qualities", menu[1].text, "所有品質")
    local names = {}
    for i = 2, 7 do
        names[#names + 1] = menu[i].text:match("^|cff%x+(.-)|r$")
    end
    check("zhTW browse quality names", table.concat(names, ","), "粗糙,普通,優秀,精良,史詩,傳說")
    check("zhTW browse hide deprecated", win.minimap.points[1][2].text, "隱藏已棄用")
    win.deprecated:SetChecked(false)
    win.deprecated:GetScript("OnClick")(win.deprecated)
    check("zhTW browse deprecated mark", win.box.buttons[3].name:GetText(),
        "|cff0070dd物品 #3|r" .. GREY .. "（已棄用）|r")
end

-- Cached-name peeks never ask the server: only ids IsItemDataCachedByID knows, each once per session.

do
    local ctx = loadGear()
    local View = ctx.addon.View
    check("CachedName: an uncached item", View.CachedName(1), nil)
    check("CachedName: an uncached item is not passed to GetItemInfo", ctx.infoCalls[1], nil)
    ctx.cache[1] = { "Plate Chest", "|Hitem:1:|h", 4, 45 }
    check("CachedName: a cached item", View.CachedName(1), "Plate Chest")
    check("CachedName: a cached item is read", ctx.infoCalls[1], 1)
    ctx.env.C_Item.IsItemDataCachedByID = function()
        return secret()
    end
    check("CachedName: a secret answer is no", View.CachedName(1), nil)
    ctx.env.C_Item.IsItemDataCachedByID = nil
    check("CachedName: without IsItemDataCachedByID", View.CachedName(1), nil)
    check("CachedName: without IsItemDataCachedByID nothing is read", ctx.infoCalls[1], 1)
end

do
    local ctx = loadBrowse()
    ctx.cache[4] = { "Cloth Robe", "|cff0070dd|Hitem:4::::|h[Cloth Robe]|h|r", 3, 30 }
    ctx.run("browse chest")
    check("browse peek: an uncached row is read only to draw it", ctx.infoCalls[2], 1)
    check("browse peek: a cached row is peeked, then drawn", ctx.infoCalls[4], 2)
    ctx.run("browse chest")
    check("browse peek: an uncached row is not peeked on the next refresh", ctx.infoCalls[2], 2)
    check("browse peek: a cached row is peeked once per session", ctx.infoCalls[4], 3)
    ctx.cursor = { "item", 15 }
    ctx.win().scripts.OnReceiveDrag(ctx.win())
    -- One read for its row, one for the sources pane's link; none to peek.
    check("browse peek: dropping an uncached item reads it only to draw it", ctx.infoCalls[15], 2)
end

do
    local ctx = loadBrowse()
    ctx.env.C_Item.IsItemDataCachedByID = nil
    ctx.cache[4] = { "Deprecated Robe", "|cff0070dd|Hitem:4::::|h[Deprecated Robe]|h|r", 3, 30 }
    ctx.equipped[5] = "|Hitem:1:|h"
    ctx.run("browse chest")
    local win = ctx.win()
    check("browse peek: without IsItemDataCachedByID a deprecated name is not peeked", rowIDs(win), "11,1,3,4,2,12")
    check("browse peek: drawing the row still flags and marks it", win.box.buttons[4].name:GetText(),
        "|cff0070ddDeprecated Robe|r" .. GREY .. " (deprecated)|r")
    ctx.run("browse chest")
    check("browse peek: the next listing hides it", rowIDs(win), "11,1,3,2,12")
end

do
    local db, shipped = gearData()
    local addon = loadWithDB(db, "enUS", { shipped = shipped })
    check("rank memo: total before the shipped data changes", addon.Advisor.Rank(2, "WARRIOR", 40).total, 5)
    local more = { items = {}, loot = {} }
    for id, r in pairs(shipped.items) do
        more.items[id] = r
    end
    for i, r in ipairs(shipped.loot) do
        more.loot[i] = r
    end
    more.items[40] = { 35, 30, 2, "INVTYPE_CHEST", 4, 1 }
    more.loot[#more.loot + 1] = { 40, "c", 500, 1429, 1 }
    addon.Shipped = more
    local r = addon.Advisor.Rank(2, "WARRIOR", 40)
    check("rank memo: replacing ns.Shipped walks again", r.rank .. "/" .. r.total, "5/6")
end

-- Tooltip (stage 4 unit 2): the Tandem lines on item tooltips.

-- A fake tooltip: AddLine records { text, r, g, b, wrap }; forbidden makes IsForbidden true.
local function fakeTooltip()
    local t = { lines = {}, forbidden = false }
    function t.AddLine(self, text, r, g, b, wrap)
        self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b, wrap = wrap }
    end
    function t.IsForbidden(self)
        return self.forbidden
    end
    return t
end

local function texts(tooltip)
    local out = {}
    for _, l in ipairs(tooltip.lines) do
        out[#out + 1] = l.text
    end
    return table.concat(out, " / ")
end

local function colour(line)
    return line and (line.r .. "," .. line.g .. "," .. line.b) or "nil"
end

-- Loads gearData() plus named sources with the tooltip API stubbed; ctx.hover(id [, tooltip]) clears the tooltip,
-- runs the captured post-call with { id = id } and returns the tooltip.
local function loadTooltip(locale, db, shipped, opts)
    opts = opts or {}
    if not db then
        db, shipped = gearData()
        db.npcs = { [448] = "Hogger" }
        db.kills = { [448] = 4 }
        db.corpses = { [449] = 2 }
        db.loot["3:c:449:1429"] = { item = 3, kind = "c", id = 449, map = 1429, count = 1 }
        db.loot["9:c:448:1429"] = { item = 9, kind = "c", id = 448, map = 1429, count = 1 }
        -- Item 50 has a source but no record until a test adds one.
        shipped.loot[#shipped.loot + 1] = { 50, "c", 500, 1429, 1 }
    end
    local hooks = {}
    local env = {
        GameTooltip = fakeTooltip(),
        ItemRefTooltip = fakeTooltip(),
        Enum = { TooltipDataType = { Item = 0 } },
        TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
            hooks[#hooks + 1] = { kind = kind, fn = fn }
        end },
    }
    if opts.noAPI then
        env.TooltipDataProcessor = nil
    end
    local ctx = loadGear(locale or "enUS", db, shipped, { env = env })
    ctx.hooks = hooks
    function ctx.hover(data, tooltip)
        tooltip = tooltip or ctx.env.GameTooltip
        tooltip.lines = {}
        hooks[1].fn(tooltip, data)
        return tooltip
    end
    function ctx.text(id, tooltip)
        return texts(ctx.hover({ id = id }, tooltip))
    end
    return ctx
end

do
    local ctx = loadTooltip()
    check("tooltip: one post-call registered", #ctx.hooks, 1)
    check("tooltip: registered for item tooltips", ctx.hooks[1].kind, 0)
    check("tooltip: the post-call is Tooltip.OnItem", ctx.hooks[1].fn, ctx.addon.Tooltip.OnItem)
    local before = #ctx.printed

    local t = ctx.hover({ id = 1 })
    check("tooltip: rank, upgrade and kill-rate source", texts(t),
        "Tandem: rank 1 of 5 for Chest (upgrade) / Tandem: drops from Hogger, Elwynn Forest (25.0% per kill)")
    check("tooltip: rank line is blue", colour(t.lines[1]), "0.4,0.8,1")
    check("tooltip: source line is grey-white", colour(t.lines[2]), "0.8,0.8,0.8")
    check("tooltip: lines do not wrap", t.lines[1].wrap, false)

    check("tooltip: corpse-rate source with more", ctx.text(3),
        "Tandem: rank 2 of 5 for Chest (upgrade) / Tandem: drops from npc #449, Elwynn Forest (up to 50.0%) (+1 more)")
    check("tooltip: source without a rate", ctx.text(2),
        "Tandem: rank 4 of 5 for Chest (upgrade) / Tandem: drops from npc #500, Elwynn Forest")
    check("tooltip: unsourced item has only the rank line", ctx.text(11),
        "Tandem: rank 1 of 6 for Chest (upgrade) (no known source)")
    check("tooltip: no ranked slot shows only the source", ctx.text(9),
        "Tandem: drops from Hogger, Elwynn Forest (25.0% per kill)")
    check("tooltip: ItemRefTooltip gets the lines too", ctx.text(2, ctx.env.ItemRefTooltip),
        "Tandem: rank 4 of 5 for Chest (upgrade) / Tandem: drops from npc #500, Elwynn Forest")

    ctx.equipped[5] = "|Hitem:1:|h"
    check("tooltip: equipped mark", ctx.text(1),
        "Tandem: rank 1 of 5 for Chest (equipped) / Tandem: drops from Hogger, Elwynn Forest (25.0% per kill)")
    ctx.equipped[5] = nil

    ctx.level = 30
    t = ctx.hover({ id = 1 })
    check("tooltip: too low a level gives no upgrade and a red line", texts(t),
        "Tandem: rank 1 of 5 for Chest / Tandem: you cannot use it: level 40 required"
            .. " / Tandem: drops from Hogger, Elwynn Forest (25.0% per kill)")
    check("tooltip: unusable line is red", colour(t.lines[2]), "1,0.25,0.25")
    ctx.class, ctx.className, ctx.level = "MAGE", "Mage", 60
    t = ctx.hover({ id = 1 })
    check("tooltip: class cannot use it", t.lines[2] and t.lines[2].text, "Tandem: your class cannot use it")
    check("tooltip: class line is red", colour(t.lines[2]), "1,0.25,0.25")
    ctx.class, ctx.className, ctx.level = "WARRIOR", "Warrior", 40

    -- Nothing at all.
    ctx.combat = true
    check("tooltip: nothing in combat", ctx.text(1), "")
    ctx.combat = false
    ctx.env.GameTooltip.forbidden = true
    check("tooltip: nothing on a forbidden tooltip", ctx.text(1), "")
    ctx.env.GameTooltip.forbidden = false
    check("tooltip: nothing on a shopping tooltip", ctx.text(1, fakeTooltip()), "")
    check("tooltip: nothing for an unknown item", ctx.text(999), "")
    check("tooltip: nothing for a secret id", ctx.text(secret()), "")
    check("tooltip: nothing for secret data", texts(ctx.hover(secret())), "")
    check("tooltip: nothing without data", texts(ctx.hover(nil)), "")
    for _, bad in ipairs({ 0, -1, 1.5, "1" }) do
        check("tooltip: nothing for id " .. tostring(bad), ctx.text(bad), "")
    end
    ctx.class = nil
    check("tooltip: nothing while the class is unknown", ctx.text(1), "")
    ctx.class = "WARRIOR"
    check("tooltip: hovering never prints", #ctx.printed, before)
    check("tooltip: /tandem rank still prints when the class is unknown", (function()
        ctx.class = nil
        local out = ctx.run("rank 1")
        ctx.class = "WARRIOR"
        return out[1]
    end)(), "Tandem: your class or level is not known yet; try again in a moment")
end

do
    local ctx = loadTooltip(nil, nil, nil, { noAPI = true })
    check("tooltip: no post-call without the API", #ctx.hooks, 0)
    check("tooltip: the module still loads", type(ctx.addon.Tooltip.OnItem), "function")
    local db, shipped = gearData()
    local addon = loadWithDB(db, "enUS", { shipped = shipped, env = { Enum = {}, TooltipDataProcessor = {} } })
    check("tooltip: an API without AddTooltipPostCall is ignored", type(addon.Tooltip), "table")
end

-- Deprecated items: one grey line, from the record or from the client's name.
do
    local db, shipped = gearData()
    db.items[3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2, 1 }
    local ctx = loadTooltip("enUS", db, shipped)
    local t = ctx.hover({ id = 3 })
    check("tooltip: a deprecated record shows one line", texts(t), "Tandem: deprecated item")
    check("tooltip: the deprecated line is grey", colour(t.lines[1]), "0.5,0.5,0.5")
    ctx.cache[1] = { "Deprecated Plate", "|Hitem:1:|h", 3, 45 }
    check("tooltip: a deprecated client name flags the item", ctx.text(1), "Tandem: deprecated item")
    check("tooltip: the flag is stored", ctx.addon.Advisor.IsDeprecated(1), true)
end

-- One-handers of a dual-wielder compare against both hands.
do
    local ctx = loadTooltip()
    ctx.cache[778] = { "Main", "|Hitem:778:|h", 2, 30 }
    ctx.cache[779] = { "Off", "|Hitem:779:|h", 2, 20 }
    ctx.equipped[16] = "|Hitem:778:|h"
    ctx.equipped[17] = "|Hitem:779:|h"
    local line = ctx.hover({ id = 7 }).lines[1].text
    check("tooltip hands: beats the weaker hand", line:match("%(upgrade%)$") ~= nil, true)
    ctx.equipped[16], ctx.equipped[17] = "|Hitem:779:|h", "|Hitem:7:|h"
    line = ctx.hover({ id = 7 }).lines[1].text
    check("tooltip hands: equipped in the off hand", line:match("%(equipped%)$") ~= nil, true)
    ctx.equipped[16], ctx.equipped[17] = "|Hitem:778:|h", "|Hitem:779:|h"
    ctx.class, ctx.className = "PALADIN", "Paladin"
    line = ctx.hover({ id = 7 }).lines[1].text
    check("tooltip hands: a non-dual-wielder compares with the main hand only", line:match("%(upgrade%)") == nil, true)
    ctx.class, ctx.className = "WARRIOR", "Warrior"
    ctx.cache[777] = { "Great", "|Hitem:777:|h", 2, 30 }
    ctx.instant[777] = "INVTYPE_2HWEAPON"
    ctx.equipped[16], ctx.equipped[17] = "|Hitem:777:|h", nil
    line = ctx.hover({ id = 7 }).lines[1].text
    check("tooltip hands: an off hand behind a two-hander is ignored", line:match("%(upgrade%)") == nil, true)
end

-- The per-item memo: one Rank and one Sources per item until a record changes or the level does.
do
    local ctx = loadTooltip()
    local A = ctx.addon.Advisor
    local calls = { rank = 0, sources = 0 }
    local rank, sources = A.Rank, A.Sources
    A.Rank = function(...)
        calls.rank = calls.rank + 1
        return rank(...)
    end
    A.Sources = function(...)
        calls.sources = calls.sources + 1
        return sources(...)
    end
    local function counts()
        return calls.rank .. "/" .. calls.sources
    end
    ctx.hover({ id = 2 })
    ctx.hover({ id = 2 })
    check("tooltip memo: a second hover reuses the first", counts(), "1/1")
    ctx.equipped[5] = "|Hitem:2:|h"
    check("tooltip memo: worn marks are not memoised", ctx.text(2):find("(equipped)", 1, true) ~= nil, true)
    check("tooltip memo: still one walk", counts(), "1/1")
    ctx.addon.Store.AddItem(50, 60, 30, 4, "INVTYPE_CHEST", 4, 4)
    check("tooltip memo: AddItem invalidates it", ctx.text(2),
        "Tandem: rank 5 of 6 for Chest (equipped) / Tandem: drops from npc #500, Elwynn Forest")
    check("tooltip memo: AddItem walks again", counts(), "2/2")
    ctx.addon.Store.AddLoot(2, "c", 448, 1429)
    check("tooltip memo: AddLoot invalidates it", ctx.text(2),
        "Tandem: rank 5 of 6 for Chest (equipped)"
            .. " / Tandem: drops from Hogger, Elwynn Forest (25.0% per kill) (+1 more)")
    check("tooltip memo: AddLoot walks again", counts(), "3/3")
    ctx.level = 41
    ctx.hover({ id = 2 })
    check("tooltip memo: a level-up walks again", counts(), "4/4")
    ctx.hover({ id = 1 })
    check("tooltip memo: another item has its own entry", counts(), "5/5")
end

for locale, want in pairs({
    enUS = { "Tandem: rank 1 of 5 for Chest (upgrade) / Tandem: drops from Hogger, Elwynn Forest (25.0% per kill)",
             "Tandem: drops from npc #449, Elwynn Forest (up to 50.0%) (+1 more)",
             "Tandem: you cannot use it: level 40 required", "Tandem: your class cannot use it",
             "Tandem: deprecated item" },
    zhTW = { "Tandem：排名第 1／5（胸部）（升級） / Tandem：掉落自 Hogger，Elwynn Forest（每次擊殺 25.0%）",
             "Tandem：掉落自 NPC #449，Elwynn Forest（最高 50.0%）（另有 1 個來源）",
             "Tandem：你無法使用：需要等級 40", "Tandem：你的職業無法使用", "Tandem：已棄用的物品" },
}) do
    local ctx = loadTooltip(locale)
    check(locale .. " tooltip rank and source", ctx.text(1), want[1])
    check(locale .. " tooltip corpse source", ctx.hover({ id = 3 }).lines[2].text, want[2])
    ctx.level = 30
    check(locale .. " tooltip level line", ctx.hover({ id = 1 }).lines[2].text, want[3])
    ctx.class, ctx.level = "MAGE", 60
    check(locale .. " tooltip class line", ctx.hover({ id = 1 }).lines[2].text, want[4])
    ctx.addon.Store.MarkDeprecated(4, ctx.addon.Advisor.Item(4))
    check(locale .. " tooltip deprecated line", ctx.text(4), want[5])
end

-- Quest and vendor sources in the display (stage 5, unit 4).

-- Item 4: own quest 100 (Alliance) and vendor 200 (Horde), own drop from 448; shipped quest 100 (Horde, so both),
-- quest 101 (no factions), vendor 201 (Alliance) and quest 102 (an invalid factions mask).
local function questVendorData()
    local db = {
        schemaVersion = 3,
        npcs = { [200] = "Vendor Bob", [448] = "Hogger" },
        quests = { [100] = "Own Quest" },
        loot = {
            ["4:q:100:1429"] = { item = 4, kind = "q", id = 100, map = 1429, count = 1, factions = 1 },
            ["4:v:200:1429"] = { item = 4, kind = "v", id = 200, map = 1429, count = 1, factions = 2 },
            ["4:c:448:1429"] = { item = 4, kind = "c", id = 448, map = 1429, count = 5 },
        },
        kills = { [448] = 10 },
    }
    local shipped = {
        loot = { { 4, "q", 100, 1429, 3 }, { 4, "q", 101, 0, 1 }, { 4, "v", 201, 1429, 2 }, { 4, "q", 102, 1429, 1 } },
        factions = { ["4:q:100:1429"] = 2, ["4:v:201:1429"] = 1, ["4:q:102:1429"] = 7 },
        questNames = { enUS = { [101] = "Shipped Quest" }, zhTW = { [101] = "運送任務" } },
    }
    return db, shipped
end

local function sourceRows(rows)
    local out = {}
    for _, s in ipairs(rows) do
        out[#out + 1] = ("%s%d:%d:%s:%s:%s"):format(s.kind, s.id, s.count, tostring(s.factions), tostring(s.name),
            tostring(s.otherFaction))
    end
    return table.concat(out, " ")
end

do
    local db, shipped = questVendorData()
    local env = { C_QuestLog = { GetTitleForQuestID = function(id)
        return id == 102 and "Client Quest" or nil
    end } }
    local A = loadAdvisor(db, shipped, env)
    check("q/v sources: Alliance order, names and factions", sourceRows(A.Sources(4, 1)),
        "q100:3:3:Own Quest:nil v201:2:1:nil:nil q101:1:nil:Shipped Quest:nil q102:1:nil:Client Quest:nil "
        .. "c448:5:nil:Hogger:nil v200:1:2:Vendor Bob:Horde")
    check("q/v sources: Horde puts the Alliance vendor last", sourceRows(A.Sources(4, 2)),
        "q100:3:3:Own Quest:nil q101:1:nil:Shipped Quest:nil q102:1:nil:Client Quest:nil v200:1:2:Vendor Bob:nil "
        .. "c448:5:nil:Hogger:nil v201:2:1:nil:Alliance")
    check("q/v sources: no faction puts every q/v row first", sourceRows(A.Sources(4)),
        "q100:3:3:Own Quest:nil v201:2:1:nil:nil q101:1:nil:Shipped Quest:nil q102:1:nil:Client Quest:nil "
        .. "v200:1:2:Vendor Bob:nil c448:5:nil:Hogger:nil")
    local rows = A.Sources(4, 1)
    check("q/v sources: no rate on a quest", tostring(rows[1].rate) .. " " .. tostring(rows[1].rateBasis), "nil nil")
    check("q/v sources: the drop keeps its rate", rows[5].rate .. " " .. rows[5].rateBasis, "0.5 kill")

    A = loadAdvisor(questVendorData())
    check("q/v sources: no quest API leaves the quest unnamed", tostring(A.Sources(4, 1)[4].name), "nil")
    A = loadWithDB(nil, "zhTW", { shipped = select(2, questVendorData()) }).Advisor
    check("q/v sources: shipped data alone, Alliance", sourceRows(A.Sources(4, 1)),
        "v201:2:1:nil:nil q101:1:nil:運送任務:nil q102:1:nil:nil:nil q100:3:2:nil:Horde")
    A = loadAdvisor(nil, { loot = { { 4, "v", 201, 1429, 2 } } })
    check("q/v sources: shipped data without factions", sourceRows(A.Sources(4, 2)), "v201:2:nil:nil:nil")

    local own = { schemaVersion = 3, loot = {
        ["4:q:100:1429"] = { item = 4, kind = "q", id = 100, map = 1429, count = 1, coords = { { 1, 1 } },
                             factions = 1 },
    } }
    A = loadAdvisor(own, { loot = { { 4, "q", 100, 12, 2, 500, 600 } }, factions = { ["4:q:100:12"] = 2 } })
    rows = A.Sources(4, 1)
    check("q/v sources: one row per quest across maps", #rows, 1)
    check("q/v sources: the lower map with its coords, max count, OR-ed factions",
        ("%d %d %d %d"):format(rows[1].map, rows[1].coords[1][1], rows[1].count, rows[1].factions), "12 500 2 3")
end

for locale, want in pairs({
    enUS = {
        lines = "  Own Quest, Elwynn Forest - quest reward /   npc #201, Elwynn Forest - vendor"
            .. " /   Shipped Quest, unknown map - quest reward /   quest #102, Elwynn Forest - quest reward"
            .. " /   Hogger, Elwynn Forest - drops: 5, 50.0% per kill / "
            .. "  Vendor Bob, Elwynn Forest - vendor (Horde only)",
        quest = "Tandem: reward from Own Quest, Elwynn Forest (+5 more)",
        horde = "Tandem: reward from Own Quest, Elwynn Forest (+5 more)",
        vendor = "Tandem: sold by Vendor Bob, Elwynn Forest (+1 more)",
        other = "Tandem: sold by npc #300, Elwynn Forest (Horde only)",
        drop = "Tandem: drops from npc #500, Elwynn Forest (+1 more)",
    },
    zhTW = {
        lines = "  Own Quest，Elwynn Forest：任務獎勵 /   NPC #201，Elwynn Forest：商人販售"
            .. " /   運送任務，未知地圖：任務獎勵 /   任務 #102，Elwynn Forest：任務獎勵"
            .. " /   Hogger，Elwynn Forest：掉落 5 次，每次擊殺 50.0% / "
            .. "  Vendor Bob，Elwynn Forest：商人販售（僅限部落）",
        quest = "Tandem：Own Quest 的任務獎勵，Elwynn Forest（另有 5 個來源）",
        horde = "Tandem：Own Quest 的任務獎勵，Elwynn Forest（另有 5 個來源）",
        vendor = "Tandem：由 Vendor Bob 販售，Elwynn Forest（另有 1 個來源）",
        other = "Tandem：由 NPC #300 販售，Elwynn Forest（僅限部落）",
        drop = "Tandem：掉落自 NPC #500，Elwynn Forest（另有 1 個來源）",
    },
}) do
    local db, shipped = questVendorData()
    local gearDB, gearShipped = gearData()
    db.items, shipped.items = gearDB.items, gearShipped.items
    for _, r in ipairs(gearShipped.loot) do
        if r[1] ~= 4 and r[1] ~= 8 then
            shipped.loot[#shipped.loot + 1] = r
        end
    end
    -- Item 2: a drop and an other-faction quest; item 8: a Horde vendor only; item 12: a drop and a Horde vendor.
    shipped.loot[#shipped.loot + 1] = { 8, "v", 300, 1429, 1 }
    shipped.loot[#shipped.loot + 1] = { 2, "q", 103, 1429, 4 }
    shipped.loot[#shipped.loot + 1] = { 12, "v", 200, 1429, 1 }
    shipped.factions["8:v:300:1429"] = 2
    shipped.factions["2:q:103:1429"] = 2
    shipped.factions["12:v:200:1429"] = 2
    local ctx = loadTooltip(locale, db, shipped)
    check(locale .. " q/v source lines", table.concat(ctx.addon.View.SourceLines(4, 10), " / "), want.lines)
    local function last(id)
        local t = ctx.hover({ id = id })
        return t.lines[#t.lines] and t.lines[#t.lines].text
    end
    check(locale .. " tooltip leads with a same-faction quest, no rate", last(4), want.quest)
    check(locale .. " tooltip: other-faction-only vendor is labelled", last(8), want.other)
    check(locale .. " tooltip: an other-faction quest sorts after a drop", last(2), want.drop)
    check(locale .. " tooltip: an other-faction vendor sorts after a drop", last(12), want.drop)
    ctx.faction = "Horde"
    ctx.level = 41
    check(locale .. " tooltip for a Horde player", last(4), want.horde)
    check(locale .. " tooltip: a Horde player sees the Horde vendor first", last(12), want.vendor)
end

do
    local db, shipped = questVendorData()
    local gearDB, gearShipped = gearData()
    db.items, shipped.items = gearDB.items, gearShipped.items
    local ctx = loadBrowse("enUS", db, shipped)
    ctx.run("browse chest")
    local win = ctx.win()
    for _, b in ipairs(win.box.buttons) do
        if b.row and b.row.id == 4 then
            b.scripts.OnClick(b)
        end
    end
    local pane = paneText(win)
    check("browse: q/v sources lead the pane", pane[2] .. " / " .. pane[3],
        "  Own Quest, Elwynn Forest - quest reward /   npc #201, Elwynn Forest - vendor")
    check("browse: the drop follows the same-faction q/v rows", pane[6],
        "  Hogger, Elwynn Forest - drops: 5, 50.0% per kill")
    check("browse: the other-faction vendor is past the cap", pane[7], "  and 1 more sources")
end

-- Check: /tandem check lists each feature's client APIs (stage 6, unit 1).

-- Every API Check looks for, first alternative only for the either-or ones.
local function checkAPIs()
    local fn = function() end
    return {
        TooltipDataProcessor = { AddTooltipPostCall = fn },
        Enum = { TooltipDataType = { Item = 0 } },
        GetQuestID = fn, GetQuestItemLink = fn, GetNumQuestChoices = fn, GetNumQuestRewards = fn,
        UnitGUID = fn, GetMerchantNumItems = fn, GetMerchantItemLink = fn,
        WorldMapFrame = { GetCanvas = fn, GetMapID = fn, OnMapChanged = fn },
        OpenWorldMap = fn, hooksecurefunc = fn,
        C_Map = { CanSetUserWaypointOnMap = fn, SetUserWaypoint = fn },
        UiMapPoint = { CreateFromCoordinates = fn },
        C_SuperTrack = { SetSuperTrackedUserWaypoint = fn },
        QuestInfoRewardsFrame = { RewardButtons = {} },
        C_Container = { GetContainerNumSlots = fn, GetContainerItemID = fn },
        GetInventoryItemLink = fn,
        C_Item = { GetItemStats = fn },
    }
end

-- Returns the check output as { [feature] = line } after the header, plus the raw lines.
local function runCheck(addon, printed)
    local out = run(addon, printed, "check")
    local byName = {}
    for i = 2, #out do
        byName[out[i]:match("^(.-):")] = out[i]
    end
    return byName, out
end

do
    local addon, printed = loadWithDB(nil)
    local byName, out = runCheck(addon, printed)
    check("check: header", out[1], "Tandem API check:")
    check("check: one line per feature", #out, 1 + #addon.Check.FEATURES)
    check("check: eight features", #addon.Check.FEATURES, 8)
    check("check: tooltip missing without the API", byName["Item tooltip"],
        "Item tooltip: missing (TooltipDataProcessor.AddTooltipPostCall missing, Enum.TooltipDataType.Item missing)")
    check("check: quest reward pick lists each button lookup", byName["Quest reward pick"],
        "Quest reward pick: missing (GetNumQuestChoices missing, GetQuestItemLink missing, "
            .. "QuestInfoRewardsFrame.RewardButtons missing, QuestInfoRewardsFrameQuestInfoItem1 missing, "
            .. "QuestRewardItem1 missing)")
    for _, name in ipairs({ "Item tooltip", "Quest sources", "Vendor sources", "Map pins", "Map waypoint",
        "Quest reward pick", "Upgrade alert", "Item stats" }) do
        check(("check: %s line present"):format(name), byName[name] ~= nil, true)
        check(("check: %s missing under bare stubs"):format(name),
            byName[name] and byName[name]:match("^[^:]*: (%a+)"), "missing")
    end
    check("check: extra words print usage", run(addon, printed, "check now")[1], "Tandem commands:")
end

do
    local addon, printed = loadWithDB(nil, "enUS", { env = checkAPIs() })
    local byName, out = runCheck(addon, printed)
    for i = 2, #out do
        check(("check: %s ok with every API"):format(out[i]:match("^(.-):")), out[i]:match("^[^:]*: (%a+)"), "ok")
    end
    check("check: an ok line lists the APIs", byName["Map waypoint"],
        "Map waypoint: ok (C_Map.CanSetUserWaypointOnMap ok, C_Map.SetUserWaypoint ok, "
            .. "UiMapPoint.CreateFromCoordinates ok, C_SuperTrack.SetSuperTrackedUserWaypoint ok)")
    check("check: the other alternative shows missing", byName["Item stats"],
        "Item stats: ok (C_Item.GetItemStats ok, GetItemStats missing)")
end

do
    local env = checkAPIs()
    env.QuestInfoRewardsFrame = nil
    env.QuestRewardItem1 = {}
    env.C_Container = nil
    env.GetContainerNumSlots = function() end
    env.WorldMapFrame = 5
    env.C_SuperTrack = {}
    local addon, printed = loadWithDB(nil, "enUS", { env = env })
    local byName = runCheck(addon, printed)
    check("check: a named reward button is enough", byName["Quest reward pick"],
        "Quest reward pick: ok (GetNumQuestChoices ok, GetQuestItemLink ok, "
            .. "QuestInfoRewardsFrame.RewardButtons missing, QuestInfoRewardsFrameQuestInfoItem1 missing, "
            .. "QuestRewardItem1 ok)")
    check("check: one need with no alternative fails the feature", byName["Upgrade alert"],
        "Upgrade alert: missing (C_Container.GetContainerNumSlots missing, GetContainerNumSlots ok, "
            .. "C_Container.GetContainerItemID missing, GetContainerItemID missing, GetInventoryItemLink ok)")
    check("check: a non-table step is missing, not an error", byName["Map pins"] and byName["Map pins"]:sub(1, 19),
        "Map pins: missing (")
    check("check: a missing field is missing", byName["Map waypoint"]:match("SetSuperTrackedUserWaypoint (%a+)"),
        "missing")
    check("check: Has on a nil step", addon.Check.Has("NoSuchTable.Field"), false)
    check("check: Has on a present value", addon.Check.Has("GetQuestID"), true)
end

do
    local addon, printed, env = loadWithDB(nil)
    env.InCombatLockdown = function()
        return true
    end
    local out = run(addon, printed, "check")
    check("check: refused in combat", out[1], "Tandem: not available in combat")
    check("check: prints only the refusal in combat", #out, 1)
end

do
    local addon, printed = loadWithDB(nil, "zhTW", { env = checkAPIs() })
    local out = run(addon, printed, "check")
    check("zhTW check: header", out[1], "Tandem API 檢查：")
    check("zhTW check: feature line", out[#out], "物品屬性：可用（C_Item.GetItemStats 可用, GetItemStats 缺少）")
end

-- Map pins (stage 6, unit 3): browse "Show on map" and /tandem map over a stubbed world map.

-- gearData() plus coords: item 1 drops from npc 448 on 1429 (own and shipped, one coord shared) and object 77 on 1411;
-- item 3 only from map 0; item 12 is quest 100's reward on 1429 (own) and 1411 (shipped); item 5 has 60 coords.
local function mapData()
    local db, shipped = gearData()
    db.loot["1:c:448:1429"].coords = { { 400, 600 }, { 410, 610 } }
    db.loot["1:o:77:1411"] = { item = 1, kind = "o", id = 77, map = 1411, count = 1, coords = { { 100, 200 } } }
    db.loot["3:c:449:0"] = { item = 3, kind = "c", id = 449, map = 0, count = 1, coords = { { 1, 2 } } }
    db.loot["12:q:100:1429"] = { item = 12, kind = "q", id = 100, map = 1429, count = 1, coords = { { 300, 300 } },
                               factions = 3 }
    shipped.loot[#shipped.loot + 1] = { 1, "c", 448, 1429, 2, 400, 600, 500, 700 }
    shipped.loot[#shipped.loot + 1] = { 12, "q", 100, 1411, 1, 500, 500 }
    local a, b = { 5, "c", 501, 1429, 3 }, { 5, "c", 502, 1411, 2 }
    for i = 1, 30 do
        for _, row in ipairs({ a, b }) do
            row[#row + 1] = i
            row[#row + 1] = i
        end
    end
    shipped.loot[#shipped.loot + 1] = a
    shipped.loot[#shipped.loot + 1] = b
    return db, shipped
end

-- Loads mapData() in the browse harness with a world map: ctx.map.mapID is the shown map, ctx.map.setMap(id) shows
-- another and runs the hooks, ctx.map.opened the map OpenWorldMap got, ctx.map.waypoint / tracked what was set,
-- ctx.map.refuse[map] makes a map refuse waypoints. opts.drop lists globals to leave out; opts.locale.
local function loadMap(opts)
    opts = opts or {}
    local m = { hooks = {}, refuse = {}, opens = 0 }
    local canvas = newWidget({ widgets = {} }, "Frame")
    canvas:SetSize(1000, 500)
    m.canvas = canvas
    local mapFrame = {
        GetCanvas = function()
            return canvas
        end,
        GetMapID = function()
            return m.mapID
        end,
    }
    function mapFrame.OnMapChanged() end
    m.onMapChanged = mapFrame.OnMapChanged
    m.frame = mapFrame
    function m.setMap(id)
        m.mapID = id
        for _, h in ipairs(m.hooks) do
            h.fn()
        end
    end
    local env = {
        WorldMapFrame = mapFrame,
        hooksecurefunc = function(t, name, fn)
            m.hooks[#m.hooks + 1] = { t = t, name = name, fn = fn }
        end,
        OpenWorldMap = function(id)
            m.opened, m.opens = id, m.opens + 1
            m.setMap(id)
        end,
        C_Map = {
            GetMapInfo = function(map)
                return map == 1429 and { name = "Elwynn Forest" } or nil
            end,
            CanSetUserWaypointOnMap = function(map)
                return not m.refuse[map]
            end,
            SetUserWaypoint = function(wp)
                m.waypoint = wp
            end,
        },
        UiMapPoint = { CreateFromCoordinates = function(map, x, y)
            return { map = map, x = x, y = y }
        end },
        C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v)
            m.tracked = v
        end },
    }
    for _, name in ipairs(opts.drop or {}) do
        env[name] = false
    end
    local db, shipped = mapData()
    local ctx = loadBrowse(opts.locale, db, shipped, { env = env })
    for _, name in ipairs(opts.drop or {}) do
        ctx.env[name] = nil
    end
    ctx.map = m
    -- Returns the shown pins as sorted "x,y" offsets from the canvas's top left.
    function ctx.pins()
        local out = {}
        for _, w in ipairs(ctx.ui.widgets) do
            if w.parent == canvas and w.kind == "Button" and w:IsShown() then
                local p = w.points[#w.points]
                out[#out + 1] = ("%g,%g"):format(p[4], p[5])
            end
        end
        table.sort(out)
        return table.concat(out, " ")
    end
    -- Returns the first shown pin at canvas offset x, y.
    function ctx.pinAt(x, y)
        for _, w in ipairs(ctx.ui.widgets) do
            local p = w.points[#w.points]
            if w.parent == canvas and w.kind == "Button" and w:IsShown() and p[4] == x and p[5] == y then
                return w
            end
        end
    end
    return ctx
end

-- Returns the browse row button of item id.
local function rowButton(win, id)
    for _, b in ipairs(win.box.buttons) do
        if b.row and b.row.id == id then
            return b
        end
    end
end

local function pointList(points)
    local out = {}
    for _, p in ipairs(points or {}) do
        out[#out + 1] = ("%g,%g %s"):format(p[1], p[2], p[3])
    end
    return table.concat(out, "; ")
end

do
    local ctx = loadMap()
    local Points = ctx.addon.MapPins.Points
    local byMap, first = Points(1)
    check("map points: first map is the first source's", first, 1429)
    check("map points: own then shipped, equal coords once", pointList(byMap[1429]),
        "0.4,0.6 npc #448; 0.41,0.61 npc #448; 0.5,0.7 npc #448")
    check("map points: a second source's map", pointList(byMap[1411]), "0.1,0.2 object #77")
    byMap, first = Points(3)
    check("map points: map 0 gives no point", next(byMap), nil)
    check("map points: map 0 gives no first map", first, nil)
    byMap, first = Points(12)
    check("map points: a quest merged across maps starts on its lower map", first, 1411)
    check("map points: the quest's lower map", pointList(byMap[1411]), "0.5,0.5 quest #100")
    check("map points: the quest's other map", pointList(byMap[1429]), "0.3,0.3 quest #100")
    byMap = Points(5)
    check("map points: 50 points at most, first source first", #byMap[1429] .. "+" .. #byMap[1411], "30+20")
    byMap, first = Points(999)
    check("map points: an unknown item has none", tostring(next(byMap)) .. " " .. tostring(first), "nil nil")
end

do
    local ctx = loadMap()
    local m = ctx.map
    check("map: nothing hooked before use", #m.hooks, 0)
    check("map: no output when pins show", #ctx.run("map 1"), 0)
    check("map: opens the first source's map", m.opened, 1429)
    check("map: one pin per coord of the shown map", ctx.pins(), "400,-300 410,-305 500,-350")
    check("map: hooks OnMapChanged", #m.hooks == 1 and m.hooks[1].t == m.frame and m.hooks[1].name, "OnMapChanged")
    check("map: Blizzard's method is not replaced", m.frame.OnMapChanged, m.onMapChanged)
    m.setMap(1411)
    check("map: another map shows its own pins", ctx.pins(), "100,-100")
    m.setMap(1)
    check("map: a map without points shows none", ctx.pins(), "")
    m.setMap(1429)
    check("map: back on the first map", ctx.pins(), "400,-300 410,-305 500,-350")

    local pin = ctx.pinAt(410, -305)
    pin.scripts.OnEnter(pin)
    check("map: pin tooltip owner", ctx.ui.tooltipOwner, pin)
    check("map: pin tooltip label", ctx.env.GameTooltip.text, "npc #448")
    check("map: pin tooltip hint", ctx.ui.tooltipLines[#ctx.ui.tooltipLines], "Click to set a waypoint")
    local from = #ctx.printed
    pin.scripts.OnClick(pin)
    check("map: click sets a waypoint", m.waypoint and ("%d %g %g"):format(m.waypoint.map, m.waypoint.x,
        m.waypoint.y), "1429 0.41 0.61")
    check("map: click super-tracks it", m.tracked, true)
    check("map: click says so", ctx.since(from)[1], "Tandem: waypoint set to npc #448")

    m.waypoint, m.tracked, m.refuse[1429] = nil, nil, true
    from = #ctx.printed
    pin.scripts.OnClick(pin)
    check("map: a refusing map gets no waypoint", m.waypoint, nil)
    check("map: a refusing map says so", ctx.since(from)[1], "Tandem: this map does not take a waypoint")
    m.refuse[1429] = nil

    ctx.env.C_SuperTrack = nil
    from = #ctx.printed
    pin.scripts.OnClick(pin)
    check("map: no waypoint without the API", m.waypoint, nil)
    check("map: missing waypoint API says so", ctx.since(from)[1],
        "Tandem: waypoints are not available on this client; see /tandem check")

    ctx.combat = true
    from = #ctx.printed
    pin.scripts.OnClick(pin)
    check("map: a click in combat is refused", ctx.since(from)[1], "Tandem: not available in combat")
    check("map: a click in combat sets nothing", m.waypoint, nil)
    ctx.combat = false

    ctx.run("map 12")
    check("map: a new item replaces the pins", ctx.pins(), "500,-250")
    check("map: a new item opens its map", m.opened, 1411)
    check("map: hooked once", #m.hooks, 1)
    check("map clear: says so", ctx.run("map clear")[1], "Tandem: map pins cleared")
    check("map clear: hides every pin", ctx.pins(), "")
    m.setMap(1429)
    check("map clear: no pin on a later map change", ctx.pins(), "")

    check("map: a shift-clicked link", #ctx.run("map " .. built(1, "a335ee", "Plate Chest")), 0)
    check("map: the link's item", ctx.pins(), "400,-300 410,-305 500,-350")
    check("map: map 0 only", ctx.run("map 3")[1], "Tandem: no known map position for item 3")
    check("map: no coords keeps the pins", ctx.pins(), "400,-300 410,-305 500,-350")
    check("map: unknown item", ctx.run("map 999")[1], "Tandem: item 999 is not known; scan or loot it first")
    check("map: no argument", ctx.run("map")[1], "Tandem: usage /tandem map <item link|id> or /tandem map clear")
    check("map: two words", ctx.run("map 1 2")[1], "Tandem: usage /tandem map <item link|id> or /tandem map clear")

    ctx.combat = true
    local opens = m.opens
    local out = ctx.run("map 12")
    check("map: refused in combat", out[1], "Tandem: not available in combat")
    check("map: prints only the refusal in combat", #out, 1)
    check("map: nothing opened in combat", m.opens, opens)
    check("map clear: refused in combat", ctx.run("map clear")[1], "Tandem: not available in combat")
    local ok, reason = ctx.addon.MapPins.Show(12)
    check("map: Show in combat", tostring(ok) .. " " .. reason, "false combat")
end

do
    local ctx = loadMap({ drop = { "WorldMapFrame" } })
    local ok, out = pcall(ctx.run, "map 1")
    check("map: no error without the map API", ok, true)
    check("map: missing map API says so", ok and out[1],
        "Tandem: map pins are not available on this client; see /tandem check")
    check("map: Show without the map API", select(2, ctx.addon.MapPins.Show(1)), "noapi")
    check("map: nothing hooked without the map API", #ctx.map.hooks, 0)
end

do
    local ctx = loadMap({ drop = { "hooksecurefunc" } })
    check("map: missing hooksecurefunc says so", ctx.run("map 1")[1],
        "Tandem: map pins are not available on this client; see /tandem check")
    check("map: nothing opened without hooksecurefunc", ctx.map.opened, nil)
end

do
    local ctx = loadMap()
    ctx.level = 45
    ctx.run("browse chest")
    local win = ctx.win()
    local map = win.pane.map
    check("browse map: button label", map:GetText(), "Show on map")
    check("browse map: button template", map.template, "UIPanelButtonTemplate")
    check("browse map: disabled with nothing selected", map:IsEnabled(), false)
    local b1 = rowButton(win, 1)
    b1.scripts.OnClick(b1)
    check("browse map: enabled once an item is selected", map:IsEnabled(), true)
    check("browse map: no output when pins show", (function()
        local from = #ctx.printed
        map.scripts.OnClick(map)
        return #ctx.since(from)
    end)(), 0)
    check("browse map: opens the source's map", ctx.map.opened, 1429)
    check("browse map: pins the selected item", ctx.pins(), "400,-300 410,-305 500,-350")
    b1.scripts.OnClick(b1)
    check("browse map: selecting the same item keeps the pins", ctx.pins(), "400,-300 410,-305 500,-350")
    local b3 = rowButton(win, 3)
    b3.scripts.OnClick(b3)
    check("browse map: a new selection clears the pins", ctx.pins(), "")
    local from = #ctx.printed
    map.scripts.OnClick(map)
    check("browse map: an item without coords says so", ctx.since(from)[1],
        "Tandem: no known map position for item 3")
    ctx.combat = true
    local opens = ctx.map.opens
    from = #ctx.printed
    b1.scripts.OnClick(b1)
    map.scripts.OnClick(map)
    check("browse map: refused in combat", ctx.since(from)[1], "Tandem: not available in combat")
    check("browse map: nothing opened in combat", ctx.map.opens, opens)
end

do
    local ctx = loadMap({ locale = "zhTW" })
    check("zhTW map: no coords", ctx.run("map 3")[1], "Tandem：物品 3 沒有已知的地圖位置")
    check("zhTW map: cleared", ctx.run("map clear")[1], "Tandem：已移除地圖標記")
end

if failures > 0 then
    os.exit(1)
end
