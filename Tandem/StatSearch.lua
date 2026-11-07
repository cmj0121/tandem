local _, ns = ...

-- Reads the client's own item tooltip, in the client's language: its lines, its stats (through the locale's
-- ns.StatPatterns) and whether it shows a requirement the player does not meet.
local StatSearch = {}
ns.StatSearch = StatSearch

local Safe = ns.Store.Safe

-- Tooltip lines per item for the session: { {text = lower-cased, raw = as shown}, ... }, colour codes stripped.
local cache = {}

-- Returns true when the client has the tooltip data API the search reads.
function StatSearch.Ready()
    return ns.Check.Ready("Stat search")
end

local function strip(text)
    text = Safe(text)
    if type(text) ~= "string" then
        return nil
    end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end

-- StatSearch.Lines(id) -> { {text = lower-cased, raw = as shown}, ... } | nil
-- Returns the item's tooltip lines, or nil while the client has not loaded the item (it is then asked for).
function StatSearch.Lines(id)
    if cache[id] then
        return cache[id]
    end
    if C_Item and C_Item.IsItemDataCachedByID and Safe(C_Item.IsItemDataCachedByID(id)) ~= true then
        ns.View.RequestItem(id)
        return nil
    end
    local data = Safe(C_TooltipInfo.GetItemByID(id))
    local raw = type(data) == "table" and Safe(data.lines)
    if type(raw) ~= "table" or #raw == 0 then
        ns.View.RequestItem(id)
        return nil
    end
    local lines = {}
    for _, line in ipairs(raw) do
        if type(line) == "table" then
            -- Some clients fill only args; SurfaceArgs copies them into leftText and rightText.
            if line.leftText == nil and line.rightText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
                pcall(TooltipUtil.SurfaceArgs, line)
            end
            local parts = {}
            for _, side in ipairs({ strip(line.leftText), strip(line.rightText) }) do
                if side and side ~= "" then
                    parts[#parts + 1] = side
                end
            end
            local text = table.concat(parts, " ")
            lines[#lines + 1] = { text = text:lower(), raw = text }
        end
    end
    cache[id] = lines
    return lines
end

local function red(color)
    if type(color) ~= "table" then
        return false
    end
    local r, g, b = Safe(color.r), Safe(color.g), Safe(color.b)
    return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.9 and g < 0.2 and b < 0.2
end

-- StatSearch.Blocked(id) -> true | false | nil
-- True when a line of the item's tooltip is in the client's red "requirement not met" colour (a class, skill, level or
-- reputation the player lacks); nil while the item is not loaded (it is then asked for); false without the tooltip
-- API. Read fresh each time, since skills and level change.
function StatSearch.Blocked(id)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
        return false
    end
    if C_Item and C_Item.IsItemDataCachedByID and Safe(C_Item.IsItemDataCachedByID(id)) ~= true then
        ns.View.RequestItem(id)
        return nil
    end
    local data = Safe(C_TooltipInfo.GetItemByID(id))
    local raw = type(data) == "table" and Safe(data.lines)
    if type(raw) ~= "table" or #raw == 0 then
        ns.View.RequestItem(id)
        return nil
    end
    for _, line in ipairs(raw) do
        if type(line) == "table" then
            if line.leftColor == nil and line.rightColor == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
                pcall(TooltipUtil.SurfaceArgs, line)
            end
            if red(Safe(line.leftColor)) or red(Safe(line.rightColor)) then
                return true
            end
        end
    end
    return false
end

-- StatSearch.ReadStats(id) -> { statKey = number } | nil
-- Parses the item's tooltip with the locale's ns.StatPatterns: the first pattern a line matches gives its stat, and
-- a stat on several lines adds up. An empty table when no line holds a stat; nil while the tooltip is not loaded.
function StatSearch.ReadStats(id)
    local lines = StatSearch.Lines(id)
    if not lines then
        return nil
    end
    local stats = {}
    for _, line in ipairs(lines) do
        for _, p in ipairs(ns.StatPatterns or {}) do
            local n = tonumber(line.raw:match(p[1]))
            if n then
                stats[p[2]] = (stats[p[2]] or 0) + n
                break
            end
        end
    end
    return stats
end
