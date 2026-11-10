local _, ns = ...

-- Map info (stage 13, D1-D5): one line of small text just under the minimap while the Tandem layout is on, with
-- the player's coordinates on the current zone map in percent and the time played at this level. Refreshed twice a
-- second while shown and on zone changes; the tooltip adds the zone, total played and this session's time.
local MapInfo = {}
ns.MapInfo = MapInfo

local GAP = 4
local TICK = 0.5
local LINE_HEIGHT = 12
local NO_POSITION = "(--, --)"

local line, on, ticker
-- GetTime at login, and the /played values with the GetTime each was last set at.
local session, total, totalAt, level, levelAt, requested

local call = ns.Store.Call

local function now()
    return tonumber((call(GetTime))) or 0
end

local function parts(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
end

-- Returns seconds as "1d5H", "1H20m" or "20m", for the line under the minimap.
function MapInfo.Short(seconds)
    local d, h, m = parts(seconds)
    if d > 0 then
        return ("%dd%dH"):format(d, h)
    elseif h > 0 then
        return ("%dH%dm"):format(h, m)
    end
    return ("%dm"):format(m)
end

-- Returns seconds as "1d 5h", "1h 20m" or "20m" in the client's language, for the tooltip.
function MapInfo.Played(seconds)
    local L = ns.L
    local d, h, m = parts(seconds)
    if d > 0 then
        return L["%dd %dh"]:format(d, h)
    elseif h > 0 then
        return L["%dh %dm"]:format(h, m)
    end
    return L["%dm"]:format(m)
end

-- The seconds played in total and at this level now, or nil before the first TIME_PLAYED_MSG.
local function played()
    if not total then
        return nil
    end
    local t = now()
    return total + (t - totalAt), level + (t - levelAt)
end

-- At PLAYER_LOGIN: starts the session clock and asks the server for /played once.
function MapInfo.OnLogin()
    session = now()
    if not requested and ns.Check.Ready("Map info") then
        requested = true
        pcall(_G.RequestTimePlayed)
    end
end

-- At TIME_PLAYED_MSG: keeps the total and this-level seconds, counted up from now on.
function MapInfo.OnTimePlayed(totalSeconds, levelSeconds)
    if type(totalSeconds) ~= "number" or type(levelSeconds) ~= "number" then
        return
    end
    local t = now()
    total, totalAt, level, levelAt = totalSeconds, t, levelSeconds, t
    MapInfo.Update()
end

-- At PLAYER_LEVEL_UP: this level starts at zero; the total keeps counting.
function MapInfo.OnLevelUp()
    if total then
        level, levelAt = 0, now()
        MapInfo.Update()
    end
end

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

local function showTooltip(self)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    tip:SetOwner(self, "ANCHOR_BOTTOM")
    local zone = call(_G.GetZoneText)
    tip:SetText(type(zone) == "string" and zone or "")
    local sub = call(_G.GetSubZoneText)
    if type(sub) == "string" and sub ~= "" then
        tip:AddLine(sub, 1, 1, 1)
    end
    local all, here = played()
    if all then
        tip:AddLine(L["Played: %s"]:format(MapInfo.Played(all)), 1, 1, 1)
        tip:AddLine(L["This level: %s"]:format(MapInfo.Played(here)), 1, 1, 1)
    end
    tip:AddLine(L["This session: %s"]:format(MapInfo.Played(now() - (session or now()))), 1, 1, 1)
    tip:Show()
end

local function create()
    line = CreateFrame("Frame", nil, UIParent)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetPoint("TOP", line, "TOP", 0, 0)
    line:SetSize(1, 1)
    line:Hide()
    line:EnableMouse(true)
    line:SetScript("OnShow", startTicker)
    line:SetScript("OnHide", stopTicker)
    line:SetScript("OnEnter", showTooltip)
    line:SetScript("OnLeave", ns.View.HideTooltip)
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
    local text = MapInfo.Coords()
    local _, here = played()
    if here then
        text = text .. " · " .. MapInfo.Short(here)
    end
    line.text:SetText(text)
    line:SetSize(math.max(1, line.text:GetStringWidth()), LINE_HEIGHT)
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
