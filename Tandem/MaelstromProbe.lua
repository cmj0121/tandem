local _, ns = ...

-- The Maelstrom Weapon probe: before Tandem shows the Shaman's Maelstrom Weapon stacks, it must learn what Forever
-- tells addons about them. For a Shaman, while the debug recorder is on, this reads Lightning Bolt's and Chain
-- Lightning's cast time and whether Lightning Bolt is overlayed, on the overlay, aura, cast and combat events and
-- every TICK seconds while in combat or while a Maelstrom buff was last seen; it logs each overlay event firing with
-- its arguments, each player UNIT_AURA's argument shapes (every one up to AURA_ALL, then one in AURA_EVERY), the
-- player's cast spell ids, and out of combat only (the aura API raises in combat) any buff named like Maelstrom with
-- its spell id and stacks. Rune API and candidate spell presence is logged at login. A reading logs as
-- "maelstrom probe: <name>=<value> combat=<bool>" only when its value or the combat state changed, up to LIMIT lines
-- a session; a value the client keeps secret logs "secret", a raising read "error", a missing function "nil-fn". The
-- events go on Tandem's own frame, which forwards them through MaelstromProbe.OnEvent. Reads only, and logs nothing
-- while the recorder is off.
local MaelstromProbe = {}
ns.MaelstromProbe = MaelstromProbe

local LIMIT = 250
local TICK = 0.2
local AURA_ALL = 50
local AURA_EVERY = 25
local MAX_AURAS = 40
-- Lightning Bolt and Chain Lightning, whose cast time Maelstrom Weapon shortens.
local SPELLS = { 403, 421 }
local BOLT = 403
-- Candidate Season of Discovery Maelstrom Weapon spell ids.
local CANDIDATES = { 408498, 408505 }
local NAMES = { "Maelstrom", "氣漩" }
local OVERLAY = {
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true, SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true,
    SPELL_ACTIVATION_OVERLAY_SHOW = true, SPELL_ACTIVATION_OVERLAY_HIDE = true,
}
local EVENTS = { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "SPELL_ACTIVATION_OVERLAY_SHOW", "SPELL_ACTIVATION_OVERLAY_HIDE", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local registered = {}
local last = {}
local lines = 0
local auraCount = 0
-- The Maelstrom buffs the last scan found, by spell id; seen is whether there was any.
local buffs = {}
local seen = false
local ticker

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

local function combat()
    return tostring(call(_G.InCombatLockdown) == true)
end

local function emit(name, value, state)
    lines = lines + 1
    ns.Debug.Log(("maelstrom probe: %s=%s combat=%s"):format(name, value, state))
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
    emit(name, value, state)
end

-- Logs a firing as name=value with the combat state, whatever was logged before.
local function log(name, value)
    if lines < LIMIT and ns.Debug.IsOn() then
        emit(name, value, combat())
    end
end

local function isPlayer(unit)
    return not isSecret(unit) and unit == "player"
end

-- Returns the cast time C_Spell.GetSpellInfo gives spell id as text.
local function castTime(id)
    local fn = field(_G.C_Spell, "GetSpellInfo")
    if type(fn) ~= "function" then
        return "nil-fn"
    end
    local ok, info = pcall(fn, id)
    if not ok then
        return "error"
    end
    if isSecret(info) then
        return "secret"
    end
    return text(field(info, "castTime"))
end

-- Reads each spell's cast time and whether Lightning Bolt is overlayed.
local function readSpells()
    for _, id in ipairs(SPELLS) do
        report("castTime:" .. id, castTime(id))
        if type(_G.GetSpellInfo) == "function" then
            local ok, v = pcall(function()
                return (select(4, _G.GetSpellInfo(id)))
            end)
            report("GetSpellInfo.castTime:" .. id, ok and text(v) or "error")
        end
    end
    report("C_SpellActivationOverlay.IsSpellOverlayed:" .. BOLT,
        read(field(_G.C_SpellActivationOverlay, "IsSpellOverlayed"), BOLT))
    if type(_G.IsSpellOverlayed) == "function" then
        report("IsSpellOverlayed:" .. BOLT, read(_G.IsSpellOverlayed, BOLT))
    end
end

-- Returns v's type as text; a table's own field names follow in braces, sorted.
local function shape(v)
    if isSecret(v) then
        return "secret"
    end
    if type(v) ~= "table" then
        return type(v)
    end
    local keys = {}
    local ok = pcall(function()
        for k in pairs(v) do
            keys[#keys + 1] = text(k)
        end
    end)
    if not ok then
        return "table{error}"
    end
    table.sort(keys)
    return "table{" .. table.concat(keys, ",") .. "}"
end

local function logAura(...)
    auraCount = auraCount + 1
    if auraCount > AURA_ALL and (auraCount - AURA_ALL) % AURA_EVERY ~= 0 then
        return
    end
    local out = {}
    for i = 1, select("#", ...) do
        out[i] = shape((select(i, ...)))
    end
    log("UNIT_AURA#" .. auraCount, table.concat(out, " "))
end

local function maelstrom(name)
    if type(name) ~= "string" or isSecret(name) then
        return false
    end
    for _, part in ipairs(NAMES) do
        if name:find(part, 1, true) then
            return true
        end
    end
    return false
end

-- Returns the player's helpful aura i as name, stacks and spell id, or nil past the last one.
local function buff(i)
    local byIndex = field(_G.C_UnitAuras, "GetAuraDataByIndex")
    if type(byIndex) == "function" then
        local aura = call(byIndex, "player", i, "HELPFUL")
        if type(aura) ~= "table" then
            return nil
        end
        return field(aura, "name"), field(aura, "applications"), field(aura, "spellId")
    end
    local name, _, count, _, _, _, _, _, _, spellId = call(_G.UnitBuff, "player", i)
    return name, count, spellId
end

-- Out of combat only: logs each Maelstrom buff the player has as spell id, name and stacks, and each one last seen
-- that is gone.
local function scanBuffs()
    if call(_G.InCombatLockdown) ~= false then
        return
    end
    local found = {}
    for i = 1, MAX_AURAS do
        local name, stacks, spellId = buff(i)
        if name == nil then
            break
        end
        if maelstrom(name) then
            local id = text(spellId)
            found[id] = true
            report("buff:" .. id, name .. " x" .. text(stacks))
        end
    end
    for id in pairs(buffs) do
        if not found[id] then
            report("buff:" .. id, "gone")
        end
    end
    buffs = found
    seen = next(found) ~= nil
end

-- Logs the rune API's presence and whether the player knows each candidate spell.
local function readPresence()
    local engraving = _G.C_Engraving
    report("C_Engraving", tostring(type(engraving) == "table"))
    report("C_Engraving.IsRuneEquipped", tostring(type(field(engraving, "IsRuneEquipped")) == "function"))
    report("C_Engraving.GetRuneForEquipmentSlot",
        tostring(type(field(engraving, "GetRuneForEquipmentSlot")) == "function"))
    for _, id in ipairs(CANDIDATES) do
        report("IsPlayerSpell:" .. id, read(_G.IsPlayerSpell, id))
    end
end

local function safely(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        pcall(report, "probe", "error " .. text(err))
    end
end

local function tick()
    if ns.Debug.IsOn() and (call(_G.InCombatLockdown) == true or seen) then
        safely(readSpells)
    end
end

-- Logs a probed event Tandem's frame received while the recorder is on and reads the spells again; any other event,
-- and a unit event for another unit, is ignored.
function MaelstromProbe.OnEvent(event, ...)
    if not registered[event] or not ns.Debug.IsOn() then
        return
    end
    if OVERLAY[event] then
        safely(log, event, results(true, ...))
    elseif event == "UNIT_AURA" then
        if not isPlayer((...)) then
            return
        end
        safely(logAura, ...)
        safely(scanBuffs)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not isPlayer((...)) then
            return
        end
        report("UNIT_SPELLCAST_SUCCEEDED", text((select(3, ...))))
    elseif event == "PLAYER_REGEN_ENABLED" then
        safely(scanBuffs)
    end
    safely(readSpells)
end

-- PLAYER_LOGIN: for a Shaman, registers the probed events on frame (Tandem's), UNIT_AURA (player) only while the
-- recorder is on so Tandem's aura handlers stay idle otherwise, logs which the client accepts and the rune API and
-- candidate spells, and starts the ticker; other classes get nothing.
function MaelstromProbe.OnLogin(frame)
    local _, classFile = call(_G.UnitClass, "player")
    if next(registered) or classFile ~= "SHAMAN" then
        return
    end
    for _, event in ipairs(EVENTS) do
        if event ~= "UNIT_AURA" then
            local ok = ns.Store.RegisterEvent(frame, event)
            registered[event] = ok or nil
            report("registered:" .. event, tostring(ok))
        elseif ns.Debug.IsOn() then
            local ok = ns.Store.RegisterUnitEvent(frame, event, "player")
            registered[event] = ok or nil
            report("registered:" .. event, tostring(ok))
        end
    end
    safely(readPresence)
    local timer = _G.C_Timer
    if not ticker and type(field(timer, "NewTicker")) == "function" then
        ticker = call(timer.NewTicker, TICK, tick)
    end
end
