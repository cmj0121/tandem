local _, ns = ...

-- The class area (stage 12, D2, D5): a plain Frame above the top action bar, in the room the Tandem layout leaves
-- under the unit frames, drawn by the module registered for the player's class. Display only: no mouse, no secure
-- template, no advice on what to cast (PLAN decision 6). Classes without a module get no area.
local ClassArea = {}
ns.ClassArea = ClassArea

local GAP, HEIGHT, TICK = 4, 68, 0.25

-- modules[classFile] = { Ready = fn() -> bool, Build = fn(area), Update = fn(event) }; Update gets "tick" from the
-- countdown timer and nil for a full refresh.
local modules = {}
local area, module, ticker, on

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

local function classModule()
    local _, classFile = call(UnitClass, "player")
    return classFile and modules[classFile]
end

local function update(event)
    if module then
        pcall(module.Update, event)
    end
end

local function startTicker()
    if not ticker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        ticker = C_Timer.NewTicker(TICK, function()
            update("tick")
        end)
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
    module.Build(area)
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

-- Forwards a game event to the class module while the area is shown; unit events count only for the player.
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
        area:Show()
    elseif area then
        area:Hide()
    end
end

ns.Layout.OnChange(onChange)
