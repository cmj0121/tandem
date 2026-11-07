local _, ns = ...

-- The Shaman class area (stage 12, D5): the four totems with their time left, the weapon enchants' time left, the
-- Lightning Shield or Water Shield charges and time, and a mana bar. State and timers only (PLAN decision 6).
local Shaman = {}

local ROW, ICON, MANA_HEIGHT = 14, 12, 12
local NONE = "—"
-- GetTotemInfo slots: FIRE_TOTEM_SLOT = 1, EARTH_TOTEM_SLOT = 2, WATER_TOTEM_SLOT = 3, AIR_TOTEM_SLOT = 4; shown
-- in Earth, Fire, Water, Air order.
local TOTEMS = { { slot = 2, label = "Earth" }, { slot = 1, label = "Fire" }, { slot = 3, label = "Water" },
    { slot = 4, label = "Air" } }
-- Lightning Shield (rank 1) and Water Shield; a client without Water Shield names only Lightning Shield.
local SHIELDS = { 324, 24398 }
local MANA = 0

local area
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

local function row(parent, column, index)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW)
    local y = -(index - 1) * ROW
    if column == 1 then
        r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        r:SetPoint("TOPRIGHT", parent, "TOP", -4, y)
    else
        r:SetPoint("TOPLEFT", parent, "TOP", 4, y)
        r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    end
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetJustifyH("LEFT")
    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.time:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.time:SetJustifyH("RIGHT")
    return r
end

local function show(r, name, time, icon)
    r.name:SetText(name)
    r.time:SetText(time)
    if icon then
        r.icon:SetTexture(icon)
        r.icon:Show()
    else
        r.icon:Hide()
    end
end

-- Paints a row from its cached entry { name, icon, expires (GetTime based), charges }: the label and a dash when
-- there is none or it has run out.
local function paint(r)
    local e, t = r.entry, now()
    if not e or (e.expires and e.expires <= t) then
        show(r, ns.L[r.label], NONE)
        return
    end
    local left = e.expires and ns.ClassArea.Clock(e.expires - t) or NONE
    if e.charges then
        left = ns.L["%d charges, %s"]:format(e.charges, left)
    end
    show(r, e.name or ns.L[r.label], left, e.icon)
end

local function paintAll()
    for _, r in ipairs(area.totems) do
        paint(r)
    end
    paint(area.mainHand)
    paint(area.offHand)
    paint(area.shield)
end

local function updateTotems()
    for i, totem in ipairs(TOTEMS) do
        local have, name, start, duration, icon = call(GetTotemInfo, totem.slot)
        local r = area.totems[i]
        r.entry = nil
        if have and type(name) == "string" and name ~= "" then
            start, duration = number(start), number(duration)
            r.entry = { name = name, icon = icon, expires = start and duration and duration > 0 and start + duration
                or nil }
        end
        paint(r)
    end
end

-- GetWeaponEnchantInfo returns (hasMain, mainMs, mainCharges, mainID, hasOff, offMs, ...) on current clients and
-- (hasMain, mainMs, mainCharges, hasOff, offMs, offCharges) on 1.12-style ones; expirations are ms left.
local function updateWeapons()
    local v = pack(call(GetWeaponEnchantInfo))
    local off, t = v.n <= 6 and 4 or 5, now()
    for _, hand in ipairs({ { area.mainHand, v[1], v[2] }, { area.offHand, v[off], v[off + 1] } }) do
        local ms = number(hand[3])
        hand[1].entry = hand[2] and ms and { expires = t + ms / 1000 } or nil
        paint(hand[1])
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
    area.shield.entry = nil
    for _, id in ipairs(SHIELDS) do
        local name = shieldName(id)
        local charges, expiration, icon
        if name then
            charges, expiration, icon = buff(name)
        end
        if charges then
            area.shield.entry = { name = name, icon = icon, charges = charges,
                expires = expiration and expiration > 0 and expiration or nil }
            break
        end
    end
    paint(area.shield)
end

local function updateMana()
    local mana, max = number(call(UnitPower, "player", MANA)), number(call(UnitPowerMax, "player", MANA))
    if not mana or not max or max <= 0 then
        area.mana:Hide()
        return
    end
    area.mana:SetMinMaxValues(0, max)
    area.mana:SetValue(mana)
    area.mana.text:SetText(("%d / %d"):format(mana, max))
    area.mana:Show()
end

local SECTIONS = {
    PLAYER_TOTEM_UPDATE = { updateTotems },
    UNIT_INVENTORY_CHANGED = { updateWeapons },
    UNIT_AURA = { updateShield },
    UNIT_POWER_UPDATE = { updateMana },
    UNIT_MAXPOWER = { updateMana },
    tick = { paintAll },
}
local ALL = { updateTotems, updateWeapons, updateShield, updateMana }

function Shaman.Ready()
    return ns.Check.Ready("Shaman area")
end

function Shaman.Build(parent)
    area = parent
    area.totems = {}
    for i, totem in ipairs(TOTEMS) do
        area.totems[i] = row(area, 1, i)
        area.totems[i].label = totem.label
    end
    area.mainHand, area.offHand, area.shield = row(area, 2, 1), row(area, 2, 2), row(area, 2, 3)
    area.mainHand.label, area.offHand.label, area.shield.label = "Main hand", "Off hand", "Shield"
    area.mana = CreateFrame("StatusBar", nil, area)
    area.mana:SetHeight(MANA_HEIGHT)
    area.mana:SetPoint("BOTTOMLEFT", area, "BOTTOM", 4, 0)
    area.mana:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    area.mana:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    area.mana:SetStatusBarColor(0, 0, 1)
    local bg = area.mana:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(area.mana)
    bg:SetColorTexture(0, 0, 0, 0.5)
    area.mana.text = area.mana:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    area.mana.text:SetPoint("CENTER", area.mana, "CENTER", 0, 0)
end

-- Refreshes the sections event touches from the client, every section for nil; "tick" only repaints the cached
-- countdowns and calls no state API.
function Shaman.Update(event)
    if not area then
        return
    end
    for _, fn in ipairs(event and SECTIONS[event] or ALL) do
        fn()
    end
end

ns.ClassArea.Register("SHAMAN", Shaman)
