local _, ns = ...

-- Map info (stage 13, D2, D3): one line of small text just under the minimap while the Tandem layout is on, with
-- the player's coordinates on the current zone map in percent. Refreshed twice a second while shown and on zone
-- changes.
local MapInfo = {}
ns.MapInfo = MapInfo

local GAP = 4
local TICK = 0.5
local NO_POSITION = "(--, --)"

local line, on, ticker

local call = ns.Store.Call

-- Returns the player's position on the current zone map as "(x, y)" in percent, or "(--, --)" where the map has
-- none.
function MapInfo.Coords()
    local maps = _G.C_Map
    if type(maps) ~= "table" then
        return NO_POSITION
    end
    local map = call(maps.GetBestMapForUnit, "player")
    local pos = map and call(maps.GetPlayerMapPosition, map, "player")
    if type(pos) ~= "table" then
        return NO_POSITION
    end
    local x, y = call(pos.GetXY, pos)
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then
        return NO_POSITION
    end
    return ("(%.2f, %.2f)"):format(x * 100, y * 100)
end

local function tick()
    MapInfo.Update()
end

local function startTicker()
    if not ticker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        ticker = C_Timer.NewTicker(TICK, tick)
    end
end

local function stopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function create()
    line = CreateFrame("Frame", nil, UIParent)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetPoint("TOP", line, "TOP", 0, 0)
    line:SetSize(1, 1)
    line:Hide()
    line:SetScript("OnShow", startTicker)
    line:SetScript("OnHide", stopTicker)
end

-- Under the minimap cluster, else the minimap, else the screen's top-right corner.
local function place()
    line:ClearAllPoints()
    for _, name in ipairs({ "MinimapCluster", "Minimap" }) do
        local anchor = _G[name]
        if type(anchor) == "table" then
            line:SetPoint("TOP", anchor, "BOTTOM", 0, -GAP)
            return
        end
    end
    line:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -200)
end

-- Refreshes the line; hides it while the layout is off or the client lacks the map API.
function MapInfo.Update()
    if not line then
        return
    end
    if not on then
        line:Hide()
        return
    end
    line.text:SetText(MapInfo.Coords())
    line:Show()
end

local function onChange(layoutOn)
    on = layoutOn and ns.Check.Ready("Map info")
    if on then
        if not line then
            create()
        end
        place()
    end
    MapInfo.Update()
end

ns.Layout.OnChange(onChange)
