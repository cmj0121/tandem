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

-- Loads the addon as a client with the given locale would; returns its namespace,
-- the printed lines, a function that fires ADDON_LOADED, the global environment and a function that fires any event.
local function loadAddon(locale)
    local printed = {}
    local handler
    local frame = {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(_, _, fn)
            handler = fn
        end,
    }
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

    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(addonDir .. file, "t", env))
        if setfenv then
            setfenv(chunk, env)
        end
        chunk("Tandem", ns)
    end

    local function fire(event, ...)
        handler(frame, event, ...)
    end
    local function fireLoaded()
        fire("ADDON_LOADED", "Tandem")
    end
    return ns, printed, fireLoaded, env, fire
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

-- Store: TandemDB validation and migration.

-- Loads the addon with TandemDB set to db, fires ADDON_LOADED; returns ns, printed lines, env.
local function loadWithDB(db, locale)
    local addon, printed, fireLoaded, env, fire = loadAddon(locale or "enUS")
    env.TandemDB = db
    fireLoaded()
    return addon, printed, env, fire
end

local function isCurrent(db)
    return type(db) == "table" and db.schemaVersion == 1 and type(db.items) == "table"
        and type(db.scan) == "table" and db.scan.cursor == 1 and db.scan.nonEquippable == 0
        and type(db.scan.blocks) == "table" and type(db.npcs) == "table" and type(db.loot) == "table"
end

do
    local addon, printed, env = loadWithDB(nil)
    check("nil db becomes a fresh v1 table", isCurrent(env.TandemDB), true)
    check("nil db prints only the load line", #printed, 1)
    check("Store.db is TandemDB", addon.Store.db, env.TandemDB)
end

do
    local _, printed, env = loadWithDB("garbage")
    check("garbage db becomes a fresh v1 table", isCurrent(env.TandemDB), true)
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
        unknownTop = true,
    })
    local db = env.TandemDB
    check("old db is migrated to v1", db.schemaVersion, 1)
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
    -- items 26 and -1, nonEquippable, block 1, npc 101, loot 9:c:1:1
    check("old db prints the drop count", printed[2], "Tandem: dropped 6 invalid saved entries")
end

do
    local _, printed, env = loadWithDB({ schemaVersion = 1, items = { [7] = { 1, 1, 1, "INVTYPE_FEET", 4, 2 } } })
    check("v1 db keeps its items", env.TandemDB.items[7][4], "INVTYPE_FEET")
    check("v1 db fills missing sections", isCurrent(env.TandemDB), true)
    check("valid v1 db prints only the load line", #printed, 1)
end

do
    local newer = { schemaVersion = 2, items = "new format" }
    local addon, printed, env = loadWithDB(newer)
    check("newer db is left untouched", env.TandemDB, newer)
    check("newer db keeps its fields", env.TandemDB.items, "new format")
    check("newer db prints a warning", printed[2],
        "Tandem: saved data uses newer schema 2; recording is off until the addon is updated")
    check("newer db blocks AddItem", addon.Store.AddItem(1, 1, 1, 1, "INVTYPE_HEAD", 4, 1), false)
    check("newer db blocks AddLoot", addon.Store.AddLoot(1, "c", 1, 1), false)
    check("newer db blocks SetNpcName", addon.Store.SetNpcName(1, "x"), false)
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

    local counts = Store.Counts()
    check("Counts items", counts.items, 1)
    check("Counts loot entries", counts.loot, 2)
    check("Counts npcs", counts.npcs, 1)
    check("Counts cursor", counts.cursor, 1)
    check("Counts nonEquippable", counts.nonEquippable, 0)
    check("Counts unsaved records", counts.unsaved, 1 + 13 + 1 + 1)
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
    check("usage line count", #help, 5)

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
    check("count empty: unsaved", out[4], "Unsaved records: 0 (saved on /reload or logout)")
    check("count empty: last run", out[5], "Last run: never")
    check("count empty line count", #out, 5)
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
    check("count: unsaved", out[4], "Unsaved records: 1 (saved on /reload or logout)")
    check("count: last run", out[5], "Last run: IDs 1-1200 at 10/s in 125.3s, 1200 processed, 3 skipped")
    check("count: last run results",
        out[6], "  42 hits (2 equippable), 1158 misses, 5 deferred, 1 timeouts")
end

do
    local addon, printed = loadWithDB({ schemaVersion = 1, scan = { lastRun = { rate = 0.25, hits = 3 } } })
    local out = run(addon, printed, "count")
    check("count: partial last run", out[5], "Last run: IDs ?-? at 15/m in ?s, ? processed, ? skipped")
end

do
    local addon, printed = loadWithDB({ schemaVersion = 2, items = "new format" })
    local out = run(addon, printed, "count")
    check("count on a newer db does not fail", out[1], "Tandem: 0 known items, ? non-equippable")
    check("count on a newer db says read-only", out[#out],
        "Recording is off: saved data uses a newer schema")
end

do
    local addon, printed = loadWithDB(nil, "zhTW")
    addon.Scanner = nil
    check("zhTW count line", run(addon, printed, "count")[5], "上次掃描：從未執行")
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
    local ctx = loadScanner({}, { schemaVersion = 2, scan = { cursor = 9 } })
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
    check("count after scan", out[5], "Last run: IDs 1-3 at 15/m in 12.0s, 3 processed, 0 skipped")
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
    ctx.loot()
    check("loot: missing GetPlayerMapPosition keeps the map", #ctx.entry("25:c:448:1429").coords, 0)
    ctx.env.C_Map.GetPlayerMapPosition = function() end
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
    local ctx = loadLoot({ schemaVersion = 2, loot = {} })
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
    ctx.fire("LOOT_READY")
    check("loot: a new window records again", ctx.entry("25:c:448:1429").count, 2)
    ctx.fire("LOOT_CLOSED")

    ctx.slots = { { link(40), sources = { CHEST, 1 } } }
    ctx.units.target = { HOGGER, "Hogger" }
    ctx.loot()
    local out = run(ctx.addon, ctx.printed, "count")
    check("count reflects loot entries", out[3], "Loot entries: 2, npc names: 0")
    check("count reflects unsaved loot", out[4], "Unsaved records: 3 (saved on /reload or logout)")
end

if failures > 0 then
    os.exit(1)
end
