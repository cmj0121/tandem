local _, ns = ...

-- The /tandem browse window: every known item for a slot, best first, with where the selected one drops.
local Browse = {}
ns.Browse = Browse

local L = ns.L
local View = ns.View
local Safe = ns.Store.Safe

local NAME = "TandemBrowseFrame"
local WIDTH, HEIGHT = 440, 520
local ROW_HEIGHT = 20
local PANE_HEIGHT = 110
local SOURCE_ROWS = 5
local REDRAW_DELAY = 0.2
local GREY, RED = "|cff808080", "|cffff2020"
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame
local slot, selected, pending
local requested = {}
local rows, listed, worn = {}, {}, {}

local function wornFor(rowSlot)
    worn[rowSlot] = worn[rowSlot] or View.Equipped(rowSlot)
    return worn[rowSlot]
end

-- Asks the client to load an item, once per session.
local function request(id)
    if not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
end

-- Returns the item's link once the client has it, else one built from its record.
local function linkOf(id)
    if C_Item and C_Item.GetItemInfo then
        local link = Safe((select(2, C_Item.GetItemInfo(id))))
        if type(link) == "string" then
            return link
        end
    end
    request(id)
    local r = ns.Advisor.Item(id)
    return View.BuiltLink(id, r and r[3])
end

-- Returns the item's name in its quality colour once the client has it; else "item #id" in the record's colour,
-- and asks the client to load it.
local function coloredName(row)
    local name, quality
    if C_Item and C_Item.GetItemInfo then
        local n, _, q = C_Item.GetItemInfo(row.id)
        name, quality = Safe(n), Safe(q)
    end
    if type(name) ~= "string" then
        request(row.id)
        name, quality = L["item #%d"]:format(row.id), row.quality
    end
    local hex = View.QUALITY_HEX[quality] or View.QUALITY_HEX[row.quality] or View.QUALITY_HEX[1]
    return ("|cff%s%s|r"):format(hex, View.Escape(name))
end

local function iconOf(id)
    local icon
    if C_Item and C_Item.GetItemInfoInstant then
        icon = Safe((select(5, C_Item.GetItemInfoInstant(id))))
    end
    return icon or NO_ICON
end

local function showIf(region, shown)
    if shown then
        region:Show()
    else
        region:Hide()
    end
end

local function updateSources()
    local pane = frame.pane
    local lines = {}
    if selected then
        pane.header:SetText(linkOf(selected))
        lines = View.SourceLines(selected, SOURCE_ROWS)
    else
        pane.header:SetText(L["Select an item to see where it drops"])
    end
    for i, fs in ipairs(pane.lines) do
        fs:SetText(lines[i] or "")
    end
end

local function onEnter(self)
    if GameTooltip and GameTooltip.SetItemByID and self.row then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.row.id)
        GameTooltip:Show()
    end
end

local function onLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function updateSelected(button)
    showIf(button.selected, button.row ~= nil and button.row.id == selected)
end

local function onClick(self)
    if not self.row then
        return
    end
    selected = self.row.id
    updateSources()
    frame.box:ForEachFrame(updateSelected)
end

local function buildRow(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
    button.icon:SetPoint("LEFT", button, "LEFT", 2, 0)
    button.level = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    button.level:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    button.level:SetWidth(36)
    button.level:SetJustifyH("RIGHT")
    button.ilvl = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    button.ilvl:SetPoint("RIGHT", button.level, "LEFT", -4, 0)
    button.ilvl:SetWidth(36)
    button.ilvl:SetJustifyH("RIGHT")
    button.name = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    button.name:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
    button.name:SetPoint("RIGHT", button.ilvl, "LEFT", -4, 0)
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)
    button.selected = button:CreateTexture(nil, "BACKGROUND")
    button.selected:SetAllPoints()
    button.selected:SetColorTexture(1, 0.82, 0, 0.2)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.1)
    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", onLeave)
    button:SetScript("OnClick", onClick)
    button.built = true
end

local function initRow(button, row)
    if not button.built then
        buildRow(button)
    end
    button.row = row
    local w = wornFor(row.slot)
    if not row.usable then
        w = { ids = w.ids, list = w.list }
    end
    local marks = View.Marks(row.id, row.ilvl, row.sourced, w)
    button.icon:SetTexture(iconOf(row.id))
    button.name:SetText(coloredName(row) .. (marks ~= "" and GREY .. marks .. "|r" or ""))
    button.ilvl:SetText(tostring(row.ilvl))
    if row.needLevel then
        button.level:SetText(RED .. row.needLevel .. "|r")
    else
        button.level:SetText(tostring(row.reqLevel))
    end
    button:SetAlpha(row.usable and 1 or 0.5)
    updateSelected(button)
end

-- Returns a scroll bar for the list: MinimalScrollBar, else WowTrimScrollBar, else nil (mouse wheel only).
local function scrollBar(parent)
    for _, template in ipairs({ "MinimalScrollBar", "WowTrimScrollBar" }) do
        local ok, bar = pcall(CreateFrame, "EventFrame", nil, parent, template)
        if ok and bar then
            return bar
        end
    end
end

local function build()
    local f = CreateFrame("Frame", NAME, UIParent, "ButtonFrameTemplate")
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    if ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(f)
    end
    if ButtonFrameTemplate_HideButtonBar then
        ButtonFrameTemplate_HideButtonBar(f)
    end
    if f.SetTitle then
        f:SetTitle(L["Tandem gear"])
    end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- The position lives in TandemDB, not in the client's layout cache.
    local dontSave = f.SetDontSavePosition and true or false
    if dontSave then
        f:SetDontSavePosition(true)
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not dontSave then
            self:SetUserPlaced(false)
        end
        local point, _, relativePoint, x, y = self:GetPoint()
        ns.Store.SetUIPosition(point, relativePoint, x, y)
    end)
    local pos = ns.Store.UIPosition()
    f:ClearAllPoints()
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, NAME)
    end

    local dropdown = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    dropdown:SetWidth(150)
    local function isSelected(s)
        return slot == s
    end
    local function setSelected(s)
        slot = s
        Browse.Refresh()
    end
    dropdown:SetupMenu(function(_, root)
        root:CreateRadio(L["All slots"], isSelected, setSelected, nil)
        for _, s in ipairs(ns.Advisor.SLOTS) do
            root:CreateRadio(View.SlotLabel(s), isSelected, setSelected, s)
        end
    end)
    f.dropdown = dropdown

    local usable = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    usable:SetPoint("LEFT", dropdown, "RIGHT", 12, 0)
    usable:SetSize(24, 24)
    usable:SetChecked(true)
    usable:SetScript("OnClick", function()
        Browse.Refresh()
    end)
    local usableText = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    usableText:SetPoint("LEFT", usable, "RIGHT", 2, 0)
    usableText:SetText(L["Usable only"])
    f.usable = usable

    f.count = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -36)

    local box = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -64)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, PANE_HEIGHT + 8)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    local bar = scrollBar(f)
    if bar then
        bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
        bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
        ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    elseif ScrollUtil.InitScrollBoxList then
        ScrollUtil.InitScrollBoxList(box, view)
    else
        box:Init(view)
    end
    f.box = box

    local pane = CreateFrame("Frame", nil, f)
    pane:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    pane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    pane:SetHeight(PANE_HEIGHT)
    pane.header = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pane.header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    pane.header:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    pane.header:SetJustifyH("LEFT")
    pane.lines = {}
    for i = 1, SOURCE_ROWS + 1 do
        local fs = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", i == 1 and pane.header or pane.lines[i - 1], "BOTTOMLEFT", 0, -2)
        fs:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        pane.lines[i] = fs
    end
    f.pane = pane
    return f
end

local function refresh(class, level)
    rows = ns.Advisor.List(slot, class, level, { usableOnly = frame.usable:GetChecked() and true or false }) or {}
    listed, worn = {}, {}
    for _, row in ipairs(rows) do
        listed[row.id] = true
    end
    frame.box:SetDataProvider(CreateDataProvider(rows))
    frame.count:SetText(L["%d items"]:format(#rows))
    updateSources()
end

-- Re-reads the player and lists the items again; nothing when the window was never built.
function Browse.Refresh()
    if not frame then
        return
    end
    local _, class, level = View.Player()
    if class then
        refresh(class, level)
    end
end

-- Opens the window on slot (nil: all slots); false in combat or while the player is unknown.
function Browse.Show(s)
    if View.InCombat() then
        return false
    end
    local _, class, level = View.Player()
    if not class then
        return false
    end
    frame = frame or build()
    slot = s
    if frame.dropdown.GenerateMenu then
        frame.dropdown:GenerateMenu()
    end
    refresh(class, level)
    frame:Show()
    return true
end

function Browse.Hide()
    if frame then
        frame:Hide()
    end
end

function Browse.Toggle()
    if frame and frame:IsShown() then
        Browse.Hide()
    else
        Browse.Show()
    end
end

local function redraw()
    pending = false
    if frame:IsShown() then
        worn = {}
        frame.box:ForEachFrame(function(button, row)
            initRow(button, row or button.row)
        end)
        updateSources()
    end
end

-- Redraws the rows once shortly after the client loads an item they show, so a burst of loads costs one redraw.
function Browse.OnItemInfo(id, success)
    id = Safe(id)
    if Safe(success) == false or not frame or not frame:IsShown() or not id or not (listed[id] or id == selected)
        or pending then
        return
    end
    pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(REDRAW_DELAY, redraw)
    else
        redraw()
    end
end

function Browse.OnCombat()
    Browse.Hide()
end
