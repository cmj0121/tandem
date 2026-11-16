local _, ns = ...

-- Weapon enchant procs (Shaman): an icon under the player frame, while the Tandem layout is on and the main hand
-- carries Windfury, Flametongue or Frostbrand, shows how often that enchant procs: procs per landed melee hit, saved
-- per character and enchant, reset by a right-click. Forever gives addons no combat log, so the counts come from
-- UNIT_COMBAT on the target (verified in game 2026-11-16: it fires for every swing with its school, the amount kept
-- secret):
-- - a hit is a physical WOUND on the target while auto attack is on, not at the instant of one of the player's own
--   casts (Stormstrike, a shock), which UNIT_SPELLCAST_SUCCEEDED marks;
-- - a Flametongue proc is a fire WOUND, a Frostbrand proc a frost WOUND, neither at a cast's instant; fire within
--   FLAME_SHOCK seconds of a Flame Shock cast is its damage over time and not counted;
-- - a Windfury proc is a physical swing within WINDFURY seconds of the previous one (its extra attack), counted as a
--   proc and not a hit. Not yet seen in game.
-- Any damage on the target counts, so another player hitting it skews the rate: the numbers are exact solo only.
-- Display only, no advice (PLAN decision 6).
local Procs = {}
ns.Procs = Procs

local SIZE = 28
-- UNIT_COMBAT schools.
local PHYSICAL, FIRE, FROST = 1, 4, 16
-- Seconds: a target event this close after one of the player's casts is that cast's; a physical swing this close
-- after the previous one is a Windfury attack; fire this long after a Flame Shock cast is its damage over time.
local CAST, WINDFURY, FLAME_SHOCK = 0.1, 0.3, 12.5
local FLAME_SHOCK_SPELL = 8050
-- The enchant ids of each family's ranks, as GetWeaponEnchantInfo returns them (3 = Flametongue seen in game).
local FAMILY = {}
for family, ids in pairs({
    windfury = { 283, 284, 525, 1669 },
    flametongue = { 5, 4, 3, 523, 1665, 1666 },
    frostbrand = { 2, 12, 524, 1667, 1668 },
}) do
    for _, id in ipairs(ids) do
        FAMILY[id] = family
    end
end
-- Each family's weapon spell, whose name and icon the icon shows, and a fallback icon.
local SPELL = { windfury = 8232, flametongue = 8024, frostbrand = 8033 }
local ICON = {
    windfury = "Interface\\Icons\\Spell_Nature_Cyclone",
    flametongue = "Interface\\Icons\\Spell_Fire_FlameTounge",
    frostbrand = "Interface\\Icons\\Spell_Frost_FrostBrand",
}
-- The physical outcomes that are a swing (a Windfury attack's timing counts from any of them).
local SWING = { WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true, ABSORB = true, IMMUNE = true,
    EVADE = true, DEFLECT = true, RESIST = true }

local button, layoutOn, family, enchantID, attacking
local lastCast, lastSwing, flameShockUntil = -math.huge, -math.huge, -math.huge
local fight = { hits = 0, procs = 0 }

local call, Safe = ns.Store.Call, ns.Store.Safe

local function now()
    return tonumber((call(_G.GetTime))) or 0
end

local function key()
    return ns.Weights.CharacterKey()
end

local function spellName(id)
    local name = type(C_Spell) == "table" and call(C_Spell.GetSpellName, id) or call(_G.GetSpellInfo, id)
    return type(name) == "string" and name or nil
end

local function spellIcon(id)
    local icon = type(C_Spell) == "table" and call(C_Spell.GetSpellTexture, id) or call(_G.GetSpellTexture, id)
    return icon
end

-- Returns the family's saved counts, zero when none.
function Procs.Count(f)
    local k = key()
    return (k and f and ns.Store.Procs(k, f)) or { hits = 0, procs = 0 }
end

-- Returns the rate text for counts: "23%", or "-" before the first hit.
function Procs.Rate(count)
    if count.hits == 0 then
        return "-"
    end
    return ("%d%%"):format(math.floor(100 * count.procs / count.hits + 0.5))
end

local function showTooltip(self)
    local tip, L = GameTooltip, ns.L
    if type(tip) ~= "table" or not family then
        return
    end
    local count = Procs.Count(family)
    tip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    tip:SetText(spellName(SPELL[family]) or family)
    tip:AddLine(L["Procs %d / hits %d (%s)"]:format(count.procs, count.hits, Procs.Rate(count)), 1, 1, 1)
    tip:AddLine(L["Counted from your melee hits on your target; exact when solo"], 0.5, 0.5, 0.5, true)
    tip:AddLine(L["Right-click to start counting again"], 0.5, 0.5, 0.5)
    tip:Show()
end

local place

local function render()
    if not button then
        return
    end
    if not (layoutOn and family and place()) then
        button:Hide()
        return
    end
    button.icon:SetTexture(spellIcon(SPELL[family]) or ICON[family])
    button.rate:SetText(Procs.Rate(Procs.Count(family)))
    button:Show()
end

-- Right-click: forgets the shown family's counts.
local function onClick(_, mouse)
    if mouse ~= "RightButton" or not family then
        return
    end
    local k = key()
    if k then
        ns.Store.SetProcs(k, family, nil)
    end
    ns.Debug.Log("procs: reset " .. family)
    render()
    if GameTooltip and GameTooltip.GetOwner and call(GameTooltip.GetOwner, GameTooltip) == button then
        showTooltip(button)
    end
end

local function create()
    if button or type(CreateFrame) ~= "function" then
        return
    end
    button = CreateFrame("Button", nil, UIParent)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("RightButtonUp")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button.rate = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.rate:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", ns.View.HideTooltip)
    button:Hide()
end

-- Places the icon centred under the player frame; false without one.
function place()
    local player = _G.PlayerFrame
    if not button or type(player) ~= "table" then
        return false
    end
    button:ClearAllPoints()
    button:SetPoint("TOP", player, "BOTTOM", 0, -2)
    return true
end

-- Reads the main hand's enchant into family (nil for none or one without procs); read when auto attack starts and
-- when the weapons change, so never from secret combat data.
local function readEnchant()
    local has, _, _, id = call(_G.GetWeaponEnchantInfo)
    id = has and Safe(id) or nil
    if id ~= enchantID then
        ns.Debug.Log(("procs: main hand enchant %s -> %s"):format(tostring(id), tostring(FAMILY[id])))
    end
    enchantID, family = id, FAMILY[id]
    render()
end

-- Adds to the family's saved counts.
local function add(hits, procs)
    local k = key()
    if not (k and family) then
        return
    end
    local count = Procs.Count(family)
    count.hits, count.procs = count.hits + hits, count.procs + procs
    ns.Store.SetProcs(k, family, count)
    fight.hits, fight.procs = fight.hits + hits, fight.procs + procs
    render()
end

local function onCombat(action, school)
    local t = now()
    if t - lastCast < CAST then
        return
    end
    if school == PHYSICAL and SWING[action] then
        local extra = family == "windfury" and t - lastSwing < WINDFURY
        lastSwing = t
        if extra then
            add(0, 1)
        elseif action == "WOUND" then
            add(1, 0)
        end
    elseif action == "WOUND" and ((family == "flametongue" and school == FIRE and t >= flameShockUntil)
        or (family == "frostbrand" and school == FROST)) then
        add(0, 1)
    end
end

-- UNIT_COMBAT, UNIT_SPELLCAST_SUCCEEDED, PLAYER_ENTER_COMBAT, PLAYER_LEAVE_COMBAT, UNIT_INVENTORY_CHANGED and
-- PLAYER_EQUIPMENT_CHANGED, forwarded by Tandem's frame for a Shaman; counts only while auto attack is on.
function Procs.OnEvent(event, unit, a2, a3, _, a5)
    if not button then
        return
    end
    if event == "PLAYER_ENTER_COMBAT" then
        attacking = true
        fight.hits, fight.procs = 0, 0
        readEnchant()
    elseif event == "PLAYER_LEAVE_COMBAT" then
        attacking = nil
        ns.Debug.Log(("procs: fight %s hits %d procs %d"):format(tostring(family), fight.hits, fight.procs))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Safe(unit) == "player" then
            lastCast = now()
            local name = spellName(Safe(a3))
            if name and name == spellName(FLAME_SHOCK_SPELL) then
                flameShockUntil = lastCast + FLAME_SHOCK
            end
        end
    elseif event == "UNIT_COMBAT" then
        if attacking and family and Safe(unit) == "target" then
            onCombat(Safe(a2), Safe(a5))
        end
    elseif (event == "UNIT_INVENTORY_CHANGED" and Safe(unit) == "player") or event == "PLAYER_EQUIPMENT_CHANGED" then
        readEnchant()
    end
end

-- The events Procs.OnEvent takes.
Procs.EVENTS = { "UNIT_COMBAT", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "UNIT_INVENTORY_CHANGED" }

-- PLAYER_LOGIN: for a Shaman with the feature's client parts, makes the icon and registers Procs.EVENTS on frame
-- (Tandem's); true when it did.
function Procs.OnLogin(frame)
    local _, classFile = call(_G.UnitClass, "player")
    if button or classFile ~= "SHAMAN" or not ns.Check.Ready("Weapon procs") then
        return false
    end
    create()
    if not button then
        return false
    end
    for _, event in ipairs(Procs.EVENTS) do
        ns.Store.RegisterEvent(frame, event)
    end
    readEnchant()
    return true
end

ns.Layout.OnChange(function(isOn)
    layoutOn = isOn
    render()
end)
