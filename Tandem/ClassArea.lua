local _, ns = ...

-- The class rail (stage 12, D5, D12): a plain Frame just above the top action bar holding up to 12 icon slots,
-- centred, each with a short timer on the icon, an optional count and a tooltip naming it, plus an optional 4px line
-- along its bottom for a resource, shown only together with a slot. The module registered for the player's class
-- fills it through ClassArea.Set.
-- Display only: the slots take the mouse for their tooltip and nothing else, no secure template, no advice on what
-- to cast (PLAN decision 6). Classes without a module get no rail.
local ClassArea = {}
ns.ClassArea = ClassArea

local GAP, HEIGHT, TICK = 4, 36, 0.25
local SIZE, SPACING, MAX_SLOTS, LINE = 32, 4, 12, 4
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- modules[classFile] = { Ready = fn() -> bool, Update = fn(event) }; Update gets nil for a full refresh and calls
-- ClassArea.Set with what to show.
local modules = {}
local area, module, ticker, on
local slots, entries, line = {}, {}, nil

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b = pcall(fn, ...)
    if ok then
        return ns.Store.Safe(a), ns.Store.Safe(b)
    end
end

function ClassArea.Register(classFile, mod)
    modules[classFile] = mod
end

-- Returns seconds left as m:ss, never below 0:00.
function ClassArea.Clock(seconds)
    local s = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- Returns the timer shown on a slot: m:ss above a minute, else whole seconds.
function ClassArea.Short(seconds)
    if seconds > 60 then
        return ClassArea.Clock(seconds)
    end
    return tostring(math.max(0, math.floor(seconds)))
end

local function now()
    local t = call(GetTime)
    return type(t) == "number" and t or 0
end

local function classModule()
    local _, classFile = call(UnitClass, "player")
    return classFile and modules[classFile]
end

local function showTooltip(slot)
    local tip, e = GameTooltip, slot.entry
    if type(tip) ~= "table" or not e then
        return
    end
    tip:SetOwner(slot, "ANCHOR_TOP")
    tip:SetText(e.label or "")
    if e.expires then
        tip:AddLine(ClassArea.Clock(e.expires - now()), 1, 1, 1)
    end
    tip:Show()
end

local function hideTooltip()
    if type(GameTooltip) == "table" then
        GameTooltip:Hide()
    end
end

local function slot(i)
    if slots[i] then
        return slots[i]
    end
    local s = CreateFrame("Frame", nil, area)
    s:SetSize(SIZE, SIZE)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints(s)
    s.time = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    s.time:SetPoint("CENTER", s, "CENTER", 0, 0)
    s.count = s:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    s.count:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
    s:EnableMouse(true)
    s:SetScript("OnEnter", showTooltip)
    s:SetScript("OnLeave", hideTooltip)
    slots[i] = s
    return s
end

-- Lays out the cached entries that have not run out, centred, with their timers against the current time; hides
-- the rail, line included, when no slot is left. Calls no client API but GetTime.
local function render()
    local t, shown = now(), {}
    for _, e in ipairs(entries) do
        if #shown < MAX_SLOTS and not (e.expires and e.expires <= t) then
            shown[#shown + 1] = e
        end
    end
    local step = SIZE + SPACING
    for i, e in ipairs(shown) do
        local s = slot(i)
        s.entry = e
        s.icon:SetTexture(e.icon or UNKNOWN_ICON)
        s.time:SetText(e.expires and ClassArea.Short(e.expires - t) or "")
        s.count:SetText(e.count and e.count > 0 and tostring(e.count) or "")
        s:ClearAllPoints()
        s:SetPoint("BOTTOM", area, "BOTTOM", (i - 1) * step - (#shown - 1) * step / 2, LINE)
        s:Show()
    end
    for i = #shown + 1, #slots do
        slots[i].entry = nil
        slots[i]:Hide()
    end
    if #shown > 0 then
        area:Show()
    else
        area:Hide()
    end
end

-- Sets what the rail shows: list is an ordered array of { icon, label, expires (GetTime based) | nil, count | nil };
-- bar is { value, max, color = { r, g, b } } for the line along the bottom, or nil for none.
function ClassArea.Set(list, bar)
    if not area then
        return
    end
    entries = list or {}
    line = bar and type(bar.max) == "number" and bar.max > 0 and bar or nil
    if line then
        area.line:SetMinMaxValues(0, line.max)
        area.line:SetValue(line.value or 0)
        area.line:SetStatusBarColor(line.color[1], line.color[2], line.color[3])
        area.line:Show()
    else
        area.line:Hide()
    end
    if on then
        render()
    end
end

local function update(event)
    if module then
        pcall(module.Update, event)
    end
end

local function startTicker()
    if not ticker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        ticker = C_Timer.NewTicker(TICK, render)
    end
end

local function stopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function create()
    area = CreateFrame("Frame", nil, UIParent)
    area:SetHeight(HEIGHT)
    area:Hide()
    area:SetScript("OnShow", startTicker)
    area:SetScript("OnHide", stopTicker)
    area.line = CreateFrame("StatusBar", nil, area)
    area.line:SetHeight(LINE)
    area.line:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, 0)
    area.line:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    area.line:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local bg = area.line:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(area.line)
    bg:SetColorTexture(0, 0, 0, 0.5)
    area.line:Hide()
end

local function place()
    local top = ns.Layout.BarAnchor()
    area:ClearAllPoints()
    if type(top) == "table" then
        area:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 0, GAP)
        area:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", 0, GAP)
    else
        area:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
        area:SetWidth(500)
    end
end

-- Forwards a game event to the class module while the layout is on; unit events count only for the player.
function ClassArea.OnEvent(event, unit)
    if not on or (event:sub(1, 5) == "UNIT_" and unit ~= "player") then
        return
    end
    update(event)
end

local function onChange(layoutOn)
    module = module or classModule()
    on = layoutOn and module ~= nil and module.Ready() == true
    if on then
        if not area then
            create()
        end
        place()
        update(nil)
        render()
    elseif area then
        area:Hide()
    end
end

ns.Layout.OnChange(onChange)
