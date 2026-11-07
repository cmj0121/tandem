local _, ns = ...

-- The /tandem slash command: parses input and prints or dispatches to the other modules.
local Commands = {}
ns.Commands = Commands

local L = ns.L
local View = ns.View

local function printUsage()
    print(L["Tandem commands:"])
    print(L["  /tandem check - list the client APIs each feature needs"])
    print(L["  /tandem weights - show the stat weights of your talent tree"])
    print(L["  /tandem weights spec <1|2|3|auto> - pick the talent tree, or follow your talents"])
    print(L["  /tandem weights set <stat> <number> - set your own weight for a stat (0 ignores it)"])
    print(L["  /tandem weights reset - drop your own weights for the active tree"])
end

-- Returns a whole number >= min parsed from s, or nil.
local function parseInt(s, min)
    local n = s and s:match("^%d+$") and tonumber(s)
    if n and n >= min then
        return n
    end
end

-- Prints one line per feature: ok when every API it needs is present, with each API's state; then one line per probe.
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
    for _, probe in ipairs(ns.Check.Probes()) do
        print(L["Probe: %s %s"]:format(probe.path, probe.ok and L["present"] or L["missing"]))
    end
end

local IS_STAT = {}
for _, key in ipairs(ns.Store.STAT_KEYS) do
    IS_STAT[key] = true
end

local WEIGHTS_USAGE = "Tandem: usage /tandem weights [spec <1|2|3|auto> | set <stat> <number> | reset]"

-- Prints the active tree, whether it follows the talents, and its effective weights with the own ones marked.
local function showWeights(className, classFile, level)
    local spec, auto = ns.Weights.Active(classFile, level)
    print(L["Tandem: %s %s weights, tree %d (%s)"]:format(L[ns.Weights.SPECS[classFile][spec]], className, spec,
        auto and L["auto"] or L["manual"]))
    local weights, own = ns.Weights.Effective(classFile, spec), ns.Weights.Overrides(spec)
    local parts, marked = {}, false
    for _, key in ipairs(ns.Store.STAT_KEYS) do
        if weights[key] then
            parts[#parts + 1] = ("%s %g%s"):format(key, weights[key], own[key] and "*" or "")
            marked = marked or own[key] ~= nil
        end
    end
    print(#parts > 0 and table.concat(parts, ", ") or L["none"])
    if marked then
        print(L["  * your own weight; /tandem weights reset drops them"])
    end
end

-- Returns the number typed as s (digits, an optional sign and decimal point), or nil.
local function parseWeight(s)
    return s and s:match("^%-?%d*%.?%d+$") and tonumber(s)
end

-- weights [spec <1|2|3|auto> | set <stat> <number> | reset] (decision 8): each change prints a line, then the
-- weights as they now are.
local function weights(args)
    local sub = args[1]
    local spec = sub == "spec" and #args == 2 and (args[2] == "auto" and "auto" or parseInt(args[2], 1))
    local key, w = sub == "set" and #args == 3 and args[2], sub == "set" and parseWeight(args[3])
    if not (#args == 0 or (spec and (spec == "auto" or spec <= 3)) or (key and w) or (sub == "reset" and #args == 1))
    then
        print(L[WEIGHTS_USAGE])
        return
    end
    if key and not IS_STAT[key] then
        print(L["Tandem: unknown stat %s; use one of: %s"]:format(key, table.concat(ns.Store.STAT_KEYS, " ")))
        return
    end
    local className, classFile, level = View.Player()
    if not className then
        return
    end
    local active = ns.Weights.Active(classFile, level)
    if not active then
        print(L["Tandem: no built-in weights for %s"]:format(className))
        return
    end
    local ok, done = true
    if spec then
        ok = ns.Weights.SetSpec(spec)
        done = spec == "auto" and L["Tandem: weights follow your talents"]
            or L["Tandem: weights use tree %d"]:format(spec)
    elseif key then
        ok = ns.Weights.SetOverride(key, w, classFile, level)
        done = L["Tandem: %s weight set to %s"]:format(key, ("%g"):format(w))
    elseif sub == "reset" then
        ok = ns.Weights.Reset(classFile, level)
        done = L["Tandem: own weights for tree %d dropped"]:format(active)
    end
    if not ok then
        print(L["Tandem: weights cannot be saved: recording is off or your character is not known yet"])
        return
    end
    if done then
        print(done)
    end
    showWeights(className, classFile, level)
end

-- Subcommands refused in combat (decision 9), before their arguments are read.
local NOT_IN_COMBAT = { check = true, weights = true }

function Commands.Run(msg)
    local args = {}
    for token in (msg or ""):lower():gmatch("%S+") do
        args[#args + 1] = token
    end
    local sub = table.remove(args, 1)
    if NOT_IN_COMBAT[sub] and View.InCombat() then
        return
    end
    if sub == "check" and #args == 0 then
        check()
    elseif sub == "weights" then
        weights(args)
    else
        printUsage()
    end
end

SLASH_TANDEM1 = "/tandem"
SlashCmdList.TANDEM = Commands.Run
