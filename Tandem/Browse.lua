local _, ns = ...

-- The /tandem browse window: every known item for a slot, best first, with where the selected one drops; a scan bar
-- that runs /tandem scan, and an item dropped on the window is looked up.
local Browse = {}
ns.Browse = Browse

local L = ns.L
local View = ns.View
local Safe = ns.Store.Safe

local NAME = "TandemBrowseFrame"
local WIDTH, HEIGHT = 440, 594
local ROW_HEIGHT = 20
local PANE_HEIGHT = 110
local SOURCE_ROWS = 5
local REDRAW_DELAY = 0.2
local PROGRESS_INTERVAL = 1
local DEFAULT_RATE_TEXT = ("%d/s"):format(ns.Commands.DEFAULT_RATE)
local DEFAULT_CAP_TEXT = tostring(ns.Commands.DEFAULT_CAP)
local GREY, RED = "|cff808080", "|cffff2020"
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, progress
local slot, selected, unknown, pending, paneStale
local rows, listed, worn = {}, {}, {}

local updateScan, startProgress, stopProgress

-- What the player wears per slot, read once per listing (refresh clears it).
local function wornFor(rowSlot)
    worn[rowSlot] = worn[rowSlot] or View.Equipped(rowSlot)
    return worn[rowSlot]
end

local function iconOf(id)
    local icon
    if C_Item and C_Item.GetItemInfoInstant then
        icon = Safe((select(5, C_Item.GetItemInfoInstant(id))))
    end
    return icon or NO_ICON
end

local function updateSources()
    local pane = frame.pane
    local lines = {}
    if selected then
        pane.header:SetText(View.LinkOf(selected))
        lines = View.SourceLines(selected, SOURCE_ROWS)
    elseif unknown then
        pane.header:SetText(L["Tandem: item %d is not known; scan or loot it first"]:format(unknown))
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

local function updateSelected(button)
    button.selected:SetShown(button.row ~= nil and button.row.id == selected)
end

local onDrop

local function onClick(self)
    if onDrop() or not self.row then
        return
    end
    selected, unknown = self.row.id, nil
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
    button:SetScript("OnLeave", View.HideTooltip)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnReceiveDrag", onDrop)
    button.built = true
end

local function initRow(button, row)
    if not button.built then
        buildRow(button)
    end
    button.row = row
    local marks = View.Marks(row, wornFor(row.slot))
    button.icon:SetTexture(iconOf(row.id))
    button.name:SetText(View.ItemName(row.id, row.quality) .. (marks ~= "" and GREY .. marks .. "|r" or ""))
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

-- An edit box from InputBoxTemplate when the client has it, else a plain one; Enter and Escape drop the focus so
-- Escape does not stay captured by the box.
local function editBox(parent, width, text)
    local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
    if not ok or not box then
        box = CreateFrame("EditBox", nil, parent)
        if box.SetFontObject then
            box:SetFontObject("ChatFontNormal")
        end
    end
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(8)
    box:SetText(text)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

local function label(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

-- The scan bar: rate, cap, Start/Stop and a status line under them.
local function buildScanBar(f)
    local rateLabel = label(f, L["Rate"])
    rateLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -70)
    f.rate = editBox(f, 60, DEFAULT_RATE_TEXT)
    f.rate:SetPoint("LEFT", rateLabel, "RIGHT", 8, 0)
    local capLabel = label(f, L["Cap"])
    capLabel:SetPoint("LEFT", f.rate, "RIGHT", 12, 0)
    f.cap = editBox(f, 60, DEFAULT_CAP_TEXT)
    f.cap:SetPoint("LEFT", capLabel, "RIGHT", 8, 0)
    local ok, button = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
    if not ok or not button then
        button = CreateFrame("Button", nil, f)
        button:SetNormalFontObject("GameFontNormal")
    end
    button:SetSize(80, 22)
    button:SetPoint("LEFT", f.cap, "RIGHT", 12, 0)
    button:SetScript("OnClick", function()
        Browse.ToggleScan()
    end)
    f.scan = button
    f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", rateLabel, "BOTTOMLEFT", 0, -12)
    f.status:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.status:SetJustifyH("LEFT")
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
    label(f, L["Usable only"]):SetPoint("LEFT", usable, "RIGHT", 2, 0)
    f.usable = usable

    f.count = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -36)

    buildScanBar(f)

    -- Under the scan bar: the minimap button's visibility, the same setting as /tandem minimap.
    local minimap = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    minimap:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -110)
    minimap:SetSize(24, 24)
    minimap:SetChecked(ns.Launcher.IsButtonShown())
    minimap:SetScript("OnClick", function(self)
        ns.Launcher.SetButtonShown(self:GetChecked() and true or false)
    end)
    label(f, L["Show minimap button"]):SetPoint("LEFT", minimap, "RIGHT", 2, 0)
    f.minimap = minimap

    local box = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -138)
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
    for _, target in ipairs({ f, box }) do
        target:SetScript("OnReceiveDrag", onDrop)
        target:SetScript("OnMouseUp", onDrop)
    end
    f:SetScript("OnShow", function()
        updateScan()
        startProgress()
    end)
    f:SetScript("OnHide", stopProgress)

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

local function reinit(button, row)
    initRow(button, row or button.row)
end

local function redraw()
    pending = false
    if frame:IsShown() then
        frame.box:ForEachFrame(reinit)
        if paneStale then
            updateSources()
        end
    end
    paneStale = false
end

-- Redraws the rows once shortly after the client loads an item they show, so a burst of loads costs one redraw;
-- the sources pane only when the selected item loaded.
function Browse.OnItemInfo(id, success)
    if not frame or not frame:IsShown() then
        return
    end
    id = Safe(id)
    if not id or not (listed[id] or id == selected) or Safe(success) == false then
        return
    end
    -- Checked before pending: the selected item may load inside a burst another item started.
    paneStale = paneStale or id == selected
    if pending then
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

-- Launcher.SetButtonShown: ticks the checkbox to match /tandem minimap; nothing when the window was never built.
function Browse.OnMinimapButtonChanged()
    if frame then
        frame.minimap:SetChecked(ns.Launcher.IsButtonShown())
    end
end

-- PLAYER_EQUIPMENT_CHANGED: what is worn decides the (equipped) and (upgrade) marks, so read it again and redraw
-- the rows; nothing while the window is hidden, since showing it lists them afresh.
function Browse.OnEquipmentChanged()
    if frame and frame:IsShown() then
        worn = {}
        frame.box:ForEachFrame(reinit)
    end
end

-- Shows the scan's progress while one runs, else how many items are known and where the next scan starts.
updateScan = function()
    if not frame then
        return
    end
    local scanner = ns.Scanner
    local processed, cap, hits = scanner.Progress()
    local cursor = tostring(ns.Store.ScanCursor() or "?")
    if processed then
        frame.status:SetText(L["Scanning: %d of %d IDs, %d found, next ID %s"]:format(processed, cap, hits, cursor))
        frame.scan:SetText(L["Stop"])
    else
        frame.status:SetText(L["%d known items, next scan from ID %s"]:format(ns.Store.ItemCount(), cursor))
        frame.scan:SetText(L["Start"])
    end
end

-- Ticks the progress while a scan runs and the window is shown.
startProgress = function()
    if not progress and frame:IsShown() and ns.Scanner.IsRunning() and C_Timer and C_Timer.NewTicker then
        progress = C_Timer.NewTicker(PROGRESS_INTERVAL, updateScan)
    end
end

stopProgress = function()
    if progress then
        progress:Cancel()
        progress = nil
    end
end

-- Start/Stop: stops a running scan, else starts one with the typed rate and cap (the /tandem scan rules).
function Browse.ToggleScan()
    if View.InCombat() then
        return
    end
    local scanner = ns.Scanner
    if scanner.IsRunning() then
        scanner.Stop()
    else
        frame.rate:ClearFocus()
        frame.cap:ClearFocus()
        local opts = ns.Commands.ScanOptions(frame.rate:GetText(), frame.cap:GetText())
        if opts then
            scanner.Start(opts)
        else
            print(L[ns.Commands.SCAN_USAGE])
        end
    end
    updateScan()
end

-- Scanner.onStart: a scan started here or by /tandem scan shows its progress.
function Browse.OnScanStarted()
    if frame and frame:IsShown() then
        updateScan()
        startProgress()
    end
end
ns.Scanner.onStart = Browse.OnScanStarted

-- Scanner.onStop: a finished or stopped scan may have found items, so list them.
function Browse.OnScanStopped()
    stopProgress()
    if frame and frame:IsShown() then
        Browse.Refresh()
        updateScan()
    end
end
ns.Scanner.onStop = Browse.OnScanStopped

-- Shows a dropped item: its slot in the list (all slots when it has none) and its sources; an unknown item says so.
local function lookup(id)
    local _, class, level = View.Player()
    if not class then
        return
    end
    local r = ns.Advisor.Place(id, class, level)
    if r then
        selected, unknown = id, nil
        slot = r.slot
        -- An item with no ranked slot is never listed, so the filter stays as it is.
        if r.slot and not r.usable then
            frame.usable:SetChecked(false)
        end
    else
        selected, unknown = nil, id
    end
    if frame.dropdown.GenerateMenu then
        frame.dropdown:GenerateMenu()
    end
    refresh(class, level)
    for _, row in ipairs(rows) do
        if row.id == id then
            if frame.box.ScrollToElementData then
                frame.box:ScrollToElementData(row)
            end
            break
        end
    end
end

-- OnReceiveDrag / OnMouseUp: looks up an item held on the cursor and clears it; true when the cursor held one.
onDrop = function()
    if not GetCursorInfo then
        return false
    end
    local kind, id = GetCursorInfo()
    kind, id = Safe(kind), Safe(id)
    if kind ~= "item" or type(id) ~= "number" then
        return false
    end
    if View.InCombat() then
        return true
    end
    if ClearCursor then
        ClearCursor()
    end
    lookup(id)
    return true
end
