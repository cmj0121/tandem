local _, ns = ...

-- The instant Lightning Bolt icon: for a Shaman, the Maelstrom Weapon icon with a yellow glow shows just above the
-- distance text while Maelstrom Weapon makes the bolt instant (PLAN D4, D5). Forever's overlay events are unusable,
-- but C_Spell.GetSpellInfo(403).castTime reads plainly in combat and drops 300 ms a stack, to 0 at five (Maelstrom
-- probe, 2026-11-20), so the icon shows only while that cast time is a plain 0 and the bolt is known; a missing,
-- secret or raising read hides it. No aura API is called. It is read on the player's UNIT_AURA and casts, which go on
-- this module's own event frame so Tandem's other aura handlers stay as they were, on combat start and end, which
-- Tandem's frame forwards through Maelstrom.OnEvent, and every TICK seconds while in combat or shown.
local Maelstrom = {}
ns.Maelstrom = Maelstrom

local BOLT = 403
-- The Maelstrom Weapon buff (seen by the probe as 「氣漩武器」) and the other candidate id, whose icon the icon shows.
local MAELSTROM = 408505
local MAELSTROM_ALT = 408498
local ICONS = { MAELSTROM, MAELSTROM_ALT, BOLT }
local SIZE = 40
local GLOW = 72
-- The icon's centre below the screen's centre: the distance text's line (RangeText's DROP, 140, size 20) has its top
-- near -130, so the icon's bottom sits 4 px above it.
local Y = -106
local FADE = 0.15
local TICK = 0.2
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local UNIT_EVENTS = { "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED" }

local call = ns.Store.Call
local registered = {}
local icon, events, ticker

local function api(t, key)
    return type(t) == "table" and t[key] or nil
end

local function known()
    return call(_G.IsPlayerSpell, BOLT) == true or call(_G.IsSpellKnown, BOLT) == true
end

-- Returns whether Lightning Bolt's cast time reads a plain 0.
local function instant()
    local info = call(api(_G.C_Spell, "GetSpellInfo"), BOLT)
    if type(info) ~= "table" then
        return false
    end
    local ok, castTime = pcall(function()
        return info.castTime
    end)
    castTime = ok and ns.Store.Safe(castTime) or nil
    return type(castTime) == "number" and castTime == 0
end

-- Returns the first of the Maelstrom Weapon ids' textures the client gives, else Lightning Bolt's.
local function texture()
    for _, id in ipairs(ICONS) do
        local found = call(api(_G.C_Spell, "GetSpellTexture"), id) or call(_G.GetSpellTexture, id)
        if found then
            return found
        end
    end
end

-- Makes the hidden icon at its fixed place, the first time it is to show.
local function make()
    icon = CreateFrame("Frame", "TandemMaelstromIcon", _G.UIParent)
    icon:SetFrameStrata("HIGH")
    call(icon.EnableMouse, icon, false)
    icon:SetSize(SIZE, SIZE)
    icon:SetPoint("CENTER", _G.UIParent, "CENTER", 0, Y)
    local art = icon:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(icon)
    art:SetTexture(texture())
    local glow = icon:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(GLOW_TEXTURE)
    call(glow.SetBlendMode, glow, "ADD")
    call(glow.SetVertexColor, glow, 1, 0.9, 0.2)
    glow:SetSize(GLOW, GLOW)
    glow:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.art, icon.glow = art, glow
    local fade = call(icon.CreateAnimationGroup, icon)
    local alpha = fade and call(fade.CreateAnimation, fade, "Alpha")
    if alpha then
        call(alpha.SetFromAlpha, alpha, 0)
        call(alpha.SetToAlpha, alpha, 1)
        call(alpha.SetDuration, alpha, FADE)
        icon.fade = fade
    end
    icon:Hide()
    icon.visible = false
end

local function hide()
    if not icon or not icon.visible then
        return
    end
    icon.visible = false
    if icon.fade then
        call(icon.fade.Stop, icon.fade)
    end
    call(icon.Hide, icon)
end

local function show()
    if not icon then
        make()
    end
    if icon.visible then
        return
    end
    icon.visible = true
    call(icon.Show, icon)
    if icon.fade then
        call(icon.fade.Play, icon.fade)
    end
end

local function update()
    if known() and instant() then
        show()
    else
        hide()
    end
end

local function safely()
    local ok, err = pcall(update)
    if not ok and ns.Debug.IsOn() then
        local okText, text = pcall(tostring, err)
        ns.Debug.Log("maelstrom: update error " .. (okText and type(text) == "string" and text or "?"))
    end
end

local function tick()
    if (icon and icon.visible) or call(_G.InCombatLockdown) == true then
        safely()
    end
end

local function onUnitEvent(_, _, unit)
    if ns.Store.Safe(unit) == "player" then
        safely()
    end
end

-- Reads the cast time again on combat start and end, which Tandem's frame forwards; other events are ignored.
function Maelstrom.OnEvent(event)
    if registered[event] then
        safely()
    end
end

-- PLAYER_LOGIN: for a Shaman, registers combat start and end on frame (Tandem's), the player's UNIT_AURA and casts
-- on this module's own frame, and starts the ticker, once; other classes get nothing.
function Maelstrom.OnLogin(frame)
    local _, classFile = call(_G.UnitClass, "player")
    if ticker or events or classFile ~= "SHAMAN" then
        return
    end
    for _, event in ipairs(EVENTS) do
        registered[event] = ns.Store.RegisterEvent(frame, event) or nil
    end
    events = CreateFrame("Frame", "TandemMaelstromEvents")
    for _, event in ipairs(UNIT_EVENTS) do
        ns.Store.RegisterUnitEvent(events, event, "player")
    end
    events:SetScript("OnEvent", onUnitEvent)
    local newTicker = api(_G.C_Timer, "NewTicker")
    if type(newTicker) == "function" then
        local ok, t = pcall(newTicker, TICK, tick)
        ticker = ok and t or nil
    end
    safely()
end
