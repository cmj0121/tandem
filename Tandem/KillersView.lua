local _, ns = ...

-- The killers window (killers D7): opened by a right-click on the minimap button or the compartment entry, it lists the
-- character's killers newest first, ROWS at a time with the mouse wheel scrolling the rest, each row with a forget
-- button, and a Clear button that clears only on a second click within CONFIRM seconds. Only Tandem's own plain frames.
local KillersView = {}
ns.KillersView = KillersView

local ROWS = 12
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 18
local WIDTH = 610
local CONFIRM = 3
local L = ns.L
local call = ns.Store.Call

local window
local offset = 0

-- The table's columns after the name, in order: key, header, width and justification. A missing value shows blank,
-- so every row keeps the same columns (killers D5).
KillersView.COLUMNS = {
    { key = "class", header = "Class", width = 70, justify = "LEFT" },
    { key = "level", header = "Level", width = 32, justify = "RIGHT" },
    { key = "count", header = "Kills", width = 36, justify = "RIGHT" },
    { key = "last", header = "Last killed", width = 110, justify = "LEFT" },
    { key = "zone", header = "Zone", width = 130, justify = "LEFT" },
}
local NAME_WIDTH = 140
local GAP = 8

-- The fields of killer k after its name for the chat line: "<class> <level>", "x<count>", the date of the last one and
-- the zone, each left out when missing (killers D5).
function KillersView.Details(k)
    local names = LOCALIZED_CLASS_NAMES_MALE
    local who = {}
    who[#who + 1] = k.class and (type(names) == "table" and names[k.class] or k.class) or nil
    who[#who + 1] = k.level and tostring(k.level) or nil
    local parts = {}
    parts[#parts + 1] = #who > 0 and table.concat(who, " ") or nil
    parts[#parts + 1] = "x" .. k.count
    parts[#parts + 1] = call(date, "%Y-%m-%d %H:%M", k.last)
    parts[#parts + 1] = k.zone
    return parts
end

-- The cells of killer k after its name in the window, one per column: the class name, the level, the count, the
-- date of the last one and the zone, each "" when missing.
function KillersView.Cells(k)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return {
        class = k.class and (type(names) == "table" and names[k.class] or k.class) or "",
        level = k.level and tostring(k.level) or "",
        count = tostring(k.count),
        last = call(date, "%Y-%m-%d %H:%M", k.last) or "",
        zone = k.zone or "",
    }
end

local function now()
    return tonumber((call(GetTime))) or 0
end

-- The character key when the list can be read and changed, else nil.
local function charKey()
    local key = ns.Weights.CharacterKey()
    if key and not ns.Store.readOnly then
        return key
    end
end

local function label(button, text)
    button.label:SetText(text)
end

local function newButton(parent, width, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label(b, text)
    return b
end

-- Puts the Clear button back to its first state.
local function disarm()
    window.clear.armedUntil = nil
    window.clear:SetScript("OnUpdate", nil)
    label(window.clear, L["Clear"])
end

local render

local function forget(row)
    local key = charKey()
    if key and row.fullName then
        ns.Store.ForgetKiller(key, row.fullName)
    end
    render()
end

-- First click arms the button for CONFIRM seconds; a second click while armed clears the list.
local function clearClick(button)
    if button.armedUntil and now() <= button.armedUntil then
        local key = charKey()
        if key then
            ns.Store.ClearKillers(key)
        end
        disarm()
        render()
        return
    end
    button.armedUntil = now() + CONFIRM
    label(button, L["Click again to clear"])
    button:SetScript("OnUpdate", function(self)
        if not self.armedUntil or now() > self.armedUntil then
            disarm()
        end
    end)
end

-- Lays out the name (in nameFont) and one font string per column (in font) on row, left to right, each fixed width
-- and on one line, so the columns line up row to row and a long value is cut instead of wrapping.
local function addCells(row, nameFont, font)
    row.name = row:CreateFontString(nil, "OVERLAY", nameFont)
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cells = {}
    local x = NAME_WIDTH + GAP
    for _, col in ipairs(KillersView.COLUMNS) do
        local cell = row:CreateFontString(nil, "OVERLAY", font)
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        cell:SetWidth(col.width)
        cell:SetJustifyH(col.justify)
        cell:SetWordWrap(false)
        row.cells[col.key] = cell
        x = x + col.width + GAP
    end
end

-- The header row above the list: the column titles in the gold small font.
local function newHeader(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 24, HEADER_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -36)
    addCells(row, "GameFontNormalSmall", "GameFontNormalSmall")
    row.name:SetText(L["Name"])
    for _, col in ipairs(KillersView.COLUMNS) do
        row.cells[col.key]:SetText(L[col.header])
    end
    return row
end

local function newRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 24, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -36 - HEADER_HEIGHT - (i - 1) * ROW_HEIGHT)
    addCells(row, "GameFontNormal", "GameFontHighlightSmall")
    row.forget = CreateFrame("Button", nil, row)
    row.forget:SetSize(18, 18)
    row.forget:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.forget:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    row.forget:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    row.forget:SetScript("OnClick", function()
        forget(row)
    end)
    return row
end

local function showRow(row, k)
    row.fullName = k.fullName
    row.name:SetText(k.fullName)
    local colour = type(RAID_CLASS_COLORS) == "table" and k.class and RAID_CLASS_COLORS[k.class]
    if type(colour) == "table" and colour.r then
        row.name:SetTextColor(colour.r, colour.g, colour.b)
    else
        row.name:SetTextColor(1, 1, 1)
    end
    local cells = KillersView.Cells(k)
    for _, col in ipairs(KillersView.COLUMNS) do
        row.cells[col.key]:SetText(cells[col.key])
    end
    row:Show()
end

-- Shows the list from offset, or the reason there is none.
render = function()
    local key = charKey()
    local list = key and ns.Store.Killers(key) or {}
    offset = math.max(0, math.min(offset, #list - ROWS))
    for i, row in ipairs(window.rows) do
        local k = list[offset + i]
        if k then
            showRow(row, k)
        else
            row.fullName = nil
            row:Hide()
        end
    end
    window.status:SetText(not key and L["Killer list unavailable."] or #list == 0 and L["No one recorded yet."] or "")
    window.range:SetText(#list > ROWS and ("%d-%d / %d"):format(offset + 1, offset + ROWS, #list) or "")
    window.clear:SetShown(key ~= nil and #list > 0)
    if not window.clear:IsShown() then
        disarm()
    end
end

local function build()
    local f = CreateFrame("Frame", "TandemKillersFrame", UIParent)
    f:SetSize(WIDTH, 36 + HEADER_HEIGHT + ROWS * ROW_HEIGHT + 40)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.85)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -10)
    f.title:SetText(L["Killers"])
    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(24, 24)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    f.close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    f.close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    f.close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    f.close:SetScript("OnClick", function()
        f:Hide()
    end)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.status:SetPoint("TOP", f, "TOP", 0, -36 - HEADER_HEIGHT - 24)
    f.header = newHeader(f)
    f.rows = {}
    for i = 1, ROWS do
        f.rows[i] = newRow(f, i)
    end
    f.range = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.range:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 14)
    f.clear = newButton(f, 160, L["Clear"])
    f.clear:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    f.clear:SetScript("OnClick", clearClick)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - (tonumber(delta) or 0)
        render()
    end)
    f:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "TandemKillersFrame")
    end
    return f
end

-- Shows the window, built on first use, or hides it.
function KillersView.Toggle()
    window = window or build()
    if window:IsShown() then
        window:Hide()
    else
        offset = 0
        render()
        window:Show()
    end
end

-- Redraws the list after a change; does nothing until the window was built.
function KillersView.Refresh()
    if window then
        render()
    end
end
