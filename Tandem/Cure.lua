local _, ns = ...

-- The cures (class feature macros, first for the Shaman): the cure macro bodies, cast on the mouseover friend, else
-- the friendly target, else the player, and the scan of the player's and party's debuffs they remove, which lights
-- the class macro flyout (Flyout.Light). The scan reads out of combat only: Forever keeps aura data secret from
-- addons in combat ("Auras cannot be accessed when secret"), so a fight leaves the hint dark until it ends. The hint
-- is advice only: nothing is cast but on the player's own click.
local Cure = {}
ns.Cure = Cure

local call = ns.Store.Call

-- Per class, its cures: the spell, the debuff type it removes and its macro's name.
Cure.CURES = {
    SHAMAN = {
        { spell = 526, kind = "Poison", macro = "Tandem Poison" },
        { spell = 2870, kind = "Disease", macro = "Tandem Disease" },
    },
}
-- The units whose debuffs light the flyout.
local UNITS = { "player", "party1", "party2", "party3", "party4" }
local WATCHED = {}
for _, unit in ipairs(UNITS) do
    WATCHED[unit] = true
end
local MAX_AURAS = 40
local TARGETS = "[@mouseover,help,nodead][@target,help,nodead][@player]"
local RIGHT_TARGETS = "[btn:2,@mouseover,help,nodead][btn:2,@target,help,nodead][btn:2,@player]"

local lastScan
-- afflicted[kind] = { "<unit name>: <debuff name>", ... } from the last scan.
local afflicted = {}

local function debugOn()
    return ns.Debug ~= nil and ns.Debug.IsOn()
end

local function log(text)
    if debugOn() then
        ns.Debug.Log(text)
    end
end

local function inCombat()
    return call(InCombatLockdown) == true
end

-- Cure.SpellInfo(id) -> name, icon: the spell's localized name and icon, or nils.
function Cure.SpellInfo(id)
    local info = call(C_Spell and C_Spell.GetSpellInfo, id)
    if type(info) == "table" and type(info.name) == "string" then
        return info.name, info.iconID
    end
    local name, _, icon = call(GetSpellInfo, id)
    if type(name) == "string" and name ~= "" then
        return name, icon
    end
end

-- Cure.Known(id) -> bool: whether the player knows the spell.
function Cure.Known(id)
    return call(IsPlayerSpell, id) == true or call(IsSpellKnown, id) == true
end

-- Cure.Afflicted(kind) -> { "<unit name>: <debuff name>", ... }: the last scan's afflicted units for a debuff type.
function Cure.Afflicted(kind)
    return afflicted[kind] or {}
end

-- Cure.Body(name) -> text: the cast line a button and its macro run for the localized cure name.
function Cure.Body(name)
    return "/cast " .. TARGETS .. " " .. name
end

-- Cure.MacroBody(name) -> text: the cure macro's body.
function Cure.MacroBody(name)
    return "#showtooltip\n" .. Cure.Body(name)
end

-- Cure.CombinedBody(left, right) -> text: the combined macro's body for the localized cure names, casting left on a
-- left click and right on a right click, each on the mouseover friend, else the friendly target, else the player.
function Cure.CombinedBody(left, right)
    return "#showtooltip\n/cast " .. RIGHT_TARGETS .. " " .. right .. "; " .. TARGETS .. " " .. left
end

-- Calls fn(debuffName, kind) for each debuff on unit until the client gives no more.
local function eachDebuff(unit, fn)
    local byIndex = type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataByIndex
    for i = 1, MAX_AURAS do
        local name, kind
        if type(byIndex) == "function" then
            local aura = byIndex(unit, i, "HARMFUL")
            if type(aura) ~= "table" then
                return
            end
            name, kind = aura.name, aura.dispelName
        else
            local _
            name, _, _, kind = UnitDebuff(unit, i)
            if name == nil then
                return
            end
        end
        fn(name, kind)
    end
end

-- Reads every watched unit's debuffs into afflicted; false when the client raised (aura data it keeps from addons).
local function readDebuffs()
    local found = {}
    for _, unit in ipairs(UNITS) do
        if unit == "player" or call(UnitExists, unit) == true then
            local who = call(UnitName, unit)
            who = type(who) == "string" and who or unit
            eachDebuff(unit, function(name, kind)
                if type(kind) == "string" then
                    found[kind] = found[kind] or {}
                    local list = found[kind]
                    list[#list + 1] = who .. ": " .. tostring(name)
                end
            end)
        end
    end
    afflicted = found
end

-- UNIT_AURA (watched units only), GROUP_ROSTER_UPDATE: reads the debuffs again and lights the flyout; in combat it
-- reads nothing and darkens them (the aura data is secret there). While debugging, logs the scan when it differs from
-- the last one logged.
function Cure.Scan(unit)
    if not ns.Flyout.Made() or (unit ~= nil and not WATCHED[unit]) then
        return
    end
    local ok, err = true, nil
    local fighting = inCombat()
    if fighting then
        afflicted = {}
    else
        ok, err = pcall(readDebuffs)
        if not ok then
            afflicted = {}
        end
    end
    ns.Flyout.Light()
    if debugOn() then
        local parts = {}
        local _, classFile = call(UnitClass, "player")
        for _, c in ipairs(Cure.CURES[classFile] or {}) do
            local list = afflicted[c.kind]
            parts[#parts + 1] = c.kind .. "=" .. (list and table.concat(list, ",") or "0")
        end
        local line = fighting and "cure scan: skipped in combat"
            or ok and ("cure scan: " .. table.concat(parts, " ")) or ("cure scan failed: " .. tostring(err))
        if line ~= lastScan then
            lastScan = line
            log(line)
        end
    end
end

-- Cure.NextX() -> x: the BOTTOMRIGHT x offset for the right edge of a button left of the shown flyout button, or
-- Rod.NextX() while it is hidden; the y offset is the rod button's.
function Cure.NextX()
    return ns.Flyout.NextX()
end
