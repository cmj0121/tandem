local _, ns = ...

-- The melee range probe: before Tandem shows whether a hostile target is in melee range, it must learn which range
-- APIs Forever answers, in and out of combat, and what the nameplates' settings and the target's plate look like.
-- While the debug recorder is on, this reads each candidate on a hostile target (spell, action, interact distance and
-- unit range) on target change, combat start and end, auto attack start and every TICK seconds, and logs a reading
-- as "range probe: <name>=<value> combat=<bool>" only when its value or the combat state changed, up to LIMIT lines a
-- session. The nameplate CVars are logged at login, the target's nameplate on target change. A value the client keeps
-- secret logs "secret", a raising read "error", a missing function "nil-fn". The events go on Tandem's own frame,
-- which forwards them through RangeProbe.OnEvent. Reads only, and logs nothing while the recorder is off.
local RangeProbe = {}
ns.RangeProbe = RangeProbe

local LIMIT = 200
local TICK = 0.5
local ACTION_SLOTS = 180
local ATTACK = 6603
local STORMSTRIKE = 17364
-- The spells whose range is read: Attack and Stormstrike (melee), Earth Shock (a 20 yd reference).
local SPELLS = { { ATTACK, "Attack" }, { STORMSTRIKE, "Stormstrike" }, { 8042, "Earth Shock" } }
local CVARS = { "nameplateOtherAtBase", "nameplateShowEnemies", "nameplateMinScale", "nameplateMaxScale",
    "nameplateGlobalScale", "nameplateOverlapV" }
local PLATE = { "GetScale", "GetEffectiveScale", "GetWidth", "GetHeight", "GetCenter" }
local EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTER_COMBAT" }

local registered = {}
local last = {}
local lines = 0
local ticker
local attackSlot

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

-- Returns fn(...)'s first return as true or false, or nil when it is secret, raises or fn is missing.
local function flag(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then
        return nil
    end
    return v and true or false
end

local function combat()
    return tostring(call(_G.InCombatLockdown) == true)
end

-- Logs name's reading value with the combat state unless both match the last line logged for name.
local function report(name, value)
    if lines >= LIMIT or not ns.Debug.IsOn() then
        return
    end
    local state = combat()
    local key = value .. " " .. state
    if last[name] == key then
        return
    end
    last[name] = key
    lines = lines + 1
    ns.Debug.Log(("range probe: %s=%s combat=%s"):format(name, value, state))
end

-- Returns the action slot holding auto attack, or nil; the last slot found is checked first.
local function findAttackSlot()
    local function holds(slot)
        local kind, id = call(_G.GetActionInfo, slot)
        return kind == "spell" and id == ATTACK
    end
    if attackSlot and holds(attackSlot) then
        return attackSlot
    end
    attackSlot = nil
    for slot = 1, ACTION_SLOTS do
        if holds(slot) then
            attackSlot = slot
            break
        end
    end
    return attackSlot
end

local function known(id)
    return call(_G.IsPlayerSpell, id) == true or call(_G.IsSpellKnown, id) == true
end

local function spellName(id, fallback)
    local name = call(field(_G.C_Spell, "GetSpellName"), id) or call(_G.GetSpellInfo, id)
    return type(name) == "string" and name or fallback
end

-- Reads each range candidate on the target, when one exists that is not plainly friendly or absent.
local function readRanges()
    if flag(_G.UnitExists, "target") == false or flag(_G.UnitCanAttack, "player", "target") == false then
        return
    end
    for _, spell in ipairs(SPELLS) do
        local id, english = spell[1], spell[2]
        if id ~= STORMSTRIKE or known(id) then
            report("C_Spell.IsSpellInRange:" .. id, read(field(_G.C_Spell, "IsSpellInRange"), id, "target"))
            local name = spellName(id, english)
            report("IsSpellInRange:" .. name, read(_G.IsSpellInRange, name, "target"))
        end
    end
    local slot = findAttackSlot()
    report("attack.slot", slot and tostring(slot) or "noslot")
    if slot then
        report("IsActionInRange", read(_G.IsActionInRange, slot))
    end
    for i = 1, 4 do
        report("CheckInteractDistance:" .. i, read(_G.CheckInteractDistance, "target", i))
    end
    report("UnitInRange", read(_G.UnitInRange, "target"))
end

-- Reads the target's nameplate: whether one is found, and its scale, size and center.
local function readPlate()
    local fn = field(_G.C_NamePlate, "GetNamePlateForUnit")
    if type(fn) ~= "function" then
        report("plate.found", "nil-fn")
        return
    end
    local ok, plate = pcall(fn, "target")
    if not ok or isSecret(plate) then
        report("plate.found", ok and "secret" or "error")
        return
    end
    report("plate.found", tostring(plate ~= nil))
    if plate == nil then
        return
    end
    for _, method in ipairs(PLATE) do
        report("plate." .. method, read(field(plate, method), plate))
    end
end

local function readCVars()
    local cvar = _G.C_CVar
    for _, name in ipairs(CVARS) do
        report("GetCVarInfo:" .. name, read(field(cvar, "GetCVarInfo"), name))
        report("GetCVar:" .. name, read(field(cvar, "GetCVar") or _G.GetCVar, name))
    end
end

local function safely(fn)
    local ok, err = pcall(fn)
    if not ok then
        pcall(report, "probe", "error " .. text(err))
    end
end

local function tick()
    if ns.Debug.IsOn() then
        safely(readRanges)
    end
end

-- Reads the ranges, and on target change the target's nameplate, for a probed event Tandem's frame received while
-- the recorder is on; any other event is ignored.
function RangeProbe.OnEvent(event)
    if not registered[event] or not ns.Debug.IsOn() then
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        safely(readPlate)
    end
    safely(readRanges)
end

-- PLAYER_LOGIN: registers the probed events on frame (Tandem's), logs which the client accepts and the nameplate
-- CVars, and starts the range ticker.
function RangeProbe.OnLogin(frame)
    if next(registered) then
        return
    end
    for _, event in ipairs(EVENTS) do
        local ok = ns.Store.RegisterEvent(frame, event)
        registered[event] = ok or nil
        report("registered:" .. event, tostring(ok))
    end
    safely(readCVars)
    local timer = _G.C_Timer
    if not ticker and type(field(timer, "NewTicker")) == "function" then
        ticker = call(timer.NewTicker, TICK, tick)
    end
end
