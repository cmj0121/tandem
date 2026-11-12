local _, ns = ...

-- The layout mode button (D1, D3, D4): one plain button left of the mute button (or of whatever is left of it when
-- the mute button is hidden) while the layout is on. A click switches this character's layout mode between damage and
-- healer through Layout.SetMode and prints the reply; its icon and tooltip show the current mode. It is parented and
-- anchored to UIParent only. Its place and visibility change only out of combat, like its neighbours' (a change asked
-- for in combat waits for Role.OnCombatEnd); a click in combat waits for Layout.OnCombatEnd, which then tells the
-- layout listener below.
local Role = {}
ns.Role = Role

local call = ns.Store.Call

local SIZE = 28
local ICONS = {
    dps = "Interface\\Icons\\INV_Sword_04",
    heal = "Interface\\Icons\\Spell_Holy_FlashHeal",
}
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local REPLY = { dps = "Tandem: damage layout", heal = "Tandem: healer layout" }

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

local function showTooltip(self)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    local heal = ns.Layout.Mode() == "heal"
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:SetText(L["Layout mode"])
    tip:AddLine(heal and L["Healer"] or L["Damage"], 1, 1, 1)
    tip:AddLine(heal and L["Click for the damage layout"] or L["Click for the healer layout"], 0.5, 0.5, 0.5)
    tip:Show()
end

-- Role.Refresh(): sets the icon from this character's mode, and the tooltip when it is shown for the button; safe in
-- combat.
function Role.Refresh()
    if not button then
        return
    end
    button.icon:SetTexture(ICONS[ns.Layout.Mode()] or UNKNOWN_ICON)
    local tip = GameTooltip
    if type(tip) == "table" and call(tip.IsOwned, tip, button) == true then
        showTooltip(button)
    end
end

-- Role.Toggle(): asks Layout.SetMode for the other mode and prints its reply; in combat the reply is the wait line
-- and the switch happens at combat end.
function Role.Toggle()
    local mode = ns.Layout.Mode() == "heal" and "dps" or "heal"
    local ok, reason = ns.Layout.SetMode(mode)
    log(("role toggle: %s ok=%s reason=%s"):format(mode, tostring(ok), tostring(reason)))
    print(ok and ns.L[REPLY[mode]] or ns.Layout.Reply(true, false, reason))
    Role.Refresh()
end

-- Refreshes the icon, then the button's place and visibility; in combat only marks the place as pending. Runs after
-- every Mute.Update (whose button it sits beside), at login and on a layout change. While debugging, logs the
-- button's state when it differs from the last one logged.
function Role.Update()
    if not button then
        return
    end
    Role.Refresh()
    if inCombat() then
        pending = true
        return
    end
    pending = nil
    local x = ns.Mute.NextX()
    if on then
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, ns.BagButton.OFFSET_Y + ns.Layout.MicroRoom())
        button:Show()
    else
        button:Hide()
    end
    local line = ("role update: on=%s mode=%s x=%s"):format(tostring(on == true), ns.Layout.Mode(), tostring(x))
    if line ~= lastUpdate then
        lastUpdate = line
        log(line)
    end
end

-- PLAYER_REGEN_ENABLED: applies the change combat held back.
function Role.OnCombatEnd()
    if pending then
        Role.Update()
    end
end

-- PLAYER_LOGIN: makes the button (never later, so it is never first made in combat by a layout change) and shows it
-- when it should. Runs before Rod.OnLogin, whose update places it again.
function Role.OnLogin()
    local ready = ns.Check.Ready("Role button")
    if not button and type(CreateFrame) == "function" and ready then
        local ok, made = pcall(CreateFrame, "Button", "TandemRoleButton", UIParent)
        if ok then
            button = made
            button:SetSize(SIZE, SIZE)
            button:SetFrameStrata("MEDIUM")
            button:RegisterForClicks("LeftButtonUp")
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetAllPoints(button)
            button:SetScript("OnClick", Role.Toggle)
            button:SetScript("OnEnter", showTooltip)
            button:SetScript("OnLeave", ns.View.HideTooltip)
            button:Hide()
        else
            log("role login: CreateFrame failed: " .. tostring(made))
        end
    end
    log(("role login: ready=%s button=%s mode=%s"):format(tostring(ready), button and "made" or "none",
        ns.Layout.Mode()))
    Role.Update()
end

-- Listens after the mute button's listener (Role.lua follows Mute.lua in the toc), so Mute.NextX() is already
-- current; it also refreshes the icon after a mode change applied at combat end.
ns.Layout.OnChange(function(layoutOn)
    on = layoutOn and ns.Check.Ready("Role button")
    Role.Update()
end)
