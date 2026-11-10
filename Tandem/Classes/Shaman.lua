local _, ns = ...

-- The Shaman class rail (stage 12, D5, D12, D13): a slot per active totem in Earth, Fire, Water, Air order, plus the
-- mana line along the rail bottom. Lightning Shield and Water Shield are not shown, by user request 2026-11-10 (this
-- replaces D10's untimed shield slot). Weapon enchants are left out: the user does not want their timers shown.
-- State and timers only (PLAN decision 6). Each event refreshes its section's cache from the client; the rail's
-- ticker only re-renders the cached expirations.
local Shaman = {}

-- GetTotemInfo slots: FIRE_TOTEM_SLOT = 1, EARTH_TOTEM_SLOT = 2, WATER_TOTEM_SLOT = 3, AIR_TOTEM_SLOT = 4; shown
-- in Earth, Fire, Water, Air order.
local TOTEMS = { 2, 1, 3, 4 }
local MANA = 0
local MANA_COLOR = { 0, 0.44, 0.87 }

local totems, mana = {}, nil

local call = ns.Store.Call

local function number(v)
    return type(v) == "number" and v or nil
end

local function updateTotems()
    totems = {}
    for _, slot in ipairs(TOTEMS) do
        local have, name, start, duration, icon = call(GetTotemInfo, slot)
        if have and type(name) == "string" and name ~= "" then
            start, duration = number(start), number(duration)
            totems[#totems + 1] = { label = name, icon = icon,
                expires = start and duration and duration > 0 and start + duration or nil }
        end
    end
end

local function updateMana()
    local cur, max = number(call(UnitPower, "player", MANA)), number(call(UnitPowerMax, "player", MANA))
    mana = cur and max and max > 0 and { value = cur, max = max, color = MANA_COLOR } or nil
end

local SECTIONS = {
    PLAYER_TOTEM_UPDATE = { updateTotems },
    UNIT_POWER_UPDATE = { updateMana },
    UNIT_MAXPOWER = { updateMana },
}
local ALL = { updateTotems, updateMana }

function Shaman.Ready()
    return ns.Check.Ready("Shaman area")
end

-- Refreshes the sections event touches from the client, every section for nil, and hands the rail its slots: the
-- totems.
function Shaman.Update(event)
    for _, fn in ipairs(event and SECTIONS[event] or ALL) do
        fn()
    end
    ns.ClassArea.Set(totems, mana)
end

ns.ClassArea.Register("SHAMAN", Shaman)
