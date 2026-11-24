local _, ns = ...

-- The craft flyout (craft flyout D2, D3, D4): one secure button left of the class macro button while the layout is
-- on, making its picked entry (Crafts.Pick) with a left click and using the item it makes with a right click, with a
-- small arrow above it that opens an upward list of up to ROWS entries in Crafts.List order. A row click makes or uses
-- that entry and makes it the pick; secure snippets re-point the main button and close the list, so this works in
-- combat too. Without the secure handler APIs the list opens, picks and closes out of combat only. With no entries the
-- button shows a placeholder, makes nothing and its tooltip says how to fill the list. A recipe's left click casts
-- its profession, which opens the window; once that window is open and ready, a left click out of combat crafts one
-- instead (Crafts.TryCraft). Attributes, rows, place and visibility change only out of combat (a change asked for in
-- combat waits for CraftFlyout.OnCombatEnd).
local CraftFlyout = {}
ns.CraftFlyout = CraftFlyout

local call = ns.Store.Call

local SIZE, GAP, ARROW = 28, 4, 12
CraftFlyout.ROWS = 10
local PLACEHOLDER_ICON = "Interface\\Icons\\Trade_Engineering"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The restricted snippets: the arrow's _onclick toggles the list; a row's OnClick pre-wrap copies its make and use
-- attributes and entry to the main button and closes the list, then lets the click act (type1 is read back from
-- spell1, since a recipe row's PreClick may have cleared it for this click); the main button's pre-wrap closes the
-- list.
CraftFlyout.SNIPPETS = {
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
local spell = self:GetAttribute("spell1")
main:SetAttribute("type1", spell and "spell" or nil)
main:SetAttribute("spell1", spell)
main:SetAttribute("type2", self:GetAttribute("type2"))
main:SetAttribute("item2", self:GetAttribute("item2"))
main:SetAttribute("entry", self:GetAttribute("entry"))
owner:Hide()
]],
    main = [[
owner:Hide()
]],
}

local main, arrow, list
local rows = {}
local secure, wired, on, pending, lastUpdate, updating
-- Whether a click out of combat is between its PreClick and PostClick: a pick it makes is saved in PostClick, so the
-- Update that follows does not restore the type1 PreClick cleared before the click acts.
local clicking
-- The shown entries in row order, and by id.
local entries, byId = {}, {}
-- The entry id picked in combat, saved at combat end; whether Update itself is setting the main button's entry.
local combatPick, applying

local log = ns.Crafts.Log

local function inCombat()
    return call(InCombatLockdown) == true
end

local function entryOf(b)
    return byId[call(b.GetAttribute, b, "entry")]
end

-- The make (type1/spell1) and use (type2/item2) attributes for entry e, or none for nil.
local function apply(b, e)
    local spell = e and (e.kind == "recipe" and e.profession or e.spell) or nil
    b:SetAttribute("type1", spell and "spell" or nil)
    b:SetAttribute("spell1", spell)
    b:SetAttribute("type2", e and e.item and "item" or nil)
    b:SetAttribute("item2", e and e.item and ("item:" .. e.item) or nil)
end

local function itemName(item)
    local c = type(C_Item) == "table" and C_Item or {}
    local name = call(c.GetItemInfo or _G.GetItemInfo, item)
    return type(name) == "string" and name or nil
end

local function showTooltip(self)
    local tip, e = GameTooltip, entryOf(self)
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    if not e then
        tip:SetText(L["Craft button"])
        tip:AddLine(L["Cast an item-making spell or open a profession once to fill this list"], 1, 0.82, 0, true)
        tip:Show()
        return
    end
    tip:SetText(e.name)
    local made = e.item and itemName(e.item)
    if made then
        tip:AddLine(L["Makes %s"]:format(made), 1, 1, 1)
    end
    if e.kind == "recipe" then
        tip:AddLine(L["The first click opens the profession; the next one makes it"], 1, 0.82, 0, true)
    end
    tip:AddLine(L["Left click: make"], 0.5, 0.5, 0.5)
    if e.item then
        tip:AddLine(L["Right click: use"], 0.5, 0.5, 0.5)
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
    tip:SetText(L["Craft button"])
    if not secure and inCombat() then
        tip:AddLine(L["Choosing waits until combat ends"], 0.5, 0.5, 0.5)
    else
        tip:AddLine(L["Click to choose what the button makes"], 0.5, 0.5, 0.5)
    end
    tip:Show()
end

-- The main button's OnAttributeChanged: its icon follows its entry; a pick made by a row is logged and saved, at
-- the click's end out of combat, at combat end in it.
local function attributeChanged(self, name, value)
    if name ~= "entry" then
        return
    end
    local e = byId[value]
    self.icon:SetTexture(e and (e.icon or UNKNOWN_ICON) or PLACEHOLDER_ICON)
    if applying or value == nil then
        return
    end
    local fighting = inCombat()
    log(("craft flyout pick: %s combat=%s"):format(tostring(value), tostring(fighting)))
    if fighting or clicking then
        combatPick = value
    else
        combatPick = nil
        ns.Crafts.SetPick(value)
    end
end

-- Without the secure handler APIs: copies the row's attributes to the main button and closes the list.
local function insecurePick(row)
    local spell = row:GetAttribute("spell1")
    main:SetAttribute("type1", spell and "spell" or nil)
    main:SetAttribute("spell1", spell)
    main:SetAttribute("type2", row:GetAttribute("type2"))
    main:SetAttribute("item2", row:GetAttribute("item2"))
    main:SetAttribute("entry", row:GetAttribute("entry"))
    list:Hide()
end

-- PreClick (main button and rows): without the secure handlers, out of combat, closes the list (a row also picks);
-- then a recipe's left click out of combat crafts it when its window is ready, and clears type1 for this click so
-- the click does not cast the profession again (PostClick restores it).
local function preClick(self, button)
    if inCombat() then
        return
    end
    clicking = true
    local e = entryOf(self)
    if not secure then
        if self == main then
            list:Hide()
        else
            insecurePick(self)
        end
    end
    if button == "LeftButton" and e and e.kind == "recipe" and ns.Crafts.TryCraft(e) then
        self.restoreType = self:GetAttribute("type1")
        self:SetAttribute("type1", nil)
    end
end

local function postClick(self)
    if self.restoreType then
        self:SetAttribute("type1", self.restoreType)
        self.restoreType = nil
    end
    clicking = nil
    if combatPick and not inCombat() then
        CraftFlyout.Update()
    end
end

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

local function decorate(b)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", ns.View.HideTooltip)
    b:SetScript("PreClick", preClick)
    b:SetScript("PostClick", postClick)
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
        arrow:SetAttribute("_onclick", CraftFlyout.SNIPPETS.arrow)
        SecureHandlerSetFrameRef(arrow, "list", list)
        SecureHandlerSetFrameRef(list, "main", main)
        for _, row in ipairs(rows) do
            SecureHandlerWrapScript(row, "OnClick", list, CraftFlyout.SNIPPETS.row)
        end
        SecureHandlerWrapScript(main, "OnClick", list, CraftFlyout.SNIPPETS.main)
    end)
    if not ok then
        log("craft flyout wire failed, out of combat only: " .. tostring(err))
        secure = false
        arrow:SetScript("OnClick", insecureToggle)
    end
end

-- CraftFlyout.NextX() -> x: the BOTTOMRIGHT x offset for the right edge of a button left of the shown main button, or
-- Cure.NextX() while it is hidden; the y offset is the rod button's.
function CraftFlyout.NextX()
    local x = ns.Cure.NextX()
    if main and call(main.IsShown, main) == true then
        x = x - SIZE - GAP
    end
    return x
end

-- Refreshes the rows, the main button's pick, place and visibility; in combat only marks the change as pending. Runs
-- after every Flyout.Update, whose button it sits beside, and on every Crafts change. A pick made in combat is saved
-- first.
function CraftFlyout.Update()
    if not main or updating then
        return
    end
    if inCombat() then
        pending = true
        return
    end
    pending = nil
    updating = true
    wire()
    if combatPick then
        local id = combatPick
        combatPick = nil
        ns.Crafts.SetPick(id)
        log(("craft flyout pick saved: %s"):format(id))
    end
    entries, byId = {}, {}
    for i, e in ipairs(ns.Crafts.List()) do
        if i > CraftFlyout.ROWS then
            break
        end
        entries[i] = e
        byId[e.id] = e
    end
    for i, row in ipairs(rows) do
        local e = entries[i]
        row:SetAttribute("useOnKeyDown", false)
        apply(row, e)
        row:SetAttribute("entry", e and e.id or nil)
        if e then
            row.icon:SetTexture(e.icon or UNKNOWN_ICON)
            row:Show()
        else
            row:Hide()
        end
    end
    list:SetSize(SIZE, math.max(1, #entries) * (SIZE + GAP) - GAP)
    local pick = entries[1]
    local x = ns.Cure.NextX()
    main:SetAttribute("useOnKeyDown", false)
    if on then
        apply(main, pick)
        applying = true
        main:SetAttribute("entry", pick and pick.id or nil)
        applying = nil
        main.icon:SetTexture(pick and (pick.icon or UNKNOWN_ICON) or PLACEHOLDER_ICON)
        main:ClearAllPoints()
        main:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, ns.BagButton.OFFSET_Y + ns.Layout.MicroRoom())
        main:Show()
        if pick then
            arrow:Show()
        else
            arrow:Hide()
            list:Hide()
        end
    else
        list:Hide()
        main:Hide()
    end
    updating = nil
    local ids = {}
    for i, e in ipairs(entries) do
        ids[i] = e.id
    end
    local line = ("craft flyout update: on=%s shown=%s entries=%d pick=%s x=%s"):format(tostring(on == true),
        table.concat(ids, ","), #entries, tostring(on and pick and pick.id), tostring(x))
    if line ~= lastUpdate then
        lastUpdate = line
        log(line)
    end
end

-- PLAYER_REGEN_DISABLED: without the secure handler APIs the list cannot close in combat, so it closes now.
function CraftFlyout.OnCombatStart()
    if main and not secure then
        list:Hide()
    end
end

-- PLAYER_REGEN_ENABLED: saves the pick made in combat and applies the change combat held back.
function CraftFlyout.OnCombatEnd()
    if pending or combatPick then
        CraftFlyout.Update()
    end
end

local function make(kind, name, parent, template)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if not ok then
        log("craft flyout login: CreateFrame failed: " .. tostring(frame))
        return nil
    end
    return frame
end

-- PLAYER_LOGIN: makes the main button, the arrow, the list and ROWS rows (never later, so never first made in
-- combat), then shows them. Runs after Flyout.OnLogin and before Mute.OnLogin, whose button sits left of this one.
function CraftFlyout.OnLogin()
    local ready = ns.Check.Ready("Craft button")
    if main or type(CreateFrame) ~= "function" or not ready then
        log(("craft flyout login: made=false why=%s"):format(main and "made already"
            or not ready and "not ready" or "no CreateFrame"))
        return
    end
    secure = ns.Check.Ready("Class macros")
    local m = make("Button", "TandemCraftButton", UIParent, "SecureActionButtonTemplate")
    local a = m and make("Button", "TandemCraftArrow", m, secure and "SecureHandlerClickTemplate" or nil)
    local l = a and make("Frame", "TandemCraftList", m, secure and "SecureHandlerBaseTemplate" or nil)
    if not l then
        log("craft flyout login: made=false why=CreateFrame failed")
        return
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
    if not secure then
        arrow:SetScript("OnClick", insecureToggle)
    end
    list:Hide()
    for i = 1, CraftFlyout.ROWS do
        local row = make("Button", "TandemCraftRow" .. i, list, "SecureActionButtonTemplate")
        if not row then
            break
        end
        rows[i] = row
        decorate(row)
    end
    log(("craft flyout login: made=true secure=%s rows=%d"):format(tostring(secure), #rows))
    -- A /reload in combat leaves the new buttons as made (no attributes, so a click does nothing) until combat ends.
    CraftFlyout.Update()
end

ns.Crafts.OnChange(CraftFlyout.Update)

-- Listens after the class macro button's listener (CraftFlyout.lua follows Flyout.lua in the toc), so Cure.NextX() is
-- already current.
ns.Layout.OnChange(function(layoutOn)
    on = layoutOn
    CraftFlyout.Update()
end)
