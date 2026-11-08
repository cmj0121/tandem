local _, ns = ...

-- The debug recorder (stage 12, D13): off by default; `/tandem debug on` records every move of Blizzard's totem bar
-- (MultiCastActionBarFrame SetPoint, ClearAllPoints, SetParent, Show, Hide) with its caller's stack, the related
-- events and Tandem's own totem bar decisions into the TandemDebug saved variable, which the client writes to disk
-- on /reload or logout for a developer to read. Nothing is printed while it records.
local Debug = {}
ns.Debug = Debug

local MAX = 300
local METHODS = { "SetPoint", "ClearAllPoints", "SetParent", "Show", "Hide" }
local EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
    "UPDATE_MULTI_CAST_ACTIONBAR", "PLAYER_TOTEM_UPDATE" }

local hooked, listening

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

-- At login: keeps recording across /reload while it is on.
function Debug.OnLogin()
    if Debug.IsOn() then
        start()
        Debug.Log("login")
    end
end
