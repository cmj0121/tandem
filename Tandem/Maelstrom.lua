local _, ns = ...

-- The Shaman's ready icons, in fixed slots just above the distance text (PLAN D4-D7), each a 40 px icon with a yellow
-- glow that fades in and hides at once. Right: the Maelstrom Weapon icon while Maelstrom Weapon makes Lightning Bolt
-- instant. Forever's overlay events are unusable, but C_Spell.GetSpellInfo(403).castTime reads plainly in combat and
-- drops 300 ms a stack, to 0 at five (Maelstrom probe, 2026-11-20), so it shows only while that cast time is a plain
-- 0 and the bolt is known; a missing, secret or raising read hides it. Left: Stormstrike's icon, in combat only, while
-- Stormstrike is known and ready. Its cooldown is read when plain (out of combat), and its length remembered; in
-- combat the cooldown is secret, so readiness comes from the last Stormstrike cast seen plus that length (else
-- STRIKE_LENGTH). No aura API is called. The player's UNIT_AURA and casts go on this module's own event frame so
-- Tandem's other aura handlers stay as they were; combat start and end come from Tandem's frame through
-- Maelstrom.OnEvent; a ticker reads every TICK seconds while in combat or an icon shows.
local Maelstrom = {}
ns.Maelstrom = Maelstrom

local BOLT = 403
local STORMSTRIKE = 17364
-- The Maelstrom Weapon buff (seen by the probe as 「氣漩武器」) and the other candidate id, whose icon the icon shows.
local MAELSTROM = 408505
local MAELSTROM_ALT = 408498
-- Stormstrike's cooldown when no plain read gave one, and the longest a global cooldown lasts.
local STRIKE_LENGTH = 20
local GCD = 1.5
local SIZE = 40
local GLOW = 72
-- The icons' centre below the screen's centre: the distance text's line (RangeText's DROP, 140, size 20) has its top
-- near -130, so the icons' bottom sits 4 px above it. Fixed slots: Stormstrike left, Maelstrom right.
local Y = -106
local STRIKE_X = -22
local MAELSTROM_X = 22
local FADE = 0.15
local TICK = 0.2
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local UNIT_EVENTS = { "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED" }

local call = ns.Store.Call
local registered = {}
-- Each icon: its frame name, slot and texture ids in order of preference; frame and visible once made.
local maelstrom = { name = "TandemMaelstromIcon", x = MAELSTROM_X, textures = { MAELSTROM, MAELSTROM_ALT, BOLT } }
local strike = { name = "TandemStormstrikeIcon", x = STRIKE_X, textures = { STORMSTRIKE } }
-- The last Stormstrike cast's GetTime, and its cooldown length from the last plain read.
local lastStrike, strikeLength
local events, ticker

local function api(t, key)
    return type(t) == "table" and t[key] or nil
end

-- Returns t[key] passed through Store.Safe, or nil when indexing raises.
local function field(t, key)
    local ok, v = pcall(function()
        return t[key]
    end)
    return ok and ns.Store.Safe(v) or nil
end

local function known(id)
    return call(_G.IsPlayerSpell, id) == true or call(_G.IsSpellKnown, id) == true
end

local function inCombat()
    return call(_G.InCombatLockdown) == true
end

-- Returns whether Lightning Bolt's cast time reads a plain 0.
local function instant()
    local info = call(api(_G.C_Spell, "GetSpellInfo"), BOLT)
    if type(info) ~= "table" then
        return false
    end
    local castTime = field(info, "castTime")
    return type(castTime) == "number" and castTime == 0
end

-- Returns whether Stormstrike is off cooldown: from a plain cooldown read, which also remembers its length, else from
-- the last cast seen plus that length. A global cooldown alone is read by the timer, since right after a cast the
-- read can show it before Stormstrike's own cooldown.
local function strikeReady()
    local cd = call(api(_G.C_Spell, "GetSpellCooldown"), STORMSTRIKE)
    if type(cd) == "table" then
        local start, duration = field(cd, "startTime"), field(cd, "duration")
        if type(start) == "number" and type(duration) == "number" then
            if start == 0 then
                return true
            end
            if duration > GCD then
                strikeLength = duration
                return false
            end
        end
    end
    if not lastStrike then
        return true
    end
    local now = call(_G.GetTime)
    return type(now) == "number" and now >= lastStrike + (strikeLength or STRIKE_LENGTH)
end

-- Returns the first of the icon's spell ids' textures the client gives.
local function texture(item)
    for _, id in ipairs(item.textures) do
        local found = call(api(_G.C_Spell, "GetSpellTexture"), id) or call(_G.GetSpellTexture, id)
        if found then
            return found
        end
    end
end

-- Makes the icon's hidden frame at its fixed slot, the first time it is to show.
local function make(item)
    local f = CreateFrame("Frame", item.name, _G.UIParent)
    f:SetFrameStrata("HIGH")
    call(f.EnableMouse, f, false)
    f:SetSize(SIZE, SIZE)
    f:SetPoint("CENTER", _G.UIParent, "CENTER", item.x, Y)
    local art = f:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(f)
    art:SetTexture(texture(item))
    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(GLOW_TEXTURE)
    call(glow.SetBlendMode, glow, "ADD")
    call(glow.SetVertexColor, glow, 1, 0.9, 0.2)
    glow:SetSize(GLOW, GLOW)
    glow:SetPoint("CENTER", f, "CENTER", 0, 0)
    local fade = call(f.CreateAnimationGroup, f)
    local alpha = fade and call(fade.CreateAnimation, fade, "Alpha")
    if alpha then
        call(alpha.SetFromAlpha, alpha, 0)
        call(alpha.SetToAlpha, alpha, 1)
        call(alpha.SetDuration, alpha, FADE)
        item.fade = fade
    end
    f:Hide()
    item.frame, item.visible = f, false
end

local function hide(item)
    if not item.visible then
        return
    end
    item.visible = false
    if item.fade then
        call(item.fade.Stop, item.fade)
    end
    call(item.frame.Hide, item.frame)
end

local function show(item)
    if not item.frame then
        make(item)
    end
    if item.visible then
        return
    end
    item.visible = true
    call(item.frame.Show, item.frame)
    if item.fade then
        call(item.fade.Play, item.fade)
    end
end

local function set(item, shown)
    if shown then
        show(item)
    else
        hide(item)
    end
end

local function update()
    set(maelstrom, known(BOLT) and instant())
    -- Read out of combat too, where the cooldown is plain and its length is learnt; shown in combat only.
    local ready = known(STORMSTRIKE) and strikeReady()
    set(strike, inCombat() and ready)
end

local function safely()
    local ok, err = pcall(update)
    if not ok and ns.Debug.IsOn() then
        local okText, text = pcall(tostring, err)
        ns.Debug.Log("maelstrom: update error " .. (okText and type(text) == "string" and text or "?"))
    end
end

local function tick()
    if maelstrom.visible or strike.visible or inCombat() then
        safely()
    end
end

-- The player's UNIT_AURA and casts, on this module's own frame; a Stormstrike cast starts its own cooldown timer.
local function onUnitEvent(_, event, unit, _, spellId)
    if ns.Store.Safe(unit) ~= "player" then
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and ns.Store.Safe(spellId) == STORMSTRIKE then
        local now = call(_G.GetTime)
        lastStrike = type(now) == "number" and now or lastStrike
    end
    safely()
end

-- Reads the icons again on combat start and end, which Tandem's frame forwards; other events are ignored.
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
