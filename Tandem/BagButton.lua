local _, ns = ...

-- The bag row (stage 12, D5, D12): a row of icon buttons at the bottom right while the Tandem layout is on: a
-- reload icon rightmost, then one bag icon with the free/total of every bag (general, profession and reagent)
-- summed on its lower edge and each part in its tooltip. A click on the bag icon opens all bags, the reagent bag
-- included. The default bag bar is faded through Layout.Conceal, never
-- hidden. At login Tandem turns on combined bags and points the "open all bags" key (B) at the same opener through an
-- override binding (no hook). The opener and the bag icon are secure action buttons whose macro clicks the default bag
-- buttons, so Blizzard's code, never Tandem's, opens the bag windows (see BagButton.Macro).
local BagButton = {}
ns.BagButton = BagButton

local OFFSET_X, OFFSET_Y = -12, 8
-- The row's anchor offsets from the bottom-right corner, for the fishing rod button to its left.
BagButton.OFFSET_X, BagButton.OFFSET_Y = OFFSET_X, OFFSET_Y
local SIZE, SPACING = 28, 4
local BAGS = 4
local LOW = 10
local BACKPACK = "Interface\\Icons\\INV_Misc_Bag_08"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local RELOAD_ICON = "Interface\\Buttons\\UI-RefreshButton"
local WHITE, YELLOW, RED = { 1, 1, 1 }, { 1, 0.82, 0 }, { 1, 0.1, 0.1 }

-- The key binding actions whose keys open all bags through Tandem's opener.
local BAG_ACTIONS = { "OPENALLBAGS", "TOGGLEBACKPACK" }

local row, on, opener, pendingBind, pendingLayout, bagIcon, reloadIcon
local width = 0

local call = ns.Store.Call

local function number(v)
    return type(v) == "number" and v or 0
end

local function api(name)
    local c = type(C_Container) == "table" and C_Container or {}
    return c[name] or _G[name]
end

-- The reagent bag's container index, or nil on a client without one.
local function reagentBag()
    local v = ns.Check.Get("Enum.BagIndex.ReagentBag")
    return type(v) == "number" and v or nil
end

local function bagOpen(bag)
    return call(_G.IsBagOpen, bag) and true or false
end

-- Whether the main bag window (combined, or the backpack) is open.
local function mainOpen()
    local combined = _G.ContainerFrameCombinedBags
    if type(combined) == "table" and call(combined.IsShown, combined) then
        return true
    end
    return bagOpen(0)
end

-- The default bag buttons the opener clicks: the backpack button (with combined bags on it opens the one window with
-- every bag) and the reagent bag slot.
local BACKPACK_BUTTON, REAGENT_SLOT = "MainMenuBarBackpackButton", "CharacterReagentBag0Slot"

-- Returns the opener's macro: a /click on the default backpack button, then one on the reagent bag slot when the
-- reagent bag has slots and the client has that button. Blizzard's own click handlers open the bags, so the bag
-- windows are never built by Tandem's code: opening them from addon code (ToggleAllBags, OpenBag) taints them, and
-- a later right-click on a bag item is then blocked ("Interface action failed because of an AddOn").
function BagButton.Macro()
    local lines = { "/click " .. BACKPACK_BUTTON }
    local reagent = reagentBag()
    if reagent and number(call(api("GetContainerNumSlots"), reagent)) > 0 and type(_G[REAGENT_SLOT]) == "table" then
        lines[2] = "/click " .. REAGENT_SLOT
    end
    return table.concat(lines, "\n")
end

-- After a click, logs the bag windows' state on the next frame to the debug recorder; reads only.
local function logClick()
    if not ns.Debug.IsOn() then
        return
    end
    local function log(when)
        local reagent = reagentBag()
        ns.Debug.Log(("bags %s: main %s reagent %s"):format(when, tostring(mainOpen()),
            tostring(reagent and bagOpen(reagent))))
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            log("next frame")
        end)
    else
        log("now")
    end
end

-- Makes a secure action button that runs the opener's macro on mouse or key up; nil when the client refuses it.
local function secureButton(name, parent)
    local ok, b = pcall(CreateFrame, "Button", name, parent, "SecureActionButtonTemplate")
    if not ok or type(b) ~= "table" then
        ns.Debug.Log("bags: CreateFrame failed: " .. tostring(b))
        return nil
    end
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type", "macro")
    b:SetScript("PostClick", logClick)
    return b
end

-- Gives the opener and every icon the current macro; out of combat only (the caller checks).
local function setMacros()
    local text = BagButton.Macro()
    if opener then
        opener:SetAttribute("macrotext", text)
    end
    if bagIcon then
        bagIcon:SetAttribute("macrotext", text)
    end
end

-- Points every key bound to "open all bags" or "open backpack" (B is either, by client) at Tandem's secure opener
-- with an override binding; waits for the end of combat, when bindings and secure buttons cannot change.
local function bindKeys()
    if type(CreateFrame) ~= "function" or type(_G.SetOverrideBindingClick) ~= "function"
        or not ns.Check.Ready("Bag button") then
        return
    end
    if call(InCombatLockdown) then
        pendingBind = true
        return
    end
    pendingBind = nil
    if not opener then
        opener = secureButton("TandemOpenAllBags", UIParent)
        if not opener then
            return
        end
    end
    setMacros()
    pcall(_G.ClearOverrideBindings, opener)
    local bound = {}
    for _, action in ipairs(BAG_ACTIONS) do
        local keys = { pcall(_G.GetBindingKey, action) }
        for i = 2, #keys do
            if type(keys[i]) == "string" then
                pcall(_G.SetOverrideBindingClick, opener, false, keys[i], "TandemOpenAllBags")
                bound[#bound + 1] = keys[i]
            end
        end
    end
    ns.Debug.Log("bags: open-all keys bound: " .. (#bound > 0 and table.concat(bound, " ") or "none"))
end

-- Binds the keys and lays out the row as deferred by combat.
function BagButton.OnCombatEnd()
    if pendingBind then
        bindKeys()
    end
    if pendingLayout then
        BagButton.Update()
    end
end

-- At login: turns on the client's combined bags (the "combinedBags" CVar), so B and the bag row open one bag
-- window with every bag. Only sets a CVar the client has; the player can still switch it off in the options, and it
-- comes back on at the next login.
function BagButton.OnLogin()
    local v = ns.Store.GetCVar("combinedBags")
    if type(v) == "string" and v ~= "1" then
        ns.Store.SetCVar("combinedBags", "1")
    end
    bindKeys()
end

local function bagTexture(bag)
    local inv = call(api("ContainerIDToInventoryID"), bag)
    local icon = inv and call(_G.GetInventoryItemTexture, "player", inv)
    return icon or UNKNOWN_ICON
end

local function bagName(bag)
    local name = call(api("GetBagName"), bag)
    return type(name) == "string" and name or nil
end

-- Returns the general group and the profession groups in family order, each { family, free, total, icon, names }
-- for bags 0..4, then the reagent bag as its own group (family "reagent") when it has slots; bags without slots are
-- skipped and names lists the bag names the client gives.
function BagButton.Count()
    local numSlots, numFree = api("GetContainerNumSlots"), api("GetContainerNumFreeSlots")
    local general = { family = 0, free = 0, total = 0, icon = BACKPACK, names = {} }
    local byFamily, families = {}, {}
    for bag = 0, BAGS do
        local total = number(call(numSlots, bag))
        if total > 0 then
            local free, family = call(numFree, bag)
            free, family = number(free), bag == 0 and 0 or number(family)
            local group = general
            if family ~= 0 then
                group = byFamily[family]
                if not group then
                    group = { family = family, free = 0, total = 0, icon = bagTexture(bag), names = {} }
                    byFamily[family] = group
                    families[#families + 1] = group
                end
            end
            group.free, group.total = group.free + free, group.total + total
            group.names[#group.names + 1] = bagName(bag)
        end
    end
    table.sort(families, function(a, b)
        return a.family < b.family
    end)
    local reagent = reagentBag()
    local total = reagent and number(call(numSlots, reagent)) or 0
    if total > 0 then
        families[#families + 1] = { family = "reagent", free = number((call(numFree, reagent))), total = total,
            icon = bagTexture(reagent), names = { bagName(reagent) } }
    end
    return general, families
end

-- Returns the general group and every profession and reagent group merged into the one bag icon's group
-- { free, total, icon, groups }: free and total summed, the backpack icon, groups listing the parts in order.
function BagButton.Merge(general, families)
    local all = { free = general.free, total = general.total, icon = BACKPACK, groups = { general } }
    for _, group in ipairs(families) do
        all.free, all.total = all.free + group.free, all.total + group.total
        all.groups[#all.groups + 1] = group
    end
    return all
end

local function countColor(free)
    if free == 0 then
        return RED
    end
    return free < LOW and YELLOW or WHITE
end

local function groupLabel(group)
    local L = ns.L
    return group.family == 0 and L["General bags"] or group.family == "reagent" and L["Reagent bag"]
        or L["Profession bag"]
end

-- The bag icon's tooltip: each part's free/total and bag names, then the click hint.
local function showTooltip(icon)
    local tip, all = GameTooltip, icon.group
    if type(tip) ~= "table" or not all then
        return
    end
    local L = ns.L
    tip:SetOwner(icon, "ANCHOR_TOPLEFT")
    tip:SetText(L["Bags"])
    for _, group in ipairs(all.groups) do
        tip:AddLine(L["%s: %d/%d free"]:format(groupLabel(group), group.free, group.total), 1, 1, 1)
        if #group.names > 0 then
            tip:AddLine(table.concat(group.names, ", "), 0.7, 0.7, 0.7)
        end
    end
    tip:AddLine(L["Click to open your bags"], 0.5, 0.5, 0.5)
    tip:Show()
end

local hideTooltip = ns.View.HideTooltip

-- The client's reload function (C_UI.Reload, else the global ReloadUI), or nil.
local function reloadFn()
    local ui = _G.C_UI
    local fn = type(ui) == "table" and ui.Reload or nil
    if type(fn) ~= "function" then
        fn = _G.ReloadUI
    end
    return type(fn) == "function" and fn or nil
end

local function reloadTooltip(button)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    tip:SetOwner(button, "ANCHOR_TOPLEFT")
    tip:SetText(ns.L["Reload UI"])
    tip:AddLine(ns.L["Click to reload the interface"], 0.5, 0.5, 0.5)
    tip:Show()
end

local function reload()
    local fn = reloadFn()
    if fn then
        fn()
    end
end

-- Returns the reload icon, made on first use as a plain button (reloading is not protected); nil without a reload
-- function on the client.
local function reloadButton()
    if reloadIcon or not reloadFn() then
        return reloadIcon
    end
    reloadIcon = CreateFrame("Button", nil, row)
    reloadIcon:SetSize(SIZE, SIZE)
    reloadIcon:RegisterForClicks("LeftButtonUp")
    reloadIcon.icon = reloadIcon:CreateTexture(nil, "ARTWORK")
    reloadIcon.icon:SetAllPoints(reloadIcon)
    reloadIcon.icon:SetTexture(RELOAD_ICON)
    reloadIcon:SetScript("OnClick", reload)
    reloadIcon:SetScript("OnEnter", reloadTooltip)
    reloadIcon:SetScript("OnLeave", hideTooltip)
    return reloadIcon
end

-- Returns the bag icon, made on first use as a secure action button running the opener's macro; out of combat only.
local function bagButton()
    if bagIcon then
        return bagIcon
    end
    bagIcon = secureButton(nil, row)
    if not bagIcon then
        return nil
    end
    bagIcon:SetSize(SIZE, SIZE)
    bagIcon.icon = bagIcon:CreateTexture(nil, "ARTWORK")
    bagIcon.icon:SetAllPoints(bagIcon)
    bagIcon.count = bagIcon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    bagIcon.count:SetPoint("BOTTOM", bagIcon, "BOTTOM", 0, 1)
    bagIcon:SetAttribute("macrotext", BagButton.Macro())
    bagIcon:SetScript("OnEnter", showTooltip)
    bagIcon:SetScript("OnLeave", hideTooltip)
    return bagIcon
end

-- Shows the merged group on the bag icon: its texture and summed free/total count, coloured.
local function paint(icon, all)
    icon.group = all
    icon.icon:SetTexture(all.icon)
    icon.count:SetText(("%d/%d"):format(all.free, all.total))
    local color = countColor(all.free)
    icon.count:SetTextColor(color[1], color[2], color[3])
end

local function create()
    row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("MEDIUM")
    row:Hide()
end

-- Places button as the row's n-th icon from the right (n from 1).
local function place(button, n)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(n - 1) * (SIZE + SPACING), 0)
end

-- Refreshes the row: the reload icon rightmost, then the one bag icon with every bag's free/total; hides the row
-- while the layout is off or the client lacks the bag API. The bag icon is a secure button, so in combat only its
-- texture and count change; the row is laid out again when combat ends.
function BagButton.Update()
    if not row then
        return
    end
    local all = BagButton.Merge(BagButton.Count())
    if call(InCombatLockdown) then
        pendingLayout = true
        if on and bagIcon and bagIcon.group then
            paint(bagIcon, all)
        end
        return
    end
    pendingLayout = nil
    if not on then
        width = 0
        row:Hide()
        return
    end
    local n = 0
    for _, make in ipairs({ reloadButton, bagButton }) do
        local button = make()
        if button then
            n = n + 1
            place(button, n)
            button:Show()
        end
    end
    if bagIcon then
        paint(bagIcon, all)
    end
    setMacros()
    width = n > 0 and n * SIZE + (n - 1) * SPACING or 0
    row:SetSize(width, SIZE)
    row:Show()
end

-- BagButton.Width() -> number: the row's width as last laid out, 0 while it is hidden.
function BagButton.Width()
    return width
end

local function onChange(layoutOn)
    on = layoutOn and ns.Check.Ready("Bag button") and api("GetContainerNumSlots") ~= nil
    if on then
        if type(_G.BagsBar) == "table" then
            ns.Layout.Conceal("BagsBar")
        end
        if not row then
            create()
        end
        -- Above the micro menu, which the layout puts in the bottom-right corner.
        row:ClearAllPoints()
        row:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", OFFSET_X, OFFSET_Y + ns.Layout.MicroRoom())
    end
    BagButton.Update()
end

ns.Layout.OnChange(onChange)
