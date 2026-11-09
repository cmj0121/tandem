local _, ns = ...

-- The debug recorder (stage 12, D13): off by default; `/tandem debug on` records the lines modules pass to
-- Debug.Log (time, combat state and what) into the TandemDebug saved variable, which the client writes to disk on
-- /reload or logout for a developer to read. Nothing is printed while it records. A snapshot (2 s after login, on
-- every layout change, or `/tandem debug snap`) lists every named, visible child of UIParent in the bottom band and
-- the known status (XP) bar frames, to find which Blizzard frame shows where. It hooks nothing.
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
    log[#log + 1] = ("%.2f combat=%s %s"):format(tonumber(call(GetTime)) or 0,
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

-- Logs the watched status bar frames, then every named, visible UIParent child in the bottom band.
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
