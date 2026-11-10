local _, ns = ...

-- Map info (stage 13, D1-D5, D9, D11): one line of small text while the Tandem layout is on, centred just below
-- Tandem's XP bar (at the screen's top centre when the bar is hidden, as at the maximum level), with the player's
-- coordinates on the current zone map in percent and the time played at this level. Refreshed twice a second while
-- shown and on zone changes; the tooltip adds the zone, total played and this session's time.
local MapInfo = {}
ns.MapInfo = MapInfo

local GAP = 4
local BELOW = 2
local TICK = 0.5
local LINE_HEIGHT = 12
local NO_POSITION = "(--, --)"

local line, on, ticker
-- The XP bar the line sits under, false at the screen's top, nil until placed.
local placedIn
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

-- Returns seconds as "1d5H", "1H20m" or "20m", for the map info line.
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
    end
    -- The XP bar hides at the maximum level; the line moves to the screen's top.
    MapInfo.Update()
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

-- Centred just below the XP bar while it shows, else at the screen's top centre; only when that changed. Always a
-- UIParent child, so the bar hiding does not hide it.
local function place()
    local bar = ns.XPBar.Frame() or false
    if bar == placedIn then
        return
    end
    placedIn = bar
    line:ClearAllPoints()
    line:SetParent(UIParent)
    if bar then
        local strata = call(bar.GetFrameStrata, bar)
        if type(strata) == "string" then
            line:SetFrameStrata(strata)
        end
        line:SetFrameLevel((tonumber((call(bar.GetFrameLevel, bar))) or 0) + 1)
        line:SetPoint("TOP", bar, "BOTTOM", 0, -BELOW)
    else
        line:SetPoint("TOP", UIParent, "TOP", 0, -GAP)
    end
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
    place()
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
        placedIn = nil
    end
    MapInfo.Update()
end

ns.Layout.OnChange(onChange)
