local _, ns = ...

-- The /tandem slash command: parses input and prints or dispatches to the other modules.
local Commands = {}
ns.Commands = Commands

local DEFAULT_RATE = 10
local DEFAULT_CAP = 100
local MAX_CAP = 100000
local MIN_RATE = 1 / 60
local MAX_RATE = 50

local GEAR_ROWS = 10
local SOURCE_ROWS = 5

local L = ns.L
local Safe = ns.Store.Safe

local SLOT_LABELS = {
    head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist",
    hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", finger = "Finger", trinket = "Trinket",
    mainhand = "Main hand", offhand = "Off hand", twohand = "Two-hand", ranged = "Ranged",
}

-- Inventory slots worn for each slot token; a pair is compared by its lower item level.
local INVENTORY = {
    head = { 1 }, neck = { 2 }, shoulder = { 3 }, back = { 15 }, chest = { 5 }, wrist = { 9 }, hands = { 10 },
    waist = { 6 }, legs = { 7 }, feet = { 8 }, finger = { 11, 12 }, trinket = { 13, 14 }, mainhand = { 16 },
    offhand = { 17 }, twohand = { 16 }, ranged = { 18 },
}

local function printUsage()
    print(L["Tandem commands:"])
    print(L["  /tandem count - show collected data"])
    print(L["  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)"])
    print(L["  /tandem scan from <id> - set the next item ID to scan"])
    print(L["  /tandem scan stop - stop the scan"])
    print(L["  /tandem gear [<slot>] [all] - best known gear you can use"])
    print(L["  /tandem rank <item link|id> - rank an item in its slot"])
    print(L["  /tandem export - show what make import would collect"])
end

-- Returns a whole number >= min parsed from s, or nil.
local function parseInt(s, min)
    local n = s and s:match("^%d+$") and tonumber(s)
    if n and n >= min then
        return n
    end
end

-- Returns a rate in IDs per second for "<n>/s" or "<n>/m" within 1/m..50/s, or nil.
function Commands.ParseRate(s)
    if type(s) ~= "string" then
        return nil
    end
    local n, unit = s:match("^(%d+)/([sm])$")
    n = tonumber(n)
    if not n then
        return nil
    end
    local rate = unit == "s" and n or n / 60
    if rate < MIN_RATE or rate > MAX_RATE then
        return nil
    end
    return rate
end

-- Returns {rate, cap} for the tokens after "scan", or nil when any token is invalid or repeated.
local function parseStart(args)
    local rate, cap
    for _, token in ipairs(args) do
        if token:find("/", 1, true) then
            if rate then
                return nil
            end
            rate = Commands.ParseRate(token)
            if not rate then
                return nil
            end
        else
            if cap then
                return nil
            end
            cap = parseInt(token, 1)
            if not cap or cap > MAX_CAP then
                return nil
            end
        end
    end
    return { rate = rate or DEFAULT_RATE, cap = cap or DEFAULT_CAP }
end

local function scan(args)
    local action
    if args[1] == "stop" then
        if #args ~= 1 then
            return printUsage()
        end
        action = function(scanner)
            scanner.Stop()
        end
    elseif args[1] == "from" then
        local id = #args == 2 and parseInt(args[2], 1)
        if not id then
            return printUsage()
        end
        action = function(scanner)
            scanner.SetCursor(id)
        end
    else
        local opts = parseStart(args)
        if not opts then
            return printUsage()
        end
        action = function(scanner)
            scanner.Start(opts)
        end
    end

    if not ns.Scanner then
        print(L["Tandem: scanner not available"])
        return
    end
    action(ns.Scanner)
end

-- Shows a possibly missing number; "?" when absent.
local function num(v)
    if v == nil then
        return "?"
    end
    return tostring(v)
end

local function formatRate(rate)
    if type(rate) ~= "number" then
        return "?"
    end
    if rate < 1 then
        return ("%g/m"):format(rate * 60)
    end
    return ("%g/s"):format(rate)
end

local function count()
    local c = ns.Store.Counts()
    print(L["Tandem: %d known items, %s non-equippable"]:format(c.items, num(c.nonEquippable)))
    local found = L["none"]
    if c.minFound and c.maxFound then
        found = ("%d-%d"):format(c.minFound, c.maxFound)
    end
    print(L["Scan cursor: %s, found IDs: %s"]:format(num(c.cursor), found))
    print(L["Loot entries: %d, npc names: %d"]:format(c.loot, c.npcs))
    print(L["Kills: %d, looted corpses: %d"]:format(c.kills, c.corpses))
    local status = ns.Kills.Status()
    if status == "on" then
        print(L["Drop rates use kills where counted, else looted corpses"])
    else
        print(L["Drop rates use looted corpses: kill counting is %s"]:format(L[status]))
    end
    print(L["Unsaved records: %d (saved on /reload or logout)"]:format(c.unsaved))

    local scanDB = ns.Store.db.scan
    local run = type(scanDB) == "table" and type(scanDB.lastRun) == "table" and scanDB.lastRun
    if run then
        local elapsed = type(run.elapsed) == "number" and ("%.1f"):format(run.elapsed) or "?"
        print(L["Last run: IDs %s-%s at %s in %ss, %s processed, %s skipped"]:format(
            num(run.from), num(run.to), formatRate(run.rate), elapsed, num(run.processed), num(run.skipped)))
        print(L["  %s hits (%s equippable), %s misses, %s deferred, %s timeouts"]:format(
            num(run.hits), num(run.equippable), num(run.misses), num(run.deferred), num(run.timeouts)))
    else
        print(L["Last run: never"])
    end
    if c.readOnly then
        print(L["Recording is off: saved data uses a newer schema"])
    end
end

-- Prints the refusal and returns true while in combat (decision 9).
local function inCombat()
    if InCombatLockdown and InCombatLockdown() then
        print(L["Tandem: not available in combat"])
        return true
    end
    return false
end

-- Returns the player's localised class name, class file and level, or nil when the client hides any of them.
local function player()
    local name, classFile, level
    if UnitClass then
        name, classFile = UnitClass("player")
        name, classFile = Safe(name), Safe(classFile)
    end
    if UnitLevel then
        level = Safe(UnitLevel("player"))
    end
    if type(classFile) ~= "string" or type(level) ~= "number" or level < 1 then
        print(L["Tandem: your class or level is not known yet; try again in a moment"])
        return nil
    end
    return type(name) == "string" and name or classFile, classFile, level
end

local QUALITY_HEX = {
    [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff",
}

-- Returns the client's link for an item when cached; else builds one from the id in its quality colour and asks
-- the client to load the item for next time.
local function itemLink(id, quality)
    if C_Item and C_Item.GetItemInfo then
        local name, link = C_Item.GetItemInfo(id)
        link = Safe(link)
        if type(link) == "string" then
            return link
        end
        if Safe(name) == nil and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    return ("|cff%s|Hitem:%d::::::::::::::|h[%s]|h|r"):format(QUALITY_HEX[quality] or QUALITY_HEX[1], id,
        L["item #%d"]:format(id))
end

local function linkOf(id)
    local r = ns.Advisor.Item(id)
    return itemLink(id, r and r[3])
end

local function slotLabel(slot)
    return L[SLOT_LABELS[slot]]
end

-- Returns the item level of an item id from the cache, else from the client, or nil.
local function ilvlOf(id)
    local r = ns.Advisor.Item(id)
    if r then
        return r[1]
    end
    if C_Item and C_Item.GetItemInfo then
        local ilvl = Safe(select(4, C_Item.GetItemInfo(id)))
        return type(ilvl) == "number" and ilvl or nil
    end
end

-- Returns the item id worn in an inventory slot, false when it is empty, or nil when the client does not tell.
-- A secret link is never compared: it is checked before anything else touches it.
local function wornID(inv)
    if not GetInventoryItemLink then
        return nil
    end
    local raw = GetInventoryItemLink("player", inv)
    if issecretvalue and issecretvalue(raw) then
        return nil
    end
    if raw == nil then
        return false
    end
    return type(raw) == "string" and tonumber(raw:match("item:(%d+)")) or nil
end

-- Returns an item's equipLoc from the cache, else from the client, or nil.
local function equipLocOf(id)
    local r = ns.Advisor.Item(id)
    if r then
        return r[4]
    end
    if C_Item and C_Item.GetItemInfoInstant then
        return Safe((select(4, C_Item.GetItemInfoInstant(id))))
    end
end

-- Returns what the player wears in a slot token: { ids = {[id] = true}, list = { {id, ilvl} | {ilvl = 0} | {unknown} },
-- ilvl } where ilvl is the one to beat (the lower of a pair, 0 when a slot is empty) or nil when unknown. An off hand
-- behind a two-hander, or behind a main hand the client does not reveal, has nothing to beat.
local function equipped(slot)
    local out = { ids = {}, list = {}, ilvl = math.huge }
    for _, inv in ipairs(INVENTORY[slot]) do
        local id = wornID(inv)
        local e = {}
        if id then
            e.id, e.ilvl = id, ilvlOf(id)
            out.ids[id] = true
        elseif id == false then
            e.ilvl = 0
        else
            e.unknown = true
        end
        out.list[#out.list + 1] = e
        if out.ilvl and e.ilvl then
            out.ilvl = math.min(out.ilvl, e.ilvl)
        else
            out.ilvl = nil
        end
    end
    if slot == "offhand" then
        local main = wornID(16)
        if main == nil or (main and equipLocOf(main) == "INVTYPE_2HWEAPON") then
            out.ilvl = nil
        end
    end
    return out
end

local function marks(id, ilvl, sourced, worn)
    local s = ""
    if worn.ids[id] then
        s = s .. L[" (equipped)"]
    elseif worn.ilvl and ilvl > worn.ilvl then
        s = s .. L[" (upgrade)"]
    end
    if not sourced then
        s = s .. L[" (no known source)"]
    end
    return s
end

local function gearOverview(all, className, level, classFile)
    print(L["Best known gear for level %d %s:"]:format(level, className))
    for _, slot in ipairs(ns.Advisor.SLOTS) do
        local top = ns.Advisor.Best(slot, classFile, level, { all = all })[1]
        if top then
            print(L["%s: %s, ilvl %d%s"]:format(slotLabel(slot), linkOf(top.id), top.ilvl,
                marks(top.id, top.ilvl, top.sourced, equipped(slot))))
        else
            print(L["%s: none known"]:format(slotLabel(slot)))
        end
    end
end

local function gearSlot(slot, all, className, level, classFile)
    local list = ns.Advisor.Best(slot, classFile, level, { all = all })
    print(L["Best %s for level %d %s:"]:format(slotLabel(slot), level, className))
    local worn = equipped(slot)
    for _, e in ipairs(worn.list) do
        if e.id then
            print(L["Equipped: %s, ilvl %s"]:format(linkOf(e.id), e.ilvl and tostring(e.ilvl) or "?"))
        elseif not e.unknown then
            print(L["Equipped: nothing"])
        end
    end
    if #list == 0 then
        print(L["No known %s you can use"]:format(slotLabel(slot)))
    end
    for i = 1, math.min(#list, GEAR_ROWS) do
        local e = list[i]
        print(L["%d. %s, ilvl %d, level %d%s"]:format(i, linkOf(e.id), e.ilvl, e.reqLevel,
            marks(e.id, e.ilvl, e.sourced, worn)))
    end
end

-- gear [<slot>] [all]
local function gear(args)
    if inCombat() then
        return
    end
    local all = args[#args] == "all"
    if all then
        args[#args] = nil
    end
    if #args > 1 then
        return printUsage()
    end
    local slot = args[1]
    if slot and not SLOT_LABELS[slot] then
        print(L["Tandem: unknown slot %s; use one of: %s"]:format(slot, table.concat(ns.Advisor.SLOTS, " ")))
        return
    end
    local className, classFile, level = player()
    if not className then
        return
    end
    if slot then
        gearSlot(slot, all, className, level, classFile)
    else
        gearOverview(all, className, level, classFile)
    end
    print(L["Ranked by item level, then quality; stats are not considered"])
end

-- Returns text with its escape character doubled so a stored name cannot inject colour codes or links.
local function escape(text)
    return (text:gsub("|", "||"))
end

local function printSources(id)
    local rows = ns.Advisor.Sources(id)
    if #rows == 0 then
        print(L["  no known source"])
        return
    end
    for i = 1, math.min(#rows, SOURCE_ROWS) do
        local s = rows[i]
        local name = s.name and escape(s.name)
        if not name then
            name = s.kind == "c" and L["npc #%d"]:format(s.id) or s.kind == "o" and L["object #%d"]:format(s.id)
                or L["unknown source"]
        end
        local map = s.mapName and escape(s.mapName) or L["unknown map"]
        if s.rateBasis == "kill" then
            print(L["  %s, %s - drops: %d, %.1f%% per kill"]:format(name, map, s.count, s.rate * 100))
        elseif s.rateBasis == "corpse" then
            print(L["  %s, %s - drops: %d, %.1f%% per looted corpse (upper bound)"]:format(name, map, s.count,
                s.rate * 100))
        else
            print(L["  %s, %s - drops: %d"]:format(name, map, s.count))
        end
    end
    if #rows > SOURCE_ROWS then
        print(L["  and %d more sources"]:format(#rows - SOURCE_ROWS))
    end
end

-- rank <item link|id>
local function rank(args)
    if inCombat() then
        return
    end
    local id = table.concat(args, " "):match("item:(%d+)") or (#args == 1 and args[1]:match("^%d+$")) or nil
    id = tonumber(id)
    if not id then
        print(L["Tandem: usage /tandem rank <item link|id>"])
        return
    end
    local _, classFile, level = player()
    if not classFile then
        return
    end
    local r = ns.Advisor.Rank(id, classFile, level)
    if not r then
        print(L["Tandem: item %d is not known; scan or loot it first"]:format(id))
        return
    end
    local link = linkOf(id)
    if r.slot then
        local worn = equipped(r.slot)
        if not r.usable then
            worn.ilvl = nil
        end
        print(L["%s: rank %d of %d for %s"]:format(link .. marks(id, ns.Advisor.Item(id)[1], true, worn), r.rank,
            r.total, slotLabel(r.slot)))
    else
        print(L["%s does not go in a ranked slot"]:format(link))
    end
    if r.reason == "level" then
        print(L["  you cannot use it: level %d required"]:format(r.needLevel))
    elseif r.reason == "proficiency" then
        print(L["  your class cannot use it"])
    end
    printSources(id)
    if r.slot then
        print(L["Ranked by item level, then quality; stats are not considered"])
    end
end

-- Prints what make import would collect (decision 8); never reloads.
local function export()
    if inCombat() then
        return
    end
    local c = ns.Store.Counts()
    print(L["Tandem export: %d loot entries, %d npc names, %d items, %d kills, %d looted corpses"]:format(c.loot,
        c.npcs, c.items, c.kills, c.corpses))
    print(L["Unsaved records: %d (saved on /reload or logout)"]:format(c.unsaved))
    if c.readOnly then
        print(L["Recording is off: saved data uses a newer schema"])
    end
    print(L["To contribute: type /reload, then run make import"])
end

function Commands.Run(msg)
    local args = {}
    for token in (msg or ""):lower():gmatch("%S+") do
        args[#args + 1] = token
    end
    local sub = table.remove(args, 1)
    if sub == "count" and #args == 0 then
        count()
    elseif sub == "scan" then
        scan(args)
    elseif sub == "gear" then
        gear(args)
    elseif sub == "rank" then
        rank(args)
    elseif sub == "export" and #args == 0 then
        export()
    else
        printUsage()
    end
end

SLASH_TANDEM1 = "/tandem"
SlashCmdList.TANDEM = Commands.Run
