local _, ns = ...

-- The bag row (stage 12, D5, D12): one row of icon buttons at the bottom right while the Tandem layout is on, the
-- general bags first, then one icon per profession bag family, each with its free/total on its lower edge. A click
-- on any icon opens all bags, the reagent bag included. The default bag bar is faded through Layout.Conceal, never
-- hidden. At login Tandem turns on combined bags and points the "open all bags" key (B) at the same opener through an
-- override binding (no hook). The opener and the icons are secure action buttons whose macro clicks the default bag
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
local WHITE, YELLOW, RED = { 1, 1, 1 }, { 1, 0.82, 0 }, { 1, 0.1, 0.1 }

-- The key binding actions whose keys open all bags through Tandem's opener.
local BAG_ACTIONS = { "OPENALLBAGS", "TOGGLEBACKPACK" }

local row, on, opener, pendingBind, pendingLayout
local width = 0
local icons = {}

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
    for _, icon in ipairs(icons) do
        icon:SetAttribute("macrotext", text)
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

local function bagIcon(bag)
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
                    group = { family = family, free = 0, total = 0, icon = bagIcon(bag), names = {} }
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
            icon = bagIcon(reagent), names = { bagName(reagent) } }
    end
    return general, families
end

local function countColor(free)
    if free == 0 then
        return RED
    end
    return free < LOW and YELLOW or WHITE
end

local function showTooltip(icon)
    local tip, group = GameTooltip, icon.group
    if type(tip) ~= "table" or not group then
        return
    end
    local L = ns.L
    tip:SetOwner(icon, "ANCHOR_TOPLEFT")
    tip:SetText(group.family == 0 and L["General bags"] or group.family == "reagent" and L["Reagent bag"]
        or L["Profession bag"])
    if #group.names > 0 then
        tip:AddLine(table.concat(group.names, ", "), 1, 1, 1)
    end
    tip:AddLine(L["%d/%d free"]:format(group.free, group.total), 1, 1, 1)
    tip:AddLine(L["Click to open your bags"], 0.5, 0.5, 0.5)
    tip:Show()
end

local hideTooltip = ns.View.HideTooltip

-- Returns icon i, made on first use as a secure action button running the opener's macro; out of combat only.
local function iconButton(i)
    local icon = icons[i]
    if icon then
        return icon
    end
    icon = secureButton(nil, row)
    if not icon then
        return nil
    end
    icon:SetSize(SIZE, SIZE)
    icon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(i - 1) * (SIZE + SPACING), 0)
    icon.icon = icon:CreateTexture(nil, "ARTWORK")
    icon.icon:SetAllPoints(icon)
    icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.count:SetPoint("BOTTOM", icon, "BOTTOM", 0, 1)
    icon:SetAttribute("macrotext", BagButton.Macro())
    icon:SetScript("OnEnter", showTooltip)
    icon:SetScript("OnLeave", hideTooltip)
    icons[i] = icon
    return icon
end

-- Shows group on icon: its texture and free/total count, coloured.
local function paint(icon, group)
    icon.group = group
    icon.icon:SetTexture(group.icon)
    icon.count:SetText(("%d/%d"):format(group.free, group.total))
    local color = countColor(group.free)
    icon.count:SetTextColor(color[1], color[2], color[3])
end

local function create()
    row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("MEDIUM")
    row:Hide()
end

-- Refreshes the icons and counts, reusing the icon buttons; hides the row while the layout is off or the client
-- lacks the bag API. The icons are secure buttons, so in combat only the shown icons' textures and counts change;
-- adding, hiding or moving icons waits for the end of combat.
function BagButton.Update()
    if not row then
        return
    end
    local general, families = BagButton.Count()
    local groups = { general }
    for _, group in ipairs(families) do
        groups[#groups + 1] = group
    end
    if call(InCombatLockdown) then
        pendingLayout = true
        if on then
            for i, group in ipairs(groups) do
                local icon = icons[i]
                if icon and icon.group then
                    paint(icon, group)
                end
            end
        end
        return
    end
    pendingLayout = nil
    if not on then
        width = 0
        row:Hide()
        return
    end
    local shown = 0
    for i, group in ipairs(groups) do
        local icon = iconButton(i)
        if icon then
            paint(icon, group)
            icon:Show()
            shown = i
        end
    end
    for i = shown + 1, #icons do
        icons[i].group = nil
        icons[i]:Hide()
    end
    setMacros()
    width = shown > 0 and shown * SIZE + (shown - 1) * SPACING or 0
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
