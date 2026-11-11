local _, ns = ...

-- The debug recorder (stage 12, D13): off by default; `/tandem debug on` records the lines modules pass to
-- Debug.Log (time, combat state and what) into the TandemDebug saved variable, which the client writes to disk on
-- /reload or logout for a developer to read. Nothing is printed while it records. A snapshot (2 s after login, on
-- every layout change, or `/tandem debug snap`) lists every named, visible child of UIParent in the bottom band and
-- the known status (XP) bar frames, to find which Blizzard frame shows where; it also walks the minimap's frames and
-- lists the minimap and coordinate CVars, to find the client's own coordinates text (D11). It hooks nothing.
local Debug = {}
ns.Debug = Debug

local MAX = 300
-- Frames whose state a snapshot always logs, shown or not: Blizzard's status (XP / reputation) bars.
local WATCHED = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
    "MainMenuExpBar", "MainMenuBarExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }
-- A snapshot lists visible frames whose bottom edge sits this low on screen.
local BAND = 300
-- A snapshot reads at most this many UIParent children.
local MAX_CHILDREN = 400
-- The minimap probe walks this deep under MinimapCluster and Minimap, reads at most this many frames and regions, and
-- logs at most this many of them; it logs at most this many CVars.
local MM_DEPTH, MM_NODES, MM_LINES, MM_CVARS = 6, 600, 60, 30

local call = ns.Store.Call

local function db()
    if type(TandemDebug) ~= "table" then
        TandemDebug = {}
    end
    if type(TandemDebug.log) ~= "table" then
        TandemDebug.log = {}
    end
    return TandemDebug
end

function Debug.IsOn()
    return type(TandemDebug) == "table" and TandemDebug.on == true
end

local function text(v)
    if type(v) == "table" then
        return tostring(call(v.GetName, v) or "<frame>")
    end
    return tostring(v)
end

-- Appends one line (time, combat, what) while recording; the oldest lines go past MAX.
function Debug.Log(what)
    if not Debug.IsOn() then
        return
    end
    local log = db().log
    log[#log + 1] = ("%.2f combat=%s %s"):format(tonumber((call(GetTime))) or 0,
        tostring(call(InCombatLockdown) == true), what)
    while #log > MAX do
        table.remove(log, 1)
    end
end

local function describe(f)
    local alpha = tonumber(call(f.GetEffectiveAlpha, f) or call(f.GetAlpha, f))
    return ("shown %s visible %s alpha %s at %s,%s size %sx%s parent %s"):format(text(call(f.IsShown, f)),
        text(call(f.IsVisible, f)), alpha and ("%.2f"):format(alpha) or "nil", text(call(f.GetLeft, f)),
        text(call(f.GetBottom, f)), text(call(f.GetWidth, f)), text(call(f.GetHeight, f)), text(call(f.GetParent, f)))
end

-- The snapshot line for one UIParent child, or nil when it is unnamed, hidden or above the band.
local function childLine(f)
    local name = type(f) == "table" and call(f.GetName, f)
    local bottom = type(f) == "table" and tonumber(call(f.GetBottom, f))
    if type(name) == "string" and bottom and bottom < BAND and call(f.IsVisible, f) then
        return "  frame " .. name .. ": " .. describe(f)
    end
end

-- Reads one probed node: logs it when it is named or a FontString with text, and queues its children and regions
-- while above MM_DEPTH. Returns the lines logged (0 or 1).
local function visit(node, queue, seen)
    local f, chain, depth = node[1], node[2], node[3]
    local name, kind, label = call(f.GetName, f), call(f.GetObjectType, f), call(f.GetText, f)
    label = type(label) == "string" and label or ""
    local logged = 0
    if type(name) == "string" or (kind == "FontString" and label ~= "") then
        Debug.Log(("  mmtree %s %s shown %s text %s"):format(chain, text(kind), text(call(f.IsShown, f)),
            (label:gsub("|", "||"))))
        logged = 1
    end
    if depth < MM_DEPTH then
        for _, list in ipairs({ { "c", f.GetChildren }, { "r", f.GetRegions } }) do
            for i, kid in ipairs({ call(list[2], f) }) do
                if #queue >= MM_NODES then
                    return logged
                end
                if type(kid) == "table" and not seen[kid] then
                    seen[kid] = true
                    local kidName = call(kid.GetName, kid)
                    queue[#queue + 1] = { kid, chain .. "." .. (type(kidName) == "string" and kidName or list[1] .. i),
                        depth + 1 }
                end
            end
        end
    end
    return logged
end

-- Walks MinimapCluster and Minimap breadth first, so each node is seen at its shallowest depth, logging every named
-- node and every FontString with text as "mmtree <chain> <type> shown <shown> text <text>". A node that raises is
-- skipped.
local function probeMinimap()
    local queue, seen, lines = {}, {}, 0
    for _, name in ipairs({ "MinimapCluster", "Minimap" }) do
        local f = _G[name]
        if type(f) == "table" and not seen[f] then
            seen[f] = true
            queue[#queue + 1] = { f, name, 0 }
        end
    end
    local i = 1
    while queue[i] and lines < MM_LINES do
        local ok, logged = pcall(visit, queue[i], queue, seen)
        lines = lines + (ok and logged or 0)
        i = i + 1
    end
end

-- Logs "mmcvar <name>=<value>" for each console CVar whose name holds "coord" or "minimap", any case.
local function probeCVars()
    local console = _G.C_Console
    local all = type(console) == "table" and console.GetAllCommands
    if type(all) ~= "function" then
        all = _G.ConsoleGetAllCommands
    end
    all = call(all)
    if type(all) ~= "table" then
        return
    end
    local lines = 0
    for _, command in ipairs(all) do
        local name = type(command) == "table" and command.command or command
        local low = type(name) == "string" and name:lower() or ""
        if low:find("coord", 1, true) or low:find("minimap", 1, true) then
            Debug.Log(("  mmcvar %s=%s"):format(name, text(ns.Store.GetCVar(name))))
            lines = lines + 1
            if lines >= MM_CVARS then
                return
            end
        end
    end
end

-- Logs the watched status bar frames, the minimap probe and its CVars, then every named, visible UIParent child in
-- the bottom band.
function Debug.Snapshot(why)
    if not Debug.IsOn() then
        return
    end
    Debug.Log("snapshot " .. tostring(why))
    for _, name in ipairs(WATCHED) do
        local f = _G[name]
        local ok, state = pcall(describe, f)
        Debug.Log("  watch " .. name .. ": " .. (type(f) ~= "table" and "missing" or ok and state or "unreadable"))
    end
    probeMinimap()
    pcall(probeCVars)
    local parent = _G.UIParent
    local children = type(parent) == "table" and { pcall(parent.GetChildren, parent) } or { false }
    if not children[1] then
        return
    end
    -- Each child is read under pcall, at most MAX_CHILDREN of them: a forbidden or odd frame is skipped, never an
    -- error, and a crowded UIParent cannot make the snapshot run too long.
    for i = 2, math.min(#children, MAX_CHILDREN + 1) do
        local ok, line = pcall(childLine, children[i])
        if ok and line then
            Debug.Log(line)
        end
    end
end

local function checkLines()
    for _, feature in ipairs(ns.Check.Status()) do
        local apis = {}
        for i, api in ipairs(feature.apis) do
            apis[i] = api.path .. " " .. (api.ok and "ok" or "missing")
        end
        Debug.Log(("check %s: %s (%s)"):format(feature.name, feature.ok and "ok" or "missing",
            table.concat(apis, ", ")))
    end
    for _, probe in ipairs(ns.Check.Probes()) do
        Debug.Log(("probe %s: %s"):format(probe.path, probe.ok and "ok" or "missing"))
    end
end

-- Logs what /tandem check prints, in English: "check <feature>: ok|missing (<path> ok|missing, ...)" per feature,
-- then "probe <path>: ok|missing" per probe.
function Debug.Check()
    if Debug.IsOn() then
        pcall(checkLines)
    end
end

-- Turns recording on or off (on starts a fresh log); returns the number of lines kept.
function Debug.Set(on)
    local d = db()
    d.on = on == true
    if d.on then
        d.log = {}
        Debug.Log("debug on")
    end
    return #d.log
end

-- At login: keeps recording across /reload while it is on, with a snapshot once the UI has settled.
function Debug.OnLogin()
    if Debug.IsOn() then
        Debug.Log("login")
        Debug.Check()
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(2, function()
                Debug.Snapshot("login")
            end)
        end
    end
end

ns.Layout.OnChange(function(on)
    Debug.Snapshot(on and "layout on" or "layout off")
end)
