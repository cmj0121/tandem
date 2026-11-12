local _, ns = ...

-- The class macro flyout (D1, D2, D4): one secure button left of the fishing rod button while the layout is on,
-- casting the character's picked class macro (ClassMacros.Pick), with a small arrow above it that opens an upward
-- list of every shown entry. A row click casts that entry and makes it the pick; secure snippets re-point the main
-- button and close the list, so this works in combat too. Without the secure handler APIs the list opens, picks and
-- closes out of combat only. A row or the main button lights with the count of party members carrying a debuff its
-- entry cures (out of combat: Cure.Scan); dragging one places that entry's character macro. Rows, bodies, places and
-- visibility change only out of combat (a change asked for in combat waits for Flyout.OnCombatEnd).
local Flyout = {}
ns.Flyout = Flyout

local call = ns.Store.Call

local SIZE, GAP, ARROW = 28, 4, 12
local MACRO_ICON = "INV_Misc_QuestionMark"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

-- The restricted snippets: the arrow's _onclick toggles the list; a row's OnClick pre-wrap copies its macro and entry
-- to the main button and closes the list, then lets the click cast; the main button's pre-wrap closes the list.
Flyout.SNIPPETS = {
    arrow = [[
local list = self:GetFrameRef("list")
if list:IsShown() then
    list:Hide()
else
    list:Show()
end
]],
    row = [[
local main = owner:GetFrameRef("main")
main:SetAttribute("macrotext", self:GetAttribute("macrotext"))
main:SetAttribute("entry", self:GetAttribute("entry"))
owner:Hide()
]],
    main = [[
owner:Hide()
]],
}

local main, arrow, list
local rows = {}
local classFile, secure, wired, on, pending, macroPending, lastUpdate
-- The shown entries in row order, and by id.
local entries, byId = {}, {}
-- The entry id picked in combat, saved at combat end; whether Update itself is setting the main button's entry.
local combatPick, applying
-- full[macro name] = true while its macro could not be made for lack of a character slot.
local full = {}

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

-- The number of debuffs the entry cures that the last scan found.
local function afflictions(e)
    local n = 0
    for _, kind in ipairs(e and e.kinds or {}) do
        n = n + #ns.Cure.Afflicted(kind)
    end
    return n
end

local function lightButton(b, n)
    if n > 0 then
        b.glow:Show()
        b.count:SetText(tostring(n))
    else
        b.glow:Hide()
        b.count:SetText("")
    end
end

-- Flyout.Light(): lights each row with its entry's count, and the main button with the count over every shown kind.
function Flyout.Light()
    if not main then
        return
    end
    local seen, total = {}, 0
    for i, row in ipairs(rows) do
        local e = entries[i]
        lightButton(row, afflictions(e))
        for _, kind in ipairs(e and e.kinds or {}) do
            if not seen[kind] then
                seen[kind] = true
                total = total + #ns.Cure.Afflicted(kind)
            end
        end
    end
    lightButton(main, total)
end

-- Makes or refreshes the entry's character macro (made only when create) and returns its index, or nil. Out of
-- combat only; in combat it marks the change as pending.
local function ensureMacro(e, create)
    if not ns.Check.Ready("Cure macro") then
        return nil
    end
    if inCombat() then
        macroPending = true
        return nil
    end
    local index, what, used, max = ns.Macro.Ensure(e.macro, MACRO_ICON, e.body, create)
    full[e.macro] = what == "full" or nil
    if what == "edited" or what == "created" then
        log(("flyout macro %s: %s index=%s body=%s"):format(e.id, what, tostring(index), (e.body:gsub("\n", "|"))))
    elseif what == "full" then
        log(("flyout macro %s: skipped: character macros full (%d/%d)"):format(e.id, used, max))
    end
    return index
end

local function entryOf(b)
    return byId[call(b.GetAttribute, b, "entry")]
end

-- OnDragStart (main button and rows): picks up the button's entry macro, making it first when it is missing; nothing
-- in combat.
local function dragStart(self)
    local e = entryOf(self)
    if inCombat() or not e then
        return
    end
    local index = ensureMacro(e, true)
    if index then
        call(PickupMacro, index)
    end
end

local function showTooltip(self)
    local tip, e = GameTooltip, entryOf(self)
    if type(tip) ~= "table" or not e then
        return
    end
    local L, fighting = ns.L, inCombat()
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:SetText(e.title)
    tip:AddLine(e.description, 1, 0.82, 0, true)
    if #e.kinds > 0 then
        if fighting then
            tip:AddLine(L["Party debuffs show again after combat"], 0.5, 0.5, 0.5)
        end
        for _, kind in ipairs(fighting and {} or e.kinds) do
            local found = ns.Cure.Afflicted(kind)
            for _, line in ipairs(found) do
                tip:AddLine(line, 1, 1, 1)
            end
            if #found == 0 then
                tip:AddLine(L["No one in your party has a %s effect"]:format(L[kind]), 0.5, 0.5, 0.5)
            end
        end
    end
    if full[e.macro] then
        tip:AddLine(L["Character macros full: no room for this macro"], 1, 0.1, 0.1)
    elseif ns.Check.Ready("Cure macro") then
        tip:AddLine(fighting and L["Drag out of combat to place this macro"]
            or L["Drag to place this macro on your action bar"], 0.5, 0.5, 0.5)
    end
    tip:Show()
end

local function arrowTooltip(self)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:SetText(L["Class macros"])
    if not secure and inCombat() then
        tip:AddLine(L["Choosing waits until combat ends"], 0.5, 0.5, 0.5)
    else
        tip:AddLine(L["Click to choose the button's macro"], 0.5, 0.5, 0.5)
    end
    tip:Show()
end

-- The main button's OnAttributeChanged: its icon follows its entry; a pick made by a row is logged and saved, at
-- once out of combat, at combat end in it.
local function attributeChanged(self, name, value)
    if name ~= "entry" then
        return
    end
    local e = byId[value]
    self.icon:SetTexture(e and e.icon or UNKNOWN_ICON)
    if applying then
        return
    end
    local fighting = inCombat()
    log(("flyout pick: %s combat=%s"):format(tostring(value), tostring(fighting)))
    if fighting then
        combatPick = value
    else
        combatPick = nil
        ns.ClassMacros.SetPick(value)
    end
end

-- Without the secure handler APIs: the arrow toggles the list and a row's click picks it, out of combat only.
local function insecureToggle()
    if inCombat() then
        return
    end
    if list:IsShown() then
        list:Hide()
    else
        list:Show()
    end
end

local function insecurePick(self)
    local id = call(self.GetAttribute, self, "entry")
    if inCombat() then
        log(("flyout pick: %s combat=true skipped"):format(tostring(id)))
        return
    end
    main:SetAttribute("macrotext", self:GetAttribute("macrotext"))
    main:SetAttribute("entry", id)
    list:Hide()
end

local function insecureClose()
    if not inCombat() then
        list:Hide()
    end
end

-- Hands the arrow, the rows and the main button the insecure, out-of-combat-only handlers; their OnClick replaces
-- the arrow template's.
local function useInsecure()
    secure = false
    arrow:SetScript("OnClick", insecureToggle)
    main:SetScript("PreClick", insecureClose)
    for _, row in ipairs(rows) do
        row:SetScript("PreClick", insecurePick)
    end
end

-- Gives b its icon, glow and count, its tooltip and drag; clicks on mouse-up only (useOnKeyDown false, set by
-- Update out of combat), so a drag that ends over a button casts nothing.
local function decorate(b)
    b:SetSize(SIZE, SIZE)
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
end

-- Anchors the arrow, list and rows and hands the secure snippets their frames; out of combat, once.
local function wire()
    if wired then
        return
    end
    wired = true
    arrow:ClearAllPoints()
    arrow:SetPoint("BOTTOM", main, "TOP", 0, 2)
    list:ClearAllPoints()
    list:SetPoint("BOTTOM", arrow, "TOP", 0, 2)
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("BOTTOM", list, "BOTTOM", 0, (i - 1) * (SIZE + GAP))
    end
    if not secure then
        return
    end
    local ok, err = pcall(function()
        arrow:SetAttribute("_onclick", Flyout.SNIPPETS.arrow)
        SecureHandlerSetFrameRef(arrow, "list", list)
        SecureHandlerSetFrameRef(list, "main", main)
        for _, row in ipairs(rows) do
            SecureHandlerWrapScript(row, "OnClick", list, Flyout.SNIPPETS.row)
        end
        SecureHandlerWrapScript(main, "OnClick", list, Flyout.SNIPPETS.main)
    end)
    if not ok then
        log("flyout wire failed, out of combat only: " .. tostring(err))
        useInsecure()
    end
end

-- Flyout.Made() -> bool: whether the flyout exists.
function Flyout.Made()
    return main ~= nil
end

-- Flyout.NextX() -> x: the BOTTOMRIGHT x offset for the right edge of a button left of the shown main button, or
-- Rod.NextX() while it is hidden; the y offset is the rod button's.
function Flyout.NextX()
    local x = ns.Rod.NextX()
    if main and call(main.IsShown, main) == true then
        x = x - SIZE - GAP
    end
    return x
end

-- Refreshes the rows, the main button's pick, place and visibility, the existing entry macros and the lights; in
-- combat only marks the change as pending. Runs after every Rod.Update, whose button it sits beside. A pick made in
-- combat is saved first.
function Flyout.Update()
    if not main then
        return
    end
    if inCombat() then
        pending = true
        return
    end
    pending, macroPending = nil, nil
    wire()
    if combatPick then
        ns.ClassMacros.SetPick(combatPick)
        log(("flyout pick saved: %s"):format(combatPick))
        combatPick = nil
    end
    entries, byId = ns.ClassMacros.List(classFile), {}
    for _, e in ipairs(entries) do
        byId[e.id] = e
    end
    for i, row in ipairs(rows) do
        local e = entries[i]
        row:SetAttribute("useOnKeyDown", false)
        if e then
            row:SetAttribute("type", "macro")
            row:SetAttribute("macrotext", e.cast)
            row:SetAttribute("entry", e.id)
            row.icon:SetTexture(e.icon or UNKNOWN_ICON)
            row:Show()
        else
            row:SetAttribute("entry", nil)
            row:Hide()
        end
    end
    list:SetSize(SIZE, math.max(1, #entries) * (SIZE + GAP) - GAP)
    local pick = ns.ClassMacros.Pick()
    local x = ns.Rod.NextX()
    main:SetAttribute("useOnKeyDown", false)
    if on and pick then
        main:SetAttribute("type", "macro")
        main:SetAttribute("macrotext", pick.cast)
        applying = true
        main:SetAttribute("entry", pick.id)
        applying = nil
        main.icon:SetTexture(pick.icon or UNKNOWN_ICON)
        main:ClearAllPoints()
        main:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, ns.BagButton.OFFSET_Y + ns.Layout.MicroRoom())
        main:Show()
    else
        list:Hide()
        main:Hide()
    end
    for _, e in ipairs(entries) do
        ensureMacro(e, false)
    end
    Flyout.Light()
    local ids = {}
    for i, e in ipairs(entries) do
        ids[i] = e.id
    end
    local line = ("flyout update: on=%s shown=%s pick=%s x=%s"):format(tostring(on == true), table.concat(ids, ","),
        tostring(on and pick and pick.id), tostring(x))
    if line ~= lastUpdate then
        lastUpdate = line
        log(line)
    end
end

-- PLAYER_REGEN_DISABLED: without the secure handler APIs the list cannot close in combat, so it closes now.
function Flyout.OnCombatStart()
    if main and not secure then
        list:Hide()
    end
end

-- PLAYER_REGEN_ENABLED: saves the pick made in combat, applies the change combat held back and reads the debuffs
-- again.
function Flyout.OnCombatEnd()
    if pending or macroPending or combatPick then
        Flyout.Update()
    end
    ns.Cure.Scan()
end

local function make(kind, name, parent, template)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if not ok then
        log("flyout login: CreateFrame failed: " .. tostring(frame))
        return nil
    end
    return frame
end

-- PLAYER_LOGIN: makes the main button, the arrow, the list and one row per class entry (never later, so never first
-- made in combat), then shows and lights them. A class without entries gets none. Runs before Rod.OnLogin, whose
-- update places them. Returns whether the flyout exists, so the caller listens to aura events.
function Flyout.OnLogin()
    local _, class = call(UnitClass, "player")
    local defined = class and ns.ClassMacros.ENTRIES[class]
    local ready = ns.Check.Ready("Class macro button")
    if not defined or main or type(CreateFrame) ~= "function" or not ready then
        log(("flyout login: class=%s ready=%s"):format(tostring(class), tostring(ready)))
        return main ~= nil
    end
    classFile, secure = class, ns.Check.Ready("Class macros")
    local m = make("Button", "TandemClassMacroButton", UIParent, "SecureActionButtonTemplate")
    local a = m and make("Button", "TandemClassMacroArrow", m, secure and "SecureHandlerClickTemplate" or nil)
    local l = a and make("Frame", "TandemClassMacroList", m, secure and "SecureHandlerBaseTemplate" or nil)
    if not l then
        return false
    end
    main, arrow, list = m, a, l
    main:SetFrameStrata("MEDIUM")
    decorate(main)
    main:SetScript("OnAttributeChanged", attributeChanged)
    arrow:SetSize(SIZE, ARROW)
    arrow:RegisterForClicks("AnyUp")
    arrow:SetNormalTexture("Interface\\Buttons\\Arrow-Up-Up")
    arrow:SetPushedTexture("Interface\\Buttons\\Arrow-Up-Down")
    arrow:SetScript("OnEnter", arrowTooltip)
    arrow:SetScript("OnLeave", ns.View.HideTooltip)
    list:Hide()
    for i in ipairs(defined) do
        local row = make("Button", "TandemClassMacroRow" .. i, list, "SecureActionButtonTemplate")
        if not row then
            break
        end
        rows[i] = row
        decorate(row)
    end
    if not secure then
        useInsecure()
    end
    log(("flyout login: class=%s ready=true secure=%s rows=%d"):format(class, tostring(secure), #rows))
    -- A /reload in combat leaves the new buttons as made (no attributes, so a click casts nothing) until combat ends.
    Flyout.Update()
    ns.Cure.Scan()
    return true
end

-- Listens after the rod button's listener (Flyout.lua follows Rod.lua in the toc), so Rod.NextX() is already current.
ns.Layout.OnChange(function(layoutOn)
    on = layoutOn
    Flyout.Update()
end)
