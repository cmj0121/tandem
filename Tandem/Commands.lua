local _, ns = ...

-- The /tandem slash command: parses input and prints or dispatches to the other modules.
local Commands = {}
ns.Commands = Commands

-- Scan defaults, shared with the browse window's scan bar.
Commands.DEFAULT_RATE = 10
Commands.DEFAULT_CAP = 100
local MAX_CAP = 100000
local MIN_RATE = 1 / 60
local MAX_RATE = 50

local GEAR_ROWS = 10
local SOURCE_ROWS = 5

local L = ns.L
local View = ns.View

Commands.SCAN_USAGE = "  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)"

local function printUsage()
    print(L["Tandem commands:"])
    print(L["  /tandem count - show collected data"])
    print(L[Commands.SCAN_USAGE])
    print(L["  /tandem scan from <id> - set the next item ID to scan"])
    print(L["  /tandem scan stop - stop the scan"])
    print(L["  /tandem gear [<slot>] [all] - best known gear you can use"])
    print(L["  /tandem gear <slot> [all] <words> - gear whose tooltip has the words on one line"])
    print(L["  /tandem rank <item link|id> - rank an item in its slot"])
    print(L["  /tandem export - show what make import would collect"])
    print(L["  /tandem browse [<slot>] - browse known gear in a window"])
    print(L["  /tandem minimap [on|off] - show or hide the minimap button"])
    print(L["  /tandem check - list the client APIs each feature needs"])
    print(L["  /tandem map <item link|id> - pin where an item comes from on the world map"])
    print(L["  /tandem map clear - remove the map pins"])
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

-- Returns text without surrounding spaces and in lower case, or nil for nil.
local function normalise(text)
    return text and text:match("^%s*(.-)%s*$"):lower()
end

-- Returns {rate, cap} for a scan from a rate ("<n>/s" or "<n>/m") and a cap (1..100000) as typed, in any case and
-- with surrounding spaces; nil or blank takes the default. Nil when either is invalid. Shared by /tandem scan and
-- the browse window's scan bar.
function Commands.ScanOptions(rateText, capText)
    rateText, capText = normalise(rateText), normalise(capText)
    local rate, cap = Commands.DEFAULT_RATE, Commands.DEFAULT_CAP
    if rateText and rateText ~= "" then
        rate = Commands.ParseRate(rateText)
    end
    if capText and capText ~= "" then
        cap = parseInt(capText, 1)
        if cap and cap > MAX_CAP then
            cap = nil
        end
    end
    if rate and cap then
        return { rate = rate, cap = cap }
    end
end

-- Returns {rate, cap} for the tokens after "scan", or nil when any token is invalid or repeated.
local function parseStart(args)
    local rateText, capText
    for _, token in ipairs(args) do
        if token:find("/", 1, true) then
            if rateText then
                return nil
            end
            rateText = token
        else
            if capText then
                return nil
            end
            capText = token
        end
    end
    return Commands.ScanOptions(rateText, capText)
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

local function gearOverview(all, className, level, classFile)
    print(L["Best known gear for level %d %s:"]:format(level, className))
    local opts = { all = all, index = ns.Advisor.SourceIndex() }
    for _, slot in ipairs(ns.Advisor.SLOTS) do
        local top = ns.Advisor.Best(slot, classFile, level, opts)[1]
        if top then
            print(L["%s: %s, ilvl %d%s"]:format(View.SlotLabel(slot), View.LinkOf(top.id), top.ilvl,
                View.Marks(top, View.Equipped(slot))))
        else
            print(L["%s: none known"]:format(View.SlotLabel(slot)))
        end
    end
end

local function gearSlot(slot, all, className, level, classFile)
    local list = ns.Advisor.Best(slot, classFile, level, { all = all })
    print(L["Best %s for level %d %s:"]:format(View.SlotLabel(slot), level, className))
    local worn = View.Equipped(slot)
    for _, e in ipairs(worn.list) do
        if e.id then
            print(L["Equipped: %s, ilvl %s"]:format(View.LinkOf(e.id), e.ilvl and tostring(e.ilvl) or "?"))
        elseif not e.unknown then
            print(L["Equipped: nothing"])
        end
    end
    if #list == 0 then
        print(L["No known %s you can use"]:format(View.SlotLabel(slot)))
    end
    for i = 1, math.min(#list, GEAR_ROWS) do
        local e = list[i]
        print(L["%d. %s, ilvl %d, level %d%s"]:format(i, View.LinkOf(e.id), e.ilvl, e.reqLevel,
            View.Marks(e, worn)))
    end
end

local function unknownSlot(slot)
    print(L["Tandem: unknown slot %s; use one of: %s"]:format(slot, table.concat(ns.Advisor.SLOTS, " ")))
end

-- Lists the slot's usable items whose tooltip has every term on one line, by the number on that line.
local function gearSearch(slot, all, terms, query, className, level, classFile)
    if not ns.StatSearch.Ready() then
        print(L["Tandem: stat search is not available on this client; see /tandem check"])
        return
    end
    local list, pending = ns.StatSearch.Filter(ns.Advisor.Best(slot, classFile, level, { all = all }), terms)
    print(L["Best %s for level %d %s matching \"%s\":"]:format(View.SlotLabel(slot), level, className, query))
    local worn = View.Equipped(slot)
    if #list == 0 then
        print(L["No known %s you can use matches \"%s\""]:format(View.SlotLabel(slot), query))
    end
    for i = 1, math.min(#list, GEAR_ROWS) do
        local e = list[i]
        print(L["%d. %s, ilvl %d, level %d%s: %s"]:format(i, View.LinkOf(e.id), e.ilvl, e.reqLevel,
            View.Marks(e, worn), View.Escape(e.line)))
    end
    local loading = 0
    for _ in pairs(pending) do
        loading = loading + 1
    end
    if loading > 0 then
        print(L["%d items are still loading; run the command again in a moment"]:format(loading))
    end
    print(L["Sorted by the number on the matching tooltip line, then item level and quality"])
end

-- gear [<slot>] [all] [<words>]: "all" right after the slot (or alone) also lists sourceless items; the words after
-- them search the tooltips and need a slot.
local function gear(args)
    local slot = table.remove(args, 1)
    local all = false
    if slot == "all" and #args == 0 then
        slot, all = nil, true
    elseif args[1] == "all" then
        all = true
        table.remove(args, 1)
    end
    if slot and not View.SLOT_LABELS[slot] then
        return unknownSlot(slot)
    end
    local query = table.concat(args, " ")
    local terms = ns.StatSearch.Parse(query)
    local className, classFile, level = View.Player()
    if not className then
        return
    end
    if terms then
        gearSearch(slot, all, terms, query, className, level, classFile)
        return
    end
    if slot then
        gearSlot(slot, all, className, level, classFile)
    else
        gearOverview(all, className, level, classFile)
    end
    print(L["Ranked by item level, then quality; stats are not considered"])
end

-- Returns the item ID of a shift-clicked link among args, or of a lone number, or nil.
local function itemArg(args)
    local id = table.concat(args, " "):match("item:(%d+)") or (#args == 1 and args[1]:match("^%d+$")) or nil
    return tonumber(id)
end

-- rank <item link|id>
local function rank(args)
    local id = itemArg(args)
    if not id then
        print(L["Tandem: usage /tandem rank <item link|id>"])
        return
    end
    local _, classFile, level = View.Player()
    if not classFile then
        return
    end
    local r = ns.Advisor.Rank(id, classFile, level)
    if not r then
        print(L["Tandem: item %d is not known; scan or loot it first"]:format(id))
        return
    end
    local link = View.LinkOf(id)
    if r.slot then
        -- Sourced: the sources follow, so no "(no known source)" mark.
        local row = { id = id, ilvl = ns.Advisor.Item(id)[1], sourced = true, usable = r.usable }
        print(L["%s: rank %d of %d for %s"]:format(link .. View.Marks(row, View.Equipped(r.slot)), r.rank, r.total,
            View.SlotLabel(r.slot)))
    else
        print(L["%s does not go in a ranked slot"]:format(link))
    end
    if r.deprecated then
        print(L["  this item is deprecated"])
    end
    if r.reason == "level" then
        print(L["  you cannot use it: level %d required"]:format(r.needLevel))
    elseif r.reason == "proficiency" then
        print(L["  your class cannot use it"])
    end
    for _, line in ipairs(View.SourceLines(id, SOURCE_ROWS)) do
        print(line)
    end
    if r.slot then
        print(L["Ranked by item level, then quality; stats are not considered"])
    end
end

-- Prints what make import would collect (decision 8); never reloads.
local function export()
    local c = ns.Store.Counts()
    print(L["Tandem export: %d loot entries, %d npc names, %d items, %d kills, %d looted corpses"]:format(c.loot,
        c.npcs, c.items, c.kills, c.corpses))
    print(L["Unsaved records: %d (saved on /reload or logout)"]:format(c.unsaved))
    if c.readOnly then
        print(L["Recording is off: saved data uses a newer schema"])
    end
    print(L["To contribute: type /reload, then run make import"])
end

-- browse [<slot>]: toggles the window, or opens it on a slot.
local function browse(args)
    if #args > 1 then
        return printUsage()
    end
    local slot = args[1]
    if not slot then
        ns.Browse.Toggle()
    elseif View.SLOT_LABELS[slot] then
        ns.Browse.Show(slot)
    else
        unknownSlot(slot)
    end
end

-- Prints one line per feature: ok when every API it needs is present, with each API's state.
local function check()
    print(L["Tandem API check:"])
    for _, feature in ipairs(ns.Check.Status()) do
        local apis = {}
        for i, api in ipairs(feature.apis) do
            apis[i] = api.path .. " " .. (api.ok and L["ok"] or L["missing"])
        end
        print(L["%s: %s (%s)"]:format(L[feature.name], feature.ok and L["ok"] or L["missing"],
            table.concat(apis, ", ")))
    end
end

-- map <item link|id> | clear
local function map(args)
    if #args == 1 and args[1] == "clear" then
        ns.MapPins.Clear()
        print(L["Tandem: map pins cleared"])
        return
    end
    local id = itemArg(args)
    if not id then
        print(L["Tandem: usage /tandem map <item link|id> or /tandem map clear"])
        return
    end
    ns.MapPins.Open(id)
end

-- Subcommands refused in combat (decision 9), before their arguments are read.
local NOT_IN_COMBAT = { gear = true, rank = true, export = true, browse = true, check = true, map = true }

-- minimap [on|off]: no argument toggles. Allowed in combat: the button is not a protected frame.
local MINIMAP_STATE = { on = true, off = false }

local function minimap(args)
    local shown
    if #args == 0 then
        shown = not ns.Launcher.IsButtonShown()
    elseif #args == 1 and MINIMAP_STATE[args[1]] ~= nil then
        shown = MINIMAP_STATE[args[1]]
    else
        return printUsage()
    end
    ns.Launcher.SetButtonShown(shown)
    print(shown and L["Tandem: minimap button shown"] or L["Tandem: minimap button hidden"])
end

function Commands.Run(msg)
    local args = {}
    for token in (msg or ""):lower():gmatch("%S+") do
        args[#args + 1] = token
    end
    local sub = table.remove(args, 1)
    if NOT_IN_COMBAT[sub] and View.InCombat() then
        return
    end
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
    elseif sub == "browse" then
        browse(args)
    elseif sub == "minimap" then
        minimap(args)
    elseif sub == "check" and #args == 0 then
        check()
    elseif sub == "map" then
        map(args)
    else
        printUsage()
    end
end

SLASH_TANDEM1 = "/tandem"
SlashCmdList.TANDEM = Commands.Run
