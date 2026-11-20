local _, ns = ...

-- Killers: Forever has no combat log, so the enemy players who killed the player are the hostile players seen
-- targeting the player shortly before death. Target, focus, mouseover and the nameplate units are read as their events
-- fire, and all of them on every UNIT_COMBAT on the player; each hostile player targeting the player is remembered
-- with the time. At PLAYER_DEAD, after one last scan, everyone seen within WINDOW seconds is saved once through
-- Store.AddKiller. Any unit read that is nil, secret or raises makes the unit not count.
-- Nearby alert (D4): a hostile player already saved as one of the character's killers who shows on a nameplate, the
-- target, mouseover or focus is announced, in or out of combat, on Tandem's own frame at the top of the screen for
-- HOLD seconds, in chat and with the raid warning sound; at most once per COOLDOWN seconds per name.
local Killers = {}
ns.Killers = Killers

local WINDOW = 10
local NAMEPLATES = 40
local EVENTS = { "UNIT_TARGET", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_FOCUS_CHANGED", "UNIT_COMBAT", "PLAYER_DEAD" }
local UNITS = { "target", "focus", "mouseover" }
local SCANNED = { target = true, focus = true, mouseover = true }
local COOLDOWN = 60
local HOLD = 5
local L = ns.L

local call = ns.Store.Call
local registered = {}
local seen = {}
local alerted = {}
local banner

local function now()
    return tonumber((call(GetTime))) or 0
end

local function isText(v)
    return type(v) == "string" and v ~= ""
end

-- The enemy names already logged as having no readable realm this session.
local noRealmLogged = {}

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
        if not noRealmLogged[name] then
            noRealmLogged[name] = true
            ns.Debug.Log("killers: no realm for " .. name)
        end
        return nil
    end
    local _, class = call(UnitClass, unit)
    local level = call(UnitLevel, unit)
    return { name = name, realm = realm, fullName = name .. "-" .. realm,
        class = type(class) == "string" and class:match("^[A-Z]+$") and class or nil,
        level = type(level) == "number" and level >= 1 and level == math.floor(level) and level or nil }
end

-- The character's saved killer entry for fullName, or nil.
local function killer(fullName)
    local key = ns.Weights.CharacterKey()
    for _, k in ipairs(key and ns.Store.Killers(key) or {}) do
        if k.fullName == fullName then
            return k
        end
    end
end

-- Tandem's alert frame, made on first use: large red text at the top centre that hides HOLD seconds after it shows.
local function alertFrame()
    if not banner then
        banner = CreateFrame("Frame", "TandemKillerAlert", UIParent)
        banner:SetSize(800, 60)
        banner:SetPoint("TOP", UIParent, "TOP", 0, -120)
        banner:SetFrameStrata("HIGH")
        banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        banner.text:SetPoint("CENTER", banner, "CENTER", 0, 0)
        banner.text:SetTextColor(1, 0.1, 0.1)
        banner:SetScript("OnUpdate", function(self)
            if now() >= self.hideAt then
                self:Hide()
            end
        end)
    end
    return banner
end

-- Announces who when saved as a killer and not announced within COOLDOWN.
local function alert(who)
    local last = alerted[who.fullName]
    if last and now() - last < COOLDOWN then
        return
    end
    local k = killer(who.fullName)
    if not k then
        return
    end
    alerted[who.fullName] = now()
    local text = L["%s is nearby (seen at your death %d times)"]:format(who.fullName, k.count)
    local f = alertFrame()
    f.text:SetText(text)
    f.hideAt = now() + HOLD
    f:Show()
    print(text)
    call(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    ns.Debug.Log("killers: nearby " .. who.fullName)
end

-- Remembers unit with the current time when it exists and is a hostile player targeting the player; with warn, also
-- alerts when it is a saved killer.
local function look(unit, warn)
    if call(UnitExists, unit) ~= true then
        return
    end
    local who = identity(unit)
    if not who then
        return
    end
    if call(UnitIsUnit, unit .. "target", "player") == true then
        seen[who.fullName] = { name = who.name, realm = who.realm, class = who.class, level = who.level, at = now() }
    end
    if warn then
        alert(who)
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
    if ns.KillersView then
        ns.KillersView.Refresh()
    end
end

local function handle(event, unit)
    if event == "PLAYER_DEAD" then
        record()
    elseif event == "UNIT_COMBAT" then
        if unit == "player" then
            scan()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        look("target", true)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        look("mouseover", true)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        look("focus", true)
    elseif type(unit) ~= "string" then
        return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if unit:match("^nameplate%d+$") then
            look(unit, true)
        end
    elseif SCANNED[unit] or unit:match("^nameplate%d+$") then
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
