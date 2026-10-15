local _, ns = ...

-- Finds items by the wording of their tooltip (decision 7): a query's terms must all appear on one line of the
-- client's own tooltip, in the client's language, and the first number on that line is the item's value. A few
-- common words the client spells differently are aliased per locale (ns.StatAliases).
local StatSearch = {}
ns.StatSearch = StatSearch

local Safe = ns.Store.Safe

-- Tooltip lines per item for the session: { {text = lower-cased, raw = as shown}, ... }, colour codes stripped.
local cache = {}

-- Returns true when the client has the tooltip data API the search reads.
function StatSearch.Ready()
    return ns.Check.Ready("Stat search")
end

-- Returns the query's terms, lower-cased and aliased, or nil for a blank query. A leading "+" is dropped from each.
function StatSearch.Parse(query)
    local aliases = ns.StatAliases or {}
    local terms = {}
    for typed in tostring(query or ""):lower():gmatch("%S+") do
        local word = typed:gsub("^%++", "")
        for term in (aliases[word] or word):gmatch("%S+") do
            terms[#terms + 1] = term
        end
    end
    if #terms > 0 then
        return terms
    end
end

local function strip(text)
    text = Safe(text)
    if type(text) ~= "string" then
        return nil
    end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end

-- Returns the item's tooltip lines, or nil while the client has not loaded the item (it is then asked for).
local function linesOf(id)
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

-- StatSearch.Match(id, terms) -> value, line | nil, pending
-- Returns the first number on the first tooltip line holding every term (0 when it has none) and that line as shown;
-- nil when no line matches, with pending true while the item's tooltip is not loaded yet.
function StatSearch.Match(id, terms)
    local lines = linesOf(id)
    if not lines then
        return nil, true
    end
    for _, line in ipairs(lines) do
        local all = true
        for _, term in ipairs(terms) do
            if not line.text:find(term, 1, true) then
                all = false
                break
            end
        end
        if all then
            return tonumber(line.text:match("%d+%.?%d*")) or 0, line.raw
        end
    end
    return nil, false
end

-- StatSearch.Filter(rows, terms) -> matched, pending
-- Returns the rows that match, each with value and line set, sorted by value desc then their order in rows; pending
-- is the set of ids still loading.
function StatSearch.Filter(rows, terms)
    local matched, pending, order = {}, {}, {}
    for i, row in ipairs(rows) do
        local value, line = StatSearch.Match(row.id, terms)
        if value then
            row.value, row.line = value, line
            matched[#matched + 1] = row
            order[row] = i
        elseif line then
            pending[row.id] = true
        end
    end
    table.sort(matched, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return order[a] < order[b]
    end)
    return matched, pending
end
