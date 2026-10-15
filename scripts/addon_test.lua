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
-- its missing files are skipped, as WoW does. A missing file the real toc lists fails the load.
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
        CreateFrame = function()
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
    return type(db) == "table" and db.schemaVersion == 2 and type(db.items) == "table"
        and type(db.scan) == "table" and db.scan.cursor == 1 and db.scan.nonEquippable == 0
        and type(db.scan.blocks) == "table" and type(db.npcs) == "table" and type(db.loot) == "table"
        and type(db.kills) == "table" and type(db.corpses) == "table"
end

do
    local addon, printed, env = loadWithDB(nil)
    check("nil db becomes a fresh v2 table", isCurrent(env.TandemDB), true)
    check("nil db prints only the load line", #printed, 1)
    check("Store.db is TandemDB", addon.Store.db, env.TandemDB)
end

do
    local _, printed, env = loadWithDB("garbage")
    check("garbage db becomes a fresh v2 table", isCurrent(env.TandemDB), true)
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
    check("old db is migrated to v2", db.schemaVersion, 2)
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
    check("v1 db prints the upgrade line", printed[2], "Tandem: saved data upgraded from schema 1 to 2")
    check("v1 db prints nothing else", #printed, 2)
end

for _, bad in ipairs({ 1.5, 0 / 0, -1, -math.huge }) do
    local _, printed, env = loadWithDB({ schemaVersion = bad })
    check("damaged version " .. tostring(bad) .. " is migrated", env.TandemDB.schemaVersion, 2)
    check("damaged version " .. tostring(bad) .. " prints no upgrade line", #printed, 1)
end

do
    local _, printed = loadWithDB({ schemaVersion = 1 }, "zhTW")
    check("zhTW upgrade line", printed[2], "Tandem：存檔資料已從結構版本 1 升級到 2")
end

do
    local _, printed, env = loadWithDB({ schemaVersion = 2, kills = { [448] = 2 }, corpses = { [448] = 5 } })
    check("v2 db keeps kills", env.TandemDB.kills[448], 2)
    check("v2 db keeps corpses", env.TandemDB.corpses[448], 5)
    check("valid v2 db prints only the load line", #printed, 1)
end

do
    local newer = { schemaVersion = 3, items = "new format" }
    local addon, printed, env = loadWithDB(newer)
    check("newer db is left untouched", env.TandemDB, newer)
    check("newer db keeps its fields", env.TandemDB.items, "new format")
    check("newer db prints a warning", printed[2],
        "Tandem: saved data uses newer schema 3; recording is off until the addon is updated")
    check("newer db blocks AddItem", addon.Store.AddItem(1, 1, 1, 1, "INVTYPE_HEAD", 4, 1), false)
    check("newer db blocks AddLoot", addon.Store.AddLoot(1, "c", 1, 1), false)
    check("newer db blocks SetNpcName", addon.Store.SetNpcName(1, "x"), false)
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

-- Runs msg through /tandem; returns the lines it printed.
local function run(addon, printed, msg)
    local from = #printed
    addon.Commands.Run(msg)
    local out = {}
    for i = from + 1, #printed do
        out[#out + 1] = printed[i]
    end
    return out
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
    check("usage line count", #help, 8)

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
    local addon, printed = loadWithDB({ schemaVersion = 3, items = "new format" })
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
    env.C_Timer = {
        NewTicker = function(interval, fn)
            local t = { interval = interval, fn = fn }
            function t.Cancel(self)
                self.cancelled = true
            end
            ctx.tickers[#ctx.tickers + 1] = t
            return t
        end,
    }
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
        local out = {}
        for i = from + 1, #printed do
            out[#out + 1] = printed[i]
        end
        return out
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
    local ctx = loadScanner({}, { schemaVersion = 3, scan = { cursor = 9 } })
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
    local ctx = loadLoot({ schemaVersion = 3, loot = {} })
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
    local addon, printed, e, fire, frame = loadWithDB(opts.db or { schemaVersion = 2 }, "enUS",
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
    local ctx = loadKills({ db = { schemaVersion = 3 } })
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
    local db = { schemaVersion = 2, items = ownItems, loot = {
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

do
    local A = loadAdvisor(gearData())
    local function slots(equipLoc, class, level)
        return table.concat(A.SlotsOf(equipLoc, class, level), ",")
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
    local A = loadAdvisor({ schemaVersion = 3, items = "new format", loot = 4 }, select(2, gearData()))
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
        schemaVersion = 2,
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
    check(locale .. " sources: FISHING_OBJECT", A.FISHING_OBJECT, 35591)
end

do
    local db = {
        schemaVersion = 2,
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
-- ctx.secret values hidden by issecretvalue. Returns ctx with addon, printed, env and a run(msg) function.
local function loadGear(locale, db, shipped, opts)
    if not db then
        db, shipped = gearData()
    end
    local ctx = { class = "WARRIOR", className = "Warrior", level = 40, equipped = {}, cache = {}, combat = false,
                  requested = {}, instant = {} }
    local env = {
        UnitClass = function(unit)
            assert(unit == "player")
            return ctx.className, ctx.class
        end,
        UnitLevel = function()
            return ctx.level
        end,
        InCombatLockdown = function()
            return ctx.combat
        end,
        GetInventoryItemLink = function(unit, slot)
            assert(unit == "player")
            return ctx.equipped[slot]
        end,
        C_Item = {
            GetItemInfo = function(id)
                local c = ctx.cache[id]
                if c then
                    return c[1], c[2], c[3], c[4]
                end
            end,
            RequestLoadItemDataByID = function(id)
                ctx.requested[id] = true
            end,
            GetItemInfoInstant = function(id)
                return id, nil, nil, ctx.instant[id]
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
    local loadOpts = { shipped = shipped, env = env, blockCLEU = opts and opts.blockCLEU }
    ctx.addon, ctx.printed, ctx.env = loadWithDB(db, locale or "enUS", loadOpts)
    function ctx.run(msg)
        return run(ctx.addon, ctx.printed, msg)
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
    for _, msg in ipairs({ "gear", "gear chest", "gear shirt", "rank 1", "rank", "export" }) do
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
    local ctx = loadGear("enUS", { schemaVersion = 3, items = "new format" }, nil)
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

if failures > 0 then
    os.exit(1)
end
