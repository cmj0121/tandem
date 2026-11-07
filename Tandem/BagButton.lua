local _, ns = ...

-- The bag button (stage 12, D2, D5): a plain Button at the bottom right while the Tandem layout is on, showing the
-- general bags' free/total and one N/M line per profession bag family behind that bag's icon. A click opens all bags.
-- The default bag bar is faded through Layout.Conceal, never hidden.
local BagButton = {}
ns.BagButton = BagButton

local OFFSET_X, OFFSET_Y = -12, 8
local ICON_SIZE, LINE_HEIGHT = 20, 12
local BAGS = 4
local BACKPACK = "Interface\\Buttons\\Button-Backpack-Up"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local button, on

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

local function bagIcon(bag)
    local inv = call(api("ContainerIDToInventoryID"), bag)
    local icon = inv and call(_G.GetInventoryItemTexture, "player", inv)
    return icon or UNKNOWN_ICON
end

local function bagName(bag)
    local name = call(api("GetBagName"), bag)
    return type(name) == "string" and name or nil
end

-- Returns the general group { free, total } and the profession groups { family, free, total, icon, name } in family
-- order, for bags 0..4; bags without slots are skipped.
function BagButton.Count()
    local numSlots, numFree = api("GetContainerNumSlots"), api("GetContainerNumFreeSlots")
    local general, byFamily, families = { free = 0, total = 0 }, {}, {}
    for bag = 0, BAGS do
        local total = number(call(numSlots, bag))
        if total > 0 then
            local free, family = call(numFree, bag)
            free, family = number(free), bag == 0 and 0 or number(family)
            local group = general
            if family ~= 0 then
                group = byFamily[family]
                if not group then
                    group = { family = family, free = 0, total = 0, icon = bagIcon(bag), name = bagName(bag) }
                    byFamily[family] = group
                    families[#families + 1] = group
                end
            end
            group.free, group.total = group.free + free, group.total + total
        end
    end
    table.sort(families, function(a, b)
        return a.family < b.family
    end)
    return general, families
end

local function slots(group)
    return ("%d/%d"):format(group.free, group.total)
end

local function iconText(icon)
    return ("|T%s:0|t"):format(icon)
end

local function showTooltip(owner)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    local general, families = BagButton.Count()
    tip:SetOwner(owner, "ANCHOR_TOPLEFT")
    tip:SetText(L["Bags"])
    tip:AddLine(iconText(BACKPACK) .. " " .. L["General bags: %d/%d free"]:format(general.free, general.total), 1, 1, 1)
    for _, group in ipairs(families) do
        tip:AddLine(iconText(group.icon) .. " " .. L["%s: %d/%d free"]:format(group.name or L["Profession bag"],
            group.free, group.total), 1, 1, 1)
    end
    tip:AddLine(L["Click to open your bags"], 0.5, 0.5, 0.5)
    tip:Show()
end

local function hideTooltip()
    if type(GameTooltip) == "table" then
        GameTooltip:Hide()
    end
end

local function create()
    button = CreateFrame("Button", nil, UIParent)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", OFFSET_X, OFFSET_Y)
    button:RegisterForClicks("LeftButtonUp")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(ICON_SIZE, ICON_SIZE)
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetTexture(BACKPACK)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 4, 0)
    button.text:SetJustifyH("LEFT")
    button:SetScript("OnClick", function()
        ToggleAllBags()
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    button:Hide()
end

-- Refreshes the counts; hides the button while the layout is off or the client lacks the bag API.
function BagButton.Update()
    if not button then
        return
    end
    if not on then
        button:Hide()
        return
    end
    local general, families = BagButton.Count()
    local lines = { slots(general) }
    for _, group in ipairs(families) do
        lines[#lines + 1] = iconText(group.icon) .. " " .. slots(group)
    end
    button.text:SetText(table.concat(lines, "\n"))
    button:SetSize(ICON_SIZE + 10 + (button.text:GetStringWidth() or 0),
        math.max(ICON_SIZE + 4, #lines * LINE_HEIGHT + 4))
    button:Show()
end

local function onChange(layoutOn)
    on = layoutOn and ns.Check.Ready("Bag button") and api("GetContainerNumSlots") ~= nil
    if on then
        if type(_G.BagsBar) == "table" then
            ns.Layout.Conceal("BagsBar")
        end
        if not button then
            create()
        end
    end
    BagButton.Update()
end

ns.Layout.OnChange(onChange)
