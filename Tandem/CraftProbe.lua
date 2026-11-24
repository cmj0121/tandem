local _, ns = ...

-- The craft probe: before Tandem crafts through a `/cast <recipe name>` macro with the profession window closed, it
-- must learn which profession APIs Forever has and whether such a cast makes anything. While the debug recorder is on,
-- this logs once at login which profession globals exist ("login GetNumTradeSkills=function ... C_TradeSkillUI=table
-- fns=<names>") and which of its events the client rejects; on each tradeskill or craft window event the profession's
-- recipes, one "recipe" line each with its index, name, type, item ID and links, again only when the list changed;
-- each player cast success and channel start and stop with its spell ID and name; and, for 3 s after a cast success or
-- a channel stop, each bag item whose count rose ("gain spell=<id> <name> item=<id> <name> delta=+<n> after=<s>"),
-- marked loot=1, mail=1 or trade=1 while such a window is open, so a fished catch shows up as well as a craft. Each
-- line carries GetTime and the combat state; a value the client keeps secret logs "secret". Lines go to
-- TandemDebug.craft (the last LIMIT), which login does not flush, up to LIMIT a session. The events go on this
-- module's own frame. Reads only; it never opens a profession window or a bag, and logs nothing while the recorder is
-- off.
local CraftProbe = {}
ns.CraftProbe = CraftProbe

local LIMIT = 500
local BAGS = 4
local WATCH = 3
local GLOBALS = { "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillRecipeLink",
    "GetTradeSkillLine", "DoTradeSkill", "GetNumCrafts", "GetCraftInfo", "DoCraft", "CastSpellByName" }
local UNIT_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }
local EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "BAG_UPDATE",
    "BAG_UPDATE_DELAYED", "LOOT_OPENED", "LOOT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED" }
-- The window events that set and clear each open flag a gain line carries.
local WINDOWS = {
    LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false }, MAIL_SHOW = { "mail", true },
    MAIL_CLOSED = { "mail", false }, TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
}

local events
local lines = 0
local open = { loot = false, mail = false, trade = false }
-- The recipe list last logged per profession, as one text.
local logged = {}
-- The cast whose gains are being watched: spell, its name, when, and the bag counts by item ID at that moment.
local watch

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

local function now()
    local t = call(_G.GetTime)
    return tonumber(t) or 0
end

local function log(what)
    if lines >= LIMIT or not ns.Debug.IsOn() then
        return
    end
    lines = lines + 1
    local d = TandemDebug
    if type(d.craft) ~= "table" then
        d.craft = {}
    end
    local out = d.craft
    out[#out + 1] = ("%.2f combat=%s %s"):format(now(), tostring(call(_G.InCombatLockdown) == true), what)
    while #out > LIMIT do
        table.remove(out, 1)
    end
end

-- Returns fn's first result for the arguments, as text, or "nil-fn" when the client has no such function.
local function read(fn, ...)
    if type(fn) ~= "function" then
        return "nil-fn"
    end
    return text((call(fn, ...)))
end

-- Returns the item ID in an item link, or nil.
local function linkID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function spellName(id)
    local spell = type(_G.C_Spell) == "table" and _G.C_Spell.GetSpellName
    if type(spell) == "function" then
        return read(spell, id)
    end
    return read(_G.GetSpellInfo, id)
end

local function itemName(id)
    local item = type(_G.C_Item) == "table" and _G.C_Item.GetItemNameByID
    if type(item) == "function" then
        return read(item, id)
    end
    return read(_G.GetItemInfo, id)
end

-- Logs once at login which profession globals exist, C_TradeSkillUI's function names, and the rejected events.
local function logGlobals(rejected)
    local out = {}
    for _, name in ipairs(GLOBALS) do
        out[#out + 1] = name .. "=" .. type(_G[name])
    end
    local ui = _G.C_TradeSkillUI
    out[#out + 1] = "C_TradeSkillUI=" .. type(ui)
    if type(ui) == "table" then
        local fns = {}
        for k, v in pairs(ui) do
            if type(v) == "function" then
                fns[#fns + 1] = tostring(k)
            end
        end
        table.sort(fns)
        out[#out + 1] = "fns=" .. table.concat(fns, ",")
    end
    out[#out + 1] = "rejected=" .. (#rejected > 0 and table.concat(rejected, ",") or "none")
    log("login " .. table.concat(out, " "))
end

-- The recipe APIs of each window kind: the profession line, the count, each recipe's info and links.
local KINDS = {
    tradeskill = { line = "GetTradeSkillLine", count = "GetNumTradeSkills", info = "GetTradeSkillInfo",
        item = "GetTradeSkillItemLink", recipe = "GetTradeSkillRecipeLink", typeAt = 2 },
    craft = { line = "GetCraftDisplaySkillLine", count = "GetNumCrafts", info = "GetCraftInfo",
        item = "GetCraftItemLink", recipe = "GetCraftRecipeLink", typeAt = 3 },
}

-- Logs the open window's profession and every recipe in it, unless that list is what was last logged for it.
local function logRecipes(kind)
    local api = KINDS[kind]
    local prof = read(_G[api.line])
    local n = tonumber((call(_G[api.count]))) or 0
    local out = { ("%s %s recipes=%d"):format(kind, prof, n) }
    for i = 1, n do
        local info = { call(_G[api.info], i) }
        local item = call(_G[api.item], i)
        out[#out + 1] = ("recipe %s #%d name=%s type=%s item=%s link=%s recipe=%s"):format(prof, i, text(info[1]),
            text(info[api.typeAt]), text(linkID(item)), text(item), read(_G[api.recipe], i))
    end
    local all = table.concat(out, "\n")
    local key = kind .. ":" .. prof
    if logged[key] == all then
        return
    end
    logged[key] = all
    for _, line in ipairs(out) do
        log(line)
    end
end

-- Returns the bag counts by item ID, bags 0..BAGS, through C_Container or the old globals.
local function counts()
    local c = type(_G.C_Container) == "table" and _G.C_Container or {}
    local numSlots = c.GetContainerNumSlots or _G.GetContainerNumSlots
    local itemID = c.GetContainerItemID or _G.GetContainerItemID
    local itemInfo = c.GetContainerItemInfo or _G.GetContainerItemInfo
    local out = {}
    for bag = 0, BAGS do
        local n = call(numSlots, bag)
        for slot = 1, type(n) == "number" and n or 0 do
            local id = call(itemID, bag, slot)
            if type(id) == "number" then
                local info, count = call(itemInfo, bag, slot)
                if type(info) == "table" then
                    count = info.stackCount
                end
                out[id] = (out[id] or 0) + (tonumber(count) or 1)
            end
        end
    end
    return out
end

local function flags()
    return ("loot=%d mail=%d trade=%d"):format(open.loot and 1 or 0, open.mail and 1 or 0, open.trade and 1 or 0)
end

-- Logs each bag item whose count rose since the watched cast's last snapshot, then snapshots again; the watch ends
-- WATCH seconds after its cast.
local function compare()
    local t = now()
    if t - watch.at > WATCH then
        watch = nil
        return
    end
    local after = counts()
    local ids = {}
    for id, n in pairs(after) do
        if n > (watch.bags[id] or 0) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        log(("gain spell=%s %s item=%d %s delta=+%d after=%.2f %s"):format(text(watch.spell), watch.name, id,
            itemName(id), after[id] - (watch.bags[id] or 0), t - watch.at, flags()))
    end
    watch.bags = after
end

-- Starts watching the bags for what spell makes, first logging what the previous watch saw since its last snapshot.
local function startWatch(spell, name)
    if watch then
        compare()
    end
    watch = { spell = spell, name = name, at = now(), bags = counts() }
end

local function isPlayer(unit)
    return not isSecret(unit) and unit == "player"
end

local function onEvent(event, ...)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        logRecipes("tradeskill")
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        logRecipes("craft")
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        if watch then
            compare()
        end
    elseif event:find("^UNIT_SPELLCAST") then
        local unit, _, spell = ...
        if not isPlayer(unit) then
            return
        end
        local name = spellName(spell)
        local what = event == "UNIT_SPELLCAST_SUCCEEDED" and "cast"
            or event == "UNIT_SPELLCAST_CHANNEL_START" and "channel start" or "channel stop"
        log(("%s id=%s name=%s %s"):format(what, text(spell), name, flags()))
        if event ~= "UNIT_SPELLCAST_CHANNEL_START" then
            startWatch(spell, name)
        end
    end
end

-- An event on this module's frame: the window flags always follow their events; everything else is logged only while
-- the recorder is on.
function CraftProbe.OnEvent(event, ...)
    local window = WINDOWS[event]
    if window then
        open[window[1]] = window[2]
    end
    if not ns.Debug.IsOn() then
        return
    end
    local ok, err = pcall(onEvent, event, ...)
    if not ok then
        pcall(log, "probe error " .. text(err))
    end
end

-- PLAYER_LOGIN: registers the events on this module's own frame, once, the casts for the player only, skipping any the
-- client rejects; with the recorder on logs the profession globals and the rejected events.
function CraftProbe.OnLogin()
    if events then
        return
    end
    events = CreateFrame("Frame", "TandemCraftProbeEvents")
    local rejected = {}
    for _, event in ipairs(UNIT_EVENTS) do
        if not ns.Store.RegisterUnitEvent(events, event, "player") then
            rejected[#rejected + 1] = event
        end
    end
    for _, event in ipairs(EVENTS) do
        if not ns.Store.RegisterEvent(events, event) then
            rejected[#rejected + 1] = event
        end
    end
    events:SetScript("OnEvent", function(_, event, ...)
        CraftProbe.OnEvent(event, ...)
    end)
    if ns.Debug.IsOn() then
        pcall(logGlobals, rejected)
    end
end
