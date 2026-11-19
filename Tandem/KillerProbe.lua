local _, ns = ...

-- The killers probe: before Tandem records which enemy players killed the player, it must learn which unit facts
-- Forever lets addons read, in and out of combat. While the debug recorder is on, this logs a snapshot of target,
-- mouseover, focus and the nameplate units as their events fire (at most one line per unit and combat state every
-- THROTTLE seconds), and of every such unit at PLAYER_DEAD. A snapshot shows, per API, whether
-- each return is plain, secret, nil or raised ("err"); flags show their plain value; a player's name, realm, class
-- and level show in plain so the developer can match them, a mob's do not. Each event is logged once when registered
-- and once when it first fires. Lines go to TandemDebug.killers (the last LIMIT), which login does not flush. The
-- events go on Tandem's own frame, which forwards them through KillerProbe.OnEvent. Reads only.
local KillerProbe = {}
ns.KillerProbe = KillerProbe

local LIMIT = 200
local THROTTLE = 5
local NAMEPLATES = 40
local EVENTS = { "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED",
    "UNIT_TARGET", "PLAYER_DEAD" }
local UNITS = { target = true, mouseover = true, focus = true }

local registered = {}
local fired = {}
local last = {}

local call = ns.Store.Call

local function isSecret(v)
    local fn = _G.issecretvalue
    if type(fn) ~= "function" then
        return false
    end
    local ok, s = pcall(fn, v)
    return not ok or s == true
end

local function now()
    return tonumber((call(_G.GetTime))) or 0
end

local function combat()
    return call(_G.InCombatLockdown) == true
end

local function log(what)
    if not ns.Debug.IsOn() then
        return
    end
    local d = TandemDebug
    if type(d.killers) ~= "table" then
        d.killers = {}
    end
    local lines = d.killers
    lines[#lines + 1] = ("%.2f combat=%s %s"):format(now(), tostring(combat()), what)
    while #lines > LIMIT do
        table.remove(lines, 1)
    end
end

-- Returns v as "secret", "nil" or "plain".
local function kind(v)
    if isSecret(v) then
        return "secret"
    end
    return v == nil and "nil" or "plain"
end

-- Returns v as text for a plain value, else its kind.
local function value(v)
    if isSecret(v) or v == nil then
        return kind(v)
    end
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

-- Calls fn(...) and returns { ok, first, second }.
local function probe(fn, ...)
    if type(fn) ~= "function" then
        return { false }
    end
    local ok, a, b = pcall(fn, ...)
    return { ok, a, b }
end

local function kinds(r, n)
    if not r[1] then
        return "err"
    end
    local out = {}
    for i = 1, n do
        out[i] = kind(r[i + 1])
    end
    return table.concat(out, ",")
end

local function flag(r)
    return r[1] and value(r[2]) or "err"
end

local function nameplate(unit)
    return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

-- Logs one unit's snapshot for reason; nothing when the unit plainly does not exist.
local function snapshot(reason, unit)
    local exists = probe(_G.UnitExists, unit)
    if exists[1] and not isSecret(exists[2]) and not exists[2] then
        return
    end
    local name, full = probe(_G.UnitName, unit), probe(_G.UnitFullName, unit)
    local player = probe(_G.UnitIsPlayer, unit)
    local class, level = probe(_G.UnitClass, unit), probe(_G.UnitLevel, unit)
    local line = ("snap %s %s exists=%s name=%s full=%s player=%s attack=%s targetsMe=%s guid=%s class=%s level=%s")
        :format(reason, unit, flag(exists), kinds(name, 2), kinds(full, 2), flag(player),
            flag(probe(_G.UnitCanAttack, "player", unit)), flag(probe(_G.UnitIsUnit, unit .. "target", "player")),
            kinds(probe(_G.UnitGUID, unit), 1), kinds(class, 2), kinds(level, 1))
    if player[1] and not isSecret(player[2]) and player[2] == true then
        local realm = name[3]
        if not isSecret(realm) and realm == nil then
            realm = full[3]
        end
        line = line .. (" | %s-%s %s %s"):format(value(name[2]), value(realm), value(class[3]), value(level[2]))
    end
    log(line)
end

-- Snapshots unit unless it logged one in this combat state within THROTTLE.
local function throttled(reason, unit)
    local key = unit .. tostring(combat())
    local t = now()
    if last[key] and t - last[key] < THROTTLE then
        return
    end
    last[key] = t
    snapshot(reason, unit)
end

local function args(...)
    local out = {}
    for i = 1, select("#", ...) do
        out[i] = value((select(i, ...)))
    end
    return table.concat(out, " ")
end

local function handle(event, ...)
    if not fired[event] then
        fired[event] = true
        log(("first %s %s"):format(event, args(...)))
    end
    local unit = ...
    if isSecret(unit) then
        unit = nil
    end
    if event == "PLAYER_DEAD" then
        for u in pairs(UNITS) do
            snapshot("dead", u)
        end
        for i = 1, NAMEPLATES do
            snapshot("dead", "nameplate" .. i)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        throttled(event, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        throttled(event, "mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        throttled(event, "focus")
    elseif (event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_TARGET")
        and (UNITS[unit] or nameplate(unit)) then
        throttled(event, unit)
    end
end

-- Logs a probed event Tandem's frame received while the recorder is on; any other event is ignored.
function KillerProbe.OnEvent(event, ...)
    if not registered[event] or not ns.Debug.IsOn() then
        return
    end
    local ok, err = pcall(handle, event, ...)
    if not ok then
        pcall(log, "error " .. value(err))
    end
end

-- PLAYER_LOGIN: registers the probed events on frame (Tandem's) and logs which the client accepts.
function KillerProbe.OnLogin(frame)
    if next(registered) then
        return
    end
    for _, event in ipairs(EVENTS) do
        local ok = ns.Store.RegisterEvent(frame, event)
        registered[event] = ok or nil
        log(("%s registered=%s"):format(event, tostring(ok)))
    end
end
