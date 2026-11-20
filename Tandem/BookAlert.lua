local _, ns = ...

-- Library book alert (library books D4): out of combat, while the player's continent holds an eligible book not yet
-- announced, a 1 s ticker reads the player's position and prints one chat line per book per session when the player
-- stands within RANGE yards of the book or its entrance. World yards compare across the maps of one continent (a
-- cave or Blackrock Mountain against the zone map); without them, map percent on the same map. /tandem books off and
-- combat stop the ticker.
local BookAlert = {}
ns.BookAlert = BookAlert

local L = ns.L
local call = ns.Store.Call

local TICK = 1
local RANGE = 40
-- Enum.UIMapType.Continent; a parent chain walks at most MAX_DEPTH maps up.
local CONTINENT = 2
local MAX_DEPTH = 10

local ready = false
local inCombat = false
local ticker
local alerted = {}
local continents = {}

local function log(text)
    if ns.Debug ~= nil and ns.Debug.IsOn() then
        ns.Debug.Log(text)
    end
end

-- The uiMapID of the continent the map lies on, found up its GetMapInfo parent chain; the map itself when the chain
-- reaches no continent.
local function continentOf(mapID)
    if continents[mapID] == nil then
        local found, id = mapID, mapID
        for _ = 1, MAX_DEPTH do
            local info = call(_G.C_Map.GetMapInfo, id)
            if type(info) ~= "table" then
                break
            end
            if info.mapType == CONTINENT then
                found = id
                break
            end
            id = info.parentMapID
            if type(id) ~= "number" or id == 0 then
                break
            end
        end
        continents[mapID] = found
    end
    return continents[mapID]
end

local function playerMap()
    local map = call(_G.C_Map.GetBestMapForUnit, "player")
    return type(map) == "number" and map or nil
end

-- The eligible books on the continent of this map not yet announced this session nor turned in (library books D6),
-- kept until Update or an alert.
local cache, cacheContinent

local function pending(map, level)
    local continent = map and continentOf(map)
    if cache and level == nil and continent == cacheContinent then
        return cache
    end
    local list = {}
    if map ~= nil then
        level = tonumber(level) or tonumber((call(_G.UnitLevel, "player"))) or 0
        for _, book in ipairs(ns.Books.Eligible(level)) do
            if not alerted[book.key] and not ns.Books.TurnedIn(book.key) and continentOf(book.map) == continent then
                list[#list + 1] = book
            end
        end
    end
    cache, cacheContinent = list, continent
    return list
end

-- A book's spots (the book, then its entrance) as { map, x, y, continent, wx, wy }, world parts nil where the client
-- places none; computed once per book for the session.
local spots = {}

local function spotsOf(book)
    if not spots[book.key] then
        local list = { { map = book.map, x = book.x, y = book.y } }
        if book.entrance then
            list[2] = { map = book.map, x = book.entrance[1], y = book.entrance[2] }
        end
        for _, spot in ipairs(list) do
            spot.continent, spot.wx, spot.wy = ns.Books.World(spot.map, spot.x, spot.y)
        end
        spots[book.key] = list
    end
    return spots[book.key]
end

-- True when the player (map, x, y in percent, world point or nil) stands within RANGE yards of the spot, as
-- ns.Books.Distance measures: world yards on one continent, else map percent on the same map.
local function near(player, spot)
    if player.continent ~= nil and player.continent == spot.continent then
        return math.sqrt((player.wx - spot.wx) ^ 2 + (player.wy - spot.wy) ^ 2) <= RANGE
    end
    local within = ns.Books.NEAR_PERCENT
    return player.map == spot.map and math.abs(player.x - spot.x) <= within and math.abs(player.y - spot.y) <= within
end

local function stop()
    if ticker then
        call(ticker.Cancel, ticker)
        ticker = nil
    end
end

-- One tick: announces each pending book the player stands near, then stops when none is left.
function BookAlert.Tick()
    local map = playerMap()
    local pos = map and call(_G.C_Map.GetPlayerMapPosition, map, "player")
    local x, y
    if type(pos) == "table" then
        x, y = call(pos.GetXY, pos)
    end
    if type(x) ~= "number" or type(y) ~= "number" then
        return
    end
    x, y = x * 100, y * 100
    local player = { map = map, x = x, y = y }
    player.continent, player.wx, player.wy = ns.Books.World(map, x, y)
    local announced = false
    for _, book in ipairs(pending(map)) do
        local hit = false
        for _, spot in ipairs(spotsOf(book)) do
            hit = hit or near(player, spot)
        end
        if hit then
            alerted[book.key], announced = true, true
            print(L["Tandem: Library book nearby: %s — %s"]:format(book.title, L[book.note]))
            log(("books alert %s map=%d at (%.2f, %.2f)"):format(book.key, map, x, y))
        end
    end
    if announced then
        cache = nil
        BookAlert.Update()
    end
end

-- Runs the ticker while ready, on, out of combat and the player's continent holds a pending book; stops it otherwise.
-- level, when given, stands in for UnitLevel (PLAYER_LEVEL_UP's new level).
function BookAlert.Update(level)
    cache = nil
    local run = ready and not inCombat and call(_G.InCombatLockdown) ~= true and ns.BookPins.On()
        and #pending(playerMap(), level) > 0
    if not run then
        stop()
    elseif not ticker then
        ticker = call(_G.C_Timer.NewTicker, TICK, BookAlert.Tick)
    end
    return ticker ~= nil
end

-- At PLAYER_LOGIN: false, never ticking, when the client lacks the Book alert API.
function BookAlert.OnLogin()
    ready = ns.Check.Ready("Book alert")
    BookAlert.Update()
    return ready
end

-- PLAYER_REGEN_DISABLED: no ticks in combat.
function BookAlert.OnCombatStart()
    inCombat = true
    stop()
end

-- PLAYER_REGEN_ENABLED: ticks again where Update allows.
function BookAlert.OnCombatEnd()
    inCombat = false
    BookAlert.Update()
end
