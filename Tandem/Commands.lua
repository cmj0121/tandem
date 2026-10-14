local _, ns = ...

-- The /tandem slash command: parses input and prints or dispatches to the other modules.
local Commands = {}
ns.Commands = Commands

local DEFAULT_RATE = 10
local DEFAULT_CAP = 100
local MAX_CAP = 100000
local MIN_RATE = 1 / 60
local MAX_RATE = 50

local L = ns.L

local function printUsage()
    print(L["Tandem commands:"])
    print(L["  /tandem count - show collected data"])
    print(L["  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)"])
    print(L["  /tandem scan from <id> - set the next item ID to scan"])
    print(L["  /tandem scan stop - stop the scan"])
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
    else
        printUsage()
    end
end

SLASH_TANDEM1 = "/tandem"
SlashCmdList.TANDEM = Commands.Run
