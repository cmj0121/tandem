local _, ns = ...

-- The mute button (D1, D2, D4): one plain button left of the cure buttons (or the rod button, or the bag row, when
-- those are hidden) while the layout is on. A click flips the Sound_EnableAllSound CVar between 1 and 0; its icon and
-- tooltip show the current state. It is parented and anchored to UIParent only. A click works in combat, but its place
-- and visibility change only out of combat, like its neighbours' (a change asked for in combat waits for
-- Mute.OnCombatEnd). Nothing is saved in TandemDB: the CVar is the state.
local Mute = {}
ns.Mute = Mute

local call = ns.Store.Call

local CVAR = "Sound_EnableAllSound"
local SIZE = 28
-- One horn, in colour while the sound is on and grey while it is off.
local ICON = "Interface\\Icons\\INV_Misc_Horn_01"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local button, on, pending, lastUpdate

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

-- Mute.IsMuted() -> bool: all sound is off.
function Mute.IsMuted()
    return ns.Store.GetCVar(CVAR) == "0"
end

local function showTooltip(self)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    local muted = Mute.IsMuted()
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:SetText(L["Sound"])
    tip:AddLine(muted and L["Sound off"] or L["Sound on"], 1, 1, 1)
    tip:AddLine(muted and L["Click to unmute"] or L["Click to mute"], 0.5, 0.5, 0.5)
    tip:Show()
end

-- Mute.Refresh(): sets the icon from the CVar, and the tooltip when it is shown for the button; safe in combat.
-- CVAR_UPDATE runs it.
function Mute.Refresh()
    if not button then
        return
    end
    local value = ns.Store.GetCVar(CVAR)
    button.icon:SetTexture(value ~= nil and ICON or UNKNOWN_ICON)
    button.icon:SetDesaturated(value == "0")
    local tip = GameTooltip
    if type(tip) == "table" and call(tip.IsOwned, tip, button) == true then
        showTooltip(button)
    end
end

-- Mute.Toggle(): flips the CVar between 1 and 0, reads it back and refreshes the icon. Works in combat.
function Mute.Toggle()
    local before = ns.Store.GetCVar(CVAR)
    if before == nil then
        log("mute toggle: no " .. CVAR)
        return
    end
    ns.Store.SetCVar(CVAR, before == "0" and "1" or "0")
    log(("mute toggle: %s -> %s"):format(tostring(before), tostring(ns.Store.GetCVar(CVAR))))
    Mute.Refresh()
end

-- Refreshes the icon, then the button's place and visibility; in combat only marks the place as pending. Runs after
-- every Rod.Update (after Cure.Update, whose buttons it sits beside), at login and on a layout change. While debugging,
-- logs the button's state when it differs from the last one logged.
function Mute.Update()
    if not button then
        return
    end
    Mute.Refresh()
    if inCombat() then
        pending = true
        return
    end
    pending = nil
    local value = ns.Store.GetCVar(CVAR)
    local x = ns.Cure.NextX()
    if on and value ~= nil then
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, ns.BagButton.OFFSET_Y + ns.Layout.MicroRoom())
        button:Show()
    else
        button:Hide()
    end
    local line = ("mute update: on=%s cvar=%s shown=%s x=%s"):format(tostring(on == true), tostring(value),
        tostring(on == true and value ~= nil), tostring(x))
    if line ~= lastUpdate then
        lastUpdate = line
        log(line)
    end
end

-- PLAYER_REGEN_ENABLED: applies the change combat held back.
function Mute.OnCombatEnd()
    if pending then
        Mute.Update()
    end
end

-- PLAYER_LOGIN: makes the button (never later, so it is never first made in combat by a layout change) and shows it
-- when it should. Runs before Rod.OnLogin, whose update places it again.
function Mute.OnLogin()
    local ready = ns.Check.Ready("Mute button")
    if not button and type(CreateFrame) == "function" and ready then
        local ok, made = pcall(CreateFrame, "Button", "TandemMuteButton", UIParent)
        if ok then
            button = made
            button:SetSize(SIZE, SIZE)
            button:SetFrameStrata("MEDIUM")
            button:RegisterForClicks("LeftButtonUp")
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetAllPoints(button)
            button:SetScript("OnClick", Mute.Toggle)
            button:SetScript("OnEnter", function(self)
                Mute.Refresh()
                showTooltip(self)
            end)
            button:SetScript("OnLeave", ns.View.HideTooltip)
            button:Hide()
        else
            log("mute login: CreateFrame failed: " .. tostring(made))
        end
    end
    log(("mute login: ready=%s button=%s cvar=%s"):format(tostring(ready), button and "made" or "none",
        tostring(ns.Store.GetCVar(CVAR))))
    Mute.Update()
end

-- Listens after the cure buttons' listener (Mute.lua follows Cure.lua in the toc), so Cure.NextX() is already current;
-- it places the button itself for a player with no rod button, whose Rod.Update does nothing.
ns.Layout.OnChange(function(layoutOn)
    on = layoutOn and ns.Check.Ready("Mute button")
    Mute.Update()
end)
