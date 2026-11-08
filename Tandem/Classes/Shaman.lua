local _, ns = ...

-- The Shaman class rail (stage 12, D5, D12, D13): a slot per active totem in Earth, Fire, Water, Air order, for an
-- active off-hand weapon enchant (the main hand's is left out: the user does not want it shown) and for Lightning
-- Shield or Water Shield with its charges, plus the mana line along the rail bottom.
-- State and timers only (PLAN decision 6). Each event refreshes its section's cache from the client; the rail's
-- ticker only re-renders the cached expirations.
local Shaman = {}

-- GetTotemInfo slots: FIRE_TOTEM_SLOT = 1, EARTH_TOTEM_SLOT = 2, WATER_TOTEM_SLOT = 3, AIR_TOTEM_SLOT = 4; shown
-- in Earth, Fire, Water, Air order.
local TOTEMS = { 2, 1, 3, 4 }
-- Lightning Shield (rank 1) and Water Shield; a client without Water Shield names only Lightning Shield.
local SHIELDS = { 324, 24398 }
local OFF_HAND = 17
local MANA = 0
local MANA_COLOR = { 0, 0.44, 0.87 }

local totems, weapons, shield, mana = {}, {}, nil, nil
local shieldNames = {}

local function safeAll(...)
    if select("#", ...) == 0 then
        return
    end
    return ns.Store.Safe((...)), safeAll(select(2, ...))
end

local function safe(ok, ...)
    if ok then
        return safeAll(...)
    end
end

local function call(fn, ...)
    if type(fn) ~= "function" then
        return
    end
    return safe(pcall(fn, ...))
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function number(v)
    return type(v) == "number" and v or nil
end

local function now()
    return number(call(GetTime)) or 0
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

-- GetWeaponEnchantInfo returns (hasMain, mainMs, mainCharges, mainID, hasOff, offMs, ...) on current clients and
-- (hasMain, mainMs, mainCharges, hasOff, offMs, offCharges) on 1.12-style ones; expirations are ms left.
local function updateWeapons()
    local v = pack(call(GetWeaponEnchantInfo))
    local off, t = v.n <= 6 and 4 or 5, now()
    weapons = {}
    for _, hand in ipairs({ { "Off hand", OFF_HAND, v[off], v[off + 1] } }) do
        local ms = number(hand[4])
        if hand[3] and ms then
            weapons[#weapons + 1] = { label = ns.L[hand[1]], icon = call(GetInventoryItemTexture, "player", hand[2]),
                expires = t + ms / 1000 }
        end
    end
end

local function shieldName(id)
    if not shieldNames[id] then
        local spell = type(C_Spell) == "table" and C_Spell.GetSpellName
        local name = call(spell, id) or call(GetSpellInfo, id)
        shieldNames[id] = type(name) == "string" and name ~= "" and name or nil
    end
    return shieldNames[id]
end

-- Returns charges, expiration time and icon of the player's buff named name, or nil when it is not up.
local function buff(name)
    local byName = type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataBySpellName
    if type(byName) == "function" then
        local data = call(byName, "player", name, "HELPFUL")
        if type(data) == "table" then
            return number(ns.Store.Safe(data.applications)) or 0, number(ns.Store.Safe(data.expirationTime)),
                ns.Store.Safe(data.icon)
        end
        return nil
    end
    for i = 1, 40 do
        local found, icon, count, _, _, expiration = call(UnitBuff, "player", i)
        if not found then
            return nil
        end
        if found == name then
            return number(count) or 0, number(expiration), icon
        end
    end
end

local function updateShield()
    shield = nil
    for _, id in ipairs(SHIELDS) do
        local name = shieldName(id)
        local charges, expiration, icon
        if name then
            charges, expiration, icon = buff(name)
        end
        if charges then
            shield = { label = name, icon = icon, count = charges,
                expires = expiration and expiration > 0 and expiration or nil }
            return
        end
    end
end

local function updateMana()
    local cur, max = number(call(UnitPower, "player", MANA)), number(call(UnitPowerMax, "player", MANA))
    mana = cur and max and max > 0 and { value = cur, max = max, color = MANA_COLOR } or nil
end

local SECTIONS = {
    PLAYER_TOTEM_UPDATE = { updateTotems },
    UNIT_INVENTORY_CHANGED = { updateWeapons },
    UNIT_AURA = { updateShield },
    UNIT_POWER_UPDATE = { updateMana },
    UNIT_MAXPOWER = { updateMana },
}
local ALL = { updateTotems, updateWeapons, updateShield, updateMana }

function Shaman.Ready()
    return ns.Check.Ready("Shaman area")
end

-- Refreshes the sections event touches from the client, every section for nil, and hands the rail its slots:
-- totems, then weapon enchants, then the shield.
function Shaman.Update(event)
    for _, fn in ipairs(event and SECTIONS[event] or ALL) do
        fn()
    end
    local list = {}
    for _, group in ipairs({ totems, weapons, { shield } }) do
        for _, e in ipairs(group) do
            list[#list + 1] = e
        end
    end
    ns.ClassArea.Set(list, mana)
end

ns.ClassArea.Register("SHAMAN", Shaman)
