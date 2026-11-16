local _, ns = ...

-- Library books (D1-D3): which of WoW Forever's Library Books a player of a level sees, on which map, whether a book
-- lies in a hostile capital, the hand-in NPCs, and the distance between two map points.
local Books = {}
ns.Books = Books

-- Without world positions, two points on the same map are close within this many map percent on both axes.
local NEAR_PERCENT = 0.7

local call = ns.Store.Call

-- The books a player of this level is meant for, in table order.
function Books.Eligible(level)
    level = tonumber(level) or 0
    local list = {}
    for _, book in ipairs(ns.BookData.books) do
        if book.level <= level then
            list[#list + 1] = book
        end
    end
    return list
end

-- The eligible books on the map with this uiMapID.
function Books.ForMap(mapID, level)
    local list = {}
    for _, book in ipairs(Books.Eligible(level)) do
        if book.map == mapID then
            list[#list + 1] = book
        end
    end
    return list
end

-- The hand-in NPCs of this faction, on the map with this uiMapID when one is given.
function Books.HandIns(faction, mapID)
    local list = {}
    for _, npc in ipairs(ns.BookData.handIns) do
        if npc.faction == faction and (mapID == nil or npc.map == mapID) then
            list[#list + 1] = npc
        end
    end
    return list
end

-- True when the book lies in a capital of another faction than this one.
function Books.Hostile(book, faction)
    return book.city ~= nil and book.city ~= faction
end

-- The continent and world position (yards) of a point given in map percent, or nil without the API or a position.
local function world(mapID, x, y)
    local maps, vector = _G.C_Map, _G.CreateVector2D
    if type(maps) ~= "table" or type(vector) ~= "function" then
        return nil
    end
    local ok, point = pcall(vector, x / 100, y / 100)
    local continent, pos = call(maps.GetWorldPosFromMapPos, mapID, ok and point or nil)
    if continent == nil or type(pos) ~= "table" then
        return nil
    end
    local wx, wy = call(pos.GetXY, pos)
    if type(wx) ~= "number" or type(wy) ~= "number" then
        return nil
    end
    return continent, wx, wy
end

-- The distance in yards between two points given as uiMapID and map percent, when the client places both on the
-- same continent (nil otherwise), and whether both lie on the same map within NEAR_PERCENT on both axes.
function Books.Distance(map1, x1, y1, map2, x2, y2)
    local close = map1 == map2 and math.abs(x1 - x2) <= NEAR_PERCENT and math.abs(y1 - y2) <= NEAR_PERCENT
    local c1, wx1, wy1 = world(map1, x1, y1)
    local c2, wx2, wy2 = world(map2, x2, y2)
    if c1 == nil or c1 ~= c2 then
        return nil, close
    end
    return math.sqrt((wx1 - wx2) ^ 2 + (wy1 - wy2) ^ 2), close
end

-- While debugging, at login: logs "books mapinfo id=<id> name=<name> type=<type>" (or "missing") for each distinct
-- uiMapID the table uses, then "books worldpos ok|missing" for one sample world position, to find wrong map ids.
function Books.LogMaps()
    local Debug = ns.Debug
    if not Debug.IsOn() then
        return
    end
    local maps, seen, ids = _G.C_Map, {}, {}
    for _, list in ipairs({ ns.BookData.books, ns.BookData.handIns }) do
        for _, entry in ipairs(list) do
            if not seen[entry.map] then
                seen[entry.map] = true
                ids[#ids + 1] = entry.map
            end
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local info = type(maps) == "table" and call(maps.GetMapInfo, id)
        if type(info) == "table" then
            Debug.Log(("books mapinfo id=%d name=%s type=%s"):format(id, tostring(info.name), tostring(info.mapType)))
        else
            Debug.Log(("books mapinfo id=%d missing"):format(id))
        end
    end
    local book = ns.BookData.books[1]
    Debug.Log("books worldpos " .. (world(book.map, book.x, book.y) ~= nil and "ok" or "missing"))
end
