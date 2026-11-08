local _, ns = ...

-- The bag row (stage 12, D5, D12): one row of icon buttons at the bottom right while the Tandem layout is on, the
-- general bags first, then one icon per profession bag family, each with its free/total on its lower edge. A click
-- on any icon opens all bags. The default bag bar is faded through Layout.Conceal, never hidden.
local BagButton = {}
ns.BagButton = BagButton

local OFFSET_X, OFFSET_Y = -12, 8
local SIZE, SPACING = 28, 4
local BAGS = 4
local LOW = 10
local BACKPACK = "Interface\\Icons\\INV_Misc_Bag_08"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local WHITE, YELLOW, RED = { 1, 1, 1 }, { 1, 0.82, 0 }, { 1, 0.1, 0.1 }

local row, on
local icons = {}

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v, w = pcall(fn, ...)
    if ok then
        return ns.Store.Safe(v), ns.Store.Safe(w)
    end
end

local function number(v)
    return type(v) == "number" and v or 0
end

local function api(name)
    local c = type(C_Container) == "table" and C_Container or {}
    return c[name] or _G[name]
end

-- At login: turns on the client's combined bags (the "combinedBags" CVar), so B and the bag row open one bag
-- window with every bag. Only sets a CVar the client has; the player can still switch it off in the options, and it
-- comes back on at the next login.
function BagButton.OnLogin()
    local get = type(C_CVar) == "table" and C_CVar.GetCVar or GetCVar
    local set = type(C_CVar) == "table" and C_CVar.SetCVar or SetCVar
    local v = call(get, "combinedBags")
    if type(v) == "string" and v ~= "1" then
        pcall(set, "combinedBags", "1")
    end
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
-- for bags 0..4; bags without slots are skipped and names lists the bag names the client gives.
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
    tip:SetText(group.family == 0 and L["General bags"] or L["Profession bag"])
    if #group.names > 0 then
        tip:AddLine(table.concat(group.names, ", "), 1, 1, 1)
    end
    tip:AddLine(L["%d/%d free"]:format(group.free, group.total), 1, 1, 1)
    tip:AddLine(L["Click to open your bags"], 0.5, 0.5, 0.5)
    tip:Show()
end

local function hideTooltip()
    if type(GameTooltip) == "table" then
        GameTooltip:Hide()
    end
end

local function iconButton(i)
    local icon = icons[i]
    if icon then
        return icon
    end
    icon = CreateFrame("Button", nil, row)
    icon:SetSize(SIZE, SIZE)
    icon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(i - 1) * (SIZE + SPACING), 0)
    icon:RegisterForClicks("LeftButtonUp")
    icon.icon = icon:CreateTexture(nil, "ARTWORK")
    icon.icon:SetAllPoints(icon)
    icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.count:SetPoint("BOTTOM", icon, "BOTTOM", 0, 1)
    icon:SetScript("OnClick", function()
        ToggleAllBags()
    end)
    icon:SetScript("OnEnter", showTooltip)
    icon:SetScript("OnLeave", hideTooltip)
    icons[i] = icon
    return icon
end

local function create()
    row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("MEDIUM")
    row:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", OFFSET_X, OFFSET_Y)
    row:Hide()
end

-- Refreshes the icons and counts, reusing the icon buttons; hides the row while the layout is off or the client
-- lacks the bag API.
function BagButton.Update()
    if not row then
        return
    end
    if not on then
        row:Hide()
        return
    end
    local general, families = BagButton.Count()
    local groups = { general }
    for _, group in ipairs(families) do
        groups[#groups + 1] = group
    end
    for i, group in ipairs(groups) do
        local icon = iconButton(i)
        icon.group = group
        icon.icon:SetTexture(group.icon)
        icon.count:SetText(("%d/%d"):format(group.free, group.total))
        local color = countColor(group.free)
        icon.count:SetTextColor(color[1], color[2], color[3])
        icon:Show()
    end
    for i = #groups + 1, #icons do
        icons[i].group = nil
        icons[i]:Hide()
    end
    row:SetSize(#groups * SIZE + (#groups - 1) * SPACING, SIZE)
    row:Show()
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
    end
    BagButton.Update()
end

ns.Layout.OnChange(onChange)
