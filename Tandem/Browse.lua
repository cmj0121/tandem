local _, ns = ...

-- The /tandem browse window: every known item for a slot, best first, with where the selected one drops; a scan bar
-- that runs /tandem scan, and an item dropped on the window is looked up.
local Browse = {}
ns.Browse = Browse

local L = ns.L
local View = ns.View
local Safe = ns.Store.Safe

local NAME = "TandemBrowseFrame"
local WIDTH, HEIGHT = 640, 620
local MIN_WIDTH, MIN_HEIGHT = 520, 480
local MAX_WIDTH, MAX_HEIGHT = 1200, 1000
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local ROW_HEIGHT = 20
local PANE_HEIGHT = 110
local SOURCE_ROWS = 5
local REDRAW_DELAY = 0.2
local PROGRESS_INTERVAL = 1
local DEFAULT_RATE_TEXT = ("%d/s"):format(ns.Commands.DEFAULT_RATE)
local DEFAULT_CAP_TEXT = tostring(ns.Commands.DEFAULT_CAP)
local GREY, RED = "|cff808080", "|cffff2020"
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
-- The worn key for a one-hander that fills either hand; slot tokens never contain "+".
local HANDS = "mainhand+offhand"

local frame, progress
local slot, onlyQuality, selected, unknown, pending, paneStale
local rows, listed, worn = {}, {}, {}
-- Items whose cached name refresh has read: a name does not change, so each is read once per session.
local peeked = {}

local updateScan, startProgress, stopProgress

-- What the player wears for a row, read once per listing (refresh clears it): both hands for a one-hander that
-- also fills the off hand, else the row's slot.
local function wornFor(row)
    local key = row.offhand and HANDS or row.slot
    if not worn[key] then
        worn[key] = row.offhand and View.EquippedHands() or View.Equipped(row.slot)
    end
    return worn[key]
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
    pane.map:SetEnabled(selected ~= nil)
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

-- Selects an item (nil: none); a new selection drops the map pins of the earlier one.
local function selectItem(id)
    if id ~= selected then
        ns.MapPins.Clear()
    end
    selected = id
end

local function onClick(self)
    if onDrop() or not self.row then
        return
    end
    selectItem(self.row.id)
    unknown = nil
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
    -- ItemName first: a loaded name may flag the item deprecated, which then shows until the next listing.
    local name = View.ItemName(row.id, row.quality)
    local marks = View.Marks(row, wornFor(row))
    if row.deprecated or ns.Advisor.IsDeprecated(row.id) then
        marks = marks .. L[" (deprecated)"]
    end
    button.icon:SetTexture(iconOf(row.id))
    button.name:SetText(name .. (marks ~= "" and GREY .. marks .. "|r" or ""))
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

-- A check box with its label on the right; returns the box and the label, for the next control to anchor to.
local function checkbox(parent, text, checked, onToggle)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetChecked(checked)
    box:SetScript("OnClick", onToggle)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", box, "RIGHT", 2, 0)
    return box, fs
end

local function clamp(v, low, high)
    return math.max(low, math.min(high, v))
end

-- Returns the largest size the window may take: MAX_WIDTH x MAX_HEIGHT, or less on a smaller screen, never below
-- the minimum.
local function maxSize()
    local w, h = MAX_WIDTH, MAX_HEIGHT
    if UIParent and UIParent.GetSize then
        local sw, sh = UIParent:GetSize()
        if type(sw) == "number" and sw > 0 and type(sh) == "number" and sh > 0 then
            w, h = math.min(w, sw), math.min(h, sh)
        end
    end
    return math.max(w, MIN_WIDTH), math.max(h, MIN_HEIGHT)
end

-- Makes f resizable from a grip at its bottom-right corner when the client can size frames; onSized runs when a
-- resize ends. Returns true when f is resizable.
local function makeResizable(f, maxW, maxH, onSized)
    if not (f.SetResizable and f.StartSizing) then
        return false
    end
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, maxW, maxH)
    else
        if f.SetMinResize then
            f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        end
        if f.SetMaxResize then
            f:SetMaxResize(maxW, maxH)
        end
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture(GRIP .. "Up")
    grip:SetPushedTexture(GRIP .. "Down")
    grip:SetHighlightTexture(GRIP .. "Highlight")
    grip:SetScript("OnMouseDown", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        onSized(f)
    end)
    f.grip = grip
    return true
end

-- A UIPanelButtonTemplate button when the client has it, else a plain one.
local function panelButton(parent, width)
    local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not ok or not b then
        b = CreateFrame("Button", nil, parent)
        b:SetNormalFontObject("GameFontNormal")
    end
    b:SetSize(width, 22)
    return b
end

-- The scan bar: rate, cap, Start/Stop and a status line under them.
local function buildScanBar(f)
    local rateLabel = label(f, L["Rate"])
    rateLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -94)
    f.rate = editBox(f, 60, DEFAULT_RATE_TEXT)
    f.rate:SetPoint("LEFT", rateLabel, "RIGHT", 8, 0)
    local capLabel = label(f, L["Cap"])
    capLabel:SetPoint("LEFT", f.rate, "RIGHT", 12, 0)
    f.cap = editBox(f, 60, DEFAULT_CAP_TEXT)
    f.cap:SetPoint("LEFT", capLabel, "RIGHT", 8, 0)
    f.scan = panelButton(f, 80)
    f.scan:SetPoint("LEFT", f.cap, "RIGHT", 12, 0)
    f.scan:SetScript("OnClick", function()
        Browse.ToggleScan()
    end)
    f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", rateLabel, "BOTTOMLEFT", 0, -12)
    f.status:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.status:SetJustifyH("LEFT")
end

local function build()
    local f = CreateFrame("Frame", NAME, UIParent, "ButtonFrameTemplate")
    f:Hide()
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
    local resizable
    -- Moving or sizing may re-anchor the window, so both save the position; sizing saves the size too.
    local function savePlace(self)
        if not dontSave then
            self:SetUserPlaced(false)
        end
        local point, _, relativePoint, x, y = self:GetPoint()
        ns.Store.SetUIPosition(point, relativePoint, x, y)
        if resizable then
            ns.Store.SetUISize(self:GetSize())
        end
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePlace(self)
    end)
    local maxW, maxH = maxSize()
    resizable = makeResizable(f, maxW, maxH, savePlace)
    local width, height = WIDTH, HEIGHT
    if resizable then
        local savedW, savedH = ns.Store.UISize()
        width, height = clamp(savedW or WIDTH, MIN_WIDTH, maxW), clamp(savedH or HEIGHT, MIN_HEIGHT, maxH)
    end
    f:SetSize(width, height)
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

    -- Quality filter: only items of the chosen quality.
    local quality = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    quality:SetPoint("LEFT", dropdown, "RIGHT", 12, 0)
    quality:SetWidth(130)
    local function isQuality(q)
        return onlyQuality == q
    end
    local function setQuality(q)
        onlyQuality = q
        Browse.Refresh()
    end
    quality:SetupMenu(function(_, root)
        root:CreateRadio(L["All qualities"], isQuality, setQuality, nil)
        for q = 0, #QUALITY_NAMES do
            root:CreateRadio(("|cff%s%s|r"):format(View.QUALITY_HEX[q], L[QUALITY_NAMES[q]]), isQuality, setQuality, q)
        end
    end)
    f.quality = quality

    f.count = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -36)

    -- Second row: the list filters, then the minimap button's visibility (the same setting as /tandem minimap).
    local usableLabel, deprecatedLabel
    f.usable, usableLabel = checkbox(f, L["Usable only"], true, Browse.Refresh)
    f.usable:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -58)
    f.deprecated, deprecatedLabel = checkbox(f, L["Hide deprecated"], true, Browse.Refresh)
    f.deprecated:SetPoint("LEFT", usableLabel, "RIGHT", 12, 0)
    f.minimap = checkbox(f, L["Show minimap button"], ns.Launcher.IsButtonShown(), function(self)
        ns.Launcher.SetButtonShown(self:GetChecked() and true or false)
    end)
    f.minimap:SetPoint("LEFT", deprecatedLabel, "RIGHT", 12, 0)

    buildScanBar(f)

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
    pane.map = panelButton(pane, 110)
    pane.map:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 2)
    pane.map:SetText(L["Show on map"])
    pane.map:SetScript("OnClick", Browse.ShowOnMap)
    pane.header = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pane.header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    pane.header:SetPoint("RIGHT", pane.map, "LEFT", -8, 0)
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
    local hide = frame.deprecated:GetChecked() and true or false
    local found = ns.Advisor.List(slot, class, level, { usableOnly = frame.usable:GetChecked() and true or false,
                                                        hideDeprecated = hide, quality = onlyQuality }) or {}
    rows, listed, worn = {}, {}, {}
    for _, row in ipairs(found) do
        -- A name the client already holds flags a deprecated item before it is shown, so it never flashes in.
        if not row.deprecated and not peeked[row.id] then
            local name = View.CachedName(row.id)
            if name then
                peeked[row.id] = true
                row.deprecated = View.NoteName(row.id, name) or nil
            end
        end
        if not (hide and row.deprecated) then
            rows[#rows + 1] = row
            listed[row.id] = true
        end
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

-- Show on map: pins the selected item's sources on the world map; refused in combat.
function Browse.ShowOnMap()
    if not selected or View.InCombat() then
        return
    end
    ns.MapPins.Open(selected)
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
    View.NoteName(id, View.CachedName(id))
    local r = ns.Advisor.Place(id, class, level)
    if r then
        selectItem(id)
        unknown = nil
        slot = r.slot
        -- An item with no ranked slot is never listed, so the filters stay as they are.
        if r.slot and not r.usable then
            frame.usable:SetChecked(false)
        end
        if r.slot and r.deprecated then
            frame.deprecated:SetChecked(false)
        end
        if r.slot and onlyQuality and ns.Advisor.Item(id)[3] ~= onlyQuality then
            onlyQuality = nil
        end
    else
        selectItem(nil)
        unknown = id
    end
    for _, menu in ipairs({ frame.dropdown, frame.quality }) do
        if menu.GenerateMenu then
            menu:GenerateMenu()
        end
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
