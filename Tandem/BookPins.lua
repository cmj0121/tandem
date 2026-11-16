local _, ns = ...

-- Library book pins (library books D2-D4): own small frames on the world map canvas for the eligible books of the
-- zone map shown (books stacked within MERGE map percent share one pin), a dimmer pin at a book's entrance and one at
-- the player's faction's hand-in NPC. The tooltip says where; a click sets a waypoint. /tandem books off hides them.
local BookPins = {}
ns.BookPins = BookPins

local L = ns.L
local call = ns.Store.Call

local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local HAND_IN_ICON = "Interface\\Icons\\INV_Misc_Book_11"
local PIN_SIZE = 18
local PIN_LEVEL = 100
local ENTRANCE_ALPHA = 0.55
local MERGE = 0.5
-- Enum.UIMapType up to Continent (cosmic, world, continent): such maps show no pins.
local CONTINENT = 2

local NOTE_COLOR = { 1, 0.82, 0 }
local LEVEL_COLOR = { 0.8, 0.8, 0.8 }
local ENEMY_COLOR = { 1, 0.2, 0.2 }
local HINT_COLOR = { 0.5, 0.5, 0.5 }

local canvas
local pins = {}

local function log(text)
    if ns.Debug ~= nil and ns.Debug.IsOn() then
        ns.Debug.Log(text)
    end
end

local function playerLevel(level)
    return tonumber(level) or tonumber((call(_G.UnitLevel, "player"))) or 0
end

-- True unless /tandem books off is saved (absent means on).
function BookPins.On()
    return ns.Store.Layout().books ~= false
end

-- Saves the switch and redraws the pins; false, changing nothing, when the db cannot be written.
function BookPins.Set(on)
    local ok = ns.Store.SetLayout("books", on == true)
    BookPins.Refresh()
    return ok
end

-- The pins of the map with this uiMapID for a player of this level and faction, in order: books (merged when
-- stacked) and their entrances as { kind = "book"|"entrance", x, y, books = { book, ... } }, then the faction's
-- hand-in NPCs as { kind = "handin", x, y, npc }. x and y are map percent.
function BookPins.Spots(mapID, level, faction)
    local spots = {}
    for _, book in ipairs(ns.Books.ForMap(mapID, level)) do
        local merged
        for _, spot in ipairs(spots) do
            if spot.kind == "book" and math.abs(spot.x - book.x) <= MERGE and math.abs(spot.y - book.y) <= MERGE then
                merged = spot
                break
            end
        end
        if merged then
            merged.books[#merged.books + 1] = book
        else
            spots[#spots + 1] = { kind = "book", x = book.x, y = book.y, books = { book } }
        end
        if book.entrance then
            spots[#spots + 1] = { kind = "entrance", x = book.entrance[1], y = book.entrance[2], books = { book } }
        end
    end
    for _, npc in ipairs(ns.Books.HandIns(faction, mapID)) do
        spots[#spots + 1] = { kind = "handin", x = npc.x, y = npc.y, npc = npc }
    end
    return spots
end

-- Sets a user waypoint at x, y (map percent) on the map and super-tracks it where the client can; false otherwise.
function BookPins.Waypoint(mapID, x, y)
    local set = ns.Check.Get("C_Map.SetUserWaypoint")
    local create = ns.Check.Get("UiMapPoint.CreateFromCoordinates")
    if type(set) ~= "function" or type(create) ~= "function" then
        return false
    end
    if call(ns.Check.Get("C_Map.CanSetUserWaypointOnMap"), mapID) == false then
        return false
    end
    local point = call(create, mapID, x / 100, y / 100)
    if point == nil or not pcall(set, point) then
        return false
    end
    call(ns.Check.Get("C_SuperTrack.SetSuperTrackedUserWaypoint"), true)
    return true
end

local function line(tip, text, color, wrap)
    tip:AddLine(text, color[1], color[2], color[3], wrap)
end

local function onEnter(pin)
    local tip, spot = _G.GameTooltip, pin.spot
    if type(tip) ~= "table" or not spot then
        return
    end
    tip:SetOwner(pin, "ANCHOR_RIGHT")
    if spot.kind == "handin" then
        tip:SetText(spot.npc.name, 1, 1, 1)
        line(tip, L[spot.npc.note], NOTE_COLOR, true)
        line(tip, L["Takes library books"], LEVEL_COLOR)
    else
        if spot.kind == "entrance" then
            tip:SetText(L["Entrance"], NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3])
        end
        for i, book in ipairs(spot.books) do
            if i == 1 and spot.kind == "book" then
                tip:SetText(book.title, 1, 1, 1)
            else
                tip:AddLine(book.title, 1, 1, 1)
            end
            line(tip, L[book.note], NOTE_COLOR, true)
            line(tip, L["Level %d+"]:format(book.level), LEVEL_COLOR)
            if pin.faction and ns.Books.Hostile(book, pin.faction) then
                line(tip, L["Enemy city"], ENEMY_COLOR)
            end
        end
    end
    line(tip, L["Click to set a waypoint"], HINT_COLOR)
    tip:Show()
end

local function onLeave()
    local tip = _G.GameTooltip
    if type(tip) == "table" then
        tip:Hide()
    end
end

-- A book pin's waypoint goes to the book's entrance when it has one.
local function onClick(pin)
    local spot = pin.spot
    if not spot then
        return
    end
    local book = spot.books and spot.books[1]
    local x, y = spot.x, spot.y
    if book and book.entrance then
        x, y = book.entrance[1], book.entrance[2]
    end
    if BookPins.Waypoint(pin.map, x, y) then
        print(L["Tandem: waypoint set to %s"]:format(book and book.title or spot.npc.name))
    else
        print(L["Tandem: a waypoint cannot be set here"])
    end
end

local function newPin()
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameLevel((tonumber((call(canvas.GetFrameLevel, canvas))) or 0) + PIN_LEVEL)
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints()
    pin:SetScript("OnEnter", onEnter)
    pin:SetScript("OnLeave", onLeave)
    pin:SetScript("OnClick", onClick)
    return pin
end

local function isZone(mapID)
    local info = call(ns.Check.Get("C_Map.GetMapInfo"), mapID)
    return not (type(info) == "table" and type(info.mapType) == "number" and info.mapType <= CONTINENT)
end

-- Places the pins of the map the world map shows (none while off, before login or on a continent) and hides the
-- rest; level, when given, stands in for UnitLevel (PLAYER_LEVEL_UP's new level). Returns the pin count and map.
function BookPins.Refresh(level)
    if not canvas then
        return 0
    end
    local map = BookPins.On() and call(_G.WorldMapFrame.GetMapID, _G.WorldMapFrame) or nil
    local faction = call(_G.UnitFactionGroup, "player")
    local spots = type(map) == "number" and isZone(map) and BookPins.Spots(map, playerLevel(level), faction) or {}
    local width, height = call(canvas.GetSize, canvas)
    width, height = tonumber(width) or 0, tonumber(height) or 0
    for i, spot in ipairs(spots) do
        local pin = pins[i] or newPin()
        pins[i] = pin
        pin.spot, pin.map, pin.faction = spot, map, faction
        pin.icon:SetTexture(spot.kind == "handin" and HAND_IN_ICON or BOOK_ICON)
        pin:SetAlpha(spot.kind == "entrance" and ENTRANCE_ALPHA or 1)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", spot.x / 100 * width, -spot.y / 100 * height)
        pin:Show()
    end
    for i = #spots + 1, #pins do
        pins[i]:Hide()
    end
    return #spots, map
end

local function onMapChanged()
    local count, map = BookPins.Refresh()
    log(("books map=%s pins=%d"):format(tostring(map), count))
end

-- At PLAYER_LOGIN: hooks the world map's map changes and follows its canvas size; false when the client lacks the
-- Book pins API.
function BookPins.OnLogin()
    if canvas then
        return true
    end
    if not ns.Check.Ready("Book pins") then
        return false
    end
    local map = _G.WorldMapFrame
    local found = call(map.GetCanvas, map)
    if type(found) ~= "table" or not pcall(hooksecurefunc, map, "OnMapChanged", onMapChanged) then
        return false
    end
    canvas = found
    local sizer = CreateFrame("Frame", nil, canvas)
    sizer:SetAllPoints(canvas)
    sizer:SetScript("OnSizeChanged", function()
        BookPins.Refresh()
    end)
    BookPins.Refresh()
    return true
end

local function say(text)
    print(text)
    log(text)
end

-- /tandem books near: prints (and logs) the player's map, its name, the position, and the nearest eligible book, in
-- yards when the client gives world positions, else in map percent on the player's map.
function BookPins.Near()
    local maps = _G.C_Map
    local map = type(maps) == "table" and call(maps.GetBestMapForUnit, "player") or nil
    local pos = type(map) == "number" and call(maps.GetPlayerMapPosition, map, "player") or nil
    local x, y
    if type(pos) == "table" then
        x, y = call(pos.GetXY, pos)
    end
    if type(x) ~= "number" or type(y) ~= "number" then
        say(L["Tandem: your map position is not known here"])
        return
    end
    x, y = x * 100, y * 100
    local info = call(maps.GetMapInfo, map)
    local name = type(info) == "table" and type(info.name) == "string" and info.name or "?"
    say(L["Tandem: map %d %s at (%.2f, %.2f)"]:format(map, name, x, y))
    local near, yards, onMap, percent
    for _, book in ipairs(ns.Books.Eligible(playerLevel())) do
        local d = ns.Books.Distance(map, x, y, book.map, book.x, book.y)
        if d and (not yards or d < yards) then
            near, yards = book, d
        end
        if book.map == map then
            local p = math.sqrt((book.x - x) ^ 2 + (book.y - y) ^ 2)
            if not percent or p < percent then
                onMap, percent = book, p
            end
        end
    end
    if near then
        say(L["Tandem: nearest book %s (%s), map %d, %d yd"]:format(near.title, L[near.note], near.map,
            math.floor(yards + 0.5)))
    elseif onMap then
        say(L["Tandem: nearest book %s (%s), %.1f map percent away"]:format(onMap.title, L[onMap.note], percent))
    else
        say(L["Tandem: no eligible book on this continent"])
    end
end
