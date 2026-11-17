local _, ns = ...

-- The eat and drink button (D1, D3, D4): one secure button left of the layout mode button (or of whatever is left of it
-- when that button is hidden) while the layout is on and a food or drink is in the bags. A left click uses the best
-- food and a right click the best drink (a mana user only), each left out while its aura is on; nothing is used without
-- that click. Health and mana are never compared: the client keeps them secret from addons. It is parented and anchored
-- to UIParent only, and its attributes, place and visibility change only out of combat (a change asked for in combat
-- waits for Eat.OnCombatEnd). The bags' tooltips are read (Food.Scan) only after a bag, item info, level or layout
-- change, and the result kept; power and aura changes pick again from that cache, once a frame at most.
local Eat = {}
ns.Eat = Eat

local call = ns.Store.Call

local SIZE = 28
local MANA = 0
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Seconds before each timed rescan while a scan leaves slots pending; none after the last.
local BACKOFF = { 1, 2, 4, 8, 16, 32 }

local button, on, lastUpdate, keyUp, scheduled
-- The cached Food.Scan result, read again on the next update once stale.
local candidates, stale = {}, true
-- The timed rescans used since the last complete scan or Eat.Rescan, and whether one waits.
local step, waiting = 0, false
-- True from the last timed rescan's firing until the scan it causes: only that scan settles what is still unsure.
local final = false
-- What the last update set the click to use, for the tooltip.
local state = {}

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

local function icon(id)
    local texture = select(5, call(C_Item and C_Item.GetItemInfoInstant, id))
    return texture or call(_G.GetItemIcon, id)
end

local function itemName(id)
    local name = call(C_Item and C_Item.GetItemInfo, id)
    return type(name) == "string" and name or ("item:" .. id)
end

local function showTooltip(self)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:SetText(L["Eat and drink"])
    if state.food then
        tip:AddLine(state.eating and L["Eating…"] or L["Left-click: eat %s"]:format(itemName(state.food.id)), 1, 1, 1)
    end
    if state.drink then
        tip:AddLine(state.drinking and L["Drinking…"] or L["Right-click: drink %s"]:format(itemName(state.drink.id)),
            1, 1, 1)
    end
    tip:Show()
end

-- The raw unit value as "type:value", for the debug line (a secret value prints its type only).
local function raw(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then
        return "error"
    end
    if issecretvalue and issecretvalue(v) then
        return "secret"
    end
    local shown, text = pcall(tostring, v)
    return type(v) .. ":" .. (shown and text or "?")
end

-- Schedules the next timed rescan unless one waits or the backoff is used up; one fired in combat does nothing, as
-- Eat.Update does nothing there and Eat.OnCombatEnd updates.
local function retry()
    if waiting or step >= #BACKOFF or not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then
        return
    end
    step = step + 1
    waiting = true
    if not pcall(C_Timer.After, BACKOFF[step], function()
        waiting = false
        final = step >= #BACKOFF
        Eat.Update()
    end) then
        waiting = false
    end
end

local function updateLine(x)
    return ("eat update: on=%s cands=%d food=%s drink=%s eating=%s drinking=%s left=%s right=%s shown=%s x=%s"
        .. " hp=%s/%s ptype=%s mp=%s/%s"):format(
        tostring(on == true), #candidates, tostring(state.food and state.food.id),
        tostring(state.drink and state.drink.id), tostring(state.eating == true), tostring(state.drinking == true),
        tostring(state.left), tostring(state.right), tostring(call(button.IsShown, button) == true), tostring(x),
        raw(UnitHealth, "player"), raw(UnitHealthMax, "player"), raw(UnitPowerType, "player"),
        raw(UnitPower, "player", MANA), raw(UnitPowerMax, "player", MANA))
end

-- Eat.Update(): picks the food and drink from the cached scan (scanning first when it is stale), sets the left and
-- right click macros, icon, place and visibility. A scan that leaves slots pending keeps the cache stale and
-- schedules a timed rescan after 1, 2, 4, 8, 16 then 32 s; the scan the last of them causes settles the items still
-- unsure (Food.Settle), and the cache is then kept until Eat.Rescan, Eat.Invalidate or a layout change. Runs after
-- every Role.Update (whose button it sits beside), at login, on a layout change and from Eat.Schedule; does nothing in
-- combat, as Eat.OnCombatEnd updates anyway. While debugging, logs the button's state when it differs from the last
-- one logged.
function Eat.Update()
    if not button then
        return
    end
    if inCombat() then
        return
    end
    if not keyUp then
        button:SetAttribute("useOnKeyDown", false)
        keyUp = true
    end
    local x = ns.Role.NextX()
    state = {}
    if on then
        if stale then
            local pending
            candidates, pending = ns.Food.Scan()
            if pending > 0 and final then
                -- The last timed rescan still leaves items unsure: they are not food.
                ns.Food.Settle()
            elseif pending > 0 then
                retry()
            else
                step = 0
            end
            stale, final = waiting, false
        end
        local eating, drinking, wellFed = ns.Food.Auras()
        state.food, state.drink = ns.Food.Pick(candidates, wellFed)
        if call(UnitPowerType, "player") ~= MANA then
            state.drink = nil
        end
        state.eating, state.drinking = eating, drinking
        state.left = not eating and ns.Food.Macro(state.food) or nil
        state.right = not drinking and ns.Food.Macro(state.drink) or nil
    end
    local item = state.food or state.drink
    if item then
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", state.left)
        button:SetAttribute("type2", "macro")
        button:SetAttribute("macrotext2", state.right)
        local shown = state.left and state.food or state.right and state.drink or item
        button.icon:SetTexture(icon(shown.id) or UNKNOWN_ICON)
        if button.icon.SetDesaturated then
            button.icon:SetDesaturated(not (state.left or state.right))
        end
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, ns.BagButton.OFFSET_Y + ns.Layout.MicroRoom())
        button:Show()
    else
        button:Hide()
    end
    if debugOn() then
        local line = updateLine(x)
        if line ~= lastUpdate then
            lastUpdate = line
            log(line)
        end
    end
end

-- BAG_UPDATE_DELAYED, PLAYER_LEVEL_UP: reads the bags again, then updates (in combat, at combat end).
function Eat.Rescan()
    stale, step, final = true, 0, false
    Eat.Update()
end

-- GET_ITEM_INFO_RECEIVED: reads the bags again on the next Eat.Schedule update.
function Eat.Invalidate()
    stale = true
end

-- UNIT_POWER_UPDATE, UNIT_MAXPOWER, UNIT_AURA (player), GET_ITEM_INFO_RECEIVED: runs one Eat.Update on the next frame
-- however many arrive before it; at once when C_Timer is missing. Nothing in combat: Eat.OnCombatEnd updates.
function Eat.Schedule()
    if not button or inCombat() then
        return
    end
    if not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then
        Eat.Update()
        return
    end
    if scheduled then
        return
    end
    scheduled = true
    if not pcall(C_Timer.After, 0, function()
        scheduled = false
        Eat.Update()
    end) then
        scheduled = false
        Eat.Update()
    end
end

-- PLAYER_REGEN_ENABLED: applies the changes combat held back.
function Eat.OnCombatEnd()
    Eat.Update()
end

-- PLAYER_LOGIN: makes the button (never later, so it is never first made in combat by a layout change) and shows it
-- when it should; returns true when the button exists, so its unit events are registered. Runs after Role.OnLogin,
-- whose place it follows, and before Rod.OnLogin, whose update places it again.
function Eat.OnLogin()
    local ready = ns.Check.Ready("Eat button")
    if not button and type(CreateFrame) == "function" and ready then
        local ok, made = pcall(CreateFrame, "Button", "TandemEatButton", UIParent, "SecureActionButtonTemplate")
        if ok then
            button = made
            button:SetSize(SIZE, SIZE)
            button:SetFrameStrata("MEDIUM")
            -- Mouse-up only (useOnKeyDown false, set by Eat.Update).
            button:RegisterForClicks("AnyUp")
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetAllPoints(button)
            button:SetScript("OnEnter", showTooltip)
            button:SetScript("OnLeave", ns.View.HideTooltip)
            button:Hide()
        else
            log("eat login: CreateFrame failed: " .. tostring(made))
        end
    end
    log(("eat login: ready=%s button=%s"):format(tostring(ready), button and "made" or "none"))
    stale = true
    Eat.Update()
    return button ~= nil
end

-- Listens after the layout mode button's listener (Eat.lua follows Role.lua in the toc), so Role.NextX() is current.
ns.Layout.OnChange(function(layoutOn)
    on = layoutOn and ns.Check.Ready("Eat button")
    stale = true
    Eat.Update()
end)
