local _, ns = ...

-- The debug recorder (stage 12, D13): off by default; `/tandem debug on` records every move of Blizzard's totem bar
-- (MultiCastActionBarFrame SetPoint, ClearAllPoints, SetParent, Show, Hide) with its caller's stack, the related
-- events and Tandem's own totem bar decisions into the TandemDebug saved variable, which the client writes to disk
-- on /reload or logout for a developer to read. Nothing is printed while it records. A snapshot (2 s after login, on
-- every layout change, or `/tandem debug snap`) lists every named, visible child of UIParent in the bottom band and
-- the known status (XP) bar frames, to find which Blizzard frame shows where.
local Debug = {}
ns.Debug = Debug

local MAX = 300
local METHODS = { "SetPoint", "ClearAllPoints", "SetParent", "Show", "Hide" }
local EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
    "UPDATE_MULTI_CAST_ACTIONBAR", "PLAYER_TOTEM_UPDATE" }

local hooked, listening
-- Frames whose state a snapshot always logs, shown or not: Blizzard's status (XP / reputation) bars.
local WATCHED = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
    "MainMenuExpBar", "MainMenuBarExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }
-- A snapshot lists visible frames whose bottom edge sits this low on screen.
local BAND = 300
-- A snapshot reads at most this many UIParent children.
local MAX_CHILDREN = 400

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok then
        return ns.Store.Safe(v)
    end
end

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

-- The totem bar's screen position and anchor points, "-" without the bar.
local function where()
    local f = _G.MultiCastActionBarFrame
    if type(f) ~= "table" then
        return "-"
    end
    local points = {}
    for i = 1, tonumber(call(f.GetNumPoints, f)) or 0 do
        local ok, p, r, rp, x, y = pcall(f.GetPoint, f, i)
        if ok then
            points[#points + 1] = ("%s %s %s %s %s"):format(text(p), text(r), text(rp), text(x), text(y))
        end
    end
    return ("at %s,%s strata %s parent %s [%s]"):format(text(call(f.GetLeft, f)), text(call(f.GetBottom, f)),
        text(call(f.GetFrameStrata, f)), text(call(f.GetParent, f)), table.concat(points, "; "))
end

local function stack()
    local s = call(debugstack, 3, 6, 0)
    if type(s) ~= "string" then
        return ""
    end
    return (s:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("%s*\n%s*", " < "))
end

-- Appends one line (time, combat, what, the totem bar's state, and the caller's stack when asked) while recording.
function Debug.Log(what, withStack)
    if not Debug.IsOn() then
        return
    end
    local log = db().log
    log[#log + 1] = ("%.2f combat=%s %s | %s%s"):format(tonumber(call(GetTime)) or 0,
        tostring(call(InCombatLockdown) == true), what, where(), withStack and (" | " .. stack()) or "")
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
        local f = children[i]
        local ok, line = pcall(function()
            local name = type(f) == "table" and call(f.GetName, f)
            local bottom = type(f) == "table" and tonumber(call(f.GetBottom, f))
            if type(name) == "string" and bottom and bottom < BAND and call(f.IsVisible, f) then
                return "  frame " .. name .. ": " .. describe(f)
            end
        end)
        if ok and line then
            Debug.Log(line)
        end
    end
end

local function hook()
    local f = _G.MultiCastActionBarFrame
    if hooked or type(f) ~= "table" or type(hooksecurefunc) ~= "function" then
        return
    end
    hooked = true
    for _, method in ipairs(METHODS) do
        if type(f[method]) == "function" then
            pcall(hooksecurefunc, f, method, function(_, ...)
                local args = {}
                for i = 1, select("#", ...) do
                    args[i] = text((select(i, ...)))
                end
                Debug.Log(method .. "(" .. table.concat(args, ", ") .. ")", true)
            end)
        end
    end
end

local function listen()
    if listening or type(CreateFrame) ~= "function" then
        return
    end
    listening = CreateFrame("Frame", nil, UIParent)
    for _, event in ipairs(EVENTS) do
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            ns.Store.RegisterUnitEvent(listening, event, "player")
        else
            ns.Store.RegisterEvent(listening, event)
        end
    end
    listening:SetScript("OnEvent", function(_, event, ...)
        local extra = event == "UNIT_SPELLCAST_SUCCEEDED" and (" spell " .. text(select(3, ...))) or ""
        Debug.Log("event " .. event .. extra)
    end)
end

local function start()
    hook()
    listen()
end

-- Turns recording on or off (on starts a fresh log); returns the number of lines kept.
function Debug.Set(on)
    local d = db()
    d.on = on == true
    if d.on then
        d.log = {}
        start()
        Debug.Log("debug on")
    end
    return #d.log
end

-- At login: keeps recording across /reload while it is on, with a snapshot once the UI has settled.
function Debug.OnLogin()
    if Debug.IsOn() then
        start()
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
