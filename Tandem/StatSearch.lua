local _, ns = ...

-- Reads the client's own item tooltip, in the client's language: its lines, its stats (through the locale's
-- ns.StatPatterns) and whether it shows a requirement the player does not meet.
local StatSearch = {}
ns.StatSearch = StatSearch

local Safe = ns.Store.Safe

-- Tooltip lines per StatSearch.Key for the session: { {text = lower-cased, raw = as shown}, ... }, colour codes
-- stripped.
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

-- Returns the link the client gives for a container slot, or nil.
local function bagLink(bag, slot)
    local fn = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    return fn and Safe(fn(bag, slot)) or nil
end

-- StatSearch.Key(src) -> string | number
-- The source's session cache key: the full link of the item it names now (so a slot holding another item, or another
-- suffix of one item id, is another key), or its item id when the client gives no link. A source is an item id,
-- { inv = slot, id }, { bag = b, slot = s, id } or { link = string, id }.
function StatSearch.Key(src)
    if type(src) ~= "table" then
        return src
    end
    local link
    if src.inv then
        link = GetInventoryItemLink and Safe(GetInventoryItemLink("player", src.inv))
    elseif src.bag then
        link = bagLink(src.bag, src.slot)
    else
        link = src.link
    end
    return type(link) == "string" and link or src.id
end

local function linesOf(data)
    data = Safe(data)
    local raw = type(data) == "table" and Safe(data.lines)
    return type(raw) == "table" and #raw > 0 and raw or nil
end

-- Returns the raw tooltip lines of the source: from the worn slot, the bag slot or the link when the client has that
-- API and it gives lines, else from the item id; nil when neither gives any.
local function rawLines(src, id)
    local api = C_TooltipInfo
    local raw
    if type(src) == "table" then
        if src.inv and api.GetInventoryItem then
            raw = linesOf(api.GetInventoryItem("player", src.inv))
        elseif src.bag and api.GetBagItem then
            raw = linesOf(api.GetBagItem(src.bag, src.slot))
        elseif src.link and api.GetHyperlink then
            raw = linesOf(api.GetHyperlink(src.link))
        end
    end
    return raw or linesOf(api.GetItemByID(id))
end

local function idOf(src)
    return type(src) == "table" and src.id or src
end

-- Returns the source's raw tooltip lines, or nil while the client has not loaded its item (it is then asked for).
local function loaded(src)
    local id = idOf(src)
    if C_Item and C_Item.IsItemDataCachedByID and Safe(C_Item.IsItemDataCachedByID(id)) ~= true then
        ns.View.RequestItem(id)
        return nil
    end
    local raw = rawLines(src, id)
    if not raw then
        ns.View.RequestItem(id)
    end
    return raw
end

-- StatSearch.Lines(src) -> { {text = lower-cased, raw = as shown}, ... } | nil
-- Returns the source's tooltip lines, or nil while the client has not loaded the item (it is then asked for). Kept
-- per Key only once the item is loaded, so a partial tooltip is never kept.
function StatSearch.Lines(src)
    local key = StatSearch.Key(src)
    if cache[key] then
        return cache[key]
    end
    local raw = loaded(src)
    if not raw then
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
    cache[key] = lines
    return lines
end

local function red(color)
    if type(color) ~= "table" then
        return false
    end
    local r, g, b = Safe(color.r), Safe(color.g), Safe(color.b)
    return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.9 and g < 0.2 and b < 0.2
end

-- StatSearch.Blocked(src) -> true | false | nil
-- True when a line of the source's tooltip is in the client's red "requirement not met" colour (a class, skill, level
-- or reputation the player lacks); nil while the item is not loaded (it is then asked for); false without the tooltip
-- API. Read fresh each time, since skills and level change.
function StatSearch.Blocked(src)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
        return false
    end
    local raw = loaded(src)
    if not raw then
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

-- StatSearch.ReadStats(src) -> { statKey = number } | nil
-- Parses the source's tooltip with the locale's ns.StatPatterns: the first pattern a line matches gives its stat, and
-- a stat on several lines adds up. An empty table when no line holds a stat; nil while the tooltip is not loaded.
function StatSearch.ReadStats(src)
    local lines = StatSearch.Lines(src)
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
