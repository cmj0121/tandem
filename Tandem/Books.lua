local _, ns = ...

-- Library books (D1-D3, D5): which of WoW Forever's Library Books a player of a level sees, on which map, whether a
-- book lies in a hostile capital, the hand-in NPCs, the distance between two map points, and which books were turned
-- in.
local Books = {}
ns.Books = Books

-- Without world positions, two points on the same map are close within this many map percent on both axes.
local NEAR_PERCENT = 0.7
Books.NEAR_PERCENT = NEAR_PERCENT

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

Books.World = world

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

-- Turned-in books (library books D5): the titles turned in this session, as QUEST_TURNED_IN reports them; a title
-- stands for the book, so both Rumi spots count once.
local turnedIn = {}

-- The client's completed-quest check and where it comes from: C_QuestLog, else the global, else none.
local function questAPI()
    local fn = ns.Check.Get("C_QuestLog.IsQuestFlaggedCompleted")
    if type(fn) == "function" then
        return fn, "C_QuestLog"
    end
    fn = ns.Check.Get("IsQuestFlaggedCompleted")
    if type(fn) == "function" then
        return fn, "global"
    end
    return nil, "none"
end

-- True only when the client reads the quest completed; nil, an error or a secret reads false.
local function flagged(quest)
    return quest ~= nil and call((questAPI()), quest) == true
end

local function byKey(key)
    for _, book in ipairs(ns.BookData.books) do
        if book.key == key then
            return book
        end
    end
end

-- True when the book with this key was turned in this session or its quest reads completed.
function Books.TurnedIn(key)
    local book = byKey(key)
    return book ~= nil and (turnedIn[book.title] == true or flagged(book.quest))
end

-- The books turned in and the distinct books there are, each title once, and the book count of the first reward
-- whose own quest is not completed (nil when all are): the game counts books the table may lack, so the reward
-- quests decide it, not the count.
function Books.Progress()
    local seen, done, total = {}, 0, 0
    for _, book in ipairs(ns.BookData.books) do
        if not seen[book.title] then
            seen[book.title] = true
            total = total + 1
            if Books.TurnedIn(book.key) then
                done = done + 1
            end
        end
    end
    for _, milestone in ipairs(ns.BookData.milestones) do
        if not flagged(milestone.quest) then
            return done, total, milestone.books
        end
    end
    return done, total, nil
end

-- A title as the comparison sees it: curly apostrophes made straight and "'s" read as "'".
local function normal(title)
    return (title:gsub("\226\128\153", "'"):gsub("'s", "'"))
end

-- QUEST_TURNED_IN: marks the book whose quest this is, else the book whose title the quest's title matches (a wrong
-- or missing quest id in the table, logged while debugging). Returns the matched book's key or nil.
function Books.OnQuestTurnedIn(questID)
    local match, byTitle
    for _, book in ipairs(ns.BookData.books) do
        if questID ~= nil and book.quest == questID then
            match = book
            break
        end
    end
    local title = call(ns.Check.Get("C_QuestLog.GetTitleForQuestID"), questID)
    if not match and type(title) == "string" then
        for _, book in ipairs(ns.BookData.books) do
            if normal(book.title) == normal(title) then
                match, byTitle = book, true
                break
            end
        end
    end
    if match then
        turnedIn[match.title] = true
    end
    local Debug = ns.Debug
    if Debug.IsOn() then
        Debug.Log(("books turnin quest=%s title=%s book=%s"):format(tostring(questID), tostring(title),
            match and match.key or "none"))
        if byTitle then
            Debug.Log(("books questid mismatch key=%s table=%s game=%s"):format(match.key, tostring(match.quest),
                tostring(questID)))
        end
    end
    return match and match.key
end

-- While debugging, at login: the quest API in use, the turned-in count and next reward, each reward quest's flag and
-- each book row's flag, so every quest id (false positives too) can be checked against the game.
function Books.LogTurnedIn()
    local Debug = ns.Debug
    if not Debug.IsOn() then
        return
    end
    local _, source = questAPI()
    Debug.Log("books questapi " .. source)
    local done, total, nextAt = Books.Progress()
    Debug.Log(("books turnedin %d/%d next=%s"):format(done, total, tostring(nextAt or "none")))
    for _, milestone in ipairs(ns.BookData.milestones) do
        Debug.Log(("books milestone %d=%s"):format(milestone.books, tostring(flagged(milestone.quest))))
    end
    for _, book in ipairs(ns.BookData.books) do
        Debug.Log(("books flag key=%s quest=%s flagged=%s"):format(book.key, tostring(book.quest),
            tostring(flagged(book.quest))))
    end
end
