local _, ns = ...

-- The mana probe: before Tandem shows a five-second-rule mana countdown, it must learn how Forever lets an addon tell
-- a mana-spending cast in combat, where UnitPower is secret. While the debug recorder is on, this logs each player
-- UNIT_SPELLCAST_SUCCEEDED as "cast id=<id> name=<name> cost=<cost> texture=<texture>", the cost being each
-- C_Spell.GetSpellPowerCost entry as type:cost:costPercent; and each player UNIT_POWER_UPDATE and UNIT_POWER_FREQUENT
-- as "<event> token=<token> gap=<s> sinceCast=<s>", the seconds since the previous firing of that event and since the
-- last cast ("none" before the first), never the amount. Once at login it logs whether a CooldownFrameTemplate frame
-- can be made and UnitPowerType("player"). Each line carries GetTime and the combat state. A value the client keeps
-- secret logs "secret", a raising read "error", a missing function "nil-fn". Lines go to TandemDebug.mana (the last
-- LIMIT), which login does not flush, up to LIMIT a session. The events go on this module's own frame, for the player
-- only. Reads only, and logs nothing while the recorder is off.
local ManaProbe = {}
ns.ManaProbe = ManaProbe

local LIMIT = 500
local EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }

local events
local lines = 0
local lastCast
local lastPower = {}

local call = ns.Store.Call

local function isSecret(v)
    local fn = _G.issecretvalue
    if type(fn) ~= "function" then
        return false
    end
    local ok, s = pcall(fn, v)
    return not ok or s == true
end

-- Returns v as text: "secret" for a value the client keeps secret, else tostring, or "?" when that raises.
local function text(v)
    if isSecret(v) then
        return "secret"
    end
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

-- Returns the results of a pcall as text: "error" when it raised, else each return joined by spaces ("nil" for none).
local function results(ok, ...)
    if not ok then
        return "error"
    end
    local n = select("#", ...)
    if n == 0 then
        return "nil"
    end
    local out = {}
    for i = 1, n do
        out[i] = text((select(i, ...)))
    end
    return table.concat(out, " ")
end

-- Returns fn(...) as text, or "nil-fn" when fn is not a function.
local function read(fn, ...)
    if type(fn) ~= "function" then
        return "nil-fn"
    end
    return results(pcall(fn, ...))
end

-- Returns t[key], or nil when t is not a plain table or indexing it raises.
local function field(t, key)
    if type(t) ~= "table" or isSecret(t) then
        return nil
    end
    local ok, v = pcall(function()
        return t[key]
    end)
    return ok and v or nil
end

local function now()
    local t = call(_G.GetTime)
    return not isSecret(t) and tonumber(t) or 0
end

local function log(what)
    if lines >= LIMIT or not ns.Debug.IsOn() then
        return
    end
    lines = lines + 1
    local d = TandemDebug
    if type(d.mana) ~= "table" then
        d.mana = {}
    end
    local out = d.mana
    out[#out + 1] = ("%.2f combat=%s %s"):format(now(), tostring(call(_G.InCombatLockdown) == true), what)
    while #out > LIMIT do
        table.remove(out, 1)
    end
end

local function isPlayer(unit)
    return not isSecret(unit) and unit == "player"
end

-- Returns spell id's power costs as text: each entry as type:cost:costPercent joined by commas, "none" for no entry.
local function cost(id)
    local fn = field(_G.C_Spell, "GetSpellPowerCost")
    if type(fn) ~= "function" then
        return "nil-fn"
    end
    local ok, costs = pcall(fn, id)
    if not ok then
        return "error"
    end
    if isSecret(costs) then
        return "secret"
    end
    if type(costs) ~= "table" then
        return text(costs)
    end
    local out = {}
    local walked = pcall(function()
        for _, entry in ipairs(costs) do
            if isSecret(entry) then
                out[#out + 1] = "secret"
            else
                out[#out + 1] = text(field(entry, "type")) .. ":" .. text(field(entry, "cost")) .. ":"
                    .. text(field(entry, "costPercent"))
            end
        end
    end)
    if not walked then
        return "error"
    end
    return #out > 0 and table.concat(out, ",") or "none"
end

local function since(t, at)
    return at and ("%.2f"):format(t - at) or "none"
end

local function onCast(id)
    lastCast = now()
    log(("cast id=%s name=%s cost=%s texture=%s"):format(text(id), read(field(_G.C_Spell, "GetSpellName"), id),
        cost(id), read(field(_G.C_Spell, "GetSpellTexture"), id)))
end

local function onPower(event, token)
    local t = now()
    local gap = since(t, lastPower[event])
    lastPower[event] = t
    log(("%s token=%s gap=%s sinceCast=%s"):format(event, text(token), gap, since(t, lastCast)))
end

-- A player cast or power event while the recorder is on; any other unit's, or any other event, is ignored.
function ManaProbe.OnEvent(event, unit, ...)
    if not ns.Debug.IsOn() or not isPlayer(unit) then
        return
    end
    local ok, err = pcall(function(...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            onCast((select(2, ...)))
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            onPower(event, (...))
        end
    end, ...)
    if not ok then
        pcall(log, "probe error " .. text(err))
    end
end

-- Returns whether a CooldownFrameTemplate frame can be made, as "frame", "error" or what CreateFrame returned.
local function cooldown()
    if type(_G.CreateFrame) ~= "function" then
        return "nil-fn"
    end
    local ok, f = pcall(_G.CreateFrame, "Cooldown", nil, _G.UIParent, "CooldownFrameTemplate")
    if not ok then
        return "error"
    end
    if type(f) == "table" and not isSecret(f) then
        return "frame"
    end
    return text(f)
end

-- PLAYER_LOGIN: registers the player's casts and power events on this module's own frame, once, and with the recorder
-- on logs the cooldown frame check and the player's power type.
function ManaProbe.OnLogin()
    if events then
        return
    end
    events = CreateFrame("Frame", "TandemManaProbeEvents")
    for _, event in ipairs(EVENTS) do
        ns.Store.RegisterUnitEvent(events, event, "player")
    end
    events:SetScript("OnEvent", function(_, event, ...)
        ManaProbe.OnEvent(event, ...)
    end)
    if ns.Debug.IsOn() then
        log(("login cooldown=%s powerType=%s"):format(cooldown(), read(_G.UnitPowerType, "player")))
    end
end
