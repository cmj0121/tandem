local _, ns = ...

-- The weapon enchant proc probe: Forever gives addons no combat log, so before Tandem counts weapon enchant procs
-- (Windfury, Flametongue, ...) it must learn which other events reach addons there. For a Shaman, while the debug
-- recorder is on, this logs each candidate event once registered ("proc probe: <event> registered=<bool>") and every
-- firing with its arguments, up to LIMIT lines a session so the recorder keeps room for the rest; the weapon enchant
-- state is logged when auto attack starts, and after each fight the client's built-in damage meter (C_DamageMeter), to
-- learn whether its per-spell data holds hit counts. The events go on Tandem's own frame, which forwards them through
-- ProcProbe.OnEvent. Reads only, and logs nothing while the recorder is off.
local ProcProbe = {}
ns.ProcProbe = ProcProbe

local LIMIT = 200
-- The candidates: damage taken by a unit (the swing count), the player's spell casts (a proc's own spell), the
-- classic combat chat lines, and auto attack starting and stopping.
local EVENTS = {
    "UNIT_COMBAT", "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES",
    "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_SELF_BUFF", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "PLAYER_REGEN_ENABLED",
}
-- UNIT_* events are logged for these units only.
local UNITS = { player = true, target = true }

local registered = {}
local lines = 0

local call = ns.Store.Call

-- Returns v as text: "secret" for a value the client keeps secret, else tostring, or "?" when that raises.
local function text(v)
    if ns.Store.Safe(v) == nil and v ~= nil then
        return "secret"
    end
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

local function log(what)
    if lines >= LIMIT or not ns.Debug.IsOn() then
        return
    end
    lines = lines + 1
    ns.Debug.Log("proc probe: " .. what)
end

-- Returns the arguments as text, joined by sep.
local function joined(sep, ...)
    local out = {}
    for i = 1, select("#", ...) do
        out[i] = text((select(i, ...)))
    end
    return table.concat(out, sep)
end

-- Logs the weapon enchant state as GetWeaponEnchantInfo returns it.
local function logEnchants()
    log("enchants " .. joined(" ", call(_G.GetWeaponEnchantInfo)))
end

-- Returns table t's fields as "key=value" text in key order, nested tables shown as "{n}" with their size.
local function fields(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    local out = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        out[#out + 1] = tostring(k) .. "=" .. (type(v) == "table" and ("{" .. #v .. "}") or text(v))
    end
    return table.concat(out, " ")
end

-- After combat: logs the client's built-in damage meter, once its data is no longer secret: C_DamageMeter's
-- functions, then the player's damage done this session and each of its spells' fields (the first 10).
local function logMeter()
    local meter = _G.C_DamageMeter
    if type(meter) ~= "table" then
        log("meter: no C_DamageMeter")
        return
    end
    local names = {}
    for name in pairs(meter) do
        names[#names + 1] = tostring(name)
    end
    table.sort(names)
    log("meter: functions " .. table.concat(names, " "))
    local enum = type(Enum) == "table" and Enum or {}
    local session = type(enum.DamageMeterSessionType) == "table" and enum.DamageMeterSessionType or {}
    local kind = type(enum.DamageMeterType) == "table" and enum.DamageMeterType or {}
    log("meter: session types " .. fields(session) .. " | meter types " .. fields(kind))
    local ok, source = pcall(meter.GetCombatSessionSourceFromType, session.Current, kind.DamageDone,
        call(_G.UnitGUID, "player"))
    if not ok or type(source) ~= "table" then
        log("meter: player source " .. text(ok) .. " " .. text(source))
        return
    end
    log("meter: player source " .. fields(source))
    local spells = type(source.combatSpells) == "table" and source.combatSpells or {}
    for i = 1, math.min(#spells, 10) do
        local spell = spells[i]
        local name = type(spell) == "table" and type(C_Spell) == "table" and call(C_Spell.GetSpellName, spell.spellID)
        log(("meter: spell %d %s %s"):format(i, text(name), type(spell) == "table" and fields(spell) or text(spell)))
    end
end

-- Logs a candidate event Tandem's frame received; any other event is ignored.
function ProcProbe.OnEvent(event, ...)
    if not registered[event] or not ns.Debug.IsOn() then
        return
    end
    local first = ...
    if event:find("^UNIT_") and not UNITS[ns.Store.Safe(first)] then
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        local ok, err = pcall(logMeter)
        if not ok then
            log("meter: error " .. text(err))
        end
        return
    end
    log(event .. " " .. joined(" | ", ...))
    if event == "PLAYER_ENTER_COMBAT" then
        logEnchants()
    end
end

-- PLAYER_LOGIN: for a Shaman, registers the candidate events on frame (Tandem's) and logs which the client accepts;
-- other classes get nothing.
function ProcProbe.OnLogin(frame)
    local _, classFile = call(_G.UnitClass, "player")
    if next(registered) or classFile ~= "SHAMAN" then
        return
    end
    for _, event in ipairs(EVENTS) do
        local ok = ns.Store.RegisterEvent(frame, event)
        registered[event] = ok or nil
        log(("%s registered=%s"):format(event, tostring(ok)))
    end
end
