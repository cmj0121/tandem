local _, ns = ...

-- The range text: one coloured line at a fixed place on the screen, under the player's own character, telling how far
-- the target is, by band, nearest first (PLAN D1): "0 - 5" red while item 8149 is in range of the target, "5 - 20"
-- green while item 10645 is, "20 - 30" blue while item 835 is, and "30+" gray when 835 reads out of range.
-- C_Item.IsItemInRange answers in combat for every class (item range probe, 2026-11-20), so no spell is involved, and
-- no nameplate is needed. A reading counts only when it is true; nil (no or a dead target, item data not loaded) is no
-- answer, so then the text hides (D2). The items' data is requested at login so their reads answer. One ticker checks
-- every TICK seconds; without a target it hides the text and reads nothing more. A target change hides the text at
-- once until the next tick reads a band. Every read goes through Store.Call, so a secret or raising one is read as
-- absent. The first band shown in combat logs one "range text: ..." debug line a session, to check the bands in game.
-- The events go on Tandem's own frame, which forwards them through RangeText.OnEvent.
local RangeText = {}
ns.RangeText = RangeText

-- The items whose range bounds each band, nearest first; FAR's out of range is "30+".
local NEAR, MID, FAR = 8149, 10645, 835
local ITEMS = { NEAR, MID, FAR }
local RED = { 0.88, 0.19, 0.19 }
local GREEN = { 0.25, 0.88, 0.25 }
local BLUE = { 0.25, 0.66, 1 }
local GRAY = { 0.62, 0.62, 0.62 }
local TICK = 0.1
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local SIZE = 20
local FLAGS = "THICKOUTLINE"
-- The pixel drop from the screen's centre to the text, so it sits under the player's character; tuned by eye in game.
local DROP = 140
local EVENTS = { "PLAYER_TARGET_CHANGED" }

local call = ns.Store.Call
local registered = {}
local logged = {}
local frame, ticker

local function logOnce(key, what)
    if not logged[key] and ns.Debug.IsOn() then
        logged[key] = true
        ns.Debug.Log("range text: " .. what)
    end
end

local function api(t, key)
    return type(t) == "table" and t[key] or nil
end

local function inRange(id)
    return call(api(_G.C_Item, "IsItemInRange"), id, "target")
end

-- Returns the band's label and colour, or nil when no reading answers.
local function band()
    if inRange(NEAR) == true then
        return "0 - 5", RED
    elseif inRange(MID) == true then
        return "5 - 20", GREEN
    end
    local far = inRange(FAR)
    if far == true then
        return "20 - 30", BLUE
    elseif far == false then
        return "30+", GRAY
    end
end

local function hide()
    if not frame or not frame.visible then
        return
    end
    frame.visible, frame.band = false, nil
    call(frame.Hide, frame)
end

-- Makes the hidden text at its fixed place, the first time it is to show.
local function make()
    frame = CreateFrame("Frame", "TandemRangeText", _G.UIParent)
    frame:SetFrameStrata("HIGH")
    call(frame.EnableMouse, frame, false)
    frame:SetSize(1, 1)
    frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, -DROP)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    call(label.SetFont, label, _G.STANDARD_TEXT_FONT or FALLBACK_FONT, SIZE, FLAGS)
    label:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.label = label
    frame:Hide()
    frame.visible = false
end

local function update()
    if call(_G.UnitExists, "target") ~= true then
        hide()
        return
    end
    local text, colour = band()
    if not text then
        hide()
        return
    end
    if not frame then
        make()
    end
    if call(_G.InCombatLockdown) == true then
        logOnce("combat", "first combat band=" .. text)
    end
    if frame.band ~= text then
        frame.band = text
        frame.label:SetText(text)
        frame.label:SetTextColor(colour[1], colour[2], colour[3])
    end
    if not frame.visible then
        frame.visible = true
        call(frame.Show, frame)
    end
end

local function tick()
    local ok, err = pcall(update)
    if not ok then
        local okText, text = pcall(tostring, err)
        logOnce("update", "update error " .. (okText and type(text) == "string" and text or "?"))
    end
end

-- Hides the text at once on a target change, until the next tick reads a band. Other events are ignored.
function RangeText.OnEvent(event)
    if registered[event] then
        hide()
    end
end

-- PLAYER_LOGIN: registers the text's event on frame (Tandem's), requests the items' data and starts the ticker, once.
function RangeText.OnLogin(eventFrame)
    if ticker then
        return
    end
    for _, event in ipairs(EVENTS) do
        registered[event] = ns.Store.RegisterEvent(eventFrame, event) or nil
    end
    for _, id in ipairs(ITEMS) do
        call(api(_G.C_Item, "RequestLoadItemDataByID"), id)
    end
    local newTicker = api(_G.C_Timer, "NewTicker")
    if type(newTicker) == "function" then
        local ok, t = pcall(newTicker, TICK, tick)
        ticker = ok and t or nil
    end
end
