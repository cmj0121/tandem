local _, ns = ...

-- The Auction House probe (auction plan U0): before Tandem scans the AH for upgrades it must learn which AH API Forever
-- has (the legacy QueryAuctionItems list or C_AuctionHouse), what a result row reads as, how the browse categories
-- describe their filters, and whether a query an addon sends works from a click and from a timer. While the debug
-- recorder is on, opening the AH logs each candidate API and frame, the throttle state and the browse categories, and
-- puts a "Tandem probe" button left of the browse tab's search button: a click sends one query with the player's
-- current selector (name, levels, rarity, usable, category) at once (a hardware event) and another DELAY seconds
-- later from a timer. Each result event logs the row count and the first ROWS rows (every return,
-- the link and its tooltip line count). Lines read "auction probe: <name>=<value> combat=<bool>", once per change,
-- at most LIMIT a session. A value the client keeps secret logs "secret", a raising read "error", a missing function
-- "nil-fn". Blocked calls are logged by Debug's ADDON_ACTION_BLOCKED line. Reads and queries only: nothing is bid on
-- or bought, and nothing is logged or shown while the recorder is off.
local AuctionProbe = {}
ns.AuctionProbe = AuctionProbe

local LIMIT = 250
local ROWS = 2
local DELAY = 3
local CATEGORIES = 20
local EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" }
local GLOBALS = { "QueryAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink", "GetNumAuctionItems",
    "CanSendAuctionQuery", "SortAuctionItems", "SortAuctionClearSort", "GetAuctionItemClasses",
    "GetAuctionItemSubClasses", "GetAuctionItemTimeLeft", "PlaceAuctionBid", "AuctionFrame", "AuctionHouseFrame",
    "AuctionFrameBrowse", "BrowseButton1", "AuctionCategories", "NUM_AUCTION_ITEMS_PER_PAGE" }
local MODERN = { "SendBrowseQuery", "GetBrowseResults", "GetNumBrowseResults", "SearchForItemKeys",
    "GetItemSearchResultInfo", "GetNumItemSearchResults", "SendSearchQuery", "IsThrottledMessageSystemReady",
    "MakeItemKey", "PlaceBid" }

local registered = {}
local last = {}
local lines = 0
local button
local sent = {}

local call = ns.Store.Call

local function isSecret(v)
    local fn = _G.issecretvalue
    if type(fn) ~= "function" then
        return false
    end
    local ok, s = pcall(fn, v)
    return not ok or s == true
end

-- Returns v as text: "secret" for a value the client keeps secret, else tostring, or "?" when that raises.
local function text(v)
    if isSecret(v) then
        return "secret"
    end
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

-- Returns the results of a pcall as text: "error <msg>" when it raised, else each return joined by "|" ("nil" for
-- none).
local function results(ok, ...)
    if not ok then
        return "error " .. text((...))
    end
    local n = select("#", ...)
    if n == 0 then
        return "nil"
    end
    local out = {}
    for i = 1, n do
        out[i] = text((select(i, ...)))
    end
    return table.concat(out, "|")
end

-- Returns fn(...) as text, or "nil-fn" when fn is not a function.
local function read(fn, ...)
    if type(fn) ~= "function" then
        return "nil-fn"
    end
    return results(pcall(fn, ...))
end

-- Returns t[key], or nil when t is not a plain table or indexing it raises.
local function field(t, key)
    if type(t) ~= "table" or isSecret(t) then
        return nil
    end
    local ok, v = pcall(function()
        return t[key]
    end)
    return ok and v or nil
end

local function combat()
    return tostring(call(_G.InCombatLockdown) == true)
end

-- Logs name's value with the combat state unless both match the last line logged for name.
local function report(name, value)
    if lines >= LIMIT or not ns.Debug.IsOn() then
        return
    end
    local state = combat()
    local key = value .. " " .. state
    if last[name] == key then
        return
    end
    last[name] = key
    lines = lines + 1
    ns.Debug.Log(("auction probe: %s=%s combat=%s"):format(name, value, state))
end

local function safely(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        pcall(report, "probe", "error " .. text(err))
    end
end

-- Returns a table's keys, sorted and joined by ",", for a plain table; else its type.
local function shape(v)
    if type(v) ~= "table" or isSecret(v) then
        return isSecret(v) and "secret" or type(v)
    end
    local keys = {}
    local ok = pcall(function()
        for k in pairs(v) do
            keys[#keys + 1] = text(k)
        end
    end)
    if not ok then
        return "table{?}"
    end
    table.sort(keys)
    return "table{" .. table.concat(keys, ",") .. "}"
end

-- Returns a table's fields as k=v (nested tables by shape), sorted and joined by " ".
local function fields(v)
    if type(v) ~= "table" or isSecret(v) then
        return text(v)
    end
    local parts = {}
    pcall(function()
        for k, x in pairs(v) do
            parts[#parts + 1] = text(k) .. "=" .. (type(x) == "table" and shape(x) or text(x))
        end
    end)
    table.sort(parts)
    return "{" .. table.concat(parts, " ") .. "}"
end

local function readAPIs()
    for _, name in ipairs(GLOBALS) do
        local v = _G[name]
        report("has:" .. name, type(v) == "number" and text(v) or type(v))
    end
    local ah = _G.C_AuctionHouse
    report("has:C_AuctionHouse", type(ah))
    for _, name in ipairs(MODERN) do
        report("has:C_AuctionHouse." .. name, type(field(ah, name)))
    end
    report("has:C_TooltipInfo.GetAuctionItem", type(field(_G.C_TooltipInfo, "GetAuctionItem")))
    report("CanSendAuctionQuery", read(_G.CanSendAuctionQuery))
    report("C_AuctionHouse.IsThrottledMessageSystemReady", read(field(ah, "IsThrottledMessageSystemReady")))
end

-- Logs the browse categories (the Blizzard AH's AuctionCategories): each one's name, its filters' fields and its
-- subcategories' count, for the first CATEGORIES.
local function readCategories()
    local cats = _G.AuctionCategories
    if type(cats) ~= "table" then
        return
    end
    report("categories", text(#cats))
    for i = 1, math.min(#cats, CATEGORIES) do
        local c = cats[i]
        local filters = field(c, "filters")
        local subs = field(c, "subCategories")
        report("category:" .. i, ("%s filters=%s first=%s subs=%s"):format(text(field(c, "name")),
            type(filters) == "table" and text(#filters) or "nil",
            type(filters) == "table" and fields(filters[1]) or "nil",
            type(subs) == "table" and text(#subs) or "nil"))
    end
end

-- Logs the tooltip line count C_TooltipInfo gives for link.
local function tooltipLines(name, link)
    if type(link) ~= "string" then
        return
    end
    local data = call(field(_G.C_TooltipInfo, "GetHyperlink"), link)
    local list = field(data, "lines")
    report(name, type(list) == "table" and text(#list) or "nil")
end

-- Legacy list: the row count and the first ROWS rows.
local function readList()
    report("GetNumAuctionItems", read(_G.GetNumAuctionItems, "list"))
    for i = 1, ROWS do
        report("row:" .. i, read(_G.GetAuctionItemInfo, "list", i))
        local link = call(_G.GetAuctionItemLink, "list", i)
        report("row:" .. i .. ".link", text(link))
        tooltipLines("row:" .. i .. ".tooltipLines", link)
        report("row:" .. i .. ".tooltip", type(field(_G.C_TooltipInfo, "GetAuctionItem")) == "function"
            and shape(call(_G.C_TooltipInfo.GetAuctionItem, "list", i)) or "nil-fn")
    end
    report("CanSendAuctionQuery", read(_G.CanSendAuctionQuery))
end

-- Modern browse: the result count and the first ROWS results.
local function readBrowse()
    local ah = _G.C_AuctionHouse
    report("GetNumBrowseResults", read(field(ah, "GetNumBrowseResults")))
    local list = call(field(ah, "GetBrowseResults"))
    report("GetBrowseResults", type(list) == "table" and text(#list) or text(list))
    if type(list) ~= "table" then
        return
    end
    for i = 1, ROWS do
        local r = list[i]
        if r == nil then
            break
        end
        report("browse:" .. i, fields(r))
        report("browse:" .. i .. ".itemKey", fields(field(r, "itemKey")))
    end
end

-- Returns the widget's text, or nil when it has none or is missing.
local function widgetText(w)
    local v = call(field(w, "GetText"), w)
    return type(v) == "string" and v ~= "" and v or nil
end

local function widgetChecked(w)
    return call(field(w, "GetChecked"), w) and true or false
end

-- Returns the filters of the browse category the player selected (AuctionFrameBrowse's category, subcategory and
-- sub-subcategory indexes into AuctionCategories), or nil for none.
local function selectedFilters(browse)
    local cats = _G.AuctionCategories
    local c = tonumber(field(browse, "selectedCategoryIndex"))
    local sc = tonumber(field(browse, "selectedSubCategoryIndex"))
    local ssc = tonumber(field(browse, "selectedSubSubCategoryIndex"))
    local node = c and field(cats, c)
    if node and sc then
        node = field(field(node, "subCategories"), sc)
        if node and ssc then
            node = field(field(node, "subCategories"), ssc)
        end
    end
    return node and field(node, "filters") or nil, ("%s/%s/%s %s"):format(text(c), text(sc), text(ssc),
        text(field(node, "name")))
end

-- Reads the AH browse tab's current selector, as the Blizzard search button would send it: { name, minLevel,
-- maxLevel, page, usable, rarity, exact, filters }, and logs it.
local function selector()
    local browse = _G.AuctionFrameBrowse
    local rarity = call(_G.UIDropDownMenu_GetSelectedValue, _G.BrowseDropDown)
    if rarity == -1 then
        rarity = nil
    end
    local filters, where = selectedFilters(browse)
    local q = {
        name = widgetText(_G.BrowseName) or "",
        minLevel = tonumber(widgetText(_G.BrowseMinLevel)),
        maxLevel = tonumber(widgetText(_G.BrowseMaxLevel)),
        page = tonumber(field(browse, "page")) or 0,
        usable = widgetChecked(_G.IsUsableCheckButton),
        rarity = rarity,
        exact = widgetChecked(_G.ExactMatchCheckButton),
        filters = filters,
    }
    report("selector", ("name=%s level=%s-%s page=%s usable=%s rarity=%s exact=%s category=%s filters=%s"):format(
        q.name, text(q.minLevel), text(q.maxLevel), text(q.page), text(q.usable), text(q.rarity), text(q.exact),
        where, type(filters) == "table" and (text(#filters) .. " first=" .. fields(filters[1])) or "nil"))
    return q
end

-- Sends one query with the player's current selector by whichever API the client has and logs what the call
-- returned. how is "click" or "timer".
local function query(how)
    report("query:" .. how .. ".CanSendAuctionQuery", read(_G.CanSendAuctionQuery))
    sent[how] = call(_G.GetTime)
    if type(_G.QueryAuctionItems) == "function" then
        local q = selector()
        report("query:" .. how, read(_G.QueryAuctionItems, q.name, q.minLevel, q.maxLevel, q.page, q.usable, q.rarity,
            false, q.exact, q.filters))
        return
    end
    -- The modern AH: its own search bar sends the query with the player's selector.
    local bar = field(_G.AuctionHouseFrame, "SearchBar")
    local start = field(bar, "StartSearch")
    if type(start) == "function" then
        report("query:" .. how, read(start, bar))
        return
    end
    report("query:" .. how, "no-api")
end

local function onClick()
    safely(query, "click")
    local after = field(_G.C_Timer, "After")
    if type(after) == "function" then
        call(after, DELAY, function()
            if ns.Debug.IsOn() then
                safely(query, "timer")
            end
        end)
    end
end

-- Logs the frame's first anchor and size, to place Tandem's own controls later.
local function where(name, f)
    if type(f) == "table" then
        report("frame:" .. name, ("point=%s size=%s"):format(read(field(f, "GetPoint"), f),
            read(field(f, "GetSize"), f)))
    end
end

-- Places the probe button on the browse tab's search row, left of the Blizzard search button; without that button,
-- below the frame's title bar.
local function place(parent)
    local search = _G.BrowseSearchButton
    button:ClearAllPoints()
    if type(search) == "table" then
        button:SetPoint("RIGHT", search, "LEFT", -4, 0)
    else
        button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -40)
    end
end

-- Puts the probe button on the AH frame (AuctionFrame or AuctionHouseFrame), once.
local function addButton()
    local parent = _G.AuctionFrame or _G.AuctionHouseFrame
    report("button.parent", parent == _G.AuctionFrame and parent and "AuctionFrame"
        or parent and "AuctionHouseFrame" or "none")
    where("BrowseSearchButton", _G.BrowseSearchButton)
    where("BrowseResetButton", _G.BrowseResetButton)
    if type(parent) ~= "table" then
        return
    end
    if not button then
        button = CreateFrame("Button", nil, _G.AuctionFrameBrowse or parent, "UIPanelButtonTemplate")
        button:SetSize(110, 22)
        button:SetText("Tandem probe")
        button:SetScript("OnClick", onClick)
    end
    place(parent)
    button:Show()
end

-- Logs how long after the last query a result event came.
local function latency(event)
    local now = tonumber((call(_G.GetTime)))
    for how, t in pairs(sent) do
        if now and tonumber(t) then
            report(event .. ".after:" .. how, ("%.2f"):format(now - t))
        end
        sent[how] = nil
    end
end

-- Handles a probed event Tandem's frame received while the recorder is on; any other event is ignored.
function AuctionProbe.OnEvent(event, ...)
    if not registered[event] or not ns.Debug.IsOn() then
        return
    end
    report("event:" .. event, ("%d args %s"):format(select("#", ...), text((...))))
    if event == "AUCTION_HOUSE_SHOW" then
        safely(readAPIs)
        safely(readCategories)
        safely(addButton)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if button then
            button:Hide()
        end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        latency(event)
        safely(readList)
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        latency(event)
        safely(readBrowse)
    end
end

-- PLAYER_LOGIN: registers the probed events on frame (Tandem's) and logs which the client accepts.
function AuctionProbe.OnLogin(frame)
    if next(registered) then
        return
    end
    for _, event in ipairs(EVENTS) do
        local ok = ns.Store.RegisterEvent(frame, event)
        registered[event] = ok or nil
        report("registered:" .. event, tostring(ok))
    end
end
