local _, ns = ...

-- The cure buttons (class feature macros, first for the Shaman): one secure button per cure spell the player knows,
-- left of the fishing rod button while the layout is on. A click casts the cure on the mouseover friend, else the
-- friendly target, else the player; dragging places a "Tandem <kind>" character macro doing the same. The player or a
-- party member carrying a debuff the cure removes lights the button's border with the count of them, and its tooltip
-- names them, out of combat only: Forever keeps aura data secret from addons in combat ("Auras cannot be accessed
-- when secret"), so a fight leaves the hint dark until it ends. The hint is advice only: nothing is cast but on the
-- player's own click. Like the rod button, a button's attributes, anchor and visibility change only out of combat (a
-- change asked for in combat waits for Cure.OnCombatEnd).
local Cure = {}
ns.Cure = Cure

local call = ns.Store.Call

-- Per class, its cures in button order, right to left: the spell, the debuff type it removes and its macro's name.
Cure.CURES = {
    SHAMAN = {
        { spell = 526, kind = "Poison", macro = "Tandem Poison" },
        { spell = 2870, kind = "Disease", macro = "Tandem Disease" },
    },
}
-- The units whose debuffs light a button.
local UNITS = { "player", "party1", "party2", "party3", "party4" }
local WATCHED = {}
for _, unit in ipairs(UNITS) do
    WATCHED[unit] = true
end
local MAX_AURAS = 40
local SIZE, GAP = 28, 4
local TARGETS = "[@mouseover,help,nodead][@target,help,nodead][@player]"
local MACRO_ICON = "INV_Misc_QuestionMark"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

local cures, buttons = {}, {}
local on, pending, macroPending, lastScan
-- afflicted[kind] = { "<unit name>: <debuff name>", ... } from the last scan.
local afflicted = {}

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

-- The spell's localized name and icon, or nils.
local function spellInfo(id)
    local info = call(C_Spell and C_Spell.GetSpellInfo, id)
    if type(info) == "table" and type(info.name) == "string" then
        return info.name, info.iconID
    end
    local name, _, icon = call(GetSpellInfo, id)
    if type(name) == "string" and name ~= "" then
        return name, icon
    end
end

local function known(id)
    return call(IsPlayerSpell, id) == true or call(IsSpellKnown, id) == true
end

-- Cure.Body(name) -> text: the cast line a button and its macro run for the localized cure name.
function Cure.Body(name)
    return "/cast " .. TARGETS .. " " .. name
end

-- Cure.MacroBody(name) -> text: the cure macro's body.
function Cure.MacroBody(name)
    return "#showtooltip\n" .. Cure.Body(name)
end

-- Calls fn(debuffName, kind) for each debuff on unit until the client gives no more.
local function eachDebuff(unit, fn)
    local byIndex = type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataByIndex
    for i = 1, MAX_AURAS do
        local name, kind
        if type(byIndex) == "function" then
            local aura = byIndex(unit, i, "HARMFUL")
            if type(aura) ~= "table" then
                return
            end
            name, kind = aura.name, aura.dispelName
        else
            local _
            name, _, _, kind = UnitDebuff(unit, i)
            if name == nil then
                return
            end
        end
        fn(name, kind)
    end
end

-- Reads every watched unit's debuffs into afflicted; false when the client raised (aura data it keeps from addons).
local function readDebuffs()
    local found = {}
    for _, unit in ipairs(UNITS) do
        if unit == "player" or call(UnitExists, unit) == true then
            local who = call(UnitName, unit)
            who = type(who) == "string" and who or unit
            eachDebuff(unit, function(name, kind)
                if type(kind) == "string" then
                    found[kind] = found[kind] or {}
                    local list = found[kind]
                    list[#list + 1] = who .. ": " .. tostring(name)
                end
            end)
        end
    end
    afflicted = found
end

-- Lights each button whose debuff type a watched unit carries, with the count of them.
local function light()
    for i, b in ipairs(buttons) do
        local list = cures[i] and afflicted[cures[i].kind]
        local n = list and #list or 0
        if n > 0 then
            b.glow:Show()
            b.count:SetText(tostring(n))
        else
            b.glow:Hide()
            b.count:SetText("")
        end
    end
end

-- UNIT_AURA (watched units only), GROUP_ROSTER_UPDATE: reads the debuffs again and lights the buttons; in combat it
-- reads nothing and darkens them (the aura data is secret there). While debugging, logs the scan when it differs from
-- the last one logged.
function Cure.Scan(unit)
    if #buttons == 0 or (unit ~= nil and not WATCHED[unit]) then
        return
    end
    local ok, err = true, nil
    local fighting = inCombat()
    if fighting then
        afflicted = {}
    else
        ok, err = pcall(readDebuffs)
        if not ok then
            afflicted = {}
        end
    end
    light()
    if debugOn() then
        local parts = {}
        for _, c in ipairs(cures) do
            local list = afflicted[c.kind]
            parts[#parts + 1] = c.kind .. "=" .. (list and table.concat(list, ",") or "0")
        end
        local line = fighting and "cure scan: skipped in combat"
            or ok and ("cure scan: " .. table.concat(parts, " ")) or ("cure scan failed: " .. tostring(err))
        if line ~= lastScan then
            lastScan = line
            log(line)
        end
    end
end

local function showTooltip(self)
    local tip, c = GameTooltip, cures[self.index]
    if type(tip) ~= "table" or not c then
        return
    end
    local L = ns.L
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:SetText((spellInfo(c.spell)) or c.macro)
    local list = afflicted[c.kind]
    if list and #list > 0 then
        for _, line in ipairs(list) do
            tip:AddLine(line, 1, 1, 1)
        end
    else
        tip:AddLine(L["No one in your party has a %s effect"]:format(L[c.kind]), 0.5, 0.5, 0.5)
    end
    tip:AddLine(L["Click to cast it on your mouseover, your target or yourself"], 0.5, 0.5, 0.5)
    if self.full then
        tip:AddLine(L["Character macros full: no room for the cure macro"], 1, 0.1, 0.1)
    elseif ns.Check.Ready("Cure macro") and not inCombat() then
        tip:AddLine(L["Drag to place the cure macro on your action bar"], 0.5, 0.5, 0.5)
    end
    tip:Show()
end

-- Makes or refreshes button i's cure macro (made only when create) and returns its index, or nil. Out of combat
-- only; in combat it marks the change as pending.
local function ensureMacro(i, create)
    local c, b = cures[i], buttons[i]
    if not ns.Check.Ready("Cure macro") then
        return nil
    end
    if inCombat() then
        macroPending = true
        return nil
    end
    local name = spellInfo(c.spell)
    if not name then
        return nil
    end
    local body = Cure.MacroBody(name)
    local index, what, used, max = ns.Macro.Ensure(c.macro, MACRO_ICON, body, create)
    b.full = what == "full" or nil
    if what == "edited" or what == "created" then
        log(("cure macro %s: %s index=%s body=%s"):format(c.kind, what, tostring(index), (body:gsub("\n", "|"))))
    elseif what == "full" then
        log(("cure macro %s: skipped: character macros full (%d/%d)"):format(c.kind, used, max))
    end
    return index
end

-- OnDragStart: picks the button's cure macro up for an action bar, making it first when it is missing; nothing in
-- combat.
local function dragStart(self)
    if inCombat() then
        return
    end
    local index = ensureMacro(self.index, true)
    if index then
        call(PickupMacro, index)
    end
end

-- Lays the buttons out right to left from Rod.NextX(), each shown while the layout is on and its spell is known.
local function place()
    local x = ns.Rod.NextX()
    local y = ns.BagButton.OFFSET_Y + ns.Layout.MicroRoom()
    local shown = {}
    for i, b in ipairs(buttons) do
        local c = cures[i]
        local name, icon = spellInfo(c.spell)
        b:SetAttribute("useOnKeyDown", false)
        if on and name and known(c.spell) then
            b:SetAttribute("type", "macro")
            b:SetAttribute("macrotext", Cure.Body(name))
            b.icon:SetTexture(icon or UNKNOWN_ICON)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, y)
            b:Show()
            x = x - SIZE - GAP
            shown[#shown + 1] = c.kind
        else
            b:Hide()
        end
    end
    return shown
end

-- Cure.NextX() -> x: the BOTTOMRIGHT x offset for the right edge of a button left of the shown cure buttons, or
-- Rod.NextX() while none is shown; the y offset is the rod button's.
function Cure.NextX()
    local x = ns.Rod.NextX()
    for _, b in ipairs(buttons) do
        if call(b.IsShown, b) == true then
            x = x - SIZE - GAP
        end
    end
    return x
end

local lastPlace

-- Refreshes the buttons' macros, icons, places and visibility and the existing cure macros; in combat only marks the
-- change as pending. Runs after every Rod.Update, whose button it sits beside.
function Cure.Update()
    if #buttons == 0 then
        return
    end
    if inCombat() then
        pending = true
        return
    end
    pending, macroPending = nil, nil
    local shown = place()
    for i in ipairs(buttons) do
        ensureMacro(i, false)
    end
    local line = ("cure update: on=%s shown=%s x=%s"):format(tostring(on == true), table.concat(shown, ","),
        tostring(ns.Rod.NextX()))
    if line ~= lastPlace then
        lastPlace = line
        log(line)
    end
end

-- PLAYER_REGEN_ENABLED: applies the change combat held back and reads the debuffs again.
function Cure.OnCombatEnd()
    if pending or macroPending then
        Cure.Update()
    end
    Cure.Scan()
end

-- PLAYER_LOGIN: makes one button per cure of the player's class (never later, so never first made in combat), then
-- shows and lights them. A class without cures gets none. Runs before Rod.OnLogin, whose update places them.
-- Returns whether there are buttons, so the caller listens to aura events.
function Cure.OnLogin()
    local _, classFile = call(UnitClass, "player")
    local list = classFile and Cure.CURES[classFile]
    if not list or #buttons > 0 or type(CreateFrame) ~= "function" or not ns.Check.Ready("Cure buttons") then
        log(("cure login: class=%s ready=%s"):format(tostring(classFile), tostring(ns.Check.Ready("Cure buttons"))))
        return #buttons > 0
    end
    for i, c in ipairs(list) do
        local ok, b = pcall(CreateFrame, "Button", "TandemCureButton" .. i, UIParent, "SecureActionButtonTemplate")
        if not ok then
            log("cure login: CreateFrame failed: " .. tostring(b))
            break
        end
        cures[i], buttons[i] = c, b
        b.index = i
        b:SetSize(SIZE, SIZE)
        b:SetFrameStrata("MEDIUM")
        -- Mouse-up only (useOnKeyDown false, set by place out of combat): the mouse-down that starts a drag must
        -- not cast.
        b:RegisterForClicks("AnyUp")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(b)
        b.glow = b:CreateTexture(nil, "OVERLAY")
        b.glow:SetTexture(GLOW)
        b.glow:SetBlendMode("ADD")
        b.glow:SetVertexColor(1, 0.82, 0)
        b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.glow:SetSize(SIZE * 1.8, SIZE * 1.8)
        b.glow:Hide()
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b:SetScript("OnEnter", showTooltip)
        b:SetScript("OnLeave", ns.View.HideTooltip)
        if ns.Check.Ready("Cure macro") then
            b:RegisterForDrag("LeftButton")
            b:SetScript("OnDragStart", dragStart)
        end
        -- A /reload in combat leaves the new buttons as made (no attributes, so a click casts nothing) until
        -- combat ends.
        if inCombat() then
            pending = true
        else
            b:Hide()
        end
    end
    log(("cure login: class=%s buttons=%d"):format(classFile, #buttons))
    Cure.Scan()
    return #buttons > 0
end

-- Listens after the rod button's listener (Cure.lua follows Rod.lua in the toc), so Rod.NextX() is already current.
ns.Layout.OnChange(function(layoutOn)
    on = layoutOn
    Cure.Update()
end)
