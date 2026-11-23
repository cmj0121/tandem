local _, ns = ...

-- The five-second rule (PLAN D1-D5): after the player casts a spell that costs mana, mana regeneration from spirit
-- pauses for five seconds. A 28 px icon right of the weapon enchant proc icon, under the player frame, shows the cast
-- spell's icon with a five-second cooldown swipe and the whole seconds left, and hides when the window ends; a recast
-- restarts it. Forever keeps UnitPower secret, so the signal is the player's UNIT_SPELLCAST_SUCCEEDED plus the spell's
-- C_Spell.GetSpellPowerCost: a plain read with a mana entry over 0 shows the icon, a plain read without one is free.
-- Every plain read is remembered per spell id; a secret, raising or missing read falls back to that memory, and a
-- spell never read plainly shows nothing. The memory is filled out of combat from the action bars' spells at login,
-- when spells or a bar slot change, and when combat ends. Mana users only (UnitPowerType 0 at the cast). Clearcasting
-- and other free casts are not told apart. The events go on this module's own frame.
local FiveSecond = {}
ns.FiveSecond = FiveSecond

local WINDOW = 5
local SIZE = 28
-- Under the player frame like the proc icon (Procs' BELOW), one icon and a 4 px gap to its right.
local X, BELOW = 32, 40
local TICK = 0.1
local SLOTS = 180
local MANA = 0
local FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local EVENTS = { "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "PLAYER_REGEN_ENABLED" }

local call, Safe = ns.Store.Call, ns.Store.Safe
-- Per spell id: whether it costs mana, and its texture, from the last plain reads.
local costs, textures = {}, {}
local events, icon, ticker, start

local function api(t, key)
    return type(t) == "table" and t[key] or nil
end

local function isSecret(v)
    local fn = _G.issecretvalue
    if type(fn) ~= "function" then
        return false
    end
    local ok, s = pcall(fn, v)
    return not ok or s == true
end

local function now()
    local t = call(_G.GetTime)
    return type(t) == "number" and t or nil
end

-- Returns whether a plain cost list holds a mana cost over 0; nil when any entry or field is secret.
local function manaCost(list)
    local mana = false
    for i = 1, #list do
        local e = list[i]
        if isSecret(e) or type(e) ~= "table" then
            return nil
        end
        local kind, cost, pct = e.type, e.cost, e.costPercent
        if isSecret(kind) or isSecret(cost) or isSecret(pct) then
            return nil
        end
        if kind == MANA and ((type(cost) == "number" and cost > 0) or (type(pct) == "number" and pct > 0)) then
            mana = true
        end
    end
    return mana
end

-- Reads the spell's cost and texture, remembering each plain read.
local function learn(id)
    local fn = api(_G.C_Spell, "GetSpellPowerCost")
    if type(fn) == "function" then
        local ok, list = pcall(fn, id)
        if ok and not isSecret(list) and type(list) == "table" then
            local okCost, mana = pcall(manaCost, list)
            if okCost and mana ~= nil then
                costs[id] = mana
            end
        end
    end
    local texture = call(api(_G.C_Spell, "GetSpellTexture"), id)
    if texture ~= nil then
        textures[id] = texture
    end
end

local function learnSlot(slot)
    local kind, id = call(_G.GetActionInfo, slot)
    if kind == "spell" and type(id) == "number" then
        learn(id)
    end
end

-- Out of combat, learns the given action slot's spell, or every action bar spell without one (or slot 0, which the
-- client sends when many slots changed).
local function warm(slot)
    if call(_G.InCombatLockdown) == true then
        return
    end
    if type(slot) == "number" and slot > 0 then
        learnSlot(slot)
        return
    end
    for i = 1, SLOTS do
        learnSlot(i)
    end
end

-- Makes the hidden icon under the player frame; false without one.
local function make()
    local player = _G.PlayerFrame
    if type(player) ~= "table" then
        return false
    end
    local f = CreateFrame("Frame", "TandemFiveSecondIcon", _G.UIParent)
    f:SetFrameStrata("MEDIUM")
    call(f.EnableMouse, f, false)
    f:SetSize(SIZE, SIZE)
    f:SetPoint("TOP", player, "BOTTOM", X, -BELOW)
    f.art = f:CreateTexture(nil, "ARTWORK")
    f.art:SetAllPoints(f)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    if ok and type(cd) == "table" then
        cd:SetAllPoints(f)
        call(cd.SetHideCountdownNumbers, cd, true)
        f.cooldown = cd
    end
    -- On the swipe's frame, so the swipe does not darken the number.
    local host = f.cooldown or f
    f.count = host:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:Hide()
    icon = f
    return true
end

local function stop()
    start = nil
    if ticker then
        call(ticker.Cancel, ticker)
        ticker = nil
    end
    if icon then
        icon:Hide()
    end
end

local function tick()
    local t = now()
    if not (start and t) or t - start >= WINDOW then
        stop()
        return
    end
    icon.count:SetText(tostring(math.ceil(WINDOW - (t - start))))
end

-- Starts the window for the spell: the ticker, its texture and the swipe from now. Without a ticker nothing would
-- hide the icon, so it does not show.
local function begin(id)
    local t = now()
    if not t or not (icon or make()) then
        return
    end
    if not ticker then
        local newTicker = api(_G.C_Timer, "NewTicker")
        local ok, made = false, nil
        if type(newTicker) == "function" then
            ok, made = pcall(newTicker, TICK, tick)
        end
        ticker = ok and made or nil
        if not ticker then
            return
        end
    end
    start = t
    icon.art:SetTexture(textures[id] or FALLBACK)
    if icon.cooldown then
        call(icon.cooldown.SetCooldown, icon.cooldown, start, WINDOW)
    end
    icon:Show()
    tick()
end

local function onCast(unit, spellId)
    local id = Safe(spellId)
    if Safe(unit) ~= "player" or type(id) ~= "number" or call(_G.UnitPowerType, "player") ~= MANA then
        return
    end
    learn(id)
    if costs[id] == true then
        begin(id)
    end
end

local function onEvent(_, event, unit, _, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        onCast(unit, spellId)
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        warm(Safe(unit))
    else
        warm()
    end
end

-- PLAYER_LOGIN: registers the player's casts and the warm-up events on this module's own frame, once, and learns the
-- action bars' spells.
function FiveSecond.OnLogin()
    if not events then
        events = CreateFrame("Frame", "TandemFiveSecondEvents")
        ns.Store.RegisterUnitEvent(events, "UNIT_SPELLCAST_SUCCEEDED", "player")
        for _, event in ipairs(EVENTS) do
            ns.Store.RegisterEvent(events, event)
        end
        events:SetScript("OnEvent", onEvent)
    end
    warm()
end
