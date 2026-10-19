local _, ns = ...

-- Red and yellow borders on the default Blizzard action buttons from SpellRanks (decisions 5 and 6). Each button gets
-- one child frame with a glow texture over it; the button's own secure attributes are never touched. Borders are
-- recomputed out of combat only: in combat they stay as they are and one refresh runs when combat ends.
local ActionBorders = {}
ns.ActionBorders = ActionBorders

local Safe = ns.Store.Safe

local BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local COLORS = {
    red = { 1, 0.15, 0.15 },
    yellow = { 1, 0.82, 0 },
}

-- The glow texture is drawn 62 pixels wide around a 36-pixel button, as Blizzard's equipped-item border is.
local GLOW = 62 / 36

-- Returns the action slot a button shows, or nil when it cannot be told.
local function slotOf(button)
    local slot = Safe(button.action)
    if type(slot) ~= "number" and ActionButton_GetPagedID then
        slot = Safe(ActionButton_GetPagedID(button))
    end
    if type(slot) ~= "number" and type(button.GetPagedID) == "function" then
        slot = Safe(button:GetPagedID())
    end
    return type(slot) == "number" and slot or nil
end

local function borderOf(button)
    local border = button.tandemBorder
    if not border then
        border = CreateFrame("Frame", nil, button)
        local size = (Safe(button:GetWidth()) or 36) * GLOW
        border:SetSize(size, size)
        border:SetPoint("CENTER", button, "CENTER")
        local texture = border:CreateTexture(nil, "OVERLAY")
        texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        texture:SetBlendMode("ADD")
        texture:SetAllPoints(border)
        border.texture = texture
        button.tandemBorder = border
    end
    return border
end

local function paint(button)
    local slot = slotOf(button)
    local color = slot and COLORS[ns.SpellRanks.State(slot)]
    if color then
        local border = borderOf(button)
        border.texture:SetVertexColor(color[1], color[2], color[3])
        border:Show()
    elseif button.tandemBorder then
        button.tandemBorder:Hide()
    end
end

local pending = false

-- Recomputes every default button's border out of combat; in combat it does nothing and the borders stay as they are.
function ActionBorders.Refresh()
    if (InCombatLockdown and InCombatLockdown()) or not ns.Check.Ready("Action bar borders") then
        return
    end
    ns.SpellRanks.Invalidate()
    for _, bar in ipairs(BARS) do
        for i = 1, 12 do
            local button = _G[bar .. i]
            if type(button) == "table" then
                paint(button)
            end
        end
    end
end

-- Bar, spell, level and trainer events, login and combat end: runs one Refresh on the next frame however many events
-- arrive before it, after Blizzard has updated the buttons' actions; at once when C_Timer is missing.
function ActionBorders.Schedule()
    if not (C_Timer and C_Timer.After) then
        ActionBorders.Refresh()
        return
    end
    if pending then
        return
    end
    pending = true
    C_Timer.After(0, function()
        pending = false
        ActionBorders.Refresh()
    end)
end
