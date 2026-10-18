local _, ns = ...

-- Walks item IDs upward from the saved cursor at a given rate and caches equippable items.
local Scanner = {}
ns.Scanner = Scanner

local TIMEOUT = 5
local BACKLOG = 10
-- Some clients report non-equippable items with this slot instead of "".
local NON_EQUIP = "INVTYPE_NON_EQUIP_IGNORE"

local L = ns.L
local Safe = ns.Store.Safe
local floor = math.floor

local running = false
local ticker, cap, startedAt, pausedShown
local pending, pendingCount = {}, 0

local function scanDB()
    return ns.Store.db.scan
end

local function itemAPI()
    return C_Item and C_Item.GetItemInfo and C_Item.GetItemInfoInstant
end

local function num(v)
    if v == nil then
        return "?"
    end
    return tostring(v)
end

local function found(id)
    local scan, run = scanDB(), scanDB().lastRun
    run.hits = run.hits + 1
    if not scan.minFound or id < scan.minFound then
        scan.minFound = id
    end
    if not scan.maxFound or id > scan.maxFound then
        scan.maxFound = id
    end
    local block = floor(id / 1000)
    scan.blocks[block] = (scan.blocks[block] or 0) + 1
end

local function isEquipLoc(equipLoc)
    return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= NON_EQUIP
end

-- Returns true when the item's stats are to be read from its tooltip: the tooltip API and the locale's patterns are
-- there and the item has none saved, or the saved ones come from an older parser.
local function needsStats(id)
    local Store = ns.Store
    if Store.readOnly or not ns.StatPatterns or not ns.Check.Ready("Stat search") then
        return false
    end
    return (Store.StatsVersion() or 0) < ns.StatSearch.VERSION or Store.Stats(id) == nil
end

-- Reads and saves the item's stats; false while its tooltip is not loaded. Saved stats from an older parser are
-- dropped first, so every item lacking stats is read again.
local function readStats(id)
    local stats = ns.StatSearch.ReadStats(id)
    if not stats then
        return false
    end
    local Store = ns.Store
    if (Store.StatsVersion() or 0) < ns.StatSearch.VERSION then
        Store.ClearStats()
        Store.SetStatsVersion(ns.StatSearch.VERSION)
    end
    Store.SetStats(id, stats)
    return true
end

-- Scanner.CacheItem(id, equipLoc, classID, subclassID) -> added, statsPending
-- Stores an equippable item's core fields when the client has them, and its tooltip stats when they are due: nil
-- when the client does not have the item yet (or the item API is missing), else whether the record was added, and
-- true for statsPending while the stats wait for the tooltip.
function Scanner.CacheItem(id, equipLoc, classID, subclassID)
    if not itemAPI() then
        return nil
    end
    local name, _, quality, ilvl, reqLevel = C_Item.GetItemInfo(id)
    name = Safe(name)
    if not name then
        return nil
    end
    local added = ns.Store.AddItem(id, Safe(ilvl), Safe(reqLevel), Safe(quality), equipLoc, classID, subclassID,
        ns.Store.IsDeprecatedName(name))
    local statsPending = ns.Store.db.items[id] ~= nil and needsStats(id) and not readStats(id)
    return added, statsPending
end

-- Scanner.Equippable(id) -> equipLoc, classID, subclassID
-- Returns the item's slot and class when it is equippable; nil when it is not, unknown or the item API is missing.
function Scanner.Equippable(id)
    if not itemAPI() then
        return nil
    end
    local instantID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    equipLoc = Safe(equipLoc)
    if not Safe(instantID) or not isEquipLoc(equipLoc) then
        return nil
    end
    return equipLoc, Safe(classID), Safe(subclassID)
end

-- Holds id until the client replies or it times out, counted as deferred; entry.stats marks a wait for the tooltip
-- only (the item record is in), entry.backfill one for an item cached before this run.
local function defer(id, entry)
    entry.at = GetTime()
    pending[id] = entry
    pendingCount = pendingCount + 1
    local run = scanDB().lastRun
    run.deferred = run.deferred + 1
end

-- Caches a scanned item and counts it in the run; returns false when the client does not have it yet.
local function cache(id, equipLoc, classID, subclassID)
    local added, statsPending = Scanner.CacheItem(id, equipLoc, classID, subclassID)
    if added == nil then
        return false
    end
    found(id)
    if added then
        local run = scanDB().lastRun
        run.equippable = run.equippable + 1
    end
    if statsPending then
        defer(id, { stats = true })
    end
    return true
end

local function release(id)
    pending[id] = nil
    pendingCount = pendingCount - 1
end

-- Reads a pending tooltip wait's stats; true once read and released.
local function retryStats(id, entry)
    if not readStats(id) then
        return false
    end
    release(id)
    if entry.backfill then
        local run = scanDB().lastRun
        run.backfilled = run.backfilled + 1
    end
    return true
end

local function finished()
    return scanDB().lastRun.processed >= cap and pendingCount == 0
end

local function process(id)
    local run = scanDB().lastRun
    if ns.Store.db.items[id] then
        if not needsStats(id) then
            run.skipped = run.skipped + 1
        elseif readStats(id) then
            run.backfilled = run.backfilled + 1
        else
            defer(id, { stats = true, backfill = true })
        end
        return
    end
    if C_Item.DoesItemExistByID and Safe(C_Item.DoesItemExistByID(id)) == false then
        run.misses = run.misses + 1
        return
    end
    local instantID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    if not Safe(instantID) then
        run.misses = run.misses + 1
        return
    end
    equipLoc = Safe(equipLoc)
    if not isEquipLoc(equipLoc) then
        local scan = scanDB()
        scan.nonEquippable = scan.nonEquippable + 1
        found(id)
        return
    end
    if not cache(id, equipLoc, Safe(classID), Safe(subclassID)) then
        defer(id, { equipLoc = equipLoc, classID = Safe(classID), subclassID = Safe(subclassID) })
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
    end
end

function Scanner.IsRunning()
    return running
end

-- Returns the running scan's IDs processed, cap and hits, or nil when no scan runs.
function Scanner.Progress()
    if not running then
        return nil
    end
    local run = scanDB().lastRun
    return run.processed, cap, run.hits
end

function Scanner.Start(opts)
    if running then
        print(L["Tandem: scan already running"])
        return
    end
    if ns.Store.readOnly then
        print(L["Recording is off: saved data uses a newer schema"])
        return
    end
    if not itemAPI() then
        print(L["Tandem: item API not available"])
        return
    end
    if not (C_Timer and C_Timer.NewTicker) then
        print(L["Tandem: timer API not available"])
        return
    end

    local scan = scanDB()
    scan.lastRun = {
        started = time(), from = scan.cursor, rate = opts.rate, processed = 0, skipped = 0, hits = 0,
        misses = 0, equippable = 0, deferred = 0, timeouts = 0, backfilled = 0, elapsed = 0,
    }
    cap = opts.cap
    startedAt = GetTime()
    pausedShown = false
    pending, pendingCount = {}, 0
    running = true
    print(L["Tandem: scanning %d IDs from ID %d"]:format(cap, scan.cursor))
    ticker = C_Timer.NewTicker(1 / opts.rate, Scanner.Tick)
    -- The browse window shows the progress of a scan started from it or from /tandem scan.
    if Scanner.onStart then
        Scanner.onStart()
    end
end

-- Stops the scan and prints its summary, then runs Scanner.onStop when set (the browse window refreshes).
function Scanner.Stop()
    if not running then
        print(L["Tandem: no scan running"])
        return
    end
    running = false
    if ticker and ticker.Cancel then
        ticker:Cancel()
    end
    ticker = nil
    pending, pendingCount = {}, 0

    local run = scanDB().lastRun
    run.elapsed = GetTime() - startedAt
    print(L["Tandem: scan stopped, IDs %s-%s in %ss, %s processed, %s skipped"]:format(
        num(run.from), num(run.to), ("%.1f"):format(run.elapsed), run.processed, run.skipped))
    print(L["  %s hits (%s equippable), %s misses, %s deferred, %s timeouts"]:format(
        run.hits, run.equippable, run.misses, run.deferred, run.timeouts))
    if run.backfilled > 0 then
        print(L["  %s cached items read for stats"]:format(run.backfilled))
    end
    if Scanner.onStop then
        Scanner.onStop()
    end
end

function Scanner.SetCursor(id)
    if running then
        print(L["Tandem: stop the scan before moving the cursor"])
        return
    end
    if ns.Store.readOnly then
        print(L["Recording is off: saved data uses a newer schema"])
        return
    end
    scanDB().cursor = id
    print(L["Tandem: next scan starts at ID %d"]:format(id))
end

function Scanner.Tick()
    if not running then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if not pausedShown then
            pausedShown = true
            print(L["Tandem: scan paused in combat"])
        end
        return
    end
    pausedShown = false

    local now = GetTime()
    local scan = scanDB()
    local run = scan.lastRun
    run.elapsed = now - startedAt
    for id, entry in pairs(pending) do
        if not (entry.stats and retryStats(id, entry)) and now - entry.at > TIMEOUT then
            release(id)
            run.timeouts = run.timeouts + 1
        end
    end

    if run.processed < cap and pendingCount < BACKLOG then
        local id = scan.cursor
        scan.cursor = id + 1
        run.to = id
        run.processed = run.processed + 1
        process(id)
    end
    if finished() then
        Scanner.Stop()
    end
end

-- GET_ITEM_INFO_RECEIVED: resolves a deferred query; other addons' queries are ignored.
function Scanner.OnItemInfo(id, success)
    id = Safe(id)
    local entry = running and id and pending[id]
    if not entry then
        return
    end
    if entry.stats then
        retryStats(id, entry)
        if finished() then
            Scanner.Stop()
        end
        return
    end
    release(id)
    if Safe(success) == false or not cache(id, entry.equipLoc, entry.classID, entry.subclassID) then
        local run = scanDB().lastRun
        run.misses = run.misses + 1
    end
    if finished() then
        Scanner.Stop()
    end
end
