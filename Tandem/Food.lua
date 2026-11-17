local _, ns = ...

-- The eat and drink button's choices (D1, D2): finds the food and drink in the bags by their tooltip, in the client's
-- language (ns.FoodText), ranks them and builds the macro text the button runs. Advises only: nothing here uses an
-- item; the click does.
local Food = {}
ns.Food = Food

local call = ns.Store.Call

local BAGS = 4
local MAX_AURAS = 40

-- Item ids already logged as unmatched seated consumables this session.
local logged = {}
-- Item ids already logged as unsure consumables this session.
local unsure = {}
-- Item ids still unsure after the whole backoff (Food.Settle): not food, never pending again this session.
local settled = {}
-- The unsure item ids of the last scan, for Food.Settle.
local lastUnsure = {}
local lastAuras, lastScan

local function debugOn()
    return ns.Debug ~= nil and ns.Debug.IsOn()
end

local function log(text)
    if debugOn() then
        ns.Debug.Log(text)
    end
end

local function container()
    return type(C_Container) == "table" and C_Container or {}
end

-- The stack count of the bag slot's item; 1 when the client does not tell.
local function stackCount(bag, slot)
    local c = container()
    if c.GetContainerItemInfo then
        local info = call(c.GetContainerItemInfo, bag, slot)
        return type(info) == "table" and type(info.stackCount) == "number" and info.stackCount or 1
    end
    local _, count = call(_G.GetContainerItemInfo, bag, slot)
    return type(count) == "number" and count or 1
end

local function has(text, list)
    for _, s in ipairs(list) do
        if text:find(s, 1, true) then
            return true
        end
    end
    return false
end

local function amount(text, list)
    for _, p in ipairs(list) do
        local n = tonumber(text:match(p))
        if n then
            return n
        end
    end
end

-- Reads one item's tooltip lines into a candidate, or nil unless it must be used seated (food or drink, not a potion)
-- and a line restores health or mana.
local function classify(lines, id, bag, slot)
    local T = ns.FoodText
    local c = { id = id, bag = bag, slot = slot, health = 0, mana = 0, buff = false, conjured = false }
    local seated = false
    for _, line in ipairs(lines) do
        local text = line.text
        local cut = text:find(T.stop, 1, true)
        local first = cut and text:sub(1, cut - 1) or text
        c.health = math.max(c.health, amount(first, T.health) or 0)
        c.mana = math.max(c.mana, amount(first, T.mana) or 0)
        c.buff = c.buff or has(text, T.wellFed)
        c.conjured = c.conjured or has(text, T.conjured)
        seated = seated or has(text, T.seated)
    end
    if seated and (c.health > 0 or c.mana > 0) then
        return c
    end
    if seated and not logged[id] then
        logged[id] = true
        local raw = {}
        for i, line in ipairs(lines) do
            raw[i] = line.raw
        end
        log("food unmatched " .. id .. ": " .. table.concat(raw, " | "))
    end
end

-- The item's class id (0 for a consumable), or nil when the client does not tell.
local function classOf(id)
    local classID = select(6, call(C_Item and C_Item.GetItemInfoInstant, id))
    return type(classID) == "number" and classID or nil
end

-- True when a tooltip line holds the locale's "Use:" text; an incomplete tooltip lacks the whole Use line.
local function hasUse(lines)
    for _, line in ipairs(lines) do
        if has(line.text, ns.FoodText.use) then
            return true
        end
    end
    return false
end

-- Logs an unsure consumable's tooltip once per item id.
local function logUnsure(id, lines)
    if not debugOn() or unsure[id] then
        return
    end
    unsure[id] = true
    local raw = {}
    for i, line in ipairs(lines) do
        raw[i] = line.raw
    end
    log(("food unsure %d: %d lines: %s"):format(id, #lines, table.concat(raw, " | ")))
end

-- Food.Scan() -> candidates, pending
-- Every bag slot (bags 0..4) whose item restores health or mana and has no unmet requirement, as
-- { id, bag, slot, health, mana, buff, conjured, count }; an item not loaded yet is left out (the client is asked for
-- it). pending counts the slots not read yet (unready) and the unblocked consumables that are not candidates and
-- show no "Use:" line (unsure: an incomplete tooltip, read again on the next scan), bar those Food.Settle settled.
-- Empty and 0 without the tooltip API or the locale's food text. Reads tooltips: the caller keeps the result. While
-- debugging, logs the counts (and the unsure item ids) when they change.
function Food.Scan()
    local found = {}
    if not (ns.FoodText and ns.StatSearch.Ready()) then
        return found, 0
    end
    local c = container()
    local numSlots = c.GetContainerNumSlots or _G.GetContainerNumSlots
    local itemID = c.GetContainerItemID or _G.GetContainerItemID
    local items, unready, unsureCount = 0, 0, 0
    local unsureIds = {}
    for bag = 0, BAGS do
        local n = call(numSlots, bag)
        for slot = 1, type(n) == "number" and n or 0 do
            local id = call(itemID, bag, slot)
            if type(id) == "number" then
                items = items + 1
                local src = { id = id, bag = bag, slot = slot }
                local lines = ns.StatSearch.Lines(src)
                local cand = lines and classify(lines, id, bag, slot)
                local blocked = cand and ns.StatSearch.Blocked(src)
                if not lines or (cand and blocked == nil) then
                    unready = unready + 1
                elseif cand and blocked == false then
                    cand.count = stackCount(bag, slot)
                    found[#found + 1] = cand
                elseif not cand and classOf(id) == 0 and not hasUse(lines)
                    and ns.StatSearch.Blocked(src) == false then
                    -- Read again on the next scan either way; a settled item no longer counts as pending.
                    ns.StatSearch.Forget(src)
                    if not settled[id] then
                        unsureCount = unsureCount + 1
                        unsureIds[#unsureIds + 1] = id
                        logUnsure(id, lines)
                    end
                end
            end
        end
    end
    if debugOn() then
        local line = ("food scan: slots=%d unready=%d unsure=%d cands=%d"):format(items, unready, unsureCount, #found)
            .. (#unsureIds > 0 and " unsure_ids=" .. table.concat(unsureIds, ",") or "")
        if line ~= lastScan then
            lastScan = line
            log(line)
        end
    end
    lastUnsure = unsureIds
    return found, unready + unsureCount
end

-- Food.Settle(): the last scan's unsure items are taken as not food (a crafting order, a quest item with no "Use:"
-- line): later scans this session still read them (one that turns out to be food is offered) but no longer count them
-- as pending, so they start no more timed rescans. Called once the eat button's backoff is used up.
function Food.Settle()
    for _, id in ipairs(lastUnsure) do
        settled[id] = true
    end
end

-- True when a ranks before b for the kind ("health" or "mana"): buff food first (food only, while not well fed),
-- then the higher amount, conjured first, the smaller stack, the lower item id.
local function before(a, b, kind, wellFed)
    if kind == "health" and not wellFed and a.buff ~= b.buff then
        return a.buff
    end
    if a[kind] ~= b[kind] then
        return a[kind] > b[kind]
    end
    if a.conjured ~= b.conjured then
        return a.conjured
    end
    if a.count ~= b.count then
        return a.count < b.count
    end
    return a.id < b.id
end

local function best(candidates, kind, wellFed)
    local top
    for _, c in ipairs(candidates) do
        if c[kind] > 0 and (not top or before(c, top, kind, wellFed)) then
            top = c
        end
    end
    return top
end

-- Food.Pick(candidates, wellFed) -> food|nil, drink|nil
-- The best candidate that restores health and the best that restores mana (D2); with wellFed true, buff food ranks as
-- plain food.
function Food.Pick(candidates, wellFed)
    return best(candidates, "health", wellFed), best(candidates, "mana", wellFed)
end

-- Food.Macro(item) -> text|nil
-- One click's macro (D1): /use the item; nil without one.
function Food.Macro(item)
    return item and "/use item:" .. item.id or nil
end

local function isAny(name, list)
    for _, s in ipairs(list) do
        if name == s then
            return true
        end
    end
    return false
end

-- The player's buff names, or nil when the client raises (aura data it keeps from addons in combat).
local function buffNames()
    local byIndex = type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataByIndex
    local names = {}
    for i = 1, MAX_AURAS do
        local ok, name
        if type(byIndex) == "function" then
            local aura
            ok, aura = pcall(byIndex, "player", i, "HELPFUL")
            name = ok and type(aura) == "table" and ns.Store.Safe(aura.name) or nil
        else
            ok, name = pcall(_G.UnitBuff, "player", i)
            name = ok and ns.Store.Safe(name) or nil
        end
        if not ok then
            return nil
        end
        if type(name) ~= "string" then
            return names
        end
        names[#names + 1] = name
    end
    return names
end

-- Food.Auras() -> eating, drinking, wellFed
-- Whether the player has the Food, Drink and Well Fed auras, by the locale's aura names; all false in combat, when the
-- client raises or without the locale's food text. While debugging, logs the player's other buffs when they change, so
-- a missed aura name can be found.
function Food.Auras()
    local T = ns.FoodText
    local names = T and call(InCombatLockdown) ~= true and buffNames()
    if not names then
        return false, false, false
    end
    local eating, drinking, wellFed = false, false, false
    local other = {}
    for _, name in ipairs(names) do
        local e, d, w = isAny(name, T.eating), isAny(name, T.drinking), isAny(name, T.wellFedAura)
        eating, drinking, wellFed = eating or e, drinking or d, wellFed or w
        if not (e or d or w) then
            other[#other + 1] = name
        end
    end
    local text = table.concat(other, ", ")
    if debugOn() and text ~= lastAuras then
        lastAuras = text
        log("food auras unmatched: " .. text)
    end
    return eating, drinking, wellFed
end
