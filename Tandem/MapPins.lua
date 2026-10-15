local _, ns = ...

-- Pins an item's sources on the built-in world map (decision 6): plain frames on the map canvas, one per stored
-- coord, shown only on their own map; clicking one sets a user waypoint. Advises only: never in combat, and quiet
-- when the client lacks the map API.
local MapPins = {}
ns.MapPins = MapPins

local L = ns.L
local View = ns.View
local Safe = ns.Store.Safe

local MAX_POINTS = 50
local PIN_SIZE = 16
local PIN_LEVEL = 100
local ICON = "Interface\\AddOns\\Tandem\\Media\\icon"
local SCALE = 1000
local EMPTY = {}

local SHOW_MESSAGES = {
    combat = "Tandem: not available in combat",
    noapi = "Tandem: map pins are not available on this client; see /tandem check",
    unknown = "Tandem: item %d is not known; scan or loot it first",
    nocoords = "Tandem: no known map position for item %d",
}
local WAYPOINT_MESSAGES = {
    noapi = "Tandem: waypoints are not available on this client; see /tandem check",
    refused = "Tandem: this map does not take a waypoint",
}

local pinned
local pins = {}
local hooked = false

local function sourceKey(kind, id, map)
    if kind == "q" or kind == "v" then
        return kind .. ":" .. id
    end
    return kind .. ":" .. id .. ":" .. map
end

-- Returns the item's stored coords grouped by source key: { [key] = { {map, {{x, y}, ...}}, ... } }, own entries and
-- shipped rows alike, each list sorted by map so the lowest map comes first, own before shipped on one map.
local function storedCoords(itemID)
    local byKey = {}
    local function add(kind, id, map, coords)
        local key = sourceKey(kind, id, map)
        local list = byKey[key] or {}
        byKey[key] = list
        list[#list + 1] = { map = map, coords = coords, order = #list }
    end
    local loot = type(ns.Store.db) == "table" and ns.Store.db.loot
    for _, v in pairs(type(loot) == "table" and loot or EMPTY) do
        if type(v) == "table" and v.item == itemID and type(v.coords) == "table" then
            add(v.kind, v.id, v.map, v.coords)
        end
    end
    for _, r in ipairs(ns.Advisor.ShippedRows(itemID)) do
        local coords = {}
        for i = 6, #r - 1, 2 do
            coords[#coords + 1] = { r[i], r[i + 1] }
        end
        add(r[2], r[3], r[4], coords)
    end
    for _, list in pairs(byKey) do
        table.sort(list, function(a, b)
            if a.map ~= b.map then
                return a.map < b.map
            end
            return a.order < b.order
        end)
    end
    return byKey
end

local function isCoord(v)
    return type(v) == "number" and v >= 0 and v <= SCALE
end

-- Returns byMap, firstMap: byMap[map] = { {x, y, label}, ... } with x, y in 0..1, at most 50 points per item and
-- equal coords on a map once; firstMap is the map of the first source, in Advisor.Sources order, with coords.
function MapPins.Points(itemID)
    local byKey = storedCoords(itemID)
    local byMap, seen, total, firstMap = {}, {}, 0, nil
    for _, s in ipairs(View.Sources(itemID)) do
        local label = View.SourceName(s)
        for _, entry in ipairs(byKey[sourceKey(s.kind, s.id, s.map)] or EMPTY) do
            if entry.map ~= 0 then
                for _, c in ipairs(entry.coords) do
                    if type(c) == "table" and isCoord(c[1]) and isCoord(c[2]) then
                        firstMap = firstMap or entry.map
                        local key = entry.map .. ":" .. c[1] .. ":" .. c[2]
                        if not seen[key] and total < MAX_POINTS then
                            seen[key], total = true, total + 1
                            local points = byMap[entry.map] or {}
                            byMap[entry.map] = points
                            points[#points + 1] = { c[1] / SCALE, c[2] / SCALE, label }
                        end
                    end
                end
            end
        end
    end
    return byMap, firstMap
end

-- Sets a user waypoint at x, y (0..1) on map and super-tracks it.
function MapPins.Waypoint(map, x, y)
    if not ns.Check.Ready("Map waypoint") then
        return false, "noapi"
    end
    if not Safe(C_Map.CanSetUserWaypointOnMap(map)) then
        return false, "refused"
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    return true
end

local function onPinEnter(pin)
    if GameTooltip then
        GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
        GameTooltip:SetText(pin.label)
        GameTooltip:AddLine(L["Click to set a waypoint"], 1, 1, 1)
        GameTooltip:Show()
    end
end

local function onPinClick(pin)
    if View.InCombat() then
        return
    end
    local ok, reason = MapPins.Waypoint(pin.map, pin.x, pin.y)
    if ok then
        print(L["Tandem: waypoint set to %s"]:format(pin.label))
    else
        print(L[WAYPOINT_MESSAGES[reason]])
    end
end

local function newPin(canvas)
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameLevel((canvas:GetFrameLevel() or 0) + PIN_LEVEL)
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints()
    pin.icon:SetTexture(ICON)
    pin:SetScript("OnEnter", onPinEnter)
    pin:SetScript("OnLeave", View.HideTooltip)
    pin:SetScript("OnClick", onPinClick)
    return pin
end

-- Places the pinned item's points of the shown map on the canvas and hides the rest.
local function refresh()
    local map = pinned and Safe(WorldMapFrame:GetMapID())
    local points = map and pinned.byMap[map] or EMPTY
    if #points > 0 then
        local canvas = WorldMapFrame:GetCanvas()
        local width, height = canvas:GetSize()
        for i, p in ipairs(points) do
            local pin = pins[i] or newPin(canvas)
            pins[i] = pin
            pin.map, pin.x, pin.y, pin.label = map, p[1], p[2], p[3]
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", p[1] * width, -p[2] * height)
            pin:Show()
        end
    end
    for i = #points + 1, #pins do
        pins[i]:Hide()
    end
end

-- Pins the item's sources and opens the world map on the first source's map, replacing any earlier item.
function MapPins.Show(itemID)
    if InCombatLockdown and InCombatLockdown() then
        return false, "combat"
    end
    if not ns.Check.Ready("Map pins") then
        return false, "noapi"
    end
    local byMap, firstMap = MapPins.Points(itemID)
    if not firstMap then
        if not ns.Advisor.Item(itemID) and #View.Sources(itemID) == 0 then
            return false, "unknown"
        end
        return false, "nocoords"
    end
    pinned = { item = itemID, byMap = byMap }
    if not hooked then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", refresh)
        hooked = true
    end
    OpenWorldMap(firstMap)
    refresh()
    return true
end

-- Show for the command and the browse button: says why when nothing is pinned. Returns Show's ok.
function MapPins.Open(itemID)
    local ok, reason = MapPins.Show(itemID)
    if not ok then
        print(L[SHOW_MESSAGES[reason]]:format(itemID))
    end
    return ok
end

function MapPins.Clear()
    pinned = nil
    for _, pin in ipairs(pins) do
        pin:Hide()
    end
end
