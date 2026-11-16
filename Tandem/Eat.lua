local _, ns = ...

-- The eat and drink button (D1, D3, D4): one secure button left of the layout mode button (or of whatever is left of
-- it when that button is hidden) while the layout is on and a food or drink is in the bags. Its click runs the macro
-- Food.Macro builds for the player's health and mana; nothing is used without that click. It is parented and anchored
-- to UIParent only, and its attributes, place and visibility change only out of combat (a change asked for in combat
-- waits for Eat.OnCombatEnd). The bags' tooltips are read (Food.Scan) only after a bag, item info, level or layout
-- change, and the result kept; health, mana and aura changes pick again from that cache, once a frame at most.
local Eat = {}
ns.Eat = Eat

local call = ns.Store.Call

local SIZE = 28
local MANA = 0
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local button, on, lastUpdate, keyUp, scheduled
-- The cached Food.Scan result, read again on the next update once stale.
local candidates, stale = {}, true
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

local function below(cur, max)
    return type(cur) == "number" and type(max) == "number" and cur < max
end

-- Whether the player's health, and mana (a mana user only), is below its maximum.
local function needs()
    local health = below(call(UnitHealth, "player"), call(UnitHealthMax, "player"))
    local mana = call(UnitPowerType, "player") == MANA
        and below(call(UnitPower, "player", MANA), call(UnitPowerMax, "player", MANA))
    return health, mana
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
    local used
    if state.needHealth and state.food then
        tip:AddLine(L["Eat %s"]:format(itemName(state.food.id)), 1, 1, 1)
        used = state.food.id
    end
    if state.needMana and state.drink and state.drink.id ~= used then
        tip:AddLine(L["Drink %s"]:format(itemName(state.drink.id)), 1, 1, 1)
    end
    if not (state.lowHealth or state.lowMana) then
        tip:AddLine(L["Health and mana are full"], 1, 1, 1)
    end
    tip:AddLine(L["Click to eat and drink"], 0.5, 0.5, 0.5)
    tip:Show()
end

local function updateLine(x)
    return ("eat update: on=%s food=%s drink=%s health=%s mana=%s macro=%s shown=%s x=%s"):format(
        tostring(on == true), tostring(state.food and state.food.id), tostring(state.drink and state.drink.id),
        tostring(state.needHealth == true), tostring(state.needMana == true),
        (tostring(state.macro):gsub("\n", "|")), tostring(call(button.IsShown, button) == true), tostring(x))
end

-- Eat.Update(): picks the food and drink from the cached scan (scanning first when it is stale), sets the macro, icon,
-- place and visibility. Runs after every Role.Update (whose button it sits beside), at login, on a layout change and
-- from Eat.Schedule; does nothing in combat, as Eat.OnCombatEnd updates anyway. While debugging, logs the button's
-- state when it differs from the last one logged.
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
            candidates, stale = ns.Food.Scan(), false
        end
        local eating, drinking, wellFed = ns.Food.Auras()
        local health, mana = needs()
        state.food, state.drink = ns.Food.Pick(candidates, wellFed)
        state.lowHealth, state.lowMana = health, mana
        state.needHealth, state.needMana = health and not eating, mana and not drinking
        state.macro = ns.Food.Macro(state.food, state.drink, state.needHealth, state.needMana)
    end
    local item = state.food or state.drink
    if item then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", state.macro)
        button.icon:SetTexture(icon(item.id) or UNKNOWN_ICON)
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
    stale = true
    Eat.Update()
end

-- GET_ITEM_INFO_RECEIVED: reads the bags again on the next Eat.Schedule update.
function Eat.Invalidate()
    stale = true
end

-- UNIT_HEALTH, UNIT_POWER_UPDATE, UNIT_MAXPOWER, UNIT_AURA (player), GET_ITEM_INFO_RECEIVED: runs one Eat.Update on
-- the next frame however many arrive before it; at once when C_Timer is missing. Nothing in combat: Eat.OnCombatEnd
-- updates.
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

-- PLAYER_REGEN_ENABLED: applies the changes combat held back, with the health and mana combat left.
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
