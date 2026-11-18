local _, ns = ...

-- Killers: Forever has no combat log, so the enemy players who killed the player are the hostile players seen
-- targeting the player shortly before death. Target, focus, mouseover and the nameplate units are read as their events
-- fire, and all of them on every UNIT_COMBAT on the player; each hostile player targeting the player is remembered
-- with the time. At PLAYER_DEAD, after one last scan, everyone seen within WINDOW seconds is saved once through
-- Store.AddKiller. Any unit read that is nil, secret or raises makes the unit not count.
local Killers = {}
ns.Killers = Killers

local WINDOW = 10
local NAMEPLATES = 40
local EVENTS = { "UNIT_TARGET", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_FOCUS_CHANGED", "UNIT_COMBAT", "PLAYER_DEAD" }
local UNITS = { "target", "focus", "mouseover" }
local SCANNED = { target = true, focus = true, mouseover = true }

local call = ns.Store.Call
local registered = {}
local seen = {}

local function now()
    return tonumber((call(GetTime))) or 0
end

local function isText(v)
    return type(v) == "string" and v ~= ""
end

-- Returns { name, realm, fullName, class, level } of unit when it is a hostile player (D1), else nil. class is the
-- class file and level a level of at least 1, each nil when unreadable.
local function identity(unit)
    if call(UnitIsPlayer, unit) ~= true or call(UnitCanAttack, "player", unit) ~= true then
        return nil
    end
    local name, realm = call(UnitName, unit)
    if not isText(name) then
        return nil
    end
    if not isText(realm) then
        realm = select(2, call(UnitFullName, unit))
    end
    if not isText(realm) then
        realm = call(GetNormalizedRealmName) or call(GetRealmName)
    end
    if not isText(realm) then
        return nil
    end
    local _, class = call(UnitClass, unit)
    local level = call(UnitLevel, unit)
    return { name = name, realm = realm, fullName = name .. "-" .. realm,
        class = type(class) == "string" and class:match("^[A-Z]+$") and class or nil,
        level = type(level) == "number" and level >= 1 and level == math.floor(level) and level or nil }
end

-- Remembers unit with the current time when it exists and is a hostile player targeting the player.
local function look(unit)
    if call(UnitExists, unit) ~= true then
        return
    end
    local who = identity(unit)
    if who and call(UnitIsUnit, unit .. "target", "player") == true then
        seen[who.fullName] = { name = who.name, realm = who.realm, class = who.class, level = who.level, at = now() }
    end
end

-- Forgets sightings older than WINDOW, then looks at every unit.
local function scan()
    local since = now() - WINDOW
    for fullName, s in pairs(seen) do
        if s.at < since then
            seen[fullName] = nil
        end
    end
    for _, u in ipairs(UNITS) do
        look(u)
    end
    for i = 1, NAMEPLATES do
        look("nameplate" .. i)
    end
end

local function record()
    scan()
    local key = ns.Weights.CharacterKey()
    local since, zone, when = now() - WINDOW, call(GetRealZoneText), call(time)
    for fullName, s in pairs(seen) do
        if key and s.at >= since and ns.Store.AddKiller(key, { name = s.name, realm = s.realm, class = s.class,
            level = s.level, zone = isText(zone) and zone or nil, when = when }) then
            ns.Debug.Log("killers: recorded " .. fullName)
        end
    end
    seen = {}
end

local function handle(event, unit)
    if event == "PLAYER_DEAD" then
        record()
    elseif event == "UNIT_COMBAT" then
        if unit == "player" then
            scan()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        look("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        look("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        look("focus")
    elseif type(unit) == "string" and (SCANNED[unit] or unit:match("^nameplate%d+$")) then
        look(unit)
    end
end

-- The events Killers.OnLogin registered, forwarded by Tandem's frame; any other event is ignored.
function Killers.OnEvent(event, ...)
    if registered[event] then
        handle(event, ns.Store.Safe((...)))
    end
end

-- PLAYER_LOGIN: registers Killers' events on frame (Tandem's); an event the client does not know is skipped.
function Killers.OnLogin(frame)
    for _, event in ipairs(EVENTS) do
        registered[event] = ns.Store.RegisterEvent(frame, event) or nil
    end
end
